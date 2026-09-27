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

function openStore(context: common.Context): preferences.Preferences {
  return preferences.getPreferencesSync(context, { name: STORE_NAME });
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
