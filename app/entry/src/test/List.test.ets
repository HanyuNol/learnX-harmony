/**
 * 测试入口。
 *
 * HarmonyOS 的测试框架从这里发现全部测试套。新增测试文件后必须在此登记，
 * 否则会被静默跳过（"没报错"不等于"跑了"）。
 */

import sm2FormatTest from './sm2Format.test';
import parseTest from './parse.test';
import setCookieTest from './setCookie.test';
import ssoFormTest from './ssoForm.test';
import errorsTest from './errors.test';
import loggerTest from './logger.test';
import themeTest from './theme.test';
import textsTest from './texts.test';
import logoutTest from './logout.test';
import semesterTest from './semester.test';
import courseTest from './course.test';
import noticeTest from './notice.test';
import assignmentTest from './assignment.test';
import parseAssignmentTest from './parseAssignment.test';
import fileTest from './file.test';
import searchTest from './search.test';
import sessionPolicyTest from './sessionPolicy.test';
import credentialPolicyTest from './credentialPolicy.test';
import reminderTest from './reminder.test';
import courseEventTest from './courseEvent.test';

export default function testsuite() {
  sm2FormatTest();
  parseTest();
  setCookieTest();
  ssoFormTest();
  errorsTest();
  loggerTest();
  themeTest();
  textsTest();
  logoutTest();
  semesterTest();
  courseTest();
  noticeTest();
  assignmentTest();
  parseAssignmentTest();
  fileTest();
  searchTest();
  sessionPolicyTest();
  credentialPolicyTest();
  reminderTest();
  courseEventTest();
}
