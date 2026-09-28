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
| `git push` 报 `Connection was reset` 或连不上 `github.com` | **命令行未走本机系统代理**（系统代理 `127.0.0.1:7897` 开着，但 WinHTTP 是直连、无代理环境变量） | 见 §6.1：设 `HTTPS_PROXY` 并配 `git config http.proxy`；不要当成网络封锁去绕行 |
| `ssh` 到 GitHub 报 `Permission denied (publickey)` | 本机公钥未注册到账号 | 注册方式见 §6.2 通道 1（2026-09-26 已注册，正常应回 `Hi HanyuNol!`） |

**关键日志位置**：应用运行日志经 `devecocli log` 获取；构建日志在 `app/.hvigor/` 下；Hvigor 用户级缓存与日志在 `D:/harmonyos/hvigor`（`HVIGOR_USER_HOME`）。

## 6. 与 GitHub 远端同步

远端：<https://github.com/HanyuNol/learnX-harmony>（**当前为 private**）。本地配置了两个远端：`origin`（HTTPS，经代理）与 `ssh`（SSH over 443，代理无关）。

### 6.1 本机的网络特殊性：命令行不走系统代理

**根因（2026-09-26 查实）**：本机开启了 Windows **系统代理** `127.0.0.1:7897`（Clash 类本地代理，端口在监听），**但 WinHTTP 为"直接访问"、且未设置任何代理环境变量**。浏览器读取系统代理因而能访问 GitHub，而 `curl` / `git` / `gh` 一律直连 —— 这才是此前"浏览器能上、命令行上不去"的真正原因。

表面上它表现为域名级的不对称可达，很容易被误判为网络封锁：

| 目标 | 直连（未走代理） | 走 `127.0.0.1:7897` |
|---|---|---|
| `github.com:443` | 超时 ~21 s，多组 GitHub IP 均失败 | **HTTP 200，约 2.5 s** |
| `api.github.com` | 正常（本就幸运地可达） | 正常，约 1.4 s |
| `ssh.github.com:443` | TCP 可达但公钥未注册，认证被拒 | 同左 |

**因此不要**把该现象当作网络封锁去绕行（例如改 IP、换协议）。正确处置是先确认代理，再让命令行走它。

**让命令行走代理**（`gh` 与临时命令用环境变量；`git` 已在本仓库配置好）：

```bash
export HTTPS_PROXY="http://127.0.0.1:7897"   # gh 与 curl 需要
export HTTP_PROXY="http://127.0.0.1:7897"
```

```bash
git config http.proxy "http://127.0.0.1:7897"   # 仓库级，已配置
# 若希望所有仓库生效（会连带影响代理关闭时的可用性，谨慎）：
# git config --global http.proxy "http://127.0.0.1:7897"
```

> 代理端口从 `HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings` 的 `ProxyServer` 读取，可能随客户端配置变化。

另注：本机 Windows 的 schannel 无法访问证书吊销端点，`git` / `curl` 直连 HTTPS 时常报误导性的 TLS 错误。**仓库级**已设（不改全局）：

```bash
git config http.schannelCheckRevoke false
```

### 6.2 推送通道

**常规 HTTPS 经代理即为首选通道**：

```bash
cd D:/Documents/LearnX-Harmony
git push origin main          # 仓库级已配 http.proxy，直接可用
```

备用通道：

1. **SSH over 443（代理无关，推荐备用）**：`~/.ssh/config` 已把 `github.com` 重定向到 `ssh.github.com:443`，公钥 `~/.ssh/id_ed25519` **已注册到账号**（2026-09-26 完成；token 已含 `admin:public_key`）。
   该通道**直连即可用、不依赖系统代理**，因此代理关闭时仍能推送。已配为备用远端 `ssh`：
   ```bash
   git push ssh main          # 代理不可用或直连 github.com 不通时用这个
   ```
   验证认证：`ssh -T git@github.com` 应回 `Hi HanyuNol! You've successfully authenticated...`
   > 换机器/换密钥后重新注册：`HTTPS_PROXY="http://127.0.0.1:7897" gh auth refresh -h github.com -s admin:public_key`（OAuth 设备码流程，**需人工在浏览器授权**；其访问的 `github.com/login/device` 同样受 §6.1 代理问题影响，故必须先设 `HTTPS_PROXY`），随后 `gh ssh-key add ~/.ssh/id_ed25519.pub --title "<名称>"`。
2. **经 `api.github.com` 的 Git Data API**（代理与 SSH 都不可用时的最后兜底，已实测可用）：
   ```bash
   GH_TOKEN="$(gh auth token)" node scripts/push-via-api.mjs
   ```
   该脚本用 Git Data API 建 blob/tree/commit 并更新 `refs/heads/main`，只依赖 `api.github.com`。
   它的 message 取自 `git cat-file commit` 的原始字节，所以**推送后远端 SHA 与本地逐位一致**——不会产生重写历史的风险。
   注意：空仓库首次使用需先用 Contents API 建占位提交（脚本已自动处理），随后强制指向真实历史，占位提交被孤立。

### 6.3 语义约束（与 `.claude/rules/git-commit.md` 一致）

- 禁止对 `main` 强制推送（通道 2 内部使用 force 更新引用，那是**首次建立**分支的场景，不是对已共享历史的改写）。
- 不擅自开 PR；不擅自 push（本仓库的初始推送是用户明确要求"创建 GitHub 库"后执行的）。

## 7. 运行单元测试（Local Test）

**Local Test 在宿主机执行，不需要设备或模拟器。** 它与被推送测试包到设备的
Instrument Test（`hdc shell aa test ...`）是两条不同的路径——**不要因为前者需要设备就认为测试无法运行**。

```bash
cd app
# 直接调 hvigorw 时需显式给 SDK 路径（走 devecocli 时会自动识别）
export DEVECO_SDK_HOME="D:/DevEco Studio/sdk"
export HVIGOR_USER_HOME="D:/harmonyos/hvigor"
"/d/DevEco Studio/tools/hvigor/bin/hvigorw.bat" test
```

测试用例放在 `entry/src/test/`，必须在 `List.test.ets` 中登记——**未登记会被静默跳过**。

### 7.1 两个必须知道的陷阱

1. **测试失败不会让构建失败。** 用例失败时输出 `ERROR: Error in <用例名>, ...`，
   但最后仍然打印 `BUILD SUCCESSFUL`。**退出码不能作为门禁判据**，必须读结果文件：

   ```
   entry/.test/default/intermediates/test/coverage_data/test_result.txt   # 逐用例 Success/Failure
   entry/.test/default/outputs/test/reports/index.html                    # 覆盖率与 HTML 报告
   entry/.test/default/outputs/test/reports/coverageReport.json           # 覆盖率数据
   ```

   统计示例：`grep -c "^result=Success" test_result.txt`。

2. **`devecocli check arkts` 默认不扫描 `src/test/`。** 它会报"零错误"而测试文件根本没被检查。
   改测试后须显式指定路径复查：

   ```bash
   devecocli check arkts entry/src/test/List.test.ets entry/src/test/*.test.ets
   ```

### 7.2 覆盖范围的边界

Local Test 只覆盖**不依赖系统能力**的代码。依赖 Kit 的模块（`network/sm2`、`network/learnClient`、
`network/webCookieStore`、`storage/credentialStore`、`repository`、`viewmodel`、`pages`）在宿主侧无法运行，
**不会被任何单元测试覆盖**——它们的正确性只能靠设备/模拟器验证。
这也是把纯逻辑拆成独立模块（`sm2Format` / `parse` / `setCookie` / `ssoForm`）的原因。

### 7.3 平台上的一条实测知识：API 24 的会话 Cookie
- 框架的 `HttpResponse.cookies` 与 `response.header` 在 **API 24 上都取不到会话 Cookie**；
  能取到 set-cookie 的是 `httpRequest.on('headersReceive')` 事件通道（其载荷是
  `{"set-cookie": [...]}` 形状的对象）。
- 自 API 26 起有 `enableAutoCookie`，本项目 SDK 为 24，用不上；改用
  `webview.WebCookieManager`（`fetchCookieSync` / `configCookieSync` / `saveCookieAsync`）。
  **`configCookieSync` 每次只接受一条 Cookie**，故写入前须按 `, ` 切分，
  且要传 `includeHttpOnly = true`，否则 HttpOnly 的会话 Cookie 写不进去。
- 上述关于 Cookie 的取舍与"WebView 与 API 共享会话"的原因见 ADR-0008 与 ARCHITECTURE §5.1。

### 7.4 注入脚本的入口点检查（改 `resources/rawfile/*.js` 后必跑）

```bash
node scripts/check-sso-inject.mjs
```

注入脚本跑在**校方页面**里、横插在登录流程中间：它一旦抛异常，后果不是"应用报错"，
而是**页面的请求发不出去**（页面只显示「网络异常，请重新登录或稍后重试」），
**而应用侧一条日志都没有**——实测为此绕了好几个来回。

两道现有检查都盖不住它：`check arkts` 不扫 rawfile；`node --check` 只查语法，
而那次是**事件回调里**的一处未声明变量赋值（严格模式抛 `ReferenceError`），
不调用就永不触发。该脚本因此在桩沙箱里执行脚本、推进它注册的定时器，
并**主动调用被覆盖的 `XMLHttpRequest.prototype.send`**（含 `saveFinger` 路径），
断言请求体被改写为 `radioVal=是`。已验证它能抓住上述那类缺陷。

### 7.5 验收时的三个"看不见"陷阱

- **Toast 不在应用窗口的 UI 节点树里**：它由 ArkUI 挂在 overlay 根节点上，`devecocli ui layout`
  看不到。要确认 Toast 弹出，看 hilog 里的
  `AceOverlay: Toast node mount to root node`（与触发动作同刻）。**别按"节点树里没有"就判定没弹**。
- **模拟器截图不可用**（返回空白帧，见 §8）：验收以节点树 + hilog 为据，两者都看不到的东西要在报告里
  明确写"未验证"，不要含糊成"看起来正常"。
- **偏好（Preferences）必须用 ApplicationContext 读写**——**机制已查明（2026-09-28）**：
  两种上下文打开的是**两份不同的存储文件**。设备上同时存在
  `<base>/preferences/learnx_settings`（`ApplicationContext` 那份）与
  `<base>/haps/entry/preferences/learnx_settings`（宿主上下文那份），**互不可见**。
  实测症状正是"设置点了没反应"：设置页（应用级上下文）写下了 `omit_course_name=true`，
  而文件下载当时拿到的是宿主上下文，读的是另一份、读到默认值 `false`，
  于是"省略课程名前缀"这个开关**对下载毫无作用**（2026-09-28 真机实测，已修）。
  **修法**：`storage/preferenceStore.ts` 的 `openStore` 一律经 `context.getApplicationContext()`
  打开——收在这一处，调用方传哪种上下文都落在同一份。**新增偏好读写时不要绕过它**。

### 7.6 详情页"改了不刷新"：状态变量必须在 build 里真的被读到

ArkUI（本机 API 24 实测）**只把 build 里实际读到的状态变量登记为依赖**。两个真机踩到的形态：

- **"计数器式刷新"无效**：详情页为"store 变了就重建"加一个 `@State revision` 并在订阅回调里 `+1`，
  但 build 从不读它 → **不会重渲染**。现象：24MB 文件下载成功、日志写着"文件已下载"，
  按钮却一直停在"下载"；作业详情的"重试"点下去也看不到结果（2026-09-28 实测，已修）。
  修法：把**真正要显示的数据**放进 `@State`（如 `@State private assignment`、`downloadState`/`percent`），
  由订阅回调赋值，build 直接读它。
- **`if` 的条件同理**：文件列表的筛选条写成 `if (this.choices().length > 1)`，而 `choices()`
  只读 store（非状态）→ 数据到达后**该分支永不重算**，筛选条一直不出现（2026-09-28 实测，已修）。
  修法：条件里要读 `@State`（本次把分类名也放进 `@State`）。

> 判别口径：**build（含 `if` 条件、`ForEach` 数据源）里读到的状态才驱动刷新**。
> 只从 store 取数、不经 `@State` 中转的渲染路径，数据变了也不会自己更新。

### 7.7 全局 `@Builder` 的多参数是**按值传递**，值变了界面不会刷新

2026-09-28 真机实测：把筛选条做成全局 `@Builder function filterBar(choices, selected, onSelect)`
并在页面里 `filterBar(this.choices(), this.filter, ...)`，**点筛选没有任何反应**——
按钮高亮不变、列表也不变（同一个组件在文件标签页与课程详情页签里都失灵）。

原因是 ArkUI 的规则：全局 `@Builder` 的**多个参数按值传递**，参数值变化**不会**驱动该
`@Builder` 内的 UI 刷新；只有"**单个对象参数**（按引用传递）"才会随状态变化刷新。

修法（已落地）：`filterBar(options: FilterBarOptions)`——把 `choices`/`selected`/`onSelect`
合成一个对象传入，调用处写 `filterBar({ choices: ..., selected: ..., onSelect: ... })`。

**判别口径**：凡"状态变了但那一块不更新"，先看它是不是经全局 `@Builder` 的多参数渲染的。

### 7.8 用 ArkWeb 打开沙箱里的文件：两个条件缺一不可

要在应用内预览下载好的文件（PDF、图片、文本…），Web 组件必须同时满足：

1. **显式 `.fileAccess(true)`**：API 12 起该能力**默认关闭**，关闭时 ArkWeb 直接拒绝本地文件；
2. **URL 用 `file://` + 沙箱绝对路径**（`file:///data/storage/el2/...`）——
   **不能**用 `fileUri.getUriFromPath()` 返回的 `file://<包名>/...`。

只满足一半时的现象都是同一句：`[WebNavigation] LoadUrl message:invalidFileUrl` +
`nweb_delegate.cc: IsUrlFileExist failed, file does not exist`（**看起来像"文件不存在"，
其实文件好好地躺在沙箱里**）。实测 2026-09-28：缺 `fileAccess(true)` 时两份形态都失败；
补上后带包名的形态仍失败、绝对路径形态立刻成功，且在 hilog 里能看到 Chromium 的
`pdf_document_helper` 在处理 PDF（说明是真的渲染了，不是加载了一个错误页）。

两处的实现都在 `native/fileAdapter.previewUrlOf` 与 `pages/FileDetail` 的 Web 属性上，
别在别处另拼 URL。

### 7.9 文案键一致性检查（改文案后必跑）

```bash
node scripts/check-l10n.mjs
```

`$r('app.string.' + key)` 传变量时是**运行时**解析资源 id：键写错不会编译报错，
只会**不渲染那个节点**（实测：登录页只剩输入框，标题与按钮文字整片消失）；
缺 `en_US` 键也不报错，系统静默回落中文，表现为"英文界面里混着中文"。
故该脚本比对 `base` 与 `en_US` 两份 `string.json` 的键集合，并核对
`common/texts.ets` 里声明的键都真实存在；退出码非 0 即不通过。

> 键 → 资源名的取用一律写成 `$r('app.string.' + key)`（**全名**）。
> 传裸键 `$r(key)` 会静默不渲染——这是本项目踩过的坑，见 `common/texts.ets` 的说明。

## 8. 本地模拟器

### 8.1 镜像默认下载到 C 盘（必须重定向）

`devecocli emulator image download` **没有指定路径的选项**，镜像固定下到：

```
C:/Users/<用户>/AppData/Local/Huawei/Sdk/system-image/<版本>/<机型>_x86/
```

单个 phone 镜像约 2.2 GB，且 `Emulator.exe` 下载进程独立于 devecocli 运行——
**杀掉 devecocli 的任务不会停止它**，它会继续往 C 盘写。

本项目以**目录联接（junction）**把该路径重定向到 D 盘，工具链无感：

```powershell
# 1) 先确认没有残留的下载进程，否则目录删不掉
Get-Process Emulator -ErrorAction SilentlyContinue | Stop-Process -Force
# 2) 清掉 C 盘上的该目录（若已有数据先 robocopy /MOVE 到 D 盘）
# 3) 建立联接
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\Huawei\Sdk" -Target 'D:\harmonyos\huawei-sdk'
```

验证：`(Get-Item "$env:LOCALAPPDATA\Huawei\Sdk").LinkType` 应为 `Junction`；
往该路径写文件应实际出现在 D 盘。

### 8.2 许可与实例

```bash
devecocli emulator license accept          # 非交互接受许可，无需 TTY
devecocli emulator image list --all        # 查看可用镜像
devecocli emulator create <名称> --device-type phone --os-version "HarmonyOS 6.1.1(24)" \
  --instance-path D:/harmonyos/emulator/<名称> --image-root D:/harmonyos/huawei-sdk/system-image
devecocli emulator start <名称>
```

`--instance-path` / `--image-root` 都应指向 D 盘——实例数据（含快照）会随使用持续增长。

> **实测坑（2026-09-27）**：同时指定 `--instance-path` 与 `--image-root` 时，
> `emulator create` 会报"已创建但未出现在列表中"，而实例实际**并未生成**（默认目录仍是空的）。
> 改用**默认路径**（不加这两个参数）即可正常创建；镜像已通过 §8.1 的联接落在 D 盘，
> 所以数据位置依然安全。创建后再用 `emulator list` 确认状态为 `stopped`/`running`。

### 8.3 仍需注意的一处 C 盘占用

DevEco Studio **自身**的数据目录在 `C:/Users/<用户>/AppData/Local/Huawei/DevEcoStudio6.1`
（IDE 缓存与索引，实测约 169 MB 且会增长）。这与镜像不同，属 IDE 行为，
**移动它可能影响 Studio 运行**，本项目暂不重定向——仅在此记录，不假装 C 盘零占用。

### 8.4 用命令行驱动界面做验收（实测有效的方法）

命令行驱动 UI 是本项目做"实机验收"的主要手段。以下几点都是实测踩出来的：

- **截图当前不可用**：`snapshot_display` 返回**空白帧**，`devecocli ui screenshot` 同样；
  `devecocli run` 会打印 `write to ... as jpeg failed!; blank check skipped` 并给
  `Smoke: PASS (screenshot unavailable, blank check skipped)`。
  这是模拟器的渲染/抓帧问题，不是应用问题（同一时刻 UI 节点树完整、交互可用）。
  → 验收改以**UI 节点树（`devecocli ui layout --format json`）+ hilog** 为依据。
- **坐标是物理像素**，与 `ui layout` 报出的 `bounds` 同一坐标系；点击取元素中心
  （`devecocli ui click <x> <y>`，位置参数，不是 `--x`）。
- **软键盘弹出时，被挤出可视区的节点不在节点树里**：直接按旧坐标点会**静默无效**
  （命令报成功但应用毫无反应）。正确顺序是：
  先 `devecocli ui text` 输入 → `hdc shell uinput -K -d 2 -u 2` 收起键盘 →
  重新 `ui layout` 取当前 `bounds` → 再 `ui click`。
- **应用日志**：`hdc shell "hilog -x" | grep "A00a11/learnX"`（tag 前缀是域号）。
  驱动前先 `hdc shell hilog -r` 清缓冲，免得在几千行里找。
- **`hdc` 路径**：`D:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe`；
  在 Git Bash 下传设备路径要 `export MSYS_NO_PATHCONV=1`，否则 `/data/...` 会被改写成 `C:/...`。
