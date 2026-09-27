/**
 * 网络学堂 HTTP 客户端：本项目对外请求的**唯一出口**。
 *
 * 职责：会话 Cookie、CSRF 注入、会话失效自动重登、以及七步登录流程。
 * 业务层不得绕过本类自行发请求（架构不变量 §3）。
 *
 * 与上游 thu-learn-lib 的三处**有意差异**（均因平台能力所限）：
 * 1. 上游登录前清除 id.tsinghua.edu.cn 的 JSESSIONID；框架无单 Cookie 清除接口，
 *    故改为**清空整个自管 Cookie 容器**——效果严格强于只清一个 Cookie。
 * 2. 上游用响应最终 URL 是否含 login_timeout 判定会话失效；框架的 HttpResponse
 *    不暴露重定向后的最终 URL，故改为**状态码 403 或响应体含 login_timeout**判定。
 * 3. 上游用 tough-cookie 自动管理 Cookie；框架的 enableAutoCookie 起始版本为 API 26
 *    （本 SDK 为 24），故由本类自管（见 cookieJar.ets）。
 */

import { http } from '@kit.NetworkKit';
import { Credentials, FailReason, AuthError, UserInfo } from '../model/auth';
import { ID_LOGIN_FORM, ID_LOGIN_CHECK, learnAuthRoam, LEARN_STUDENT_HOME, LEARN_LOGOUT } from '../model/urls';
import { Logger } from '../common/logger';
import { apiChanged, authFailed, fromStatusCode, normalize } from '../common/errors';
import { extractSm2PublicKey, extractTicket, extractCsrfToken, isSessionExpired, extractUserName } from './parse';
import { CookieJar } from './cookieJar';
import { encryptPassword } from './sm2';

const TAG: string = 'learnClient';

/** 单次请求超时上限，对齐 NFR-PERF */
const TIMEOUT_MS: number = 15000;

/** 登录请求的重试次数。只对网络不可达重试；认证失败与语义变更不重试 */
const LOGIN_RETRY_LIMIT: number = 1;

/** 网络学堂域名标识，用于决定是否注入 CSRF */
const TSINGHUA_HOST_MARKER: string = 'tsinghua.edu.cn';

/** 会话失效的响应体标记 */
const SESSION_EXPIRED_BODY_MARKER: string = 'login_timeout';

/**
 * 二次认证页面的标记。
 *
 * 实测：账号开启二次认证时，登录校验的响应是标题为「二次认证」的页面（约 1661 字节），
 * 而非带漫游工单的成功页。这类失败**必须与"密码错误"分开呈现**，
 * 否则会把用户与排障都引向错误方向（见 NFR-NET 的错误四分类要求）。
 */
const SECOND_AUTH_MARKER: string = '二次认证';

/** 一次请求的原始结果 */
export class HttpResult {
  readonly body: string;
  readonly status: number;

  constructor(body: string, status: number) {
    this.body = body;
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

export class LearnClient {
  private static instance: LearnClient | null = null;

  /** 会话级请求实例。全程复用同一个，避免连接层状态反复重建 */
  private request: http.HttpRequest;
  /** 自管 Cookie：框架的 enableAutoCookie 起始版本为 API 26，本 SDK(24) 不可用 */
  private jar: CookieJar = new CookieJar();
  private csrfToken: string = '';
  private credentials: Credentials | null = null;

  private constructor() {
    this.request = http.createHttp();
    this.request.on('headersReceive', this.headerCallback);
  }

  /** 当前请求的 URL。`headersReceive` 回调不带 URL，故在组装请求头时记下 */
  private pendingUrl: string = '';

  /**
   * 响应头事件回调——**取 Set-Cookie 的第三条通道**。
   *
   * 前两条（`HttpResponse.cookies` 字段、`response.header` 的 set-cookie）在 API 24 上
   * 都取不到会话 Cookie，服务端因此丢会话、解不开 SM2 密文。官方文档称 `headersReceive`
   * 自 API 8 起替代旧的 `headerReceive`，是独立于 `response.header` 的事件通道。
   * 此处先打印其实际内容（截断），以便确认字段名与结构。
   */
  private headerCallback: (header: Object) => void = (header: Object) => {
    try {
      const text: string = JSON.stringify(header);
      Logger.info(TAG, `headersReceive len=${text.length} head=${text.substring(0, 300)}`);

      const parsed: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      let raw: Object = parsed['set-cookie'];
      if (raw === undefined) {
        raw = parsed['Set-Cookie'];
      }
      if (typeof raw === 'string') {
        this.jar.store(this.pendingUrl, raw);
      } else if (Array.isArray(raw)) {
        const items: Array<string> = raw as Array<string>;
        for (const item of items) {
          if (typeof item === 'string') {
            this.jar.store(this.pendingUrl, item);
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
   * 重置会话：清空 Cookie、CSRF 与内存凭据。
   *
   * 登录开始前与登出后都必须调用——否则会串用上一次会话的 Cookie。
   */
  private resetSession(): void {
    this.jar.clear();
    this.csrfToken = '';
    this.credentials = null;
  }

  getCsrfToken(): string {
    return this.csrfToken;
  }

  /** 为 *.tsinghua.edu.cn 的请求追加 CSRF 查询参数（对齐上游 addCSRFTokenToUrl） */
  private addCsrf(url: string): string {
    if (!url.includes(TSINGHUA_HOST_MARKER) || this.csrfToken.length === 0) {
      return url;
    }
    const separator: string = url.includes('?') ? '&' : '?';
    return `${url}${separator}_csrf=${this.csrfToken}`;
  }

  /** 组装请求头，并按主机注入已持有的 Cookie */
  private buildHeaders(url: string, accept: string, contentType: string): Record<string, string> {
    // 供 headersReceive 回调取 Cookie 时定位主机
    this.pendingUrl = url;
    const headers: Record<string, string> = {};
    headers['Accept'] = accept;
    if (contentType.length > 0) {
      headers['Content-Type'] = contentType;
    }
    const cookie: string = this.jar.headerFor(url);
    if (cookie.length > 0) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /** 发起一次 GET，返回响应体与状态码 */
  private async get(url: string): Promise<HttpResult> {
    try {
      const response: http.HttpResponse = await this.request.request(url, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(url, 'text/html,application/json', ''),
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      this.captureCookies(url, response);
      return new HttpResult(asText(response.result), response.responseCode as number);
    } catch (err) {
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

    try {
      const response: http.HttpResponse = await this.request.request(url, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(url, 'text/html', 'application/x-www-form-urlencoded'),
        extraData: body,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      this.captureCookies(url, response);
      return new HttpResult(asText(response.result), response.responseCode as number);
    } catch (err) {
      throw normalize(err, `POST ${this.maskUrl(url)}`);
    }
  }

  /**
   * 发起一次 multipart/form-data POST。
   *
   * **实测修正**：登录表单原先用 application/x-www-form-urlencoded（当时的判断是
   * "该校方页面是标准 HTML 表单"）。真实凭据下服务端不返回漫游工单，说明该判断不成立——
   * 上游用 React Native 的 FormData（multipart）才是服务端接受的格式，此处对齐上游。
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

    try {
      const response: http.HttpResponse = await this.request.request(url, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(url, 'text/html', `multipart/form-data; boundary=${boundary}`),
        extraData: body,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS
      });
      this.captureCookies(url, response);
      return new HttpResult(asText(response.result), response.responseCode as number);
    } catch (err) {
      throw normalize(err, `POST(multipart) ${this.maskUrl(url)}`);
    }
  }

  /**
   * 从响应中收纳 Cookie。**本方法绝不允许中断请求**。
   *
   * 实测教训（两点）：
   * 1. 框架的 `HttpResponse.cookies` 在本 SDK（API 24）上始终为空，会话 Cookie 从未进入容器，
   *    服务端因此丢会话、解不开 SM2 密文——用户表现为"密码正确也登不上"。
   * 2. 改从响应头 `set-cookie` 读取时，用模板串拼接该值触发了**栈溢出**
   *    （该值可能含循环结构）。故此处**只接受字符串**，绝不字符串化任意对象，并整体兜底。
   */
  private captureCookies(url: string, response: http.HttpResponse): void {
    try {
      if (response.cookies !== undefined && response.cookies.length > 0) {
        this.jar.store(url, response.cookies);
        return;
      }

      // 官方文档：`header` "当前返回的是 JSON 格式字符串，需开发者自行解析"——
      // 它不是对象，直接取 header['set-cookie'] 恒为 undefined（这正是此前的失败原因）
      const rawHeader: string = response.header as string;
      if (typeof rawHeader !== 'string' || rawHeader.length === 0) {
        return;
      }
      const parsed: Record<string, Object> = JSON.parse(rawHeader) as Record<string, Object>;
      // 头部名大小写不保证，两种写法都试
      let raw: Object = parsed['set-cookie'];
      if (raw === undefined) {
        raw = parsed['Set-Cookie'];
      }
      if (typeof raw === 'string') {
        this.jar.store(url, raw);
      } else if (Array.isArray(raw)) {
        const items: Array<string> = raw as Array<string>;
        for (const item of items) {
          if (typeof item === 'string') {
            this.jar.store(url, item);
          }
        }
      }
    } catch (err) {
      Logger.warn(TAG, '收纳 Cookie 失败，本次请求继续');
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
   * 七步登录流程（见 spec §3.2）。
   *
   * 成功后本实例即可用于带会话的后续请求。
   */
  async login(credentials: Credentials): Promise<void> {
    this.resetSession();

    let attempt: number = 0;
    while (true) {
      try {
        await this.performLogin(credentials);
        this.credentials = credentials;
        Logger.info(TAG, '登录成功');
        return;
      } catch (err) {
        const error: AuthError = normalize(err, '登录');
        // 只对网络不可达重试：认证失败与接口语义变更重试无意义，且会放大失败
        const retryable: boolean = error.reason === FailReason.NETWORK_UNREACHABLE;
        if (!retryable || attempt >= LOGIN_RETRY_LIMIT) {
          throw error;
        }
        attempt++;
        Logger.warn(TAG, `登录因网络问题失败，第 ${attempt} 次重试`);
      }
    }
  }

  private async performLogin(credentials: Credentials): Promise<void> {
    // 步骤 2：取 SM2 公钥
    const loginPage: HttpResult = await this.get(ID_LOGIN_FORM);
    if (loginPage.status !== 200) {
      throw fromStatusCode(loginPage.status, '获取统一身份认证登录页');
    }
    const publicKeyHex: string = extractSm2PublicKey(loginPage.body);
    // 诊断：服务端依赖会话 Cookie（JSESSIONID）绑定 SM2 密钥对。
    // 实测（Node 复刻上游协议）表明：不带该 Cookie 提交会得到 1300 字节的
    // "数据已丢失，请重新操作" 错误页，而非工单。此日志用于确认 Cookie 是否取到。
    Logger.info(TAG, `登录页取毕 cookieLen=${this.jar.headerFor(ID_LOGIN_FORM).length}`);
    if (publicKeyHex.length === 0) {
      throw apiChanged('登录页未找到 SM2 公钥，页面结构可能已变更');
    }

    // 步骤 3：提交加密后的凭据
    const encryptedPassword: string = await encryptPassword(credentials.password, publicKeyHex);
    const fields: Map<string, string> = new Map();
    fields.set('i_user', credentials.username);
    fields.set('i_pass', `04${encryptedPassword.startsWith('04') ? encryptedPassword.substring(2) : encryptedPassword}`);
    fields.set('singleLogin', 'on');
    fields.set('fingerPrint', credentials.fingerPrint);
    fields.set('fingerGenPrint', '');
    fields.set('fingerGenPrint3', '');
    fields.set('i_captcha', '');

    const checkResult: HttpResult = await this.postMultipart(ID_LOGIN_CHECK, fields);
    Logger.info(TAG, `提交登录时 cookieLen=${this.jar.headerFor(ID_LOGIN_CHECK).length}`);
    if (checkResult.status !== 200) {
      throw fromStatusCode(checkResult.status, '提交登录凭据');
    }

    // 步骤 4：从响应中取漫游工单
    const ticket: string = extractTicket(checkResult.body);
    if (ticket.length === 0) {
      // 只记长度与开头片段，不记全文：用于区分"服务端拒绝凭据"与"响应结构变了"，
      // 这两种原因在用户看来都是"登录不上"，此前无法从日志分辨
      const excerpt: string = checkResult.body.substring(0, 120).replace(/\s+/g, ' ');
      Logger.warn(TAG, `登录校验响应未含工单 len=${checkResult.body.length} head=${excerpt}`);

      // 账号开启二次认证时，服务端返回"二次认证"页而非工单。
      // 这**不是**密码错误——此前一律报"密码错误"，会把用户和排障都带偏。
      if (checkResult.body.includes(SECOND_AUTH_MARKER)) {
        throw apiChanged('该账号需要二次认证（短信/OTP），当前版本尚未支持该流程');
      }
      throw authFailed('未取得漫游工单，通常是学号或密码错误');
    }

    // 步骤 5：带工单漫游到网络学堂，建立会话
    const roamResult: HttpResult = await this.get(learnAuthRoam(ticket));
    if (roamResult.status !== 200) {
      throw fromStatusCode(roamResult.status, '漫游到网络学堂');
    }

    // 步骤 6：从首页提取 CSRF 令牌
    const homeResult: HttpResult = await this.get(LEARN_STUDENT_HOME);
    if (homeResult.status !== 200) {
      throw fromStatusCode(homeResult.status, '获取网络学堂首页');
    }
    const token: string = extractCsrfToken(homeResult.body);
    if (token.length === 0) {
      throw apiChanged('未能从首页提取 CSRF 令牌，接口可能已变更');
    }
    this.csrfToken = token;
  }

  /** 登出并清空本地会话状态 */
  async logout(): Promise<void> {
    try {
      await this.postForm(LEARN_LOGOUT, new Map<string, string>());
    } catch (err) {
      // 登出失败不影响本地状态清理：把用户登出意图贯彻到底
      Logger.warn(TAG, '服务端登出失败，仍清理本地会话');
    }
    this.resetSession();
  }

  /**
   * 带会话的请求；命中会话失效则自动重登一次并重放。
   *
   * 无凭据（用户未保存密码）时直接抛认证失败，由页面引导重新登录。
   */
  async getWithAuth(url: string): Promise<HttpResult> {
    const first: HttpResult = await this.get(this.addCsrf(url));
    if (!this.isExpired(first)) {
      return first;
    }

    const credentials: Credentials | null = this.credentials;
    if (credentials === null) {
      throw authFailed('会话已失效，且本地无凭据可自动重登');
    }

    Logger.info(TAG, '会话失效，尝试自动重登');
    await this.login(credentials);

    const second: HttpResult = await this.get(this.addCsrf(url));
    if (this.isExpired(second)) {
      // 重登后仍失效：不再循环，交给上层引导用户
      throw authFailed('自动重登后会话仍失效');
    }
    return second;
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
