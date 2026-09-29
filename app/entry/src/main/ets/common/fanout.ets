/**
 * 按课程扇出时的**分块参数与切法**（纯逻辑，可穷举测试）。
 *
 * 为什么抽出来（2026-09-28 代码审查 m13）：三个仓储（通知/作业/文件）各自写了一份
 * `const FANOUT_LIMIT = 4` 和同样的 `slice` 循环。这个数字是**对服务器友好的并发上限**，
 * 三处各写一份的代价是"有人调了一个、忘了另两个"，于是各维度的并发悄悄不一致。
 */

/**
 * 同时在飞的课程数上限（每块内并行、块间顺序，见各仓储的说明）。
 *
 * 取值理由（沿用通知那套工程判断）：学堂接口对同一客户端的并发不友好，
 * 12 门课一次全放出去容易被限流或超时；4 是实测能稳住的量级。
 */
export const FANOUT_LIMIT: number = 4;

/**
 * 把数组按每块 `size` 个切开；**不修改入参**，元素顺序不变。
 *
 * `size <= 0` 时返回**空数组**（而不是"一整块"）：那是个非法参数，
 * 静默当成"不分块"会让调用方以为限流生效了，而实际是全量并发——宁可什么都不切。
 */
export function chunksOf<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  if (size <= 0) {
    return chunks;
  }
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}
