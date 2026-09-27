/**
 * 设置页。本批次**只有"主题"一项**（FR-13）——其余设置项属 FR-16，现在不放占位行
 * （"提前出现的占位"算镀金，见 `scope-discipline` §2）。
 *
 * 分层：本页只表达"用户选了哪个模式"，持久化与应用交给 `viewmodel/settingsStore`
 * （→ `storage.preferenceStore` + `native/themeAdapter`），页面不碰存储与系统能力。
 * 获取宿主上下文属于 ArkUI 的 UI 能力（与 `SsoLogin` 读注入脚本同一做法），
 * 传递下去即可。
 */

import { common } from '@kit.AbilityKit';
import { AuthStore } from '../viewmodel/authStore';
import { changeThemeMode, loadThemeMode } from '../viewmodel/settingsStore';
import { ThemeMode } from '../common/theme';
import { TextKeys } from '../common/texts';
import { showToast } from '../components/toast';

/** 主题三个选项的取值与文案键（顺序即展示顺序） */
const THEME_OPTIONS: ThemeMode[] = [ThemeMode.FOLLOW_SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK];

function textKeyOfThemeMode(mode: ThemeMode): string {
  if (mode === ThemeMode.LIGHT) {
    return TextKeys.THEME_LIGHT;
  }
  if (mode === ThemeMode.DARK) {
    return TextKeys.THEME_DARK;
  }
  return TextKeys.THEME_FOLLOW_SYSTEM;
}

@Component
export struct SettingsView {
  /** 当前主题模式。仅本页关心，故用页内状态 */
  @State private themeMode: ThemeMode = ThemeMode.FOLLOW_SYSTEM;

  private store: AuthStore = AuthStore.getInstance();

  /**
   * 供偏好读写使用的上下文。
   *
   * **必须与启动路径一致用 ApplicationContext**：`getHostContext()` 给的是
   * UIAbilityContext，实测它写入的偏好**重启后读不回来**（2026-09-27 真机：
   * 设置页写 FOLLOW_SYSTEM → force-stop 重启 → 读到旧值 DARK），
   * 而启动路径用 ApplicationContext 写的值能持久化。故这里统一到应用级上下文。
   */
  private appContext(): common.Context {
    const host: common.Context = this.getUIContext().getHostContext() as common.Context;
    return host.getApplicationContext();
  }

  aboutToAppear(): void {
    this.themeMode = loadThemeMode(this.appContext());
  }

  private select(mode: ThemeMode): void {
    // 先记下用户的选择，再如实回报结果：写入成功不等于主题已生效（审查 R-09）
    this.themeMode = mode;
    if (!changeThemeMode(this.appContext(), mode)) {
      showToast($r('app.string.' + TextKeys.THEME_APPLY_FAILED));
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
