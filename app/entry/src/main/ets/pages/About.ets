/**
 * "关于与帮助"页（FR-16）。
 *
 * 这一页有两个不可省的内容：
 * - **来源与许可**：ADR-0002 要求保留上游归属，这是合规项而不是装饰；
 * - **版本号来自打包信息**（`native/appInfoAdapter`），不硬编码——硬编码的版本号在发版后
 *   必然与真值不符，而这一页正是用户核对版本的地方。
 *
 * 分层：本页只展示，信息取自 `native/appInfoAdapter`（系统能力的唯一出口）。
 */

import { AppInfo, appInfo } from '../native/appInfoAdapter';
import { TextKeys } from '../common/texts';

/** "关于与帮助"在设置栈里的目的地名（`Main` 的 `navDestination` 用它分派） */
export const ABOUT_DESTINATION: string = 'about';

@Component
export struct AboutView {
  /** 应用信息在进页时读一次即可（打包信息在运行期不会变） */
  @State private info: AppInfo = new AppInfo('', '');

  aboutToAppear(): void {
    this.info = appInfo();
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 版本与包名：值直接来自打包信息
        this.infoRow(TextKeys.ABOUT_VERSION, this.info.versionName)
        this.infoRow(TextKeys.ABOUT_BUNDLE, this.info.bundleName)

        Text($r('app.string.' + TextKeys.ABOUT_ATTRIBUTION_TITLE))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 8 })
        Text($r('app.string.' + TextKeys.ABOUT_ATTRIBUTION_BODY))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Text($r('app.string.' + TextKeys.HELP_TITLE))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 8 })
        this.helpLine(TextKeys.HELP_NETWORK)
        this.helpLine(TextKeys.HELP_LOGIN)
        this.helpLine(TextKeys.HELP_FILE)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  infoRow(labelKey: string, value: string) {
    Row({ space: 8 }) {
      Text($r('app.string.' + labelKey))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  helpLine(key: string) {
    Text($r('app.string.' + key))
      .fontSize(14)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
  }
}
