/**
 * 全局搜索的纯逻辑测试（search spec §5 第 1–3 项）。
 *
 * 钉住三件容易错的事：**空关键词不能等于"全命中"**、**四段顺序固定**、
 * **课程内搜索不得混进别的课程**。
 */

import { describe, expect, it } from '@ohos/hypium';
import { Course } from '../main/ets/model/course';
import { LearnFile } from '../main/ets/model/file';
import { Notice } from '../main/ets/model/notice';
import { Assignment, AssignmentAttachments } from '../main/ets/model/assignment';
import {
  SearchKind, SearchResults, normalizeQuery, searchAll, searchCourses
} from '../main/ets/model/search';

function course(id: string, name: string, teacher: string): Course {
  return new Course(id, name, name, '', teacher, '', '', 0);
}

function file(id: string, courseId: string, title: string): LearnFile {
  return new LearnFile(id, `f${id}`, courseId, '课程甲', '张老师', title, '描述',
    '1MB', 1048576, '2025-05-01 10:00', 1, 'pdf', '课件', false, false);
}

function notice(id: string, courseId: string, title: string): Notice {
  return new Notice(id, courseId, '课程甲', title, '正文', false, false, 1, '发布者', '', '');
}

function assignment(id: string, courseId: string, title: string): Assignment {
  return new Assignment(id, `b${id}`, courseId, '课程甲', '张老师', title, '正文',
    '2025-05-01 10:00', 1, '', false, false, false, 1, 2, '', '', '', '', '', '',
    AssignmentAttachments.empty(), true);
}

export default function searchTest() {
  describe('search', () => {

    it('关键词归一化：去空白 + 小写；空串表示还没输入', 0, () => {
      expect(normalizeQuery('  BiO  ')).assertEqual('bio');
      expect(normalizeQuery('   ')).assertEqual('');
    });

    it('空关键词不命中任何东西（否则等于"全命中"）', 0, () => {
      const results: SearchResults = searchAll([course('c1', '生物化学', '李珍')],
        [file('f1', 'c1', '讲义')], [notice('n1', 'c1', '通知')], [assignment('a1', 'c1', '作业')],
        '', '');
      expect(results.isEmpty()).assertTrue();
      expect(results.total()).assertEqual(0);
    });

    it('大小写不敏感，且标题/描述/课程名/教师名任一命中即算', 0, () => {
      const courses: Course[] = [course('c1', 'Biochemistry', '李珍'), course('c2', '大学物理', '李渭')];
      expect(searchCourses(courses, 'bio').length).assertEqual(1);
      expect(searchCourses(courses, 'BIO').length).assertEqual(1);
      // 教师名也参与匹配
      expect(searchCourses(courses, '李渭').length).assertEqual(1);
      expect(searchCourses(courses, '不存在').length).assertEqual(0);
    });

    it('四类各自命中，且顺序固定为 课程→文件→通知→作业', 0, () => {
      const results: SearchResults = searchAll(
        [course('c1', '线性代数', '王老师')],
        [file('f1', 'c1', '线性代数讲义')],
        [notice('n1', 'c1', '线性代数调课')],
        [assignment('a1', 'c1', '线性代数作业')],
        '线性代数', '');
      expect(results.courses.length).assertEqual(1);
      expect(results.files.length).assertEqual(1);
      expect(results.notices.length).assertEqual(1);
      expect(results.assignments.length).assertEqual(1);
      expect(results.total()).assertEqual(4);
      expect(results.isEmpty()).assertFalse();
      // 顺序由页面按 COURSE→FILE→NOTICE→ASSIGNMENT 渲染，这里钉住枚举取值本身
      expect(SearchKind.COURSE).assertEqual('course');
      expect(SearchKind.FILE).assertEqual('file');
      expect(SearchKind.NOTICE).assertEqual('notice');
      expect(SearchKind.ASSIGNMENT).assertEqual('assignment');
    });

    it('课程内搜索：只出现该课程的条目，且不返回课程结果', 0, () => {
      const results: SearchResults = searchAll(
        [course('c1', '大学物理B(2)', '李渭')],
        [file('f1', 'c1', '第五次课'), file('f2', 'c2', '第五次课')],
        [notice('n1', 'c1', '第五次课调课'), notice('n2', 'c2', '第五次课调课')],
        [assignment('a1', 'c1', '第五次课作业'), assignment('a2', 'c2', '第五次课作业')],
        '第五次课', 'c1');
      expect(results.courses.length).assertEqual(0);
      expect(results.files.length).assertEqual(1);
      expect(results.files[0].id).assertEqual('f1');
      expect(results.notices.length).assertEqual(1);
      expect(results.notices[0].id).assertEqual('n1');
      expect(results.assignments.length).assertEqual(1);
      expect(results.assignments[0].id).assertEqual('a1');
    });
  });
}
