import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  themeAccentTextColor,
  themeDividerColor,
  themeFieldBackground,
  themePrimaryText,
  themeSelectedBackground,
  themeSurface
} from './AppPalette';
import { uiListItemSelectedBackground } from './AppSurfaceStyle';

export interface SelectColorSet {
  buttonText: ResourceColor;
  buttonBackground: string;
  menuBackground: string;
  optionBackground: ResourceColor;
  optionText: ResourceColor;
  selectedOptionBackground: ResourceColor;
  selectedOptionText: ResourceColor;
  arrow: ResourceColor;
  outline: ResourceColor;
}
export function readerSelectColors(): SelectColorSet {
  return {
    buttonText: themePrimaryText(),
    buttonBackground: themeFieldBackground(),
    menuBackground: themeSurface(),
    optionBackground: Color.Transparent,
    optionText: themePrimaryText(),
    selectedOptionBackground: uiListItemSelectedBackground(themeSelectedBackground()),
    selectedOptionText: themeAccentTextColor(),
    arrow: themePrimaryText(),
    outline: themeDividerColor()
  };
}

export function selectArrowModifier(color: ResourceColor = themePrimaryText(), size: number = 16): SymbolGlyphModifier {
  const modifier = new SymbolGlyphModifier();
  modifier
    .fontSize(size)
    .fontColor([color]);
  return modifier;
}
