/**
 * 生物识别的适配：`@kit.UserAuthenticationKit` 的**唯一出口**（架构不变量 §3）。
 *
 * 两个函数，语义界限很清楚：
 * - `biometricUsable()`：**这台设备现在能不能**做指纹/人脸验证（没录入、没硬件都算不能）；
 * - `authenticateBiometric()`：发起一次验证，只回答"过了没有"。
 *
 * **它不产生、也不接触任何凭据**（FR-24 的关键约束，见 `docs/specs/biometric-login.md` §3.3 第 4 条）：
 * `challenge` 传空数组（本场景不防重放，验证结果在本进程内即用即弃），
 * 系统只回一个结果码。**谁是凭据、凭据从哪读**是 `storage.CredentialStore` 的事，与本层无关。
 *
 * 不需要任何权限（`@ohos.userIAM.userAuth` 的普通应用接口）。
 */

import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/logger';

const TAG: string = 'biometric';

/**
 * 信任等级取 `ATL2`（普通应用做"本机解锁"这一档）。
 *
 * 档位越低越容易被系统判定为"可用"，越高越严（`ATL4` 要锁屏密码级别）。取高了会在设备上
 * 直接报 `12500006 信任等级不支持` —— 只需改这一处。
 */
const TRUST_LEVEL: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL2;

/** 某一种认证类型此刻是否可用（`getAvailableStatus` 不可用即抛，故用异常判定） */
function typeUsable(authType: userAuth.UserAuthType): boolean {
  try {
    userAuth.getAvailableStatus(authType, TRUST_LEVEL);
    return true;
  } catch (err) {
    // 12500005 类型不支持 / 12500010 未录入 / 12500013 凭据过期等，都归"这台设备现在用不了"
    Logger.debug(TAG, `生物识别不可用 type=${authType} code=${(err as BusinessError).code}`);
    return false;
  }
}

/** 这台设备现在能否做指纹或人脸验证（两者都不可用才算不可用） */
export function biometricUsable(): boolean {
  return typeUsable(userAuth.UserAuthType.FINGERPRINT) || typeUsable(userAuth.UserAuthType.FACE);
}

/**
 * 发起一次验证。**通过返回 true，其余（取消/失败/系统异常）一律返回 false**——
 * 对调用方来说这些是同一件事："没验证通过，不许用凭据"。细分只在日志里。
 *
 * `title` 是系统验证弹窗的标题，由调用方给（页面负责取本地化文案）。
 */
export async function authenticateBiometric(title: string): Promise<boolean> {
  const authParam: userAuth.AuthParam = {
    // 空 challenge（长度 0）：本场景不防重放，验证结果在本进程内即用即弃
    challenge: new Uint8Array(0),
    authType: [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE],
    authTrustLevel: TRUST_LEVEL
  };
  const widgetParam: userAuth.WidgetParam = { title: title };

  return await new Promise<boolean>((resolve: (passed: boolean) => void) => {
    let settled: boolean = false;
    const finish = (passed: boolean): void => {
      if (!settled) {
        settled = true;
        resolve(passed);
      }
    };
    try {
      const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      // 回调要按 `IAuthCallback` 这个**接口**给（ArkTS 不接受裸箭头函数）
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          const passed: boolean = result.result === userAuth.UserAuthResultCode.SUCCESS;
          Logger.info(TAG, `生物识别结果 code=${result.result} 通过=${passed}`);
          finish(passed);
        }
      };
      instance.on('result', callback);
      instance.start();
    } catch (err) {
      // 发起就失败（参数不被接受、系统忙、档位不支持…）：按"没通过"结束，**不能让 Promise 悬着**
      Logger.warn(TAG, `发起生物识别失败 code=${(err as BusinessError).code}`);
      finish(false);
    }
  });
}
