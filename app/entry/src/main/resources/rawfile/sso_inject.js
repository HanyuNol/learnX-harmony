/**
 * 统一身份认证登录页的注入脚本（模板）。
 *
 * ## 为什么需要它
 *
 * 本校账号普遍启用多因子认证，**验证码只能由用户在真实页面上输入**："纯 API 登录"
 * 没有任何位置能承载这一步（ADR-0008）。因此登录由 WebView 主导，本脚本只做三件
 * 不需要用户介入的事：
 *
 * 1. 预填学号与密码（置为只读——用户若要改，须关闭页面回登录界面重新输入）；
 * 2. 页面询问"是否信任此浏览器"时，替用户答"是"并写入应用自己的设备指纹；
 * 3. 把提交时的完整表单体回传应用——其中的 `fingerPrint` / `fingerGenPrint` /
 *    `fingerGenPrint3` 由页面生成，应用无法自行构造，只能这样拿到。
 *
 * 应用**不代填、不代答验证码**：那是用户的步骤，不是遗漏。
 *
 * ## 唯一维护点
 *
 * 本文件是"页面结构依赖"的**唯一维护点**：选择器、接口路径、页面文案都只写在这里。
 * 校方页面改版导致登录失败时，只改这一个文件——失败会被归入"接口语义变更"类错误
 * （见 `network/ssoForm.ets`），而不是被误报成"密码错误"。
 *
 * ## 占位符
 *
 * `__LEARNX_*__` 由 `pages/SsoLogin.ets` 在注入前替换，替换值经 JSON 转义
 * （见 `network/ssoForm.ets` 的 `buildInjectedScript`）。本文件本身不是可执行脚本。
 *
 * ## 与上游的差异
 *
 * 上游（`robertying/learnX` 的 `src/helpers/preval/sso.js`）只覆盖 jQuery 的
 * `$.fn.submit`。本项目额外挂了原生 `submit` 事件的捕获阶段监听：ArkWeb 不保证
 * 页面用 jQuery 提交，两条路径并存才稳。其余（XHR 拦截、字段注入、回传格式）照实复刻。
 */
(function () {
  'use strict';

  /* ---------- 页面结构依赖：校方改版时只需改这一段 ---------- */
  var SELECTOR_USERNAME_INPUT = 'input#i_user';
  var SELECTOR_PASSWORD_INPUT = 'input#i_pass';
  var SELECTOR_FINGER_PRINT_FIELD = '[name="fingerPrint"]';
  var SELECTOR_SINGLE_LOGIN_FIELD = '[name="singleLogin"]';
  var SELECTOR_LOGIN_FORM = 'form';
  /** 二次认证登记"信任此浏览器"的接口路径（XHR 拦截用） */
  var PATH_SAVE_FINGER = '/b/doubleAuth/personal/saveFinger';
  /** 页面提示"信任浏览器数量"达到上限时的识别串：命中即回报，由应用给出可操作引导 */
  var TEXT_TRUST_LIMIT = '信任浏览器数量已达到上限';
  /* -------------------------------------------------------- */

  var USERNAME = __LEARNX_USERNAME__;
  var PASSWORD = __LEARNX_PASSWORD__;
  var FINGER_PRINT = __LEARNX_FINGER_PRINT__;
  var DEVICE_NAME = __LEARNX_DEVICE_NAME__;

  /** 预填迟迟不成功即上报：避免用户对着一个空白页等（超时值放宽到 20s，页面加载可能慢） */
  var PREFILL_DEADLINE_MS = 20000;
  /** 合并同一帧内的密集 DOM 变动，避免在页面重绘时反复读表单 */
  var MUTATION_DEBOUNCE_MS = 50;

  var startedAt = Date.now();
  var reportedPrefillFailure = false;
  var lastReportedBody = '';

  /** "保存信任浏览器"请求的结果——排障的关键事实；初始值即"没见过这条请求" */
  var saveFingerResult = '未见该请求';

  /**
   * 响应体脱敏摘要：把长值（令牌、指纹）折叠掉，只留结构、字段名与短值。
   *
   * 为什么要看响应体：页面那句"无法设置为信任浏览器"是它自己的提示，
   * 而请求的 `result` 只是 RPC 信封——真正的原因（拒登、名额满、字段缺失）
   * 只可能出现在响应体里。不下发值本身，避免把设备标识带进日志。
   */
  function sanitize(text) {
    if (!text) {
      return '(空)';
    }
    return String(text)
      .substring(0, 300)
      .replace(/[A-Za-z0-9_\-+/=]{24,}/g, '<长值>')
      .replace(/\s+/g, ' ');
  }

  function bridge() {
    var candidate = window.learnXSsoBridge;
    return candidate && typeof candidate.postMessage === 'function' ? candidate : null;
  }

  /**
   * 打点：同时写到**页面控制台**与 JS 桥。
   *
   * 为什么两个都要：桥在子框架里未必可用（实测 cef 日志出现过
   * `native proxy object not found, name:learnXSsoBridge`），而"信任浏览器"这一步
   * 的请求究竟有没有发出、有没有超时，只能靠页面侧的记录说清。
   * 控制台那条由应用侧 `onConsole` 转发到 hilog，不依赖桥。
   */
  function mark(text) {
    try {
      console.log('learnX[sso] ' + text);
    } catch (error) {
      // 控制台不可用不影响流程
    }
  }

  function send(type, data) {
    var channel = bridge();
    if (!channel) {
      return;
    }
    try {
      channel.postMessage(JSON.stringify({ type: type, data: data || {} }));
    } catch (error) {
      // 通道不可用不应影响页面本身：用户仍可手填并自行完成登录
    }
  }

  /**
   * 环境探测：只报**可用性与长度**，不报任何值。
   *
   * 为什么需要：页面用 localforage（IndexedDB → WebSQL → localStorage）持久化设备标记，
   * 存储不可用就会被它判定为"浏览器处于隐私或匿名模式"，从而拒绝登记信任浏览器。
   * 这件事只能从页面内部看清——宿主侧看不到，只能靠这份回报。
   */
  function reportEnvironment() {
    var parts = [];

    try {
      parts.push('cookieEnabled=' + String(navigator.cookieEnabled));
    } catch (error) {
      parts.push('cookieEnabled=?');
    }
    try {
      parts.push('cookieLen=' + String((document.cookie || '').length));
    } catch (error) {
      parts.push('cookieLen=?');
    }

    // localStorage：不只看有没有，还做一次写入-读回（并还原），这才是"能不能持久化"的实测
    try {
      var key = '__learnx_probe__';
      window.localStorage.setItem(key, '1');
      var roundTrip = window.localStorage.getItem(key) === '1';
      window.localStorage.removeItem(key);
      parts.push('localStorage=' + (roundTrip ? 'ok' : 'no'));
    } catch (error) {
      parts.push('localStorage=throw');
    }

    try {
      parts.push('sessionStorage=' + (window.sessionStorage ? 'ok' : 'no'));
    } catch (error) {
      parts.push('sessionStorage=throw');
    }

    // indexedDB 只探存在性：不给校方域创建数据库，避免留下副作用
    parts.push('indexedDB=' + (window.indexedDB ? 'present' : 'absent'));

    // UA 有助于判断"页面把我们当什么浏览器"——它那句"隐私或匿名模式"的判定可能与此有关
    try {
      parts.push('ua=' + String(navigator.userAgent || '').substring(0, 120));
    } catch (error) {
      parts.push('ua=?');
    }

    send('ENV_PROBE', { body: parts.join(' ') });
  }

  /**
   * 表单体的**字段名与各值长度**（不给值）——用于确认登记请求到底带了什么。
   *
   * 需要它是因为服务端回了 `msg: "否"`（拒绝登记）：要判断原因是"我们改写没生效"
   * 还是"页面自己没拿到设备标记（`fingerGenPrint3` 为空）"，只能看请求体里有哪些字段。
   */
  function summarizeBody(body) {
    try {
      var params = new URLSearchParams(body);
      var parts = [];
      params.forEach(function (value, key) {
        parts.push(key + ':' + String(value || '').length);
      });
      return '[' + parts.join(' ') + ']';
    } catch (error) {
      return '(无法解析)';
    }
  }

  /**
   * 拦截 XHR：页面询问"是否信任此浏览器"时替用户答"是"。
   *
   * 这一步与验证码无关——它解决的只是那个信任询问，写入应用持久化的设备指纹，
   * 使设备进入信任名单、后续登录不再被问。**设备指纹必须复用**：每次换新指纹会
   * 迅速占满信任浏览器名额（名额有上限）。
   *
   * 同时把这次请求的**结果**回报应用：服务端是否真的登记成功，决定了后续
   * 重新登录会不会又被要求验证码——这是排障时的第一手事实。
   */
  function interceptTrustRequest() {
    var originalOpen = XMLHttpRequest.prototype.open;
    var originalSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function (method, url) {
      this.__learnxUrl = url;
      return originalOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function (body) {
      var url = this.__learnxUrl || '';
      var isTrustRequest = url.indexOf(PATH_SAVE_FINGER) >= 0;

      if (isTrustRequest) {
        saveFingerResult = '请求体不是字符串，未改写';
        var rewritten = '否';
        if (typeof body === 'string') {
          try {
            var params = new URLSearchParams(body);
            params.set('fingerprint', FINGER_PRINT);
            params.set('deviceName', DEVICE_NAME);
            params.set('radioVal', '是');
            body = params.toString();
            rewritten = '是';
            saveFingerResult = '已改写待响应';
          } catch (error) {
            saveFingerResult = '请求体解析失败，未改写';
          }
        }
        // 请求体里有什么（字段名 + 各值长度）：判断服务端为何回 `msg:"否"` 的第一手依据
        var bodySummary = summarizeBody(body);
        mark('改写=' + rewritten + ' 请求体=' + bodySummary);
        send('ENV_PROBE', { body: '登记请求体 ' + bodySummary });
        saveFingerResult = '改写=' + rewritten + ' 请求体=' + bodySummary;

        // 服务端返回什么，是"信任浏览器到底存上了没有"的唯一答案。
        // **立刻回报**：这一步发生在用户输入验证码之后、收尾之前，等不到提交那一刻；
        // 而它恰恰决定了后续重新登录会不会又被要求验证码。
        var xhr = this;
        this.addEventListener('load', function () {
          var raw = '';
          try {
            raw = String(xhr.responseText || '');
          } catch (error) {
            raw = '';
          }
          var result = '未知';
          try {
            var matched = raw.match(/"result"\s*:\s*"([^"]{0,40})"/);
            result = matched ? matched[1] : ('status=' + xhr.status);
          } catch (error) {
            result = 'responseUnreadable';
          }
          saveFingerResult = '改写=' + rewritten + ' status=' + xhr.status + ' result=' + result +
            ' 请求体=' + bodySummary;
          mark('响应 ' + saveFingerResult + ' 响应体=' + sanitize(raw));
          send('ENV_PROBE', { body: '信任浏览器请求 ' + saveFingerResult + ' 响应=' + sanitize(raw) });
        });
        // 失败 / 超时 / 中断也要留痕：页面那句「网络异常，请重新登录或稍后重试」正是
        // jQuery `$.ajax({timeout:5000})` 的 fail 分支——只有在这里才能分清是哪一种。
        this.addEventListener('timeout', function () {
          mark('登记请求 超时 页面timeout=' + xhr.timeout + 'ms');
        });
        this.addEventListener('error', function () {
          mark('登记请求 网络错误 status=' + xhr.status + ' readyState=' + xhr.readyState);
        });
        this.addEventListener('abort', function () {
          mark('登记请求 被中断');
        });
      }

      return originalSend.apply(this, arguments);
    };
  }

  /** 预填学号与密码并置为只读。页面元素未就绪时返回 false（稍后重试） */
  function prefill() {
    var usernameInput = document.querySelector(SELECTOR_USERNAME_INPUT);
    var passwordInput = document.querySelector(SELECTOR_PASSWORD_INPUT);
    if (!usernameInput || !passwordInput) {
      return false;
    }
    usernameInput.value = USERNAME;
    usernameInput.readOnly = true;
    passwordInput.value = PASSWORD;
    passwordInput.readOnly = true;
    return true;
  }

  /** 取某字段值的长度（-1 表示字段不存在）。只报长度，不报值 */
  function fieldLength(form, name) {
    var element = form.querySelector('[name="' + name + '"]');
    return element ? String(element.value || '').length : -1;
  }

  /**
   * 提交时的关键事实：三项设备信任标识**拿到了没有**，以及"保存信任浏览器"的结果。
   *
   * 这三项里 `fingerGenPrint` / `fingerGenPrint3` 由页面自行取得（服务端 + 本地存储），
   * 长度为 0 就说明页面那一侧没拿到——这会直接导致重新登录时又被要求验证码。
   */
  function reportSubmitFacts(form) {
    var parts = [];
    parts.push('提交时 fingerPrint=' + fieldLength(form, 'fingerPrint'));
    parts.push('fingerGenPrint=' + fieldLength(form, 'fingerGenPrint'));
    parts.push('fingerGenPrint3=' + fieldLength(form, 'fingerGenPrint3'));
    parts.push('信任浏览器=' + saveFingerResult);
    send('ENV_PROBE', { body: parts.join(' ') });
  }

  /**
   * 抓取表单体并回传。
   *
   * @param form 目标表单
   * @param injectTrustFields 是否同时把应用设备指纹写进表单、并勾选"单点登录"。
   *        仅在提交路径为 true——单纯的 DOM 变动只做被动快照，不去改页面的表单。
   */
  function snapshot(form, injectTrustFields) {
    if (!form) {
      return;
    }

    if (injectTrustFields) {
      var fingerPrintField = form.querySelector(SELECTOR_FINGER_PRINT_FIELD);
      if (fingerPrintField) {
        fingerPrintField.value = FINGER_PRINT;
      }
      var singleLoginField = form.querySelector(SELECTOR_SINGLE_LOGIN_FIELD);
      if (singleLoginField && !singleLoginField.checked) {
        singleLoginField.checked = true;
      }
    }

    var body;
    try {
      body = new URLSearchParams(new FormData(form)).toString();
    } catch (error) {
      return;
    }
    if (body === lastReportedBody) {
      return;
    }
    lastReportedBody = body;
    send('SUBMIT_FORM', { formId: form.id || '', body: body });
    if (injectTrustFields) {
      reportSubmitFacts(form);
    }
  }

  /** 命中页面文案即回报，由应用给出"删除旧设备"的可操作引导 */
  var reportedTrustLimit = false;

  function checkTrustLimitHint() {
    if (reportedTrustLimit || !document.body) {
      return;
    }
    var text = document.body.innerText || '';
    if (text.indexOf(TEXT_TRUST_LIMIT) >= 0) {
      reportedTrustLimit = true;
      send('TRUST_LIMIT', {});
    }
  }

  /** 登录表单页的路径标识（与 `model/urls.ets` 的 `ID_LOGIN_FORM` 对应） */
  var LOGIN_FORM_URL_MARKER = '/do/off/ui/auth/login/form/';

  /**
   * 当前文档是不是校方**登录表单页**（按 URL 判定）。
   *
   * **只有它才谈得上"预填失败"**：本脚本会在每一个文档上注入，而二次认证页、门户页、
   * 忘记密码页本来就没有登录表单——在那里判"预填失败"会把已经推进的认证流程误报成
   * "页面结构变了"，应用随即中止流程并把用户踢回登录界面。
   * 实测踩到：验证码通过后页面跳到门户，20 秒后本脚本误报 PREFILL_FAILED，
   * 用户看到的是"网络学堂接口似乎有变化"，而认证其实已经成功。
   *
   * 按 URL 而不是"页面上有没有表单元素"判定：忘记密码页之类也带用户名框，
   * 用元素判定仍会误报。
   */
  function isLoginFormDocument() {
    try {
      return String(window.location.href || '').indexOf(LOGIN_FORM_URL_MARKER) >= 0;
    } catch (error) {
      return false;
    }
  }

  /** 到期时若不在登录表单页：记一条诊断（只给路径，不带查询串），证明我们**保持了沉默** */
  var reportedPrefillSkip = false;

  function pass() {
    if (!prefill()) {
      if (!reportedPrefillFailure && Date.now() - startedAt > PREFILL_DEADLINE_MS) {
        if (isLoginFormDocument()) {
          reportedPrefillFailure = true;
          send('PREFILL_FAILED', {});
        } else if (!reportedPrefillSkip) {
          reportedPrefillSkip = true;
          var path = '未知';
          try {
            path = String(window.location.pathname || '未识别的路径');
          } catch (error) {
            path = '?';
          }
          send('ENV_PROBE', { body: '预填检查：当前文档不是登录表单页，保持沉默 pathname=' + path });
        }
      }
      // 页面尚未渲染出表单（可能还在二次认证步骤），继续等下一次变动
      return;
    }
    snapshot(document.querySelector(SELECTOR_LOGIN_FORM), false);
    checkTrustLimitHint();
  }

  // 原生提交（捕获阶段）：不依赖页面是否使用 jQuery
  document.addEventListener(
    'submit',
    function (event) {
      var target = event.target;
      if (target && target.tagName === 'FORM') {
        snapshot(target, true);
      }
    },
    true
  );

  // jQuery 路径：页面若用 $('#theform').submit() 触发，原生 submit 事件不会派发，
  // 因此另需覆盖 $.fn.submit（上游即用此法）
  var jqueryProbe = setInterval(function () {
    var jq = window.jQuery;
    if (!jq || !jq.fn || !jq.fn.submit || jq.fn.submit.__learnxOverridden) {
      return;
    }
    clearInterval(jqueryProbe);
    var originalSubmit = jq.fn.submit;
    jq.fn.submit = function () {
      var form = this[0];
      if (form && form.tagName === 'FORM') {
        snapshot(form, true);
      }
      return originalSubmit.apply(this, arguments);
    };
    jq.fn.submit.__learnxOverridden = true;
  }, 100);

  interceptTrustRequest();

  // 页面会异步渲染表单，二次认证后还可能重绘，故用变动观察持续补做
  var passPending = false;
  var observer = new MutationObserver(function () {
    if (passPending) {
      return;
    }
    passPending = true;
    setTimeout(function () {
      passPending = false;
      pass();
    }, MUTATION_DEBOUNCE_MS);
  });

  /**
   * 回报当前**文档的身份与它加载的脚本清单**（只给路径，去掉查询串）。
   *
   * 用途：校方在"二次认证页"上判定"浏览器处于隐私或匿名模式"，而那段判定代码不在登录页
   * 的任何脚本里——只有拿到该页自己的脚本清单，才能把它取下来读清楚它到底查什么，
   * 而不是继续猜。
   */
  function reportDocument() {
    var parts = [];
    try {
      parts.push('title=' + String(document.title || '').substring(0, 60));
    } catch (error) {
      parts.push('title=?');
    }
    try {
      parts.push('path=' + String(window.location.pathname || ''));
    } catch (error) {
      parts.push('path=?');
    }
    try {
      var nodes = document.querySelectorAll('script[src]');
      var srcs = [];
      for (var i = 0; i < nodes.length && i < 12; i++) {
        var src = String(nodes[i].getAttribute('src') || '');
        var questionMark = src.indexOf('?');
        srcs.push(questionMark >= 0 ? src.substring(0, questionMark) : src);
      }
      parts.push('脚本=[' + srcs.join(' ') + ']');
    } catch (error) {
      parts.push('脚本=?');
    }
    send('ENV_PROBE', { body: '文档 ' + parts.join(' ') });
  }

  /** 二次认证页上那句"隐私模式"文案的识别串（用于判断页面到底算出了什么） */
  var PRIVACY_TEXT = '隐私或匿名模式';

  /**
   * 校方页面判断"是否隐私/匿名模式"用的是第三方库 `detectIncognito` v1.4.1，
   * 而它的判据在移动端 WebView 上会**误报**——它把"存储配额偏小"当成隐私模式：
   *
   * - 触屏 / Safari 分支：`navigator.storage.estimate().quota < 2GB` → 隐私模式
   * - Chrome 分支：`webkitTemporaryStorage` 配额 `< 2×JS 堆上限` → 隐私模式
   *
   * 误报的后果很实际：页面据此**只提供"否"**（不信任此浏览器），设备信任登记就永远登记不上，
   * 于是每次登录都要重新二次验证（实测：登记请求返回 `msg:"否"`；而 Web 实际并非隐私模式——
   * 应用侧 `isIncognitoMode()` 实测为 `false`）。
   *
   * 因此把这两个"配额查询"接口的读数抬到阈值之上。它只是客户端启发式，**不是安全控制**；
   * 是否信任此浏览器由页面向用户询问，而那个回答按用户意图由本脚本置为"是"。
   */
  function reportDetectionInputs() {
    var parts = [];

    // 库用来分支的指纹：toFixed 抛错信息的长度（44=Safari 分支 / 51=Chrome 分支 / 25=Firefox）
    try {
      var length = 0;
      var value = parseInt('-1');
      try {
        value.toFixed(value);
      } catch (error) {
        length = error.message.length;
      }
      parts.push('分支判据=' + length);
    } catch (error) {
      parts.push('分支判据=?');
    }

    parts.push('estimate=' + (navigator.storage && navigator.storage.estimate ? '有' : '无'));
    parts.push('webkitTemporaryStorage=' + (navigator.webkitTemporaryStorage ? '有' : '无'));

    // 库的默认阈值：堆上限缺省按 1GB 计，即 2GB
    try {
      parts.push('jsHeapSizeLimit=' + ((performance.memory && performance.memory.jsHeapSizeLimit) || '缺省'));
    } catch (error) {
      parts.push('jsHeapSizeLimit=?');
    }

    send('ENV_PROBE', { body: '隐私判定输入 ' + parts.join(' ') });
  }

  function patchIncognitoDetection() {
    // 必须**明显大于** 2×JS 堆上限（实测本机 jsHeapSizeLimit≈2.19GB → 阈值≈4.18GB）。
    // 取值过小会原地踏步：4GB 仍被判为隐私模式（踩过——差点按"文案消失"误报成功）。
    var LARGE_QUOTA = 68719476736;

    // **只就地替换那两个"配额查询"方法**，不替换 navigator.storage /
    // webkitTemporaryStorage 对象本身：页面若用到它们的其他成员
    // （persist / persisted / getDirectory …），换成对象就会缺方法。
    try {
      if (navigator.storage && typeof navigator.storage.estimate === 'function') {
        navigator.storage.estimate = function () {
          return Promise.resolve({ usage: 0, quota: LARGE_QUOTA });
        };
      }
    } catch (error) {
      // 抬不动就让原判据生效：页面顶多多问一次"是否信任"，不影响流程
    }

    try {
      if (navigator.webkitTemporaryStorage) {
        navigator.webkitTemporaryStorage.queryUsageAndQuota = function (success) {
          if (typeof success === 'function') {
            success(0, LARGE_QUOTA);
          }
        };
      }
    } catch (error) {
      // 同上
    }
  }

  /** 页面上是否出现了"隐私模式"那句文案——直接观察页面算出的结论 */
  function reportPrivacyText() {
    var text = document.body ? (document.body.innerText || '') : '';
    send('ENV_PROBE', { body: '页面文案 隐私提示=' + (text.indexOf(PRIVACY_TEXT) >= 0 ? '有' : '无') });
  }

  /**
   * **复刻库的 Chrome 分支公式**，直接报出它会得出的结论。
   *
   * 为什么需要它：那句"隐私提示"只在二次认证页的对话框里渲染，光看"文案有没有出现"
   * 无法区分"判据被修好了"与"对话框还没渲染"。这里直接算并报出 `isPrivate`，
   * 才是在任一页面上都能自证的判据。
   */
  function reportDetectionVerdict(label) {
    try {
      if (!navigator.webkitTemporaryStorage ||
        typeof navigator.webkitTemporaryStorage.queryUsageAndQuota !== 'function') {
        send('ENV_PROBE', { body: '隐私判定结论(' + label + ') 无法计算（无 webkitTemporaryStorage）' });
        return;
      }
      navigator.webkitTemporaryStorage.queryUsageAndQuota(
        function (usage, quota) {
          var heap = 1073741824;
          try {
            if (performance.memory && performance.memory.jsHeapSizeLimit) {
              heap = performance.memory.jsHeapSizeLimit;
            }
          } catch (error) {
            // 用缺省值
          }
          var quotaMb = Math.round(quota / 1048576);
          var thresholdMb = 2 * Math.round(heap / 1048576);
          send('ENV_PROBE', {
            body: '隐私判定结论(' + label + ') isPrivate=' + (quotaMb < thresholdMb) +
              ' 配额MB=' + quotaMb + ' 阈值MB=' + thresholdMb
          });
        },
        function () {
          send('ENV_PROBE', { body: '隐私判定结论(' + label + ') 配额查询失败' });
        }
      );
    } catch (error) {
      send('ENV_PROBE', { body: '隐私判定结论(' + label + ') 计算异常' });
    }
  }

  /**
   * 文档开始即执行：先在页面脚本之前把误报的判据修好，再回报原始读数以备核对。
   */
  function beforePageScripts() {
    var frame = '顶层';
    var pathname = '?';
    try {
      frame = window.top === window ? '顶层' : '子框架';
      pathname = String(window.location.pathname || '?');
    } catch (error) {
      frame = '跨域子框架';
    }
    mark('文档开始 框架=' + frame + ' 桥=' + (bridge() ? '有' : '无') + ' path=' + pathname);

    // 未处理的 Promise 拒绝只报 `#<Object>` 时看不出原因（页面用 localforage 取设备标记，
    // 它失败会让 `#fingerGenPrint3` 一直为空），这里把原因也写出来
    try {
      window.addEventListener('unhandledrejection', function (event) {
        var reason = event && event.reason;
        var text = reason && reason.message ? reason.message : String(reason);
        mark('未处理的拒绝 ' + String(text).substring(0, 160));
      });
    } catch (error) {
      // 加不上就靠控制台原始输出
    }

    reportDetectionInputs();
    // 修复前先算一次：这是"误报确实存在"的对照证据
    reportDetectionVerdict('修复前');
    patchIncognitoDetection();
    setTimeout(function () {
      reportDetectionVerdict('修复后');
    }, 200);
    setTimeout(reportPrivacyText, 4000);
    setTimeout(reportPrivacyText, 12000);
  }

  function start() {
    if (!document.documentElement) {
      return;
    }
    observer.observe(document.documentElement, { childList: true, subtree: true });
    pass();
    // 页面稳定后回报一次环境事实（存储可用性等）与文档身份，供应用侧排障
    setTimeout(reportEnvironment, 1500);
    setTimeout(reportDocument, 2500);
    // 到点主动复查一次：页面若不再变动，单靠变动观察不会再次调用 pass()，
    // "预填失败/保持沉默"的判断就会永远不发生
    setTimeout(function () {
      if (!reportedPrefillFailure && !reportedPrefillSkip) {
        pass();
      }
    }, PREFILL_DEADLINE_MS + 200);
  }

  if (document.documentElement) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start);
  }

  // 在页面脚本之前动手（本脚本由 javaScriptOnDocumentStart 注入）
  beforePageScripts();

  // 返回 true 是 Web 注入约定的一部分：脚本执行完毕
  return true;
})();
