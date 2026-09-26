/**
 * 日志脱敏的单元测试。
 *
 * 覆盖 spec §5 第 5 项的"凭据不出现在日志"这一半：
 * 断言脱敏函数在任何输入下都不会原样返回敏感值。
 *
 * 注意：这只证明**脱敏机制本身**正确；"程序里没有别处绕过它打印凭据"
 * 需要静态检查与实机日志抽查，属设备侧验收（见 spec §5 第 11 项）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { redact } from '../main/ets/common/logger';

export default function loggerTest() {
  describe('logger.redact', () => {

    it('空串应返回空串', 0, () => {
      expect(redact('')).assertEqual('');
    });

    it('极短值应全部打码，不泄漏任何字符', 0, () => {
      expect(redact('a')).assertEqual('*');
      expect(redact('ab')).assertEqual('**');
      expect(redact('a') === 'a').assertFalse();
    });

    it('长值应保留首字符、长度不变', 0, () => {
      const secret: string = '2019000000';
      const masked: string = redact(secret);
      expect(masked.length).assertEqual(secret.length);
      expect(masked.startsWith('2')).assertTrue();
    });

    it('脱敏结果不得包含原值', 0, () => {
      const secrets: string[] = ['1', 'ab', 'password123', '2019000000', '!@#$%^&*'];
      for (const secret of secrets) {
        const masked: string = redact(secret);
        // 长度 > 2 时首字符按设计保留，故只断言剩余部分不出现
        if (secret.length > 2) {
          expect(masked.includes(secret.substring(1))).assertFalse();
        }
        expect(masked === secret).assertFalse();
      }
    });
  });
}
