/**
 * 通知列表页。
 *
 * 同一组件服务两处（对齐上游：课程详情里内嵌的也是同一套列表）：
 * - 通知标签：聚合**当前学期所有课程**的通知；
 * - 课程详情的"通知"页签：传 `courseId`，只取该课程。
 *
 * 触发时机：订阅 `semesterStore` 与 `courseStore`——学期或课程集一变就让通知与之对齐；
 * 具体"发不发请求"由 `noticeStore` 统一判断（学期/课程为空都不发）。
 *
 * 分层：本页只订阅状态、下发意图，不碰网络与存储。
 */

import { Course } from '../model/course';
import { Notice, NoticeFilter, formatPublishDate, summarize } from '../model/notice';
import { NoticeState, NoticeStateListener, NoticeStore } from '../viewmodel/noticeStore';
import { CourseStateListener, CourseStore } from '../viewmodel/courseStore';
import { SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { FailReason } from '../model/auth';
import { TextKeys } from '../common/texts';
import { FilterChoice, filterBar } from '../components/FilterBar';
import { emptyView, errorView, loadingView } from '../components/StateView';

/** 通知详情在通知栈里的目的地名（`Main` 的 `navDestination` 用它分派） */
export const NOTICE_DETAIL_DESTINATION: string = 'notice-detail';

@Component
export struct NoticeListTab {
  /** 非空时只显示该课程的通知（课程详情的页签用） */
  @Prop courseId: string = '';
  /** 打开**全局搜索**。由持有本栈的 `Main` 提供（漏传＝点了没反应） */
  onOpenSearch?: () => void;
  /** 打开通知详情。由持有通知栈的 `Main` 提供 */
  onOpenNotice?: (noticeId: string) => void;

  @State private fetching: boolean = false;
  @State private items: Notice[] = [];
  /** 筛选是**本视图自己的**状态：两个视图共用一个会让筛选互相串（见 store 注释） */
  @State private filter: NoticeFilter = NoticeFilter.ALL;
  @State private failedCourses: number = 0;
  @State private totalCourses: number = 0;
  @State private errorReason: FailReason | null = null;

  private store: NoticeStore = NoticeStore.getInstance();
  private courseStore: CourseStore = CourseStore.getInstance();
  private semesterStore: SemesterStore = SemesterStore.getInstance();

  private listener: NoticeStateListener = (state: NoticeState) => {
    this.fetching = state.fetching;
    // **赋一个新引用的数组**：`markRead` 只改本地已读覆盖、快照里的 items 仍是同一个数组引用，
    // 若按原引用赋回，@State 不认为是变化 → 列表不重渲染 → 已读标记不消失
    // （2026-09-28 代码审查 🟡 M5；此前的 readVersion 计数器只写不读，同样无效）
    this.items = state.items.slice();
    this.failedCourses = state.failedCourses;
    this.totalCourses = state.totalCourses;
    this.errorReason = state.errorReason;
  };

  /** 学期变化或课程集变化都要让通知对齐（store 内部有签名比对，不会白拉） */
  private coursesListener: CourseStateListener = () => {
    this.alignWithSemester();
  };

  private semesterListener: SemesterStateListener = () => {
    this.alignWithSemester();
  };

  /** 名字不叫 align： 是 ArkUI 内置的组件属性，同名会编译报错 */
  private alignWithSemester(): void {
    this.store.ensureLoadedFor(this.semesterStore.snapshot().current, this.scopedCourses());
  }

  /**
   * 取数范围恒为**当前学期的全部课程**，与本组件是否只展示一门课无关。
   *
   * 为什么不做"只取这一门课"的优化：那样会让本页签与通知标签**抢同一份 store 数据**
   * （后请求的一方把列表换掉，另一处显示成别人的内容——实测踩到的互相混）。
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
          // 取值就是 `NoticeFilter` 的字面量，故可直接放回（筛选状态留在本页）
          this.filter = value === NoticeFilter.UNREAD ? NoticeFilter.UNREAD : NoticeFilter.ALL;
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
        Button($r('app.string.' + TextKeys.NOTICE_REFRESH))
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

      // 部分课程失败：列表仍可用，故用一条提示而不是整页错误态（spec §3.3 第 2 条）
      if (this.failedCourses > 0 && this.totalCourses > 0 && this.failedCourses < this.totalCourses) {
        Text($r('app.string.' + TextKeys.NOTICE_PARTIAL_FAILED))
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
        // 可能没有通知、或本课程没有通知、或学期/课程未就绪——都属空态，不是错误
        // 可能是"学期未就绪""课程为空"或"筛完没有"——都属空态，不是错误
        emptyView()
      } else {
        List() {
          ForEach(this.visible(), (notice: Notice) => {
            ListItem() {
              this.noticeRow(notice)
            }
          }, (notice: Notice) => notice.id)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  /** 本视图要展示的列表：按本组件的课程范围 + 筛选 + 本地已读覆盖 */
  private visible(): Notice[] {
    return this.store.visibleFor(this.courseId, this.filter);
  }

  /** 筛选条选项。用文案键（固定语义的两个选项，中英各一份） */
  private choices(): FilterChoice[] {
    return [
      FilterChoice.ofKey(NoticeFilter.ALL, TextKeys.NOTICE_FILTER_ALL),
      FilterChoice.ofKey(NoticeFilter.UNREAD, TextKeys.NOTICE_FILTER_UNREAD)
    ];
  }

  @Builder
  noticeRow(notice: Notice) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(notice.title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (!this.store.isRead(notice)) {
          Text($r('app.string.' + TextKeys.NOTICE_FILTER_UNREAD))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
        }
      }
      .width('100%')

      Text(summarize(notice.content))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .width('100%')

      Row({ space: 8 }) {
        // 课程名：单课页签下没有信息量，故只在聚合列表里显示
        if (this.courseId.length === 0 && notice.courseName.length > 0) {
          Text(notice.courseName)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        Text(notice.publisher)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(formatPublishDate(notice.publishTime))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      const open: ((noticeId: string) => void) | undefined = this.onOpenNotice;
      if (open !== undefined) {
        open(notice.id);
      }
    })
  }
}
