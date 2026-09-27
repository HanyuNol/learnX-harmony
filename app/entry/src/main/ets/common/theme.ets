/**
 * 主题模式：存储值 ⇄ 领域模式 ⇄ 系统 ColorMode 的映射。
 *
 * 为什么单独成模块：这是**纯映射逻辑**，不碰存储、不碰 UI，可在宿主侧穷举测试
 * （testing-and-quality §1.1「纯逻辑必须与平台调用分离」）。真正调用
 * `setColorMode` 的系统能力在 `native/themeAdapter.ets`。
 *
 * 为什么"跟随系统"不是一种颜色而是一个**不设置**：主题的深浅两套色值放在
 * `resources/base/` 与 `resources/dark/`，由系统按深浅自动取材。应用只管把
 * `COLOR_MODE_NOT_SET` 交回去，让系统自己决定——这样手动指定与跟随系统共用同一套资源，
 * 不必在页面里分叉（ui-shell spec §3.3）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 主题模式。取值即**持久化的字面量**，改动会破坏已存偏好——
 * 新增取值可行，改名须同时迁移存储。
 */
export enum ThemeMode {
  /** 跟随系统深浅 */
  FOLLOW_SYSTEM = 'FOLLOW_SYSTEM',
  /** 强制浅色 */
  LIGHT = 'LIGHT',
  /** 强制深色 */
  DARK = 'DARK'
}

/** 存储读到空值 / 未知值时的退让目标 */
export const DEFAULT_THEME_MODE: ThemeMode = ThemeMode.FOLLOW_SYSTEM;

/**
 * 把存储里的字符串解析为模式。
 *
 * **严格匹配**：存储由本应用写入，大小写不符或带空白都视为非法值——
 * 退让为跟随系统，而不是猜测（静默修正是最难排查的一类问题）。
 */
export function parseThemeMode(raw: string): ThemeMode {
  if (raw === ThemeMode.LIGHT) {
    return ThemeMode.LIGHT;
  }
  if (raw === ThemeMode.DARK) {
    return ThemeMode.DARK;
  }
  return DEFAULT_THEME_MODE;
}

/**
 * 映射为系统 ColorMode。
 *
 * `FOLLOW_SYSTEM` → `COLOR_MODE_NOT_SET`（由系统决定），
 * 这正是"跟随系统"的实现方式，故不需要额外的"系统当前深浅"输入。
 */
export function themeModeToColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
  if (mode === ThemeMode.LIGHT) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  if (mode === ThemeMode.DARK) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}
