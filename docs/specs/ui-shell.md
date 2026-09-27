# 功能规格：UI 骨架（底部标签导航 · 加载/空/错误态 · 主题 · 多语言）

> 状态：开发中（2026-09-27 审核通过）　·　关联 PRD：FR-11 / FR-15 / FR-13 / FR-14　·　分支：main
> 信息架构参照：用户提供的安卓版 learnX 页面截图（**仅作信息架构参照，不作视觉验收**）；
> 结构参照上游 `robertying/learnX`（`src/App.tsx` 的导航定义、`src/constants/Colors.ts`、
> `src/helpers/i18n.ts` 与 `src/assets/translations/`）。
> 上游用 `@bottom-tabs/react-navigation` + `@react-navigation/native-stack`；本项目用 ArkUI
> 原生 `Tabs` + `Navigation`/`NavPathStack` 实现同等结构（ADR-0001：原生重建，不移植 RN 生态）。
> **视觉口径以 ADR-0003 为准**：采用 HarmonyOS 原生设计语言，不自绘 Material 控件、不引入
> Material 图标集，**不以"与截图对齐"作为验收判据**（ADR-0003 已把"逐页对齐截图"列为其否决的备选方案）。

## 1. 背景与目标

登录已经走通（0.5.0）。接下来的四个 FR 是**横切能力**：底部导航、状态反馈、主题、多语言。
它们不是"某一个页面"，而是**后续每个内容页（通知/作业/文件/课程/设置）都要落在上面的骨架**。
先把它们立起来，可以避免后面每做一个列表页都要回头改造（见 §7「骨架先立」的判断）。

本 spec 交付后，应用从"登录后一个占位页"变成"有五个标签、能切换、深浅色正常、中英文齐备"的壳，
各标签内先放**状态组件演示的占位页**——内容由 FR-05～FR-09、FR-16 各自填充。

### 1.1 关联 FR 与交付口径

| FR | 内容 | 对应任务 |
|---|---|---|
| FR-11 | 底部标签导航 + 每标签独立页面栈 | T0（可行性 spike）、T5 |
| FR-15 | 加载 / 空 / 错误态 + Toast | T4 |
| FR-13 | 深浅色主题跟随系统并可手动指定 | T1、T2、T6 |
| FR-14 | 中英文国际化 | T3 |

> 一个 spec 覆盖四个 FR：四条共享同一份骨架设计（§3），若拆四份会复制 §3 并互相引用，收益不抵成本——合一份的约定见 `docs/specs/README.md`。
> **交付状态在 PRD §4 逐条维护**：四条各自满足自己的验收后才标 `已交付@vX.Y.Z`；若其中一条顺延，其余三条不受影响（这正是分表列任务的理由）。

## 2. 需求（要什么）

- **FR-11｜导航**：底部五个标签（通知 / 作业 / 文件 / 课程 / 设置），顺序与上游一致；
  图标用系统规范符号（`sys.symbol.*`）或自备资源，**不复刻截图里的 Material 图标**（ADR-0003）；
  每个标签有**各自的页面栈**（进入详情页后可返回，且切换标签不丢栈）。
- **FR-15｜状态反馈**：统一的**加载态 / 空态 / 错误态 / Toast** 四件套，供所有列表与详情页复用；
  错误态按错误分类给出可理解文案与重试入口（不白屏、不空白）。
- **FR-13｜主题**：深浅色跟随系统，并可在设置页手动指定（跟随系统 / 浅色 / 深色），选择持久化。
- **FR-14｜多语言**：中英文齐备，跟随系统语言；**用户可见文案必须同时提供中英文**
  （NFR-I18N）。当前硬编码的中文（登录页、SSO 页、错误分类文案、引导文案）一并迁移，清单见 §3.4。

**范围内**：上述四项 + 为承载它们所需的占位页与设置项（**仅**"主题"一项设置，其余设置项属 FR-16）。
设置页只放主题项，**不得为 FR-16 的其余项留占位行**——"提前出现的占位"算镀金（`scope-discipline` §2）。

**不做（属其他 FR）**：通知/作业/文件/课程的真实数据与列表（FR-05～FR-09）、设置页的其余项（FR-16）、
搜索（FR-17，P2）、日历同步（FR-19，P2）、作业提交（FR-20，P2）、PDF 预览（FR-21，P2）、
动效与骨架屏打磨（FR-29，P3）。**截图中的"搜索页""日历与提醒事项""作业提交""PDF 预览内嵌"
属 P2/P3，本批次不做**——它们已记入 §6 的越界提醒。

## 3. 设计（怎么做）

### 3.1 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `resources` | `base/element/color.json`、`dark/element/color.json` | 语义色两套（浅色/深色），页面只引用语义名，不写死色值 |
| `resources` | `base/element/string.json`、`en_US/element/string.json` | 中英文文案；页面只引用 `$r('app.string.*')` |
| `common` | `theme.ets` | 主题模式类型与 `ThemeMode → ColorMode` 映射（纯逻辑；只依赖平台**枚举类型**、无副作用，可宿主侧单测） |
| `common` | `texts.ets` | 文案键定义与"键 → 资源名"映射（纯函数；页面据此取 `$r`） |
| `storage` | `preferenceStore.ets` | 偏好读写唯一入口（主题模式等键值），复用系统首选项 |
| `native` | `themeAdapter.ets` | 应用主题模式（`ApplicationContext.setColorMode`）的封装；页面不得直接调用 |
| `components` | `StateView.ets` | 加载态 / 空态 / 错误态三个可复用组件（错误态含重试回调） |
| `components` | `toast.ets` | Toast 统一封装（供各页面调用，避免各页各写一套） |
| `pages` | `Main.ets` | 五个标签的壳：`Tabs` + 每标签一个 `Navigation`（各带 `NavPathStack`） |
| `pages` | `tabs/NoticesTab.ets` 等 5 个 | 各标签的首页占位（分别固定展示加载 / 空 / 错误三态，供 FR-15 验收） |
| `pages` | `Settings.ets` | 设置页骨架（**仅**主题项；其余项由 FR-16 补，本批不留占位行） |

### 3.2 导航结构（对齐上游）

上游是"根栈 + 底部标签 + 每标签一个栈"：`NoticeStack / AssignmentStack / FileStack / CourseStack /
SettingStack`，各自 `createNativeStackNavigator`。ArkUI 侧对应：

- 根：应用按登录态分发（现有 `Index.ets` 已有该逻辑）→ 已登录进入 `Main`。
- `Main`：`Tabs({ barPosition: BarPosition.End })`，五个 `TabContent`，每个内容是一个 `Navigation`
  持有自己的 `NavPathStack`（栈状态随标签保留）。
- 详情页：作为所属标签栈内的 `NavDestination`（如通知详情、作业详情、文件详情、课程详情、
  设置子页、学期切换）。**跨标签共用**的页面（登录页、SSO 页）不在栈内，仍由登录态分发。
- **系统返回**：多个 `Navigation` 并存时，返回键 / 侧滑应由**当前可见**的那个栈消费。
  该行为与"切标签再切回仍在详情页"一并在 **T0** 实测确认（§4、§6）。

> 为什么不用"一个大 `Navigation` + 全局栈"：那会让"切标签"与"返回上一页"互相干扰
> （在通知里点进详情、切到课程再切回来，期望仍在通知详情）。上游同样是每标签一栈
> （`App.tsx` 里 `NoticeStack` / `AssignmentStack` / `FileStack` / `CourseStack` / `SettingStack`
> 各自 `createNativeStackNavigator`，详情页按栈重复声明）。
>
> **T0 已实测确认（2026-09-27）**：方案 (a) 成立——五个 `Navigation` 各持自己的栈是可行的，
> 栈随标签保留、返回键由可见栈消费。另有一项待 T5 定义：可见栈为空时按 BACK 会退出到后台（见 §4 T0）。

### 3.3 主题

- **深色跟随系统**：色值放在 `base/`（浅）与 `dark/`（深）两套资源里，系统切深浅时自动生效，
  页面代码不感知。
- **手动指定**：设置页三项（跟随系统 / 浅色 / 深色）。三种模式映射为
  `ConfigurationConstant.ColorMode`：**跟随系统 = `COLOR_MODE_NOT_SET`**、浅色 = `COLOR_MODE_LIGHT`、
  深色 = `COLOR_MODE_DARK`；持久化读到非法值时退让为 `COLOR_MODE_NOT_SET`（即跟随系统），不崩溃。
- **应用时机与归属**：启动时与用户切换时，读取偏好并调用 `ApplicationContext.setColorMode`
  （该接口同时影响系统组件的取色）。它是系统能力调用，**不得写在页面里**（架构不变量 §1）——
  落在 `native/` 适配器：`EntryAbility` 启动时经适配器应用一次，设置页改动时经适配器应用。
- **语义色**：不直接写 `#RRGGBB`，一律引用语义名（如 `app.color.bg_page`、`app.color.text_primary`、
  `app.color.accent`）。主色沿用上游 `learnX` **品牌紫**（上游 `src/constants/Colors.ts` 的
  `#9A25AE`，深色侧取更亮的可读版本）——**品牌色是保留项，不代表复刻 Material 视觉**（ADR-0003）。

### 3.4 多语言

- 文案键值成对出现（`base` 中文、`en_US` 英文），**新增文案必须同时加两处**（NFR-I18N）。
- 键名沿用上游 `translations` 的语义（如 `notices` / `assignments` / `files` / `courses` / `settings`），
  便于将来对照；不必逐字照抄上游文案。
- **分层**：`model`/`network`/`viewmodel` 层不持有 `Resource`（那是 UI 层概念）。它们只产出
  **文案键**（字符串常量 / 枚举）；**键 → `Resource` 的解析由页面完成**（页面是唯一持有
  `Resource` 的层）。键到资源名的映射做成**纯函数**（零系统依赖、可单测），保证每个键都有值。
- **门在脚本与测试，不在编译器（如实说明）**：`$r` 只在参数是**字符串字面量**时才于编译期解析
  资源 id；传变量时改为运行时解析（`ets-loader` 对非字面量参数生成 id `-1`，由运行时
  `__getResourceId__` 解析）。且**缺 `en_US` 键不会编译报错**——系统回落 `base`，表现为"漏翻译"。
  故以 `scripts/check-l10n.mjs`（§5.2）+ 键映射覆盖单测为门，不依赖编译期检查。
- **变量形式的 `$r` 必须传全名（实测硬规则，2026-09-27）**：`$r` 的参数只要是**变量**
  （含 `$r(TextKeys.X)` 这种属性访问），必须写成 `$r('app.string.' + key)`；传**裸键**
  `$r(TextKeys.X)` 时资源解析失败，**不编译报错、不打日志、直接不渲染该节点**——
  现象是登录页只剩输入框，标题、按钮文字、提示整片消失（本轮真机上踩到，靠 UI 节点树发现）。
  故 `common/texts.ets` 只提供裸键，页面取资源时自己拼 `app.string.` 前缀。
  > 这条正是"编译器给不了保证"的具体后果，也是本批必须靠**设备验收**（节点树）而非静态门的原因。
- **`pages/Index.ets` 的入口占位文案不迁移**：T5 会用 `Main`（五标签）替换整个占位页，
  现在改成文案键等于改了又删。故 T3 的迁移范围不含它，T5 直接删除该占位页。
- **迁移现有硬编码中文（清单要全，否则 T3 必漏）**：
  - `pages/Login.ets`：`网络学堂` / `学号` / `密码` / `记住密码` / `登录` / `登录中…` /
    `下一步会在网页中打开统一身份认证，请在页面上完成登录（含验证码）` / `需连接校园网或校方 VPN 后使用`；
  - `pages/SsoLogin.ets`：`登录网络学堂` / `取消` / `正在建立登录会话…`，以及两处 `fatalText`
    （`登录流程状态已丢失，请返回重新登录`、`应用资源缺失，无法打开登录页`）；
  - `pages/Index.ets` 入口占位页：`已登录` / `内容页面将在后续迭代中实现` / `登出`；
  - `viewmodel/authStore.ets` 的 `describe()`：四类文案（网络不可达 / 认证失败 / 接口语义变更 /
    用户取消）与 `PARSE_FAILED` 兜底；
  - `network/ssoForm.ets` 的 `TRUST_LIMIT_GUIDANCE` 引导文案。
- **`AuthError` 的 `detail` / `userHint` 定性（本批必须一并处理，否则 NFR-I18N 这条过不了）**：
  - `detail` 是**排障用技术串**（含状态码、英文页面串；`network/learnClient.ets` 与
    `network/ssoForm.ets` 有多处中文构造），**只进日志、不进 UI**。当前 `authStore.describe()`
    的兜底 `` `登录失败：${detail}` `` 会把中文技术串直接呈现给用户（`PARSE_FAILED` 路径必现），
    该呈现路径删除。
  - `userHint` 目前是中文散文（如 `TRUST_LIMIT_GUIDANCE`），改为**键 + 可选参数**，由页面解析文案；
    `model/auth.ets` 的 `AuthError` 字段类型随之调整。
  - 注：`FailReason` 共 **5** 个值（含 `CANCELLED`，见 `model/auth.ets`），文案必须覆盖全部 5 个。

### 3.5 状态组件

| 组件 | 呈现 | 用法 |
|---|---|---|
| `LoadingView` | 居中进度指示（截图中无此态，按 HarmonyOS 习惯实现） | 首次加载 / 刷新 |
| `EmptyView` | 居中图标 + 「无内容」（对齐截图：灰色对勾图标 + 文字） | 列表为空 |
| `ErrorView` | 图标 + 分类文案 + 「重试」按钮 | 请求失败 |
| `Toast` | 底部短提示 | 轻量反馈（如"已复制"） |

错误态的文案按已有的错误分类（`FailReason`，**共 5 个值**）给出：网络不可达 / 认证失败 /
接口语义变更 / 解析失败 / 用户取消，各自一句可理解的话——这条要求已在认证 spec 里立过，这里做成组件。
`CANCELLED` 不是缺陷，默认不展示错误态（`authStore` 已把它映射为空文案），但组件必须**显式**处理它，
不得让它落到兜底文案上。

## 4. 任务拆分

- [x] **T0 导航可行性 spike**（2026-09-27 完成，**方案 (a) 成立**）：最小脚手架——两个标签各一个
  `Navigation` 各持一个 `NavPathStack`，各自 push 一个 `NavDestination`，在模拟器上实测：
  - ① **切标签往返后仍停在原详情页**（切到 B 再切回 A，`详情A` 仍在、栈深度=1）；
  - ② **系统返回键由当前可见的栈消费**（在 A 详情按 BACK 回到 A 首页；隐藏的 B 栈仍停在 `详情B`、深度=1）；
  - ③ **追加发现（交 T5 定义）**：可见栈为空时按 BACK 会**退出到后台**，而不是回到第一个标签——
    T5 需明确该行为，并与上游 `@bottom-tabs` 的 backBehavior 对齐后再定。
  - 证据：`devecocli ui layout --device learnx --format json` 节点树输出；系统返回由
    `hdc shell "uinput -K -d 2 -u 2"` 触发；`devecocli run` 末尾 `Smoke: PASS`、无 hilog 报错。
    脚手架为临时文件（`pages/SpikeNav.ets`），验证后已删除，工作区未留残迹。
  - 结论与 §3.2 一致，**无需新 ADR**；代价：为让模拟器接受安装，临时抬高过 `app.json5` 的
    `versionCode`（已还原为 5000，模拟器现状见 §6）。
- [x] T1 主题：语义色两套资源（`base/` + `dark/`）+ `common/theme.ets`（`ThemeMode → ColorMode` 映射，
  含非法值退让；纯逻辑 + 单测）+ `native/themeAdapter.ets` 适配器入口（`EntryAbility` 已改为经它应用）
  - 已交付物：`common/theme.ets`、`native/themeAdapter.ets`、两套 `color.json` 语义色
    （`bg_page` / `bg_card` / `text_primary` / `text_secondary` / `accent` / `divider` / `icon_empty` / `danger`）；
    `EntryAbility` 的 `setColorMode` 调用改为经 `applyThemeMode`（行为不变，仍是"跟随系统"）。
  - 证据（2026-09-27）：`check arkts` 主源码 23 文件 / 测试 8 文件均 **0 error**（测试须显式传路径）、
    `check lint` 0 defect、`devecocli build` 成功、`hvigorw test` → `Tests run: 70, Failure: 0, Pass: 70`。
  - 用例非空转：把 `parseThemeMode` 改成容忍小写 `dark` 后，**该用例转 Failure**（构建仍打印
    `BUILD SUCCESSFUL`，再次印证 testing-and-quality §1.1 的陷阱 1），改回后恢复 70/70。
- [x] T2 偏好存储：`storage/preferenceStore.ets`（主题模式的读写）
  - 交付物：`readThemeMode(context)` / `writeThemeMode(context, mode)` —— 系统首选项的**唯一**读写入口，
    与凭据存储分开（凭据走加密存储，ADR-0007）；`EntryAbility` 启动改为
    **读偏好 → 经 `themeAdapter` 应用**，未保存过或读失败时退让为"跟随系统"。
  - 可测性说明：本文件是**平台调用的薄封装**，其纯逻辑（字符串 → `ThemeMode`、非法值退让）
    已在 T1 的 `common/theme.ets` 穷举覆盖；故这里不重复造单测。
  - 证据（2026-09-27，模拟器 `learnx`）：
    - 写入与读回：`[T2probe] 探针：首次写入 DARK 结果=true` → `探针：读回=DARK` →
      `[themeAdapter] 已应用主题模式 mode=DARK`；
    - **跨进程持久化**：`aa force-stop` 后重启（**未重装**，新 pid）→ `探针：未写入（已有偏好）`
      → `探针：读回=DARK`；
    - **跨装包持久化**：改动 `versionCode` 后重新装包并启动，仍读到 `mode=DARK`；
    - 移除探针后的最终代码重新装包启动：`[themeAdapter] 已应用主题模式 mode=DARK`（读到已存偏好）。
    - 静态门：`check arkts` 24 文件 / 测试 8 文件 0 error、`lint` 0、`build` 成功、`hvigorw test` 70/70。
  - 遗留状态：模拟器上的主题偏好现为 `DARK`（验证写入时留下，且已证明跨装包存活）。
    T6 的设置页将提供改回"跟随系统"的开关；在此之前该偏好会一直生效。
- [x] T3 多语言：中英文案资源骨架 + §3.4 清单里的硬编码中文全部迁移为文案键 +
  `scripts/check-l10n.mjs`（键集合一致性）+ 键映射覆盖单测
  - 交付物：`resources/base`（中）与 `resources/en_US`（英）两份 `string.json`（各 21 键）、
    `common/texts.ets`（`TextKeys` 裸键 + `textKeyOfFailReason` 纯映射）、`scripts/check-l10n.mjs`、
    `texts.test.ets`（6 用例）。迁移面：`pages/Login.ets`、`pages/SsoLogin.ets`、
    `viewmodel/authStore.ets`、`network/ssoForm.ets`、`model/auth.ets`。
  - `AuthError` 调整：`userHint`（中文散文）→ `hintKey`（文案键）；`detail` 退出 UI，
    改由 `authStore` 以 `Logger.debug` 记录（排障能力不丢，用户不再看到技术串）。
    原先"把 `detail` 拼进用户文案"的兜底路径已删除。
  - 顺带落实语义色引用：登录页把写死的 `Color.Red`/`Color.Gray` 换成
    `app.color.danger`/`text_secondary`，并加 `bg_page` 背景——T1 引入的语义色开始有真实引用。
  - 证据（2026-09-27，模拟器 `learnx`）：
    - 中文（系统 zh-Hans）：节点树显示 `网络学堂 / 记住密码 / 登录 / 下一步会在网页中打开统一身份认证… / 需连接校园网或校方 VPN 后使用`；
    - **英文**：临时探针 `ApplicationContext.setLanguage('en-US')` 后节点树显示
      `Learn / Remember password / Sign in / Next, the Tsinghua SSO page opens in a web view… / Requires the campus network or the university VPN.`；
      移除探针后回到系统语言（中文），临时探针已删净。
    - `check-l10n.mjs` 非空转：删掉 en_US 的 `err_auth_failed` 后**退出码 1** 并指出"会回落成中文"，还原后退出码 0。
    - 键映射非空转：把 `AUTH_FAILED` 改成映射到 `ERR_API_CHANGED` 后该用例转 Failure（构建仍 `BUILD SUCCESSFUL`），还原后 76/76。
    - 静态门：`check arkts` 主 25 文件 / 测试 9 文件 0 error、`lint` 0、`build` 成功、`hvigorw test` 76/76。
  - **本轮踩到并已修正的真机缺陷**：`$r(TextKeys.X)`（裸键、变量形式）导致 Text/Button
    **整片不渲染**且无任何报错；改为 `$r('app.string.' + key)` 后恢复。详见 §3.4 的硬规则。
  - 未覆盖：**系统语言切换**无法在本机验证——`hdc shell param set persist.global.language en-US`
    被拒（errNum 1001，非 root）。英文是用应用级 `setLanguage` 探针验证的（已证 en_US 资源可用）。
    T7 若要验"系统切英文"，须走模拟器设置界面或取得 root；这条记为 T7 的已知障碍。
- [ ] T4 状态组件：`StateView.ets`（三态）+ `toast.ets`
- [ ] T5 导航骨架：`Main.ets` 五标签 + 每标签独立栈；五个占位页接入状态组件
- [ ] T6 设置页骨架：仅"主题"一项（跟随系统/浅色/深色），不留 FR-16 占位行
- [ ] T7 验收：模拟器上五标签切换与栈保持、深色模式、中英切换、状态三态可见
- [ ] 文档同步：PRD 四条 FR 状态、`ARCHITECTURE.md`（导航结构与分层）、CHANGELOG 未发布段

## 5. 验收标准

**自动化可验证（单元测试，不依赖设备）**：

1. `common/theme.ets`：`ThemeMode → ConfigurationConstant.ColorMode` 的映射正确
   （跟随系统 = `COLOR_MODE_NOT_SET`、浅 = `COLOR_MODE_LIGHT`、深 = `COLOR_MODE_DARK`）；
   非法存储值退让为 `COLOR_MODE_NOT_SET` 而不是崩溃。
   > 说明：不测"跟随系统时由系统值决定"这类映射——跟随系统走 `COLOR_MODE_NOT_SET` 交给系统，
   > 系统值不经过应用代码，写这样一个纯函数会是没有调用方的空壳（`scope-discipline` §3）。
2. 文案键完整性：中英文案资源**键集合一致**（缺项会让某语言漏文案）。该检查做成
   `scripts/check-l10n.mjs`（比对两份 `string.json` 的键），纳入提交前门。
3. 键映射覆盖：`FailReason`（5 个值）与其余文案键枚举的每个取值都映射到**非空**资源名；
   漏映射会让运行时取到空文案（`id=-1` 不抛错），故必须以单测兜住。
4. `devecocli check arkts` 与 `check lint` 零错误（测试源码须显式传路径，见 `testing-and-quality` §1.1）；`build` 成功。

**设备验收（模拟器/真机）**：

5. 五个标签可见、可切换，**信息架构（标签数、顺序、每标签一栈）与上游一致**；进详情页后返回栈正常；
   **切换标签再切回，仍停在原详情页**；系统返回键 / 侧滑由当前可见栈消费。
   > 判据是"功能与交互一致"，**不是**与截图观感一致（ADR-0003）。
6. 系统切深色 → 界面自动跟随；设置页手动选"浅色"→ 保持浅色且**重启后仍生效**。
7. 系统切英文 → 五个标签与已迁移页面显示英文；**不存在只写了中文的可见文案**（含错误态 5 类文案、
   登录页 / SSO 页 / 入口占位页）。
8. 三个状态组件均有可见入口（对应占位页固定展示加载 / 空 / 错误三态），且错误态有"重试"按钮。
9. 冷启动首屏 ≤3s（NFR-PERF），在模拟器上观察；异常则改懒加载标签内容。
10. **不留悬空资源**：T1 引入的语义色在本批结束时必须都有页面引用；无引用者删除
   （`scope-discipline` §3 不为未来预留空壳）。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| 截图含 P2/P3 页面 | 用户提供的截图里含搜索（FR-17）、日历与提醒事项（FR-19）、作业提交（FR-20）、PDF 预览（FR-21）、课程信息共享（FR-27）、更新日志（FR-28） | **本批次不做**，按范围纪律留在各自 FR；已在本 spec §2 显式声明，避免被当成遗漏 |
| ~~ArkUI 的每标签独立栈~~ **已解除**（T0 实测） | `Tabs` 内嵌 `Navigation` 的栈保持、返回键归属 | **方案 (a) 成立，无需备选**：切标签往返仍停在原详情页；返回键由当前可见的栈消费，隐藏栈不受影响。若将来回归，备选顺序为 (b) 单个 `Navigation` + 切标签换绑（需先验 `Navigation` 是否响应 `@State` 重绑）→ (c) 退回单栈（切标签丢详情页，与上游不一致，**不接受**） |
| **空栈时按 BACK 的行为**（T0 追加发现） | 可见栈为空时按 BACK 会**退出到后台**，不是回到第一个标签 | T5 明确该行为并与上游 `@bottom-tabs` 的 backBehavior 对齐；先确认上游默认再定，不臆测 |
| 模拟器已装版本高于仓库版本 | 模拟器上现存 `versionCode=1000001`（`versionName=1.0.0`，早期本地安装留下），而仓库 `app.json5` 为 `5000`（与 VERSION `0.5.0` 一致）→ 直接 `devecocli run` 会报 `install version downgrade` | 这是**本机环境**问题，不是仓库问题。重装前先 `hdc uninstall io.github.hanyunol.learnx`，或临时抬高 `app.json5` 的 `versionCode`（**验完必须还原，不得提交**——不得为装包改发布元数据） |
| **模拟器上的凭据存储为空（登录态不在）** | 本机为**未签名 debug 安装**（`SignHap` 警告 `Will skip sign 'hos_hap'`，无 signingConfigs）。2026-09-27 观察：`hilog` 报 `[credentialStore] 凭据不完整，需要用户登录`，界面回落登录页。<br>**更正一处早先的误判**：曾据此写成"装包会重置应用数据"，**不成立**——实测**普通偏好（Preferences）跨装包存活两次**（写入 `DARK` → 卸旧装新 → 启动仍读到 `DARK`）。故凭据何时丢失、为何丢失**均未验证**（本次或更早那次安装都有可能），机制疑与未签名安装下的关键资产归属有关，属推断 | 要演示"杀进程重开仍保持登录态"，须由**用户**用真实账号重新登录（凭据不进代码/日志，Agent 不代持）；已交付记录的 v0.5.0 证据不受影响（`auth-login.md` §11 记录在前）。**不要假设装包会清偏好，也不要假设它不会清凭据**——按"需要保留就重装前先确认"办 |
| ~~T0 结论若偏离 §3.2~~ **已确认一致** | 导航结构属架构决策 | T0 结论与 §3.2 一致，**无需新 ADR**；`ARCHITECTURE.md` 的导航结构描述在 T5 交付时一并补（不在 spike 阶段写） |
| 手动主题与系统组件的取色 | `setColorMode` 能否覆盖 `$r('sys.color.*')` 需实测 | 若不行，则改为"只用自定义语义色，不引用 sys 色"——影响面在颜色资源，不扩散到页面 |
| 文案键迁移触及 network/viewmodel 层 | `ssoForm` / `authStore` 现有中文常量与 `AuthError` 的 `detail` / `userHint` 要改成键 | 分层上由它们在 `model` 里定义键、页面负责取文案（§3.4 已定）；`detail` 改为止于日志；改动局限在文案取值处 |
| 应用体积/性能 | 五标签各持一个 `Navigation` 会增加首屏组件数 | 冷启动 ≤3s 是 NFR-PERF；T7 在模拟器上观察首屏时间，异常则改为懒加载标签内容 |
