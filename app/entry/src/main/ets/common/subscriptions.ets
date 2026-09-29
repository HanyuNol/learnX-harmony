/**
 * 订阅注册表（**纯类**，无平台依赖、无副作用，可穷举测试）。
 *
 * 为什么要有它（2026-09-28 代码审查 m13 + R1）：六个 Store 各自逐字重复了
 * `listeners` 数组 + subscribe/unsubscribe/listenerCount + 通知循环；
 * 而"订阅计数归零"是 `testing-and-quality` §2 点名的高风险区，**Store 本身 import 平台、
 * 宿主侧测不了**，于是这一块一直没有测试。把它抽成纯类之后：
 * 去重、反订阅、计数、通知时的隔离与遍历语义**都能在单测里钉住**，Store 只剩一行接线。
 *
 * 语义（与抽取前逐字一致，重构不改行为）：
 * - **重复订阅同一回调不重复登记**，但 `subscribe` 的调用方仍会立即收到一次快照
 *   （那是 Store 的行为：`subscribe` 之后紧接着 `listener(snapshot())`）；
 * - **通知遍历的是快照**：回调里自行订阅/反订阅不会让本轮跳过或重复通知；
 * - **单个回调抛错只隔离它自己**：其余订阅者照常收到通知（错误交给调用方记录）。
 */

export class SubscriptionRegistry<T> {
  private listeners: T[] = [];

  /**
   * 登记订阅者；**已登记过则不变**（避免同一回调被通知两次）。
   *
   * 返回是否是新登记——调用方据此决定要不要额外做什么（Store 目前不看返回值，
   * 仍是无条件把快照推给传入的回调，与重构前一致）。
   */
  subscribe(listener: T): boolean {
    if (this.listeners.includes(listener)) {
      return false;
    }
    this.listeners.push(listener);
    return true;
  }

  /** 反订阅；**没登记过也不报错**（页面 onDisappear 与 onAppear 未必成对触发） */
  unsubscribe(listener: T): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前订阅者数量。页面与测试用它核对"进出平衡"（计数必须能归零） */
  listenerCount(): number {
    return this.listeners.length;
  }

  /**
   * 逐个通知。`deliver` 负责把快照交给某个订阅者，`onError` 负责记录被隔离的异常
   * （日志是调用方的事——本类是纯的，不碰平台）。
   */
  notifyEach(deliver: (listener: T) => void, onError: (err: Object) => void): void {
    // 遍历**副本**：回调里自行 subscribe/unsubscribe 会改动原数组，
    // 直接遍历原数组会跳过或重复回调（抽取前各 Store 已有此注释与实现）
    const current: T[] = this.listeners.slice();
    for (const listener of current) {
      try {
        deliver(listener);
      } catch (err) {
        onError(err as Object);
      }
    }
  }
}
