import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { appSettingsStore } from '../services/AppSettingsStore';
import {
  isDarkTheme,
  themeGlassSurface,
  themeMaterialContentColor,
  themeMaterialSecondaryContentColor,
  themeAccentTextColor,
  themePrimaryColor,
  themeSelectedBackground,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant
} from './AppPalette';

export const EH_UI_STYLE_CLASSIC: string = 'Classic';
export const EH_UI_STYLE_HARMONY: string = 'Harmony';
const EH_UI_STYLE_HARMONY_LEGACY: string = 'HarmonyOS 7';

let harmony7ChromeMaterial: uiMaterial.Material | undefined;
const harmony7SearchMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7SegmentMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7TintedSegmentMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7ReaderOptionSegmentMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7PanelMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7DialogMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7SelectDialogMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
let immersiveMaterialSupport: boolean | undefined;

function supportsImmersiveMaterial(): boolean {
  if (deviceInfo.sdkApiVersion < 26) {
    return false;
  }
  if (immersiveMaterialSupport === undefined) {
    try {
      immersiveMaterialSupport = uiMaterial.isImmersiveMaterialSupported();
    } catch (error) {
      immersiveMaterialSupport = false;
    }
  }
  return immersiveMaterialSupport;
}

function supportsBackgroundBlur(): boolean {
  return deviceInfo.apiAvailable(9);
}

function supportsBackgroundEffect(): boolean {
  return deviceInfo.apiAvailable(11);
}

export function isHarmonyMaterialEnabled(): boolean {
  return isHarmonyUiStyle() && supportsImmersiveMaterial();
}

export function normalizeUiStyleName(value: string): string {
  return value === EH_UI_STYLE_HARMONY || value === EH_UI_STYLE_HARMONY_LEGACY ?
    EH_UI_STYLE_HARMONY : EH_UI_STYLE_CLASSIC;
}

export function currentUiStyleName(): string {
  return normalizeUiStyleName(appSettingsStore.getValue('ui_style', EH_UI_STYLE_CLASSIC));
}

// 界面风格只保留鸿蒙原生材质一套。基础风格已从设置里移除，这里恒为 true，
// 保留函数是为了让调用点不必改动，也方便将来重新引入第二套皮肤。
export function isHarmonyUiStyle(): boolean {
  return true;
}

export function uiControlRadius(classicRadius: number = 6): number {
  return Math.max(12, classicRadius);
}

export function uiCardRadius(classicRadius: number = 8): number {
  return Math.max(16, classicRadius);
}

export function uiPanelRadius(classicRadius: number = 12): number {
  return Math.max(24, classicRadius);
}

export function uiPillRadius(classicRadius: number = 18): number {
  return Math.max(22, classicRadius);
}

export function uiRadius(classicRadius: number): number {
  if (classicRadius >= 18) {
    return uiPillRadius(classicRadius);
  }
  if (classicRadius >= 8) {
    return uiCardRadius(classicRadius);
  }
  return uiControlRadius(classicRadius);
}

export function uiButtonMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    return uiMaterial.Material.empty;
  }
  return undefined;
}

export function uiTintedButtonMaterial(_solidColor: string): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    return uiMaterial.Material.empty;
  }
  return undefined;
}
// 搜索框的 API 26 交互材质。harmony7SearchMaterials 缓存一直在，
// 导出函数在某次改动里被删掉了，导致搜索框退回普通按钮材质、丢掉点按光效。
export function uiSearchMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle() || !supportsImmersiveMaterial()) {
    return undefined;
  }
  const materialColor = isDarkTheme() ? 'transparent' : 'rgba(255,255,255,0.22)';
  const cached = harmony7SearchMaterials.get(materialColor);
  if (cached !== undefined) {
    return cached;
  }
  const material = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: materialColor,
    applyShadow: false,
    interactive: true,
    lightEffect: { color: Color.White }
  });
  harmony7SearchMaterials.set(materialColor, material);
  return material;
}

export function uiSegmentMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = 'transparent';
    const cached = harmony7SegmentMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: Color.White }
    });
    harmony7SegmentMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

function translucentMaterialColor(solidColor: string): string {
  const color = solidColor.trim();
  if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
    return '#73' + color.substring(1);
  }
  const rgba = /^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*[\d.]+\s*\)$/i.exec(color);
  if (rgba !== null) {
    return 'rgba(' + rgba[1] + ',' + rgba[2] + ',' + rgba[3] + ',0.45)';
  }
  return color;
}

function materialColorWithAlpha(solidColor: string, alpha: string): string {
  const color = solidColor.trim();
  if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
    return '#' + alpha + color.substring(1);
  }
  return color;
}

export function uiTintedSegmentMaterial(solidColor: string): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = translucentMaterialColor(solidColor);
    const cached = harmony7TintedSegmentMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: materialColor,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: Color.White }
    });
    harmony7TintedSegmentMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiReaderOptionButtonMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    return uiMaterial.Material.empty;
  }
  return undefined;
}

export function uiReaderOptionSegmentMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = isDarkTheme() ? 'transparent' : 'rgba(255,255,255,0.22)';
    const cached = harmony7ReaderOptionSegmentMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: materialColor,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: Color.White }
    });
    harmony7ReaderOptionSegmentMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiMaterialBackground(solidColor: ResourceColor): ResourceColor {
  if (!isHarmonyMaterialEnabled()) {
    return solidColor;
  }
  // An opaque backgroundColor is documented to cover the system material.
  // Keep the authored color only as the pre-API-26 fallback; API 26 uses the
  // material's own tint and filter.
  return Color.Transparent;
}

export function uiMaterialLayerBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  // 子层没有自己的材质，全透明会在低端设备（无沉浸材质）上直接消失。
  // 这里保留一个高不透明度的同色底，材质只在它上层做滤镜。
  return isHarmonyMaterialEnabled() ? materialColorWithAlpha(solidColor, 'E6') : solidColor;
}

export function uiButtonHighlightBorderColor(): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return Color.Transparent;
  }
  return isDarkTheme() ? 'rgba(255,255,255,0.30)' : materialColorWithAlpha(themePrimaryColor(), '52');
}

// 浮起胶囊的边缘：玻璃切面在浅色下是一道纯白高光，深色下只留极淡的冷白。
// 关键在"上亮下暗"——单色描边在白底上完全看不见，必须给顶部一道强高光、
// 底部一道弱反光，玻璃才有厚度。
export function uiDockHighlightBorder(): BorderOptions {
  if (!isHarmonyUiStyle()) {
    return { width: 0, color: Color.Transparent };
  }
  // 描边只留轮廓，不承担「高光」：1px 白线在深色界面就是一道硬边，
  // 系统应用的高光是从顶端往下渐隐的一段，不是一根线。渐变由 uiDockHighlightLayer 补。
  if (isDarkTheme()) {
    return {
      width: 1,
      color: {
        top: 'rgba(255,255,255,0.12)',
        right: 'rgba(255,255,255,0.07)',
        bottom: 'rgba(255,255,255,0.05)',
        left: 'rgba(255,255,255,0.07)'
      }
    };
  }
  return {
    width: 1,
    color: {
      top: 'rgba(255,255,255,0.55)',
      right: 'rgba(255,255,255,0.30)',
      bottom: 'rgba(255,255,255,0.18)',
      left: 'rgba(255,255,255,0.30)'
    }
  };
}

export function uiPopupMaterialBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  if (isHarmonyMaterialEnabled()) {
    return 'rgba(0,0,0,0)';
  }
  return isDarkTheme() ? 'rgba(17,24,39,0.84)' : 'rgba(248,249,252,0.84)';
}
export function uiMaterialForegroundColor(fallbackColor: ResourceColor): ResourceColor {
  return isHarmonyMaterialEnabled() ? themeMaterialContentColor() : fallbackColor;
}
// 顶栏、底部胶囊、侧边抽屉统一用这一套玻璃参数：
// 同一模糊半径、同一薄纱浓度，透出的背景强度一致。
// 三处若不共用同一组参数，透光率会出现差异，表现为底部最实、顶栏最透。
// radius 可调：整条栏用 64 把背景糊成一片纯色，悬浮按钮浮在图片上，
// 64 会把背后的图糊成一个实心色块，看着像没透。按钮用小半径保住纹理。
export function uiGlassBarEffect(radius: number = 64): BackgroundEffectOptions {
  const effectEnabled = supportsBackgroundEffect();
  if (!isHarmonyUiStyle() || !effectEnabled) {
    return {
      radius: effectEnabled ? 34 : 0,
      saturation: 1,
      brightness: 1,
      color: Color.Transparent,
      adaptiveColor: AdaptiveColor.DEFAULT
    };
  }
  return {
    radius: radius,
    saturation: isDarkTheme() ? 1.5 : 1.7,
    brightness: 1,
    color: isDarkTheme() ? 'rgba(28,30,36,0.20)' : 'rgba(255,255,255,0.14)',
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

// 悬浮按钮与底坞、顶栏同源，只把半径收到 26。
// 上一版给按钮单独做了"反方向薄纱"（浅色压暗 0.09、深色提白 0.10）：
// 实测浅色下按钮整颗发灰，和底坞的白纱并排一眼就不同色，用户直接指出来过。
// 悬浮不是换一套光学参数的理由，玻璃就是玻璃。
export function uiGlassFloatingButtonEffect(): BackgroundEffectOptions {
  return uiGlassBarEffect(26);
}

export function uiTitleBarBackgroundEffect(): BackgroundEffectOptions {
  return uiGlassBarEffect();
}

export function uiTransparentButtonBackgroundEffect(): BackgroundEffectOptions | undefined {
  if (!isHarmonyUiStyle() || !supportsBackgroundEffect()) {
    return undefined;
  }
  return {
    radius: 40,
    saturation: 1.08,
    brightness: isDarkTheme() ? 0.92 : 1.04,
    color: isDarkTheme() ? 'rgba(16,22,30,0.48)' : 'rgba(255,255,255,0.62)',
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiTitleBarFadeHeight(): number {
  return isHarmonyUiStyle() ? 36 : 8;
}
export function uiReaderMenuBackgroundEffect(): BackgroundEffectOptions {
  const effectEnabled = isHarmonyUiStyle() && supportsBackgroundEffect();
  return {
    radius: effectEnabled ? 10 : 0,
    saturation: 1.04,
    brightness: effectEnabled ? (isDarkTheme() ? 0.98 : 1.04) : 1,
    color: effectEnabled ?
      (isDarkTheme() ? 'rgba(11,16,25,0.56)' : 'rgba(255,255,255,0.52)') : Color.Transparent,
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiReaderProgressBackgroundEffect(): BackgroundEffectOptions {
  return uiPopupBackgroundEffect();
}

export function uiReaderProgressBackgroundColor(fallbackColor: string): string {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return supportsBackgroundEffect() ? 'rgba(0,0,0,0)' : themeSurface();
}

function uiSurfaceBlurStyle(style: BlurStyle): BlurStyle {
  return isHarmonyUiStyle() && supportsBackgroundBlur() ? style : BlurStyle.NONE;
}

export function uiCapsuleButtonBackground(selected: boolean = false,
  selectedColor: string = themeSelectedBackground()): ResourceColor {
  return selected ? selectedColor : (isDarkTheme() ? themeSurfaceVariant() : '#FFFFFF');
}

function uiSurfaceBlurOptions(): BackgroundBlurStyleOptions {
  return {
    colorMode: isDarkTheme() ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
    adaptiveColor: AdaptiveColor.DEFAULT,
    scale: 0.82
  };
}

export function uiPopupBlurStyle(): BlurStyle {
  return uiSurfaceBlurStyle(BlurStyle.COMPONENT_THICK);
}

export function uiPopupBlurOptions(): BackgroundBlurStyleOptions {
  return uiSurfaceBlurOptions();
}

export function uiPopupBackgroundEffect(): BackgroundEffectOptions {
  const effectEnabled = isHarmonyUiStyle() && supportsBackgroundEffect();
  return {
    radius: effectEnabled ? 24 : 0,
    saturation: effectEnabled ? 1.08 : 1,
    brightness: effectEnabled ? (isDarkTheme() ? 0.84 : 1.04) : 1,
    color: Color.Transparent,
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiFloatingButtonBackgroundEffect(tintColor: string = ''): BackgroundEffectOptions | undefined {
  if (tintColor.length === 0) {
    return uiTransparentButtonBackgroundEffect();
  }
  if (!isHarmonyUiStyle() || !supportsBackgroundEffect()) {
    return undefined;
  }
  return {
    radius: 22,
    saturation: 1.12,
    brightness: isDarkTheme() ? 0.9 : 1.04,
    color: materialColorWithAlpha(tintColor, '34'),
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

// 底部浮起胶囊：与顶栏同一族材质（模糊 + 提亮 + 饱和），白度按顶栏的淡色蒙版取，不能比顶栏更实。
// 顶栏是 0.72→0.20 的白渐变，胶囊若压到 0.86 就会变成一块实白，所以这里只上薄薄一层白，
// 靠更大的模糊半径保证文字可读。
// 底部胶囊与顶栏、抽屉共用同一套玻璃参数，保证三处透光一致。
export function uiDockBackgroundEffect(): BackgroundEffectOptions {
  return uiGlassBarEffect();
}

export function uiReaderOptionControlBackground(
  fallbackColor: ResourceColor = Color.Transparent
): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  if (isDarkTheme() || isHarmonyMaterialEnabled()) {
    return Color.Transparent;
  }
  return 'rgba(255,255,255,0.22)';
}

export function uiReaderSelectControlBackground(fallbackColor: ResourceColor): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  if (isDarkTheme() || isHarmonyMaterialEnabled()) {
    return Color.Transparent;
  }
  return 'rgba(255,255,255,0.58)';
}

export function uiPopupEffectBackground(solidColor: string): string {
  return isHarmonyUiStyle() && (supportsBackgroundEffect() || supportsBackgroundBlur()) ?
    'rgba(0,0,0,0)' : solidColor;
}

export function uiSelectPopupBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  if (!isDarkTheme() && (supportsBackgroundEffect() || supportsBackgroundBlur())) {
    return 'rgba(255,255,255,0.82)';
  }
  return uiPopupEffectBackground(solidColor);
}

export function uiReaderSelectPopupBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  if (!isDarkTheme() && (supportsBackgroundEffect() || supportsBackgroundBlur())) {
    return 'rgba(255,255,255,0.90)';
  }
  // 旧系统无法为 Select 菜单单独指定模糊色调，底色也须保证暗色文字对比度。
  return uiPopupMaterialBackground(solidColor);
}

export function uiSearchFieldHeight(): number {
  return isHarmonyUiStyle() ? 44 : 40;
}

function isLightHexColor(color: string): boolean {
  if (color.length < 7 || color.charAt(0) !== '#') {
    return false;
  }
  const r = Number.parseInt(color.substring(1, 3), 16);
  const g = Number.parseInt(color.substring(3, 5), 16);
  const b = Number.parseInt(color.substring(5, 7), 16);
  if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
    return false;
  }
  return (r * 299 + g * 587 + b * 114) / 1000 > 179;
}

// 关闭态轨道：深色界面用浅色半透明，浅色界面用深色半透明。
export function uiSwitchTrackOffColor(): string {
  return isDarkTheme() ? 'rgba(255,255,255,0.20)' : 'rgba(0,0,0,0.12)';
}

// 滑块描边：轨道亮就用深描边，轨道暗就用浅描边，保证任何底色下都能看清滑块轮廓。
export function uiSwitchThumbStrokeColor(isOn: boolean, trackColor: string): string {
  if (!isOn) {
    return isDarkTheme() ? 'rgba(255,255,255,0.38)' : 'rgba(0,0,0,0.20)';
  }
  const track = trackColor.length > 0 ? trackColor : themeAccentTextColor();
  return isLightHexColor(track) ? 'rgba(0,0,0,0.42)' : 'rgba(255,255,255,0.42)';
}

export function uiSwitchWidth(): number {
  return 52;
}

export function uiSwitchHeight(): number {
  return 32;
}

export function uiSelectorHeight(): number {
  return isHarmonyUiStyle() ? 42 : 38;
}

export function uiReaderOptionRowHeight(): number {
  return isHarmonyUiStyle() ? 50 : 52;
}

export function uiTabHeight(): number {
  return isHarmonyUiStyle() ? 42 : 38;
}

export function uiListGap(): number {
  return isHarmonyUiStyle() ? 12 : 8;
}

export function uiPageHorizontalPadding(contentWidth: number): number {
  if (contentWidth >= 840) {
    return 24;
  }
  if (contentWidth >= 600) {
    return 20;
  }
  return 12;
}

export function uiAdaptiveColumnCount(contentWidth: number, preferredWidth: number, gap: number = uiListGap(),
  horizontalPadding: number = 0): number {
  if (contentWidth <= 0 || preferredWidth <= 0) {
    return 1;
  }
  const edgePadding = horizontalPadding > 0 ? horizontalPadding : uiPageHorizontalPadding(contentWidth);
  const padding = edgePadding * 2;
  return Math.max(1, Math.floor((Math.max(0, contentWidth - padding) + gap) / (preferredWidth + gap)));
}

export function uiListItemBackground(fallbackColor: string): string {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(255,255,255,0.055)' : 'rgba(255,255,255,0.78)';
}

export function uiListItemSelectedBackground(fallbackColor: string): string {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(86,192,235,0.18)' : 'rgba(45,134,168,0.14)';
}

export function uiListItemBorderColor(fallbackColor: ResourceColor): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.08)';
}

export function uiAdaptiveTitleSize(contentWidth: number): number {
  return contentWidth >= 600 ? 22 : 20;
}

export function uiAdaptiveToolbarHeight(contentWidth: number): number {
  return contentWidth >= 600 ? 64 : 60;
}

export function uiPanelMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = materialColorWithAlpha(themeSurface(), isDarkTheme() ? 'E6' : 'F0');
    const cached = harmony7PanelMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK,
      materialColor: materialColor,
      applyShadow: true,
      interactive: false
    });
    harmony7PanelMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiDialogMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    // Keep the dialog surface transparent so the blur filter can sample the
    // page behind the modal. An opaque materialColor turns API 26 dialogs into
    // flat panels and hides the background blur.
    const materialColor = 'transparent';
    const cached = harmony7DialogMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false,
      interactive: false
    });
    harmony7DialogMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiSelectDialogMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = isDarkTheme() ? 'rgba(17,24,39,0.88)' : 'rgba(255,255,255,0.82)';
    const cached = harmony7SelectDialogMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: materialColor,
      applyShadow: false,
      interactive: false
    });
    harmony7SelectDialogMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiDialogSurfaceBackground(): string {
  return uiPopupEffectBackground(themeSurface());
}

export function uiDialogBlurStyle(): BlurStyle {
  // ConfirmActionOverlay and the other in-app dialogs are custom Stack layers,
  // not framework Dialog components. Their systemMaterial call is out of scope,
  // so disabling this blur on API 26 turns the panel into plain transparency.
  return isHarmonyUiStyle() ? uiSurfaceBlurStyle(BlurStyle.BACKGROUND_THICK) : BlurStyle.NONE;
}

export function uiDialogBlurOptions(): BackgroundBlurStyleOptions {
  return uiSurfaceBlurOptions();
}

export function uiDialogSurfaceRadius(): number {
  return uiPanelRadius(12);
}

export function uiDialogSurfaceShadow(): ShadowOptions {
  return {
    radius: 18,
    color: themeShadowColor(),
    offsetX: 0,
    offsetY: 8
  };
}
