# 功能规格：认证与凭据（账号密码登录 · 凭据存储 · 登录态）

> 状态：开发中　·　关联 PRD：FR-01 / FR-03 / FR-04　·　分支：main

> **实现进展（2026-09-27）**：T1–T8 已实现，`check arkts` / `check lint` / `build` 三道静态关卡全绿。
> **但单元测试与实机验收均尚未执行**——单元测试需连接设备（官方：命令行执行测试脚本需 `aa test` 推送测试包到设备），
> 当前无设备也无模拟器。详见 §5 的说明与 §6 风险表。因此本 spec **不得**标记为已交付。

## 1. 背景与目标

P1 的地基。所有其余 FR（学期、通知、作业、文件、课程）都必须先有"能认证、能发请求"的前提，因此本功能先做。

要解决的问题：在 HarmonyOS 上复刻 learnX 的网络学堂认证链——用学号密码换到会话，并让后续请求自动携带会话与 CSRF 令牌；同时把凭据安全地存在设备上，让用户不必每次登录。

**三个 FR 合成一个 spec 的原因**：它们共用同一组模块（`network` / `storage` / `repository` / `model`），无法单独交付。

## 2. 需求（要什么）

- **FR-01**：以学号 + 密码登录网络学堂，登录成功后持久化会话与凭据，下次启动免登录。
- **FR-03**：凭据（学号、密码）与设备指纹必须以系统加密能力存储；不落明文、不入日志、不进代码、不入库。
- **FR-04**：应用启动与每次请求前校验登录态；服务端判定会话失效时给出明确提示并引导重新登录，不静默失败、不白屏。

**范围内**：

- 账号密码登录（含上游的 SM2 加密与漫游工单流程）
- CSRF 令牌的获取与注入
- 会话内的 Cookie 复用
- 凭据的加密存储与读取
- 登录态判定、失效识别、一次自动重登
- 承载上述能力所需的**最小登录界面**（输入框 + 登录按钮 + 错误提示），使 FR-01 可在真机上被用户验收

**不做（范围外，属其他 FR）**：

- **FR-02 统一身份认证（SSO）** —— 走 WebView，另行实现。本 spec 不得埋 SSO 的占位字段或空壳。
- **FR-24 生物识别** —— 另行实现。
- **FR-15 加载态/空态/错误态体系** 与 **FR-13 主题**、**FR-14 国际化** —— 横切能力，另行实现。本功能只做能用的最小错误提示，不引入主题与多语言框架。
- **FR-11 导航** —— 登录成功后先跳到一个临时占位页，不做标签导航。
- 注册、找回密码、修改密码 —— 网络学堂不提供，本项目也不做。

## 3. 设计（怎么做）

### 3.1 模块与文件

| 模块 | 文件 | 职责 |
|---|---|---|
| `model` | `auth.ets` | `Auth`、`LoginState`、`AuthError`（四分类）、`UserInfo`、`FailReason` 概念 |
| `model` | `urls.ets` | 网络学堂与统一身份认证的 URL 常量（对齐上游 `thu-learn-lib/src/urls.ts` 中认证相关项） |
| `common` | `logger.ets` | 分级日志，**内置凭据脱敏**：任何入参先经脱敏再输出 |
| `common` | `errors.ets` | 错误四分类的构造与归一（网络不可达 / 认证失败 / 接口语义变更 / 解析失败） |
| `network` | `sm2Format.ets` | SM2 密文裸格式：坐标补零、C1C3C2 拼接、公钥解析。**纯逻辑，不依赖系统能力** |
| `network` | `sm2.ets` | SM2 加密（调平台加密框架），产出服务端可接受的提交值 |
| `network` | `parse.ets` | 登录链路 HTML 抓取：SM2 公钥、漫游工单、CSRF 令牌、用户名的提取。**纯逻辑** |
| `network` | `cookieJar.ets` | 自管 Cookie：解析、按主机分组、注入。**纯逻辑**（见 §3.4） |
| `network` | `learnClient.ets` | HTTP 唯一出口：会话、CSRF 注入、失效自动重登、七步登录流程 |
| `storage` | `credentialStore.ets` | 凭据的唯一读写入口（关键资产存储服务） |
| `repository` | `authRepository.ets` | 编排：登录 / 登出 / 会话校验 / 用户信息 |
| `viewmodel` | `authStore.ets` | 应用级会话状态（单一 Store，见 ADR-0004），供页面订阅 |
| `pages` | `Login.ets` | 最小登录界面 |
| `pages` | `Index.ets` | 改为：未登录 → 显示登录界面；已登录 → 临时占位页 |

> **相对原设计新增 3 个文件**（`sm2Format.ets` / `parse.ets` / `cookieJar.ets`），理由一致：
> 把**与外部服务互操作的高风险逻辑**（密文拼接、页面抓取、Cookie 解析）做成不依赖系统能力的纯模块，
> 从而能在无设备环境下单元测试。这是实现期发现的重要约束——若与平台调用混在一起，
> 这些最易出错的逻辑将完全无法离线验证。

依赖方向严格遵循 `pages → viewmodel → repository → network/storage`，`model`/`common` 为叶子层（架构不变量 §1）。

### 3.2 登录流程（对齐上游 `thu-learn-lib@4.0.0` 的真实契约）

**这是本功能的核心，逐步照实复刻，不凭印象发挥**：

1. **清会话**：把 `id.tsinghua.edu.cn` 的 `JSESSIONID` 置空，确保总是从登录页开始（避免沿用他人/他次会话）。
2. **取 SM2 公钥**：`GET https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0`，从响应 HTML 中提取 `#sm2publicKey` 元素文本，即公钥的十六进制串。
3. **提交登录**：`POST https://id.tsinghua.edu.cn/do/off/ui/auth/login/check`，表单字段：
   - `i_user` = 学号
   - `i_pass` = `'04'` + SM2 加密结果（详见 §3.3）
   - `singleLogin` = `on`
   - `fingerPrint` = 设备指纹（32 位十六进制，随机生成后持久化，见 §3.5）
   - `fingerGenPrint` = 空串、`fingerGenPrint3` = 空串（上游亦传空串；语义未知，**不臆测其含义**）
   - `i_captcha` = 空串
4. **取漫游工单**：从步骤 3 响应 HTML 中取首个 `<a>` 的 `href`，其 `ticket` 查询参数值即工单。
5. **漫游到网络学堂**：`GET https://learn.tsinghua.edu.cn/b/j_spring_security_thauth_roaming_entry?ticket=<ticket>`；非 2xx 即失败。
6. **取 CSRF 令牌**：`GET https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/`，用正则 `/^.*&_csrf=(\S*)".*$/gm` 提取令牌；提取不到即判定为"接口语义变更"。该令牌**在登录/重登后失效**，必须随之刷新。
7. **后续请求**：对 `*.tsinghua.edu.cn` 的请求，一律以**查询参数** `_csrf=<token>` 追加（上游 `addCSRFTokenToUrl` 的行为）。

### 3.3 SM2 加密（本功能最大的技术风险点）

上游用 JS 库 `sm-crypto` 的 `sm2.doEncrypt(password, publicKey)`，其输出为**裸十六进制**，再前置 `'04'` 组成提交值。服务端期望的就是这个**非 ASN.1 的裸拼接格式**。

HarmonyOS 侧用 `@ohos.security.cryptoFramework`（非对称加解密当前仅支持 RSA 与 SM2，见官方 API 文档）：

- **公钥构造**：页面给的是裸十六进制（`04` + 32 字节 X + 32 字节 Y）。用 `createAsyKeyGeneratorBySpec()` 配合 ECC/SM2 密钥参数（由 X、Y 构造）得到公钥对象，**不走** PEM/X.509 路径。
- **加密**：SM2 非对称加解密，`init` 后直接 `doFinal`（该算法不支持 `update`）。
- **密文格式转换（关键）**：框架的密文为 ASN.1(DER)，而服务端要裸拼接。用 `SM2CryptoUtil.getCipherTextSpec(cipherText, 'C1C3C2')` 取出 `C1_X` / `C1_Y` / `C2` / `C3` 分量，再手工拼成 `'04' + C1_X + C1_Y + C3 + C2` 的十六进制串。官方文档明确提示：**拼接时 X、Y 分量若不足 32 字节须高位补零**。
- 该"手工拼接"是与外部服务互操作所必需的约束，代码处须留注释说明原因（否则后人会误以为是冗余代码）。

> 具体的公钥参数构造 API 形态需在实现期以官方文档与实机编译为准；若 `createAsyKeyGeneratorBySpec` 无法直接接受裸 X/Y，则改用 `ECCKeyUtil` 生成点参数，路线不变。此点列为 §6 待定项。

### 3.4 会话与 Cookie（实现期修正）

> **本节原设计已被实现推翻**：原计划用 `@ohos.net.http` 的 `enableAutoCookie(true)`
> 自动复用 Cookie，但实测该接口**起始版本为 API 26**，本项目 SDK 为 API 24，不可用。
> 改为**自管 Cookie 容器**（`network/cookieJar.ets`）。

- `LearnClient` 全程复用**同一个 `HttpRequest` 实例**。
- 每次响应后用 `response.cookies`（原始 Cookie 串，API 8+）更新自管容器；
  每次请求前按**主机名**注入 `Cookie` 请求头。
- **按主机名精确分组**，不做 Domain 匹配：本项目 Cookie 只落在
  `id.tsinghua.edu.cn` 与 `learn.tsinghua.edu.cn` 两个主机上，精确分组既够用又不引入歧义；
  登录横跨两个主机，分组错了会串会话。
- 重置会话即清空该容器（对齐上游"登录前清 JSESSIONID"的意图，且效果更强）。
- Cookie 串解析是纯逻辑，已单测覆盖（含属性剔除与跨主机隔离）。

### 3.5 凭据与设备指纹存储

存入**关键资产存储服务**（`@ohos.security.asset`），别名固定：

| 键 | 内容 | 说明 |
|---|---|---|
| `learnx.username` | 学号 | |
| `learnx.password` | 密码 | 仅在用户勾选"记住密码"时写入 |
| `learnx.fingerPrint` | 设备指纹 | 32 位十六进制随机串；**首次生成后持久化**，不随登录变化（上游每次登录用新随机值，本项目改为持久化以避免服务端把它当新设备；此差异记入 §6） |

- 唯一读写入口是 `storage/credentialStore.ets`；其余模块不得直接调用该 Kit。
- 登出时**必须**清除全部凭据与指纹。
- 该选择与备选方案的取舍见 ADR-0007。

### 3.6 登录态判定与失效重登

- **失效信号**（对齐上游 `noLogin`）：响应最终 URL 含 `login_timeout`，或 HTTP 状态为 403。
- **自动重登**：带凭据的请求命中失效信号时，自动重登**一次**并重放该请求；再次失效则向上抛出认证失败，不再循环。
- 无凭据（用户未保存密码）时命中失效信号 → 直接抛认证失败，由页面引导重新登录。
- **错误四分类**（对应 ARCHITECTURE §5.4）：
  - 网络不可达（超时、DNS、连接失败）
  - 认证失败（凭据错误、会话失效且无法重登）
  - 接口语义变更（登录页找不到 SM2 公钥、找不到工单锚点、提取不到 CSRF、非预期状态码）
  - 解析失败（响应体结构不符预期）
- 服务端/网络问题**不得**报成应用缺陷。

### 3.7 重试

上游对登录本身有一次重试包装。本项目同样仅对**登录**加一次重试，且**只对网络不可达类**重试；认证失败与语义变更类**不重试**（重试无意义且会放大失败）。

## 4. 任务拆分

- [x] T1 `model`：`auth.ets`、`urls.ets`
- [x] T2 `common`：`logger.ets`（含凭据脱敏）、`errors.ets`（四分类）
- [x] T3 `network`：`sm2Format.ets`（纯格式）+ `sm2.ets`（平台加密）
- [x] T4 `network`：`parse.ets`、`cookieJar.ets`（纯逻辑）、`learnClient.ets`（会话与七步登录）
- [x] T5 `storage/credentialStore.ets`：关键资产存储读写与清除
- [x] T6 `repository/authRepository.ets` + `viewmodel/authStore.ets`
- [x] T7 `pages/Login.ets` 最小登录界面；`pages/Index.ets` 登录态分发
- [x] T8 测试：4 个测试套 + 入口（`entry/src/test/`）已编写且通过类型检查
- [ ] **执行测试**：需连接设备（`aa test` 推送测试包），当前无设备 → **未执行**
- [x] T9 文档同步：PRD 状态、ARCHITECTURE §5.1/§5.2、API.md §2.1、CHANGELOG

## 5. 验收标准

> **执行状态（2026-09-27）**：以下第 1–6 项的测试**已编写**（`entry/src/test/`，4 个测试套，通过 ArkTS 类型检查），
> 但**尚未执行**——HarmonyOS 的单元测试需连接设备/模拟器（命令行经 `aa test` 推送测试包），当前两者都没有。
> 因此第 7 项（静态检查与构建）**已通过**，第 1–6、8–11 项**均未验证**。本 spec 在测试真正跑过之前不得标记已交付。

**自动化可验证（单元测试，不依赖校园网）**：

1. `sm2`：给定固定公钥与明文，输出为 `04` 起始、总长符合 `02 + 64 + 32 + 32` 字节的十六进制；X/Y 分量不足 32 字节时正确补零。
2. `learnClient`：从样例登录页 HTML 能提取出 SM2 公钥；从样例 check 响应能提取出 ticket；从样例课程页能提取出 CSRF 令牌。
3. `learnClient`：样例响应 URL 含 `login_timeout` 或状态 403 时，被正确归类为认证失效。
4. `errors`：构造网络超时、凭据错误、缺公钥、响应畸形四类输入，断言归类互不串台（尤其网络问题不得归为应用缺陷）。
5. `credentialStore`：写入后读取一致；清除后读不到；**断言凭据值不出现在任何日志输出中**。
6. `authStore`：登录态迁移（未登录 → 登录中 → 已登录 / 失败）不出现非法中间态。

**构建与静态检查**：

7. `devecocli check arkts` 与 `devecocli check lint` 零错误；`devecocli build` 成功。

**【需用户确认】实机与真实环境验收（校园网 + 真实账号）**：

8. 在校园网（或校方 VPN）与模拟器/真机上，用真实学号密码完成登录，进入占位页；杀进程重开仍保持登录态。
9. 断网启动：呈现"网络不可达"提示，不白屏、不崩溃；恢复网络后可重试成功。
10. 故意输错密码：呈现"认证失败"提示，且**不被误报为网络或应用缺陷**。
11. 检查设备与日志：无明文凭据落盘、无凭据出现在日志中（可用 `devecocli log` 抽查）。

> 第 8–11 项需在校园网内由用户确认。**单元测试全绿不替代它们**；在本项目具备校园网环境前，本 spec 不得标记为已交付。

## 6. 风险 / 待定

| 项 | 说明 | 处置 |
|---|---|---|
| **测试与实机验收无法执行** | 无设备、无模拟器；单元测试需 `aa test` 推包到设备 | **这是当前最大的未验证面**。需先登录华为账号建模拟器（或接真机），否则本功能无法声称可用 |
| **登录表单提交格式未验证** | 上游用 multipart（RN 的 FormData），本项目用 `application/x-www-form-urlencoded`，理由是该校方页面为标准 HTML 表单 | 实现已按 urlencoded 提交；**若服务端只接受 multipart，登录会失败**，改动局限于 `learnClient.postForm` 一处。需真机验证 |
| SM2 密文格式互操作 | 框架输出 ASN.1，服务端要裸 C1C3C2 | 已按官方文档拼接（含坐标补零），并有单测；**仍需真机验证服务端是否接受** |
| `enableAutoCookie` 不可用（API 26） | 原设计依赖该接口，实测本 SDK(24) 无此接口 | 已改为自管 Cookie 容器（§3.4），并有跨主机隔离单测 |
| 公钥构造 API 形态 | `createAsyKeyGeneratorBySpec` + `ECCKeyUtil.genECCCommonParamsSpec('NID_sm2')` | 已通过 ArkTS 类型检查，说明签名匹配；运行时行为待验证 |
| 会话失效判定差异 | `HttpResponse` 不暴露重定向后 URL，改为 403 或响应体含 `login_timeout` | 已实现；若服务端以其他方式表达失效，需按现象补判据 |
| 登录页/校验接口可能变更 | 抓不到公钥、锚点、CSRF 即全链路失效 | 归入"接口语义变更"类错误并给出明确提示；解析集中在 `parse.ets` 便于修 |
| `fingerGenPrint` / `fingerGenPrint3` 语义未知 | 上游传空串 | 本项目同样传空串，不臆测 |
| 设备指纹持久化 vs 上游每次随机 | 上游每次登录生成新指纹，本项目持久化 | **有意差异**，避免服务端视为新设备；若服务端行为异常则回退到每次随机 |
| 无校园网即无法验证真实登录 | 阻塞第 8–11 项验收 | 验收集中在校园网时段完成 |
| 凭据存储的 Kit 行为（如设备锁屏态） | 关键资产存储服务在某些状态下可能要求设备解锁 | 实现已把失败分支归入认证失败并给出可理解提示 |
