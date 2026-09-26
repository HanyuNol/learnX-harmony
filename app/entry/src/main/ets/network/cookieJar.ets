/**
 * 轻量 Cookie 管理。
 *
 * 为什么自己管：框架的 `enableAutoCookie` 起始版本为 API 26，本项目 SDK 是 API 24，
 * 用不了；而会话（尤其登录时跨 `id.tsinghua.edu.cn` 与 `learn.tsinghua.edu.cn`
 * 两个主机）完全依赖 Cookie，必须自己维护。
 *
 * 解析部分是**纯函数**，可离线单测——Cookie 串的解析是最容易在真机上才暴露问题的地方。
 */

/** 不应作为 Cookie 名保存的响应属性（大小写不敏感） */
const COOKIE_ATTRIBUTES: string[] = [
  'path', 'domain', 'expires', 'max-age', 'samesite', 'httponly', 'secure', 'version', 'comment'
];

/** 以 `名字=` 为界切分多个 Cookie——避开 Expires 里逗号造成的误切 */
const COOKIE_BOUNDARY: RegExp = /,\s*(?=[^;=,\s]+=)/;

function isCookieAttribute(name: string): boolean {
  return COOKIE_ATTRIBUTES.includes(name.trim().toLowerCase());
}

/**
 * 把服务端返回的原始 Cookie 串解析为 名→值。
 *
 * 兼容两种形态：
 * - 单个 Cookie 带属性：`JSESSIONID=abc; Path=/; HttpOnly`
 * - 多个 Cookie 拼接：`a=1; Path=/, b=2`
 *
 * 每个 Cookie 段内**扫描全部 `;` 片段、取第一个非属性的名值对**，而不是只看第一段。
 * 起初只取第一段是错的：像 `garbage; a=1` 这类输入会让真正的 Cookie 被整段丢弃
 * （该缺陷由单元测试 `无等号的片段应被忽略` 抓出）。
 * 属性一律丢弃；同名后出现的覆盖先出现的。
 */
export function parseCookies(raw: string): Map<string, string> {
  const result: Map<string, string> = new Map();
  if (raw.length === 0) {
    return result;
  }

  const cookieStrings: string[] = raw.split(COOKIE_BOUNDARY);
  for (const cookieString of cookieStrings) {
    const parts: string[] = cookieString.split(';');
    for (const part of parts) {
      const pair: string = part.trim();
      if (pair.length === 0) {
        continue;
      }

      const equalsIndex: number = pair.indexOf('=');
      if (equalsIndex <= 0) {
        continue;
      }

      const name: string = pair.substring(0, equalsIndex).trim();
      const value: string = pair.substring(equalsIndex + 1).trim();
      if (name.length === 0 || isCookieAttribute(name) || value.length === 0) {
        continue;
      }

      // 一个 Cookie 段内只有第一个有效名值对才是 Cookie，其余是属性
      result.set(name, value);
      break;
    }
  }
  return result;
}

/** 从 URL 中取出主机名，用作 Cookie 的作用域键 */
export function hostOf(url: string): string {
  const schemeIndex: number = url.indexOf('://');
  const start: number = schemeIndex >= 0 ? schemeIndex + 3 : 0;
  const end: number = url.indexOf('/', start);
  const hostPort: string = end >= 0 ? url.substring(start, end) : url.substring(start);
  const colonIndex: number = hostPort.indexOf(':');
  return colonIndex >= 0 ? hostPort.substring(0, colonIndex) : hostPort;
}

/**
 * 按主机名分组的 Cookie 容器。
 *
 * 按主机名精确分组而不做 Domain 匹配：本项目的 Cookie 都落在
 * `id.tsinghua.edu.cn` 与 `learn.tsinghua.edu.cn` 两个主机上，精确分组既够用又不引入歧义。
 */
export class CookieJar {
  private byHost: Map<string, Map<string, string>> = new Map();

  /** 收纳服务端在本次响应中下发的 Cookie */
  store(url: string, rawCookies: string): void {
    const parsed: Map<string, string> = parseCookies(rawCookies);
    if (parsed.size === 0) {
      return;
    }

    const host: string = hostOf(url);
    let cookies: Map<string, string> | undefined = this.byHost.get(host);
    if (cookies === undefined) {
      cookies = new Map();
      this.byHost.set(host, cookies);
    }
    parsed.forEach((value: string, name: string) => {
      cookies!.set(name, value);
    });
  }

  /** 生成发往该 URL 的 Cookie 请求头；无 Cookie 时返回空串 */
  headerFor(url: string): string {
    const cookies: Map<string, string> | undefined = this.byHost.get(hostOf(url));
    if (cookies === undefined || cookies.size === 0) {
      return '';
    }

    const pairs: string[] = [];
    cookies.forEach((value: string, name: string) => {
      pairs.push(`${name}=${value}`);
    });
    return pairs.join('; ');
  }

  clear(): void {
    this.byHost.clear();
  }
}
