/**
 * 订阅注册表的单元测试（审查 m13 + R1 的"Store 订阅计数归零"）。
 *
 * 抽取这个纯类的**全部意义**就在这些用例：那几条语义原先散在六个 Store 里、
 * 而 Store 测不了；现在它们是可验的。
 */

import { describe, expect, it } from '@ohos/hypium';
import { SubscriptionRegistry } from '../main/ets/common/subscriptions';

/** 造一个能计数"被通知了几次"的订阅者 */
class Counter {
  hits: number = 0;
  readonly onNotify: (state: string) => void = (state: string) => {
    this.hits++;
  };
}

export default function subscriptionsTest() {
  describe('subscriptions', () => {

    it('订阅后计数为 1；重复订阅同一回调不增加（也不会被通知两次）', 0, () => {
      const registry: SubscriptionRegistry<(s: string) => void> =
        new SubscriptionRegistry<(s: string) => void>();
      const counter: Counter = new Counter();
      registry.subscribe(counter.onNotify);
      registry.subscribe(counter.onNotify);
      expect(registry.listenerCount()).assertEqual(1);
      registry.notifyEach((l: (s: string) => void) => {
        l('snapshot');
      }, (err: Object) => {
        expect(false).assertTrue();
      });
      expect(counter.hits).assertEqual(1);
    });

    it('反订阅后**计数归零**（页面进出成对的判据）', 0, () => {
      const registry: SubscriptionRegistry<(s: string) => void> =
        new SubscriptionRegistry<(s: string) => void>();
      const counter: Counter = new Counter();
      registry.subscribe(counter.onNotify);
      registry.unsubscribe(counter.onNotify);
      expect(registry.listenerCount()).assertEqual(0);
      registry.notifyEach((l: (s: string) => void) => {
        l('snapshot');
      }, (err: Object) => {
        expect(false).assertTrue();
      });
      expect(counter.hits).assertEqual(0);
    });

    it('反订阅没登记过的回调不报错（进出未必成对）', 0, () => {
      const registry: SubscriptionRegistry<(s: string) => void> =
        new SubscriptionRegistry<(s: string) => void>();
      const counter: Counter = new Counter();
      registry.unsubscribe(counter.onNotify);
      expect(registry.listenerCount()).assertEqual(0);
    });

    it('通知遍历快照：回调里反订阅自己，本轮仍只收到一次', 0, () => {
      const registry: SubscriptionRegistry<(s: string) => void> =
        new SubscriptionRegistry<(s: string) => void>();
      const counter: Counter = new Counter();
      const selfRemoving: (s: string) => void = (state: string) => {
        counter.hits++;
        registry.unsubscribe(selfRemoving);
      };
      registry.subscribe(selfRemoving);
      registry.notifyEach((l: (s: string) => void) => {
        l('snapshot');
      }, (err: Object) => {
        expect(false).assertTrue();
      });
      expect(counter.hits).assertEqual(1);
      expect(registry.listenerCount()).assertEqual(0);
    });

    it('单个回调抛错只隔离它自己：其余订阅者照常收到通知，错误交给 onError', 0, () => {
      const registry: SubscriptionRegistry<(s: string) => void> =
        new SubscriptionRegistry<(s: string) => void>();
      const healthy: Counter = new Counter();
      let errors: number = 0;
      const boom: (s: string) => void = (state: string) => {
        throw new Error('订阅者自己炸了');
      };
      registry.subscribe(boom);
      registry.subscribe(healthy.onNotify);
      registry.notifyEach((l: (s: string) => void) => {
        l('snapshot');
      }, (err: Object) => {
        errors++;
      });
      expect(errors).assertEqual(1);
      expect(healthy.hits).assertEqual(1);
    });
  });
}
