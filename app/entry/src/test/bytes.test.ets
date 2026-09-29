/**
 * 字节组装（`readFully`）的单元测试——审查 R-01 的**回归防线**。
 *
 * 为什么把用例写成"注入假 reader"：R-01 的根因是"把字节读进了一份拷贝、原缓冲区永远是零"，
 * 那是**组装逻辑**的错，与文件系统无关。把组装抽成纯函数后，用假 reader 就能确定性地复现
 * ——包括**短读**（每次只回几个字节）与**中途 EOF**（返回 0），而这两条恰恰是原实现声称要处理、
 * 实际却没处理好的情形。
 */

import { describe, expect, it } from '@ohos/hypium';
import { readFully } from '../main/ets/common/bytes';

export default function bytesTest() {
  describe('bytes', () => {

    it('一次读满：读回的就是写进去的字节（R-01 的正例）', 0, () => {
      const source: Uint8Array = new Uint8Array([1, 2, 3, 4]);
      const out: Uint8Array = new Uint8Array(readFully(4, (chunk: ArrayBuffer) => {
        new Uint8Array(chunk).set(source);
        return 4;
      }));
      expect(out.length).assertEqual(4);
      expect(out[0]).assertEqual(1);
      expect(out[3]).assertEqual(4);
    });

    it('**短读**也要拼对：每次只回 3 字节 → 3+3+2 拼满 8 字节', 0, () => {
      const source: Uint8Array = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
      let pos: number = 0;
      const out: Uint8Array = new Uint8Array(readFully(8, (chunk: ArrayBuffer) => {
        const n: number = Math.min(3, chunk.byteLength, source.length - pos);
        new Uint8Array(chunk).set(source.subarray(pos, pos + n));
        pos += n;
        return n;
      }));
      expect(out.length).assertEqual(8);
      for (let i = 0; i < 8; i++) {
        expect(out[i]).assertEqual(i + 1);
      }
    });

    it('中途读完（read 返回 0）→ 按**实际**长度收尾，不补零', 0, () => {
      const source: Uint8Array = new Uint8Array([9, 8, 7]);
      let pos: number = 0;
      const out: Uint8Array = new Uint8Array(readFully(10, (chunk: ArrayBuffer) => {
        if (pos >= source.length) {
          return 0;
        }
        const n: number = source.length - pos;
        new Uint8Array(chunk).set(source.subarray(pos));
        pos += n;
        return n;
      }));
      // 声明 10 字节、实际只有 3 字节：长度必须是 3（半截文件不能被当成完整文件）
      expect(out.length).assertEqual(3);
      expect(out[0]).assertEqual(9);
      expect(out[2]).assertEqual(7);
    });

    it('长度为 0 时返回空，且不去调 read', 0, () => {
      let called: number = 0;
      const out: ArrayBuffer = readFully(0, (chunk: ArrayBuffer) => {
        called++;
        return 0;
      });
      expect(out.byteLength).assertEqual(0);
      expect(called).assertEqual(0);
    });

    it('负长度按 0 处理（不构造非法 ArrayBuffer）', 0, () => {
      expect(readFully(-1, (chunk: ArrayBuffer) => 0).byteLength).assertEqual(0);
    });
  });
}
