/**
 * 作业提醒的对齐编排（FR-18）：读偏好 → 算期望与差量（纯逻辑）→ 落到系统通知代理。
 *
 * 为什么单独一个模块而不是塞进 `settingsStore`：`settingsStore` 是"用户选了什么"的缝，
 * 而这里是"把选择变成系统里的提醒"的一整套编排（含串行化与失败归类），职责不同。
 * 页面（设置页、作业页）只调这里的入口，不碰存储与系统能力（架构不变量 §1）。
 *
 * 失败**不向上抛**：提醒是"尽力而为"的系统能力（`ARCHITECTURE.md` §5.5），
 * 登记不上不该让作业列表或设置页的任何操作失败；失败只记日志、并把结果如实返回给
 * 需要告知用户的那一处（设置页）。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Assignment } from '../model/assignment';
import { ReminderEntry, ReminderPlan, ReminderRecord, planReminders, reconcile } from '../model/reminder';
import { cancelReminder, listReminders, notificationsEnabled, publishReminder } from '../native/reminderAdapter';
import {
  readAssignmentReminder, readAssignmentReminderNoIfComplete, readAssignmentReminderOffset
} from '../storage/preferenceStore';
import { Logger } from '../common/logger';

const TAG: string = 'reminderSync';

/** 系统通知总开关关着（`publishReminder` 会报这个码） */
const ERR_NOTIFICATION_DISABLED: number = 1700001;

/** 提醒条数超过系统上限（`publishReminder` 会报这个码） */
const ERR_TOO_MANY_REMINDERS: number = 1700002;

/** 一次对齐的结果。`failed` 表示"没能读到系统现状或没能登记"，不代表偏好没生效 */
export class ReminderSyncResult {
  /** 本次对齐时开关是否为开（关时为 false，此时就该把已登记的撤干净） */
  readonly enabled: boolean;
  readonly published: number;
  readonly cancelled: number;
  readonly failed: boolean;

  constructor(enabled: boolean, published: number, cancelled: number, failed: boolean) {
    this.enabled = enabled;
    this.published = published;
    this.cancelled = cancelled;
    this.failed = failed;
  }
}

/**
 * 串行化的队列。
 *
 * "读系统现状 → 算差量 → 落系统"不是原子的：两次对齐并发时，双方可能都读到"系统里没有这条"
 * 而各登记一次，于是同一条作业出现两条提醒。这个应用里的触发点都是用户动作（页面进来、
 * 改动设置），并发本就罕见，但**代价是用户看到重复通知**，故用一条 Promise 链把对齐串起来，
 * 顺序执行、后一次能看到前一次的结果。
 */
let chain: Promise<void> = Promise.resolve();

/**
 * 对齐作业提醒（可 await 的版本）。
 *
 * @param assignments 当前**已知的**作业（`AssignmentStore` 的当前快照）。
 * @param dataComplete 这份作业列表是否**完整可信**（= 当前学期全部课程都取到了）。
 *   ⚠️ 这一位必须如实传：对齐是"以期望集合为准，多则撤"，而**空集合等于"一条提醒都不要"**。
 *   数据还没加载、或部分课程请求失败时若照传，会把已登记的提醒**成批撤掉**——
 *   用户不会看到任何提示，只是提醒突然不响了。故这种情形下**一条也不动**（见 `runSync`）。
 *   关闭开关是例外：那时"空集合"正是用户的意思，照撤。
 */
export function syncAssignmentReminders(context: common.Context, assignments: Assignment[],
                                        dataComplete: boolean): Promise<ReminderSyncResult> {
  const next: Promise<ReminderSyncResult> = chain.then(() => runSync(context, assignments, dataComplete));
  chain = next.then((): void => {
  }).catch((): void => {
  });
  return next;
}

/**
 * 对齐作业提醒（**不等结果**的版本）。
 *
 * 作业页只需要"数据落地了，顺手对齐一次"，没有任何 UI 依赖结果，故不返回 Promise——
 * 免得调用方以为该 await 它（await 会把列表渲染卡在系统调用上）。
 */
export function requestAssignmentReminderSync(context: common.Context, assignments: Assignment[],
                                              dataComplete: boolean): void {
  syncAssignmentReminders(context, assignments, dataComplete).catch((err: Error) => {
    Logger.warn(TAG, `提醒对齐未完成 err=${err.message}`);
  });
}

/** 系统通知总开关是否开着（设置页据此提示"提醒登记了也弹不出来"） */
export function reminderNotificationsEnabled(): boolean {
  return notificationsEnabled();
}

async function runSync(context: common.Context, assignments: Assignment[],
                       dataComplete: boolean): Promise<ReminderSyncResult> {
  const enabled: boolean = readAssignmentReminder(context);
  const offsetMinutes: number = readAssignmentReminderOffset(context);
  const noRemindIfComplete: boolean = readAssignmentReminderNoIfComplete(context);

  // 开关开着、但这份作业列表不是"当前学期的全貌"（还没加载出来，或部分课程请求失败）：
  // **一条也不动**。否则期望集合为空 → 差量会把已登记的提醒成批撤掉，而用户毫不知情
  // （2026-09-28 推演出的缺陷：部分课程失败是应用明确容忍的常态，见 notices spec §5.2）。
  // 关闭开关时不走这条路：那时"空集合"正是用户的意思。
  if (enabled && !dataComplete) {
    Logger.info(TAG, '作业数据不完整（未加载或部分课程失败），本次不动系统提醒');
    return new ReminderSyncResult(enabled, 0, 0, false);
  }

  const desired: ReminderEntry[] = enabled
    ? planReminders(assignments, offsetMinutes, noRemindIfComplete, Date.now())
    : [];

  let current: ReminderRecord[] = [];
  try {
    current = await listReminders();
  } catch (err) {
    Logger.warn(TAG, `读取现有提醒失败，本次不对齐 code=${(err as BusinessError).code}`);
    return new ReminderSyncResult(enabled, 0, 0, true);
  }

  const plan: ReminderPlan = reconcile(desired, current);
  if (plan.isEmpty()) {
    Logger.info(TAG, `提醒已是最新，无需变更 enabled=${enabled}`);
    return new ReminderSyncResult(enabled, 0, 0, false);
  }

  let cancelled: number = 0;
  for (const reminderId of plan.toCancel) {
    try {
      await cancelReminder(reminderId);
      cancelled++;
    } catch (err) {
      // 撤销失败不中断：剩下的该撤的还得撤、该登的还得登，否则会停在半途状态
      Logger.warn(TAG, `撤销提醒失败 id=${reminderId} code=${(err as BusinessError).code}`);
    }
  }

  const bundleName: string = context.applicationInfo.name;
  let published: number = 0;
  let failed: boolean = false;
  for (const entry of plan.toPublish) {
    try {
      await publishReminder(entry, bundleName);
      published++;
    } catch (err) {
      const code: number = (err as BusinessError).code;
      Logger.warn(TAG, `登记提醒失败 key=${entry.key} code=${code}`);
      failed = true;
      // 这两种失败后面每一条都会同样失败，继续试只是白刷日志（也拖慢页面）：
      // 通知总开关关着、或已达系统条数上限——第 2 种下次对齐还会再试（到期的提醒会腾出额度）
      if (code === ERR_NOTIFICATION_DISABLED || code === ERR_TOO_MANY_REMINDERS) {
        Logger.warn(TAG, `停止本次登记 code=${code} 已登记=${published} 待登记=${plan.toPublish.length}`);
        break;
      }
    }
  }

  Logger.info(TAG, `提醒对齐完成 enabled=${enabled} 新登=${published} 撤销=${cancelled}`
    + ` 期望=${desired.length} 现状=${current.length} 失败=${failed}`);
  return new ReminderSyncResult(enabled, published, cancelled, failed);
}
