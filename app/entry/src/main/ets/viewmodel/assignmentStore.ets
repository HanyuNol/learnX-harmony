/**
 * 作业状态：单一应用级 Store（ADR-0004），形状与 notice/course store 一致。
 *
 * 与通知同构：取数输入是"当前学期的课程列表"，用"学期 + 课程 id 集"作签名对齐；
 * 在途时不丢弃目标（末次请求胜出）；**全部失败按错误态**；**筛选是页面本地状态**
 * （这两条都是通知那次实测踩过的坑，见 notices spec §5.2）。
 */

import { Course } from '../model/course';
import { Assignment, AssignmentFilter, filterAssignments, sortAssignments } from '../model/assignment';
import { AssignmentBatch, AssignmentRepository } from '../repository/assignmentRepository';
import { MultipartFile } from '../model/multipart';
import { FailReason } from '../model/auth';
import { normalize } from '../common/errors';
import { textKeyOfFailReason } from '../common/texts';
import { Logger } from '../common/logger';
import { SubscriptionRegistry } from '../common/subscriptions';

const TAG: string = 'assignmentStore';

class AssignmentRequest {
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

export class AssignmentState {
  readonly fetching: boolean;
  readonly items: Assignment[];
  readonly failedCourses: number;
  readonly totalCourses: number;
  readonly errorReason: FailReason | null;
  readonly errorTextKey: string;

  constructor(fetching: boolean, items: Assignment[], failedCourses: number, totalCourses: number,
              errorReason: FailReason | null, errorTextKey: string) {
    this.fetching = fetching;
    this.items = items;
    this.failedCourses = failedCourses;
    this.totalCourses = totalCourses;
    this.errorReason = errorReason;
    this.errorTextKey = errorTextKey;
  }
}

export type AssignmentStateListener = (state: AssignmentState) => void;

export class AssignmentStore {
  private static instance: AssignmentStore | null = null;

  static getInstance(): AssignmentStore {
    if (AssignmentStore.instance === null) {
      AssignmentStore.instance = new AssignmentStore();
    }
    return AssignmentStore.instance;
  }

  /** 订阅注册表（纯类，见 `common/subscriptions`）：去重/反订阅/计数/隔离通知都在那里 */
  private subscriptions: SubscriptionRegistry<AssignmentStateListener> = new SubscriptionRegistry<AssignmentStateListener>();
  private fetching: boolean = false;
  private items: Assignment[] = [];
  private failedCourses: number = 0;
  private totalCourses: number = 0;
  private errorReason: FailReason | null = null;
  private errorTextKey: string = '';
  private loadedSignature: string = '';
  private requested: AssignmentRequest | null = null;

  subscribe(listener: AssignmentStateListener): void {
    this.subscriptions.subscribe(listener);
    listener(this.snapshot());
  }

  unsubscribe(listener: AssignmentStateListener): void {
    this.subscriptions.unsubscribe(listener);
  }

  listenerCount(): number {
    return this.subscriptions.listenerCount();
  }

  snapshot(): AssignmentState {
    return new AssignmentState(this.fetching, this.items, this.failedCourses,
      this.totalCourses, this.errorReason, this.errorTextKey);
  }

  /**
   * 某视图要展示的作业：按课程范围过滤（课程详情页签传 courseId），再按未完成/已完成筛选，
   * 最后**按当前时间重排**——批次是按取数那一刻的 `now` 排的，展示时再排一次，
   * 排序才与"现在还剩多久"一致（列表在页面上可能已停留很久）。
   */
  visibleFor(courseId: string, filter: AssignmentFilter, now: number): Assignment[] {
    const scoped: Assignment[] = courseId.length === 0
      ? this.items
      : this.items.filter((item: Assignment) => item.courseId === courseId);
    return sortAssignments(filterAssignments(scoped, filter), now);
  }

  /** 按 id 找一条（详情页用）；找不到返回 null */
  assignmentOf(id: string): Assignment | null {
    for (const item of this.items) {
      if (item.id === id) {
        return item;
      }
    }
    return null;
  }

  /**
   * 提交作业，成功后**按上次的学期与课程重拉一次**。
   *
   * 为什么重拉：提交会改变完成状态（未提交→已提交）与已提交附件，
   * 而这两样**都来自服务端**（完成状态由端点决定，见 spec §3.1），
   * 本地自己改状态等于编数据。重拉用上次请求的入参，页面不必再传一遍。
   */
  async submit(assignmentId: string, content: string, file: MultipartFile | null,
               removeAttachment: boolean): Promise<void> {
    await AssignmentRepository.submitHomework(assignmentId, content, file, removeAttachment);
    const last: AssignmentRequest | null = this.requested;
    if (last !== null) {
      this.loadedSignature = '';
      await this.refresh(last.semesterId, last.courses);
    }
  }

  /**
   * 重取某一条的详情（详情页"详情未能加载 → 重试"用）。
   *
   * 只补一条而不是整表重拉：整表重拉会把列表滚回去、也白花几十个请求，
   * 而用户要的只是这一条。成功后就地替换该条并通知。
   */
  async reloadDetailOf(id: string): Promise<void> {
    const item: Assignment | null = this.assignmentOf(id);
    if (item === null) {
      return;
    }
    const filled: Assignment = await AssignmentRepository.loadDetail(item);
    const replaced: Assignment[] = this.items.map((entry: Assignment) =>
      entry.id === id ? filled : entry);
    this.items = replaced;
    this.notify();
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
    this.requested = new AssignmentRequest(semesterId, courses);
    if (this.fetching) {
      Logger.info(TAG, '作业请求在途，改记为待补拉');
      return;
    }

    this.fetching = true;
    this.errorReason = null;
    this.errorTextKey = '';
    this.notify();

    let succeeded: boolean = false;
    try {
      const batch: AssignmentBatch = await AssignmentRepository.loadAll(courses, Date.now());
      this.items = batch.items;
      this.failedCourses = batch.failedCourses;
      this.totalCourses = batch.totalCourses;
      this.loadedSignature = signature;
      succeeded = true;
    } catch (err) {
      const error = normalize(err, '加载作业');
      this.errorReason = error.reason;
      this.errorTextKey = textKeyOfFailReason(error.reason, error.hintKey);
      Logger.warn(TAG, `作业加载失败 reason=${error.reason}`);
    } finally {
      this.fetching = false;
      this.notify();
      const pending: AssignmentRequest | null = this.requested;
      if (succeeded && pending !== null
        && signatureOf(pending.semesterId, pending.courses) !== this.loadedSignature) {
        Logger.info(TAG, '目标已变化，补拉作业');
        await this.refresh(pending.semesterId, pending.courses);
      }
    }
  }

  private notify(): void {
    const snapshot: AssignmentState = this.snapshot();
    // 遍历副本与单回调隔离都在注册表里（原先六个 Store 各写一份）
    this.subscriptions.notifyEach((listener: AssignmentStateListener) => {
      listener(snapshot);
    }, (err: Object) => {
      Logger.warn(TAG, '订阅回调抛错，已隔离');
    });
  }
}
