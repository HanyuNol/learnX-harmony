# ADR-0001：采用 ArkTS/ArkUI 原生重建，而非 RNOH 跨平台移植

## 状态
已接受

## 背景

上游 learnX 是 React Native 应用（`react-native@0.87.1` + `react@19.3.0` + `expo@58`，94 个 TS 文件、15,293 行），近纯 TS 实现，原生代码仅 `MainActivity.kt` / `MainApplication.kt` 两个 RN 标准壳。

HarmonyOS NEXT 无 AOSP/Android 运行时，RN 应用不能直接运行。存在两条路线：

- **路线 A（移植）**：用 RNOH（React Native for OpenHarmony）把 RN 应用适配到鸿蒙。
- **路线 B（重建）**：用 ArkTS/ArkUI 重新实现，只参照上游的功能与接口语义。

**否决路线 A 的依据**（RNOH 官方 `docs/zh-cn/roadmap.md`，2026 年社区版路线图，仓库已迁移至 `gitcode.com/openharmony-RN/ohos_react_native`）：

1. **版本不匹配且无计划**：RNOH 版本支持矩阵中 **`0.87.x` 标注为 `NA`**（不适配，且无首次发布计划）。已交付的最高稳定适配版本为 `0.82`（2025 Q4），`0.84`/`0.86`/`0.88` 分别在 2026 Q2/Q3/Q4。上游正好卡在 RNOH **永久不支持的 0.87**，而 0.88（Q4 2026）仍落后于上游当前版本。
2. **降级代价极高**：把上游从 RN 0.87 降到 0.82，需回退新架构相关 API 与 React 19.3 特性；上游还对 RN 核心本身打了补丁（`patches/react-native+0.87.1.patch`，共 13 个补丁，涉及 `react-native-webview`、`react-native-pdf`、`react-native-screens`、`expo-file-system` 等），这些补丁在新旧版本间均需重做。
3. **Expo 生态无等价物**：应用重度依赖 `expo-*` 系列（secure-store、file-system、calendar、image-picker、document-picker、intent-launcher、haptics、crypto、background-task、task-manager，均为 58 版）。RNOH 的适配范围是 `react-native-*` 社区库，Expo 模块不在其生态内，需逐个替换为自研原生模块——此时"移植"的工作量已逼近重建。
4. **必须主动降级上游**：上游保持持续升级，路线 A 要么冻结在旧版本、要么反复回滚，长期不可维护。

## 决策

采用**路线 B：以 ArkTS / ArkUI 原生重建**，只参照上游的功能清单、数据模型语义与外部接口契约，不移植其任何 JS/TS 代码与依赖。

## 理由

- 上游的业务价值集中在**功能语义与接口对接**（网络学堂的登录、CSRF、数据结构），而 `thu-learn-lib` 已把接口语义抽象清楚，ArkTS 侧按同一语义重写 HTTP + 解析即可，这部分逻辑与语言无关。
- 真正的迁移成本在 UI 与原生能力，而这两项在鸿蒙侧都有**官方 Kit 一一对应**（PDF Kit、Share Kit、Calendar Kit、Notification Kit、Asset Store Kit、ArkWeb 等），不需要绕道 RN 桥接层。
- 原生重建产出的是可长期维护的原生应用，不受 RNOH 版本节奏与 Expo 生态缺位牵制。
- 鸿蒙开发工具链（DevEco CLI）对 ArkTS 具备 `check arkts` 静态检查 + 模拟器 UI 自动化验证能力，有利于"编码 → 运行 → 验证 → 修复"的 Agent 闭环。

## 后果

- **正面**：目标应用是真正的原生鸿蒙应用；无 RN/Expo 依赖带来的版本脆弱性；UI 与系统能力可按鸿蒙规范做深。
- **负面**：上游的 UI 实现（23 个页面 / 22 个组件）需全部重写，无法复用；上游后续功能更新需手工同步，两个仓库会逐渐分叉。
- **后续约束**：禁止在本项目引入 RN / JS 生态依赖（见 `architecture-invariants.md`）；上游仅作为**功能与接口的参照基线**，不构成代码依赖。

## 备选方案

- **RNOH 移植**：因上述四点否决（版本 `NA`、降级代价、Expo 缺位、需主动降级上游）。
- **WebView 套壳**：把网络学堂 Web 页面用 ArkWeb 包一层。开发量最小，但丢失原生列表/离线/通知/日历等全部本地能力，且用户在校外无法访问——与产品目标不符。若未来目标降级为"仅能在校园网下打开网页"，可重新评估。
- **等待 RNOH 适配 0.88（2026 Q4）后再移植**：仍需处理 Expo 缺位与 13 个核心补丁，且把项目排期押在第三方路线图上，风险不可控。
