/**
 * 网络学堂 HTTP 客户端：本项目对外请求的**唯一出口**。
 *
 * 职责：会话 Cookie、CSRF 注入、会话失效自动重登，以及两条登录路径：
 * - `loginWithFormData`：**主路径**，重放 WebView 抓到的表单体（ADR-0008）。
 * - `login`：备选路径，纯 API 七步登录，适用于未启用多因子认证的账号。
 *
 * 业务层不得绕过本类自行发请求（架构不变量 §3）。
 *
 * 与上游 thu-learn-lib 的**有意差异**（均因平台能力所限）：
 * 1. 上游用响应最终 URL 是否含 login_timeout 判定会话失效；框架的 HttpResponse
 *    不暴露重定向后的最终 URL，故改为**状态码 403 或响应体含 login_timeout**判定。
 * 2. 上游用 tough-cookie 自动管理 Cookie；框架的 enableAutoCookie 起始版本为 API 26
 *    （本 SDK 为 24），故改由 `WebCookieStore` 承载——它与 WebView 共享同一份会话，
 *    这正是"重放页面表单体"能成立的前提。
 */

import { http } from '@kit.NetworkKit';
import { Credentials, FailReason, AuthError, UserInfo } from '../model/auth';
import {
  ID_PREFIX,
  ID_LOGIN_FORM,
  ID_LOGIN_CHECK,
  ID_LOGIN_CHECK_SINGLE,
  learnAuthRoam,
  LEARN_STUDENT_HOME,
  LEARN_LOGOUT,
  LEARN_SEMESTER_LIST,
  learnCourseList,
  learnNoticeList,
  learnAssignmentList,
  learnAssignmentHtmlDetail,
  learnFileList,
  learnFileCategoryList,
  learnFileDownload,
  learnAssignmentAttachmentDownload,
  LEARN_HOMEWORK_SUBMIT,
  LEARN_HOMEWORK_DETAIL,
  LEARN_CURRENT_SEMESTER
} from '../model/urls';
import { Logger } from '../common/logger';
import { apiChanged, authFailed, fromStatusCode, normalize } from '../common/errors';
import { extractSm2PublicKey, extractTicket, extractCsrfToken, isSessionExpired, extractUserName } from './parse';
import { WebCookieStore } from './webCookieStore';
import { SsoFingerPrints, classifyCheckResponse } from './ssoForm';
import { encryptPassword } from './sm2';
import { parseCurrentSemesterId, parseSemesterIdList } from './parseSemester';
import { parseCourseList } from './parseCourse';
import { parseNoticeList } from './parseNotice';
import { parseAssignmentDescription, parseAssignmentList, parseAssignmentAttachments } from './parseAssignment';
import { parseFileCategoryList, parseFileList } from './parseFile';
import { MultipartFile, buildMultipartBody } from './multipart';
import { Assignment, AssignmentAttachments } from '../model/assignment';
import { LearnFile } from '../model/file';
import { Notice } from '../model/notice';
import { Course } from '../model/course';

const TAG: string = 'learnClient';

/** 单次请求超时上限，对齐 NFR-PERF */
const TIMEOUT_MS: number = 15000;

/** 登录请求的重试次数。只对网络不可达重试；认证失败与语义变更不重试 */
const LOGIN_RETRY_LIMIT: number = 1;

/** 网络学堂域名标识，用于决定是否注入 CSRF */
const TSINGHUA_HOST_MARKER: string = 'tsinghua.edu.cn';

/**
 * 截止时间解析不出时留一条日志（只打时间串本身，不含任何隐私）。
 *
 * 服务端的时间串形态没有文档（assignments spec §6 待定项），`parseDeadlineTimestamp`
 * 是按常见形态写的；这条日志是**长期守卫**而不是临时探针——形态一变（或原先猜错），
 * 日志里就能看见，从而"已截止/还剩几天"不会静默地全变成"时间未知"。
 */
function logUnparsedDeadline(items: Assignment[]): void {
  for (const item of items) {
    if (item.deadline.length > 0 && item.deadlineTime <= 0) {
      Logger.warn(TAG, `截止时间无法解析 id=${item.id} 原串=「${item.deadline}」`);
    }
  }
}

/**
 * 二次认证页面的标记。
 *
 * 实测：账号开启二次认证时，登录校验的响应是标题为「二次认证」的页面（约 1661 字节），
 * 而非带漫游工单的成功页。这类失败**必须与"密码错误"分开呈现**，
 * 否则会把用户与排障都引向错误方向（见 NFR-NET 的错误四分类要求）。
 */
const SECOND_AUTH_MARKER: string = '二次认证';

/**
 * 需要图形验证码的页面标记。
 *
 * 上游对同一片段做同样判定。本项目不做图形验证码识别——真出现该形态时，
 * 只能引导用户走 WebView 登录（那里由用户自己看验证码）。
 */
const CAPTCHA_MARKER: string = '$("#c_code").removeClass(\'hidden\');';

/** 登录页的"设备已被信任"形态标记，对应另一个校验端点 */
const CHECK_SINGLE_MARKER: string = 'checkSingle';

/** 一次请求的原始结果 */
export class HttpResult {
  readonly body: string;
  readonly status: number;

  constructor(body: string, status: number) {
    this.body = body;
    this.status = status;
  }
}

/** 一次"取字节"请求的结果（下载用，响应体是二进制而非文本） */
export class ByteResult {
  readonly data: ArrayBuffer;
  readonly status: number;

  constructor(data: ArrayBuffer, status: number) {
    this.data = data;
    this.status = status;
  }
}

/** 把 HttpResponse.result 归一为字符串 */
function asText(result: string | Object | ArrayBuffer): string {
  if (typeof result === 'string') {
    return result;
  }
  return JSON.stringify(result);
}

/**
 * 日志用：只报三项设备信任标识**拿到了没有**，不报值。
 *
 * 这三项是"服务端是否把本机当成已登记浏览器"的关键，排障时首先要知道它们有没有拿到；
 * 值本身是设备标识，不进日志。
 */
function describePrints(prints: SsoFingerPrints): string {
  const has = (value: string): string => (value.length > 0 ? '有' : '无');
  return `设备信任标识 fingerPrint=${has(prints.fingerPrint)} fingerGenPrint=${has(prints.fingerGenPrint)} ` +
    `fingerGenPrint3=${has(prints.fingerGenPrint3)}`;
}

export class LearnClient {
  private static instance: LearnClient | null = null;

  /** 会话级请求实例。全程复用同一个，避免连接层状态反复重建 */
  private csrfToken: string = '';
  /**
   * 进行中的自动重登。
   *
   * 并发的两个请求可能同时发现会话失效；若各自 `login()`，而 `login` 第一步就是
   * **清进程级会话 Cookie + 清 CSRF**，后来的那次会把前一次刚建立的会话清掉
   * （SM2 密钥对与会话绑定，于是双双失败），症状正是"丢会话被归成密码错误"——
   * 与 R-03 修掉的那类相同，只是根因换成了重登互相踩（代码审查 N-01）。
   * 共享同一个 Promise，保证并发下**只登一次**。
   */
  private reloginInFlight: Promise<void> | null = null;
  private credentials: Credentials | null = null;

  private constructor() {
  }

  /**
   * 建一个**只服务这一次请求**的实例，并把响应头监听绑到该请求自己的 URL 上。
   *
   * 为什么不再共用一个实例：`headersReceive` 的事件不带 URL，共用一个实例时只能用
   * "最后写入的 URL"去猜 Cookie 属于哪个主机——并发请求下必然猜错，把会话 Cookie
   * 写到错误主机，症状会被下游归成"密码错误"（代码审查 R-03）。
   * 每请求一个实例后，事件与请求一一对应，归属不再需要猜。
   *
   * 代价是放弃实例级的连接复用（原实现为此共用一个实例）。这是刻意的取舍：
   * 归属正确优先，且本项目没有"同主机高频请求"的场景。
   */
  private static createRequest(url: string, onHeader: (url: string, header: Object) => void): http.HttpRequest {
    const request: http.HttpRequest = http.createHttp();
    request.on('headersReceive', (header: Object) => {
      onHeader(url, header);
    });
    return request;
  }

  /**
   * 响应头事件回调——**取 Set-Cookie 的第三条通道**。
   *
   * 前两条（`HttpResponse.cookies` 字段、`response.header` 的 set-cookie）在 API 24 上
   * 都取不到会话 Cookie，服务端因此丢会话、解不开 SM2 密文。官方文档称 `headersReceive`
   * 自 API 8 起替代旧的 `headerReceive`，是独立于 `response.header` 的事件通道。
   */
  private static handleResponseHeader(url: string, header: Object): void {
    try {
      // 回调入参是响应头对象（官方示例即把它当对象处理），但类型签名只给到 `Object`；
      // 收窄成表类型才能按键名取值——ArkTS 禁动态属性访问。
      // 不用 JSON 往返来收窄：那是深拷贝，代价大且会被 linter 判为反模式。
      const parsed: Record<string, Object> = header as Record<string, Object>;
      let raw: Object = parsed['set-cookie'];
      if (raw === undefined) {
        raw = parsed['Set-Cookie'];
      }
      if (typeof raw === 'string') {
        WebCookieStore.storeFromResponse(url, raw);
      } else if (Array.isArray(raw)) {
        const items: Array<string> = raw as Array<string>;
        for (const item of items) {
          if (typeof item === 'string') {
            WebCookieStore.storeFromResponse(url, item);
          }
        }
      }
    } catch (err) {
      Logger.warn(TAG, 'headersReceive 处理失败，本次请求继续');
    }
  };

  static getInstance(): LearnClient {
    if (LearnClient.instance === null) {
      LearnClient.instance = new LearnClient();
    }
    return LearnClient.instance;
  }

  /**
   * 重置会话的**应用内**状态：CSRF 与内存凭据。
   *
   * 刻意不动 Cookie：Cookie 由 WebCookieStore 承载，且 WebView 主导登录时它承载的正是
   * "页面那一次会话"——清掉它，服务端就解不开页面加密的密码（ADR-0008）。
   * 需要干净会话起步时另调 `WebCookieStore.clearSession()`（见 `login`）。
   */
  private resetSession(): void {
    this.csrfToken = '';
    this.credentials = null;
  }

  getCsrfToken(): string {
    return this.csrfToken;
  }

  /** 为 *.tsinghua.edu.cn 的请求追加 CSRF 查询参数（对齐上游 addCSRFTokenToUrl） */
  /**
   * 往 URL 上挂 CSRF 令牌。
   *
   * **每个请求都要挂**（GET 与 POST 一样）：上游是在 `#myFetchWithToken` 里对所有请求
   * 无条件注入（`thu-learn-lib/src/index.ts:85-90`），Spring 的 CSRF 校验对 POST 同样生效。
   * 本项目原先只在 GET 路径注入，结果**所有 POST 都被 403 挡掉**——实测：通知扇出 12 门课
   * 全失败、`status=403`。（登出同样走 POST，也受影响。）
   */
  private addCsrf(url: string): string {
    if (!url.includes(TSINGHUA_HOST_MARKER) || this.csrfToken.length === 0) {
      return url;
    }
    const separator: string = url.includes('?') ? '&' : '?';
    return `${url}${separator}_csrf=${this.csrfToken}`;
  }

  /** 组装请求头，并按主机注入已持有的 Cookie */
  private buildHeaders(url: string, accept: string, contentType: string): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Accept'] = accept;
    if (contentType.length > 0) {
      headers['Content-Type'] = contentType;
    }
    const cookie: string = WebCookieStore.headerFor(url);
    if (cookie.length > 0) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /** 发起一次 GET，返回响应体与状态码 */
  private async get(url: string): Promise<HttpResult> {
    const request: http.HttpRequest = LearnClient.createRequest(url, LearnClient.handleResponseHeader);
    try {
      const response: http.HttpResponse = await request.request(this.addCsrf(url), {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(url, 'text/html,application/json', ''),
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      request.destroy();
      return new HttpResult(asText(response.result), response.responseCode as number);
    } catch (err) {
      request.destroy();
      throw normalize(err, `GET ${this.maskUrl(url)}`);
    }
  }

  /** 发起一次表单 POST（application/x-www-form-urlencoded） */
  private async postForm(url: string, fields: Map<string, string>): Promise<HttpResult> {
    const pairs: string[] = [];
    fields.forEach((value: string, key: string) => {
      pairs.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    });
    const body: string = pairs.join('&');

    const request: http.HttpRequest = LearnClient.createRequest(url, LearnClient.handleResponseHeader);
    try {
      const response: http.HttpResponse = await request.request(this.addCsrf(url), {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(url, 'text/html', 'application/x-www-form-urlencoded'),
        extraData: body,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      request.destroy();
      return new HttpResult(asText(response.result), response.responseCode as number);
    } catch (err) {
      request.destroy();
      throw normalize(err, `POST ${this.maskUrl(url)}`);
    }
  }

  /**
   * 发起一次 multipart/form-data POST。
   *
   * 校方登录表单接受 multipart（上游用 React Native 的 FormData 即此格式）；
   * 对照实验也表明 urlencoded 同样被接受，故两种编码都不是失败原因
   * （见 CHANGELOG 的更正说明）。这里沿用 multipart 以对齐上游。
   */
  private async postMultipart(url: string, fields: Map<string, string>): Promise<HttpResult> {
    const boundary: string = '----learnXBoundary8f3a1c';
    let body: string = '';
    fields.forEach((value: string, key: string) => {
      body += `--${boundary}\r\n`;
      body += `Content-Disposition: form-data; name="${key}"\r\n\r\n`;
      body += `${value}\r\n`;
    });
    body += `--${boundary}--\r\n`;

    const request: http.HttpRequest = LearnClient.createRequest(url, LearnClient.handleResponseHeader);
    try {
      const response: http.HttpResponse = await request.request(this.addCsrf(url), {
        method: http.RequestMethod.POST,
        // Accept 用 `*/*`：这些端点可能返回 JSON（如通知列表），只声明 text/html 会被判
        // 406 Not Acceptable。上游的 fetch 默认就是 `*/*`（实测踩到：改前 12 门课全 406）
        header: this.buildHeaders(url, '*/*', `multipart/form-data; boundary=${boundary}`),
        extraData: body,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      request.destroy();
      return new HttpResult(asText(response.result), response.responseCode as number);
    } catch (err) {
      request.destroy();
      throw normalize(err, `POST(multipart) ${this.maskUrl(url)}`);
    }
  }

  /** 日志用：只保留 URL 的路径部分，避免把可能带令牌的查询串写进日志 */
  private maskUrl(url: string): string {
    const questionMark: number = url.indexOf('?');
    return questionMark >= 0 ? `${url.substring(0, questionMark)}?...` : url;
  }

  /** 判定响应是否表示会话失效 */
  private isExpired(result: HttpResult): boolean {
    return isSessionExpired(result.body, result.status);
  }

  /**
   * 登录链路的收尾：取漫游工单 → 漫游建会话 → 取 CSRF。
   *
   * 两条登录路径共用本段——它们的差别只在"如何提交凭据"。
   */
  private async establishSession(checkResult: HttpResult, context: string): Promise<void> {
    // 步骤 4：从响应中取漫游工单
    const ticket: string = extractTicket(checkResult.body);
    if (ticket.length === 0) {
      // 只记长度、归类与开头片段，不记全文：用于区分"服务端拒绝凭据"与"响应结构变了"，
      // 这两种原因在用户看来都是"登录不上"，此前无法从日志分辨
      const excerpt: string = checkResult.body.substring(0, 120).replace(/\s+/g, ' ');
      Logger.warn(TAG, `${context} 响应未含工单 status=${checkResult.status} ` +
        `len=${checkResult.body.length} 归类=${classifyCheckResponse(checkResult.body)} head=${excerpt}`);

      // 账号开启二次认证时，服务端返回"二次认证"页而非工单。
      // 这**不是**密码错误——此前一律报"密码错误"，会把用户和排障都带偏。
      if (checkResult.body.includes(SECOND_AUTH_MARKER)) {
        throw apiChanged('该账号需要多因子认证，且本机尚未被登记为信任浏览器，请回到网页登录完成认证');
      }
      throw authFailed('未取得漫游工单，通常是学号或密码错误');
    }

    // 步骤 5：带工单漫游到网络学堂，建立会话
    const roamResult: HttpResult = await this.get(learnAuthRoam(ticket));
    if (roamResult.status !== 200) {
      throw fromStatusCode(roamResult.status, '漫游到网络学堂');
    }

    await this.fetchCsrf();
  }

  /** 从网络学堂首页提取 CSRF 令牌，并把 Cookie 落盘 */
  private async fetchCsrf(): Promise<void> {
    const homeResult: HttpResult = await this.get(LEARN_STUDENT_HOME);
    if (homeResult.status !== 200) {
      throw fromStatusCode(homeResult.status, '获取网络学堂首页');
    }
    const token: string = extractCsrfToken(homeResult.body);
    if (token.length === 0) {
      throw apiChanged('未能从首页提取 CSRF 令牌，接口可能已变更');
    }
    this.csrfToken = token;

    // 立刻落盘：验收要求"杀进程重开仍保持登录态"，不能只靠 30s 的周期保存
    WebCookieStore.persist();
  }

  /**
   * 用 WebView 截到的**漫游票据**直接建立会话——收尾的首选路径。
   *
   * 为什么它比"重新登录一遍"更可靠：它就是浏览器原本要做的那一步，因此
   * **不需要密码、不需要设备已被登记为信任浏览器**。后者在真实账号上恰恰会失败
   * （校方页面判定"浏览器处于隐私模式"而拒绝登记），一旦没登记上，任何重新登录
   * 都会被要求验证码，纯 API 路径就永远走不通。
   *
   * **刻意不清 Cookie**：漫游请求本就该带着页面的会话（浏览器自己发的话也是带着的），
   * 清掉反而可能让票据校验失去上下文。
   */
  async loginWithRoamUrl(credentials: Credentials, roamUrl: string, context: string): Promise<void> {
    this.resetSession();

    const roamResult: HttpResult = await this.get(roamUrl);
    if (roamResult.status !== 200) {
      throw fromStatusCode(roamResult.status, context);
    }

    await this.fetchCsrf();
    this.credentials = credentials;
    Logger.info(TAG, `${context}成功（复用网页会话，未重新登录）`);
  }

  /**
   * 备选路径：纯 API 登录（spec §3.2）。
   *
   * 仅适用于**未启用多因子认证**的账号，以及启动时的静默恢复与会话失效自动重登。
   * 启用多因子认证的账号必须走 WebView 主导路径——验证码只能在真实页面上由用户输入。
   */
  async login(credentials: Credentials): Promise<void> {
    await this.loginWithFingerPrints(credentials, SsoFingerPrints.empty(), '纯 API 登录');
  }

  /**
   * **主路径的收尾**：带着页面生成的设备信任标识，在**全新会话**里重新登录（ADR-0008）。
   *
   * 为什么是"重新登录"而不是"重放页面那份表单体"：
   * - `i_pass` 是页面用它那次会话的 SM2 公钥加密的，密文与页面会话绑定；重放它要求
   *   我们的请求恰好带着页面那次会话，实测在真实账号下拿不到漫游工单。
   * - 上游 `learnX` 也是重新登录：抓取表单体的目的**只是拿到
   *   `fingerPrint` / `fingerGenPrint` / `fingerGenPrint3` 这三个应用构造不出的设备信任标识，
   *   密码则由新会话的公钥重新加密（`thu-learn-lib` 的
   *   `login(username, password, fingerPrint, fingerGenPrint, fingerGenPrint3)`）。
   *   服务端据此认出"同一台已登记的浏览器"，不再要求验证码。
   *
   * 这与 ADR-0008 §决策 5（"以抓到的表单数据执行既有 API 登录流程以建立会话"）一致——
   * 早期实现把"以抓到的表单数据"读成了"重放表单体"，是误读。
   */
  async loginWithFingerPrints(
    credentials: Credentials,
    prints: SsoFingerPrints,
    context: string = 'WebView 表单登录'
  ): Promise<void> {
    // 干净会话起步（对齐上游登录前清 JSESSIONID）：SM2 密钥对绑在会话上，
    // 沿用旧会话会让服务端把这次登录绑到上一次的会话上。
    // **只清会话 Cookie**，保留可能用于认设备的持久 Cookie。
    WebCookieStore.clearSession();
    this.resetSession();

    let attempt: number = 0;
    while (true) {
      try {
        await this.performLogin(credentials, prints);
        this.credentials = credentials;
        Logger.info(TAG, `${context}成功 ${describePrints(prints)}`);
        return;
      } catch (err) {
        const error: AuthError = normalize(err, context);
        // 只对网络不可达重试：认证失败与接口语义变更重试无意义，且会放大失败
        if (error.reason !== FailReason.NETWORK_UNREACHABLE || attempt >= LOGIN_RETRY_LIMIT) {
          throw error;
        }
        attempt++;
        Logger.warn(TAG, `${context} 因网络问题失败，第 ${attempt} 次重试`);
      }
    }
  }

  /**
   * 一次登录尝试：取登录页 → 提交凭据（或走已信任设备表单）→ 收尾。
   *
   * `prints` 为页面抓到的设备信任标识；纯 API 路径传空串（与旧行为一致）。
   */
  private async performLogin(credentials: Credentials, prints: SsoFingerPrints): Promise<void> {
    const loginPage: HttpResult = await this.get(ID_LOGIN_FORM);
    if (loginPage.status !== 200) {
      throw fromStatusCode(loginPage.status, '获取统一身份认证登录页');
    }

    // 设备指纹优先用页面抓到的那一个：它是服务端登记过的信任标识，与本地持久化的是
    // 同一个值（注入脚本就是把它写进页面的），但以服务端见过的为准。
    const fingerPrint: string = prints.fingerPrint.length > 0 ? prints.fingerPrint : credentials.fingerPrint;

    // 设备已在"信任浏览器"名单内时，页面换成另一套表单，校验端点也不同
    if (loginPage.body.includes(CHECK_SINGLE_MARKER)) {
      const singleFields: Map<string, string> = new Map();
      singleFields.set('i_rememberme', 'on');
      singleFields.set('fingerPrint', fingerPrint);
      singleFields.set('fingerGenPrint', prints.fingerGenPrint);
      const singleResult: HttpResult = await this.postMultipart(ID_LOGIN_CHECK_SINGLE, singleFields);
      if (singleResult.status !== 200) {
        throw fromStatusCode(singleResult.status, '提交登录凭据（已信任设备）');
      }
      await this.establishSession(singleResult, '已信任设备登录');
      return;
    }

    if (loginPage.body.includes(CAPTCHA_MARKER)) {
      throw apiChanged('登录需要图形验证码，请使用网页登录方式完成认证');
    }

    const publicKeyHex: string = extractSm2PublicKey(loginPage.body);
    if (publicKeyHex.length === 0) {
      throw apiChanged('登录页未找到 SM2 公钥，页面结构可能已变更');
    }

    // 诊断：服务端依赖会话 Cookie（JSESSIONID）绑定 SM2 密钥对。
    // 实测：不带该 Cookie 提交会得到"数据已丢失，请重新操作"的错误页而非工单。
    Logger.info(TAG, `登录页取毕 cookieLen=${WebCookieStore.headerFor(ID_LOGIN_FORM).length}`);

    const encryptedPassword: string = await encryptPassword(credentials.password, publicKeyHex);
    const fields: Map<string, string> = new Map();
    fields.set('i_user', credentials.username);
    fields.set('i_pass', `04${encryptedPassword.startsWith('04') ? encryptedPassword.substring(2) : encryptedPassword}`);
    fields.set('singleLogin', 'on');
    fields.set('fingerPrint', fingerPrint);
    fields.set('fingerGenPrint', prints.fingerGenPrint);
    fields.set('fingerGenPrint3', prints.fingerGenPrint3);
    fields.set('i_captcha', '');

    const checkResult: HttpResult = await this.postMultipart(ID_LOGIN_CHECK, fields);
    Logger.info(TAG, `提交登录时 cookieLen=${WebCookieStore.headerFor(ID_LOGIN_CHECK).length}`);
    if (checkResult.status !== 200) {
      throw fromStatusCode(checkResult.status, '提交登录凭据');
    }

    await this.establishSession(checkResult, '登录校验');
  }

  /**
   * 用已保存的凭据静默恢复会话（应用启动时）。
   *
   * **先看 Cookie 里的会话还活着没有**：活着就什么都不做——那正是"杀进程重开仍是
   * 登录态"；只有会话确实失效才走一次纯 API 登录。
   *
   * 此前实现无条件调 `login()`，而 `login()` 会清掉会话 Cookie，
   * 于是启动时会把一份好端端的持久化会话清掉：登录态永远恢复不了，且从日志
   * 只能看到"登录失败"，看不出是被自己清掉的。
   */
  async restoreSession(credentials: Credentials): Promise<void> {
    // 先挂上：会话失效时 getWithAuth 才有凭据可自动重登
    this.credentials = credentials;

    const home: HttpResult = await this.get(LEARN_STUDENT_HOME);
    if (home.status === 200 && !this.isExpired(home)) {
      const token: string = extractCsrfToken(home.body);
      if (token.length > 0) {
        this.csrfToken = token;
        Logger.info(TAG, '沿用已持久化的会话');
        return;
      }
    }

    Logger.info(TAG, '已持久化的会话不可用，重新登录');
    await this.login(credentials);
  }

  /**
   * 以干净的**会话**起步（进入 WebView 主导登录前）。
   *
   * 只清会话 Cookie，**保留持久 Cookie**——服务端可能用后者认设备，
   * 抹掉它会让本机每次登录都被当成"从未见过、且不能持久化"的浏览器
   * （见 `WebCookieStore.clearSession` 的说明）。
   * 对齐上游"登录前只清 id 域 JSESSIONID"的意图。
   */
  startFreshSession(): void {
    Logger.info(TAG, `进入登录页前 id 域 Cookie=[${WebCookieStore.cookieNamesFor(ID_PREFIX)}]`);
    WebCookieStore.clearSession();
    Logger.info(TAG, `清除后 id 域 Cookie=[${WebCookieStore.cookieNamesFor(ID_PREFIX)}]`);
    this.resetSession();
  }

  /** 登出并清空本地**会话**状态（保留持久 Cookie，见 `WebCookieStore.clearSession`） */
  async logout(): Promise<void> {
    try {
      await this.postForm(LEARN_LOGOUT, new Map<string, string>());
    } catch (err) {
      // 登出失败不影响本地状态清理：把用户登出意图贯彻到底
      Logger.warn(TAG, '服务端登出失败，仍清理本地会话');
    }
    WebCookieStore.clearSession();
    this.resetSession();
  }

  /**
   * 带会话的请求；命中会话失效则自动重登一次并重放。
   *
   * 无凭据（用户未保存密码）时直接抛认证失败，由页面引导重新登录。
   *
   * 已知限制：自动重登走的是**纯 API 路径**，对启用多因子认证的账号依赖
   * "设备已被信任"才能成功；失败时向上抛认证失败，由页面引导用户重新走网页登录。
   */
  async getWithAuth(url: string): Promise<HttpResult> {
    const first: HttpResult = await this.get(url);
    if (!this.isExpired(first)) {
      return first;
    }

    const credentials: Credentials | null = this.credentials;
    if (credentials === null) {
      throw authFailed('会话已失效，且本地无凭据可自动重登');
    }

    await this.reloginOnce(credentials);

    const second: HttpResult = await this.get(url);
    if (this.isExpired(second)) {
      // 重登后仍失效：不再循环，交给上层引导用户
      throw authFailed('自动重登后会话仍失效');
    }
    return second;
  }

  /**
   * 学期 id 列表（未排序；"最新在前"由 repository 决定）。
   *
   * 非 2xx 由 `fromStatusCode` 分类；响应结构不符由解析层抛"解析失败"。
   * 会话失效时 `getWithAuth` 会先试自动重登（沿用既有语义）。
   */
  async fetchSemesterIds(): Promise<string[]> {
    const result: HttpResult = await this.getWithAuth(LEARN_SEMESTER_LIST);
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取学期列表');
    }
    return parseSemesterIdList(result.body);
  }

  /**
   * 某学期的课程列表。
   *
   * `lang` 由 repository 从 `native/localeAdapter` 取好传进来——网络层不依赖系统能力。
   * 非 2xx 由 `fromStatusCode` 分类；结构不符由解析层抛"解析失败"。
   */
  async fetchCourses(semesterId: string, lang: string): Promise<Course[]> {
    const result: HttpResult = await this.getWithAuth(learnCourseList(semesterId, lang));
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取课程列表');
    }
    return parseCourseList(result.body);
  }

  /**
   * 某课程的**全部**通知：未过期与已过期两批（上游也是两次请求再合并）。
   *
   * `courseName` 由 repository 从课程列表取好传进来——通知接口不返回课程信息，
   * 上游同样是在客户端回填。
   */
  async fetchNoticesOfCourse(courseId: string, courseName: string): Promise<Notice[]> {
    const unexpired: Notice[] = await this.fetchNoticeBatch(courseId, courseName, false);
    const expired: Notice[] = await this.fetchNoticeBatch(courseId, courseName, true);
    return unexpired.concat(expired);
  }

  /** 单批通知（`expired=false` 未过期 / `true` 已过期）。表单体只有 `aoData` 一个字段 */
  private async fetchNoticeBatch(courseId: string, courseName: string, expired: boolean): Promise<Notice[]> {
    const fields: Map<string, string> = new Map();
    // 与上游一致的形态：aoData 是一个 JSON 数组的字符串（multipart 表单字段）
    fields.set('aoData', JSON.stringify([{ name: 'wlkcid', value: courseId }]));

    const result: HttpResult = await this.postMultipart(learnNoticeList(expired), fields);
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取通知列表');
    }
    return parseNoticeList(result.body, courseId, courseName);
  }

  /**
   * 某课程的作业：**三个端点**（未提交/已提交/已评分）分别请求后合并。
   *
   * 完成状态由端点决定（见 `model/assignment.ets` 的 STATUS_* 常量与 spec §3.1）。
   */
  async fetchAssignmentsOfCourse(courseId: string, courseName: string, courseTeacherName: string): Promise<Assignment[]> {
    const unsubmitted: Assignment[] =
      await this.fetchAssignmentBatch(courseId, courseName, courseTeacherName, 0, false, false);
    const submitted: Assignment[] =
      await this.fetchAssignmentBatch(courseId, courseName, courseTeacherName, 1, true, false);
    const graded: Assignment[] =
      await this.fetchAssignmentBatch(courseId, courseName, courseTeacherName, 2, true, true);
    return unsubmitted.concat(submitted).concat(graded);
  }

  private async fetchAssignmentBatch(courseId: string, courseName: string, courseTeacherName: string,
                                     kind: number, submitted: boolean, graded: boolean): Promise<Assignment[]> {
    const fields: Map<string, string> = new Map();
    fields.set('aoData', JSON.stringify([{ name: 'wlkcid', value: courseId }]));
    const result: HttpResult = await this.postMultipart(learnAssignmentList(kind), fields);
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取作业列表');
    }
    const items: Assignment[] =
      parseAssignmentList(result.body, courseId, courseName, courseTeacherName, submitted, graded);
    logUnparsedDeadline(items);
    return items;
  }

  /** 作业详情正文（POST `id=<作业本体 id>`，取 json.msg） */
  async fetchAssignmentDescription(baseId: string): Promise<string> {
    const fields: Map<string, string> = new Map();
    fields.set('id', baseId);
    const result: HttpResult = await this.postMultipart(LEARN_HOMEWORK_DETAIL, fields);
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取作业详情');
    }
    return parseAssignmentDescription(result.body);
  }

  /**
   * 作业详情页 HTML 里的四类附件（GET `viewCj?wlkcid=<课程>&xszyid=<学生作业 id>`）。
   *
   * 与正文分开的原因：正文在上面的 JSON 端点里，附件只在这个 HTML 页里
   * （上游 `index.ts:1090-1091` 也是两个请求一起发，JSON 的正文**覆盖** HTML 的那份）。
   */
  async fetchAssignmentAttachments(courseId: string, homeworkId: string): Promise<AssignmentAttachments> {
    const result: HttpResult = await this.getWithAuth(learnAssignmentHtmlDetail(courseId, homeworkId));
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取作业附件');
    }
    return parseAssignmentAttachments(result.body);
  }

  /**
   * 某课程的文件：**两次 GET**（文件列表 + 分类列表），分类名由 `kjflid` 关联回填。
   *
   * 分类是展示用的附加信息：取不到时**降级为空映射**（列表项少一段文字），
   * 不让"分类接口挂了"表现成"这门课没有文件"。
   */
  async fetchFilesOfCourse(courseId: string, courseName: string,
                           courseTeacherName: string): Promise<LearnFile[]> {
    let categoryNames: Map<string, string> = new Map();
    try {
      const categoryResult: HttpResult = await this.getWithAuth(learnFileCategoryList(courseId));
      if (categoryResult.status === 200) {
        categoryNames = parseFileCategoryList(categoryResult.body);
      }
    } catch (err) {
      Logger.warn(TAG, `文件分类获取失败 course=${courseId}，分类名留空`);
    }

    const result: HttpResult = await this.getWithAuth(learnFileList(courseId));
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取文件列表');
    }
    return parseFileList(result.body, courseId, courseName, courseTeacherName, categoryNames);
  }

  /**
   * 下载一个文件的**字节**（带会话与 CSRF）。
   *
   * 落盘不在这里做：网络层只负责"取回字节"，写文件属系统能力，走 `native.fileAdapter`
   * （见 files spec §3.3 第 1 条）。
   *
   * 会话失效的判定与 `getWithAuth` 一致（403 视为失效，自动重登一次再试）——
   * 只是响应体是二进制，无法像文本那样查 `login_timeout` 标记，故以状态码为准。
   */
  async downloadFileBytes(fileId: string, onProgress?: (received: number, total: number) => void): Promise<ArrayBuffer> {
    return this.downloadBytesVia(learnFileDownload(fileId), onProgress);
  }

  /**
   * 下载**作业附件**的字节。
   *
   * 端点与课件文件**不同**（作业附件是 `…/kczy/zy/student/downloadFile/<课程>/<附件 id>`，
   * 见 `learnAssignmentAttachmentDownload`），其余流程（会话注入、403 重登、字节返回）
   * 与 `downloadFileBytes` 完全一致，故共用 `downloadBytesVia`。
   */
  async downloadAssignmentAttachmentBytes(courseId: string, attachmentId: string,
                                          onProgress?: (received: number, total: number) => void): Promise<ArrayBuffer> {
    return this.downloadBytesVia(learnAssignmentAttachmentDownload(courseId, attachmentId), onProgress);
  }

  /** 下载字节的通用流程：取一次 → 遇 403 自动重登一次 → 再取，非 200 归类报错 */
  private async downloadBytesVia(url: string,
                                 onProgress?: (received: number, total: number) => void): Promise<ArrayBuffer> {
    const first: ByteResult = await this.getBytes(url, onProgress);
    let status: number = first.status;
    let data: ArrayBuffer = first.data;

    if (status === 403) {
      const credentials: Credentials | null = this.credentials;
      if (credentials === null) {
        throw authFailed('会话已失效，且本地无凭据可自动重登');
      }
      Logger.info(TAG, '下载遇会话失效，尝试自动重登后重试');
      await this.reloginOnce(credentials);
      const second: ByteResult = await this.getBytes(url, onProgress);
      status = second.status;
      data = second.data;
    }

    if (status !== 200) {
      throw fromStatusCode(status, '下载文件');
    }
    return data;
  }

  /**
   * GET 原始字节（`expectDataType: ARRAY_BUFFER`），返回状态码供调用方判定。
   *
   * `onProgress` 接到 `dataReceiveProgress` 事件上（收了多少 / 一共多少）。服务端不给
   * `Content-Length` 时 `total` 为 0，由调用方按"进度未知"处理——**不猜百分比**。
   */
  private async getBytes(url: string, onProgress?: (received: number, total: number) => void): Promise<ByteResult> {
    const request: http.HttpRequest = LearnClient.createRequest(url, LearnClient.handleResponseHeader);
    if (onProgress !== undefined) {
      const report: (received: number, total: number) => void = onProgress;
      request.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
        try {
          report(info.receiveSize, info.totalSize);
        } catch (err) {
          Logger.warn(TAG, '下载进度回调抛错，已隔离');
        }
      });
    }
    try {
      const response: http.HttpResponse = await request.request(this.addCsrf(url), {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(url, '*/*', ''),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      request.destroy();
      const raw: string | Object | ArrayBuffer = response.result;
      const data: ArrayBuffer = raw instanceof ArrayBuffer ? raw : new ArrayBuffer(0);
      return new ByteResult(data, response.responseCode as number);
    } catch (err) {
      request.destroy();
      throw normalize(err, `GET(bytes) ${this.maskUrl(url)}`);
    }
  }

  /**
   * 提交作业（含可选附件）。
   *
   * 表单字段照上游 `urls.ts:141-156` 写死：`xszyid`（学生作业 id）、`zynr`（正文）、
   * `fileupload`（**没有附件时也要传一个值为字符串 `undefined` 的文本字段**——服务端以此
   * 判断"本次没有上传文件"，而不是靠字段缺失）、`isDeleted`（`1` 表示移除已提交的附件）。
   *
   * 成功判定 `result === 'success'`；其余按"操作失败"归类（与账号密码无关，
   * 不得报成认证问题）。
   */
  async submitHomework(xszyid: string, content: string, file: MultipartFile | null,
                       removeAttachment: boolean): Promise<void> {
    const fields: Map<string, string> = new Map();
    fields.set('xszyid', xszyid);
    fields.set('zynr', content);
    fields.set('isDeleted', removeAttachment ? '1' : '0');
    if (file === null) {
      fields.set('fileupload', 'undefined');
    }

    const boundary: string = '----learnXSubmitBoundary7c41e9';
    const body: ArrayBuffer = buildMultipartBody(boundary, fields, file);

    const request: http.HttpRequest = LearnClient.createRequest(LEARN_HOMEWORK_SUBMIT, LearnClient.handleResponseHeader);
    let response: http.HttpResponse;
    try {
      response = await request.request(this.addCsrf(LEARN_HOMEWORK_SUBMIT), {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(LEARN_HOMEWORK_SUBMIT, '*/*',
          `multipart/form-data; boundary=${boundary}`),
        extraData: body,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      request.destroy();
    } catch (err) {
      request.destroy();
      throw normalize(err, '提交作业');
    }

    const text: string = asText(response.result);
    if (response.responseCode as number !== 200) {
      throw fromStatusCode(response.responseCode as number, '提交作业');
    }
    if (!text.includes('"success"')) {
      // 服务端用 JSON 报文表达业务失败（如已过截止时间），归类为"操作失败"而非网络问题
      Logger.warn(TAG, `提交作业未成功 status=${response.responseCode as number}`);
      throw apiChanged('提交作业未成功（服务端未返回 success）');
    }
  }

  /** 服务端认定的当前学期 id */
  async fetchCurrentSemesterId(): Promise<string> {
    const result: HttpResult = await this.getWithAuth(LEARN_CURRENT_SEMESTER);
    if (result.status !== 200) {
      throw fromStatusCode(result.status, '获取当前学期');
    }
    return parseCurrentSemesterId(result.body);
  }

  /** 自动重登：并发下共享同一次登录（见 `reloginInFlight` 的说明） */
  private async reloginOnce(credentials: Credentials): Promise<void> {
    if (this.reloginInFlight === null) {
      Logger.info(TAG, '会话失效，尝试自动重登');
      this.reloginInFlight = this.performRelogin(credentials);
    } else {
      Logger.info(TAG, '已有重登在进行中，等它完成');
    }
    await this.reloginInFlight;
  }

  private async performRelogin(credentials: Credentials): Promise<void> {
    try {
      await this.login(credentials);
    } finally {
      // 无论成败都要清掉，否则失败之后的重登会被永久挡在门外
      this.reloginInFlight = null;
    }
  }

  /** 读取用户信息（姓名与院系）；取不到不视为失败 */
  async fetchUserInfo(): Promise<UserInfo> {
    const result: HttpResult = await this.getWithAuth(LEARN_STUDENT_HOME);
    const name: string = extractUserName(result.body);
    if (name.length === 0) {
      Logger.warn(TAG, '未能解析用户姓名');
    }
    return new UserInfo(name, '');
  }

  /** 当前是否已持有可用会话（凭据已在内存且 CSRF 已取得） */
  hasSession(): boolean {
    return this.credentials !== null && this.csrfToken.length > 0;
  }
}
