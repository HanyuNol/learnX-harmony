/**
 * 系统日历的适配：Calendar Kit（`@ohos.calendarManager`）的**唯一出口**（架构不变量 §3）。
 *
 * 只封装系统调用，**不做业务判断**（哪些作业该进日历、和现有日程比多什么少什么，
 * 全部由 `model/reminder` 的纯逻辑算出、由 `viewmodel/reminderSync` 编排）。
 * 每个函数把系统异常原样抛出，由上层归类记日志。
 *
 * 为什么用**自建日历账户**而不是写进系统默认日历：① 本应用的日程与用户自己的日程
 * 泾渭分明，用户能在日历应用里单独隐藏/删除；② 整批清理时不必逐条判断归属
 * （权限也明确允许"增删改**当前应用创建的**账户及其下的日程"）。上游 learnX 同样自建日历。
 *
 * 环境依据（2026-09-28 查官方文档）：日历读写是**用户授权**级普通权限
 * （`ohos.permission.READ_CALENDAR` / `WRITE_CALENDAR`，`user_grant`/`normal`），
 * Calendar Kit 支持模拟器，服务地区为中国境内（不含港澳台）。
 */

import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, bundleManager, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CalendarEventPlan, ExistingCalendarEvent } from '../model/reminder';
import { Logger } from '../common/logger';

const TAG: string = 'calendarAdapter';

/** 写日程与改账户所需 */
const PERMISSION_WRITE: Permissions = 'ohos.permission.WRITE_CALENDAR';
/** 读回日程（对齐的输入）所需 */
const PERMISSION_READ: Permissions = 'ohos.permission.READ_CALENDAR';

/** 权限申请结果里"已授予"的取值（官方 `GrantStatus.PERMISSION_GRANTED`） */
const GRANTED: number = 0;

/** 本应用的 accessTokenId（查/申请权限都要它）。取不到时抛错，由上层按"无权限"处理 */
function tokenId(): number {
  const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
    bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
  return info.appInfo.accessTokenId;
}

/**
 * 是否已获得读写日历的权限。
 *
 * 查不出来时返回 `false`（**按未授权处理**）：与"通知开关查不出来就按已开启"相反，
 * 这里宁可多弹一次授权框，也不要出现"以为有权限、其实没写进去"（那是静默失败）。
 */
export function hasCalendarPermission(): boolean {
  try {
    const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const id: number = tokenId();
    const read: number = manager.checkAccessTokenSync(id, PERMISSION_READ);
    const write: number = manager.checkAccessTokenSync(id, PERMISSION_WRITE);
    return read === GRANTED && write === GRANTED;
  } catch (err) {
    Logger.warn(TAG, `查询日历权限失败，按未授权处理 code=${(err as BusinessError).code}`);
    return false;
  }
}

/**
 * 申请读写日历的权限（系统会弹授权框）。返回是否**两个都**被授予。
 *
 * 申请失败（用户拒绝、系统异常）都只是返回 false，不抛：调用方据此在设置页如实提示。
 */
export async function requestCalendarPermission(context: common.Context): Promise<boolean> {
  try {
    const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result: PermissionRequestResult =
      await manager.requestPermissionsFromUser(context, [PERMISSION_READ, PERMISSION_WRITE]);
    const results: number[] = result.authResults;
    if (results.length < 2) {
      return false;
    }
    for (const item of results) {
      if (item !== GRANTED) {
        return false;
      }
    }
    return true;
  } catch (err) {
    Logger.warn(TAG, `申请日历权限失败 code=${(err as BusinessError).code}`);
    return false;
  }
}

/**
 * 取用于写入日程的日历：**系统默认日历账户**。
 *
 * 为什么不用"本应用自建的账户"（原设计，与上游一致）：**2026-09-28 模拟器实测
 * `createCalendar()` 被拒**——通用错误码 `201`（权限拒绝），而 `READ_CALENDAR` /
 * `WRITE_CALENDAR` 都已授予、`getAllCalendars()` 也正常返回。官方文档给的正是替代路径：
 * "默认 Calendar 是日历存储首次运行时创建的，若创建 Event 时不关注其 Calendar 归属，
 * 则无须通过 createCalendar() 创建 Calendar，直接使用默认 Calendar"；权限对照表也明确
 * `WRITE_CALENDAR` 允许"**添加、删除或修改系统默认日历账户下当前应用创建的日程**"——
 * 正好就是我们的用法。
 *
 * 我们在默认账户里的身份靠日程的 `identifier`（`learnx:` 前缀）认领：读回来只认带前缀的，
 * 没有前缀的一律不动（那是用户或别的应用写的）。代价是这些截止日程与用户自己的日程同处
 * 一个日历、不能整账户隐藏——如实记在 `docs/specs/reminders.md` §6。
 */
export async function ensureCalendar(context: common.Context): Promise<calendarManager.Calendar> {
  const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
  return manager.getCalendar();
}

/**
 * 读回本账户下的全部日程。
 *
 * **不传任何参数**：`getEvents(eventFilter?, eventKey?)` 显式传 `undefined` 会被判为参数错误
 * （实测 `401`），而 API 20 起默认查询字段本就包含 `id`、`identifier`、`title`、`startTime`、
 * `reminderTime`（官方 API 参考的"默认查询字段"说明）——对齐要用的都在里面。
 * 默认账户里能读到的只有**本应用创建的**日程（`READ_CALENDAR` 的授权范围即如此）；
 * 何况我们还按 `identifier` 前缀认领，不认的一律不动。
 */
export async function listEvents(calendar: calendarManager.Calendar): Promise<ExistingCalendarEvent[]> {
  const events: calendarManager.Event[] = await calendar.getEvents();
  const result: ExistingCalendarEvent[] = [];
  for (const event of events) {
    const id: number | undefined = event.id;
    if (id === undefined) {
      continue;
    }
    const identifier: string = event.identifier === undefined ? '' : event.identifier;
    const title: string = event.title === undefined ? '' : event.title;
    const startTime: number = event.startTime === undefined ? 0 : event.startTime;
    const times: number[] | undefined = event.reminderTime;
    const reminderMinutes: number | null = times === undefined || times.length === 0 ? null : times[0];
    // 地点在 `Location` 对象里（`{ location, longitude, latitude }`），自由文本是 `location` 字段
    const place: calendarManager.Location | undefined = event.location;
    const location: string = place === undefined || place.location === undefined ? '' : place.location;
    result.push(new ExistingCalendarEvent(id, identifier, title, location, startTime, reminderMinutes));
  }
  return result;
}

/**
 * 写入一条日程，返回系统给的日程 id。
 *
 * 两个可选字段都**只在需要时才填**：不设提醒就不填 `reminderTime`（官方"不填即不提醒"，
 * 空数组的语义官方没写，不拿它赌）；没有地点就不填 `location`。
 * 地点写进 `Location.location`（自由文本），另两个字段是经纬度，本项目不用。
 */
export async function addEvent(calendar: calendarManager.Calendar,
                               plan: CalendarEventPlan): Promise<number> {
  const event: calendarManager.Event = {
    type: calendarManager.EventType.NORMAL,
    title: plan.title,
    startTime: plan.startTime,
    endTime: plan.endTime,
    description: plan.description,
    identifier: plan.key
  };
  if (plan.reminderMinutes !== null) {
    event.reminderTime = [plan.reminderMinutes];
  }
  if (plan.location.length > 0) {
    event.location = { location: plan.location };
  }
  return calendar.addEvent(event);
}

/** 删除一条日程 */
export async function deleteEvent(calendar: calendarManager.Calendar, eventId: number): Promise<void> {
  await calendar.deleteEvent(eventId);
}
