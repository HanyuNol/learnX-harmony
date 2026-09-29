/**
 * 变更日志（`CHANGELOG.md`）的读取：**打包资源**里那一份。
 *
 * 为什么是打进来的副本而不是联网取：应用要能**离线**看到"这个版本改了什么"，
 * 而仓库地址对匿名用户不可见（private），联网取 changelog 根本取不到。
 * 副本由 `scripts/sync-changelog.mjs` 从仓库根同步到 `resources/rawfile/`，**发版前必跑**
 * （与 `sync-version.mjs` 同一性质；漏跑只表现为"日志少了一段"，不会让应用出错）。
 *
 * 读不到（漏打包、文件名写错）**返回空串**，不抛——调用方据此显示空态。
 * 这是"关于"类信息的常见兜底：读不到日志不该让页面打不开。
 */

import { common } from '@kit.AbilityKit';
import { readRawFileText } from './resourceAdapter';
import { Logger } from '../common/logger';

const TAG: string = 'changelog';

/** 打包进 rawfile 的变更日志文件名 */
const CHANGELOG_RAWFILE: string = 'CHANGELOG.md';

/** 读入变更日志的 Markdown 源码；读不到返回空串 */
export function readChangelogSource(context: common.Context): string {
  try {
    return readRawFileText(context, CHANGELOG_RAWFILE);
  } catch (err) {
    Logger.warn(TAG, `变更日志资源读取失败：${(err as Error).message}`);
    return '';
  }
}
