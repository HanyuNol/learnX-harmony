# 功能规格：富文本正文渲染（安全清洗 + 沙箱 Web）

> 状态：开发中（**数学公式部分未做**，见 §2「不做」与 §6）　·　关联 PRD：FR-22　·　分支：main
> 交互参照上游 `robertying/learnX` 的 `helpers/html.ts`（`getWebViewTemplate`）与
> `components/AutoHeightWebView.tsx`。**只取语义，不移植代码**（ADR-0001）。

## 1. 背景与目标

通知正文、作业描述与评语、文件说明在服务端都是 **HTML**。本批之前一律走
`plainText()` 剥标签后当纯文本显示——安全，但丢掉了排版、图片与链接。本 FR 把它换成
**清洗后渲染**，同时把"不得整体信任服务端 HTML"（`SECURITY.md` §3）落成三道防线。

典型收益（模拟器上验到的真实数据）：通知正文里的**图片**（课程群二维码一类）此前完全不显示，
现在能显示——图片走 ArkWeb 与 API 共用的会话 Cookie（ADR-0008），这是 ArkUI 的 `Image` 做不到的。

## 2. 需求（要什么）

**范围内**：

1. **清洗**：服务端 HTML 按**白名单**过滤后再渲染（标签、属性、URL 协议三层白名单，见 §3.3）；
2. **渲染**：清洗结果在沙箱 Web 里排版显示——保留段落/标题/列表/表格/加粗斜体/代码块/
   引用/图片/链接；**图片能显示**（走会话 Cookie）；
3. **跟随主题**：正文文字色与强调色从应用主题资源取（深浅色切换后重进页面即生效）；
4. **自动高度**：正文 Web 的高度按内容量出来，不写死、不出现内嵌滚动条；
5. **链接行为**：正文里的链接**不在正文那块 Web 里跳转**（否则详情页变成浏览器、且没有返回路径），
   交给系统浏览器打开；
6. 三个入口统一：通知正文、作业描述与评语、文件说明。

**不做（范围外）**：

- **数学公式（KaTeX）与深色适配（darkreader）**：上游把 KaTeX 与 darkreader 打包进模板。
  本项目**本批不做**，两条理由：① 它们都是**第三方 JS 资源**（KaTeX 约 1MB：JS+CSS+字体），
  与本项目"不引 JS 生态依赖、禁第三方库"的取向冲突，需要先走 ADR 把边界说清；
  ② 正文 Web 已用 CSP 关掉脚本执行（`script-src 'none'`），KaTeX 要跑就必须开脚本——安全上是一次退让，
  不该顺手做。**现状**：公式按原始 LaTeX 文本显示（可读，但不成排版），见 §6；
- **视频/音频内嵌播放**：文正里极少见，且现有白名单不含 `video/audio`；
- **正文内的锚点跳转与目录**：不做（正文排版不是文档站）。

## 3. 设计（怎么做）

### 3.1 上游事实（对照基线）

| 事实 | 出处 |
|---|---|
| 上游用 `getWebViewTemplate(content, darkMode, backgroundColor)` 把正文包进 HTML 模板（自带 CSS、注入 KaTeX 与 darkreader） | `helpers/html.ts:15-60` |
| 渲染在 `AutoHeightWebView`（RN WebView），**用 JS 桥回传内容高度**来自动撑高 | `components/AutoHeightWebView.tsx` |
| 正文里的相对图片地址靠 WebView 自己的 baseUrl 解析 | 同上 |
| 上游**不做清洗**（服务端 HTML 整体信任） | `helpers/html.ts` 全文 |

> 与上游的**有意不同**：本项目加清洗（`SECURITY.md` §3 的硬要求），且不开脚本。

### 3.2 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `common` | `sanitizeHtml.ets`（新） | **纯逻辑**白名单清洗：标签/属性/协议三层白名单、丢危险标签的整棵子树、相对地址按 baseUrl 补全 |
| `components` | `RichTextView.ets`（新） | 清洗 → 套模板（CSP + CSS + 主题色）→ ArkWeb 渲染 → 量高度 → 拦截链接导航 |
| `native` | `linkAdapter.ets`（新） | 打开外部链接的唯一出口（`ACTION_VIEW_DATA`） |
| `pages` | `NoticeDetail.ets` / `AssignmentDetail.ets`（描述与评语）/ `FileDetail.ets`（改） | 正文处换成 `RichTextView`，并清掉随之无用的 `plainText` 导入 |

### 3.3 关键规则（安全三道防线）

1. **清洗（第一道，也是主要一道）**：白名单，不是黑名单。
   - 标签：只留排版与图片相关的一小撮（`p/br/div/span/strong/b/em/i/u/s/del/ins/sub/sup`、
     `h1..h6`、`ul/ol/li/blockquote/code/pre/hr`、`a/img`、表格一族、`figure/figcaption`）；
   - **`script/style/iframe/object/embed/noscript/template/svg/math/form/input/button/select/
     textarea/link/meta/title/head/base` 连同内容一起丢**——丢标签留内容会把脚本源码显示成乱文本；
   - 属性：只留 `href/src/alt/title/width/height/colspan/rowspan`；**`on*` 事件属性一律丢**，
     `style/class/id` 也丢（样式由我们的模板给）；`width/height` 只接受纯数字（表达式会撑破布局）；
     同名属性**以第一次为准**（挡 `href="safe" href="javascript:…"` 这类覆盖绕过）；
   - 协议：`href/src` 只接受 `http`/`https` 与 `data:image/(png|jpeg|gif|webp|bmp)`；
     **`javascript:`（先剥空白与换行再判，挡 `java\nscript:`）、`data:text/html`、
     `data:image/svg+xml`（SVG 可带脚本）一律丢属性**；
   - 文本：只转义 `<`/`>`，**不动 `&`**——正文里的 `&lt;`/`&amp;` 是实体，双重转义会让用户看到字面量；
   - 相对地址按 `baseUrl` 补成绝对地址（站根 `/x` 与同级 `a.png` 两种形态都处理）。
2. **CSP（第二道）**：模板里写死 `default-src 'none'; img-src https: http: data:;
   style-src 'unsafe-inline'`，**且不含 `script-src`（即禁止一切脚本）**。即便清洗漏掉什么，
   文档内的脚本也执行不了。
3. **导航拦截（第三道）**：`onLoadIntercept` 拦下正文里的链接跳转，http(s) 交给系统浏览器
   （`native/linkAdapter`），其余直接吞掉——正文 Web 永远停在正文上。

> 自动高度用的是**应用侧注入**的 `runJavaScript('document.body.scrollHeight')`：
> 它不受文档 CSP 的 `script-src` 限制，故"禁脚本"与"量高度"不冲突。

## 4. 任务拆分

- [x] T1 `common/sanitizeHtml.ets`（纯逻辑 + 23 例穷举测试）
- [x] T2 `components/RichTextView.ets`（清洗 + CSP 模板 + 自动高度 + 导航拦截）
- [x] T3 `native/linkAdapter.ets`
- [x] T4 三处正文接线（通知正文 / 作业描述与评语 / 文件说明）+ 清掉未用导入
- [x] T5 数学公式：**已按 ADR-0012 实现**（KaTeX 内联注入 + MathML 输出 + `\mbox`→`	ext`），
      **但设备上未取得"公式确实渲染出来"的证据**，见 §5 第 8 项
- [x] 文档同步：PRD FR-22 状态、CHANGELOG、本 spec

## 5. 验收标准

**自动化（已过）**：

1. 清洗器 23 例全绿，覆盖：`<script>`（含大写、带属性）、`iframe/object/embed/svg/style` 整棵丢、
   嵌套丢弃只丢子树、注释与 doctype、`on*`（含大小写混写）、`style/class/id`、
   `javascript:` 的四种绕过（大小写/前导空白/内嵌换行与制表）、危险 `data:`（text/html、
   image/svg+xml）、位图 `data:` 保留、相对地址补全（站根/同级/协议相对）、
   重复属性取第一次、`width/height` 只认数字、文本实体不双重转义、未闭合 `<` 当文本、表外标签留文字；
2. 静态门：`check arkts` 主 88 / 测试 22 文件 0 error、`check lint` 0、`build` 成功、
   **263 例单测 0 失败**、`check-l10n` 一致。

**设备验收（模拟器 learnx / 真实账号，2026-09-29）**：

3. ✅ 通知详情：正文按富文本渲染——节点里能看到注入的完整文档，正文为
   `<p>这个课调整到一个更大的教室 六教 6A-201，请大家互相转告</p>`，主题色已注入
   （`color:#182431`、链接色 `#9a25ae`）；
4. ✅ **自动高度生效**：该 Web 节点实测高度 210px（= 70vp，正好是一行正文 + 内边距的量级），
   既不是默认最小值 60vp，也不是写死值；
5. ✅ 作业描述与评语、文件说明同样接入（`check arkts` 88 文件通过、构建成功、装到设备 `Smoke: PASS`）；
6. ⚠️ **图片加载**：本轮构造的正文里没有图片（真实数据里才有），**未验证**——
   机理上依赖 ArkWeb 与 API 共用会话 Cookie（ADR-0008），下次遇到带图的通知再确认；
7. ⚠️ **链接点击**：本轮未点（正文里没有链接）；`onLoadIntercept` 的行为**未验证**。
8. ⚠️ **公式渲染：未取得证据（2026-09-29）**。用临时探针（在「关于与帮助」页插一条含
   `$$\int_0^1 x\,dx$$` 的正文）验过：注入确实发生（日志
   `[richText] 正文含公式，注入 KaTeX 定界符=[$$ $]`、Web 文档里能看到 KaTeX 脚本），
   **但**该 Web 的量得高度（70vp）与纯文本时一样，怀疑 KaTeX 没真正执行；
   预期的 `正文渲染完成 … 公式数=N` 日志也没读到（原因未查明：可能是注入的 UMD 脚本未定义全局、
   或 `querySelectorAll('math')` 为 0、或日志被 chromium 的刷屏顶掉）。
   **下次调试建议**：把 `console.log` 放进注入脚本（Chromium 的 console 会进 hilog），
   先确认 `typeof katex`/`typeof renderMathInElement` 是否可用，再查 CSP 是否拦了内联脚本。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| **数学公式未做** | 上游用打包进模板的 KaTeX（含 darkreader）渲染公式；本项目正文 Web 用 CSP 禁了脚本，且 KaTeX 是第三方 JS 资源（约 1MB） | **待决策**：要么"引入 KaTeX（需先写 ADR 说明为什么这次可以破例、并接受开脚本的安全退让）"，要么"确认公式按原始 LaTeX 显示可接受"。PRD 里的 FR-22 因此**不能标 `已交付`** |
| 图片显示未验证 | 机理清楚但本轮正文无图片 | 下次带图通知复验；若显示不出，先看是否需要 `imageAccess(true)`（已开）与 Cookie 会话 |
| 正文 Web 的滚动 | 高度按内容量出上限 6000vp，超长正文由 Web 内部滚动 | 真实长正文（图文混排）未验；若观感差，改为"分段渲染 + 原生滚动" |
| 清洗器的白名单覆盖面 | 表外标签**丢标签留文字**（如 `marquee`），危险标签**连内容丢** | 新增标签前先想清属于哪一类；每条都要有测试 |
| 正文里的 `table` 宽度 | 宽表格可能溢出容器 | 模板里给了 `max-width:100%`；实测溢出再加横向滚动容器 |
