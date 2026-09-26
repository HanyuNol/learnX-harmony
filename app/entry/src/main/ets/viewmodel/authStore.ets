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

import { FailReason, UserInfo, LoginStatus } from '../model/auth';
import { AuthRepository } from '../repository/authRepository';
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

  private setFailure(reason: FailReason, detail: string): void {
    this.status = LoginStatus.LOGGED_OUT;
    this.userInfo = null;
    this.errorReason = reason;
    this.errorDetail = detail;
    this.notify();
  }

  /**
   * 把失败原因映射为面向用户的说明。
   *
   * 四分类在这里落地为**不同的用户可见文案**——尤其"网络不可达"必须与
   * "密码错误"区分开，否则用户会去反复检查密码而非网络（NFR-NET）。
   */
  private describe(reason: FailReason, detail: string): string {
    if (reason === FailReason.NETWORK_UNREACHABLE) {
      return '无法连接网络学堂，请确认已连接校园网或校方 VPN';
    }
    if (reason === FailReason.AUTH_FAILED) {
      return '学号或密码不正确，或登录状态已失效';
    }
    if (reason === FailReason.API_CHANGED) {
      return '网络学堂接口似乎有变化，暂时无法登录';
    }
    return `登录失败：${detail}`;
  }

  /** 用户主动登录 */
  async login(username: string, password: string, rememberPassword: boolean): Promise<void> {
    if (this.status === LoginStatus.LOGGING_IN) {
      Logger.warn(TAG, '登录已在进行中，忽略重复请求');
      return;
    }

    this.status = LoginStatus.LOGGING_IN;
    this.errorReason = null;
    this.errorDetail = '';
    this.notify();

    try {
      const userInfo: UserInfo = await AuthRepository.login(username, password, rememberPassword);
      this.setLoggedIn(userInfo);
    } catch (err) {
      const error = normalize(err, '登录');
      Logger.warn(TAG, `登录失败 reason=${error.reason}`);
      this.setFailure(error.reason, error.detail);
    }
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
