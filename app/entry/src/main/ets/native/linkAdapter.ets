/**
 * 打开外部链接：`startAbility(ACTION_VIEW_DATA)` 的**唯一出口**（架构不变量 §3）。
 *
 * 用途单一：正文渲染里用户点了 `http(s)` 链接时，**不在正文那小块 Web 里导航**
 * （那样会失去返回路径、也把正文页变成浏览器），而是交给系统浏览器打开。
 *
 * 只做"把 URL 交给系统"，**不做协议白名单**——那是调用方（渲染层）的判断；
 * 本层只负责调用与失败语义（失败原样抛出，由调用方决定是否提示）。
 */

import { common, Want } from '@kit.AbilityKit';

/** 交给系统打开一个 http(s) 链接 */
export async function openExternalUrl(context: common.UIAbilityContext, url: string): Promise<void> {
  const want: Want = {
    action: 'ohos.want.action.viewData',
    entities: ['entity.system.browsable'],
    uri: url
  };
  await context.startAbility(want);
}
