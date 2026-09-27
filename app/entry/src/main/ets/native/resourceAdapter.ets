/**
 * 应用资源读取：资源访问的**唯一出口**（架构不变量 §3）。
 *
 * 目前只有一个用途：把注入脚本模板（`resources/rawfile/sso_inject.js`）读成字符串。
 * 之所以不让页面自己去碰 `resourceManager`：`pages` 不得直接调用系统能力，
 * 而且"模板从哪来"将来可能变成别的位置（如随包配置），收敛在一处更好改。
 */

import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';

/**
 * 读取 rawfile 文本。文件不存在或读取失败时抛错——调用方应据此判定为
 * "应用自身资源缺失"（构建缺陷），而不是用户可修复的问题。
 */
export function readRawFileText(context: common.Context, path: string): string {
  const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(path);
  return buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('utf-8');
}
