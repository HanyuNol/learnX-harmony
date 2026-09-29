/**
 * 列表加载骨架：按真实行的形状摆出若干行灰条，整块带"呼吸"（1 ↔ 0.5 往返淡入淡出）。
 *
 * 为什么是 `@Component` 而不是像 `StateView` 那样做成全局 `@Builder`：呼吸需要**自己的状态**
 * （`StateView` 里那三个状态是纯展示、无自身状态，故按项目 lint 用 `@Builder` 更划算）。
 *
 * 为什么不是"居中转圈"：列表的等待感来自"不知道要等多少东西"，转圈对"马上会出现一列内容"
 * 一个字都没说。**只在列表里用它**——骨架要有"行"才成立，摆在没有行的地方（详情页）就是骗人。
 *
 * 与上游 `helpers/... Skeleton.tsx` 同一语义（灰条＝占位、整块循环呼吸），但形状按本项目的行重排：
 * 每行三根，高度分别对齐正文的 16 / 14 / 12 号字（标题 / 摘要 / 元信息），
 * 宽度只是"文字长短的示意"，不追求像素级还原（见 `docs/specs/motion-skeleton.md` §2）。
 */

/** 呼吸时长（单程）。与上游 500ms 一来一回同量级 */
const BREATHE_MS: number = 500;

/** 呼吸的低点透明度 */
const DIM_OPACITY: number = 0.5;

/** 骨架根的组件标识：`ui layout` 的节点树据此判定"此刻是骨架而不是转圈"（骨架是瞬时状态，抓拍难） */
const SKELETON_ID: string = 'listSkeleton';

/** 一根灰条：宽度、高度（对齐它所代表的文字的字号） */
@Builder
function bar(width: string, height: number) {
  Column()
    .width(width)
    .height(height)
    .borderRadius(height / 2)
    .backgroundColor($r('app.color.skeleton'))
}

/** 一行占位：标题 / 摘要 / 元信息 */
@Builder
function row() {
  Column({ space: 6 }) {
    bar('60%', 16)
    bar('100%', 14)
    bar('40%', 12)
  }
  .width('100%')
  .padding({ top: 10, bottom: 10 })
}

@Component
export struct SkeletonList {
  /** 占位行数。默认 6 行——够铺满首屏，再多也没人看 */
  rows: number = 6;

  @State private dimmed: boolean = false;

  private breathe(): void {
    // **一次 `animateTo` 就够**：`iterations: -1` 无限次、`Alternate` 往返，由平台管收尾。
    // 不用递归 `onFinish` 的写法——那种版本在组件销毁时还得自己判断要不要再排一次。
    animateTo({
      duration: BREATHE_MS,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.dimmed = true;
    });
  }

  /** 生成 `rows` 个占位行的键（ForEach 要数组，ArkTS 里用不了展开语法） */
  private indices(): number[] {
    const list: number[] = [];
    for (let i = 0; i < this.rows; i++) {
      list.push(i);
    }
    return list;
  }

  aboutToAppear(): void {
    this.breathe();
  }

  build() {
    Column() {
      ForEach(this.indices(), (index: number) => {
        row()
      }, (index: number) => index.toString())
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .opacity(this.dimmed ? DIM_OPACITY : 1)
    .id(SKELETON_ID)
  }
}
