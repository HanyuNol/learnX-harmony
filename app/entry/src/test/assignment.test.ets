/**
 * 作业纯逻辑的单元测试（assignments spec §5 第 1–5 项里不依赖端点的那部分）。
 *
 * 端点相关的解析在 `parseAssignment.test` 里另测。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  Assignment, AssignmentFilter, isPast, filterAssignments, sortAssignments
} from '../main/ets/model/assignment';

const DAY: number = 24 * 60 * 60 * 1000;

function assignment(id: string, deadlineTime: number, submitted: boolean): Assignment {
  return new Assignment(id, `base-${id}`, 'c1', '课程甲', '张老师', `作业${id}`, '正文',
    'raw', deadlineTime, '', submitted, false, false, '', '', '', '', '', '',
    [], true);
}

export default function assignmentTest() {
  describe('assignment', () => {

    describe('是否已截止', () => {

      it('严格大于才算过期（正好等于截止时间不算）', 0, () => {
        const deadline: number = 1000;
        expect(isPast(deadline, deadline)).assertFalse();
        expect(isPast(deadline, deadline + 1)).assertTrue();
        expect(isPast(deadline, deadline - 1)).assertFalse();
      });

      it('时间未知（0）时不得说它过期', 0, () => {
        expect(isPast(0, 999999)).assertFalse();
      });
    });

    describe('筛选', () => {

      it('未完成/已完成按 submitted 分流', 0, () => {
        const items: Assignment[] = [assignment('a', 1, false), assignment('b', 2, true)];
        expect(filterAssignments(items, AssignmentFilter.UNFINISHED).length).assertEqual(1);
        expect(filterAssignments(items, AssignmentFilter.UNFINISHED)[0].id).assertEqual('a');
        expect(filterAssignments(items, AssignmentFilter.FINISHED)[0].id).assertEqual('b');
      });
    });

    describe('排序', () => {

      it('未截止在前（按截止升序）、已截止在后（按截止降序）、时间未知的在最后', 0, () => {
        const now: number = 100 * DAY;
        const sorted: Assignment[] = sortAssignments([
          assignment('overdue-old', now - 10 * DAY, false),
          assignment('upcoming-late', now + 5 * DAY, false),
          assignment('unknown', 0, false),
          assignment('upcoming-soon', now + 1 * DAY, false),
          assignment('overdue-recent', now - 1 * DAY, false)],
          now);

        expect(sorted[0].id).assertEqual('upcoming-soon');
        expect(sorted[1].id).assertEqual('upcoming-late');
        expect(sorted[2].id).assertEqual('overdue-recent');
        expect(sorted[3].id).assertEqual('overdue-old');
        expect(sorted[4].id).assertEqual('unknown');
      });
    });
  });
}
