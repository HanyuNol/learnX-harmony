/**
 * 学期：类型与**纯解析/决策**逻辑。
 *
 * 为什么单独成模块：学期相关逻辑里，只有"id 怎么解、列表怎么排、当前学期听谁的"
 * 是纯函数；发请求与服务端端点值得留在 `network`/`repository`。分开之后这几条
 * 可以在宿主侧穷举测试（`testing-and-quality` §1.1）——两个学期端点都要会话，
 * 设备验收必须登录后才能跑。
 *
 * 语义对齐上游 `thu-learn-lib@4.0.0` 的 `SemesterInfo` / `parseSemesterType`
 * 与 `learnX` 的 `data/actions/semesters.ts`（**只取语义，不移植代码**，ADR-0001）。
 */

/** 学期类型。取值语义对齐上游 `SemesterType` */
export enum SemesterType {
  FALL = 'fall',
  SPRING = 'spring',
  SUMMER = 'summer',
  /** 认不出来（id 形态异常，或学期序号不是 1/2/3） */
  UNKNOWN = 'unknown'
}

/** 学期 id 的段数（形如 `2024-2025-1`） */
const SEMESTER_ID_SEGMENTS: number = 3;
/** 年份段的字符数（`2024`） */
const YEAR_DIGITS: number = 4;

/**
 * 一个学期的**可显示形态**。
 *
 * 拆成"年份串 + 季节类型"两段而不是一句拼好的中文：页面据此渲染两个节点
 * （数字 + 文案键），避免用字符串拼接绕过 NFR-I18N。
 */
export class Semester {
  /** 原始 id，切换与后续请求都用它 */
  readonly id: string;
  /** 形如 `2024-2025`；id 形态异常时**保留原串**，保证仍可显示 */
  readonly yearsText: string;
  readonly type: SemesterType;
  /** id 形态是否被识别（false 只表示"认不出"，不表示数据非法） */
  readonly valid: boolean;

  constructor(id: string, yearsText: string, type: SemesterType, valid: boolean) {
    this.id = id;
    this.yearsText = yearsText;
    this.type = type;
    this.valid = valid;
  }
}

/** 学期序号 → 类型。1=秋、2=春、3=夏；其余（含非数字）认不出 */
function typeOfOrdinal(ordinal: string): SemesterType {
  if (ordinal === '1') {
    return SemesterType.FALL;
  }
  if (ordinal === '2') {
    return SemesterType.SPRING;
  }
  if (ordinal === '3') {
    return SemesterType.SUMMER;
  }
  return SemesterType.UNKNOWN;
}

function isDigits(value: string, length: number): boolean {
  if (value.length !== length) {
    return false;
  }
  for (let i = 0; i < value.length; i++) {
    const code: number = value.charCodeAt(i);
    if (code < 0x30 || code > 0x39) {
      return false;
    }
  }
  return true;
}

/**
 * 解析学期 id。
 *
 * **不抛错、不返回空**：形态异常时退让为"未知类型 + 保留原串"，这样界面仍能把
 * 服务端给的东西显示出来（总比白屏强），是否可信由 `valid` 表达。
 */
export function parseSemester(id: string): Semester {
  const segments: string[] = id.split('-');
  if (segments.length !== SEMESTER_ID_SEGMENTS) {
    return new Semester(id, id, SemesterType.UNKNOWN, false);
  }

  const startYear: string = segments[0];
  const endYear: string = segments[1];
  if (!isDigits(startYear, YEAR_DIGITS) || !isDigits(endYear, YEAR_DIGITS)) {
    return new Semester(id, id, SemesterType.UNKNOWN, false);
  }

  const yearsText: string = `${startYear}-${endYear}`;
  return new Semester(id, yearsText, typeOfOrdinal(segments[2]), true);
}

/**
 * 排序：最新在前。
 *
 * 定长 `YYYY-YYYY-N` 形态下，字符串降序与时间序一致（同学年内 `-2` 排在 `-1` 前，
 * 即春季晚于秋季）。**认不出的 id 置后**且保持原本的相对顺序——它们不该影响
 * 可信数据的排序，也不该被悄悄丢掉。
 */
export function sortSemesterIds(ids: string[]): string[] {
  const valid: string[] = [];
  const unknown: string[] = [];
  for (const id of ids) {
    if (parseSemester(id).valid) {
      valid.push(id);
    } else {
      unknown.push(id);
    }
  }
  valid.sort((left: string, right: string): number => {
    if (left === right) {
      return 0;
    }
    return left > right ? -1 : 1;
  });
  return valid.concat(unknown);
}

/**
 * 决定"当前学期"。
 *
 * 对齐上游（`learnX:data/actions/semesters.ts:45-51`）：**服务端的当前学期只在本地
 * 还没存过时采用**。用户手动切过之后就不再被覆盖——否则"手动切换"会在下次刷新时
 * 被悄悄改回去。代价是新学期开始不会自动跟随，那属于新需求，须先确认。
 */
export function decideCurrentSemester(persisted: string, serverCurrent: string): string {
  return persisted.length > 0 ? persisted : serverCurrent;
}
