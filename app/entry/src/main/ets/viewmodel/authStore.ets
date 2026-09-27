/**
 * 会话状态：应用级单一 Store（ADR-0004）。
 *
 * 承载跨页面共享的登录态，替代上游的 Redux。刻意不做 reducer/action/middleware 全套：
 * 本项目共享状态规模很小，那套范式是为大型前端团队协作设计的，这里属过度工程。
 *
 * 订阅采用**回调推送**：页面在 aboutToAppear 订阅、aboutToDisappear 反订阅，
 * 把状态写入自身 @State 触发刷新。相比 @Observed/@ObjectLink，回调方式在
 * 跨页共享与生命周期释放上更直观，也便于单测（可在无 UI 环境下驱动）。
 *
 * **反订阅是硬要求**：忘记反订阅会导致页面销毁后仍被回调，属已知内存泄漏风险
 * （见 architecture-invariants 与 spec §5 第 6 项）。
 */

import { AuthError, FailReason, LoginStatus, SsoInjection, UserInfo } from '../model/auth';
import { AuthRepository } from '../repository/authRepository';
import { SsoFormBody } from '../network/ssoForm';
import { Logger } from '../common/logger';
import { normalize } from '../common/errors';

const TAG: string = 'authStore';

/** 会话状态快照。页面拿到的是不可变副本，避免直接改内部状态 */
export class AuthState {
  readonly status: LoginStatus;
  readonly userInfo: UserInfo | null;
  readonly errorReason: FailReason | null;
  /** 面向用户的错误说明，已由四分类映射为可理解的文案键 */
  readonly errorDetail: string;

  constructor(status: LoginStatus, userInfo: UserInfo | null, errorReason: FailReason | null, errorDetail: string) {
    this.status = status;
    this.userInfo = userInfo;
    this.errorReason = errorReason;
    this.errorDetail = errorDetail;
  }
}

export type AuthStateListener = (state: AuthState) => void;

export class AuthStore {
  private static instance: AuthStore | null = null;

  private status: LoginStatus = LoginStatus.LOGGED_OUT;
  private userInfo: UserInfo | null = null;
  private errorReason: FailReason | null = null;
  private errorDetail: string = '';
  private listeners: AuthStateListener[] = [];

  /**
   * 待注入 WebView 的取值（含密码明文）。
   *
   * 刻意**不是** `@State`：组件状态会被无障碍树读取，密码明文不能出现在那里
   * （见 `SsoInjection` 的说明）。离开网页登录流程即清除。
   */
  private injection: SsoInjection | null = null;
  /** 用户是否勾选"记住密码"；在登录真正成功时才据此决定是否落盘 */
  private pendingRemember: boolean = true;

  static getInstance(): AuthStore {
    if (AuthStore.instance === null) {
      AuthStore.instance = new AuthStore();
    }
    return AuthStore.instance;
  }

  /** 订阅状态变化。**调用方必须在销毁时反订阅** */
  subscribe(listener: AuthStateListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: AuthStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前订阅者数量。供测试断言无泄漏 */
  listenerCount(): number {
    return this.listeners.length;
  }

  getState(): AuthState {
    return this.snapshot();
  }

  private snapshot(): AuthState {
    return new AuthState(this.status, this.userInfo, this.errorReason, this.errorDetail);
  }

  private notify(): void {
    const snapshot: AuthState = this.snapshot();
    for (const listener of this.listeners) {
      listener(snapshot);
    }
  }

  private setLoggedIn(userInfo: UserInfo): void {
    this.status = LoginStatus.LOGGED_IN;
    this.userInfo = userInfo;
    this.errorReason = null;
    this.errorDetail = '';
    this.notify();
  }

  private setFailure(error: AuthError): void {
    this.status = LoginStatus.LOGGED_OUT;
    this.userInfo = null;
    this.errorReason = error.reason;
    this.errorDetail = this.describe(error.reason, error.detail, error.userHint);
    this.notify();
  }

  /**
   * 把失败原因映射为面向用户的说明。
   *
   * 四分类在这里落地为**不同的用户可见文案**——尤其"网络不可达"必须与
   * "密码错误"区分开，否则用户会去反复检查密码而非网络（NFR-NET）。
   *
   * `userHint` 非空时优先：那是**具体可操作**的引导（如"去删旧设备"），
   * 通用文案会把它盖掉。本方法此前从未被调用（死代码），用户看到的是
   * "漫游到网络学堂 (status=401)" 这类技术细节——不可理解，也不指向任何动作。
   */
  private describe(reason: FailReason, detail: string, userHint: string): string {
    if (userHint.length > 0) {
      return userHint;
    }
    if (reason === FailReason.NETWORK_UNREACHABLE) {
      return '无法连接网络学堂，请确认已连接校园网或校方 VPN';
    }
    if (reason === FailReason.AUTH_FAILED) {
      return '学号或密码不正确，或登录状态已失效';
    }
    if (reason === FailReason.API_CHANGED) {
      return '网络学堂接口似乎有变化，暂时无法登录';
    }
    if (reason === FailReason.CANCELLED) {
      return '';
    }
    return `登录失败：${detail}`;
  }

  /**
   * 进入 WebView 主导的登录（ADR-0008 的主路径）。
   *
   * 只把"打开页面所需的取值"备好并切到 `SSO_IN_PROGRESS`；真正的认证由用户在
   * 页面内完成（多因子认证的验证码只能由用户输入）。
   */
  async startSso(username: string, password: string, rememberPassword: boolean): Promise<void> {
    if (this.status === LoginStatus.SSO_IN_PROGRESS || this.status === LoginStatus.LOGGING_IN) {
      Logger.warn(TAG, '登录已在进行中，忽略重复请求');
      return;
    }

    // 先把注入取值备齐，**再**切状态：SSO 页在 aboutToAppear 就取用这些取值，
    // 状态先切会让它在取值就绪前渲染，直接落到"缺少取值"的失败分支。
    // 真机实测踩过：日志表现为「已清空全部 Cookie」紧跟「缺少网页登录所需的取值」。
    try {
      AuthRepository.prepareSsoSession();
      this.injection = await AuthRepository.buildSsoInjection(username, password);
      this.pendingRemember = rememberPassword;
    } catch (err) {
      const error = normalize(err, '准备网页登录');
      Logger.warn(TAG, `准备网页登录失败 reason=${error.reason}`);
      this.injection = null;
      this.setFailure(error);
      return;
    }

    this.status = LoginStatus.SSO_IN_PROGRESS;
    this.errorReason = null;
    this.errorDetail = '';
    this.notify();
  }

  /** 供 SSO 页面取用注入脚本的取值；未进入该流程时返回 null */
  ssoInjection(): SsoInjection | null {
    return this.injection;
  }

  /**
   * WebView 抓到了完整表单体与漫游地址，据此建立会话。
   *
   * 由 SSO 页面在导航命中漫游地址时调用。`roamUrl` 是截到的那次导航目标——
   * 带票据的首选建会话路径要用它；为空则退回"重新登录"。
   */
  async completeSso(body: SsoFormBody, roamUrl: string): Promise<void> {
    const injection: SsoInjection | null = this.injection;
    if (injection === null) {
      Logger.warn(TAG, '未持有注入取值，忽略本次网页登录结果');
      return;
    }

    this.status = LoginStatus.LOGGING_IN;
    this.notify();

    try {
      const userInfo: UserInfo =
        await AuthRepository.loginWithSsoForm(injection, body, roamUrl, this.pendingRemember);
      this.clearInjection();
      this.setLoggedIn(userInfo);
    } catch (err) {
      const error = normalize(err, '网页登录');
      Logger.warn(TAG, `网页登录失败 reason=${error.reason}`);
      this.clearInjection();
      this.setFailure(error);
    }
  }

  /** 用户主动放弃网页登录：归"用户取消"，**不报错**（spec §8.2） */
  cancelSso(): void {
    this.clearInjection();
    this.status = LoginStatus.LOGGED_OUT;
    this.userInfo = null;
    this.errorReason = null;
    this.errorDetail = '';
    this.notify();
  }

  /**
   * 上报 WebView 侧的异常信号，由本层归类后呈现。
   *
   * 页面只把信号原样传上来，不做归类判断（分层：pages 不含业务判断）。
   */
  reportSsoProblem(code: string): void {
    const error: AuthError = AuthRepository.classifySsoProblem(code);
    Logger.warn(TAG, `网页登录异常 code=${code} reason=${error.reason}`);
    this.clearInjection();
    this.setFailure(error);
  }

  /** 清掉内存中的注入取值（含密码明文）：离开该流程即不再需要 */
  private clearInjection(): void {
    this.injection = null;
  }

  /**
   * 启动时尝试恢复登录态。
   *
   * 失败不视为用户可见错误：无凭据是正常状态，静默进入未登录即可。
   */
  async restoreSession(): Promise<void> {
    try {
      const userInfo: UserInfo | null = await AuthRepository.tryRestoreSession();
      if (userInfo !== null) {
        this.setLoggedIn(userInfo);
      }
    } catch (err) {
      const error = normalize(err, '恢复登录态');
      Logger.info(TAG, `未能自动恢复登录态 reason=${error.reason}`);
    }
  }

  async logout(): Promise<void> {
    try {
      await AuthRepository.logout();
    } catch (err) {
      const error = normalize(err, '登出');
      Logger.warn(TAG, `登出时出错 reason=${error.reason}`);
    }
    this.clearInjection();
    this.status = LoginStatus.LOGGED_OUT;
    this.userInfo = null;
    this.errorReason = null;
    this.errorDetail = '';
    this.notify();
  }

  /** 供登录页回填学号 */
  async loadSavedUsername(): Promise<string> {
    try {
      return await AuthRepository.loadSavedUsername();
    } catch (err) {
      Logger.warn(TAG, '读取已保存学号失败，忽略');
      return '';
    }
  }
}
