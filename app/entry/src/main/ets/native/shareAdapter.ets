/**
 * 系统分享的适配：**Share Kit 的唯一出口**（架构不变量 §3）。
 *
 * 只封装系统调用，**不做业务判断**（"该不该分享、失败了怎么提示"由 `repository` 与页面决定）。
 *
 * 两处平台口径（与日历同源）：
 * - **必须用 `UIAbilityContext`**：分享面板是 ability 级 UI，`ApplicationContext` 起不来；
 * - **`uri` 用"应用沙箱文件 URI"**（`fileUri.getUriFromPath`，形如 `file://<包名>/data/...`）：
 *   系统据此给目标应用**临时读授权**。它不是 `native/fileAdapter.previewUrlOf` 那个
 *   供 ArkWeb 用的 `file://` + 绝对路径形态（那个喂给分享面板是读不到的）。
 *
 * 不订阅 `shareCompleted`：用户分享到哪儿、成没成，是系统 UI 与用户之间的事（见 share spec §2）。
 */

import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { isFileUri } from '../model/file';
import { utdOfExtension } from '../common/fileUtd';

/**
 * 把一个文件交给系统分享面板。
 *
 * `extension` 是用于**描述类型**的扩展名（不带点），由 `common/fileUtd` 映射成 UTD；
 * 认不出来会退让成 `general.file`，不会因此失败。
 *
 * 失败原样抛出（`1003702001 记录类型不支持` / `1003702002 IPC 数据过大` / 系统无分享面板），
 * 由调用方归类与提示。
 */
export async function shareFile(context: common.UIAbilityContext, pathOrUri: string,
                                title: string, extension: string): Promise<void> {
  // 与 `fileAdapter.openFile` 同一口径：沙箱绝对路径要包成 URI，已经是 URI 的（自定义
  // 下载目录那种）再包一次会得到非法 URI
  const uri: string = isFileUri(pathOrUri) ? pathOrUri : fileUri.getUriFromPath(pathOrUri);
  const record: systemShare.SharedRecord = {
    utd: utdOfExtension(extension),
    uri: uri,
    title: title
  };
  const data: systemShare.SharedData = new systemShare.SharedData(record);
  const controller: systemShare.ShareController = new systemShare.ShareController(data);
  // 单选模式：本应用每次只分享一个文件，多选模式只支持批量文件记录（官方错误码 1003702001）
  await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE });
}
