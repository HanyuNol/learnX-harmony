/**
 * 课表取数：注册中心**三步**编排（取工单 → 认证 → 拉 JSONP）。
 *
 * 三步都是不可跳过的：工单只能用一次且绑当前会话，认证跳转把注册中心的会话建立起来，
 * 课表接口才认（上游 `thu-learn-lib/src/index.ts:286-307` 同一顺序）。
 *
 * 失败语义沿用既有口径：非 2xx 由 `LearnClient` 归入
 * 网络不可达 / 认证失效 / 接口语义变更，结构不符由解析层归入"解析失败"，
 * 故这里**不做二次归类**（避免把网络问题误报成应用缺陷，NFR-NET）。
 */

import { CourseSession } from '../model/courseEvent';
import { LearnClient } from '../network/learnClient';
import { ScheduleParseResult, parseScheduleJsonp } from '../network/parseSchedule';
import { Logger } from '../common/logger';

const TAG: string = 'scheduleRepository';

/** 一次课表取数的结果 */
export class ScheduleBatch {
  readonly sessions: CourseSession[];
  /** 服务端给的原始条数（与 `sessions` 的差值＝被跳过的残缺条目，值得记日志） */
  readonly rawCount: number;

  constructor(sessions: CourseSession[], rawCount: number) {
    this.sessions = sessions;
    this.rawCount = rawCount;
  }
}

export class ScheduleRepository {
  /** 取一趟课表（三步）。任一步失败都会抛出**已归一**的错误，由页面按四分类呈现 */
  static async load(startDate: string, endDate: string, graduate: boolean): Promise<ScheduleBatch> {
    const client: LearnClient = LearnClient.getInstance();

    const ticket: string = await client.fetchRegistrarTicket();
    await client.authenticateRegistrar(ticket);
    const body: string = await client.fetchCourseScheduleJsonp(startDate, endDate, graduate);

    const parsed: ScheduleParseResult = parseScheduleJsonp(body);
    if (parsed.rawCount > parsed.sessions.length) {
      Logger.warn(TAG, `课表有 ${parsed.rawCount - parsed.sessions.length} 条因缺字段被跳过`
        + `（原始 ${parsed.rawCount} 条）`);
    }
    Logger.info(TAG, `课表取毕 ${startDate}~${endDate} 研究生=${graduate}`
      + ` 原始=${parsed.rawCount} 可用=${parsed.sessions.length}`);
    return new ScheduleBatch(parsed.sessions, parsed.rawCount);
  }
}
