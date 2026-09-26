# 代码风格与静态检查（防风格 / 质量漂移）

> 统一格式化与静态检查，把低级问题挡在提交之前。

## 1. 本项目的工具链

| 用途 | 工具 | 调用方式 |
|---|---|---|
| 代码规范检查 | DevEco Code Linter | `devecocli check lint`（可用 `--fix` 自动修复可修项） |
| ArkTS 静态检查 | DevEco `etsStandaloneChecker` | `devecocli check arkts` |
| 格式化 | DevEco Studio 内置格式化 / `.editorconfig` | IDE 内格式化；缩进与换行按仓库根 `.editorconfig` |
| API 兼容性扫描 | DevEco `apkanalyzer-apiscan` | `devecocli check compat`（跨 SDK 版本迁移时用） |

- 规则集固定在工程根的 `app/code-linter.json5`，**不随个人机器变化**。
- `devecocli check arkts` 的节奏：**一轮编辑结束后、构建之前跑一次**，不要每次编辑都跑（它是全项目扫描）。

## 2. 强制要求

- **提交前**：本次改动范围内必须同时满足
  1. `devecocli check arkts` 零错误；
  2. `devecocli check lint` 零错误；
  3. 项目可构建（`devecocli build`）。
  未满足不得形成最终提交（与 `testing-and-quality.md` 的验证门同级）。
- **CI 门禁**：本项目当前为单人开发、**暂未接入 CI**。若后续接入，上述三项必须作为合并前的强制门禁，与测试同级。
- **依赖漏洞**：ohpm 依赖引入或升级时走 `sdd-bump-dependencies` 流程（读变更说明、最小升级、跑回归），升级后重跑上列三项。
- **禁用某条 lint 规则**：必须在 `code-linter.json5` 中集中声明并注明原因，**不得**在代码里零散地内联关闭。
- 工具与规则版本固定（写进配置），避免不同机器结果不一致。

## 3. 与现有规则的关系

- 本规则是 `testing-and-quality.md` 的补充：测试管"行为对不对"，静态检查管"写法干不干净"。
- 静态检查通过**不替代**测试，也**不替代**实机验收（见 `docs/PRD.md` §6）。
- ArkTS 的语言限制（禁 `any`、禁反射、禁动态属性）属架构不变量，见 `architecture-invariants.md` §4——由 `check arkts` 客观强制。
