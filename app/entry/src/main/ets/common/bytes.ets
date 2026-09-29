/**
 * 字节缓冲的组装（**纯逻辑**，可穷举测试）。
 *
 * 为什么单独成模块：这件事原先写在 `native/fileAdapter` 与 `native/filePickerAdapter` 里各一份，
 * 而 `native` 依赖平台、宿主侧测不了——于是"读回来的字节对不对"这条判据**从来没有测试**
 * （2026-09-29 审查 R-01 就是这么漏过去的：两份实现都把字节读进了一份**拷贝**里、
 * 结果 buffer 全是零，"另存为"为此写出全零文件、附件上传传全零字节）。
 *
 * 把"反复读、组装、按实际读到的长度收尾"抽成这里的纯函数之后：
 * 平台侧只剩一句"把 chunk 交给 `readSync`"，而组装逻辑与**短读**行为都能在单测里钉死。
 */

/**
 * 调用 `read` 反复读取直到读满 `size` 字节，返回**实际读到的**那一段。
 *
 * `read(chunk)` 的契约：把数据写进给定的 `chunk`（**可能少于** chunk 的长度——即"短读"），
 * 返回写进去的字节数；返回 `<= 0` 表示没有更多数据（文件被截断/读取中断），此时按实际长度收尾。
 *
 * 关键：每次新开一个 `chunk` 读、再**显式拷回**结果缓冲区的对应位置。
 * 反过来写（在结果缓冲区上开一个拷贝去读）就是 R-01 的错法——读进了拷贝，原缓冲区永远是零。
 */
export function readFully(size: number, read: (chunk: ArrayBuffer) => number): ArrayBuffer {
  const buffer: ArrayBuffer = new ArrayBuffer(size > 0 ? size : 0);
  const view: Uint8Array = new Uint8Array(buffer);
  let offset: number = 0;
  while (offset < size) {
    const chunk: ArrayBuffer = new ArrayBuffer(size - offset);
    const got: number = read(chunk);
    if (got <= 0) {
      break;
    }
    // 只拷**实际读到的**那一段：chunk 的尾部可能是零填充（短读），不该进结果
    view.set(new Uint8Array(chunk, 0, got), offset);
    offset += got;
  }
  // 截到实际长度：调用方拿到的长度就是真实内容长度（半截文件不会被当成完整文件）
  return buffer.slice(0, offset);
}
