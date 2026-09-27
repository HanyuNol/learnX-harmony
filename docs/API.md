# 接口契约：learnX 鸿蒙版

> 对外接口的单一真源。始终原地更新到当前契约。

本项目是纯客户端，**不对外提供服务端接口**。本文档记录三类契约：
§2 为**所依赖的外部接口语义基线**（接口变更的对照依据），§3 为**应用与系统 / 其他应用之间的互通契约**，§4 为**项目内部模块边界契约**。

## 1. 通用约定

- **协议形态**：应用与校方服务之间为 HTTP(S)；与系统能力之间为 HarmonyOS Kit 接口；内部模块之间为 ArkTS 接口。
- **认证**：基于会话 Cookie（登录后由 `network/LearnClient` 统一注入），写操作另需 CSRF 令牌。
- **编码**：请求与响应按 UTF-8 处理；表单提交按 `multipart/form-data`（对齐上游的 FormData；
  urlencoded 经对照实验证实同样被服务端接受），GraphQL 按 `application/json`。
- **超时**：单次请求超时上限 15s（对应 NFR-PERF）；超时归入"网络不可达"类错误。
- **分页**：全部数据按学期一次性获取后本地分页/筛选，不做服务端分页（与上游行为一致）。
- **版本**：无显式接口版本；语义变更通过 §2 的对照基线发现。

## 2. 所依赖的外部接口语义基线

> 本节的目的是**在接口发生变更时能快速定位影响面**，不是逐字段抄录上游文档。字段语义以参照实现 `thu-learn-lib` 为准。

### 2.1 登录（主路径＝WebView 主导；备选＝纯 API）

登录**不在网络学堂完成**，而是经统一身份认证换工单、再漫游回网络学堂。
**主路径由 ArkWeb 承载真实认证页**（ADR-0008）——因为多因子认证的验证码只能由用户在真实页面上输入。

#### 2.1.1 主路径：WebView 主导（FR-01 + FR-02）

- **页面**：`GET https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0`
  - 在应用内 `Web` 组件中打开，`javaScriptOnDocumentStart` 注入脚本（仅匹配 `id.tsinghua.edu.cn`）
  - 注入脚本预填 `input#i_user` / `input#i_pass`（只读），用户其余步骤在页面内完成
- **信任浏览器登记**：页面以 XHR `POST /b/doubleAuth/personal/saveFinger` 询问"是否信任此浏览器"
  - 注入脚本覆写该请求体：`fingerprint` = 应用持久化设备指纹、`deviceName` = 设备名、`radioVal` = `是`
  - **该方法与验证码无关**：验证码由用户自行输入，应用不代填、不代答
- **表单抓取**：提交时注入脚本抓取完整表单体（urlencoded）经 JS 通道回传
  - 字段：`i_user`、`i_pass`、`singleLogin`、`fingerPrint`、`fingerGenPrint`、`fingerGenPrint3`、`i_captcha`
  - 其中 `fingerPrint` / `fingerGenPrint` / `fingerGenPrint3` **只能由页面生成**，应用无法自行构造
- **认证完成判据**：导航目标命中 `https://learn.tsinghua.edu.cn/f/j_spring_security_thauth_roaming_entry`
  （注意与下方 API 侧漫游的 `/b/...` 是两条不同路径，上游两者都在用）
- **建会话（两条路径，按可靠性排序）**：
  1. **首选：用截到的漫游地址里的 `ticket` 直接发起漫游**（`GET <截到的漫游地址>`）——
     它就是浏览器原本要做的那一步，不需要密码、也不需要设备已被登记为信任浏览器；
     随后取首页 CSRF 令牌。
  2. **兜底：带页面生成的设备信任标识重新登录**——从抓到的表单体取出
     `fingerPrint` / `fingerGenPrint` / `fingerGenPrint3`，在**全新会话**里由新公钥重新加密
     密码再登录（对齐上游 `thu-learn-lib` 的同名参数）。**不重放页面那份密文**：
     它与页面会话绑定，实测真实账号下拿不到工单。
- **错误**：用户中途关闭页面 → 归"用户取消"，不报错；认证页结构变化 → **接口语义变更**；
  页面提示"信任浏览器数量已达到上限"或"浏览器处于隐私模式" → 给出可操作引导，见 spec §8.2 / §9

#### 2.1.2 备选路径：纯 API 七步登录（仅未启用多因子认证的账号、静默恢复与自动重登）

- **步骤 1｜取登录页**：`GET https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0`
  - 响应：HTML，其中含 `id="sm2publicKey"` 的元素，文本为 SM2 公钥十六进制串
  - 若响应含 `checkSingle` → 改用**已信任设备**表单（步骤 2'）
  - 若响应含 `$("#c_code").removeClass('hidden');` → 需要图形验证码，本项目不做识别，归**接口语义变更**并引导走网页登录
  - 错误：取不到公钥 → **接口语义变更**
- **步骤 2｜提交凭据**：`POST https://id.tsinghua.edu.cn/do/off/ui/auth/login/check`
  - 请求：`multipart/form-data`（对齐上游的 FormData；**对照实验表明 urlencoded 同样被接受**，两种编码都不是失败原因）

    | 字段 | 取值 |
    |---|---|
    | `i_user` | 学号 |
    | `i_pass` | `04` + SM2 加密结果（裸 C1C3C2 十六进制） |
    | `singleLogin` | `on` |
    | `fingerPrint` | 设备指纹，32 位十六进制 |
    | `fingerGenPrint` | 空串（语义未知，不臆测） |
    | `fingerGenPrint3` | 空串 |
    | `i_captcha` | 空串 |

  - 响应：HTML，含跳转锚点 `<a href="...ticket=xxx">`
  - 错误：取不到锚点/工单 → 通常是凭据错误，归**认证失败**；响应含「二次认证」→ **接口语义变更**（该账号必须走主路径）
- **步骤 2'｜已信任设备**：`POST https://id.tsinghua.edu.cn/do/off/ui/auth/login/checkSingle`
  - 请求：`i_rememberme` = `on`、`fingerPrint`、`fingerGenPrint`（不再需要密码）
- **步骤 3｜漫游建会话**：`GET https://learn.tsinghua.edu.cn/b/j_spring_security_thauth_roaming_entry?ticket=<ticket>`
  - 响应：非 2xx 即失败；成功后 `learn.tsinghua.edu.cn` 下发送会话 Cookie
- **步骤 4｜取 CSRF**：`GET https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/`
  - 响应：HTML，含形如 `&_csrf=<token>"` 的片段
  - 错误：提取不到 → **接口语义变更**
- **后续请求**：对 `*.tsinghua.edu.cn` 一律追加查询参数 `_csrf=<token>`

**会话失效的表达**：响应状态 `403`，或最终落到含 `login_timeout` 的页面。

**会话 Cookie 的载体**：`webview.WebCookieManager`（进程级、与 WebView 共享），
而非应用自管容器——主路径的"重放同一份会话"依赖它。见 ADR-0008 与 ARCHITECTURE §5.1。

### 2.2 统一身份认证（SSO）的页面结构依赖

主路径依赖校方页面的以下结构，**全部集中在 `resources/rawfile/sso_inject.js` 一处维护**
（校方改版时只改这一个文件，失败会归入"接口语义变更"而不是被误报成"密码错误"）：

| 依赖 | 用途 |
|---|---|
| `input#i_user` / `input#i_pass` | 预填学号与密码 |
| `[name="fingerPrint"]` / `[name="singleLogin"]` | 提交前写入应用指纹、勾选单点登录 |
| XHR 路径 `/b/doubleAuth/personal/saveFinger` | 回答"是否信任此浏览器" |
| 页面文案「信任浏览器数量」 | 名额已满时回报，触发可操作引导 |
| 提交事件（原生 `submit` 捕获 + jQuery `$.fn.submit` 覆写） | 抓取完整表单体；**两条路径并存**，因为 ArkWeb 不保证页面用 jQuery 提交 |

- **错误**：用户中途放弃 → 归入"用户取消"，不报错

### 2.3 学期列表与当前学期

- **路径**（对齐上游 `thu-learn-lib@4.0.0` 的 `src/urls.ts`，**照抄，不要改写**）：
  - 学期 id 列表：`GET {LEARN_PREFIX}/b/wlxt/kc/v_wlkc_xs_xktjb_coassb/queryxnxq`
    → **JSON 字符串数组**，服务端偶发返回 `null` 项，解析时过滤
  - 当前与下一学期：`GET {LEARN_PREFIX}/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester`
    → 要求 `message === 'success'`，当前学期取 `result.id`
- **注意形态**：这两个端点是 `/b/...`，与认证期的 `/f/...` **不是同一类路径**，不要"统一"
- **学期 id 形态**：`YYYY-YYYY-N`，N 为 1=秋 / 2=春 / 3=夏；本项目按 id 派生显示用的年份与季节
- **响应**：学期标识列表 + 当前学期
- **当前学期归属**：由服务端给出，但客户端**只在本地没存过时采用**，不覆盖用户的手动选择
- **错误**：解析失败 → 归入"解析失败"并记录原始响应片段（**不含凭据**）

### 2.4 通知 / 作业 / 文件 / 课程（四类内容数据）

- **课程列表路径**（照抄上游 `urls.ts:34-37`，学生形态，两个路径参数都做 URL 编码）：
  `GET {LEARN_PREFIX}/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/{semester}/{lang}`
  - 判定：`message === 'success'` 且 `resultList` 是数组
  - 字段映射：`wlkcid→id`、`zywkcm→name`、`kcm→chineseName`、`ywkcm→englishName`、
    `jsm→teacherName`、`jsh→teacherNumber`、`kch→courseNumber`、`kxh→courseIndex`
    （名称类字段需解 HTML 实体）
  - `lang` 取 `zh`/`en`（对齐上游 `Language` 枚举），由 `native/localeAdapter` 按系统语言给出
- **通知/作业/文件**：**按课程取**，请求带课程 id（非学期 id）；三者都从课程列表派生 courseIds 再扇出
- **请求**：按学期参数（课程）／按课程参数（通知/作业/文件）
- **响应**：各维度条目列表；作业含截止时间与完成/提交状态；文件含下载地址
- **错误**：单维度失败不得阻塞其他维度（见 ARCHITECTURE §5.3）

### 2.5 文件下载

- **路径**：文件条目给出的下载地址
- **方式**：带会话 Cookie 的 HTTP GET，落盘至应用沙箱目录
- **错误**：下载中断需可重试；响应非文件类型时归入"解析失败"

### 2.6 课程信息共享（CourseX，可选）

- **方法 / 路径**：`POST https://api.tsinghua.app/v1/graphql`
- **请求**：GraphQL 查询
- **响应**：课程共享信息
- **错误**：第三方服务不可用 → 该功能整体不可用（FR-27 为 P3，允许放弃）

## 3. 与系统 / 其他应用的互通契约

| 能力 | 契约 | 约束 |
|---|---|---|
| 分享导出 | 分享 Kit：以 URI + MIME 类型发起系统分享 | 仅分享用户主动选择的文件/文本 |
| 接收分享 | 声明接收的 MIME 类型，由系统拉起并传入 URI | 仅处理白名单类型，未知类型忽略 |
| 系统日历 | 日历 Kit：创建/更新/删除日程，记录日程 ID 以支持增量同步 | 需用户授权；拒绝授权不影响主流程 |
| 本地通知 | 通知 Kit：按作业截止时间提交定时通知 | 需用户授权；同一条目不得重复通知 |
| PDF 查看 | PDF Kit：以本地文件路径打开 | 仅打开已下载的本地文件 |
| 文件选择 | 文件选择器：由系统 UI 返回 URI | 仅请求所需类型 |
| 生物识别 | 用户认证 Kit：发起认证并接收结果 | 不得作为凭据的替代存储；认证失败回退到密码 |

## 4. 内部模块边界契约

| 边界 | 职责 | 禁止 |
|---|---|---|
| `network.LearnClient` | 校方请求的唯一出口；Cookie 与 CSRF 统一处理 | 任何上层模块不得自行发 HTTP 请求 |
| `network.WebCookieStore` | 会话 Cookie 的唯一载体（`webview.WebCookieManager`）；WebView 与 API 共享 | 其余模块不得自行读写 Cookie |
| `native.resourceAdapter` | 应用资源（rawfile）读取的唯一出口 | 页面不得直接调 `resourceManager` |
| `native.deviceAdapter` | 设备信息的唯一出口 | 页面不得直接调 `deviceInfo` |
| `network` 对内暴露 | 返回数据或归类后的错误 | 不得泄漏底层 HTTP 细节到上层 |
| `storage.CredentialStore` | 凭据读写唯一出口 | 其他模块不得直接触碰凭据存储 |
| `native.*Adapter` | 各系统能力的唯一出口 | 不得在 `pages` / `viewmodel` 中直接调用系统 Kit |
| `model` / `common` | 叶子层，供各层依赖 | 不得 import 任何上层模块 |
