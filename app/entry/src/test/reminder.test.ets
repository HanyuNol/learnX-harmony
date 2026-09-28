/**
 * 作业提醒纯逻辑的单元测试（reminders spec §5 第 1–6 项）。
 *
 * 钉住三件最容易错的事：**提醒时刻已过去的不该登记**（过去时刻系统不接受）、
 * **"该撤哪些"必须包含"时刻变了"这一种**（否则老师改截止时间后提醒会停在旧时刻）、
 * **月份从 1 起算**（这批字段直接喂给系统的 `LocalDateTime`，差一月就是差一个月）。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  Assignment, AssignmentAttachments, HomeworkCompletionType, HomeworkSubmissionType
} from '../main/ets/model/assignment';
import {
  DEFAULT_OFFSET_MINUTES, MAX_REMINDERS, ReminderEntry, ReminderMoment, ReminderPlan, ReminderRecord,
  momentOf, parseOffsetMinutes, planReminders, reconcile, reminderContentOf, reminderKeyOf,
  reminderTitleOf, sameMoment
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

/** 断言用：把"期望的那一条"从计划里取出来（取不到就抛，避免用手写索引） */
function entryOf(entries: ReminderEntry[], key: string): ReminderEntry {
  for (const entry of entries) {
    if (entry.key === key) {
      return entry;
    }
  }
  throw new Error(`期望集合里应有 ${key}`);
}

/** 差量对齐用例共用：由作业算出"期望登记的提醒"（与实现同一条纯函数，`now` 固定便于断言） */
function desiredOf(items: Assignment[], offsetMinutes: number, now: number): ReminderEntry[] {
  return planReminders(items, offsetMinutes, false, now);
}

function record(id: number, key: string, moment: ReminderMoment): ReminderRecord {
  return new ReminderRecord(id, key, moment);
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

    describe('作业 → 提醒条目', () => {

      it('只收未过期的作业（严格晚于当前时刻）', 0, () => {
        const now: number = 1000 * DAY;
        const items: Assignment[] = [
          assignment('a', 'c1', now + DAY, false, '正文'),
          assignment('b', 'c1', now - DAY, false, '正文'),
          assignment('c', 'c1', now, false, '正文')
        ];
        const entries: ReminderEntry[] = planReminders(items, 60, false, now);
        expect(entries.length).assertEqual(1);
        expect(entries[0].key).assertEqual('c1:a');
      });

      it('提醒时刻 = 截止 − 提前量；提前量已把时刻推到过去的不登记', 0, () => {
        const now: number = 1000 * DAY;
        const items: Assignment[] = [
          // 还有 2 小时截止，提前 1 小时提醒 → 时刻在未来，登记
          assignment('a', 'c1', now + 2 * HOUR, false, '正文'),
          // 还有 30 分钟截止，提前 1 小时提醒 → 时刻已过去，不登记
          assignment('b', 'c1', now + 30 * MINUTE, false, '正文')
        ];
        const entries: ReminderEntry[] = planReminders(items, 60, false, now);
        expect(entries.length).assertEqual(1);
        expect(entries[0].triggerTime).assertEqual(now + 2 * HOUR - HOUR);
      });

      it('提前量为 0 时在截止时刻提醒（仍属未来才登记）', 0, () => {
        const now: number = 1000 * DAY;
        const entries: ReminderEntry[] = planReminders(
          [assignment('a', 'c1', now + 10 * MINUTE, false, '正文')], 0, false, now);
        expect(entries.length).assertEqual(1);
        expect(entries[0].triggerTime).assertEqual(now + 10 * MINUTE);
      });

      it('截止时间解析不出（0）的不登记', 0, () => {
        const now: number = 1000 * DAY;
        expect(planReminders([assignment('a', 'c1', 0, false, '正文')], 60, false, now).length)
          .assertEqual(0);
      });

      it('勾了"已完成不提醒"时跳过已提交的；未勾时照登记', 0, () => {
        const now: number = 1000 * DAY;
        const items: Assignment[] = [
          assignment('done', 'c1', now + DAY, true, '正文'),
          assignment('todo', 'c1', now + DAY, false, '正文')
        ];
        const withoutFlag: ReminderEntry[] = planReminders(items, 60, false, now);
        expect(withoutFlag.length).assertEqual(2);

        const withFlag: ReminderEntry[] = planReminders(items, 60, true, now);
        expect(withFlag.length).assertEqual(1);
        expect(withFlag[0].key).assertEqual('c1:todo');
      });

      it('标题为「作业名 - 课程名」，正文是截止时刻与摘要（不含界面文案）', 0, () => {
        const due: number = new Date(2026, 8, 29, 23, 59).getTime();
        const item: Assignment = assignment('a', 'c1', due, false, '第一章  习题\n第二题');
        expect(reminderTitleOf(item)).assertEqual('作业a - 课程c1');
        expect(reminderContentOf(item)).assertEqual('2026-09-29 23:59\n第一章 习题 第二题');
      });

      it('正文为空时只给截止时刻', 0, () => {
        const due: number = new Date(2026, 8, 29, 23, 59).getTime();
        expect(reminderContentOf(assignment('a', 'c1', due, false, '')))
          .assertEqual('2026-09-29 23:59');
      });

      it('去重键是「课程 id:作业 id」——不同课程的同一作业 id 不互相顶替', 0, () => {
        const now: number = 1000 * DAY;
        const items: Assignment[] = [
          assignment('same', 'c1', now + DAY, false, '正文'),
          assignment('same', 'c2', now + DAY, false, '正文')
        ];
        const entries: ReminderEntry[] = planReminders(items, 60, false, now);
        expect(entries.length).assertEqual(2);
        expect(reminderKeyOf(items[0])).assertEqual('c1:same');
        expect(reminderKeyOf(items[1])).assertEqual('c2:same');
      });
    });

    describe('条数上限', () => {

      it('超过上限时按触发时刻从近到远截断', 0, () => {
        const now: number = 1000 * DAY;
        const items: Assignment[] = [];
        // 截止时间越往后越远，故意用倒序填充，确认排序不是"按输入顺序"；
        // 加一小时是为了让 i=1 那条的提醒时刻（截止 − 60 分钟）仍在未来
        for (let i: number = MAX_REMINDERS + 5; i >= 1; i--) {
          items.push(assignment(`a${i}`, 'c1', now + (i + 1) * HOUR, false, '正文'));
        }
        const entries: ReminderEntry[] = planReminders(items, 60, false, now);
        expect(entries.length).assertEqual(MAX_REMINDERS);
        // 最近的一条是 2 小时后截止（提醒在 1 小时后）的那个
        expect(entries[0].key).assertEqual('c1:a1');
        // 触发时刻单调不减
        let previous: number = 0;
        for (const entry of entries) {
          expect(entry.triggerTime >= previous).assertTrue();
          previous = entry.triggerTime;
        }
      });
    });

    describe('时间戳 → 提醒时刻', () => {

      it('按本地时区取年月日时分，月份从 1 起算', 0, () => {
        const moment: ReminderMoment = momentOf(new Date(2026, 0, 5, 8, 30).getTime());
        expect(moment.year).assertEqual(2026);
        expect(moment.month).assertEqual(1);
        expect(moment.day).assertEqual(5);
        expect(moment.hour).assertEqual(8);
        expect(moment.minute).assertEqual(30);
      });

      it('跨月与跨年边界（12 月 31 日 23:59）', 0, () => {
        const moment: ReminderMoment = momentOf(new Date(2025, 11, 31, 23, 59).getTime());
        expect(moment.year).assertEqual(2025);
        expect(moment.month).assertEqual(12);
        expect(moment.day).assertEqual(31);
        expect(moment.hour).assertEqual(23);
        expect(moment.minute).assertEqual(59);
      });

      it('同一刻的判定只看这五个字段', 0, () => {
        const left: ReminderMoment = new ReminderMoment(2026, 1, 1, 0, 0);
        expect(sameMoment(left, new ReminderMoment(2026, 1, 1, 0, 0))).assertTrue();
        expect(sameMoment(left, new ReminderMoment(2026, 1, 1, 0, 1))).assertFalse();
        expect(sameMoment(left, new ReminderMoment(2026, 2, 1, 0, 0))).assertFalse();
      });
    });

    describe('差量对齐', () => {

      const now: number = 1000 * DAY;

      it('系统里没有的 → 登记', 0, () => {
        const desired: ReminderEntry[] = desiredOf([assignment('a', 'c1', now + DAY, false, '正文')], 60, now);
        const plan: ReminderPlan = reconcile(desired, []);
        expect(plan.toPublish.length).assertEqual(1);
        expect(plan.toCancel.length).assertEqual(0);
      });

      it('不在期望集合里的（已截止 / 已勾选完成不提醒）→ 撤销', 0, () => {
        const plan: ReminderPlan = reconcile([], [record(7, 'c1:a', momentOf(now + DAY))]);
        expect(plan.toPublish.length).assertEqual(0);
        expect(plan.toCancel.length).assertEqual(1);
        expect(plan.toCancel[0]).assertEqual(7);
      });

      it('时刻变了（老师改了截止时间）→ 撤销并重登', 0, () => {
        const desired: ReminderEntry[] = desiredOf([assignment('a', 'c1', now + 2 * DAY, false, '正文')], 60, now);
        const stale: ReminderRecord[] = [record(9, 'c1:a', momentOf(now + DAY))];
        const plan: ReminderPlan = reconcile(desired, stale);
        expect(plan.toCancel.length).assertEqual(1);
        expect(plan.toCancel[0]).assertEqual(9);
        expect(plan.toPublish.length).assertEqual(1);
      });

      it('完全相同 → 空计划（同一份数据连跑两次必须是幂等的）', 0, () => {
        const desired: ReminderEntry[] = desiredOf([assignment('a', 'c1', now + DAY, false, '正文')], 60, now);
        const current: ReminderRecord[] = [record(3, desired[0].key, desired[0].moment())];
        const plan: ReminderPlan = reconcile(desired, current);
        expect(plan.isEmpty()).assertTrue();
      });

      it('没有去重键的（不是本功能登记的）不动', 0, () => {
        const desired: ReminderEntry[] = desiredOf([assignment('a', 'c1', now + DAY, false, '正文')], 60, now);
        const plan: ReminderPlan = reconcile(desired, [record(11, '', momentOf(now + HOUR))]);
        expect(plan.toCancel.length).assertEqual(0);
        expect(plan.toPublish.length).assertEqual(1);
      });

      it('同一个键在系统里出现两次 → 撤掉后来者，自愈成一条', 0, () => {
        const desired: ReminderEntry[] = desiredOf([assignment('a', 'c1', now + DAY, false, '正文')], 60, now);
        const duplicated: ReminderRecord[] = [
          record(1, desired[0].key, desired[0].moment()),
          record(2, desired[0].key, desired[0].moment())
        ];
        const plan: ReminderPlan = reconcile(desired, duplicated);
        expect(plan.toCancel.length).assertEqual(1);
        expect(plan.toCancel[0]).assertEqual(2);
        expect(plan.toPublish.length).assertEqual(0);
      });

      it('默认提前量是 24 小时（对齐上游）', 0, () => {
        expect(DEFAULT_OFFSET_MINUTES).assertEqual(1440);
      });
    });
  });
}
