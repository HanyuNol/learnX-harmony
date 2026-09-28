/**
 * 偏好存储：系统首选项（Preferences）的**唯一读写入口**（架构不变量 §3）。
 *
 * 与凭据分开的理由：凭据走关键资产存储（加密、需要认证），偏好是普通键值，
 * 混在一起会让"哪些数据被加密保护"变得含混（ADR-0007 只把凭据纳入加密存储）。
 *
 * 只存**当前已确定的偏好**，不为将来预留键。新增偏好时在此加一对读写函数，
 * 并由 `viewmodel`/`native` 侧调用——`pages` 不得直接读写存储（架构不变量 §1）。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DEFAULT_THEME_MODE, ThemeMode, parseThemeMode } from '../common/theme';
import { Logger } from '../common/logger';

const TAG: string = 'preferenceStore';

/** 首选项文件名。应用内唯一，避免与其他偏好混在一起 */
const STORE_NAME: string = 'learnx_settings';

/** 主题模式的键名。**改动会丢已存偏好**，改名须同时迁移 */
const KEY_THEME_MODE: string = 'theme_mode';

/** 当前学期的键名。值为学期 id（形如 `2024-2025-1`）；空串表示"还没定过" */
const KEY_CURRENT_SEMESTER: string = 'current_semester';

/** 下载目标目录的键名。缺省/`false` = 缓存目录，`true` = 应用文件目录（FR-10） */
const KEY_USE_DOCUMENT_DIR: string = 'use_document_dir';

/** 下载文件名是否省略课程名前缀的键名。缺省/`false` = 带课程名前缀（FR-16） */
const KEY_OMIT_COURSE_NAME: string = 'omit_course_name';

/** 自定义下载目录（用户选定的外部目录 URI）；空串 = 未设置（用应用内目录） */
const KEY_CUSTOM_DIR: string = 'custom_download_dir';

/**
 * 打开偏好存储。
 *
 * **一律经 `getApplicationContext()`**（2026-09-28 真机实测的硬规则）：
 * 用页面宿主上下文（`UIAbilityContext`）打开偏好会在 `<base>/haps/entry/preferences/`
 * 下**另起一份**，与 `ApplicationContext` 那份（`<base>/preferences/`）互不可见——
 * 实测：设置页（应用级上下文）写下了"省略课程名前缀"，而文件下载（当时拿到的是宿主上下文）
 * 读的是另一份、读到默认值 false，于是**设置"点了没反应"**。
 *
 * 收在这一处，任何调用方传进来的是哪种上下文都会落到同一份。文件下载需要宿主上下文
 * 只是为了 `startAbility` 打开文件，不该让它顺带把偏好也换个地方读。
 */
function openStore(context: common.Context): preferences.Preferences {
  return preferences.getPreferencesSync(context.getApplicationContext(), { name: STORE_NAME });
}

/**
 * 读取主题模式。
 *
 * 值非法（含从未写入、被外部改写）时退让为默认模式——退让规则本身在
 * `common/theme.ets` 里，是纯逻辑、已被单测覆盖；这里只负责把字符串取出来。
 * 存储打不开时同样退让，并记 WARN：外观偏好不值得让启动失败。
 */
export function readThemeMode(context: common.Context): ThemeMode {
  try {
    const raw: string = openStore(context).getSync(KEY_THEME_MODE, DEFAULT_THEME_MODE) as string;
    return parseThemeMode(raw);
  } catch (err) {
    Logger.warn(TAG, `读取主题模式失败，退让为默认值 code=${(err as BusinessError).code}`);
    return DEFAULT_THEME_MODE;
  }
}

/**
 * 写入主题模式。
 *
 * 返回是否成功：写失败要能被上层感知——静默丢掉用户的选择、下次启动又弹回旧值，
 * 是最难排查的一类问题。故这里不吞异常，而是把它变成明确的返回值。
 */
export function writeThemeMode(context: common.Context, mode: ThemeMode): boolean {
  try {
    const store: preferences.Preferences = openStore(context);
    store.putSync(KEY_THEME_MODE, mode);
    store.flushSync();
    return true;
  } catch (err) {
    Logger.warn(TAG, `写入主题模式失败 mode=${mode} code=${(err as BusinessError).code}`);
    return false;
  }
}

/**
 * 读取当前学期 id。
 *
 * 空串表示"还没定过"（首次运行或存储被清），由上层据此决定是否采用服务端的当前学期。
 * 存储打不开、或存进去的类型不是字符串时同样退让为空串并记 WARN——学期缺失只会让
 * 下游不发请求，不该让应用起不来。
 */
export function readCurrentSemester(context: common.Context): string {
  try {
    const raw: Object = openStore(context).getSync(KEY_CURRENT_SEMESTER, '');
    return typeof raw === 'string' ? raw : '';
  } catch (err) {
    Logger.warn(TAG, `读取当前学期失败，视为未设置 code=${(err as BusinessError).code}`);
    return '';
  }
}

/** 写入当前学期 id。返回是否成功（写失败要能被上层感知，语义同 writeThemeMode） */
export function writeCurrentSemester(context: common.Context, semesterId: string): boolean {
  try {
    const store: preferences.Preferences = openStore(context);
    store.putSync(KEY_CURRENT_SEMESTER, semesterId);
    store.flushSync();
    return true;
  } catch (err) {
    Logger.warn(TAG, `写入当前学期失败 code=${(err as BusinessError).code}`);
    return false;
  }
}

/**
 * 读取"下载是否落到应用文件目录"。
 *
 * 默认 **false**（缓存目录）——FR-08 交付的行为就是缓存目录，改默认值会让用户已下的文件
 * 突然"找不到"（downloads spec §2 第 2 条）。非布尔值同样退让为默认值。
 */
export function readUseDocumentDir(context: common.Context): boolean {
  try {
    const raw: Object = openStore(context).getSync(KEY_USE_DOCUMENT_DIR, false);
    return typeof raw === 'boolean' ? raw : false;
  } catch (err) {
    Logger.warn(TAG, `读取下载目录偏好失败，退让为缓存目录 code=${(err as BusinessError).code}`);
    return false;
  }
}

/** 写入"下载是否落到应用文件目录"。返回是否成功（语义同 writeThemeMode） */
export function writeUseDocumentDir(context: common.Context, useDocumentDir: boolean): boolean {
  try {
    const store: preferences.Preferences = openStore(context);
    store.putSync(KEY_USE_DOCUMENT_DIR, useDocumentDir);
    store.flushSync();
    return true;
  } catch (err) {
    Logger.warn(TAG, `写入下载目录偏好失败 code=${(err as BusinessError).code}`);
    return false;
  }
}

/**
 * 读取"下载文件名是否省略课程名前缀"。
 *
 * 默认 **false**（带课程名前缀）——与上游默认值一致，也是 FR-08 交付时的行为。
 */
export function readOmitCourseName(context: common.Context): boolean {
  try {
    const raw: Object = openStore(context).getSync(KEY_OMIT_COURSE_NAME, false);
    return typeof raw === 'boolean' ? raw : false;
  } catch (err) {
    Logger.warn(TAG, `读取文件名偏好失败，退让为带课程名前缀 code=${(err as BusinessError).code}`);
    return false;
  }
}

/** 写入"下载文件名是否省略课程名前缀"。返回是否成功（语义同 writeThemeMode） */
export function writeOmitCourseName(context: common.Context, omitCourseName: boolean): boolean {
  try {
    const store: preferences.Preferences = openStore(context);
    store.putSync(KEY_OMIT_COURSE_NAME, omitCourseName);
    store.flushSync();
    return true;
  } catch (err) {
    Logger.warn(TAG, `写入文件名偏好失败 code=${(err as BusinessError).code}`);
    return false;
  }
}

/**
 * 读取用户选定的**自定义下载目录**（外部目录 URI）。
 *
 * 空串表示未设置——此时仍用应用沙箱内的目录（缓存 / 应用文件目录，见 FR-10）。
 * 该 URI 是用户通过系统目录选择器授权的，授权已持久化（见 `native/filePickerAdapter`）。
 */
export function readCustomDownloadDir(context: common.Context): string {
  try {
    const raw: Object = openStore(context).getSync(KEY_CUSTOM_DIR, '');
    return typeof raw === 'string' ? raw : '';
  } catch (err) {
    Logger.warn(TAG, `读取自定义下载目录失败 code=${(err as BusinessError).code}`);
    return '';
  }
}

/** 写入自定义下载目录？返回是否成功（语义同 writeThemeMode） */
export function writeCustomDownloadDir(context: common.Context, uri: string): boolean {
  try {
    const store: preferences.Preferences = openStore(context);
    store.putSync(KEY_CUSTOM_DIR, uri);
    store.flushSync();
    return true;
  } catch (err) {
    Logger.warn(TAG, `写入自定义下载目录失败 code=${(err as BusinessError).code}`);
    return false;
  }
}
