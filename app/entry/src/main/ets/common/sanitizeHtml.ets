/**
 * 服务端 HTML 的**白名单清洗**（纯逻辑，零系统依赖，可宿主侧穷举测试）。
 *
 * 为什么必须有它：通知与作业的正文是**服务端给的 HTML**，上游直接塞进 WebView 渲染
 * （`helpers/html.ts` 的 `getWebViewTemplate` + `AutoHeightWebView`）。而 `SECURITY.md` §3 要求
 * **不得整体信任服务端 HTML**——学堂的正文理论上可能被课程参与者写入（讨论/作业描述一类），
 * 一旦其中带 `<script>`、`onerror=` 或 `javascript:` 链接，塞进 WebView 就等于**执行任意脚本**。
 *
 * 规则：**白名单**（不在表里的一律丢掉），不是黑名单（黑名单永远列不全）。
 * 三条边界：
 * 1. 标签：只留排版与图片相关的一小撮；`script`/`style`/`iframe`/`object`/`embed`/`svg`/`form`
 *    一类**连同内容一起丢**（丢标签留正文会把脚本源码显示成乱文本）；
 * 2. 属性：只留白名单里的，且**事件属性（`on*`）一律丢**；`style`/`class`/`id` 也丢
 *    （样式由我们自己的模板给，服务端的内联样式既不可控又能被用来做钓鱼式排版）；
 * 3. 链接：`href`/`src` 只接受 `http`/`https` 与 `data:image/(png|jpeg|gif|webp)`；
 *    `javascript:` / `data:text/html` / `data:image/svg+xml`（SVG 可带脚本）**一律丢属性**。
 *
 * 相对地址按调用方给的 `baseUrl` 补成绝对地址（学堂正文里的图片多是相对路径，
 * 不补的话在 Web 里就是空图）。
 *
 * 不引第三方 HTML 解析库（架构不变量 §2）：按实际需要的标签写最小解析器——这也让
 * "哪些标签/属性被允许"成为**可枚举、可测试**的事实。
 */

/** 允许保留的标签（小写）。表外的一律丢标签，内容按"是否危险"决定留或丢 */
const ALLOWED_TAGS: string[] = [
  'p', 'br', 'div', 'span', 'strong', 'b', 'em', 'i', 'u', 's', 'del', 'ins', 'sub', 'sup',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'li', 'blockquote', 'code', 'pre', 'hr',
  'a', 'img', 'table', 'thead', 'tbody', 'tr', 'td', 'th', 'caption', 'figure', 'figcaption'
];

/** 这些标签**连同内容一起丢**：它们的内容不是"正文"，留下只会变成乱文本或可执行片段 */
const DROPPED_WITH_CONTENT: string[] = [
  'script', 'style', 'iframe', 'object', 'embed', 'noscript', 'template', 'svg', 'math',
  'form', 'input', 'button', 'select', 'textarea', 'link', 'meta', 'title', 'head', 'base'
];

/** 允许保留的属性（按标签） */
const ALLOWED_ATTRS: string[] = ['href', 'src', 'alt', 'title', 'width', 'height', 'colspan', 'rowspan'];

/** 允许的链接协议（其余一律丢属性） */
const ALLOWED_SCHEMES: string[] = ['http:', 'https:'];

/** 允许的 `data:` 图片类型（**不含 svg**：SVG 能带脚本） */
const ALLOWED_DATA_IMAGE: string[] = ['data:image/png', 'data:image/jpeg', 'data:image/gif',
  'data:image/webp', 'data:image/bmp'];

function isAllowedTag(tag: string): boolean {
  return ALLOWED_TAGS.includes(tag);
}

function isDroppedWithContent(tag: string): boolean {
  return DROPPED_WITH_CONTENT.includes(tag);
}

/** 取 URL 的协议前缀（小写、去掉空白与控制字符——`java\nscript:` 这类绕过要先剥掉再判） */
function schemeOf(url: string): string {
  let cleaned: string = '';
  for (let i: number = 0; i < url.length; i++) {
    const ch: string = url.charAt(i);
    if (ch === '\t' || ch === '\n' || ch === '\r' || ch === ' ') {
      continue;
    }
    cleaned += ch;
  }
  const colon: number = cleaned.indexOf(':');
  if (colon < 0) {
    return '';
  }
  return cleaned.substring(0, colon + 1).toLowerCase();
}

/**
 * URL 是否可用。**相对地址允许**（后续按 baseUrl 补成绝对地址）；
 * 有协议时只认 http/https 与白名单里的 data:image。
 */
function isAllowedUrl(url: string): boolean {
  const scheme: string = schemeOf(url);
  if (scheme.length === 0) {
    // 相对地址（`/b/xxx`、`images/a.png`、`#anchor`）：交给 baseUrl 补全
    return true;
  }
  if (ALLOWED_SCHEMES.includes(scheme)) {
    return true;
  }
  const lowered: string = url.toLowerCase();
  for (const prefix of ALLOWED_DATA_IMAGE) {
    if (lowered.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

/**
 * 转义正文文本里的 `<` 与 `>`。
 *
 * **刻意不动 `&`**：正文里的 `&lt;`/`&amp;` 是**实体**，浏览器会解码成字符；
 * 若把 `&` 也转义一遍，用户就会看到字面量 `&lt;`（正文里这种实体很常见）。
 * 安全性不受影响——标签是在**词法层**识别的，这里的 `<`/`>` 转义保证文本不会重新拼出标签。
 */
function escapeText(text: string): string {
  return text.replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** 转义属性值（含引号） */
function escapeAttr(value: string): string {
  return value.replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/** 把相对地址补成绝对地址；已是绝对或 `data:` 的原样返回 */
export function absolutize(url: string, baseUrl: string): string {
  const trimmed: string = url.trim();
  if (trimmed.length === 0 || baseUrl.length === 0) {
    return trimmed;
  }
  const lowered: string = trimmed.toLowerCase();
  if (lowered.startsWith('http:') || lowered.startsWith('https:') || lowered.startsWith('data:')
    || lowered.startsWith('#') || lowered.startsWith('mailto:')) {
    return trimmed;
  }
  if (trimmed.startsWith('//')) {
    return `https:${trimmed}`;
  }
  const base: string = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  if (trimmed.startsWith('/')) {
    // 站点根路径：只取 baseUrl 的协议 + 主机
    const schemeEnd: number = base.indexOf('://');
    if (schemeEnd < 0) {
      return trimmed;
    }
    const afterScheme: number = base.indexOf('/', schemeEnd + 3);
    const host: string = afterScheme < 0 ? base : base.substring(0, afterScheme);
    return `${host}${trimmed}`;
  }
  return `${base}/${trimmed}`;
}

/** 一个标签的解析结果 */
class TagToken {
  readonly name: string;
  readonly attrs: Map<string, string>;
  readonly closing: boolean;

  constructor(name: string, attrs: Map<string, string>, closing: boolean) {
    this.name = name;
    this.attrs = attrs;
    this.closing = closing;
  }
}

/** 解析 `<...>` 的内容（标签名 + 属性）。属性只认 `k="v"` / `k='v'` / `k=v` / `k` */
function parseTag(raw: string): TagToken | null {
  const trimmed: string = raw.trim();
  if (trimmed.length === 0) {
    return null;
  }
  let index: number = 0;
  const closing: boolean = trimmed.charAt(0) === '/';
  if (closing) {
    index = 1;
  }
  let name: string = '';
  while (index < trimmed.length) {
    const ch: string = trimmed.charAt(index);
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '/' || ch === '>') {
      break;
    }
    name += ch;
    index++;
  }
  name = name.toLowerCase();
  if (name.length === 0) {
    return null;
  }

  const attrs: Map<string, string> = new Map();
  while (index < trimmed.length) {
    // 跳过空白与斜杠
    while (index < trimmed.length && ' \t\n\r/'.includes(trimmed.charAt(index))) {
      index++;
    }
    if (index >= trimmed.length) {
      break;
    }
    let key: string = '';
    while (index < trimmed.length) {
      const ch: string = trimmed.charAt(index);
      if (ch === '=' || ch === ' ' || ch === '\t' || ch === '\n' || ch === '/') {
        break;
      }
      key += ch;
      index++;
    }
    key = key.toLowerCase();
    if (key.length === 0) {
      index++;
      continue;
    }
    let value: string = '';
    // 跳过 `=` 两侧空白
    while (index < trimmed.length && ' \t\n'.includes(trimmed.charAt(index))) {
      index++;
    }
    if (index < trimmed.length && trimmed.charAt(index) === '=') {
      index++;
      while (index < trimmed.length && ' \t\n'.includes(trimmed.charAt(index))) {
        index++;
      }
      if (index < trimmed.length && (trimmed.charAt(index) === '"' || trimmed.charAt(index) === '\'')) {
        const quote: string = trimmed.charAt(index);
        index++;
        while (index < trimmed.length && trimmed.charAt(index) !== quote) {
          value += trimmed.charAt(index);
          index++;
        }
        index++;
      } else {
        while (index < trimmed.length && !' \t\n/'.includes(trimmed.charAt(index))) {
          value += trimmed.charAt(index);
          index++;
        }
      }
    }
    // 同名属性以**第一次**出现为准（`href="safe" href="javascript:..."` 这类绕过）
    if (!attrs.has(key)) {
      attrs.set(key, value);
    }
  }
  return new TagToken(name, attrs, closing);
}

/** 把标签重新拼成安全的 HTML 片段（只输出白名单里的标签与属性） */
function rebuildTag(token: TagToken, baseUrl: string): string {
  if (!isAllowedTag(token.name)) {
    // 表外标签：丢标签本身（内容由调用方决定留或丢）
    return '';
  }
  if (token.closing) {
    return `</${token.name}>`;
  }
  let out: string = `<${token.name}`;
  token.attrs.forEach((value: string, key: string) => {
    if (!ALLOWED_ATTRS.includes(key)) {
      return;
    }
    if (key === 'href' || key === 'src') {
      if (!isAllowedUrl(value)) {
        return;
      }
      const absolute: string = absolutize(value, baseUrl);
      out += ` ${key}="${escapeAttr(absolute)}"`;
      return;
    }
    if (key === 'width' || key === 'height' || key === 'colspan' || key === 'rowspan') {
      // 只接受数字：`width="100%"` 一类表达式在 Web 里没意义，还可能撑破布局
      const numeric: boolean = /^\d{1,4}$/.test(value.trim());
      if (!numeric) {
        return;
      }
      out += ` ${key}="${value.trim()}"`;
      return;
    }
    out += ` ${key}="${escapeAttr(value)}"`;
  });
  if (token.name === 'a') {
    // 链接一律新窗口语义 + 不可被用来操作 opener（渲染层还会拦截导航）
    out += ' rel="noopener noreferrer"';
  }
  out += '>';
  return out;
}

/**
 * 清洗服务端 HTML：只留白名单标签与属性，其余丢弃。
 *
 * `baseUrl` 用于把正文里的相对图片/链接补成绝对地址（学堂正文多是相对路径）。
 * 空串表示不做补全。
 */
export function sanitizeHtml(raw: string, baseUrl: string): string {
  let out: string = '';
  let index: number = 0;
  // "连同内容一起丢"的标签，用计数处理嵌套（`<div><script>…</script></div>`）
  let dropDepth: number = 0;
  let dropTag: string = '';

  while (index < raw.length) {
    const lt: number = raw.indexOf('<', index);
    if (lt < 0) {
      if (dropDepth === 0) {
        out += escapeText(raw.substring(index));
      }
      break;
    }
    if (lt > index && dropDepth === 0) {
      out += escapeText(raw.substring(index, lt));
    }

    // 注释与 doctype：整段丢
    if (raw.startsWith('<!--', lt)) {
      const endComment: number = raw.indexOf('-->', lt + 4);
      index = endComment < 0 ? raw.length : endComment + 3;
      continue;
    }
    if (raw.startsWith('<!', lt)) {
      const endDecl: number = raw.indexOf('>', lt + 2);
      index = endDecl < 0 ? raw.length : endDecl + 1;
      continue;
    }

    const gt: number = raw.indexOf('>', lt + 1);
    if (gt < 0) {
      // 没有闭合的 `<`：当普通文本（转义后输出），不猜
      if (dropDepth === 0) {
        out += escapeText(raw.substring(lt));
      }
      break;
    }
    const token: TagToken | null = parseTag(raw.substring(lt + 1, gt));
    index = gt + 1;
    if (token === null) {
      continue;
    }

    if (dropDepth > 0) {
      // 正在丢弃的子树里：只找它的闭合标签
      if (token.closing && token.name === dropTag) {
        dropDepth--;
        if (dropDepth === 0) {
          dropTag = '';
        }
      } else if (!token.closing && token.name === dropTag) {
        dropDepth++;
      }
      continue;
    }

    if (isDroppedWithContent(token.name)) {
      if (!token.closing) {
        dropDepth = 1;
        dropTag = token.name;
      }
      continue;
    }

    out += rebuildTag(token, baseUrl);
  }
  return out;
}
