/**
 * 登录链路 HTML 抓取的单元测试。
 *
 * 覆盖 spec §5 第 2、3 项：从样例页面提取 SM2 公钥、漫游工单、CSRF 令牌，
 * 以及会话失效的判定。样例取自上游对页面结构的既有假设。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  extractCsrfToken,
  extractSm2PublicKey,
  extractTicket,
  extractUserName,
  isSessionExpired,
  stripTags
} from '../main/ets/network/parse';

const SAMPLE_PUBLIC_KEY: string = '04' + 'ab'.repeat(64);

const SAMPLE_LOGIN_PAGE: string =
  `<html><body><form>` +
  `<div id="sm2publicKey">${SAMPLE_PUBLIC_KEY}</div>` +
  `<input name="i_user" /></form></body></html>`;

const SAMPLE_CHECK_RESPONSE: string =
  `<html><body><a href="https://learn.tsinghua.edu.cn/b/j_spring_security_thauth_roaming_entry?ticket=ABC123">继续</a></body></html>`;

const SAMPLE_HOME_PAGE: string =
  `<html><body><script src="/f/wlxt/common/js?x=1&_csrf=TOKEN987"></script>` +
  `<a class="user-log">张三</a></body></html>`;

export default function parseTest() {
  describe('parse', () => {

    it('应从登录页提取 SM2 公钥', 0, () => {
      expect(extractSm2PublicKey(SAMPLE_LOGIN_PAGE)).assertEqual(SAMPLE_PUBLIC_KEY);
    });

    it('登录页无公钥元素时应返回空串', 0, () => {
      expect(extractSm2PublicKey('<html><body></body></html>')).assertEqual('');
    });

    it('应从校验响应提取漫游工单', 0, () => {
      expect(extractTicket(SAMPLE_CHECK_RESPONSE)).assertEqual('ABC123');
    });

    it('无锚点时应返回空串', 0, () => {
      expect(extractTicket('<html><body>错误</body></html>')).assertEqual('');
    });

    it('应从首页提取 CSRF 令牌', 0, () => {
      expect(extractCsrfToken(SAMPLE_HOME_PAGE)).assertEqual('TOKEN987');
    });

    it('无 CSRF 时应返回空串', 0, () => {
      expect(extractCsrfToken('<html><body>无</body></html>')).assertEqual('');
    });

    it('会话失效判定：403 或 URL 含 login_timeout', 0, () => {
      expect(isSessionExpired('https://learn.tsinghua.edu.cn/f/wlxt/index', 403)).assertTrue();
      expect(isSessionExpired('https://learn.tsinghua.edu.cn/login_timeout', 200)).assertTrue();
      expect(isSessionExpired('https://learn.tsinghua.edu.cn/f/wlxt/index', 200)).assertFalse();
      // 500 属服务端错误，不得被误判为会话失效
      expect(isSessionExpired('https://learn.tsinghua.edu.cn/f/wlxt/index', 500)).assertFalse();
    });

    it('应从首页提取用户名', 0, () => {
      expect(extractUserName(SAMPLE_HOME_PAGE)).assertEqual('张三');
      expect(extractUserName('<html></html>')).assertEqual('');
    });

    it('去标签应合并多余空白', 0, () => {
      expect(stripTags('<b> 甲 </b>\n  <i>乙</i>')).assertEqual('甲 乙');
    });
  });
}
