/**
 * 通知详情页。
 *
 * 本批正文按**纯文本**呈现（富文本渲染属 FR-22，且 SECURITY §3 要求"按白名单清洗、
 * 不得整体信任服务端 HTML"——现在更不该把未清洗的 HTML 塞进 WebView）。
 * 附件本批只显示名字，点开跳文件详情属 FR-08。
 *
 * 打开时按上游发一次"已读"请求（服务端据此记已读），成功后由 store 记下**本地已读覆盖**，
 * 让列表的未读标记立刻消失；下次刷新以服务端为准（notices spec §3.3 第 7 条）。
 */

import { common } from '@kit.AbilityKit';
import { Notice, formatPublishDate, plainText } from '../model/notice';
import { NoticeStateListener, NoticeStore } from '../viewmodel/noticeStore';
import { TextKeys } from '../common/texts';
import { composeShareText } from '../common/shareText';
import { shareText } from '../native/shareAdapter';
import { emptyView } from '../components/StateView';
import { showToast } from '../components/toast';
import { RichTextView } from '../components/RichTextView';

/** 详情目的地的参数载体 */
export class NoticeDetailParam {
  readonly noticeId: string;

  constructor(noticeId: string) {
    this.noticeId = noticeId;
  }
}

@Component
export struct NoticeDetailView {
  @Prop noticeId: string;
  /** 打开时发"已读"请求的开关：课程详情页签里内嵌详情时不重复发 */
  @Prop markReadOnOpen: boolean = true;

  private store: NoticeStore = NoticeStore.getInstance();

  /**
   * 当前这条通知（放进 @State）。
   *
   * 为什么不让 build 直接读 store（2026-09-28 代码审查 m2）：列表整表替换（如切换学期）后，
   * 只读 store 的渲染路径**不会重算**，详情页会继续显示已经不存在的旧通知。
   */
  @State private notice: Notice | null = null;

  private listener: NoticeStateListener = () => {
    this.notice = this.store.noticeOf(this.noticeId);
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    this.notice = this.store.noticeOf(this.noticeId);
    if (this.notice !== null && this.markReadOnOpen) {
      this.store.markReadByOpening(this.notice as Notice);
    }
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  build() {
    Column() {
      if (this.notice === null) {
        // 通知不在当前列表里（例如列表刚被整表替换）——给它一个可理解的状态，而不是空白
        emptyView()
      } else {
        this.detail(this.notice as Notice)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  /**
   * 分享这条通知的正文（FR-23）。
   *
   * 正文走 `plainText`（把服务端 HTML 剥成纯文本）——分享出去的必须是**对方能直接读的东西**，
   * 而不是带标签的 HTML；组装与截断规则在 `common/shareText`（纯函数、有单测）。
   * 清洗后的正文一个字都没有时不发（分享一条空白没有意义）。
   */
  private shareNotice(notice: Notice): void {
    const text: string = composeShareText(notice.title, plainText(notice.content));
    if (text.length === 0) {
      return;
    }
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    shareText(context, text, notice.title).catch(() => {
      // 面板起不来（或用户在系统侧取消不了的那类错误）：如实提示；取消不算失败故不提示
      showToast($r('app.string.' + TextKeys.SHARE_FAILED));
    });
  }

  @Builder
  detail(notice: Notice) {
    Scroll() {
      Column({ space: 12 }) {
        Text(notice.title)
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Row({ space: 8 }) {
          Text(notice.publisher)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(formatPublishDate(notice.publishTime))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        // 正文按**清洗后的富文本**渲染（含图片；脚本/事件属性/危险链接已在清洗层丢掉）
        RichTextView({ raw: notice.content })

        // 分享正文（FR-23 的文本一半）：把"标题 + 正文纯文本"交给系统分享面板。
        // 用**文字按钮**而不是标题栏图标：图标不进 UI 节点树，看不见就等于没验过（陷阱 8）。
        Button($r('app.string.' + TextKeys.SHARE))
          .fontSize(14)
          .onClick(() => {
            this.shareNotice(notice);
          })

        if (notice.attachmentName.length > 0) {
          Row({ space: 8 }) {
            Text($r('app.string.' + TextKeys.NOTICE_ATTACHMENT))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(notice.attachmentName)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }
}
