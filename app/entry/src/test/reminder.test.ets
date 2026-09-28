/**
 * 作业截止提醒纯逻辑的单元测试（reminders spec §5 第 1–4 项）。
 *
 * 钉住三件最容易错的事：**提醒时刻已过去时不设提醒（但日程照写）**——系统对"提醒时间已过
 * 但日程未结束"的日程会立即弹提醒，那等于当场发一条无意义的通知；
 * **提醒分钟数相对的是日程开始时间**（官方语义），而日程结束于截止时刻，故要减掉 30 分钟；
 * **"内容变了"必须删了重建**，否则老师改了截止时间后，日历里会停在旧时刻。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  Assignment, AssignmentAttachments, HomeworkCompletionType, HomeworkSubmissionType
} from '../main/ets/model/assignment';
import {
  CalendarAlignPlan, CalendarEventPlan, DEFAULT_OFFSET_MINUTES, EVENT_LENGTH_MINUTES, EVENT_KEY_PREFIX,
  ExistingCalendarEvent, alignCalendarEvents, eventDescriptionOf, eventKeyOf, eventTitleOf,
  parseOffsetMinutes, planAssignmentEvents
} from '../main/ets/model/reminder';

const MINUTE: number = 60 * 1000;
const HOUR: number = 60 * MINUTE;
const DAY: number = 24 * HOUR;

function assignment(id: string, courseId: string, deadlineTime: number, submitted: boolean,
                    description: string): Assignment {
  return new Assignment(id, `base-${id}`, courseId, `课程${courseId}`, '张老师', `作业${id}`,
    description, 'raw', deadlineTime, '', submitted, false, false,
    HomeworkCompletionType.INDIVIDUAL, HomeworkSubmissionType.WEB_LEARNING, '',
    '', '', '', '', '', AssignmentAttachments.empty(), true);
}

function existing(eventId: number, key: string, title: string, startTime: number,
                  reminderMinutes: number | null): ExistingCalendarEvent {
  // 作业日程没有地点（留空）；地点参与等价判定，见课程日程那批用例
  return new ExistingCalendarEvent(eventId, key, title, '', startTime, reminderMinutes);
}

/** 期望里那一条（取不到就抛，避免用手写索引） */
function planOf(plans: CalendarEventPlan[], key: string): CalendarEventPlan {
  for (const plan of plans) {
    if (plan.key === key) {
      return plan;
    }
  }
  throw new Error(`期望里应有 ${key}`);
}

/** 差量对齐用例共用：由一条作业算出"期望的日程"（`now` 固定便于断言） */
function desiredOf(deadline: number, offsetMinutes: number, now: number): CalendarEventPlan[] {
  return planAssignmentEvents([assignment('a', 'c1', deadline, false, '正文')], offsetMinutes, false, now);
}

export default function reminderTest() {
  describe('reminder', () => {

    describe('提前量文本解析', () => {

      it('0 与正整数通过（含前后空格）', 0, () => {
        expect(parseOffsetMinutes('0')).assertEqual(0);
        expect(parseOffsetMinutes('1440')).assertEqual(1440);
        expect(parseOffsetMinutes(' 60 ')).assertEqual(60);
      });

      it('空串 / 非整数 / 负数 / 带小数 / 超过上限被拒', 0, () => {
        expect(parseOffsetMinutes('')).assertEqual(null);
        expect(parseOffsetMinutes('   ')).assertEqual(null);
        expect(parseOffsetMinutes('abc')).assertEqual(null);
        expect(parseOffsetMinutes('-5')).assertEqual(null);
        expect(parseOffsetMinutes('1.5')).assertEqual(null);
        // 科学计数法不该被当成"用户想输 1000 分钟"
        expect(parseOffsetMinutes('1e3')).assertEqual(null);
        expect(parseOffsetMinutes(`${14 * 24 * 60 + 1}`)).assertEqual(null);
        expect(parseOffsetMinutes(`${14 * 24 * 60}`)).assertEqual(14 * 24 * 60);
      });
    });

    describe('作业 → 日历日程', () => {

      it('只收未过期的作业（严格晚于当前时刻）', 0, () => {
        const now: number = 1000 * DAY;
        const plans: CalendarEventPlan[] = planAssignmentEvents([
          assignment('a', 'c1', now + DAY, false, '正文'),
          assignment('b', 'c1', now - DAY, false, '正文'),
          assignment('c', 'c1', now, false, '正文')
        ], 60, false, now);
        expect(plans.length).assertEqual(1);
        expect(plans[0].key).assertEqual(`${EVENT_KEY_PREFIX}c1:a`);
      });

      it('日程结束于截止时刻、开始于截止前 30 分钟', 0, () => {
        const now: number = 1000 * DAY;
        const deadline: number = now + 2 * DAY;
        const plans: CalendarEventPlan[] = planAssignmentEvents(
          [assignment('a', 'c1', deadline, false, '正文')], 60, false, now);
        expect(plans[0].endTime).assertEqual(deadline);
        expect(plans[0].startTime).assertEqual(deadline - EVENT_LENGTH_MINUTES * MINUTE);
      });

      it('提醒分钟数相对**开始时间**，故等于提前量减日程时长', 0, () => {
        const now: number = 1000 * DAY;
        const plans: CalendarEventPlan[] = planAssignmentEvents(
          [assignment('a', 'c1', now + 2 * DAY, false, '正文')], 1440, false, now);
        expect(plans[0].reminderMinutes).assertEqual(1440 - 30);
      });

      it('提前量为 0 时提醒落在截止时刻（负值＝开始之后）', 0, () => {
        const now: number = 1000 * DAY;
        const plans: CalendarEventPlan[] = planAssignmentEvents(
          [assignment('a', 'c1', now + 2 * HOUR, false, '正文')], 0, false, now);
        expect(plans[0].reminderMinutes).assertEqual(-30);
      });

      it('提醒时刻已过去时不设提醒，但日程照写', 0, () => {
        const now: number = 1000 * DAY;
        const plans: CalendarEventPlan[] = planAssignmentEvents(
          [assignment('a', 'c1', now + 30 * MINUTE, false, '正文')], 60, false, now);
        expect(plans.length).assertEqual(1);
        expect(plans[0].reminderMinutes).assertEqual(null);
      });

      it('截止时间解析不出（0）的不登记', 0, () => {
        const now: number = 1000 * DAY;
        expect(planAssignmentEvents([assignment('a', 'c1', 0, false, '正文')], 60, false, now).length)
          .assertEqual(0);
      });

      it('勾了"已完成不提醒"时跳过已提交的；未勾时照登记', 0, () => {
        const now: number = 1000 * DAY;
        const items: Assignment[] = [
          assignment('done', 'c1', now + DAY, true, '正文'),
          assignment('todo', 'c1', now + DAY, false, '正文')
        ];
        expect(planAssignmentEvents(items, 60, false, now).length).assertEqual(2);
        const withFlag: CalendarEventPlan[] = planAssignmentEvents(items, 60, true, now);
        expect(withFlag.length).assertEqual(1);
        expect(withFlag[0].key).assertEqual(`${EVENT_KEY_PREFIX}c1:todo`);
      });

      it('按开始时间升序、同一刻按标识定序（结果稳定）', 0, () => {
        const now: number = 1000 * DAY;
        const plans: CalendarEventPlan[] = planAssignmentEvents([
          assignment('b', 'c1', now + 2 * DAY, false, '正文'),
          assignment('a', 'c1', now + DAY, false, '正文')
        ], 60, false, now);
        expect(plans[0].key).assertEqual(`${EVENT_KEY_PREFIX}c1:a`);
        expect(plans[1].key).assertEqual(`${EVENT_KEY_PREFIX}c1:b`);
      });

      it('标题为「作业名 - 课程名」，描述是截止时刻与摘要（不含界面文案）', 0, () => {
        const due: number = new Date(2026, 8, 29, 23, 59).getTime();
        const item: Assignment = assignment('a', 'c1', due, false, '第一章  习题\n第二题');
        expect(eventTitleOf(item)).assertEqual('作业a - 课程c1');
        expect(eventDescriptionOf(item)).assertEqual('2026-09-29 23:59\n第一章 习题 第二题');
        // 日程标识带前缀，据此判定"这条日程是不是本应用写的"
        expect(eventKeyOf(item).startsWith(EVENT_KEY_PREFIX)).assertTrue();
      });

      it('描述为空时只给截止时刻', 0, () => {
        const due: number = new Date(2026, 8, 29, 23, 59).getTime();
        expect(eventDescriptionOf(assignment('a', 'c1', due, false, '')))
          .assertEqual('2026-09-29 23:59');
      });

      it('不同课程的同一作业 id 不互相顶替（标识是复合键）', 0, () => {
        const now: number = 1000 * DAY;
        const plans: CalendarEventPlan[] = planAssignmentEvents([
          assignment('same', 'c1', now + DAY, false, '正文'),
          assignment('same', 'c2', now + DAY, false, '正文')
        ], 60, false, now);
        expect(plans.length).assertEqual(2);
        expect(plans[0].key === plans[1].key).assertFalse();
      });

      it('默认提前量是 24 小时（对齐上游）', 0, () => {
        expect(DEFAULT_OFFSET_MINUTES).assertEqual(1440);
      });
    });

    describe('与日历现状的差量对齐', () => {

      const now: number = 1000 * DAY;

      it('日历里没有的 → 新增', 0, () => {
        const plan: CalendarAlignPlan = alignCalendarEvents(desiredOf(now + DAY, 60, now), [], EVENT_KEY_PREFIX);
        expect(plan.toAdd.length).assertEqual(1);
        expect(plan.toDelete.length).assertEqual(0);
      });

      it('不在期望里的（已截止 / 已勾选完成不提醒）→ 删除', 0, () => {
        const plan: CalendarAlignPlan = alignCalendarEvents([],
          [existing(7, `${EVENT_KEY_PREFIX}c1:a`, '作业a - 课程c1', now + DAY, 30)], EVENT_KEY_PREFIX);
        expect(plan.toAdd.length).assertEqual(0);
        expect(plan.toDelete.length).assertEqual(1);
        expect(plan.toDelete[0]).assertEqual(7);
      });

      it('截止时间被改（开始时间变了）→ 删了重建', 0, () => {
        const desired: CalendarEventPlan[] = desiredOf(now + 2 * DAY, 60, now);
        const plan: CalendarAlignPlan = alignCalendarEvents(desired,
          [existing(9, desired[0].key, desired[0].title, now + DAY, 30)], EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(1);
        expect(plan.toDelete[0]).assertEqual(9);
        expect(plan.toAdd.length).assertEqual(1);
      });

      it('提前量被改（提醒分钟数变了）→ 删了重建', 0, () => {
        const desired: CalendarEventPlan[] = desiredOf(now + 2 * DAY, 120, now);
        const stale: ExistingCalendarEvent[] =
          [existing(4, desired[0].key, desired[0].title, desired[0].startTime, 1440 - 30)];
        const plan: CalendarAlignPlan = alignCalendarEvents(desired, stale, EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(1);
        expect(plan.toAdd.length).assertEqual(1);
      });

      it('完全相同 → 空计划（同一份数据连跑两次必须幂等）', 0, () => {
        const desired: CalendarEventPlan[] = desiredOf(now + DAY, 60, now);
        const current: ExistingCalendarEvent[] =
          [existing(3, desired[0].key, desired[0].title, desired[0].startTime, desired[0].reminderMinutes)];
        expect(alignCalendarEvents(desired, current, EVENT_KEY_PREFIX).isEmpty()).assertTrue();
      });

      it('"没有提醒"也算一种状态：期望有提醒而现状没有 → 重建', 0, () => {
        const desired: CalendarEventPlan[] = desiredOf(now + DAY, 60, now);
        const current: ExistingCalendarEvent[] =
          [existing(5, desired[0].key, desired[0].title, desired[0].startTime, null)];
        const plan: CalendarAlignPlan = alignCalendarEvents(desired, current, EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(1);
        expect(plan.toAdd.length).assertEqual(1);
      });

      it('没有账户标识的日程（不是本应用写的）不动', 0, () => {
        const desired: CalendarEventPlan[] = desiredOf(now + DAY, 60, now);
        const plan: CalendarAlignPlan =
          alignCalendarEvents(desired, [existing(11, '', '用户自己加的日程', now + HOUR, null)], EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(0);
        expect(plan.toAdd.length).assertEqual(1);
      });

      it('同一标识在日历里出现两次 → 删掉后来者，自愈成一条', 0, () => {
        const desired: CalendarEventPlan[] = desiredOf(now + DAY, 60, now);
        const duplicated: ExistingCalendarEvent[] = [
          existing(1, desired[0].key, desired[0].title, desired[0].startTime, desired[0].reminderMinutes),
          existing(2, desired[0].key, desired[0].title, desired[0].startTime, desired[0].reminderMinutes)
        ];
        const plan: CalendarAlignPlan = alignCalendarEvents(desired, duplicated, EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(1);
        expect(plan.toDelete[0]).assertEqual(2);
        expect(plan.toAdd.length).assertEqual(0);
      });

      it('前缀作用域：课程日程与无前缀的日程都不动（不认识的绝不删）', 0, () => {
        const desired: CalendarEventPlan[] = desiredOf(now + DAY, 60, now);
        const otherFamily: ExistingCalendarEvent[] = [
          // 课程日程（另一族）：期望里没有它，但**不属于**作业族，不许删
          existing(31, 'learnx-course:202609290800:高等数学', '高等数学', now + DAY, 60),
          // 没有标识的（用户自己加的）：同样不碰
          existing(32, '', '用户自己加的日程', now + HOUR, null)
        ];
        const plan: CalendarAlignPlan =
          alignCalendarEvents(desired, otherFamily, EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(0);
        expect(plan.toAdd.length).assertEqual(1);
      });

      it('期望为空时只清本族（作业族清空不碰课程日程）', 0, () => {
        const existingEvents: ExistingCalendarEvent[] = [
          existing(41, `${EVENT_KEY_PREFIX}c1:a`, '作业a - 课程c1', now + DAY, 30),
          existing(42, 'learnx-course:202609290800:高等数学', '高等数学', now + DAY, 60)
        ];
        const plan: CalendarAlignPlan =
          alignCalendarEvents([], existingEvents, EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(1);
        expect(plan.toDelete[0]).assertEqual(41);
      });

      it('取消条数截断后，未过期作业一条都不漏', 0, () => {
        // 上一版按代理提醒的"API ≤25 上限 30 条"做了截断；日历日程没有这个限制，
        // 人为截断只会造成"某些作业不写进日历"的隐形缺口
        const items: Assignment[] = [];
        for (let i: number = 1; i <= 40; i++) {
          items.push(assignment(`a${i}`, 'c1', now + i * DAY, false, '正文'));
        }
        expect(planAssignmentEvents(items, 60, false, now).length).assertEqual(40);
      });
    });
  });
}
