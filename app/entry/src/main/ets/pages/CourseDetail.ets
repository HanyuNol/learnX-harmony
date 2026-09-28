/**
 * 课程详情页：本批交付**骨架**——课程基本信息 + 三个内容页签（通知/作业/文件）的占位。
 *
 * 三块内容由 FR-06～FR-08 各自填充；上游也是在课程详情里内嵌这三块
 * （`CourseDetail.tsx:44-157`），故这里先把结构与页签立起来，填内容时不用动导航结构。
 *
 * 课程名/教师名从 `courseStore` 按 id 取（上游是把整个课程对象随路由参数带过去；
 * 我们用 id 查 store，避免路由参数里塞一份可能过期的副本）。
 */

import { CourseStore } from '../viewmodel/courseStore';
import { TextKeys } from '../common/texts';
import { NoticeListTab } from './Notices';
import { AssignmentListTab } from './Assignments';
import { FileListTab } from './Files';

/** 课程详情的目的地名与参数载体（`Main` 的 navDestination 用它分派） */
export const COURSE_DETAIL_DESTINATION: string = 'course-detail';

export class CourseDetailParam {
  readonly courseId: string;

  constructor(courseId: string) {
    this.courseId = courseId;
  }
}

/** 三个内容页签的顺序固定，与上游一致 */
const CONTENT_TAB_KEYS: string[] = [TextKeys.TAB_NOTICES, TextKeys.TAB_ASSIGNMENTS, TextKeys.TAB_FILES];

@Component
export struct CourseDetailView {
  /** 要展示的课程 id */
  @Prop courseId: string;
  /**
   * 打开通知详情。由持有课程栈的 `Main` 提供——在课程详情里点通知，
   * **推在课程栈上**（与上游一致：`CourseStack` 里也注册了 `NoticeDetail`），
   * 这样返回时是回到课程详情，而不是跳到通知标签。
   */
  onOpenNotice?: (noticeId: string) => void;
  /**
   * 打开作业详情。同样由 `Main` 提供、同样推在课程栈上。
   * **必须传下去**——列表行的点击在回调为空时是静默无效的（本项目踩过的坑）。
   */
  onOpenAssignment?: (assignmentId: string) => void;
  /** 打开文件详情。同样由 `Main` 提供、同样推在课程栈上，同样**必须传下去** */
  onOpenFile?: (fileId: string) => void;
  /** 打开**本课程内**的搜索。同样由 `Main` 提供、推在课程栈上 */
  onOpenSearch?: (courseId: string, courseName: string) => void;

  @State private activeTab: number = 0;

  private store: CourseStore = CourseStore.getInstance();

  build() {
    Column() {
      // 课程基本信息。查不到时只显示占位符，不阻塞页面（课程列表可能刚好在重取）
      Text(this.store.nameOf(this.courseId))
        .fontSize(20)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      // 课程内搜索入口：范围限定在这门课（结果页顶部会写明，见 search spec §3.3 第 3 条）
      Row() {
        Button($r('app.string.' + TextKeys.SEARCH_TITLE))
          .fontSize(14)
          .onClick(() => {
            const open: ((courseId: string, courseName: string) => void) | undefined = this.onOpenSearch;
            if (open !== undefined) {
              open(this.courseId, this.store.nameOf(this.courseId));
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      Tabs({ barPosition: BarPosition.Start, index: this.activeTab }) {
        TabContent() {
          // 与通知标签共用同一套列表，只是按当前课程过滤（对齐上游在课程详情里内嵌列表）；
          // onOpenNotice 必须传下去——列表行的点击在回调为空时是**静默无效**的
          NoticeListTab({
            courseId: this.courseId,
            onOpenNotice: this.onOpenNotice
          })
        }
        .tabBar($r('app.string.' + TextKeys.TAB_NOTICES))

        TabContent() {
          // 与作业标签共用同一套列表，只是按当前课程过滤；
          // onOpenAssignment 必须传下去——列表行的点击在回调为空时是**静默无效**的
          AssignmentListTab({
            courseId: this.courseId,
            // 回调**必须传下去**：漏传时点击是静默无效的（本项目踩过）
            onOpenAssignment: this.onOpenAssignment
          })
        }
        .tabBar($r('app.string.' + TextKeys.TAB_ASSIGNMENTS))

        TabContent() {
          // 与文件标签共用同一套列表，只是按当前课程过滤；onOpenFile 同样必须传下去
          FileListTab({
            courseId: this.courseId,
            onOpenFile: this.onOpenFile
          })
        }
        .tabBar($r('app.string.' + TextKeys.TAB_FILES))
      }
      .barMode(BarMode.Fixed)
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => {
        this.activeTab = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
