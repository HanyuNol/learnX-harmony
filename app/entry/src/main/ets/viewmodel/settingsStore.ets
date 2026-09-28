/**
 * 主题偏好的读写与应用：设置页与此之间的**唯一缝**。
 *
 * 为什么需要这一层：架构不变量 §1 要求 `pages` 不直接读写存储、不直接调用系统能力。
 * 设置页只表达"用户选了哪个模式"，由这里落到 `storage.preferenceStore`（持久化）
 * 与 `native.themeAdapter`（应用到系统）——两个唯一出口各自不变。
 *
 * 为什么**不带状态**：主题一改就由系统立即生效（`setColorMode` 影响全局取色），
 * 没有任何页面需要"观察"这个值，故不设订阅。将来设置项变多（FR-16）且需要跨页共享时，
 * 再按 ADR-0004 把它做成 `authStore` 那样的订阅式 Store——现在不做。
 */

import { common } from '@kit.AbilityKit';
import { ThemeMode } from '../common/theme';
import {
  readThemeMode, writeThemeMode, readUseDocumentDir, writeUseDocumentDir, readOmitCourseName,
  writeOmitCourseName, readCustomDownloadDir, writeCustomDownloadDir
} from '../storage/preferenceStore';
import { applyThemeMode } from '../native/themeAdapter';
import { Logger } from '../common/logger';

const TAG: string = 'settingsStore';

/** 读取当前主题模式（未设置过或存储读失败时为"跟随系统"） */
export function loadThemeMode(context: common.Context): ThemeMode {
  return readThemeMode(context);
}

/**
 * 切换主题模式：先持久化，再应用到系统。
 *
 * 返回**是否完全生效**。设置页不得只看"写入成功"就提示成功——写入成功而
 * `setColorMode` 抛异常时主题并未改变（代码审查 R-09）。任一步失败都返回 false，
 * 由页面如实告知用户（失败原因已在各自模块里记日志）。
 */
export function changeThemeMode(context: common.Context, mode: ThemeMode): boolean {
  const persisted: boolean = writeThemeMode(context, mode);
  if (!persisted) {
    Logger.warn(TAG, `主题模式未能持久化 mode=${mode}`);
    return false;
  }

  const applied: boolean = applyThemeMode(context as common.ApplicationContext, mode);
  if (!applied) {
    Logger.warn(TAG, `主题模式已保存但未能应用 mode=${mode}`);
    return false;
  }
  return true;
}

/** 读取下载目标目录偏好（`true` = 应用文件目录，`false`/未设置 = 缓存目录） */
export function loadUseDocumentDir(context: common.Context): boolean {
  return readUseDocumentDir(context);
}

/**
 * 设置下载目标目录。
 *
 * 返回**是否持久化成功**（与主题不同，这项没有"应用到系统"这一步，故只有一道门）。
 * 写失败要能被页面感知：静默丢掉用户的选择、下次启动又弹回旧值，是最难排查的一类问题。
 */
export function changeUseDocumentDir(context: common.Context, useDocumentDir: boolean): boolean {
  const persisted: boolean = writeUseDocumentDir(context, useDocumentDir);
  if (!persisted) {
    Logger.warn(TAG, `下载目录偏好未能持久化 useDocumentDir=${useDocumentDir}`);
  }
  return persisted;
}

/** 读取"下载文件名是否省略课程名前缀"（FR-16 的显示项） */
export function loadOmitCourseName(context: common.Context): boolean {
  return readOmitCourseName(context);
}

/** 设置"下载文件名是否省略课程名前缀"。返回是否持久化成功 */
export function changeOmitCourseName(context: common.Context, omitCourseName: boolean): boolean {
  const persisted: boolean = writeOmitCourseName(context, omitCourseName);
  if (!persisted) {
    Logger.warn(TAG, `文件名偏好未能持久化 omitCourseName=${omitCourseName}`);
  }
  return persisted;
}

/** 读取用户选定的自定义下载目录（空串 = 未设置，用应用内目录） */
export function loadCustomDownloadDir(context: common.Context): string {
  return readCustomDownloadDir(context);
}

/** 设置/清除自定义下载目录（传空串即清除）。返回是否持久化成功 */
export function changeCustomDownloadDir(context: common.Context, uri: string): boolean {
  const persisted: boolean = writeCustomDownloadDir(context, uri);
  if (!persisted) {
    Logger.warn(TAG, '自定义下载目录未能持久化');
  }
  return persisted;
}
