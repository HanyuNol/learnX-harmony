/**
 * 文件列表与分类的**响应解析**（纯逻辑，零系统依赖，可宿主侧穷举测试）。
 *
 * 上游判定与映射（`thu-learn-lib/src/index.ts:503-556`，逐行核过）：
 * - 成功判定 **`result === 'success'`**；
 * - **容器的形态与本项目其他三个维度都不同**：学生形态下 `json.object` **本身就是数组**
 *   （通知/作业是 `object.aaData`）；教师形态才是 `object.resultsList`。这里三者都认，
 *   认不出时抛出——**静默成空列表会让"服务端改了结构"表现成"没有文件"**。
 * - 分类：容器 `object.rows`，`kjflid→id`、`bt→分类名`；文件用 `kjflid` 关联分类名。
 */

import { LearnFile } from '../model/file';
import { parseFailed } from '../common/errors';
import { ServerTime, serverTimeOf } from '../common/time';
import { decodeHtmlEntities } from './parseCourse';

function str(field: Object | undefined): string {
  return typeof field === 'string' ? field : '';
}

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

/** 取 `result === 'success'` 的信封，返回其 `object` 字段（缺失/非成功则抛） */
function objectOf(body: string, what: string): Object {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (err) {
    throw parseFailed(`${what}响应不是合法 JSON`);
  }
  const envelope: Record<string, Object> = parsed as Record<string, Object>;
  const resultFlag: Object | undefined = envelope['result'];
  if (typeof resultFlag !== 'string' || resultFlag !== 'success') {
    throw parseFailed(`${what}响应缺少 success 标记`);
  }
  const value: Object | undefined = envelope['object'];
  if (typeof value !== 'object' || value === null) {
    throw parseFailed(`${what}响应缺少 object`);
  }
  return value;
}

/**
 * 解析文件列表。
 *
 * `categoryNames` 是"分类 id → 分类名"的映射（来自 `parseFileCategoryList`）；
 * 取不到分类名的文件，分类名为空串（**退让**，不整批失败）。
 */
export function parseFileList(body: string, courseId: string, courseName: string,
                              courseTeacherName: string,
                              categoryNames: Map<string, string>): LearnFile[] {
  const value: Object = objectOf(body, '文件列表');

  let raw: Array<Object> | null = null;
  if (Array.isArray(value)) {
    // 学生形态：object 本身是数组（上游 index.ts:511-517 的第一个分支是教师形态）
    raw = value as Array<Object>;
  } else {
    const container: Record<string, Object> = value as Record<string, Object>;
    const byResultsList: Object | undefined = container['resultsList'];
    if (Array.isArray(byResultsList)) {
      raw = byResultsList as Array<Object>;
    }
  }
  if (raw === null) {
    throw parseFailed('文件列表响应里找不到数组容器');
  }

  const items: LearnFile[] = [];
  for (const entry of raw) {
    if (typeof entry !== 'object' || entry === null) {
      continue;
    }
    const f: Record<string, Object> = entry as Record<string, Object>;
    // 时间字段与作业一样**成对**出现（`scsj` 可能是 epoch 毫秒、`scsjStr` 是可读串）：
    // 用同一套规则读，避免"某一端点是数字就静默丢时间"这类缺陷在文件维度重演
    const uploadTime: ServerTime = serverTimeOf(f['scsjStr'], f['scsj']);
    const categoryId: string = str(f['kjflid']);
    const categoryName: string | undefined = categoryNames.get(categoryId);
    items.push(new LearnFile(
      str(f['kjxxid']),
      str(f['wjid']),
      courseId,
      courseName,
      courseTeacherName,
      decodeHtmlEntities(str(f['bt'])),
      decodeHtmlEntities(str(f['ms'])),
      str(f['fileSize']),
      num(f['wjdx'], 0),
      uploadTime.raw,
      uploadTime.ms,
      str(f['wjlx']),
      categoryName === undefined ? '' : categoryName,
      num(f['sfqd'], 0) === 1,
      f['isNew'] === true
    ));
  }
  return items;
}

/**
 * 解析文件分类列表 → "分类 id → 分类名"。
 *
 * 分类**只用于显示**，故解析失败由调用方决定是否降级为空映射（见 `learnClient`）；
 * 这里仍按"结构不对就抛"的规矩来，不静默返回空。
 */
export function parseFileCategoryList(body: string): Map<string, string> {
  const value: Object = objectOf(body, '文件分类');
  const container: Record<string, Object> = value as Record<string, Object>;
  const rows: Object | undefined = container['rows'];
  if (!Array.isArray(rows)) {
    throw parseFailed('文件分类响应缺少 rows 数组');
  }

  const names: Map<string, string> = new Map();
  const raw: Array<Object> = rows as Array<Object>;
  for (const entry of raw) {
    if (typeof entry !== 'object' || entry === null) {
      continue;
    }
    const c: Record<string, Object> = entry as Record<string, Object>;
    const id: string = str(c['kjflid']);
    if (id.length > 0) {
      names.set(id, decodeHtmlEntities(str(c['bt'])));
    }
  }
  return names;
}
