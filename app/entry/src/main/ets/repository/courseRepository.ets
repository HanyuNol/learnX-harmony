/**
 * 课程：取数编排。
 *
 * 只做一件事的编排层：把"当前学期"变成"课程列表"。分层上本层才能同时碰网络与系统能力
 * （`LearnClient` 与 `localeAdapter`）；`viewmodel` 不直接碰它们（架构不变量 §1、§3）。
 */

import { Course } from '../model/course';
import { LearnClient } from '../network/learnClient';
import { serverLang } from '../native/localeAdapter';

export class CourseRepository {
  /**
   * 取某学期的课程列表。
   *
   * **学期为空时直接返回空列表、不发请求**：学期还没定就不该猜着查
   * （上游在这一点上漏了守卫，见 courses spec §3.1）。
   */
  static async load(semesterId: string): Promise<Course[]> {
    if (semesterId.length === 0) {
      return [];
    }
    return LearnClient.getInstance().fetchCourses(semesterId, serverLang());
  }
}
