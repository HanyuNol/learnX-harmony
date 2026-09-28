/**
 * 文件选择与目录选择的适配：系统能力的**唯一出口**（架构不变量 §3）。
 *
 * 两件事：
 * - `pickFile()`：让用户从设备上选一个文件（作业提交要上传附件）；
 * - `pickFolder()`：让用户选一个目录（下载位置自定义），并**持久化访问授权**——
 *   否则重启后拿到的 URI 会因授权失效而写不进去。
 *
 * 返回 `null` 表示用户取消了选择：**取消不是失败**，调用方按"什么都没发生"处理，
 * 不得弹错误（与登录页取消 SSO 同一口径）。
 */

import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { fileShare } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/logger';

const TAG: string = 'filePickerAdapter';

/** 用户选中的文件：名称 + 字节（字节在读入选完就取，避免 URI 授权过期后读不到） */
export class PickedFile {
  readonly name: string;
  readonly data: ArrayBuffer;

  constructor(name: string, data: ArrayBuffer) {
    this.name = name;
    this.data = data;
  }
}

/** 从 URI 里取文件名（末段；去掉查询串） */
function nameOfUri(uri: string): string {
  const cut: number = uri.indexOf('?');
  const clean: string = cut >= 0 ? uri.substring(0, cut) : uri;
  const slash: number = clean.lastIndexOf('/');
  const name: string = slash >= 0 ? clean.substring(slash + 1) : clean;
  return name.length > 0 ? decodeURIComponent(name) : 'file';
}

/** 读取一个 URI 的全部字节 */
function readAll(uri: string): ArrayBuffer {
  const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const size: number = fs.statSync(file.fd).size;
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    fs.readSync(file.fd, buffer);
    return buffer;
  } finally {
    fs.closeSync(file);
  }
}

/**
 * 让用户选一个文件并读回字节。
 *
 * 读字节放在这里而不是"只回 URI"：选择器给的授权是**临时**的，
 * 立刻读走最稳；上传时要的也是字节。
 */
export async function pickFile(context: common.UIAbilityContext): Promise<PickedFile | null> {
  const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  let uris: string[] = [];
  try {
    // **必须传 UIAbilityContext**：SDK 文档写明无参构造"not recommended due to the potential
    // risk of operation failure"，且带参构造只接受 UIAbilityContext。实测无参构造在设备上
    // **静默失败**（选择器进程起来又立刻退出，既没有返回值也没有异常），见 OPERATIONS §7.7
    Logger.info(TAG, '打开文件选择器');
    uris = await new picker.DocumentViewPicker(context).select(options);
  } catch (err) {
    // 取消会走到这里（错误码 13900020 一类），不是失败
    Logger.info(TAG, `选择文件未完成 ${(err as BusinessError).code}`);
    return null;
  }
  if (uris.length === 0) {
    return null;
  }
  const uri: string = uris[0];
  try {
    const data: ArrayBuffer = readAll(uri);
    Logger.info(TAG, `已选文件 字节=${data.byteLength}`);
    return new PickedFile(nameOfUri(uri), data);
  } catch (err) {
    Logger.warn(TAG, `读取所选文件失败 code=${(err as BusinessError).code}`);
    throw new Error('读取所选文件失败');
  }
}

/** 用户选中的目录：URI（用于拼子文件路径） */
export async function pickFolder(context: common.UIAbilityContext): Promise<string | null> {
  const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  // 注意：`selectMode = FOLDER` **只支持二合一设备**（系统文档原文），手机上传这个参数无效、
  // 会退化成"选文件"。故调用方必须先看 `deviceAdapter.supportsFolderSelection()`；
  // 这里仍再校验一次返回值**真的是目录**，避免把"选中的文件"当目录用
  options.selectMode = picker.DocumentSelectMode.FOLDER;
  let uris: string[] = [];
  try {
    Logger.info(TAG, '打开目录选择器');
    uris = await new picker.DocumentViewPicker(context).select(options);
  } catch (err) {
    Logger.info(TAG, `选择目录未完成 ${(err as BusinessError).code}`);
    return null;
  }
  if (uris.length === 0) {
    return null;
  }
  const uri: string = uris[0];
  if (!isDirectory(uri)) {
    // 设备不支持选目录时，选择器会当成选文件返回——此时**必须报错**，
    // 否则会把它当目录用，下载全落不进去（用户看到的是"设置了没反应"）
    Logger.warn(TAG, '所选内容不是目录（本设备可能不支持选择文件夹）');
    throw new Error('所选内容不是目录');
  }
  // 持久化授权：不申请就会在应用重启后失效，表现为"设置过的目录突然写不进去"
  try {
    await fileShare.persistPermission([{
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
    }]);
    Logger.info(TAG, '目录授权已持久化');
  } catch (err) {
    // 授权持久化失败不阻断本次选择（当次仍可用），但要让上层知道"可能只这一会儿有效"
    Logger.warn(TAG, `目录授权持久化失败 code=${(err as BusinessError).code}`);
    throw new Error('目录授权未能持久化');
  }
  return uri;
}

/** 往"已授权的目录 URI"里写一个文件（同名覆盖） */
export function writeIntoFolder(folderUri: string, fileName: string, data: ArrayBuffer): void {
  const target: string = `${folderUri}/${encodeURIComponent(fileName)}`;
  const file: fs.File = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, data);
  } finally {
    fs.closeSync(file);
  }
}

/** 删除外部 URI 处的文件（清理半截文件用；失败不抛——清理不是关键路径） */
export function removeAtUri(uri: string): void {
  try {
    fs.unlinkSync(uri);
  } catch (err) {
    Logger.warn(TAG, `删除外部文件失败 code=${(err as BusinessError).code}`);
  }
}

/** 该 URI 是否为目录（探测失败按"不是目录"处理，宁可拒绝也不误用） */
function isDirectory(uri: string): boolean {
  try {
    return fs.statSync(uri).isDirectory();
  } catch (err) {
    Logger.warn(TAG, `判断是否为目录失败 code=${(err as BusinessError).code}`);
    return false;
  }
}

/**
 * **另存为**：让用户挑一个位置与文件名保存这份字节。
 *
 * 这是**手机上唯一可用的"我自己选保存位置"方式**——手机不支持选文件夹（见 `pickFolder`），
 * 但 `save()` 是逐次选择目标位置的，手机上完全可用。
 * 返回是否真的保存了（用户取消返回 false，**取消不是失败**）。
 */
export async function saveAs(suggestedName: string, data: ArrayBuffer,
                             context: common.UIAbilityContext): Promise<boolean> {
  const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = [suggestedName];
  let uris: string[] = [];
  try {
    uris = await new picker.DocumentViewPicker(context).save(options);
  } catch (err) {
    Logger.info(TAG, `另存为未完成 ${(err as BusinessError).code}`);
    return false;
  }
  if (uris.length === 0) {
    return false;
  }
  const target: string = uris[0];
  try {
    const file: fs.File = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, data);
    } finally {
      fs.closeSync(file);
    }
    Logger.info(TAG, `另存为完成 字节=${data.byteLength}`);
    return true;
  } catch (err) {
    Logger.warn(TAG, `另存为写入失败 code=${(err as BusinessError).code}`);
    throw new Error('另存为写入失败');
  }
}

/** 外部 URI 处是否已有文件（权限失效或不存在都返回 false——宁可按"没有"处理） */
export function existsAt(uri: string): boolean {
  try {
    return fs.accessSync(uri);
  } catch (err) {
    return false;
  }
}
