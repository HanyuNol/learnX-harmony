# ADR-0005：仓库布局为"根治理 + app/ 工程"，工具链全部落盘至非系统盘

## 状态
已接受（2026-09-26 首次成功构建后补充了**工程路径字符集**约束，见 §决策 4）

## 背景

三件事需要一起定：SDD 治理文档与 HarmonyOS 工程目录的关系、工具链的落盘位置、以及工程路径本身的合法字符集。

1. **目录关系**：DevEco CLI 的 `devecocli create --project-path <dir>` 要求目标目录**为空**。若先把 SDD 治理铺在仓库根，工程就无法直接建在根上；反之若工程先占根，治理文档又得另找地方。
2. **磁盘约束**：开发机 `C:` 盘可用空间约 24 GB（使用率 95%），`D:` 盘可用约 185 GB。而本项目的工具链需求为：DevEco Studio（完整 IDE，含 IntelliJ 基底）、HarmonyOS SDK、模拟器系统镜像（单个数 GB）、SDD/Node 依赖——合计数十 GB 量级。官方文档对命令行构建流水线给出的硬盘要求是 **100 GB 以上**。
3. **路径字符集约束（实测确认）**：DevEco 官方构建错误码文档明文规定：
   - **`00306002 工程路径不能包含中文字符`** —— 报错 `The Node directory and node name cannot contain Chinese characters.`，处理步骤为"移除工程路径中的中文字符"。
   - **`00306003 工程路径无效`** —— 工程路径存在中文或特殊字符时触发；合法字符集仅为**字母、数字、`-`、`_`、`.`、英文括号、空格、`@`**。
   - **`00308002`（场景二）** —— Hvigor 初始化读取环境变量 `HVIGOR_USER_HOME`，若 `HVIGOR_USER_HOME` **或 DevEco Studio 安装路径含空格**，会导致路径解析失败、构建异常；官方建议把 `HVIGOR_USER_HOME` 指到不含空格的路径。

## 决策

1. **目录布局**：仓库根放 SDD 治理与文档，**HarmonyOS 工程作为 `app/` 子目录**，由 `devecocli create --project-path ./app` 生成。

```
D:/Documents/LearnX-Harmony/   ← 仓库根：SDD 治理 + 文档
├── docs/                      PRD / ARCHITECTURE / API / ADR / specs
├── .claude/rules/             防漂移规则
├── .github/                   PR/Issue 模板
├── VERSION / CHANGELOG.md / LICENSE / README.md / SECURITY.md
└── app/                       ← HarmonyOS 工程根（build-profile.json5 所在）
```

2. **工具链全部落在 `D:` 盘**，通过环境变量显式指定，不用默认路径：

| 内容 | 环境变量 / 方式 | 落点 |
|---|---|---|
| devecocli 本体与全局 npm 包 | `npm install -g --prefix <D 盘目录>` | `D:/harmonyos/npm-global` |
| 文档知识库与 CLI 数据 | `DEVECO_CLI_DATA_DIR` | `D:/harmonyos/.deveco-data` |
| DevEco Studio 工具链根 | `DEVECO_CLI_STUDIO_PATH` | `D:/DevEco Studio`（6.1.1.418） |
| Command Line Tools 根 | `DEVECO_CLI_CLT_PATH` | （未使用；Studio 路线已满足） |
| HarmonyOS SDK | `DEVECO_SDK_HOME` | 随 Studio：`D:/DevEco Studio/sdk`（API 24 / 6.1.1.125 Release） |
| Hvigor 用户级缓存 | `HVIGOR_USER_HOME` | `D:/harmonyos/hvigor` |
| 模拟器系统镜像 / 实例 | `emulator create --image-root` / `--instance-path` | `D:` 盘 |

3. **遥测默认关闭**：`DEVECO_CLI_DISABLE_TELEMETRY=1`。

4. **工程路径必须为纯 ASCII、不含中文**（依据 §背景 3）。用户最初指定的 `D:\文档\LearnX Harmony` 因含中文而被拒用，改用 `D:/Documents/LearnX-Harmony`。同时因为 `D:/DevEco Studio` 的安装路径**含空格**，**必须**显式设置无空格的 `HVIGOR_USER_HOME` 以规避 `00308002`。

## 理由

- `app/` 子目录是**唯一同时满足 `devecocli create` 空目录约束与"治理文档与代码同仓"诉求**的布局；把工程放在根、文档另置会导致治理文档脱离代码审查范围。
- 磁盘是硬约束：`C:` 盘 24 GB 不足以容纳 SDK 与模拟器镜像，且盘满会直接导致构建与模拟器启动失败。用环境变量重定向是官方支持的路径（`DEVECO_CLI_STUDIO_PATH > DEVECO_CLI_CLT_PATH > 自动探测` 的优先级链）。
- 全部重定向而非部分，避免"文档库在 D、SDK 在 C"这类难以排查的混合状态。
- 工程路径的 ASCII 约束不是偏好而是**编译期硬失败**：`00306002` 会直接中断构建，故必须在建工程时就避开，事后改路径代价更高。
- `D:\文档\LearnX Harmony` 同时踩中中文（`00306002`）与空格（`00308002` 同类风险）两项，故整体替换为 ASCII 等价路径以保留用户的"`D:` 盘 + Documents 语义 + 项目名"意图。

## 后果

- **正面**：系统盘几乎不被工具链占用；治理文档与代码同仓、同提交、同审查；路径显式，多版本并存时可切换。
- **负面**：
  - **每条 `devecocli` / hvigor 调用都必须带对应环境变量**，否则回退默认路径——本项目特有易错点，已记入 `OPERATIONS.md` 与 `.claude/rules/architecture-invariants.md`。
  - 实测评注：`C:` 盘仍有 **约 73 KB** 的 ohpm 元数据缓存落在 `~/.ohpm`（注册表索引，非依赖本体）。量级可忽略，但**不是零占用**——后续若要彻底清零，需确认 ohpm 是否支持重定向其用户目录。
- **后续约束**：不得在未设环境变量的 shell 里直接跑 `devecocli`；新增任何工具链组件前先确认落盘位置；**任何新建工程/模块的路径不得含中文**。

## 备选方案

- **工程建在 `D:\文档\LearnX Harmony`（用户原始指定）**：**已否决** —— 含中文触发官方错误码 `00306002`（工程路径不能包含中文字符），构建必然失败。用户的 `文档` 目录意图以 ASCII 的 `D:/Documents/` 保留。
- **工程建在仓库根、治理文档放子目录**：会让 PRD/ADR 脱离常规代码审查视野，且 `devecocli` 的工作目录假设是工程根，命令易失效。
- **工程建在根、先 create 后把治理文件拷进去**：可行但引入了"移动已生成工程"的脆弱步骤，且工程初始化会覆盖同名文件。已否决。
- **全部用默认路径（落 C 盘）**：`C:` 盘空间不足，直接阻塞。
