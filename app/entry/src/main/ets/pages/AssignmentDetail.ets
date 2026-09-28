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
  Assignment, AssignmentAttachments, HomeworkSubmissionType, RelativeDeadline, relativeDeadlineOf,
  formatDateTime
} from '../model/assignment';
import { plainText } from '../model/notice';
import { Attachment } from '../model/attachment';
import { AssignmentStateListener, AssignmentStore } from '../viewmodel/assignmentStore';
import { TextKeys, textKeyOfRelativeDeadline, textKeyOfCompletionType, textKeyOfSubmissionType, textKeyOfGradeLevel } from '../common/texts';
import { showToast } from '../components/toast';
import { PreviewPane } from '../components/PreviewPane';
import { emptyView } from '../components/StateView';
import { common } from '@kit.AbilityKit';
import { LearnFile, attachmentFileOf, canPreviewInApp } from '../model/file';
import { FileStore } from '../viewmodel/fileStore';
import { Logger } from '../common/logger';

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
  /** 打开提交页。由持有作业栈的 `Main` 提供（页面不自己造路由栈） */
  onOpenSubmit?: (assignmentId: string) => void;

  /**
   * 当前这条作业（放进 **@State**，且 **build 里真的读它**）。
   *
   * 为什么不是"加一个计数器让页面重建"：2026-09-28 真机实测——**只在 build 里被读到的
   * 状态变量才会触发重渲染**；只写不读的计数器不会让页面刷新（详情页重试后看不到结果，
   * 见 OPERATIONS.md §7）。
   */
  @State private assignment: Assignment | null = null;
  /**
   * 点开的附件其应用内预览 URL（空串＝不显示预览区）。
   * 与文件详情同一套：本机没有能处理该类型的应用时（`startAbility` 报 16000019），
   * 应用内预览是"打开附件"唯一可用的路径（附件同样要能看）。
   */
  @State private previewUri: string = '';
  /** 正在预览的附件（非 null 即处于预览态）；关闭预览时清空 */
  @State private attachmentOfPreview: Attachment | null = null;
  /** 正在处理的附件 id（用于按钮禁用与"下载中…"文案） */
  @State private busyAttachment: string = '';
  /** 本次会话里已下载成功的附件 id（用于行内"已下载"标记；重启后由文件系统判定） */
  @State private downloadedIds: string[] = [];

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

  /** 预览态：整页只有预览面板（与文件详情同一套组件与行为，见 docs/specs/pdf-preview.md §2.6） */
  @Builder
  previewOnly(attachment: Attachment, assignment: Assignment) {
    Column() {
      PreviewPane({
        uri: this.previewUri,
        onClose: () => {
          this.previewUri = '';
        },
        onOpenExternal: () => {
          // 附件已在沙箱（预览前已下载）：直接交给系统应用，失败如实提示
          const context: common.UIAbilityContext =
            this.getUIContext().getHostContext() as common.UIAbilityContext;
          FileStore.getInstance().openAttachment(
            attachmentFileOf(attachment, assignment.courseId, assignment.courseName,
              assignment.courseTeacherName), assignment.id, context)
            .catch(() => {
              showToast($r('app.string.' + TextKeys.FILE_OPEN_FAILED));
            });
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  @Builder
  detail(assignment: Assignment) {
    // 预览态**独占页面**：进入预览后收起作业内容，把空间留给文件本身
    // **不能写 `return`**：ArkUI 的 @Builder 里只允许 UI 语法，故用 if/else 分流
    if (this.previewUri.length > 0 && this.attachmentOfPreview !== null) {
      this.previewOnly(this.attachmentOfPreview as Attachment, assignment)
    } else {
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

        this.teacherAttachment(assignment)

        if (assignment.submitted) {
          this.submittedBlock(assignment)
        }

        if (assignment.graded) {
          this.gradeBlock(assignment)
        }

        // 提交 / 修改提交：只在**在线提交**的作业上给（线下提交的作业在网上无事可做，
        // 显示了却点不动属假动作）
        if (assignment.submissionType !== HomeworkSubmissionType.OFFLINE) {
          Button($r('app.string.' + (assignment.submitted
            ? TextKeys.ASSIGNMENT_MODIFY_SUBMISSION : TextKeys.ASSIGNMENT_SUBMIT)))
            .width('100%')
            .padding({ top: 12 })
            .onClick(() => {
              const open: ((assignmentId: string) => void) | undefined = this.onOpenSubmit;
              if (open !== undefined) {
                open(this.assignmentId);
              }
            })
        }

      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    }
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
  teacherAttachment(assignment: Assignment) {
    if (assignment.attachments.teacher !== null) {
      this.attachmentRow(TextKeys.ASSIGNMENT_ATTACHMENT,
        assignment.attachments.teacher as Attachment, assignment)
    }
  }

  /**
   * 一行附件：显示名称，**点击即下载并打开**（可预览的类型在页内预览，
   * 不可预览的交给系统应用）。附件此前只显示名字、点不动——那是个缺口。
   */
  @Builder
  attachmentRow(labelKey: string, attachment: Attachment, assignment: Assignment) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text($r('app.string.' + labelKey))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        Text(attachment.name)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.busyAttachment === attachment.fileId) {
          Text($r('app.string.' + TextKeys.FILE_DOWNLOADING))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        } else if (this.downloadedIds.includes(attachment.fileId)) {
          Text($r('app.string.' + TextKeys.FILE_DOWNLOADED))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
        }
      }
      .width('100%')

      // **查看与下载分成两个动作**（用户反馈：附件此前只能"点此查看"、不能下载）。
      // 查看＝下载后立即打开（可预览的页内预览，其余交系统应用）；下载＝只落盘。
      Row({ space: 12 }) {
        Button($r('app.string.' + TextKeys.ASSIGNMENT_ATTACHMENT_VIEW))
          .fontSize(14)
          .enabled(this.busyAttachment.length === 0)
          .onClick(() => {
            this.viewAttachment(attachment, assignment);
          })
        Button($r('app.string.' + TextKeys.ASSIGNMENT_ATTACHMENT_DOWNLOAD))
          .fontSize(14)
          .enabled(this.busyAttachment.length === 0)
          .onClick(() => {
            this.downloadAttachment(attachment, assignment);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /** 只下载附件（不打开）：落盘后行内显示"已下载" */
  private downloadAttachment(attachment: Attachment, assignment: Assignment): void {
    if (this.busyAttachment.length > 0) {
      return;
    }
    const store: FileStore = FileStore.getInstance();
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const file: LearnFile = attachmentFileOf(attachment, assignment.courseId,
      assignment.courseName, assignment.courseTeacherName);

    this.busyAttachment = attachment.fileId;
    store.downloadAttachment(file, assignment.id, context, false).then(() => {
      this.busyAttachment = '';
      if (!this.downloadedIds.includes(attachment.fileId)) {
        this.downloadedIds = this.downloadedIds.concat([attachment.fileId]);
      }
    }).catch(() => {
      this.busyAttachment = '';
      showToast($r('app.string.' + TextKeys.FILE_DOWNLOAD_FAILED));
    });
  }

  /** 查看附件：下载（已下过则复用）→ 可预览就页内预览，否则交给系统应用 */
  private viewAttachment(attachment: Attachment, assignment: Assignment): void {
    if (this.busyAttachment.length > 0) {
      return;
    }
    const store: FileStore = FileStore.getInstance();
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const file: LearnFile = attachmentFileOf(attachment, assignment.courseId,
      assignment.courseName, assignment.courseTeacherName);

    this.busyAttachment = attachment.fileId;
    store.downloadAttachment(file, assignment.id, context, false).then(() => {
      this.busyAttachment = '';
      if (!this.downloadedIds.includes(attachment.fileId)) {
        this.downloadedIds = this.downloadedIds.concat([attachment.fileId]);
      }
      if (canPreviewInApp(file.fileType)) {
        const uri: string = store.previewUriOfAttachment(file, assignment.id, context);
        if (uri.length > 0) {
          this.attachmentOfPreview = attachment;
          this.previewUri = uri;
          return;
        }
      }
      // 浏览器渲染不出来的类型（Office 文档等）：交给系统应用，失败如实提示
      store.openAttachment(file, assignment.id, context).catch(() => {
        showToast($r('app.string.' + TextKeys.FILE_OPEN_FAILED));
      });
    }).catch(() => {
      this.busyAttachment = '';
      showToast($r('app.string.' + TextKeys.FILE_DOWNLOAD_FAILED));
    });
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
        this.attachmentRow(TextKeys.ASSIGNMENT_SUBMITTED_ATTACHMENT,
          assignment.attachments.submitted as Attachment, assignment)
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
        this.attachmentRow(TextKeys.ASSIGNMENT_GRADE_ATTACHMENT,
          assignment.attachments.grade as Attachment, assignment)
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
