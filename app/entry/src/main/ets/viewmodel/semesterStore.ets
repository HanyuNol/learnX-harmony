/**
 * 学期状态：单一应用级 Store（ADR-0004：ArkUI 原生状态 + 应用级单例 + 观察者订阅）。
 *
 * 形状对齐既有 `authStore`（订阅/快照/反订阅），因为它解决的正是同一类问题：
 * 学期要被多个页面（学期切换页、以及将来各维度的列表页）共享，且必须能跨进程存活。
 *
 * 分工：
 * - `fetching` / `items` / `current` / 错误键是本层的状态；
 * - 取数、决策、落盘都在 `repository` 与 `model`（本层不碰网络与存储，架构不变量 §1）；
 * - **只有列表的失败**才进错误态；当前学期取不到由 repository 降级（见其注释）。
 *
 * 订阅生命周期是本项目已明示的泄漏风险（`testing-and-quality` §2 第 5 项），
 * 故 `listenerCount()` 供页面/测试核对进出平衡。
 */

import { common } from '@kit.AbilityKit';
import { FailReason } from '../model/auth';
import { SemesterSnapshot, SemesterRepository } from '../repository/semesterRepository';
import { normalize } from '../common/errors';
import { TextKeys, textKeyOfFailReason } from '../common/texts';
import { Logger } from '../common/logger';

const TAG: string = 'semesterStore';

/** 对外快照（不可变） */
export class SemesterState {
  readonly fetching: boolean;
  readonly items: string[];
  readonly current: string;
  readonly errorReason: FailReason | null;
  /** 面向用户的错误文案键；无错误时为空串 */
  readonly errorTextKey: string;

  constructor(fetching: boolean, items: string[], current: string,
              errorReason: FailReason | null, errorTextKey: string) {
    this.fetching = fetching;
    this.items = items;
    this.current = current;
    this.errorReason = errorReason;
    this.errorTextKey = errorTextKey;
  }
}

export type SemesterStateListener = (state: SemesterState) => void;

export class SemesterStore {
  private static instance: SemesterStore | null = null;

  static getInstance(): SemesterStore {
    if (SemesterStore.instance === null) {
      SemesterStore.instance = new SemesterStore();
    }
    return SemesterStore.instance;
  }

  private listeners: SemesterStateListener[] = [];
  private fetching: boolean = false;
  private items: string[] = [];
  private current: string = '';
  private errorReason: FailReason | null = null;
  private errorTextKey: string = '';

  subscribe(listener: SemesterStateListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: SemesterStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前订阅者数量。供页面/测试断言无泄漏 */
  listenerCount(): number {
    return this.listeners.length;
  }

  snapshot(): SemesterState {
    return new SemesterState(this.fetching, this.items, this.current,
      this.errorReason, this.errorTextKey);
  }

  /**
   * 已加载过就不重复拉（对齐上游：登录后且列表为空时才拉一次）。
   *
   * 先把已存的当前学期读进来渲染，避免"进页面时选中态空一拍"。
   */
  async ensureLoaded(context: common.Context): Promise<void> {
    if (this.items.length > 0) {
      return;
    }
    const persisted: string = SemesterRepository.readPersisted(context);
    if (persisted.length > 0 && this.current.length === 0) {
      this.current = persisted;
      this.notify();
    }
    await this.refresh(context);
  }

  /** 强制重新拉取。失败进错误态（页面给"重试"），不自动重试——对齐上游 */
  async refresh(context: common.Context): Promise<void> {
    if (this.fetching) {
      return;
    }
    this.fetching = true;
    this.errorReason = null;
    this.errorTextKey = '';
    this.notify();

    try {
      const snapshot: SemesterSnapshot = await SemesterRepository.load(context);
      this.items = snapshot.items;
      this.current = snapshot.current;
      Logger.info(TAG, `学期加载完成 数量=${this.items.length} 当前=${this.current}`);
    } catch (err) {
      const error = normalize(err, '加载学期');
      this.errorReason = error.reason;
      this.errorTextKey = textKeyOfFailReason(error.reason, error.hintKey);
      Logger.warn(TAG, `学期加载失败 reason=${error.reason}`);
    } finally {
      this.fetching = false;
      this.notify();
    }
  }

  /**
   * 切换当前学期：只写本地，**不发服务端请求**（对齐上游）。
   *
   * 落盘失败时不改内存状态——否则界面显示已切换、重启后又变回去，
   * 与"登出失败却谎报成功"是同一类错误（审查 R-02 的教训）。
   */
  async switchTo(context: common.Context, semesterId: string): Promise<void> {
    if (!SemesterRepository.persist(context, semesterId)) {
      Logger.warn(TAG, `学期未能保存 id=${semesterId}`);
      this.errorTextKey = TextKeys.SEMESTER_SWITCH_FAILED;
      this.notify();
      return;
    }
    this.current = semesterId;
    this.errorReason = null;
    this.errorTextKey = '';
    Logger.info(TAG, `当前学期已切换 id=${semesterId}`);
    this.notify();
  }

  private notify(): void {
    const snapshot: SemesterState = this.snapshot();
    // 遍历副本 + 单回调隔离（同 authStore：回调内改订阅数组会跳过或重复回调）
    const current: SemesterStateListener[] = this.listeners.slice();
    for (const listener of current) {
      try {
        listener(snapshot);
      } catch (err) {
        Logger.warn(TAG, '订阅回调抛错，已隔离');
      }
    }
  }
}
