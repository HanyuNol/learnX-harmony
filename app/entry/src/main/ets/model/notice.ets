/**
 * 通知类型与**纯逻辑**（排序、摘要、未读筛选）。
 *
 * 与本项目其他 `model` 一样：不 import 上层、不碰系统能力，便于宿主侧穷举测试
 * （通知按课程扇出，真机路径要会话）。
 *
 * 字段语义对齐上游 `thu-learn-lib@4.0.0` 的 `INotification`（`src/types.ts:102-120`）与其映射
 * （`src/index.ts:479-497`）。
 */

/** 摘要长度上限（字符数，不是字节——中文不能被切成半个字） */
const SUMMARY_LIMIT: number = 80;

/** 通知筛选选项。本批只做通知维度（通用筛选框架属 FR-12） */
export enum NoticeFilter {
  ALL = 'all',
  UNREAD = 'unread'
}

export class Notice {
  /** 通知 id（上游 `ggid`） */
  readonly id: string;
  /** 所属课程 id。上游接口不返回它，由扇出时注入 */
  readonly courseId: string;
  /** 课程名。同样由本项目回填（上游用 `courses.names` 填） */
  readonly courseName: string;
  /** 标题（上游 `bt`，已解 HTML 实体） */
  readonly title: string;
  /** 正文（上游 `ggnr`，Base64 解出的原始 HTML。展示前经 `summarize` 或纯文本化） */
  readonly content: string;
  /** 是否已读（上游 `sfyd === '是'`）。**只读服务端字段**，本地不自行判定 */
  readonly hasRead: boolean;
  /** 是否标记为重要（上游 `zd`） */
  readonly markedImportant: boolean;
  /** 发布时间（毫秒时间戳；取不到为 0） */
  readonly publishTime: number;
  /** 发布者（上游 `fbrxm`） */
  readonly publisher: string;
  /** 详情页 URL。打开详情时用它发一次"已读"请求 */
  readonly url: string;
  /** 附件名（上游 `fjmc`/`fjbt`）。无附件为空串 */
  readonly attachmentName: string;

  constructor(id: string, courseId: string, courseName: string, title: string, content: string,
              hasRead: boolean, markedImportant: boolean, publishTime: number, publisher: string,
              url: string, attachmentName: string) {
    this.id = id;
    this.courseId = courseId;
    this.courseName = courseName;
    this.title = title;
    this.content = content;
    this.hasRead = hasRead;
    this.markedImportant = markedImportant;
    this.publishTime = publishTime;
    this.publisher = publisher;
    this.url = url;
    this.attachmentName = attachmentName;
  }
}

/**
 * 排序：发布时间倒序，同一时间按 id 倒序（对齐上游 `actions/notices.ts:38-45`）。
 *
 * 时间相同时用 id 兜底，是为了**顺序稳定**——否则同一批数据每次渲染顺序都可能不同，
 * 用户会觉得列表在跳。
 */
export function sortNotices(items: Notice[]): Notice[] {
  const sorted: Notice[] = items.slice();
  sorted.sort((left: Notice, right: Notice): number => {
    if (left.publishTime !== right.publishTime) {
      return left.publishTime > right.publishTime ? -1 : 1;
    }
    if (left.id === right.id) {
      return 0;
    }
    return left.id > right.id ? -1 : 1;
  });
  return sorted;
}

/**
 * 把正文的 HTML 标签去掉，得到**可读纯文本**（保留换行，供详情页用）。
 *
 * 本批不做富文本渲染（属 FR-22），故详情页直接把正文当纯文本看。这也更安全：
 * SECURITY §3 要求"按白名单清洗、不得整体信任服务端 HTML"，那件事在 FR-22 一并做——
 * 现在更不该把未清洗的 HTML 塞进 WebView。
 */
export function plainText(content: string): string {
  let text: string = '';
  let inTag: boolean = false;
  for (let i = 0; i < content.length; i++) {
    const ch: string = content.charAt(i);
    if (ch === '<') {
      inTag = true;
    } else if (ch === '>') {
      inTag = false;
    } else if (!inTag) {
      text += ch;
    }
  }
  return text;
}

/**
 * 发布时间 → `YYYY-MM-DD`。
 *
 * 用绝对日期而不是"3 天前"：相对时间要先确认可用的格式化能力（notices spec §6 待定项），
 * 而绝对日期是纯函数、可测、也不会有'i18n'上的坑。时间戳为 0（拿不到时间）时返回空串，
 * 由界面决定不显示——**不猜时间**。
 */
export function formatPublishDate(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const date: Date = new Date(timestamp);
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  const mm: string = month < 10 ? `0${month}` : `${month}`;
  const dd: string = day < 10 ? `0${day}` : `${day}`;
  return `${date.getFullYear()}-${mm}-${dd}`;
}

/**
 * 把正文压成一行摘要：去标签、压缩空白、截断。
 *
 * 这里**不**复用 `network/parse.stripTags`：`model` 不得 import 上层（架构不变量 §1）。
 * 两者职责也不同——那边的 `stripTags` 服务于抓取解析，这里的目的是"给列表看的一行"。
 */
export function summarize(content: string): string {
  const text: string = plainText(content);

  // 压缩所有空白（含换行与全角空格）为单个半角空格
  let collapsed: string = '';
  let lastWasSpace: boolean = false;
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    const isSpace: boolean = ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\u3000';
    if (isSpace) {
      if (!lastWasSpace && collapsed.length > 0) {
        collapsed += ' ';
      }
      lastWasSpace = true;
    } else {
      collapsed += ch;
      lastWasSpace = false;
    }
  }
  const trimmed: string = collapsed.trim();
  return trimmed.length > SUMMARY_LIMIT ? `${trimmed.substring(0, SUMMARY_LIMIT)}…` : trimmed;
}

/**
 * 未读筛选。`ALL` 原样返回（不复制，调用方不改数组）。
 *
 * `readOverrides` 是**本地已读覆盖**（打开过详情的那些通知，见 notices spec §3.3 第 7 条）：
 * 服务端的 `hasRead` 要等下次刷新才更新，本地先记着，用户才不会觉得"点了没反应"。
 * 判据放在这里而不是页面里，是为了可穷举测试。
 */
export function filterNotices(items: Notice[], filter: NoticeFilter, readOverrides: string[] = []): Notice[] {
  if (filter === NoticeFilter.UNREAD) {
    return items.filter((item: Notice) => !item.hasRead && !readOverrides.includes(item.id));
  }
  return items;
}

/** 按课程扇出后的合并结果 */
export class NoticeBatch {
  /** 已按发布时间倒序的通知 */
  readonly items: Notice[];
  /** 加载失败的课程数（0 表示全部成功） */
  readonly failedCourses: number;
  /** 参与扇出的课程总数 */
  readonly totalCourses: number;

  constructor(items: Notice[], failedCourses: number, totalCourses: number) {
    this.items = items;
    this.failedCourses = failedCourses;
    this.totalCourses = totalCourses;
  }
}

/**
 * 合并"每门课的结果或失败"。
 *
 * **部分失败不整页失败**（notices spec §3.3 第 2 条，本项目刻意不照抄上游的 Promise.all）：
 * 上游只要有一门课失败就整体失败、整页空白；这里保留拿到的通知，只记下失败课程数，
 * 由页面用一条提示告诉用户"有几门课没取到"。**全部失败也仍然返回空列表而不是抛错**——
 * 是否呈现为错误态由调用方按 `failedCourses === totalCourses` 判断。
 *
 * `null` 表示该课程失败。
 */
export function mergeNoticeBatches(batches: Array<Notice[] | null>): NoticeBatch {
  const merged: Notice[] = [];
  let failed: number = 0;
  for (const batch of batches) {
    if (batch === null) {
      failed++;
      continue;
    }
    for (const notice of batch) {
      merged.push(notice);
    }
  }
  return new NoticeBatch(sortNotices(merged), failed, batches.length);
}
