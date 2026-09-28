/**
 * 往 URL 上挂 CSRF 令牌（**纯逻辑**，零系统依赖，可宿主侧穷举测试）。
 *
 * 为什么单独成模块（2026-09-28 代码审查 R1）：这条规则属 `testing-and-quality` §2 的必测高风险区
 * （"CSRF 的获取-注入-刷新是否覆盖写操作"），而它原先写在 `LearnClient` 的私有方法里、
 * 随平台类一起不可测。**漏注入 CSRF 会让所有 POST 被 403 挡掉**，而现象容易被误当成
 * "密码错误"一类认证问题（本项目真栽过：见 API.md 记录的 403 实测），故必须可测。
 *
 * 规则：
 * 1. 域名标识命中 `tsinghua.edu.cn` 才注入——**注意这包含统一身份认证域**
 *    （见下面的"已知偏差"）；
 * 2. 令牌为空时不注入（会话还没建立）；
 * 3. URL 已有查询串时用 `&`，否则用 `?`。
 *
 * **已知偏差（2026-09-28 审查记录，未改）**：上游 `addCSRFTokenToUrl` **不做任何域名判断**
 * （"add CSRF token to any request URL"），但它的认证域请求走的**不是**带令牌的那条路径，
 * 因此**效果上只有学堂请求带 `_csrf`**；本项目对两域一视同仁，认证域的登录请求也会带这个参数。
 * 现状**设备实测登录可用**，且收窄改动会落在"无法自行复验"的登录路径上（需要用户密码），
 * 故**不改**：若将来认证域变严，再收窄为 `learn.tsinghua.edu.cn`，并在真实登录时复验。
 */

/** 需要注入 CSRF 的域名标识（含统一身份认证域，见上文的已知偏差） */
export const TSINGHUA_HOST_MARKER: string = 'tsinghua.edu.cn';

export function withCsrfToken(url: string, csrfToken: string): string {
  if (csrfToken.length === 0 || !url.includes(TSINGHUA_HOST_MARKER)) {
    return url;
  }
  const separator: string = url.includes('?') ? '&' : '?';
  return `${url}${separator}_csrf=${csrfToken}`;
}
