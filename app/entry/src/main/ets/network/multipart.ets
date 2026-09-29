/**
 * multipart/form-data 请求体的构造（**纯逻辑**，不碰网络）。
 *
 * 为什么要自己拼：`@ohos.net.http` 只接受字符串或 `ArrayBuffer` 作为请求体，
 * 而**上传附件**要求请求体里混有**二进制**部分（文件字节），字符串拼不出来。
 * 本项目禁用第三方 HTTP 库（架构不变量 §2），故按 RFC 7578 的最小形态拼：
 * 每个部分＝边界行 + 头部 + 空行 + 内容 + CRLF，最后以 `--边界--` 收尾。
 *
 * 文本部分按 UTF-8 编码（学号、提交内容都是中文环境下的常见内容）。
 */

import { util } from '@kit.ArkTS';
import { MultipartFile } from '../model/multipart';

function utf8(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

/** 把若干字节段拼成一个 `ArrayBuffer` */
function concat(chunks: Uint8Array[]): ArrayBuffer {
  let total: number = 0;
  for (const chunk of chunks) {
    total += chunk.byteLength;
  }
  const out: Uint8Array = new Uint8Array(total);
  let offset: number = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out.buffer as ArrayBuffer;
}

/**
 * 拼出请求体。
 *
 * `file` 为空时**不产生文件部分**——调用方若要表达"移除附件"，应传一个值为 `undefined`
 * 的普通文本字段（服务端的约定，见 `learnClient.submitHomework`）。
 */
export function buildMultipartBody(boundary: string, fields: Map<string, string>,
                                  file: MultipartFile | null): ArrayBuffer {
  const chunks: Uint8Array[] = [];
  fields.forEach((value: string, key: string) => {
    chunks.push(utf8(`--${boundary}\r\nContent-Disposition: form-data; name="${key}"\r\n\r\n${value}\r\n`));
  });

  if (file !== null) {
    chunks.push(utf8(`--${boundary}\r\nContent-Disposition: form-data; name="${file.fieldName}"; `
      + `filename="${file.fileName}"\r\nContent-Type: ${file.contentType}\r\n\r\n`));
    chunks.push(new Uint8Array(file.data));
    chunks.push(utf8('\r\n'));
  }

  chunks.push(utf8(`--${boundary}--\r\n`));
  return concat(chunks);
}
