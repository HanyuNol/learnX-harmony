/**
 * 作业**响应解析**的单元测试（assignments spec §5 第 1–2 项）。
 *
 * 这里钉住的是"哪些判据是从端点来的、哪些是从字段来的"——尤其**完成状态由端点注入**：
 * 响应里根本没有 `submitted`/`graded` 字段，谁把它们当成响应字段去读，就会永远读到 false。
 */

import { describe, expect, it } from '@ohos/hypium';
import { Assignment } from '../main/ets/model/assignment';
import {
  parseAssignmentDescription, parseAssignmentList, parseDeadlineTimestamp
} from '../main/ets/network/parseAssignment';

/** 一个成功信封（容器是 `object.aaData`，与上游一致） */
function envelope(data: string): string {
  return `{"result":"success","object":{"aaData":${data}}}`;
}

const ONE_ITEM: string = '[{"xszyid":"s1","zyid":"b1","bt":"标题&amp;副标题","jzsj":"2025-05-03 23:59",'
  + '"bjjzsj":"2025-05-10 23:59","sfbj":"是","zywcfs":2,"zytjfs":0,"scsj":"2025-05-01 10:00",'
  + '"cj":-100,"jsm":"李老师","pynr":"写得不错","pysj":"2025-05-06 09:00"}]';

function throws(fn: () => void): boolean {
  try {
    fn();
    return false;
  } catch (err) {
    return true;
  }
}

function first(body: string, submitted: boolean, graded: boolean): Assignment {
  const items: Assignment[] = parseAssignmentList(body, 'c1', '课程甲', '张老师', submitted, graded);
  return items[0];
}

export default function parseAssignmentTest() {
  describe('parseAssignment', () => {

    describe('完成状态由端点注入', () => {

      it('未提交端点 → false/false', 0, () => {
        const item: Assignment = first(envelope(ONE_ITEM), false, false);
        expect(item.submitted).assertFalse();
        expect(item.graded).assertFalse();
      });

      it('已提交端点 → true/false', 0, () => {
        const item: Assignment = first(envelope(ONE_ITEM), true, false);
        expect(item.submitted).assertTrue();
        expect(item.graded).assertFalse();
      });

      it('已评分端点 → true/true（同一份响应，状态不同）', 0, () => {
        const item: Assignment = first(envelope(ONE_ITEM), true, true);
        expect(item.submitted).assertTrue();
        expect(item.graded).assertTrue();
      });
    });

    describe('字段映射', () => {

      it('标题解 HTML 实体，时间原串保留并解析成时间戳', 0, () => {
        const item: Assignment = first(envelope(ONE_ITEM), false, false);
        expect(item.title).assertEqual('标题&副标题');
        expect(item.baseId).assertEqual('b1');
        expect(item.deadline).assertEqual('2025-05-03 23:59');
        expect(item.deadlineTime > 0).assertTrue();
        expect(item.lateDeadline).assertEqual('2025-05-10 23:59');
      });

      it('中文字面量判据：sfbj=是 记为补交', 0, () => {
        expect(first(envelope(ONE_ITEM), false, false).isLateSubmission).assertTrue();
        const notLate: string = '[{"xszyid":"s2","zyid":"b2","jzsj":"2025-05-03 23:59","sfbj":"否"}]';
        expect(first(envelope(notLate), false, false).isLateSubmission).assertFalse();
      });

      it('完成/提交方式按数字映射', 0, () => {
        const item: Assignment = first(envelope(ONE_ITEM), false, false);
        expect(item.completionType).assertEqual(2);
        expect(item.submissionType).assertEqual(0);
      });

      it('cj 为负数代码 → 走等级名；为正数 → 走分数', 0, () => {
        const graded: Assignment = first(envelope(ONE_ITEM), false, false);
        expect(graded.gradeLevel).assertEqual('checked');
        expect(graded.grade).assertEqual('');

        const scored: string = '[{"xszyid":"s3","zyid":"b3","jzsj":"2025-05-03 23:59","cj":87}]';
        const byScore: Assignment = first(envelope(scored), false, false);
        expect(byScore.grade).assertEqual('87');
        expect(byScore.gradeLevel).assertEqual('');
      });

      it('缺字段退让成空串，不整批失败', 0, () => {
        const sparse: string = '[{"xszyid":"s4","zyid":"b4"}]';
        const item: Assignment = first(envelope(sparse), false, false);
        expect(item.id).assertEqual('s4');
        expect(item.deadline).assertEqual('');
        expect(item.deadlineTime).assertEqual(0);
        expect(item.graderName).assertEqual('');
      });

      it('空数组是合法结果', 0, () => {
        expect(parseAssignmentList(envelope('[]'), 'c1', '课程甲', '张老师', false, false).length)
          .assertEqual(0);
      });
    });

    describe('结构不符必须抛出（不静默成空）', () => {

      it('坏 JSON / 缺 success / aaData 不是数组 → 抛出', 0, () => {
        expect(throws(() => parseAssignmentList('not json', 'c1', '甲', '师', false, false)))
          .assertTrue();
        expect(throws(() => parseAssignmentList('{"result":"fail","object":{"aaData":[]}}',
          'c1', '甲', '师', false, false))).assertTrue();
        expect(throws(() => parseAssignmentList('{"result":"success","object":{}}',
          'c1', '甲', '师', false, false))).assertTrue();
      });
    });

    describe('详情正文与截止时间解析', () => {

      it('详情 body 取 msg 并解实体；非 success 抛出', 0, () => {
        expect(parseAssignmentDescription('{"result":"success","msg":"A &amp; B"}'))
          .assertEqual('A & B');
        expect(throws(() => parseAssignmentDescription('{"result":"fail"}'))).assertTrue();
      });

      it('截止时间接受几种常见形态；解析不出退 0（不猜）', 0, () => {
        expect(parseDeadlineTimestamp('2025-05-03 23:59') > 0).assertTrue();
        expect(parseDeadlineTimestamp('2025/05/03 23:59') > 0).assertTrue();
        expect(parseDeadlineTimestamp('2025-05-03T23:59:00') > 0).assertTrue();
        expect(parseDeadlineTimestamp('')).assertEqual(0);
        expect(parseDeadlineTimestamp('待定')).assertEqual(0);
      });
    });
  });
}
