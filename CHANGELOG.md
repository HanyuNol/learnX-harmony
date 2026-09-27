# 变更日志

本项目所有值得注意的变更都记录在此。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## 0.5.0（2026-09-27）

> **首个可交付版本：在真实账号 + 校园网下完成一次完整登录，且登录态跨进程存活。**
> 版本级别说明：此前 `VERSION` 只是占位 `0.1.0`、仓库无任何 tag，本次为首次发版；
> 按 0.x 语义（尚未达到 MVP 完成度）定为 **0.5.0**——登录这条地基已通，内容页尚待实现。

### 新增

- SDD 治理与规格体系：PRD（30 个 FR / 3 期）、ARCHITECTURE、API、SECURITY、OPERATIONS、
  9 条 ADR（0001–0009）、防漂移规则（`.claude/rules/`）与协作模板（`.github/`）
- HarmonyOS 工程 `app/`（API 24，包名 `io.github.hanyunol.learnx`），构建–安装–启动闭环打通
- **认证与凭据（FR-01 / FR-02 / FR-03 / FR-04）**：
  - **登录主路径为 WebView（ArkWeb）主导**（ADR-0008）：应用内打开真实统一身份认证页，
    注入脚本 `resources/rawfile/sso_inject.js` 预填学号密码、按用户意图回答"是否信任此浏览器"、
    抓取完整表单体；用户在其中完成认证（含多因子验证码——**应用不代填、不代答**）
  - 会话建立采用**漫游票据优先**（ADR-0009）：用 `onLoadIntercept` 截到的漫游地址直接换会话，
    不需要重新认证、也不依赖"设备已被登记为信任浏览器"
  - 备选路径（纯 API 登录）、启动时静默恢复、会话失效后自动重登一次
  - 凭据经**关键资产存储服务**加密保存（ADR-0007）；设备指纹生成后持久化复用
  - 会话 Cookie 由 `webview.WebCookieManager` 承载，WebView 与 API 请求共享同一份会话
  - 错误四分类落地为用户可见文案；「信任浏览器名额已满」给出可操作引导
- 纯逻辑模块与 6 个测试套：`sm2Format` / `parse` / `setCookie` / `ssoForm` / `errors` / `logger`
- `scripts/check-sso-inject.mjs`：注入脚本的入口点检查（见"修复"末条）

### 变更

- 登录入口由"直接发 API 登录请求"改为跳转 WebView 登录页；纯 API 登录降为备选路径
- 清理 Cookie 由"清空全部"改为"**只清会话 Cookie**"——保留服务端可能用于认设备的持久 Cookie
  （对齐上游：它只清 `id` 域的 `JSESSIONID`）
- 登出**保留设备指纹**：原实现连同指纹一起清除，导致每次登出再登录都被服务端当成新设备
- PRD 中 FR-02（统一身份认证）由 P2 提为 P1；`scope-discipline.md` 与 `testing-and-quality.md`
  两处与 ADR-0008 冲突的口径同步更正

### 修复（除标注外，均为真机实测暴露——静态检查与单测都发现不了）

- **凭据存储首登失败**：`asset.update` 对不存在的资产返回 **401 参数错误**（而非假设的未找到），
  首登在取设备指纹一步即中断 → 改为"先 `add`、已存在则先删再 add"
- **登录按钮在软键盘弹出时不可达**：表单原先垂直居中且不可滚动 → 改为可滚动
- **「登录」按钮永远点不动**：密码字段改为非 `@State` 后输入不再触发界面重建，按钮 `enabled` 卡在 false
- **进入 SSO 页即失败**：`startSso` 先切状态、再准备注入取值，页面在取值就绪前就渲染了
- **静默恢复登录态会清掉持久化的会话** → 改为"先看会话是否还活，失效才重新登录"
- **「登出后再登录仍需二次验证」**：登出把设备指纹一并清除（见"变更"）
- **注入脚本误报 `PREFILL_FAILED` 掐断已成功的认证**：脚本在每个文档上注入，验证码通过后页面
  跳到门户，它在那里等 20 秒便判定"登录页结构变了"，应用据此中止流程把用户踢回登录界面
  → 判据收紧为"**按 URL 就是登录表单页**却仍填不进去"
- **「浏览器处于隐私或匿名模式」**：校方页面用第三方库 `detectIncognito` v1.4.1 判断隐私模式，
  其判据是"存储配额 < 2×JS 堆上限"，在移动端 WebView 上**误报**
  （实测 ArkWeb 报 3504MB < 阈值 4178MB）→ 注入脚本把两个配额查询接口的读数抬到阈值之上，
  `isPrivate` 由 true 变 false（有修复前后对照日志）
- **「网络异常，请重新登录或稍后重试」**：注入脚本内一处**未声明的变量赋值**在严格模式下抛
  `ReferenceError`，而它恰在 `XMLHttpRequest.prototype.send` 覆盖里——"保存信任浏览器"的请求
  根本没发出，页面只显示该提示、应用侧一条日志都没有
  → 修复；并新增 `scripts/check-sso-inject.mjs`：在桩沙箱里执行脚本、推进其定时器、
  **主动调用被覆盖的 `send`** 并断言请求体改写生效。已验证该检查能抓住此类缺陷，
  且已并入提交前门（`.claude/rules/static-analysis.md` §2）

### 移除

- 自管 Cookie 容器 `network/cookieJar.ets`（改由 `WebCookieManager` 承载）；
  其 Set-Cookie 切分逻辑保留为 `network/setCookie.ets`

### 已验证

- 单元测试：`hvigorw test` **65 个用例全部通过，0 失败**（Local Test 宿主侧运行，无需设备）
- `devecocli check arkts` 主源码 21 文件 + 测试 7 文件零错误；`check lint` 零问题；`build` 成功
  （产物 `entry-default-unsigned.hap`）
- 注入脚本入口点检查通过
- **设备实测**（模拟器 `learnx`，HarmonyOS 6.1.1 / API 24）：
  - **真实账号 + 校园网登录成功**（用户确认）；日志 `漫游票据建会话成功` / `建会话方式=漫游票据`
  - 杀进程重开后 `沿用已持久化的会话` + `已恢复登录态`，无需再次登录
  - 凭据零泄漏：全量 hilog 4427 行中，明文密码与学号出现 **0 次**
  - 真实账号输错密码时应用不误报（由页面自行提示），应用侧无任何失败上报

### 未验证与已知限制

- **断网表现未端到端复验**：`PAGE_LOAD_FAILED → 网络不可达` 的归类有单测覆盖、代码路径已就位，
  但"断网进入 SSO 页时的实际呈现"未在断网环境下单独复验 → 并入 FR-15（加载/空/错误态）一起做
- 平台依赖层（`sm2` / `learnClient` / `webCookieStore` / `credentialStore` / `repository` /
  `viewmodel` / `pages`）无单元测试覆盖，只能在设备上人工验证
- 登录页存在一个未处理的 Promise 拒绝（原因对象无 `message`，暂未命名）；与票据路径无关，
  若要让"重新登录"兜底路径也可用则需查清
- 构建产物**未签名**；安装到真机或上架前需 `devecocli auth login` → `devecocli signature generate`
- 上游 13 个依赖补丁隐含的行为语义，仍需在实现对应 FR 时逐条反推
