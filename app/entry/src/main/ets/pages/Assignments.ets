/**
 * 作业列表页。
 *
 * 同一组件服务两处（对齐上游：课程详情里内嵌的也是同一套列表）：
 * - 作业标签：聚合**当前学期所有课程**的作业；
 * - 课程详情的"作业"页签：传 `courseId`，只显示该课程（收窄在展示层做）。
 *
 * 触发时机与通知同构：订阅 `semesterStore` 与 `courseStore`，学期或课程集一变就让作业与之对齐；
 * "发不发请求"由 `assignmentStore` 统一判断（学期/课程为空都不发）。
 *
 * 分层：本页只订阅状态、下发意图，不碰网络与存储。
 */

import { Course } from '../model/course';
import {
  Assignment, AssignmentFilter, RelativeDeadline, relativeDeadlineOf
} from '../model/assignment';
import { AssignmentState, AssignmentStateListener, AssignmentStore } from '../viewmodel/assignmentStore';
import { CourseStateListener, CourseStore } from '../viewmodel/courseStore';
import { SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { requestAssignmentReminderSync } from '../viewmodel/reminderSync';
import { applicationContextOf } from '../native/contextAdapter';
import { common } from '@kit.AbilityKit';
import { FailReason } from '../model/auth';
import { TextKeys, textKeyOfRelativeDeadline } from '../common/texts';
import { FilterChoice, filterBar } from '../components/FilterBar';
import { emptyView, errorView, loadingView } from '../components/StateView';

/** 作业详情在作业栈里的目的地名（`Main` 的 `navDestination` 用它分派） */
export const ASSIGNMENT_DETAIL_DESTINATION: string = 'assignment-detail';

@Component
export struct AssignmentListTab {
  /** 非空时只显示该课程的作业（课程详情的页签用） */
  @Prop courseId: string = '';
  /** 打开**全局搜索**。由持有本栈的 `Main` 提供（漏传＝点了没反应） */
  onOpenSearch?: () => void;
  /** 打开作业详情。由持有作业栈的 `Main` 提供 */
  onOpenAssignment?: (assignmentId: string) => void;

  @State private fetching: boolean = false;
  @State private items: Assignment[] = [];
  /** 筛选是**本视图自己的**状态：两个视图共用一个会让筛选互相串（通知那次实测踩到） */
  @State private filter: AssignmentFilter = AssignmentFilter.UNFINISHED;
  @State private failedCourses: number = 0;
  @State private totalCourses: number = 0;
  @State private errorReason: FailReason | null = null;

  private store: AssignmentStore = AssignmentStore.getInstance();
  private courseStore: CourseStore = CourseStore.getInstance();
  private semesterStore: SemesterStore = SemesterStore.getInstance();

  /** 上一次通知时是否处于"取数在途"——用来认出"一次加载刚刚结束"（见 `alignRemindersAfterLoad`） */
  private wasFetching: boolean = false;

  private listener: AssignmentStateListener = (state: AssignmentState) => {
    this.fetching = state.fetching;
    this.items = state.items;
    this.failedCourses = state.failedCourses;
    this.totalCourses = state.totalCourses;
    this.errorReason = state.errorReason;
    this.alignRemindersAfterLoad(state);
  };

  /** 偏好读写一律走应用级上下文；原因见 `native/contextAdapter.ets` */
  private appContext(): common.ApplicationContext {
    return applicationContextOf(this.getUIContext().getHostContext() as common.Context);
  }

  /**
   * 一次加载**结束**时顺手对齐系统提醒（FR-18）。
   *
   * 判据取"`fetching` 由真转假"，而不是"每次通知都对一次"：通知在刷新开始 / 结束 / 提交后
   * 重拉 / 补详情时都会发，每次都对齐等于把系统调用绑到渲染节奏上。对齐本身很便宜
   * （读一次现有提醒、算差量、无变化就什么也不做），但它该由"数据落地"决定，不由 UI 事件频率决定。
   *
   * 失败与空数据不触发：错误态下同一批作业还会再拉一次，等那次成功再对齐（对齐是幂等的）。
   */
  private alignRemindersAfterLoad(state: AssignmentState): void {
    const finished: boolean = this.wasFetching && !state.fetching;
    this.wasFetching = state.fetching;
    if (!finished || state.errorReason !== null || state.items.length === 0) {
      return;
    }
    // "完整"=当前学期**每门课**都取到了（totalCourses 是本次请求的课程数）。
    // 部分课程失败时传 false：对齐会一条也不动，宁可这份数据晚点生效，
    // 也不能因为一次部分失败就把用户已登记的提醒撤掉。
    const complete: boolean = state.totalCourses > 0 && state.failedCourses === 0;
    requestAssignmentReminderSync(this.appContext(), state.items, complete);
  }

  /** 学期变化或课程集变化都要让作业对齐（store 内部有签名比对，不会白拉） */
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

  /**
   * 取数范围恒为**当前学期的全部课程**，与本组件是否只展示一门课无关。
   *
   * 为什么不做"只取这一门课"的优化：那会让本页签与作业标签**抢同一份 store 数据**
   * （后请求的一方把列表换掉，另一处显示成别人的内容——通知那处实测踩到互相混）。
   * 课程范围的收窄放在展示层（`visibleFor`）。
   */
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
      filterBar({
        choices: this.choices(),
        selected: this.filter,
        onSelect: (value: string) => {
          // 取值就是 `AssignmentFilter` 的字面量，故可直接放回（筛选状态留在本页）
          this.filter = value === AssignmentFilter.FINISHED
            ? AssignmentFilter.FINISHED : AssignmentFilter.UNFINISHED;
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
        Button($r('app.string.' + TextKeys.ASSIGNMENT_REFRESH))
          .fontSize(14)
          .onClick(() => {
            this.store.refresh(this.semesterStore.snapshot().current, this.scopedCourses());
          })
        Button() {
          Image($r('app.media.ic_search'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_primary'))
        }
        .backgroundColor(Color.Transparent)
        .padding(4)
        .onClick(() => {
          const open: (() => void) | undefined = this.onOpenSearch;
          if (open !== undefined) {
            open();
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      // 部分课程失败：列表仍可用，故用一条提示而不是整页错误态（spec §3.3 第 7 条）
      if (this.failedCourses > 0 && this.totalCourses > 0 && this.failedCourses < this.totalCourses) {
        Text($r('app.string.' + TextKeys.ASSIGNMENT_PARTIAL_FAILED))
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
        // 可能没有作业、或本课程没有作业、或学期/课程未就绪、或筛完没有——都属空态，不是错误
        emptyView()
      } else {
        List() {
          ForEach(this.visible(), (assignment: Assignment) => {
            ListItem() {
              this.assignmentRow(assignment)
            }
          }, (assignment: Assignment) => assignment.id)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  /** 本视图要展示的列表：按本组件的课程范围 + 筛选，并按当前时间重排 */
  private visible(): Assignment[] {
    return this.store.visibleFor(this.courseId, this.filter, Date.now());
  }

  /** 筛选条选项。用文案键（固定语义的两个选项，中英各一份） */
  private choices(): FilterChoice[] {
    return [
      FilterChoice.ofKey(AssignmentFilter.UNFINISHED, TextKeys.ASSIGNMENT_FILTER_UNFINISHED),
      FilterChoice.ofKey(AssignmentFilter.FINISHED, TextKeys.ASSIGNMENT_FILTER_FINISHED)
    ];
  }

  @Builder
  assignmentRow(assignment: Assignment) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(assignment.title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        // 完成/评分标记用**文字**：SymbolGlyph 不进 UI 节点树，图标无法验收（陷阱 7）
        if (assignment.graded) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_GRADED))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
        } else if (assignment.submitted) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_SUBMITTED))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
        }
      }
      .width('100%')

      if (assignment.summary().length > 0) {
        Text(assignment.summary())
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .width('100%')
      }

      Row({ space: 8 }) {
        // 课程名：单课页签下没有信息量，故只在聚合列表里显示
        if (this.courseId.length === 0 && assignment.courseName.length > 0) {
          Text(assignment.courseName)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        Text(assignment.courseTeacherName)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        this.deadlineText(assignment)
        if (assignment.attachments.hasAny()) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_ATTACHMENT))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      const open: ((assignmentId: string) => void) | undefined = this.onOpenAssignment;
      if (open !== undefined) {
        open(assignment.id);
      }
    })
  }

  /**
   * 截止时间文案：相对描述（上游列表就是这个口径："还剩 3 天"/"3 天前截止"）。
   *
   * 解析不出时间时不显示任何东西——**不猜**。已截止用危险色，与未截止一眼分开。
   */
  @Builder
  deadlineText(assignment: Assignment) {
    if (assignment.deadlineTime > 0) {
      Text($r('app.string.' + relativeKeyOf(assignment), relativeValueOf(assignment)))
        .fontSize(12)
        .fontColor(assignment.deadlineTime < Date.now()
          ? $r('app.color.danger') : $r('app.color.text_secondary'))
    }
  }
}

/** 相对描述的资源键（`model` 不持有文案，映射集中在 `common/texts.ets`） */
function relativeKeyOf(assignment: Assignment): string {
  const relative: RelativeDeadline | null = relativeDeadlineOf(assignment.deadlineTime, Date.now());
  if (relative === null) {
    return TextKeys.NONE;
  }
  return textKeyOfRelativeDeadline(relative);
}

/** 相对描述里的数量 */
function relativeValueOf(assignment: Assignment): number {
  const relative: RelativeDeadline | null = relativeDeadlineOf(assignment.deadlineTime, Date.now());
  return relative === null ? 0 : relative.value;
}
