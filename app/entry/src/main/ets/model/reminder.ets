/**
 * 作业提醒：类型与**纯逻辑**（筛选、提醒时刻、通知标题与正文、条数上限，以及与系统现状的差量对齐）。
 *
 * 单独成模块的理由同其他 model：登记提醒要落到系统服务，设备验收必须登录且有通知服务才能跑，
 * 而"哪些作业该提醒、提醒在哪一刻、和系统里已有的比多什么少什么"这些判断可以在这里穷举测试。
 *
 * 字段语义与规则对齐上游 `robertying/learnX` 的 `helpers/event.ts`
 * （`saveAssignmentsToReminderOrCalendar` / `saveAssignmentEvent`）——**只取语义，不移植代码**（ADR-0001）。
 * 上游那套 iOS `expo-calendar` 的 Reminders 通道在鸿蒙没有对应物，这里落到系统通知代理
 * （`@ohos.reminderAgentManager`），见 `docs/specs/reminders.md` §3。
 */

import { Assignment, formatDateTime, isPast } from './assignment';

/**
 * 默认提前量（分钟）：**1440 = 24 小时**，与上游
 * `alarms.assignmentReminderAlarmOffset ?? 24 * 60` 一致。
 */
export const DEFAULT_OFFSET_MINUTES: number = 1440;

/**
 * 提前量上限（分钟）：14 天。
 *
 * 这不是业务约束（提前一个月提醒也不是错），只为挡住"多打几个 0"的手误——
 * 输入框里一个手误就会变成一个永远不触发（或语义荒唐）的值，用户却看不出哪里不对。
 */
export const OFFSET_MINUTES_MAX: number = 14 * 24 * 60;

/**
 * 单次登记的提醒条数上限。
 *
 * 官方《代理提醒(ArkTS)》约束与限制·个数限制写明：**API ≤ 25 的普通应用有效提醒不超过 30 个**
 * （API ≥ 26 为 64）。本项目 SDK 锁 API 24，故取 30。多出来的按**触发时刻从近到远**保留——
 * 到点后提醒会从"有效提醒"里消失，下次对齐自动补上更远的，一次截断不会让后面的作业永久漏掉。
 */
export const MAX_REMINDERS: number = 30;

const MINUTE_MS: number = 60 * 1000;

/**
 * 解析用户输入的提前量（分钟）。
 *
 * 拒绝：空串、非数字、负数、带小数、超过上限。**允许 0**（= 在截止时刻提醒，上游同样允许）。
 * 返回 `null` 表示"这串不能被接受"，由调用方决定退回旧值还是提示——`model` 不持有文案。
 */
export function parseOffsetMinutes(text: string): number | null {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return null;
  }
  // 只接受纯十进制整数：`Number('1.5')` 会给出 1.5，`Number('1e3')` 会给出 1000，
  // 两者都不该被当成"用户想输 1 分钟 / 1000 分钟"接受。
  if (!/^\d+$/.test(trimmed)) {
    return null;
  }
  const value: number = Number(trimmed);
  if (!Number.isFinite(value) || value > OFFSET_MINUTES_MAX) {
    return null;
  }
  return value;
}

/**
 * 提醒时刻的"年月日时分"。
 *
 * 为什么不直接留时间戳：系统那边收的就是这个形状（`LocalDateTime`），
 * 而**"系统里已有的提醒是不是我想要的这一刻"只能比字段**——时间戳比得出来但换不回去，
 * 所以对齐的时候一定需要这份字段化的值。
 *
 * `month` **从 1 起算**（1 = 一月）：官方《后台代理提醒》API 参考的 `LocalDateTime` 表写明
 * `month | 月，取值范围是[1, 12]`（见 `docs/specs/reminders.md` §6 的出处）。
 * 故这里用 `Date.getMonth() + 1`，**不是** `getMonth()`。
 */
export class ReminderMoment {
  readonly year: number;
  /** 1–12 */
  readonly month: number;
  readonly day: number;
  readonly hour: number;
  readonly minute: number;

  constructor(year: number, month: number, day: number, hour: number, minute: number) {
    this.year = year;
    this.month = month;
    this.day = day;
    this.hour = hour;
    this.minute = minute;
  }
}

/** 时间戳 → 提醒时刻（按**设备本地时区**取字段，与系统对 `LocalDateTime` 的解释一致） */
export function momentOf(timestamp: number): ReminderMoment {
  const date: Date = new Date(timestamp);
  return new ReminderMoment(date.getFullYear(), date.getMonth() + 1, date.getDate(),
    date.getHours(), date.getMinutes());
}

/** 两个时刻是否同一刻（对齐时用它判断"要不要重登"） */
export function sameMoment(left: ReminderMoment, right: ReminderMoment): boolean {
  return left.year === right.year && left.month === right.month && left.day === right.day
    && left.hour === right.hour && left.minute === right.minute;
}

/**
 * 一条待登记的提醒。
 *
 * `key` 是**去重键**，同时也是写到系统提醒 `groupId` 上的值（见 spec §3.3 第 2 条）：
 * 对齐时靠它认领"这条提醒对应哪份作业"，因而不需要本地映射表。
 * 取 `课程 id:作业 id` 而非只用作业 id——`xszyid` 是否跨课程唯一无从保证，复合键不会串。
 */
export class ReminderEntry {
  readonly key: string;
  readonly title: string;
  readonly content: string;
  readonly triggerTime: number;

  constructor(key: string, title: string, content: string, triggerTime: number) {
    this.key = key;
    this.title = title;
    this.content = content;
    this.triggerTime = triggerTime;
  }

  /** 该条对应的提醒时刻（与系统现状比对用；不进系统调用参数，故现算） */
  moment(): ReminderMoment {
    return momentOf(this.triggerTime);
  }
}

/** 去重键：`课程 id:作业 id` */
export function reminderKeyOf(assignment: Assignment): string {
  return `${assignment.courseId}:${assignment.id}`;
}

/**
 * 提醒的**标题**：`作业名 - 课程名`（上游拼接方式）。
 *
 * 标题/正文都是**数据**，不含界面文案：提醒由系统在通知里显示，`native` 侧取不到 `Resource`
 * （架构不变量 §1）。故这里也不做任何语言相关的措辞（spec §3.3 第 10 条）。
 */
export function reminderTitleOf(assignment: Assignment): string {
  return `${assignment.title} - ${assignment.courseName}`;
}

/**
 * 提醒的**正文**：截止时刻（`YYYY-MM-DD HH:mm`，语言无关），摘要非空时另起一行。
 *
 * 用摘要而不是全文：通知里只展示两三行，长正文会被系统截断，读者也看不出重点。
 * 摘要来自列表阶段的数据，未取到详情时为空——此时只显示截止时刻。
 */
export function reminderContentOf(assignment: Assignment): string {
  const due: string = formatDateTime(assignment.deadlineTime);
  const summary: string = assignment.summary();
  if (summary.length === 0) {
    return due;
  }
  return due.length === 0 ? summary : `${due}\n${summary}`;
}

/**
 * 算出**期望登记的提醒**（纯逻辑，`now` 由调用方注入便于穷举）。
 *
 * 四道筛子，每条都对齐上游 `saveAssignmentsToReminderOrCalendar` 的语义：
 * 1. 截止时间解析不出（`deadlineTime <= 0`）→ 不登记（不知道就不拿它做提醒，同 FR-07 口径）；
 * 2. 已过期（`dayjs(deadline).isAfter(dayjs())` 的等价式：**严格晚于**当前时刻）→ 不登记；
 * 3. 勾了"已完成不提醒"且该作业已提交 → 不登记；
 * 4. 提醒时刻已经过去（现在离截止已不足一个提前量）→ **不登记**——系统不接受过去时刻的提醒。
 *
 * 结果按触发时刻从近到远排序，并截到 `MAX_REMINDERS` 条。
 */
export function planReminders(assignments: Assignment[], offsetMinutes: number,
                             noRemindIfComplete: boolean, now: number): ReminderEntry[] {
  const offsetMs: number = offsetMinutes * MINUTE_MS;
  const candidates: ReminderEntry[] = [];

  for (const assignment of assignments) {
    if (assignment.deadlineTime <= 0) {
      continue;
    }
    if (isPast(assignment.deadlineTime, now)) {
      continue;
    }
    if (noRemindIfComplete && assignment.submitted) {
      continue;
    }
    const triggerTime: number = assignment.deadlineTime - offsetMs;
    if (triggerTime <= now) {
      continue;
    }
    candidates.push(new ReminderEntry(reminderKeyOf(assignment), reminderTitleOf(assignment),
      reminderContentOf(assignment), triggerTime));
  }

  // 触发时刻升序；同一刻按去重键定序，让结果**稳定**（上限截断才可复现、可测）
  candidates.sort((left: ReminderEntry, right: ReminderEntry): number => {
    if (left.triggerTime !== right.triggerTime) {
      return left.triggerTime - right.triggerTime;
    }
    if (left.key === right.key) {
      return 0;
    }
    return left.key > right.key ? 1 : -1;
  });

  return candidates.length > MAX_REMINDERS ? candidates.slice(0, MAX_REMINDERS) : candidates;
}

/**
 * 系统里**现有**的一条提醒（由 `native/reminderAdapter` 读回后装配）。
 *
 * `key` 取自该提醒的 `groupId`；空串表示**不是本功能登记的**（本项目此前没用过提醒代理，
 * 理论上不会有；但真出现就不要去动它——不认识的东西不撤）。
 */
export class ReminderRecord {
  readonly reminderId: number;
  readonly key: string;
  readonly moment: ReminderMoment;

  constructor(reminderId: number, key: string, moment: ReminderMoment) {
    this.reminderId = reminderId;
    this.key = key;
    this.moment = moment;
  }
}

/** 差量对齐的结果：该登记的、该撤销的（撤销按系统给的 `reminderId`） */
export class ReminderPlan {
  readonly toPublish: ReminderEntry[];
  readonly toCancel: number[];

  constructor(toPublish: ReminderEntry[], toCancel: number[]) {
    this.toPublish = toPublish;
    this.toCancel = toCancel;
  }

  /** 无事可做（幂等判据：同一份数据连跑两次，第二次必须是空计划） */
  isEmpty(): boolean {
    return this.toPublish.length === 0 && this.toCancel.length === 0;
  }
}

/**
 * 期望集合与系统现状的**差量**。
 *
 * 撤销的三种情形：① 不在期望集合里的（作业已截止 / 已提交且勾了"已完成不提醒" / 已不在当前学期）；
 * ② 在集合里但**时刻变了**（截止时间被老师改了）；③ —— 其余原样留着。
 * 登记的两种情形：① 系统里没有这条；② 有但当**时刻不同**（同 ② 的另一半，先撤后登）。
 *
 * 为什么要"时刻不同就重登"而不是每次都重登：提醒是系统里的一条持久登记，
 * 每次刷新都删了重建会让系统侧的提醒列表反复抖动，也更容易撞上条数上限。
 */
export function reconcile(desired: ReminderEntry[], current: ReminderRecord[]): ReminderPlan {
  const desiredByKey: Map<string, ReminderEntry> = new Map();
  for (const entry of desired) {
    desiredByKey.set(entry.key, entry);
  }

  const currentByKey: Map<string, ReminderRecord> = new Map();
  const toCancel: number[] = [];
  for (const record of current) {
    if (record.key.length === 0) {
      continue;
    }
    // 同一个键在系统里出现两次（不该发生）：撤掉后来者，自愈成一条
    if (currentByKey.has(record.key)) {
      toCancel.push(record.reminderId);
      continue;
    }
    currentByKey.set(record.key, record);
    const wanted: ReminderEntry | undefined = desiredByKey.get(record.key);
    if (wanted === undefined) {
      toCancel.push(record.reminderId);
    } else if (!sameMoment(wanted.moment(), record.moment)) {
      toCancel.push(record.reminderId);
    }
  }

  const toPublish: ReminderEntry[] = [];
  for (const entry of desired) {
    const existing: ReminderRecord | undefined = currentByKey.get(entry.key);
    if (existing === undefined) {
      toPublish.push(entry);
    } else if (!sameMoment(entry.moment(), existing.moment)) {
      toPublish.push(entry);
    }
  }

  return new ReminderPlan(toPublish, toCancel);
}
