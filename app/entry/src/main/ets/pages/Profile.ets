/**
 * 个人信息页（FR-16 的一个入口）。
 *
 * 两节：
 * - **账号**：登录后解析到的姓名与院系（此前这两个信息哪儿都没显示）；
 * - **下载位置**：应用内（缓存 / 文件目录）或**自定义目录**（用户用系统目录选择器选一个
 *   外部目录，授权持久化后下载直接落到那儿）。自定义目录里的文件**不做应用内预览**——
 *   那是外部文档 URI，ArkWeb 吃不了，交给系统应用打开才对（页面里有说明）。
 *
 * 分层：页面只表达"选了哪个"，落盘与授权交给 `filePickerAdapter`（系统能力出口）与
 * `settingsStore`（偏好）；不碰网络，也不自己拼沙箱路径。
 */

import { common } from '@kit.AbilityKit';
import { AuthStore } from '../viewmodel/authStore';
import { UserInfo } from '../model/auth';
import {
  changeCustomDownloadDir, changeUseDocumentDir, loadCustomDownloadDir, loadUseDocumentDir
} from '../viewmodel/settingsStore';
import { TextKeys } from '../common/texts';
import { showToast } from '../components/toast';
import { pickFolder } from '../native/filePickerAdapter';
import { applicationContextOf } from '../native/contextAdapter';

/** 个人信息页在设置栈里的目的地名 */
export const PROFILE_DESTINATION: string = 'profile';

@Component
export struct ProfileView {
  /** 是否使用应用内文件目录（否则缓存目录）；设置了自定义目录时以自定义目录优先 */
  @State private useDocumentDir: boolean = false;
  /** 自定义下载目录 URI（空串＝未设置） */
  @State private customDir: string = '';
  /** 账号信息（姓名 · 院系） */
  @State private account: string = '';

  private authStore: AuthStore = AuthStore.getInstance();

  aboutToAppear(): void {
    this.useDocumentDir = loadUseDocumentDir(this.appContext());
    this.customDir = loadCustomDownloadDir(this.appContext());
    const info: UserInfo | null = this.authStore.currentUserInfo();
    if (info !== null) {
      this.account = info.department.length > 0 ? `${info.name} · ${info.department}` : info.name;
    }
  }

  /** 偏好与目录授权都走应用级上下文（宿主上下文会落到另一份偏好文件，见 OPERATIONS §7.5） */
  private appContext(): common.ApplicationContext {
    return applicationContextOf(this.getUIContext().getHostContext() as common.Context);
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

          Text($r('app.string.' + TextKeys.PROFILE_DOWNLOAD_TITLE))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 16 })

          this.dirOption(false, TextKeys.PROFILE_DIR_APP_CACHE)
          this.dirOption(true, TextKeys.PROFILE_DIR_APP_FILES)

          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text($r('app.string.' + TextKeys.PROFILE_DIR_CUSTOM))
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(this.shortDir())
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .layoutWeight(1)

            Button($r('app.string.' + TextKeys.PROFILE_PICK_FOLDER))
              .fontSize(14)
              .onClick(() => {
                this.chooseFolder();
              })
            if (this.customDir.length > 0) {
              Button($r('app.string.' + TextKeys.PROFILE_CLEAR_FOLDER))
                .fontSize(14)
                .onClick(() => {
                  this.applyCustomDir('');
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.bg_card'))

          if (this.customDir.length === 0) {
            Text($r('app.string.' + TextKeys.PROFILE_NO_FOLDER))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 4 })
          }

          if (this.customDir.length > 0) {
            Text($r('app.string.' + TextKeys.PROFILE_CUSTOM_DIR_HINT))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 4 })
          }
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

  /** 应用内目录的单选项。选中它会清掉自定义目录——两者互斥，否则用户看不出文件存哪 */
  @Builder
  dirOption(useDocumentDir: boolean, labelKey: string) {
    Row() {
      Text($r('app.string.' + labelKey))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Radio({ value: useDocumentDir ? 'files' : 'cache', group: 'profile-download-dir' })
        .checked(this.customDir.length === 0 && this.useDocumentDir === useDocumentDir)
        .onChange((checked: boolean) => {
          if (checked) {
            this.useDocumentDir = useDocumentDir;
            changeUseDocumentDir(this.appContext(), useDocumentDir);
            this.applyCustomDir('');
          }
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.bg_card'))
  }

  /** 自定义目录只显示末段（完整 URI 又长又难读，但它确实是外部目录） */
  private shortDir(): string {
    if (this.customDir.length === 0) {
      return '';
    }
    const cut: number = this.customDir.lastIndexOf('/');
    return cut >= 0 ? decodeURIComponent(this.customDir.substring(cut + 1)) : this.customDir;
  }

  private chooseFolder(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    pickFolder(context).then((uri: string | null) => {
      if (uri === null) {
        return;
      }
      this.applyCustomDir(uri);
    }).catch(() => {
      showToast($r('app.string.' + TextKeys.PROFILE_PICK_FOLDER_FAILED));
    });
  }

  private applyCustomDir(uri: string): void {
    this.customDir = uri;
    if (!changeCustomDownloadDir(this.appContext(), uri)) {
      this.customDir = loadCustomDownloadDir(this.appContext());
      showToast($r('app.string.' + TextKeys.SETTINGS_SAVE_FAILED));
    }
  }
}
