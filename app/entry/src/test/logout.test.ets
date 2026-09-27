/**
 * 登出判定的单元测试。
 *
 * 覆盖代码审查 R-02 的不变量：**只有本地凭据被真正清除，才算登出成功**。
 * 此前 `AuthStore.logout` 把异常吞成一条 WARN 后无条件转 `LOGGED_OUT`，
 * 于是"凭据清除失败、界面却显示已登出"——下次启动还会用残留凭据静默重新登录。
 *
 * 这里测的是判定本身（纯逻辑）；平台调用（Asset Store 删除失败）无法在宿主侧构造，
 * 故不在此覆盖——那正是本项目要求"纯逻辑与平台调用分离"的原因。
 */

import { describe, expect, it } from '@ohos/hypium';
import { LogoutResult } from '../main/ets/model/auth';
import { LogoutOutcome, logoutOutcome } from '../main/ets/common/logout';
import { TextKeys } from '../main/ets/common/texts';

export default function logoutTest() {
  describe('logout', () => {

    it('本地凭据已清除时应判定为登出成功，且无需提示文案', 0, () => {
      const outcome: LogoutOutcome = logoutOutcome(new LogoutResult(true));
      expect(outcome.loggedOut).assertTrue();
      expect(outcome.errorTextKey).assertEqual(TextKeys.NONE);
    });

    it('本地凭据未清除时不得判定为登出成功，且必须给出用户可见文案', 0, () => {
      const outcome: LogoutOutcome = logoutOutcome(new LogoutResult(false));
      expect(outcome.loggedOut).assertFalse();
      expect(outcome.errorTextKey).assertEqual(TextKeys.ERR_LOGOUT_INCOMPLETE);
    });

    it('失败文案键必须是已知键，避免拼错后静默不渲染', 0, () => {
      const key: string = logoutOutcome(new LogoutResult(false)).errorTextKey;
      expect(key.length > 0).assertTrue();
      expect(/^[a-z][a-z0-9_]*$/.test(key)).assertTrue();
    });

    it('判定结果与入参一一对应，不得把失败当成功', 0, () => {
      // 同一判定连续调用应稳定（无隐藏状态）
      expect(logoutOutcome(new LogoutResult(false)).loggedOut).assertFalse();
      expect(logoutOutcome(new LogoutResult(true)).loggedOut).assertTrue();
    });
  });
}
