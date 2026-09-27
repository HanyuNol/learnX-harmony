# 功能规格：作业（列表 · 详情 · 完成状态与截止时间）

> 状态：已实现（自动化验收已过；设备项待用户统一验收）　·　关联 PRD：FR-07（与 FR-08 / FR-20 的边界见 §2）　·　分支：main
> 接口语义基线：上游 `thu-learn-lib@4.0.0` 的 `src/urls.ts` / `src/index.ts`；
> 交互参照上游 `robertying/learnX` 的 `data/actions|assignments.ts`、
> `screens/Assignments.tsx`、`screens/AssignmentDetail.tsx`、`components/AssignmentCard.tsx`。
> **只取语义，不移植代码**（ADR-0001）。

## 1. 背景与目标

作业是四个内容维度里第二个落地的，与通知同构：**按课程扇出**（先有课程，再有作业），
列表项要带课程名/教师名（由客户端回填）。交付后用户能在"作业"标签按课程看到**当前学期**的
作业、看到截止时间与完成状态、点进详情看正文与评分。

## 2. 需求（要什么）

**范围内**：

1. 作业列表：聚合**当前学期所有课程**的作业；
2. 列表项：课程名、标题、正文摘要（去标签、两行）、教师名、**截止时间**、是否已截止、
   有附件标记（对齐上游 `AssignmentCard` 的这些字段）；
3. **完成/评分状态**：未提交 / 已提交未评分 / 已评分（见 §3.1 的关键事实）；
4. **筛选**：未完成 / 已完成（对齐上游默认选中"未完成"）；排序：**未截止的在前、按截止升序；
   已截止的在后、按截止降序**（对齐上游，把"要先做的"排在前面）；
5. **详情**：标题、完成方式/提交方式、截止时间（含补交截止）、正文（**纯文本**）、
   教师附件名、已提交信息（提交时间/附件名）、评分信息（分数或等级、评语、评分人、评分时间）；
   详情**随列表预取**，故点开即见、无加载态；
6. 三态齐备（加载/空/错误+重试）；手动刷新；
7. 从课程详情页的"作业"页签进入时只列该课程的作业。

**不做（属其他 FR，或本批不做）**：

- **附件点开/下载**：属 **FR-08**（文件）。本批只显示附件名；
- **作业提交**：属 **FR-20**（P2）。详情页**不显示**上传按钮——显示了却点了不能用，是假动作；
- **正文富文本渲染**：属 FR-22（P2）。本批一律纯文本（也避免把未清洗的 HTML 塞进 WebView，SECURITY §3）；
- **优秀作业列表**（上游的 `yzxzylist`）：**PRD 里没有这条需求**，属镀金，不做；
- 日历同步 / 本地提醒（FR-19 / FR-18，P2）；后台同步（FR-25，P2）；
- **逐条预取作业详情**（见 §3.3 第 1 条，本项目刻意不照抄）。

## 3. 设计（怎么做）

### 3.1 上游事实（对照基线，逐行核过）

| 事实 | 出处 |
|---|---|
| 作业列表由**三个 POST 端点合并**：`…/student/zyListWj`（未提交）、`zyListYjwg`（已提交）、`zyListYpg`（已评分） | `thu-learn-lib/src/urls.ts:91-117` |
| **`submitted` / `graded` 不是响应字段**，而是**由"哪个端点返回的"写死并注入**：`Wj→{false,false}`、`Yjwg→{true,false}`、`Ypg→{true,true}` | `urls.ts:95-117`、`index.ts:1083`、`types.ts:162-165` |
| 请求体只有 `aoData`（= `[{name:'wlkcid',value:courseID}]` 的 JSON 字符串，multipart） | `urls.ts:235-239`、`index.ts:1036-1039` |
| 成功判定 **`result === 'success'`**，容器 **`json.object.aaData`** | `index.ts:1041,1048` |
| 字段映射：`xszyid→id`、`zyid→baseId`、`bt→title`（解 HTML 实体）、`jzsj→deadline`（**原样字符串**）、`bjjzsj→lateSubmissionDeadline`、`sfbj==='是'→isLateSubmission`、`zywcfs→completionType`(1 个人/2 小组)、`zytjfs→submissionType`(2 网上/0 线下)、`scsj→submitTime`、`cj→grade`+`gradeLevel`、`jsm→graderName`、`pynr→gradeContent`、`pysj→gradeTime`、`sfsc==='是'→isFavorite`、`bznr→comment` | `index.ts:1057-1084` |
| **详情要额外两次请求**：① HTML 详情页 `…/f/…/viewCj?wlkcid=&xszyid=`（解析正文与**四类附件**）；② POST `…/b/…/student/detail`（`id=baseId`，成功判定同为 `result==='success'`，取 `json.msg` 作 `description`） | `index.ts:1090-1091,1190-1225`、`urls.ts:119-131` |
| 客户端的**已截止判定在客户端算**（拿 `deadline` 与当前时间比），服务端只给字符串 | `Assignments.tsx:49-50`、`AssignmentCard.tsx:42-51` |
| 列表排序：未截止在前按截止**升序**、已截止在后按截止**降序** | `data/actions/assignments.ts:46-65` |
| 筛选：未完成/已完成由 `submitted` 布尔字段决定（不再请求）；默认选中"未完成" | `hooks/useFilteredData.ts:49-57`、`Assignments.tsx:121` |
| 列表页**没有错误态 UI**（`error` 存了不读） | `Assignments.tsx` 全文 |
| 课程名/教师名由客户端用 `courses.names[courseId]` 回填（接口不返回） | `actions/assignments.ts:39-45,93-102` |
| 切学期后**旧学期作业会残留在 items 里**（只有全量刷新才整体替换；单课程刷新只替换该课程） | `reducers/assignments.ts:32-38,51-62`、`App.tsx:349-353` |
| 作业被 redux-persist 持久化 | `store.ts:20-25` |

### 3.2 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `model` | `assignment.ets` | `Assignment` 类型 + 纯逻辑：排序、摘要、筛选、"是否已截止"判定、**相对截止描述**（`relativeDeadlineOf`）、绝对时间格式化、评分等级名映射（均注入 `now`，便于测试）；**四类附件按槽位**（`AssignmentAttachments`，见 §3.3 第 9 条） |
| `network` | `parseAssignment.ets` | **纯解析**：单个端点的响应 → `Assignment[]`（带该端点的 `submitted/graded` 注入）；详情页 HTML 的附件块 → `AssignmentAttachments`；结构不符抛出 |
| `network` | `urls.ets`（改） | 三个列表端点 + 详情端点（POST 与 HTML 两个） |
| `network` | `learnClient.ets`（改） | `fetchAssignmentsOfCourse(courseId, courseName, teacherName)`（三次 POST 合并）；`fetchAssignmentDescription(baseId)`（JSON 正文）；`fetchAssignmentAttachments(courseId, xszyid)`（HTML 页四类附件） |
| `repository` | `assignmentRepository.ets` | 扇出（沿用通知的分块并发与部分失败策略）+ 详情取数（正文与附件各取各的、各自降级）+ `loadDetail`（详情页重试用） |
| `viewmodel` | `assignmentStore.ets` | 单一应用级 Store：`items`/`fetching`/错误键 + 按 semester+courses 签名对齐 + **末次胜出**；`visibleFor` 在展示时按当前时间重排；`reloadDetailOf`（只补一条详情） |
| `pages` | `Assignments.ets` | 作业列表页（筛选、刷新、三态、部分失败提示），同一组件服务作业标签与课程详情页签 |
| `pages` | `AssignmentDetail.ets` | 作业详情（纯文本正文 + 附件名 + 评分块）；详情随列表预取，进页即见；预取失败时给"详情未能加载 + 重试" |
| `pages` | `Main.ets` / `CourseDetail.ets`（改） | 接入作业标签与两个栈的目的地；课程详情的"作业"页签 |

### 3.3 关键规则

1. **详情随列表一起预取**（用户 2026-09-27 决定，对齐上游）：列表取回后继续取**每条**作业的
   详情（每条 2 个请求：HTML 详情页 + JSON 详情接口），这样**点开即见、详情页无加载态**。
   代价是请求量随作业数增长（上游同样如此）；缓解手段是沿用分块并发上限，并把实测的
   请求量/耗时记回 §6。详情缺失（取详情那一步失败）**不影响列表**：该条仍显示，
   进详情时显示"详情未能加载"并给重试。
2. **完成状态来自端点**（§3.1 第 2 条）：解析函数必须由调用方告知"这批来自哪个端点"，
   从而注入 `submitted/graded`——**不许去响应里找这两个字段**（那里没有）。
3. **已截止在客户端算**：`deadline` 原串进模型，解析成时间戳（解析失败为 0，**不猜**）；
   `isPast(timestamp, now)` 做成纯函数（`now` 注入，便于测试）。时间戳为 0 时不显示"已截止"。
4. **排序对齐上游**：未截止在前（截止升序）、已截止在后（截止降序）；时间戳 0 的（解析不出）
   排在最后。做成纯函数。
5. **切学期整表替换**：不残留旧学期作业（上游那条残留是缺陷，不照抄）；沿用
   `semester + 课程 id 集` 的签名与"末次请求胜出"。
6. **正文纯文本**（FR-22 再上富文本）。
7. **失败面沿用通知那套**：单课失败不整页失败（顶部提示"部分课程的作业未能加载"）；
   **全部失败按错误态**（带重试）——通知那次实测踩到的"全失败静默成空态"不再重演。
8. **筛选是页面本地状态**（通知那次实测踩到"放进 store 会互相串"）。
9. **附件按槽位而非平铺**：详情页 HTML 的四类附件块**按出现位置**对应教师 / 答案 / 已提交 / 评分
   （上游 `parseHomeworkAtUrl` 也是按下标取）。实现里用 `AssignmentAttachments` 的四个可空槽位承载：
   平铺数组在某一类缺失时会让后续类别**前移串位**（把参考答案显示成"我的提交"），有单测钉住这条。
10. **相对截止时间**：列表项与详情都显示"还剩 3 天"/"3 天前截止"（上游口径），另在详情附上
   绝对时间 `YYYY-MM-DD HH:mm`。单位分 分/时/天/月/年 五档，**向下取整**（说"还剩"时不多报）。
    文案经 `common/texts.ets` 映射成资源键，数量用 `$r(key, value)` 的 `%d` 占位填入。
11. **提交时间与评分时间原样显示**：服务端给的已是可读字符串，本批不做二次格式化（避免为
    星期几等语言相关名字再引一批文案键）。

## 4. 任务拆分

- [x] T1 `model/assignment.ets`：类型、排序、摘要、筛选、`isPast`（纯逻辑 + 单测）
- [x] T2 `network/parseAssignment.ets`：响应解析（含按端点注入完成状态）（纯逻辑 + 单测）
- [x] T3 `model/urls.ets` + `network/learnClient.ets`：三个列表端点与两个详情端点
- [x] T4 `repository/assignmentRepository.ets` + `viewmodel/assignmentStore.ets`：扇出、详情随列表预取
- [x] T5 `pages/Assignments.ets` + `AssignmentDetail.ets` + `Main`/`CourseDetail` 接线
- [x] 文档同步：PRD FR-07 状态、`API.md` §2.4（作业端点与"完成状态来自端点"这条）、
      `ARCHITECTURE.md`（现实与文档无出入，未改）、CHANGELOG 未发布段
- [ ] T6 验收（见 §5）：**自动化部分已过；设备部分尚未做**（原因见 §5 末尾）

> 实现期相对 spec 的两处偏离，已在 §3.2/§3.3 更新并在此留痕：
> ① 附件由"平铺数组"改为"四类可空槽位"（平铺会串位，见 §3.3 第 9 条）；
> ② 提交/评分时间不做二次格式化（见 §3.3 第 11 条）。

## 5. 验收标准

> **状态（2026-09-27 夜）**：第 1–6 项**已过**（本轮 `hvigorw test` 153 例全绿、`check arkts`
> 主源码 0 错误、`check lint` 0、`build` 成功、`check-l10n` 键集合一致）。
> 第 7–12 项是**设备项，尚未做**——模拟器上唯一的真实会话不能被装包破坏（传闻中被实测推翻的
> 是"装包清偏好"，但**凭据在未签名 debug 安装下是否会丢仍未验证**），而重新登录要用户本人的密码，
> 故**不为验收牺牲该会话**。这与通知/课程那批的处理一致，统一留到用户验收时当面演示。

**自动化可验证（单元测试，不依赖设备）— 已过**：

1. 解析：三个端点的响应分别解析为 `Assignment[]`，且 `submitted/graded` **按端点注入**正确
   （Wj→false/false、Yjwg→true/false、Ypg→true/true）；非数组 / 坏 JSON / 非 success → 抛出；
   空数组是合法结果。
2. 字段映射：标题解 HTML 实体；缺字段退让而不整批失败；`sfbj` 的中文字面量判据正确；
   `zywcfs/zytjfs` 按数字映射；`cj` 负数走等级名、正数走分数。
3. 排序：未截止按截止升序在前、已截止按截止降序在后；解析不出时间的排最后；顺序稳定。
4. `isPast`：`now` 注入下的边界（正好等于截止时间不算过期）。
5. 筛选：未完成/已完成按 `submitted`。
6. 静态门：`check arkts`（主 + 测试显式传路径）、`check lint` 零错误；`build` 成功；`check-l10n` 一致。
   另：相对截止时间的分档与取整、四类附件的位置解析（含"某类缺失不串位"）均有单测。

**设备验收（模拟器/真机，已登录）— 未做**：

7. 作业标签加载出当前学期多门课的作业；未截止的排在前面；
8. 列表项含课程名/标题/摘要/教师/截止时间，且"已截止"标记与时间一致；
9. 筛选切"未完成/已完成"：内容随之变化；
10. 点一条进详情：**无需等待、不出现加载态**，直接显示正文（纯文本）、附件名、评分块（有则显示）
    ——这是"详情随列表预取"的直接验收判据；
11. 课程详情页的"作业"页签只显示该课程的作业（与作业标签互不串）；
12. 错误面：断网/会话失效 → 错误态 + 重试；部分课程失败 → 顶部提示且已拿到的仍显示。

**需用户确认**：PRD §6 第 2 项里"浏览作业"这一环节，以及第 8/10/11 项的**真实数据**表现。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| `deadline` 的字符串形态未知 | 上游**不做任何解析**、原样交给 `dayjs`；本库也没找到样例值与格式说明 | 已按常见形态（`YYYY-MM-DD HH:mm[:ss]`、`YYYY/MM/DD`、ISO）解析，解析失败退 0 并保留原串。**真实形态仍待设备确认**：`learnClient` 对"非空但解析不出"的时间打一条 warning（`logUnparsedDeadline`），形态不对时能立刻看见，而不是静默全变"时间未知" |
| 三个端点的合并量 | 每个课程 3 个 POST：12 门课 = 36 个请求（按 4 分块 = 9 块） | 沿用通知的分块并发与上限（4）；**实测失败率/耗时待设备** |
| **详情预取的请求量** | 每条作业 2 个请求（HTML 详情 + JSON 详情），与列表请求同批扇出：12 门课 × N 条作业会明显放大总量（上游亦然） | 已实现为**每条 2 个请求**、分块限流 4。**未实测**总量与耗时；若首屏明显变慢，再与用户确认是否改为按需取 |
| 详情与列表的一致性 | 详情随列表预取，列表刷新后旧详情应一并失效 | 列表整表替换时详情随条目一起换掉（`withDetail` 产生新对象）；无需单独失效 |
| 详情那一步失败的降级 | 详情失败不应让整条作业消失 | 该条仍在列表里（`detailLoaded=false`），进详情显示"详情未能加载"+ 重试（重试只补这一条） |
| 「已截止」与上游 `isAfter` 语义 | 上游用 `dayjs().isAfter(deadline)`，等于**严格大于** | 已对齐：正好等于截止时间**不算**已截止（`isPast` 与 `relativeDeadlineOf` 同一口径，各有单测钉住） |
| `$r(key, %d)` 占位渲染未在本工程验证过 | 相对时间文案靠 `$r('app.string.' + key, value)` 填数量，**本工程此前没有参数化文案的先例**；`$r` 传变量的坑（裸键静默不渲染）本项目踩过 | 待设备确认（这是设备验收第 8 项的观察点之一）。若占位不生效，退路是把数量与单位拆成相邻的两个 `Text` 节点 |
| 附件的**真实 HTML 形态**未见真页面 | 解析规则按上游选择器 + 自制样例移植，样例覆盖了"某类无附件"的情形 | 待设备确认附件名是否显示；不显示则按 `hilog` 与页面结构校对选择器 |
| 与 FR-08 / FR-20 的边界 | 附件点开属 FR-08、提交属 FR-20 | §2 已明确不做，且详情页**不显示**提交按钮（不放假动作） |
| 优秀作业列表 | 上游有 `yzxzylist`，PRD 无此需求 | 不做；若要加，先走需求登记 |
