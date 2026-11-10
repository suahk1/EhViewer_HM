import { uiStatusText, uiText } from '../../shared/AppRuntime';
import {
  themeAccentTextColor,
  themeDividerColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
} from '../../shared/AppPalette';
import { uiCapsuleButtonBackground, uiRadius } from '../../shared/AppSurfaceStyle';

// 详情页四个分区（信息/标签/评论/预览）共用的失败态：一行标题 + 原因 + 单块重试。
// 网络慢时不能一直转圈，超时后必须给出可点的出口。
@Component
export struct DetailSectionRetry {
  @Prop sectionTitle: string = '';
  @Prop message: string = '';
  onRetry: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.sectionTitle.length > 0 ?
          uiText(this.sectionTitle) + ' ' + uiText('failed to load') : uiText('Failed to load'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.message.length > 0) {
          Text(uiStatusText(this.message))
            .fontSize(11)
            .fontColor(themeSecondaryText())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(uiText('Retry'), { type: ButtonType.Capsule, stateEffect: true })
        .height(32)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(themeAccentTextColor())
        .backgroundColor(uiCapsuleButtonBackground())
        .borderRadius(uiRadius(16))
        .padding({ left: 14, right: 14 })
        .flexShrink(0)
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(themeSurface())
    .borderRadius(uiRadius(10))
    .border({ width: 1, color: themeDividerColor() })
  }
}
