/**
 * 进入应用时的**后台预载**编排（FR-25）。
 *
 * 只做编排：目标与顺序的判据在 `common/prefetch`（纯逻辑、有单测），取数在各 store。
 * 三条纪律（见 `docs/specs/startup-sync.md` §3.3）：
 *
 * 1. **串行**：通知 → 文件。两个维度各自按课程扇出（`FANOUT_LIMIT=4`），同时在飞会把
 *    峰值并发翻倍，对同一个小服务器不友好；用户在等的是别的事，慢一点没代价。
 * 2. **一个学期只发起一次**：课程状态每次 `notify()` 都会叫醒订阅者，而下游 store 只在
 *    **成功**时才记下签名——只靠它去重的话，一次失败会被几次 notify 放大成几次重拉。
 *    显式重试仍留给用户（切开那个标签 → 错误态 → 重试）。
 * 3. **异常在此终结**：预载是后台动作，失败**不得**冒到 UI，也不弹提示——页面各有自己的
 *    错误态与重试。
 */

import { Course } from '../model/course';
import { PREFETCH_FILES, PREFETCH_NOTICES, prefetchTargetsFor } from '../common/prefetch';
import { Logger } from '../common/logger';
import { NoticeStore } from './noticeStore';
import { FileStore } from './fileStore';

const TAG: string = 'startupSync';

export class StartupSync {
  private static instance: StartupSync | null = null;

  static getInstance(): StartupSync {
    if (StartupSync.instance === null) {
      StartupSync.instance = new StartupSync();
    }
    return StartupSync.instance;
  }

  /** 上次发起预载的学期。切换学期后允许再跑一次（下游按签名比对，不会白拉） */
  private startedSemesterId: string = '';

  /**
   * 课程就绪时调用（`Main` 的课程订阅者）。**不返回 Promise**：调用方不需要等它，
   * 预载也不该阻塞 UI。
   */
  run(semesterId: string, courses: Course[]): void {
    const targets: string[] = prefetchTargetsFor(semesterId, courses.length);
    if (targets.length === 0 || semesterId === this.startedSemesterId) {
      return;
    }
    this.startedSemesterId = semesterId;
    Logger.info(TAG, `启动预载开始 学期=${semesterId} 课程数=${courses.length}`
      + ` 目标=[${targets.join(' ')}]`);
    this.runSequentially(semesterId, courses, targets).catch((err: Error) => {
      // 兜底（单个目标内部已各自 try/catch）：预载的任何异常都不冒到 UI
      Logger.warn(TAG, `启动预载异常终止：${err.message}`);
    });
  }

  private async runSequentially(semesterId: string, courses: Course[],
                                targets: string[]): Promise<void> {
    for (const target of targets) {
      try {
        if (target === PREFETCH_NOTICES) {
          await NoticeStore.getInstance().ensureLoadedFor(semesterId, courses);
        } else if (target === PREFETCH_FILES) {
          await FileStore.getInstance().ensureLoadedFor(semesterId, courses);
        }
        Logger.info(TAG, `启动预载完成 目标=${target}`);
      } catch (err) {
        // store 内部已归类进错误态；这里只留痕，不改变用户看到的东西
        Logger.warn(TAG, `启动预载失败 目标=${target}`);
      }
    }
  }
}
