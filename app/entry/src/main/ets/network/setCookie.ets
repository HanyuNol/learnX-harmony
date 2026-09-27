/**
 * Set-Cookie 头的切分（**纯逻辑**）。
 *
 * 为什么需要它：ArkWeb 的 `configCookieSync` **每次只接受一条 Cookie**，而
 * `headersReceive` 回调给出的 set-cookie 既可能是字符串数组，也可能是以 `, ` 合并的
 * 一整串。切分必须避开 `Expires=Wed, 21 Oct 2015 07:28:00 GMT` 里的逗号。
 *
 * 与"只看名值对"的解析不同，这里**连属性一起保留**：Path 决定 Cookie 的作用域、
 * Expires 决定它是不是会话 Cookie，丢了会让 Cookie 到不了正确的主机或提前失效。
 *
 * 本文件的前身是 `network/cookieJar.ets`（自管内存 Cookie 容器）。容器已退役
 * （ADR-0008 改用 `WebCookieManager` 共享会话），但切分逻辑仍被
 * `network/webCookieStore.ets` 使用，故保留并收窄为只做切分。
 */

/**
 * 以"逗号后紧跟 `名字=`"作为多个 Cookie 的边界——不能见逗号就切，
 * 否则 `Expires=Wed, 21 Oct 2015 ...` 会被切成两段。
 */
const COOKIE_BOUNDARY: RegExp = /,\s*(?=[^;=,\s]+=)/;

/** 把一条（可能合并了多个 Cookie 的）Set-Cookie 头切成单条 Cookie 串 */
export function splitSetCookie(raw: string): string[] {
  const result: string[] = [];
  if (raw.trim().length === 0) {
    return result;
  }

  const segments: string[] = raw.split(COOKIE_BOUNDARY);
  for (const segment of segments) {
    const cookie: string = segment.trim();
    if (cookie.length > 0) {
      result.push(cookie);
    }
  }
  return result;
}
