/**
 * 认证编排层：把网络客户端、凭据存储与会话状态串起来。
 *
 * 上层（viewmodel / 页面）只与本类交互，不直接触碰 LearnClient 或 CredentialStore
 * ——保证"网络唯一出口""凭据唯一入口"两条不变量。
 */

import { AuthError, Credentials, LogoutResult, SsoInjection, UserInfo } from '../model/auth';
import { LearnClient } from '../network/learnClient';
import { SsoFormBody, classifySsoProblem, fingerPrintsOf } from '../network/ssoForm';
import { CredentialStore } from '../storage/credentialStore';
import { deviceLabel } from '../native/deviceAdapter';
import { Logger } from '../common/logger';
import { normalize } from '../common/errors';

const TAG: string = 'authRepository';

export class AuthRepository {
  /**
   * 进入 WebView 主导登录前的准备：清掉旧会话，以干净会话起步。
   *
   * 由本层（而非页面）调用网络层——`pages` 不得直接触碰网络或系统能力（架构不变量 §1）。
   */
  static prepareSsoSession(): void {
    LearnClient.getInstance().startFreshSession();
  }

  /**
   * 准备 WebView 注入登录页所需的取值。
   *
   * 设备指纹在此取得（注入脚本要用它回答"是否信任此浏览器"，且必须复用——
   * 每次换新指纹会很快占满信任浏览器名额）；设备名由 `native` 适配层提供。
   */
  static async buildSsoInjection(username: string, password: string): Promise<SsoInjection> {
    const fingerPrint: string = await CredentialStore.getOrCreateFingerPrint();
    return new SsoInjection(username, password, fingerPrint, deviceLabel());
  }

  /**
   * **主路径**：用 WebView 抓到的信息完成登录（ADR-0008）。
   *
   * 两条收尾路径，按可靠性排序：
   * 1. **用截到的漫游票据直接建会话**（首选）：它就是浏览器原本要做的那一步，
   *    不需要密码、也不需要设备已被登记为信任浏览器。
   * 2. **带页面生成的设备信任标识重新登录**（兜底）：用于没截到票据的情况。
   *
   * 为什么必须有首选路径：校方页面在判定"浏览器处于隐私或匿名模式"时会**拒绝登记
   * 信任浏览器**（真机实测），一旦没登记上，服务端对任何重新登录都会再要一次验证码，
   * 兜底路径就永远走不通——而票据路径绕开了整个重新认证。
   *
   * 凭据落盘的时机在这里——只有真的登录成功才值得存。
   */
  static async loginWithSsoForm(
    injection: SsoInjection,
    body: SsoFormBody,
    roamUrl: string,
    rememberPassword: boolean
  ): Promise<UserInfo> {
    const credentials: Credentials = new Credentials(injection.username, injection.password, injection.fingerPrint);
    const client: LearnClient = LearnClient.getInstance();

    let established: boolean = false;
    if (roamUrl.length > 0) {
      try {
        await client.loginWithRoamUrl(credentials, roamUrl, '漫游票据建会话');
        established = true;
      } catch (err) {
        const error = normalize(err, '漫游票据建会话');
        Logger.warn(TAG, `漫游票据建会话失败 reason=${error.reason}，改用重新登录`);
      }
    } else {
      Logger.warn(TAG, '未截到漫游地址，直接走重新登录');
    }

    if (!established) {
      await client.loginWithFingerPrints(credentials, fingerPrintsOf(body));
    }

    const userInfo: UserInfo = await client.fetchUserInfo();

    // 凭据在**取到用户信息之后**才落盘：反过来的话，取用户信息失败会留下
    // "界面说登录失败、凭据却已保存"的不一致，且下次启动会被静默恢复（代码审查 R-05）。
    await CredentialStore.save(credentials, rememberPassword);
    Logger.info(TAG, `WebView 主导登录流程完成 建会话方式=${established ? '漫游票据' : '重新登录'}`);

    return userInfo;
  }

  /**
   * 归类 WebView 上报的异常信号。
   *
   * 归类留在本层（而非页面）：`pages` 只做 UI，不含业务判断（架构不变量 §1）；
   * 页面只负责把信号原样传上来。
   */
  static classifySsoProblem(code: string): AuthError {
    return classifySsoProblem(code);
  }

  /**
   * 登出：清本地凭据 + 通知服务端（**保留设备指纹**，见 `CredentialStore.clearCredentials`）。
   *
   * **顺序与错误处理都是刻意的**：
   * - 先清凭据：它是"登出"这件事的**唯一实质**。清除失败必须作为结果上报，
   *   不能被"服务端登出失败可忽略"一起吞掉——那样界面会谎报登出成功，而凭据还在，
   *   下次启动会静默重新登录（代码审查 R-02）。
   * - 再通知服务端并清会话 Cookie：`LearnClient.logout` 内部已兜底（服务端失败也清本地会话），
   *   故它不会让本方法失败；即便失败也不改变本地登出的结论。
   */
  static async logout(): Promise<LogoutResult> {
    let credentialsCleared: boolean = true;
    try {
      await CredentialStore.clearCredentials();
    } catch (err) {
      const error = normalize(err, '清除凭据');
      Logger.error(TAG, `本地凭据未能清除 reason=${error.reason}：登出未完成`);
      credentialsCleared = false;
    }

    await LearnClient.getInstance().logout();
    if (credentialsCleared) {
      Logger.info(TAG, '已登出并清理本地凭据');
    }
    return new LogoutResult(credentialsCleared);
  }

  /**
   * 尝试用已保存的凭据静默恢复登录态。
   *
   * 返回 null 表示没有可用凭据（首次运行、或用户未选记住密码），
   * 这是正常状态而非错误，调用方应引导用户输入。
   */
  static async tryRestoreSession(): Promise<UserInfo | null> {
    const credentials: Credentials | null = await CredentialStore.load();
    if (credentials === null) {
      return null;
    }

    const client: LearnClient = LearnClient.getInstance();
    await client.restoreSession(credentials);
    Logger.info(TAG, '已恢复登录态');
    return await client.fetchUserInfo();
  }

  /** 仅读取学号用于回填登录框 */
  static async loadSavedUsername(): Promise<string> {
    const username: string | null = await CredentialStore.loadUsername();
    return username === null ? '' : username;
  }
}
