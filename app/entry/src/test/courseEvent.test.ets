/**
 * 课表纯逻辑的单元测试（course-calendar spec §5 第 1–5 项）。
 *
 * 钉住三件最容易错的事：**时间按北京时间换算**（设备可能在别的时区，用本地 `Date` 构造会错）、
 * **不存在的日期要能识别**（`Date.UTC` 会把 20260230 静默进位成 3 月 2 日）、
 * **课程日程与作业日程互不越界**（前缀作用域，否则一次课程同步会把作业日程全删掉）。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  COURSE_KEY_PREFIX, CourseSession, beijingTimeOf, courseEventKeyOf, planCourseEvents
} from '../main/ets/model/courseEvent';
import {
  CalendarAlignPlan, CalendarEventPlan, EVENT_KEY_PREFIX, ExistingCalendarEvent, alignCalendarEvents
} from '../main/ets/model/reminder';
import { ScheduleParseResult, parseScheduleJsonp } from '../main/ets/network/parseSchedule';

const HOUR: number = 60 * 60 * 1000;
const DAY: number = 24 * HOUR;

function session(courseName: string, date: string, startTime: string, endTime: string,
                 location: string): CourseSession {
  return new CourseSession(courseName, location, date, startTime, endTime);
}

/** 上游 `thu-learn-lib` 映射的原始字段名（`nr/nq/kssj/jssj/dd`） */
function jsonpOf(rows: string): string {
  return `thu_learn_lib_jsonp_extractor(${rows})`;
}

/** 解析是否抛错（"坏输入都该抛"的用例共用；不可测的布尔计数写法容易漏） */
function throwsOn(body: string): boolean {
  try {
    parseScheduleJsonp(body);
    return false;
  } catch (err) {
    return true;
  }
}

/** 两族互不越界的用例共用：一条作业日程 */
function existingAssignment(eventId: number, key: string, title: string, startTime: number): ExistingCalendarEvent {
  return new ExistingCalendarEvent(eventId, key, title, '', startTime, 30);
}

export default function courseEventTest() {
  describe('courseEvent', () => {

    describe('北京时间换算', () => {

      it('按北京时间换算，与运行设备的时区无关', 0, () => {
        // 2026-09-29 08:00（北京）= 2026-09-29T00:00Z
        const expected: number = Date.UTC(2026, 8, 29, 0, 0);
        expect(beijingTimeOf('20260929', '0800')).assertEqual(expected);
        // 同一天的 23:59（北京）= 15:59Z
        expect(beijingTimeOf('20260929', '2359')).assertEqual(Date.UTC(2026, 8, 29, 15, 59));
      });

      it('时间字段的几种形态都认（0800 / 800 / 08:00 / 080000）', 0, () => {
        const expected: number = Date.UTC(2026, 8, 29, 0, 0);
        expect(beijingTimeOf('20260929', '0800')).assertEqual(expected);
        expect(beijingTimeOf('20260929', '800')).assertEqual(expected);
        expect(beijingTimeOf('20260929', '08:00')).assertEqual(expected);
        expect(beijingTimeOf('20260929', '080000')).assertEqual(expected);
      });

      it('不存在的日期与非法时刻解析不出（返回 0，不猜）', 0, () => {
        expect(beijingTimeOf('20260230', '0800')).assertEqual(0);
        expect(beijingTimeOf('20261332', '0800')).assertEqual(0);
        expect(beijingTimeOf('20260929', '2560')).assertEqual(0);
        expect(beijingTimeOf('20260929', '')).assertEqual(0);
        expect(beijingTimeOf('2026', '0800')).assertEqual(0);
        expect(beijingTimeOf('', '')).assertEqual(0);
      });
    });

    describe('课表条目 → 日程计划', () => {

      const now: number = Date.UTC(2026, 8, 1, 0, 0);

      it('标题是课程名、起止是这次课的时间、地点照给', 0, () => {
        const plans: CalendarEventPlan[] = planCourseEvents(
          [session('高等数学', '20260929', '0800', '0950', '六教6A101')], 15, now);
        expect(plans.length).assertEqual(1);
        expect(plans[0].title).assertEqual('高等数学');
        expect(plans[0].description).assertEqual('六教6A101');
        expect(plans[0].location).assertEqual('六教6A101');
        expect(plans[0].startTime).assertEqual(beijingTimeOf('20260929', '0800'));
        expect(plans[0].endTime).assertEqual(beijingTimeOf('20260929', '0950'));
        expect(plans[0].reminderMinutes).assertEqual(15);
      });

      it('上课提醒关着时不给提醒（null），但日程照写', 0, () => {
        const plans: CalendarEventPlan[] = planCourseEvents(
          [session('高等数学', '20260929', '0800', '0950', '')], null, now);
        expect(plans.length).assertEqual(1);
        expect(plans[0].reminderMinutes).assertEqual(null);
      });

      it('已经结束的课不写（结束时刻不晚于当前）', 0, () => {
        const after: number = beijingTimeOf('20260929', '1000');
        const plans: CalendarEventPlan[] = planCourseEvents(
          [session('高等数学', '20260929', '0800', '0950', '')], 15, after);
        expect(plans.length).assertEqual(0);
      });

      it('日期或时间解析不出的条目跳过（不整批失败）', 0, () => {
        const plans: CalendarEventPlan[] = planCourseEvents([
          session('高等数学', '20260929', '0800', '0950', ''),
          session('坏数据', '2026092', '0800', '0950', ''),
          session('坏时间', '20260930', '9999', '0950', '')
        ], 15, now);
        expect(plans.length).assertEqual(1);
      });

      it('按开始时间升序排列（结果稳定）', 0, () => {
        const plans: CalendarEventPlan[] = planCourseEvents([
          session('下午的课', '20260929', '1400', '1550', ''),
          session('上午的课', '20260929', '0800', '0950', '')
        ], 15, now);
        expect(plans[0].title).assertEqual('上午的课');
        expect(plans[1].title).assertEqual('下午的课');
      });

      it('键带课程前缀，且同一门课同一天同一时刻只算一条', 0, () => {
        const first: CourseSession = session('高等数学', '20260929', '0800', '0950', '');
        expect(courseEventKeyOf(first).startsWith(COURSE_KEY_PREFIX)).assertTrue();
        expect(courseEventKeyOf(first)).assertEqual(courseEventKeyOf(
          session('高等数学', '20260929', '0800', '1005', '')));
        // 课程前缀与作业前缀不重叠：分属两族，对齐时互不越界
        expect(courseEventKeyOf(first).startsWith(EVENT_KEY_PREFIX)).assertFalse();
      });
    });

    describe('JSONP 解析', () => {

      it('取出括号内的数组并映射字段', 0, () => {
        const body: string = jsonpOf(
          '[{"nr":"高等数学","nq":"20260929","kssj":"0800","jssj":"0950","dd":"六教6A101","fl":"1"}]');
        const result: ScheduleParseResult = parseScheduleJsonp(body);
        expect(result.rawCount).assertEqual(1);
        expect(result.sessions.length).assertEqual(1);
        expect(result.sessions[0].courseName).assertEqual('高等数学');
        expect(result.sessions[0].date).assertEqual('20260929');
        expect(result.sessions[0].location).assertEqual('六教6A101');
      });

      it('空数组是合法结果', 0, () => {
        const result: ScheduleParseResult = parseScheduleJsonp(jsonpOf('[]'));
        expect(result.sessions.length).assertEqual(0);
        expect(result.rawCount).assertEqual(0);
      });

      it('缺字段的条目跳过，但原始条数如实带出（用于发现"在悄悄丢数据"）', 0, () => {
        const body: string = jsonpOf(
          '[{"nr":"高等数学","nq":"20260929","kssj":"0800","jssj":"0950"},'
          + '{"nr":"缺时间","nq":"20260929","kssj":"","jssj":""},'
          + '{"nr":"","nq":"20260929","kssj":"0800","jssj":"0950"}]');
        const result: ScheduleParseResult = parseScheduleJsonp(body);
        expect(result.rawCount).assertEqual(3);
        expect(result.sessions.length).assertEqual(1);
      });

      it('不是 JSONP / 括号内不是数组 / 内层不是合法 JSON 都抛"解析失败"', 0, () => {
        expect(throwsOn('no-parens-at-all')).assertTrue();
        expect(throwsOn('cb([]')).assertTrue();
        expect(throwsOn('cb({})')).assertTrue();
        expect(throwsOn('cb([{')).assertTrue();
      });
    });

    describe('课程与作业两族互不越界', () => {
      const now: number = Date.UTC(2026, 8, 1, 0, 0);

      it('课程对齐不碰作业日程（前缀作用域的反向验收）', 0, () => {
        const desired: CalendarEventPlan[] = planCourseEvents(
          [session('高等数学', '20260929', '0800', '0950', '')], 15, now);
        const existing: ExistingCalendarEvent[] = [
          existingAssignment(1, `${EVENT_KEY_PREFIX}c1:a`, '作业a - 课程c1', now + DAY)
        ];
        const plan: CalendarAlignPlan =
          alignCalendarEvents(desired, existing, COURSE_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(0);
        expect(plan.toAdd.length).assertEqual(1);
      });

      it('作业对齐不碰课程日程', 0, () => {
        // 日历里只有课程日程，作业侧期望为空：只该删"作业族"的，课程族一条都不许删
        const courseEvents: ExistingCalendarEvent[] = [
          new ExistingCalendarEvent(51, `${COURSE_KEY_PREFIX}202609290800:高等数学`,
            '高等数学', '六教6A101', now + DAY, 15)
        ];
        const plan: CalendarAlignPlan = alignCalendarEvents([], courseEvents, EVENT_KEY_PREFIX);
        expect(plan.toDelete.length).assertEqual(0);
      });
    });
  });
}
