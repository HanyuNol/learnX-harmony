/**
 * 服务端时间串 → 时间戳（纯函数，无副作用）。
 *
 * 网络学堂的时间字段（作业截止、文件上传时间…）是**本地时间字符串**，没有文档说明格式。
 * 上游完全不做解析、原样交给 `dayjs`（由它按本机时区猜）。这里把常见形态显式列出并
 * 归一化，解析不出返回 0——**不猜**，由调用方按"时间未知"处理。
 *
 * 单独成模块的理由：作业与文件两处都要解析服务端时间，规则只留一份，
 * 顺带让"哪些形态被接受"成为可测的事实。
 */

/**
 * 接受 `YYYY-MM-DD HH:mm[:ss]`、`YYYY/MM/DD HH:mm[:ss]`、ISO（含 `T` 分隔符）。
 *
 * 归一化只做两件事：斜杠换横线、把日期与时间之间的空格换成 `T`——这样
 * `Date.parse` 在各平台上的解释一致（空格形态在部分实现里被视为不可解析）。
 */
export function parseServerTime(raw: string): number {
  const trimmed: string = raw.trim();
  if (trimmed.length === 0) {
    return 0;
  }
  const normalized: string = trimmed.replace(/\//g, '-').replace(' ', 'T');
  const parsed: number = Date.parse(normalized);
  return isNaN(parsed) ? 0 : parsed;
}
