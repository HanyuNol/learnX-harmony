/**
 * 登录界面（最小可用集）。
 *
 * 刻意不做主题、多语言与复杂动效——那些属 FR-13/FR-14/FR-15，另行实现。
 * 这里只保证 FR-01 能在真机上被用户验收：能输入、能提交、能看到**分类型**的错误。
 *
 * 登录按钮自身不发请求：它进入 WebView 主导的登录页（ADR-0008）——多因子认证的
 * 验证码只能由用户在真实页面上输入，本页因此只负责收学号密码，认证交给页面。
 */

import { AuthState, AuthStateListener, AuthStore } from '../viewmodel/authStore';
import { LoginStatus } from '../model/auth';

@Component
export struct LoginView {
  @State private username: string = '';
  /**
   * 密码必须是 `@State`：它是「登录」按钮可用性（`canSubmit`）的输入之一，
   * 不是 `@State` 就不会在输入后触发重建，按钮会**一直停在不可点**的状态。
   *
   * 真机实测踩过：改成普通字段后，界面上密码框有内容、按钮却点不动，
   * 静态检查与单测都不会发现。
   *
   * 与之相关但**不需要** `@State` 的地方是输入框的 `text` 绑定：不绑定 `text`
   * 就不会把明文写进组件属性（`InputType.Password` 虽然会掩码显示，
   * 少一处承载明文的地方仍更稳妥）。
   */
  @State private password: string = '';
  @State private rememberPassword: boolean = true;
  @State private submitting: boolean = false;
  @State private errorText: string = '';

  private store: AuthStore = AuthStore.getInstance();

  /**
   * 订阅回调。必须保存为字段引用，否则 aboutToDisappear 无法反订阅，
   * 会造成页面销毁后仍被回调（已知内存泄漏风险）。
   */
  private listener: AuthStateListener = (state: AuthState) => {
    this.submitting = state.status === LoginStatus.LOGGING_IN || state.status === LoginStatus.SSO_IN_PROGRESS;
    this.errorText = state.errorDetail;
  };

  aboutToAppear(): void {
    this.store.subscribe(this.listener);
    this.store.loadSavedUsername().then((saved: string) => {
      if (saved.length > 0) {
        this.username = saved;
      }
    });
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.listener);
  }

  private canSubmit(): boolean {
    return this.username.length > 0 && this.password.length > 0 && !this.submitting;
  }

  build() {
    // 必须可滚动：软键盘弹出时会把下方元素挤出可交互区域，
    // 实测会导致「登录」按钮点不到（真机验证发现，非猜测）
    Scroll() {
      Column({ space: 16 }) {
        Text('网络学堂')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)

        TextInput({ placeholder: '学号', text: this.username })
          .type(InputType.Number)
          .width('100%')
          .enabled(!this.submitting)
          .onChange((value: string) => {
            this.username = value;
          })

        TextInput({ placeholder: '密码' })
          .type(InputType.Password)
          .width('100%')
          .enabled(!this.submitting)
          .onChange((value: string) => {
            this.password = value;
          })

        Row({ space: 8 }) {
          Checkbox()
            .select(this.rememberPassword)
            .enabled(!this.submitting)
            .onChange((checked: boolean) => {
              this.rememberPassword = checked;
            })
          Text('记住密码').fontSize(14)
        }
        .width('100%')

        // 错误按四分类给出不同文案：网络问题不得与密码错误混为一谈
        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(14)
            .fontColor(Color.Red)
            .width('100%')
        }

        Button(this.submitting ? '登录中…' : '登录')
          .width('100%')
          .enabled(this.canSubmit())
          .onClick(() => {
            this.store.startSso(this.username, this.password, this.rememberPassword);
          })

        // 让用户对"下一步会打开网页"有预期——多因子认证的验证码要在那里输入
        Text('下一步会在网页中打开统一身份认证，请在页面上完成登录（含验证码）')
          .fontSize(12)
          .fontColor(Color.Gray)
          .width('100%')

        Text('需连接校园网或校方 VPN 后使用')
          .fontSize(12)
          .fontColor(Color.Gray)
      }
      .width('100%')
      .padding(24)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Center)
  }
}
