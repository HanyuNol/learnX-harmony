/**
 * 用户可见文案的**键**，以及"失败原因 → 文案键"的映射。
 *
 * 为什么键在这里而不在页面里：`model`/`network`/`viewmodel` 不持有 `Resource`
 * （那是 UI 层概念，架构不变量 §1）。这些层只产出**键**，页面用
 * `$r('app.string.' + key)` 取文案。好处有二：分层不被 `Resource` 污染；
 * "哪些键必须有资源"变成可枚举、可测试的事实（见 `scripts/check-l10n.mjs`）。
 *
 * 键名必须与 `resources/base/element/string.json`、`resources/en_US/element/string.json`
 * 里的 `name` 逐字一致——**门在 check-l10n.mjs 与单测，不在编译器**：
 * `$r` 传变量时是运行时解析，写错键不会编译报错，只会显示不出文案。
 *
 * **实测硬规则（2026-09-27，模拟器 API 24）**：`$r` 的参数只要是**变量**（含
 * `$r(TextKeys.X)` 这种属性访问），就必须传**全名**——即 `$r('app.string.' + TextKeys.X)`。
 * 传裸键 `$r(TextKeys.X)` 时资源解析失败，**不报错、不打日志，直接不渲染该节点**
 * （现象：登录页只剩输入框，标题与按钮连同文字一起消失）。故本文件只提供**裸键**，
 * 页面取资源时一律自己拼 `'app.string.'` 前缀。
 */

import { FailReason } from '../model/auth';
import { SemesterType } from '../model/semester';

/**
 * 文案键。取值即资源名（不含 `app.string.` 前缀）。
 *
 * 用 `static readonly` 而非枚举：这些值要拼进 `$r('app.string.' + key)`，
 * 需要的是字符串本身；且枚举值无法在编译期与资源文件对齐。
 */
export class TextKeys {
  /** 登录页标题 */
  static readonly LOGIN_TITLE: string = 'login_title';
  /** 学号输入框占位 */
  static readonly LOGIN_USERNAME: string = 'login_username';
  /** 密码输入框占位 */
  static readonly LOGIN_PASSWORD: string = 'login_password';
  /** 「记住密码」 */
  static readonly LOGIN_REMEMBER_PASSWORD: string = 'login_remember_password';
  /** 「登录」按钮 */
  static readonly LOGIN_SUBMIT: string = 'login_submit';
  /** 「登录中…」按钮 */
  static readonly LOGIN_SUBMITTING: string = 'login_submitting';
  /** 提示下一步会打开网页完成认证（含验证码） */
  static readonly LOGIN_SSO_HINT: string = 'login_sso_hint';
  /** 提示需要校园网或校方 VPN */
  static readonly LOGIN_NETWORK_HINT: string = 'login_network_hint';
  /** 失败时的兜底文案。**不含技术细节**（`AuthError.detail` 只进日志） */
  static readonly LOGIN_FAILED: string = 'login_failed';
  /** 登出未完成：本地凭据未能清除（安全语义，不得谎报成功） */
  static readonly ERR_LOGOUT_INCOMPLETE: string = 'err_logout_incomplete';

  /** 底部标签：通知 */
  static readonly TAB_NOTICES: string = 'tab_notices';
  /** 底部标签：作业 */
  static readonly TAB_ASSIGNMENTS: string = 'tab_assignments';
  /** 底部标签：文件 */
  static readonly TAB_FILES: string = 'tab_files';
  /** 底部标签：课程 */
  static readonly TAB_COURSES: string = 'tab_courses';
  /** 底部标签：设置 */
  static readonly TAB_SETTINGS: string = 'tab_settings';
  /** 占位页提示：内容将在后续迭代实现（首页与详情占位共用） */
  static readonly PLACEHOLDER_HINT: string = 'placeholder_hint';
  /** 占位页按钮：进入详情（用于验证每标签独立栈） */
  static readonly TAB_OPEN_DETAIL: string = 'tab_open_detail';
  /** 详情页按钮：返回 */
  static readonly TAB_BACK: string = 'tab_back';
  /** 设置页：登出（FR-04 的入口，随页签从入口占位页搬来） */
  static readonly SETTINGS_LOGOUT: string = 'settings_logout';

  /** 加载态：加载中 */
  static readonly STATE_LOADING: string = 'state_loading';
  /** 空态：无内容 */
  static readonly STATE_EMPTY: string = 'state_empty';
  /** 错误态：重试按钮 */
  static readonly STATE_RETRY: string = 'state_retry';
  /** 轻量反馈：正在重试（Toast） */
  static readonly TOAST_RETRYING: string = 'toast_retrying';

  /** 设置页：主题小节标题 */
  static readonly SETTINGS_THEME_TITLE: string = 'settings_theme_title';
  /** 主题选项：跟随系统 */
  static readonly THEME_FOLLOW_SYSTEM: string = 'theme_follow_system';
  /** 主题选项：浅色 */
  static readonly THEME_LIGHT: string = 'theme_light';
  /** 主题选项：深色 */
  static readonly THEME_DARK: string = 'theme_dark';
  /** 主题未能生效（写入成功但应用失败也归此，R-09） */
  static readonly THEME_APPLY_FAILED: string = 'theme_apply_failed';

  /** 学期季节：秋季 */
  static readonly SEMESTER_SEASON_FALL: string = 'semester_season_fall';
  /** 学期季节：春季 */
  static readonly SEMESTER_SEASON_SPRING: string = 'semester_season_spring';
  /** 学期季节：夏季 */
  static readonly SEMESTER_SEASON_SUMMER: string = 'semester_season_summer';
  /** 学期季节：识别不出（id 形态异常）——保留原串可显示，不崩 */
  static readonly SEMESTER_SEASON_UNKNOWN: string = 'semester_season_unknown';

  /** 设置页入口：学期切换 */
  static readonly SETTINGS_SEMESTER: string = 'settings_semester';
  /** 学期页：重新加载 */
  static readonly SEMESTER_REFRESH: string = 'semester_refresh';
  /** 学期切换未能保存（安全语义：不得谎报切换成功，同审查 R-02 的教训） */
  static readonly SEMESTER_SWITCH_FAILED: string = 'semester_switch_failed';
  /** 学期页：当前学期的文字标注（与勾选图标并存——图标在节点树里不可验证，文字可） */
  static readonly SEMESTER_CURRENT: string = 'semester_current';

  /** SSO 页顶部标题 */
  static readonly SSO_TITLE: string = 'sso_title';
  /** 「取消」按钮 */
  static readonly SSO_CANCEL: string = 'sso_cancel';
  /** 「正在建立登录会话…」 */
  static readonly SSO_ESTABLISHING: string = 'sso_establishing';
  /** SSO 页致命错误：登录流程状态丢失 */
  static readonly SSO_STATE_LOST: string = 'sso_state_lost';
  /** SSO 页致命错误：应用资源缺失（构建缺陷，非用户可修复） */
  static readonly SSO_RESOURCE_MISSING: string = 'sso_resource_missing';

  /** 网络不可达 */
  static readonly ERR_NETWORK_UNREACHABLE: string = 'err_network_unreachable';
  /** 认证失败 */
  static readonly ERR_AUTH_FAILED: string = 'err_auth_failed';
  /** 接口语义变更 */
  static readonly ERR_API_CHANGED: string = 'err_api_changed';
  /** 信任浏览器名额已满（带可操作步骤，故与通用 API_CHANGED 文案分开） */
  static readonly ERR_TRUST_LIMIT: string = 'err_trust_limit';

  /**
   * 「无需展示文案」的哨兵值：用户主动取消不是失败，不该弹错误。
   * 空串不会被拼成 `$r('app.string.')`——页面在渲染前先判空。
   */
  static readonly NONE: string = '';
}

/**
 * 把失败原因映射为文案键。
 *
 * `hintKey` 非空时优先：那是**具体可操作**的引导（如"去删旧设备"），
 * 通用文案会把它盖掉，用户就无从知道该做什么。
 *
 * `reason` 未覆盖到时退让为通用失败文案——**不把技术细节（`detail`）呈现给用户**：
 * 那是排障用的（含状态码与页面串），对用户不可理解，也不指向任何动作。
 */
export function textKeyOfFailReason(reason: FailReason, hintKey: string = ''): string {
  if (hintKey.length > 0) {
    return hintKey;
  }
  if (reason === FailReason.NETWORK_UNREACHABLE) {
    return TextKeys.ERR_NETWORK_UNREACHABLE;
  }
  if (reason === FailReason.AUTH_FAILED) {
    return TextKeys.ERR_AUTH_FAILED;
  }
  if (reason === FailReason.API_CHANGED) {
    return TextKeys.ERR_API_CHANGED;
  }
  if (reason === FailReason.CANCELLED) {
    return TextKeys.NONE;
  }
  return TextKeys.LOGIN_FAILED;
}

/**
 * 学期季节类型 → 文案键。
 *
 * 放在这里而不是 `model/semester.ets`：键是 UI 层概念，全部集中在本文件，
 * 才能被 `scripts/check-l10n.mjs` 一个地方扫到（`model` 保持与文案无关）。
 */
export function textKeyOfSemesterType(type: SemesterType): string {
  if (type === SemesterType.FALL) {
    return TextKeys.SEMESTER_SEASON_FALL;
  }
  if (type === SemesterType.SPRING) {
    return TextKeys.SEMESTER_SEASON_SPRING;
  }
  if (type === SemesterType.SUMMER) {
    return TextKeys.SEMESTER_SEASON_SUMMER;
  }
  return TextKeys.SEMESTER_SEASON_UNKNOWN;
}
