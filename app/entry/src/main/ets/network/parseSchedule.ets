/**
 * 课表接口的**响应解析**（纯逻辑，零系统依赖，可宿主侧穷举测试）。
 *
 * 响应是 **JSONP**：`<jsoncallback>(<数组>)`。上游用 `Function()` 求值取出数组
 * （`thu-learn-lib/src/utils.ts:80-87`），而 ArkTS **禁用动态求值**（架构不变量 §4：禁反射），
 * 故这里改为**按字符串切出括号之间的内容**再 `JSON.parse`——同样的结果，不做求值。
 *
 * 结构不符一律抛"解析失败"（服务端改结构不能表现成应用缺陷，NFR-NET）；
 * 但**个别条目缺字段只跳过该条**（课表里出现残缺行时不该整批失败），
 * 同时把"原始条数"带出来，供调用方比较"取到几条、可用几条"——
 * 差值持续变大就是接口变结构的早期信号。
 */

import { CourseSession } from '../model/courseEvent';
import { authFailed, parseFailed } from '../common/errors';

/**
 * 响应是不是一个 HTML 页面（而不是我们期待的 JSONP/JSON）。
 *
 * 用途：**区分"会话失效"与"解析失败"**（NFR-NET 的四分类要求）。
 * 注册中心未认证时返回的是登录页 HTML，把它报成"解析失败"就是把服务端/会话问题
 * 误报成应用缺陷——2026-09-28 实测踩到（第二次同步拿到了 HTML，日志却写"不是 JSONP"）。
 */
export function looksLikeHtml(body: string): boolean {
  const head: string = body.substring(0, 512).toLowerCase();
  return head.includes('<html') || head.includes('<!doctype') || head.includes('<script');
}

/**
 * 解析注册中心**工单**。
 *
 * 服务端返回的是**带引号的字符串字面量**（如 `"abc123"`，上游 `index.ts:292-293` 用
 * `substring(1, len-1)` 去引号）。这里做同样的处理，但**先 trim 再去引号**，
 * 且只去**成对**的首尾引号——防的是"某天服务端不引号了，我们却把首字符吃掉"。
 */
export function parseRegistrarTicket(body: string): string {
  const text: string = body.trim();
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    return text.substring(1, text.length - 1);
  }
  return text;
}

/** 解析结果：可用条目 + 原始条数（后者用于判断"是不是在悄悄丢数据"） */
export class ScheduleParseResult {
  readonly sessions: CourseSession[];
  readonly rawCount: number;

  constructor(sessions: CourseSession[], rawCount: number) {
    this.sessions = sessions;
    this.rawCount = rawCount;
  }
}

/** 取字符串字段；缺失或不是字符串时给空串（**不猜**） */
function stringOf(record: Record<string, Object>, key: string): string {
  const value: Object = record[key];
  if (value === undefined || value === null) {
    return '';
  }
  return typeof value === 'string' ? value : '';
}

/**
 * 解析课表 JSONP。
 *
 * 上游字段映射（`thu-learn-lib/src/index.ts:309-316`）：
 * `nr→courseName`、`nq→date`、`kssj→startTime`、`jssj→endTime`、`dd→location`。
 */
export function parseScheduleJsonp(body: string): ScheduleParseResult {
  const text: string = body.trim();
  const open: number = text.indexOf('(');
  const close: number = text.lastIndexOf(')');
  if (open < 0 || close <= open) {
    // 拿到 HTML 说明多半是"没认证/会话失效"（注册中心把登录页返回来了），
    // 而不是"服务端改了结构"——两者对用户的处置完全不同，不能混为一类
    if (looksLikeHtml(text)) {
      throw authFailed('课表响应是 HTML（注册中心会话未建立或已失效）');
    }
    throw parseFailed('课表响应不是 JSONP（找不到回调括号）');
  }
  const inner: string = text.substring(open + 1, close);

  let parsed: Object;
  try {
    parsed = JSON.parse(inner) as Object;
  } catch (err) {
    throw parseFailed('课表响应括号内不是合法 JSON');
  }
  if (!Array.isArray(parsed)) {
    throw parseFailed('课表响应括号内不是数组');
  }

  const rows: Array<Object> = parsed as Array<Object>;
  const sessions: CourseSession[] = [];
  for (const row of rows) {
    if (row === null || row === undefined) {
      continue;
    }
    const record: Record<string, Object> = row as Record<string, Object>;
    const courseName: string = stringOf(record, 'nr');
    const date: string = stringOf(record, 'nq');
    const startTime: string = stringOf(record, 'kssj');
    const endTime: string = stringOf(record, 'jssj');
    const location: string = stringOf(record, 'dd');
    // 缺课程名/日期/起止时间的条目：跳过该条（不是整批失败）
    if (courseName.length === 0 || date.length === 0
      || startTime.length === 0 || endTime.length === 0) {
      continue;
    }
    sessions.push(new CourseSession(courseName, location, date, startTime, endTime));
  }
  return new ScheduleParseResult(sessions, rows.length);
}
