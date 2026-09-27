/**
 * Set-Cookie 头切分的单元测试。
 *
 * 为什么值得测死：`configCookieSync` 每次只接受一条 Cookie，而服务端下发的可能是
 * 合并的一整串。切错（尤其被 `Expires` 里的逗号骗到）会让会话 Cookie 写不进去，
 * 表现为"登录成功但下一步就失效"——最难从现象反推原因的一类故障。
 */

import { describe, expect, it } from '@ohos/hypium';
import { splitSetCookie } from '../main/ets/network/setCookie';

export default function setCookieTest() {
  describe('splitSetCookie', () => {

    it('单条带属性的 Cookie 应原样保留属性', 0, () => {
      const cookies: string[] = splitSetCookie('JSESSIONID=abc123; Path=/; HttpOnly');
      expect(cookies.length).assertEqual(1);
      // 属性必须保留：Path 决定作用域、HttpOnly 决定写入时要不要放行
      expect(cookies[0]).assertEqual('JSESSIONID=abc123; Path=/; HttpOnly');
    });

    it('Expires 里的逗号不应被当成 Cookie 分隔符', 0, () => {
      const raw: string = 'a=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/';
      const cookies: string[] = splitSetCookie(raw);
      expect(cookies.length).assertEqual(1);
      expect(cookies[0].includes('21 Oct 2015')).assertTrue();
    });

    it('多条拼接的 Cookie 应被切开', 0, () => {
      const cookies: string[] = splitSetCookie('a=1; Path=/, b=2; HttpOnly');
      expect(cookies.length).assertEqual(2);
      expect(cookies[0]).assertEqual('a=1; Path=/');
      expect(cookies[1]).assertEqual('b=2; HttpOnly');
    });

    it('空串与纯空白应得到空数组', 0, () => {
      expect(splitSetCookie('').length).assertEqual(0);
      expect(splitSetCookie('   ').length).assertEqual(0);
    });

    it('每条结果的空白应被去掉', 0, () => {
      const cookies: string[] = splitSetCookie('  a=1 ; Path=/  ');
      expect(cookies.length).assertEqual(1);
      expect(cookies[0]).assertEqual('a=1 ; Path=/');
    });
  });
}
