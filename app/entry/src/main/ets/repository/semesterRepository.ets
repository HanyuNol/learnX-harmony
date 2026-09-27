/**
 * 学期：取数、决策、持久化的编排。
 *
 * 分层：本层（repository）才能同时碰网络（`network.LearnClient`）与存储
 * （`storage.preferenceStore`）；`viewmodel` 不直接碰它们，`pages` 更不碰
 * （架构不变量 §1、§3）。
 */

import { common } from '@kit.AbilityKit';
import { LearnClient } from '../network/learnClient';
import { readCurrentSemester, writeCurrentSemester } from '../storage/preferenceStore';
import { decideCurrentSemester, sortSemesterIds } from '../model/semester';
import { Logger } from '../common/logger';

const TAG: string = 'semesterRepository';

/** 一次加载的结果：已排序的学期列表 + 决策后的当前学期 */
export class SemesterSnapshot {
  /** 学期 id，最新在前 */
  readonly items: string[];
  /** 当前学期 id；空串表示"还没定过"（下游据此不发请求） */
  readonly current: string;

  constructor(items: string[], current: string) {
    this.items = items;
    this.current = current;
  }
}

export class SemesterRepository {
  /**
   * 拉学期列表与服务端当前学期，决定"当前学期"，并把新定下来的当前学期落盘。
   *
   * **只有列表失败才算加载失败**：当前学期取不到时降级为"沿用已存值"，不让整页报错——
   * 上游也把这两个请求当两个独立动作（各自的失败互不阻塞）。列表是页面要展示的主体，
   * 它拿不到才该呈现错误态。
   */
  static async load(context: common.Context): Promise<SemesterSnapshot> {
    const client: LearnClient = LearnClient.getInstance();

    const ids: string[] = await client.fetchSemesterIds();

    const persisted: string = readCurrentSemester(context);
    let serverCurrent: string = '';
    try {
      serverCurrent = await client.fetchCurrentSemesterId();
    } catch (err) {
      // 降级：不影响列表展示与已存选择；刷新可再试
      Logger.warn(TAG, '未能取得服务端当前学期，沿用已存值');
    }

    const current: string = decideCurrentSemester(persisted, serverCurrent);
    if (current.length > 0 && current !== persisted) {
      // 落盘失败不影响本次展示，但会记 WARN——下次启动会回到"未设置"
      if (!writeCurrentSemester(context, current)) {
        Logger.warn(TAG, `当前学期未能落盘 id=${current}`);
      }
    }

    return new SemesterSnapshot(sortSemesterIds(ids), current);
  }

  /** 只读取本地已存的当前学期（不联网）。页面先据此渲染选中态 */
  static readPersisted(context: common.Context): string {
    return readCurrentSemester(context);
  }

  /** 切换当前学期：只写本地（对齐上游，无服务端调用）。返回是否落盘成功 */
  static persist(context: common.Context, semesterId: string): boolean {
    return writeCurrentSemester(context, semesterId);
  }
}
