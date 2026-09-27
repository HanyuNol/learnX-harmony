/**
 * 文件状态：单一应用级 Store（ADR-0004），形状与 notice/assignment store 一致。
 *
 * 取数输入是"当前学期的课程列表"，用"学期 + 课程 id 集"作签名对齐；在途时不丢弃目标
 * （末次请求胜出）；**全部失败按错误态**。本批不做筛选（属 FR-12），故没有页面本地筛选状态。
 *
 * 下载状态**按文件 id 记**并单独发一个版本号：下载是"某一条"的状态变化，不该让整表重排；
 * 页面订阅这个版本号来重建自己的那一块。下载动作本身走 `FileRepository`（含落盘与打开），
 * `pages` 不碰网络也不碰系统能力。
 */

import { Course } from '../model/course';
import { LearnFile, PROGRESS_UNKNOWN, categoryNamesOf, filterByCategory, percentOf, sortFiles } from '../model/file';
import { FileBatch, FileRepository } from '../repository/fileRepository';
import { FailReason } from '../model/auth';
import { normalize } from '../common/errors';
import { textKeyOfFailReason } from '../common/texts';
import { Logger } from '../common/logger';
import { common } from '@kit.AbilityKit';

const TAG: string = 'fileStore';

/** 某一条文件的下载状态 */
export enum DownloadState {
  /** 还没下过 */
  IDLE = 'idle',
  /** 正在下载 */
  DOWNLOADING = 'downloading',
  /** 已落到沙箱 */
  READY = 'ready',
  /** 下载失败（详情页给重试） */
  FAILED = 'failed'
}

class FileRequest {
  readonly semesterId: string;
  readonly courses: Course[];

  constructor(semesterId: string, courses: Course[]) {
    this.semesterId = semesterId;
    this.courses = courses;
  }
}

function signatureOf(semesterId: string, courses: Course[]): string {
  return `${semesterId}|${courses.map((course: Course) => course.id).join(',')}`;
}

export class FileState {
  readonly fetching: boolean;
  readonly items: LearnFile[];
  readonly failedCourses: number;
  readonly totalCourses: number;
  readonly errorReason: FailReason | null;
  readonly errorTextKey: string;
  /** 下载状态变化的版本号（页面据此重建自己那块，不影响列表本身） */
  readonly downloadVersion: number;

  constructor(fetching: boolean, items: LearnFile[], failedCourses: number, totalCourses: number,
              errorReason: FailReason | null, errorTextKey: string, downloadVersion: number) {
    this.fetching = fetching;
    this.items = items;
    this.failedCourses = failedCourses;
    this.totalCourses = totalCourses;
    this.errorReason = errorReason;
    this.errorTextKey = errorTextKey;
    this.downloadVersion = downloadVersion;
  }
}

export type FileStateListener = (state: FileState) => void;

export class FileStore {
  private static instance: FileStore | null = null;

  static getInstance(): FileStore {
    if (FileStore.instance === null) {
      FileStore.instance = new FileStore();
    }
    return FileStore.instance;
  }

  private listeners: FileStateListener[] = [];
  private fetching: boolean = false;
  private items: LearnFile[] = [];
  private failedCourses: number = 0;
  private totalCourses: number = 0;
  private errorReason: FailReason | null = null;
  private errorTextKey: string = '';
  private loadedSignature: string = '';
  private requested: FileRequest | null = null;
  private downloadStates: Map<string, DownloadState> = new Map();
  /** 各文件的下载百分比（`PROGRESS_UNKNOWN` = 服务端没给总长度） */
  private downloadPercents: Map<string, number> = new Map();
  private downloadVersion: number = 0;

  subscribe(listener: FileStateListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: FileStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  listenerCount(): number {
    return this.listeners.length;
  }

  snapshot(): FileState {
    return new FileState(this.fetching, this.items, this.failedCourses, this.totalCourses,
      this.errorReason, this.errorTextKey, this.downloadVersion);
  }

  /**
   * 某视图要展示的文件：按课程范围过滤（课程详情页签传 courseId），再按分类筛（FR-12），
   * 最后按上传时间倒序。
   */
  visibleFor(courseId: string, categoryName: string): LearnFile[] {
    const scoped: LearnFile[] = courseId.length === 0
      ? this.items
      : this.items.filter((item: LearnFile) => item.courseId === courseId);
    return sortFiles(filterByCategory(scoped, categoryName));
  }

  /** 某视图筛选条里可用的分类名（来自该范围内实际出现过的分类） */
  categoriesFor(courseId: string): string[] {
    const scoped: LearnFile[] = courseId.length === 0
      ? this.items
      : this.items.filter((item: LearnFile) => item.courseId === courseId);
    return categoryNamesOf(scoped);
  }

  /** 按 id 找一条（详情页用）；找不到返回 null */
  fileOf(id: string): LearnFile | null {
    for (const item of this.items) {
      if (item.id === id) {
        return item;
      }
    }
    return null;
  }

  downloadStateOf(fileId: string): DownloadState {
    const state: DownloadState | undefined = this.downloadStates.get(fileId);
    return state === undefined ? DownloadState.IDLE : state;
  }

  async ensureLoadedFor(semesterId: string, courses: Course[]): Promise<void> {
    if (semesterId.length === 0 || courses.length === 0) {
      return;
    }
    if (signatureOf(semesterId, courses) === this.loadedSignature) {
      return;
    }
    await this.refresh(semesterId, courses);
  }

  /** 强制重拉。失败进错误态（页面给"重试"），不自动重试——对齐上游 */
  async refresh(semesterId: string, courses: Course[]): Promise<void> {
    if (semesterId.length === 0 || courses.length === 0) {
      return;
    }
    const signature: string = signatureOf(semesterId, courses);
    this.requested = new FileRequest(semesterId, courses);
    if (this.fetching) {
      Logger.info(TAG, '文件请求在途，改记为待补拉');
      return;
    }

    this.fetching = true;
    this.errorReason = null;
    this.errorTextKey = '';
    this.notify();

    let succeeded: boolean = false;
    try {
      const batch: FileBatch = await FileRepository.loadAll(courses);
      this.items = batch.items;
      this.failedCourses = batch.failedCourses;
      this.totalCourses = batch.totalCourses;
      this.loadedSignature = signature;
      succeeded = true;
    } catch (err) {
      const error = normalize(err, '加载文件');
      this.errorReason = error.reason;
      this.errorTextKey = textKeyOfFailReason(error.reason, error.hintKey);
      Logger.warn(TAG, `文件加载失败 reason=${error.reason}`);
    } finally {
      this.fetching = false;
      this.notify();
      const pending: FileRequest | null = this.requested;
      if (succeeded && pending !== null
        && signatureOf(pending.semesterId, pending.courses) !== this.loadedSignature) {
        Logger.info(TAG, '目标已变化，补拉文件');
        await this.refresh(pending.semesterId, pending.courses);
      }
    }
  }

  /**
   * 只下载（不打开）。状态机：`IDLE/FAILED → DOWNLOADING → READY|FAILED`。
   * 失败时**抛**给页面，由页面给可见反馈（Toast）——不静默（files spec §3.3 第 5 条）。
   *
   * `forceRefresh` 为真即"重新下载"（downloads spec §2 第 4 条）：覆盖旧文件重下一遍。
   */
  async download(file: LearnFile, context: common.Context, forceRefresh: boolean): Promise<void> {
    if (this.downloadStateOf(file.id) === DownloadState.DOWNLOADING) {
      return;
    }
    this.setDownloadState(file.id, DownloadState.DOWNLOADING);
    this.setDownloadPercent(file.id, PROGRESS_UNKNOWN);
    try {
      const report: (received: number, total: number) => void = (received: number, total: number) => {
        // 百分比只在**整数值变化**时才通知：下载事件很密，每次都通知会让页面反复重建
        this.setDownloadPercent(file.id, percentOf(received, total));
      };
      await FileRepository.download(file, context, forceRefresh, report);
      this.setDownloadState(file.id, DownloadState.READY);
      this.setDownloadPercent(file.id, 100);
    } catch (err) {
      this.setDownloadState(file.id, DownloadState.FAILED);
      this.setDownloadPercent(file.id, PROGRESS_UNKNOWN);
      Logger.warn(TAG, `文件下载失败 id=${file.id}`);
      throw new Error('文件下载失败');
    }
  }

  /**
   * 下载（已下过则复用）并在系统查看器中打开。
   *
   * 与 `download` 分开是因为两者对用户是**两个动作**：一个只落盘，一个要打开
   * （files spec §2.3）。两者共用同一份状态与同一套失败语义。
   */
  async openDownloaded(file: LearnFile, context: common.UIAbilityContext): Promise<void> {
    if (this.downloadStateOf(file.id) === DownloadState.DOWNLOADING) {
      return;
    }
    this.setDownloadState(file.id, DownloadState.DOWNLOADING);
    try {
      await FileRepository.openDownloaded(file, context);
      this.setDownloadState(file.id, DownloadState.READY);
    } catch (err) {
      this.setDownloadState(file.id, DownloadState.FAILED);
      Logger.warn(TAG, `文件打开失败 id=${file.id}`);
      throw new Error('文件打开失败');
    }
  }

  /** 该文件当前的下载百分比（0~100）；`PROGRESS_UNKNOWN` 表示服务端没给总长度 */
  downloadPercentOf(fileId: string): number {
    const percent: number | undefined = this.downloadPercents.get(fileId);
    return percent === undefined ? PROGRESS_UNKNOWN : percent;
  }

  /** 该文件是否已在沙箱（详情页显示"已下载"） */
  isDownloaded(file: LearnFile, context: common.Context): boolean {
    if (this.downloadStateOf(file.id) === DownloadState.READY) {
      return true;
    }
    return FileRepository.isDownloaded(file, context);
  }

  private setDownloadState(fileId: string, state: DownloadState): void {
    const next: Map<string, DownloadState> = new Map(this.downloadStates);
    next.set(fileId, state);
    this.downloadStates = next;
    this.downloadVersion = this.downloadVersion + 1;
    this.notify();
  }

  /** 进度百分比变化时才通知（整数不变就不打扰页面） */
  private setDownloadPercent(fileId: string, percent: number): void {
    if (this.downloadPercentOf(fileId) === percent) {
      return;
    }
    const next: Map<string, number> = new Map(this.downloadPercents);
    next.set(fileId, percent);
    this.downloadPercents = next;
    this.notify();
  }

  private notify(): void {
    const snapshot: FileState = this.snapshot();
    const current: FileStateListener[] = this.listeners.slice();
    for (const listener of current) {
      try {
        listener(snapshot);
      } catch (err) {
        Logger.warn(TAG, '订阅回调抛错，已隔离');
      }
    }
  }
}
