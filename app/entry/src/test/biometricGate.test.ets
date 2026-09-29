/**
 * 恢复闸门判据的单元测试（FR-24 / biometric-login spec §3.3）。
 *
 * 逐行钉住那张表：**"没有凭据不恢复"、"设备不可用要照旧恢复"、"验证不过不恢复"**。
 * 中间那条最要紧——写错会让所有无生物识别的设备登不进去，而开发机上根本看不出来。
 */

import { describe, expect, it } from '@ohos/hypium';
import { RESTORE_NONE, RESTORE_SILENT, RESTORE_UNLOCKED, decideRestore }
  from '../main/ets/common/biometricGate';

export default function biometricGateTest() {
  describe('biometricGate', () => {

    it('没有凭据 → 不恢复（不看设备能不能生物识别）', 0, () => {
      expect(decideRestore(false, true, true)).assertEqual(RESTORE_NONE);
      expect(decideRestore(false, false, false)).assertEqual(RESTORE_NONE);
    });

    it('设备不可生物识别 → **照旧**静默恢复（老设备/模拟器不能被挡住）', 0, () => {
      // 没发起验证，authPassed 传什么都不能影响结论
      expect(decideRestore(true, false, false)).assertEqual(RESTORE_SILENT);
      expect(decideRestore(true, false, true)).assertEqual(RESTORE_SILENT);
    });

    it('可生物识别且验证通过 → 恢复', 0, () => {
      expect(decideRestore(true, true, true)).assertEqual(RESTORE_UNLOCKED);
    });

    it('可生物识别但验证未通过（取消/失败）→ 不恢复，回退密码登录', 0, () => {
      expect(decideRestore(true, true, false)).assertEqual(RESTORE_NONE);
    });
  });
}
