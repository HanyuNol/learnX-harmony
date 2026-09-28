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

import { Notice, formatPublishDate } from '../model/notice';
import { NoticeStateListener, NoticeStore } from '../viewmodel/noticeStore';
import { TextKeys } from '../common/texts';
import { emptyView } from '../components/StateView';
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
