/**
 * 作业：类型与**纯逻辑**（排序、筛选、是否已截止、摘要）。
 *
 * 单独成模块的理由同其他 model：作业端点要会话，设备验收必须登录后才能跑，
 * 而"怎么排序、过没过期、筛哪一批"这些判断可以在这里穷举测试。
 *
 * 字段语义对齐上游 `thu-learn-lib@4.0.0` 的 `IHomework`/`IHomeworkDetail`
 * 与其映射（`src/index.ts:1057-1084`）。**只取语义，不移植代码**（ADR-0001）。
 */

import { summarize } from './notice';

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

/** 作业筛选。本批只做"未完成 / 已完成"（通用筛选框架属 FR-12） */
export enum AssignmentFilter {
  UNFINISHED = 'unfinished',
  FINISHED = 'finished'
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
  /** 提交时间（原串，未提交为空串） */
  readonly submitTime: string;
  /** 评分（原串；未评分为空串） */
  readonly grade: string;
  /** 评分等级（上游按分数映射成枚举，未评分为空串） */
  readonly gradeLevel: string;
  readonly graderName: string;
  /** 评语（纯文本，取不到为空串） */
  readonly gradeContent: string;
  readonly gradeTime: string;
  /** 附件名列表（教师附件 + 答案附件 + 已提交附件 + 评分附件，本批只显示名字） */
  readonly attachmentNames: string[];
  /** 详情是否取到了（预取失败时为 false，列表仍显示该条） */
  readonly detailLoaded: boolean;

  constructor(id: string, baseId: string, courseId: string, courseName: string, courseTeacherName: string,
              title: string, description: string, deadline: string, deadlineTime: number, lateDeadline: string,
              submitted: boolean, graded: boolean, isLateSubmission: boolean, submitTime: string,
              grade: string, gradeLevel: string, graderName: string, gradeContent: string, gradeTime: string,
              attachmentNames: string[], detailLoaded: boolean) {
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
    this.submitTime = submitTime;
    this.grade = grade;
    this.gradeLevel = gradeLevel;
    this.graderName = graderName;
    this.gradeContent = gradeContent;
    this.gradeTime = gradeTime;
    this.attachmentNames = attachmentNames;
    this.detailLoaded = detailLoaded;
  }

  /** 取到详情后的副本（保留其余字段不变） */
  withDetail(description: string, attachmentNames: string[]): Assignment {
    return new Assignment(this.id, this.baseId, this.courseId, this.courseName, this.courseTeacherName,
      this.title, description, this.deadline, this.deadlineTime, this.lateDeadline,
      this.submitted, this.graded, this.isLateSubmission, this.submitTime,
      this.grade, this.gradeLevel, this.graderName, this.gradeContent, this.gradeTime,
      attachmentNames, true);
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
