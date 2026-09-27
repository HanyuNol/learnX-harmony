/**
 * 网络学堂与统一身份认证的 URL 常量。
 *
 * 语义对齐上游 thu-learn-lib@4.0.0 的 src/urls.ts；本项目只取认证相关部分，
 * 其余接口随对应 FR 逐步补齐。
 */

/** 统一身份认证前缀 */
export const ID_PREFIX: string = 'https://id.tsinghua.edu.cn';

/** 网络学堂前缀 */
export const LEARN_PREFIX: string = 'https://learn.tsinghua.edu.cn';

/**
 * 统一身份认证登录表单页。
 *
 * 路径中的 token 是校方页面的固定标识，取自上游 thu-learn-lib；
 * 服务端若调整该路径，登录会因抓不到 SM2 公钥而失败，归入"接口语义变更"。
 */
export const ID_LOGIN_FORM: string =
  `${ID_PREFIX}/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0`;

/** 登录凭据校验端点（POST，表单） */
export const ID_LOGIN_CHECK: string = `${ID_PREFIX}/do/off/ui/auth/login/check`;

/**
 * 登录校验端点（设备已在"信任浏览器"名单内时页面使用的形态）。
 *
 * 该形态的表单含 `i_rememberme`，不再需要密码。端点选择见 `network/ssoForm.ets`。
 */
export const ID_LOGIN_CHECK_SINGLE: string = `${ID_PREFIX}/do/off/ui/auth/login/checkSingle`;

/**
 * 网络学堂漫游地址前缀。WebView 导航命中它即视为认证完成。
 *
 * 注意与 `learnAuthRoam()` 的 `/b/...` 是**两条不同路径**：前者是认证页会跳到的入口，
 * 后者是 API 侧建立会话的入口——两者上游都在用，不要合并。
 */
export const LEARN_ROAMING_PREFIX: string = `${LEARN_PREFIX}/f/j_spring_security_thauth_roaming_entry`;

/** 统一身份认证的来源；注入脚本只对它匹配，避免脚本进入无关页面 */
export const ID_ORIGIN: string = ID_PREFIX;

/** 带漫游工单跳转到网络学堂，完成会话建立 */
export function learnAuthRoam(ticket: string): string {
  return `${LEARN_PREFIX}/b/j_spring_security_thauth_roaming_entry?ticket=${ticket}`;
}

/** 网络学堂首页（学生课程列表页）；CSRF 令牌即从该页提取 */
export const LEARN_STUDENT_HOME: string = `${LEARN_PREFIX}/f/wlxt/index/course/student/`;

/** 登出 */
export const LEARN_LOGOUT: string = `${LEARN_PREFIX}/f/j_spring_security_logout`;

// 曾有一个 ID_SESSION_COOKIE 常量，但会话 Cookie 的判定一直走
// WebCookieStore.clearSessionCookieSync()，常量无人引用，已删除（审查 R-23）。
