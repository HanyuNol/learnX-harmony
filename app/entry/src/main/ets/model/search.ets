/**
 * 全局搜索的**纯逻辑**：关键词归一化、四类匹配、结果分组。
 *
 * 为什么单独成模块：搜索的判据（"搜哪些字段、大小写、空关键词怎么办"）是**可穷举测试**的
 * 纯函数，而"数据从哪来、点结果去哪"是页面的事。分开后前者能在宿主侧测，
 * 后者只需在真机上点一遍。
 *
 * 搜索范围＝**已经加载到本地的数据**（学堂没有搜索接口，见 search spec §3.1）。
 */

import { Course } from './course';
import { LearnFile } from './file';
import { Notice, plainText } from './notice';
import { Assignment } from './assignment';

/** 结果分组：四类，顺序固定（课程 → 文件 → 通知 → 作业） */
export enum SearchKind {
  COURSE = 'course',
  FILE = 'file',
  NOTICE = 'notice',
  ASSIGNMENT = 'assignment'
}

/** 归一化关键词：去首尾空白 + 小写。空串表示"还没输入" */
export function normalizeQuery(query: string): string {
  return query.trim().toLowerCase();
}

/** 命中判定：大小写不敏感的子串匹配；关键词为空时**一律不命中**（否则等于"全命中"） */
export function matches(haystack: string, normalizedQuery: string): boolean {
  if (normalizedQuery.length === 0) {
    return false;
  }
  return haystack.toLowerCase().includes(normalizedQuery);
}

/** 任一字段命中即算命中（字段为空的不参与） */
function matchesAny(fields: string[], normalizedQuery: string): boolean {
  for (const field of fields) {
    if (matches(field, normalizedQuery)) {
      return true;
    }
  }
  return false;
}

export function searchCourses(items: Course[], query: string): Course[] {
  const q: string = normalizeQuery(query);
  return items.filter((item: Course) => matchesAny(
    [item.name, item.chineseName, item.englishName, item.teacherName], q));
}

export function searchFiles(items: LearnFile[], query: string): LearnFile[] {
  const q: string = normalizeQuery(query);
  return items.filter((item: LearnFile) => matchesAny(
    [item.title, item.description, item.categoryName, item.courseName], q));
}

export function searchNotices(items: Notice[], query: string): Notice[] {
  const q: string = normalizeQuery(query);
  return items.filter((item: Notice) => matchesAny(
    [item.title, plainText(item.content), item.publisher, item.courseName], q));
}

export function searchAssignments(items: Assignment[], query: string): Assignment[] {
  const q: string = normalizeQuery(query);
  return items.filter((item: Assignment) => matchesAny(
    [item.title, plainText(item.description), item.courseName, item.courseTeacherName], q));
}

/** 四段结果 */
export class SearchResults {
  readonly courses: Course[];
  readonly files: LearnFile[];
  readonly notices: Notice[];
  readonly assignments: Assignment[];

  constructor(courses: Course[], files: LearnFile[], notices: Notice[], assignments: Assignment[]) {
    this.courses = courses;
    this.files = files;
    this.notices = notices;
    this.assignments = assignments;
  }

  /** 四段是否都没有命中 */
  isEmpty(): boolean {
    return this.courses.length === 0 && this.files.length === 0
      && this.notices.length === 0 && this.assignments.length === 0;
  }

  /** 命中总数 */
  total(): number {
    return this.courses.length + this.files.length + this.notices.length + this.assignments.length;
  }
}

/**
 * 一次搜索：四类各筛一遍。
 *
 * `courseId` 非空时（课程详情页内的搜索）先按课程收窄——课程本身没有"属于哪门课"这一说，
 * 故该范围内**不返回课程结果**（只有文件/通知/作业三类）。
 */
export function searchAll(courses: Course[], files: LearnFile[], notices: Notice[],
                          assignments: Assignment[], query: string, courseId: string): SearchResults {
  const scoped: boolean = courseId.length > 0;
  const filesInScope: LearnFile[] = scoped
    ? files.filter((item: LearnFile) => item.courseId === courseId) : files;
  const noticesInScope: Notice[] = scoped
    ? notices.filter((item: Notice) => item.courseId === courseId) : notices;
  const assignmentsInScope: Assignment[] = scoped
    ? assignments.filter((item: Assignment) => item.courseId === courseId) : assignments;

  return new SearchResults(
    scoped ? [] : searchCourses(courses, query),
    searchFiles(filesInScope, query),
    searchNotices(noticesInScope, query),
    searchAssignments(assignmentsInScope, query));
}
