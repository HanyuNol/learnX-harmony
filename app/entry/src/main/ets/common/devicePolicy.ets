/**
 * 设备相关的**策略判断**（纯函数，可穷举测试）。
 *
 * 为什么单独放在 `common`（2026-09-28 代码审查 m12）：判断"这台设备能不能选文件夹"是**策略**，
 * 不是系统调用；原先它夹在 `native/deviceAdapter`（只该封装系统能力、不含业务判断）里，
 * 既违反分层，又因为 `native` 依赖平台而在宿主侧测不了。
 */

/** 系统支持"选择文件夹"的设备类型（官方文档：`selectMode = FOLDER` 仅 2-in-1 支持） */
const FOLDER_SELECTION_DEVICE_TYPES: string[] = ['2in1'];

/**
 * 该设备类型是否支持**选择文件夹**。
 *
 * 依据：`DocumentSelectOptions.selectMode = FOLDER` 标注 "Only 2-in-1 devices are supported"，
 * 默认值是 `FILE`——也就是说**手机上调用它会退化成选文件**，用户会看到"选文件"而不是"选目录"
 * （2026-09-28 用户实测反馈）。故不支持时不去调它、也不给这个入口。
 */
export function supportsFolderSelectionOn(deviceType: string): boolean {
  return FOLDER_SELECTION_DEVICE_TYPES.includes(deviceType);
}
