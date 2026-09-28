/**
 * 富文本正文渲染：把服务端 HTML **清洗后**在沙箱 Web 里排版显示。
 *
 * 为什么用 ArkWeb 而不是把 HTML 转成 ArkUI 的 Text/Span：正文里有**图片**（通知/作业里常见，
 * 例如课程微信群的二维码），而图片来自学堂服务器、需要**会话 Cookie**——只有 ArkWeb 与 API
 * 请求共用同一份 Cookie（ADR-0008 的 `WebCookieManager`），ArkUI 的 `Image` 拿不到它。
 *
 * 安全三层（`SECURITY.md` §3 要求不得整体信任服务端 HTML）：
 * 1. **清洗**：`common/sanitizeHtml` 白名单过滤（纯函数 + 穷举测试），脚本/事件属性/危险协议全丢；
 * 2. **CSP**：模板里写死 `script-src 'none'`，即便清洗漏了什么，文档内的脚本也执行不了；
 * 3. **导航拦截**：正文里的链接**不在本 Web 里跳转**，交给系统浏览器打开（`native/linkAdapter`）。
 *
 * 自动高度：Web 组件本身不会"缩到内容那么高"，故在加载完成后用 `runJavaScript` 读
 * `document.body.scrollHeight` 再把组件高度设过去（应用侧注入，不受 CSP 的 `script-src` 限制）。
 */

import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { sanitizeHtml } from '../common/sanitizeHtml';
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

  private buildDocument(): string {
    const body: string = sanitizeHtml(this.raw, this.baseUrl);
    if (body.trim().length === 0) {
      return '';
    }
    const primary: string = this.colorOf('text_primary');
    const secondary: string = this.colorOf('text_secondary');
    const accent: string = this.colorOf('accent');
    return `<!DOCTYPE html><html><head><meta charset="utf-8">`
      + `<meta name="viewport" content="width=device-width, initial-scale=1">`
      // CSP：**禁掉一切脚本**（清洗已丢脚本标签，这是第二道防线）；图片允许 http(s) 与 data:，
      // 样式只允许本模板自己的（正文的内联 style 已被清洗丢掉）
      + `<meta http-equiv="Content-Security-Policy" `
      + `content="default-src 'none'; img-src https: http: data:; style-src 'unsafe-inline'">`
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
      + `</style></head><body>${body}</body></html>`;
  }

  /** 量出正文真实高度并套到组件上（量不到就保持默认高度，由 Web 内部滚动兜底） */
  private measure(): void {
    this.controller.runJavaScript('document.body.scrollHeight').then((value: string) => {
      const measured: number = Number(value);
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
        Web({ src: this.document, controller: this.controller })
          .width('100%')
          .height(this.bodyHeight)
          .backgroundColor(Color.Transparent)
          // 正文只需要图片与排版：脚本由 CSP 与本组件的使用方式共同约束，
          // 打开它是为了 `runJavaScript` 量高度（应用侧注入不受文档 CSP 限制）
          .javaScriptAccess(true)
          .fileAccess(false)
          .imageAccess(true)
          .darkMode(WebDarkMode.Off)
          .onPageEnd((event: OnPageEndEvent) => {
            this.measure();
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            Logger.warn(TAG, `正文渲染出错 code=${event.error.getErrorCode()}`);
          })
          // 正文里的链接不在这一小块 Web 里跳转（那样会失去返回路径、把详情页变成浏览器）
          .onLoadIntercept((event: OnLoadInterceptEvent) => {
            const url: string = event.data.getRequestUrl();
            if (url.startsWith('http://') || url.startsWith('https://')) {
              const context: common.UIAbilityContext =
                this.getUIContext().getHostContext() as common.UIAbilityContext;
              openExternalUrl(context, url).catch((err: BusinessError) => {
                Logger.warn(TAG, `交给系统打开链接失败 code=${err.code}`);
              });
            }
            return true;
          })
      }
    }
    .width('100%')
  }
}
