import { uiText } from '../shared/AppRuntime';
import {
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText
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
  uiMaterialBackground,
  uiMaterialForegroundColor
} from '../shared/AppSurfaceStyle';
import { PopupScrim } from './PopupScrim';

// 结果弹窗：所有「跑完要说结果」的功能都走这里——镜像 ConfirmActionOverlay 的
// 半透明毛玻璃卡片，居中、底衬遮罩、点弹窗外或点确定才关闭。
// 与 ConfirmActionOverlay 的区别：这里只汇报，不做危险操作，所以只有确定键。
@Component
export struct ResultOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  title: string = '';
  message: string = '';
  confirmLabel: string = 'OK';
  altLabel: string = '';
  onConfirm: () => void = () => {};
  onAlt: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onConfirm
      })

      Column() {
        Text(uiText(this.title))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')
        Text(uiText(this.message))
          .fontSize(14)
          .fontColor(themeSecondaryText())
          .lineHeight(20)
          .width('100%')
          .margin({ top: 10 })

        Row({ space: 8 }) {
          if (this.altLabel.length > 0) {
            Button(uiText(this.altLabel), { type: ButtonType.Normal, stateEffect: true })
              .fontSize(14)
              .fontColor(uiMaterialForegroundColor(themePrimaryText()))
              .backgroundColor(uiMaterialBackground(themePrimaryColor()))
              .layoutWeight(1)
              .borderRadius(uiControlRadius(6))
              .backgroundEffect(uiFloatingButtonBackgroundEffect(themePrimaryColor()))
              .systemMaterial(uiButtonMaterial())
              .opacity(0.85)
              .onClick(this.onAlt)
          }
          Button(uiText(this.confirmLabel), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .layoutWeight(1)
            .borderRadius(uiControlRadius(6))
            .backgroundEffect(uiFloatingButtonBackgroundEffect(themePrimaryColor()))
            .systemMaterial(uiButtonMaterial())
            .onClick(this.onConfirm)
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
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
