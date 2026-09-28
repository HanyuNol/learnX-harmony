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

/** 文件列表一次取数的条数上限（照抄上游 `urls.ts:9` 的 `MAX_SIZE`） */
export const FILE_LIST_SIZE: number = 200;

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

/**
 * 学期 id 列表。
 *
 * 端点路径**照抄上游** `thu-learn-lib@4.0.0` 的 `urls.ts`：注意它是 `/b/...` 形态，
 * 与本文件里认证期的 `/f/...` 不是同一类路径，**不要"统一"**。
 * 响应是 JSON 字符串数组，服务端偶发返回 null 项（上游有专门注释），解析层会过滤。
 */
export const LEARN_SEMESTER_LIST: string =
  `${LEARN_PREFIX}/b/wlxt/kc/v_wlkc_xs_xktjb_coassb/queryxnxq`;

/**
 * 当前与下一学期。响应要求 `message === 'success'`，取 `result.id` 作为当前学期。
 * 同样照抄上游路径（`/b/...`）。
 */
export const LEARN_CURRENT_SEMESTER: string =
  `${LEARN_PREFIX}/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester`;

/** 网络学堂首页（学生课程列表页）；CSRF 令牌即从该页提取 */
export const LEARN_STUDENT_HOME: string = `${LEARN_PREFIX}/f/wlxt/index/course/student/`;

/**
 * 某学期的课程列表。**学期 id 与语言都是路径参数**，故都做 URL 编码
 * （学期 id 是外部输入；同类问题见代码审查 R-14：票据未编码）。
 *
 * 路径照抄上游 `thu-learn-lib@4.0.0` 的 `urls.ts:34-37`（学生形态）。
 */
export function learnCourseList(semesterId: string, lang: string): string {
  return `${LEARN_PREFIX}/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId` +
    `/${encodeURIComponent(semesterId)}/${encodeURIComponent(lang)}`;
}

/**
 * 通知列表。**按课程取**，且分"未过期/已过期"两批。
 *
 * 路径照抄上游 `thu-learn-lib@4.0.0` 的 `urls.ts:78-81`（学生形态）：
 * `…/student/pageListXsby` + `Wgq`（未过期）/ `Ygq`（已过期）。
 * 注意它是 `/b/...`（数据接口），与详情页的 `/f/...` 不是同一类。
 */
export function learnNoticeList(expired: boolean): string {
  return `${LEARN_PREFIX}/b/wlxt/kcgg/wlkc_ggb/student/pageListXsby${expired ? 'Ygq' : 'Wgq'}`;
}

/**
 * 通知详情页 URL（`/f/...` 形态）。
 *
 * **由客户端拼**而不是取响应字段：上游就是这么构造的（`index.ts:481`），
 * 它同时是"打开详情时发一次已读请求"的目标。
 */
export function learnNoticeDetailUrl(courseId: string, noticeId: string): string {
  return `${LEARN_PREFIX}/f/wlxt/kcgg/wlkc_ggb/student/beforeViewXs` +
    `?wlkcid=${encodeURIComponent(courseId)}&id=${encodeURIComponent(noticeId)}`;
}

/**
 * 作业列表。**按课程取**，且分**三个端点**：未提交 / 已提交 / 已评分。
 *
 * 路径照抄上游 `thu-learn-lib@4.0.0` 的 `urls.ts:91-117`（学生形态）。
 * 关键：**完成状态来自"请求了哪个端点"**，响应里没有 `submitted/graded` 字段——
 * 三个端点分别对应（false,false）/（true,false）/（true,true）。
 */
export function learnAssignmentList(kind: number): string {
  const tail: string = kind === 0 ? 'zyListWj' : (kind === 1 ? 'zyListYjwg' : 'zyListYpg');
  return `${LEARN_PREFIX}/b/wlxt/kczy/zy/student/${tail}`;
}

/** 作业详情（JSON）：POST `id=<作业本体 id>`，取 `json.msg` 作正文 */
export const LEARN_HOMEWORK_DETAIL: string =
  `${LEARN_PREFIX}/b/wlxt/kczy/zy/student/detail`;

/** 作业详情页（HTML）：附件在这里（`/f/...` 形态，与上面两个 `/b/...` 不同） */
export function learnAssignmentHtmlDetail(courseId: string, homeworkId: string): string {
  return `${LEARN_PREFIX}/f/wlxt/kczy/zy/student/viewCj` +
    `?wlkcid=${encodeURIComponent(courseId)}&xszyid=${encodeURIComponent(homeworkId)}`;
}

/**
 * 文件列表。**按课程取**，一次 GET 拿全（`size` 是取数上限，照抄上游的 200）。
 *
 * 路径照抄上游 `thu-learn-lib@4.0.0` 的 `urls.ts:45-48`（学生形态）。
 * 注意它的成功容器与通知/作业**不同**：学生的文件列表在 `json.object` **本身就是数组**里
 * （通知/作业是 `object.aaData`）——同一套 API 的第三个信封变体。
 */
export function learnFileList(courseId: string): string {
  return `${LEARN_PREFIX}/b/wlxt/kj/wlkc_kjxxb/student/kjxxbByWlkcidAndSizeForStudent` +
    `?wlkcid=${encodeURIComponent(courseId)}&size=${FILE_LIST_SIZE}`;
}

/** 文件分类列表：容器 `object.rows`，文件用 `kjflid` 关联（上游 `urls.ts:50-51`） */
export function learnFileCategoryList(courseId: string): string {
  return `${LEARN_PREFIX}/b/wlxt/kj/wlkc_kjflb/student/pageList` +
    `?wlkcid=${encodeURIComponent(courseId)}`;
}

/**
 * 文件下载。**由客户端拼**（上游 `urls.ts:70-71`），要带会话与 CSRF。
 *
 * `sfgk=0` 是上游写死的参数（照抄，不改）。
 */
export function learnFileDownload(fileId: string): string {
  return `${LEARN_PREFIX}/b/wlxt/kj/wlkc_kjxxb/student/downloadFile` +
    `?sfgk=0&wjid=${encodeURIComponent(fileId)}`;
}

/**
 * 作业附件的下载端点。**注意与课件文件的下载端点不同**：
 * 课件走 `…/kj/wlkc_kjxxb/student/downloadFile?wjid=`，作业附件走
 * `…/kczy/zy/student/downloadFile/<课程 id>/<附件 id>`（上游 `urls.ts:132-133`）。
 */
export function learnAssignmentAttachmentDownload(courseId: string, attachmentId: string): string {
  return `${LEARN_PREFIX}/b/wlxt/kczy/zy/student/downloadFile/`
    + `${encodeURIComponent(courseId)}/${encodeURIComponent(attachmentId)}`;
}

/** 作业提交（POST，multipart：`xszyid` / `zynr` / `fileupload` / `isDeleted`） */
export const LEARN_HOMEWORK_SUBMIT: string = `${LEARN_PREFIX}/b/wlxt/kczy/zy/student/tjzy`;

/** 登出 */
export const LEARN_LOGOUT: string = `${LEARN_PREFIX}/f/j_spring_security_logout`;
// 曾有一个 ID_SESSION_COOKIE 常量，但会话 Cookie 的判定一直走
// WebCookieStore.clearSessionCookieSync()，常量无人引用，已删除（审查 R-23）。
