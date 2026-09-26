# 架构不变量（防架构漂移）

> 以下是本项目锁定的架构约束（依据 `docs/ARCHITECTURE.md` 与 `docs/adr/`）。**违反任一条即为架构漂移。**
> 确需改变某条 → 先写新 ADR 取代旧决策、经确认后再改；**禁止在代码里静默违背**。

## 1. 分层与依赖方向

单向依赖，禁止反向穿透：

```
pages → viewmodel → repository → network / storage / native
                          ↓
                    model / common（叶子层）
```

- `pages` 只做 UI 与交互：**不得**直接发网络请求、**不得**直接读写存储、**不得**直接调用系统 Kit。
- `native` 只封装系统能力，不含业务判断；失败语义由 `repository` 归类。
- `model` / `common` 是叶子层：**不得** import 任何上层模块。`common` 中的函数必须无副作用（便于穷举测试）。
- 跨层共享的类型必须落在 `model`，不得由上层向下层泄漏实现细节。

## 2. 简单优先（本项目禁用的重型件）

- **禁止引入 React Native / JS 生态依赖**（含任何 `react-native-*`、`expo-*` 或其鸿蒙移植版）——本项目是原生重建，不是移植（ADR-0001）。
- **禁止引入第三方状态管理库**：状态用 ArkUI 原生状态 + 单一应用级 Store（ADR-0004）。需求增长到单例难以维护时，先写新 ADR。
- **禁止引入第三方 HTTP / GraphQL 客户端**：用 `@ohos.net.http`；GraphQL 只是 HTTP POST。
- **禁止引入第三方 HTML 解析库**：按实际需要的标签写最小白名单解析。
- **禁止引入关系型数据库**：当前缓存用键值 + 文件即可；真需要时走 ADR。
- **禁止多模块（HSP/HAR）拆分**：单 `entry` 模块，当前阶段拆分收益不抵成本。

> 需要引入上列任一能力时：**先停止、先走 ADR、经确认后**再引。

## 3. 真源与一致性

- **需求的唯一真源是 `docs/PRD.md` §4 的 FR 表**；代码不得实现表中不存在的能力（防镀金，见 `scope-discipline.md`）。
- **凭据与 Cookie 的唯一真源是系统加密存储**，唯一访问入口是 `storage.CredentialStore`；其余模块不得直接触碰。
- **HTTP 请求的唯一出口是 `network.LearnClient`**；Cookie 与 CSRF 令牌在此统一注入，业务层不得自行拼接。
- **系统能力的唯一出口是 `native.*Adapter`**。
- 缓存的权威在校方接口：本地缓存是副本，冲突时以重新拉取为准，不得把缓存当权威。

## 4. 技术栈锁定

- **应用语言与 UI**：ArkTS + ArkUI（声明式），HarmonyOS NEXT Stage 模型。
- **构建与包管理**：hvigor + ohpm，经 DevEco CLI（`devecocli`）调用。
- **SDK 版本**：工程锁定 **API 24**（随 DevEco Studio 6.1.1.418 的 SDK 6.1.1.125 Release）；**升级 SDK 属架构决策，先写 ADR**。
- **包名**：`io.github.hanyunol.learnx`（刻意区别于上游已上架的 `io.robertying.learnx`）。变更需同步签名材料与 `AppScope/app.json5`。
- **ArkTS 语言限制（硬性）**：禁 `any`、禁反射、禁动态属性访问、禁运行时改变对象结构。违反会在 `devecocli check arkts` 报错。
- **工具链落盘**：全部在 `D:` 盘，经环境变量指定（`DEVECO_CLI_STUDIO_PATH` / `DEVECO_CLI_DATA_DIR` / `HVIGOR_USER_HOME`）；**不得在未设环境变量的 shell 中调用 `devecocli`**（会静默回退到空间不足的 C 盘，见 ADR-0005）。
- **路径字符集（硬性）**：**任何工程、模块、签名材料的路径不得包含中文字符**（官方错误码 `00306002`，编译期硬失败）；路径只允许字母、数字、`-`、`_`、`.`、英文括号、空格、`@`（`00306003`）。`HVIGOR_USER_HOME` 必须指向无空格路径（`00308002`）。

## 5. 外部依赖边界

- **不得**为"让校外也能用"而引入中转、代理、镜像服务（ADR-0006）。
- 网络不可达 / 认证失效 / 接口语义变更 / 解析失败**四类错误必须分开归类**，不得把服务端或网络问题误报为应用缺陷。
- 第三方服务（`api.tsinghua.app`）不得进入关键路径。

## 红线（出现即停止并先确认）

引入 RN/JS 生态依赖 · 引入被禁的重型件 · `pages` 直连网络或存储或系统 Kit · `model`/`common` 反向 import 上层 · 绕过 `LearnClient` 或 `CredentialStore` 自行访问网络或凭据 · 在日志或明文文件中写入凭据 · 擅自升级 SDK 或技术栈 · 为校外访问引入中转代理 · 把网络问题报成应用缺陷 · 在含中文或非法字符的路径下新建工程/模块 · 静默违背任一已接受 ADR
