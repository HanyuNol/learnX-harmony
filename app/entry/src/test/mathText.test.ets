/**
 * 公式文本纯逻辑的单元测试（ADR-0012 / rich-text spec）。
 *
 * 钉住两件事：**判据取宽**（`$`/`\(`/`\[` 任一出现就算有公式，宁可多注入一次脚本，
 * 也不要漏渲染）与 **`\mbox`→`\text` 只做这一处替换**（猜多了比不做更糟）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { containsMath, delimitersPresent, normalizeMathText } from '../main/ets/common/mathText';

export default function mathTextTest() {
  describe('mathText', () => {

    describe('有没有公式', () => {

      it('三种定界符任一出现即算有公式', 0, () => {
        expect(containsMath('价格 $5')).assertTrue();
        expect(containsMath('行内 \\(x^2\\)')).assertTrue();
        expect(containsMath('块级 \\[x\\]')).assertTrue();
        expect(containsMath('$$\\int_0^1$$')).assertTrue();
      });

      it('纯文本与空串不算有公式', 0, () => {
        expect(containsMath('')).assertFalse();
        expect(containsMath('这个课换到六教 6A-201')).assertFalse();
      });

      it('报出用到的定界符（诊断"是不是定界符没匹配上"）', 0, () => {
        const found: string = delimitersPresent('a $$b$$ c \(d\)');
        expect(found.length > 0).assertTrue();
        expect(delimitersPresent('没有公式')).assertEqual('');
      });
    });

    describe('渲染前的文本规整', () => {

      it('\\mbox 换成 \\text（KaTeX 不支持前者，而上游为真实数据专门替换过）', 0, () => {
        expect(normalizeMathText('\\mbox{甲} + \\mbox{乙}')).assertEqual('\\text{甲} + \\text{乙}');
      });

      it('只动 mbox，别的一概不碰（猜错了比不做更糟）', 0, () => {
        const raw: string = '\\frac{1}{2} 与 \\text{已经是对的} 与 $5';
        expect(normalizeMathText(raw)).assertEqual(raw);
      });

      it('没有 mbox 时原样返回', 0, () => {
        expect(normalizeMathText('普通正文')).assertEqual('普通正文');
      });
    });
  });
}
