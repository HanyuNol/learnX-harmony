/**
 * 应用自身信息的适配：系统能力的**唯一出口**（架构不变量 §3）。
 *
 * 为什么要从打包信息读而不是写常量：版本号写在 `AppScope/app.json5` 里，发版时由
 * 发布流程改；在代码里再抄一份必然在发版后与真值不符，而"关于"页正是用户核对版本的地方
 * （settings spec §3.3 第 1 条）。
 */

import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 应用信息的读取结果。读不到时字段为空串，由界面决定显示"未知" */
export class AppInfo {
  readonly versionName: string;
  readonly bundleName: string;

  constructor(versionName: string, bundleName: string) {
    this.versionName = versionName;
    this.bundleName = bundleName;
  }
}

/**
 * 读取本应用的版本名与包名。
 *
 * 读失败**不抛**：关于页读不到版本号不是需要中断用户操作的事，退让为空串即可
 * （空串由界面处理成"未知"）。
 */
export function appInfo(): AppInfo {
  try {
    const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return new AppInfo(info.versionName, info.name);
  } catch (err) {
    const error: BusinessError = err as BusinessError;
    return new AppInfo('', `（读取失败 code=${error.code}）`);
  }
}
