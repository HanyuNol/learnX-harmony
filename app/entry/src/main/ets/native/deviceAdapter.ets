/**
 * 设备信息适配：系统设备信息能力的**唯一出口**（架构不变量 §3）。
 *
 * 用途单一：二次认证登记"信任此浏览器"时，请求体里要带一个设备标识串，
 * 用户在统一身份认证的"信任浏览器数量"列表里靠它分辨哪条是哪台设备——
 * 只写个笼统的 "learnX" 会让"删除旧设备"这件必须做的事无从下手。
 */

import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 设备标识串：优先"外部产品系列"（如 `HUAWEI Mate 60 Pro`，最易辨认），
 * 退回"品牌 + 认证型号"。两者都取不到时返回设备类型，保证非空。
 */
export function deviceLabel(): string {
  const marketName: string = deviceInfo.marketName;
  if (marketName.length > 0) {
    return marketName;
  }

  const brand: string = deviceInfo.brand;
  const model: string = deviceInfo.productModel;
  if (model.length > 0) {
    return brand.length > 0 ? `${brand} ${model}` : model;
  }
  return deviceInfo.deviceType;
}
