/**
 * WebView 主导的登录页（ADR-0008）。
 *
 * ## 它做什么
 *
 * 把**真实的统一身份认证页**开在应用内的 ArkWeb 里，让用户在页面里完成认证
 * （包括输入多因子认证验证码），应用只做三件不越界的事：
 * 1. 注入脚本预填学号密码（见 `resources/rawfile/sso_inject.js`）；
 * 2. 通过 JS 通道接收页面回传的**完整表单体**；
 * 3. 导航命中网络学堂漫游地址时收尾——把表单体交给上层建立会话。
 *
 * ## 它刻意不做什么
 *
 * - **不代填、不代答验证码**：那是用户的步骤，不是遗漏。应用在这段时间就是等。
 * - **不直接调网络/存储/系统能力**：收尾动作经 `AuthStore` → `repository` 完成
 *   （架构不变量 §1）；本页只管 UI 与 Web 组件本身。
 *
 * ## 为什么登录由网页主导（而不是纯 API）
 *
 * 多因子认证的验证码只能在真实页面上输入，"纯 API 登录"没有任何位置承载这一步。
 * 同理，`fingerPrint` / `fingerGenPrint` / `fingerGenPrint3` 这些设备信任标识由页面
 * 生成，应用无法自行构造。详见 ADR-0008 与 spec §7。
 *
 * ## 会话共享
 *
 * 本页**不清也不能清** Cookie：页面那次会话的 Cookie 是后续 API 重放同一份表单体的
 * 前提（`LearnClient.loginWithFormData`）。清 Cookie 的动作发生在进入本页之前
 * （`AuthRepository.prepareSsoSession`），那是"以干净会话起步"的正确时机。
 */

import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { AuthState, AuthStateListener, AuthStore } from '../viewmodel/authStore';
import { LoginStatus, SsoInjection } from '../model/auth';
import { ID_LOGIN_FORM, ID_ORIGIN } from '../model/urls';
import {
  FIELD_FINGER_PRINT,
  MSG_ENV_PROBE,
  MSG_PREFILL_FAILED,
  MSG_NO_FORM_BODY,
  MSG_PAGE_LOAD_FAILED,
  MSG_SUBMIT_FORM,
  MSG_TRUST_LIMIT,
  SsoBridgeMessage,
  SsoFormBody,
  buildInjectedScript,
  describeRoamUrl,
  formBodyOf,
  isRoamingUrl,
  parseBridgeMessage,
  ticketOfRoamUrl
} from '../network/ssoForm';
import { readRawFileText } from '../native/resourceAdapter';
import { Logger } from '../common/logger';
import { normalize } from '../common/errors';

const TAG: string = 'ssoLogin';

/** 注入脚本模板的资源路径（与 `resources/rawfile/` 下的文件名一致） */
const INJECT_TEMPLATE_PATH: string = 'sso_inject.js';

/** JS 通道对象名。注入脚本按此名取用，改名须同步 `sso_inject.js` */
const BRIDGE_NAME: string = 'learnXSsoBridge';

/** 注入脚本在页面控制台里的打点前缀（与 `sso_inject.js` 的 `mark()` 一致） */
const CONSOLE_MARKER: string = 'learnX[sso]';

/**
 * 注入脚本回传消息的接收对象。
 *
 * 必须是**只有方法**的类：ArkWeb 的 `javaScriptProxy` 不暴露属性，实例字段既不会
 * 出现在页面侧，也可能让注册失败。因此回调经类静态字段转交，由页面在生命周期内设置/清除。
 */
class SsoBridge {
  static handler: ((raw: string) => void) | null = null;

  postMessage(raw: string): void {
    const handler: ((raw: string) => void) | null = SsoBridge.handler;
    if (handler !== null) {
      handler(raw);
    }
  }
}

@Component
export struct SsoLoginView {
  /** 页面加载进度，0–100 */
  @State private progress: number = 0;
  /** 已抓到表单体、正在建立会话：此时盖一层提示，用户不必再操作页面 */
  @State private establishing: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: SsoBridge = new SsoBridge();
  private scripts: Array<ScriptItem> = [];
  private store: AuthStore = AuthStore.getInstance();

  /** 最近一次可用的表单体（urlencoded）。非 @State：含表单内容，不需要驱动 UI */
  private capturedBody: string = '';
  /** 截到的漫游地址（含一次性票据）。非 @State，且**绝不写进日志** */
  private roamUrl: string = '';
  /** 收尾只做一次：漫游地址可能被多次导航命中 */
  private finishing: boolean = false;
  /** 应用自身资源缺失等致命问题：页面无法工作时的提示 */
  @State private fatalText: string = '';

  private listener: AuthStateListener = (state: AuthState) => {
    // 上层若已离开网页登录流程（成功、失败或取消），本页随之失效
    if (state.status !== LoginStatus.SSO_IN_PROGRESS && state.status !== LoginStatus.LOGGING_IN) {
      this.establishing = false;
    }
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);

    const injection: SsoInjection | null = this.store.ssoInjection();
    if (injection === null) {
      Logger.warn(TAG, '缺少网页登录所需的取值，无法注入');
      this.fatalText = '登录流程状态已丢失，请返回重新登录';
      return;
    }

    SsoBridge.handler = (raw: string) => {
      this.onBridgeMessage(raw);
    };

    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      Logger.error(TAG, '未能取得宿主上下文，无法读取注入脚本');
      this.fatalText = '应用资源缺失，无法打开登录页';
      return;
    }

    try {
      const template: string = readRawFileText(context, INJECT_TEMPLATE_PATH);
      const script: string = buildInjectedScript(
        template,
        injection.username,
        injection.password,
        injection.fingerPrint,
        injection.deviceName
      );
      // 只对统一身份认证来源注入：脚本依赖该校方页面结构，注入到别处百害无益
      this.scripts = [{ script: script, scriptRules: [ID_ORIGIN] }];
    } catch (err) {
      const error = normalize(err, '读取登录页注入脚本');
      Logger.error(TAG, `注入脚本读取失败 reason=${error.reason}`);
      this.fatalText = '应用资源缺失，无法打开登录页';
    }
  }

  aboutToDisappear(): void {
    SsoBridge.handler = null;
    this.store.unsubscribe(this.listener);
    // 不注销会泄漏已注入的对象（官方要求与 deleteJavaScriptRegister 配对使用）
    try {
      this.controller.deleteJavaScriptRegister(BRIDGE_NAME);
    } catch (err) {
      Logger.debug(TAG, '注销 JS 通道失败，忽略');
    }
  }

  /** 处理注入脚本回传的消息 */
  private onBridgeMessage(raw: string): void {
    const message: SsoBridgeMessage | null = parseBridgeMessage(raw);
    if (message === null) {
      Logger.warn(TAG, '忽略无法解析的 WebView 消息');
      return;
    }

    if (message.type === MSG_SUBMIT_FORM) {
      const body: SsoFormBody = formBodyOf(message.body);
      if (!body.isUsable()) {
        // 页面可能先回传一份隐藏字段尚未生成的快照（jQuery 提交被覆盖的副作用），
        // 丢弃它，等后续快照覆盖——残缺快照会让重放登录缺字段
        Logger.debug(TAG, '回传的表单体尚不完整，等待后续快照');
        return;
      }
      this.capturedBody = message.body;
      // 只记字段数与指纹长度，不记任何字段值
      Logger.info(TAG, `已抓到登录表单 字段数=${body.fields.size} 指纹长度=${body.get(FIELD_FINGER_PRINT).length}`);
      return;
    }

    if (message.type === MSG_ENV_PROBE) {
      // 页面内部的环境事实（存储可用性、保存信任浏览器的结果），只能由脚本回报；
      // 截断以防意外带入页面内容
      Logger.info(TAG, `页面环境探测 ${message.body.substring(0, 400)}`);
      return;
    }

    if (message.type === MSG_PREFILL_FAILED || message.type === MSG_TRUST_LIMIT) {
      Logger.warn(TAG, `登录页上报异常 type=${message.type}`);
      this.store.reportSsoProblem(message.type);
    }
  }

  /** 认证完成：把截到的漫游地址与抓到的表单体交给上层建立会话 */
  private finish(): void {
    if (this.finishing) {
      return;
    }
    this.finishing = true;
    this.establishing = true;

    const captured: string = this.capturedBody;
    const roamUrl: string = this.roamUrl;

    // 有票据就能直接建会话（不需要表单体）；两者都没有才是真的没抓到东西
    if (captured.length === 0 && ticketOfRoamUrl(roamUrl).length === 0) {
      this.store.reportSsoProblem(MSG_NO_FORM_BODY);
      return;
    }

    // 只记参数名与票据长度，不记票据本身
    Logger.info(TAG, `收尾：漫游地址 ${describeRoamUrl(roamUrl)} 表单体长度=${captured.length}`);

    // 延后一拍：此刻仍在 Web 组件的导航回调栈内，上层会因状态变化销毁本组件，
    // 在回调栈里销毁 Web 有重入风险
    setTimeout(() => {
      this.store.completeSso(formBodyOf(captured), roamUrl);
    }, 50);
  }

  build() {
    Column() {
      // 顶部条：让用户知道这是登录流程的一部分，并随时可退出
      Row({ space: 12 }) {
        Text('登录网络学堂')
          .fontSize(18)
          .layoutWeight(1)
        Button('取消')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor(Color.Blue)
          .onClick(() => {
            this.store.cancelSso();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100 })
          .width('100%')
      }

      if (this.fatalText.length > 0) {
        Text(this.fatalText)
          .fontSize(14)
          .fontColor(Color.Red)
          .padding(16)
      } else {
        Stack() {
          Web({ src: ID_LOGIN_FORM, controller: this.controller })
            .javaScriptAccess(true)
            // 认证页用 localforage（IndexedDB → WebSQL → localStorage）持久化设备标记；
            // 两者任一不可用，页面就会判定"浏览器处于隐私或匿名模式"并**拒绝登记信任浏览器**
            // （真机上踩到过，见 spec §8.6）。domStorageAccess 管 localStorage，
            // databaseAccess 管 Web SQL，默认都是关闭。
            .domStorageAccess(true)
            .databaseAccess(true)
            .javaScriptProxy({
              object: this.bridge,
              name: BRIDGE_NAME,
              methodList: ['postMessage'],
              controller: this.controller
            })
            // 文档开始即注入：XHR 拦截必须在页面脚本之前装好
            .javaScriptOnDocumentStart(this.scripts)
            .onControllerAttached(() => {
              // 直接问出"这个 Web 是不是隐私模式"，而不是猜（校方页面把信任登记失败
              // 归因于"浏览器处于隐私或匿名模式"，这一句需要被证实或排除）
              try {
                Logger.info(TAG, `Web 隐私模式=${this.controller.isIncognitoMode()}`);
              } catch (err) {
                Logger.warn(TAG, '查询隐私模式失败');
              }
            })
            .onProgressChange((event) => {
              this.progress = event.newProgress;
            })
            .onConsole((event) => {
              // 页面控制台是我们**不依赖 JS 桥**的观测通道：桥在子框架里未必可用，
              // 而注入脚本的关键打点（拦截、改写、响应、失败）都同时写到控制台。
              // 只转发自己的标记与页面报错，避免刷屏；返回 false 让它仍进 hilog。
              const text: string = event.message.getMessage();
              if (text.includes(CONSOLE_MARKER) || text.includes('Uncaught') || text.includes('finger')) {
                Logger.info(TAG, `页面控制台 ${text.substring(0, 300)}`);
              }
              return false;
            })
            .onLoadIntercept((event) => {
              const url: string = event.data.getRequestUrl();
              if (!isRoamingUrl(url)) {
                return false;
              }
              // 命中漫游地址 = 认证完成。阻止这次导航（会话改由应用侧 API 建立），据此收尾
              this.roamUrl = url;
              Logger.info(TAG, '导航命中漫游地址，认证完成');
              this.finish();
              return true;
            })
            .onErrorReceive((event) => {
              // 子资源（图片、样式）出错不影响认证流程，只关心主文档
              if (!event.request.isMainFrame()) {
                return;
              }
              Logger.warn(TAG, `登录页加载失败 code=${event.error.getErrorCode()}`);
              this.store.reportSsoProblem(MSG_PAGE_LOAD_FAILED);
            })
            .width('100%')
            .height('100%')

          if (this.establishing) {
            Column({ space: 12 }) {
              LoadingProgress().width(48).height(48)
              Text('正在建立登录会话…').fontSize(14)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F2FFFFFF')
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
