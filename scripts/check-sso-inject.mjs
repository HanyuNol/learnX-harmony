/**
 * 注入脚本（resources/rawfile/sso_inject.js）的入口点检查。
 *
 * ## 为什么需要它
 *
 * 这个脚本运行在**校方页面**里，横插在登录流程中间。它一旦抛异常，后果不是"应用报错"，
 * 而是**页面的请求发不出去**——实测踩过一次：脚本里一处未声明的变量赋值（严格模式下
 * 抛 ReferenceError），让「保存信任浏览器」的请求根本没发出，页面只显示
 * 「网络异常，请重新登录或稍后重试」，而应用侧一条日志都没有，排障绕了好几个来回。
 *
 * `node --check` 只查语法，查不出这类问题；把脚本放进只有桩对象的沙箱里"执行一遍"也不够
 * ——出问题的那段代码在事件回调里，不调用就永远不触发。所以这里**主动调用**它的关键入口：
 *
 * 1. 执行整个脚本（文档开始时的注入路径）；
 * 2. 推进它注册的定时器（预填检查、环境探测、文档回报）；
 * 3. 调用被它覆盖的 `XMLHttpRequest.prototype.send`，分别用普通 URL 与
 *    `saveFinger` 路径，并断言请求体被改写为 `radioVal=是`。
 *
 * 用法：`node scripts/check-sso-inject.mjs`
 */

import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const scriptPath = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'app',
  'entry',
  'src',
  'main',
  'resources',
  'rawfile',
  'sso_inject.js'
);

/**
 * 记住属性读写与赋值的桩对象。
 *
 * 必须**记住**赋值：脚本会把函数挂到 `XMLHttpRequest.prototype.open/send` 上，
 * 只有记住它们，检查才能把它们取出来调用——这正是能抓到"回调里抛异常"的关键。
 */
function makeStub() {
  const store = new Map();
  const target = function () {
    return makeStub();
  };
  return new Proxy(target, {
    get(_t, key) {
      if (key === 'then') {
        return undefined;
      }
      if (typeof key === 'symbol') {
        return undefined;
      }
      if (key === 'length') {
        return 0;
      }
      if (key === 'toString') {
        return () => '';
      }
      if (key === 'valueOf') {
        return () => '';
      }
      if (!store.has(key)) {
        store.set(key, makeStub());
      }
      return store.get(key);
    },
    set(_t, key, value) {
      store.set(key, value);
      return true;
    },
    apply() {
      return makeStub();
    },
    construct() {
      return makeStub();
    }
  });
}

const marks = [];
const timers = [];

function buildContext() {
  return {
    window: makeStub(),
    document: makeStub(),
    navigator: makeStub(),
    console: { log: (text) => marks.push(String(text)), error: () => {}, warn: () => {} },
    setTimeout: (fn) => {
      timers.push(fn);
      return timers.length;
    },
    setInterval: () => 0,
    clearInterval: () => {},
    clearTimeout: () => {},
    XMLHttpRequest: makeStub(),
    MutationObserver: makeStub(),
    URLSearchParams: makeStub(),
    FormData: makeStub(),
    Blob: makeStub(),
    performance: makeStub(),
    location: makeStub(),
    self: makeStub(),
    indexedDB: makeStub(),
    Math,
    Date,
    JSON,
    Promise,
    Object,
    Array,
    String,
    Number,
    Boolean,
    Error,
    parseInt,
    isNaN
  };
}

function substitute(source) {
  return source
    .replace('__LEARNX_USERNAME__', () => JSON.stringify('2023001'))
    .replace('__LEARNX_PASSWORD__', () => JSON.stringify('p"w\\$&x'))
    .replace('__LEARNX_FINGER_PRINT__', () => JSON.stringify('ab12'))
    .replace('__LEARNX_DEVICE_NAME__', () => JSON.stringify('HUAWEI Mate 60'));
}

const failures = [];

function fail(what, error) {
  failures.push(`${what}：${error && error.name ? error.name + ' —— ' + error.message : String(error)}`);
}

const source = substitute(readFileSync(scriptPath, 'utf8'));
const context = buildContext();
runInContext(source, createContext(context), { filename: 'sso_inject.js' });

// 推进定时器：预填检查、环境探测、文档回报都在这些回调里
for (const timer of timers) {
  try {
    timer();
  } catch (error) {
    fail('定时器回调执行抛错', error);
  }
}

/** 模拟一次 XHR 发送，调用被脚本覆盖的 send */
function invokeSend(url, body) {
  const prototype = context.XMLHttpRequest.prototype;
  if (typeof prototype.send !== 'function') {
    failures.push('未能取到被覆盖的 send（脚本没挂上覆盖？）');
    return;
  }
  const fake = {
    __learnxUrl: url,
    timeout: 5000,
    status: 0,
    readyState: 0,
    responseText: '',
    addEventListener: () => {}
  };
  try {
    prototype.send.call(fake, body);
  } catch (error) {
    fail(`调用 send(${url}) 抛错`, error);
  }
}

invokeSend('https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/', 'a=1');
invokeSend('/b/doubleAuth/personal/saveFinger', 'fingerprint=page&deviceName=web&radioVal=否&singleLogin=yes');

const rewriteMarked = marks.some((text) => text.includes('learnX[sso]') && text.includes('改写=是'));
if (!rewriteMarked) {
  failures.push('未见到「saveFinger 请求体被改写为 radioVal=是」的打点');
}

if (failures.length > 0) {
  console.error('❌ 注入脚本入口点检查未通过：');
  for (const item of failures) {
    console.error('   - ' + item);
  }
  process.exit(1);
}

console.log('✅ 注入脚本入口点检查通过（脚本可执行、定时器回调与 saveFinger 拦截均无异常，且请求体改写生效）');
