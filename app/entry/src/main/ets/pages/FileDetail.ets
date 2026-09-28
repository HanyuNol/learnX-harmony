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

import { LearnFile, PROGRESS_UNKNOWN, canPreviewInApp, formatUploadDate } from '../model/file';
import { plainText } from '../model/notice';
import { DownloadState, FileStateListener, FileStore } from '../viewmodel/fileStore';
import { TextKeys } from '../common/texts';
import { showToast } from '../components/toast';
import { emptyView } from '../components/StateView';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { Logger } from '../common/logger';

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
   * 下载状态与进度**放进 @State 并在 build 里读**。
   *
   * 为什么不是"加一个计数器让页面重建"：2026-09-28 真机实测——**只在 build 里被读到的
   * 状态变量才会触发重渲染**；一个只写不读的计数器不会让页面刷新，
   * 于是下载明明成功了、按钮还停在"下载"（详情页的"后来居上"陷阱，见 OPERATIONS.md §7）。
   */
  /**
   * 当前这条文件（放进 @State，且 build 只读它）。
   *
   * 与通知/课程详情同一类问题（2026-09-28 第二轮扫描补漏）：原先 build 直接读
   * `this.store.fileOf(this.fileId)`，而订阅回调只更新**派生状态**（下载状态/进度/已下载）——
   * 列表整表替换（如切换学期）后，这些派生值往往没变 → @State 无变化 → 不重渲染，
   * 详情页会继续显示已经不存在的旧文件（本应转成空态）。
   */
  @State private file: LearnFile | null = null;
  @State private downloadState: DownloadState = DownloadState.IDLE;
  @State private percent: number = PROGRESS_UNKNOWN;
  @State private downloaded: boolean = false;
  /**
   * 应用内预览的 `file://` URI（空串＝不显示预览区）。
   *
   * 为什么需要它：设备上未必装了能打开该类型的应用（模拟器上实测
   * `16000019 No matching ability is found`），此时"打开"不能只报失败。
   * 上游 learnX 的做法正是**内置预览**（PDF 用 pdf 组件、其他用 WebView，
   * 见 `screens/FileDetail.tsx` 的 canRender 分支）；这里用系统 ArkWeb 承载本地文件，
   * 效果等同它那条 WebView 分支。
   */
  @State private previewUri: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();

  private store: FileStore = FileStore.getInstance();

  private listener: FileStateListener = () => {
    this.file = this.store.fileOf(this.fileId);
    this.downloadState = this.store.downloadStateOf(this.fileId);
    this.percent = this.store.downloadPercentOf(this.fileId);
    const current: LearnFile | null = this.file;
    this.downloaded = current !== null && this.store.isDownloaded(current, this.context());
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
      if (this.file === null) {
        // 文件不在当前列表里（例如列表刚被整表替换）——给一个可理解的状态，而不是空白
        emptyView()
      } else {
        this.detail(this.file as LearnFile)
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

        // 下载中的进度：**图形之外必须有文字**——进度条不进节点树就无从验收（陷阱 7）
        if (this.downloadState === DownloadState.DOWNLOADING) {
          Column({ space: 4 }) {
            if (this.percent >= 0) {
              Progress({ value: this.percent, total: 100, type: ProgressType.Linear })
                .width('100%')
              Text($r('app.string.' + TextKeys.FILE_DOWNLOAD_PROGRESS, this.percent))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            } else {
              // 服务端没给总长度：只说"下载中…"，**不猜百分比**（downloads spec §3.3 第 3 条）
              Text($r('app.string.' + TextKeys.FILE_DOWNLOADING))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .width('100%')
          .padding({ top: 8 })
        }

        // 失败：明说失败并给"重试"（覆盖旧文件重下一遍）
        if (this.downloadState === DownloadState.FAILED) {
          Row({ space: 8 }) {
            Text($r('app.string.' + TextKeys.FILE_DOWNLOAD_FAILED))
              .fontSize(14)
              .fontColor($r('app.color.danger'))
              .layoutWeight(1)
            Button($r('app.string.' + TextKeys.STATE_RETRY))
              .fontSize(14)
              .onClick(() => {
                this.download(file, true);
              })
          }
          .width('100%')
          .padding({ top: 8 })
        }

        Row({ space: 12 }) {
          // 落在盘上：下载 / 覆盖重下
          Button($r('app.string.' + this.downloadKey(file)))
            .fontSize(16)
            .enabled(this.downloadState !== DownloadState.DOWNLOADING)
            .onClick(() => {
              this.download(file, false);
            })
          Button($r('app.string.' + TextKeys.FILE_REDOWNLOAD))
            .fontSize(16)
            .enabled(this.downloadState !== DownloadState.DOWNLOADING)
            .onClick(() => {
              this.download(file, true);
            })
        }
        .width('100%')
        .padding({ top: 12 })

        Row({ space: 12 }) {
          // 应用内预览：不依赖设备上装没装能打开该类型的应用（上游 learnX 也是内置预览为主）。
          // **只在浏览器渲染得出来的类型上给这个按钮**——Office 文档点了也是空白，
          // 不给点了没用的按钮
          if (canPreviewInApp(file.fileType)) {
            Button($r('app.string.' + TextKeys.FILE_PREVIEW))
              .fontSize(16)
              .enabled(this.downloadState !== DownloadState.DOWNLOADING)
              .onClick(() => {
                this.preview(file);
              })
          }
          // 交给系统应用（装了 WPS 一类应用时才有用；设备上没有处理器会如实报错）
          Button($r('app.string.' + TextKeys.FILE_OPEN))
            .fontSize(16)
            .enabled(this.downloadState !== DownloadState.DOWNLOADING)
            .onClick(() => {
              this.openExternal(file);
            })
          // **另存为**：手机上唯一能"自己挑保存位置"的方式（手机不支持选文件夹）
          Button($r('app.string.' + TextKeys.FILE_SAVE_AS))
            .fontSize(16)
            .enabled(this.downloadState !== DownloadState.DOWNLOADING)
            .onClick(() => {
              this.saveAsFile(file);
            })
        }
        .width('100%')
        .padding({ top: 12 })

        // 说清为什么没有"预览"按钮：Office 文档在应用内渲染不出来，需用其他应用打开
        if (!canPreviewInApp(file.fileType)) {
          Text($r('app.string.' + TextKeys.FILE_NEEDS_OTHER_APP))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        // 应用内预览（仅在"系统查看器不可用"时出现）
        if (this.previewUri.length > 0) {
          Web({ src: this.previewUri, controller: this.webController })
            .width('100%')
            .height(720)
            // **必须显式打开**：API 12 起 `fileAccess` 默认关闭，关闭时 ArkWeb 会拒绝
            // `file://` 本地文件（实测报 `IsUrlFileExist failed` / `invalidFileUrl`），
            // 沙箱里的课件就打不开（2026-09-28 真机实测）
            .fileAccess(true)
            .onPageEnd((event: OnPageEndEvent) => {
              // ArkWeb 加载结束：有这条日志才说明本地文件确实被交到渲染器手里
              Logger.info('filePreview', '预览加载结束');
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              Logger.warn('filePreview', `预览加载出错 code=${event.error.getErrorCode()}`);
            })
        }
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  /** 下载按钮的文案：下载 / 下载中… / 已下载 */
  private downloadKey(file: LearnFile): string {
    if (this.downloadState === DownloadState.DOWNLOADING) {
      return TextKeys.FILE_DOWNLOADING;
    }
    return this.downloaded ? TextKeys.FILE_DOWNLOADED : TextKeys.FILE_DOWNLOAD;
  }

  /** 点"已下载"再下一遍没有意义；要重下用"重新下载"（forceRefresh=true） */
  private download(file: LearnFile, forceRefresh: boolean): void {
    this.store.download(file, this.context(), forceRefresh).catch(() => {
      // 失败必须有可见反馈，不静默（files spec §3.3 第 5 条）
      showToast($r('app.string.' + TextKeys.FILE_DOWNLOAD_FAILED));
    });
  }

  /** 应用内预览：先确保文件在沙箱（已下过则复用），再把 URL 交给 ArkWeb */
  private preview(file: LearnFile): void {
    this.store.download(file, this.context(), false).then(() => {
      const url: string = this.store.previewUriOf(file, this.context());
      if (url.length === 0) {
        // 下载成功了却算不出路径=不该发生；如实报，不静默
        showToast($r('app.string.' + TextKeys.FILE_OPEN_FAILED));
        return;
      }
      this.previewUri = url;
    }).catch(() => {
      showToast($r('app.string.' + TextKeys.FILE_DOWNLOAD_FAILED));
    });
  }

  /** 另存为：先确保文件在沙箱（已下过则复用），再让用户挑位置保存一份 */
  private saveAsFile(file: LearnFile): void {
    this.store.saveAs(file, this.context()).then((saved: boolean) => {
      if (saved) {
        showToast($r('app.string.' + TextKeys.FILE_SAVE_AS_SUCCEEDED));
      }
      // 用户取消选择不是失败，不提示
    }).catch(() => {
      showToast($r('app.string.' + TextKeys.FILE_SAVE_AS_FAILED));
    });
  }

  /** 交给系统应用打开（设备上未必有能处理该类型的应用，故与预览分开且不改文案） */
  private openExternal(file: LearnFile): void {
    this.store.openDownloaded(file, this.context()).catch(() => {
      showToast($r('app.string.' + TextKeys.FILE_OPEN_FAILED));
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
