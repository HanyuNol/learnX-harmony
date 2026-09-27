/**
 * 上下文适配：把 ArkUI 给页面的**宿主上下文**（UIAbilityContext）转成应用级上下文。
 *
 * 为什么需要它、且需要集中一处：2026-09-27 真机实测——用页面 `getUIContext().getHostContext()`
 * 拿到的 UIAbilityContext 去**写偏好**，表现为"写入成功、重启后读不回来"
 * （设置页写 `FOLLOW_SYSTEM` → force-stop 重启 → 读到旧值 `DARK`），而启动路径用
 * `ApplicationContext` 写的值能持久化。规则因此是：**应用级偏好一律走 ApplicationContext**
 * （见 `OPERATIONS.md` §7.5）。
 *
 * 收成一个函数而不是每页各写一次 `getApplicationContext()`：这条规则连带原因只留一处，
 * 新页面照用即可，不会各自踩一遍。
 */

import { common } from '@kit.AbilityKit';

/**
 * 取应用级上下文。
 *
 * `host` 来自 `this.getUIContext().getHostContext()`——取它属 ArkUI 的 UI 能力
 * （与 `SsoLogin` 读注入脚本同一做法），不是"页面直连系统 Kit"。
 */
export function applicationContextOf(host: common.Context): common.ApplicationContext {
  return host.getApplicationContext();
}
