/**
 * 作业纯逻辑的单元测试（assignments spec §5 第 1–5 项里不依赖端点的那部分）。
 *
 * 端点相关的解析（信封、字段映射、完成状态注入）也在这里测——它们同样是纯函数。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  Assignment, AssignmentAttachments, AssignmentFilter, HomeworkCompletionType,
  HomeworkSubmissionType, RelativeDeadline, RelativeUnit, formatDateTime, gradeLevelNameOf,
  isPast, filterAssignments, relativeDeadlineOf, sortAssignments
} from '../main/ets/model/assignment';
import { Attachment } from '../main/ets/model/attachment';
import { parseAssignmentAttachments } from '../main/ets/network/parseAssignment';

const DAY: number = 24 * 60 * 60 * 1000;
const HOUR: number = 60 * 60 * 1000;
const MINUTE: number = 60 * 1000;

function assignment(id: string, deadlineTime: number, submitted: boolean): Assignment {
  return new Assignment(id, `base-${id}`, 'c1', '课程甲', '张老师', `作业${id}`, '正文',
    'raw', deadlineTime, '', submitted, false, false,
    HomeworkCompletionType.INDIVIDUAL, HomeworkSubmissionType.WEB_LEARNING, '',
    '', '', '', '', '', AssignmentAttachments.empty(), true);
}

/** 相对时间断言前必须确认非 null（ArkTS 不做流式收窄，先判再取） */
function requireRelative(deadlineTime: number, now: number): RelativeDeadline {
  const relative: RelativeDeadline | null = relativeDeadlineOf(deadlineTime, now);
  if (relative === null) {
    throw new Error('相对时间不应为 null');
  }
  return relative;
}

function requireAttachment(attachment: Attachment | null): Attachment {
  if (attachment === null) {
    throw new Error('该槽位不应为空');
  }
  return attachment;
}

/** 按上游 `div.list.fujian.clearfix` 的结构造的样例（四类附件各一） */
const DETAIL_HTML: string =
  '<div class="list fujian clearfix"><div class="ftitle">' +
  '<a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=101&random=1">作业要求.pdf</a></div>' +
  '<div class="fl"><span class="color1">1.2 MB</span></div></div>' +
  '<div class="list fujian clearfix"><div class="ftitle">' +
  '<a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=202">参考答案.pdf</a></div></div>' +
  '<div class="list fujian clearfix"><div class="fl">' +
  '<a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=303&downloadUrl=%2Fb%2Freal%2F303">我的提交.zip</a></div></div>' +
  '<div class="list fujian clearfix"><div class="ftitle">' +
  '<a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=404"><span>批注</span>.pdf</a></div></div>';

/** 答案那一块是空的（有块、无链接）——用来钉住"后面的类别不前移串位" */
const DETAIL_HTML_EMPTY_ANSWER: string =
  '<div class="list fujian clearfix"><div class="ftitle">' +
  '<a href="/b/x?fileId=101">作业要求.pdf</a></div></div>' +
  '<div class="list fujian clearfix"><div class="ftitle">暂无参考答案</div></div>' +
  '<div class="list fujian clearfix"><div class="fl">' +
  '<a href="/b/x?fileId=303">我的提交.zip</a></div></div>';

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

    describe('相对截止时间', () => {

      it('按跨度选单位：分/时/天/月/年，并向下取整', 0, () => {
        const now: number = 1000 * DAY;
        const inMinutes: RelativeDeadline = requireRelative(now + 30 * MINUTE, now);
        expect(inMinutes.unit).assertEqual(RelativeUnit.MINUTE);
        expect(inMinutes.value).assertEqual(30);

        // 30 小时 → 1 天（向下取整，不夸大剩余时间）
        const inDays: RelativeDeadline = requireRelative(now + 30 * HOUR, now);
        expect(inDays.unit).assertEqual(RelativeUnit.DAY);
        expect(inDays.value).assertEqual(1);

        const inMonths: RelativeDeadline = requireRelative(now + 45 * DAY, now);
        expect(inMonths.unit).assertEqual(RelativeUnit.MONTH);
        expect(inMonths.value).assertEqual(1);

        const inYears: RelativeDeadline = requireRelative(now + 400 * DAY, now);
        expect(inYears.unit).assertEqual(RelativeUnit.YEAR);
        expect(inYears.value).assertEqual(1);
      });

      it('已过截止时标记 past，数量是"过去多久"', 0, () => {
        const now: number = 1000 * DAY;
        const overdue: RelativeDeadline = requireRelative(now - 3 * DAY, now);
        expect(overdue.past).assertTrue();
        expect(overdue.value).assertEqual(3);
        expect(overdue.unit).assertEqual(RelativeUnit.DAY);
      });

      it('正好等于截止时间不算已过（与 isPast 同一口径）', 0, () => {
        const deadline: number = 1234;
        expect(requireRelative(deadline, deadline).past).assertFalse();
      });

      it('时间未知（0）返回 null —— 不猜', 0, () => {
        expect(relativeDeadlineOf(0, 999999) === null).assertTrue();
      });
    });

    describe('绝对时间与评分等级', () => {

      it('时间戳 0 不显示时间', 0, () => {
        expect(formatDateTime(0)).assertEqual('');
      });

      it('时间戳格式化为 YYYY-MM-DD HH:mm', 0, () => {
        // 用本地时间构造，避免时区差异导致断言不稳
        const timestamp: number = new Date(2025, 4, 3, 9, 7, 0).getTime();
        expect(formatDateTime(timestamp)).assertEqual('2025-05-03 09:07');
      });

      it('负数代码映射成等级；正数分数没有等级名', 0, () => {
        expect(gradeLevelNameOf(-100)).assertEqual('checked');
        expect(gradeLevelNameOf(-99)).assertEqual('A+');
        expect(gradeLevelNameOf(-85)).assertEqual('distinction');
        expect(gradeLevelNameOf(-63)).assertEqual('pass');
        expect(gradeLevelNameOf(-50)).assertEqual('incomplete');
        expect(gradeLevelNameOf(87)).assertEqual('');
        expect(gradeLevelNameOf(0)).assertEqual('');
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

    describe('详情页附件解析', () => {

      it('应按位置落入四类槽位，并解出名字与文件 id', 0, () => {
        const files: AssignmentAttachments = parseAssignmentAttachments(DETAIL_HTML);
        const teacher: Attachment = requireAttachment(files.teacher);
        expect(teacher.name).assertEqual('作业要求.pdf');
        expect(teacher.fileId).assertEqual('101');
        expect(requireAttachment(files.answer).name).assertEqual('参考答案.pdf');
        expect(requireAttachment(files.submitted).name).assertEqual('我的提交.zip');
        expect(requireAttachment(files.grade).name).assertEqual('批注.pdf');
        expect(files.hasAny()).assertTrue();
      });

      it('链接里带 downloadUrl 参数时应以它为准（上游那两行的口径）', 0, () => {
        const files: AssignmentAttachments = parseAssignmentAttachments(DETAIL_HTML);
        expect(requireAttachment(files.submitted).downloadUrl.includes('/b/real/303')).assertTrue();
      });

      it('某一类没有附件时该槽位为 null，后面的类别不得前移串位', 0, () => {
        const files: AssignmentAttachments = parseAssignmentAttachments(DETAIL_HTML_EMPTY_ANSWER);
        expect(files.answer === null).assertTrue();
        // 关键：我的提交仍然落在 submitted 槽位，而不是被当成参考答案
        expect(requireAttachment(files.submitted).name).assertEqual('我的提交.zip');
        expect(files.grade === null).assertTrue();
      });

      it('没有附件块的页面应返回四类皆空，而不是抛错', 0, () => {
        expect(parseAssignmentAttachments('<div>没有附件</div>').hasAny()).assertFalse();
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
