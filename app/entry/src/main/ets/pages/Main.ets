/**
 * 登录后的主界面：底部五个标签，**每个标签一个独立的页面栈**。
 *
 * 结构对齐上游（`src/App.tsx`）：五个「根栈 + 底部标签」组合，切标签不丢栈。
 * 是否可行已在 T0 用最小脚手架实测（`docs/specs/ui-shell.md` §4）：
 * 切标签往返仍停在原详情页、系统返回键由当前可见的栈消费。
 *
 * 分层：本页只做 UI 与交互，不发请求、不读写存储、不调系统能力（架构不变量 §1）。
 *
 * 返回键行为对齐上游 `@bottom-tabs` 的默认值 `backBehavior: 'firstRoute'`
 * （上游源码未显式设置该选项）：当前栈非空时由该栈弹出；栈为空且不在第一个标签时
 * 回到第一个标签；在第一个标签且栈为空时交给系统（与本项目此前行为一致）。
 * 前半段由 NavDestination 自身处理，后两段由 `Index` 的 `onBackPress` 处理。
 */

import { TextKeys } from '../common/texts';
import { FailReason } from '../model/auth';
import { emptyView, errorView, loadingView } from '../components/StateView';
import { showToast } from '../components/toast';
import { SettingsView } from './Settings';
import { SEMESTER_DESTINATION, SemesterSelectionView } from './SemesterSelection';
import { CourseListTab } from './Courses';
import { NOTICE_DETAIL_DESTINATION, NoticeListTab } from './Notices';
import { NoticeDetailParam, NoticeDetailView } from './NoticeDetail';
import { COURSE_DETAIL_DESTINATION, CourseDetailParam, CourseDetailView } from './CourseDetail';
import { SemesterState, SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { CourseStore } from '../viewmodel/courseStore';
import { applicationContextOf } from '../native/contextAdapter';
import { common } from '@kit.AbilityKit';

@Component
export struct MainView {
  /** 当前标签索引。由 `Index` 持有：返回键逻辑在页面级（`onBackPress`） */
  @Link currentTabIndex: number;
  /** 需要展示的错误文案键（如"登出未完成"）；为空则不显示 */
  @Prop errorKey: string;

  private semesterStore: SemesterStore = SemesterStore.getInstance();

  /**
   * 登录后**立刻把学期准备好**——学期是课程与三个内容维度的共同前提。
   *
   * 为什么放在这里而不是各页自己拉：学期为空时那些页面按规则**不发请求**
   * （见 semester / courses spec）。实测踩到过：不在启动时加载，课程页只会显示
   * "暂无内容"，用户得先去设置里打开一次"学期切换"才会好——那是把内部依赖
   * 暴露成了用户操作。
   */
  private courseStore: CourseStore = CourseStore.getInstance();

  /**
   * 学期就绪后**顺带把课程也拉起来**。
   *
   * 为什么放在这里：通知是**按课程扇出**的，课程列表为空时通知一条都取不到。
   * 而课程原先只在用户打开"课程"标签时才加载——实测踩到：登录后直接看通知标签，
   * 只见"暂无内容"，得先去点一下课程标签才会好。跟学期那次是同一类缺口
   * （把内部依赖暴露成了用户操作），所以两者都在 shell 这一层准备好。
   */
  private semesterListener: SemesterStateListener = (state: SemesterState) => {
    this.courseStore.ensureLoadedFor(state.current);
  };

  aboutToAppear(): void {
    const context: common.ApplicationContext =
      applicationContextOf(this.getUIContext().getHostContext() as common.Context);
    this.semesterStore.subscribe(this.semesterListener);
    this.semesterStore.ensureLoaded(context);
  }

  aboutToDisappear(): void {
    this.semesterStore.unsubscribe(this.semesterListener);
  }

  private noticesStack: NavPathStack = new NavPathStack();
  private assignmentsStack: NavPathStack = new NavPathStack();
  private filesStack: NavPathStack = new NavPathStack();
  private coursesStack: NavPathStack = new NavPathStack();
  private settingsStack: NavPathStack = new NavPathStack();

  /**
   * 标签首页占位。真实内容由 FR-05～FR-09、FR-16 各自填充。
   *
   * 本批次先让三个状态组件**各有可见入口**（FR-15 的验收项）：
   * 通知 → 加载态；作业 → 空态；文件 → 错误态（含重试）；课程 → 保留"进入详情"，
   * 用于验证每标签独立栈。这不是调试开关，就是各页此刻的真实内容。
   */
  @Builder
  tabHome(titleKey: string, stack: NavPathStack) {
    Column() {
      if (titleKey === TextKeys.TAB_NOTICES) {
        loadingView()
      } else if (titleKey === TextKeys.TAB_ASSIGNMENTS) {
        emptyView()
      } else if (titleKey === TextKeys.TAB_FILES) {
        // 错误态演示用"网络不可达"：这条最需要与"密码错误"区分开（NFR-NET）
        errorView(FailReason.NETWORK_UNREACHABLE, () => {
          showToast($r('app.string.' + TextKeys.TOAST_RETRYING));
        })
      } else {
        Column({ space: 12 }) {
          Text($r('app.string.' + titleKey))
            .fontSize(24)
          Text($r('app.string.' + TextKeys.PLACEHOLDER_HINT))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Button($r('app.string.' + TextKeys.TAB_OPEN_DETAIL))
            .onClick(() => {
              stack.pushPath({ name: titleKey });
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  /** 详情占位页。每个栈各一个 builder：返回按钮要弹出**自己栈**的栈顶 */
  @Builder
  detailOf(stack: NavPathStack, titleKey: string) {
    NavDestination() {
      Column({ space: 12 }) {
        Text($r('app.string.' + titleKey))
          .fontSize(24)
        Text($r('app.string.' + TextKeys.PLACEHOLDER_HINT))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        Button($r('app.string.' + TextKeys.TAB_BACK))
          .onClick(() => {
            stack.pop();
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_page'))
    }
    .title($r('app.string.' + titleKey))
  }

  @Builder
  noticesDetail(name: string, param: object) {
    if (name === NOTICE_DETAIL_DESTINATION) {
      NavDestination() {
        NoticeDetailView({ noticeId: (param as NoticeDetailParam).noticeId })
      }
      .title($r('app.string.' + TextKeys.TAB_NOTICES))
    } else {
      this.detailOf(this.noticesStack, name)
    }
  }

  @Builder
  assignmentsDetail(name: string) {
    this.detailOf(this.assignmentsStack, name)
  }

  @Builder
  filesDetail(name: string) {
    this.detailOf(this.filesStack, name)
  }

  @Builder
  coursesDetail(name: string, param: object) {
    if (name === COURSE_DETAIL_DESTINATION) {
      NavDestination() {
        CourseDetailView({ courseId: (param as CourseDetailParam).courseId })
      }
      .title($r('app.string.' + TextKeys.TAB_COURSES))
    } else {
      this.detailOf(this.coursesStack, name)
    }
  }

  @Builder
  settingsDetail(name: string) {
    if (name === SEMESTER_DESTINATION) {
      NavDestination() {
        SemesterSelectionView()
      }
      .title($r('app.string.' + TextKeys.SETTINGS_SEMESTER))
    } else {
      this.detailOf(this.settingsStack, name)
    }
  }

  build() {
    Column() {
      // 登出未完成一类错误在此呈报（原先挂在入口占位页上，随页签迁移到这里）
      if (this.errorKey.length > 0) {
        Text($r('app.string.' + this.errorKey))
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.bg_card'))
      }

      Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
        TabContent() {
          Navigation(this.noticesStack) {
            NoticeListTab({
              onOpenNotice: (noticeId: string) => {
                this.noticesStack.pushPath({
                  name: NOTICE_DETAIL_DESTINATION,
                  param: new NoticeDetailParam(noticeId)
                });
              }
            })
          }
          .title($r('app.string.' + TextKeys.TAB_NOTICES))
          .navDestination(this.noticesDetail)
        }
        .tabBar($r('app.string.' + TextKeys.TAB_NOTICES))

        TabContent() {
          Navigation(this.assignmentsStack) {
            this.tabHome(TextKeys.TAB_ASSIGNMENTS, this.assignmentsStack)
          }
          .title($r('app.string.' + TextKeys.TAB_ASSIGNMENTS))
          .navDestination(this.assignmentsDetail)
        }
        .tabBar($r('app.string.' + TextKeys.TAB_ASSIGNMENTS))

        TabContent() {
          Navigation(this.filesStack) {
            this.tabHome(TextKeys.TAB_FILES, this.filesStack)
          }
          .title($r('app.string.' + TextKeys.TAB_FILES))
          .navDestination(this.filesDetail)
        }
        .tabBar($r('app.string.' + TextKeys.TAB_FILES))

        TabContent() {
          Navigation(this.coursesStack) {
            CourseListTab({
              onOpenCourse: (courseId: string) => {
                this.coursesStack.pushPath({
                  name: COURSE_DETAIL_DESTINATION,
                  param: new CourseDetailParam(courseId)
                });
              }
            })
          }
          .title($r('app.string.' + TextKeys.TAB_COURSES))
          .navDestination(this.coursesDetail)
        }
        .tabBar($r('app.string.' + TextKeys.TAB_COURSES))

        TabContent() {
          Navigation(this.settingsStack) {
            SettingsView({
              onOpenSemesters: () => {
                this.settingsStack.pushPath({ name: SEMESTER_DESTINATION });
              }
            })
          }
          .title($r('app.string.' + TextKeys.TAB_SETTINGS))
          .navDestination(this.settingsDetail)
        }
        .tabBar($r('app.string.' + TextKeys.TAB_SETTINGS))
      }
      .barMode(BarMode.Fixed)
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
