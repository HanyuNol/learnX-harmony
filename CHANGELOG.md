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

### 已验证

- 无设备构建闭环打通：`devecocli check arkts` 零错误（3 个文件）；`devecocli build` 成功（31 s），产物 `entry-default-unsigned.hap`
- 工具链环境脱离 `C:` 盘：`HVIGOR_USER_HOME` 与 `DEVECO_CLI_DATA_DIR` 均已重定向，`~/.hvigor` 不存在

### 已知限制

- 构建产物未签名（无 `signingConfigs`）——安装到设备前需华为账号完成
  `devecocli auth login` → `devecocli signature generate`
- `C:` 盘仍有约 73 KB 的 ohpm 注册表元数据缓存（`~/.ohpm`），量级可忽略但非零占用
