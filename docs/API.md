# 接口契约：learnX 鸿蒙版

> 对外接口的单一真源。始终原地更新到当前契约。

本项目是纯客户端，**不对外提供服务端接口**。本文档记录三类契约：
§2 为**所依赖的外部接口语义基线**（接口变更的对照依据），§3 为**应用与系统 / 其他应用之间的互通契约**，§4 为**项目内部模块边界契约**。

## 1. 通用约定

- **协议形态**：应用与校方服务之间为 HTTP(S)；与系统能力之间为 HarmonyOS Kit 接口；内部模块之间为 ArkTS 接口。
- **认证**：基于会话 Cookie（登录后由 `network/LearnClient` 统一注入），写操作另需 CSRF 令牌。
- **编码**：请求与响应按 UTF-8 处理；表单提交按 `application/x-www-form-urlencoded`，GraphQL 按 `application/json`。
- **超时**：单次请求超时上限 15s（对应 NFR-PERF）；超时归入"网络不可达"类错误。
- **分页**：全部数据按学期一次性获取后本地分页/筛选，不做服务端分页（与上游行为一致）。
- **版本**：无显式接口版本；语义变更通过 §2 的对照基线发现。

## 2. 所依赖的外部接口语义基线

> 本节的目的是**在接口发生变更时能快速定位影响面**，不是逐字段抄录上游文档。字段语义以参照实现 `thu-learn-lib` 为准。

### 2.1 登录（账号密码）

登录**不在网络学堂完成**，而是经统一身份认证换工单、再漫游回网络学堂。

- **步骤 1｜取登录页**：`GET https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0`
  - 响应：HTML，其中含 `id="sm2publicKey"` 的元素，文本为 SM2 公钥十六进制串
  - 错误：取不到该元素 → **接口语义变更**
- **步骤 2｜提交凭据**：`POST https://id.tsinghua.edu.cn/do/off/ui/auth/login/check`
  - 请求：`application/x-www-form-urlencoded`

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
  - 错误：取不到锚点/工单 → 通常是凭据错误，归**认证失败**
- **步骤 3｜漫游建会话**：`GET https://learn.tsinghua.edu.cn/b/j_spring_security_thauth_roaming_entry?ticket=<ticket>`
  - 响应：非 2xx 即失败；成功后 `learn.tsinghua.edu.cn` 下发送会话 Cookie
- **步骤 4｜取 CSRF**：`GET https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/`
  - 响应：HTML，含形如 `&_csrf=<token>"` 的片段
  - 错误：提取不到 → **接口语义变更**
- **后续请求**：对 `*.tsinghua.edu.cn` 一律追加查询参数 `_csrf=<token>`

**会话失效的表达**：响应状态 `403`，或最终落到含 `login_timeout` 的页面。

> 待真机验证项：登录表单的提交格式。上游用 multipart（React Native 的 FormData），
> 本项目按"该校方页面是标准 HTML 表单"的判断改用 urlencoded。若服务端只接受 multipart，
> 改动局限于 `learnClient.postForm`。

### 2.2 统一身份认证（SSO，属 FR-02，尚未实现）

- **路径**：`https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/<token>/0`
- **方式**：WebView 流程；用户在页面内完成认证后，从 WebView 会话中提取 Cookie
- **错误**：用户中途放弃 → 归入"用户取消"，不报错

### 2.3 学期列表

- **路径**：网络学堂学期接口
- **响应**：学期标识列表 + 当前学期
- **错误**：解析失败 → 归入"解析失败"并记录原始响应片段（**不含凭据**）

### 2.4 通知 / 作业 / 文件 / 课程（四类内容数据）

- **路径**：网络学堂对应维度的数据接口（语义详见 `thu-learn-lib`）
- **请求**：按学期参数
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
| `network` 对内暴露 | 返回数据或归类后的错误 | 不得泄漏底层 HTTP 细节到上层 |
| `storage.CredentialStore` | 凭据读写唯一出口 | 其他模块不得直接触碰凭据存储 |
| `native.*Adapter` | 各系统能力的唯一出口 | 不得在 `pages` / `viewmodel` 中直接调用系统 Kit |
| `model` / `common` | 叶子层，供各层依赖 | 不得 import 任何上层模块 |
