/**
 * 最小 Markdown → HTML（**纯逻辑**、可穷举测试）。
 *
 * 用途只有一个：把打进包里的 `CHANGELOG.md` 渲染成"更新日志"页（FR-28）。
 * 为什么自己写：架构不变量 §2 **禁止引入第三方 HTML/Markdown 解析库**，
 * 而变更日志用的 Markdown 语法是一小撮**有限且已知**的构造，按需写最小解析足够。
 *
 * **不追求通用**：只支持本项目自己写的那些构造——标题、有序/无序列表（含一层缩进）、
 * 段落、`**加粗**`、`` `行内代码` ``、``` 围栏代码块 ```、`>` 引用、`---` 分隔线、`[文字](链接)`。
 * 遇到不认识的构造**当普通文本**渲染（宁可朴素，不可丢失）。
 *
 * **安全**：输出仍要过 `common/sanitizeHtml` 白名单清洗（`RichTextView` 会自动做），
 * 这里也先自行转义 `<`/`>`——两道防线，且转义后 Markdown 里的尖括号不会被当成标签。
 *
 * 已知取舍：加粗/链接的替换在行内代码之后**没有**再做保护，所以 `` `**x**` `` 里的星号
 * 也会变粗。变更日志里不会这么写，故不为此加状态机。
 */

/** 围栏代码块的分隔符 */
const FENCE: string = '```';

/** 转义 HTML 的尖括号与和号（`&` 也转，避免 `&lt;` 这类源码被二次解释） */
function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** 行内替换：加粗、行内代码、链接。输入须是**已转义**的文本 */
function inline(text: string): string {
  let out: string = text;
  // 链接：只接受 http(s)，与 sanitizeHtml 的协议白名单一致（其余当普通文本）
  out = out.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2">$1</a>');
  out = out.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  out = out.replace(/`([^`]+)`/g, '<code>$1</code>');
  return out;
}

/** 去掉列表行前缀后剩下的层级：缩进 ≥ 2 个空格算第二层，其余算第一层 */
function listDepthOf(indent: string): number {
  return indent.length >= 2 ? 2 : 1;
}

export function markdownToHtml(markdown: string): string {
  const lines: string[] = markdown.split('\n');
  const html: string[] = [];
  let inCode: boolean = false;
  let openListDepth: number = 0;
  let inQuote: boolean = false;

  const closeLists = (): void => {
    while (openListDepth > 0) {
      html.push('</ul>');
      openListDepth--;
    }
  };
  const closeQuote = (): void => {
    if (inQuote) {
      html.push('</blockquote>');
      inQuote = false;
    }
  };
  /** 段前收尾：列表与引用都要关掉（它们在 Markdown 里不由空行续接） */
  const closeBlocks = (): void => {
    closeLists();
    closeQuote();
  };

  for (const raw of lines) {
    const line: string = raw.replace(/\r$/, '');

    // 围栏代码块：内部原样保留（只转义），不做任何解析
    if (line.trim().startsWith(FENCE)) {
      if (inCode) {
        html.push('</code></pre>');
        inCode = false;
      } else {
        closeBlocks();
        html.push('<pre><code>');
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      html.push(escapeHtml(line) + '\n');
      continue;
    }

    // 空行：关闭所有块级容器
    if (line.trim().length === 0) {
      closeBlocks();
      continue;
    }

    const heading: RegExpMatchArray | null = line.match(/^(#{1,6})\s+(.*)$/);
    if (heading !== null) {
      closeBlocks();
      const level: number = heading[1].length;
      html.push(`<h${level}>${inline(escapeHtml(heading[2].trim()))}</h${level}>`);
      continue;
    }

    if (/^\s*-{3,}\s*$/.test(line)) {
      closeBlocks();
      html.push('<hr>');
      continue;
    }

    const bullet: RegExpMatchArray | null = line.match(/^(\s*)-\s+(.*)$/);
    if (bullet !== null) {
      closeQuote();
      const depth: number = listDepthOf(bullet[1]);
      // 层级变浅：先关到目标层；层级变深：开新的一层
      while (openListDepth > depth) {
        html.push('</ul>');
        openListDepth--;
      }
      if (openListDepth < depth) {
        html.push('<ul>');
        openListDepth++;
      }
      html.push(`<li>${inline(escapeHtml(bullet[2].trim()))}</li>`);
      continue;
    }

    const quoted: RegExpMatchArray | null = line.match(/^>\s?(.*)$/);
    if (quoted !== null) {
      closeLists();
      if (!inQuote) {
        html.push('<blockquote>');
        inQuote = true;
      }
      html.push(`<p>${inline(escapeHtml(quoted[1].trim()))}</p>`);
      continue;
    }

    // 其余：一段独立文本。变更日志是"一行一段"的写法，故不合并连续行
    closeBlocks();
    html.push(`<p>${inline(escapeHtml(line.trim()))}</p>`);
  }

  if (inCode) {
    html.push('</code></pre>');
  }
  closeBlocks();
  return html.join('');
}
