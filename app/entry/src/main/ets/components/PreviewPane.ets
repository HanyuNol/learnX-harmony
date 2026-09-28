/**
 * 应用内预览面板：**沉浸布局 + 关闭入口 + 加载态 + 失败态**，文件详情与作业附件详情共用。
 *
 * 为什么单独成组件：预览的这几个状态在两处必须一致，而**交给 ArkWeb 的两个硬条件**
 * （`.fileAccess(true)` 与 `file://` + 绝对路径）一旦漏掉就是"静默打不开、报错都像文件不存在"
 * （见 `docs/specs/files.md` §3.3 第 9 条）。收在一处才不会"一处打磨、一处忘"。
 *
 * 能力边界（如实记在 `docs/specs/pdf-preview.md` §2）：内嵌的是系统 ArkWeb 的 Chromium
 * PDF 查看器插件，**页码跳转与全文搜索做不到**——架构不变量 §2 禁止引入第三方 PDF 库，
 * 而这个插件我们无法编程。故本组件只做"看得顺"：铺满、可缩放、有状态、能退出。
 */

import { webview } from '@kit.ArkWeb';
import { Logger } from '../common/logger';
import { TextKeys } from '../common/texts';

const TAG: string = 'filePreview';

@Component
export struct PreviewPane {
  /** 预览用的 `file://` URI（由调用方算好；调用方只在非空时才渲染本组件） */
  uri: string = '';
  /** 关闭预览：调用方清空 URI，页面恢复原布局 */
  onClose?: () => void;
  /** 重试：本组件内部重新加载同一个 URI（文件已在沙箱，重试无需再下载） */
  onRetry?: () => void;
  /** 交给其他应用打开：预览打不开时的另一条出路（与详情页「打开」同一路径） */
  onOpenExternal?: () => void;

  /** 正在渲染（下载阶段由页面自己的"下载中…"负责，这里只管交给 ArkWeb 之后） */
  @State private loading: boolean = true;
  /** 渲染失败（ArkWeb 报了错） */
  @State private failed: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController();

  /** 重新加载：文件已在沙箱，直接把同一个 URI 再交给 ArkWeb 一次 */
  private retry(): void {
    this.failed = false;
    this.loading = true;
    try {
      this.controller.loadUrl(this.uri);
    } catch (err) {
      Logger.warn(TAG, '预览重试失败，按打不开处理');
      this.loading = false;
      this.failed = true;
    }
  }

  build() {
    Column() {
      // 头部条：明示"这是预览"，并给出**唯一的退出入口**（原先只能往下滚，找不到出口）
      Row({ space: 8 }) {
        Text($r('app.string.' + TextKeys.FILE_PREVIEW_TITLE))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Button($r('app.string.' + TextKeys.FILE_PREVIEW_CLOSE))
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent'))
          .onClick(() => {
            const close: (() => void) | undefined = this.onClose;
            if (close !== undefined) {
              close();
            }
          })
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 4 })

      // 失败态：**给可读提示 + 两个出路**（只提示不给出路，用户只能干瞪眼）
      if (this.failed) {
        Column({ space: 12 }) {
          Text($r('app.string.' + TextKeys.FILE_PREVIEW_FAILED))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          Row({ space: 12 }) {
            Button($r('app.string.' + TextKeys.FILE_PREVIEW_RETRY))
              .fontSize(14)
              .onClick(() => {
                this.retry();
              })
            Button($r('app.string.' + TextKeys.FILE_OPEN))
              .fontSize(14)
              .onClick(() => {
                const open: (() => void) | undefined = this.onOpenExternal;
                if (open !== undefined) {
                  open();
                }
              })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 预览区**铺满剩余高度**（原先写死 720vp，长文档只能在一个半屏窗口里滚）
        Stack() {
          Web({ src: this.uri, controller: this.controller })
            .width('100%')
            .height('100%')
            // **必须显式打开**：API 12 起 `fileAccess` 默认关闭，关闭时 ArkWeb 会拒绝
            // `file://` 本地文件（实测报 `IsUrlFileExist failed` / `invalidFileUrl`），
            // 沙箱里的课件就打不开（2026-09-28 真机实测）
            .fileAccess(true)
            // 允许双指缩放看小字（PDF 的正文常是扫描件/小字号）
            .zoomAccess(true)
            // 深浅色交给文件自己（**不强制反色**：PDF 反色会让插图与彩色标注失真）
            .darkMode(WebDarkMode.Off)
            .onPageEnd((event: OnPageEndEvent) => {
              // ArkWeb 加载结束：有这条日志才说明本地文件确实被交到渲染器手里
              Logger.info(TAG, '预览加载结束');
              this.loading = false;
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              Logger.warn(TAG, `预览加载出错 code=${event.error.getErrorCode()}`);
              this.loading = false;
              this.failed = true;
            })

          if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(40)
                .height(40)
                .color($r('app.color.accent'))
              Text($r('app.string.' + TextKeys.FILE_PREVIEW_LOADING))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.bg_page'))
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
}
