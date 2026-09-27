/**
 * 扩展名 → MIME 类型（纯查表，无副作用、可穷举测试）。
 *
 * 为什么要自己写：打开文件时要告诉系统查看器"这是什么类型"，而**禁止引入第三方库**
 * （架构不变量 §2 禁 RN/JS 生态依赖，`mime-types` 正是上游用的那个库）。课件类型是
 * 有限且已知的，查表足够，不需要通用 MIME 库。
 *
 * 未知扩展名退让成 `application/octet-stream`（"二进制流"），由系统决定怎么处理——
 * **不猜**成某个具体类型，猜错会让系统用错误的程序打开。
 */

const DEFAULT_MIME: string = 'application/octet-stream';

const MIME_BY_EXTENSION: Map<string, string> = new Map([
  ['pdf', 'application/pdf'],
  ['doc', 'application/msword'],
  ['docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
  ['ppt', 'application/vnd.ms-powerpoint'],
  ['pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'],
  ['xls', 'application/vnd.ms-excel'],
  ['xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
  ['csv', 'text/csv'],
  ['txt', 'text/plain'],
  ['md', 'text/markdown'],
  ['zip', 'application/zip'],
  ['rar', 'application/vnd.rar'],
  ['7z', 'application/x-7z-compressed'],
  ['gz', 'application/gzip'],
  ['tar', 'application/x-tar'],
  ['png', 'image/png'],
  ['jpg', 'image/jpeg'],
  ['jpeg', 'image/jpeg'],
  ['gif', 'image/gif'],
  ['bmp', 'image/bmp'],
  ['webp', 'image/webp'],
  ['svg', 'image/svg+xml'],
  ['mp3', 'audio/mpeg'],
  ['wav', 'audio/wav'],
  ['m4a', 'audio/mp4'],
  ['mp4', 'video/mp4'],
  ['mov', 'video/quicktime'],
  ['avi', 'video/x-msvideo'],
  ['mkv', 'video/x-matroska'],
  ['html', 'text/html'],
  ['htm', 'text/html'],
  ['json', 'application/json'],
  ['xml', 'application/xml']
]);

/**
 * 取扩展名对应的 MIME。大小写不敏感；扩展名可带前导点也可不带。
 * 未知/为空 → `application/octet-stream`。
 */
export function mimeOfExtension(extension: string): string {
  const normalized: string = extension.trim().toLowerCase().replace(/^\./, '');
  const mime: string | undefined = MIME_BY_EXTENSION.get(normalized);
  return mime === undefined ? DEFAULT_MIME : mime;
}
