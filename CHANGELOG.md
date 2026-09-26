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

- 无设备构建闭环打通：`devecocli check arkts` 零错误（16 个主源码文件）、
  `devecocli check lint` 零问题、`devecocli build` 成功
- 测试文件本身通过 ArkTS 类型检查（6 个文件）
- 工具链环境脱离 `C:` 盘：`HVIGOR_USER_HOME` 与 `DEVECO_CLI_DATA_DIR` 均已重定向，`~/.hvigor` 不存在

### 未验证（重要）

- **单元测试尚未执行**——HarmonyOS 单元测试需连接设备（经 `aa test` 推送测试包），
  当前无设备也无模拟器。5 个测试套只通过类型检查，**没有跑过一次**
- **实机与真实环境验收未做**——校园网 + 真实账号的完整登录链路、断网提示、
  凭据落盘抽查，均未验证
- 因此 FR-01 / FR-03 / FR-04 状态为**开发中**，不是已交付

### 已知限制

- 构建产物未签名（无 `signingConfigs`）——安装到设备前需华为账号完成
  `devecocli auth login` → `devecocli signature generate`
- 登录表单以 `application/x-www-form-urlencoded` 提交（上游用 multipart），
  若服务端只接受 multipart 需改 `learnClient.postForm` 一处
- `C:` 盘仍有约 73 KB 的 ohpm 注册表元数据缓存（`~/.ohpm`），量级可忽略但非零占用
- 工程脚手架文件（`EntryAbility.ets` 等）保留华为模板的 Apache-2.0 头，
  与本项目 MIT 许可并存，属正常的多许可混合
