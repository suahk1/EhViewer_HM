import { uiStatusText, uiText } from '../../shared/AppRuntime';
import { BOTTOM_AVOID_HEIGHT_KEY } from '../../shared/AppRuntime';
import { appDockBottomInset } from '../FloatingDock';
import { themeAccentTextColor, themeFieldBackground, themePrimaryText, themeSecondaryText,
  themeTransparentColor } from '../../shared/AppPalette';
import { uiCapsuleButtonBackground, uiRadius, uiSearchFieldHeight, uiTitleBarBackgroundEffect } from '../../shared/AppSurfaceStyle';
import { reportAppOverlayHidden } from '../../services/AppChromeSignal';

@Component
export struct CommentComposer {
  @Prop draft: string = '';
  @Prop posting: boolean = false;
  @Prop status: string = '';
  // 未聚焦时底坞浮在输入条上方，输入条要自己让出胶囊高度；
  // 聚焦后底坞会被收走（onFocus 里 reportAppOverlayHidden），此时再让位就是白空一块。
  @State focused: boolean = false;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;

  onDraftChange: (value: string) => void = (_value: string) => {};
  onPost: () => void = () => {};

  // defaultFocus 只在组件首次挂载时生效，页面切换复用时就不灵了（实测 focused 仍为 false）。
  // 这里在每次出现时主动请求一次焦点，保证从「写评论」进来就能直接打字。
  aboutToAppear(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('comment-draft');
      } catch (_error) {
      }
    }, 120);
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        TextArea({ text: this.draft, placeholder: uiText('Write a comment...') })
          .id('comment-draft')
          // 从「写评论」进来就是要写，直接给焦点；之前没有这一行，进页面后
          // 必须手动点一下输入框才弹键盘（实测 focused=false）。
          .defaultFocus(true)
          .layoutWeight(1)
          .height('auto')
          .minLines(1)
          // TextArea.align controls the paragraph's vertical position. This
          // keeps the one-line state centered while remaining harmless once
          // the auto-growing area has multiple lines.
          .align(Alignment.Center)
          // API 20+ supports scrolling overflow in both the auto-growing and
          // constrained states. TextOverflow.None keeps the text content live
          // instead of clipping it before MaxLinesMode.SCROLL can apply.
          .textOverflow(TextOverflow.None)
          .maxLines(4, { overflowMode: MaxLinesMode.SCROLL })
          .barState(BarState.Auto)
          .constraintSize({ minHeight: uiSearchFieldHeight(), maxHeight: 132 })
          .fontSize(15)
          .fontColor(themePrimaryText())
          .placeholderColor(themeSecondaryText())
          .backgroundColor(themeFieldBackground())
          .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .enabled(!this.posting)
          .onChange((value: string) => this.onDraftChange(value))
          // 输入条本身就贴在屏幕底缘，底坞浮在它上面；一聚焦就把底坞收走，
          // 否则输入框和发送按钮会被胶囊挡掉一半（键盘弹起后更明显）。
          .onFocus(() => {
            this.focused = true;
            reportAppOverlayHidden(true);
          })
          .onBlur(() => {
            this.focused = false;
            reportAppOverlayHidden(false);
          })
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(20)
            .fontColor([themeAccentTextColor()])
        }
          .id('post-comment')
          .width(uiSearchFieldHeight())
          .height(uiSearchFieldHeight())
          .backgroundColor(uiCapsuleButtonBackground(true))
          .enabled(!this.posting && this.draft.trim().length > 0)
          .onClick(() => this.onPost())
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      if (this.status.length > 0) {
        Text(uiStatusText(this.status))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .width('100%')
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: this.focused ? 10 : appDockBottomInset(this.bottomAvoidHeight) + 6
    })
    .backgroundColor(themeTransparentColor())
    .backgroundEffect(uiTitleBarBackgroundEffect())
  }
}
