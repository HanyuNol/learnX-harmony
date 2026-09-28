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
import {
  FileReadFilter, FileRow, LearnFile, UNCATEGORIZED_MARKER, buildFileRows, formatUploadDate
} from '../model/file';
import { FileState, FileStateListener, FileStore } from '../viewmodel/fileStore';
import { CourseStateListener, CourseStore } from '../viewmodel/courseStore';
import { SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { FailReason } from '../model/auth';
import { TextKeys } from '../common/texts';
import { FilterChoice, filterBar } from '../components/FilterBar';
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
  /**
   * 已读/未读筛选是**本视图自己的**状态（见 list-filter-sort spec §3.3）。
   * 默认"全部"：文件不像作业有"该做的/做完的"之分，默认全看更符合预期。
   */
  @State private readFilter: FileReadFilter = FileReadFilter.ALL;

  private store: FileStore = FileStore.getInstance();
  private courseStore: CourseStore = CourseStore.getInstance();
  private semesterStore: SemesterStore = SemesterStore.getInstance();

  private listener: FileStateListener = (state: FileState) => {
    this.fetching = state.fetching;
    this.items = state.items;
    this.failedCourses = state.failedCourses;
    this.totalCourses = state.totalCourses;
    this.errorReason = state.errorReason;
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
      // 已读/未读筛选：固定在顶部（不依赖数据，故不必等加载完才出现）
      filterBar({
        choices: this.choices(),
        selected: this.readFilter,
        onSelect: (value: string) => {
          this.readFilter = value === FileReadFilter.UNREAD ? FileReadFilter.UNREAD
            : (value === FileReadFilter.READ ? FileReadFilter.READ : FileReadFilter.ALL);
        }
      })

      Row({ space: 8 }) {
        Blank()
        // 让"点了刷新"有可见反馈：在途时给一行文字（数据没变时界面本来就看不出差别）
        if (this.fetching) {
          Text($r('app.string.' + TextKeys.LIST_REFRESHING))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
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
          // **课程详情页按分类分组**（一门课里的分类才有意义），聚合页平铺
          // （跨课程时分类名看不出属于哪门课，见 list-filter-sort spec §3.3 第 4 条）
          ForEach(this.rows(), (row: FileRow) => {
            ListItem() {
              if (row.header.length > 0) {
                this.groupHeader(row.header)
              } else {
                this.fileRow(row.file as LearnFile)
              }
            }
          }, (row: FileRow) => row.header.length > 0 ? `h:${row.header}` : `f:${(row.file as LearnFile).id}`)
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
    return this.store.visibleFor(this.courseId, this.readFilter);
  }

  /** 列表要渲染的行：课程详情页分组、聚合页平铺（分组与否由是否有 courseId 决定） */
  private rows(): FileRow[] {
    return buildFileRows(this.visible(), this.courseId.length > 0);
  }

  /** 筛选条：全部 / 未读 / 已读（未读＝服务端的"新文件"标记，与上游一致） */
  private choices(): FilterChoice[] {
    return [
      FilterChoice.ofKey(FileReadFilter.ALL, TextKeys.FILTER_ALL),
      FilterChoice.ofKey(FileReadFilter.UNREAD, TextKeys.FILE_FILTER_UNREAD),
      FilterChoice.ofKey(FileReadFilter.READ, TextKeys.FILE_FILTER_READ)
    ];
  }

  /** 分组标题行（课程详情页的文件列表用）。分类名是服务端数据，故走字面量分支 */
  @Builder
  groupHeader(category: string) {
    if (category === UNCATEGORIZED_MARKER) {
      Text($r('app.string.' + TextKeys.FILE_CATEGORY_NONE))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })
    } else {
      Text(category)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })
    }
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
