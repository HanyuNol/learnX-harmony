/**
 * Cookie 管理的单元测试。
 *
 * 覆盖：原始 Cookie 串的解析（单条带属性、多条拼接）、属性剔除、
 * 以及按主机名隔离——登录横跨两个主机，隔离错了会串会话。
 */

import { describe, expect, it } from '@ohos/hypium';
import { CookieJar, hostOf, parseCookies } from '../main/ets/network/cookieJar';

export default function cookieJarTest() {
  describe('cookieJar', () => {

    it('应解析单条带属性的 Cookie，并剔除属性', 0, () => {
      const parsed: Map<string, string> = parseCookies('JSESSIONID=abc123; Path=/; HttpOnly; Secure');
      expect(parsed.size).assertEqual(1);
      expect(parsed.get('JSESSIONID')).assertEqual('abc123');
      expect(parsed.get('Path')).assertNull();
      expect(parsed.get('HttpOnly')).assertNull();
    });

    it('应解析多条拼接的 Cookie', 0, () => {
      const parsed: Map<string, string> = parseCookies('a=1; Path=/, b=2; HttpOnly');
      expect(parsed.get('a')).assertEqual('1');
      expect(parsed.get('b')).assertEqual('2');
    });

    it('空串应解析出空集合', 0, () => {
      expect(parseCookies('').size).assertEqual(0);
    });

    it('无等号的片段应被忽略', 0, () => {
      expect(parseCookies('garbage; a=1').size).assertEqual(1);
    });

    it('应从 URL 取出主机名（含端口与路径）', 0, () => {
      expect(hostOf('https://id.tsinghua.edu.cn/do/off?x=1')).assertEqual('id.tsinghua.edu.cn');
      expect(hostOf('https://learn.tsinghua.edu.cn:443/f/wlxt')).assertEqual('learn.tsinghua.edu.cn');
      expect(hostOf('http://127.0.0.1:7897/x')).assertEqual('127.0.0.1');
    });

    it('Cookie 应按主机隔离，不得跨主机发送', 0, () => {
      const jar: CookieJar = new CookieJar();
      jar.store('https://id.tsinghua.edu.cn/login', 'JSESSIONID=id-session; Path=/');

      // 认证主机的 Cookie 只能发给认证主机
      expect(jar.headerFor('https://id.tsinghua.edu.cn/check')).assertEqual('JSESSIONID=id-session');
      // 网络学堂主机此时还没有 Cookie
      expect(jar.headerFor('https://learn.tsinghua.edu.cn/f/wlxt/index')).assertEqual('');
    });

    it('同一主机的多次下发应累积，同名以最新为准', 0, () => {
      const jar: CookieJar = new CookieJar();
      jar.store('https://learn.tsinghua.edu.cn/a', 'SID=old');
      jar.store('https://learn.tsinghua.edu.cn/b', 'SID=new; Path=/');

      expect(jar.headerFor('https://learn.tsinghua.edu.cn/c')).assertEqual('SID=new');
    });

    it('清空后不应再发出任何 Cookie', 0, () => {
      const jar: CookieJar = new CookieJar();
      jar.store('https://learn.tsinghua.edu.cn/a', 'SID=1');
      jar.clear();
      expect(jar.headerFor('https://learn.tsinghua.edu.cn/b')).assertEqual('');
    });
  });
}
