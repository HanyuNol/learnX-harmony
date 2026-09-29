# 功能规格：富文本正文渲染（安全清洗 + 沙箱 Web）

> 状态：**已实现，且设备验收通过**（正文渲染与公式两项都齐，见 §5；发版时由
> `sdd-release-version` 统一标 `已交付@vX.Y.Z`）　·　关联 PRD：FR-22　·　关联 ADR：0012　·　分支：main
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

- **深色适配（darkreader）**：上游把 darkreader 也打进模板。本项目不做——正文的底色与文字色
  已由模板按应用主题给（§3.1），不需要再塞一个运行时改样式的脚本；
- ~~**数学公式（KaTeX）**~~：**已由 [ADR-0012](../adr/0012-katex-for-math-rendering.md) 决策引入并实现**
  （用户 2026-09-29 选定 A 路）。这里的取舍过程保留以留痕：当时不做它有两条理由
  （第三方 JS 资源与"禁第三方库"冲突；开脚本是安全退让），ADR-0012 说明了两条如何被接受与限制
  （仅公式渲染这一处、按最小面开脚本、清洗仍是第一道防线）。**实现偏差**：实际用 `output:'mathml'`
  且**不带 KaTeX 字体**（包体只增 279KB，而非 ADR 预估的 1MB），数学排版由 Chromium 的 MathML 呈现；
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

> 与上游的**有意不同**：本项目加清洗（`SECURITY.md` §3 的硬要求）；
> 脚本只在**确含公式的正文**上按最小面放开（ADR-0012），其余正文仍禁一切脚本。

### 3.2 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `common` | `sanitizeHtml.ets`（新） | **纯逻辑**白名单清洗：标签/属性/协议三层白名单、丢危险标签的整棵子树、相对地址按 baseUrl 补全 |
| `common` | `mathText.ets`（新） | **纯逻辑**公式识别与规整：定界符判据取宽、`\mbox`→`\text` |
| `common` | `scriptResult.ets`（新） | **纯逻辑**解码 `runJavaScript` 的 JSON 回传值（不脱引号高度就是 `NaN`，见 §3.4） |
| `components` | `RichTextView.ets`（新） | 清洗 → 套模板（CSP + CSS + 主题色）→ `loadData` 渲染 → 量高度 → 拦截链接导航 |
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
   （`native/linkAdapter`）——正文 Web 永远停在正文上。
   **只拦 `http(s)`，其余一律放行**：这个回调对**主框架加载**同样触发，无脑 `return true`
   会把文档自身的加载也拦掉（页面白屏），见 §3.4。

### 3.4 把文档交给 ArkWeb 的四个硬约束（全部在设备上踩出来过）

症状统一是**"节点树里能看到内容、但什么都没发生"**（2026-09-29 排查记录见
`OPERATIONS.md` §7.11）：

1. **HTML 必须走 `loadData`，不能从 `src` 传**。`src` 是资源地址，喂整篇 HTML 会被当 URL 解析
   失败（hilog：`[WebNavigation] LoadUrl message:invalidUrl`），**页面从不加载**，
   `onPageBegin`/`onPageEnd` 一次都不触发，注入的脚本自然不跑。用
   `Web({ src: '' })` + `onControllerAttached` → `controller.loadData(document, 'text/html', 'utf-8', baseUrl)`；
   `baseUrl` 给学堂首页（相对地址可解析，文档 origin 落在学堂域上）。
2. **`onLoadIntercept` 只对 `http(s)` 返回 `true`**（同第 3 条防线）。
3. **`runJavaScript` 的回传值是 JSON 编码的**，字符串会带一对引号；须过
   `common/scriptResult.ets` 的 `unwrapScriptResult` 再解析，否则高度恒为 `NaN`、
   组件停在最小高度（"自动高度"静默失效）。
4. **页面 `console` 默认不进 hilog**，故加 `.onConsole()` 把页面日志转进本组件日志——
   否则"注入的脚本跑没跑、CSP 有没有拦"完全无从判断。

> 自动高度用的是**应用侧注入**的 `runJavaScript('document.body.scrollHeight')`：
> 它不受文档 CSP 的 `script-src` 限制，故"禁脚本"与"量高度"不冲突。
> 同一句里还顺带读回 `document.querySelectorAll('math').length`——这是"公式确实渲染出来"
> 在设备上唯一的客观证据（Web 内部 DOM 不进 UI 节点树）。

## 4. 任务拆分

- [x] T1 `common/sanitizeHtml.ets`（纯逻辑 + 23 例穷举测试）
- [x] T2 `components/RichTextView.ets`（清洗 + CSP 模板 + 自动高度 + 导航拦截）
- [x] T3 `native/linkAdapter.ets`
- [x] T4 三处正文接线（通知正文 / 作业描述与评语 / 文件说明）+ 清掉未用导入
- [x] T5 数学公式：已按 ADR-0012 实现（KaTeX 内联注入 + MathML 输出 + `\mbox`→`	ext`），
      并在设备上取得"公式确实渲染出来"的证据（§5 第 8 项）
- [x] T6 **修掉三个让文档根本加载不起来的缺陷**（§3.4 第 1~3 条：`src` 传 HTML、`onLoadIntercept`
      拦主框架、`runJavaScript` 回传值未解码），并把解码那步做成纯函数 + 单测
- [x] 文档同步：PRD FR-22 状态、CHANGELOG、`OPERATIONS.md` §7.11、本 spec

## 5. 验收标准

**自动化（已过）**：

1. 清洗器 23 例全绿，覆盖：`<script>`（含大写、带属性）、`iframe/object/embed/svg/style` 整棵丢、
   嵌套丢弃只丢子树、注释与 doctype、`on*`（含大小写混写）、`style/class/id`、
   `javascript:` 的四种绕过（大小写/前导空白/内嵌换行与制表）、危险 `data:`（text/html、
   image/svg+xml）、位图 `data:` 保留、相对地址补全（站根/同级/协议相对）、
   重复属性取第一次、`width/height` 只认数字、文本实体不双重转义、未闭合 `<` 当文本、表外标签留文字；
2. 静态门：`check arkts` 主 90 / 测试 24 文件 0 error、`check lint` 0 error、`build` 成功、
   **274 例单测 0 失败**、`check-l10n` 一致。

**设备验收（模拟器 learnx / 真实账号，2026-09-29）**：

3. ✅ 通知详情：正文按富文本渲染，正文为
   `<p>（示例）这门课的地点调整到 A201，请互相转告</p>`，主题色已注入
   （`color:#182431`、链接色 `#9a25ae`）；`onPageEnd` 触发、日志
   `正文渲染完成 高度=51 公式数=0 期望含公式=false`；
4. ✅ **自动高度生效**：同一份正文量得 51（CSS px，与 vp 近似 1:1）→ 组件高度按
   `min/max` 取到 60vp；「关于与帮助」页那条探针量得 74 → 78vp，节点树里正文区域随之变高。
   > **注**：本项原先写成"210px = 70vp，不是默认最小值"是**误读**——210 设备像素正是 **60vp
   > 的默认最小值**，而当时高度解析恒为 `NaN`（§3.4 第 3 条），自动高度其实**从未生效**；
   > 该误读连同上面"节点里能看到注入的完整文档"一并由本次排查纠正（那只是 `src` 的回显）；
5. ✅ 作业描述与评语、文件说明同样接入（`check arkts` 通过、构建成功、装到设备 `Smoke: PASS`）；
6. ⚠️ **图片加载**：本轮构造的正文里没有图片（真实数据里才有），**未验证**。
   机理上依赖 ArkWeb 与 API 共用会话 Cookie（ADR-0008）；`loadData` 的 `baseUrl` 已给学堂首页，
   但 `loadData` 内部走 `data:` URL，**文档 origin 是否真落在学堂域上尚未证实**，下次带图通知复验；
7. ⚠️ **链接点击**：本轮未点（正文里没有链接），**未验证**。但 `onLoadIntercept` 的行为已被间接
   验证——它的返回值决定文档能否加载（§3.4 第 2 条），当前"只拦 http(s)"的写法下文档能正常加载；
8. ✅ **公式渲染：已取得证据**。临时探针（「关于与帮助」页插一条含
   `行内 \(x^2\)`、`块级 $$\int_0^1 x\,dx$$`、`\mbox{甲}` 的正文；验完已还原）三项证据：
   - `[richText] 页面console: [katexProbe] typeof katex=object typeof renderMathInElement=function`
     ——注入的两个全局**都在**，CSP 没有拦内联脚本；
   - `[richText] 正文渲染完成 高度=74 公式数=2 期望含公式=true`——两个公式都渲染出来了；
   - `devecocli ui layout` 的节点树里出现 `mathMLIdentifier`（`𝑥`/`𝑑`）、`mathMLNumber`（`2`/`1`/`0`）、
     `mathMLOperator`（`∫`）——**MathML 真的排出来了**（`output:'mathml'` 生效）。
   另：`\mbox{甲}` 规整成 `\text{甲}` 后落在**公式定界符之外**，故按源码显示（符合预期，
   探针本身如此摆放；真正需要它的是定界符内的用法）。
   > **注**：本项原先记的"注入发生但高度与纯文本相同、怀疑 KaTeX 没执行"结论**方向对、根因错**——
   > 不是 KaTeX 的问题，是**整篇文档压根没加载**（§3.4 第 1、2 条）。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| **公式渲染开了脚本** | 安全退让已由 [ADR-0012](../adr/0012-katex-for-math-rendering.md) 明确接受：清洗器是第一道防线，CSP 仍禁外部脚本源，且**只有确含公式的正文**才开内联脚本 | 已落地并设备验证（§5 第 8 项）；清洗器白名单与 23 例穷举测试是该风险的主要对冲 |
| 图片显示未验证 | 机理清楚但本轮正文无图片；`loadData` 走 `data:` URL，文档 origin 是否落在学堂域上未证实 | 下次带图通知复验；若显示不出，考虑改走 `loadData` 之外的加载方式（把图片换成应用侧取回后内联的 `data:`，或落到沙箱文件用 `file://` 加载） |
| 图片/长正文的加载路径 | 现在整篇文档（含 279KB KaTeX）都经 `loadData` 走 `data:` URL | 目前实测正常（260KB 量级）；若正文显著变大，评估是否把 KaTeX 拆成单独加载 |
| 正文 Web 的滚动 | 高度按内容量出上限 6000vp，超长正文由 Web 内部滚动 | 真实长正文（图文混排）未验；若观感差，改为"分段渲染 + 原生滚动" |
| 清洗器的白名单覆盖面 | 表外标签**丢标签留文字**（如 `marquee`），危险标签**连内容丢** | 新增标签前先想清属于哪一类；每条都要有测试 |
| 正文里的 `table` 宽度 | 宽表格可能溢出容器 | 模板里给了 `max-width:100%`；实测溢出再加横向滚动容器 |
