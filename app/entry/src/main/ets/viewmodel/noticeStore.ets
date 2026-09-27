/**
 * 通知状态：单一应用级 Store（ADR-0004），形状与 semesterStore/courseStore 一致。
 *
 * 职责边界：
 * - 本层不碰网络（扇出在 `repository`）；
 * - 取数的"输入"是**课程列表**（通知按课程取），故 `ensureLoadedFor(semesterId, courses)`
 *   用"学期 + 课程 id 集"作为签名：学期变了或课程集变了都要重取；
 * - 并发下**末次请求胜出**（与 courseStore 同一套做法，见代码审查 N-02 的教训）：
 *   在途时不丢弃目标，本次成功后再按最新目标补拉一次；
 * - **本地已读覆盖**：打开详情时按上游发一次服务端"已读"请求，成功后在这里记下
 *   该条已读（乐观），下次刷新以服务端为准（notices spec §3.3 第 7 条）。
 */

import { Course } from '../model/course';
import { Notice, NoticeBatch, NoticeFilter, filterByCourse, filterNotices } from '../model/notice';
import { NoticeRepository } from '../repository/noticeRepository';
import { FailReason } from '../model/auth';
import { normalize } from '../common/errors';
import { textKeyOfFailReason } from '../common/texts';
import { Logger } from '../common/logger';

const TAG: string = 'noticeStore';

/** 一次取数请求的输入（用于"末次胜出"） */
class NoticeRequest {
  readonly semesterId: string;
  readonly courses: Course[];

  constructor(semesterId: string, courses: Course[]) {
    this.semesterId = semesterId;
    this.courses = courses;
  }
}

function signatureOf(semesterId: string, courses: Course[]): string {
  const ids: string[] = courses.map((course: Course) => course.id);
  return `${semesterId}|${ids.join(',')}`;
}

export class NoticeState {
  readonly fetching: boolean;
  readonly items: Notice[];
  readonly failedCourses: number;
  readonly totalCourses: number;
  readonly errorReason: FailReason | null;
  readonly errorTextKey: string;
  /**
   * "本地已读覆盖"的版本号。
   *
   * 存在的理由：`readOverrides` 变了但 items/filter 等字段没变时，ArkUI 不会重建页面，
   * 于是"刚点开过的通知"仍然是未读样式。页面把这个字段抄进 `@State`，覆盖一变就重建。
   */
  readonly readVersion: number;

  constructor(fetching: boolean, items: Notice[], failedCourses: number,
              totalCourses: number, errorReason: FailReason | null, errorTextKey: string,
              readVersion: number) {
    this.fetching = fetching;
    this.items = items;
    this.failedCourses = failedCourses;
    this.totalCourses = totalCourses;
    this.errorReason = errorReason;
    this.errorTextKey = errorTextKey;
    this.readVersion = readVersion;
  }
}

export type NoticeStateListener = (state: NoticeState) => void;

export class NoticeStore {
  private static instance: NoticeStore | null = null;

  static getInstance(): NoticeStore {
    if (NoticeStore.instance === null) {
      NoticeStore.instance = new NoticeStore();
    }
    return NoticeStore.instance;
  }

  private listeners: NoticeStateListener[] = [];
  private fetching: boolean = false;
  private items: Notice[] = [];
  private failedCourses: number = 0;
  private totalCourses: number = 0;
  private errorReason: FailReason | null = null;
  private errorTextKey: string = '';

  /** 已加载对应的签名（学期 + 课程集）；空串表示尚未加载 */
  private loadedSignature: string = '';
  /** 在途时被要求的最新目标；本次结束后据此补拉 */
  private requested: NoticeRequest | null = null;
  /** 本地已读覆盖（乐观更新）。以服务端字段为准，这里只是"刚点开过"的即时反馈 */
  private readOverrides: string[] = [];
  /** 覆盖的版本号，随覆盖变化而自增（供页面重建） */
  private readVersion: number = 0;

  subscribe(listener: NoticeStateListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: NoticeStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前订阅者数量。供页面/测试断言无泄漏 */
  listenerCount(): number {
    return this.listeners.length;
  }

  snapshot(): NoticeState {
    return new NoticeState(this.fetching, this.items, this.failedCourses,
      this.totalCourses, this.errorReason, this.errorTextKey, this.readVersion);
  }

  /**
   * 某视图要展示的通知：先按课程范围过滤（课程详情页签传 courseId，通知标签传空），
   * 再按"全部/未读"筛选，并计入本地已读覆盖。
   *
   * **课程范围在展示层过滤**：store 只有一份全学期列表，两个视图共享它；
   * 若各自按范围去取数，就会互相把对方的列表换掉（曾实测踩到）。
   */
  visibleFor(courseId: string, filter: NoticeFilter): Notice[] {
    return filterNotices(filterByCourse(this.items, courseId), filter, this.readOverrides);
  }

  /** 是否已读：服务端字段 + 本地覆盖（刚打开过详情的那些） */
  isRead(notice: Notice): boolean {
    return notice.hasRead || this.readOverrides.includes(notice.id);
  }

  /** 按 id 找通知（详情页用）。找不到返回 null */
  noticeOf(noticeId: string): Notice | null {
    for (const notice of this.items) {
      if (notice.id === noticeId) {
        return notice;
      }
    }
    return null;
  }

  /**
   * 打开详情时调用：发一次服务端"已读"请求，**成功才**记本地已读覆盖。
   *
   * 失败不标记——否则界面会说"已读"而服务端仍认为未读，下次刷新又跳回未读，更让人困惑。
   */
  async markReadByOpening(notice: Notice): Promise<void> {
    if (this.isRead(notice)) {
      return;
    }
    const ok: boolean = await NoticeRepository.markRead(notice.url);
    if (ok) {
      this.markRead(notice.id);
    }
  }

  /** 打开详情后按上游发过"已读"请求且成功时调用（乐观） */
  markRead(noticeId: string): void {
    if (noticeId.length === 0 || this.readOverrides.includes(noticeId)) {
      return;
    }
    this.readOverrides.push(noticeId);
    this.readVersion++;
    this.notify();
  }

  /**
   * 让通知对齐"当前学期 + 当前课程集"。
   *
   * **筛选不在这里**：`filter` 是**页面本地**状态（`visibleFor` 由调用方传入）。
   * 放进 store 会让两个视图（通知标签、课程详情页签）共用同一个筛选，互相串——
   * 实测用户报的"未读里出现全部、要刷新才分辨得出"就是它。
   *
   * **取数范围恒为整个学期**（`courses` 传当前学期的全部课程）：课程详情页签同样触发这一次
   * 取数、再按 courseId 过滤展示——范围只有一个，两个视图才不会互相覆盖。
   *
   * 学期为空 → 不做任何事（不发请求，呈现空态而非错误态，notices spec §3.3 第 8 条）；
   * 课程为空 → 同样不发请求（上游在这一点漏了守卫）。
   */
  async ensureLoadedFor(semesterId: string, courses: Course[]): Promise<void> {
    if (semesterId.length === 0 || courses.length === 0) {
      return;
    }
    if (signatureOf(semesterId, courses) === this.loadedSignature) {
      return;
    }
    await this.refresh(semesterId, courses);
  }

  /**
   * 强制重拉。
   *
   * 失败进错误态（页面给"重试"），**不自动重试**——对齐上游。
   * 在途时不丢弃目标：记下来，本次**成功**后按最新目标补拉一次
   * （失败后补拉会变成失败循环，那种情况该让用户看到错误态并手动重试）。
   */
  async refresh(semesterId: string, courses: Course[]): Promise<void> {
    if (semesterId.length === 0 || courses.length === 0) {
      return;
    }
    const signature: string = signatureOf(semesterId, courses);
    if (this.fetching) {
      this.requested = new NoticeRequest(semesterId, courses);
      Logger.info(TAG, '通知请求在途，改记为待补拉');
      return;
    }

    this.fetching = true;
    this.requested = new NoticeRequest(semesterId, courses);
    this.errorReason = null;
    this.errorTextKey = '';
    this.notify();

    let succeeded: boolean = false;
    try {
      const batch: NoticeBatch = await NoticeRepository.loadAll(courses);
      this.items = batch.items;
      this.failedCourses = batch.failedCourses;
      this.totalCourses = batch.totalCourses;
      this.loadedSignature = signature;
      succeeded = true;
    } catch (err) {
      const error = normalize(err, '加载通知');
      this.errorReason = error.reason;
      this.errorTextKey = textKeyOfFailReason(error.reason, error.hintKey);
      Logger.warn(TAG, `通知加载失败 reason=${error.reason}`);
    } finally {
      this.fetching = false;
      this.notify();

      const pending: NoticeRequest | null = this.requested;
      if (succeeded && pending !== null
        && signatureOf(pending.semesterId, pending.courses) !== this.loadedSignature) {
        Logger.info(TAG, '目标已变化，补拉通知');
        await this.refresh(pending.semesterId, pending.courses);
      }
    }
  }

  private notify(): void {
    const snapshot: NoticeState = this.snapshot();
    const current: NoticeStateListener[] = this.listeners.slice();
    for (const listener of current) {
      try {
        listener(snapshot);
      } catch (err) {
        Logger.warn(TAG, '订阅回调抛错，已隔离');
      }
    }
  }
}
