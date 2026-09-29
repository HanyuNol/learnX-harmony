/**
 * 学期切换页。挂在**设置标签的栈**里（与上游 IA 一致：设置 → 学期切换）。
 *
 * 交互对齐上游 `screens/SemesterSelection.tsx`：单选列表、当前项有标记、切换后**不返回**
 * （仅更新选中态）、可手动刷新。
 *
 * 状态四态都接状态组件（FR-15）：加载 / 空 / 错误+重试 / 有列表。
 * 分层：本页只订阅 `viewmodel.semesterStore` 并下发用户意图，不碰网络与存储。
 */

import { common } from '@kit.AbilityKit';
import { FailReason } from '../model/auth';
import { parseSemester } from '../model/semester';
import { SemesterState, SemesterStateListener, SemesterStore } from '../viewmodel/semesterStore';
import { TextKeys, textKeyOfSemesterType } from '../common/texts';
import { applicationContextOf } from '../native/contextAdapter';
import { emptyView, errorView, loadingView } from '../components/StateView';

/** 设置栈里本页的路由名（`Main` 的 `navDestination` 用它分派） */
export const SEMESTER_DESTINATION: string = 'semester-selection';

@Component
export struct SemesterSelectionView {
  @State private fetching: boolean = false;
  @State private items: string[] = [];
  @State private current: string = '';
  @State private errorTextKey: string = '';
  /** 错误态需要一个原因去取分类文案；null 表示当前不是错误态 */
  @State private errorReasonValue: FailReason | null = null;

  private store: SemesterStore = SemesterStore.getInstance();

  /** 订阅回调必须保存为字段引用，否则 aboutToDisappear 无法反订阅（ADR-0004 的泄漏风险） */
  private listener: SemesterStateListener = (state: SemesterState) => {
    this.fetching = state.fetching;
    this.items = state.items;
    this.current = state.current;
    this.errorTextKey = state.errorTextKey;
    this.errorReasonValue = state.errorReason;
  };

  private appContext(): common.ApplicationContext {
    return applicationContextOf(this.getUIContext().getHostContext() as common.Context);
  }

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    // 已加载过则不会重复拉（store 内有守卫）
    this.store.ensureLoaded(this.appContext());
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  build() {
    Column() {
      if (this.errorReasonValue !== null && this.items.length === 0) {
        errorView(this.errorReasonValue as FailReason, () => {
          this.store.refresh(this.appContext());
        })
      } else if (this.fetching && this.items.length === 0) {
        loadingView()
      } else if (this.items.length === 0) {
        emptyView()
      } else {
        List() {
          ForEach(this.items, (id: string) => {
            ListItem() {
              this.semesterRow(id)
            }
          }, (id: string) => id)
        }
        .layoutWeight(1)
        .width('100%')
      }

      // 切换未能保存一类错误：列表仍可用，故用一行提示而不是整页错误态
      if (this.errorTextKey.length > 0 && this.items.length > 0) {
        Text($r('app.string.' + this.errorTextKey))
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding(8)
      }

      Button($r('app.string.' + TextKeys.SEMESTER_REFRESH))
        .width('100%')
        .margin({ top: 8, bottom: 16 })
        .onClick(() => {
          this.store.refresh(this.appContext());
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.bg_page'))
  }

  /**
   * 一行学期。
   *
   * 年份与季节**分两个节点**渲染（数字 + 季节文案键），不在代码里拼中文——
   * 拼接会绕过 NFR-I18N（见 spec §3.3 第 3 条）。
   */
  @Builder
  semesterRow(id: string) {
    Row({ space: 8 }) {
      Text(parseSemester(id).yearsText)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Text($r('app.string.' + textKeyOfSemesterType(parseSemester(id).type)))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Blank()
      if (id === this.current) {
        // 既给图标也给文字：图标在本项目的 UI 节点树里看不到（SymbolGlyph 不被表示），
        // 只有文字能让"当前项有没有标出来"这件事在验收时被真正验证，也更不容易误读
        Text($r('app.string.' + TextKeys.SEMESTER_CURRENT))
          .fontSize(14)
          .fontColor($r('app.color.accent'))
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([$r('app.color.accent')])
          // 装饰：同一行已有文字说明"当前学期"，勾只是个视觉标记
          .accessibilityLevel('no')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .onClick(() => {
      this.store.switchTo(this.appContext(), id);
    })
  }
}
