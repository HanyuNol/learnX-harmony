/**
 * 通知：按课程扇出的编排。
 *
 * 分层：本层才能同时碰网络与课程数据；`viewmodel` 只拿结果（架构不变量 §1、§3）。
 *
 * **并发上限**是刻意加的：上游对全部课程 `Promise.all`、每课再并行两批，12 门课就是
 * 24 个请求同时在飞；移动端对网络与内存都不友好，也正是并发出问题的场景
 * （见 notices spec §3.3 第 1 条）。
 */

import { Course } from '../model/course';
import { Notice, NoticeBatch, mergeNoticeBatches } from '../model/notice';
import { AuthError } from '../model/auth';
import { LearnClient } from '../network/learnClient';
import { Logger } from '../common/logger';
import { normalize } from '../common/errors';

const TAG: string = 'noticeRepository';

/** 同时在飞的课程数上限。取值是工程判断（spec §6 已登记），以实测失败率/耗时为定 */
const FANOUT_LIMIT: number = 4;

/** 单门课的取数结果：`notices` 为 null 表示失败，`error` 带回失败原因 */
class CourseNoticeResult {
  readonly notices: Notice[] | null;
  readonly error: AuthError | null;

  constructor(notices: Notice[] | null, error: AuthError | null) {
    this.notices = notices;
    this.error = error;
  }
}

export class NoticeRepository {
  /**
   * 取全部课程的通知并合并。
   *
   * 分块并发：每块最多 `FANOUT_LIMIT` 门课，块内并行、块间顺序。
   * 单门课失败**不让整体失败**——`loadOne` 返回 `null`，由 `mergeNoticeBatches` 记入
   * 失败课程数（部分失败策略见 notices spec §3.3 第 2 条）。
   */
  static async loadAll(courses: Course[]): Promise<NoticeBatch> {
    const batches: Array<Notice[] | null> = [];
    let firstError: AuthError | null = null;
    for (let i = 0; i < courses.length; i += FANOUT_LIMIT) {
      const chunk: Course[] = courses.slice(i, i + FANOUT_LIMIT);
      const settled: Array<CourseNoticeResult> =
        await Promise.all(chunk.map((course: Course) => NoticeRepository.loadOne(course)));
      for (const item of settled) {
        batches.push(item.notices);
        if (firstError === null && item.error !== null) {
          firstError = item.error;
        }
      }
    }

    // **全部失败**时抛出，交给上层既有的错误路径（错误态 + 重试 + 正确文案）。
    // 不抛的话调用方只会看到一个空列表——实测用户报的"偶尔没有通知、刷新后才出现"
    // 就是这种情形：瞬时失败导致 12 门课全失败，而"部分失败"的提示只在部分失败时显示，
    // 全失败反而静默成空态。
    if (batches.length > 0 && firstError !== null
      && batches.every((item: Notice[] | null) => item === null)) {
      Logger.warn(TAG, `全部 ${batches.length} 门课程的通知都加载失败，按错误态处理`);
      throw firstError;
    }

    const merged: NoticeBatch = mergeNoticeBatches(batches);
    Logger.info(TAG, `通知加载完成 课程数=${merged.totalCourses} 失败=${merged.failedCourses} 通知数=${merged.items.length}`);
    return merged;
  }

  /**
   * 单门课的通知。
   *
   * 失败**不抛**（交由合并层计失败数、部分失败不整页失败），但要把**错误本身**带回去：
   * 否则"全部失败"时上层拿不到归类，只能给个空列表。
   */
  private static async loadOne(course: Course): Promise<CourseNoticeResult> {
    try {
      const notices: Notice[] =
        await LearnClient.getInstance().fetchNoticesOfCourse(course.id, course.displayName());
      return new CourseNoticeResult(notices, null);
    } catch (err) {
      // 带上归类与细节：否则"12 门全失败"这种情形只能看到一堆课程 id，看不出为什么
      // （代码审查 N-10 提的正是这类"日志缺上下文"）
      const error = normalize(err, '加载课程通知');
      Logger.warn(TAG, `课程通知加载失败 course=${course.id} reason=${error.reason} detail=${error.detail}`);
      return new CourseNoticeResult(null, error);
    }
  }

  /**
   * 通知详情的"已读"请求。
   *
   * 上游打开详情时会对详情 URL 发一次 GET，服务端据此记已读（`NoticeDetail.tsx:68-70`）。
   * 这里也照做，但**返回是否成功**——失败时不该在本地假装已读。
   */
  static async markRead(detailUrl: string): Promise<boolean> {
    if (detailUrl.length === 0) {
      return false;
    }
    try {
      await LearnClient.getInstance().getWithAuth(detailUrl);
      return true;
    } catch (err) {
      Logger.warn(TAG, '通知"已读"请求失败，本地不标记');
      return false;
    }
  }
}
