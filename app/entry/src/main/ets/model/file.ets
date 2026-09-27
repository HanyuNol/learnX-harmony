/**
 * 文件（课件类资料）：类型与**纯逻辑**（排序、摘要、上传日期格式化、文件名与路径清洗）。
 *
 * 与其他 `model` 一样：不 import 上层、不碰系统能力，便于宿主侧穷举测试
 * （文件按课程扇出，真机路径要会话）。
 *
 * 字段语义对齐上游 `thu-learn-lib@4.0.0` 的 `IFile`（`src/types.ts:130-160`）与其映射
 * （`src/index.ts:520-555`）。**只取语义，不移植代码**（ADR-0001）。
 */

import { summarize, formatPublishDate } from './notice';

/** 上传日期 → `YYYY-MM-DD`（与通知同一口径、同一实现，故复用） */
export function formatUploadDate(timestamp: number): string {
  return formatPublishDate(timestamp);
}

export class LearnFile {
  /** 文件记录 id（上游 `kjxxid`） */
  readonly id: string;
  /** 文件本体 id（上游 `wjid`），下载要用它 */
  readonly fileId: string;
  readonly courseId: string;
  readonly courseName: string;
  readonly courseTeacherName: string;
  /** 标题（上游 `bt`，已解 HTML 实体） */
  readonly title: string;
  /** 描述（上游 `ms`，已解 HTML 实体） */
  readonly description: string;
  /** 服务端给的可读大小串（上游 `fileSize`，如 `1.2MB`）——本批直接显示它，不自己算 */
  readonly size: string;
  /** 字节数（上游 `wjdx`），下载与调试用 */
  readonly rawSize: number;
  /** 上传时间**原串**（服务端不做格式化） */
  readonly uploadTime: string;
  /** 上传时间时间戳；`0` 表示解析不出——**不猜** */
  readonly uploadTimeMs: number;
  /** 文件类型/扩展名（上游 `wjlx`，如 `pdf`） */
  readonly fileType: string;
  /** 所属分类名（由 `kjflid` 关联到分类列表；关联不到为空串） */
  readonly categoryName: string;
  /** 是否标记为重要（上游 `sfqd === 1`） */
  readonly markedImportant: boolean;
  /** 是否新文件（上游 `isNew`） */
  readonly isNew: boolean;

  constructor(id: string, fileId: string, courseId: string, courseName: string, courseTeacherName: string,
              title: string, description: string, size: string, rawSize: number,
              uploadTime: string, uploadTimeMs: number, fileType: string, categoryName: string,
              markedImportant: boolean, isNew: boolean) {
    this.id = id;
    this.fileId = fileId;
    this.courseId = courseId;
    this.courseName = courseName;
    this.courseTeacherName = courseTeacherName;
    this.title = title;
    this.description = description;
    this.size = size;
    this.rawSize = rawSize;
    this.uploadTime = uploadTime;
    this.uploadTimeMs = uploadTimeMs;
    this.fileType = fileType;
    this.categoryName = categoryName;
    this.markedImportant = markedImportant;
    this.isNew = isNew;
  }

  /** 列表摘要：描述压成一行（复用通知那套文本工具，同层复用） */
  summary(): string {
    return summarize(this.description);
  }

  /** 列表项的那行元信息：`分类名 类型 大小`（对齐上游 `FileCard`，去空白） */
  metaLine(): string {
    const parts: string[] = [this.categoryName, this.fileType.length > 0 ? this.fileType.toUpperCase() : '', this.size];
    return parts.filter((part: string) => part.length > 0).join(' ');
  }
}

/**
 * 排序：上传时间**倒序**，同一时间按 id 倒序（对齐上游 `actions/files.ts:38-46`）。
 *
 * id 兜底是为了**顺序稳定**——否则同一批数据每次渲染顺序都可能不同，用户会觉得列表在跳。
 */
export function sortFiles(items: LearnFile[]): LearnFile[] {
  const sorted: LearnFile[] = items.slice();
  sorted.sort((left: LearnFile, right: LearnFile): number => {
    if (left.uploadTimeMs !== right.uploadTimeMs) {
      return left.uploadTimeMs > right.uploadTimeMs ? -1 : 1;
    }
    if (left.id === right.id) {
      return 0;
    }
    return left.id > right.id ? -1 : 1;
  });
  return sorted;
}

/**
 * 清洗一个用作**文件名/目录名**的片段。
 *
 * 课件标题里出现 `/`、`\`、`..` 是**服务端数据**，不是攻击者——但任其进入路径会
 * 在沙箱里越级或直接失败。故：路径分隔符与冒号替换成下划线，去掉首尾空白与点，
 * 空结果退让成占位符。
 */
export function sanitizePathSegment(raw: string): string {
  let cleaned: string = '';
  for (let i = 0; i < raw.length; i++) {
    const ch: string = raw.charAt(i);
    if (ch === '/' || ch === '\\' || ch === ':' || ch === '\u0000') {
      cleaned += '_';
    } else {
      cleaned += ch;
    }
  }
  // 首尾的点会造出 `.` / `..` 这类特殊目录名，一并去掉
  const trimmed: string = cleaned.trim().replace(/^\.+/, '').replace(/\.+$/, '').trim();
  return trimmed.length > 0 ? trimmed : 'file';
}

/**
 * 下载文件名：`<课程名>-<标题>.<类型>`（对齐上游 `helpers/fs.ts:55-60`）。
 *
 * 各段都先经 `sanitizePathSegment`；类型为空时**不加后缀**——判空要看**原串**：
 * `sanitizePathSegment('')` 会给出占位符 `file`，用它当扩展名会造出 `.file` 这种假后缀。
 */
export function downloadFileName(courseName: string, title: string, fileType: string): string {
  const course: string = sanitizePathSegment(courseName);
  const name: string = sanitizePathSegment(title);
  if (fileType.trim().length === 0) {
    return `${course}-${name}`;
  }
  return `${course}-${name}.${sanitizePathSegment(fileType)}`;
}

/**
 * "进度未知"的哨兵值。
 *
 * 服务端不给 `Content-Length` 时无法算出百分比，此时必须**什么都不显示**而不是显示 0%
 * （0% 看起来像"卡住了"）或 100%（更糟）。用 `-1` 而不是 `0` 正是为了把两者分开。
 */
export const PROGRESS_UNKNOWN: number = -1;

/**
 * 已收字节 / 总字节 → 0~100 的整数百分比。
 *
 * 总量不明（<= 0）时返回 `PROGRESS_UNKNOWN`；服务端给错（已收多于总量）时上限收到 100，
 * 不产生"104%"这种数字。纯函数，便于穷举测试。
 */
export function percentOf(received: number, total: number): number {
  if (total <= 0 || received < 0) {
    return PROGRESS_UNKNOWN;
  }
  const percent: number = Math.floor((received / total) * 100);
  if (percent < 0) {
    return 0;
  }
  return percent > 100 ? 100 : percent;
}
