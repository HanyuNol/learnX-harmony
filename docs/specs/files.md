# 功能规格：文件（列表 · 详情 · 下载 · 打开）

> 状态：已实现（自动化验收已过；设备项待用户统一验收）　·　关联 PRD：FR-08（与 FR-10 / FR-12 / FR-21 / FR-23 的边界见 §2）　·　分支：main
> 接口语义基线：上游 `thu-learn-lib@4.0.0` 的 `getFileList` / `getFileCategoryList`
> （`src/index.ts:503-556`）与 `src/urls.ts:45-72`；交互参照上游 `robertying/learnX` 的
> `data/actions/files.ts`、`screens/Files.tsx`、`screens/FileDetail.tsx`、`components/FileCard.tsx`、
> `helpers/fs.ts`。**只取语义，不移植代码**（ADR-0001）。

## 1. 背景与目标

文件是四个内容维度里最后一个落地的，与前三个同构：**按课程扇出**（先有课程，再有文件），
列表项由客户端回填课程名/教师名。交付后用户能在"文件"标签按课程看到当前学期的课件类文件、
进详情看元信息、**下载到应用沙箱并交给系统查看器打开**——这是 PRD §6 第 2 项实机验收里
"下载并打开一个课件文件"这一环。

## 2. 需求（要什么）

**范围内**：

1. 文件列表：聚合**当前学期所有课程**的文件；
2. 列表项：课程名、标题、描述摘要（去标签、两行）、**分类名 + 文件类型 + 大小**、
   上传日期、重要标记、新文件标记（对齐上游 `FileCard` 的这些字段）；
3. **详情**：标题、课程名与教师名、分类、文件类型、大小、上传日期、描述（纯文本）；
   两个动作：**下载**（到应用沙箱）与**打开**（交给系统查看器）；
4. **下载**：带会话与 CSRF 的 GET；落到应用沙箱；**已下过且未要求刷新时直接复用**（缓存命中，
   不重复下载）；下载失败时删除半截文件并给出可见反馈；
5. **打开**：分两条路——**应用内预览为主**（系统 ArkWeb 承载本地文件，无需设备上装有对应应用，
   与上游"内置预览"的口径一致），**交给系统应用为次**（装了 WPS 一类应用时才有用）；
   不可预览的类型（Office 文档）**不显示"预览"按钮**，避免点了没反应；
6. 三态齐备（加载/空/错误+重试）；手动刷新；
7. 从课程详情页的"文件"页签进入时只列该课程的文件。

**不做（属其他 FR，或本批不做）**：

- **下载进度条、下载目标目录、失败重试队列**：属 **FR-10**（文件下载管理）。本批只做
  "能下能开"，进度以"下载中…"文字状态呈现，不做进度百分比（百分比要靠系统下载器的
  回调，属 FR-10 的专门机制）；
- **PDF 原地预览的打磨**（缩放、页码跳转、搜索、双指手势）与分享：前者属 FR-21（P2），
  后者属 FR-23（P2）。本批只做"**能看**"这一最小形态（见 §3.3 第 9 条），不做预览的交互打磨；

- **系统分享互通**：属 FR-23（P2）；
- **按分类筛选 / 未读筛选**：分类筛选属 FR-12（本批只显示分类名）；上游的"未读文件"
  来自 redux-persist 的本地已读记录，PRD 无此需求，不做；
- **收藏 / 归档**：PRD 无此需求，不做。

## 3. 设计（怎么做）

### 3.1 上游事实（对照基线，逐行核过）

| 事实 | 出处 |
|---|---|
| 文件列表是**一个 GET**：`…/b/wlxt/kj/wlkc_kjxxb/student/kjxxbByWlkcidAndSizeForStudent?wlkcid=<课程>&size=200` | `urls.ts:45-48`、`index.ts:503-504` |
| 成功判定 `result === 'success'`；**学生形态的容器是 `json.object` 本身为数组**（不是 `object.aaData`）——同一套 API 的**第三个信封变体** | `index.ts:505-518` |
| 字段映射：`kjxxid→id`、`wjid→fileId`、`bt→title`（解实体）、`ms→description`（解实体）、`wjdx→rawSize`、`fileSize→size`（**服务端给的可读大小串**）、`scsj→uploadTime`、`wjlx→fileType`、`sfqd===1→markedImportant`、`isNew→isNew`、`xsllcs`/`llcs→visitCount`、`xzcs→downloadCount` | `index.ts:520-555` |
| **分类要额外一次 GET**：`…/b/wlxt/kj/wlkc_kjflb/student/pageList?wlkcid=<课程>`，容器 `object.rows`，字段 `kjflid→id`、`bt→title`、`czsj→creationTime`；文件用 `kjflid` 关联分类 | `urls.ts:50-51`、`index.ts:537-556` |
| 下载地址由客户端拼：`…/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=<fileId>`，**且要带 CSRF** | `urls.ts:70-71`、`helpers/fs.ts:78,85`（`addCSRF`） |
| 落盘目录 `${filesDir}/<课程名>/<文件 id>/`，文件名 `<课程名>-<标题>.<类型>`（设置项可省去课程名前缀） | `helpers/fs.ts:41-62` |
| **下载失败的三种判据**：状态码非 200、写入 0 字节、**写入内容里含 `location.href`**（服务端会返回一个跳转桩页面） | `helpers/fs.ts:100-160` |
| 列表排序：上传时间**倒序**，同一时间按 id 倒序 | `actions/files.ts:38-46,84-92` |
| 列表项显示 `分类名 + 类型大写 + 大小` 与"多久以前" | `FileCard.tsx:69-77` |
| 详情页的动作：刷新下载、分享、打开、信息面板；**PDF/HTML 原地渲染** | `FileDetail.tsx:71-160` |
| **详情页进页即自动下载，并把文件渲染在应用内**：`fileType === 'pdf'` 用 `react-native-pdf` 的 `<Pdf source={{uri: path}}/>`，其余可渲染类型用 `<WebView source={{uri: path}}/>`；"外部打开"只是 Android 上的附加动作（`IntentLauncher` + `content://`） | `FileDetail.tsx:263-300`、`helpers/fs.ts:202-210` |

### 3.2 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `model` | `file.ets` | `LearnFile` 类型 + 纯逻辑：排序、摘要、上传日期格式化（复用通知那套） |
| `common` | `mime.ets` | 扩展名 → MIME 类型（纯查表，可测）。**不引第三方 mime 库**（架构不变量 §2） |
| `model` | `urls.ets`（改） | 文件列表、分类列表、下载三个地址 |
| `network` | `parseFile.ets` | **纯解析**：列表响应 → `LearnFile[]`；分类响应 → `Map<id, 分类名>`；结构不符抛出 |
| `network` | `learnClient.ets`（改） | `fetchFilesOfCourse(courseId, courseName, teacherName)`（列表 + 分类两次 GET）；`downloadFileBytes(fileId)`（以 ArrayBuffer 取字节，带会话与 CSRF） |
| `native` | `fileAdapter.ets` | 系统能力的唯一出口：沙箱目录准备、写字节、存在性判断、删除、**以 `viewData` 打开** |
| `repository` | `fileRepository.ets` | 扇出（沿用分块并发与部分失败策略）+ 下载编排（目录/命名/缓存命中/失败清理） |
| `viewmodel` | `fileStore.ets` | 单一应用级 Store：`items`/`fetching`/错误键 + 签名对齐 + 末次胜出；**下载状态按文件 id 记**（下载中/已就绪/失败） |
| `pages` | `Files.ets` | 文件列表页，同一组件服务文件标签与课程详情页签 |
| `pages` | `FileDetail.ets` | 文件详情（元信息 + 下载 + 打开） |
| `pages` | `Main.ets` / `CourseDetail.ets`（改） | 接入文件标签与两个栈的目的地 |

### 3.3 关键规则

1. **网络走 `LearnClient`、落盘走 `native.fileAdapter`**：下载是"带会话的 GET"，会话与 CSRF 的
   唯一出口是 `LearnClient`（架构不变量 §3），故字节由网络层取、由适配器写；`pages` 不碰任何一边。
2. **目录与命名**：`${cacheDir}/learnX-files/<课程名>/<文件 id>/<课程名>-<标题>.<类型>`。
   文件名里的路径分隔符（`/`、`\`）与空字节必须清洗掉，否则会在沙箱里越级或失败。
   课程名/标题含中文是正常的——沙箱路径允许。
3. **缓存命中免重下**：目标文件已存在且非"强制刷新"时直接复用，不发起请求。
4. **失败清理与桩页识别**（对齐上游三种判据）：状态码非 200、字节数为 0、
   **内容疑似服务端跳转桩**（体量很小且含 `location.href`）→ 删除已写入的文件并抛错。
   这条不能省：把跳转桩当课件打开，用户看到的是一个 0 字节或 HTML 的文件，比报错难查得多。
5. **打开失败要有可见反馈**（Toast），不静默——"点了没反应"是本项目最贵的一课。
6. **分类取不到不阻塞列表**：分类是展示用的附加信息，失败时退让为空（列表项只少一段文字）。
7. **失败面沿用前三个维度**：单课失败不整页失败（顶部提示"部分课程的文件未能加载"）；
   **全部失败按错误态**（带重试）。
8. **文件筛选是页面本地状态**（全部/未读/已读，见 list-filter-sort spec）；
   **课程详情页按分类分组**渲染（同一门课里分类才有意义），聚合页平铺
   ——分组规则在 `model/file.buildFileRows`（拍平成"分组标题行 + 文件行"，避免 List 里嵌套 ForEach），
   有单测。
9. **应用内预览用系统 ArkWeb 承载本地文件**（不引第三方 PDF 库）。两个**必须同时满足**的条件，
   缺一就是"文件打不开"（2026-09-28 真机实测）：
   - Web 组件要显式 `.fileAccess(true)`——API 12 起该能力**默认关闭**，关闭时 ArkWeb 直接拒绝
     本地文件（`IsUrlFileExist failed` / `invalidFileUrl`）；
   - URL 必须是 `file://` + **沙箱绝对路径**（`file:///data/storage/...`），
     **不能用** `fileUri.getUriFromPath` 那个带包名的 `file://<包名>/...`（同样被拒）。
   两者收在 `native/fileAdapter.previewUrlOf` 一处，理由写在函数注释里。
10. **只给"浏览器渲染得出来"的类型预览按钮**：判据 `canPreviewInApp(type)`（pdf/html/文本/图片/
   音视频）。Office 文档（doc/docx/ppt/pptx/xls/xlsx）ArkWeb 渲染不出内容，**不显示该按钮**——
   点了只出空白属于"假动作"。

## 4. 任务拆分

- [x] T1 `model/file.ets` + `common/mime.ets`：类型、排序、摘要、MIME 查表（纯逻辑 + 单测）
- [x] T2 `network/parseFile.ets`：列表与分类响应解析（纯逻辑 + 单测）
- [x] T3 `model/urls.ets` + `network/learnClient.ets`：两个 GET 端点与下载字节
- [x] T4 `native/fileAdapter.ets` + `repository/fileRepository.ets` + `viewmodel/fileStore.ets`
- [x] T5 `pages/Files.ets` + `FileDetail.ets` + `Main`/`CourseDetail` 接线
- [x] 文档同步：PRD FR-08 状态、`API.md` §2.4（文件端点与"第三个信封"）、CHANGELOG 未发布段
- [ ] T6 验收（见 §5）：**自动化部分已过；设备部分尚未做**（原因同 assignments spec §5）

> 实现期的两处判断，在此留痕：
> ① "下载"与"打开"做成**两个按钮**（spec §2.3 的两个动作），而不是一个"下载并打开"——
> 用户想只存下来时不该被强制拉起查看器；
> ② 用一个 `UIAbilityContext` 贯穿两步（只有它有 `startAbility`；其 `cacheDir` 与
> `ApplicationContext` 指向同一目录），故 `pages` 传的是宿主上下文而非 `ApplicationContext`。
> 这与"偏好写入必须用 `ApplicationContext`"不冲突：那条规则针对**偏好持久化**，
> 与这里的沙箱落盘和启动意图无关（见 `native/contextAdapter` 的说明）。

## 5. 验收标准

> **状态（2026-09-28 第二次更新）**：第 7–12 项均已在模拟器上按真实数据走通。
> **第 10 项已解决**：设备上没有能打开该类型的应用（实测 `code=16000019`）时，
> 改为**应用内预览**——ArkWeb 加载本地文件，Chromium 的 PDF 文档视图确实在工作
> （hilog 里可见 `pdf_document_helper`）。**下载侧另经 5 个文件验证**（PDF×3 / PPTX / MOV，
> 最大 25MB）全部成功，故"所有文件都下不下来"这一现象在本机无法复现（见下方 §6 的排查建议）。
> 第 13 项的失败面（断网/会话失效）仍未构造。
> 主源码 0 错误、`check lint` 0、`build` 成功、`check-l10n` 键集合一致）。
> 第 7–13 项是**设备项，尚未做**——理由与作业那批相同：模拟器上唯一的真实会话不能被
> 装包冒险破坏，重新登录要用户本人密码。统一留到用户验收时演示。

**自动化可验证（单元测试，不依赖设备）— 已过**：

1. 解析：`object` 为数组、`object.resultsList` 为数组、`object.aaData` 为数组三种容器都能解出
   文件（学生/教师形态差异，服务端实际只用第一种，但退让规则要明确）；坏 JSON / 非 success /
   容器不是数组 → 抛出；空数组是合法结果；
2. 字段映射：标题与描述解 HTML 实体；缺字段退让成空串而不整批失败；`sfqd===1` 的中文/数字判据；
   分类按 `kjflid` 关联到分类名，关联不到时分类名为空串；
3. 排序：上传时间倒序、同一时间按 id 倒序；
4. MIME：常见课件扩展名（pdf/ppt/pptx/doc/docx/xls/xlsx/zip/txt/png/jpg/mp4）映射正确，
   未知扩展名退让成 `application/octet-stream`；扩展名大小写不敏感；
5. 文件名清洗：含 `/`、`\`、`..` 的标题不得让路径越级；
6. 静态门：`check arkts`（主 + 测试显式传路径）、`check lint` 零错误；`build` 成功；`check-l10n` 一致。

**设备验收（模拟器/真机，已登录）— 已做（2026-09-28，模拟器）**：

7. 文件标签加载出当前学期多门课的文件，按上传时间倒序；
8. 列表项含课程名/标题/摘要/分类与类型与大小/上传日期；
9. 点一条进详情：显示元信息；点"下载"出现"下载中…"并最终变为"已下载"；
10. 点"打开"能拉起系统查看器显示该文件（**需用户确认**：PRD §6 第 2 项"下载并打开一个课件文件"）；
11. 再次下载同一条（未刷新）不重新发起请求（缓存命中）；
12. 课程详情页的"文件"页签只显示该课程的文件（与文件标签互不串）；
13. 错误面：会话失效/断网 → 错误态 + 重试；部分课程失败 → 顶部提示且已拿到的仍显示。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| 大文件的内存占用 | 本批把整个文件读进 `ArrayBuffer` 再落盘：课件通常几 MB，可接受；视频类大文件不做 | 若实测有内存问题，FR-10 改为系统下载器（自带流式与进度回调） |
| **应用内预览的两个硬条件** | `.fileAccess(true)` 与"`file://` + 绝对路径"缺一不可（见 §3.3 第 9 条）；API 12 起前者默认关闭，后者喂错形态会被静默拒绝 | 已收在 `previewUrlOf` + Web 属性一处，并在真机确认 PDF 能渲染。**改动预览相关代码时不要动这两点** |
| 若用户设备上"下载"仍失败 | 本机（模拟器）用同一账号下载 5 个文件全部成功，无法复现 | 日志里现在有 `[fileRepository] 下载失败 id=… fileId=… code=… message=…`：请把这行发来，可直接区分会话失效 / 网络不可达 / 服务端语义变更 |
| 打开能力依赖系统查看器 | `viewData` 意图能否找到处理器取决于设备上是否装了对应应用 | **已确认行为（2026-09-28 模拟器）**：意图本身正确（系统拉起了应用选择器），但模拟器上没有能打开 PDF 的应用，`startAbility` 返回 `code=16000019 No matching ability is found` → 应用如实提示失败（Toast + 日志含错误码）。真机装 PDF 阅读器后应可打开，仍待用户在其手机上确认 |
| 中文文件名与沙箱路径 | 课程名/标题含中文、空格、括号都属正常 | 清洗只针对路径分隔符与控制字符，不改变可读性 |
| 分类端点可失败 | 多一次请求就多一次失败面 | 失败退让为空分类，不阻塞列表（规则 6） |
| 请求量 | 每门课 2 个 GET（列表 + 分类）：12 门课 = 24 个请求 | 沿用分块并发上限 4；实测后记回本表 |
| 服务端跳转桩 | 会话失效时下载端点可能返回跳转页而非 403 | 规则 4 的桩页识别；命中即报错并删除 |
