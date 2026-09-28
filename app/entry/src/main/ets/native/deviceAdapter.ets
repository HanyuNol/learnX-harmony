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

/** 设备类型原始串（`phone` / `tablet` / `2in1` / …，取自系统） */
export function deviceType(): string {
  return deviceInfo.deviceType;
}

/**
 * 本设备是否支持**选择文件夹**。
 *
 * 依据系统文档：`DocumentSelectOptions.selectMode = FOLDER` 标注
 * "**Only 2-in-1 devices are supported**"，默认值是 `FILE`——也就是说**手机上调用它会退化成选文件**，
 * 用户看到的会是"选文件"而不是"选目录"（2026-09-28 用户实测反馈）。
 * 故这里显式判断设备类型，不支持时不去调它、也不给这个按钮，免得给出一个必然失败或
 * 语义错误的入口。
 */
export function supportsFolderSelection(): boolean {
  return deviceInfo.deviceType === '2in1';
}
