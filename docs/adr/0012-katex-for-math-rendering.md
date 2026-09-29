# ADR-0012：引入 KaTeX 渲染数学公式，接受正文 Web 开脚本的安全退让

## 状态

已接受（2026-09-29 用户选择，见 PRD FR-22；**已实现并在设备上验收通过**，见文末「实现结果」）

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

## 实现结果（2026-09-29，替代原先的"待办清单"）

**与上文预案的三处偏差**（都是"更省"的选择）：

1. **不带字体、不用 CSS**：用 `output:'mathml'`，数学排版交给 Chromium 自带的 MathML，
   于是**既不引 `katex.min.css` 也不引 `fonts/*.woff2`**——包体只增 **279KB**（`katex.min.js`
   0.16.11 + `auto-render.min.js`），而非原文预估的约 1MB。两个 JS 内联进正文文档
   （`resources/rawfile/`，与 SSO 注入脚本同一处）。
2. **定界符用 auto-render 的默认集**（`$$`、`\(`、`\[`，**不含单 `$`**），与上游一致；
   没有像预案那样显式传 `delimiters`。要开单 `$` 只改 `common/mathText.ets` 的 `DELIMITERS` 一处。
3. **"按需开脚本"落在文档级**：只有 `containsMath()` 为真的正文档才把 CSP 写成
   `script-src 'unsafe-inline'` 并注入脚本；其余正文的 CSP 仍是禁一切脚本。

**验收证据（模拟器 learnx，真实账号，2026-09-29）**：注入的两个全局可用
（`typeof katex=object`、`typeof renderMathInElement=function`）；含 `\(x^2\)` 与
`$$\int_0^1 x\,dx$$` 的正文报 `公式数=2`；`devecocli ui layout` 的节点树里出现
`mathMLIdentifier`/`mathMLNumber`/`mathMLOperator`（MathML 真的排出来了）。
`\mbox`→`\text` 与定界符规则由 `common/mathText.ets` 的 8 例单测钉住。

**顺带修掉的真缺陷**（与 KaTeX 无关，但让"公式渲染"看起来失败）：
HTML 经 Web 组件的 `src` 传入根本不会加载、`onLoadIntercept` 无脑返回 `true` 会拦掉主框架加载、
`runJavaScript` 的回传值没脱 JSON 引号致自动高度恒为 `NaN`。
三条都记在 `docs/specs/rich-text.md` §3.4 与 `docs/OPERATIONS.md` §7.11。

**文档同步（已完成）**：`SECURITY.md` §3、`ARCHITECTURE.md` 不变量的例外条目、
PRD FR-22、`docs/specs/rich-text.md`、CHANGELOG。
