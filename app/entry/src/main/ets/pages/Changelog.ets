/**
 * 更新日志页（FR-28 的"更新日志展示"）。
 *
 * 内容来自**打包进包里的** `CHANGELOG.md`（`native/changelogAdapter` 读 rawfile），
 * 用最小的 Markdown → HTML（`common/markdown`，纯函数 + 单测）转成富文本，
 * 再走**同一套**清洗 + 沙箱渲染（`components/RichTextView`）。
 *
 * 为什么不写 `<Text>` 直接显示 Markdown 源码：变更日志是"要给人读"的东西，
 * 而它自己的语法（`##`、`-`、`**`）会糊住内容。复用富文本那条路成本很低
 * （转换是纯函数、渲染与清洗都已存在），收益是这一页真的能读。
 *
 * 分层：读资源走 `native/changelogAdapter`，转换走 `common/markdown`（纯逻辑），
 * 本页只负责组织与展示。
 */

import { common } from '@kit.AbilityKit';
import { RichTextView } from '../components/RichTextView';
import { markdownToHtml } from '../common/markdown';
import { readChangelogSource } from '../native/changelogAdapter';
import { TextKeys } from '../common/texts';

/** "更新日志"在设置栈里的目的地名（`Main` 的 `navDestination` 用它分派） */
export const CHANGELOG_DESTINATION: string = 'changelog';

@Component
export struct ChangelogView {
  /** 转换好的 HTML；空串＝资源读不到（显示空态，不显示空白页） */
  @State private html: string = '';

  aboutToAppear(): void {
    const context: common.Context = this.getUIContext().getHostContext() as common.Context;
    const source: string = readChangelogSource(context);
    this.html = markdownToHtml(source);
  }

  build() {
    Column() {
      if (this.html.length === 0) {
        // 读不到就说读不到（漏打包/文件被删），不要给用户一片空白
        Text($r('app.string.' + TextKeys.CHANGELOG_EMPTY))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(24)
      } else {
        // `fillHeight`：这一页**就是**这篇文档，让它独占高度、自己滚（避免内外两层滚动条）
        RichTextView({ raw: this.html, fillHeight: true })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
