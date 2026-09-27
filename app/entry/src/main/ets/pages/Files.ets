/**
 * 文件列表页。
 *
 * 同一组件服务两处（对齐上游：课程详情里内嵌的也是同一套列表）：
 * - 文件标签：聚合**当前学期所有课程**的文件；
 * - 课程详情的"文件"页签：传 `courseId`，只显示该课程（收窄在展示层做）。
 *
 * 触发与"发不发请求"的规则与通知/作业同构：订阅 `semesterStore` 与 `courseStore`，
 * 具体判断由 `fileStore` 统一做（学期/课程为空都不发）。本批不做筛选（属 FR-12）。
 *
 * 分层：本页只订阅状态、下发意图，不碰网络与存储，也不碰系统能力（下载走 store → repository）。
 */

import { Course } from '../model/course';
import { LearnFile, categoryNamesOf, formatUploadDate } from '../model/file';
import { FileState, FileStateListener, FileStore } from '../viewmodel/fileStore';
import { CourseState, CourseStateListener, CourseStore } from '../viewmodel/courseStore';
import { SemesterState, SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { FailReason } from '../model/auth';
import { TextKeys } from '../common/texts';
import { FILTER_ALL, FilterChoice, allChoice, filterBar } from '../components/FilterBar';
import { emptyView, errorView, loadingView } from '../components/StateView';

/** 文件详情在文件栈里的目的地名（`Main` 的 `navDestination` 用它分派） */
export const FILE_DETAIL_DESTINATION: string = 'file-detail';

@Component
export struct FileListTab {
  /** 非空时只显示该课程的文件（课程详情的页签用） */
  @Prop courseId: string = '';
  /** 打开文件详情。由持有文件栈的 `Main` 提供 */
  onOpenFile?: (fileId: string) => void;

  @State private fetching: boolean = false;
  @State private items: LearnFile[] = [];
  @State private failedCourses: number = 0;
  @State private totalCourses: number = 0;
  @State private errorReason: FailReason | null = null;
  /** 分类筛选是**本视图自己的**状态（'全部' 时为 `FILTER_ALL`，见 list-filter-sort spec §3.3） */
  @State private category: string = FILTER_ALL;
  /** 本范围内实际出现过的分类名（@State：筛选条的显隐与选项都由它决定） */
  @State private categories: string[] = [];

  private store: FileStore = FileStore.getInstance();
  private courseStore: CourseStore = CourseStore.getInstance();
  private semesterStore: SemesterStore = SemesterStore.getInstance();

  private listener: FileStateListener = (state: FileState) => {
    this.fetching = state.fetching;
    this.items = state.items;
    this.failedCourses = state.failedCourses;
    this.totalCourses = state.totalCourses;
    this.errorReason = state.errorReason;
    // 分类名也放进 **@State**：筛选条的显示与否取决于它，而决定 `if` 分支要不要重算的
    // 是**条件里读到的状态变量**——条件若只读 store（非状态），数据到达后分支不会重算，
    // 筛选条就会一直不出现（2026-09-28 真机实测，见 OPERATIONS.md §7）
    const scoped: LearnFile[] = this.courseId.length === 0
      ? state.items
      : state.items.filter((item: LearnFile) => item.courseId === this.courseId);
    this.categories = categoryNamesOf(scoped);
  };

  private coursesListener: CourseStateListener = () => {
    this.alignWithSemester();
  };

  private semesterListener: SemesterStateListener = () => {
    this.alignWithSemester();
  };

  /** 名字不叫 align：那是 ArkUI 内置的组件属性，同名会编译报错 */
  private alignWithSemester(): void {
    this.store.ensureLoadedFor(this.semesterStore.snapshot().current, this.scopedCourses());
  }

  /** 取数范围恒为当前学期全部课程；课程范围的收窄在展示层（`visibleFor`） */
  private scopedCourses(): Course[] {
    return this.courseStore.snapshot().items;
  }

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    this.courseStore.subscribe(this.coursesListener);
    this.semesterStore.subscribe(this.semesterListener);
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
    this.courseStore.unsubscribe(this.coursesListener);
    this.semesterStore.unsubscribe(this.semesterListener);
  }

  build() {
    Column() {
      // 分类筛选（FR-12）：选项来自**实际出现过的**分类，故随数据变化
      if (this.choices().length > 1) {
        filterBar(this.choices(), this.category, (value: string) => {
          this.category = value;
        })
      }

      Row({ space: 8 }) {
        Blank()
        Button($r('app.string.' + TextKeys.FILE_REFRESH))
          .fontSize(14)
          .onClick(() => {
            this.store.refresh(this.semesterStore.snapshot().current, this.scopedCourses());
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.failedCourses > 0 && this.totalCourses > 0 && this.failedCourses < this.totalCourses) {
        Text($r('app.string.' + TextKeys.FILE_PARTIAL_FAILED))
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding(8)
      }

      if (this.errorReason !== null && this.items.length === 0) {
        errorView(this.errorReason as FailReason, () => {
          this.store.refresh(this.semesterStore.snapshot().current, this.scopedCourses());
        })
      } else if (this.fetching && this.items.length === 0) {
        loadingView()
      } else if (this.visible().length === 0) {
        // 可能没有文件、或本课程没有文件、或学期/课程未就绪——都属空态，不是错误
        emptyView()
      } else {
        List() {
          ForEach(this.visible(), (file: LearnFile) => {
            ListItem() {
              this.fileRow(file)
            }
          }, (file: LearnFile) => file.id)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  private visible(): LearnFile[] {
    return this.store.visibleFor(this.courseId, this.category);
  }

  /** 筛选条的选项："全部" + 本范围内的分类名（无分类时不显示筛选条） */
  private choices(): FilterChoice[] {
    const options: FilterChoice[] = [allChoice()];
    for (const name of this.categories) {
      options.push(FilterChoice.ofText(name, name));
    }
    return options;
  }

  @Builder
  fileRow(file: LearnFile) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(file.title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        // 标记用**文字**：图标不进 UI 节点树，无法验收（陷阱 7）
        if (file.markedImportant) {
          Text($r('app.string.' + TextKeys.FILE_IMPORTANT))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
        }
        if (file.isNew) {
          Text($r('app.string.' + TextKeys.FILE_NEW))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
        }
      }
      .width('100%')

      if (file.summary().length > 0) {
        Text(file.summary())
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .width('100%')
      }

      Row({ space: 8 }) {
        // 课程名：单课页签下没有信息量，故只在聚合列表里显示
        if (this.courseId.length === 0 && file.courseName.length > 0) {
          Text(file.courseName)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        Text(file.metaLine())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(formatUploadDate(file.uploadTimeMs))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      const open: ((fileId: string) => void) | undefined = this.onOpenFile;
      if (open !== undefined) {
        open(file.id);
      }
    })
  }
}
