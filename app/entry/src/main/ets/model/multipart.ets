/**
 * 上传附件时的**文件部分**（跨层共享的类型，按架构不变量 §1 落在 `model`）。
 *
 * 原先它定义在 `network/multipart` 里，于是 `viewmodel`（作业提交）与 `pages`（提交页）
 * 都得从 `network` 取这个类型——那是依赖方向的轻微漂移（审查 m3）。
 * 请求体的**拼装**（RFC 7578 的最小形态）仍留在 `network/multipart`：那是网络层的活。
 *
 * 本文件是叶子层：不 import 任何上层模块，也不碰系统能力（只用到 `ArrayBuffer`）。
 */

/** 一个要上传的文件部分 */
export class MultipartFile {
  /** 表单字段名（如 `fileupload`） */
  readonly fieldName: string;
  /** 传给服务端的文件名 */
  readonly fileName: string;
  /** MIME 类型；未知时用 `application/octet-stream` */
  readonly contentType: string;
  readonly data: ArrayBuffer;

  constructor(fieldName: string, fileName: string, contentType: string, data: ArrayBuffer) {
    this.fieldName = fieldName;
    this.fileName = fileName;
    this.contentType = contentType;
    this.data = data;
  }
}
