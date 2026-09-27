# 功能规格：课程列表与详情

> 状态：待审核　·　关联 PRD：FR-09（并**为 FR-06 / FR-07 / FR-08 解除前置依赖**）　·　分支：main
> 接口语义基线：上游 `thu-learn-lib@4.0.0` 的 `src/urls.ts` / `src/index.ts`；
> 交互参照上游 `robertying/learnX` 的 `data/actions|courses.ts`、`screens/Courses.tsx`、
> `screens/CourseDetail.tsx`。**只取语义，不移植代码**（ADR-0001）。

## 1. 背景与目标

### 1.1 为什么先做课程（对既定顺序的一处调整）

原计划的顺序是"学期 → 通知 → 作业 → 文件 → 课程"。**逐行读上游后发现这个顺序做不下去**：

- 通知是按**课程**取的：`getNotificationList(courseID, ...)`
  （`thu-learn-lib/src/index.ts:446-455`），请求体里只有 `wlkcid`，没有学期参数；
- RN 侧的通知/作业/文件三个列表页，都是先从课程状态派生 `courseIds` 再扇出取数
  （`Notices.tsx:21-24,38`、`Assignments.tsx:27-30,55`、`Files.tsx:21-24,38`）；
- 课程条目里的**课程名/教师名**也是这三类条目的展示字段来源
  （三者的 action 用 `courses.names[courseId]` 回填 `courseName/courseTeacherName`，
  如 `actions/notices.ts:64-78`）；文件下载目录还直接用 `courseName` 分段
  （`helpers/fs.ts:56`）。

**结论：课程是通知/作业/文件的前置**。本 FR 落地后才动 FR-06～FR-08。

### 1.2 目标

让用户在"课程"标签里看到**当前学期**的课程列表，点进某一门课能看到它的基本信息与
（将来的）三块内容；并提供这三块内容取数所需的 `courseIds` 与课程名映射。

## 2. 需求（要什么）

**范围内**：

1. 按**当前学期**取课程列表（学期为空则不发请求，等学期就绪）；
2. 课程卡展示：课程名 + 教师名（上游卡片还显示三个计数徽标，见"不做"）；
3. 课程详情页**骨架**：课程基本信息 + 三个内容页签（通知/作业/文件）的占位，
   三块内容由 FR-06～FR-08 各自填充；
4. 三态齐备（加载/空/错误+重试），失败不白屏；
5. 切换学期后课程列表**整表替换**，且不残留上一学期的课程（对齐上游 `reducers/courses.ts:29-49`）；
6. 对外提供：课程 id 列表（供 FR-06～FR-08 扇出）与 `id → 课程名/教师名` 映射（供它们回填展示字段）。

**不做（属其他 FR 或本批不做）**：

- 三门课的内容（通知/作业/文件）——FR-06～FR-08，本 FR 只留页签与占位；
- 课程卡片上的三个计数徽标（未读通知/未完成作业/新文件）——它们是那三个维度的派生数据，
  等 FR-06～FR-08 落地后再加（现在加只能显示 0，是假信息）；
- **逐课额外取"时间地点"**：上游为每门课再发一次请求
  （`index.ts:369-372`，URL `/b/kc/v_wlkc_xk_sjddb/detail?id=`，失败即忽略）。本项目本批**不取**：
  列表与详情都不展示它，为不展示的字段引入 N 次请求不值得，等真有展示需求再说；
- 隐藏课程与自定义排序（上游 `setHideCourse` / `setCourseOrder`）——属设置/筛选范畴，
  留给 FR-12 或 FR-16；
- 课程信息共享 CourseX（FR-27，P3）。

## 3. 设计（怎么做）

### 3.1 上游事实（对照基线，逐行核过）

| 事实 | 出处 |
|---|---|
| 列表端点：学生 `GET {LEARN_PREFIX}/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/{semester}/{lang}` | `thu-learn-lib/src/urls.ts:34-37` |
| 学期 id 作为**路径参数**直接拼接（故需 URL 编码；见 §6） | `urls.ts:36` |
| 字段：`id`(wlkcid)、`name`(zywkcm 解码)、`chineseName`、`englishName`、`teacherName`(jsm)、`teacherNumber`、`courseNumber`、`courseIndex`、`courseType` | `index.ts:373-385`、`types.ts:76-90` |
| 没有独立的"课程详情"接口：详情页只用列表项 + 三个内容接口 | `Courses.tsx:77`、`CourseDetail.tsx:170,227,234,241,252` |
| 取数时先 `setLanguage(lang)`，给每项补 `semesterId`，按 id 排序 | `actions/courses.ts:33-40` |
| 切换学期**整表替换** `items`（失败则保留旧值只记 error） | `reducers/courses.ts:29-55` |
| 课程被持久化（redux-persist 黑名单只有 `auth`/`settings`） | `store.ts:20-25` |
| 详情页 = 三个页签（通知/作业/文件）+ 课程信息按钮；三块**只在用户下拉刷新时**取数，进页面不自动加载 | `CourseDetail.tsx:159-163,44-157,52-56,91-95,129-133` |
| 课程页错误态：**上游没有**（reducer 存了 error，页面不读） | `Courses.tsx` 全文、`reducers/courses.ts:50-55` |
| 课程空时，通知/作业/文件的扇出**没有** `courseIds.length === 0` 守卫（空数组也会发一次） | `Notices.tsx:36-40` 等；对比后台任务有守卫 `background.ts:122-129` |

### 3.2 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `model` | `course.ets` | `Course` 类型 + 纯逻辑：列表排序、`id → 显示名` 回退规则 |
| `model` | `urls.ets`（改） | 课程列表端点常量（含学期与 lang 的路径参数） |
| `network` | `parseCourse.ets` | **纯解析**：响应文本 → `Course[]`（结构不符抛出） |
| `network` | `learnClient.ets`（改） | `fetchCourses(semesterId)`，经 `getWithAuth`；对学期 id 做 `encodeURIComponent` |
| `repository` | `courseRepository.ets` | 取数编排（学期为空则不发请求） |
| `viewmodel` | `courseStore.ets` | 单一应用级 Store：`items` / `fetching` / 错误键 + 订阅；`ensureLoadedFor(semesterId)` / `refresh` / 课程名查询 |
| `pages` | `courses/CoursesTab.ets`（或 `pages/CoursesView.ets`） | 课程标签的列表页；点行进详情 |
| `pages` | `CourseDetail.ets` | 课程详情骨架（基本信息 + 三个页签占位），挂在该标签的栈里 |
| `pages` | `Main.ets`（改） | 课程的 `NavDestination` 接入详情页；学期就绪后触发课程加载 |

**分层**：`pages` 只做 UI；网络与存储分别只经 `LearnClient` / `preferenceStore`
（本 FR 不新增偏好；隐藏/排序留后）。解析零系统依赖，可宿主侧穷举测试。

### 3.3 关键规则

1. **学期为空不发请求**：`ensureLoadedFor` 收到空学期 id 时直接返回（对齐 §2 范围第 1 条，
   也补上上游那条缺失的守卫）。
2. **按学期缓存与替换**：`items` 记住它属于哪个学期；学期一变即视为过期并重取，
   成功后**整表替换**（不追加），避免两个学期的课程混在一起。
3. **显示名回退**：`name` 为空时退回 `chineseName`，再为空退回课程号（避免空白行）；
   这三者的取舍写成纯函数并测。
4. **排序**：按课程 id 升序（对齐上游 `actions/courses.ts`），保证同一份数据每次顺序一致。
5. **失败归类**：非 2xx 走 `fromStatusCode`；结构不符 → 解析失败；网络错误由 `normalize` 归类。
   **空列表是空态，不是错误**。
6. **为下游留接口**：`courseStore` 暴露 `courseIds()` 与 `nameOf(id)`——FR-06～FR-08 据此扇出
   并回填展示字段；**课程为空时下游不得发请求**（上游漏了这条守卫，我们补上）。
7. **本 FR 不引入并发**：课程列表是**一次请求**，没有扇出，故不触发 `ARCHITECTURE` §5.6 记的
   R-03（Set-Cookie 归属）。**R-03 仍须在 FR-06 之前修**——那里才会按课程扇出。

## 4. 任务拆分

- [ ] T1 `model/course.ets`：类型、排序、显示名回退（纯逻辑 + 单测）
- [ ] T2 `network/parseCourse.ets`：响应解析（纯逻辑 + 单测）
- [ ] T3 `model/urls.ets` + `network/learnClient.ets`：端点与取数方法（学期 id 编码）
- [ ] T4 `repository/courseRepository.ets` + `viewmodel/courseStore.ets`：编排、按学期替换、课程名查询
- [ ] T5 `pages/CoursesTab` + `CourseDetail` + `Main` 接线（学期就绪后触发加载）
- [ ] T6 验收（见 §5）
- [ ] 文档同步：PRD FR-09 状态、`API.md` §2.4（课程端点精确路径）、`ARCHITECTURE.md`
      §3 数据模型（`Course` 字段与实际一致）、CHANGELOG 未发布段

## 5. 验收标准

**自动化可验证（单元测试，不依赖设备）**：

1. 响应解析：合法数组 → `Course[]`（含字段缺失的项按回退规则处理）；非数组 / 坏 JSON → 抛出。
2. 显示名回退：`name` → `chineseName` → 课程号；三者皆空时给可识别的占位而不是空串。
3. 排序：按 id 升序稳定。
4. 学期归属：`items` 属于的学期与入参不一致时，视为过期（纯函数判定）。
5. 空学期不发请求：`ensureLoadedFor('')` 不产生请求（以桩/纯判定覆盖）。
6. 静态门：`check arkts`（主 + **测试源码显式传路径**）、`check lint` 零错误；`build` 成功；
   `check-l10n` 键集合一致。

**设备验收（模拟器/真机，**需要已登录会话**）**：

7. 课程标签显示当前学期的课程（课程名 + 教师名），非空；
8. 点课程进详情：页签与课程信息可见；返回正常；
9. 切换学期后回到课程标签：列表**变成新学期的课程**，不残留旧学期条目；
10. 无会话/断网时呈现错误态 +「重试」；课程为空时呈空态（不是错误态）。

> 7–10 需要已登录会话；当前模拟器凭据存储为空，**在完成前本 FR 不标完成**。

**需用户确认**：PRD §6 第 2 项里"浏览课程"这一环节。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| 学期 id 进 URL 路径 | 学期 id 形如 `2024-2025-1`（含 `-`，当前形态下编码后不变），但这是外部输入且拼进 path | 写入时 `encodeURIComponent`（同类问题见审查 R-14：票据未编码） |
| 课程响应的实际字段形态 | 上游对 `zywkcm` 做解码、`timeAndLocation` 另取；字段名与嵌套层级需以真实响应为准 | **实现时先打印一次真实响应的字段名清单**（不含敏感信息），再定解析；spec 只写"按上游字段语义"，不臆测嵌套 |
| 课程数量大时的扇出 | FR-06 起按课程扇出取数，课程多则请求多 | 那时按维度并发并**先修 R-03**；必要时加并发上限（届时再定，不提前设计） |
| 课程名缺失影响文件目录 | FR-08 的下载目录用 `courseName` 分段 | 本 FR 的显示名回退保证 `courseName` 非空；FR-08 落地时按其自身规则再校验目录安全 |
| 详情页三块内容的页签先有后填 | 本 FR 交付的是"壳"，页签里先放状态占位 | 与 UI 骨架批次一致（`StateView` 已有三态组件）；FR-06～FR-08 填内容时不改导航结构 |
| 隐藏课程/自定义排序 | 上游有，属设置范畴 | 明确不在本 FR；留给 FR-12 或 FR-16，届时再评估是否需要 |
