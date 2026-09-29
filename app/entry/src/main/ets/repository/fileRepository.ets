/**
 * 文件：按课程扇出的编排 + 下载编排。
 *
 * 扇出部分与前三个维度同构：分块并发（每块 ≤ `FANOUT_LIMIT` 门课），单门课失败不让整体失败，
 * **全部失败则抛出**（由上层显示错误态 + 重试）——通知那次实测踩到"全失败静默成空态"。
 *
 * 下载部分把"取字节（网络）"与"落盘（系统能力）"编排在一起，并做**失败清理**：
 * 半截文件与"服务端跳转桩"都必须删掉，否则用户会打开一个 0 字节或 HTML 的假课件
 * （files spec §3.3 第 4 条）。
 */

import { Course } from '../model/course';
import { FANOUT_LIMIT, chunksOf } from '../common/fanout';
import {
  LearnFile, basenameOf, canReuseExisting, downloadFileName, sanitizePathSegment, sortFiles
} from '../model/file';
import { mimeOfExtension } from '../common/mime';
import { LearnClient } from '../network/learnClient';
import {
  ensureDir, ensureFilesRoot, filesRoot, filesRoots, fileExists, sizeOf, writeBytes, readAllBytes,
  removeFile, decodePrefix, openFile, describeError
} from '../native/fileAdapter';
import { existsAt, removeAtUri, saveAs, sizeAtUri, writeIntoFolder } from '../native/filePickerAdapter';
import { readCustomDownloadDir, readOmitCourseName, readUseDocumentDir } from '../storage/preferenceStore';
import { shareFile } from '../native/shareAdapter';
import { previewUrlOf } from '../native/fileAdapter';
import { Logger } from '../common/logger';
import { apiChanged, authFailed, firstFailure, normalize } from '../common/errors';
import { AuthError } from '../model/auth';
import { common } from '@kit.AbilityKit';

const TAG: string = 'fileRepository';

/** `downloadVia` 的取字节来源标识（只影响日志与目录，不影响逻辑） */
const ATTACHMENT_KIND: string = '作业附件';

/** 同时在飞的课程数上限（沿用通知那套工程判断） */

/** 内容嗅探的字节数：跳转桩是极小的 HTML，看开头这点就够 */
const SNIFF_BYTES: number = 512;

/** 跳转桩超过这个体量就不像桩页面了（正常课件不会这么小） */
const STUB_MAX_BYTES: number = 4096;

/** 服务端跳转桩的特征串 */
const REDIRECT_MARKER: string = 'location.href';

export class FileBatch {
  /** 已按上传时间倒序的文件 */
  readonly items: LearnFile[];
  /** 加载失败的课程数（0 表示全部成功） */
  readonly failedCourses: number;
  readonly totalCourses: number;

  constructor(items: LearnFile[], failedCourses: number, totalCourses: number) {
    this.items = items;
    this.failedCourses = failedCourses;
    this.totalCourses = totalCourses;
  }
}

/** 单门课的取数结果：`items` 为 null 表示失败 */
class CourseFileResult {
  readonly items: LearnFile[] | null;
  readonly course: Course;
  /** 失败原因（**已归一**，保住四分类）；成功时为 null */
  readonly failure: AuthError | null;

  constructor(items: LearnFile[] | null, course: Course, failure: AuthError | null) {
    this.items = items;
    this.course = course;
    this.failure = failure;
  }
}

export class FileRepository {
  /** 取全部课程的文件。全部失败时抛出，交给上层既有错误路径 */
  static async loadAll(courses: Course[]): Promise<FileBatch> {
    const collected: LearnFile[] = [];
    /** 各课**已归一**的失败原因（全失败时要抛它，见 common/errors.firstFailure 的说明） */
    const failures: AuthError[] = [];
    let failed: number = 0;

    for (const chunk of chunksOf(courses, FANOUT_LIMIT)) {
      const settled: Array<CourseFileResult> = await Promise.all(
        chunk.map((course: Course) => FileRepository.loadOneCourse(course)));
      for (const entry of settled) {
        if (entry.items === null) {
          failed++;
          if (entry.failure !== null) {
            failures.push(entry.failure);
          }
          continue;
        }
        for (const item of entry.items) {
          collected.push(item);
        }
      }
    }

    if (courses.length > 0 && failed === courses.length) {
      const first: AuthError = firstFailure(failures, '加载文件');
      Logger.warn(TAG, `全部 ${courses.length} 门课程的文件都加载失败，按错误态处理 reason=${first.reason}`);
      // **抛已归一的错误**（不抛裸 Error）：否则会被 normalize 归成"解析失败"，
      // 把"登录失效/断网"显示成"响应无法识别"（2026-09-28 审查 🔴）
      throw first;
    }

    const sorted: LearnFile[] = sortFiles(collected);
    Logger.info(TAG, `文件加载完成 课程数=${courses.length} 失败=${failed} 文件数=${sorted.length}`);
    return new FileBatch(sorted, failed, courses.length);
  }

  private static async loadOneCourse(course: Course): Promise<CourseFileResult> {
    try {
      const items: LearnFile[] = await LearnClient.getInstance()
        .fetchFilesOfCourse(course.id, course.displayName(), course.teacherName);
      return new CourseFileResult(items, course, null);
    } catch (err) {
      const error: AuthError = normalize(err, '加载课程文件');
      Logger.warn(TAG, `课程文件加载失败 course=${course.id} reason=${error.reason}`);
      return new CourseFileResult(null, course, error);
    }
  }

  /**
   * 下载一个文件到应用沙箱，返回沙箱内的绝对路径。
   *
   * 目标目录按偏好选择（缓存 / 应用文件目录，见 downloads spec §2）；
   * `forceRefresh` 为 false 且目标文件已存在时**直接复用**（不发起请求）。
   * `onProgress` 是"已收字节 / 总字节"，网络层原样转达——百分比由上层算（规则 2：
   * 进度只在网络层产生，页面不自估）。
   * 失败时抛错，且已写入的半截文件会被删除。
   */
  static async download(file: LearnFile, context: common.Context, forceRefresh: boolean,
                        onProgress?: (received: number, total: number) => void): Promise<string> {
    return FileRepository.downloadVia(file, context, forceRefresh, onProgress, '文件',
      FileRepository.relativeDirOf(file));
  }

  /**
   * 下载一个**作业附件**（教师附件 / 已提交附件 / 评分附件）。
   *
   * 与课件文件走**同一套**落盘、命名、缓存与校验逻辑，只有两处不同：
   * 取字节的端点不同（作业附件用的是 `…/kczy/zy/student/downloadFile/<课程>/<附件 id>`），
   * 目标目录多一层，避免与同名课件互相覆盖。
   */
  static async downloadAttachment(file: LearnFile, homeworkId: string, context: common.Context,
                                  forceRefresh: boolean,
                                  onProgress?: (received: number, total: number) => void): Promise<string> {
    return FileRepository.downloadVia(file, context, forceRefresh, onProgress, ATTACHMENT_KIND,
      FileRepository.attachmentDirOf(file.fileId, homeworkId, file.courseName));
  }

  /**
   * 下载的**通用核心**：落盘 → 复用判定 → 取字节 → 校验 → 写入。
   *
   * `kind` 只用于日志与目录分层（`附件/` 前缀），取字节由调用方给定的来源决定。
   */
  private static async downloadVia(file: LearnFile, context: common.Context, forceRefresh: boolean,
                                   onProgress: ((received: number, total: number) => void) | undefined,
                                   kind: string, relativeDir: string): Promise<string> {
    const customDir: string = readCustomDownloadDir(context);
    const fileName: string = downloadFileName(file.courseName, file.title, file.fileType,
      readOmitCourseName(context));
    let path: string = '';
    if (customDir.length > 0) {
      // 用户选了自定义目录：**平铺**放进去，不建子目录——外部目录不保证允许建目录，
      // 平铺也正是用户在"下载"里期待的样子
      path = `${customDir}/${encodeURIComponent(fileName)}`;
      // 平铺意味着路径里**没有文件 id**：同名不同文件会撞到同一路径，故复用前必须
      // 能证明"这就是同一份"（体积一致），否则重下覆盖（见 model/file.canReuseExisting 的说明）
      if (!forceRefresh && canReuseExisting(sizeAtUri(path), file.rawSize)) {
        Logger.info(TAG, `文件已在自定义目录且体积一致，直接复用 id=${file.id}`);
        return path;
      }
      if (!forceRefresh && existsAt(path)) {
        Logger.warn(TAG, `自定义目录已有同名文件但体积不符（文件 id=${file.id}），重下覆盖`);
      }
    } else {
      const root: string = ensureFilesRoot(context, readUseDocumentDir(context));
      const directory: string = `${root}/${relativeDir}`;
      ensureDir(directory);
      path = `${directory}/${fileName}`;
      // 沙箱路径含文件 id 目录，同名不会撞车，存在即可复用
      if (!forceRefresh && fileExists(path)) {
        Logger.info(TAG, `文件已在本地，直接复用 id=${file.id}`);
        return path;
      }
    }

    let data: ArrayBuffer;
    try {
      data = kind === ATTACHMENT_KIND
        ? await LearnClient.getInstance().downloadAssignmentAttachmentBytes(file.courseId, file.fileId, onProgress)
        : await LearnClient.getInstance().downloadFileBytes(file.fileId, onProgress);
    } catch (err) {
      // 带上失败原因：只说"下载失败"没法定位是会话、网络还是服务端语义问题
      Logger.warn(TAG, `${kind}下载失败 id=${file.id} fileId=${file.fileId} ${describeError(err)}`);
      throw normalize(err, `${kind}下载`);
    }
    if (data.byteLength <= 0) {
      FileRepository.removeAt(customDir, path);
      throw apiChanged('下载到的文件为空（服务端语义可能变更）');
    }
    if (FileRepository.looksLikeRedirectStub(data)) {
      FileRepository.removeAt(customDir, path);
      // 跳转桩页面是**会话失效**的典型表现，必须归为认证失败而不是"解析失败"——
      // 否则用户看到"响应无法识别"，不知道要重新登录（2026-09-28 审查 M1）
      throw authFailed('下载端点返回了跳转页面（会话可能已失效）');
    }

    try {
      if (customDir.length > 0) {
        // 外部目录用被授权 URI 写（`writeIntoFolder` 会拼子路径），不能走沙箱的 fs 路径写法
        writeIntoFolder(customDir, fileName, data);
      } else {
        writeBytes(path, data);
      }
    } catch (err) {
      // **写失败要清理**：留下的 0 字节/半截文件会被下次的"存在即复用"当成好东西
      // （2026-09-28 代码审查 🟡 M4）
      FileRepository.removeAt(customDir, path);
      Logger.warn(TAG, `写盘失败，已清理半截文件 id=${file.id} ${describeError(err)}`);
      throw normalize(err, '写入下载文件');
    }
    Logger.info(TAG, `${kind}已下载 id=${file.id} 字节=${data.byteLength} 路径长度=${path.length}`);
    return path;
  }

  /** 失败清理：沙箱文件直接删，外部 URI 交给适配器删 */
  private static removeAt(customDir: string, path: string): void {
    if (customDir.length > 0) {
      removeAtUri(path);
    } else {
      removeFile(path);
    }
  }

  /**
   * 该文件在**自定义目录**里的路径（未设置自定义目录返回空串）。
   *
   * **两种命名都看**（与沙箱侧一致）：用户切换过"省略课程名前缀"后，旧文件仍按旧命名存在，
   * 只看当前命名会误判成"未下载"（2026-09-28 代码审查 🟡 M10）。
   */
  static customPathOf(file: LearnFile, context: common.Context): string {
    const customDir: string = readCustomDownloadDir(context);
    if (customDir.length === 0) {
      return '';
    }
    for (const omit of [readOmitCourseName(context), !readOmitCourseName(context)]) {
      const name: string = downloadFileName(file.courseName, file.title, file.fileType, omit);
      const path: string = `${customDir}/${encodeURIComponent(name)}`;
      if (existsAt(path)) {
        return path;
      }
    }
    return '';
  }

  /** 沙箱里的文件路径（按**当前偏好**算，不下载；判定"已下载"用 `isDownloaded`） */
  static pathOf(file: LearnFile, context: common.Context): string {
    return FileRepository.pathIn(filesRoot(context, readUseDocumentDir(context)),
      FileRepository.relativeDirOf(file), file, readOmitCourseName(context));
  }

  /**
   * 该文件是否已经在沙箱里（"已下载"状态）。
   *
   * **两个目录 × 两种命名都看**：用户可能切换过目标目录（FR-10）或切换过"省略课程名前缀"
   * （FR-16），旧文件仍在原处；只看当前偏好会让详情页显示"未下载"而文件其实还在。
   */
  static isDownloaded(file: LearnFile, context: common.Context): boolean {
    return FileRepository.downloadedPathOf(file, context).length > 0
      || FileRepository.customPathOf(file, context).length > 0;
  }

  /** 已下载时的绝对路径（任一目录 + 任一种命名命中即可）；都没命中返回空串 */
  static downloadedPathOf(file: LearnFile, context: common.Context): string {
    return FileRepository.findExisting(file, context, FileRepository.relativeDirOf(file));
  }

  /** 作业附件是否已在该作业的附件目录下 */
  static isAttachmentDownloaded(file: LearnFile, homeworkId: string, context: common.Context): boolean {
    return FileRepository.downloadedAttachmentPathOf(file, homeworkId, context).length > 0;
  }

  /** 已下载附件的绝对路径 */
  static downloadedAttachmentPathOf(file: LearnFile, homeworkId: string,
                                    context: common.Context): string {
    return FileRepository.findExisting(file, context,
      FileRepository.attachmentDirOf(file.fileId, homeworkId, file.courseName));
  }

  /**
   * 在"两个根目录 × 两种命名"里找已存在的文件。
   *
   * 为什么都要看：用户可能切换过目标目录（FR-10）或"省略课程名前缀"（FR-16），
   * 旧文件仍在原处；只看当前偏好会让界面显示"未下载"而文件其实还在。
   */
  private static findExisting(file: LearnFile, context: common.Context, relativeDir: string): string {
    for (const root of filesRoots(context)) {
      for (const omit of [false, true]) {
        const path: string = FileRepository.pathIn(root, relativeDir, file, omit);
        if (fileExists(path)) {
          return path;
        }
      }
    }
    return '';
  }

  /**
   * 已下载文件的 `file://` URI（供应用内预览用）；未下载时返回空串。
   *
   * 放这里而不是页面里：`fileUri` 是系统能力，`pages` 不得直接用（架构不变量 §1）。
   */
  static previewUriOf(file: LearnFile, context: common.Context): string {
    // 只对**沙箱内**的文件做应用内预览：外部目录（自定义下载目录）拿到的是文档 URI，
    // ArkWeb 吃不了它，这类文件交给系统应用打开才对
    const path: string = FileRepository.downloadedPathOf(file, context);
    return path.length > 0 ? previewUrlOf(path) : '';
  }

  /** 已下载文件的位置（沙箱优先，其次自定义目录）；都没命中返回空串 */
  static anyDownloadedPathOf(file: LearnFile, context: common.Context): string {
    const inSandbox: string = FileRepository.downloadedPathOf(file, context);
    return inSandbox.length > 0 ? inSandbox : FileRepository.customPathOf(file, context);
  }

  /**
   * **另存为**：让用户挑一个位置保存这份文件（手机上唯一能自选位置的方式）。
   *
   * 先确保文件在沙箱（已下过则复用），再把字节交给系统保存对话框；返回用户是否真的保存了
   * （取消返回 false，**不是失败**）。
   */
  static async saveAsTo(file: LearnFile, context: common.UIAbilityContext): Promise<boolean> {
    const existing: string = FileRepository.downloadedPathOf(file, context);
    const path: string = existing.length > 0 ? existing
      : await FileRepository.download(file, context, false);
    const data: ArrayBuffer = readAllBytes(path);
    const name: string = downloadFileName(file.courseName, file.title, file.fileType,
      readOmitCourseName(context));
    return saveAs(name, data, context);
  }

  /** 把沙箱路径变成应用内预览 URL（供附件走同一条预览路径） */
  static previewUrlOfPath(path: string): string {
    return previewUrlOf(path);
  }

  /** 把沙箱路径交给系统应用打开（错误由调用方归类；失败明细在这里记） */
  static async openPath(path: string, mime: string, context: common.UIAbilityContext): Promise<void> {
    try {
      await openFile(context, path, mime);
    } catch (err) {
      Logger.warn(TAG, `打开文件失败 路径长度=${path.length} ${describeError(err)}`);
      throw normalize(err, '打开文件');
    }
  }

  private static pathIn(root: string, relativeDir: string, file: LearnFile,
                        omitCourseName: boolean): string {
    return `${root}/${relativeDir}`
      + `/${downloadFileName(file.courseName, file.title, file.fileType, omitCourseName)}`;
  }

  /** 该文件对应的 MIME（交给系统查看器用） */
  static mimeOf(file: LearnFile): string {
    return mimeOfExtension(file.fileType);
  }

  /**
   * "打开"：确保文件在沙箱里（已下过则直接复用），再交给系统查看器。
   *
   * 两步都失败会抛出，由调用方给用户可见反馈——**不静默**。
   */
  static async openDownloaded(file: LearnFile, context: common.UIAbilityContext): Promise<void> {
    const existing: string = FileRepository.anyDownloadedPathOf(file, context);
    const path: string = existing.length > 0
      ? existing
      : await FileRepository.download(file, context, false);
    try {
      await openFile(context, path, FileRepository.mimeOf(file));
    } catch (err) {
      // 记下系统错误码：`16000019 No matching ability is found` 是"设备上没有能打开该类型的应用"，
      // 与"意图本身不合法"要能分开（2026-09-28 真机实测，模拟器上就是前者）
      Logger.warn(TAG, `打开文件失败 id=${file.id} ${describeError(err)}`);
      // ArkTS 不允许 throw 任意类型；交给既有归类（NFR-NET 的四分类），把技术细节留在日志里
      throw normalize(err, '打开文件');
    }
  }

  /**
   * "分享"：把**已在沙箱**的那一份交给系统分享面板。
   *
   * 只接受沙箱内文件：自定义下载目录里那份拿到的是**文档 URI**（`file://docs/…`），
   * 分享面板读不到它的字节。调用方负责先确保落盘（`fileStore.share` 复用下载状态机）。
   */
  static async share(file: LearnFile, context: common.UIAbilityContext): Promise<void> {
    const path: string = FileRepository.downloadedPathOf(file, context);
    if (path.length === 0) {
      throw normalize(new Error('文件不在沙箱'), '分享文件');
    }
    await FileRepository.presentShare(path, file.fileType, context);
  }

  /** 作业附件的"分享"（同一套，只是路径来自附件目录） */
  static async shareAttachment(file: LearnFile, homeworkId: string,
                               context: common.UIAbilityContext): Promise<void> {
    const path: string = FileRepository.downloadedAttachmentPathOf(file, homeworkId, context);
    if (path.length === 0) {
      throw normalize(new Error('附件不在沙箱'), '分享附件');
    }
    await FileRepository.presentShare(path, file.fileType, context);
  }

  /**
   * 调系统分享面板。标题取**磁盘上那个文件名**（用户看到的、对方收到的就是这个），
   * 不从 `title` 拼——`findExisting` 可能命中"当时没省略课程名前缀"的那一份，
   * 现拼会与真实文件名不符。
   */
  private static async presentShare(path: string, extension: string,
                                    context: common.UIAbilityContext): Promise<void> {
    try {
      await shareFile(context, path, basenameOf(path), extension);
    } catch (err) {
      // 记下系统错误码：`1003702001 记录类型不支持` 是"我们给的类型它不认"，
      // 与"设备上根本没有分享面板"要能分开（见 share spec §6）
      Logger.warn(TAG, `分享失败 ${describeError(err)}`);
      throw normalize(err, '分享文件');
    }
  }

  /** 相对目录：`<课程名>/<文件 id>`（清洗过，不得越级） */
  static relativeDirOf(file: LearnFile): string {
    return `${sanitizePathSegment(file.courseName)}/${sanitizePathSegment(file.fileId)}`;
  }

  /**
   * 作业附件的相对目录：`附件/<课程名>/<作业 id>/<附件 id>`。
   *
   * 比课件多一层：同一门课里，附件与课件可能**同名**（都叫「作业要求.pdf」），
   * 不加分隔会互相覆盖。
   */
  static attachmentDirOf(attachmentId: string, homeworkId: string, courseName: string): string {
    return `附件/${sanitizePathSegment(courseName)}/${sanitizePathSegment(homeworkId)}/${sanitizePathSegment(attachmentId)}`;
  }

  /**
   * 内容是否像服务端的**跳转桩页面**：体量很小且含 `location.href`。
   *
   * 两个条件都要求：正常课件可能正好含这个串（比如讲义里贴了 JS 代码），
   * 但那种文件不会只有几 KB。
   */
  private static looksLikeRedirectStub(data: ArrayBuffer): boolean {
    if (data.byteLength > STUB_MAX_BYTES) {
      return false;
    }
    const prefix: string = decodePrefix(data, SNIFF_BYTES);
    return prefix.includes(REDIRECT_MARKER);
  }
}
