/**
 * SM2 密文格式处理（纯逻辑，**不依赖任何系统能力**）。
 *
 * 单独成文件的理由：这些是与外部服务互操作的关键逻辑，也是最容易出错的地方
 * （坐标补零、分量顺序）。做成无依赖的纯函数才能在单元测试里穷举验证，
 * 且不受设备环境影响。平台加密调用在 sm2.ets。
 *
 * 背景：上游用 JS 的 sm-crypto，其 doEncrypt 输出**裸十六进制**，再前置 '04' 提交。
 * 服务端要的就是这个非 ASN.1 的裸拼接格式，而 HarmonyOS 加密框架产出 ASN.1(DER)，
 * 故必须取分量后手工拼接——这不是冗余代码，是与外部服务互操作的硬约束。
 */

/** 单个坐标分量的字节长度（SM2 为 256 位曲线） */
const COORDINATE_BYTES: number = 32;

/** 椭球点未压缩标识 */
export const UNCOMPRESSED_POINT_PREFIX: string = '04';

/** 十六进制字符集，用于合法性校验 */
const HEX_PATTERN: RegExp = /^[0-9a-fA-F]+$/;

/** 字节数组转小写十六进制串 */
export function bytesToHex(bytes: Uint8Array): string {
  let hex: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const byte: number = bytes[i];
    hex += byte < 16 ? `0${byte.toString(16)}` : byte.toString(16);
  }
  return hex;
}

/**
 * bigint 转为定长（32 字节 = 64 个十六进制字符）的十六进制串，高位补零。
 *
 * 官方文档明确要求：拼接 C1C3C2 密文时，x/y 分量不足 32 字节须高位补零，
 * 否则服务端解析出的点位会错位。
 */
export function bigintToPaddedHex(value: bigint): string {
  let hex: string = value.toString(16);
  if (hex.length > COORDINATE_BYTES * 2) {
    throw new Error(`SM2 坐标分量超出 32 字节：${hex.length} 个十六进制字符`);
  }
  while (hex.length < COORDINATE_BYTES * 2) {
    hex = `0${hex}`;
  }
  return hex;
}

/**
 * 拼装服务端可接受的 SM2 密文提交值。
 *
 * 格式：`04` + C1_X + C1_Y + C3 + C2（C1C3C2 顺序的裸拼接，全小写十六进制）。
 *
 * @param xCoordinate C1 的 x 分量
 * @param yCoordinate C1 的 y 分量
 * @param cipherTextData C2，密文本体
 * @param hashData C3，杂凑值
 */
export function buildRawCipherHex(xCoordinate: bigint, yCoordinate: bigint,
  cipherTextData: Uint8Array, hashData: Uint8Array): string {
  return UNCOMPRESSED_POINT_PREFIX
    + bigintToPaddedHex(xCoordinate)
    + bigintToPaddedHex(yCoordinate)
    + bytesToHex(hashData)
    + bytesToHex(cipherTextData);
}

/** SM2 公钥的坐标 */
export class Sm2PublicKey {
  readonly x: bigint;
  readonly y: bigint;

  constructor(x: bigint, y: bigint) {
    this.x = x;
    this.y = y;
  }
}

/**
 * 解析登录页给出的 SM2 公钥十六进制串。
 *
 * 兼容两种形态：带 `04` 未压缩前缀的 130 字符，以及不带前缀的 128 字符。
 * 长度或字符集不符即抛错——这类问题意味着页面结构变了，
 * 由调用方按上下文归入"接口语义变更"或"解析失败"。
 */
export function parsePublicKeyHex(publicKeyHex: string): Sm2PublicKey {
  let hex: string = publicKeyHex.trim();
  if (hex.startsWith(UNCOMPRESSED_POINT_PREFIX)) {
    hex = hex.substring(UNCOMPRESSED_POINT_PREFIX.length);
  }

  const expectedLength: number = COORDINATE_BYTES * 4;
  if (hex.length !== expectedLength) {
    throw new Error(`SM2 公钥长度异常：期望 ${expectedLength} 个十六进制字符，实际 ${hex.length}`);
  }
  if (!HEX_PATTERN.test(hex)) {
    throw new Error('SM2 公钥含非十六进制字符');
  }

  const half: number = hex.length / 2;
  return new Sm2PublicKey(BigInt(`0x${hex.substring(0, half)}`), BigInt(`0x${hex.substring(half)}`));
}
