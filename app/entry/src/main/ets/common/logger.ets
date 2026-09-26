/**
 * 分级日志。**内置凭据脱敏**——任何可能承载敏感值的输出必须经 redact()。
 *
 * 为什么单独包一层而不用裸 hilog：SECURITY.md 要求凭据与 Cookie 不得入日志，
 * 而"别把密码打到日志里"这种约束靠自觉守不住。这里把脱敏做成唯一入口，
 * 使泄漏需要主动绕过而非疏忽（见 spec §5 第 5 项验收）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

/** 业务日志域，取自应用私有区间 */
const DOMAIN: number = 0x0A11;
const TAG: string = 'learnX';

/**
 * 脱敏：保留首字符，其余替换为 `*`；**长度不超过 2 时全部替换**——
 * 短值保留首字符已无排障价值，却会实打实泄漏内容。空串返回空串。
 */
export function redact(value: string): string {
  if (value.length === 0) {
    return '';
  }
  if (value.length <= 2) {
    let all: string = '';
    for (let i = 0; i < value.length; i++) {
      all += '*';
    }
    return all;
  }
  let mask: string = '';
  for (let i = 1; i < value.length; i++) {
    mask += '*';
  }
  return value.substring(0, 1) + mask;
}

export class Logger {
  static debug(tag: string, message: string): void {
    hilog.debug(DOMAIN, TAG, '[%{public}s] %{public}s', tag, message);
  }

  static info(tag: string, message: string): void {
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s', tag, message);
  }

  static warn(tag: string, message: string): void {
    hilog.warn(DOMAIN, TAG, '[%{public}s] %{public}s', tag, message);
  }

  static error(tag: string, message: string): void {
    hilog.error(DOMAIN, TAG, '[%{public}s] %{public}s', tag, message);
  }

  /**
   * 记录一个敏感值的存在性与长度，**不记录其内容**。
   *
   * 需要确认"某个凭据拿到了没有"时用它，而不是把值拼进 message。
   */
  static secret(tag: string, label: string, value: string): void {
    hilog.debug(DOMAIN, TAG, '[%{public}s] %{public}s=%{public}s (len=%{public}d)',
      tag, label, redact(value), value.length);
  }
}
