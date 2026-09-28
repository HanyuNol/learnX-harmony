/**
 * 个人信息页（FR-16 的一个入口）。
 *
 * 目前是**账号**一节：登录后解析到的姓名与院系（此前这两个信息哪儿都没显示）。
 *
 * 下载位置**不在这里**——用户反馈后已挪到「设置 → 下载目录」（那才是它该在的地方）。
 *
 * 分层：页面只读 `authStore` 的状态，不碰网络与系统能力。
 */

import { AuthStore } from '../viewmodel/authStore';
import { UserInfo } from '../model/auth';
import { TextKeys } from '../common/texts';

/** 个人信息页在设置栈里的目的地名 */
export const PROFILE_DESTINATION: string = 'profile';

@Component
export struct ProfileView {
  /** 账号信息（姓名 · 院系） */
  @State private account: string = '';

  private authStore: AuthStore = AuthStore.getInstance();

  aboutToAppear(): void {
    const info: UserInfo | null = this.authStore.currentUserInfo();
    if (info !== null) {
      this.account = info.department.length > 0 ? `${info.name} · ${info.department}` : info.name;
    }
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 8 }) {
          Text($r('app.string.' + TextKeys.PROFILE_ACCOUNT_TITLE))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 8 })

          Row() {
            Text(this.account.length > 0 ? this.account : '—')
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))

        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
