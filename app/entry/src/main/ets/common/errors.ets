/**
 * 错误四分类的构造与归一。
 *
 * 分类的唯一目的是**区分责任**：网络与服务端的问题不得报成应用缺陷
 * （ARCHITECTURE §5.4、PRD 的 NFR-NET）。因此每一类的判定依据都要写明，
 * 不能凭感觉归类。
 */

import { BusinessError } from '@kit.BasicServicesKit';
import { AuthError, FailReason } from '../model/auth';
import { Logger } from './logger';

const TAG: string = 'errors';

/**
 * 判定为"网络不可达"的 HTTP 错误码（@ohos.net.http）。
 *
 * 判定依据：这一组错误都发生在**数据离开应用之前或链路层**——
 * 域名解析、建连、超时、收发失败，以及 TLS 握手问题。
 * 它们都不是应用逻辑的缺陷，而是环境问题。
 */
const NETWORK_UNREACHABLE_CODES: number[] = [
  2300005, // 代理名解析失败
  2300006, // 域名解析失败
  2300007, // 连接服务器失败
  2300028, // 操作超时
  2300055, // 向对端发送数据失败
  2300056, // 从对端接收数据失败
  2300052, // 服务端未返回任何内容（无响应头也无数据）
  2300058, // 本地 SSL 证书错误
  2300059, // 指定的 SSL 加密套件不可用
  2300060, // 对端 SSL 证书无效
  2300077  // SSL CA 证书不存在或不可访问
];

/** 判定为"认证失败"的 HTTP 状态码 */
const AUTH_STATUS_CODES: number[] = [401, 403];

/** 业务错误：非预期状态码等。`hintKey` 是"可操作引导"的文案键，见 `AuthError.hintKey` */
export function apiChanged(detail: string, hintKey: string = ''): AuthError {
  return new AuthError(FailReason.API_CHANGED, detail, hintKey);
}

/** 构造"网络不可达"错误 */
export function networkUnreachable(detail: string): AuthError {
  return new AuthError(FailReason.NETWORK_UNREACHABLE, detail);
}

/** 构造"认证失败"错误 */
export function authFailed(detail: string): AuthError {
  return new AuthError(FailReason.AUTH_FAILED, detail);
}

/** 构造"解析失败"错误 */
export function parseFailed(detail: string): AuthError {
  return new AuthError(FailReason.PARSE_FAILED, detail);
}

/**
 * 把任意抛出物归一为 AuthError。
 *
 * 已是 AuthError 的原样透传（避免分类信息在层层包装中丢失）；
 * 否则按平台错误码归类；再否则归入 PARSE_FAILED 并保留原文供排障。
 */
export function normalize(err: Object, context: string): AuthError {
  if (err instanceof AuthError) {
    return err;
  }

  const businessError = err as BusinessError;
  const code: number = businessError.code;
  if (typeof code === 'number') {
    if (NETWORK_UNREACHABLE_CODES.includes(code)) {
      return networkUnreachable(`${context} (code=${code})`);
    }
    Logger.warn(TAG, `${context} 未归类的平台错误码 code=${code}`);
    return apiChanged(`${context} (code=${code})`);
  }

  const message: string = businessError.message ?? '';
  return parseFailed(`${context} (${message})`);
}

/**
 * 依据 HTTP 状态码归类。
 *
 * 401/403 视为认证失败；其余非 2xx 视为"接口语义变更"——
 * 因为服务端返回了非预期状态，说明我们对接口的假设过期了。
 */
export function fromStatusCode(status: number, context: string): AuthError {
  if (AUTH_STATUS_CODES.includes(status)) {
    return authFailed(`${context} (status=${status})`);
  }
  return apiChanged(`${context} (status=${status})`);
}
