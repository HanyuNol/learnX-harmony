# 功能规格：学期列表与切换

> 状态：待审核　·　关联 PRD：FR-05　·　分支：main
> 接口语义基线：上游 `thu-learn-lib@4.0.0` 的 `src/urls.ts` / `src/index.ts`；
> 交互与状态形状参照上游 `robertying/learnX` 的 `data/actions|reducers/semesters.ts`
> 与 `screens/SemesterSelection.tsx`。
> **只取语义，不移植代码**（ADR-0001）。

## 1. 背景与目标

通知/作业/文件/课程四个维度都挂在"当前学期"上：上游用 `if (loggedIn && currentSemester)`
作守卫，学期为空时**不发**这些请求（`src/App.tsx:336-353`）。所以学期是第一个必须立起来的
内容维度——它决定后面四个维度"查哪一学期"，也决定切换学期后哪些数据要重取。

上游的事实（逐行读过，见 §3.1）：

- 学期 id 形如 `2024-2025-1`（11 字符，第三段 1=秋 / 2=春 / 3=夏）。
- **"当前学期"由服务端决定**：`getCurrentAndNextSemester` 返回 `result.id`；客户端只在
  自己还没存过时采用它（`data/actions/semesters.ts:45-51`），**不会覆盖用户的手动选择**。
- 列表由客户端排序为**最新在前**（`sort().reverse()`）。
- 学期被持久化（上游把它放进 redux-persist 的持久化范围，白名单只排除 `auth`/`settings`）。
- 入口在设置页（`Settings → SemesterSelection`），单列表 + 选中标记，切换后**不返回**。
- 上游**没有**"按日期自动切换学期"的逻辑，也**没有**自动重试。

## 2. 需求（要什么）

- **FR-05**：获取学期列表并切换当前学期。

**范围内**：
1. 拉取学期 id 列表与服务端当前学期；
2. "当前学期"的**决策规则**：本地存过就用本地的，没存过才采用服务端的（对齐上游）；
3. 当前学期**持久化**（跨进程存活）；
4. 用户可切换当前学期，切换即时生效并持久化；
5. 学期切换页：列表（最新在前）、当前项有选中标记、可手动刷新、三态齐备（加载/空/错误+重试）；
6. 设置页加"学期切换"入口（与上游 IA 一致）；
7. **给下游立规则**：当前学期为空时，四个维度的请求不得发出（守卫；具体实现在各自 FR）。

**不做（属其他 FR）**：
- 各维度按学期取数（FR-06～FR-09）、按学期分区的列表缓存（§3 数据模型的"按学期分区"由各维度 FR 落地）、
  文件目录按学期分区（上游也没有，见 §3.1 事实 9）、下拉刷新的全局手势（各维度 FR 各自做）；
- 按日期自动切换学期（上游没有，且属"猜用户意图"，不做）。

## 3. 设计（怎么做）

### 3.1 上游事实（作为对照基线，逐行核过）

| 事实 | 出处 |
|---|---|
| 列表端点 `…/b/wlxt/kc/v_wlkc_xs_xktjb_coassb/queryxnxq`，返回 **JSON 字符串数组**，含 `null` 项需过滤 | `thu-learn-lib/src/urls.ts:30`、`src/index.ts:319-330` |
| 当前学期端点 `…/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester`，要求 `message === 'success'`，取 `result.id`；`result.xnxq` 只用于派生年份与类型 | `urls.ts:32`、`index.ts:332-349` |
| 非数组 / 非 success 都判为响应无效，客户端只记 `error`、**不自动重试** | `index.ts:321-326,334-339`、`reducers/semesters.ts:35-40` |
| 只在 `current` 为空时采用服务端值 | `data/actions/semesters.ts:45-51` |
| 列表按最新在前排序 | `data/actions/semesters.ts:28` |
| 切换 = 写一个 id 到本地状态，无服务端调用；不返回上一页 | `data/actions/semesters.ts:58-61`、`SemesterSelection.tsx:33-35,66-76` |
| 学期**不影响**下载目录与缓存 key | `helpers/fs.ts:56`（按课程名+文件 id 分区） |
| 入口在设置页；学期 id 的显示名由"第三段"映射秋/春/夏 | `Settings.tsx:106-108`、`helpers/parse.ts:4-17` |
| 无按日期自动切换 | 全 `src/data` 与 `SemesterSelection.tsx` 未找到日期推断 |

### 3.2 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `model` | `semester.ets` | `Semester`/`SemesterType` 类型 + **纯解析**：id → 年份串 + 季节键；非法 id 退让 |
| `model` | `urls.ets`（改） | 新增两个学期端点常量（**照抄上游路径**，不改写） |
| `network` | `parseSemester.ets` | **纯解析**：响应文本 → 学期 id 列表 / 当前学期 id（结构不符时抛出） |
| `network` | `learnClient.ets`（改） | `fetchSemesterIds()` / `fetchCurrentSemesterId()`，经 `getWithAuth` 并发起真实请求 |
| `storage` | `preferenceStore.ets`（改） | 当前学期的读写（键 `current_semester`） |
| `repository` | `semesterRepository.ets` | 拉取 + 决策 + 持久化的编排（不碰 UI） |
| `viewmodel` | `semesterStore.ets` | 单一应用级 Store（ADR-0004）：`items` / `current` / `fetching` / 错误键 + 订阅；`ensureLoaded` / `refresh` / `switchTo` |
| `pages` | `SemesterSelection.ets` | 学期切换页（列表 + 选中态 + 刷新 + 三态） |
| `pages` | `Settings.ets`（改）、`Main.ets`（改） | 设置页加入口；`Main` 的设置栈增加该 `NavDestination` |

**分层**：`pages` 只做 UI；存储与网络分别只经 `preferenceStore` / `LearnClient`
（架构不变量 §1、§3）。`model`/`network` 的解析部分**零系统依赖**，可宿主侧穷举测试
（`testing-and-quality` §1.1）。

### 3.3 关键规则

1. **当前学期决策**（纯函数，可测）：`decideCurrentSemester(persisted, serverCurrent)` ——
   本地非空则用本地（**不覆盖用户选择**），否则用服务端值；两者都空则保持空（下游不发请求）。
2. **排序**（纯函数）：id 按字符串降序（最新在前）。形如 `YYYY-YYYY-N` 的定长格式下，
   字符串序与时间序一致；非法 id 不参与排序但也不丢（置后）。
3. **id → 显示**（纯函数）：拆成 `yearsText`（如 `2024-2025`）与 `seasonKey`
   （`semester_season_fall|spring|summer|unknown` 文案键）。**页面不拼中文**——年份与季节
   分两个节点渲染（或用资源占位符），否则 NFR-I18N 会被字符串拼接绕过。
4. **持久化**：当前学期存 `preferenceStore`（与主题模式同一入口）。**读写一律用
   `ApplicationContext`**——用页面 `getHostContext()` 写的偏好在真机上重启读不回来
   （2026-09-27 实测，见 `OPERATIONS.md` §7.5）。
5. **失败归类**（沿用四分类）：HTTP 非 2xx 走 `fromStatusCode`（接口语义变更 / 认证失败）；
   结构不符（非数组、非 `success`、缺 `result.id`）→ 解析失败；网络层错误由
   `normalize` 归类。**不得把网络问题报成应用缺陷**（NFR-NET）。
6. **空列表**：服务端返回空数组是合法结果，呈现空态而非错误态。
7. **不自动重试**：对齐上游。错误态给"重试"（`errorView` 的重试回调），由用户触发。

### 3.4 与 ADR 的关系

不引入新的架构决策：状态用 ArkUI + 单一 Store（ADR-0004）；网络唯一出口 `LearnClient`；
偏好走 `preferenceStore`。上游的"学期切换放在设置页"属信息架构，直接沿用。

## 4. 任务拆分

- [ ] T1 `model/semester.ets`：类型 + id 解析（纯逻辑 + 单测）
- [ ] T2 `network/parseSemester.ets`：两个响应解析（纯逻辑 + 单测）
- [ ] T3 `model/urls.ets` + `network/learnClient.ets`：两个端点与取数方法
- [ ] T4 `storage/preferenceStore.ets`：当前学期读写
- [ ] T5 `repository/semesterRepository.ets` + `viewmodel/semesterStore.ets`：编排、决策、订阅
- [ ] T6 `pages/SemesterSelection.ets` + 设置页入口 + `Main` 的 `NavDestination`
- [ ] T7 验收（见 §5）
- [ ] 文档同步：PRD FR-05 状态、`ARCHITECTURE.md`（数据模型/机制若与原文有出入）、`API.md` §2.3、CHANGELOG 未发布段

## 5. 验收标准

**自动化可验证（单元测试，不依赖设备）**：

1. id 解析：`2024-2025-1/2/3` → 年份串与秋/春/夏；非法输入（空串、段数不足、非数字、
   年份非 4 位）→ 退让为 unknown + 保留原串可显示，**不崩**。
2. 列表解析：合法 JSON 数组（含 `null` 项）→ 过滤后返回；非数组 / 坏 JSON → 抛出（由上层归为解析失败）。
3. 当前学期解析：`message === 'success'` 且有 `result.id` → 返回该 id；否则抛出。
4. 决策：本地非空时**不**被服务端值覆盖；本地为空时采用服务端值；两者皆空 → 空。
5. 排序：最新在前；非法 id 不破坏其余顺序。
6. 静态门：`check arkts`（主源码 + **测试源码显式传路径**）与 `check lint` 零错误；`build` 成功；
   `check-l10n.mjs` 键集合一致。

**设备验收（模拟器/真机，**需要已登录会话**）**：

7. 设置页可见"学期切换"入口；进入后列表加载成功、**最新学期在最前**、当前学期有选中标记。
8. 点另一个学期 → 选中态即时更新；**杀进程重开后仍是它**（持久化生效）。
9. 断网或会话失效时：呈现错误态（可理解的文案）且有"重试"；点重试能重新发起。
10. 空列表（服务端返回空数组）时呈现空态，不是错误态。

> 7–10 **必须在有真实会话的模拟器或真机上跑**（这两个端点都要会话）。当前模拟器上
> 凭据存储为空，故这几项需用户登录后验证；在此之前，本 FR 视为**未完成**。

**需用户确认（PRD §6 第 2 项的一部分）**：真实账号 + 校园网下"切换到目标学期"这一环节。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| `result.id` 与 `result.xnxq` 是否同形 | 上游把两者分开处理（`id` 用来切换、`xnxq` 只用于切片派生年份），但列表 id 与 `id` 必须同形才能匹配上"当前项" | **实现时同时打印两者比对**（脱敏：都是学期串，无隐私问题）。若不同形，显示名改由 `id` 派生，并在 spec 记下实测结论 |
| 端点路径形态 | 学期两端点是 `/b/...`，而本项目认证期用的是 `/f/...`；两者是不同形态，不可"统一" | 常量**照抄上游**并加注释说明；`API.md` §2.3 补精确路径 |
| 学期 id 进 URL path | FR-09 会把学期 id 拼进 `getCourseList` 的 path；本项目已发现同类问题（审查 R-14：票据未编码） | 本 FR 只记录该风险，FR-09 实现时对 path 参数做 `encodeURIComponent` |
| 列表加载时机 | 上游在登录后且 `items` 为空时拉一次 | 登录成功后触发 `ensureLoaded`；本 FR 不做后台定期刷新（属 FR-25） |
| 当前学期为空时的下游 | 四个维度不得发请求 | 本 FR 定规则并写进 §2 范围内第 7 条；各维度 FR 落地时遵守，并由其测试覆盖 |
| 覆盖用户的自动行为 | 服务端"当前学期"可能随学期更替变化 | 只首次采用，不覆盖用户选择（对齐上游）；若将来要"自动跟随新学期"，那是新需求，须先确认 |
