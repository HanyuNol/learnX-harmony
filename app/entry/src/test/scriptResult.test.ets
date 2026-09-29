/**
 * `runJavaScript` 回传值解码的单元测试。
 *
 * 钉住那个**真实踩到的坑**：ArkWeb 对脚本结果做了一次 JSON 编码，
 * 字符串回传会多出一对引号；不解开就会 `NaN`（高度静默丢失）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { unwrapScriptResult } from '../main/ets/common/scriptResult';

export default function scriptResultTest() {
  describe('scriptResult', () => {

    it('带引号的字符串回传：脱掉 JSON 引号（设备实测形态）', 0, () => {
      expect(unwrapScriptResult('"74|2"')).assertEqual('74|2');
    });

    it('内含转义字符时按 JSON 规则还原', 0, () => {
      expect(unwrapScriptResult('"换\\n行"')).assertEqual('换\n行');
    });

    it('不是 JSON 就按原样用（对端变了也不至于拿到空串）', 0, () => {
      expect(unwrapScriptResult('74|2')).assertEqual('74|2');
    });

    it('数字回传同样解码成字符串', 0, () => {
      expect(unwrapScriptResult('42')).assertEqual('42');
    });

    it('空串不崩', 0, () => {
      expect(unwrapScriptResult('')).assertEqual('');
    });
  });
}
