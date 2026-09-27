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

/**
 * 常见的**命名实体**表。
 *
 * 为什么要这张表（2026-09-28 真机实测）：课程材料里中文标点几乎总以命名实体出现
 * （`&ldquo;`/`&rdquo;`/`&hellip;`），原先只认 `amp/lt/gt/quot/apos/nbsp`，
 * 于是作业摘要里直接露出 `&ldquo;` 这种字样（用户可见的乱码）。
 * **不引入 HTML 解析库**（架构不变量 §2），故按实际见到的补表；
 * 表外的命名实体**原样保留**（不猜、不吞字），数字实体走下面两支。
 */
const NAMED_ENTITIES: Map<string, string> = new Map([
  ['quot', '"'], ['amp', '&'], ['apos', '\''], ['lt', '<'], ['gt', '>'],
  ['nbsp', '\u00A0'], ['ensp', '\u2002'], ['emsp', '\u2003'], ['thinsp', '\u2009'],
  ['ldquo', '\u201C'], ['rdquo', '\u201D'], ['lsquo', '\u2018'], ['rsquo', '\u2019'],
  ['laquo', '\u00AB'], ['raquo', '\u00BB'], ['sbquo', '\u201A'], ['bdquo', '\u201E'],
  ['mdash', '\u2014'], ['ndash', '\u2013'], ['minus', '\u2212'], ['shy', '\u00AD'],
  ['hellip', '\u2026'], ['bull', '\u2022'], ['middot', '\u00B7'], ['sect', '\u00A7'],
  ['para', '\u00B6'], ['dagger', '\u2020'], ['Dagger', '\u2021'],
  ['prime', '\u2032'], ['Prime', '\u2033'], ['times', '\u00D7'], ['divide', '\u00F7'],
  ['plusmn', '\u00B1'], ['deg', '\u00B0'], ['permil', '\u2030'], ['frac12', '\u00BD'],
  ['copy', '\u00A9'], ['reg', '\u00AE'], ['trade', '\u2122'],
  ['euro', '\u20AC'], ['pound', '\u00A3'], ['yen', '\u00A5'], ['cent', '\u00A2'],
  ['larr', '\u2190'], ['uarr', '\u2191'], ['rarr', '\u2192'], ['darr', '\u2193'],
  ['harr', '\u2194'], ['crarr', '\u21B5'], ['lArr', '\u21D0'], ['rArr', '\u21D2'], ['hArr', '\u21D4'],
  ['ne', '\u2260'], ['le', '\u2264'], ['ge', '\u2265'], ['asymp', '\u2248'],
  ['equiv', '\u2261'], ['infin', '\u221E'], ['sum', '\u2211'], ['prod', '\u220F'],
  ['radic', '\u221A'], ['int', '\u222B'], ['part', '\u2202'], ['nabla', '\u2207'],
  ['isin', '\u2208'], ['notin', '\u2209'], ['cap', '\u2229'], ['cup', '\u222A'],
  ['alpha', '\u03B1'], ['beta', '\u03B2'], ['gamma', '\u03B3'], ['delta', '\u03B4'],
  ['epsilon', '\u03B5'], ['zeta', '\u03B6'], ['eta', '\u03B7'], ['theta', '\u03B8'],
  ['lambda', '\u03BB'], ['mu', '\u03BC'], ['nu', '\u03BD'], ['xi', '\u03BE'],
  ['pi', '\u03C0'], ['rho', '\u03C1'], ['sigma', '\u03C3'], ['tau', '\u03C4'],
  ['phi', '\u03C6'], ['chi', '\u03C7'], ['psi', '\u03C8'], ['omega', '\u03C9'],
  ['Delta', '\u0394'], ['Sigma', '\u03A3'], ['Omega', '\u03A9'], ['Pi', '\u03A0'],
  ['check', '\u2713'], ['cross', '\u2717'], ['star', '\u2606'], ['starf', '\u2605']
]);

/** 解单个实体名（不含 `&` 与 `;`）。认不出返回 null（**原样保留**，不吞字） */
function decodeOne(name: string): string | null {
  const named: string | undefined = NAMED_ENTITIES.get(name);
  if (named !== undefined) {
    return named;
  }
  if (name.startsWith('#x') || name.startsWith('#X')) {
    const code: number = parseInt(name.substring(2), 16);
    // 用 fromCodePoint：增补平面字符（如 emoji）超出一个 UTF-16 单元
    return isNaN(code) ? null : String.fromCodePoint(code);
  }
  if (name.startsWith('#')) {
    const code: number = parseInt(name.substring(1), 10);
    return isNaN(code) ? null : String.fromCodePoint(code);
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
