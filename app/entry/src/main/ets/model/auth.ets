/**
 * 认证相关的领域模型。
 */

/**
 * 失败原因四分类。
 *
 * 分类的意义在于**区分责任**：网络与服务端的问题不得报成应用缺陷
 * （见 ARCHITECTURE §5.4 与 PRD 的 NFR-NET）。
 */
export enum FailReason {
  /** 网络不可达：超时、连接失败、DNS 失败 */
  NETWORK_UNREACHABLE = 'NETWORK_UNREACHABLE',
  /** 认证失败：凭据错误，或会话失效且无法自动重登 */
  AUTH_FAILED = 'AUTH_FAILED',
  /** 接口语义变更：页面结构变化导致抓不到 SM2 公钥 / 工单 / CSRF，或非预期状态码 */
  API_CHANGED = 'API_CHANGED',
  /** 解析失败：响应体结构不符预期 */
  PARSE_FAILED = 'PARSE_FAILED',
  /** 用户取消（例如 SSO 中途退出） */
  CANCELLED = 'CANCELLED'
}

/**
 * 认证领域错误。所有跨层的失败都以该类型向上传递，
 * 避免底层 HTTP 细节泄漏到 viewmodel 与页面。
 */
export class AuthError extends Error {
  readonly reason: FailReason;
  /** 供排障用的补充信息；**不得**放入凭据或 Cookie */
  readonly detail: string;

  constructor(reason: FailReason, detail: string) {
    super(`${reason}: ${detail}`);
    this.name = 'AuthError';
    this.reason = reason;
    this.detail = detail;
  }
}

/** 用户凭据；仅在存储层与网络层之间传递，禁止进入 UI 状态与日志 */
export class Credentials {
  readonly username: string;
  readonly password: string;
  /** 设备指纹，32 位十六进制 */
  readonly fingerPrint: string;

  constructor(username: string, password: string, fingerPrint: string) {
    this.username = username;
    this.password = password;
    this.fingerPrint = fingerPrint;
  }
}

/** 用户信息（登录后从网络学堂首页解析） */
export class UserInfo {
  readonly name: string;
  readonly department: string;

  constructor(name: string, department: string) {
    this.name = name;
    this.department = department;
  }
}

/**
 * 登录态。
 *
 * 状态迁移：LOGGED_OUT → LOGGING_IN → LOGGED_IN | LOGGED_OUT(失败)
 * 不允许出现"既非登录中又非已知结果"的中间态（见 spec §5 第 6 项）。
 */
export enum LoginStatus {
  LOGGED_OUT = 'LOGGED_OUT',
  LOGGING_IN = 'LOGGING_IN',
  LOGGED_IN = 'LOGGED_IN'
}
