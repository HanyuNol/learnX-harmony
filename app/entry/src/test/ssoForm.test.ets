/**
 * WebView 主导登录（SSO）纯逻辑的单元测试。
 *
 * 覆盖三处最容易在真机上才暴露、而宿主侧就能测死的地方：
 * 1. 注入脚本的占位符替换——密码含引号、反斜杠或 `$` 时，替换若把脚本写坏，
 *    表现只是"预填没生效"，与"校方页面改版"极难区分；
 * 2. 页面回传的表单体解析——字段缺失、重复、`+` 与百分号转义、畸形片段；
 * 3. 信号归类——"信任浏览器名额已满"必须带可操作引导，页面加载失败必须归网络类，
 *    二者都不能被误报成"密码错误"。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  MSG_PAGE_LOAD_FAILED,
  MSG_PREFILL_FAILED,
  MSG_SUBMIT_FORM,
  MSG_TRUST_LIMIT,
  MSG_UNKNOWN,
  PLACEHOLDER_DEVICE_NAME,
  PLACEHOLDER_FINGER_PRINT,
  PLACEHOLDER_PASSWORD,
  PLACEHOLDER_USERNAME,
  SsoFingerPrints,
  buildInjectedScript,
  classifyCheckResponse,
  classifySsoProblem,
  describeRoamUrl,
  fingerPrintsOf,
  formBodyOf,
  isRoamingUrl,
  parseBridgeMessage,
  parseFormBody,
  ticketOfRoamUrl
} from '../main/ets/network/ssoForm';
import { FailReason } from '../main/ets/model/auth';
import { TextKeys } from '../main/ets/common/texts';

/** 模板骨架：只含四个占位符，便于断言替换结果 */
const SAMPLE_TEMPLATE: string =
  `var u = ${PLACEHOLDER_USERNAME};var p = ${PLACEHOLDER_PASSWORD};` +
  `var f = ${PLACEHOLDER_FINGER_PRINT};var d = ${PLACEHOLDER_DEVICE_NAME};`;

export default function ssoFormTest() {
  describe('ssoForm', () => {

    describe('buildInjectedScript', () => {

      it('四个占位符都应被替换为对应取值', 0, () => {
        const script: string = buildInjectedScript(SAMPLE_TEMPLATE, '2023001', 'pw', 'ab12', 'HUAWEI Mate 60');
        expect(script.includes(PLACEHOLDER_USERNAME)).assertFalse();
        expect(script.includes(PLACEHOLDER_PASSWORD)).assertFalse();
        expect(script.includes(PLACEHOLDER_FINGER_PRINT)).assertFalse();
        expect(script.includes(PLACEHOLDER_DEVICE_NAME)).assertFalse();
        expect(script.includes('"2023001"')).assertTrue();
        expect(script.includes('"ab12"')).assertTrue();
        expect(script.includes('"HUAWEI Mate 60"')).assertTrue();
      });

      it('密码含引号与反斜杠时应转义为合法 JS 字符串，而不是把脚本写坏', 0, () => {
        const script: string = buildInjectedScript(SAMPLE_TEMPLATE, 'u', 'a"b\\c', 'f', 'd');
        // 转义后的字面量必须原样出现在脚本里：换行、引号都不得裸奔
        expect(script.includes('"a\\"b\\\\c"')).assertTrue();
        expect(script.includes('\n')).assertFalse();
      });

      it('密码含 $& 时不应被当成替换模式展开', 0, () => {
        // String.replace 的字符串替换会把 $& 展开为"被匹配的子串"——
        // 用函数式替换才能避免这个 bug，本用例守住它
        const script: string = buildInjectedScript(SAMPLE_TEMPLATE, 'u', 'p$&w', 'f', 'd');
        expect(script.includes('p$&w')).assertTrue();
      });

      it('密码含换行时不得把值裸拼进脚本', 0, () => {
        const script: string = buildInjectedScript(SAMPLE_TEMPLATE, 'u', 'line1\nline2', 'f', 'd');
        expect(script.includes('\\n')).assertTrue();
        expect(script.includes('line1\nline2')).assertFalse();
      });
    });

    describe('parseFormBody', () => {

      it('应解析出多个字段', 0, () => {
        const fields: Map<string, string> = parseFormBody('i_user=2023001&fingerPrint=abc&i_captcha=');
        expect(fields.size).assertEqual(3);
        expect(fields.get('i_user')).assertEqual('2023001');
        expect(fields.get('fingerPrint')).assertEqual('abc');
        expect(fields.get('i_captcha')).assertEqual('');
      });

      it('加号应还原为空格，百分号转义应被解码', 0, () => {
        const fields: Map<string, string> = parseFormBody('deviceName=HUAWEI+Mate+60&x=%E6%98%AF');
        expect(fields.get('deviceName')).assertEqual('HUAWEI Mate 60');
        expect(fields.get('x')).assertEqual('是');
      });

      it('同名字段后出现的应覆盖先出现的', 0, () => {
        const fields: Map<string, string> = parseFormBody('a=1&a=2');
        expect(fields.get('a')).assertEqual('2');
      });

      it('无等号的片段应按空值字段处理', 0, () => {
        const fields: Map<string, string> = parseFormBody('flag');
        expect(fields.get('flag')).assertEqual('');
      });

      it('空串应解析出空集合', 0, () => {
        expect(parseFormBody('').size).assertEqual(0);
      });

      it('畸形百分号序列不应抛错，也不应丢掉其余字段', 0, () => {
        const fields: Map<string, string> = parseFormBody('bad=%E4%B8&good=1');
        expect(fields.get('bad')).assertEqual('%E4%B8');
        expect(fields.get('good')).assertEqual('1');
      });
    });

    describe('parseBridgeMessage', () => {

      it('SUBMIT_FORM 应带出表单体字符串', 0, () => {
        const raw: string = '{"type":"SUBMIT_FORM","data":{"formId":"theform","body":"a=1&b=2"}}';
        const message = parseBridgeMessage(raw);
        expect(message === null).assertFalse();
        expect(message?.type).assertEqual(MSG_SUBMIT_FORM);
        expect(message?.body).assertEqual('a=1&b=2');
      });

      it('SUBMIT_FORM 缺少 data 或 body 时应判为不可用', 0, () => {
        expect(parseBridgeMessage('{"type":"SUBMIT_FORM"}') === null).assertTrue();
        expect(parseBridgeMessage('{"type":"SUBMIT_FORM","data":{"formId":"x"}}') === null).assertTrue();
      });

      it('TRUST_LIMIT 与 PREFILL_FAILED 应被识别', 0, () => {
        expect(parseBridgeMessage('{"type":"TRUST_LIMIT","data":{}}')?.type).assertEqual(MSG_TRUST_LIMIT);
        expect(parseBridgeMessage('{"type":"PREFILL_FAILED","data":{}}')?.type).assertEqual(MSG_PREFILL_FAILED);
      });

      it('未识别的类型应归为 UNKNOWN 而不是丢弃', 0, () => {
        expect(parseBridgeMessage('{"type":"SOMETHING_ELSE"}')?.type).assertEqual(MSG_UNKNOWN);
      });

      it('非法 JSON 或类型字段非字符串时应返回 null', 0, () => {
        expect(parseBridgeMessage('not json') === null).assertTrue();
        expect(parseBridgeMessage('{"type":123}') === null).assertTrue();
        expect(parseBridgeMessage('[1,2,3]') === null).assertTrue();
      });
    });

    describe('isRoamingUrl 与票据提取', () => {

      it('带 ticket 的漫游地址应命中', 0, () => {
        expect(isRoamingUrl('https://learn.tsinghua.edu.cn/f/j_spring_security_thauth_roaming_entry?ticket=T1'))
          .assertTrue();
      });

      it('认证页自身的地址不应命中', 0, () => {
        expect(isRoamingUrl('https://id.tsinghua.edu.cn/do/off/ui/auth/login/check')).assertFalse();
      });

      it('应从漫游地址取出票据', 0, () => {
        expect(ticketOfRoamUrl('https://learn.example/f/roam?ticket=ABC123&x=1')).assertEqual('ABC123');
      });

      it('无查询参数或无数值时应返回空串', 0, () => {
        // 空票据意味着收尾要走兜底的"重新登录"，不能把 undefined 当票据用
        expect(ticketOfRoamUrl('https://learn.example/f/roam')).assertEqual('');
        expect(ticketOfRoamUrl('https://learn.example/f/roam?foo=1')).assertEqual('');
        expect(ticketOfRoamUrl('https://learn.example/f/roam?ticket=')).assertEqual('');
      });

      it('排障描述应只给出参数名与票据长度', 0, () => {
        // 票据是一次性凭据，不能进日志——所以这里断言"描述里不含票据值"
        const described: string = describeRoamUrl('https://learn.example/f/roam?ticket=SECRET&x=1');
        expect(described.includes('SECRET')).assertFalse();
        expect(described.includes('ticket长度=6')).assertTrue();
        expect(described.includes('ticket')).assertTrue();
      });

      it('无查询参数时应明说', 0, () => {
        expect(describeRoamUrl('https://learn.example/f/roam')).assertEqual('无查询参数');
      });
    });

    describe('SsoFormBody 与设备信任标识', () => {

      it('缺少指纹的表单体应判为不可用', 0, () => {
        expect(formBodyOf('i_user=2023001').isUsable()).assertFalse();
        expect(formBodyOf('i_user=2023001&fingerPrint=').isUsable()).assertFalse();
        expect(formBodyOf('i_user=2023001&fingerPrint=ab').isUsable()).assertTrue();
      });

      it('应从表单体取出三项设备信任标识', 0, () => {
        const prints = fingerPrintsOf(
          formBodyOf('i_user=2023001&fingerPrint=fp&fingerGenPrint=gp&fingerGenPrint3=gp3')
        );
        expect(prints.fingerPrint).assertEqual('fp');
        expect(prints.fingerGenPrint).assertEqual('gp');
        expect(prints.fingerGenPrint3).assertEqual('gp3');
      });

      it('页面未给出后两项时应为空串而不是 undefined', 0, () => {
        // 后两项由页面自行取得，可能拿不到；拿不到时应传空串（对齐上游），不是崩掉
        const prints = fingerPrintsOf(formBodyOf('i_user=2023001&fingerPrint=fp'));
        expect(prints.fingerGenPrint).assertEqual('');
        expect(prints.fingerGenPrint3).assertEqual('');
      });

      it('备选路径用的空三元组应三项皆空', 0, () => {
        const prints = SsoFingerPrints.empty();
        expect(prints.fingerPrint).assertEqual('');
        expect(prints.fingerGenPrint).assertEqual('');
        expect(prints.fingerGenPrint3).assertEqual('');
      });
    });

    describe('classifyCheckResponse', () => {

      it('含二次认证字样应归为二次认证页', 0, () => {
        expect(classifyCheckResponse('<html><title>二次认证</title></html>')).assertEqual('二次认证页');
      });

      it('含登录页特征应归为会话未生效', 0, () => {
        expect(classifyCheckResponse('<div id="sm2publicKey">ab</div>')).assertEqual('登录页（会话未生效）');
        expect(classifyCheckResponse('<input name="i_user" />')).assertEqual('登录页（会话未生效）');
      });

      it('都不像时应归为未识别的页面', 0, () => {
        expect(classifyCheckResponse('<html>数据已丢失，请重新操作</html>')).assertEqual('未识别的页面');
      });
    });

    describe('classifySsoProblem', () => {

      it('信任浏览器名额已满应归接口语义变更，并带可操作引导', 0, () => {
        const error = classifySsoProblem(MSG_TRUST_LIMIT);
        expect(error.reason).assertEqual(FailReason.API_CHANGED);
        // 通用文案会盖掉引导，用户就无从知道要去删旧设备。
        // 这里断言**键**而非文案内容：文案已迁到资源里，键才是本层该保证的事实
        expect(error.hintKey).assertEqual(TextKeys.ERR_TRUST_LIMIT);
      });

      it('预填失败应归接口语义变更，不得误报为密码错误', 0, () => {
        expect(classifySsoProblem(MSG_PREFILL_FAILED).reason).assertEqual(FailReason.API_CHANGED);
      });

      it('页面加载失败应归网络不可达，不得误报为应用缺陷', 0, () => {
        expect(classifySsoProblem(MSG_PAGE_LOAD_FAILED).reason).assertEqual(FailReason.NETWORK_UNREACHABLE);
      });
    });
  });
}
