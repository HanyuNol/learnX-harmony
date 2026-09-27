/**
 * Toast：轻量反馈的**唯一出口**。
 *
 * 为什么收一处：Toast 是"操作成功/失败但不打断流程"的反馈（如"已复制"），
 * 散着调用会各写一套时长与样式。这里只封装 ArkUI 的 `promptAction`，
 * 不含业务判断。
 *
 * 关于分层：`promptAction` 是 ArkUI 的 UI 能力（不是设备/存储类系统 Kit），
 * 故放在 `components` 而不是 `native`；`pages` 也不再各处直接调它。
 */

import { promptAction } from '@kit.ArkUI';

/** Toast 展示时长（毫秒）。短到不挡操作，长到能读完一句中文 */
const TOAST_DURATION: number = 2000;

/**
 * 弹一条短提示。
 *
 * `message` 只接受**资源或字符串**，不接受拼好的用户文案——调用方若需要
 * 动态内容，用的是文案键而不是中文拼接（NFR-I18N）。
 */
export function showToast(message: ResourceStr): void {
  promptAction.showToast({
    message: message,
    duration: TOAST_DURATION
  });
}
