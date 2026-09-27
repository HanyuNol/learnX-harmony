/**
 * 远程附件（作业/文件里带的东西）。
 *
 * 语义对齐上游 `thu-learn-lib` 的 `RemoteFile`：**只留本项目要用的三项**——
 * 名字（列表/详情要显示）、下载地址与文件 id（FR-08 下载要用）。
 * 上游还带 previewUrl/size，本项目本批不展示预览与大小，故不留（不预埋字段）。
 */

export class Attachment {
  /** 服务端文件 id（上游从链接的 `fileId` 查询参数取） */
  readonly fileId: string;
  readonly name: string;
  /** 下载地址（绝对地址） */
  readonly downloadUrl: string;

  constructor(fileId: string, name: string, downloadUrl: string) {
    this.fileId = fileId;
    this.name = name;
    this.downloadUrl = downloadUrl;
  }
}
