/**
 * "要不要用已保存凭据恢复登录态"的**纯逻辑判据**（FR-24）。
 *
 * 抽成纯函数只有一个理由：**这张表写错的后果是用户登不进去**——
 * 尤其"设备不可生物识别时要照旧静默恢复"那一行，写成"不可用就不恢复"，
 * 那么所有没有指纹/人脸的老设备（和模拟器）上，勾过「记住密码」的人会全部被挡在登录页。
 * 这种缺陷在开发机上体现不出来，故逐行钉死在用例里。
 *
 * 本模块**不碰任何系统能力**：能生物识别与否由 `native/biometricAdapter` 查，验证由它发起。
 */

/** 处置：没有可用凭据（首次运行 / 没勾「记住密码」）→ 不恢复 */
export const RESTORE_NONE: string = 'none';
/** 处置：**照旧**静默恢复（设备没有生物识别能力，凭空加闸就是制造故障） */
export const RESTORE_SILENT: string = 'silent';
/** 处置：生物识别已通过 → 恢复 */
export const RESTORE_UNLOCKED: string = 'unlocked';

/**
 * 由三件事决定处置（见 `docs/specs/biometric-login.md` §3.3 第 2 条的表）：
 *
 * | 有凭据 | 可生物识别 | 验证通过 | 处置 |
 * |---|---|---|---|
 * | 否 | — | — | `none` |
 * | 是 | 否 | — | `silent`（**不看验证结果**：没发起验证，那个值没有意义） |
 * | 是 | 是 | 是 | `unlocked` |
 * | 是 | 是 | 否 | `none` |
 */
export function decideRestore(hasCredentials: boolean, biometricUsable: boolean,
                              authPassed: boolean): string {
  if (!hasCredentials) {
    return RESTORE_NONE;
  }
  if (!biometricUsable) {
    return RESTORE_SILENT;
  }
  return authPassed ? RESTORE_UNLOCKED : RESTORE_NONE;
}
