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
 * FR-11（导航）尚未实现，故这里用条件渲染而非路由栈；
 * 登录后的内容页是占位，等 FR-11 与各内容 FR 落地后替换。
 */

import { AuthState, AuthStateListener, AuthStore } from '../viewmodel/authStore';
import { LoginStatus } from '../model/auth';
import { LoginView } from './Login';
import { SsoLoginView } from './SsoLogin';

@Entry
@Component
struct Index {
  @State private status: LoginStatus = LoginStatus.LOGGED_OUT;
  @State private userName: string = '';
  @State private errorKey: string = '';

  private store: AuthStore = AuthStore.getInstance();

  private listener: AuthStateListener = (state: AuthState) => {
    this.status = state.status;
    this.userName = state.userInfo === null ? '' : state.userInfo.name;
    this.errorKey = state.errorTextKey;
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    // 启动时尝试用已保存的凭据静默恢复登录态
    this.store.restoreSession();
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  build() {
    Column() {
      if (this.status === LoginStatus.LOGGED_IN) {
        this.LoggedInPlaceholder()
      } else if (this.status === LoginStatus.SSO_IN_PROGRESS) {
        // WebView 主导的登录页（ADR-0008）：用户在这里完成认证，包括输入验证码
        SsoLoginView()
      } else {
        LoginView()
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 登录后的占位页。仅用于验证 FR-01/03/04 的完整链路，
   * 内容浏览由后续 FR 实现后替换。
   */
  @Builder
  LoggedInPlaceholder() {
    Column({ space: 16 }) {
      Text(this.userName.length > 0 ? `已登录：${this.userName}` : '已登录')
        .fontSize(20)
      Text('内容页面将在后续迭代中实现')
        .fontSize(14)
        .fontColor(Color.Gray)
      // 登出未完成（本地凭据未能清除）时必须让用户看见——否则点"登出"像没反应，
      // 而实际仍处于登录态。文案键由 viewmodel 给出（见 common/logout.ets）
      if (this.errorKey.length > 0) {
        Text($r('app.string.' + this.errorKey))
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Button('登出')
        .onClick(() => {
          this.store.logout();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
