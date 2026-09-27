/**
 * 作业详情页。
 *
 * **详情随列表一起预取**（用户 2026-09-27 决定，对齐上游），所以正常路径下进页即见、
 * 没有加载态。若那条的详情在预取时失败，这里给"详情未能加载 + 重试"（只补这一条）。
 *
 * 正文按**纯文本**呈现（富文本渲染属 FR-22，且 SECURITY §3 要求"按白名单清洗、
 * 不得整体信任服务端 HTML"）。附件本批只显示名字，点开下载属 FR-08。
 * **不显示提交按钮**：作业提交属 FR-20（P2），显示了却点不动是假动作（spec §2）。
 *
 * 分层：本页只订阅状态、下发意图，不碰网络与存储。
 */

import {
  Assignment, AssignmentAttachments, RelativeDeadline, relativeDeadlineOf, formatDateTime
} from '../model/assignment';
import { plainText } from '../model/notice';
import { Attachment } from '../model/attachment';
import { AssignmentState, AssignmentStateListener, AssignmentStore } from '../viewmodel/assignmentStore';
import { TextKeys, textKeyOfRelativeDeadline, textKeyOfCompletionType, textKeyOfSubmissionType, textKeyOfGradeLevel } from '../common/texts';
import { showToast } from '../components/toast';
import { emptyView } from '../components/StateView';

/** 详情目的地的参数载体 */
export class AssignmentDetailParam {
  readonly assignmentId: string;

  constructor(assignmentId: string) {
    this.assignmentId = assignmentId;
  }
}

@Component
export struct AssignmentDetailView {
  @Prop assignmentId: string;

  /**
   * 当前这条作业（放进 **@State**，且 **build 里真的读它**）。
   *
   * 为什么不是"加一个计数器让页面重建"：2026-09-28 真机实测——**只在 build 里被读到的
   * 状态变量才会触发重渲染**；只写不读的计数器不会让页面刷新（详情页重试后看不到结果，
   * 见 OPERATIONS.md §7）。
   */
  @State private assignment: Assignment | null = null;

  private store: AssignmentStore = AssignmentStore.getInstance();

  private listener: AssignmentStateListener = () => {
    this.assignment = this.store.assignmentOf(this.assignmentId);
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  build() {
    Column() {
      if (this.assignment === null) {
        // 作业不在当前列表里（例如列表刚被整表替换）——给它一个可理解的状态，而不是空白
        emptyView()
      } else {
        this.detail(this.assignment as Assignment)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  detail(assignment: Assignment) {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text($r('app.string.' + textKeyOfCompletionType(assignment.completionType)))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text($r('app.string.' + textKeyOfSubmissionType(assignment.submissionType)))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          if (assignment.submitted) {
            Text($r('app.string.' + TextKeys.ASSIGNMENT_SUBMITTED))
              .fontSize(12)
              .fontColor($r('app.color.accent'))
          }
          if (assignment.graded) {
            Text($r('app.string.' + TextKeys.ASSIGNMENT_GRADED))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
          }
        }
        .width('100%')

        Text(assignment.title)
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Row({ space: 8 }) {
          this.deadlineText(assignment)
          if (formatDateTime(assignment.deadlineTime).length > 0) {
            Text(formatDateTime(assignment.deadlineTime))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')

        if (assignment.lateDeadline.length > 0) {
          Row({ space: 8 }) {
            Text($r('app.string.' + TextKeys.ASSIGNMENT_LATE_DEADLINE))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(assignment.lateDeadline)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }

        // 详情预取失败：明说没加载到，并给一个真的会重试的按钮
        if (!assignment.detailLoaded) {
          Row({ space: 8 }) {
            Text($r('app.string.' + TextKeys.ASSIGNMENT_DETAIL_FAILED))
              .fontSize(14)
              .fontColor($r('app.color.danger'))
            Button($r('app.string.' + TextKeys.STATE_RETRY))
              .fontSize(14)
              .onClick(() => {
                this.retryDetail();
              })
          }
          .width('100%')
        }

        // 正文（纯文本）
        if (assignment.description.length > 0) {
          Text(plainText(assignment.description))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        } else {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_NO_DESCRIPTION))
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        this.teacherAttachment(assignment.attachments)

        if (assignment.submitted) {
          this.submittedBlock(assignment)
        }

        if (assignment.graded) {
          this.gradeBlock(assignment)
        }
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  private retryDetail(): void {
    this.store.reloadDetailOf(this.assignmentId).catch(() => {
      // 重试仍失败：给出反馈，不做静默无效（本项目最贵的一课）
      showToast($r('app.string.' + TextKeys.ASSIGNMENT_DETAIL_FAILED));
    });
  }

  @Builder
  deadlineText(assignment: Assignment) {
    if (assignment.deadlineTime > 0) {
      Text($r('app.string.' + relativeKeyOf(assignment), relativeValueOf(assignment)))
        .fontSize(12)
        .fontColor(assignment.deadlineTime < Date.now()
          ? $r('app.color.danger') : $r('app.color.text_secondary'))
    }
  }

  @Builder
  teacherAttachment(attachments: AssignmentAttachments) {
    if (attachments.teacher !== null) {
      Row({ space: 8 }) {
        Text($r('app.string.' + TextKeys.ASSIGNMENT_ATTACHMENT))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        Text((attachments.teacher as Attachment).name)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
    }
  }

  @Builder
  submittedBlock(assignment: Assignment) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text($r('app.string.' + TextKeys.ASSIGNMENT_SUBMIT_TIME))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        // 提交时间原样呈现：服务端给的已是可读字符串，本批不做二次格式化（spec §6）
        if (assignment.submitTime.length > 0) {
          Text(assignment.submitTime)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        } else {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_SUBMITTED))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }
      }
      .width('100%')

      if (assignment.attachments.submitted !== null) {
        Row({ space: 8 }) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_SUBMITTED_ATTACHMENT))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text((assignment.attachments.submitted as Attachment).name)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 8 })
  }

  @Builder
  gradeBlock(assignment: Assignment) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text($r('app.string.' + TextKeys.ASSIGNMENT_GRADE))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        this.gradeValue(assignment)
      }
      .width('100%')

      if (assignment.gradeContent.length > 0) {
        Text(plainText(assignment.gradeContent))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }

      if (assignment.graderName.length > 0) {
        Row({ space: 8 }) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_GRADER))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text(assignment.graderName)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
      }

      if (assignment.gradeTime.length > 0) {
        Row({ space: 8 }) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_GRADE_TIME))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text(assignment.gradeTime)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
      }

      if (assignment.attachments.grade !== null) {
        Row({ space: 8 }) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_GRADE_ATTACHMENT))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text((assignment.attachments.grade as Attachment).name)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 8 })
  }

  /** 评分：有等级显示等级（能翻译的用文案，A+/B 一类直接显示代码），否则显示分数 */
  @Builder
  gradeValue(assignment: Assignment) {
    if (assignment.gradeLevel.length > 0) {
      if (textKeyOfGradeLevel(assignment.gradeLevel) !== TextKeys.NONE) {
        Text($r('app.string.' + textKeyOfGradeLevel(assignment.gradeLevel)))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
      } else {
        Text(assignment.gradeLevel)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
      }
    } else if (assignment.grade.length > 0) {
      Text(assignment.grade)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    }
  }
}

/** 相对描述的资源键（同列表页：`model` 不持有文案） */
function relativeKeyOf(assignment: Assignment): string {
  const relative: RelativeDeadline | null = relativeDeadlineOf(assignment.deadlineTime, Date.now());
  if (relative === null) {
    return TextKeys.NONE;
  }
  return textKeyOfRelativeDeadline(relative);
}

function relativeValueOf(assignment: Assignment): number {
  const relative: RelativeDeadline | null = relativeDeadlineOf(assignment.deadlineTime, Date.now());
  return relative === null ? 0 : relative.value;
}
