/**
 * 测试入口。
 *
 * HarmonyOS 的测试框架从这里发现全部测试套。新增测试文件后必须在此登记，
 * 否则会被静默跳过（"没报错"不等于"跑了"）。
 */

import sm2FormatTest from './sm2Format.test';
import parseTest from './parse.test';
import cookieJarTest from './cookieJar.test';
import errorsTest from './errors.test';
import loggerTest from './logger.test';

export default function testsuite() {
  sm2FormatTest();
  parseTest();
  cookieJarTest();
  errorsTest();
  loggerTest();
}
