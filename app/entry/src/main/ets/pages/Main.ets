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
import { SettingsView } from './Settings';
import { AboutView, ABOUT_DESTINATION } from './About';
import { PROFILE_DESTINATION, ProfileView } from './Profile';
import { SEARCH_DESTINATION, SearchParam, SearchView } from './Search';
import { SearchKind } from '../model/search';
import { SEMESTER_DESTINATION, SemesterSelectionView } from './SemesterSelection';
import { CourseListTab } from './Courses';
import { NOTICE_DETAIL_DESTINATION, NoticeListTab } from './Notices';
import { NoticeDetailParam, NoticeDetailView } from './NoticeDetail';
import { ASSIGNMENT_DETAIL_DESTINATION, AssignmentListTab } from './Assignments';
import { AssignmentDetailParam, AssignmentDetailView } from './AssignmentDetail';
import { ASSIGNMENT_SUBMIT_DESTINATION, AssignmentSubmitParam, AssignmentSubmitView } from './AssignmentSubmit';
import { FILE_DETAIL_DESTINATION, FileListTab } from './Files';
import { FileDetailParam, FileDetailView } from './FileDetail';
import { COURSE_DETAIL_DESTINATION, CourseDetailParam, CourseDetailView } from './CourseDetail';
import { SemesterState, SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { CourseState, CourseStateListener, CourseStore } from '../viewmodel/courseStore';
import { StartupSync } from '../viewmodel/startupSync';
import { applicationContextOf } from '../native/contextAdapter';
import { common } from '@kit.AbilityKit';

/** 底部标签切换的过渡时长（毫秒）。取值理由见 `build()` 里 `Tabs` 上的注释 */
const TAB_SWITCH_MS: number = 200;

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

  /**
   * 课程就绪即**预载通知与文件**（FR-25）。
   *
   * 这两个维度原先只在用户切到对应标签时才拉，切过去先看到转圈。预载是后台动作：
   * 不阻塞、不提示、失败只进日志（`docs/specs/startup-sync.md`）。
   * 判断"该不该预载、按什么顺序"在 `common/prefetch`（纯逻辑），编排在 `viewmodel`。
   */
  private coursesListener: CourseStateListener = (state: CourseState) => {
    StartupSync.getInstance().run(state.semesterId, state.items);
  };

  aboutToAppear(): void {
    const context: common.ApplicationContext =
      applicationContextOf(this.getUIContext().getHostContext() as common.Context);
    this.semesterStore.subscribe(this.semesterListener);
    this.courseStore.subscribe(this.coursesListener);
    this.semesterStore.ensureLoaded(context);
  }

  aboutToDisappear(): void {
    this.semesterStore.unsubscribe(this.semesterListener);
    this.courseStore.unsubscribe(this.coursesListener);
  }

  private noticesStack: NavPathStack = new NavPathStack();
  private assignmentsStack: NavPathStack = new NavPathStack();
  private filesStack: NavPathStack = new NavPathStack();
  private coursesStack: NavPathStack = new NavPathStack();
  private settingsStack: NavPathStack = new NavPathStack();

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

  /**
   * **五个栈共用一个目的地分派**。
   *
   * 为什么不再一栈一份：搜索结果可能落在任意一类上（在通知标签里搜到一门课程、点进去要看课程详情），
   * 一栈一份的写法会让"从本栈打开别的类型"无处可去。共用之后每个栈都能打开任何详情，
   * 也顺带去掉了五份重复代码。
   */
  @Builder
  routeOf(stack: NavPathStack, name: string, param: object) {
    if (name === NOTICE_DETAIL_DESTINATION) {
      NavDestination() {
        NoticeDetailView({ noticeId: (param as NoticeDetailParam).noticeId })
      }
      .title($r('app.string.' + TextKeys.TAB_NOTICES))
    } else if (name === ASSIGNMENT_DETAIL_DESTINATION) {
      NavDestination() {
        AssignmentDetailView({
          assignmentId: (param as AssignmentDetailParam).assignmentId,
          onOpenSubmit: (assignmentId: string) => {
            stack.pushPath({
              name: ASSIGNMENT_SUBMIT_DESTINATION,
              param: new AssignmentSubmitParam(assignmentId)
            });
          }
        })
      }
      .title($r('app.string.' + TextKeys.TAB_ASSIGNMENTS))
    } else if (name === ASSIGNMENT_SUBMIT_DESTINATION) {
      NavDestination() {
        AssignmentSubmitView({ assignmentId: (param as AssignmentSubmitParam).assignmentId })
      }
      .title($r('app.string.' + TextKeys.ASSIGNMENT_SUBMIT))
    } else if (name === FILE_DETAIL_DESTINATION) {
      NavDestination() {
        FileDetailView({ fileId: (param as FileDetailParam).fileId })
      }
      .title($r('app.string.' + TextKeys.TAB_FILES))
    } else if (name === COURSE_DETAIL_DESTINATION) {
      NavDestination() {
        CourseDetailView({
          courseId: (param as CourseDetailParam).courseId,
          onOpenNotice: (noticeId: string) => {
            stack.pushPath({
              name: NOTICE_DETAIL_DESTINATION,
              param: new NoticeDetailParam(noticeId)
            });
          },
          onOpenAssignment: (assignmentId: string) => {
            stack.pushPath({
              name: ASSIGNMENT_DETAIL_DESTINATION,
              param: new AssignmentDetailParam(assignmentId)
            });
          },
          onOpenFile: (fileId: string) => {
            stack.pushPath({
              name: FILE_DETAIL_DESTINATION,
              param: new FileDetailParam(fileId)
            });
          },
          // 课程内的搜索：带 courseId 与课程名，预览页据此标明范围
          onOpenSearch: (courseId: string, courseName: string) => {
            stack.pushPath({
              name: SEARCH_DESTINATION,
              param: new SearchParam(courseId, courseName)
            });
          }
        })
      }
      .title($r('app.string.' + TextKeys.TAB_COURSES))
    } else if (name === SEMESTER_DESTINATION) {
      NavDestination() {
        SemesterSelectionView()
      }
      .title($r('app.string.' + TextKeys.SETTINGS_SEMESTER))
    } else if (name === ABOUT_DESTINATION) {
      NavDestination() {
        AboutView()
      }
      .title($r('app.string.' + TextKeys.SETTINGS_ABOUT))
    } else if (name === PROFILE_DESTINATION) {
      NavDestination() {
        ProfileView()
      }
      .title($r('app.string.' + TextKeys.SETTINGS_PROFILE))
    } else if (name === SEARCH_DESTINATION) {
      NavDestination() {
        SearchView({
          courseId: (param as SearchParam).courseId,
          courseName: (param as SearchParam).courseName,
          onOpenResult: (kind: string, id: string) => {
            this.openSearchResult(stack, kind, id);
          }
        })
      }
      .title($r('app.string.' + TextKeys.SEARCH_TITLE))
    } else {
      this.detailOf(stack, name)
    }
  }

  /** 搜索结果的跳转：按类型推对应详情（推在**发起搜索的那个栈**上，返回即回搜索页） */
  private openSearchResult(stack: NavPathStack, kind: string, id: string): void {
    if (kind === SearchKind.COURSE) {
      stack.pushPath({ name: COURSE_DETAIL_DESTINATION, param: new CourseDetailParam(id) });
    } else if (kind === SearchKind.FILE) {
      stack.pushPath({ name: FILE_DETAIL_DESTINATION, param: new FileDetailParam(id) });
    } else if (kind === SearchKind.NOTICE) {
      stack.pushPath({ name: NOTICE_DETAIL_DESTINATION, param: new NoticeDetailParam(id) });
    } else if (kind === SearchKind.ASSIGNMENT) {
      stack.pushPath({ name: ASSIGNMENT_DETAIL_DESTINATION, param: new AssignmentDetailParam(id) });
    }
  }

  /**
   * 每个栈一个**薄包装**，只为满足 ArkUI 的要求：`navDestination` 收的必须是
   * `@Builder` 方法（传箭头函数不会渲染出内容——2026-09-28 实测：点搜索后整页空白）。
   * 真正的分派在 `routeOf`，五个包装各自只交代"用哪个栈"。
   */
  @Builder
  noticesDetail(name: string, param: object) {
    this.routeOf(this.noticesStack, name, param)
  }

  @Builder
  assignmentsDetail(name: string, param: object) {
    this.routeOf(this.assignmentsStack, name, param)
  }

  @Builder
  filesDetail(name: string, param: object) {
    this.routeOf(this.filesStack, name, param)
  }

  @Builder
  coursesDetail(name: string, param: object) {
    this.routeOf(this.coursesStack, name, param)
  }

  @Builder
  settingsDetail(name: string, param: object) {
    this.routeOf(this.settingsStack, name, param)
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
              onOpenSearch: () => {
                this.noticesStack.pushPath({ name: SEARCH_DESTINATION, param: new SearchParam('', '') });
              },
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
            AssignmentListTab({
              onOpenSearch: () => {
                this.assignmentsStack.pushPath({ name: SEARCH_DESTINATION, param: new SearchParam('', '') });
              },
              onOpenAssignment: (assignmentId: string) => {
                this.assignmentsStack.pushPath({
                  name: ASSIGNMENT_DETAIL_DESTINATION,
                  param: new AssignmentDetailParam(assignmentId)
                });
              }
            })
          }
          .title($r('app.string.' + TextKeys.TAB_ASSIGNMENTS))
          .navDestination(this.assignmentsDetail)
        }
        .tabBar($r('app.string.' + TextKeys.TAB_ASSIGNMENTS))

        TabContent() {
          Navigation(this.filesStack) {
            FileListTab({
              onOpenSearch: () => {
                this.filesStack.pushPath({ name: SEARCH_DESTINATION, param: new SearchParam('', '') });
              },
              onOpenFile: (fileId: string) => {
                this.filesStack.pushPath({
                  name: FILE_DETAIL_DESTINATION,
                  param: new FileDetailParam(fileId)
                });
              }
            })
          }
          .title($r('app.string.' + TextKeys.TAB_FILES))
          .navDestination(this.filesDetail)
        }
        .tabBar($r('app.string.' + TextKeys.TAB_FILES))

        TabContent() {
          Navigation(this.coursesStack) {
            CourseListTab({
              onOpenSearch: () => {
                this.coursesStack.pushPath({ name: SEARCH_DESTINATION, param: new SearchParam('', '') });
              },
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
              onOpenSearch: () => {
                this.settingsStack.pushPath({ name: SEARCH_DESTINATION, param: new SearchParam('', '') });
              },
              onOpenSemesters: () => {
                this.settingsStack.pushPath({ name: SEMESTER_DESTINATION });
              },
              onOpenAbout: () => {
                this.settingsStack.pushPath({ name: ABOUT_DESTINATION });
              },
              onOpenProfile: () => {
                this.settingsStack.pushPath({ name: PROFILE_DESTINATION });
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
      // 切标签的过渡（FR-29）：`animationDuration` 不设时平台默认是 **0**，也就是硬切
      // （见 tabs.d.ts 该属性的说明），故显式给 200ms——与系统其他过渡同量级。
      // `CONTENT_FIRST` 是平台默认值，这里写出来是为了让"先备好内容再过渡"这个意图留在代码里
      // （避免滑过去先看到一片空白）。
      .animationDuration(TAB_SWITCH_MS)
      .animationMode(AnimationMode.CONTENT_FIRST)
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
