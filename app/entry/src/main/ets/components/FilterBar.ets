/**
 * 通用筛选条（FR-12）。
 *
 * 四个维度的筛选长得一样、行为一样，各写一份必然走样（有的换行、有的选中态不同色）。
 * 这里收成一处：一行横向可滚动的选项按钮，选中态高亮，点选后回调取值。
 *
 * **文字有两种来源**，因为两类筛选天然不同：
 * - 通知/作业的选项是固定的语义（"全部/未读"），走**文案键**（中英各一份）；
 * - 文件的分类名来自**服务端数据**，只能当**字面量**显示（它没有、也不该有文案键）。
 *
 * 做成全局 `@Builder` 而不是自定义组件：这是**纯展示**、无自身状态，项目 lint 的
 * `avoid-overusing-custom-component-check` 明确要求这种场景用 `@Builder`（与 StateView 一致）。
 *
 * 选中状态由调用方持有（筛选必须留在页面本地，见 list-filter-sort spec §3.3 第 1 条）。
 */

import { TextKeys } from '../common/texts';

/** 一个筛选项：`value` 是取值；`labelKey` 非空时用它取文案，否则用 `labelText` 字面量 */
export class FilterChoice {
  readonly value: string;
  readonly labelKey: string;
  readonly labelText: string;

  constructor(value: string, labelKey: string, labelText: string) {
    this.value = value;
    this.labelKey = labelKey;
    this.labelText = labelText;
  }

  /** 用文案键构造（通知/作业这类固定语义的筛选项） */
  static ofKey(value: string, labelKey: string): FilterChoice {
    return new FilterChoice(value, labelKey, '');
  }

  /** 用字面量构造（服务端数据里的分类名这类） */
  static ofText(value: string, labelText: string): FilterChoice {
    return new FilterChoice(value, '', labelText);
  }
}

/** "全部"选项的取值（空串，文件维度用它表示不筛） */
export const FILTER_ALL: string = '';

/** 构造"全部"这一项 */
export function allChoice(): FilterChoice {
  return FilterChoice.ofKey(FILTER_ALL, TextKeys.FILTER_ALL);
}

/**
 * 渲染筛选条。
 *
 * `onSelect` 为空时点击**静默无效**——调用方必须传（本项目踩过"可选回调漏传"的坑）。
 */
@Builder
export function filterBar(choices: FilterChoice[], selected: string, onSelect: (value: string) => void) {
  Scroll() {
    Row({ space: 8 }) {
      ForEach(choices, (choice: FilterChoice) => {
        // 标签是资源还是字符串必须**分开两支**渲染：`$r` 传变量要求拼全名，
        // 且 Resource 与 string 不能混在同一个 Text 的参数位置（见 common/texts.ets 的说明）
        if (choice.labelKey.length > 0) {
          Button($r('app.string.' + choice.labelKey))
            .fontSize(14)
            .backgroundColor(selected === choice.value ? $r('app.color.accent') : $r('app.color.bg_card'))
            .fontColor(selected === choice.value ? $r('app.color.bg_card') : $r('app.color.text_primary'))
            .onClick(() => {
              onSelect(choice.value);
            })
        } else {
          Button(choice.labelText)
            .fontSize(14)
            .backgroundColor(selected === choice.value ? $r('app.color.accent') : $r('app.color.bg_card'))
            .fontColor(selected === choice.value ? $r('app.color.bg_card') : $r('app.color.text_primary'))
            .onClick(() => {
              onSelect(choice.value);
            })
        }
      }, (choice: FilterChoice) => choice.value)
    }
    .padding({ left: 16, right: 16 })
  }
  .scrollable(ScrollDirection.Horizontal)
  .scrollBar(BarState.Off)
  .width('100%')
  .padding({ top: 8, bottom: 8 })
}
