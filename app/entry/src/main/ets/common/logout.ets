/**
 * 登出判定：结果 → 状态与文案（纯逻辑，可宿主侧单测）。
 *
 * 为什么单独成模块：这条规则是**安全语义**——"界面说已登出"必须等价于"本地凭据已清除"。
 * 此前它隐含在 `AuthStore.logout` 的 try/catch 里（异常被吞后仍无条件转到已登出），
 * 于是凭据清除失败时界面谎报成功、下次启动又用残留凭据静默登录（代码审查 R-02）。
 * 抽成纯函数后，这条不变量才可以被穷举测试，而不必构造 Asset Store 的平台异常。
 */

import { LogoutResult } from '../model/auth';
import { TextKeys } from './texts';

/** 登出判定的结果：是否算登出成功，以及不成功时给用户看的文案键 */
export class LogoutOutcome {
  /** 是否真正完成登出（唯一判据：本地凭据已按策略处置） */
  readonly loggedOut: boolean;
  /** 用户可见文案键；成功时为 `TextKeys.NONE`（无需展示） */
  readonly errorTextKey: string;

  constructor(loggedOut: boolean, errorTextKey: string) {
    this.loggedOut = loggedOut;
    this.errorTextKey = errorTextKey;
  }
}

/**
 * 判定登出是否完成。
 *
 * 凭据未能处置（读写存储失败）时**保持登录态并如实告知**，而不是"看起来登出了、
 * 其实凭据还在且未按用户意愿处理"——后者会让用户在共用/丢失设备上误判风险。
 *
 * 注意 FR-31 之后仍有"保留"这一合法结果（用户勾选了记住密码）：那种情况下
 * `credentialsHandled` 为 true，属**成功**，不是失败。
 */
export function logoutOutcome(result: LogoutResult): LogoutOutcome {
  if (result.credentialsHandled) {
    return new LogoutOutcome(true, TextKeys.NONE);
  }
  return new LogoutOutcome(false, TextKeys.ERR_LOGOUT_INCOMPLETE);
}
