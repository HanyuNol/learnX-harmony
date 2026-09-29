# 架构设计：learnX 鸿蒙版

> 系统当前真貌（HOW）。始终原地更新到现状；结构 / 机制变了就改它。
> 本项目为**全新重建**：以下架构为项目锁定设计（已接受 ADR 支撑），代码按此实现。

## 1. 定位与边界

一个 HarmonyOS NEXT 原生客户端，直连清华网络学堂与统一身份认证的既有 HTTP 接口，在设备本地完成存储、缓存与提醒。

**是什么**：客户端应用（HAP）。**不是什么**：不是服务端、不是代理中转、不是数据缓存中心；不含 RN/JS 运行时；不访问除校方接口与第三方课程信息共享服务之外的任何后端。

**边界与外部依赖**：

| 外部系统 | 用途 | 可达前提 |
|---|---|---|
| `learn.tsinghua.edu.cn` | 通知/作业/文件/课程/学期数据 | 校园网或校方 VPN |
| `id.tsinghua.edu.cn` | 统一身份认证（WebView 流程） | 同上 |
| `api.tsinghua.app` | 课程信息共享（CourseX，GraphQL） | 公网，第三方非官方服务 |
| 系统能力 | 日历、通知、分享、PDF、生物识别、文件 | 设备本地 |

网络不可达是**常态而非异常**（大量用户在校外），因此错误归类与离线退让是架构的一等公民，不是补丁。

## 2. 模块与依赖

工程位于 `app/`（HarmonyOS 工程根），与仓库根的 SDD 治理文档并列。

```
app/entry/src/main/ets/
├── entryability/     应用入口与生命周期
├── pages/            ArkUI 页面（对应上游 screens/）
├── components/       可复用 UI 组件（对应上游 components/）
├── viewmodel/        页面状态与业务编排（对应上游 hooks/ + 部分 data/actions）
├── repository/       数据获取与缓存编排（对应上游 data/actions + data/source）
├── network/          HTTP 客户端、会话 Cookie、CSRF、SM2、页面抓取、SSO 表单逻辑、错误归类
├── storage/          凭据、偏好、列表缓存、文件管理
├── native/           系统 Kit 适配层（设备信息、应用资源、文件与目录、系统日历、系统分享；PDF/生物识别后续补）
├── model/            领域模型与类型定义（对应上游 data/types + thu-learn-lib 类型）
├── i18n/             中英文文案资源
└── common/           无副作用工具（日期、HTML 清洗、日志、格式化）
```

> **纯逻辑与平台调用分离的约定**：凡与外部服务互操作、且不依赖系统能力的逻辑
> （密文格式拼接、页面抓取正则、Set-Cookie 切分、SSO 注入脚本拼装与回传消息解析），
> 一律单独成模块并保持**零系统 Kit 依赖**，以便在无设备环境下单元测试。
> 当前此类模块：`network/sm2Format.ets`、`network/parse.ets`、`network/ssoForm.ets`、
> `network/setCookie.ets`。新增同类逻辑时遵循该约定。

**依赖方向（单向，禁止反向穿透）**：

```
pages → viewmodel → repository → network / storage / native
                          ↓
                    model / common（被各层依赖，自身不依赖任何上层）
```

- `pages` 只做 UI 与用户交互，不直接发网络请求、不直接读写存储。
- `native` 只封装系统 Kit，不含业务判断；业务失败语义由 `repository` 归类。
- `model`、`common` 是叶子层，禁止反向 import 任何上层模块。
- 违反此方向即为架构漂移（见 `.claude/rules/architecture-invariants.md`）。

## 3. 数据模型

核心实体（`model/` 中定义，字段语义对齐上游 `thu-learn-lib`，**不引入其代码**）：

| 实体 | 关键字段 | 说明 |
|---|---|---|
| `Auth` | `username`、`password`、`fingerPrint` 等 | 凭据，仅存于加密存储 |
| `SsoInjection` | `username`、`password`、`fingerPrint`、`deviceName` | WebView 注入登录页所需的取值，**只驻留内存**、不进 `@State`、不入日志 |
| `SsoFormBody` | 页面表单的字段表 | WebView 抓到的表单体，用于重放登录；含 `i_rememberme` 时走已信任设备端点 |
| `Semester` | 学期标识、名称 | 数据按学期划分 |
| `Notice` | id、标题、发布时间、已读标记、正文 | 通知公告 |
| `Assignment` | id、标题、截止时间、完成状态、提交状态、附件 | 作业 |
| `CourseFile` | id、标题、类型、大小、下载地址、本地路径 | 课件文件 |
| `Course` | id、名称、教师、时间地点、课程号 | 课程 |
| `CalendarEvent` | 标题、开始/结束、地点 | 日历同步用 |
| `UserInfo` | 姓名、院系等 | 用户信息 |
| `Settings` | 提醒偏移、文件目录策略、显示项开关、当前学期 | 本地偏好 |

**持久化形态**：

- 凭据 / Cookie：系统加密存储（`storage/`），**唯一允许接触凭据的模块**。
- 偏好设置：系统首选项（键值）。
- 列表数据缓存：本地缓存 + 结构化索引，按学期分区，可整体失效重建。
- 文件：应用沙箱目录，用户可选"文档目录"或"缓存目录"两种策略（对齐上游 `fileUseDocumentDir`）。

## 4. 接口

**对外接口**：本项目不提供服务端接口。唯一的"对外接口"是应用与系统其他应用的互通（分享、日历、文件打开），契约见 `API.md` §3。

**对内关键边界**（详细契约见 `API.md`）：

- `network.LearnClient`：网络学堂所有请求的唯一出口，统一处理 Cookie 与 CSRF。
- `storage.CredentialStore`：凭据读写唯一出口。
- `native.*Adapter`：各系统能力唯一出口。

上游依赖的**外部接口语义**记录在 `API.md` §2，作为接口变更的对照基线。

## 5. 关键机制

### 5.1 认证与会话

**主路径：WebView 主导登录**（ADR-0008，2026-09-27 起）：

1. 应用侧先清掉旧会话 Cookie，以干净会话起步（`LearnClient.startFreshSession`）。
2. `pages/SsoLogin.ets` 用 ArkWeb 的 `Web` 组件打开**真实的**统一身份认证登录页，
   并以 `javaScriptOnDocumentStart` 注入 `resources/rawfile/sso_inject.js`（只匹配
   `id.tsinghua.edu.cn` 来源）。注入脚本：预填学号密码（只读）→ 页面询问"是否信任此浏览器"时
   替用户答"是"并写入应用持久化的设备指纹 → 提交时抓取**完整表单体**经 JS 通道回传。
3. **用户在该页面内完成认证，包括输入多因子认证验证码**。应用不代填、不代答验证码
   （那是用户的步骤，不是遗漏）；这段时间应用只能等。
4. 导航目标命中网络学堂漫游地址（`LEARN_ROAMING_PREFIX`）即视为认证完成；
   `onLoadIntercept` 取消该次导航，把抓到的表单体交给上层。
5. 收尾建会话，**两条路径按可靠性排序**：
   - **首选：用截到的漫游地址里的票据直接漫游**（`LearnClient.loginWithRoamUrl`）。
     它就是浏览器原本要做的那一步，因此不需要密码、也不需要设备已被登记为信任浏览器。
     这条路径的存在有实测理由：校方页面会判定"浏览器处于隐私或匿名模式"而**拒绝登记
     信任浏览器**，一旦没登记上，服务端对任何重新登录都会再要一次验证码——重新登录
     就永远走不通，而票据路径绕开了整个重新认证。
   - **兜底：带页面生成的设备信任标识重新登录**（`loginWithFingerPrints`）：从抓到的表单体
     取出 `fingerPrint` / `fingerGenPrint` / `fingerGenPrint3`，在全新会话里由新公钥重新加密
     密码再登录。**不重放页面那份密文**（它与页面会话绑定，真机实测拿不到工单）。
     上游 `thu-learn-lib` 的 `login(username, password, fingerPrint, fingerGenPrint, fingerGenPrint3)`
     就是这条。
   两条路径都以"取首页 CSRF"收尾。

**备选路径：纯 API 七步登录**（`LearnClient.login`，仅适用未启用多因子认证的账号，
以及启动时的静默恢复与失效自动重登）：

1. `GET` 统一身份认证登录页，抓取 `#sm2publicKey`；页面含 `checkSingle` 时改用已信任设备表单。
2. `POST` 加密后的凭据（`i_user` / `i_pass` / `singleLogin` / `fingerPrint` / `fingerGenPrint` / `fingerGenPrint3` / `i_captcha`）。
3. 从校验响应中提取漫游工单 `ticket`。
4. `GET` 带工单漫游到网络学堂，建立会话。
5. `GET` 网络学堂首页，正则提取 `_csrf` 令牌。
6. 后续对 `*.tsinghua.edu.cn` 的请求一律追加 `_csrf` 查询参数。

**密码以 SM2 国密加密后提交**，不是明文：公钥取自登录页，加密用平台加密框架
（非对称加解密目前仅支持 RSA 与 SM2），并须把框架产出的 ASN.1 密文转成服务端要求的
裸 C1C3C2 拼接格式（`network/sm2Format.ets`）。表单以 multipart 提交（对齐上游的 FormData）；
对照实验表明 urlencoded 同样被服务端接受，两种编码都不是失败原因。

**会话与 Cookie**：由 `network/webCookieStore.ets` 承载，底层是 `webview.WebCookieManager`
（进程级、同步读写、可强制落盘）。选它而非自管容器的原因见 ADR-0008：WebView 与 API 请求
**必须是同一份会话**——页面加密密码用的公钥绑在它那次会话上。自管容器（原 `network/cookieJar.ets`）
已退役，其 Set-Cookie 切分逻辑保留为 `network/setCookie.ets`
（`configCookieSync` 每次只接受一条 Cookie）。框架的 `enableAutoCookie` 起始版本为 API 26，
本项目 SDK 为 24，不可用。

**失效与重登**：响应状态 403 或响应体含 `login_timeout` 即判定失效；
带凭据的请求命中失效时自动重登**一次**并重放（走备选路径），再次失效则向上抛认证失败，
不再循环。无凭据时直接抛认证失败，由页面引导重新登录。
启动时的静默恢复**先看已持久化的会话是否还活**，活着就不再登录——
否则会把一份好端端的会话清掉（实测踩过的缺陷）。

### 5.2 CSRF

网络学堂的写操作需要 CSRF 令牌。令牌的获取（首页正则）、附加（查询参数）、
刷新（每次登录/重登后重新提取）**全部集中在 `network/learnClient.ets`**，
业务层不得自行拼接 URL 参数。

### 5.3 数据同步与缓存

- 用户进入应用或手动下拉时触发同步；同一学期内按维度（通知/作业/文件/课程）独立同步，互不阻塞。
- **进入应用时预载"通知 + 文件"（FR-25）**：课程一就绪即后台预载这两维（原先要等用户切到对应
  标签才开始拉，切过去先转圈）。**作业不预载**——它每门课 3 个端点 + 逐条详情，是最贵的一维。
  预载**串行**执行（两个维度各自按课程扇出，同时在飞会把峰值并发翻倍）、**一个学期只发起一次**
  （下游 store 只在成功时记签名，单靠它去重会把一次失败放大成几次重拉）、
  **失败只进日志**（页面各有自己的错误态与重试）。纯判据在 `common/prefetch.ets`（可穷举测试），
  编排在 `viewmodel/startupSync.ets`，触发点在 `pages/Main` 的课程订阅者。详见
  `docs/specs/startup-sync.md`。
- 网络失败时退让为"展示上次缓存 + 明确提示"，不呈现白屏。
- 缓存按学期分区；切换学期不要求全量重下，但允许用户手动刷新。

### 5.4 错误归类

上游将失败原因归为有限枚举（`FailReason`）。本项目沿用该归类思路：**网络不可达、认证失效、接口语义变更、解析失败**四类分开呈现，服务端异常不得误报为应用缺陷（对应 NFR-NET）。

### 5.5 系统能力编排

日历同步、通知提醒、后台同步均为"尽力而为"：任一系统能力被拒绝授权时，主流程（浏览数据）不受影响，仅在设置页提示。

**作业截止提醒（FR-18）**：载体是**系统日历**（Calendar Kit，`@ohos.calendarManager`），
不是"应用内定时器 + 自建通知"——应用不常驻后台，自建定时器在进程被杀后不会响，属于
"看起来有、其实没有"。每次对齐把未过期的作业写进**系统默认日历账户**（标题 `作业名 - 课程名`、
结束时间＝截止时刻、开始时间＝截止前半小时、按设置提前量挂 `reminderTime`），
由系统在到点时刻弹出日程提醒。权限 `READ_CALENDAR` / `WRITE_CALENDAR`（用户授权级）。

> **为什么不是后台代理提醒**（原设计）：据官方《代理提醒(ArkTS)》约束与限制，手机、平板、PC/2in1
> 对该能力**存在管控、普通应用默认不可用**（错误码 `1700002` 的官方"可能原因"第一条即
> "没有使用权限时提醒数量上限视为 0"；模拟器实测任何登记都报此码）。官方出路是改用 Calendar Kit
> 或向华为申请权限，用户选择前者；上游在 Android 上用的也正是"日历事件 + 闹钟"。

对齐是**无状态的自愈**：作业键（`learnX:<课程 id>:<作业 id>`）写在日程的 `identifier` 上，
每次"读回现有日程 → 算差量 → 多则删、少则加、变则删了重建"——既不落本地映射表
（上游用 `syncedReminderAssignments`，表一旦丢/错就永远对不上），也能自动修掉重复与
"截止时间被改"的旧日程；**没有该标识的日程一律不动**（用户或别的应用写的）。
触发点是**作业数据落地**（加载成功、改动设置），不是用户手动点同步；
**数据不完整（未加载/部分课程失败）时一条也不动**，否则空集合会把已写进日历的日程成批删掉。

两条实测约束（2026-09-28，写进代码注释）：日历接口必须传 **UIAbilityContext**
（用 ApplicationContext 一律报 `201`，而权限查下来是已授予的）；`getEvents` **不能传参数**
（传 `undefined` 报 `401`，API 20 起默认查询字段已含所需字段）。

**课程表同步（FR-19）**：同一套日历管道，数据来自**注册中心**（`zhjw.cic.tsinghua.edu.cn`，跨主机、
JSONP，三步：取工单 → 票据认证 → 拉课表）。每次同步取"今天起 4 周"（接口单次上限 29 天），
把课程写进系统默认日历（标题＝课程名、起止＝该次课时间、地点写日程地点），按设置挂上课提醒。
纯逻辑在 `model/courseEvent.ets`（北京时间换算、条目 → 日程计划），解析在
`network/parseSchedule.ets`（ArkTS 禁动态求值，故按括号切分 JSONP），编排在
`viewmodel/courseCalendarSync.ets`。

> **两族日程按前缀划作用域**：日程标识 `learnx:`（作业）与 `learnx-course:`（课程）互不重叠，
> 差量对齐**只认本族**——否则一次课程同步会把作业日程成批删掉（本次一并修掉）。
> **注册中心的会话要每次重建**：该主机自己的 `JSESSIONID` 若还在，票据认证会返回登录页 HTML
> （实测"只有第一次同步成功"），故认证前先把它置过期；与学堂同值时**不清**（那是同一份域 Cookie）。

> 分层的落点：纯逻辑（筛选 / 提醒时刻 / 标题正文 / 差量对齐）在 `model/reminder.ets`（可穷举测试），
> 系统调用在 `native/reminderAdapter.ets`（不含业务判断），两者之间的编排在
> `viewmodel/reminderSync.ets`。详见 `docs/specs/reminders.md`。

### 5.6 已知缺口（2026-09-27 代码审查，带修复触发点）

这三条是**已确认、但按当前进度不必立即修**的缺口；都写明了触发条件，**触发时必须先修**。
审查全文（含其余低危项）为过程稿，不入库。

| 缺口 | 说明 | 何时必须修 |
|---|---|---|
| ~~Set-Cookie 归属依赖单个可变字段~~ **已解决（2026-09-28 复核）**：代码早已改为**每请求** `http.createHttp()`+`destroy()`（`network/learnClient.ets:177-183`），全仓已无 `pendingUrl`，归属不再需要猜。原条目保留以留痕 | `LearnClient` 用 `pendingUrl`（每次组装请求头时覆写）判断响应头的 Cookie 属于哪个主机。并发请求下会把 Cookie 写到错误主机 → 会话丢失，而现象会被归成"密码错误"。当前认证流程是顺序的，不可触发 | **FR-06 起引入"按维度独立同步"（§5.3）之前**。修法：每请求 `createHttp()`+`destroy()`，或把 URL 与请求句柄关联 |
| 高风险区缺测试、且当前不可离线验证 | 凭据写入/清除成对、会话状态机、Store 订阅计数归零（`testing-and-quality.md` §2 第 1/2/5 项）无任何单测——相关模块 import 平台 Kit（Asset Store、`@ohos.net.http`），宿主侧导入即失败，不满足 §1.1"纯逻辑与平台调用分离" | 下次改动认证/存储状态机时**一并**把可测部分拆出来（不得只改不补测试） |
| ~~「记住密码」的语义与现行安全规则冲突~~ **已解决（2026-09-28 复核）**：`SECURITY.md` §2 已按 FR-31 改为「按用户选择分流」、ADR-0011 已写、功能已实现。原条目保留以留痕 | `SECURITY.md` §2 要求"登出必须清除学号与密码"，而用户目标语义是"勾选记住密码后登出仍保留"（PRD FR-31） | **所有 P1 功能完成后**（用户 2026-09-27 指定最后做）。实现时同批改 SECURITY §2 措辞 + 写 ADR |
| 注入脚本抬升页面存储配额读数的**必要性**未验证 | 见 [ADR-0010](adr/0010-injection-raises-storage-quota-reading.md)：脚本注释的理由与 `specs/auth-login.md` §11.2 的实测记载相反，两边都不能当结论 | 下一次**真实账号**登录时做 ADR-0010 的对照实验（临时移除该 patch → 看登记结果与是否仍要验证码） |


## 6. 部署

- **产物**：HAP（调试安装）/ APP（上架分发）。
- **运行形态**：单进程应用，装于 HarmonyOS 设备；无服务端、无中间件。
- **SDK 目标**：工程 `app/build-profile.json5` 锁定为 **API 24**（随 DevEco Studio 6.1.1.418 的 SDK 6.1.1.125 Release）。升级 SDK 属架构决策，走 ADR。
- **工程标识**：应用名 `learnX`，包名 `io.github.hanyunol.learnx`（刻意区别于上游已上架的 `io.robertying.learnx`，避免市场冲突）。包名变更需同步签名材料与 `AppScope/app.json5`。
- **签名**：调试签名由 `devecocli auth login` + `devecocli signature generate` 生成，需要华为开发者账号与已连接设备。**未配置签名时构建仍成功**，但产物为未签名 HAP、不可安装——构建闭环因此可在无账号时验证。
- **构建与设备**：统一经 `devecocli`（`check arkts` / `check lint` / `build` / `run` / `log` / `ui`），具体命令、环境变量与工具链落盘位置见 `OPERATIONS.md`。**工程路径必须为纯 ASCII**（含中文触发错误码 `00306002`），见 ADR-0005。

## 7. 关键裁决与不做项

| 裁决 | ADR |
|---|---|
| 原生 ArkTS/ArkUI 重建，而非 RNOH 跨平台移植 | ADR-0001 |
| 沿用上游 MIT 许可，保留来源归属 | ADR-0002 |
| 采用 HarmonyOS 原生设计语言，不复刻 Material 3 视觉 | ADR-0003 |
| 状态管理方案选型 | ADR-0004 |
| 仓库布局与工具链落盘位置（避让系统盘） | ADR-0005 |
| 外部依赖与校园网前提的接受 | ADR-0006 |
| 凭据与设备指纹存于关键资产存储服务 | ADR-0007 |
| 登录改为 WebView（ArkWeb）主导，纯 API 登录降为备选 | ADR-0008 |
| 登录以漫游工单收尾（而非沿用页面会话） | ADR-0009 |
| 为完成设备信任登记，注入脚本就地抬高页面存储配额读数（必要性未验证） | ADR-0010 |
| 「记住密码」改变登出语义：勾选后登出保留凭据 | ADR-0011 |
| 引入 KaTeX 渲染数学公式，接受正文 Web 开脚本的安全退让 | ADR-0012 |

**当前不做**（避免过度设计）：

- 不做多模块（HSP/HAR）拆分——单 `entry` 模块，模块化收益不足以抵偿当前成本。
- 不引入网络层第三方库——`@ohos.net.http` 足够，GraphQL 只是 HTTP POST。
- 不引入 HTML 解析第三方库——按实际需要的标签写最小解析。
- 不做数据库选型（关系型）——当前缓存需求用键值 + 文件即可；真需要时走 ADR。
- 不做离线写操作队列——读取为主，写操作（提交作业）要求在线。
