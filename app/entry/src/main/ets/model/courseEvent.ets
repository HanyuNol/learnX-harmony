/**
 * 课表：类型与**纯逻辑**（北京时间换算、条目 → 日程计划）。
 *
 * 与作业截止（`model/reminder.ets`）的分工：那份管"差量对齐"（两族共用），
 * 这份管"课表特有的是什么"——时间怎么换算、键怎么生成、哪些条目该跳过。
 *
 * 数据来自注册中心的课表接口（三步取数，见 `docs/specs/course-calendar.md` §3.1），
 * 字段语义对齐上游 `thu-learn-lib` 的 `CalendarEvent`
 * （`nr→courseName`、`nq→date`、`kssj→startTime`、`jssj→endTime`、`dd→location`）。**不移植代码**（ADR-0001）。
 */

import { CalendarEventPlan } from './reminder';

/**
 * 课程日程的标识前缀。
 *
 * 与作业的 `learnx:` **必须不同且互不重叠**——差量对齐按前缀划分作用域，
 * 混在一起会让一次课程同步把作业日程全删掉（`'learnx-course:x'` 不以 `'learnx:'` 开头，
 * 两族天然不交）。
 */
export const COURSE_KEY_PREFIX: string = 'learnx-course:';

/**
 * 课表时间所在的时区偏移（小时）：课表给的都是**北京时间**。
 *
 * 为什么要显式钉住：接口返回的是"本地时间"字符串（`20260929` + `0800`），语义是北京时间；
 * 而设备的时区可能不是东八区（留学生、出国交流）。若用 `new Date(y, m, d, h, min)` 构造，
 * 会按**设备时区**解释，于是"8:00 的课"在别的时区会落到另一个绝对时刻。
 * 上游同样把时区钉成 `Asia/Shanghai`。
 */
const BEIJING_UTC_OFFSET_HOURS: number = 8;

const HOUR_MS: number = 60 * 60 * 1000;

/** 课表里的一次课（解析后的领域模型；时间仍是服务端给的**字符串原样**） */
export class CourseSession {
  readonly courseName: string;
  /** 地点（服务端原样字符串，可能为空） */
  readonly location: string;
  /** 日期，形如 `20260929` */
  readonly date: string;
  /** 开始时间，形如 `0800` */
  readonly startTime: string;
  /** 结束时间，形如 `0950` */
  readonly endTime: string;

  constructor(courseName: string, location: string, date: string, startTime: string, endTime: string) {
    this.courseName = courseName;
    this.location = location;
    this.date = date;
    this.startTime = startTime;
    this.endTime = endTime;
  }
}

/** 只留数字：`"8:00"` / `"0800"` / `"08:00:00"` 都能用 */
function digitsOf(text: string): string {
  let out: string = '';
  for (let i: number = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (ch >= '0' && ch <= '9') {
      out += ch;
    }
  }
  return out;
}

/**
 * `日期 + 时刻` → **北京时间对应的绝对时刻**（毫秒）。
 *
 * 解析不出或不是合法日期时返回 `0`（**不猜**，与 FR-07 的"时间未知"同一口径）：
 * 调用方据此跳过该条，而不是把它写成一个错的时间。
 *
 * 合法性靠**回代校验**：先按"北京时间"造一个 UTC 时刻，再把该时刻换算回北京时间的年月日时分，
 * 与输入比对——这样 `20260230`、`20261332` 这类不存在的日期会被识别出来
 * （否则 `Date.UTC` 会静默进位成 3 月 2 日 / 次年 1 月）。
 */
export function beijingTimeOf(date: string, time: string): number {
  const dateDigits: string = digitsOf(date);
  if (dateDigits.length !== 8) {
    return 0;
  }
  const timeDigits: string = digitsOf(time);
  // 3–4 位按 `H(H)mm`（`800` / `0800`），5–6 位按 `H(H)mmss`（`80000` / `080000`，秒忽略）
  if (timeDigits.length < 3 || timeDigits.length > 6) {
    return 0;
  }
  const hasSeconds: boolean = timeDigits.length > 4;
  const hourEnd: number = hasSeconds ? timeDigits.length - 4 : timeDigits.length - 2;
  const hourPart: string = timeDigits.substring(0, hourEnd);
  const minutePart: string = timeDigits.substring(hourEnd, hourEnd + 2);
  const year: number = Number(dateDigits.substring(0, 4));
  const month: number = Number(dateDigits.substring(4, 6));
  const day: number = Number(dateDigits.substring(6, 8));
  const hour: number = Number(hourPart);
  const minute: number = Number(minutePart);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
    return 0;
  }

  const timestamp: number = Date.UTC(year, month - 1, day, hour - BEIJING_UTC_OFFSET_HOURS, minute);
  // 回代：把绝对时刻换回北京时间的字段，必须与输入一致（挡掉"不存在的日期"的静默进位）
  const back: Date = new Date(timestamp + BEIJING_UTC_OFFSET_HOURS * HOUR_MS);
  if (back.getUTCFullYear() !== year || back.getUTCMonth() + 1 !== month || back.getUTCDate() !== day
    || back.getUTCHours() !== hour || back.getUTCMinutes() !== minute) {
    return 0;
  }
  return timestamp;
}

/**
 * 日程标识：`learnx-course:<日期><开始时间>:<课程名>`。
 *
 * 同一门课在同一时刻只留一条；课程名参与键，避免同一时段两门不同的课互相顶替。
 */
export function courseEventKeyOf(session: CourseSession): string {
  return `${COURSE_KEY_PREFIX}${digitsOf(session.date)}${digitsOf(session.startTime)}:${session.courseName}`;
}

/** 日程描述：地点（有则显示）。课表没有"备注"字段，这里就用地点，免得详情里空空如也 */
export function courseEventDescriptionOf(session: CourseSession): string {
  return session.location;
}

/**
 * 课表条目 → 日程计划（纯逻辑，`now` 由调用方注入便于穷举）。
 *
 * 跳过的情形：① 日期或起止时间解析不出（`time` 为 0，见 `beijingTimeOf`）；
 * ② 这次课**已经结束**（结束时刻不晚于当前）——把已经上完的课写进日历没有意义，
 * 而且窗口滚动时它们本来也会被对齐清掉。
 *
 * `remindMinutes` 为 `null` 表示"上课提醒"关着（不设提醒）。
 */
export function planCourseEvents(sessions: CourseSession[], remindMinutes: number | null,
                                 now: number): CalendarEventPlan[] {
  const plans: CalendarEventPlan[] = [];
  for (const session of sessions) {
    const startTime: number = beijingTimeOf(session.date, session.startTime);
    const endTime: number = beijingTimeOf(session.date, session.endTime);
    if (startTime === 0 || endTime === 0 || endTime <= now) {
      continue;
    }
    plans.push(new CalendarEventPlan(courseEventKeyOf(session), session.courseName,
      courseEventDescriptionOf(session), session.location, startTime, endTime, remindMinutes));
  }

  // 开始时间升序；同一刻按标识定序，让结果**稳定**（可复现、可测）
  plans.sort((left: CalendarEventPlan, right: CalendarEventPlan): number => {
    if (left.startTime !== right.startTime) {
      return left.startTime - right.startTime;
    }
    if (left.key === right.key) {
      return 0;
    }
    return left.key > right.key ? 1 : -1;
  });
  return plans;
}

/**
 * 同步窗口（接口要的是 `YYYYMMDD` 字符串）。
 *
 * 窗口按**北京的今天**算：接口的日期语义就是北京日期，设备在别的时区时若按本地日期算，
 * 边界那天会整段错位（与时间换算同一个理由）。
 */
export class ScheduleRange {
  readonly startDate: string;
  readonly endDate: string;

  constructor(startDate: string, endDate: string) {
    this.startDate = startDate;
    this.endDate = endDate;
  }
}

/** 窗口天数：取 4 周。接口单次查询上限 29 天（上游注释），留出余量；条数也控制在一屏能看完的量级 */
export const SCHEDULE_WINDOW_DAYS: number = 28;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** `now` 对应的**北京日期**，形如 `20260928` */
export function beijingDateString(now: number): string {
  const beijing: Date = new Date(now + BEIJING_UTC_OFFSET_HOURS * HOUR_MS);
  return `${beijing.getUTCFullYear()}${pad2(beijing.getUTCMonth() + 1)}${pad2(beijing.getUTCDate())}`;
}

/** 同步窗口：从北京的今天起 `SCHEDULE_WINDOW_DAYS` 天（含今天） */
export function scheduleRangeOf(now: number): ScheduleRange {
  const dayMs: number = 24 * HOUR_MS;
  // 北京当天 00:00 对应的绝对时刻，再加天数——避免"加 27×24 小时"跨夏令时/边界时的偏移
  const beijingMidnight: number = now + BEIJING_UTC_OFFSET_HOURS * HOUR_MS
    - ((now + BEIJING_UTC_OFFSET_HOURS * HOUR_MS) % dayMs);
  return new ScheduleRange(beijingDateString(beijingMidnight),
    beijingDateString(beijingMidnight + (SCHEDULE_WINDOW_DAYS - 1) * dayMs));
}
