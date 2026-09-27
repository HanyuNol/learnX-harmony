/**
 * 会话 Cookie 的载体：`webview.WebCookieManager` 适配层。
 *
 * 为什么不是自管容器（ADR-0008 的决策）：登录由 WebView 主导，WebView 与 API 请求
 * **必须是同一份会话**——页面用它那次会话的 SM2 公钥加密了密码，只有沿用同一份
 * Cookie，服务端才解得开（见 `LearnClient.loginWithFormData` 的说明）。
 * WebCookieManager 是进程级的，WebView 写入的 Cookie 本层直接可读，冷启动还能持久化。
 *
 * 为什么不是框架的 `enableAutoCookie`：该接口起始版本为 API 26，本项目 SDK 为 24。
 *
 * 与系统能力的边界：本类只做"读/写/清/落盘"四件事，不含任何业务判断；
 * 失败语义由调用方（`LearnClient`）归类，且**读失败一律退让为空串**——
 * 拿不到 Cookie 只应表现为"需要重新登录"，不该让请求崩掉。
 */

import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/logger';
import { splitSetCookie } from './setCookie';

const TAG: string = 'webCookieStore';

export class WebCookieStore {
  /**
   * 取得发往该 URL 的 Cookie 请求头；无 Cookie、或 Web 引擎尚未就绪时返回空串。
   *
   * 冷启动时应用可能还没有创建过任何 Web 组件，此时该接口可能拿不到已落盘的 Cookie。
   * 那会表现为"启动时需要重新登录"，属可接受的退让——但需实机确认（见 spec §6 待定项）。
   */
  static headerFor(url: string): string {
    try {
      return webview.WebCookieManager.fetchCookieSync(url, false);
    } catch (err) {
      const error = err as BusinessError;
      // 17100002 = 该 URL 没有有效 Cookie。这是"未登录"的正常表达，不是错误。
      Logger.debug(TAG, `读取 Cookie 未命中 code=${error.code}`);
      return '';
    }
  }

  /**
   * 收纳响应下发的 Set-Cookie。
   *
   * `includeHttpOnly` 必须为 true：会话 Cookie（JSESSIONID）带 HttpOnly，
   * 不允许覆盖时写不进去——那会让"下一步请求带上会话"彻底失效。
   */
  static storeFromResponse(url: string, setCookie: string): void {
    const cookies: string[] = splitSetCookie(setCookie);
    for (const cookie of cookies) {
      try {
        webview.WebCookieManager.configCookieSync(url, cookie, false, true);
      } catch (err) {
        // 单条写入失败不中断其余：会话 Cookie 不止一个，能写进多少算多少
        const error = err as BusinessError;
        Logger.warn(TAG, `写入 Cookie 失败 code=${error.code}`);
      }
    }
  }

  /**
   * 清除**会话 Cookie**（保留持久 Cookie）：登录前以干净的登录会话起步。
   *
   * **为什么不是清空全部**（本方法原先是 `clearAllCookiesSync`）：上游只清
   * `id.tsinghua.edu.cn` 那一条 `JSESSIONID`。清空全部会连带抹掉服务端可能用来
   * **认设备的持久 Cookie**——那样每次登录在服务端看来都是"从没见过的浏览器，
   * 且不能持久化任何东西"，于是拒绝把本机登记为信任浏览器
   * （实测：登记请求返回 `{"result":"success","msg":"否"}`，页面据此提示"隐私模式"）。
   * 会话 Cookie 才是"上次登录的残留"，该清的只有它。
   */
  static clearSession(): void {
    try {
      webview.WebCookieManager.clearSessionCookieSync();
      Logger.info(TAG, '已清除会话 Cookie（保留持久 Cookie）');
    } catch (err) {
      const error = err as BusinessError;
      Logger.warn(TAG, `清除会话 Cookie 失败 code=${error.code}`);
    }
  }

  /**
   * 列出该 URL 名下**有哪些 Cookie（只给名字，不给值）**，供排障。
   *
   * 需要它是因为"服务端有没有给过我们一个用来认设备的持久 Cookie、
   * 以及它有没有被我们清掉"只能这样看出来；值属于会话数据，不进日志。
   */
  static cookieNamesFor(url: string): string {
    const raw: string = WebCookieStore.headerFor(url);
    if (raw.length === 0) {
      return '（无）';
    }
    const names: string[] = [];
    for (const pair of raw.split(';')) {
      const trimmed: string = pair.trim();
      const equalsIndex: number = trimmed.indexOf('=');
      if (equalsIndex > 0) {
        names.push(trimmed.substring(0, equalsIndex));
      }
    }
    return names.length === 0 ? '（无）' : names.join(',');
  }

  /**
   * 强制落盘。
   *
   * Cookie 默认每 30s 周期保存一次，而"杀进程重开仍保持登录"是 FR-04 的验收项——
   * 登录成功后立刻主动落盘，不赌那个周期。
   */
  static persist(): void {
    webview.WebCookieManager.saveCookieAsync()
      .then(() => {
        Logger.info(TAG, 'Cookie 已落盘');
      })
      .catch((err: BusinessError) => {
        Logger.warn(TAG, `Cookie 落盘失败 code=${err.code}`);
      });
  }
}
