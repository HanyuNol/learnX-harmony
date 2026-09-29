/**
 * 启动预载的**纯逻辑**：预载哪些目标、按什么顺序，以及"什么时候不该预载"。
 *
 * 只描述策略，不做任何取数（编排在 `viewmodel/startupSync`）。放在 `common` 是为了能被
 * 穷举测试——这几条判据一旦松掉（学期为空也去拉、课程没拿到就扇出），代价是**启动时
 * 打出一串注定失败的请求**，而那种问题在设备上只表现为"启动慢了一点"，很难归因。
 */

/** 预载目标：通知列表（按课程扇出，单端点） */
export const PREFETCH_NOTICES: string = 'notices';

/** 预载目标：文件列表（按课程扇出，单端点） */
export const PREFETCH_FILES: string = 'files';

/**
 * 本次该预载什么，**顺序即执行顺序**。
 *
 * 判据：学期为空、或一门课都没拿到 → **一个目标都不给**（没有扇出的分母，
 * 发出去也是空转/报错）。否则给"通知 → 文件"两项。
 *
 * **作业不在其中**（FR-25 的范围外，见 `docs/specs/startup-sync.md` §2）：
 * 它每门课要 3 个端点再加逐条详情，是四个维度里最贵的，且属"挑着看"的场景。
 * 这条由单测钉住，防以后被"顺手补上"。
 *
 * 为什么通知在前：它最便宜（单端点、数据量小），且是默认标签页——
 * 串行执行下，先让用户最先看到的那一屏就绪。
 */
export function prefetchTargetsFor(semesterId: string, courseCount: number): string[] {
  if (semesterId.length === 0 || courseCount <= 0) {
    return [];
  }
  return [PREFETCH_NOTICES, PREFETCH_FILES];
}
