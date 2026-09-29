/**
 * 富文本正文渲染：把服务端 HTML **清洗后**在沙箱 Web 里排版显示。
 *
 * 为什么用 ArkWeb 而不是把 HTML 转成 ArkUI 的 Text/Span：正文里有**图片**（通知/作业里常见，
 * 例如课程微信群的二维码），而图片来自学堂服务器、需要**会话 Cookie**——只有 ArkWeb 与 API
 * 请求共用同一份 Cookie（ADR-0008 的 `WebCookieManager`），ArkUI 的 `Image` 拿不到它。
 *
 * 安全三层（`SECURITY.md` §3 要求不得整体信任服务端 HTML）：
 * 1. **清洗**：`common/sanitizeHtml` 白名单过滤（纯函数 + 穷举测试），脚本/事件属性/危险协议全丢；
 * 2. **CSP**：模板默认写死**禁一切脚本**；**只有确知正文里有公式时**才放开成
 *    `script-src 'unsafe-inline'`（用来跑本项目注入的 KaTeX）——见
 *    `docs/adr/0012-katex-for-math-rendering.md` 的"按最小面开脚本"；
 * 3. **导航拦截**：正文里的链接**不在本 Web 里跳转**，交给系统浏览器打开（`native/linkAdapter`）。
 *
 * 公式（FR-22 的公式部分，ADR-0012）：正文含定界符时，把 KaTeX 与 auto-render **内联**注入
 * （与上游 preval 内联同一思路），按 `output:'mathml'` 渲染——**不带 KaTeX 字体**（体积小一个数量级），
 * 由 Chromium 自带的数学排版呈现。渲染失败退回源码（`throwOnError:false`），不留白屏。
 *
 * 自动高度：Web 组件本身不会"缩到内容那么高"，故在加载完成后用 `runJavaScript` 读
 * `document.body.scrollHeight` 再把组件高度设过去（应用侧注入，不受 CSP 的 `script-src` 限制）。
 */

import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { sanitizeHtml } from '../common/sanitizeHtml';
import { containsMath, delimitersPresent, normalizeMathText } from '../common/mathText';
import { unwrapScriptResult } from '../common/scriptResult';
import { readRawFileText } from '../native/resourceAdapter';
import { openExternalUrl } from '../native/linkAdapter';
import { Logger } from '../common/logger';

const TAG: string = 'richText';

/** 学堂首页：正文里的相对图片/链接按它补成绝对地址 */
const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';

/** 量到真实高度之前给的最小高度（避免先闪一下 0 高度） */
const MIN_HEIGHT: number = 60;
/** 高度上限：正文再长也不该把页面撑爆（超过就由 Web 内部滚动） */
const MAX_HEIGHT: number = 6000;

@Component
export struct RichTextView {
  /** 服务端给的原始 HTML */
  raw: string = '';
  /** 相对地址的基址（默认学堂首页） */
  baseUrl: string = LEARN_BASE;

  @State private bodyHeight: number = MIN_HEIGHT;
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 内联的 KaTeX 脚本（首次用到时读一次；空串＝资源不可用，公式退回源码） */
  private katexCache: string = '';
  /** 本次文档是否注入了公式脚本（日志用） */
  private mathExpected: boolean = false;

  /** 清洗 + 套模板后的完整 HTML（只在 `aboutToAppear` 算一次，避免每次重绘都重算） */
  private document: string = '';

  aboutToAppear(): void {
    this.document = this.buildDocument();
  }

  /** 主题色交给 Web：正文用页面的文字色、底色透明（跟随卡片背景） */
  private colorOf(key: string): string {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const value: number = context.resourceManager.getColorSync($r(`app.color.${key}`).id);
      // 资源色是 ARGB，转成 CSS 用的 #RRGGBB
      const hex: string = (value & 0xFFFFFF).toString(16).padStart(6, '0');
      return `#${hex}`;
    } catch (err) {
      Logger.warn(TAG, `读取主题色失败 key=${key}，用兜底色`);
      return key === 'text_primary' ? '#182431' : '#666666';
    }
  }

  /**
   * 读入内联的 KaTeX 脚本（只读一次并缓存）。
   *
   * 读不到（资源缺失/构建漏打包）**不抛**：公式退回源码显示，正文照常渲染——
   * 一个可选增强不该让整页正文打不开。
   */
  private katexScript(): string {
    if (this.katexCache.length > 0) {
      return this.katexCache;
    }
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const core: string = readRawFileText(context, 'katex.min.js');
      const autoRender: string = readRawFileText(context, 'auto-render.min.js');
      this.katexCache = `${core}
${autoRender}`;
    } catch (err) {
      Logger.warn(TAG, `KaTeX 资源读取失败，公式将按源码显示：${(err as Error).message}`);
      this.katexCache = '';
    }
    return this.katexCache;
  }

  private buildDocument(): string {
    // **先清洗、后规整**：清洗保证安全，规整只动数学记号（`\mbox`→`	ext`）
    const body: string = normalizeMathText(sanitizeHtml(this.raw, this.baseUrl));
    if (body.trim().length === 0) {
      return '';
    }
    const withMath: boolean = containsMath(body) && this.katexScript().length > 0;
    this.mathExpected = withMath;
    if (withMath) {
      Logger.info(TAG, `正文含公式，注入 KaTeX 定界符=[${delimitersPresent(body)}]`);
    }
    const primary: string = this.colorOf('text_primary');
    const secondary: string = this.colorOf('text_secondary');
    const accent: string = this.colorOf('accent');
    return `<!DOCTYPE html><html><head><meta charset="utf-8">`
      + `<meta name="viewport" content="width=device-width, initial-scale=1">`
      // CSP：**禁掉一切脚本**（清洗已丢脚本标签，这是第二道防线）；图片允许 http(s) 与 data:，
      // 样式只允许本模板自己的（正文的内联 style 已被清洗丢掉）
      + `<meta http-equiv="Content-Security-Policy" `
      // 有公式时才放开内联脚本（跑我们注入的 KaTeX）；否则维持"禁一切脚本"
      + `content="default-src 'none'; img-src https: http: data:; style-src 'unsafe-inline'; `
      + (withMath ? `script-src 'unsafe-inline'` : `script-src 'none'`) + `">`
      + `<style>`
      + `html,body{margin:0;padding:0;background:transparent;}`
      + `body{font-size:16px;line-height:1.6;color:${primary};`
      + `font-family:sans-serif;word-break:break-word;overflow-wrap:anywhere;}`
      + `p{margin:0 0 12px 0;}`
      + `h1,h2,h3,h4,h5,h6{margin:16px 0 8px 0;line-height:1.3;}`
      + `ul,ol{margin:0 0 12px 0;padding-left:24px;}`
      + `blockquote{margin:0 0 12px 0;padding-left:12px;border-left:3px solid ${secondary};color:${secondary};}`
      + `code,pre{font-family:monospace;background:rgba(127,127,127,0.12);border-radius:4px;}`
      + `code{padding:1px 4px;}`
      + `pre{padding:8px;overflow-x:auto;}`
      + `img{max-width:100%;height:auto;}`
      + `a{color:${accent};text-decoration:none;}`
      + `table{border-collapse:collapse;max-width:100%;}`
      + `td,th{border:1px solid rgba(127,127,127,0.35);padding:4px 8px;}`
      + `</style></head><body>${body}</body>`
      + (withMath ? this.katexTag() : '')
      + `</html>`;
  }

  /**
   * 内联注入 KaTeX 与 auto-render，并渲染公式。
   *
   * 定界符用 KaTeX auto-render 的**默认集**（`$$`、`\(`、`\[`，**不含单 `$`**），与上游一致；
   * `throwOnError:false` 让不支持的宏退回源码而不是报错。
   */
  private katexTag(): string {
    return `<script>${this.katexScript()}</script>`
      + `<script>try{renderMathInElement(document.body,{throwOnError:false,output:'mathml'})}`
      + `catch(e){console.error('[katex] 渲染失败: ' + (e && e.message))}</script>`;
  }

  /** 量出正文真实高度并套到组件上（量不到就保持默认高度，由 Web 内部滚动兜底） */
  private measure(): void {
    // 一起把"渲染出几个公式"读回来：这是公式功能在**设备上唯一的客观证据**
    // （Web 内部 DOM 不进 UI 节点树，截图也不便判读）
    this.controller.runJavaScript(
      `document.body.scrollHeight + '|' + document.querySelectorAll('math').length`)
      .then((value: string) => {
        const parts: string[] = unwrapScriptResult(value).split('|');
        const measured: number = Number(parts[0]);
        const mathCount: number = parts.length > 1 ? Number(parts[1]) : 0;
        Logger.info(TAG, `正文渲染完成 高度=${parts[0]} 公式数=${mathCount}`
          + ` 期望含公式=${this.mathExpected}`);
        if (!Number.isFinite(measured) || measured <= 0) {
          return;
        }
        this.bodyHeight = Math.min(MAX_HEIGHT, Math.max(MIN_HEIGHT, measured + 4));
      }).catch((err: Error) => {
      Logger.warn(TAG, `量正文高度失败，用默认高度：${err.message}`);
    });
  }

  build() {
    Column() {
      if (this.document.length === 0) {
        // 清洗后没有内容（全是被丢的危险片段）：**什么都不显示**，不给用户看脚本源码
        Text('')
      } else {
        Web({ src: '', controller: this.controller })
          .width('100%')
          .height(this.bodyHeight)
          .backgroundColor(Color.Transparent)
          // 正文只需要图片与排版：脚本由 CSP 与本组件的使用方式共同约束，
          // 打开它是为了 `runJavaScript` 量高度（应用侧注入不受文档 CSP 限制）
          .javaScriptAccess(true)
          .fileAccess(false)
          .imageAccess(true)
          .darkMode(WebDarkMode.Off)
          // 文档**不能经 `src` 传入**：`src` 是资源地址，喂 HTML 字符串会被当 URL 解析失败
          // （hilog 里 `[WebNavigation] LoadUrl message:invalidUrl`），页面根本不加载，
          // `onPageEnd` 不触发、高度量不到、注入的脚本也不执行。必须走 `loadData`。
          // baseUrl 给学堂首页：相对地址可解析，且文档 origin 落在学堂域上，图片才带得上会话 Cookie。
          .onControllerAttached(() => {
            this.controller.loadData(this.document, 'text/html', 'utf-8', this.baseUrl);
          })
          .onPageEnd((event: OnPageEndEvent) => {
            this.measure();
          })
          // 页面里的 console 默认不进 hilog，静默的失败（CSP 拦截、KaTeX 报错）就查不到；
          // 把它转进本组件日志，让"公式没渲染出来"这类问题有据可查。
          .onConsole((event: OnConsoleEvent) => {
            Logger.info(TAG, `页面console: ${event.message.getMessage()}`);
            return false;
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            Logger.warn(TAG, `正文渲染出错 code=${event.error.getErrorCode()}`);
          })
          // 正文里的链接不在这一小块 Web 里跳转（那样会失去返回路径、把详情页变成浏览器）
          //
          // 注意：`onLoadIntercept` 对**主框架加载**同样触发，返回 `true` 就是"拦下不放行"。
          // 无脑返回 `true` 会把**文档自身的加载**也拦掉（hilog 表现为
          // `OnLoadError errorCode:ERR_ABORTED(-3) mainFrame:1`，页面永远白屏）。
          // 因此这里只拦 http(s)——那才是"点链接"；文档自身走 `loadData`（`data:` URL）放行。
          .onLoadIntercept((event: OnLoadInterceptEvent) => {
            const url: string = event.data.getRequestUrl();
            if (url.startsWith('http://') || url.startsWith('https://')) {
              const context: common.UIAbilityContext =
                this.getUIContext().getHostContext() as common.UIAbilityContext;
              openExternalUrl(context, url).catch((err: BusinessError) => {
                Logger.warn(TAG, `交给系统打开链接失败 code=${err.code}`);
              });
              return true;
            }
            return false;
          })
      }
    }
    .width('100%')
  }
}
