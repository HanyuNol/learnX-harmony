/**
 * 通知接口的**响应解析**（纯逻辑；除 Base64 解码外零系统依赖，可宿主侧穷举测试）。
 *
 * 上游判定与映射（`thu-learn-lib/src/index.ts:470-497`，逐行核过）：
 * - 成功标记是 **`result === 'success'`**（注意同学期/课程接口用的 `message` 不是同一个字段）；
 * - 结果容器 `object.aaData`，取不到退 `object.resultsList`；
 * - 正文 `ggnr` 是 **Base64**；标题等文本字段解 HTML 实体；
 * - 已读判据 `sfyd === '是'`；**重要标记是 `Number(sfqd) === 1`**（不是 `zd`；
 *   `sfqd` 在学生形态是数字、教师形态是字符串，故用 `Number` 归一）；
 * - `url` 是**客户端按 (courseId, noticeId) 拼**的，响应里没有这个字段；
 * - 发布时间取 `fbsj`，为空时退 `fbsjStr`。
 *
 * 与本项目其他解析层一样：**结构不符就抛错**（由调用方归"解析失败"），
 * 但**单项字段缺失不抛**——缺字段的通知照样要能显示，只是内容空。
 */

import { buffer } from '@kit.ArkTS';
import { Notice } from '../model/notice';
import { parseFailed } from '../common/errors';
import { decodeHtmlEntities } from './parseCourse';
import { learnNoticeDetailUrl } from '../model/urls';

/** `sfyd` 表示"已读"的字面量 */
const READ_MARKER: string = '是';

function str(field: Object | undefined): string {
  return typeof field === 'string' ? field : '';
}

/**
 * 取数字字段；非数字退让为 `fallback`。
 *
 * `sfqd`（重要标记）在学生形态是**数字**、教师形态是字符串，故必须用 `Number` 归一——
 * 按字符串读会得到空串、标记恒为 false（2026-09-28 代码审查 m1）。
 */
function num(field: Object | undefined, fallback: number): number {
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
 * 解 Base64 正文。
 *
 * 解不出来时**退回原串**而不是空串：宁可显示一串噪声，也不要让用户以为"这条通知没有正文"——
 * 前者能被发现并报错，后者会被当成正常。
 */
function decodeBase64(value: string): string {
  if (value.length === 0) {
    return '';
  }
  try {
    return buffer.from(value, 'base64').toString('utf-8');
  } catch (err) {
    return value;
  }
}

/** 发布时间字段：优先 `fbsj`，为空退 `fbsjStr`（上游 `index.ts:487` 就是这么取的） */
function publishTimeOf(raw: Record<string, Object>): string {
  const primary: string = str(raw['fbsj']);
  return primary.length > 0 ? primary : str(raw['fbsjStr']);
}

/**
 * 把发布时间解析为毫秒时间戳。
 *
 * 服务端给的是 `YYYY-MM-DD HH:mm:ss` 形态的本地时间。用 `Date` 解析失败（NaN）时退回 0，
 * 由排序把它排到最后——**不猜时间**。
 */
function parsePublishTime(value: string): number {
  if (value.length === 0) {
    return 0;
  }
  const parsed: number = Date.parse(value.replace(' ', 'T'));
  return isNaN(parsed) ? 0 : parsed;
}

/**
 * 解析一批通知。
 *
 * `courseId` / `courseName` 由调用方传入：上游接口不返回课程信息，是客户端回填的
 * （上游用 `courses.names[courseId]`）。
 */
export function parseNoticeList(body: string, courseId: string, courseName: string): Notice[] {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (err) {
    throw parseFailed('通知列表响应不是合法 JSON');
  }

  const envelope: Record<string, Object> = parsed as Record<string, Object>;
  const resultFlag: Object | undefined = envelope['result'];
  if (typeof resultFlag !== 'string' || resultFlag !== 'success') {
    throw parseFailed('通知列表响应缺少 success 标记');
  }

  const objectValue: Object | undefined = envelope['object'];
  if (typeof objectValue !== 'object' || objectValue === null) {
    throw parseFailed('通知列表响应缺少 object');
  }

  const container: Record<string, Object> = objectValue as Record<string, Object>;
  let listValue: Object | undefined = container['aaData'];
  if (!Array.isArray(listValue)) {
    listValue = container['resultsList'];
  }
  if (!Array.isArray(listValue)) {
    throw parseFailed('通知列表响应缺少结果数组');
  }

  const notices: Notice[] = [];
  const items: Array<Object> = listValue as Array<Object>;
  for (const item of items) {
    if (typeof item !== 'object' || item === null) {
      continue;
    }
    const raw: Record<string, Object> = item as Record<string, Object>;
    notices.push(new Notice(
      str(raw['ggid']),
      courseId,
      courseName,
      decodeHtmlEntities(str(raw['bt'])),
      decodeHtmlEntities(decodeBase64(str(raw['ggnr']))),
      str(raw['sfyd']) === READ_MARKER,
      // **必须用 num**：`sfqd` 在学生形态是**数字**，`str()` 会把它变成空串 → 恒 false
      // （2026-09-28 代码审查 m1；同文件 parseFile 用的就是 num）
      num(raw['sfqd'], 0) === 1,
      parsePublishTime(publishTimeOf(raw)),
      str(raw['fbrxm']),
      learnNoticeDetailUrl(courseId, str(raw['ggid'])),
      str(raw['fjmc']).length > 0 ? str(raw['fjmc']) : str(raw['fjbt'])
    ));
  }
  return notices;
}
