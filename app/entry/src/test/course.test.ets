/**
 * 课程列表与显示名的单元测试。
 *
 * 覆盖 courses spec §5 第 1–5 项。这些是纯逻辑，故意与平台调用分开——
 * 课程端点要会话，设备验收必须登录后才能跑。
 *
 * 说明：本模块的测试与实现一并写成，**没有单独跑一次"红"**，改以更强的
 * **变异验证**兜底（改坏实现必须让用例转 Failure），并在提交信息里记明。
 */

import { describe, expect, it } from '@ohos/hypium';
import { Course, isCourseListStale, sortCourses } from '../main/ets/model/course';
import { decodeHtmlEntities, parseCourseList } from '../main/ets/network/parseCourse';

/** 上游真实字段名的最小样本（学生形态） */
const ONE_COURSE: string = '{"message":"success","resultList":[{' +
  '"wlkcid":"2024-2025-1-001","zywkcm":"高职英语 A&amp;B","kcm":"英语","ywkcm":"English",' +
  '"jsm":"张老师","jsh":"2019001","kch":"001","kxh":1}]}';

export default function courseTest() {
  describe('course', () => {

    describe('显示名回退', () => {

      it('有 name 时用 name', 0, () => {
        expect(new Course('id1', '操作系统', '操作系统', 'OS', '张老师', '001', '001', 1)
          .displayName()).assertEqual('操作系统');
      });

      it('name 为空时退回中文名，再为空退回课程号', 0, () => {
        expect(new Course('id1', '', '操作系统', 'OS', '张老师', '001', '001', 1)
          .displayName()).assertEqual('操作系统');
        expect(new Course('id1', '', '', 'OS', '张老师', '001', '001', 1)
          .displayName()).assertEqual('001');
      });

      it('三者皆空时给可识别的占位，而不是空串', 0, () => {
        // 注意课程号也算显示名的一级回退，故这里必须把 name/chineseName/courseNumber 三者都置空
        const name: string = new Course('id1', '', '', '', '张老师', '', '', 1).displayName();
        expect(name.length > 0).assertTrue();
        expect(name).assertEqual('—');
      });
    });

    describe('排序与学期归属', () => {

      it('应按 id 升序排列', 0, () => {
        const sorted: Course[] = sortCourses([
          new Course('c', 'c', '', '', '', '', '', 3),
          new Course('a', 'a', '', '', '', '', '', 1),
          new Course('b', 'b', '', '', '', '', '', 2)]);
        expect(sorted[0].id).assertEqual('a');
        expect(sorted[1].id).assertEqual('b');
        expect(sorted[2].id).assertEqual('c');
      });

      it('请求学期为空时不算过期（空学期不发请求，无需重取）', 0, () => {
        expect(isCourseListStale('2024-2025-1', '')).assertFalse();
      });

      it('已加载学期与请求学期不同时视为过期', 0, () => {
        expect(isCourseListStale('2024-2025-1', '2025-2026-1')).assertTrue();
        expect(isCourseListStale('2024-2025-1', '2024-2025-1')).assertFalse();
      });

      it('尚未加载过（空串）时应视为过期，从而触发一次加载', 0, () => {
        expect(isCourseListStale('', '2024-2025-1')).assertTrue();
      });
    });

    describe('HTML 实体解码', () => {

      it('应解出常见命名实体与数字实体', 0, () => {
        expect(decodeHtmlEntities('A&amp;B')).assertEqual('A&B');
        expect(decodeHtmlEntities('&lt;x&gt;')).assertEqual('<x>');
        expect(decodeHtmlEntities('&quot;q&quot;')).assertEqual('"q"');
        expect(decodeHtmlEntities('&#39;')).assertEqual('\'');
        expect(decodeHtmlEntities('&#65;&#x42;')).assertEqual('AB');
        expect(decodeHtmlEntities('&nbsp;')).assertEqual('\u00A0');
      });

      it('不认识或残缺的实体应原样保留，不吞字符', 0, () => {
        expect(decodeHtmlEntities('a &unknown; b')).assertEqual('a &unknown; b');
        expect(decodeHtmlEntities('100% & 50%')).assertEqual('100% & 50%');
        expect(decodeHtmlEntities('&amp')).assertEqual('&amp');
      });
    });

    describe('课程列表响应解析', () => {

      it('应把上游字段映射为课程', 0, () => {
        const courses: Course[] = parseCourseList(ONE_COURSE);
        expect(courses.length).assertEqual(1);
        expect(courses[0].id).assertEqual('2024-2025-1-001');
        expect(courses[0].teacherName).assertEqual('张老师');
        expect(courses[0].courseNumber).assertEqual('001');
        expect(courses[0].displayName()).assertEqual('高职英语 A&B');
      });

      it('空列表是合法结果，应返回空数组而不是抛错', 0, () => {
        expect(parseCourseList('{"message":"success","resultList":[]}').length).assertEqual(0);
      });

      it('非 success、resultList 非数组、坏 JSON 都应抛错', 0, () => {
        const bad: string[] = [
          '{"message":"fail","resultList":[]}',
          '{"message":"success","resultList":{}}',
          '{"message":"success"}',
          '[',
        ];
        bad.forEach((body: string) => {
          let threw: boolean = false;
          try {
            parseCourseList(body);
          } catch (err) {
            threw = true;
          }
          expect(threw).assertTrue();
        });
      });

      it('字段缺失的项不应让整批解析失败，显示名按回退规则处理', 0, () => {
        const body: string = '{"message":"success","resultList":[{"wlkcid":"x1","kch":"002"}]}';
        const courses: Course[] = parseCourseList(body);
        expect(courses.length).assertEqual(1);
        expect(courses[0].id).assertEqual('x1');
        expect(courses[0].teacherName).assertEqual('');
        expect(courses[0].displayName()).assertEqual('002');
      });
    });
  });
}
