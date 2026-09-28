/**
 * 设置页：主题（FR-13）、下载目录（FR-10）、学期切换入口（FR-05）、登出（FR-04）。
 * 其余设置项属 FR-16，尚未落地——不放占位行（"提前出现的占位"算镀金，见 `scope-discipline` §2）。
 *
 * 分层：本页只表达"用户选了哪个"，持久化与应用交给 `viewmodel/settingsStore`
 * （→ `storage.preferenceStore` + `native/themeAdapter`），页面不碰存储与系统能力。
 * 获取宿主上下文属于 ArkUI 的 UI 能力（与 `SsoLogin` 读注入脚本同一做法），
 * 传递下去即可。
 */

import { common } from '@kit.AbilityKit';
import { AuthStore } from '../viewmodel/authStore';
import {
  changeCustomDownloadDir, changeOmitCourseName, changeThemeMode, changeUseDocumentDir,
  loadCustomDownloadDir, loadOmitCourseName, loadThemeMode, loadUseDocumentDir
} from '../viewmodel/settingsStore';
import { pickFolder } from '../native/filePickerAdapter';
import { supportsFolderSelection } from '../native/deviceAdapter';
import { ThemeMode } from '../common/theme';
import { TextKeys } from '../common/texts';
import { showToast } from '../components/toast';
import { applicationContextOf } from '../native/contextAdapter';

/** 主题三个选项的取值与文案键（顺序即展示顺序） */
const THEME_OPTIONS: ThemeMode[] = [ThemeMode.FOLLOW_SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK];

/** 下载目录两个选项：缓存目录在前（当前默认值，先展示） */
const DOWNLOAD_DIR_OPTIONS: boolean[] = [false, true];

function textKeyOfThemeMode(mode: ThemeMode): string {
  if (mode === ThemeMode.LIGHT) {
    return TextKeys.THEME_LIGHT;
  }
  if (mode === ThemeMode.DARK) {
    return TextKeys.THEME_DARK;
  }
  return TextKeys.THEME_FOLLOW_SYSTEM;
}

function textKeyOfDownloadDir(useDocumentDir: boolean): string {
  return useDocumentDir ? TextKeys.SETTINGS_DOWNLOAD_DIR_FILES : TextKeys.SETTINGS_DOWNLOAD_DIR_CACHE;
}

@Component
export struct SettingsView {
  /** 打开学期切换页。由持有设置栈的 `Main` 提供——页面不自己造路由栈 */
  onOpenSemesters?: () => void;
  /** 打开"关于与帮助"。同上 */
  onOpenAbout?: () => void;
  /** 打开"个人信息"。同上 */
  onOpenProfile?: () => void;

  /** 当前主题模式。仅本页关心，故用页内状态 */
  @State private themeMode: ThemeMode = ThemeMode.FOLLOW_SYSTEM;
  /** 当前下载目录选择（`false` = 缓存目录） */
  @State private useDocumentDir: boolean = false;
  /** 下载文件名是否省略课程名前缀 */
  @State private omitCourseName: boolean = false;
  /** 自定义下载目录 URI（空串＝未设置）。设置后下载**平铺**落进该目录 */
  @State private customDir: string = '';
  /** 本设备是否支持选择文件夹（二合一支持；手机不支持，界面要如实说明） */
  @State private folderSelectionSupported: boolean = false;

  private store: AuthStore = AuthStore.getInstance();

  /** 偏好读写一律走应用级上下文；原因见 `native/contextAdapter.ets` */
  private appContext(): common.ApplicationContext {
    return applicationContextOf(this.getUIContext().getHostContext() as common.Context);
  }

  aboutToAppear(): void {
    this.themeMode = loadThemeMode(this.appContext());
    this.useDocumentDir = loadUseDocumentDir(this.appContext());
    this.omitCourseName = loadOmitCourseName(this.appContext());
    this.customDir = loadCustomDownloadDir(this.appContext());
    this.folderSelectionSupported = supportsFolderSelection();
  }

  /** 自定义目录只显示末段：完整 URI 又长又难读 */
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
      // 两种可能都要说清：选择未完成/未授权，或所选内容不是文件夹（设备不支持选文件夹）
      showToast($r('app.string.' + TextKeys.SETTINGS_FOLDER_NOT_DIR));
    });
  }

  private applyCustomDir(uri: string): void {
    this.customDir = uri;
    if (!changeCustomDownloadDir(this.appContext(), uri)) {
      this.customDir = loadCustomDownloadDir(this.appContext());
      showToast($r('app.string.' + TextKeys.SETTINGS_SAVE_FAILED));
    }
  }

  private selectOmitCourseName(omitCourseName: boolean): void {
    this.omitCourseName = omitCourseName;
    if (!changeOmitCourseName(this.appContext(), omitCourseName)) {
      // 写不进去就退回真实值，不留"界面与存储不一致"
      this.omitCourseName = loadOmitCourseName(this.appContext());
      showToast($r('app.string.' + TextKeys.SETTINGS_SAVE_FAILED));
    }
  }

  private select(mode: ThemeMode): void {
    // 先记下用户的选择，再如实回报结果：写入成功不等于主题已生效（审查 R-09）
    this.themeMode = mode;
    if (!changeThemeMode(this.appContext(), mode)) {
      showToast($r('app.string.' + TextKeys.THEME_APPLY_FAILED));
    }
  }

  private selectDownloadDir(useDocumentDir: boolean): void {
    this.useDocumentDir = useDocumentDir;
    if (!changeUseDocumentDir(this.appContext(), useDocumentDir)) {
      // 写不进去就如实说，并且把界面退回真实值，免得界面与存储长期不一致
      this.useDocumentDir = loadUseDocumentDir(this.appContext());
      showToast($r('app.string.' + TextKeys.SETTINGS_SAVE_FAILED));
    }
  }

  build() {
    Column() {
      Text($r('app.string.' + TextKeys.SETTINGS_THEME_TITLE))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })

      ForEach(THEME_OPTIONS, (mode: ThemeMode) => {
        Row() {
          Text($r('app.string.' + textKeyOfThemeMode(mode)))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Radio({ value: mode, group: TextKeys.SETTINGS_THEME_TITLE })
            .checked(this.themeMode === mode)
            .onChange((checked: boolean) => {
              if (checked) {
                this.select(mode);
              }
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.bg_card'))
      }, (mode: ThemeMode) => mode)

      // 下载目标目录（FR-10；两项的取舍见 docs/specs/downloads.md §2 第 2 条）
      Text($r('app.string.' + TextKeys.SETTINGS_DOWNLOAD_DIR_TITLE))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })

      ForEach(DOWNLOAD_DIR_OPTIONS, (option: boolean) => {
        Row() {
          Text($r('app.string.' + textKeyOfDownloadDir(option)))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Radio({ value: option ? 'files' : 'cache', group: TextKeys.SETTINGS_DOWNLOAD_DIR_TITLE })
            .checked(this.useDocumentDir === option)
            .onChange((checked: boolean) => {
              if (checked) {
                this.selectDownloadDir(option);
              }
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.bg_card'))
      }, (option: boolean) => option ? 'files' : 'cache')

      // 自定义目录：用户可选一个外部目录，下载直接落到那儿（授权已持久化）
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text($r('app.string.' + TextKeys.SETTINGS_DOWNLOAD_DIR_CUSTOM))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          // 未设置时这里留空，下面的提示行会说明"尚未选择目录"
          Text(this.shortDir())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)

        // **只在支持选文件夹的设备上给这个按钮**（系统文档：FOLDER 模式只支持二合一设备；
        // 手机上传了也会退化成"选文件"）。手机用户在文件详情页用"另存为"选位置
        if (this.folderSelectionSupported) {
          Button($r('app.string.' + TextKeys.SETTINGS_PICK_FOLDER))
            .fontSize(14)
            .onClick(() => {
              this.chooseFolder();
            })
        }
        if (this.customDir.length > 0) {
          Button($r('app.string.' + TextKeys.SETTINGS_CLEAR_FOLDER))
            .fontSize(14)
            .onClick(() => {
              this.applyCustomDir('');
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.bg_card'))

      if (!this.folderSelectionSupported) {
        Text($r('app.string.' + TextKeys.SETTINGS_FOLDER_UNSUPPORTED))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })
      } else if (this.customDir.length === 0) {
        Text($r('app.string.' + TextKeys.SETTINGS_NO_FOLDER))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })
      } else {
        Text($r('app.string.' + TextKeys.SETTINGS_CUSTOM_DIR_HINT))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })
      }

      // 显示项：下载文件名是否省略课程名前缀（FR-16）
      Text($r('app.string.' + TextKeys.SETTINGS_DISPLAY_TITLE))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })

      Row() {
        Text($r('app.string.' + TextKeys.SETTINGS_OMIT_COURSE_NAME))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.omitCourseName })
          .onChange((isOn: boolean) => {
            this.selectOmitCourseName(isOn);
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.bg_card'))

      // 学期切换入口（FR-05 的用户入口；上游也放在设置页）
      Row() {
        Text($r('app.string.' + TextKeys.SETTINGS_SEMESTER))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.bg_card'))
      .onClick(() => {
        const open: (() => void) | undefined = this.onOpenSemesters;
        if (open !== undefined) {
          open();
        }
      })

      // 个人信息（账号 + 下载位置，含自定义目录）
      Row() {
        Text($r('app.string.' + TextKeys.SETTINGS_PROFILE))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.bg_card'))
      .onClick(() => {
        const open: (() => void) | undefined = this.onOpenProfile;
        if (open !== undefined) {
          open();
        }
      })

      // 关于与帮助（FR-16）
      Row() {
        Text($r('app.string.' + TextKeys.SETTINGS_ABOUT))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.bg_card'))
      .onClick(() => {
        const open: (() => void) | undefined = this.onOpenAbout;
        if (open !== undefined) {
          open();
        }
      })

      Blank()

      // 登出：FR-04 的入口（原先挂在入口占位页上，随页签搬到这里）
      Button($r('app.string.' + TextKeys.SETTINGS_LOGOUT))
        .width('100%')
        .margin({ bottom: 24 })
        .onClick(() => {
          this.store.logout();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.bg_page'))
  }
}
