/**
 * 会话失效处置策略的单元测试（2026-09-28 代码审查 🟡 M2 的回归防护）。
 *
 * 钉住一条**次序**：**"是否已有在途重登"必须先判**，它比"有没有凭据"更优先。
 * 原先的写法是"先看凭据"，而重登流程会清空凭据字段——并发的其它请求在那段窗口里
 * 会误判成"无凭据可重登"而直接失败，不会加入已经在进行的重登。
 */

import { describe, expect, it } from '@ohos/hypium';
import { ReloginPlan, reloginPlan } from '../main/ets/network/sessionPolicy';

export default function sessionPolicyTest() {
  describe('sessionPolicy', () => {

    it('已有在途重登时一律"加入它"——哪怕此刻凭据字段已被重登流程清空', 0, () => {
      expect(reloginPlan(true, true)).assertEqual(ReloginPlan.JOIN_IN_FLIGHT);
      // 这条是关键回归：凭据为 null 但已有在途，仍必须去等它，不能报失败
      expect(reloginPlan(true, false)).assertEqual(ReloginPlan.JOIN_IN_FLIGHT);
    });

    it('没有在途且有凭据才发起重登', 0, () => {
      expect(reloginPlan(false, true)).assertEqual(ReloginPlan.START);
    });

    it('既没有在途也没有凭据才认输（由页面引导重新登录）', 0, () => {
      expect(reloginPlan(false, false)).assertEqual(ReloginPlan.FAIL);
    });
  });
}
