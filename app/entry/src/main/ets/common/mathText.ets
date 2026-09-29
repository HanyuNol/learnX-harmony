/**
 * 公式文本的**纯逻辑**：判断正文里有没有公式、以及渲染前的文本规整。
 *
 * 与 `common/sanitizeHtml` 的分工：那份管"安全"（白名单过滤），这份管"数学"（识别与规整）。
 * 两者都是纯函数、都可穷举测试（`testing-and-quality.md` §1.1）。
 *
 * **分工顺序固定**：先清洗、再规整、最后交给 KaTeX 渲染。禁止把服务端内容拼进脚本片段——
 * 公式文本只作为 `renderMathInElement` 的**参数**（它在 DOM 上扫描），不是代码。
 */

/**
 * KaTeX 支持的定界符（与上游 `helpers/html.ts` 的 `renderMathInElement` **默认值一致**）。
 *
 * 注意**不含单 `$...$`**：KaTeX 的 auto-render 默认也不开它，因为正文里成对的 `$`
 * （价格、美元符）会被误当公式。上游同样只用默认值，故本项目保持一致——
 * 若真实数据里出现单 `$` 公式再单独评估（改这一处即可）。
 */
const DELIMITERS: string[] = ['$$', '\\\\(', '\\\\[', '$'];

/**
 * 正文里是否出现公式定界符。
 *
 * 用途：**只在有公式时才注入 KaTeX 脚本**——多数正文没有公式，那它们的 CSP 仍是
 * "禁一切脚本"（见 `docs/adr/0012-katex-for-math-rendering.md` 的"按最小面开脚本"）。
 * 判据取宽（出现 `$` 或 `\(` 就算）：**宁可多注入一次脚本，也不要漏渲染**；
 * 真出现误判，代价只是那一条正文多跑一段脚本。
 */
export function containsMath(raw: string): boolean {
  return raw.includes('$') || raw.includes('\\(') || raw.includes('\\[');
}

/** 该正文会用到哪些定界符（诊断用：日志里记一下，便于判断"是不是定界符没匹配上"） */
export function delimitersPresent(raw: string): string {
  const found: string[] = [];
  for (const delimiter of DELIMITERS) {
    if (raw.includes(delimiter.replace(/\\\\/g, '\\'))) {
      found.push(delimiter.replace(/\\\\/g, '\\'));
    }
  }
  return found.join(' ');
}

/**
 * 渲染前的文本规整：`\mbox{...}` → `\text{...}`。
 *
 * 为什么需要（对齐上游 `helpers/html.ts` 的 `content.replace(/\\mbox/g, '\\text')`）：
 * **KaTeX 不支持 `\mbox`**，而学堂正文里出现过它。不替换就等于那条公式渲染失败
 * （`throwOnError: false` 会把它退回源码——对用户来说仍是"没渲染出来"）。
 *
 * 只做这一处替换：不做别的"智能修正"，猜错了比不做更糟。
 */
export function normalizeMathText(raw: string): string {
  return raw.replace(/\\mbox/g, '\\text');
}
