/**
 * 服务端 HTML 清洗器的单元测试（pdf-preview/富文本 spec §5 的安全用例）。
 *
 * 这是**安全敏感**的一块：`SECURITY.md` §3 要求不得整体信任服务端 HTML。
 * 故这里的用例按"攻击面"穷举：脚本标签、事件属性、`javascript:`（含加空白/换行的绕过）、
 * 危险 `data:` 类型、被丢标签的嵌套、重复属性（后者覆盖前者）、未闭合的 `<`。
 */

import { describe, expect, it } from '@ohos/hypium';
import { absolutize, sanitizeHtml } from '../main/ets/common/sanitizeHtml';

const BASE: string = 'https://learn.tsinghua.edu.cn';

export default function sanitizeHtmlTest() {
  describe('sanitizeHtml', () => {

    describe('脚本与危险标签', () => {

      it('script 标签连同内容一起丢掉', 0, () => {
        expect(sanitizeHtml('<p>前</p><script>alert(1)</script><p>后</p>', BASE))
          .assertEqual('<p>前</p><p>后</p>');
      });

      it('大写与带属性的 script 同样丢掉', 0, () => {
        expect(sanitizeHtml('<SCRIPT type="text/javascript">evil()</SCRIPT>', BASE)).assertEqual('');
      });

      it('iframe / object / embed / svg / style 连同内容丢掉', 0, () => {
        const inputs: string[] = [
          '<iframe src="https://evil.test"></iframe>',
          '<object data="x"></object>',
          '<embed src="x">',
          '<svg><script>alert(1)</script></svg>',
          '<style>body{display:none}</style>'
        ];
        for (const raw of inputs) {
          expect(sanitizeHtml(raw, BASE)).assertEqual('');
        }
      });

      it('被丢标签**嵌套**时只丢那一棵子树，兄弟节点保留', 0, () => {
        expect(sanitizeHtml('<div>保留<script>丢掉<b>也不留</b></script>保留</div>', BASE))
          .assertEqual('<div>保留保留</div>');
      });

      it('注释与 doctype 丢掉', 0, () => {
        expect(sanitizeHtml('<!DOCTYPE html><!-- 注释 --><p>正文</p>', BASE)).assertEqual('<p>正文</p>');
      });
    });

    describe('事件属性与样式', () => {

      it('on* 事件属性一律丢（img 的 onerror 是典型）', 0, () => {
        expect(sanitizeHtml('<img src="/a.png" onerror="alert(1)">', BASE))
          .assertEqual(`<img src="${BASE}/a.png">`);
      });

      it('on* 属性大小写混写同样丢', 0, () => {
        expect(sanitizeHtml('<p OnClick="evil()">正文</p>', BASE)).assertEqual('<p>正文</p>');
      });

      it('style / class / id 丢（样式由我们的模板给，不给服务端排版权）', 0, () => {
        expect(sanitizeHtml('<p style="color:red" class="x" id="y">正文</p>', BASE))
          .assertEqual('<p>正文</p>');
      });
    });

    describe('链接与图片地址', () => {

      it('javascript: 链接丢掉 href，文字保留', 0, () => {
        expect(sanitizeHtml('<a href="javascript:alert(1)">点我</a>', BASE))
          .assertEqual('<a rel="noopener noreferrer">点我</a>');
      });

      it('javascript: 里插空白/换行的绕过同样丢掉', 0, () => {
        const inputs: string[] = [
          '<a href="java\nscript:alert(1)">x</a>',
          '<a href="JaVaScRiPt:alert(1)">x</a>',
          '<a href=" javascript:alert(1)">x</a>',
          '<a href="javascript\t:alert(1)">x</a>'
        ];
        for (const raw of inputs) {
          expect(sanitizeHtml(raw, BASE)).assertEqual('<a rel="noopener noreferrer">x</a>');
        }
      });

      it('危险 data: 类型丢掉：text/html 与 image/svg+xml', 0, () => {
        expect(sanitizeHtml('<img src="data:text/html;base64,PHNjcmlwdD4=">', BASE)).assertEqual('<img>');
        expect(sanitizeHtml('<img src="data:image/svg+xml;base64,PHN2Zz4=">', BASE)).assertEqual('<img>');
      });

      it('图片的 data: 位图类型保留（不补 baseUrl）', 0, () => {
        expect(sanitizeHtml('<img src="data:image/png;base64,AAAA">', BASE))
          .assertEqual('<img src="data:image/png;base64,AAAA">');
      });

      it('相对地址按 baseUrl 补成绝对地址（站根 / 同级两种）', 0, () => {
        expect(sanitizeHtml('<img src="/b/x.png">', BASE)).assertEqual(`<img src="${BASE}/b/x.png">`);
        expect(sanitizeHtml('<img src="pics/a.png">', BASE))
          .assertEqual(`<img src="${BASE}/pics/a.png">`);
        expect(sanitizeHtml('<a href="//cdn.test/a">x</a>', BASE))
          .assertEqual('<a href="https://cdn.test/a" rel="noopener noreferrer">x</a>');
      });

      it('http 链接保留并加 rel=noopener', 0, () => {
        expect(sanitizeHtml('<a href="http://example.com/a?b=1&amp;c=2">x</a>', BASE))
          .assertEqual('<a href="http://example.com/a?b=1&amp;c=2" rel="noopener noreferrer">x</a>');
      });

      it('重复属性以**第一次**为准（后者想覆盖成 javascript: 也不行）', 0, () => {
        expect(sanitizeHtml('<a href="https://safe.test" href="javascript:evil()">x</a>', BASE))
          .assertEqual('<a href="https://safe.test" rel="noopener noreferrer">x</a>');
      });

      it('width/height 只接受纯数字（表达式与百分比丢弃）', 0, () => {
        expect(sanitizeHtml('<img src="/a.png" width="320" height="100%">', BASE))
          .assertEqual(`<img src="${BASE}/a.png" width="320">`);
      });
    });

    describe('正文文本与实体', () => {

      it('文本里的 `<` `>` 被转义，`&` 实体原样保留（不双重转义）', 0, () => {
        expect(sanitizeHtml('a < b &amp; c &lt;tag&gt;', BASE))
          .assertEqual('a &lt; b &amp; c &lt;tag&gt;');
      });

      it('未闭合的 `<` 当普通文本，不猜', 0, () => {
        expect(sanitizeHtml('随便 < 一个', BASE)).assertEqual('随便 &lt; 一个');
      });

      it('表外标签丢标签但留文字（不认识的东西不当正文丢）', 0, () => {
        expect(sanitizeHtml('<marquee>跑马灯</marquee>', BASE)).assertEqual('跑马灯');
      });

      it('常见排版标签保留（段落/列表/表格/加粗/换行）', 0, () => {
        const raw: string = '<h2>标题</h2><p>一段<strong>加粗</strong><em>斜体</em><br>换行</p>'
          + '<ul><li>甲</li><li>乙</li></ul><table><tr><td colspan="2">格</td></tr></table>';
        expect(sanitizeHtml(raw, BASE)).assertEqual(raw);
      });

      it('空串与纯文本原样（没有标签时等于转义后的原文）', 0, () => {
        expect(sanitizeHtml('', BASE)).assertEqual('');
        expect(sanitizeHtml('纯文本 1 + 1 = 2', BASE)).assertEqual('纯文本 1 + 1 = 2');
      });
    });

    describe('地址补全', () => {

      it('已是绝对的、锚点、mailto 原样返回', 0, () => {
        expect(absolutize('https://a.test/x', BASE)).assertEqual('https://a.test/x');
        expect(absolutize('#sec', BASE)).assertEqual('#sec');
        expect(absolutize('mailto:a@b.c', BASE)).assertEqual('mailto:a@b.c');
      });

      it('baseUrl 为空时不补全', 0, () => {
        expect(absolutize('/b/x.png', '')).assertEqual('/b/x.png');
      });
    });
  });
}
