/**
 * 作业：按课程扇出的编排。
 *
 * 与本项目其他"按课程取"的维度同构：分块并发（每块 ≤ `FANOUT_LIMIT` 门课），
 * 单门课失败不让整体失败。
 *
 * **详情随列表一起预取**（用户 2026-09-27 决定，对齐上游）：点开即见、详情页无加载态。
 * 代价是请求量随作业数增长，故详情取数同样分块限流；详情失败只让该条 `detailLoaded=false`，
 * 不影响它出现在列表里。
 */

import { Course } from '../model/course';
import { Assignment, AssignmentAttachments, sortAssignments } from '../model/assignment';
import { LearnClient } from '../network/learnClient';
import { MultipartFile } from '../network/multipart';
import { Logger } from '../common/logger';

const TAG: string = 'assignmentRepository';

/** 同时在飞的课程数上限（沿用通知那套工程判断，spec §6 已登记） */
const FANOUT_LIMIT: number = 4;
/** 同时在飞的详情请求数上限（每条作业 1 个请求） */
const DETAIL_LIMIT: number = 4;

export class AssignmentBatch {
  /** 已按"未截止在前"排序的作业 */
  readonly items: Assignment[];
  /** 加载失败的课程数（0 表示全部成功） */
  readonly failedCourses: number;
  readonly totalCourses: number;

  constructor(items: Assignment[], failedCourses: number, totalCourses: number) {
    this.items = items;
    this.failedCourses = failedCourses;
    this.totalCourses = totalCourses;
  }
}

/** 单门课的取数结果：`items` 为 null 表示失败 */
class CourseAssignmentResult {
  readonly items: Assignment[] | null;
  readonly course: Course;

  constructor(items: Assignment[] | null, course: Course) {
    this.items = items;
    this.course = course;
  }
}

export class AssignmentRepository {
  /**
   * 取全部课程的作业（含详情），并按"未截止在前"排序。
   *
   * 全部课程失败时**抛出**，交给上层既有错误路径（错误态 + 重试）——通知那次实测踩到
   * "全失败静默成空态"，不重演。
   */
  static async loadAll(courses: Course[], now: number): Promise<AssignmentBatch> {
    const collected: Assignment[] = [];
    let failed: number = 0;

    for (let i = 0; i < courses.length; i += FANOUT_LIMIT) {
      const chunk: Course[] = courses.slice(i, i + FANOUT_LIMIT);
      const settled: Array<CourseAssignmentResult> = await Promise.all(
        chunk.map((course: Course) => AssignmentRepository.loadOneCourse(course)));
      for (const entry of settled) {
        if (entry.items === null) {
          failed++;
          continue;
        }
        for (const item of entry.items) {
          collected.push(item);
        }
      }
    }

    if (courses.length > 0 && failed === courses.length) {
      Logger.warn(TAG, `全部 ${courses.length} 门课程的作业都加载失败，按错误态处理`);
      throw new Error('全部课程的作业都加载失败');
    }

    const withDetail: Assignment[] = await AssignmentRepository.fillDetails(collected);
    const sorted: Assignment[] = sortAssignments(withDetail, now);
    Logger.info(TAG, `作业加载完成 课程数=${courses.length} 失败=${failed} 作业数=${sorted.length}`);
    return new AssignmentBatch(sorted, failed, courses.length);
  }

  /** 单门课：失败返回 `items=null`（不抛，交由上层计失败数） */
  private static async loadOneCourse(course: Course): Promise<CourseAssignmentResult> {
    try {
      const items: Assignment[] = await LearnClient.getInstance()
        .fetchAssignmentsOfCourse(course.id, course.displayName(), course.teacherName);
      return new CourseAssignmentResult(items, course);
    } catch (err) {
      Logger.warn(TAG, `课程作业加载失败 course=${course.id}`);
      return new CourseAssignmentResult(null, course);
    }
  }

  /**
   * 逐条取详情（分块限流）。
   *
   * 详情失败**不丢该条**：返回的仍是列表里那条（`detailLoaded=false`），
   * 进详情页时给"详情未能加载 + 重试"（spec §6）。
   */
  private static async fillDetails(items: Assignment[]): Promise<Assignment[]> {
    const filled: Assignment[] = [];
    for (let i = 0; i < items.length; i += DETAIL_LIMIT) {
      const chunk: Assignment[] = items.slice(i, i + DETAIL_LIMIT);
      const settled: Assignment[] = await Promise.all(
        chunk.map((item: Assignment) => AssignmentRepository.fillOneDetail(item)));
      for (const item of settled) {
        filled.push(item);
      }
    }
    return filled;
  }

  /**
   * 提交作业（含可选附件）。
   *
   * 编排留在这里而不是页面里：网络只能经 `LearnClient`（架构不变量 §3），
   * 页面不得自己拼请求。
   */
  static async submitHomework(xszyid: string, content: string, file: MultipartFile | null,
                              removeAttachment: boolean): Promise<void> {
    await LearnClient.getInstance().submitHomework(xszyid, content, file, removeAttachment);
    Logger.info(TAG, `作业已提交 id=${xszyid} 带附件=${file !== null} 移除附件=${removeAttachment}`);
  }

  /** 单条作业的详情（正文 + 四类附件）。详情页"重试"用；两半都没取到时抛出 */
  static async loadDetail(item: Assignment): Promise<Assignment> {
    const filled: Assignment = await AssignmentRepository.fillOneDetail(item);
    if (!filled.detailLoaded) {
      throw new Error('作业详情未能加载');
    }
    return filled;
  }

  private static async fillOneDetail(item: Assignment): Promise<Assignment> {
    const client: LearnClient = LearnClient.getInstance();
    // 正文与附件在两个端点（JSON detail 的 msg / HTML 详情页的附件块）。
    // 各取各的、各自降级：正文取不到就空着，附件取不到就四类皆空——
    // 任一失败都不该让整条作业从列表里消失。
    // 用"取到了"而不是"内容非空"作判据：正文本来就可能是空的（无描述的作业），
    // 那不是加载失败。
    let description: string = item.description;
    let descriptionOk: boolean = false;
    try {
      description = await client.fetchAssignmentDescription(item.baseId);
      descriptionOk = true;
    } catch (err) {
      Logger.warn(TAG, `作业正文加载失败 id=${item.id}`);
    }

    let attachments: AssignmentAttachments = item.attachments;
    let attachmentsOk: boolean = false;
    try {
      attachments = await client.fetchAssignmentAttachments(item.courseId, item.id);
      attachmentsOk = true;
    } catch (err) {
      Logger.warn(TAG, `作业附件加载失败 id=${item.id}`);
    }

    if (!descriptionOk && !attachmentsOk) {
      // 两半都没拿到：保持 detailLoaded=false，详情页给"详情未能加载 + 重试"
      return item;
    }
    return item.withDetail(description, attachments);
  }
}
