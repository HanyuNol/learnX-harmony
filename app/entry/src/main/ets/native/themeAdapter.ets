/**
 * 主题应用：`ApplicationContext.setColorMode` 的**唯一出口**（架构不变量 §3）。
 *
 * 为什么要有这一层：`setColorMode` 是系统能力调用，而 `pages` 不得直接调用系统能力
 * （架构不变量 §1）。页面只改偏好，由本适配器把偏好落到系统——
 * 启动路径（`EntryAbility`）与设置页共用同一个入口，不会两处各写一遍。
 *
 * 与 `common/theme.ets` 的分工：那里只做"存储值 ⇄ 模式 ⇄ ColorMode"的纯映射（可单测），
 * 真正触碰系统能力的是这里。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemeMode, themeModeToColorMode } from '../common/theme';
import { Logger } from '../common/logger';

const TAG: string = 'themeAdapter';

/**
 * 把主题模式应用到系统。
 *
 * 失败**不向上抛**：主题是外观偏好，取不到就退回系统默认深浅，
 * 不应因为设置颜色失败而拦住启动或让用户的操作失败。
 *
 * **但必须如实把结果返回给调用方**：写偏好成功不等于主题已生效。设置页（T6）
 * 要据此区分"已保存但未应用"并提示用户，不能只看 `writeThemeMode` 的返回值
 * （代码审查 R-09）。启动路径可以忽略返回值——那时没有可告知的对象。
 */
export function applyThemeMode(applicationContext: common.ApplicationContext, mode: ThemeMode): boolean {
  try {
    applicationContext.setColorMode(themeModeToColorMode(mode));
    Logger.info(TAG, `已应用主题模式 mode=${mode}`);
    return true;
  } catch (err) {
    Logger.warn(TAG, `应用主题模式失败 mode=${mode} code=${(err as BusinessError).code}`);
    return false;
  }
}
