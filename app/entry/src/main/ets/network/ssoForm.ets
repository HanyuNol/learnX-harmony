/**
 * WebView 主导登录（SSO）的**纯逻辑**：注入脚本的拼装、页面回传消息的解析、字段还原。
 *
 * 与系统能力无关，故可在宿主侧离线单测——这段恰是本流程最容易在真机上才暴露问题的
 * 地方：占位符替换会把密码里的引号或 `$` 写坏；页面回传的表单体可能缺项或畸形。
 *
 * 与页面结构强耦合的常量（选择器、接口路径、页面文案）**不在本文件**，
 * 它们集中在注入脚本资源 `resources/rawfile/sso_inject.js` 一处维护
 * （spec §8.3 T11）——校方改版时只改那一个文件。
 */

import { AuthError } from '../model/auth';
import { apiChanged, networkUnreachable } from '../common/errors';
import { LEARN_ROAMING_PREFIX } from '../model/urls';
import { TextKeys } from '../common/texts';

/** 注入脚本模板中待替换的占位符。改动须同步 `resources/rawfile/sso_inject.js` */
export const PLACEHOLDER_USERNAME: string = '__LEARNX_USERNAME__';
export const PLACEHOLDER_PASSWORD: string = '__LEARNX_PASSWORD__';
export const PLACEHOLDER_FINGER_PRINT: string = '__LEARNX_FINGER_PRINT__';
export const PLACEHOLDER_DEVICE_NAME: string = '__LEARNX_DEVICE_NAME__';

/** 注入脚本经 JS 通道回传的消息类型 */
export const MSG_SUBMIT_FORM: string = 'SUBMIT_FORM';
export const MSG_PREFILL_FAILED: string = 'PREFILL_FAILED';
export const MSG_TRUST_LIMIT: string = 'TRUST_LIMIT';
export const MSG_UNKNOWN: string = 'UNKNOWN';
/** 页面本身加载失败（无网络、证书记不住等），由 `onErrorReceive` 上报 */
export const MSG_PAGE_LOAD_FAILED: string = 'PAGE_LOAD_FAILED';
/** 认证已完成但没抓到表单体：多半是页面结构变了 */
export const MSG_NO_FORM_BODY: string = 'NO_FORM_BODY';
/**
 * 注入脚本上报的页面环境探测结果（排障用，只含可用性与长度，不含任何值）。
 *
 * 为什么需要它：校方页面用 localforage（IndexedDB → WebSQL → localStorage）持久化设备标记，
 * 一旦这些存储不可用，页面就会判定"浏览器处于隐私或匿名模式"并**拒绝登记信任浏览器**。
 * 这是纯环境事实，只能从页面内部探测，故由脚本回报、应用只记日志。
 */
export const MSG_ENV_PROBE: string = 'ENV_PROBE';

/** 页面表单字段名（与校方页面一致，改动须同步注入脚本与 API.md §2.1） */
export const FIELD_FINGER_PRINT: string = 'fingerPrint';
export const FIELD_FINGER_GEN_PRINT: string = 'fingerGenPrint';
export const FIELD_FINGER_GEN_PRINT3: string = 'fingerGenPrint3';

/** 「信任浏览器数量已达上限」的可操作引导：存**文案键**，由页面取文案（spec §3.4） */
export const TRUST_LIMIT_HINT_KEY: string = TextKeys.ERR_TRUST_LIMIT;

/** 一条来自 WebView 的消息 */
export class SsoBridgeMessage {
  readonly type: string;
  /** 仅 `SUBMIT_FORM` 携带：页面表单的 urlencoded 提交体 */
  readonly body: string;

  constructor(type: string, body: string) {
    this.type = type;
    this.body = body;
  }
}

/**
 * 把模板里的占位符替换为实际取值。
 *
 * 替换值一律经 `JSON.stringify` 生成 JS 字符串字面量，并**用函数式替换**：
 * 字符串形式的替换会把值里的 `$&` / `$1` 当成替换模式展开，密码含 `$` 时会被改写。
 * 密码含引号或反斜杠时，直接拼接会把注入脚本写成语法错误——表现是"预填没生效"，
 * 排查起来与"页面改版"难以区分。
 */
export function buildInjectedScript(
  template: string,
  username: string,
  password: string,
  fingerPrint: string,
  deviceName: string
): string {
  return template
    .replace(PLACEHOLDER_USERNAME, () => JSON.stringify(username))
    .replace(PLACEHOLDER_PASSWORD, () => JSON.stringify(password))
    .replace(PLACEHOLDER_FINGER_PRINT, () => JSON.stringify(fingerPrint))
    .replace(PLACEHOLDER_DEVICE_NAME, () => JSON.stringify(deviceName));
}

/**
 * 解析 urlencoded 表单体。同名后出现的覆盖先出现的（对齐 `FormData` 转对象的语义）。
 */
export function parseFormBody(body: string): Map<string, string> {
  const fields: Map<string, string> = new Map();
  if (body.length === 0) {
    return fields;
  }

  const segments: string[] = body.split('&');
  for (const segment of segments) {
    if (segment.length === 0) {
      continue;
    }
    const equalsIndex: number = segment.indexOf('=');
    const rawName: string = equalsIndex >= 0 ? segment.substring(0, equalsIndex) : segment;
    const rawValue: string = equalsIndex >= 0 ? segment.substring(equalsIndex + 1) : '';
    const name: string = decodeFormComponent(rawName);
    if (name.length === 0) {
      continue;
    }
    fields.set(name, decodeFormComponent(rawValue));
  }
  return fields;
}

/**
 * 表单编码里 `+` 表示空格，`decodeURIComponent` 不认，须先还原。
 * 非法百分号序列（页面回传被截断时可能出现）原样返回——不为一个坏字段丢掉整份表单。
 */
function decodeFormComponent(raw: string): string {
  const plusRestored: string = raw.split('+').join(' ');
  try {
    return decodeURIComponent(plusRestored);
  } catch (err) {
    return plusRestored;
  }
}

/**
 * 解析 WebView 回传的消息。
 *
 * 只按固定键名取值（`type` / `data.body`），不用动态属性访问——ArkTS 禁止后者。
 * 因此注入脚本把表单体编码成 urlencoded 字符串回传，而不是直接塞一个对象。
 */
export function parseBridgeMessage(raw: string): SsoBridgeMessage | null {
  try {
    const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const typeValue: Object | undefined = parsed['type'];
    if (typeof typeValue !== 'string') {
      return null;
    }

    const dataValue: Object | undefined = parsed['data'];
    const data: Record<string, Object> | null =
      typeof dataValue === 'object' && dataValue !== null ? dataValue as Record<string, Object> : null;

    if (typeValue === MSG_SUBMIT_FORM || typeValue === MSG_ENV_PROBE) {
      if (data === null) {
        return null;
      }
      const bodyValue: Object | undefined = data['body'];
      return typeof bodyValue === 'string'
        ? new SsoBridgeMessage(typeValue, bodyValue)
        : null;
    }

    if (typeValue === MSG_PREFILL_FAILED || typeValue === MSG_TRUST_LIMIT) {
      return new SsoBridgeMessage(typeValue, '');
    }
    return new SsoBridgeMessage(MSG_UNKNOWN, '');
  } catch (err) {
    // 页面回传不是合法 JSON：丢弃该条，不影响页面继续
    return null;
  }
}

/**
 * 判据：导航目标以网络学堂漫游地址开头即视为认证完成。
 *
 * 用前缀而非完整相等——漫游地址后面还带 `?ticket=...`。对齐上游 SSO 页的判定。
 */
export function isRoamingUrl(url: string): boolean {
  return url.startsWith(LEARN_ROAMING_PREFIX);
}

/** 取查询参数中某个名字的值；没有则空串 */
function queryParamOf(url: string, wanted: string): string {
  const questionMark: number = url.indexOf('?');
  if (questionMark < 0) {
    return '';
  }
  const segments: string[] = url.substring(questionMark + 1).split('&');
  for (const segment of segments) {
    const equalsIndex: number = segment.indexOf('=');
    if (equalsIndex <= 0) {
      continue;
    }
    if (segment.substring(0, equalsIndex) === wanted) {
      return segment.substring(equalsIndex + 1);
    }
  }
  return '';
}

/**
 * 从漫游地址里取出票据。
 *
 * 它是**一次性凭据**：只用于发起那一次漫游请求，**绝不进日志**（日志只记长度）。
 * 拿它去漫游比"重新登录一遍"更可靠——不需要密码、不需要设备已被登记为信任浏览器，
 * 就是浏览器原本要做的那一步。
 */
export function ticketOfRoamUrl(url: string): string {
  return queryParamOf(url, 'ticket');
}

/**
 * 排障用：漫游地址的查询**参数名**与票据长度（不记任何值）。
 *
 * 需要它是因为"截到的漫游地址里到底有没有票据"决定了收尾走哪条路，
 * 而这一条只能从真机上看到。
 */
export function describeRoamUrl(url: string): string {
  const questionMark: number = url.indexOf('?');
  if (questionMark < 0) {
    return '无查询参数';
  }
  const names: string[] = [];
  const segments: string[] = url.substring(questionMark + 1).split('&');
  for (const segment of segments) {
    const equalsIndex: number = segment.indexOf('=');
    const name: string = equalsIndex >= 0 ? segment.substring(0, equalsIndex) : segment;
    if (name.length > 0) {
      names.push(name);
    }
  }
  return `参数=[${names.join(',')}] ticket长度=${ticketOfRoamUrl(url).length}`;
}

/** WebView 抓到的表单体 */
export class SsoFormBody {
  readonly fields: Map<string, string>;

  constructor(fields: Map<string, string>) {
    this.fields = fields;
  }

  get(name: string): string {
    const value: string | undefined = this.fields.get(name);
    return value === undefined ? '' : value;
  }

  has(name: string): boolean {
    return this.fields.has(name);
  }

  /**
   * 是否足以用于取出设备信任标识：必须有页面指纹。
   *
   * 页面可能先回传一份隐藏字段尚未生成的快照（jQuery 提交被覆盖的副作用），
   * 用这条挡住，避免残缺快照覆盖完整快照。
   */
  isUsable(): boolean {
    return this.get(FIELD_FINGER_PRINT).length > 0;
  }
}

/** 便捷构造：从 urlencoded 提交体得到表单对象 */
export function formBodyOf(rawBody: string): SsoFormBody {
  return new SsoFormBody(parseFormBody(rawBody));
}

/**
 * 设备信任标识的三元组。
 *
 * 这三个值由校方页面生成（`fingerPrint` 是应用注入的设备指纹，`fingerGenPrint` /
 * `fingerGenPrint3` 由页面从服务端与本地存储取得），**应用无法自行构造**——
 * 这正是"把登录交给 WebView"的理由之一。
 *
 * 用途不是"重放页面那份密文"，而是**在全新会话里重新登录时带上它们**，
 * 使服务端认出这是同一台已登记的浏览器（上游即如此，见 ADR-0008 §决策 5）。
 */
export class SsoFingerPrints {
  readonly fingerPrint: string;
  readonly fingerGenPrint: string;
  readonly fingerGenPrint3: string;

  constructor(fingerPrint: string, fingerGenPrint: string, fingerGenPrint3: string) {
    this.fingerPrint = fingerPrint;
    this.fingerGenPrint = fingerGenPrint;
    this.fingerGenPrint3 = fingerGenPrint3;
  }

  /** 备选（纯 API）路径用：三项均为空串 */
  static empty(): SsoFingerPrints {
    return new SsoFingerPrints('', '', '');
  }
}

/** 从抓到的页面表单体取出三项设备信任标识 */
export function fingerPrintsOf(body: SsoFormBody): SsoFingerPrints {
  return new SsoFingerPrints(
    body.get(FIELD_FINGER_PRINT),
    body.get(FIELD_FINGER_GEN_PRINT),
    body.get(FIELD_FINGER_GEN_PRINT3)
  );
}

/**
 * 给校验响应做一句话归类，供排障日志使用。
 *
 * 缺失工单时，"服务端到底返回了什么"决定了该归哪一类错误——是会话丢了（回到登录页）、
 * 还是要二次认证、还是页面结构变了。仅凭"没工单"分不出来，实测为此绕过弯路。
 */
export function classifyCheckResponse(body: string): string {
  if (body.includes(SECOND_AUTH_MARKER)) {
    return '二次认证页';
  }
  if (body.includes('sm2publicKey') || body.includes('i_user')) {
    return '登录页（会话未生效）';
  }
  return '未识别的页面';
}

/** 二次认证页面的标记（与 `learnClient` 保持一致，避免两处各写一遍中文串） */
const SECOND_AUTH_MARKER: string = '二次认证';

/**
 * 把 WebView 上报的异常信号归类为领域错误。
 *
 * 归类放在这里（而非页面）的原因：`pages` 只做 UI，不含业务判断（架构不变量 §1）。
 * 两个信号都归"接口语义变更"而非"认证失败"——它们都不是用户输错密码，
 * 误导用户去反复检查密码是实测踩过的坑。
 */
export function classifySsoProblem(code: string): AuthError {
  if (code === MSG_TRUST_LIMIT) {
    // 这条有具体可操作步骤，放进 userHint——通用文案会把它盖掉，用户就无从知道该删旧设备
    return apiChanged('WebView 登录页提示信任浏览器数量已达上限', TRUST_LIMIT_HINT_KEY);
  }
  if (code === MSG_PREFILL_FAILED) {
    return apiChanged('统一身份认证页面结构似乎已变化，未能预填登录表单');
  }
  if (code === MSG_NO_FORM_BODY) {
    return apiChanged('认证已完成但未取到登录表单数据，认证页结构可能已变更');
  }
  if (code === MSG_PAGE_LOAD_FAILED) {
    // 页面加载失败最可能的原因是网络：报成网络不可达，让用户先去查网络而不是查密码
    return networkUnreachable('统一身份认证页面加载失败');
  }
  return apiChanged(`WebView 登录异常（${code}）`);
}
