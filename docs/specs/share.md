# 功能规格：与系统分享互通（把下载好的文件交给系统分享面板）

> 状态：开发中　·　关联 PRD：FR-23　·　分支：main
> 交互参照上游 `robertying/learnX` 的 `helpers/fs.ts` 的 `shareFile`（RN `Share.open`）。
> **只取语义，不移植代码**（ADR-0001）。

## 1. 背景与目标

下载好的课件落在**应用沙箱**里，只有应用自己看得见；用户想把某份课件发给同学、存进网盘或
丢进微信，此前没有任何出路（"另存为"只能存到本机某个目录，出不了这台设备）。
本 FR 补上这条出口：**把已下载的文件交给系统分享面板**，由系统决定给谁、到哪里。

## 2. 需求（要什么）

**范围内**：

1. **文件详情页**新增「分享」：把该文件交给系统分享面板（发给联系人、存到网盘/其他应用）；
2. **作业附件行**同样有「分享」——老师附件 / 我提交的附件 / 评语附件**三处共用同一行**，
   故一处改动三处生效；
3. **未下载时先自动下载再分享**：与「打开」「另存为」一致（都是"确保在沙箱 → 再动作"），
   用户不必先点一次下载；
4. **失败要看得见**：分享面板起不来（系统侧异常）必须有提示，不静默；
5. 分享的是**沙箱里的那一份拷贝本身**（不复制、不改名），用户拿到的文件名就是文件列表里
   看到的那个。

**不做（范围外）**：

- **接收外部分享**（把本应用注册成系统分享目标）：**不做**。两条理由：
  ① **收进来没有落地动作**——本项目没有"从外部导入文件"的入口。上游接这个能力是为了一件
  具体的事：把别处拿到的文件当**作业附件**提交（`App.tsx` 注册、`AssignmentSubmission.tsx`
  消费）。本项目要做就得新开一条冷启动路径（额外 Ability + 技能声明 + 落地页 + 权限），
  **面大而收益窄**，属镀金（`scope-discipline.md`）；
  ② 真要做，落地点是"作业提交时的附件候选"，与"分享出去"不是同一件事，应单独立项。
- **分享正文文本**（通知正文 / 作业描述）：不做。正文的可用形态要么是 HTML（对方未必能读、
  还可能带脚本）、要么是剥标签纯文本（本项目已刻意不再用 `plainText` 渲染正文，且剥出来会
  丢掉公式与图片）——**没有一个形态是"分享出去也好看"的**，收益不明确。本 FR 聚焦文件。
- **分享完成后的回执与统计**：不订阅 `shareCompleted`（用户分享到哪儿、成没成，
  是系统 UI 与用户之间的事，拿来打点属越界）；面板被取消（`dismiss`）也**不提示**——
  取消不是失败。

## 3. 设计（怎么做）

### 3.1 上游事实（对照基线）

| 事实 | 出处 |
|---|---|
| `shareFile(file)`：**先确保下载**，再 `Share.open({ filename: '<标题>.<类型>', url: path, type: mime,\n  title: '分享文件', showAppsToView: true, failOnCancel: false })` | `src/helpers/fs.ts` |
| 入口在**文件详情工具栏**的 `ios-share` 图标（禁用条件是"出错或还没下载"） | `src/screens/FileDetail.tsx` |
| 上游另用 `react-native-share-menu` **接收**外部分享，落在作业提交页当附件候选 | `src/App.tsx`、`src/screens/AssignmentSubmission.tsx` |

> 与上游的**有意不同**：① 不做接收（§2）；② 上游在 iOS/Mac 上还有"拷到下载目录"，
> 本项目已有「另存为」（FR-10）覆盖同一需求，不重复。

### 3.2 模块与文件

| 层 | 文件 | 职责 |
|---|---|---|
| `native` | `shareAdapter.ets`（新） | **Share Kit 的唯一出口**：构造 `SharedRecord` → `ShareController.show` |
| `common` | `fileUtd.ets`（新） | **纯逻辑**查表：扩展名 → UTD（分享记录的类型描述） |
| `repository` | `fileRepository.ets`（改） | `shareOf`：确保文件在沙箱 → 交给 `shareAdapter`；失败归类 |
| `viewmodel` | `fileStore.ets`（改） | `share` / `shareAttachment`：复用下载状态机与四分类失败语义 |
| `pages` | `FileDetail.ets`、`AssignmentDetail.ets`（改） | 各加一个「分享」按钮 |
| 文案 | `common/texts.ets` + 两份 `string.json` | `file_share`、`file_share_failed` |

### 3.3 关键规则

1. **API 形状**（`@hms.collaboration.systemShare`，经 `@kit.ShareKit`）：
   `new systemShare.SharedData(record)` → `new systemShare.ShareController(data)` →
   `show(context, { selectionMode: systemShare.SelectionMode.SINGLE })`。
   **构造参数是 `SharedRecord`（不是 `ShareData`）**，唯一必填字段是 `utd`；
   文件用 `uri`，文字用 `content`，另有可选的 `title`/`description`/`thumbnail`。
   返回的 Promise 失败会抛 `1003702001 记录类型不支持` / `1003702002 IPC 数据过大`。
   **不需要新增任何权限**（带 `SET_SYSTEMSHARE_APPLAUNCHTRUSTLIST` 的那个仅用于设置目标应用白名单，
   本 FR 不用）。
2. **必须传 `UIAbilityContext`**：分享面板是 ability 级 UI，与日历同一条教训
   （`ApplicationContext` 拿不到需要 ability 的能力）。
3. **`uri` 用"应用沙箱文件 URI"**：`fileUri.getUriFromPath(path)`（形如 `file://<包名>/data/...`）——
   系统据此给目标应用**临时读授权**。**不是** `previewUrlOf` 那个 `file://` + 绝对路径形态
   （那是喂 ArkWeb 的，见 `native/fileAdapter` 的说明）。
4. **类型（`utd`）如实描述、认不出来就退让**：按扩展名查表，命中不了用 `general.file`。
   查表只在**已确认存在**的 UTD 常量里取值（`@ohos.data.uniformTypeDescriptor`），**不猜**字符串。
5. **取消不是失败**：面板被划掉、用户没选目标，都不提示。
6. **不改文件名、不做临时副本**：分享的就是沙箱里那一份（`另存为` 已经覆盖"复制一份"的需求）。

## 4. 任务拆分

- [x] T1 `common/fileUtd.ets`（纯逻辑 + 穷举测试）
- [x] T2 `native/shareAdapter.ets`（Share Kit 出口）
- [x] T3 `fileRepository.share` / `shareAttachment` + `fileStore.share` / `shareAttachment`
- [x] T4 两处入口（文件详情 / 附件行）+ 文案键（`check-l10n` 一致）
- [x] T5 文档同步：本 spec、PRD FR-23、`API.md`、`CHANGELOG.md`

## 5. 验收标准

**自动化（已过）**：

1. `fileUtd` 4 组用例：已确认的扩展名各自命中正确 UTD；未知/空/大写/带点一律退让 `general.file`；
2. 静态门：`check arkts` 主 92 / 测试 25 文件 0 error、`check lint` 0 error、`build` 成功、
   **278 例单测 0 失败**、`check-l10n` 一致（base/en_US 204 键）。

**设备验收（模拟器 learnx / 真实账号，2026-09-29）**：

3. ✅ 文件详情页出现「分享」按钮（节点树 `('分享', (490, 2080))`），动作行重排为
   2+2+2（下载/重新下载 · 预览/打开 · 另存为/分享），4 个按钮挤一行会溢出；
4. ✅ 点「分享」（PDF 课件）：日志 `[fileRepository] 文件已在本地，直接复用 id=…` →
   系统分享面板启动。**面板日志给了三条硬证据**：
   - `[FSUtils] getTotalSizeByUris end 1` + `update summary size 3507456`
     ——面板**真的读到了沙箱里的文件字节**（大小与文件列表的 3.0M 一致），
     也就是 §3.3 第 3 条那个"沙箱文件 URI 能否被系统读取"成立；
   - `refreshViewProperties summary {"summary":{"com.adobe.pdf":1},…,"uriCount":1,"totalCount":1}`
     ——查表给出的 `utd` 被面板采纳、识别为 PDF（§6 第 2 条风险解除）；
   - `[SummaryViewModel] indexTitle is 分享 1 项` + 枚举出分享目标（华为分享等 4 个）
     ——面板**确实弹出**且带 1 条记录。全程无 `分享失败` 日志（`show` 未 reject）。
5. ✅ 作业附件行同样三按钮（查看/下载/分享，节点树 `('分享', (667, 2144))`）；
   点「分享」后 `[fileRepository] 文件已在本地，直接复用 id=2021311552_ZY_…`，
   面板 `summary size 144581`、`{"com.adobe.pdf":1}`——附件这条走通。
6. ⚠️ **未验**：在面板里**真的选一个目标把文件发出去**（模拟器上只有一个"华为分享"目标，
   且需要另一台设备/账号）；这一条属系统侧行为，按 §2 应用不追踪结果。

> 面板是**系统 UI（独立窗口）**，不进本应用的节点树——这也是"分享成功了没有"不能靠
> `ui layout` 判断的原因，证据只能来自系统侧日志（`A07dfe/SystemShare`）。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| ~~模拟器上有没有分享面板~~ | 曾是最大的不确定项：面板是系统 UI（HMS Share Kit 的 system share ability），模拟器上未必装了它 | **已实测：模拟器上有**（面板进程 `A07dfe/SystemShare` 启动、弹出并枚举出 4 个目标）。失败提示那条降级路径仍然成立（`show` reject → Toast） |
| ~~`uri` 形态是否被接受~~ | 沙箱文件的 `file://<包名>/…` 是否被 Share Kit 认可 | **已实测：认可**——面板按该 URI 读出了文件真实字节数（`getTotalSizeByUris`） |
| 没在面板里真的选目标发出文件 | 模拟器只有一个"华为分享"目标，实际发送需要另一台设备/账号 | 属系统侧行为，应用按 §2 不追踪结果；留作"未验" |
| 一次只能分享一个文件 | `SelectionMode.SINGLE`；多选模式官方只支持**批量文件记录**（错误码 `1003702001`） | 本 FR 的场景就是"分享某一个文件"；将来若要"批量分享"，需按官方约束改成批量记录 |
