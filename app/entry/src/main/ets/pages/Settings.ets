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
import { AssignmentStore } from '../viewmodel/assignmentStore';
import { AssignmentState } from '../viewmodel/assignmentStore';
import {
  assignmentReminderOffsetMax, changeAssignmentReminder, changeAssignmentReminderNoIfComplete,
  changeAssignmentReminderOffset, changeCustomDownloadDir, changeOmitCourseName, changeThemeMode,
  changeUseDocumentDir, loadAssignmentReminder, loadAssignmentReminderNoIfComplete,
  loadAssignmentReminderOffset, loadCustomDownloadDir, loadOmitCourseName, loadThemeMode,
  loadUseDocumentDir, parseAssignmentReminderOffset
} from '../viewmodel/settingsStore';
import { ReminderSyncResult, reminderNotificationsEnabled, syncAssignmentReminders }
  from '../viewmodel/reminderSync';
import { SemesterStore } from '../viewmodel/semesterStore';
import { CourseStore } from '../viewmodel/courseStore';
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
  /** 打开**全局搜索**（漏传＝点了没反应） */
  onOpenSearch?: () => void;

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
  /** 是否登记作业截止提醒（FR-18） */
  @State private reminderEnabled: boolean = false;
  /** 提醒提前量（分钟）的**已持久化值** */
  @State private reminderOffsetMinutes: number = 0;
  /** 提前量输入框里的文本（可能尚未通过校验） */
  @State private reminderOffsetText: string = '';
  /** 已完成的作业不提醒 */
  @State private reminderNoIfComplete: boolean = false;
  /** 系统通知总开关是否开着（关着时提醒登记了也弹不出来） */
  @State private reminderNotificationOn: boolean = true;
  /** 正在对齐系统提醒（含为对齐而补拉作业数据） */
  @State private reminderAligning: boolean = false;
  /** 上一次对齐**没能把提醒登记进系统**（如系统通知被关、设备不支持）——常驻提示，不是一闪而过的 Toast */
  @State private reminderFailed: boolean = false;

  private store: AuthStore = AuthStore.getInstance();
  /** 对齐提醒要用到"当前已知的作业"；没有数据时要先把作业拉起来（见 `alignReminders`） */
  private assignmentStore: AssignmentStore = AssignmentStore.getInstance();
  /** 同上：作业取数需要"当前学期 + 课程集"这两个前提（与作业页的取数口径一致） */
  private semesterStore: SemesterStore = SemesterStore.getInstance();
  private courseStore: CourseStore = CourseStore.getInstance();

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
    this.reminderEnabled = loadAssignmentReminder(this.appContext());
    this.reminderOffsetMinutes = loadAssignmentReminderOffset(this.appContext());
    this.reminderOffsetText = `${this.reminderOffsetMinutes}`;
    this.reminderNoIfComplete = loadAssignmentReminderNoIfComplete(this.appContext());
    this.reminderNotificationOn = reminderNotificationsEnabled();
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

  /**
   * 开/关作业截止提醒（FR-18）。
   *
   * 改动后**立刻对齐一次**：开启＝把当前作业登记上（没有数据就先把作业拉起来，见 `alignReminders`），
   * 关闭＝把此前登记的撤干净。不留"关了还在弹"的幽灵提醒。
   */
  private selectReminderEnabled(enabled: boolean): void {
    const before: boolean = this.reminderEnabled;
    this.reminderEnabled = enabled;
    if (!changeAssignmentReminder(this.appContext(), enabled)) {
      this.reminderEnabled = before;
      showToast($r('app.string.' + TextKeys.SETTINGS_SAVE_FAILED));
      return;
    }
    this.alignReminders();
  }

  private selectReminderNoIfComplete(enabled: boolean): void {
    this.reminderNoIfComplete = enabled;
    if (!changeAssignmentReminderNoIfComplete(this.appContext(), enabled)) {
      this.reminderNoIfComplete = !enabled;
      showToast($r('app.string.' + TextKeys.SETTINGS_SAVE_FAILED));
      return;
    }
    if (this.reminderEnabled) {
      this.alignReminders();
    }
  }

  /**
   * 提交提前量输入。
   *
   * 非法输入**不改存储、退回真实值**并提示——静默丢掉用户的输入、或把它当数字存下去，
   * 都会让"设置里写的"和"实际生效的"对不上（与 `fileOmitCourseName` 那条同一考虑）。
   * 输入与已存值相同则不写、也不触发对齐（省一次系统调用）。
   */
  private applyReminderOffset(): void {
    const parsed: number | null = parseAssignmentReminderOffset(this.reminderOffsetText);
    if (parsed === null) {
      showToast($r('app.string.' + TextKeys.SETTINGS_REMINDER_OFFSET_INVALID,
        assignmentReminderOffsetMax()));
      this.reminderOffsetText = `${this.reminderOffsetMinutes}`;
      return;
    }
    if (parsed === this.reminderOffsetMinutes) {
      // 顺手归一化显示（用户可能输了前导空格），但不重复写
      this.reminderOffsetText = `${parsed}`;
      return;
    }
    if (!changeAssignmentReminderOffset(this.appContext(), parsed)) {
      this.reminderOffsetText = `${this.reminderOffsetMinutes}`;
      showToast($r('app.string.' + TextKeys.SETTINGS_SAVE_FAILED));
      return;
    }
    this.reminderOffsetMinutes = parsed;
    this.reminderOffsetText = `${parsed}`;
    if (this.reminderEnabled) {
      this.alignReminders();
    }
  }

  /**
   * 把当前设置与当前作业对齐到系统提醒。
   *
   * 先 `ensureLoadedFor` 再对齐的原因：提醒是"作业数据的函数"，用户刚打开提醒开关时
   * 作业可能一条都还没加载（作业是进"作业"标签才拉的）。不补这一步，用户打开开关却
   * 一个提醒也没登记，而且**界面上看不出任何异常**——要等他恰好去作业页看一眼才生效，
   * 那正是这个功能要避免的"被落下"。已有数据时这一句是空操作（store 内有签名比对）。
   */
  private alignReminders(): void {
    const context: common.ApplicationContext = this.appContext();
    this.reminderAligning = true;
    this.reminderFailed = false;
    this.assignmentStore.ensureLoadedFor(this.semesterStore.snapshot().current,
      this.courseStore.snapshot().items)
      .then(() => {
        // "完整"=当前学期每门课都取到了；不完整时 syncAssignmentReminders 会一条也不动
        const state: AssignmentState = this.assignmentStore.snapshot();
        const complete: boolean = state.totalCourses > 0 && state.failedCourses === 0;
        return syncAssignmentReminders(context, state.items, complete);
      })
      .then((result: ReminderSyncResult) => {
        this.reminderAligning = false;
        // 登记可能因"系统通知被关掉 / 系统拒绝登记"而失败，顺带刷新这一提示行
        this.reminderNotificationOn = reminderNotificationsEnabled();
        this.reminderFailed = result.failed;
        if (result.failed) {
          showToast($r('app.string.' + TextKeys.SETTINGS_REMINDER_FAILED));
        }
      })
      .catch(() => {
        this.reminderAligning = false;
        this.reminderFailed = true;
        showToast($r('app.string.' + TextKeys.SETTINGS_REMINDER_FAILED));
      });
  }

  build() {
    Column() {
      // **必须有滚动容器**：设置项多起来会超过一屏，裸 Column 只会把超出的部分裁掉、
      // 而且滑不动（2026-09-28 用户实测报"设置页无法上下滑动"）
      Scroll() {
        Column() {
          this.content()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  /** 设置项（整块放进 Scroll；登出也在这里，跟在内容末尾） */
  @Builder
  content() {
    Column() {
      // 搜索入口：与其它标签页一致，是**可见的文字按钮**
      Row({ space: 8 }) {
        Blank()
        Button() {
          Image($r('app.media.ic_search'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_primary'))
        }
        .backgroundColor(Color.Transparent)
        .padding(4)
        .onClick(() => {
          const open: (() => void) | undefined = this.onOpenSearch;
          if (open !== undefined) {
            open();
          }
        })
      }
      .width('100%')
      .padding({ top: 8 })

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

      // 提醒（FR-18）：作业截止前由系统弹出本地通知
      Text($r('app.string.' + TextKeys.SETTINGS_REMINDER_TITLE))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })

      Row({ space: 8 }) {
        Text($r('app.string.' + TextKeys.SETTINGS_REMINDER_ENABLED))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        // 对齐要读系统现有提醒、必要时还要先拉作业数据，给一个可见的进行中反馈
        if (this.reminderAligning) {
          Text($r('app.string.' + TextKeys.LIST_REFRESHING))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
          .onChange((isOn: boolean) => {
            this.selectReminderEnabled(isOn);
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.bg_card'))

      // 两项参数只在开关打开时出现（不给当前无效果的设置行——scope-discipline §3）
      if (this.reminderEnabled) {
        Row({ space: 8 }) {
          Text($r('app.string.' + TextKeys.SETTINGS_REMINDER_OFFSET))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          TextInput({ text: this.reminderOffsetText })
            .type(InputType.Number)
            .fontSize(16)
            .width(96)
            .textAlign(TextAlign.End)
            .onChange((value: string) => {
              this.reminderOffsetText = value;
            })
            .onSubmit(() => {
              this.applyReminderOffset();
            })
            .onBlur(() => {
              this.applyReminderOffset();
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.bg_card'))

        Row() {
          Text($r('app.string.' + TextKeys.SETTINGS_REMINDER_NO_IF_COMPLETE))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.reminderNoIfComplete })
            .onChange((isOn: boolean) => {
              this.selectReminderNoIfComplete(isOn);
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.bg_card'))

        Text($r('app.string.' + TextKeys.SETTINGS_REMINDER_HINT))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })

        // 系统通知被关掉时**如实说**：提醒登记得上，但弹不出来，用户不该以为"设置好了"
        if (!this.reminderNotificationOn) {
          Text($r('app.string.' + TextKeys.SETTINGS_REMINDER_NOTIFICATION_OFF))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 4 })
        }

        // 上一次**没能登记进系统**时也留在界面上（Toast 一闪就没了，
        // 而"提醒其实没登记上"是用户必须知道的状态——2026-09-28 模拟器实测：
        // 该模拟器的提醒服务拒绝一切登记，正是靠这条才看得出来）
        if (this.reminderFailed) {
          Text($r('app.string.' + TextKeys.SETTINGS_REMINDER_FAILED))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 4 })
        }
      }

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

      // 登出：FR-04 的入口（原先挂在入口占位页上，随页签搬到这里）
      Button($r('app.string.' + TextKeys.SETTINGS_LOGOUT))
        .width('100%')
        .margin({ top: 24 })
        .onClick(() => {
          this.store.logout();
        })
    }
    .width('100%')
  }
}
