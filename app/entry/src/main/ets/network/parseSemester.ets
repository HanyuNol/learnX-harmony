/**
 * 学期接口的**响应解析**（纯逻辑，零系统依赖，可宿主侧穷举测试）。
 *
 * 与 `network/parse.ets`（HTML 解析）同属"把不可信响应变成领域值"的一层：
 * 结构不符就抛错，由调用方归入"解析失败"——服务端改了结构不能表现成"应用坏了"
 * （NFR-NET、ARCHITECTURE §5.4）。
 *
 * 对齐上游 `thu-learn-lib@4.0.0`：`getSemesterIdList` 要求返回 **JSON 字符串数组**
 * （含 `null` 项需过滤）；`getCurrentSemester` 要求 `message === 'success'` 且取 `result.id`
 * （`result.xnxq` 只用于派生年份，本项目改由 id 派生，见 spec §6 待实测项）。
 */

import { parseFailed } from '../common/errors';

/**
 * 解析学期 id 列表。
 *
 * 上游对 `null` 项有专门注释（服务端偶发返回 null），故过滤掉非字符串项；
 * 空数组是**合法**结果（不是错误），由调用方按"空态"呈现。
 */
export function parseSemesterIdList(body: string): string[] {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (err) {
    throw parseFailed('学期列表响应不是合法 JSON');
  }

  if (!Array.isArray(parsed)) {
    throw parseFailed('学期列表响应不是 JSON 数组');
  }

  const raw: Array<Object> = parsed as Array<Object>;
  const ids: string[] = [];
  for (const item of raw) {
    if (typeof item === 'string' && item.length > 0) {
      ids.push(item);
    }
  }
  return ids;
}

/**
 * 解析"当前学期"。
 *
 * 返回的是 `result.id`（切换与后续请求都用它）。非 `success`、缺 `result`、
 * `result.id` 不是非空字符串，都判为解析失败——**不猜、不退让**：猜错了会把
 * 用户带到错误的学期。
 */
export function parseCurrentSemesterId(body: string): string {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (err) {
    throw parseFailed('当前学期响应不是合法 JSON');
  }

  const envelope: Record<string, Object> = parsed as Record<string, Object>;
  const message: Object | undefined = envelope['message'];
  if (typeof message !== 'string' || message !== 'success') {
    throw parseFailed('当前学期响应缺少 success 标记');
  }

  const resultValue: Object | undefined = envelope['result'];
  if (typeof resultValue !== 'object' || resultValue === null) {
    throw parseFailed('当前学期响应缺少 result');
  }

  const result: Record<string, Object> = resultValue as Record<string, Object>;
  const id: Object | undefined = result['id'];
  if (typeof id !== 'string' || id.length === 0) {
    throw parseFailed('当前学期响应缺少 result.id');
  }
  return id;
}
