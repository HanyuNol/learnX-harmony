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
import { Attachment } from '../model/attachment';
import { LEARN_PREFIX } from '../model/urls';

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


/** 附件块的类名（上游用 `div.list.fujian.clearfix` 选，且**按出现顺序**对应四类） */
const ATTACHMENT_BLOCK_MARKER: string = 'list fujian clearfix';

function queryParamOf(href: string, name: string): string {
  const question: number = href.indexOf('?');
  if (question < 0) {
    return '';
  }
  const pairs: string[] = href.substring(question + 1).split('&');
  for (const pair of pairs) {
    const equals: number = pair.indexOf('=');
    if (equals < 0) {
      continue;
    }
    if (pair.substring(0, equals) === name) {
      return decodeURIComponent(pair.substring(equals + 1));
    }
  }
  return '';
}

/** 从一段附件块里取第一个链接的（显示名, href） */
function firstLinkOf(block: string): string[] {
  const anchor: number = block.indexOf('<a ');
  if (anchor < 0) {
    return [];
  }
  const hrefStart: number = block.indexOf('href="', anchor);
  const contentStart: number = block.indexOf('>', anchor);
  const contentEnd: number = block.indexOf('</a>', contentStart);
  if (hrefStart < 0 || contentStart < 0 || contentEnd < 0) {
    return [];
  }
  const hrefEnd: number = block.indexOf('"', hrefStart + 6);
  if (hrefEnd < 0) {
    return [];
  }
  const href: string = block.substring(hrefStart + 6, hrefEnd);
  // 链接文本里可能再嵌标签（如 <span>），按上游口径取纯文本
  const rawName: string = block.substring(contentStart + 1, contentEnd);
  const name: string = decodeHtmlEntities(stripInnerTags(rawName)).trim();
  return [name, href];
}

function stripInnerTags(fragment: string): string {
  let text: string = '';
  let inTag: boolean = false;
  for (let i = 0; i < fragment.length; i++) {
    const ch: string = fragment.charAt(i);
    if (ch === '<') {
      inTag = true;
    } else if (ch === '>') {
      inTag = false;
    } else if (!inTag) {
      text += ch;
    }
  }
  return text;
}

/**
 * 解析作业详情页 HTML 里的附件（**按上游 `parseHomeworkAtUrl` 的结构移植**，
 * `thu-learn-lib/src/index.ts:1190-1251`）。
 *
 * 结构：`div.list.fujian.clearfix` 在页面里出现多次，**按顺序**对应
 * 教师附件 / 答案附件 / 已提交附件 / 评分附件；每块里第一个 `<a href=...>` 就是该附件，
 * 显示名是链接文本，`fileId` 从 href 的查询参数取，下载地址是 `LEARN_PREFIX + href`
 * （若 href 带 `downloadUrl` 参数则以它为准——上游那两行注释写着 "so dirty here"）。
 *
 * 本项目禁止引入 HTML 解析库（架构不变量 §2），故这里只做"找块 + 取第一个链接"的
 * 最小白名单解析，不做通用 DOM。**块里没有链接的类别直接跳过**（不是错误）。
 */
export function parseAssignmentAttachments(html: string): Attachment[] {
  const blocks: string[] = [];
  let searchFrom: number = 0;
  while (true) {
    const marker: number = html.indexOf(ATTACHMENT_BLOCK_MARKER, searchFrom);
    if (marker < 0) {
      break;
    }
    const next: number = html.indexOf(ATTACHMENT_BLOCK_MARKER, marker + ATTACHMENT_BLOCK_MARKER.length);
    blocks.push(next < 0 ? html.substring(marker) : html.substring(marker, next));
    searchFrom = marker + ATTACHMENT_BLOCK_MARKER.length;
  }

  const attachments: Attachment[] = [];
  for (const block of blocks) {
    const link: string[] = firstLinkOf(block);
    if (link.length < 2 || link[1].length === 0) {
      continue;
    }
    const href: string = link[1];
    const fileId: string = queryParamOf(href, 'fileId');
    const explicit: string = queryParamOf(href, 'downloadUrl');
    const downloadUrl: string = explicit.length > 0 ? `${LEARN_PREFIX}${explicit}` : `${LEARN_PREFIX}${href}`;
    attachments.push(new Attachment(fileId, link[0], downloadUrl));
  }
  return attachments;
}
