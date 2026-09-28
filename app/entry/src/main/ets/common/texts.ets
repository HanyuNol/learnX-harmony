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
import {
  HomeworkCompletionType, HomeworkSubmissionType, RelativeDeadline, RelativeUnit
} from '../model/assignment';

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

  /** 通知筛选：全部 */
  static readonly NOTICE_FILTER_ALL: string = 'notice_filter_all';
  /** 通知筛选：未读（同时用作列表项的未读标记文字） */
  static readonly NOTICE_FILTER_UNREAD: string = 'notice_filter_unread';
  /** 通知页：重新加载 */
  static readonly NOTICE_REFRESH: string = 'notice_refresh';
  /** 通知页：部分课程的通知未能加载 */
  static readonly NOTICE_PARTIAL_FAILED: string = 'notice_partial_failed';
  /** 通知详情：附件 */
  static readonly NOTICE_ATTACHMENT: string = 'notice_attachment';

  /** 作业筛选：未完成（同时是列表项的"未提交"口径） */
  static readonly ASSIGNMENT_FILTER_UNFINISHED: string = 'assignment_filter_unfinished';
  /** 作业筛选：已完成 */
  static readonly ASSIGNMENT_FILTER_FINISHED: string = 'assignment_filter_finished';
  /** 作业页：重新加载 */
  static readonly ASSIGNMENT_REFRESH: string = 'assignment_refresh';
  /** 作业页：部分课程的作业未能加载 */
  static readonly ASSIGNMENT_PARTIAL_FAILED: string = 'assignment_partial_failed';
  /** 列表项标记：已提交 */
  static readonly ASSIGNMENT_SUBMITTED: string = 'assignment_submitted';
  /** 列表项标记：已评分 */
  static readonly ASSIGNMENT_GRADED: string = 'assignment_graded';
  /** 详情：独立完成 */
  static readonly ASSIGNMENT_COMPLETION_INDIVIDUAL: string = 'assignment_completion_individual';
  /** 详情：小组完成 */
  static readonly ASSIGNMENT_COMPLETION_GROUP: string = 'assignment_completion_group';
  /** 详情：在线提交 */
  static readonly ASSIGNMENT_SUBMISSION_ONLINE: string = 'assignment_submission_online';
  /** 详情：线下提交 */
  static readonly ASSIGNMENT_SUBMISSION_OFFLINE: string = 'assignment_submission_offline';
  /** 详情：教师附件 */
  static readonly ASSIGNMENT_ATTACHMENT: string = 'assignment_attachment';
  /** 详情：已提交附件 */
  static readonly ASSIGNMENT_SUBMITTED_ATTACHMENT: string = 'assignment_submitted_attachment';
  /** 详情：评分附件 */
  static readonly ASSIGNMENT_GRADE_ATTACHMENT: string = 'assignment_grade_attachment';
  /** 详情：附件行的动作提示（点击下载并打开） */
  static readonly ASSIGNMENT_ATTACHMENT_OPEN: string = 'assignment_attachment_open';
  /** 详情：提交作业（未提交时） */
  static readonly ASSIGNMENT_SUBMIT: string = 'assignment_submit';
  /** 详情：修改提交（已提交时） */
  static readonly ASSIGNMENT_MODIFY_SUBMISSION: string = 'assignment_modify_submission';
  /** 提交页：提交中… */
  static readonly ASSIGNMENT_SUBMITTING: string = 'assignment_submitting';
  /** 提交页：正文小节 */
  static readonly ASSIGNMENT_SUBMIT_CONTENT: string = 'assignment_submit_content';
  /** 提交页：正文输入提示 */
  static readonly ASSIGNMENT_SUBMIT_CONTENT_HINT: string = 'assignment_submit_content_hint';
  /** 提交页：附件小节 */
  static readonly ASSIGNMENT_SUBMIT_ATTACHMENT: string = 'assignment_submit_attachment';
  /** 提交页：选择文件 */
  static readonly ASSIGNMENT_PICK_FILE: string = 'assignment_pick_file';
  /** 提交页：选择文件失败 */
  static readonly ASSIGNMENT_PICK_FILE_FAILED: string = 'assignment_pick_file_failed';
  /** 提交页：移除所选 */
  static readonly ASSIGNMENT_REMOVE_PICKED: string = 'assignment_remove_picked';
  /** 提交页：移除已提交的附件 */
  static readonly ASSIGNMENT_REMOVE_ATTACHMENT: string = 'assignment_remove_attachment';
  /** 提交页：保留已提交的附件（取消移除） */
  static readonly ASSIGNMENT_KEEP_ATTACHMENT: string = 'assignment_keep_attachment';
  /** 提交页：未选择附件 */
  static readonly ASSIGNMENT_NO_ATTACHMENT: string = 'assignment_no_attachment';
  /** 提交页：已上传的附件前缀 */
  static readonly ASSIGNMENT_ALREADY_UPLOADED: string = 'assignment_already_uploaded';
  /** 提交页：已过截止时间 */
  static readonly ASSIGNMENT_PAST_DEADLINE: string = 'assignment_past_deadline';
  /** 提交成功 */
  static readonly ASSIGNMENT_SUBMIT_SUCCEEDED: string = 'assignment_submit_succeeded';
  /** 提交失败 */
  static readonly ASSIGNMENT_SUBMIT_FAILED: string = 'assignment_submit_failed';
  /** 详情：补交截止 */
  static readonly ASSIGNMENT_LATE_DEADLINE: string = 'assignment_late_deadline';
  /** 详情：提交时间 */
  static readonly ASSIGNMENT_SUBMIT_TIME: string = 'assignment_submit_time';
  /** 详情：评分小节 */
  static readonly ASSIGNMENT_GRADE: string = 'assignment_grade';
  /** 详情：评分人 */
  static readonly ASSIGNMENT_GRADER: string = 'assignment_grader';
  /** 详情：评分时间 */
  static readonly ASSIGNMENT_GRADE_TIME: string = 'assignment_grade_time';
  /** 详情：正文缺失时的占位 */
  static readonly ASSIGNMENT_NO_DESCRIPTION: string = 'assignment_no_description';
  /** 详情：详情未能加载（预取失败） */
  static readonly ASSIGNMENT_DETAIL_FAILED: string = 'assignment_detail_failed';

  /** 相对截止：还剩 %d 分钟 */
  static readonly ASSIGNMENT_DUE_MINUTE: string = 'assignment_due_minute';
  /** 相对截止：还剩 %d 小时 */
  static readonly ASSIGNMENT_DUE_HOUR: string = 'assignment_due_hour';
  /** 相对截止：还剩 %d 天 */
  static readonly ASSIGNMENT_DUE_DAY: string = 'assignment_due_day';
  /** 相对截止：还剩 %d 个月 */
  static readonly ASSIGNMENT_DUE_MONTH: string = 'assignment_due_month';
  /** 相对截止：还剩 %d 年 */
  static readonly ASSIGNMENT_DUE_YEAR: string = 'assignment_due_year';
  /** 相对截止：%d 分钟前截止 */
  static readonly ASSIGNMENT_OVERDUE_MINUTE: string = 'assignment_overdue_minute';
  /** 相对截止：%d 小时前截止 */
  static readonly ASSIGNMENT_OVERDUE_HOUR: string = 'assignment_overdue_hour';
  /** 相对截止：%d 天前截止 */
  static readonly ASSIGNMENT_OVERDUE_DAY: string = 'assignment_overdue_day';
  /** 相对截止：%d 个月前截止 */
  static readonly ASSIGNMENT_OVERDUE_MONTH: string = 'assignment_overdue_month';
  /** 相对截止：%d 年前截止 */
  static readonly ASSIGNMENT_OVERDUE_YEAR: string = 'assignment_overdue_year';

  /** 评分等级：已阅 */
  static readonly GRADE_LEVEL_CHECKED: string = 'grade_level_checked';
  /** 评分等级：优秀 */
  static readonly GRADE_LEVEL_DISTINCTION: string = 'grade_level_distinction';
  /** 评分等级：免课 */
  static readonly GRADE_LEVEL_EXEMPTED_COURSE: string = 'grade_level_exempted_course';
  /** 评分等级：免修 */
  static readonly GRADE_LEVEL_EXEMPTION: string = 'grade_level_exemption';
  /** 评分等级：通过 */
  static readonly GRADE_LEVEL_PASS: string = 'grade_level_pass';
  /** 评分等级：不通过 */
  static readonly GRADE_LEVEL_FAILURE: string = 'grade_level_failure';
  /** 评分等级：缓考 */
  static readonly GRADE_LEVEL_INCOMPLETE: string = 'grade_level_incomplete';

  /** 文件页：重新加载 */
  static readonly FILE_REFRESH: string = 'file_refresh';
  /** 文件页：部分课程的文件未能加载 */
  static readonly FILE_PARTIAL_FAILED: string = 'file_partial_failed';
  /** 列表项标记：重要 */
  static readonly FILE_IMPORTANT: string = 'file_important';
  /** 列表项标记：新文件 */
  static readonly FILE_NEW: string = 'file_new';
  /** 详情：课程 */
  static readonly FILE_COURSE: string = 'file_course';
  /** 详情：教师 */
  static readonly FILE_TEACHER: string = 'file_teacher';
  /** 详情：分类 */
  static readonly FILE_CATEGORY: string = 'file_category';
  /** 详情：类型 */
  static readonly FILE_TYPE: string = 'file_type';
  /** 详情：大小 */
  static readonly FILE_SIZE: string = 'file_size';
  /** 详情：上传时间 */
  static readonly FILE_UPLOAD_TIME: string = 'file_upload_time';
  /** 详情：无描述时的占位 */
  static readonly FILE_NO_DESCRIPTION: string = 'file_no_description';
  /** 详情：下载 */
  static readonly FILE_DOWNLOAD: string = 'file_download';
  /** 详情：下载中… */
  static readonly FILE_DOWNLOADING: string = 'file_downloading';
  /** 详情：已下载 */
  static readonly FILE_DOWNLOADED: string = 'file_downloaded';
  /** 详情：在系统查看器中打开（次要路径，设备上未必有能打开该类型的应用） */
  static readonly FILE_OPEN: string = 'file_open';
  /** 详情：应用内预览（主路径，无需设备上装有对应应用） */
  static readonly FILE_PREVIEW: string = 'file_preview';
  /** 打开失败：设备上没有能打开该类型文件的应用（与"下载失败"分开，否则用户无从判断） */
  static readonly FILE_OPEN_FAILED: string = 'file_open_failed';
  /** 下载或打开失败 */
  static readonly FILE_DOWNLOAD_FAILED: string = 'file_download_failed';
  /** 该类型无法应用内预览，需用其他应用打开（Office 文档一类） */
  static readonly FILE_NEEDS_OTHER_APP: string = 'file_needs_other_app';
  /** 文件筛选：未读（服务端 isNew） */
  static readonly FILE_FILTER_UNREAD: string = 'file_filter_unread';
  /** 文件筛选：已读 */
  static readonly FILE_FILTER_READ: string = 'file_filter_read';
  /** 课程详情页文件分组：未分类 */
  static readonly FILE_CATEGORY_NONE: string = 'file_category_none';
  /** 作业附件行：查看 */
  static readonly ASSIGNMENT_ATTACHMENT_VIEW: string = 'assignment_attachment_view';
  /** 作业附件行：下载 */
  static readonly ASSIGNMENT_ATTACHMENT_DOWNLOAD: string = 'assignment_attachment_download';
  /** 下载进度：`下载中 %d%%`（图形之外必须有文字才可验收） */
  static readonly FILE_DOWNLOAD_PROGRESS: string = 'file_download_progress';
  /** 详情：重新下载 */
  static readonly FILE_REDOWNLOAD: string = 'file_redownload';

  /** 设置页：下载目录小节标题 */
  static readonly SETTINGS_DOWNLOAD_DIR_TITLE: string = 'settings_download_dir_title';
  /** 下载目录选项：缓存目录（可被系统回收） */
  static readonly SETTINGS_DOWNLOAD_DIR_CACHE: string = 'settings_download_dir_cache';
  /** 下载目录选项：应用文件目录（随应用数据保留） */
  static readonly SETTINGS_DOWNLOAD_DIR_FILES: string = 'settings_download_dir_files';
  /** 设置项未能保存（偏好写入失败） */
  static readonly SETTINGS_SAVE_FAILED: string = 'settings_save_failed';
  /** 本设备不支持选择文件夹（手机不支持；改用"另存为"） */
  static readonly SETTINGS_FOLDER_UNSUPPORTED: string = 'settings_folder_unsupported';
  /** 所选内容不是文件夹 */
  static readonly SETTINGS_FOLDER_NOT_DIR: string = 'settings_folder_not_dir';
  /** 详情：另存为（保存到用户挑选的位置） */
  static readonly FILE_SAVE_AS: string = 'file_save_as';
  /** 另存为成功 */
  static readonly FILE_SAVE_AS_SUCCEEDED: string = 'file_save_as_succeeded';
  /** 另存为失败 */
  static readonly FILE_SAVE_AS_FAILED: string = 'file_save_as_failed';

  /** 通用筛选：全部（FR-12 的通用筛选条，各维度共用） */
  static readonly FILTER_ALL: string = 'filter_all';
  /** 通用：刷新中…（放在刷新按钮旁，让"点了刷新"有可见反馈） */
  static readonly LIST_REFRESHING: string = 'list_refreshing';
  /** 搜索页标题 */
  static readonly SEARCH_TITLE: string = 'search_title';
  /** 搜索页：输入框占位 */
  static readonly SEARCH_PLACEHOLDER: string = 'search_placeholder';
  /** 搜索页：未输入时的引导 */
  static readonly SEARCH_HINT: string = 'search_hint';
  /** 搜索页：课程内的范围说明（`%s` 为课程名） */
  static readonly SEARCH_SCOPE_COURSE: string = 'search_scope_course';
  /** 搜索结果段标题：课程 */
  static readonly SEARCH_SECTION_COURSE: string = 'search_section_course';
  /** 搜索结果段标题：文件 */
  static readonly SEARCH_SECTION_FILE: string = 'search_section_file';
  /** 搜索结果段标题：通知 */
  static readonly SEARCH_SECTION_NOTICE: string = 'search_section_notice';
  /** 搜索结果段标题：作业 */
  static readonly SEARCH_SECTION_ASSIGNMENT: string = 'search_section_assignment';

  /** 设置页：显示项小节标题 */
  static readonly SETTINGS_DISPLAY_TITLE: string = 'settings_display_title';
  /** 设置页：提醒小节标题（FR-18） */
  static readonly SETTINGS_REMINDER_TITLE: string = 'settings_reminder_title';
  /** 提醒：作业截止提醒开关 */
  static readonly SETTINGS_REMINDER_ENABLED: string = 'settings_reminder_enabled';
  /** 提醒：提前多久提醒（分钟） */
  static readonly SETTINGS_REMINDER_OFFSET: string = 'settings_reminder_offset';
  /** 提醒：已完成的作业不提醒 */
  static readonly SETTINGS_REMINDER_NO_IF_COMPLETE: string = 'settings_reminder_no_if_complete';
  /** 提醒：说明对齐范围与时机 */
  static readonly SETTINGS_REMINDER_HINT: string = 'settings_reminder_hint';
  /** 提醒：提前量输入非法（`%d` 为上限分钟数） */
  static readonly SETTINGS_REMINDER_OFFSET_INVALID: string = 'settings_reminder_offset_invalid';
  /** 提醒：未获得日历权限（写不进日历，需用户去系统设置授权） */
  static readonly SETTINGS_REMINDER_PERMISSION_MISSING: string = 'settings_reminder_permission_missing';
  /** 提醒：写入系统日历失败 */
  static readonly SETTINGS_REMINDER_FAILED: string = 'settings_reminder_failed';
  /** 显示项：下载文件名省略课程名前缀 */
  static readonly SETTINGS_OMIT_COURSE_NAME: string = 'settings_omit_course_name';
  /** 设置页入口：关于与帮助 */
  static readonly SETTINGS_ABOUT: string = 'settings_about';
  /** 设置页入口：个人信息 */
  static readonly SETTINGS_PROFILE: string = 'settings_profile';
  /** 个人信息页：姓名与院系的标题 */
  static readonly PROFILE_ACCOUNT_TITLE: string = 'profile_account_title';
  /** 个人信息页：下载位置小节标题 */
  static readonly PROFILE_DOWNLOAD_TITLE: string = 'profile_download_title';
  /** 个人信息页：下载位置选项——应用内（缓存） */
  static readonly PROFILE_DIR_APP_CACHE: string = 'profile_dir_app_cache';
  /** 个人信息页：下载位置选项——应用内（文件目录） */
  static readonly PROFILE_DIR_APP_FILES: string = 'profile_dir_app_files';
  /** 个人信息页：下载位置选项——自定义目录 */
  static readonly SETTINGS_DOWNLOAD_DIR_CUSTOM: string = 'settings_download_dir_custom';
  /** 个人信息页：选择自定义目录 */
  static readonly SETTINGS_PICK_FOLDER: string = 'settings_pick_folder';
  /** 个人信息页：清除自定义目录 */
  static readonly SETTINGS_CLEAR_FOLDER: string = 'settings_clear_folder';
  /** 个人信息页：尚未选择目录 */
  static readonly SETTINGS_NO_FOLDER: string = 'settings_no_folder';
  /** 个人信息页：目录选择失败 */
  static readonly SETTINGS_PICK_FOLDER_FAILED: string = 'settings_pick_folder_failed';
  /** 个人信息页：自定义目录下文件的应用内预览不可用，说明 */
  static readonly SETTINGS_CUSTOM_DIR_HINT: string = 'settings_custom_dir_hint';
  /** 关于：版本 */
  static readonly ABOUT_VERSION: string = 'about_version';
  /** 关于：包名 */
  static readonly ABOUT_BUNDLE: string = 'about_bundle';
  /** 关于：来源与许可小节标题 */
  static readonly ABOUT_ATTRIBUTION_TITLE: string = 'about_attribution_title';
  /** 关于：来源与许可正文（ADR-0002 要求的归属） */
  static readonly ABOUT_ATTRIBUTION_BODY: string = 'about_attribution_body';
  /** 帮助小节标题 */
  static readonly HELP_TITLE: string = 'help_title';
  /** 帮助：网络前提 */
  static readonly HELP_NETWORK: string = 'help_network';
  /** 帮助：登录方式 */
  static readonly HELP_LOGIN: string = 'help_login';
  /** 帮助：文件下载与打开 */
  static readonly HELP_FILE: string = 'help_file';
  /** 帮助：记住密码的语义（勾选后登出不清除凭据）——ADR-0011 登记的"界面未告知"缺口 */
  static readonly HELP_REMEMBER: string = 'help_remember';

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
  /** 解析失败：响应结构不符合预期（服务端改了结构，或返回了无法识别的内容） */
  static readonly ERR_PARSE_FAILED: string = 'err_parse_failed';
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
  if (reason === FailReason.PARSE_FAILED) {
    return TextKeys.ERR_PARSE_FAILED;
  }
  if (reason === FailReason.CANCELLED) {
    return TextKeys.NONE;
  }
  // 兜底：`FailReason` 目前 5 个取值都已覆盖，这里防的是**将来新增取值**时漏配文案。
  // 它给的是"登录失败"，语气不准——若真落到这里，应视为漏配而不是正常路径。
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

/**
 * 相对截止描述 → 文案键（键里的 `%d` 由调用方用 `$r(key, value)` 填数量）。
 *
 * 放在这里而不是页面里，理由同 `textKeyOfSemesterType`：键集中一处才能被
 * `scripts/check-l10n.mjs` 一个地方扫到，也让"每个单位+方向都有文案"可测。
 */
export function textKeyOfRelativeDeadline(relative: RelativeDeadline): string {
  if (relative.past) {
    if (relative.unit === RelativeUnit.MINUTE) {
      return TextKeys.ASSIGNMENT_OVERDUE_MINUTE;
    }
    if (relative.unit === RelativeUnit.HOUR) {
      return TextKeys.ASSIGNMENT_OVERDUE_HOUR;
    }
    if (relative.unit === RelativeUnit.DAY) {
      return TextKeys.ASSIGNMENT_OVERDUE_DAY;
    }
    if (relative.unit === RelativeUnit.MONTH) {
      return TextKeys.ASSIGNMENT_OVERDUE_MONTH;
    }
    return TextKeys.ASSIGNMENT_OVERDUE_YEAR;
  }
  if (relative.unit === RelativeUnit.MINUTE) {
    return TextKeys.ASSIGNMENT_DUE_MINUTE;
  }
  if (relative.unit === RelativeUnit.HOUR) {
    return TextKeys.ASSIGNMENT_DUE_HOUR;
  }
  if (relative.unit === RelativeUnit.DAY) {
    return TextKeys.ASSIGNMENT_DUE_DAY;
  }
  if (relative.unit === RelativeUnit.MONTH) {
    return TextKeys.ASSIGNMENT_DUE_MONTH;
  }
  return TextKeys.ASSIGNMENT_DUE_YEAR;
}

/** 完成方式 → 文案键（认不出按"独立完成"，与上游默认分支一致） */
export function textKeyOfCompletionType(completionType: number): string {
  if (completionType === HomeworkCompletionType.GROUP) {
    return TextKeys.ASSIGNMENT_COMPLETION_GROUP;
  }
  return TextKeys.ASSIGNMENT_COMPLETION_INDIVIDUAL;
}

/** 提交方式 → 文案键（认不出按"在线提交"，与上游默认分支一致） */
export function textKeyOfSubmissionType(submissionType: number): string {
  if (submissionType === HomeworkSubmissionType.OFFLINE) {
    return TextKeys.ASSIGNMENT_SUBMISSION_OFFLINE;
  }
  return TextKeys.ASSIGNMENT_SUBMISSION_ONLINE;
}

/**
 * 评分等级代码 → 文案键；上游只给这几个等级配了词（`helpers/i18n.ts:21-41`），
 * 其余（A+/B/…）返回空串，由调用方直接显示等级代码本身。
 */
export function textKeyOfGradeLevel(level: string): string {
  if (level === 'checked') {
    return TextKeys.GRADE_LEVEL_CHECKED;
  }
  if (level === 'distinction') {
    return TextKeys.GRADE_LEVEL_DISTINCTION;
  }
  if (level === 'exempted course') {
    return TextKeys.GRADE_LEVEL_EXEMPTED_COURSE;
  }
  if (level === 'exemption') {
    return TextKeys.GRADE_LEVEL_EXEMPTION;
  }
  if (level === 'pass') {
    return TextKeys.GRADE_LEVEL_PASS;
  }
  if (level === 'failure') {
    return TextKeys.GRADE_LEVEL_FAILURE;
  }
  if (level === 'incomplete') {
    return TextKeys.GRADE_LEVEL_INCOMPLETE;
  }
  return TextKeys.NONE;
}
