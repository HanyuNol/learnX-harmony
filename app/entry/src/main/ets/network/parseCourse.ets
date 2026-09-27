/**
 * 课程接口的**响应解析**（纯逻辑，零系统依赖，可宿主侧穷举测试）。
 *
 * 上游判定：`message === 'success'` 且 `resultList` 是数组，否则判无效响应
 * （`thu-learn-lib/src/index.ts:359-365`）。本项目沿用同一判据，不合则抛错，
 * 由调用方归入"解析失败"——服务端改结构不能表现成应用缺陷（NFR-NET）。
 *
 * 字段映射同样照上游（`src/index.ts:373-385`）：
 * `wlkcid→id`、`zywkcm→name`、`kcm→chineseName`、`ywkcm→englishName`、
 * `jsm→teacherName`、`jsh→teacherNumber`、`kch→courseNumber`、`kxh→courseIndex`。
 */

import { Course } from '../model/course';
import { parseFailed } from '../common/errors';

/**
 * 解 HTML 实体。
 *
 * 为什么需要：课程名等字段服务端会做 HTML 转义（上游对 `zywkcm`/`kcm`/`ywkcm`
 * 都过了一遍 HTML 解码）。只处理常见实体与数字实体，**认不出的一律原样保留**——
 * 宁可显示 `&foo;` 也不能吞掉字符（课程名少一截比多一个实体串更难排查）。
 */
export function decodeHtmlEntities(text: string): string {
  let result: string = '';
  let index: number = 0;
  while (index < text.length) {
    const amp: number = text.indexOf('&', index);
    if (amp < 0) {
      result += text.substring(index);
      break;
    }
    result += text.substring(index, amp);

    const semicolon: number = text.indexOf(';', amp + 1);
    // 实体名不会太长；超出范围就说明这个 & 不是实体开头
    const decoded: string | null = semicolon > amp && semicolon - amp <= 10
      ? decodeOne(text.substring(amp + 1, semicolon))
      : null;
    if (decoded === null) {
      result += '&';
      index = amp + 1;
    } else {
      result += decoded;
      index = semicolon + 1;
    }
  }
  return result;
}

/** 解单个实体名（不含 `&` 与 `;`）。认不出返回 null */
function decodeOne(name: string): string | null {
  if (name === 'amp') {
    return '&';
  }
  if (name === 'lt') {
    return '<';
  }
  if (name === 'gt') {
    return '>';
  }
  if (name === 'quot') {
    return '"';
  }
  if (name === 'apos' || name === '#39') {
    return '\'';
  }
  if (name === 'nbsp') {
    return '\u00A0';
  }
  if (name.startsWith('#x') || name.startsWith('#X')) {
    const code: number = parseInt(name.substring(2), 16);
    return isNaN(code) ? null : String.fromCharCode(code);
  }
  if (name.startsWith('#')) {
    const code: number = parseInt(name.substring(1), 10);
    return isNaN(code) ? null : String.fromCharCode(code);
  }
  return null;
}

/** 取字符串字段；非字符串或缺失一律退让为空串（单项缺字段不该让整批失败） */
function str(field: Object | undefined): string {
  return typeof field === 'string' ? field : '';
}

/** 取数字字段；非数字退让为 0（`kxh` 在学生形态是数字、教师形态是字符串，故用 Number） */
function num(field: Object | undefined): number {
  if (typeof field === 'number') {
    return field;
  }
  if (typeof field === 'string') {
    const parsed: number = Number(field);
    return isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

/**
 * 解析课程列表响应。
 *
 * **单项字段缺失不抛错**：只把该字段退让为空，课程本身仍出现（缺字段的课程照样要能进），
 * 显示名由 `Course.displayName()` 的回退链兜底。抛错只保留给"整体结构不对"。
 */
export function parseCourseList(body: string): Course[] {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (err) {
    throw parseFailed('课程列表响应不是合法 JSON');
  }

  const envelope: Record<string, Object> = parsed as Record<string, Object>;
  const message: Object | undefined = envelope['message'];
  if (typeof message !== 'string' || message !== 'success') {
    throw parseFailed('课程列表响应缺少 success 标记');
  }

  const listValue: Object | undefined = envelope['resultList'];
  if (!Array.isArray(listValue)) {
    throw parseFailed('课程列表响应的 resultList 不是数组');
  }

  const courses: Course[] = [];
  const items: Array<Object> = listValue as Array<Object>;
  for (const item of items) {
    if (typeof item !== 'object' || item === null) {
      continue;
    }
    const raw: Record<string, Object> = item as Record<string, Object>;
    courses.push(new Course(
      str(raw['wlkcid']),
      decodeHtmlEntities(str(raw['zywkcm'])),
      decodeHtmlEntities(str(raw['kcm'])),
      decodeHtmlEntities(str(raw['ywkcm'])),
      str(raw['jsm']),
      str(raw['kch']),
      str(raw['jsh']),
      num(raw['kxh'])
    ));
  }
  return courses;
}
