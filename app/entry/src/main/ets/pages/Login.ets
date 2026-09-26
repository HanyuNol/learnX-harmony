/**
 * 登录界面（最小可用集）。
 *
 * 刻意不做主题、多语言与复杂动效——那些属 FR-13/FR-14/FR-15，另行实现。
 * 这里只保证 FR-01 能在真机上被用户验收：能输入、能提交、能看到**分类型**的错误。
 */

import { AuthState, AuthStateListener, AuthStore } from '../viewmodel/authStore';
import { LoginStatus } from '../model/auth';

@Component
export struct LoginView {
  @State private username: string = '';
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
    this.submitting = state.status === LoginStatus.LOGGING_IN;
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

        TextInput({ placeholder: '密码', text: this.password })
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
            this.store.login(this.username, this.password, this.rememberPassword);
          })

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
