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
├── network/          HTTP 客户端、Cookie 管理、CSRF、SM2、页面抓取、错误归类
├── storage/          凭据、偏好、列表缓存、文件管理
├── native/           系统 Kit 适配层（日历/通知/分享/PDF/生物识别/文件选择）
├── model/            领域模型与类型定义（对应上游 data/types + thu-learn-lib 类型）
├── i18n/             中英文文案资源
└── common/           无副作用工具（日期、HTML 清洗、日志、格式化）
```

> **纯逻辑与平台调用分离的约定**：凡与外部服务互操作、且不依赖系统能力的逻辑
> （密文格式拼接、页面抓取正则、Cookie 解析），一律单独成模块并保持**零系统 Kit 依赖**，
> 以便在无设备环境下单元测试。当前此类模块：`network/sm2Format.ets`、`network/parse.ets`、
> `network/cookieJar.ets`。新增同类逻辑时遵循该约定。

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

登录共七步，逐步对齐上游 `thu-learn-lib@4.0.0` 的真实契约：

1. 重置本地会话（清空自管 Cookie 容器）。
2. `GET` 统一身份认证登录页，抓取 `#sm2publicKey`。
3. `POST` 加密后的凭据（`i_user` / `i_pass` / `singleLogin` / `fingerPrint` / `fingerGenPrint` / `fingerGenPrint3` / `i_captcha`）。
4. 从校验响应中提取漫游工单 `ticket`。
5. `GET` 带工单漫游到网络学堂，建立会话。
6. `GET` 网络学堂首页，正则提取 `_csrf` 令牌。
7. 后续对 `*.tsinghua.edu.cn` 的请求一律追加 `_csrf` 查询参数。

**密码以 SM2 国密加密后提交**，不是明文：公钥取自登录页，加密用平台加密框架
（非对称加解密目前仅支持 RSA 与 SM2），并须把框架产出的 ASN.1 密文转成服务端要求的
裸 C1C3C2 拼接格式（`network/sm2Format.ets`）。

**会话与 Cookie**：框架的 `enableAutoCookie` 起始版本为 API 26，本项目 SDK 为 24，
故 Cookie 由 `network/cookieJar.ets` 自管，**按主机名分组**——登录横跨
`id.tsinghua.edu.cn` 与 `learn.tsinghua.edu.cn` 两个主机，分组错了会串会话。

**失效与重登**：响应状态 403 或响应体含 `login_timeout` 即判定失效；
带凭据的请求命中失效时自动重登**一次**并重放，再次失效则向上抛认证失败，
不再循环。无凭据时直接抛认证失败，由页面引导重新登录。

### 5.2 CSRF

网络学堂的写操作需要 CSRF 令牌。令牌的获取（首页正则）、附加（查询参数）、
刷新（每次登录/重登后重新提取）**全部集中在 `network/learnClient.ets`**，
业务层不得自行拼接 URL 参数。

### 5.3 数据同步与缓存

- 用户进入应用或手动下拉时触发同步；同一学期内按维度（通知/作业/文件/课程）独立同步，互不阻塞。
- 网络失败时退让为"展示上次缓存 + 明确提示"，不呈现白屏。
- 缓存按学期分区；切换学期不要求全量重下，但允许用户手动刷新。

### 5.4 错误归类

上游将失败原因归为有限枚举（`FailReason`）。本项目沿用该归类思路：**网络不可达、认证失效、接口语义变更、解析失败**四类分开呈现，服务端异常不得误报为应用缺陷（对应 NFR-NET）。

### 5.5 系统能力编排

日历同步、通知提醒、后台同步均为"尽力而为"：任一系统能力被拒绝授权时，主流程（浏览数据）不受影响，仅在设置页提示。

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

**当前不做**（避免过度设计）：

- 不做多模块（HSP/HAR）拆分——单 `entry` 模块，模块化收益不足以抵偿当前成本。
- 不引入网络层第三方库——`@ohos.net.http` 足够，GraphQL 只是 HTTP POST。
- 不引入 HTML 解析第三方库——按实际需要的标签写最小解析。
- 不做数据库选型（关系型）——当前缓存需求用键值 + 文件即可；真需要时走 ADR。
- 不做离线写操作队列——读取为主，写操作（提交作业）要求在线。
