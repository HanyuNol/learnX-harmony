/**
 * SM2 密文格式的单元测试。
 *
 * 覆盖 spec §5 第 1 项：输出格式、坐标补零、分量顺序、公钥解析的边界。
 * 这些是与服务端互操作最易出错的地方，必须穷举边界而非只测正常路径。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  bytesToHex,
  bigintToPaddedHex,
  buildRawCipherHex,
  parsePublicKeyHex,
  Sm2PublicKey,
  UNCOMPRESSED_POINT_PREFIX
} from '../main/ets/network/sm2Format';

/** 生成指定长度的字节数组，内容为递增字节 */
function makeBytes(length: number, start: number): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(length);
  for (let i = 0; i < length; i++) {
    bytes[i] = start + i;
  }
  return bytes;
}

export default function sm2FormatTest() {
  describe('sm2Format', () => {

    it('字节数组转十六进制应逐字节补零到两位', 0, () => {
      expect(bytesToHex(new Uint8Array([0, 15, 16, 255]))).assertEqual('000f10ff');
      expect(bytesToHex(new Uint8Array([]))).assertEqual('');
    });

    it('坐标分量应补零到 32 字节', 0, () => {
      expect(bigintToPaddedHex(BigInt(1)).length).assertEqual(64);
      expect(bigintToPaddedHex(BigInt(1))).assertEqual('0'.repeat(63) + '1');
      expect(bigintToPaddedHex(BigInt(0))).assertEqual('0'.repeat(64));
    });

    it('满 32 字节的坐标分量不应被改写', 0, () => {
      const full: bigint = BigInt('0x' + 'f'.repeat(64));
      const hex: string = bigintToPaddedHex(full);
      expect(hex.length).assertEqual(64);
      expect(hex).assertEqual('f'.repeat(64));
    });

    it('超出 32 字节的坐标分量应抛错而非静默截断', 0, () => {
      let threw: boolean = false;
      try {
        bigintToPaddedHex(BigInt('0x1' + '0'.repeat(64)));
      } catch (err) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('密文应为 04 + C1x + C1y + C3 + C2 的裸拼接', 0, () => {
      const c2: Uint8Array = makeBytes(2, 0xAA);
      const c3: Uint8Array = makeBytes(3, 0xBB);
      const result: string = buildRawCipherHex(BigInt(1), BigInt(2), c2, c3);

      const expected: string = UNCOMPRESSED_POINT_PREFIX
        + bigintToPaddedHex(BigInt(1))
        + bigintToPaddedHex(BigInt(2))
        + bytesToHex(c3)
        + bytesToHex(c2);
      expect(result).assertEqual(expected);

      // 顺序断言：C3 必须早于 C2 出现（C1C3C2 而非 C1C2C3）
      expect(result.indexOf(bytesToHex(c3)) < result.indexOf(bytesToHex(c2))).assertTrue();
      // 长度断言：2 + 64 + 64 + (3+2)*2
      expect(result.length).assertEqual(2 + 64 + 64 + 10);
      expect(result.startsWith(UNCOMPRESSED_POINT_PREFIX)).assertTrue();
    });

    it('应解析带 04 前缀的 130 字符公钥', 0, () => {
      const x: string = '1'.repeat(64);
      const y: string = '2'.repeat(64);
      const publicKey: Sm2PublicKey = parsePublicKeyHex(`04${x}${y}`);
      expect(publicKey.x).assertEqual(BigInt(`0x${x}`));
      expect(publicKey.y).assertEqual(BigInt(`0x${y}`));
    });

    it('应解析不带前缀的 128 字符公钥', 0, () => {
      const publicKey: Sm2PublicKey = parsePublicKeyHex(`${'a'.repeat(64)}${'b'.repeat(64)}`);
      expect(publicKey.x).assertEqual(BigInt(`0x${'a'.repeat(64)}`));
      expect(publicKey.y).assertEqual(BigInt(`0x${'b'.repeat(64)}`));
    });

    it('长度异常的公钥应抛错', 0, () => {
      let threw: boolean = false;
      try {
        parsePublicKeyHex('04abcd');
      } catch (err) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('含非十六进制字符的公钥应抛错', 0, () => {
      let threw: boolean = false;
      try {
        parsePublicKeyHex('z'.repeat(128));
      } catch (err) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
