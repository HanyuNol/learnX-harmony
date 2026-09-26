# 架构决策记录（ADR）

记录本项目的重大架构决策：背景、决策、理由、后果与被否的备选。每条决策一页，便于后来者理解"为什么是这样"。

| 编号 | 决策 | 状态 |
|---|---|---|
| [0001](0001-native-rewrite-over-rnoh.md) | 采用 ArkTS/ArkUI 原生重建，而非 RNOH 跨平台移植 | 已接受 |
| [0002](0002-mit-license-and-attribution.md) | 沿用上游 MIT 许可并保留来源归属 | 已接受 |
| [0003](0003-harmonyos-native-design-over-material.md) | 采用 HarmonyOS 原生设计语言，不复刻 Material 3 视觉 | 已接受 |
| [0004](0004-state-management.md) | 状态管理采用 ArkUI 原生状态 + 单一应用级 Store | 已接受 |
| [0005](0005-repo-layout-and-toolchain-paths.md) | 仓库布局为"根治理 + app/ 工程"，工具链全部落盘至非系统盘 | 已接受 |
| [0006](0006-external-dependency-and-campus-network.md) | 接受"仅校园网可达"前提，不自建中转服务 | 已接受 |
| [0007](0007-credential-storage.md) | 凭据与会话存储采用关键资产存储服务 | 已接受 |

> 模板：状态 / 背景 / 决策 / 理由 / 后果 / 备选方案。

> **别慌通读**：ADR 有意稀少（只为重大决策写），理解现状看 [`../ARCHITECTURE.md`](../ARCHITECTURE.md)，ADR 只按需查"为什么"；被取代的归档不打扰，当前架构 = 未取代的活跃集。增长过快是滥写信号——日常变更归 PRD 状态列 + CHANGELOG。
