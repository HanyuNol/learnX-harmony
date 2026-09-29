# ADR-0012：引入 KaTeX 渲染数学公式，接受正文 Web 开脚本的安全退让

## 状态

已接受（2026-09-29 用户选择，见 PRD FR-22；**实现尚未开始**）

## 背景

PRD FR-22 的原文是"富文本正文渲染与数学公式（**KaTeX**）显示"。本批已把前半段落地：
服务端 HTML 经白名单清洗后在沙箱 Web 渲染（`docs/specs/rich-text.md`），**公式部分当时留作待定**，
理由是它同时触碰两条既有的取向：

1. **禁止引入第三方库**（架构不变量 §2）——KaTeX 是一份约 1MB 的第三方 JS + CSS + 字体资源；
2. **正文 Web 禁止一切脚本**——清洗后的正文用 CSP `default-src 'none'` 且**不写 `script-src`**，
   这是"不得整体信任服务端 HTML"（`SECURITY.md` §3）的第二道防线。KaTeX 是 JS，
   要跑就必须把这道门打开一条缝。

为什么仍要考虑引入（而不是简单放弃）——三条事实：

- **学堂正文里确实有 LaTeX**：上游 `learnX/src/helpers/html.ts` 在使用 KaTeX 时先做了一次
  替换 `content.replace(/\\mbox/g, '\\text')`，注释写着 *"katex doesn't support \mbox"*。
  `\mbox` 是 LaTeX 宏，这条 workaround 本身就是"真实数据里出现过公式"的证据。
- **上游就是这么做**：它把 KaTeX（0.18.7）与 KaTeX 的 auto-render 打进 WebView 模板，
  用 `renderMathInElement` 扫正文渲染，并 `throwOnError: false`（不支持的宏退回源码）。
  本项目与上游保持同一套呈现，用户的观感一致（ADR-0001 的"重建而非移植"不排斥语义对齐）。
- **用户的课程会出现公式**：2026-09-29 用户选择 A（引入），依据是其课程实际情况。

## 决策

1. **引入 KaTeX 渲染公式**，作为**唯一的第三方 JS 资源例外**。范围仅限"正文渲染"这一处：
   KaTeX 的 JS/CSS/字体随包分发（`resources/rawfile/`），不引入任何其他 JS 生态依赖。
2. **脚本按需开、按最小面开**：只有"需要渲染公式的正文 Web"开 `javaScriptAccess(true)`，
   且该文档的 CSP 由"禁一切脚本"改为**只允许我们注入的这一段**（`script-src 'unsafe-inline'`
   ——内联是我们把 KaTeX 送进去的方式）。**其余 WebView（SSO 登录页注入、文件预览）的脚本策略不变**。
3. **清洗器仍是第一道防线、且不放松**：正文先过 `common/sanitizeHtml` 白名单（脚本标签、
   `on*`、危险协议全丢，23 例穷举测试钉住），**再**把 KaTeX 注入到已清洗的正文上。
   注入顺序固定为"先清洗、后注入"，禁止把服务端内容拼进脚本片段。
4. **渲染失败必须退回源码**：`throwOnError: false`；KaTeX 缺失或加载失败时，公式按原始 LaTeX 显示，
   **不得白屏**。
5. **`SECURITY.md` §3 的措辞同批补充**：把"正文 Web 不执行任何脚本"改为
   "正文 Web 只执行本项目注入的公式渲染脚本；服务端内容一律先经白名单清洗"。

## 后果

**接受的风险**（这条 ADR 的全部意义所在）：

- **第二道防线被削弱**：正文 Web 现在会在文档内执行内联脚本。也就是说，一旦清洗器出现绕过
  （某个未列入黑名单但可执行的构造），恶意内容**有机会**执行——原先 CSP 会把这条路彻底堵死。
  缓解措施：清洗器的白名单与穷举测试是该风险的主要对冲；CSP 仍禁外部脚本源、
  禁 `object/embed/iframe`、`img-src` 仍限 http(s) 与位图 `data:`。
- **包体增大约 1MB**（KaTeX JS + CSS + 字体）。
- 与"禁第三方库"的取向相抵：故在架构不变量 §2 的清单里**显式记一条例外**，并限定为"仅公式渲染"。

**得到的**：

- 公式在应用内呈现为排版好的数学式，而不是 `\frac{...}` 源码；与上游观感一致。
- 影响面被限制在"正文渲染"一处，可单独回退（回退即"公式显示源码"，其余功能不受影响）。

## 待办（实现清单，供下个会话直接执行）

1. **取资源**：下载 KaTeX 发行包（`katex.min.js`、`katex.min.css`、`fonts/*.woff2`），
   放进 `app/entry/src/main/resources/rawfile/katex/`。**优先只带 woff2**（体积最小），
   记录来源版本号（上游用 0.18.7）。
2. **模板改造**（`components/RichTextView.ets`）：
   - CSS 与字体改为从 rawfile 引用（ArkWeb 加载 `resource://rawfile/…` 或把 CSS 内联、
     字体重写到 rawfile 路径——**先做一个最小实验确认哪种能加载**，别一次写完再试）；
   - 追加 `<script>`：KaTeX JS + `renderMathInElement(document.body, {throwOnError:false,
     delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false},
     {left:'\\(',right:'\\)',display:false},{left:'\\[',right:'\\]',display:true}]})`；
   - 沿用上游那条 `\mbox` → `\text` 替换（KaTeX 不支持 `\mbox`）；
   - 把 `\mbox` 替换与 delimiters 这类**可枚举的规则**做成纯函数（`common/mathText.ets`）并加单测。
3. **CSP**：`script-src 'unsafe-inline'`，同时确认 `runJavaScript`（量高度）仍可用。
4. **验收**：构造一条含 `$E=mc^2$`、`$$\int_0^1 x dx$$`、`\mbox` 的正文，确认渲染成公式、
   不支持的宏退回源码、**正文里没有任何脚本被服务端内容执行**（用 `<img onerror>` 一类探针验证
   清洗器仍在拦）。
5. 文档同步：`SECURITY.md` §3、架构不变量 §2 的例外条目、PRD FR-22 状态、CHANGELOG。
