/**
 * 课程标签的列表页。
 *
 * 数据来自 `viewmodel.courseStore`；**触发时机**是这里订阅 `semesterStore`：
 * 学期一到手（首次加载或切换）就让课程列表与该学期对齐。这样"学期为空不发请求"
 * 这条规则由 store 里的 `ensureLoadedFor` 统一保证，页面不需要自己判断。
 *
 * 分层：本页只订阅状态、下发用户意图（进详情），不碰网络与存储。
 */

import { Course } from '../model/course';
import { CourseState, CourseStateListener, CourseStore } from '../viewmodel/courseStore';
import { SemesterState, SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { FailReason } from '../model/auth';
import { TextKeys } from '../common/texts';
import { emptyView, errorView } from '../components/StateView';
import { SkeletonList } from '../components/Skeleton';

@Component
export struct CourseListTab {
  /** 打开课程详情。由持有课程标签栈的 `Main` 提供——页面不自己造路由栈 */
  onOpenCourse?: (courseId: string) => void;
  /** 打开**全局搜索**（漏传＝点了没反应） */
  onOpenSearch?: () => void;

  @State private fetching: boolean = false;
  @State private courses: Course[] = [];
  @State private errorReason: FailReason | null = null;

  private store: CourseStore = CourseStore.getInstance();
  private semesterStore: SemesterStore = SemesterStore.getInstance();

  private listener: CourseStateListener = (state: CourseState) => {
    this.fetching = state.fetching;
    this.courses = state.items;
    this.errorReason = state.errorReason;
  };

  /** 学期变化即对齐课程（首次加载、切换学期、或学期刚从服务端定下来） */
  private semesterListener: SemesterStateListener = (state: SemesterState) => {
    this.store.ensureLoadedFor(state.current);
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    this.semesterStore.subscribe(this.semesterListener);
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
    this.semesterStore.unsubscribe(this.semesterListener);
  }

  build() {
    Column() {
      // 搜索入口：**可见的文字按钮**（标题栏菜单项在设备上不显示符号，用户实测反馈）
      Row({ space: 8 }) {
        Blank()
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

      if (this.errorReason !== null && this.courses.length === 0) {
        errorView(this.errorReason as FailReason, () => {
          this.store.refresh(this.semesterStore.snapshot().current);
        })
      } else if (this.fetching && this.courses.length === 0) {
        // 列表加载态给骨架（FR-29）：转圈说不出"马上会出现一列内容"
        SkeletonList()
      } else if (this.courses.length === 0) {
        // 注意：这里也可能是"学期未就绪"，不是失败——故呈空态而不是错误态
        emptyView()
      } else {
        List() {
          ForEach(this.courses, (course: Course) => {
            ListItem() {
              this.courseRow(course)
            }
          }, (course: Course) => course.id)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  /** 课程行：课程名 + 教师名（上游卡片还带三个计数徽标，那是三个维度的派生数据，本批不做） */
  @Builder
  courseRow(course: Course) {
    Column({ space: 4 }) {
      Text(course.displayName())
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (course.teacherName.length > 0) {
        Text(course.teacherName)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      const open: ((courseId: string) => void) | undefined = this.onOpenCourse;
      if (open !== undefined) {
        open(course.id);
      }
    })
  }
}
