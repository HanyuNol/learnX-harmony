/**
 * 启动预载判据的单元测试（FR-25 / startup-sync spec §3.3）。
 *
 * 钉住两件事：**没有扇出分母时一个目标都不给**、**作业永远不在预载目标里**。
 */

import { describe, expect, it } from '@ohos/hypium';
import { PREFETCH_FILES, PREFETCH_NOTICES, prefetchTargetsFor } from '../main/ets/common/prefetch';

export default function prefetchTest() {
  describe('prefetch', () => {

    it('学期与课程都齐了：通知在前、文件在后', 0, () => {
      const targets: string[] = prefetchTargetsFor('2026-2027-1', 12);
      expect(targets.length).assertEqual(2);
      expect(targets[0]).assertEqual(PREFETCH_NOTICES);
      expect(targets[1]).assertEqual(PREFETCH_FILES);
    });

    it('学期为空 → 不预载（否则会发出一批注定失败的请求）', 0, () => {
      expect(prefetchTargetsFor('', 12).length).assertEqual(0);
    });

    it('一门课都没拿到 → 不预载（按课程扇出没有分母）', 0, () => {
      expect(prefetchTargetsFor('2026-2027-1', 0).length).assertEqual(0);
      expect(prefetchTargetsFor('2026-2027-1', -1).length).assertEqual(0);
    });

    it('作业不在预载目标里（它是最贵的一维，属"挑着看"）', 0, () => {
      const targets: string[] = prefetchTargetsFor('2026-2027-1', 12);
      expect(targets.includes('assignments')).assertFalse();
      expect(targets.length).assertEqual(2);
    });
  });
}
