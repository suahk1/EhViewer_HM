import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { uiText } from '../shared/AppRuntime';
import { pushActiveBackHandler } from '../shared/AppRuntime';
import { themeOnPrimaryText, themePrimaryColor, themePrimaryText, themeSecondaryText } from '../shared/AppPalette';
import {
  uiButtonMaterial,
  uiControlRadius,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiFloatingButtonBackgroundEffect,
  uiMaterialBackground,
  uiMaterialForegroundColor
} from '../shared/AppSurfaceStyle';
import { PopupScrim } from './PopupScrim';

/// 赞赏弹层：与其它弹窗同款沉浸毛玻璃，按钮走底部栏的光效与显示模式反色。
@Component
export struct DonateOverlay {
  onClose: () => void = () => {};
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @State saving: boolean = false;
  private releaseBackHandler: (() => void) | null = null;

  // 侧滑返回与返回键都要能关掉本弹层：注册到全局返回处理器链，
  // 否则 Index.onBackPress 会把返回当成「离开设置页」，弹层残留在上层。
  aboutToAppear(): void {
    this.releaseBackHandler = pushActiveBackHandler(() => {
      this.onClose();
      return true;
    });
  }

  aboutToDisappear(): void {
    if (this.releaseBackHandler !== null) {
      this.releaseBackHandler();
      this.releaseBackHandler = null;
    }
  }

  private readDonateBytes(context: common.UIAbilityContext): ArrayBuffer {
    const content = context.resourceManager.getMediaContentSync($r('app.media.donation_wechat').id);
    const bytes = new Uint8Array(content);
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  }

  // SaveButton 点击成功时已下发一次性媒体写权限，在授权窗口内直接 createAsset 再写入。
  // 不走 showAssetsCreationDialog：它需要媒体库进程读源文件，而源文件在应用私有 cacheDir，
  // 跨进程读不到，必然返回 14000011 Internal system error。
  private async saveToAlbum(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    console.info('[donate] save start');
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const payload = this.readDonateBytes(context);
      const fileName = 'donation_wechat_' + Date.now().toString();
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      // 用 createAsset（老 API）而非 createImageAssetRequest：后者在当前 SDK 上
      // 内部路径解析失败，抛 13900002 no such file。
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png',
        { title: fileName });
      const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, payload);
      fs.fsyncSync(file.fd);
      fs.closeSync(file);
      console.info('[donate] save ok uri=' + uri);
      promptAction.showToast({ message: uiText('Saved to album') });
    } catch (e) {
      const err = e as BusinessError;
      console.error('[donate] save failed code=' + err.code + ' msg=' + err.message);
      promptAction.showToast({ message: uiText('Save failed') + ' ' + err.code });
    } finally {
      this.saving = false;
    }
  }

  private async openWeChat(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const targets: string[] = ['weixin://scanqrcode', 'weixin://dl/scan', 'weixin://'];
    for (let i = 0; i < targets.length; i++) {
      try {
        await context.startAbility({ action: 'ohos.want.action.viewData', uri: targets[i] });
        return;
      } catch (_e) {
        // 换下一个 scheme
      }
    }
    promptAction.showToast({ message: uiText('Could not open WeChat.') });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onClose
      })

      Column() {
        Row() {
          Text(uiText('Buy me a coffee'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)

          Text(uiText('Close'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .padding({ left: 12 })
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')

        // 正文里「扫码」两字可点：先存图再拉起微信。
        Flex({ wrap: FlexWrap.Wrap }) {
          Text(uiText('Thanks for using the HarmonyOS build. No ads, no tricks. If this app saved you some time, you can'))
            .fontSize(13)
            .lineHeight(21)
            .fontColor(themeSecondaryText())

          Text(uiText('scan the code'))
            .fontSize(13)
            .lineHeight(21)
            .fontColor(themePrimaryColor())
            .decoration({ type: TextDecorationType.Underline, color: themePrimaryColor() })
            .onClick(() => {
              this.saveToAlbum().then(() => {
                this.openWeChat();
              });
            })

          Text(uiText('to buy me a drink.'))
            .fontSize(13)
            .lineHeight(21)
            .fontColor(themeSecondaryText())
        }
        .width('100%')
        .margin({ top: 10 })

        Text(uiText('One-off tip, not a subscription.'))
          .fontSize(11)
          .fontColor(themeSecondaryText())
          .opacity(0.72)
          .width('100%')
          .margin({ top: 6 })

        Image($r('app.media.donation_wechat'))
          .width(200)
          .height(200)
          .borderRadius(12)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#FFFFFF')
          .margin({ top: 12 })

        Text(uiText('Tier gags'))
          .fontSize(12)
          .lineHeight(19)
          .fontColor(themeSecondaryText())
          .width('100%')
          .margin({ top: 12 })

        Text(uiText('This app is a local reader only and ships no content. Tips are voluntary.'))
          .fontSize(11)
          .lineHeight(17)
          .fontColor(themeSecondaryText())
          .opacity(0.65)
          .width('100%')
          .margin({ top: 8 })

        Row({ space: 8 }) {
          // 用系统保存控件：它会给一次性的媒体库写权限，
          // 普通按钮直接建资产会被拒（14000011/201），这是官方推荐的落图方式。
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE,
            buttonType: ButtonType.Normal })
            .fontSize(14)
            .height(40)
            .width('48%')
            .borderRadius(uiControlRadius(6))
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .enabled(!this.saving)
            .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                this.saveToAlbum();
              } else {
                promptAction.showToast({ message: uiText('Save failed') });
              }
            })

          Button(uiText('Open WeChat'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .height(40)
            .layoutWeight(1)
            .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .borderRadius(uiControlRadius(6))
            .backgroundEffect(uiFloatingButtonBackgroundEffect(themePrimaryColor()))
            .systemMaterial(uiButtonMaterial())
            .onClick(() => {
              this.openWeChat();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420, maxHeight: '84%' })
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
