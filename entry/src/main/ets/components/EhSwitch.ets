import { themeAccentTextColor } from '../shared/AppPalette';
import {
  uiSwitchHeight,
  uiSwitchThumbStrokeColor,
  uiSwitchTrackOffColor,
  uiSwitchWidth
} from '../shared/AppSurfaceStyle';

/**
 * 开关控件：滑块带描边。
 * 系统 Toggle 的滑块只有填色，深色界面配白色强调色时会出现「白轨道 + 白滑块」，
 * 关闭态也会因为轨道偏暗而看不出滑块位置，所以这里自绘一个带描边的开关。
 */
@Component
export struct EhSwitch {
  @Prop isOn: boolean = false;
  @Prop trackColor: string = '';
  isEnabled: boolean = true;
  onToggle: (isOn: boolean) => void = (_isOn: boolean) => {};

  private activeTrack(): string {
    return this.trackColor.length > 0 ? this.trackColor : themeAccentTextColor();
  }

  build() {
    Row() {
      Circle()
        .width(uiSwitchHeight() - 4)
        .height(uiSwitchHeight() - 4)
        .fill('#FFFFFF')
        .stroke(uiSwitchThumbStrokeColor(this.isOn, this.trackColor))
        .strokeWidth(1)
    }
    .width(uiSwitchWidth())
    .height(uiSwitchHeight())
    .padding(2)
    .justifyContent(this.isOn ? FlexAlign.End : FlexAlign.Start)
    .borderRadius(uiSwitchHeight() / 2)
    .backgroundColor(this.isOn ? this.activeTrack() : uiSwitchTrackOffColor())
    .opacity(this.isEnabled ? 1 : 0.45)
    .onClick(() => {
      if (this.isEnabled) {
        this.onToggle(!this.isOn);
      }
    })
  }
}
