/**
 * 文件详情页：元信息 + **下载** + **打开**。
 *
 * 本批刻意不做的事（见 files spec §2）：
 * - 不做进度条（属 FR-10；这里只给"下载中…"文字状态）；
 * - 不做 PDF / 图片原地预览（属 FR-21），也**不建预览适配器**（`scope-discipline` §2 判其为镀金）；
 * - 不做分享（属 FR-23）。
 *
 * 分层：本页只订阅状态、下发意图。下载与打开经 `fileStore` → `fileRepository` → `native.fileAdapter`，
 * 页面本身不碰网络与系统能力；页面唯一接触系统的地方是把宿主上下文转成应用级上下文
 * （与设置页写偏好同一做法，见 `native/contextAdapter` 的说明）。
 */

import { LearnFile, formatUploadDate } from '../model/file';
import { plainText } from '../model/notice';
import { DownloadState, FileState, FileStateListener, FileStore } from '../viewmodel/fileStore';
import { TextKeys } from '../common/texts';
import { showToast } from '../components/toast';
import { emptyView } from '../components/StateView';
import { common } from '@kit.AbilityKit';

/** 详情目的地的参数载体 */
export class FileDetailParam {
  readonly fileId: string;

  constructor(fileId: string) {
    this.fileId = fileId;
  }
}

@Component
export struct FileDetailView {
  @Prop fileId: string;

  /**
   * 只为了"store 变了就重建这一页"：下载状态变化要靠它触发刷新。
   * 必须真的赋新值——回调里什么都不写，ArkUI 观察不到变化（即"静默无效"）。
   */
  @State private revision: number = 0;

  private store: FileStore = FileStore.getInstance();

  private listener: FileStateListener = () => {
    this.revision = this.revision + 1;
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  /**
   * 与系统交互用的上下文。
   *
   * 用 `UIAbilityContext` 而不是 `ApplicationContext`：只有前者有 `startAbility`
   * （"用系统查看器打开"要用），而它的 `cacheDir` 与 `ApplicationContext` 指向同一个
   * 应用缓存目录，故下载落盘也用它，**一个上下文贯穿两步**。
   */
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  build() {
    Column() {
      if (this.store.fileOf(this.fileId) === null) {
        // 文件不在当前列表里（例如列表刚被整表替换）——给一个可理解的状态，而不是空白
        emptyView()
      } else {
        this.detail(this.store.fileOf(this.fileId) as LearnFile)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  detail(file: LearnFile) {
    Scroll() {
      Column({ space: 8 }) {
        Text(file.title)
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Row({ space: 8 }) {
          if (file.markedImportant) {
            Text($r('app.string.' + TextKeys.FILE_IMPORTANT))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
          }
          if (file.isNew) {
            Text($r('app.string.' + TextKeys.FILE_NEW))
              .fontSize(12)
              .fontColor($r('app.color.accent'))
          }
        }
        .width('100%')

        this.infoRow(TextKeys.FILE_COURSE, file.courseName)
        this.infoRow(TextKeys.FILE_TEACHER, file.courseTeacherName)
        this.infoRow(TextKeys.FILE_CATEGORY, file.categoryName)
        this.infoRow(TextKeys.FILE_TYPE, file.fileType.length > 0 ? file.fileType.toUpperCase() : '')
        this.infoRow(TextKeys.FILE_SIZE, file.size)
        this.infoRow(TextKeys.FILE_UPLOAD_TIME, formatUploadDate(file.uploadTimeMs))

        if (file.description.length > 0) {
          Text(plainText(file.description))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ top: 4 })
        } else {
          Text($r('app.string.' + TextKeys.FILE_NO_DESCRIPTION))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 4 })
        }

        Row({ space: 12 }) {
          // 两个动作分开（files spec §2.3）：一个只落盘，一个要交给系统查看器
          Button($r('app.string.' + this.downloadKey(file)))
            .fontSize(16)
            .enabled(this.store.downloadStateOf(file.id) !== DownloadState.DOWNLOADING)
            .onClick(() => {
              this.download(file);
            })
          Button($r('app.string.' + TextKeys.FILE_OPEN))
            .fontSize(16)
            .enabled(this.store.downloadStateOf(file.id) !== DownloadState.DOWNLOADING)
            .onClick(() => {
              this.openFile(file);
            })
        }
        .width('100%')
        .padding({ top: 12 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  /** 下载按钮的文案：下载 / 下载中… / 已下载 */
  private downloadKey(file: LearnFile): string {
    if (this.store.downloadStateOf(file.id) === DownloadState.DOWNLOADING) {
      return TextKeys.FILE_DOWNLOADING;
    }
    if (this.store.isDownloaded(file, this.context())) {
      return TextKeys.FILE_DOWNLOADED;
    }
    return TextKeys.FILE_DOWNLOAD;
  }

  /** 点"已下载"再下一遍是没有意义的；但按钮不置灰——重新下载是 FR-10 的"重试"职责 */
  private download(file: LearnFile): void {
    this.store.download(file, this.context(), false).catch(() => {
      // 失败必须有可见反馈，不静默（files spec §3.3 第 5 条）
      showToast($r('app.string.' + TextKeys.FILE_DOWNLOAD_FAILED));
    });
  }

  private openFile(file: LearnFile): void {
    this.store.openDownloaded(file, this.context()).catch(() => {
      showToast($r('app.string.' + TextKeys.FILE_DOWNLOAD_FAILED));
    });
  }

  @Builder
  infoRow(labelKey: string, value: string) {
    if (value.length > 0) {
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
  }
}
