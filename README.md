# learnX 鸿蒙版

> 清华大学网络学堂的 HarmonyOS NEXT 原生客户端。由开源 React Native 应用 [learnX](https://github.com/robertying/learnX) 重建而来。

## 当前状态

功能已完整可用，版本 `0.7.0`（见 `VERSION`）。已实现的包括：

- 登录：统一身份认证（WebView 主路径，验证码由用户输入）、凭据加密存储、记住密码、生物识别快速登录；
- 内容：通知（富文本 + 数学公式）、作业（含提交）、课件文件（下载管理、应用内预览）、课程与课表；
- 增强：全局搜索、筛选排序、作业截止提醒与课程表写入系统日历、启动后台预载、分享导出、更新日志；
- 体验：主题与多语言、骨架屏与过渡动效、无障碍（可读名称、触摸目标、大字号）。

仓库同时包含完整的 SDD 治理文档（PRD / 架构 / ADR / 功能规格），源码在 `app/`（ArkTS / ArkUI，API 24）。

**安装**：仓库不提供签名后的安装包。自行构建需 DevEco Studio 与华为开发者账号（调试签名会自动登记本机设备），步骤见 [docs/OPERATIONS.md](docs/OPERATIONS.md) §1 与 §9。

## 这是什么

- **是**：一个 HarmonyOS NEXT 原生应用（ArkTS / ArkUI），登录清华网络学堂后查看通知公告、作业、课件文件与课程信息，支持下载、提醒与日历同步。
- **不是**：不是跨平台方案，不含 React Native 运行时；不是服务端，不做代理或中转；**不是清华官方客户端**。
- 校外访问需要校方 VPN——网络学堂本身仅在校园网内可达（见 [ADR-0006](docs/adr/0006-external-dependency-and-campus-network.md)）。

## 系统由哪些部分组成

```
仓库根：SDD 治理 + 文档
├── docs/                      PRD（要什么）/ ARCHITECTURE（怎么建）/ API / ADR（为什么这么定）/ specs
├── .claude/rules/             防漂移规则（迭代时强制遵守）
├── app/                       HarmonyOS 工程（ArkTS / ArkUI，包名 io.github.hanyunol.learnx）
│   └── entry/src/main/ets/     pages · components · viewmodel · repository · network
│                               · storage · native · model · i18n · common
└── VERSION / CHANGELOG.md / SECURITY.md / LICENSE
```

> **工程路径必须为纯 ASCII**：含中文会被官方错误码 `00306002` 直接拒绝（详见 [ADR-0005](docs/adr/0005-repo-layout-and-toolchain-paths.md)）。

分层为单向依赖：`pages → viewmodel → repository → network/storage/native`，`model`/`common` 为叶子层。详见 [ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 关键决策

| 决策 | 结论 | ADR |
|---|---|---|
| 迁移路线 | 原生 ArkTS/ArkUI 重建（RNOH 因不支持 RN 0.87 且无 Expo 生态而否决） | [0001](docs/adr/0001-native-rewrite-over-rnoh.md) |
| 许可 | MIT，保留上游归属 | [0002](docs/adr/0002-mit-license-and-attribution.md) |
| 视觉 | 采用鸿蒙原生设计语言，不复刻 Material 3 | [0003](docs/adr/0003-harmonyos-native-design-over-material.md) |
| 状态管理 | ArkUI 原生状态 + 单一应用级 Store，不引第三方状态库 | [0004](docs/adr/0004-state-management.md) |
| 仓库与工具链 | 治理在根、工程在 `app/`；工具链全部落 `D:` 盘 | [0005](docs/adr/0005-repo-layout-and-toolchain-paths.md) |
| 外部依赖 | 不自建中转；接受"仅校园网可达"为前提 | [0006](docs/adr/0006-external-dependency-and-campus-network.md) |

## 快速开始

环境搭建（含必须的 `D:` 盘环境变量）与构建命令见 [docs/OPERATIONS.md](docs/OPERATIONS.md) §1。

> **前置**：DevEco Studio 需用户自行从华为开发者联盟下载中心下载并用华为账号安装到 `D:` 盘——该下载不支持脚本化获取。

## 文档导航

| 文档 | 内容 |
|---|---|
| [docs/PRD.md](docs/PRD.md) | 需求与路线图；FR 表是需求的唯一真源 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 模块、依赖方向、数据模型、关键机制 |
| [docs/API.md](docs/API.md) | 外部接口语义基线、系统互通契约、模块边界 |
| [docs/adr/](docs/adr/) | 重大决策记录 |
| [docs/specs/](docs/specs/) | 功能级工作规格（开发期） |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | 环境搭建、构建、排障 |
| [docs/SECURITY.md](docs/SECURITY.md) | 信任模型与凭据处理 |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | 协作与迭代流程 |

## 许可与归属

[MIT](LICENSE) © 2026 learnX-harmony contributors

功能设计与接口对接方式参照上游开源项目：

- [robertying/learnX](https://github.com/robertying/learnX)（MIT，© Rui Ying）——功能参照源
- [Harry-Chen/thu-learn-lib](https://github.com/Harry-Chen/thu-learn-lib)——网络学堂接口语义参照

随包分发的第三方组件：

- [KaTeX](https://katex.org/)（MIT，© Khan Academy 及贡献者）——通知与文件描述中的数学公式渲染

本项目**不复制上游代码**，为独立实现。**非清华大学官方应用**，与校方无隶属关系。
