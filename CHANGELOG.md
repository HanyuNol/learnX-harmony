# 变更日志

本项目所有值得注意的变更都记录在此。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增

- 初始化 SDD 项目治理：PRD / ARCHITECTURE / API / SECURITY / OPERATIONS 与 6 条 ADR
- 安装防漂移规则（`.claude/rules/`）与协作模板（`.github/`）
- 确定迁移路线：以 ArkTS / ArkUI 原生重建，否决 RNOH 移植路线（ADR-0001）
- 创建 HarmonyOS 工程（`app/`，API 24，包名 `io.github.hanyunol.learnx`）
- 建立 ADR-0005：仓库布局、工具链落盘 `D:` 盘，以及工程路径的 ASCII 硬约束
- **认证与凭据（FR-01 / FR-03 / FR-04）实现**：网络学堂七步登录（含 SM2 国密加密密码、
  漫游工单换会话、CSRF 令牌提取与注入）、凭据经关键资产存储服务加密保存、
  登录态校验与失效自动重登一次；四类错误分开归类；最小登录界面与登录态分发页
- 纯逻辑模块（`sm2Format` / `parse` / `cookieJar`）与 5 个单元测试套

### 已验证

- **单元测试已实际执行**（`hvigorw test`，Local Test 宿主侧运行、**无需设备**）：
  **37 个用例全部通过，0 失败**。行覆盖率：`sm2Format` 100%、`errors` 100%、
  `parse` 96.4%、`cookieJar` 94.1%
- 单元测试过程中抓出并修复一处真实缺陷：`parseCookies` 只取第一个分号片段，
  遇到 `garbage; a=1` 这类输入会丢弃真正的 Cookie
- `devecocli check arkts` 零错误（主源码 16 文件 + 测试 6 文件）、`check lint` 零问题、`build` 成功
- 工具链环境脱离 `C:` 盘：`HVIGOR_USER_HOME` 与 `DEVECO_CLI_DATA_DIR` 均已重定向，`~/.hvigor` 不存在

### 真机验证发现并修复的缺陷

- **凭据存储首登失败**：`asset.update` 在资产不存在时返回 **401 参数错误**（而非假设的 24000002 未找到），
  导致首登在取设备指纹一步即中断。改为「先 `add`、已存在则先删再 `add`」。
  修复前 `devecocli run` 报 `Smoke: FAIL_CRASH`，修复后为 `Smoke: PASS`
- **登录按钮在键盘弹出时不可达**：表单原先垂直居中且不可滚动，软键盘弹出后
  「记住密码」「登录」被挤出可交互区域。改为 `Scroll` 包裹

> 这两处都不是静态检查能发现的——只有真正跑起来才会暴露。

### 真机验证结论（模拟器 `learnx`，HarmonyOS 6.1.1 / API 24）

在模拟器上安装、启动、并以假凭据驱动完整登录流程，实测得到：

- 应用安装启动正常，界面渲染正确（UI 节点树含标题、两个输入框、复选框、登录按钮）
- **登录链实际执行到第 4 步**：HTTP 可达 `id.tsinghua.edu.cn`；
  **SM2 公钥提取与加密实际运行无误**（本项目最大的技术风险点由此得到验证）；
  表单提交被服务端受理并返回
- 假凭据下正确呈现「未取得漫游工单，通常是学号或密码错误」，归类为**认证失败**，
  未被误报为网络问题或应用缺陷

### 未验证（重要）

- **真实凭据下的登录成功路径未验证**——需要校园网与真实账号，由用户确认
- **`urlencoded` 与上游 multipart 的差异未排除**：假凭据下无法区分"密码错误"与
  "表单格式不被服务端接受"这两种原因，该风险仍开放
- **平台依赖层仍无单元测试覆盖**：`sm2` / `learnClient` / `credentialStore` / `repository` /
  `viewmodel` / `pages` 依赖系统能力，宿主侧跑不了，只能在设备上人工验证（已完成一次）
- 因此 FR-01 / FR-03 / FR-04 状态为**开发中**，不是已交付

> 更正：本文件此前记录"单元测试需连接设备，无法执行"——**该结论是错的**。
> 需要设备的是 Instrument Test（`aa test`）路径；Local Test 经 `hvigorw test` 在宿主机直接运行。

### 已知限制

- 构建产物未签名（无 `signingConfigs`）——安装到设备前需华为账号完成
  `devecocli auth login` → `devecocli signature generate`
- 登录表单以 `application/x-www-form-urlencoded` 提交（上游用 multipart），
  若服务端只接受 multipart 需改 `learnClient.postForm` 一处
- `C:` 盘仍有约 73 KB 的 ohpm 注册表元数据缓存（`~/.ohpm`），量级可忽略但非零占用
- 工程脚手架文件（`EntryAbility.ets` 等）保留华为模板的 Apache-2.0 头，
  与本项目 MIT 许可并存，属正常的多许可混合
