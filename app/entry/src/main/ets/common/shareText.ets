/**
 * 组装"分享出去的正文文本"的**纯逻辑**（FR-23 的文本一半）。
 *
 * 为什么要有规则、而不是 `title + '\n' + body` 一拼了事：
 * 分享出去的东西会落到别人的聊天窗口/备忘录里，多余的空行、首尾空白、空标题留下的孤零零
 * 一个换行都很显眼；而正文本身可能很长（服务端 HTML 剥出来动辄几千字），
 * 交给系统分享面板的 IPC 有体积上限（官方错误码 `1003702002`）。
 *
 * 三条规则：**空的部分不留空行**、**连续空行压成一个空行**、**超长截断**。
 */

/** 分享文本的长度上限（超出截断并加省略号）。通知正文通常几十到几百字，这是防线不是常态 */
const MAX_SHARE_CHARS: number = 4000;

/** 截断时补的省略号 */
const ELLIPSIS: string = '…';

/** 压掉首尾空白与"三个以上连续换行"（保留一个空行作为段落间隔） */
function tidy(text: string): string {
  return text
    .replace(/\r\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

/**
 * 把标题与正文拼成分享用的纯文本。
 *
 * - 只有标题、或只有正文，都只产出那一部分（**不留空行**——那是"缺一半"的痕迹）；
 * - 两者都没有 → 返回空串，调用方据此不发分享（分享一条空白没有意义）；
 * - 超过 `MAX_SHARE_CHARS` 就截断加省略号。
 */
export function composeShareText(title: string, body: string): string {
  const parts: string[] = [];
  const cleanTitle: string = tidy(title);
  const cleanBody: string = tidy(body);
  if (cleanTitle.length > 0) {
    parts.push(cleanTitle);
  }
  if (cleanBody.length > 0) {
    parts.push(cleanBody);
  }
  const joined: string = parts.join('\n\n');
  if (joined.length <= MAX_SHARE_CHARS) {
    return joined;
  }
  return joined.substring(0, MAX_SHARE_CHARS) + ELLIPSIS;
}
