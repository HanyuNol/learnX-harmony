/**
 * 会话失效后的处置策略（**纯逻辑**，零系统依赖，可宿主侧穷举测试）。
 *
 * 为什么要单独成模块（2026-09-28 代码审查 🟡 M2）：自动重登的判定原先散在
 * `LearnClient.getWithAuth` 里，写成了"先 `await get()`、再看 `this.credentials` 是否为空"。
 * 而重登流程本身会 `resetSession()` 把 `credentials` 清空——于是**并发的其它请求**
 * 在这段窗口里读到 null，直接抛"无凭据可自动重登"，**不会**加入已经在进行的重登。
 * 真相是：**"是否已有在途重登"必须先判**，它比"有没有凭据"更优先——
 * 有在途就等它（哪怕此刻凭据字段是空的），没有在途才看凭据。
 *
 * 把这条次序写成纯函数后，它才可以被穷举测试钉住（原先埋在一次网络调用里，测不到）。
 */

/** 会话失效后该怎么做 */
export enum ReloginPlan {
  /** 已有在途重登：**等它**（不要自己再判凭据，那段窗口里凭据字段可能已被清空） */
  JOIN_IN_FLIGHT = 'join',
  /** 没有在途：用当前凭据发起一次重登 */
  START = 'start',
  /** 既没有在途、也没有凭据：只能报认证失败，由页面引导重新登录 */
  FAIL = 'fail'
}

/**
 * 给出处置方案。**参数顺序即优先级**：`hasInFlight` 先判。
 */
export function reloginPlan(hasInFlight: boolean, hasCredentials: boolean): ReloginPlan {
  if (hasInFlight) {
    return ReloginPlan.JOIN_IN_FLIGHT;
  }
  return hasCredentials ? ReloginPlan.START : ReloginPlan.FAIL;
}
