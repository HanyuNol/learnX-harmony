/**
 * 文件系统与"打开文件"的适配：系统能力的**唯一出口**（架构不变量 §3）。
 *
 * 只封装系统调用，**不做业务判断**（哪些算失败、要不要重试，由 `repository` 归类和决定）。
 * 每个函数把系统异常原样抛出或转换成可读错误，不吞掉。
 *
 * 目录约定：应用沙箱缓存目录下的 `learnX-files/`（见 files spec §3.3 第 2 条）。
 * 用缓存目录而不是文档目录：这些是**可重新下载的副本**，系统在空间紧张时回收它们是对的；
 * "下载到哪里由用户指定"属 FR-10。
 */

import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common, wantConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 沙箱内放下载文件的目录名 */
const FILES_DIR_NAME: string = 'learnX-files';

/** 打开文件用的意图（系统据此挑查看器） */
const ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';

/**
 * 下载文件的根目录。
 *
 * `useDocumentDir` 为真用**应用文件目录**（随应用数据保留），否则用**缓存目录**
 * （系统空间紧张时可回收）。默认缓存目录与 FR-08 的行为一致（见 downloads spec §2 第 2 条）。
 */
export function filesRoot(context: common.Context, useDocumentDir: boolean): string {
  return useDocumentDir ? `${context.filesDir}/${FILES_DIR_NAME}` : `${context.cacheDir}/${FILES_DIR_NAME}`;
}

/** 创建并返回下载根目录 */
export function ensureFilesRoot(context: common.Context, useDocumentDir: boolean): string {
  const root: string = filesRoot(context, useDocumentDir);
  ensureDir(root);
  return root;
}

/**
 * 两个可能的下载根目录（缓存在前）。
 *
 * "这个文件下载过没有"必须**两个目录都看**：用户切换过目标目录后，旧文件仍在原处，
 * 只看新目录会让详情页显示"未下载"，而文件其实还在（downloads spec §3.3 第 5 条）。
 * 这里只算路径、不创建目录。
 */
export function filesRoots(context: common.Context): string[] {
  return [filesRoot(context, false), filesRoot(context, true)];
}

/** 递归创建目录（已存在不报错） */
export function ensureDir(path: string): void {
  try {
    if (fs.accessSync(path)) {
      return;
    }
  } catch (err) {
    // 不存在会抛异常，落到创建
  }
  fs.mkdirSync(path, true);
}

/** 文件是否已存在 */
export function fileExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (err) {
    return false;
  }
}

/**
 * 把字节写入文件（覆盖写）。
 *
 * 覆盖而不是追加：半截文件重下时必须从头写，否则会拼出一份损坏的文件。
 */
export function writeBytes(path: string, data: ArrayBuffer): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, data);
  } finally {
    fs.closeSync(file);
  }
}

/** 删除文件；不存在不报错（清理半截文件用） */
export function removeFile(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (err) {
    // 已经不在就算了——清理不是关键路径
  }
}

/**
 * 把字节的前若干字节按 UTF-8 解成文本。
 *
 * 给调用方做**内容嗅探**用的原语（例如识别服务端返回的跳转桩页面），
 * 判断本身留在 `repository`。
 */
export function decodePrefix(data: ArrayBuffer, maxBytes: number): string {
  const length: number = Math.min(maxBytes, data.byteLength);
  if (length <= 0) {
    return '';
  }
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(new Uint8Array(data, 0, length));
}

/**
 * 用系统查看器打开沙箱里的文件。
 *
 * `type` 是 MIME（由扩展名推断），`FLAG_AUTH_READ_URI_PERMISSION` 把读权限临时授予
 * 查看器——不给这个标志，外部应用读不到应用沙箱里的文件。
 *
 * 失败（设备上没有能处理该类型的应用）会抛出，由调用方给用户可见反馈。
 */
export async function openFile(context: common.UIAbilityContext, path: string, mime: string): Promise<void> {
  const uri: string = fileUri.getUriFromPath(path);
  const want: Want = {
    action: ACTION_VIEW_DATA,
    uri: uri,
    type: mime,
    flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
  };
  await context.startAbility(want);
}

/**
 * 把系统异常收敛成一句可读描述（**只进日志**，不呈现给用户）。
 *
 * 打开文件失败时最需要知道的就是错误码：它区分"设备上没有能处理该类型的应用"
 * （`16000001` 类）与"意图本身不合法"（我们自己写错了）——没有码就只能靠猜。
 */
export function describeError(err: Object): string {
  const error: BusinessError = err as BusinessError;
  return `code=${error.code} message=${error.message}`;
}

/**
 * 沙箱绝对路径 → **交给系统查看器**的 `file://` URI（形如 `file://<包名>/data/...`）。
 *
 * 与 `previewUrlOf` 是**两个不同的东西**，别混用：
 * - 系统查看器要 `getUriFromPath` 那个带包名的形态；
 * - ArkWeb 要 `file://` + 绝对路径，喂它带包名的形态会被拒绝
 *   （2026-09-28 实测：`IsUrlFileExist failed` / `invalidFileUrl`）。
 */
export function fileUriOf(path: string): string {
  return fileUri.getUriFromPath(path);
}

/**
 * 沙箱绝对路径 → **应用内预览（ArkWeb）**的 URL：`file://` + 绝对路径。
 *
 * 两个实测坑（2026-09-28，缺一不可）：
 * 1. 形态必须是 `file://` + 绝对路径（`file:///data/storage/...`），**不能用**
 *    `getUriFromPath` 那个 `file://<包名>/...`——ArkWeb 会报 `invalidFileUrl`；
 * 2. Web 组件必须显式 `.fileAccess(true)`：API 12 起该能力**默认关闭**，关闭时不认本地文件。
 */
export function previewUrlOf(path: string): string {
  return `file://${path}`;
}

/** 读取沙箱文件的全部字节（另存为要把它交给系统保存对话框） */
export function readAllBytes(path: string): ArrayBuffer {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size: number = fs.statSync(file.fd).size;
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    fs.readSync(file.fd, buffer);
    return buffer;
  } finally {
    fs.closeSync(file);
  }
}
