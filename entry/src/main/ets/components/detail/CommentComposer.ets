import { uiStatusText, uiText } from '../../shared/AppRuntime';
import { themeAccentTextColor, themeFieldBackground, themePrimaryText, themeSecondaryText,
  themeTransparentColor } from '../../shared/AppPalette';
import { uiCapsuleButtonBackground, uiRadius, uiSearchFieldHeight, uiTitleBarBackgroundEffect } from '../../shared/AppSurfaceStyle';
import { reportAppOverlayHidden } from '../../services/AppChromeSignal';

@Component
export struct CommentComposer {
  @Prop draft: string = '';
  @Prop posting: boolean = false;
  @Prop status: string = '';
  onDraftChange: (value: string) => void = (_value: string) => {};
  onPost: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        TextArea({ text: this.draft, placeholder: uiText('Write a comment...') })
          .id('comment-draft')
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
            reportAppOverlayHidden(true);
          })
          .onBlur(() => {
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
    .padding({ left: 16, right: 16, top: 8, bottom: 10 })
    .backgroundColor(themeTransparentColor())
    .backgroundEffect(uiTitleBarBackgroundEffect())
  }
}
