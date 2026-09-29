/**
 * 最小 Markdown → HTML 的单元测试（FR-28 更新日志页）。
 *
 * 两个重点：**支持的构造要按预期出标签**、**不认识的构造不能被当成标签吃进去**
 * （尖括号一律先转义）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { markdownToHtml } from '../main/ets/common/markdown';

export default function markdownTest() {
  describe('markdown', () => {

    it('标题按级数出 h1..h6', 0, () => {
      expect(markdownToHtml('# 一')).assertEqual('<h1>一</h1>');
      expect(markdownToHtml('### 三')).assertEqual('<h3>三</h3>');
    });

    it('无序列表成 ul/li，一层缩进成嵌套 ul', 0, () => {
      const html: string = markdownToHtml('- 甲\n- 乙\n  - 乙一\n- 丙');
      expect(html).assertEqual('<ul><li>甲</li><li>乙</li><ul><li>乙一</li></ul><li>丙</li></ul>');
    });

    it('空行收束列表，标题不会掉进列表里', 0, () => {
      const html: string = markdownToHtml('- 甲\n\n## 标题');
      expect(html).assertEqual('<ul><li>甲</li></ul><h2>标题</h2>');
    });

    it('加粗、行内代码、链接', 0, () => {
      expect(markdownToHtml('**粗**与`码`'))
        .assertEqual('<p><strong>粗</strong>与<code>码</code></p>');
      expect(markdownToHtml('[上游](https://github.com/x)'))
        .assertEqual('<p><a href="https://github.com/x">上游</a></p>');
    });

    it('非 http(s) 的链接不当链接（与清洗器的协议白名单一致）', 0, () => {
      const html: string = markdownToHtml('[x](javascript:alert(1))');
      expect(html.includes('<a ')).assertFalse();
    });

    it('引用成 blockquote，分隔线成 hr', 0, () => {
      expect(markdownToHtml('> 注\n> 续')).assertEqual('<blockquote><p>注</p><p>续</p></blockquote>');
      expect(markdownToHtml('---')).assertEqual('<hr>');
    });

    it('围栏代码块内部原样保留（只转义），块内语法不解析', 0, () => {
      const html: string = markdownToHtml('```\n# 不是标题\n- 不是列表\n```');
      expect(html).assertEqual('<pre><code># 不是标题\n- 不是列表\n</code></pre>');
    });

    it('尖括号先转义：Markdown 里的 HTML 标签只会显示为文本', 0, () => {
      const html: string = markdownToHtml('<script>alert(1)</script>');
      expect(html).assertEqual('<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>');
    });

    it('与号也转义（避免源码里的实体被二次解释）', 0, () => {
      expect(markdownToHtml('a & b')).assertEqual('<p>a &amp; b</p>');
    });

    it('未闭合的代码围栏也要收尾，不留断标签', 0, () => {
      expect(markdownToHtml('```\n漏了结尾')).assertEqual('<pre><code>漏了结尾\n</code></pre>');
    });

    it('空输入返回空串', 0, () => {
      expect(markdownToHtml('')).assertEqual('');
    });
  });
}
