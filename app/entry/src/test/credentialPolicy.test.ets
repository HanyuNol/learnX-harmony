/**
 * CSRF 注入规则与凭据保存次序的单元测试。
 *
 * 这两条都属 `testing-and-quality` §2 的必测高风险区（2026-09-28 代码审查 R1）：
 * - **漏注入 CSRF 会让所有 POST 被 403 挡掉**，且现象容易被误当成认证问题；
 * - **凭据写入与清除必须成对**，次序错了会留下与用户选择相悖的残留。
 * 原先它们分别埋在 `LearnClient` 的私有方法与平台调用里，宿主侧测不到；现已抽为纯函数。
 */

import { describe, expect, it } from '@ohos/hypium';
import { withCsrfToken } from '../main/ets/network/csrfUrl';
import { CredentialOp, credentialSavePlan } from '../main/ets/model/auth';

export default function credentialPolicyTest() {
  describe('csrfUrl', () => {

    it('学堂请求必带令牌；非清华域名不带', 0, () => {
      const learn: string = 'https://learn.tsinghua.edu.cn/b/x';
      expect(withCsrfToken(learn, 'T1').includes('_csrf=T1')).assertTrue();
      const other: string = 'https://example.com/x';
      expect(withCsrfToken(other, 'T1').includes('_csrf')).assertFalse();
    });

    it('统一身份认证域**当前也会带上**令牌（与上游的已知偏差，如实钉住）', 0, () => {
      // 上游只让学堂请求带（它的认证域请求不走那条路径）；本项目对两域一视同仁。
      // 设备实测登录可用，故保留现状；这条用例是**记录现状**，不是"期望如此"——
      // 若将来收窄到 learn 域，这条会失败，正是提醒去真机复验登录的信号
      const idDomain: string = 'https://id.tsinghua.edu.cn/do/off/ui/auth/login/check';
      expect(withCsrfToken(idDomain, 'T1').includes('_csrf=T1')).assertTrue();
    });

    it('令牌为空时不注入（会话还没建立）', 0, () => {
      const learn: string = 'https://learn.tsinghua.edu.cn/b/x';
      expect(withCsrfToken(learn, '')).assertEqual(learn);
    });

    it('已有查询串用 & 连接，否则用 ?', 0, () => {
      expect(withCsrfToken('https://learn.tsinghua.edu.cn/b/x?a=1', 'T'))
        .assertEqual('https://learn.tsinghua.edu.cn/b/x?a=1&_csrf=T');
      expect(withCsrfToken('https://learn.tsinghua.edu.cn/b/x', 'T'))
        .assertEqual('https://learn.tsinghua.edu.cn/b/x?_csrf=T');
    });
  });

  describe('credentialSavePlan', () => {

    it('未勾选"记住密码"：**第一步就是删密码**（fail-closed，不留旧密码）', 0, () => {
      const plan: CredentialOp[] = credentialSavePlan(false);
      expect(plan[0]).assertEqual(CredentialOp.DELETE_PASSWORD);
      expect(plan.includes(CredentialOp.WRITE_PASSWORD)).assertFalse();
    });

    it('勾选"记住密码"：密码**写在最后**（前面失败不会留下与学号不匹配的密码）', 0, () => {
      const plan: CredentialOp[] = credentialSavePlan(true);
      expect(plan.includes(CredentialOp.DELETE_PASSWORD)).assertFalse();
      expect(plan[plan.length - 1]).assertEqual(CredentialOp.WRITE_PASSWORD);
      expect(plan[0]).assertEqual(CredentialOp.WRITE_USERNAME);
    });
  });
}
