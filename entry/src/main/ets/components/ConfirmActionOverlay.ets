import { uiStatusText, uiText } from '../shared/AppRuntime';
import {
  themeDangerBackground,
  themeDangerText,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurfaceVariant
} from '../shared/AppPalette';
import {
  uiControlRadius,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiButtonMaterial,
  uiFloatingButtonBackgroundEffect,
  uiTransparentButtonBackgroundEffect,
  uiMaterialBackground,
  uiMaterialForegroundColor
} from '../shared/AppSurfaceStyle';
import { PopupScrim } from './PopupScrim';

@Component
export struct ConfirmActionOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop confirmLabel: string = 'OK';
  @Prop altLabel: string = '';
  @Prop danger: boolean = true;
  @Prop showCancel: boolean = true;
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};
  onAlt: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onCancel
      })

      Column() {
        Text(uiText(this.title))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')
        Text(uiStatusText(this.message))
          .fontSize(14)
          .fontColor(themeSecondaryText())
          .lineHeight(20)
          .width('100%')
          .margin({ top: 10 })

        // 按钮顺序固定：次动作 → 主动作 → 取消。取消永远在最后，避免默认焦点落在「取消」上。
        Row({ space: 8 }) {
          if (this.altLabel.length > 0) {
            Button(uiText(this.altLabel), { type: ButtonType.Normal, stateEffect: true })
              .fontSize(14)
              .fontColor(uiMaterialForegroundColor(themePrimaryText()))
              .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
              .layoutWeight(1)
              .borderRadius(uiControlRadius(6))
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(this.onAlt)
          }
          Button(uiText(this.confirmLabel), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(this.danger ? themeDangerText() : uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(uiMaterialBackground(this.danger ? themeDangerBackground() : themePrimaryColor()))
            .layoutWeight(1)
            .borderRadius(uiControlRadius(6))
            .backgroundEffect(uiFloatingButtonBackgroundEffect(this.danger ?
              themeDangerBackground() : themePrimaryColor()))
            .systemMaterial(uiButtonMaterial())
            .onClick(this.onConfirm)
          if (this.showCancel) {
            Button(uiText('Cancel'), { type: ButtonType.Normal, stateEffect: true })
              .fontSize(14)
              .fontColor(uiMaterialForegroundColor(themePrimaryText()))
              .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
              .layoutWeight(1)
              .borderRadius(uiControlRadius(6))
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(this.onCancel)
          }
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .backgroundColor(uiDialogSurfaceBackground())
      .shadow(uiDialogSurfaceShadow())
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.popupWidth = Number.parseFloat(newArea.width.toString());
        this.popupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
    // 修复：BLOCK_HIERARCHY 会让卡片内所有按钮（确认/取消）退出命中测试，
    // 点击落在卡片自身或遮罩上，确认永远不触发（清日志/退出登录/恢复默认全中招）。
    // 改为默认命中：卡片内按钮可点，点卡片空白落在卡片自身（无动作，不误关）。
    .hitTestBehavior(HitTestMode.Default)
  }
}
