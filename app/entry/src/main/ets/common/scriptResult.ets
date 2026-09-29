/**
 * `runJavaScript` 回传值的**解码**（纯逻辑、可穷举测试）。
 *
 * ArkWeb 的 `WebviewController.runJavaScript` 把脚本结果**按 JSON 编码**再回传：
 * 脚本返回字符串时，拿到的会带上一对引号（实测 `document.body.scrollHeight + '|' + n`
 * 回来是 `"74|2"`）。不脱这层引号，`Number('"74')` 就是 `NaN`——
 * `RichTextView` 的高度因此被静默丢弃、组件一直停在最小高度（自动高度形同没做）。
 *
 * 解码失败（不是 JSON，或对端版本变了）**按原样返回**：宁可拿到未解码的值，
 * 也不要因为解析失败让调用方拿到空串。
 */
export function unwrapScriptResult(value: string): string {
  try {
    const parsed: string = JSON.parse(value) as string;
    return typeof parsed === 'string' ? parsed : value;
  } catch (err) {
    return value;
  }
}
