import { uiStatusText, uiText } from '../shared/AppRuntime';
import {
  themePrimaryText,
  themeSecondaryText,
  themeSurfaceVariant
} from '../shared/AppPalette';
import {
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialBackground
} from '../shared/AppSurfaceStyle';
import { PopupScrim } from './PopupScrim';

@Component
export struct BlockingBusyOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @Prop message: string = 'Loading...';
  @Prop progressText: string = '';
  @Prop progressCurrent: number = -1;
  @Prop progressTotal: number = -1;
  // 完成态：结果常驻弹窗（一闪而过的 toast 看不清汇总数字），点「知道了」关闭。
  @Prop isDone: boolean = false;
  // 进行中给一个「停止」出口：匹配任务收敛异常时用户不必干等（F-115）。
  @Prop showStop: boolean = false;
  // 最小化出口（F-118）：缩为右上角进度圆点，不挡界面。
  @Prop showMinimize: boolean = false;
  onStop: () => void = () => {};
  onDismiss: () => void = () => {};
  onMinimize: () => void = () => {};
  // 点弹窗外部（F-120 红线）：进行中切后台（最小化），完成态直接关闭。
  onScrimTap: () => void = () => {};

  private hasProgress(): boolean {
    return this.progressCurrent >= 0 && this.progressTotal > 0;
  }

  private progressValue(): number {
    if (!this.hasProgress()) {
      return 0;
    }
    return Math.max(0, Math.min(100, this.progressCurrent * 100 / this.progressTotal));
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: () => {
          this.onScrimTap();
        }
      })

      Column({ space: 12 }) {
        if (!this.isDone) {
          LoadingProgress()
            .width(42)
            .height(42)
            .color(themePrimaryText())
        }
        Text(uiStatusText(this.message))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .textAlign(TextAlign.Center)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (!this.isDone && this.hasProgress()) {
          Progress({ value: this.progressValue(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .color(themePrimaryText())
        }
        // 进度数字独立一行，只要有就显示（不依赖进度条参数，F-113）。
        if (!this.isDone && this.progressText.length > 0) {
          Text(this.progressText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(themeSecondaryText())
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .width('100%')
        }
        if (!this.isDone && this.showStop) {
          Button(uiText('Stop'))
            .width('100%')
            .height(38)
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .backgroundColor(themeSurfaceVariant())
            .onClick(() => {
              this.onStop();
            })
        }
        if (!this.isDone && this.showMinimize) {
          Button(uiText('Minimize'))
            .width('100%')
            .height(38)
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .backgroundColor(themeSurfaceVariant())
            .onClick(() => {
              this.onMinimize();
            })
        }
        if (this.isDone) {
          Button(uiText('Got it'))
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(themeSurfaceVariant())
            .onClick(() => {
              this.onDismiss();
            })
        }
      }
      .width(280)
      .constraintSize({ maxWidth: '72%' })
      .padding({ left: 20, right: 20, top: 20, bottom: 18 })
      .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
      .shadow(uiDialogSurfaceShadow())
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .systemMaterial(uiDialogMaterial())
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
