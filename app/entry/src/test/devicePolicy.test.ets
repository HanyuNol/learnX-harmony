/**
 * 设备策略判断的单元测试（审查 m12：策略原先夹在 native 适配层里，宿主侧测不到）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { supportsFolderSelectionOn } from '../main/ets/common/devicePolicy';

export default function devicePolicyTest() {
  describe('devicePolicy', () => {

    it('只有 2in1 支持选文件夹（官方文档：selectMode=FOLDER 仅 2-in-1）', 0, () => {
      expect(supportsFolderSelectionOn('2in1')).assertTrue();
    });

    it('手机/平板/其它类型都不支持（手机上会退化成"选文件"）', 0, () => {
      expect(supportsFolderSelectionOn('phone')).assertFalse();
      expect(supportsFolderSelectionOn('tablet')).assertFalse();
      expect(supportsFolderSelectionOn('')).assertFalse();
      expect(supportsFolderSelectionOn('2IN1')).assertFalse();
    });
  });
}
