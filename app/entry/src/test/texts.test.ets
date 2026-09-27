/**
 * 文案键映射的单元测试。
 *
 * 覆盖 ui-shell spec §5 第 3 项：`FailReason`（5 个值）的每个取值都映射到**已知文案键**，
 * 不留未覆盖项，也不把排障细节带进用户可见文案。
 *
 * 资源是否真的存在由 `scripts/check-l10n.mjs` 把关（`$r` 传变量是运行时解析，
 * 写错键不会编译报错），本测试管的是"映射本身不遗漏、不串台"。
 */

import { describe, expect, it } from '@ohos/hypium';
import { FailReason } from '../main/ets/model/auth';
import { TextKeys, textKeyOfFailReason } from '../main/ets/common/texts';

/** 全部已知键（NONE 是"无需展示"的哨兵，不是资源） */
const KNOWN_KEYS: string[] = [
  TextKeys.LOGIN_TITLE,
  TextKeys.LOGIN_USERNAME,
  TextKeys.LOGIN_PASSWORD,
  TextKeys.LOGIN_REMEMBER_PASSWORD,
  TextKeys.LOGIN_SUBMIT,
  TextKeys.LOGIN_SUBMITTING,
  TextKeys.LOGIN_SSO_HINT,
  TextKeys.LOGIN_NETWORK_HINT,
  TextKeys.LOGIN_FAILED,
  TextKeys.ERR_LOGOUT_INCOMPLETE,
  TextKeys.TAB_NOTICES,
  TextKeys.TAB_ASSIGNMENTS,
  TextKeys.TAB_FILES,
  TextKeys.TAB_COURSES,
  TextKeys.TAB_SETTINGS,
  TextKeys.PLACEHOLDER_HINT,
  TextKeys.TAB_OPEN_DETAIL,
  TextKeys.TAB_BACK,
  TextKeys.SETTINGS_LOGOUT,
  TextKeys.STATE_LOADING,
  TextKeys.STATE_EMPTY,
  TextKeys.STATE_RETRY,
  TextKeys.TOAST_RETRYING,
  TextKeys.SETTINGS_THEME_TITLE,
  TextKeys.THEME_FOLLOW_SYSTEM,
  TextKeys.THEME_LIGHT,
  TextKeys.THEME_DARK,
  TextKeys.THEME_APPLY_FAILED,
  TextKeys.SEMESTER_SEASON_FALL,
  TextKeys.SEMESTER_SEASON_SPRING,
  TextKeys.SEMESTER_SEASON_SUMMER,
  TextKeys.SEMESTER_SEASON_UNKNOWN,
  TextKeys.SETTINGS_SEMESTER,
  TextKeys.SEMESTER_REFRESH,
  TextKeys.SEMESTER_SWITCH_FAILED,
  TextKeys.SEMESTER_CURRENT,
  TextKeys.SSO_TITLE,
  TextKeys.SSO_CANCEL,
  TextKeys.SSO_ESTABLISHING,
  TextKeys.SSO_STATE_LOST,
  TextKeys.SSO_RESOURCE_MISSING,
  TextKeys.ERR_NETWORK_UNREACHABLE,
  TextKeys.ERR_AUTH_FAILED,
  TextKeys.ERR_API_CHANGED,
  TextKeys.ERR_PARSE_FAILED,
  TextKeys.ERR_TRUST_LIMIT
];

const ALL_REASONS: FailReason[] = [
  FailReason.NETWORK_UNREACHABLE,
  FailReason.AUTH_FAILED,
  FailReason.API_CHANGED,
  FailReason.PARSE_FAILED,
  FailReason.CANCELLED
];

export default function textsTest() {
  describe('texts', () => {

    it('每个 FailReason 都应映射到已知文案键，不留未覆盖项', 0, () => {
      ALL_REASONS.forEach((reason: FailReason) => {
        const key: string = textKeyOfFailReason(reason);
        const covered: boolean = KNOWN_KEYS.includes(key) || key === TextKeys.NONE;
        expect(covered).assertTrue();
      });
      // 枚举新增取值后须同步补映射与用例
      expect(ALL_REASONS.length).assertEqual(5);
    });

    it('用户取消不是失败，应映射为空键表示无需展示', 0, () => {
      expect(textKeyOfFailReason(FailReason.CANCELLED)).assertEqual(TextKeys.NONE);
    });

    it('hintKey 非空时应优先于通用文案，以保留可操作引导', 0, () => {
      expect(textKeyOfFailReason(FailReason.API_CHANGED, TextKeys.ERR_TRUST_LIMIT))
        .assertEqual(TextKeys.ERR_TRUST_LIMIT);
      // 空的 hintKey 不应影响原有分类
      expect(textKeyOfFailReason(FailReason.API_CHANGED, '')).assertEqual(TextKeys.ERR_API_CHANGED);
    });

    it('四类失败应各有不同文案，不得互相串台', 0, () => {
      const network: string = textKeyOfFailReason(FailReason.NETWORK_UNREACHABLE);
      const auth: string = textKeyOfFailReason(FailReason.AUTH_FAILED);
      const api: string = textKeyOfFailReason(FailReason.API_CHANGED);
      const parse: string = textKeyOfFailReason(FailReason.PARSE_FAILED);

      expect(network === auth).assertFalse();
      expect(network === api).assertFalse();
      expect(auth === api).assertFalse();
      expect(network === parse).assertFalse();
      expect(auth === parse).assertFalse();
      expect(api === parse).assertFalse();
    });

    it('解析失败应有专用文案，不得报成"登录失败"', 0, () => {
      // 解析失败的场景（学期/课程/通知响应结构变了）与登录无关，
      // 报成"登录失败"会诱导用户去查密码——这是审查 N-03 记的错误面误报
      const parse: string = textKeyOfFailReason(FailReason.PARSE_FAILED);
      expect(parse).assertEqual(TextKeys.ERR_PARSE_FAILED);
      expect(parse === TextKeys.LOGIN_FAILED).assertFalse();
    });

    it('映射结果只能是键本身，不得把排障细节带进用户文案', 0, () => {
      // 逐一带上技术串作为 hintKey：只有 hintKey 本身非空时才生效，
      // 说明"技术细节"没有进入映射的输入通道
      expect(textKeyOfFailReason(FailReason.PARSE_FAILED, TextKeys.ERR_NETWORK_UNREACHABLE))
        .assertEqual(TextKeys.ERR_NETWORK_UNREACHABLE);
      // 注意：这一条原先断言 PARSE_FAILED 映射到 LOGIN_FAILED——那正是审查 N-03 记的
      // 错误面误报，被旧断言固化成了"期望行为"。现在改为断言专用键。
      expect(textKeyOfFailReason(FailReason.PARSE_FAILED)).assertEqual(TextKeys.ERR_PARSE_FAILED);
    });

    it('键名应符合资源名格式，且除哨兵外都非空', 0, () => {
      KNOWN_KEYS.forEach((key: string) => {
        expect(key.length > 0).assertTrue();
        expect(/^[a-z][a-z0-9_]*$/.test(key)).assertTrue();
      });
      expect(KNOWN_KEYS.length).assertEqual(46);
    });
  });
}
