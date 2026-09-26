/**
 * 认证编排层：把网络客户端、凭据存储与会话状态串起来。
 *
 * 上层（viewmodel / 页面）只与本类交互，不直接触碰 LearnClient 或 CredentialStore
 * ——保证"网络唯一出口""凭据唯一入口"两条不变量。
 */

import { Credentials, UserInfo } from '../model/auth';
import { LearnClient } from '../network/learnClient';
import { CredentialStore } from '../storage/credentialStore';
import { Logger } from '../common/logger';

const TAG: string = 'authRepository';

export class AuthRepository {
  /**
   * 登录。
   *
   * @param rememberPassword 是否持久化密码。为 false 时只保存学号与设备指纹，
   *        下次启动需重新输入密码。
   */
  static async login(username: string, password: string, rememberPassword: boolean): Promise<UserInfo> {
    const fingerPrint: string = await CredentialStore.getOrCreateFingerPrint();
    const credentials: Credentials = new Credentials(username, password, fingerPrint);

    const client: LearnClient = LearnClient.getInstance();
    await client.login(credentials);

    await CredentialStore.save(credentials, rememberPassword);
    Logger.info(TAG, '登录流程完成');

    return await client.fetchUserInfo();
  }

  /** 登出：先通知服务端，再无条件清理本地凭据与会话 */
  static async logout(): Promise<void> {
    await LearnClient.getInstance().logout();
    await CredentialStore.clear();
    Logger.info(TAG, '已登出并清理本地凭据');
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
    await client.login(credentials);
    Logger.info(TAG, '已用保存的凭据恢复登录态');
    return await client.fetchUserInfo();
  }

  /** 仅读取学号用于回填登录框 */
  static async loadSavedUsername(): Promise<string> {
    const username: string | null = await CredentialStore.loadUsername();
    return username === null ? '' : username;
  }
}
