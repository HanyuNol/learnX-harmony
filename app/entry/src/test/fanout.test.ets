/**
 * 分块切法的单元测试（审查 m13：原先三个仓储各写一份 slice 循环）。
 *
 * 钉住"块数与顺序"以及那条防御规则：**size<=0 返回空**而不是"一整块"
 * （静默返回整块会让调用方以为限流生效了，实际是全量并发）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { FANOUT_LIMIT, chunksOf } from '../main/ets/common/fanout';

export default function fanoutTest() {
  describe('fanout', () => {

    it('按上限切开：整除时每块正好 size 个', 0, () => {
      const chunks: number[][] = chunksOf([1, 2, 3, 4, 5, 6, 7, 8], 4);
      expect(chunks.length).assertEqual(2);
      expect(chunks[0].length).assertEqual(4);
      expect(chunks[1].length).assertEqual(4);
      expect(chunks[0][0]).assertEqual(1);
      expect(chunks[1][3]).assertEqual(8);
    });

    it('有余数时最后一块是零头（12 门课 → 4/4/4）', 0, () => {
      const twelve: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
      const chunks: number[][] = chunksOf(twelve, FANOUT_LIMIT);
      expect(chunks.length).assertEqual(3);
      expect(chunks[2].length).assertEqual(4);

      const thirteen: number[] = twelve.concat([13]);
      const chunks2: number[][] = chunksOf(thirteen, FANOUT_LIMIT);
      expect(chunks2.length).assertEqual(4);
      expect(chunks2[3].length).assertEqual(1);
    });

    it('空数组不产生块', 0, () => {
      expect(chunksOf([], FANOUT_LIMIT).length).assertEqual(0);
    });

    it('size<=0 返回空块（那是非法参数，不能静默当成"不分块"）', 0, () => {
      expect(chunksOf([1, 2, 3], 0).length).assertEqual(0);
      expect(chunksOf([1, 2, 3], -1).length).assertEqual(0);
    });

    it('不改动入参、元素顺序不变', 0, () => {
      const items: string[] = ['a', 'b', 'c', 'd', 'e'];
      const chunks: string[][] = chunksOf(items, 2);
      expect(items.length).assertEqual(5);
      expect(chunks[0][0]).assertEqual('a');
      expect(chunks[2][0]).assertEqual('e');
    });
  });
}
