/**
 * 作业列表的**响应解析**（纯逻辑，零系统依赖，可宿主侧穷举测试）。
 *
 * 上游判定与映射（`thu-learn-lib/src/index.ts:1041-1084`，逐行核过）：
 * - 成功判定 **`result === 'success'`**（本套 API 里三种信封之一），容器 **`object.aaData`**；
 * - 字段：`xszyid→id`、`zyid→baseId`、`bt→title`（解 HTML 实体）、`jzsj→deadline`（**原样字符串**）、
 *   `bjjzsj→补交截止`、`sfbj==='是'→isLateSubmission`、`scsj→submitTime`、`cj→grade`、
 *   `jsm→graderName`、`pynr→gradeContent`、`pysj→gradeTime`；
 * - **`submitted` / `graded` 由调用方按"这批来自哪个端点"注入**，响应里没有这两个字段。
 */

import { Assignment } from '../model/assignment';
import { parseFailed } from '../common/errors';
import { decodeHtmlEntities } from './parseCourse';

const YES: string = '是';

function str(field: Object | undefined): string {
  return typeof field === 'string' ? field : '';
}

/**
 * 截止时间原串 → 时间戳；解析不出返回 0（**不猜**，由模型层据此说"时间未知"）。
 *
 * 服务端给的是本地时间字符串，上游完全不做解析、原样交给 `dayjs`。这里接受几种常见形态
 * （`YYYY-MM-DD HH:mm[:ss]`、`YYYY/MM/DD HH:mm[:ss]`、ISO），并把 `T` 分隔符归一——
 * 具体形态由真机实测确认（见 spec §6 与本节末尾的日志）。
 */
export function parseDeadlineTimestamp(raw: string): number {
  const trimmed: string = raw.trim();
  if (trimmed.length === 0) {
    return 0;
  }
  const normalized: string = trimmed.replace(/\//g, '-').replace(' ', 'T');
  const parsed: number = Date.parse(normalized);
  return isNaN(parsed) ? 0 : parsed;
}

/**
 * 解析一个端点的作业列表。
 *
 * `submitted`/`graded` 必须由调用方传入（来自端点），**不要**试图从响应里取。
 * 单项字段缺失不抛错；只有整体结构不对才抛。
 */
export function parseAssignmentList(body: string, courseId: string, courseName: string,
                                    courseTeacherName: string, submitted: boolean,
                                    graded: boolean): Assignment[] {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (err) {
    throw parseFailed('作业列表响应不是合法 JSON');
  }

  const envelope: Record<string, Object> = parsed as Record<string, Object>;
  const resultFlag: Object | undefined = envelope['result'];
  if (typeof resultFlag !== 'string' || resultFlag !== 'success') {
    throw parseFailed('作业列表响应缺少 success 标记');
  }

  const objectValue: Object | undefined = envelope['object'];
  if (typeof objectValue !== 'object' || objectValue === null) {
    throw parseFailed('作业列表响应缺少 object');
  }
  const container: Record<string, Object> = objectValue as Record<string, Object>;
  const listValue: Object | undefined = container['aaData'];
  if (!Array.isArray(listValue)) {
    throw parseFailed('作业列表响应缺少 aaData 数组');
  }

  const items: Assignment[] = [];
  const raw: Array<Object> = listValue as Array<Object>;
  for (const entry of raw) {
    if (typeof entry !== 'object' || entry === null) {
      continue;
    }
    const h: Record<string, Object> = entry as Record<string, Object>;
    const deadline: string = str(h['jzsj']);
    items.push(new Assignment(
      str(h['xszyid']),
      str(h['zyid']),
      courseId,
      courseName,
      courseTeacherName,
      decodeHtmlEntities(str(h['bt'])),
      '',
      deadline,
      parseDeadlineTimestamp(deadline),
      str(h['bjjzsj']),
      submitted,
      graded,
      str(h['sfbj']) === YES,
      str(h['scsj']),
      str(h['cj']),
      str(h['cj']),
      str(h['jsm']),
      str(h['pynr']),
      str(h['pysj']),
      [],
      false
    ));
  }
  return items;
}

/** 解析详情接口（JSON）里的正文：`result === 'success'` 时取 `json.msg` */
export function parseAssignmentDescription(body: string): string {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (err) {
    throw parseFailed('作业详情响应不是合法 JSON');
  }
  const envelope: Record<string, Object> = parsed as Record<string, Object>;
  const resultFlag: Object | undefined = envelope['result'];
  if (typeof resultFlag !== 'string' || resultFlag !== 'success') {
    throw parseFailed('作业详情响应缺少 success 标记');
  }
  return decodeHtmlEntities(str(envelope['msg']));
}
