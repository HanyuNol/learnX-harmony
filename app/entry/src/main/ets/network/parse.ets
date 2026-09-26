/**
 * 登录链路上的 HTML 抓取。
 *
 * 刻意做成**纯函数**（输入字符串、输出字符串，不碰网络与系统能力），
 * 原因有两个：这些正则是最容易随服务端页面改版而失效的地方，必须能离线单测；
 * 以及把"页面结构变了"这件事收敛到一处，便于失效时快速修。
 *
 * 失败一律返回空串，由调用方按上下文归入"接口语义变更"并给出可理解的提示。
 */

/** 匹配 id 为 sm2publicKey 的元素文本内容 */
const SM2_PUBLIC_KEY_PATTERN: RegExp = /id=["']sm2publicKey["'][^>]*>([\s\S]*?)</;

/** 匹配第一个 <a> 标签的 href 属性 */
const FIRST_ANCHOR_HREF_PATTERN: RegExp = /<a\b[^>]*\bhref=["']([^"']*)["']/i;

/** 匹配 CSRF 令牌：`&_csrf=<token>"`，令牌不含空白与引号 */
const CSRF_TOKEN_PATTERN: RegExp = /&_csrf=([^\s"]*)"/;

/**
 * 从统一身份认证登录页提取 SM2 公钥（十六进制串）。
 *
 * 上游用 DOM 选择器取 `#sm2publicKey` 的文本；这里用正则等价实现，
 * 避免为一次取值引入完整的 DOM 解析。
 */
export function extractSm2PublicKey(html: string): string {
  const matched: RegExpMatchArray | null = html.match(SM2_PUBLIC_KEY_PATTERN);
  if (matched === null || matched.length < 2) {
    return '';
  }
  return matched[1].trim();
}

/**
 * 从登录校验响应中提取漫游工单。
 *
 * 上游取页面第一个 `<a>` 的 href，再按 `=` 切分取最后一段。这里照同样的规则，
 * 以保持与上游一致——服务端若改结构，两边会同时失效。
 */
export function extractTicket(html: string): string {
  const matched: RegExpMatchArray | null = html.match(FIRST_ANCHOR_HREF_PATTERN);
  if (matched === null || matched.length < 2) {
    return '';
  }

  const href: string = matched[1];
  if (href.length === 0) {
    return '';
  }

  const segments: string[] = href.split('=');
  return segments[segments.length - 1].trim();
}

/**
 * 从网络学堂首页提取 CSRF 令牌。
 *
 * 该令牌在每次登录/重登后都会失效，必须随之刷新（见 spec §3.2 第 6 步）。
 */
export function extractCsrfToken(html: string): string {
  const matched: RegExpMatchArray | null = html.match(CSRF_TOKEN_PATTERN);
  if (matched === null || matched.length < 2) {
    return '';
  }
  return matched[1];
}

/**
 * 判定响应是否为"会话失效"。
 *
 * 依据上游 noLogin 的判定：最终 URL 含 login_timeout，或状态码 403。
 * 这是服务端表达"你得重新登录"的既有方式，不随页面改版而变。
 */
export function isSessionExpired(finalUrl: string, statusCode: number): boolean {
  return finalUrl.includes('login_timeout') || statusCode === 403;
}

/**
 * 为用户信息解析出姓名与院系。
 *
 * 上游取 `a.user-log` 的文本与 `.fl.up-img-info p:nth-child(2) label`。
 * 同样用正则等价实现；取不到时返回空串，不影响登录成功这一事实。
 */
const USER_NAME_PATTERN: RegExp = /<a[^>]*class=["'][^"']*\buser-log\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i;

export function extractUserName(html: string): string {
  const matched: RegExpMatchArray | null = html.match(USER_NAME_PATTERN);
  if (matched === null || matched.length < 2) {
    return '';
  }
  return stripTags(matched[1]).trim();
}

/** 去掉标签与多余空白，用于从 HTML 片段取纯文本 */
export function stripTags(fragment: string): string {
  return fragment.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
}
