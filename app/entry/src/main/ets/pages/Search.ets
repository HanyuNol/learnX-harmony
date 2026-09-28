/**
 * 搜索页（FR-17）：输入关键词 → 四类结果自上而下预览 → 点一条进详情。
 *
 * 两类范围，**外观上要能一眼区分**（用户要求）：
 * - **全局**（从五个标签页打开）：标题「搜索」，结果含课程/文件/通知/作业四段；
 * - **课程内**（从课程详情页打开）：标题「在《课程名》内搜索」，只有文件/通知/作业三段。
 *
 * 进页即把四类数据**备齐**（`ensureLoadedFor`）：搜索只能在已加载的数据里搜
 * （学堂没有搜索接口），不主动加载的话"没进过文件标签就搜不到文件"，
 * 用户会认为搜索不好用——这与启动时预加载学期/课程是同一类问题。
 *
 * 分层：页面负责输入与渲染，匹配与分组全在 `model/search.ets`；跳转交给 `Main` 提供的回调。
 */

import { Course } from '../model/course';
import { LearnFile, formatUploadDate } from '../model/file';
import { Notice, formatPublishDate, summarize } from '../model/notice';
import { Assignment } from '../model/assignment';
import {
  SearchKind, SearchResults, normalizeQuery, searchAll
} from '../model/search';
import { CourseStore } from '../viewmodel/courseStore';
import { FileStore, FileState } from '../viewmodel/fileStore';
import { NoticeStore, NoticeState } from '../viewmodel/noticeStore';
import { AssignmentStore, AssignmentState } from '../viewmodel/assignmentStore';
import { SemesterStore } from '../viewmodel/semesterStore';
import { TextKeys } from '../common/texts';

/** 搜索页在各栈里的目的地名 */
export const SEARCH_DESTINATION: string = 'search';

/** 每段最多预览的条数（预览页不承担完整列表的职责，见 search spec §3.3 第 4 条） */
const PREVIEW_LIMIT: number = 10;

/** 参数载体：`courseId` 非空即"课程内搜索" */
export class SearchParam {
  readonly courseId: string;
  readonly courseName: string;

  constructor(courseId: string, courseName: string) {
    this.courseId = courseId;
    this.courseName = courseName;
  }
}

@Component
export struct SearchView {
  /** 课程内搜索的范围（空串＝全局搜索） */
  @Prop courseId: string = '';
  @Prop courseName: string = '';
  /** 点结果：`kind` 见 `SearchKind`，由 `Main` 决定推哪个详情页 */
  onOpenResult?: (kind: string, id: string) => void;

  @State private query: string = '';
  /** 结果版本号：store 变化（数据到齐）后据此重算 */
  @State private dataVersion: number = 0;

  private courseStore: CourseStore = CourseStore.getInstance();
  private fileStore: FileStore = FileStore.getInstance();
  private noticeStore: NoticeStore = NoticeStore.getInstance();
  private assignmentStore: AssignmentStore = AssignmentStore.getInstance();
  private semesterStore: SemesterStore = SemesterStore.getInstance();

  aboutToAppear(): void {
    const semester: string = this.semesterStore.snapshot().current;
    const courses: Course[] = this.courseStore.snapshot().items;
    // 四类数据都备齐（各自内部有签名比对，不会白拉）
    this.courseStore.ensureLoadedFor(semester);
    this.noticeStore.ensureLoadedFor(semester, courses);
    this.fileStore.ensureLoadedFor(semester, courses);
    this.assignmentStore.ensureLoadedFor(semester, courses);
    // 数据到齐后要重算结果：订阅四类 store（只更新版本号，结果在 build 里现算）
    this.noticeStore.subscribe(this.noticeListener);
    this.fileStore.subscribe(this.fileListener);
    this.assignmentStore.subscribe(this.assignmentListener);
  }

  aboutToDisappear(): void {
    this.noticeStore.unsubscribe(this.noticeListener);
    this.fileStore.unsubscribe(this.fileListener);
    this.assignmentStore.unsubscribe(this.assignmentListener);
  }

  private noticeListener = (state: NoticeState) => {
    this.dataVersion = state.items.length;
  };
  private fileListener = (state: FileState) => {
    this.dataVersion = state.items.length;
  };
  private assignmentListener = (state: AssignmentState) => {
    this.dataVersion = state.items.length;
  };

  build() {
    Column() {
      // 搜索框
      TextInput({ text: this.query, placeholder: $r('app.string.' + TextKeys.SEARCH_PLACEHOLDER) })
        .width('100%')
        .onChange((value: string) => {
          this.query = value;
        })

      // 范围说明：课程内搜索与全局搜索**外观上可区分**
      if (this.courseId.length > 0) {
        Text($r('app.string.' + TextKeys.SEARCH_SCOPE_COURSE, this.courseName))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .width('100%')
          .padding({ top: 8 })
      }

      if (normalizeQuery(this.query).length === 0) {
        Text($r('app.string.' + TextKeys.SEARCH_HINT))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 16 })
      } else if (this.results().isEmpty()) {
        Text($r('app.string.' + TextKeys.STATE_EMPTY))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 16 })
      } else {
        this.sections(this.results())
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_page'))
  }

  /** 现算结果：`dataVersion` 与 `query` 都是 @State，变化即重算 */
  private results(): SearchResults {
    return searchAll(this.courseStore.snapshot().items, this.fileStore.snapshot().items,
      this.noticeStore.snapshot().items, this.assignmentStore.snapshot().items,
      this.query, this.courseId);
  }

  @Builder
  sections(results: SearchResults) {
    Scroll() {
      Column({ space: 8 }) {
        // 四段**自上而下**：课程 → 文件 → 通知 → 作业（课程内搜索时课程段为空、不显示）
        if (results.courses.length > 0) {
          this.sectionTitle(TextKeys.SEARCH_SECTION_COURSE, results.courses.length)
          ForEach(results.courses.slice(0, PREVIEW_LIMIT), (course: Course) => {
            this.resultRow(course.displayName(), course.teacherName, SearchKind.COURSE, course.id)
          }, (course: Course) => `c:${course.id}`)
        }

        if (results.files.length > 0) {
          this.sectionTitle(TextKeys.SEARCH_SECTION_FILE, results.files.length)
          ForEach(results.files.slice(0, PREVIEW_LIMIT), (file: LearnFile) => {
            this.resultRow(file.title, `${file.courseName} ${formatUploadDate(file.uploadTimeMs)}`,
              SearchKind.FILE, file.id)
          }, (file: LearnFile) => `f:${file.id}`)
        }

        if (results.notices.length > 0) {
          this.sectionTitle(TextKeys.SEARCH_SECTION_NOTICE, results.notices.length)
          ForEach(results.notices.slice(0, PREVIEW_LIMIT), (notice: Notice) => {
            this.resultRow(notice.title, `${notice.courseName} ${summarize(notice.content)}`,
              SearchKind.NOTICE, notice.id)
          }, (notice: Notice) => `n:${notice.id}`)
        }

        if (results.assignments.length > 0) {
          this.sectionTitle(TextKeys.SEARCH_SECTION_ASSIGNMENT, results.assignments.length)
          ForEach(results.assignments.slice(0, PREVIEW_LIMIT), (item: Assignment) => {
            this.resultRow(item.title, `${item.courseName} ${item.summary()}`,
              SearchKind.ASSIGNMENT, item.id)
          }, (item: Assignment) => `a:${item.id}`)
        }
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }

  /**
   * 段标题 + 命中条数。
   *
   * **资源不能与字符串相加**（`$r(...) + '…'` 在运行期会出问题、整页渲染不出来——
   * 2026-09-28 实测：搜索页一片空白），故拆成两个 `Text` 放在一行里。
   */
  @Builder
  sectionTitle(titleKey: string, count: number) {
    Row({ space: 6 }) {
      Text($r('app.string.' + titleKey))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text(`${count}`)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 12, bottom: 4 })
  }

  @Builder
  resultRow(title: string, subtitle: string, kind: string, id: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .width('100%')
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      const open: ((kind: string, id: string) => void) | undefined = this.onOpenResult;
      if (open !== undefined) {
        open(kind, id);
      }
    })
  }
}
