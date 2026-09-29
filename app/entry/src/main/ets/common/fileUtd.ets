/**
 * 扩展名 → UTD（统一类型描述符）的**纯查表**（无副作用、可穷举测试）。
 *
 * 为什么单独一份、不复用 `common/mime.ets`：MIME 与 UTD 是**两套**类型体系——
 * MIME 给系统查看器（`startAbility` 的 `type`），UTD 给系统分享面板
 * （`SharedRecord.utd`，取自 `@ohos.data.uniformTypeDescriptor`）。两者取值不同、
 * 用途不同，混用会得到"系统按错误类型处理"的静默差错。
 *
 * 表里只放**已确认存在**的 UTD 常量（对着 `@ohos.data.uniformTypeDescriptor.d.ts`
 * 的 `UniformDataType` 枚举抄的），**不猜**字符串：编造一个不存在的 UTD 会让
 * `ShareController.show` 报 `1003702001 记录类型不支持`。
 * 课件里罕见的类型（`docx/xlsx/pptx/网页存档…`）**退让成 `general.file`**——
 * "一个通用文件"是实话，比猜一个更细的类型安全。
 */

/** 认不出类型时的退让值（`UniformDataType.FILE`） */
const DEFAULT_UTD: string = 'general.file';

const UTD_BY_EXTENSION: Map<string, string> = new Map([
  ['pdf', 'com.adobe.pdf'],
  ['doc', 'com.microsoft.word.doc'],
  ['txt', 'general.plain-text'],
  ['md', 'general.markdown'],
  ['csv', 'general.comma-separated-values-text'],
  ['html', 'general.html'],
  ['htm', 'general.html'],
  ['png', 'general.png'],
  ['jpg', 'general.jpeg'],
  ['jpeg', 'general.jpeg'],
  ['gif', 'general.gif'],
  ['bmp', 'com.microsoft.bmp'],
  // 有具体 UTD 就写具体，没有的归到上位类型（图形/压缩包/视频）
  ['webp', 'general.image'],
  ['svg', 'general.image'],
  ['zip', 'general.zip-archive'],
  ['rar', 'com.rarlab.rar-archive'],
  ['tar', 'general.tar-archive'],
  ['gz', 'general.archive'],
  ['7z', 'general.archive'],
  ['mp3', 'general.mpeg-audio'],
  ['wav', 'com.microsoft.waveform-audio'],
  ['m4a', 'general.mpeg-4-audio'],
  ['mp4', 'general.video'],
  ['mov', 'general.video'],
  ['avi', 'general.video'],
  ['mkv', 'general.video']
]);

/**
 * 取扩展名对应的 UTD。大小写不敏感；扩展名可带前导点也可不带。
 * 未知/为空 → `general.file`。
 */
export function utdOfExtension(extension: string): string {
  const normalized: string = extension.trim().toLowerCase().replace(/^\./, '');
  const utd: string | undefined = UTD_BY_EXTENSION.get(normalized);
  return utd === undefined ? DEFAULT_UTD : utd;
}
