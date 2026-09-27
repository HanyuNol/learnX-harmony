/**
 * 课程状态：单一应用级 Store（ADR-0004）。
 *
 * 形状与 `semesterStore`/`authStore` 一致（订阅 + 快照 + 反订阅 + `listenerCount`），
 * 因为它们解决同一类问题：课程要被课程列表页、课程详情页、以及**将来的三个维度页**
 * （通知/作业/文件按课程扇出）共享。
 *
 * 职责边界：
 * - 本层**不碰网络与系统能力**，取数交给 `repository`；
 * - `items` 记住自己属于哪个学期（`semesterId`），学期一变即视为过期并重取，
 *   成功后**整表替换**——否则会把两个学期的课程混在一起（courses spec §3.3 第 2 条）；
 * - 对外提供 `courseIds()` 与 `nameOf(id)`：FR-06～FR-08 据此扇出并回填课程名。
 */

import { common } from '@kit.AbilityKit';
import { Course, isCourseListStale, sortCourses } from '../model/course';
import { CourseRepository } from '../repository/courseRepository';
import { FailReason } from '../model/auth';
import { normalize } from '../common/errors';
import { textKeyOfFailReason } from '../common/texts';
import { Logger } from '../common/logger';

const TAG: string = 'courseStore';

/** 对外快照（不可变） */
export class CourseState {
  readonly fetching: boolean;
  readonly items: Course[];
  /** 当前 items 属于哪个学期；空串表示尚未加载过 */
  readonly semesterId: string;
  readonly errorReason: FailReason | null;
  readonly errorTextKey: string;

  constructor(fetching: boolean, items: Course[], semesterId: string,
              errorReason: FailReason | null, errorTextKey: string) {
    this.fetching = fetching;
    this.items = items;
    this.semesterId = semesterId;
    this.errorReason = errorReason;
    this.errorTextKey = errorTextKey;
  }
}

export type CourseStateListener = (state: CourseState) => void;

export class CourseStore {
  private static instance: CourseStore | null = null;

  static getInstance(): CourseStore {
    if (CourseStore.instance === null) {
      CourseStore.instance = new CourseStore();
    }
    return CourseStore.instance;
  }

  private listeners: CourseStateListener[] = [];
  private fetching: boolean = false;
  private items: Course[] = [];
  private loadedSemesterId: string = '';
  private errorReason: FailReason | null = null;
  private errorTextKey: string = '';

  subscribe(listener: CourseStateListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: CourseStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前订阅者数量。供页面/测试断言无泄漏 */
  listenerCount(): number {
    return this.listeners.length;
  }

  snapshot(): CourseState {
    return new CourseState(this.fetching, this.items, this.loadedSemesterId,
      this.errorReason, this.errorTextKey);
  }

  /** 课程 id 列表，供下游三个维度扇出。**空数组时下游不得发请求** */
  courseIds(): string[] {
    const ids: string[] = [];
    for (const course of this.items) {
      if (course.id.length > 0) {
        ids.push(course.id);
      }
    }
    return ids;
  }

  /** 课程显示名（供下游条目回填 courseName）；查不到返回空串由调用方决定回退 */
  nameOf(courseId: string): string {
    for (const course of this.items) {
      if (course.id === courseId) {
        return course.displayName();
      }
    }
    return '';
  }

  /**
   * 让课程列表对得上给定学期：学期为空则不做任何事；
   * 已加载的正是这个学期则跳过；否则重新拉（覆盖式）。
   */
  async ensureLoadedFor(semesterId: string): Promise<void> {
    if (semesterId.length === 0) {
      return;
    }
    if (!isCourseListStale(this.loadedSemesterId, semesterId)) {
      return;
    }
    await this.refresh(semesterId);
  }

  /** 强制重拉。失败进错误态（页面给"重试"），不自动重试——对齐上游 */
  async refresh(semesterId: string): Promise<void> {
    if (this.fetching || semesterId.length === 0) {
      return;
    }
    this.fetching = true;
    this.errorReason = null;
    this.errorTextKey = '';
    this.notify();

    try {
      const courses: Course[] = sortCourses(await CourseRepository.load(semesterId));
      this.items = courses;
      this.loadedSemesterId = semesterId;
      Logger.info(TAG, `课程加载完成 学期=${semesterId} 数量=${courses.length}`);
    } catch (err) {
      const error = normalize(err, '加载课程');
      this.errorReason = error.reason;
      this.errorTextKey = textKeyOfFailReason(error.reason, error.hintKey);
      Logger.warn(TAG, `课程加载失败 reason=${error.reason}`);
    } finally {
      this.fetching = false;
      this.notify();
    }
  }

  private notify(): void {
    const snapshot: CourseState = this.snapshot();
    const current: CourseStateListener[] = this.listeners.slice();
    for (const listener of current) {
      try {
        listener(snapshot);
      } catch (err) {
        Logger.warn(TAG, '订阅回调抛错，已隔离');
      }
    }
  }
}
