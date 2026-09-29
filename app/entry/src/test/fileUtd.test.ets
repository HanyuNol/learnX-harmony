/**
 * 扩展名 → UTD 查表的单元测试。
 *
 * 钉住两件事：**命中已确认的 UTD 常量**、**认不出来一律退让 `general.file`**
 * （编造 UTD 会让系统分享面板报"记录类型不支持"）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { utdOfExtension } from '../main/ets/common/fileUtd';

export default function fileUtdTest() {
  describe('fileUtd', () => {

    it('课件常见类型命中各自的 UTD', 0, () => {
      expect(utdOfExtension('pdf')).assertEqual('com.adobe.pdf');
      expect(utdOfExtension('doc')).assertEqual('com.microsoft.word.doc');
      expect(utdOfExtension('png')).assertEqual('general.png');
      expect(utdOfExtension('jpg')).assertEqual('general.jpeg');
      expect(utdOfExtension('zip')).assertEqual('general.zip-archive');
      expect(utdOfExtension('mp4')).assertEqual('general.video');
      expect(utdOfExtension('txt')).assertEqual('general.plain-text');
    });

    it('大小写不敏感、可带前导点（与 mime 查表同一口径）', 0, () => {
      expect(utdOfExtension('PDF')).assertEqual('com.adobe.pdf');
      expect(utdOfExtension('.Pdf')).assertEqual('com.adobe.pdf');
      expect(utdOfExtension('  .JPG ')).assertEqual('general.jpeg');
    });

    it('认不出来的退让成 general.file（不猜具体类型）', 0, () => {
      expect(utdOfExtension('docx')).assertEqual('general.file');
      expect(utdOfExtension('pptx')).assertEqual('general.file');
      expect(utdOfExtension('xyz')).assertEqual('general.file');
      expect(utdOfExtension('')).assertEqual('general.file');
      expect(utdOfExtension('   ')).assertEqual('general.file');
      expect(utdOfExtension('.')).assertEqual('general.file');
    });

    it('没有具体 UTD 的归到上位类型', 0, () => {
      expect(utdOfExtension('webp')).assertEqual('general.image');
      expect(utdOfExtension('7z')).assertEqual('general.archive');
    });
  });
}
