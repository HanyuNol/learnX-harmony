/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 应用入口页：按登录态分发。
 *
 * 未登录 → 登录表单；网页登录与建立会话中 → SSO 页；已登录 → 主界面（`MainView`，五标签）。
 * 返回键的"空栈行为"也在这一层处理（页面级 `onBackPress`，见下方说明）。
 */

import { common } from '@kit.AbilityKit';
import { TextKeys } from '../common/texts';
import { AuthState, AuthStateListener, AuthStore } from '../viewmodel/authStore';
import { LoginStatus } from '../model/auth';
import { LoginView } from './Login';
import { SsoLoginView } from './SsoLogin';
import { MainView } from './Main';

@Entry
@Component
struct Index {
  @State private status: LoginStatus = LoginStatus.LOGGED_OUT;
  @State private errorKey: string = '';
  /** 当前底部标签索引。由本页持有：返回键逻辑在页面级，需要读它、也要能改它 */
  @State private activeTab: number = 0;

  private store: AuthStore = AuthStore.getInstance();

  private listener: AuthStateListener = (state: AuthState) => {
    this.status = state.status;
    this.errorKey = state.errorTextKey;
  };

  /**
   * 返回键：栈为空时的行为对齐上游（`@bottom-tabs` 的默认 `backBehavior: 'firstRoute'`，
   * 上游源码未显式设置该选项）——非第一个标签回第一个标签，第一个标签交给系统。
   *
   * 栈非空时不会走到这里：`NavDestination` 会先消费返回键（由该栈弹出）。
   * 返回 `true` 表示已处理，不再交给系统。
   */
  onBackPress(): boolean {
    if (this.status === LoginStatus.LOGGED_IN && this.activeTab !== 0) {
      this.activeTab = 0;
      return true;
    }
    return false;
  }

  /**
   * 系统验证弹窗（FR-24）的标题。**页面负责取文案**：`$r` 与资源管理器是 UI 侧的东西，
   * 不该沿着 store → repository 一路穿下去，故在这里解析成字符串再传。
   */
  private biometricTitle(): string {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      return context.resourceManager.getStringSync($r('app.string.' + TextKeys.BIOMETRIC_PROMPT).id);
    } catch (err) {
      // 取不到文案不该影响启动：给一个中性兜底（专有名词，无需翻译）
      return 'LearnX';
    }
  }

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    // 启动时尝试用已保存的凭据恢复登录态（有凭据时会先要一次生物识别，见 FR-24）
    this.store.restoreSession(this.biometricTitle());
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  build() {
    Column() {
      if (this.status === LoginStatus.LOGGED_IN) {
        // 主界面：五标签 + 每标签独立栈。标签索引与错误文案由本页持有/下发
        MainView({ currentTabIndex: this.activeTab, errorKey: this.errorKey })
      } else if (this.status === LoginStatus.SSO_IN_PROGRESS || this.status === LoginStatus.LOGGING_IN) {
        // WebView 主导的登录页（ADR-0008）：用户在这里完成认证，包括输入验证码。
        // `LOGGING_IN`（认证完成后建立会话的那几秒）**也用它**：该视图在此期间显示
        // "正在建立登录会话…"。早先只渲染 SSO_IN_PROGRESS，于是用户刚认证完，
        // 界面会突然回落到登录表单，那段"建立中"遮罩成了死代码（代码审查 R-04）。
        SsoLoginView()
      } else {
        LoginView()
      }
    }
    .width('100%')
    .height('100%')
  }
}
