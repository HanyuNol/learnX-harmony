/**
 * 语言适配：给"服务端要语言参数"的接口提供 `zh` / `en`。
 *
 * 为什么要它：课程列表（以及将来的其他内容接口）的路径里带语言参数，它决定服务端
 * 返回哪个语言的课程名。这个不只是 UI 文案的事——**英文界面下看到中文课程名也是 i18n 缺陷**。
 * 上游取应用语言后传给接口（`thu-learn-lib/src/index.ts:256,355`），取值域只有 `zh`/`en`
 * （`types.ts:424-427`，默认 `zh`）。
 *
 * 放在 `native` 的理由同其他适配器：这里才有系统能力调用；`network` 只接收 `lang` 参数，
 * 由 `repository` 传下去，避免网络层反向依赖系统能力。
 */

import { i18n } from '@kit.LocalizationKit';
import { Logger } from '../common/logger';

const TAG: string = 'localeAdapter';

/** 服务端接受的语言取值（对齐上游 `Language` 枚举） */
const LANG_ZH: string = 'zh';
const LANG_EN: string = 'en';

/**
 * 当前应用语言对应的接口语言参数。
 *
 * 取不到系统语言时退回 `zh`——那是上游的默认值，且本应用的主要使用场景是中文界面；
 * 退让而不是抛错：语言取值不该让课程列表加载失败。
 */
export function serverLang(): string {
  try {
    const language: string = i18n.System.getSystemLanguage();
    return language.startsWith('zh') ? LANG_ZH : LANG_EN;
  } catch (err) {
    Logger.warn(TAG, `取系统语言失败，按默认值 ${LANG_ZH} 处理`);
    return LANG_ZH;
  }
}
