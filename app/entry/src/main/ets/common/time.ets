/**
 * 服务端时间串 → 时间戳（纯函数，无副作用）。
 *
 * 网络学堂的时间字段（作业截止、文件上传时间…）是**本地时间字符串**，没有文档说明格式。
 * 上游完全不做解析、原样交给 `dayjs`（由它按本机时区猜）。这里把常见形态显式列出并
 * 归一化，解析不出返回 0——**不猜**，由调用方按"时间未知"处理。
 *
 * 单独成模块的理由：作业与文件两处都要解析服务端时间，规则只留一份，
 * 顺带让"哪些形态被接受"成为可测的事实。
 */

/**
 * 接受 `YYYY-MM-DD HH:mm[:ss]`、`YYYY/MM/DD HH:mm[:ss]`、ISO（含 `T` 分隔符）。
 *
 * 归一化只做两件事：斜杠换横线、把日期与时间之间的空格换成 `T`——这样
 * `Date.parse` 在各平台上的解释一致（空格形态在部分实现里被视为不可解析）。
 */
export function parseServerTime(raw: string): number {
  const trimmed: string = raw.trim();
  if (trimmed.length === 0) {
    return 0;
  }
  const normalized: string = trimmed.replace(/\//g, '-').replace(' ', 'T');
  const parsed: number = Date.parse(normalized);
  return isNaN(parsed) ? 0 : parsed;
}

/**
 * 成对出现的服务端时间字段的取值结果：**显示串 + 毫秒时间戳**。
 *
 * 为什么要专门建模（2026-09-28 真机实测）：当前服务端把时间字段**成对**给出——
 * `xxx` 是 epoch 毫秒（number）、`xxxStr` 才是可读串（如 `2026-10-09 23:59`）。
 * 上游 `thu-learn-lib@4.0.0` 只取不带 `Str` 的那个，交给 `dayjs` 处理 number 也能工作；
 * 本项目原先按**字符串**读，于是这些时间**一个都读不到**（作业列表因此完全没有截止时间）。
 */
export class ServerTime {
  /** 用于显示的串；只有数字时由调用方补出可读形态 */
  readonly raw: string;
  /** 毫秒时间戳；解析不出为 0 */
  readonly ms: number;

  constructor(raw: string, ms: number) {
    this.raw = raw;
    this.ms = ms;
  }
}

/** 取字符串字段的安全版本（非字符串退让为空串） */
function textOf(field: Object | undefined): string {
  return typeof field === 'string' ? field.trim() : '';
}

/** 取数字字段的安全版本（非数字退让为 `fallback`） */
function numberOf(field: Object | undefined, fallback: number): number {
  if (typeof field === 'number') {
    return field;
  }
  if (typeof field === 'string' && field.trim().length > 0) {
    const parsed: number = Number(field);
    return isNaN(parsed) ? fallback : parsed;
  }
  return fallback;
}

/**
 * 从成对的时间字段里取值。三种形态都认（服务端不同端点/版本并不一致）：
 * 1. 数字字段是 epoch 毫秒（当前主形态）→ 时间戳取它；显示串优先 `*Str`，
 *    没有 `*Str` 时用 `formatTimeText` 补出可读形态；
 * 2. 数字字段其实是时间串（旧形态 / 上游测试数据）→ 当文本解析；
 * 3. 只有 `*Str` → 当文本解析。
 *
 * `fallbackText` 是"只有数字、连格式化都做不了"时的兜底（调用方传空串即可）。
 */
export function serverTimeOf(strField: Object | undefined, numField: Object | undefined): ServerTime {
  const text: string = textOf(strField);
  const numeric: number = numberOf(numField, 0);
  if (numeric > 0) {
    return new ServerTime(text.length > 0 ? text : formatTimeText(numeric), numeric);
  }
  // 数字字段本身也可能是时间串：不能因为"它叫 jzsj 不是 jzsjStr"就把它丢掉
  const inline: string = textOf(numField);
  const chosen: string = text.length > 0 ? text : inline;
  return new ServerTime(chosen, parseServerTime(chosen));
}

/** 毫秒时间戳 → `YYYY-MM-DD HH:mm`（与作业详情页的绝对时间同一口径） */
export function formatTimeText(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const date: Date = new Date(timestamp);
  const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
    + ` ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
