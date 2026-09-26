# 运维手册：learnX 鸿蒙版

> 部署、升级、备份恢复、回滚、排障的操作指南。运维方式变化时更新。
> 本项目是客户端应用，没有服务端；"运维"指**开发环境的搭建与维护**，以及应用的构建、签名、安装。

## 1. 部署（开发环境搭建与首次构建）

### 1.1 前置要求

| 组件 | 要求 | 本机实际 |
|---|---|---|
| Node.js | ≥ 22 | v24.15.0 |
| DevEco Studio | ≥ 6.0.0（`emulator` 子命令需 ≥ 6.1.0） | **6.1.1.418**，装于 `D:/DevEco Studio` |
| 随附 HarmonyOS SDK | — | API **24**（6.1.1.125 Release） |
| JDK | 21 | Studio 自带 JBR；系统另有 JDK 21 |
| 华为开发者账号 | 模拟器启动、调试签名需要 | **首次启动未要求登录**——登录只在启动模拟器 / 签名时触发 |
| 校园网 / 校方 VPN | 端到端验收与真实数据调试的前提（见 ADR-0006） | — |

> **DevEco Studio 必须由用户从华为开发者联盟下载中心用华为账号手动下载并安装到 `D:` 盘**——下载中心不向非浏览器请求开放（返回 403），无法脚本化获取。

> **安装与工程路径必须为纯 ASCII**：工程路径含中文触发错误码 `00306002`（构建硬失败）；`DevEco Studio` 安装路径含空格时须用 `HVIGOR_USER_HOME` 规避 `00308002`。详见 ADR-0005。

### 1.2 环境变量（每次调用 devecocli / hvigor 前必须设置）

> 未设置时 devecocli 回退默认路径（**C 盘**），hvigor 缓存落到 `~/.hvigor` —— 而 `C:` 盘空间不足以容纳 SDK 与模拟器镜像。

```bash
export DEVECO_CLI_STUDIO_PATH="D:/DevEco Studio"     # DevEco Studio 根（含空格，故下一行必设）
export HVIGOR_USER_HOME="D:/harmonyos/hvigor"        # 无空格路径，规避 00308002
export DEVECO_CLI_DATA_DIR="D:/harmonyos/.deveco-data"  # 文档库与 CLI 数据
export DEVECO_CLI_DISABLE_TELEMETRY=1                # 关闭遥测
export PATH="/d/harmonyos/npm-global:$PATH"          # devecocli 本体所在
```

`DEVECO_SDK_HOME` 无需设置：SDK 随 Studio 在 `D:/DevEco Studio/sdk`，工具链自动识别。

### 1.3 首次构建（已实测通过，2026-09-26）

工程信息：根 `app/`，应用名 `learnX`，包名 `io.github.hanyunol.learnx`，API level 24。

```bash
cd app
devecocli check arkts          # 结果：No errors found in 3 file(s)
devecocli build                # 结果：BUILD SUCCESSFUL in 31 s 692 ms
```

产物：`app/entry/build/default/outputs/default/entry-default-unsigned.hap`。

> `build` 会告警 `Will skip sign 'hos_hap'. No signingConfigs profile is configured` —— **这是预期**：签名需要华为账号（见 `signature generate`）。未签名的 HAP 不能安装到设备，但**构建闭环无需账号即可验证**。

整包（`.app`）用 `devecocli build --product <name>`。

### 1.4 健康检查（怎么算环境是好的）

```bash
devecocli --version            # 应输出 1.3.4 或更高
devecocli docs catalog         # 能返回文档分类 = 工具链根被正确识别
devecocli build                # 在 app/ 下能成功构建
devecocli device list          # 能列出设备/模拟器（需先有设备或模拟器）
```

`devecocli docs catalog` 报 `DevEco Studio installation not found` 即表示 `DEVECO_CLI_STUDIO_PATH` / `DEVECO_CLI_CLT_PATH` 未生效——**这是最常见的环境问题，且它会让包括 `create`、`docs` 在内的所有子命令都失败**。

## 2. 升级

- **devecocli**：`devecocli update`。
- **SDK / DevEco Studio**：属架构决策，**先写 ADR 再升级**（见 ARCHITECTURE §6）。
- **依赖（ohpm）**：走 `sdd-bump-dependencies`，最小升级 + 回归。
- 升级后必须重跑 §1.4 健康检查与验证门。

## 3. 数据备份与恢复

**应用数据**（用户侧）：凭据与偏好存于设备，应用卸载即清除；课件文件存于应用沙箱或用户文档目录。本项目**不提供云端备份**，也不应在本机留存用户数据副本。

**开发侧**：需备份的是 `app/` 源码与仓库根的治理文档——二者同仓，即仓库本身。工具链（SDK、模拟器镜像）可重装，不需备份。

### 恢复演练

从零克隆仓库 → 按 §1 重建环境 → 跑通 §1.4 健康检查与 `devecocli build`。**该项在首次成功构建后由用户在本机执行一次并记录结论**；在此之前不得声称环境可复现。

## 4. 回滚

- **代码**：`git revert` 目标提交（遵循 `.claude/rules/git-commit.md` §4.4，禁止重写已共享历史）。
- **应用侧**：重新安装上一个已知良好的 HAP。
- **环境侧**：SDK / Studio 版本回退需同步回退 `app/build-profile.json5` 的 SDK 版本声明，否则构建失败。
- **数据边界**：应用无服务端数据，回滚不涉及数据迁移；但缓存格式变更时需在应用内清缓存。

## 5. 排障

| 现象 | 排查路径 | 处置 |
|---|---|---|
| `DevEco Studio installation not found` | 检查 `DEVECO_CLI_STUDIO_PATH` / `DEVECO_CLI_CLT_PATH` 是否设置且指向真实目录 | 设置环境变量（§1.2） |
| 构建报 `00306002`（`The Node directory and node name cannot contain Chinese characters`） | 工程路径是否含中文 | **移除路径中的中文字符**（官方处置）；即 ADR-0005 §决策 4 |
| 构建报 `00306003 工程路径无效` | 路径是否含中文或非白名单字符 | 路径只允许字母/数字/`-`/`_`/`.`/英文括号/空格/`@` |
| 构建报 `00308002` 且提示 `Space is not supported in HVIGOR_USER_HOME` | `HVIGOR_USER_HOME` 或 Studio 安装路径含空格 | 设 `HVIGOR_USER_HOME` 到无空格路径（§1.2） |
| 构建/模拟器因空间不足失败 | 检查 `C:` 与目标盘剩余空间 | 确认工具链全部在 `D:`；`devecocli build clean` |
| 构建告警 `skip sign 'hos_hap'` | 工程未配置签名 | 预期行为；需装到设备时先跑 `devecocli auth login` → `signature generate` |
| 模拟器启动失败 | 官方已知原因：路径含中文、内存不足、显卡驱动过低、CPU 不支持 AES、SDK 路径变更 | 按官方 FAQ 逐项核对；**AppData/安装/工程路径均不得含中文** |
| 模拟器提示需在 DevEco Studio 内登录 | 模拟器启动需华为账号登录 | 在 DevEco Studio 中登录后从设备管理启动（首次启动无登录提示属正常） |
| `install sign info inconsistent` | 签名材料变更 | `devecocli run --uninstall` 或 `devecocli signature generate --force` |
| 应用内一切请求超时 | 是否处于校园网 / 校方 VPN 内 | 属预期边界（ADR-0006），非缺陷 |
| 登录后立刻失效 | Cookie 未正确保存或注入 | 检查 `storage.CredentialStore` 与 `LearnClient` 的 Cookie 注入路径 |
| 应用崩溃 | `devecocli log --crash --bundle-name io.github.hanyunol.learnx` | 按崩溃栈定位；`devecocli log --level E` 看错误级日志 |

**关键日志位置**：应用运行日志经 `devecocli log` 获取；构建日志在 `app/.hvigor/` 下；Hvigor 用户级缓存与日志在 `D:/harmonyos/hvigor`（`HVIGOR_USER_HOME`）。
