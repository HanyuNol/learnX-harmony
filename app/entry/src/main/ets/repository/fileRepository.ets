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
import { LearnFile, downloadFileName, sanitizePathSegment, sortFiles } from '../model/file';
import { mimeOfExtension } from '../common/mime';
import { LearnClient } from '../network/learnClient';
import { ensureDir, ensureFilesRoot, fileExists, writeBytes, removeFile, decodePrefix, openFile } from '../native/fileAdapter';
import { Logger } from '../common/logger';
import { common } from '@kit.AbilityKit';

const TAG: string = 'fileRepository';

/** 同时在飞的课程数上限（沿用通知那套工程判断） */
const FANOUT_LIMIT: number = 4;

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

  constructor(items: LearnFile[] | null, course: Course) {
    this.items = items;
    this.course = course;
  }
}

export class FileRepository {
  /** 取全部课程的文件。全部失败时抛出，交给上层既有错误路径 */
  static async loadAll(courses: Course[]): Promise<FileBatch> {
    const collected: LearnFile[] = [];
    let failed: number = 0;

    for (let i = 0; i < courses.length; i += FANOUT_LIMIT) {
      const chunk: Course[] = courses.slice(i, i + FANOUT_LIMIT);
      const settled: Array<CourseFileResult> = await Promise.all(
        chunk.map((course: Course) => FileRepository.loadOneCourse(course)));
      for (const entry of settled) {
        if (entry.items === null) {
          failed++;
          continue;
        }
        for (const item of entry.items) {
          collected.push(item);
        }
      }
    }

    if (courses.length > 0 && failed === courses.length) {
      Logger.warn(TAG, `全部 ${courses.length} 门课程的文件都加载失败，按错误态处理`);
      throw new Error('全部课程的文件都加载失败');
    }

    const sorted: LearnFile[] = sortFiles(collected);
    Logger.info(TAG, `文件加载完成 课程数=${courses.length} 失败=${failed} 文件数=${sorted.length}`);
    return new FileBatch(sorted, failed, courses.length);
  }

  private static async loadOneCourse(course: Course): Promise<CourseFileResult> {
    try {
      const items: LearnFile[] = await LearnClient.getInstance()
        .fetchFilesOfCourse(course.id, course.displayName(), course.teacherName);
      return new CourseFileResult(items, course);
    } catch (err) {
      Logger.warn(TAG, `课程文件加载失败 course=${course.id}`);
      return new CourseFileResult(null, course);
    }
  }

  /**
   * 下载一个文件到应用沙箱，返回沙箱内的绝对路径。
   *
   * `forceRefresh` 为 false 且目标文件已存在时**直接复用**（不发起请求）。
   * 失败时抛错，且已写入的半截文件会被删除。
   */
  static async download(file: LearnFile, context: common.Context, forceRefresh: boolean): Promise<string> {
    const root: string = ensureFilesRoot(context);
    const directory: string = `${root}/${sanitizePathSegment(file.courseName)}/${sanitizePathSegment(file.fileId)}`;
    ensureDir(directory);
    const path: string = `${directory}/${downloadFileName(file.courseName, file.title, file.fileType)}`;

    if (!forceRefresh && fileExists(path)) {
      Logger.info(TAG, `文件已在本地，直接复用 id=${file.id}`);
      return path;
    }

    const data: ArrayBuffer = await LearnClient.getInstance().downloadFileBytes(file.fileId);
    if (data.byteLength <= 0) {
      removeFile(path);
      throw new Error('下载到的文件为空');
    }
    if (FileRepository.looksLikeRedirectStub(data)) {
      removeFile(path);
      throw new Error('下载端点返回了跳转页面（会话可能已失效）');
    }

    writeBytes(path, data);
    Logger.info(TAG, `文件已下载 id=${file.id} 字节=${data.byteLength}`);
    return path;
  }

  /** 沙箱里的文件路径（不下载，只算路径；详情页判断"是否已下载"用） */
  static pathOf(file: LearnFile, context: common.Context): string {
    const root: string = ensureFilesRoot(context);
    return `${root}/${sanitizePathSegment(file.courseName)}/${sanitizePathSegment(file.fileId)}`
      + `/${downloadFileName(file.courseName, file.title, file.fileType)}`;
  }

  /** 该文件是否已经在沙箱里（"已下载"状态） */
  static isDownloaded(file: LearnFile, context: common.Context): boolean {
    return fileExists(FileRepository.pathOf(file, context));
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
    const path: string = await FileRepository.download(file, context, false);
    await openFile(context, path, FileRepository.mimeOf(file));
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
