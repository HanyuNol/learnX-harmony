/**
 * 作业截止提醒的对齐编排：读偏好 → 算期望与差量（纯逻辑）→ 落到**系统日历**（Calendar Kit）。
 *
 * 为什么单独一个模块而不是塞进 `settingsStore`：`settingsStore` 是"用户选了什么"的缝，
 * 而这里是"把选择变成日历里的日程"的一整套编排（含串行化、权限与失败归类），职责不同。
 * 页面（设置页、作业页）只调这里的入口，不碰存储与系统能力（架构不变量 §1）。
 *
 * 失败**不向上抛**：日历写不进去不该让作业列表或设置页的任何操作失败
 * （`ARCHITECTURE.md` §5.5 "尽力而为"）；失败只记日志、并把结果如实返回给需要告知用户的那一处。
 */

import { common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Assignment } from '../model/assignment';
import {
  CalendarAlignPlan, CalendarEventPlan, EVENT_KEY_PREFIX, ExistingCalendarEvent, alignCalendarEvents,
  planAssignmentEvents
} from '../model/reminder';
import {
  addEvent, deleteEvent, ensureCalendar, hasCalendarPermission, listEvents, requestCalendarPermission
} from '../native/calendarAdapter';
import {
  readAssignmentReminder, readAssignmentReminderNoIfComplete, readAssignmentReminderOffset
} from '../storage/preferenceStore';
import { Logger } from '../common/logger';

const TAG: string = 'reminderSync';

/** 一次对齐的结果。`failed` 表示"读/写日历出错"，`permissionMissing` 表示"没拿到日历权限" */
export class ReminderSyncResult {
  /** 本次对齐时开关是否为开（关时为 false，此时就该把已登记的日程清干净） */
  readonly enabled: boolean;
  readonly added: number;
  readonly deleted: number;
  readonly failed: boolean;
  readonly permissionMissing: boolean;

  constructor(enabled: boolean, added: number, deleted: number, failed: boolean,
              permissionMissing: boolean) {
    this.enabled = enabled;
    this.added = added;
    this.deleted = deleted;
    this.failed = failed;
    this.permissionMissing = permissionMissing;
  }
}

/**
 * 串行化的队列。
 *
 * "读现有日程 → 算差量 → 写日历"不是原子的：两次对齐并发时，双方可能都读到"日历里没有这条"
 * 而各写一次，于是同一条作业出现两条日程。这个应用里的触发点都是用户动作（页面进来、
 * 改动设置），并发本就罕见，但代价是用户日历里出现重复日程，故用一条 Promise 链把对齐串起来。
 */
let chain: Promise<void> = Promise.resolve();

/**
 * 对齐作业日程（可 await 的版本）。
 *
 * @param assignments 当前**已知的**作业（`AssignmentStore` 的当前快照）。
 * @param dataComplete 这份作业列表是否**完整可信**（= 当前学期全部课程都取到了）。
 *   ⚠️ 这一位必须如实传：对齐是"以期望集合为准，多则删"，而**空集合等于"一条日程都不要"**。
 *   数据还没加载、或部分课程请求失败时若照传，会把用户日历里已有的日程**成批删掉**——
 *   用户不会看到任何提示，只是日历里的截止日程突然没了。故这种情形下**一条也不动**。
 *   关闭开关是例外：那时"空集合"正是用户的意思，照删。
 *
 * `context` 必须是 **UIAbilityContext**（不是 ApplicationContext）：2026-09-28 模拟器实测，
 * 用应用级上下文调 `calendarManager.getCalendar()` 一律报 `201`（权限拒绝）——而权限查下来是
 * 已授予的；换成 Ability 上下文即通过。官方文档的样例也一律用 Ability 上下文。
 */
export function syncAssignmentReminders(context: common.UIAbilityContext, assignments: Assignment[],
                                        dataComplete: boolean): Promise<ReminderSyncResult> {
  const next: Promise<ReminderSyncResult> = chain.then(() => runSync(context, assignments, dataComplete));
  chain = next.then((): void => {
  }).catch((): void => {
  });
  return next;
}

/**
 * 对齐作业日程（**不等结果**的版本）。
 *
 * 作业页只需要"数据落地了，顺手对齐一次"，没有任何 UI 依赖结果，故不返回 Promise——
 * 免得调用方以为该 await 它（await 会把列表渲染卡在系统调用上）。
 */
export function requestAssignmentReminderSync(context: common.UIAbilityContext, assignments: Assignment[],
                                              dataComplete: boolean): void {
  syncAssignmentReminders(context, assignments, dataComplete).catch((err: Error) => {
    Logger.warn(TAG, `日程对齐未完成 err=${err.message}`);
  });
}

/** 是否已获得读写日历的权限（设置页据此提示"没权限，日程写不进去"） */
export function calendarPermissionGranted(): boolean {
  return hasCalendarPermission();
}

/** 申请日历权限（设置页在用户打开开关时调用）。返回是否两个权限都被授予 */
export function requestCalendarAccess(context: common.UIAbilityContext): Promise<boolean> {
  return requestCalendarPermission(context);
}

async function runSync(context: common.UIAbilityContext, assignments: Assignment[],
                       dataComplete: boolean): Promise<ReminderSyncResult> {
  const enabled: boolean = readAssignmentReminder(context);
  const offsetMinutes: number = readAssignmentReminderOffset(context);
  const noRemindIfComplete: boolean = readAssignmentReminderNoIfComplete(context);

  // 开关开着、但这份作业列表不是"当前学期的全貌"（还没加载出来，或部分课程请求失败）：
  // **一条也不动**。否则期望集合为空 → 差量会把日历里已有的日程成批删掉，而用户毫不知情。
  // 关闭开关时不走这条路：那时"空集合"正是用户的意思。
  if (enabled && !dataComplete) {
    Logger.info(TAG, '作业数据不完整（未加载或部分课程失败），本次不动日历');
    return new ReminderSyncResult(enabled, 0, 0, false, false);
  }

  if (!hasCalendarPermission()) {
    // 没权限时**不去调**日历接口（必失败且刷一堆错误日志）：如实把"缺权限"报上去，
    // 由设置页提示用户去授权。关闭开关也走这里——想清理但没权限，只能等用户授权,
    // 这一点由提示行说明。
    Logger.warn(TAG, `没有日历权限，本次不改动日历 enabled=${enabled}`);
    return new ReminderSyncResult(enabled, 0, 0, false, true);
  }

  const desired: CalendarEventPlan[] = enabled
    ? planAssignmentEvents(assignments, offsetMinutes, noRemindIfComplete, Date.now())
    : [];

  // 下面三步各自 try：失败点要能一眼看出（只报一个笼统的"对齐失败"，
  // 排查时得靠猜是哪一步——2026-09-28 就为这个多花了一轮）。
  let calendar: calendarManager.Calendar;
  try {
    calendar = await ensureCalendar(context);
  } catch (err) {
    Logger.warn(TAG, `取日历账户失败 code=${(err as BusinessError).code}`);
    return new ReminderSyncResult(enabled, 0, 0, true, false);
  }

  let existing: ExistingCalendarEvent[];
  try {
    existing = await listEvents(calendar);
  } catch (err) {
    Logger.warn(TAG, `读取现有日程失败 code=${(err as BusinessError).code}`);
    return new ReminderSyncResult(enabled, 0, 0, true, false);
  }

  const plan: CalendarAlignPlan = alignCalendarEvents(desired, existing, EVENT_KEY_PREFIX);
  if (plan.isEmpty()) {
    Logger.info(TAG, `日历日程已是最新，无需变更 enabled=${enabled}`);
    return new ReminderSyncResult(enabled, 0, 0, false, false);
  }

  let deleted: number = 0;
  for (const eventId of plan.toDelete) {
    try {
      await deleteEvent(calendar, eventId);
      deleted++;
    } catch (err) {
      // 单条删除失败不中断：剩下的该删的还得删、该加的还得加，否则会停在半途状态
      Logger.warn(TAG, `删除日程失败 id=${eventId} code=${(err as BusinessError).code}`);
    }
  }

  let added: number = 0;
  let failed: boolean = false;
  for (const entry of plan.toAdd) {
    try {
      await addEvent(calendar, entry);
      added++;
    } catch (err) {
      Logger.warn(TAG, `写入日程失败 key=${entry.key} code=${(err as BusinessError).code}`);
      failed = true;
    }
  }

  Logger.info(TAG, `日历对齐完成 enabled=${enabled} 新增=${added} 删除=${deleted}`
    + ` 期望=${desired.length} 现状=${existing.length} 失败=${failed}`);
  return new ReminderSyncResult(enabled, added, deleted, failed, false);
}
