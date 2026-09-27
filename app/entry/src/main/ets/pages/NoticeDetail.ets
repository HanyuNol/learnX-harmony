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

import { Notice, formatPublishDate, plainText } from '../model/notice';
import { NoticeStore } from '../viewmodel/noticeStore';
import { TextKeys } from '../common/texts';
import { emptyView } from '../components/StateView';

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

  aboutToAppear(): void {
    const notice: Notice | null = this.store.noticeOf(this.noticeId);
    if (notice !== null && this.markReadOnOpen) {
      this.store.markReadByOpening(notice);
    }
  }

  build() {
    Column() {
      if (this.store.noticeOf(this.noticeId) === null) {
        // 通知不在当前列表里（例如列表刚被整表替换）——给它一个可理解的状态，而不是空白
        emptyView()
      } else {
        this.detail(this.store.noticeOf(this.noticeId) as Notice)
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

        Text(plainText(notice.content))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

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
