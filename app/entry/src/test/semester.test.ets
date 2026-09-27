/**
 * 学期解析与决策的单元测试。
 *
 * 覆盖 semester spec §5 第 1–5 项：id 解析、响应解析、当前学期决策、排序。
 * 这些都是**纯逻辑**，故意与平台调用分开——两个学期端点都要会话，设备验收
 * 必须登录后才能跑，而这里把"结构解析对不对、决策错不错"先钉死。
 */

import { describe, expect, it } from '@ohos/hypium';
import { Semester, SemesterType, decideCurrentSemester, parseSemester, sortSemesterIds } from '../main/ets/model/semester';
import { TextKeys, textKeyOfSemesterType } from '../main/ets/common/texts';
import { parseCurrentSemesterId, parseSemesterIdList } from '../main/ets/network/parseSemester';

export default function semesterTest() {
  describe('semester', () => {

    describe('id 解析', () => {

      it('1/2/3 段应解析为秋季/春季/夏季', 0, () => {
        expect(parseSemester('2024-2025-1').type).assertEqual(SemesterType.FALL);
        expect(parseSemester('2024-2025-2').type).assertEqual(SemesterType.SPRING);
        expect(parseSemester('2024-2025-3').type).assertEqual(SemesterType.SUMMER);
        expect(parseSemester('2024-2025-1').yearsText).assertEqual('2024-2025');
        expect(parseSemester('2024-2025-1').valid).assertTrue();
      });

      it('年份段合法但学期序号不认识时：形态算识别，只把季节退让为未知', 0, () => {
        // 序号非 1/2/3（含非数字）都属这一类：三段且年份合规 ⇒ valid=true，
        // 年份串照常可用，只有季节认不出。与"形态异常"是两回事。
        const unrecognized: string[] = ['2024-2025-9', '2024-2025-x'];
        unrecognized.forEach((id: string) => {
          const parsed: Semester = parseSemester(id);
          expect(parsed.valid).assertTrue();
          expect(parsed.type).assertEqual(SemesterType.UNKNOWN);
          expect(parsed.yearsText).assertEqual('2024-2025');
        });
      });

      it('形态异常时应退让为未知并保留原串可显示，而不是崩溃', 0, () => {
        // 形态异常 = 段数不足 / 年份非 4 位 / 空串（序号不认识不算，见上一条用例）
        const bad: string[] = ['', '2024', '2024-2025', '24-25-1', '2024-20255-1', 'abcd-efgh-1'];
        bad.forEach((id: string) => {
          const parsed: Semester = parseSemester(id);
          expect(parsed.valid).assertFalse();
          expect(parsed.type).assertEqual(SemesterType.UNKNOWN);
          expect(parsed.yearsText).assertEqual(id);
        });
      });

      it('季节类型应映射到对应文案键', 0, () => {
        expect(textKeyOfSemesterType(SemesterType.FALL)).assertEqual(TextKeys.SEMESTER_SEASON_FALL);
        expect(textKeyOfSemesterType(SemesterType.SPRING)).assertEqual(TextKeys.SEMESTER_SEASON_SPRING);
        expect(textKeyOfSemesterType(SemesterType.SUMMER)).assertEqual(TextKeys.SEMESTER_SEASON_SUMMER);
        expect(textKeyOfSemesterType(SemesterType.UNKNOWN)).assertEqual(TextKeys.SEMESTER_SEASON_UNKNOWN);
      });
    });

    describe('排序', () => {

      it('应按最新在前排序（同学年内春季晚于秋季）', 0, () => {
        const sorted: string[] = sortSemesterIds(
          ['2023-2024-2', '2025-2026-1', '2024-2025-1', '2024-2025-2']);
        expect(sorted[0]).assertEqual('2025-2026-1');
        expect(sorted[1]).assertEqual('2024-2025-2');
        expect(sorted[2]).assertEqual('2024-2025-1');
        expect(sorted[3]).assertEqual('2023-2024-2');
      });

      it('形态异常的 id 应置后，且不破坏其余顺序', 0, () => {
        const sorted: string[] = sortSemesterIds(['2023-2024-2', 'bad-id', '2025-2026-1']);
        expect(sorted[0]).assertEqual('2025-2026-1');
        expect(sorted[1]).assertEqual('2023-2024-2');
        expect(sorted[2]).assertEqual('bad-id');
      });
    });

    describe('当前学期决策', () => {

      it('本地已存过时不得被服务端值覆盖', 0, () => {
        expect(decideCurrentSemester('2023-2024-2', '2025-2026-1')).assertEqual('2023-2024-2');
      });

      it('本地为空时应采用服务端值', 0, () => {
        expect(decideCurrentSemester('', '2025-2026-1')).assertEqual('2025-2026-1');
      });

      it('两者都空时应保持空（下游据此不发请求）', 0, () => {
        expect(decideCurrentSemester('', '')).assertEqual('');
      });
    });

    describe('响应解析', () => {

      it('学期列表应过滤 null 只留字符串', 0, () => {
        const ids: string[] = parseSemesterIdList('["2024-2025-1",null,"2023-2024-2"]');
        expect(ids.length).assertEqual(2);
        expect(ids[0]).assertEqual('2024-2025-1');
        expect(ids[1]).assertEqual('2023-2024-2');
      });

      it('空数组是合法结果，应返回空列表而不是抛错', 0, () => {
        expect(parseSemesterIdList('[]').length).assertEqual(0);
      });

      it('非数组或坏 JSON 应抛错（由上层归为解析失败）', 0, () => {
        let threw: boolean = false;
        try {
          parseSemesterIdList('{"message":"success"}');
        } catch (err) {
          threw = true;
        }
        expect(threw).assertTrue();

        let threwBad: boolean = false;
        try {
          parseSemesterIdList('[');
        } catch (err) {
          threwBad = true;
        }
        expect(threwBad).assertTrue();
      });

      it('当前学期应取 result.id', 0, () => {
        const body: string = '{"message":"success","result":{"id":"2024-2025-1","xnxq":"2024-2025-1"}}';
        expect(parseCurrentSemesterId(body)).assertEqual('2024-2025-1');
      });

      it('非 success 或缺 id 应抛错', 0, () => {
        let threwFail: boolean = false;
        try {
          parseCurrentSemesterId('{"message":"fail","result":{"id":"2024-2025-1"}}');
        } catch (err) {
          threwFail = true;
        }
        expect(threwFail).assertTrue();

        let threwNoId: boolean = false;
        try {
          parseCurrentSemesterId('{"message":"success","result":{}}');
        } catch (err) {
          threwNoId = true;
        }
        expect(threwNoId).assertTrue();
      });
    });
  });
}
