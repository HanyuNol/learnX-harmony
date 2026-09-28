/**
 * 作业截止提醒：类型与**纯逻辑**（筛选、日程起止与提醒时刻、标题描述，以及与现有日程的差量对齐）。
 *
 * 单独成模块的理由同其他 model：写系统日历要设备与授权，验收必须登录后才跑得动，
 * 而"哪些作业该进日历、日程从几点到几点、提醒提前多少、和日历里现有的比多什么少什么"
 * 这些判断可以在这里穷举测试。
 *
 * 规则对齐上游 `robertying/learnX` 的 `helpers/event.ts`
 * （`saveAssignmentsToReminderOrCalendar` / `saveAssignmentEvent`）——**只取语义，不移植代码**（ADR-0001）。
 * 平台能力是 **Calendar Kit**（`@ohos.calendarManager`），不是后台代理提醒：后者在手机/平板/PC 上
 * 受管控、普通应用默认不可用（见 `docs/specs/reminders.md` §0）。
 */

import { Assignment, formatDateTime } from './assignment';

/**
 * 默认提前量（分钟）：**1440 = 24 小时**，与上游
 * `alarms.assignmentCalendarAlarmOffset ?? 24 * 60` 一致。
 */
export const DEFAULT_OFFSET_MINUTES: number = 1440;

/**
 * 提前量上限（分钟）：14 天。
 *
 * 不是业务约束（提前一个月提醒也不算错），只为挡住"多打几个 0"的手误——
 * 输入框里一个手误就会变成一个语义荒唐的值，而用户看不出哪里不对。
 */
export const OFFSET_MINUTES_MAX: number = 14 * 24 * 60;

/**
 * 日程时长（分钟）：30。对齐上游 `settings.calendarEventLength ?? 30`——
 * 日程**结束于截止时刻**，于是日历上表现为"截止前半小时"那一小块，一眼看得出due 在什么时候。
 * 不做成设置项：上游有，但需求里没有，多一个设置只会多一个要解释的东西。
 */
export const EVENT_LENGTH_MINUTES: number = 30;

const MINUTE_MS: number = 60 * 1000;

/**
 * 本应用写入的日程标识前缀。
 *
 * 写在日程的 `identifier` 上（API 12+ 的"写入方可指定日程唯一标识"，查询默认返回），
 * 对齐时靠它认领"这条日程对应哪份作业"——因此**不需要本地映射表**
 * （上游用 `syncedReminderAssignments`，表一丢或写错就永远对不上）。
 * 前缀让"这个账户下的日程是不是本应用写的"成为可判定的事实。
 */
export const EVENT_KEY_PREFIX: string = 'learnx:';

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
  // 只接受纯十进制整数：`Number('1.5')` 会给出 1.5、`Number('1e3')` 会给出 1000，
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
 * 一条待写入日历的日程。
 *
 * 时间用**13 位时间戳**（官方要求，与 `Date.now()` 同量纲）。
 */
export class CalendarEventPlan {
  /** 日程唯一标识（写到 `identifier`），见 `EVENT_KEY_PREFIX` */
  readonly key: string;
  readonly title: string;
  readonly description: string;
  readonly startTime: number;
  readonly endTime: number;
  /** 距**开始时间**提前多少分钟提醒；`null` = 不设提醒 */
  readonly reminderMinutes: number | null;

  constructor(key: string, title: string, description: string, startTime: number, endTime: number,
              reminderMinutes: number | null) {
    this.key = key;
    this.title = title;
    this.description = description;
    this.startTime = startTime;
    this.endTime = endTime;
    this.reminderMinutes = reminderMinutes;
  }
}

/** 日程标识：`learnx:<课程 id>:<作业 id>`。取复合键是因为 `xszyid` 是否跨课程唯一无从保证 */
export function eventKeyOf(assignment: Assignment): string {
  return `${EVENT_KEY_PREFIX}${assignment.courseId}:${assignment.id}`;
}

/**
 * 日程**标题**：`作业名 - 课程名`（上游拼接方式）。
 *
 * 标题/描述都是**数据**，不含界面文案：日程由系统日历显示，`native` 侧取不到 `Resource`
 * （架构不变量 §1）。故这里不做任何语言相关的措辞。
 */
export function eventTitleOf(assignment: Assignment): string {
  return `${assignment.title} - ${assignment.courseName}`;
}

/**
 * 日程**描述**：截止时刻（`YYYY-MM-DD HH:mm`，语言无关），摘要非空时另起一行。
 *
 * 用摘要而不是全文：日历的日程详情地方有限，长正文读起来也没重点。
 * 摘要来自列表阶段的数据，未取到详情时为空——此时只显示截止时刻。
 */
export function eventDescriptionOf(assignment: Assignment): string {
  const due: string = formatDateTime(assignment.deadlineTime);
  const summary: string = assignment.summary();
  if (summary.length === 0) {
    return due;
  }
  return due.length === 0 ? summary : `${due}\n${summary}`;
}

/**
 * 算出**期望写入日历的日程**（纯逻辑，`now` 由调用方注入便于穷举）。
 *
 * 三道筛子，对齐上游 `saveAssignmentsToReminderOrCalendar` 的语义：
 * 1. 截止时间解析不出（`deadlineTime <= 0`）→ 不登记（不知道就不拿它做提醒，同 FR-07 口径）；
 * 2. 已过期（上游 `dayjs(deadline).isAfter(dayjs())` 的等价式：**严格晚于**当前时刻）→ 不登记；
 * 3. 勾了"已完成不提醒"且该作业已提交 → 不登记。
 *
 * 提醒时刻 = 截止 − 提前量；**已经过去时不设提醒**（`reminderMinutes = null`），
 * 但**日程照写**——系统对"提醒时间已过但日程未结束"的日程会**立即提醒**，
 * 那等于当场弹一条无意义的通知；而"日历里能看到截止"本身有价值。
 */
export function planAssignmentEvents(assignments: Assignment[], offsetMinutes: number,
                                     noRemindIfComplete: boolean, now: number): CalendarEventPlan[] {
  const offsetMs: number = offsetMinutes * MINUTE_MS;
  const lengthMs: number = EVENT_LENGTH_MINUTES * MINUTE_MS;
  const plans: CalendarEventPlan[] = [];

  for (const assignment of assignments) {
    if (assignment.deadlineTime <= 0) {
      continue;
    }
    // **严格晚于**当前时刻（上游 `dayjs(deadline).isAfter(dayjs())`）：正好等于当前时刻的不写——
    // 那一刻这条日程已整体过去（结束时间就是截止时刻），写进日历没有意义。
    // 注：这里与 FR-07 列表的"已截止"口径（`isPast`，等于不算过期）差一个瞬间，是有意的。
    if (assignment.deadlineTime <= now) {
      continue;
    }
    if (noRemindIfComplete && assignment.submitted) {
      continue;
    }
    const endTime: number = assignment.deadlineTime;
    const startTime: number = endTime - lengthMs;
    // 距开始时间提前多少分钟 = 提前量 − 日程时长（提前量为 0 时为负，即"开始之后 30 分钟"，
    // 正好落在截止时刻——官方：负值表示开始之后）
    const remindAt: number = endTime - offsetMs;
    const reminderMinutes: number | null = remindAt > now
      ? offsetMinutes - EVENT_LENGTH_MINUTES
      : null;
    plans.push(new CalendarEventPlan(eventKeyOf(assignment), eventTitleOf(assignment),
      eventDescriptionOf(assignment), startTime, endTime, reminderMinutes));
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
 * 日历里**现有**的一条日程（由 `native/calendarAdapter` 读回后装配）。
 *
 * `key` 取自日程的 `identifier`；**空串表示不是本应用写的**（用户自己加进这个账户的日程、
 * 或本应用更早版本写的）——差量对齐据此判定"不认识的东西不删"。
 */
export class ExistingCalendarEvent {
  readonly eventId: number;
  readonly key: string;
  readonly title: string;
  readonly startTime: number;
  readonly reminderMinutes: number | null;

  constructor(eventId: number, key: string, title: string, startTime: number,
              reminderMinutes: number | null) {
    this.eventId = eventId;
    this.key = key;
    this.title = title;
    this.startTime = startTime;
    this.reminderMinutes = reminderMinutes;
  }
}

/** 差量对齐的结果：该加的日程、该删的日程（按系统给的日程 id） */
export class CalendarAlignPlan {
  readonly toAdd: CalendarEventPlan[];
  readonly toDelete: number[];

  constructor(toAdd: CalendarEventPlan[], toDelete: number[]) {
    this.toAdd = toAdd;
    this.toDelete = toDelete;
  }

  /** 无事可做（幂等判据：同一份数据连跑两次，第二次必须是空计划） */
  isEmpty(): boolean {
    return this.toAdd.length === 0 && this.toDelete.length === 0;
  }
}

function sameReminder(left: number | null, right: number | null): boolean {
  if (left === null || right === null) {
    return left === null && right === null;
  }
  return left === right;
}

/** 期望的日程与现有日程是否**等价**（等价就不动它，免得每次刷新都重写用户的日历） */
function sameEvent(plan: CalendarEventPlan, existing: ExistingCalendarEvent): boolean {
  return plan.title === existing.title && plan.startTime === existing.startTime
    && sameReminder(plan.reminderMinutes, existing.reminderMinutes);
}

/**
 * 期望集合与日历现状的**差量**。
 *
 * 删除的三种情形：① 不在期望集合里的（作业已截止 / 已提交且勾了"已完成不提醒" / 已不在当前学期）；
 * ② 在集合里但**内容变了**（老师改了截止时间、改了作业名）；③ 同一标识在日历里重复出现（自愈成一条）。
 * 其余原样留着。
 *
 * 为什么要"变了就删了重建"而不是更新：更新需要拿日程 id 去改，而 id 只存在于"刚读回来的那份"
 * 里——重建用的是我们自己的期望值，来源单一、不会出现"改了一半"的中间态。
 */
export function alignCalendarEvents(desired: CalendarEventPlan[],
                                    existing: ExistingCalendarEvent[]): CalendarAlignPlan {
  const desiredByKey: Map<string, CalendarEventPlan> = new Map();
  for (const plan of desired) {
    desiredByKey.set(plan.key, plan);
  }

  const existingByKey: Map<string, ExistingCalendarEvent> = new Map();
  const toDelete: number[] = [];
  for (const event of existing) {
    if (event.key.length === 0) {
      continue;
    }
    // 同一标识在日历里出现两次（不该发生）：删掉后来者，自愈成一条
    if (existingByKey.has(event.key)) {
      toDelete.push(event.eventId);
      continue;
    }
    existingByKey.set(event.key, event);
    const wanted: CalendarEventPlan | undefined = desiredByKey.get(event.key);
    if (wanted === undefined) {
      toDelete.push(event.eventId);
    } else if (!sameEvent(wanted, event)) {
      toDelete.push(event.eventId);
    }
  }

  const toAdd: CalendarEventPlan[] = [];
  for (const plan of desired) {
    const current: ExistingCalendarEvent | undefined = existingByKey.get(plan.key);
    if (current === undefined) {
      toAdd.push(plan);
    } else if (!sameEvent(plan, current)) {
      toAdd.push(plan);
    }
  }

  return new CalendarAlignPlan(toAdd, toDelete);
}
