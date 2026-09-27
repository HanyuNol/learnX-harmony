/**
 * 作业状态：单一应用级 Store（ADR-0004），形状与 notice/course store 一致。
 *
 * 与通知同构：取数输入是"当前学期的课程列表"，用"学期 + 课程 id 集"作签名对齐；
 * 在途时不丢弃目标（末次请求胜出）；**全部失败按错误态**；**筛选是页面本地状态**
 * （这两条都是通知那次实测踩过的坑，见 notices spec §5.2）。
 */

import { Course } from '../model/course';
import { Assignment, AssignmentFilter, filterAssignments } from '../model/assignment';
import { AssignmentBatch, AssignmentRepository } from '../repository/assignmentRepository';
import { FailReason } from '../model/auth';
import { normalize } from '../common/errors';
import { textKeyOfFailReason } from '../common/texts';
import { Logger } from '../common/logger';

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

  private listeners: AssignmentStateListener[] = [];
  private fetching: boolean = false;
  private items: Assignment[] = [];
  private failedCourses: number = 0;
  private totalCourses: number = 0;
  private errorReason: FailReason | null = null;
  private errorTextKey: string = '';
  private loadedSignature: string = '';
  private requested: AssignmentRequest | null = null;

  subscribe(listener: AssignmentStateListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: AssignmentStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  listenerCount(): number {
    return this.listeners.length;
  }

  snapshot(): AssignmentState {
    return new AssignmentState(this.fetching, this.items, this.failedCourses,
      this.totalCourses, this.errorReason, this.errorTextKey);
  }

  /** 某视图要展示的作业：按课程范围过滤（课程详情页签传 courseId），再按未完成/已完成筛选 */
  visibleFor(courseId: string, filter: AssignmentFilter, now: number): Assignment[] {
    const scoped: Assignment[] = courseId.length === 0
      ? this.items
      : this.items.filter((item: Assignment) => item.courseId === courseId);
    return filterAssignments(scoped, filter);
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
    const current: AssignmentStateListener[] = this.listeners.slice();
    for (const listener of current) {
      try {
        listener(snapshot);
      } catch (err) {
        Logger.warn(TAG, '订阅回调抛错，已隔离');
      }
    }
  }
}
