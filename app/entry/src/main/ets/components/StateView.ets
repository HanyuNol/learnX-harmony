/**
 * 状态反馈：加载态 / 空态 / 错误态（全局 `@Builder`）。
 *
 * 为什么做成可复用的 builder 而不是自定义组件：这四种状态在通知/作业/文件/课程
 * 四个维度及其详情页上都要出现（FR-15），散着写必然"有的转圈、有的写文字、有的白屏"。
 * 用 `@Builder` 而非 `@Component` 是按项目 lint 的 `avoid-overusing-custom-component-check`
 * ——纯展示、无自身状态的场景下自定义组件的开销不划算。
 *
 * 错误态的文案**不在这里硬编码**：由 `FailReason` 经 `textKeyOfFailReason` 映射
 * （网络问题必须与"密码错误"分开，NFR-NET），故只收 `reason`，不收支文案。
 *
 * 视觉遵循 ADR-0003：系统符号 + 语义色，不自绘 Material 控件。
 */

import { FailReason } from '../model/auth';
import { TextKeys, textKeyOfFailReason } from '../common/texts';

/**
 * 加载态：居中进度指示。
 *
 * **列表页不要用这个**——内容列表的加载态用 `components/Skeleton.ets` 的 `SkeletonList`
 * （FR-29：骨架才说得出"马上会出现一列内容"）。这里留给详情页、学期选择页这类
 * "一次一个动作"的等待。
 */
@Builder
export function loadingView() {
  Column({ space: 12 }) {
    LoadingProgress()
      .width(48)
      .height(48)
      .color($r('app.color.accent'))
    Text($r('app.string.' + TextKeys.STATE_LOADING))
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
}

/** 空态：系统符号 + 一句说明 */
@Builder
export function emptyView() {
  Column({ space: 12 }) {
    SymbolGlyph($r('sys.symbol.checkmark_circle'))
      .fontSize(48)
      .fontColor([$r('app.color.icon_empty')])
      // 装饰：真正的信息在下面那行文字里（空态/错误分类），图标念出来只是噪音
      .accessibilityLevel('no')
    Text($r('app.string.' + TextKeys.STATE_EMPTY))
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
}

/**
 * 错误态：分类文案 + 重试入口。
 *
 * `reason` 必填（分类是这条反馈的核心）；`onRetry` 为空时不渲染按钮——
 * 没有可重试的动作就不该给用户一个按了没反应的按钮。
 */
@Builder
export function errorView(reason: FailReason, onRetry?: () => void) {
  Column({ space: 12 }) {
    SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
      .fontSize(48)
      .fontColor([$r('app.color.danger')])
      // 装饰：真正的信息在下面那行文字里（空态/错误分类），图标念出来只是噪音
      .accessibilityLevel('no')
    Text($r('app.string.' + textKeyOfFailReason(reason)))
      .fontSize(14)
      .fontColor($r('app.color.text_primary'))
      .textAlign(TextAlign.Center)
      .width('100%')
    if (onRetry !== undefined) {
      Button($r('app.string.' + TextKeys.STATE_RETRY))
        .onClick(() => {
          const retry: () => void = onRetry as () => void;
          retry();
        })
    }
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .padding(24)
}
