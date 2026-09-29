/**
 * 课程表同步的编排（FR-19）：取课表 → 算期望日程 → 与日历现状差量对齐 → 落系统日历。
 *
 * 与作业提醒（`viewmodel/reminderSync.ets`）**共用同一套日历管道**（Calendar Kit、默认账户、
 * `identifier` 认领、差量对齐），差别只在三处：数据来源是注册中心的 JSONP 接口、
 * 用**课程前缀**划出作用域、以及支持"清除课程日程"。
 *
 * 两个作用域的并发是安全的：两边各自只读全量、只写/删自己前缀内的日程，
 * 故各用一条串行链即可（没有共享的可变状态）。
 *
 * 失败**不向上抛**：课表取不到只是"这次没同步成"，不该让设置页崩掉；
 * 失败的**可读原因**（四分类）随结果返回，由界面如实显示。
 */

import { common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  CalendarAlignPlan, CalendarApplyVerdict, CalendarEventPlan, ExistingCalendarEvent,
  alignCalendarEvents, calendarApplyVerdict
} from '../model/reminder';
import { COURSE_KEY_PREFIX, ScheduleRange, planCourseEvents, scheduleRangeOf } from '../model/courseEvent';
import { ScheduleBatch, ScheduleRepository } from '../repository/scheduleRepository';
import {
  addEvent, deleteEvent, ensureCalendar, hasCalendarPermission, listEvents
} from '../native/calendarAdapter';
import {
  readCourseGraduate, readCourseReminder, readCourseReminderOffset, writeLastCourseSyncAt
} from '../storage/preferenceStore';
import { AuthError } from '../model/auth';
import { normalize } from '../common/errors';
import { TextKeys, textKeyOfFailReason } from '../common/texts';
import { Logger } from '../common/logger';

const TAG: string = 'courseCalendarSync';

/** 一次课程表同步的结果。`errorTextKey` 非空表示失败（四分类口径的可读原因） */
export class CourseSyncResult {
  readonly ok: boolean;
  /** 写入的日程数（本次新增/重建的） */
  readonly added: number;
  readonly deleted: number;
  /** 期望留在日历里的课程日程总数（界面用它说"已同步 N 条"，而不是说"新增 N 条"） */
  readonly expected: number;
  readonly permissionMissing: boolean;
  readonly errorTextKey: string;

  constructor(ok: boolean, added: number, deleted: number, expected: number,
              permissionMissing: boolean, errorTextKey: string) {
    this.ok = ok;
    this.added = added;
    this.deleted = deleted;
    this.expected = expected;
    this.permissionMissing = permissionMissing;
    this.errorTextKey = errorTextKey;
  }
}

/** 串行化：同步与清除不该同时跑（两个都会读全量再写）。同一族的两次操作顺序执行 */
let chain: Promise<void> = Promise.resolve();

function serialized(task: () => Promise<CourseSyncResult>): Promise<CourseSyncResult> {
  const next: Promise<CourseSyncResult> = chain.then(task);
  chain = next.then((): void => {
  }).catch((): void => {
  });
  return next;
}

/** 是否已获得读写日历的权限（与作业提醒同一个权限，界面共用同一条提示） */
export function courseCalendarPermissionGranted(): boolean {
  return hasCalendarPermission();
}

/** 同步课程表到日历（取"今天起 4 周"，见 `model/courseEvent.scheduleRangeOf`） */
export function syncCourseSchedule(context: common.UIAbilityContext): Promise<CourseSyncResult> {
  return serialized(() => runSync(context));
}

/** 清除已同步的课程日程：期望集合为空 → 差量会把课程前缀下的日程删干净（不碰作业日程） */
export function clearCourseSchedule(context: common.UIAbilityContext): Promise<CourseSyncResult> {
  return serialized(() => runApply(context, [], false));
}

async function runSync(context: common.UIAbilityContext): Promise<CourseSyncResult> {
  if (!hasCalendarPermission()) {
    Logger.warn(TAG, '没有日历权限，本次不改动日历');
    return new CourseSyncResult(false, 0, 0, 0, true, '');
  }

  const now: number = Date.now();
  const range: ScheduleRange = scheduleRangeOf(now);
  const graduate: boolean = readCourseGraduate(context);
  const reminderOn: boolean = readCourseReminder(context);

  let batch: ScheduleBatch;
  try {
    batch = await ScheduleRepository.load(range.startDate, range.endDate, graduate);
  } catch (err) {
    const failure: AuthError = normalize(err, '取课表');
    Logger.warn(TAG, `课表取数失败 reason=${failure.reason} detail=${failure.detail}`);
    return new CourseSyncResult(false, 0, 0, 0, false,
      textKeyOfFailReason(failure.reason, failure.hintKey));
  }

  const remindMinutes: number | null = reminderOn ? readCourseReminderOffset(context) : null;
  const desired: CalendarEventPlan[] = planCourseEvents(batch.sessions, remindMinutes, now);
  return runApply(context, desired, true);
}

/** 把期望集合落到日历（`countAsSync=false` 时不更新"上次同步时间"——清除不算同步过） */
async function runApply(context: common.UIAbilityContext, desired: CalendarEventPlan[],
                        countAsSync: boolean): Promise<CourseSyncResult> {
  let calendar: calendarManager.Calendar;
  try {
    calendar = await ensureCalendar(context);
  } catch (err) {
    Logger.warn(TAG, `取日历账户失败 code=${(err as BusinessError).code}`);
    return new CourseSyncResult(false, 0, 0, desired.length, false, '');
  }

  let existing: ExistingCalendarEvent[];
  try {
    existing = await listEvents(calendar);
  } catch (err) {
    Logger.warn(TAG, `读取现有日程失败 code=${(err as BusinessError).code}`);
    return new CourseSyncResult(false, 0, 0, desired.length, false, '');
  }

  const plan: CalendarAlignPlan = alignCalendarEvents(desired, existing, COURSE_KEY_PREFIX);
  if (!plan.isEmpty()) {
    let deleted: number = 0;
    let failed: number = 0;
    for (const eventId of plan.toDelete) {
      try {
        await deleteEvent(calendar, eventId);
        deleted++;
      } catch (err) {
        // 失败要**计数**：删不掉的日程会让"现状"与"期望"长期不一致，结论里必须体现
        // （审查 R-04：原先只记日志，于是照样报"成功"、还照记"上次同步时间"）
        failed++;
        Logger.warn(TAG, `删除日程失败 id=${eventId} code=${(err as BusinessError).code}`);
      }
    }
    let added: number = 0;
    for (const entry of plan.toAdd) {
      try {
        await addEvent(calendar, entry);
        added++;
      } catch (err) {
        failed++;
        Logger.warn(TAG, `写入日程失败 key=${entry.key} code=${(err as BusinessError).code}`);
      }
    }
    const verdict: CalendarApplyVerdict = calendarApplyVerdict(failed, countAsSync);
    Logger.info(TAG, `课程日程对齐完成 新增=${added} 删除=${deleted} 失败=${failed}`
      + ` 期望=${desired.length} 算成功=${verdict.ok}`);
    if (verdict.recordSyncTime) {
      writeLastCourseSyncAt(context, Date.now());
    }
    return new CourseSyncResult(verdict.ok, added, deleted, desired.length, false,
      verdict.ok ? '' : TextKeys.SETTINGS_COURSE_PARTIAL);
  }

  Logger.info(TAG, `课程日程已是最新，无需变更 期望=${desired.length}`);
  if (calendarApplyVerdict(0, countAsSync).recordSyncTime) {
    writeLastCourseSyncAt(context, Date.now());
  }
  return new CourseSyncResult(true, 0, 0, desired.length, false, '');
}
