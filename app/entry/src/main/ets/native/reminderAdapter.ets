/**
 * 系统提醒（通知代理）的适配：`@ohos.reminderAgentManager` 的**唯一出口**（架构不变量 §3）。
 *
 * 只封装系统调用，**不做业务判断**（哪些作业该提醒、该不该重登，全部由 `model/reminder` 的
 * 纯逻辑算出、由 `viewmodel/reminderSync` 编排）。每个函数把系统异常原样抛出，
 * 由上层归类记日志；只有一处例外：**撤销一条已经不存在的提醒视为成功**（见 `cancelReminder`）。
 *
 * 选提醒代理而不是"自己起定时器 + `notificationManager` 发通知"的理由：
 * 提醒是**系统侧的持久登记**，应用被杀死或没在运行也照弹（NFR 上"不被落下"正是这个功能的价值）；
 * 自建定时器只在应用活着时有效，而这个应用不是常驻后台的。
 */

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReminderEntry, ReminderMoment, ReminderRecord } from '../model/reminder';
import { Logger } from '../common/logger';

const TAG: string = 'reminderAdapter';

/**
 * 点通知后打开的界面：本应用入口 Ability（`entry/src/main/module.json5` 的 `mainElement`）。
 *
 * 为什么不查 `bundleManager` 动态取：本应用只有一个入口 Ability，额外引入一次异步查询
 * 只为了让一个已知常量"可能变化"——真改了名字，这里与 `module.json5` 同时改即可。
 */
const ENTRY_ABILITY: string = 'EntryAbility';

/** 提醒已不存在（撤销时报这个码，视为"已达成目的"） */
const ERR_REMINDER_NOT_EXIST: number = 1700003;

/**
 * 登记一条提醒，返回系统给的提醒 id。
 *
 * 不设 `notificationId`：系统的提醒身份由它会给的 id 与我们的 `groupId` 一起决定，
 * 我们自己不用 id 认提醒（用 `groupId`，见 spec §3.3 第 2 条），让系统分配更不容易撞。
 * 提醒时刻按**设备本地时区**解释（`LocalDateTime` 无时区字段），与 `momentOf` 的取向一致。
 */
export async function publishReminder(entry: ReminderEntry, bundleName: string): Promise<number> {
  const moment: ReminderMoment = entry.moment();
  const request: reminderAgentManager.ReminderRequestCalendar = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
    dateTime: {
      year: moment.year,
      month: moment.month,
      day: moment.day,
      hour: moment.hour,
      minute: moment.minute
    },
    title: entry.title,
    content: entry.content,
    groupId: entry.key,
    // 服务信息（高优先）而不是社交：截止提醒该被看见，但不是"消息"
    slotType: notificationManager.SlotType.SERVICE_INFORMATION,
    wantAgent: {
      pkgName: bundleName,
      abilityName: ENTRY_ABILITY
    }
  };

  return reminderAgentManager.publishReminder(request);
}

/**
 * 撤销一条提醒。
 *
 * **已经不存在的提醒视为撤销成功**：调用方"撤掉这一条"的意图是"让它不再出现"，
 * 系统说它本来就不在了，意图已经达成。把它当失败会让一次并发对齐后的清理记一堆假错误。
 */
export async function cancelReminder(reminderId: number): Promise<void> {
  try {
    await reminderAgentManager.cancelReminder(reminderId);
  } catch (err) {
    if ((err as BusinessError).code === ERR_REMINDER_NOT_EXIST) {
      Logger.info(TAG, `提醒已不存在，视为已撤销 id=${reminderId}`);
      return;
    }
    throw err as Error;
  }
}

/**
 * 列出本应用当前**有效**的提醒（到点的提醒会自动从有效集合里消失）。
 *
 * 只收 `REMINDER_TYPE_CALENDAR` 的：本应用只登记这一种，其余类型读不出时刻、
 * 也不该被我们撤销。`groupId` 缺失或为空时键记为**空串**——纯逻辑据此判定
 * "不是本功能登记的，别动它"。
 */
export async function listReminders(): Promise<ReminderRecord[]> {
  const infos: reminderAgentManager.ReminderInfo[] = await reminderAgentManager.getAllValidReminders();

  const records: ReminderRecord[] = [];
  for (const info of infos) {
    const request: reminderAgentManager.ReminderRequest = info.reminderReq;
    if (request.reminderType !== reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
      continue;
    }
    const calendar: reminderAgentManager.ReminderRequestCalendar =
      request as reminderAgentManager.ReminderRequestCalendar;
    const dateTime: reminderAgentManager.LocalDateTime = calendar.dateTime;
    const key: string = calendar.groupId === undefined ? '' : calendar.groupId;
    records.push(new ReminderRecord(info.reminderId, key,
      new ReminderMoment(dateTime.year, dateTime.month, dateTime.day, dateTime.hour, dateTime.minute)));
  }
  return records;
}

/**
 * 系统通知总开关是否开着。
 *
 * 查不出来时返回 `true`（**不冤枉**）：这只是设置页的一句提示，查询失败时宁可不提示，
 * 也不能因为一次查询失败就告诉用户"你的通知关着"——那是会让人白折腾的假消息。
 */
export function notificationsEnabled(): boolean {
  try {
    return notificationManager.isNotificationEnabledSync();
  } catch (err) {
    Logger.warn(TAG, `查询通知开关失败，按已开启处理 code=${(err as BusinessError).code}`);
    return true;
  }
}
