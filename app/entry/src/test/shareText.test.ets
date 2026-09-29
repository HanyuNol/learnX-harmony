/**
 * 分享文本组装规则的单元测试（FR-23 / share spec）。
 *
 * 钉住三件事：**缺一半不留空行**、**连续空行压成一个**、**超长截断**。
 */

import { describe, expect, it } from '@ohos/hypium';
import { composeShareText } from '../main/ets/common/shareText';

export default function shareTextTest() {
  describe('shareText', () => {

    it('标题与正文之间空一行', 0, () => {
      expect(composeShareText('换教室', '这周改到 6A-201')).assertEqual('换教室\n\n这周改到 6A-201');
    });

    it('只有标题或只有正文时不留下孤零零的空行', 0, () => {
      expect(composeShareText('只有标题', '')).assertEqual('只有标题');
      expect(composeShareText('   ', '只有正文')).assertEqual('只有正文');
    });

    it('两者都空 → 空串（调用方据此不发分享）', 0, () => {
      expect(composeShareText('', '')).assertEqual('');
      expect(composeShareText('  \n ', '\n\t')).assertEqual('');
    });

    it('首尾空白去掉、连续空行压成一个', 0, () => {
      expect(composeShareText('  标题  ', '\n\n正文一\n\n\n\n正文二\n\n'))
        .assertEqual('标题\n\n正文一\n\n正文二');
    });

    it('行尾空白与 CRLF 也清掉（正文从 HTML 剥出来常带这些）', 0, () => {
      expect(composeShareText('标题', '甲  \r\n乙')).assertEqual('标题\n\n甲\n乙');
    });

    it('超长截断并加省略号（系统分享 IPC 有体积上限）', 0, () => {
      const long: string = '字'.repeat(5000);
      const out: string = composeShareText('标题', long);
      expect(out.length).assertEqual(4000 + 1);
      expect(out.endsWith('…')).assertTrue();
    });

    it('刚好在上限内不动它', 0, () => {
      const body: string = '字'.repeat(3000);
      expect(composeShareText('', body).length).assertEqual(3000);
    });
  });
}
