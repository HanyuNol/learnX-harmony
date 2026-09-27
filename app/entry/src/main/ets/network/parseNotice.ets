/**
 * 通知接口的**响应解析**（纯逻辑；除 Base64 解码外零系统依赖，可宿主侧穷举测试）。
 *
 * 上游判定与映射（`thu-learn-lib/src/index.ts:475-497`）：
 * 结果容器是 `object.aaData`，取不到时退 `object.resultsList`；正文 `ggnr` 是 **Base64**，
 * 标题等文本字段需解 HTML 实体；已读判据 `sfyd === '是'`。
 *
 * 与本项目其他解析层一样：**结构不符就抛错**（由调用方归"解析失败"），
 * 但**单项字段缺失不抛**——缺字段的通知照样要能显示，只是内容空。
 */

import { buffer } from '@kit.ArkTS';
import { Notice } from '../model/notice';
import { parseFailed } from '../common/errors';
import { decodeHtmlEntities } from './parseCourse';

/** `sfyd` 表示"已读"的字面量 */
const READ_MARKER: string = '是';

function str(field: Object | undefined): string {
  return typeof field === 'string' ? field : '';
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
      str(raw['zd']).length > 0,
      parsePublishTime(str(raw['fbsj'])),
      str(raw['fbrxm']),
      str(raw['url']),
      str(raw['fjmc']).length > 0 ? str(raw['fjmc']) : str(raw['fjbt'])
    ));
  }
  return notices;
}
