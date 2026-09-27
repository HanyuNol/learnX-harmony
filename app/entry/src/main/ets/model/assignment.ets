/**
 * 作业：类型与**纯逻辑**（排序、筛选、是否已截止、相对截止文案、摘要）。
 *
 * 单独成模块的理由同其他 model：作业端点要会话，设备验收必须登录后才能跑，
 * 而"怎么排序、过没过期、筛哪一批、还剩几天"这些判断可以在这里穷举测试。
 *
 * 字段语义对齐上游 `thu-learn-lib@4.0.0` 的 `IHomework`/`IHomeworkDetail`
 * 与其映射（`src/index.ts:1057-1084,1190-1225`）。**只取语义，不移植代码**（ADR-0001）。
 */

import { summarize } from './notice';
import { Attachment } from './attachment';

/**
 * 作业的完成状态。
 *
 * **注意它不是从响应里读出来的**（见 assignments spec §3.1）：上游用三个端点分别代表
 * 未提交 / 已提交 / 已评分，解析时由调用方"这批来自哪个端点"来注入。
 */
export class AssignmentStatus {
  readonly submitted: boolean;
  readonly graded: boolean;

  constructor(submitted: boolean, graded: boolean) {
    this.submitted = submitted;
    this.graded = graded;
  }
}

/** 三个列表端点各自对应的完成状态（上游 `urls.ts:95-117` 写死的那三组） */
export const STATUS_UNSUBMITTED: AssignmentStatus = new AssignmentStatus(false, false);
export const STATUS_SUBMITTED: AssignmentStatus = new AssignmentStatus(true, false);
export const STATUS_GRADED: AssignmentStatus = new AssignmentStatus(true, true);

/** 完成方式（上游 `HomeworkCompletionType`，来自 `zywcfs`） */
export enum HomeworkCompletionType {
  INDIVIDUAL = 1,
  GROUP = 2
}

/** 提交方式（上游 `HomeworkSubmissionType`，来自 `zytjfs`） */
export enum HomeworkSubmissionType {
  WEB_LEARNING = 2,
  OFFLINE = 0
}

/** 作业筛选。本批只做"未完成 / 已完成"（通用筛选框架属 FR-12） */
export enum AssignmentFilter {
  UNFINISHED = 'unfinished',
  FINISHED = 'finished'
}

/**
 * 作业的四类附件，**按类别各占一个槽位**（对齐上游 `IHomeworkDetail` 的
 * `attachment` / `answerAttachment` / `submittedAttachment` / `gradeAttachment`）。
 *
 * 为什么不是一个平铺数组：详情页要分别显示"教师附件""已提交附件""评分附件"，
 * 平铺数组在某一类缺失时会让后续类别**前移串位**（把参考答案当成我的提交）。
 * 槽位为 `null` 表示该类没有附件。
 */
export class AssignmentAttachments {
  /** 教师布置的附件 */
  readonly teacher: Attachment | null;
  /** 教师给的参考答案附件 */
  readonly answer: Attachment | null;
  /** 学生提交的附件 */
  readonly submitted: Attachment | null;
  /** 教师批改的附件 */
  readonly grade: Attachment | null;

  constructor(teacher: Attachment | null, answer: Attachment | null,
              submitted: Attachment | null, grade: Attachment | null) {
    this.teacher = teacher;
    this.answer = answer;
    this.submitted = submitted;
    this.grade = grade;
  }

  /** 是否至少有一类附件（列表项"有附件"标记用） */
  hasAny(): boolean {
    return this.teacher !== null || this.answer !== null
      || this.submitted !== null || this.grade !== null;
  }

  /** 四类都没有时使用（列表阶段尚未取到详情） */
  static empty(): AssignmentAttachments {
    return new AssignmentAttachments(null, null, null, null);
  }
}

export class Assignment {
  /** 学生侧作业 id（上游 `xszyid`） */
  readonly id: string;
  /** 作业本体 id（上游 `zyid`），取详情要用它 */
  readonly baseId: string;
  readonly courseId: string;
  readonly courseName: string;
  readonly courseTeacherName: string;
  readonly title: string;
  /** 正文（详情里的 `description`，已是纯文本；取不到为空串） */
  readonly description: string;
  /** 截止时间**原串**（服务端不做格式化，上游也是原样留着） */
  readonly deadline: string;
  /** 截止时间的时间戳；`0` 表示解析不出——**不猜** */
  readonly deadlineTime: number;
  /** 补交截止时间原串（无则为空串） */
  readonly lateDeadline: string;
  readonly submitted: boolean;
  readonly graded: boolean;
  /** 是否补交（上游 `sfbj === '是'`） */
  readonly isLateSubmission: boolean;
  /** 完成方式（上游 `zywcfs`） */
  readonly completionType: number;
  /** 提交方式（上游 `zytjfs`） */
  readonly submissionType: number;
  /** 提交时间（原串，未提交为空串） */
  readonly submitTime: string;
  /** 评分（原串；未评分为空串。分数或等级代码，见 `gradeLevel`） */
  readonly grade: string;
  /** 评分等级代码（上游 `GRADE_LEVEL_MAP` 映射；等级/已阅一类走这里，没有为空串） */
  readonly gradeLevel: string;
  readonly graderName: string;
  /** 评语（纯文本，取不到为空串） */
  readonly gradeContent: string;
  readonly gradeTime: string;
  /** 四类附件（见 `AssignmentAttachments`）。本批只显示名字；下载归 FR-08 */
  readonly attachments: AssignmentAttachments;
  /** 详情是否取到了（预取失败时为 false，列表仍显示该条） */
  readonly detailLoaded: boolean;

  constructor(id: string, baseId: string, courseId: string, courseName: string, courseTeacherName: string,
              title: string, description: string, deadline: string, deadlineTime: number, lateDeadline: string,
              submitted: boolean, graded: boolean, isLateSubmission: boolean,
              completionType: number, submissionType: number, submitTime: string,
              grade: string, gradeLevel: string, graderName: string, gradeContent: string, gradeTime: string,
              attachments: AssignmentAttachments, detailLoaded: boolean) {
    this.id = id;
    this.baseId = baseId;
    this.courseId = courseId;
    this.courseName = courseName;
    this.courseTeacherName = courseTeacherName;
    this.title = title;
    this.description = description;
    this.deadline = deadline;
    this.deadlineTime = deadlineTime;
    this.lateDeadline = lateDeadline;
    this.submitted = submitted;
    this.graded = graded;
    this.isLateSubmission = isLateSubmission;
    this.completionType = completionType;
    this.submissionType = submissionType;
    this.submitTime = submitTime;
    this.grade = grade;
    this.gradeLevel = gradeLevel;
    this.graderName = graderName;
    this.gradeContent = gradeContent;
    this.gradeTime = gradeTime;
    this.attachments = attachments;
    this.detailLoaded = detailLoaded;
  }

  /** 取到详情后的副本（保留其余字段不变） */
  withDetail(description: string, attachments: AssignmentAttachments): Assignment {
    return new Assignment(this.id, this.baseId, this.courseId, this.courseName, this.courseTeacherName,
      this.title, description, this.deadline, this.deadlineTime, this.lateDeadline,
      this.submitted, this.graded, this.isLateSubmission, this.completionType, this.submissionType,
      this.submitTime, this.grade, this.gradeLevel, this.graderName, this.gradeContent, this.gradeTime,
      attachments, true);
  }

  /** 列表摘要：正文压成一行（复用通知那套文本工具，同层复用） */
  summary(): string {
    return summarize(this.description);
  }
}

/**
 * 是否已过截止时间。
 *
 * 对齐上游 `dayjs().isAfter(deadline)` 的语义：**严格大于**——正好等于截止时间不算过期。
 * 时间戳为 0（解析不出）时返回 false：**不知道就不说它过期**，免得把能提交的说成不能。
 */
export function isPast(deadlineTime: number, now: number): boolean {
  if (deadlineTime <= 0) {
    return false;
  }
  return now > deadlineTime;
}

/** 相对时间的单位（粒度对齐上游 `dayjs().to(...)` 的常用档位） */
export enum RelativeUnit {
  MINUTE = 'minute',
  HOUR = 'hour',
  DAY = 'day',
  MONTH = 'month',
  YEAR = 'year'
}

/**
 * 相对截止时间：`past` 表示"已过截止"，`value` + `unit` 描述相差多少。
 *
 * 只带**数字与单位**、不带任何文字：文案在 `common/texts.ets` 里映射成资源键，
 * `model` 保持与文案无关（架构不变量 §1）。
 */
export class RelativeDeadline {
  readonly past: boolean;
  readonly value: number;
  readonly unit: RelativeUnit;

  constructor(past: boolean, value: number, unit: RelativeUnit) {
    this.past = past;
    this.value = value;
    this.unit = unit;
  }
}

const MINUTE_MS: number = 60 * 1000;
const HOUR_MS: number = 60 * MINUTE_MS;
const DAY_MS: number = 24 * HOUR_MS;
const MONTH_MS: number = 30 * DAY_MS;
const YEAR_MS: number = 365 * DAY_MS;

/**
 * 把截止时间换算成相对描述（上游列表项显示"还剩 3 天"/"3 天前截止"，不是绝对日期）。
 *
 * 时间戳为 0（解析不出）返回 `null`：**不猜**——调用方据此只显示绝对时间原串或不显示。
 * `now` 由调用方注入，便于穷举测试。
 */
export function relativeDeadlineOf(deadlineTime: number, now: number): RelativeDeadline | null {
  if (deadlineTime <= 0) {
    return null;
  }
  const past: boolean = now > deadlineTime;
  const delta: number = past ? now - deadlineTime : deadlineTime - now;

  let unit: RelativeUnit;
  let span: number;
  if (delta < HOUR_MS) {
    unit = RelativeUnit.MINUTE;
    span = MINUTE_MS;
  } else if (delta < DAY_MS) {
    unit = RelativeUnit.HOUR;
    span = HOUR_MS;
  } else if (delta < MONTH_MS) {
    unit = RelativeUnit.DAY;
    span = DAY_MS;
  } else if (delta < YEAR_MS) {
    unit = RelativeUnit.MONTH;
    span = MONTH_MS;
  } else {
    unit = RelativeUnit.YEAR;
    span = YEAR_MS;
  }
  // 向下取整：说"还剩"时不能多报，说"已过"时也不能夸大
  const value: number = Math.max(1, Math.floor(delta / span));
  return new RelativeDeadline(past, value, unit);
}

/**
 * 时间戳 → `YYYY-MM-DD HH:mm`（纯数字拼接，无文案、无语言差异）。
 *
 * 详情页在相对描述之外还给出确切时间。不输出星期几：那需要语言相关的名字，
 * 本批不做（见 spec §6 待定）。
 */
export function formatDateTime(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const date: Date = new Date(timestamp);
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`
    + ` ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/**
 * 评分等级代码 → 等级名。上游 `GRADE_LEVEL_MAP`（`utils.ts:50-74`）把 `cj` 的负数代码
 * 映射成等级枚举；不在表里的（如正数分数）没有等级名，返回空串。
 */
const GRADE_LEVELS: Map<number, string> = new Map([
  [-100, 'checked'],
  [-99, 'A+'],
  [-98, 'A'],
  [-92, 'A-'],
  [-87, 'B+'],
  [-85, 'distinction'],
  [-82, 'B'],
  [-78, 'B-'],
  [-74, 'C+'],
  [-71, 'C'],
  [-68, 'C-'],
  [-67, 'G'],
  [-66, 'D+'],
  [-64, 'D'],
  [-65, 'exempted course'],
  [-63, 'pass'],
  [-62, 'EX'],
  [-61, 'exemption'],
  [-60, 'pass'],
  [-59, 'failure'],
  [-55, 'W'],
  [-51, 'I'],
  [-50, 'incomplete'],
  [-31, 'NA'],
  [-30, 'F']
]);

export function gradeLevelNameOf(gradeCode: number): string {
  const level: string | undefined = GRADE_LEVELS.get(gradeCode);
  return level === undefined ? '' : level;
}

/** 未完成 / 已完成按 `submitted` 决定（对齐上游 `useFilteredData.ts:49-57`） */
export function filterAssignments(items: Assignment[], filter: AssignmentFilter): Assignment[] {
  if (filter === AssignmentFilter.UNFINISHED) {
    return items.filter((item: Assignment) => !item.submitted);
  }
  return items.filter((item: Assignment) => item.submitted);
}

/**
 * 排序（对齐上游 `actions/assignments.ts:46-65`）：
 * **未截止的在前、按截止时间升序**（最急的先做）；**已截止的在后、按截止时间降序**
 * （刚过期的更可能是还关心的）。
 *
 * 解析不出时间（0）的排在最后：它们是"时间未知"，不该混进正常顺序里。
 * `now` 由调用方注入，便于穷举测试。
 */
export function sortAssignments(items: Assignment[], now: number): Assignment[] {
  const upcoming: Assignment[] = [];
  const overdue: Assignment[] = [];
  const unknown: Assignment[] = [];
  for (const item of items) {
    if (item.deadlineTime <= 0) {
      unknown.push(item);
    } else if (isPast(item.deadlineTime, now)) {
      overdue.push(item);
    } else {
      upcoming.push(item);
    }
  }

  upcoming.sort((left: Assignment, right: Assignment): number =>
    left.deadlineTime - right.deadlineTime);
  overdue.sort((left: Assignment, right: Assignment): number =>
    right.deadlineTime - left.deadlineTime);
  unknown.sort((left: Assignment, right: Assignment): number => {
    if (left.id === right.id) {
      return 0;
    }
    return left.id > right.id ? -1 : 1;
  });

  return upcoming.concat(overdue).concat(unknown);
}
