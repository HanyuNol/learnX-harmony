/**
 * 作业提交页（FR-20）。**已提交的作业从这里改提交**。
 *
 * 与上游 `screens/AssignmentSubmission.tsx` 同构：正文（多行）+ 可选附件（选择/移除）
 * + 提交按钮。差异只在本项目的分层：附件选择走 `native.filePickerAdapter`（系统能力出口），
 * 提交走 `assignmentStore` → `repository` → `LearnClient`，页面不碰网络与系统 Kit。
 *
 * 提交成功后**不自己编状态**：完成状态与已提交附件都来自服务端，故由 store 重拉一次列表
 * （见 `assignmentStore.submit` 的说明）。
 */

import { Assignment } from '../model/assignment';
import { Attachment } from '../model/attachment';
import { MultipartFile } from '../model/multipart';
import { extensionOf } from '../model/file';
import { mimeOfExtension } from '../common/mime';
import { AssignmentStateListener, AssignmentStore } from '../viewmodel/assignmentStore';
import { TextKeys } from '../common/texts';
import { showToast } from '../components/toast';
import { emptyView } from '../components/StateView';
import { PickedFile, pickFile } from '../native/filePickerAdapter';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger';

const TAG: string = 'assignmentSubmit';

/** 提交页在作业栈里的目的地名 */
export const ASSIGNMENT_SUBMIT_DESTINATION: string = 'assignment-submit';

/** 参数载体 */
export class AssignmentSubmitParam {
  readonly assignmentId: string;

  constructor(assignmentId: string) {
    this.assignmentId = assignmentId;
  }
}

@Component
export struct AssignmentSubmitView {
  @Prop assignmentId: string;

  /** 当前这条作业（@State 且 build 里读它——只写不读的状态不会让页面刷新） */
  @State private assignment: Assignment | null = null;
  /** 正文（进页时用已提交内容预填，便于"改提交"） */
  @State private content: string = '';
  /** 选中的附件名（展示用；字节放在非状态字段里，避免大对象进状态） */
  @State private pickedName: string = '';
  /** 是否请求移除已提交的附件 */
  @State private removeAttachment: boolean = false;
  @State private submitting: boolean = false;

  private picked: PickedFile | null = null;
  private store: AssignmentStore = AssignmentStore.getInstance();

  private listener: AssignmentStateListener = () => {
    this.assignment = this.store.assignmentOf(this.assignmentId);
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    // 正文默认留空：服务端的"已提交正文"在详情页 HTML 里（`submittedContent`），
    // 本项目本批只取附件与正文，未取该字段；预填它属 FR-21 的富文本那批一并做。
    // **不拿作业描述或评语来冒充**——那是别人的内容。
    this.assignment = this.store.assignmentOf(this.assignmentId);
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  build() {
    Column() {
      if (this.assignment === null) {
        emptyView()
      } else {
        this.form(this.assignment as Assignment)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  form(assignment: Assignment) {
    Scroll() {
      Column({ space: 12 }) {
        Text(assignment.title)
          .fontSize(18)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        // 已过截止时间：明说，而不是让用户提交完才知道
        if (assignment.deadlineTime > 0 && Date.now() > assignment.deadlineTime) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_PAST_DEADLINE))
            .fontSize(14)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }

        Text($r('app.string.' + TextKeys.ASSIGNMENT_SUBMIT_CONTENT))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextArea({ text: this.content, placeholder: $r('app.string.' + TextKeys.ASSIGNMENT_SUBMIT_CONTENT_HINT) })
          .width('100%')
          .height(200)
          .onChange((value: string) => {
            this.content = value;
          })

        Text($r('app.string.' + TextKeys.ASSIGNMENT_SUBMIT_ATTACHMENT))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        if (this.pickedName.length > 0) {
          Row({ space: 8 }) {
            Text(this.pickedName)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Button($r('app.string.' + TextKeys.ASSIGNMENT_REMOVE_PICKED))
              .fontSize(14)
              .onClick(() => {
                this.picked = null;
                this.pickedName = '';
              })
          }
          .width('100%')
        } else if (assignment.attachments.submitted !== null && !this.removeAttachment) {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_ALREADY_UPLOADED)
            + (assignment.attachments.submitted as Attachment).name)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else {
          Text($r('app.string.' + TextKeys.ASSIGNMENT_NO_ATTACHMENT))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        Row({ space: 12 }) {
          Button($r('app.string.' + TextKeys.ASSIGNMENT_PICK_FILE))
            .fontSize(14)
            .enabled(!this.submitting)
            .onClick(() => {
              this.chooseFile();
            })
          if (assignment.attachments.submitted !== null) {
            Button($r('app.string.' + (this.removeAttachment
              ? TextKeys.ASSIGNMENT_KEEP_ATTACHMENT : TextKeys.ASSIGNMENT_REMOVE_ATTACHMENT)))
              .fontSize(14)
              .enabled(!this.submitting)
              .onClick(() => {
                this.removeAttachment = !this.removeAttachment;
              })
          }
        }
        .width('100%')
        Button($r('app.string.' + (this.submitting ? TextKeys.ASSIGNMENT_SUBMITTING
          : (assignment.submitted ? TextKeys.ASSIGNMENT_MODIFY_SUBMISSION : TextKeys.ASSIGNMENT_SUBMIT))))
          .width('100%')
          .enabled(!this.submitting)
          .onClick(() => {
            this.submit(assignment);
          })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  /** 选附件：用户取消（返回 null）不是失败，什么都不做 */
  private chooseFile(): void {
    // 选择器需要宿主上下文（UIAbilityContext）；页面取它属 ArkUI 的 UI 能力
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    pickFile(context).then((picked: PickedFile | null) => {
      if (picked === null) {
        return;
      }
      this.picked = picked;
      this.pickedName = picked.name;
    }).catch(() => {
      showToast($r('app.string.' + TextKeys.ASSIGNMENT_PICK_FILE_FAILED));
    });
  }

  /**
   * 提交。成功后由 store 重拉一次列表（完成状态来自服务端，本地不编），
   * 页面订阅到新数据后按钮自动变成"修改提交"。
   */
  private submit(assignment: Assignment): void {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    const file: MultipartFile | null = this.picked === null ? null
      : new MultipartFile('fileupload', this.picked.name,
        mimeOfExtension(extensionOf(this.picked.name)), this.picked.data);

    this.store.submit(assignment.id, this.content, file, this.removeAttachment).then(() => {
      this.submitting = false;
      this.picked = null;
      this.pickedName = '';
      this.removeAttachment = false;
      showToast($r('app.string.' + TextKeys.ASSIGNMENT_SUBMIT_SUCCEEDED));
    }).catch((err: Object) => {
      this.submitting = false;
      // 失败明细（服务端报文 / 网络 / 会话）由下层记日志，这里给用户一句可行动的提示
      Logger.warn(TAG, '提交未成功');
      showToast($r('app.string.' + TextKeys.ASSIGNMENT_SUBMIT_FAILED));
    });
  }
}
