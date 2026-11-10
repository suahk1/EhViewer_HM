import { ALL_CATEGORY, GalleryCategory } from '../model/GalleryModels';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from '../services/EhUrl';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import { mainContentWidthFallbackVp } from '../services/WindowChromeController';
import { appDockBottomInset } from './FloatingDock';
import {
  normalizeLegacySearchKeywordValue,
  normalizeSubmittedSearchKeywordValue, fullTagNamespace, isKnownTagNamespace} from '../services/SearchKeywordNormalization';
import {
  BOTTOM_AVOID_HEIGHT_KEY,
  LANGUAGE_REVISION_KEY,
  THEME_REVISION_KEY,
  categoryColor,
  categoryDisplayName,
  shouldShowTagTranslations,
  tagNamespaceDisplayName,
  tagTranslationOptionText,
  uiText
} from '../shared/AppRuntime';
import { isDarkTheme, themeAccentTextColor, themeControlMutedBackground, themeControlNeutralBackground, themeFieldBackground, themeInactiveActionText, themeOnPrimaryText, themePageBackground, themePrimaryColor, themePrimaryText, themeSecondaryText, themeShadowColor, themeSurface, themeSurfaceVariant } from '../shared/AppPalette';
import { themeSelectedButtonTextColor } from '../shared/AppPalette';
import {
  isHarmonyMaterialEnabled,
  isHarmonyUiStyle,
  uiButtonMaterial,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiTransparentButtonBackgroundEffect,
  uiButtonHighlightBorderColor,
  uiDockHighlightBorder,
  uiCapsuleButtonBackground,
  uiFloatingButtonBackgroundEffect,
  uiGlassFloatingButtonEffect,
  uiPopupEffectBackground,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiPanelMaterial,
  uiPopupMaterialBackground,
  uiPillRadius,
  uiRadius,
  uiSearchFieldHeight,
  uiSwitchHeight,
  uiSwitchWidth,
  uiTabHeight,
  uiTintedButtonMaterial,
} from '../shared/AppSurfaceStyle';
import { EhSwitch } from './EhSwitch';
import {
  FLOATING_ACTION_GAP,
  FLOATING_ACTION_PRIMARY_GAP,
  FLOATING_ACTION_PRIMARY_SIZE,
  FLOATING_ACTION_SIZE,
  FLOATING_ACTION_SIDE_LEFT,
  FLOATING_ACTION_SIDE_RIGHT,
  floatingActionGridHeight,
  floatingActionGridWidth,
  floatingActionHitIndex,
  floatingActionIndexesForColumn,
  floatingActionSideFromDrag,
  floatingActionToolbarWidth,
  floatingActionVisualColumns,
  normalizeFloatingActionSide
} from './FloatingActionLayoutSupport';

export interface SearchSuggestionItem {
  kind: string;
  title: string;
  subtitle: string;
  query: string;
  translated?: string;
  namespace?: string;
}

export interface GalleryUrlMatch {
  gid: number;
  token: string;
}

@Component
export struct FloatingActionDock {
  @Prop side: string = FLOATING_ACTION_SIDE_RIGHT;
  @Prop extraBottomAvoid: number = 0;
  @BuilderParam content: () => void = this.EmptyContent;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;

  @Builder
  private EmptyContent() {}

  private isLeftSide(): boolean {
    return normalizeFloatingActionSide(this.side) === FLOATING_ACTION_SIDE_LEFT;
  }

  build() {
    // 对齐必须跟 side 一起切：只改内层 alignItems、外层钉死 BottomEnd 的话，
    // 整列永远贴在右边，一级按钮被"焊死"在右下，展开的二级菜单却按 side 排到列的左边。
    // 首次渲染会不会先右后左，取决于 @State 初值（见 storedFloatingActionSide），不靠这里兜。
    Stack({ alignContent: this.isLeftSide() ? Alignment.BottomStart : Alignment.BottomEnd }) {
      Column() {
        this.content()
      }
      .alignItems(this.isLeftSide() ? HorizontalAlign.Start : HorizontalAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 24 + this.bottomAvoidHeight + this.extraBottomAvoid })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

function floatingActionForeground(): ResourceColor {
  // 按钮已改成玻璃底，前景不能再取 onPrimary：自适应主题色下 onPrimary 在深色界面是近黑色，
  // 压在深灰玻璃上等于看不见。统一走正文色，深色界面白、浅色界面黑。
  return themePrimaryText();
}

function floatingActionBackground(solidColor: string): ResourceColor {
  return uiMaterialBackground(solidColor);
}

interface SearchCategoryOption {
  label: string;
  category: number;
}

interface SearchModeOption {
  label: string;
  mode: ListMode;
}

interface TagNamespaceOption {
  value: string;
}

const SEARCH_SUGGESTION_RENDER_BATCH: number = 80;
const TAG_NAMESPACE_OPTIONS: TagNamespaceOption[] = [
  { value: 'artist' },
  { value: 'group' },
  { value: 'parody' },
  { value: 'character' },
  { value: 'female' },
  { value: 'male' },
  { value: 'mixed' },
  { value: 'language' },
  { value: 'cosplayer' },
  { value: 'other' },
  { value: 'location' },
  { value: 'rows' }
];


function isDefaultFilterDisableFlag(flag: number): boolean {
  return flag === 0x100 || flag === 0x200 || flag === 0x400;
}

function activeTagPrefix(keyword: string): string {
  const parts = keyword.trim().split(/\s+/);
  const collected: string[] = [];
  for (let i = parts.length - 1; i >= 0; i--) {
    if (parts[i].indexOf(':') >= 0 || parts[i].indexOf('$') >= 0) {
      break;
    }
    collected.unshift(parts[i]);
  }
  return collected.join(' ').trim();
}

interface ActiveTagSearchInput {
  text: string;
  query: string;
  namespace: string;
}

function activeTagSearchInput(keyword: string): ActiveTagSearchInput {
  const trimmed = keyword.trim();
  const explicit = trimmed.match(/(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*(.*)$/);
  if (explicit !== null && isKnownTagNamespace(explicit[2])) {
    const rawQuery = explicit[3].trim();
    const quoted = /^["“＂]/.test(rawQuery);
    let query = rawQuery.replace(/^["“＂]/, '').trim();
    query = query.replace(/\$+$/, '').trim();
    query = query.replace(/["”＂]$/, '').trim();
    query = query.replace(/\$+$/, '').trim();
    if (quoted || !/\s/.test(query)) {
      return {
        text: explicit[0].trim(),
        query: query,
        namespace: fullTagNamespace(explicit[2])
      };
    }
  }
  const active = activeTagPrefix(trimmed);
  return {
    text: active,
    query: active,
    namespace: ''
  };
}

const EXACT_TAG_PATTERN: RegExp = /(^|\s)([A-Za-z0-9_]+:[^$]+?\$)(?=\s|$)/g;

export function normalizeLegacySearchKeyword(keyword: string): string {
  return normalizeLegacySearchKeywordValue(keyword);
}

export function normalizeSubmittedSearchKeyword(keyword: string): string {
  return normalizeSubmittedSearchKeywordValue(keyword);
}

export function normalizeSearchTagToken(tag: string): string {
  const trimmed = tag.trim();
  if (trimmed.length === 0) {
    return '';
  }
  return trimmed.endsWith('$') ? trimmed : trimmed + '$';
}

export function searchTagTokens(keyword: string): string[] {
  const normalizedKeyword = normalizeLegacySearchKeyword(keyword);
  const tokens: string[] = [];
  const seen: string[] = [];
  EXACT_TAG_PATTERN.lastIndex = 0;
  let match: RegExpExecArray | null = EXACT_TAG_PATTERN.exec(normalizedKeyword);
  while (match !== null) {
    const token = match[2].trim();
    const key = token.toLowerCase();
    const colon = token.indexOf(':');
    const namespace = colon > 0 ? token.substring(0, colon) : '';
    if (token.length > 0 && isKnownTagNamespace(namespace) && seen.indexOf(key) < 0) {
      tokens.push(token);
      seen.push(key);
    }
    match = EXACT_TAG_PATTERN.exec(normalizedKeyword);
  }
  return tokens;
}

export function searchKeywordWithoutTagTokens(keyword: string): string {
  const normalizedKeyword = normalizeLegacySearchKeyword(keyword);
  EXACT_TAG_PATTERN.lastIndex = 0;
  const text = normalizedKeyword.replace(EXACT_TAG_PATTERN,
    (_all: string, leading: string, token: string): string => {
      const colon = token.indexOf(':');
      const namespace = colon > 0 ? token.substring(0, colon) : '';
      return isKnownTagNamespace(namespace) ? leading : _all;
    });
  EXACT_TAG_PATTERN.lastIndex = 0;
  return text.replace(/\s+/g, ' ').trim();
}

export function searchTagTokenLabel(token: string): string {
  let value = token.trim();
  if (value.endsWith('$')) {
    value = value.substring(0, value.length - 1).trim();
  }
  const colon = value.indexOf(':');
  if (colon >= 0 && colon < value.length - 1) {
    value = value.substring(colon + 1).trim();
  }
  return value.replace(/\s+/g, ' ').trim();
}

export function searchTagTokenDisplayLabel(token: string): string {
  let value = token.trim();
  if (value.endsWith('$')) {
    value = value.substring(0, value.length - 1).trim();
  }
  const colon = value.indexOf(':');
  const namespace = colon > 0 ? value.substring(0, colon).trim() : '';
  const tag = colon >= 0 && colon < value.length - 1 ? value.substring(colon + 1).trim() : value;
  if (shouldShowTagTranslations()) {
    const translated = ehTagTranslationStore.translate(namespace, tag);
    if (translated.length > 0) {
      return translated;
    }
  }
  return searchTagTokenLabel(token).replace(/_/g, ' ').replace(/\$/g, ' ').trim();
}

export function searchKeywordForRequest(keyword: string): string {
  const tokens = searchTagTokens(keyword);
  if (tokens.length === 0) {
    return keyword.trim();
  }

  const parts: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const token = searchTagTokenForRequest(tokens[i]);
    if (token.length > 0) {
      parts.push(token);
    }
  }
  const text = searchKeywordWithoutTagTokens(keyword);
  if (text.length > 0) {
    parts.push(text);
  }
  return parts.join(' ').replace(/\s+/g, ' ').trim();
}

function searchTagTokenForRequest(token: string): string {
  let value = token.trim();
  if (value.endsWith('$')) {
    value = value.substring(0, value.length - 1).trim();
  }
  const colon = value.indexOf(':');
  if (colon <= 0 || colon >= value.length - 1) {
    return '';
  }
  const namespace = value.substring(0, colon).trim();
  const tag = value.substring(colon + 1).trim();
  if (namespace.length === 0 || tag.length === 0) {
    return '';
  }
  if (/\s/.test(tag)) {
    return namespace + ':"' + tag.replace(/"/g, '\\"') + '$"';
  }
  return namespace + ':' + tag + '$';
}

export function composeSearchKeywordWithInput(keyword: string, input: string): string {
  const tokens = searchTagTokens(keyword);
  const text = input.trim();
  if (text.length > 0) {
    tokens.push(text);
  }
  return tokens.join(' ').trim();
}

export function removeSearchTagToken(keyword: string, token: string): string {
  const removeKey = token.trim().toLowerCase();
  const tokens = searchTagTokens(keyword).filter((item: string) => item.toLowerCase() !== removeKey);
  const text = searchKeywordWithoutTagTokens(keyword);
  if (text.length > 0) {
    tokens.push(text);
  }
  return tokens.join(' ').trim();
}
export function applyTagSuggestionToKeyword(keyword: string, tag: string, namespace: string = '',
  terminate: boolean = false): string {
  const normalizedTag = tag.trim().replace(/\s+/g, ' ');
  const normalizedNamespace = namespace.trim().toLowerCase();
  const rawFullTag = normalizedTag.indexOf(':') >= 0 || normalizedNamespace.length === 0 ?
    normalizedTag : normalizedNamespace + ':' + normalizedTag;
  const fullTag = terminate ? normalizeSearchTagToken(rawFullTag) : rawFullTag;
  const trimmed = keyword.trim();
  if (trimmed.length === 0) {
    return fullTag;
  }
  // Suggestions are selected for the complete active `namespace: query`
  // expression. For multi-word queries, activeTagSearchInput intentionally
  // avoids treating the text as a live suggestion prefix, so remove that
  // expression here explicitly instead of only removing its final word.
  const explicit = trimmed.match(/(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*([^$]*)$/);
  if (explicit !== null && isKnownTagNamespace(explicit[2])) {
    const start = explicit.index === undefined ? 0 : explicit.index;
    const prefix = trimmed.substring(0, start).trim();
    return (prefix.length > 0 ? prefix + ' ' : '') + tag.trim();
  }
  const active = activeTagSearchInput(trimmed);
  if (active.text.length === 0) {
    return (trimmed + ' ' + fullTag).trim();
  }
  const start = trimmed.length - active.text.length;
  if (start <= 0) {
    return fullTag;
  }
  return (trimmed.substring(0, start).trim() + ' ' + fullTag).trim();
}

export function recordSearchHistory(keyword: string): void {
  ehSearchHistoryStore.record(keyword);
}

function parseGalleryUrl(text: string): GalleryUrlMatch | null {
  const match = text.match(/\/g\/(\d+)\/([a-fA-F0-9]+)\/?/);
  if (match === null) {
    return null;
  }
  const gid = Number.parseInt(match[1]);
  if (Number.isNaN(gid) || gid <= 0) {
    return null;
  }
  return { gid: gid, token: match[2] };
}

export function gallerySuggestionUrl(text: string): GalleryUrlMatch | null {
  return parseGalleryUrl(text);
}

export function buildSearchSuggestions(keyword: string, limit: number = 0,
  namespaces: string[] = []): SearchSuggestionItem[] {
  const text = keyword.trim();
  const next: SearchSuggestionItem[] = [];
  if (text.length === 0) {
    const historyKeywords = ehSearchHistoryStore.getKeywords();
    const unlimited = limit <= 0;
    for (let i = 0; i < historyKeywords.length && (unlimited || next.length < limit); i++) {
      const history = historyKeywords[i];
      next.push({
        kind: 'history',
        title: history,
        subtitle: '',
        query: history
      });
    }
    return next;
  }

  const active = activeTagSearchInput(text);
  if (active.query.length === 0) {
    return next;
  }

  const activeNamespaces = active.namespace.length > 0 ? [active.namespace] : namespaces;
  const tags = ehTagTranslationStore.suggest(active.query, limit, activeNamespaces);
  for (let i = 0; i < tags.length; i++) {
    const tag = tags[i];
    const translated = shouldShowTagTranslations() && tag.translated.length > 0;
    next.push({
      kind: 'tag',
      title: translated ? tag.translated : tag.tag,
      subtitle: translated ? tag.tag : '',
      query: tag.tag,
      translated: tag.translated,
      namespace: tag.namespace
    });
  }
  return next;
}

@Component
export struct SearchSummaryStrip {
  @Prop selectedTagNamespaces: string[] = [];
  @Prop selectedTagNamespaceKey: string = '';
  @Prop revision: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  onToggleTagNamespace: (namespace: string) => void = (_namespace: string) => {};

  build() {
    // 分类标签一行在窄屏放不下，右端用一层渐隐收边：暗示还能继续滑，
    // 同时避免最后一个 chip 被硬切一半。
    Stack({ alignContent: Alignment.End }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(TAG_NAMESPACE_OPTIONS, (option: TagNamespaceOption, index: number) => {
            SearchNamespaceChip({
              label: tagNamespaceDisplayName(option.value),
              paletteIndex: index,
              isActive: this.namespaceSelected(option.value),
              revision: this.revision,
              onClickAction: () => {
                this.onToggleTagNamespace(option.value);
              }
            })
          }, (option: TagNamespaceOption) => option.value + ':' + this.languageRevision.toString())
        }
        .padding({ left: 12, right: 28 })
      }
      .width('100%')
      .height(36)
      .padding({ top: 1, bottom: 1 })
      .align(Alignment.Start)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      Row()
        .width(28)
        .height(36)
        .linearGradient({
          angle: 90,
          colors: [[Color.Transparent, 0], [themePageBackground(), 1]]
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(36)
  }

  private namespaceSelected(namespace: string): boolean {
    return ('|' + this.selectedTagNamespaceKey + '|').indexOf('|' + namespace + '|') >= 0 ||
      this.selectedTagNamespaces.indexOf(namespace) >= 0;
  }
}

@Component
export struct SearchSuggestionList {
  @Prop suggestions: SearchSuggestionItem[] = [];
  @Prop @Watch('onRevisionChanged') revision: number = 0;
  onSelect: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};
  onRemoveHistory: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};
  @State contentWidth: number = 0;
  @State renderLimit: number = SEARCH_SUGGESTION_RENDER_BATCH;
  // 长按删掉的历史词先在本地屏蔽，列表能立刻少一行；父级若跟着重建 revision，
  // 这里就清空——那时 store 里已经没有这个词，重新按 store 渲染不会把它带回来。
  @State suppressedHistory: string[] = [];

  aboutToAppear(): void {
    this.syncContentWidthFromWindow();
    this.resetRenderLimit();
  }

  onRevisionChanged(): void {
    this.suppressedHistory = [];
    this.resetRenderLimit();
  }

  private resetRenderLimit(): void {
    this.renderLimit = SEARCH_SUGGESTION_RENDER_BATCH;
  }

  private activeSuggestions(): SearchSuggestionItem[] {
    if (this.suppressedHistory.length === 0) {
      return this.suggestions;
    }
    return this.suggestions.filter((item: SearchSuggestionItem): boolean =>
      !(item.kind === 'history' && this.suppressedHistory.indexOf(item.query) >= 0));
  }

  private visibleSuggestions(): SearchSuggestionItem[] {
    const active = this.activeSuggestions();
    if (active.length <= this.renderLimit) {
      return active;
    }
    return active.slice(0, this.renderLimit);
  }

  private loadMoreVisibleSuggestions(): void {
    const total = this.activeSuggestions().length;
    if (this.renderLimit < total) {
      this.renderLimit = Math.min(total, this.renderLimit + SEARCH_SUGGESTION_RENDER_BATCH);
    }
  }

  private removeHistorySuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind !== 'history' || suggestion.query.trim().length === 0) {
      return;
    }
    ehSearchHistoryStore.removeKeyword(suggestion.query);
    const next = this.suppressedHistory.slice();
    if (next.indexOf(suggestion.query) < 0) {
      next.push(suggestion.query);
    }
    this.suppressedHistory = next;
    this.onRemoveHistory(suggestion);
  }

  private columnCount(): number {
    const active = this.activeSuggestions();
    const historyCards = active.length > 0 && active[0].kind === 'history';
    if (this.contentWidth <= 0) {
      return 1;
    }
    if (historyCards) {
      if (this.contentWidth < 760) {
        return 1;
      }
      if (this.contentWidth < 1180) {
        return 2;
      }
      return 3;
    }
    if (this.contentWidth < 320) {
      return 1;
    }
    if (this.contentWidth < 520) {
      return 2;
    }
    if (this.contentWidth < 760) {
      return 3;
    }
    if (this.contentWidth < 980) {
      return 4;
    }
    return 5;
  }

  private columnsTemplate(): string {
    const columns = this.columnCount();
    let value = '1fr';
    for (let i = 1; i < columns; i++) {
      value += ' 1fr';
    }
    return value;
  }

  private syncContentWidthFromWindow(): void {
    const width = mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    if (width >= 240) {
      this.contentWidth = width;
    }
  }

  build() {
    Grid() {
      ForEach(this.visibleSuggestions(), (suggestion: SearchSuggestionItem) => {
        GridItem() {
          SearchSuggestionTile({
            suggestion: suggestion,
            onSelect: (item: SearchSuggestionItem) => {
              this.onSelect(item);
            },
            onRemove: (item: SearchSuggestionItem) => {
              this.removeHistorySuggestion(item);
            }
          })
        }
      }, (suggestion: SearchSuggestionItem, index: number) => this.revision.toString() + ':' +
        index.toString() + ':' + suggestion.kind + ':' + suggestion.query + ':' + suggestion.subtitle)
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(6)
    .rowsGap(6)
    // 滚到底最后一行会被底部胶囊栏压住；用 contentEndOffset 只加尾部空白，
    // 不动容器内边距，避免像刚才那样把卡片内容挤没。
    .contentEndOffset(appDockBottomInset(0))
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.None)
    .onReachEnd(() => {
      this.loadMoreVisibleSuggestions();
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = Math.floor(newArea.width as number);
      if (width > 0 && !Number.isNaN(width) && Math.abs(width - this.contentWidth) >= 1) {
        this.contentWidth = width;
      }
    })
  }
}

@Component
struct SearchSuggestionTile {
  @Prop suggestion: SearchSuggestionItem = { kind: '', title: '', subtitle: '', query: '' };
  onSelect: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};
  onRemove: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};

  private iconForKind(kind: string): Resource {
    return kind === 'tag' ? $r('sys.symbol.star') : $r('sys.symbol.clock');
  }

  private tintForKind(kind: string): string {
    return kind === 'tag' ? themeAccentTextColor() : themeSecondaryText();
  }

  build() {
    Row({ space: 5 }) {
      SymbolGlyph(this.iconForKind(this.suggestion.kind))
        .fontSize(18)
        .fontColor([this.tintForKind(this.suggestion.kind)])
        .width(19)
        .flexShrink(0)
      Column({ space: 1 }) {
        Text(this.suggestion.kind === 'history' ? uiText(this.suggestion.title) : this.suggestion.title)
          .fontSize(17)
          .height(22)
          .lineHeight(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.suggestion.subtitle.length > 0) {
          Text(this.suggestion.subtitle)
            .fontSize(13)
            .height(16)
            .lineHeight(16)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 6, right: 6 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(themeSurface())
    .borderRadius(uiRadius(5))
    .onClick(() => {
      this.onSelect(this.suggestion);
    })
    // 历史条目长按删除单条；标签建议是全局词表，不给删。
    .gesture(
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction(() => {
          if (this.suggestion.kind === 'history') {
            this.onRemove(this.suggestion);
          }
        })
    )
  }
}

@Component
struct SearchNamespaceChip {
  @Prop label: string = '';
  @Prop paletteIndex: number = 0;
  @Prop isActive: boolean = false;
  @Prop revision: number = 0;
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;
  onClickAction: () => void = () => {};

  private activeColor(): string {
    const colors: string[] = ['#245F82', '#5B4EA0', '#955626', '#24704D', '#8F3E66', '#456B9F'];
    return colors[this.paletteIndex % colors.length];
  }

  private softColor(): string {
    const colors: string[] = ['#D9EEF7', '#E8E3F8', '#F5E6D8', '#D8F0E4', '#F4DFEB', '#DEEAF7'];
    return colors[this.paletteIndex % colors.length];
  }

  private selectedColor(): string {
    return isDarkTheme() ? this.softColor() : this.activeColor();
  }

  build() {
    Button(this.label, { type: ButtonType.Capsule, stateEffect: true })
      .width(102)
      .height(34)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.isActive ? this.activeColor() : themeSecondaryText())
      .backgroundColor(uiCapsuleButtonBackground(this.isActive, this.softColor()))
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .padding({ left: 4, right: 4 })
      .borderRadius(uiPillRadius(17))
      .onClick(() => {
        this.onClickAction();
      })
  }
}

@Component
export struct SearchAdvancedPanel {
  // A dialog supplies its own scroll container, surface and save/cancel actions.
  @Prop embedded: boolean = false;
  @Prop searchModeValue: ListMode = ListMode.Normal;
  @Prop searchCategory: number = GalleryCategory.None;
  @Prop advancedSearchEnabled: boolean = false;
  @Prop advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @Prop searchFilterEnabled: boolean = true;
  @Prop minRating: number = -1;
  @Prop pageFrom: number = -1;
  @Prop pageTo: number = -1;
  @Prop panelMaxHeight: number = 520;
  @State modeDraft: ListMode = ListMode.Normal;
  @State categoryDraft: number = GalleryCategory.None;
  @State advancedEnabledDraft: boolean = false;
  @State advanceSearchDraft: number = DEFAULT_ADVANCE_SEARCH;
  @State minRatingDraft: number = -1;
  @State pageFromDraft: number = -1;
  @State pageToDraft: number = -1;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  onSearchModeChange: (mode: ListMode) => void = (_mode: ListMode) => {};
  onSearchCategoryChange: (category: number) => void = (_category: number) => {};
  onAdvancedEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onAdvanceSearchChange: (flags: number) => void = (_flags: number) => {};
  onMinRatingChange: (rating: number) => void = (_rating: number) => {};
  onPageFromChange: (value: number) => void = (_value: number) => {};
  onPageToChange: (value: number) => void = (_value: number) => {};
  onClose: () => void = () => {};
  onSearch: () => void = () => {};

  aboutToAppear(): void {
    this.modeDraft = this.searchModeValue;
    this.categoryDraft = this.searchCategory;
    this.advancedEnabledDraft = this.advancedSearchEnabled;
    this.advanceSearchDraft = this.advanceSearch >= 0 ? this.advanceSearch : DEFAULT_ADVANCE_SEARCH;
    this.minRatingDraft = this.minRating;
    this.pageFromDraft = this.pageFrom;
    this.pageToDraft = this.pageTo;
  }

  // 四种搜索模式的字段不一样：一般/订阅按分类筛，上传者和标签直接用关键词输入。
  // 之前四个 tab 共用同一套表单，点订阅搜索只有高亮变化，用户会以为切换失败。
  private showsCategoryPicker(): boolean {
    return this.modeDraft === ListMode.Normal || this.modeDraft === ListMode.Subscription;
  }

  private modeHintText(): string {
    if (this.modeDraft === ListMode.Subscription) {
      return uiText('Searches only inside your subscriptions');
    }
    if (this.modeDraft === ListMode.Uploader) {
      return uiText('Type an uploader name, or uploader:name for an exact match');
    }
    if (this.modeDraft === ListMode.Tag) {
      return uiText('Type tags, for example artist:sample or language:chinese');
    }
    return '';
  }

  private searchModeOptions(): SearchModeOption[] {
    return [
      { label: 'General search', mode: ListMode.Normal },
      { label: 'Subscription search', mode: ListMode.Subscription },
      { label: 'Uploader search', mode: ListMode.Uploader },
      { label: 'Tag search', mode: ListMode.Tag }
    ];
  }
  private categoryOptions(): SearchCategoryOption[] {
    return [
      { label: categoryDisplayName(GalleryCategory.Doujinshi), category: GalleryCategory.Doujinshi },
      { label: categoryDisplayName(GalleryCategory.Manga), category: GalleryCategory.Manga },
      { label: categoryDisplayName(GalleryCategory.ArtistCg), category: GalleryCategory.ArtistCg },
      { label: categoryDisplayName(GalleryCategory.GameCg), category: GalleryCategory.GameCg },
      { label: categoryDisplayName(GalleryCategory.ImageSet), category: GalleryCategory.ImageSet },
      { label: categoryDisplayName(GalleryCategory.Cosplay), category: GalleryCategory.Cosplay },
      { label: categoryDisplayName(GalleryCategory.AsianPorn), category: GalleryCategory.AsianPorn },
      { label: categoryDisplayName(GalleryCategory.NonH), category: GalleryCategory.NonH },
      { label: categoryDisplayName(GalleryCategory.Western), category: GalleryCategory.Western },
      { label: categoryDisplayName(GalleryCategory.Misc), category: GalleryCategory.Misc }
    ];
  }

  private selectedCategoryMask(): number {
    if (this.categoryDraft === GalleryCategory.None) {
      return ALL_CATEGORY;
    }
    return this.categoryDraft & ALL_CATEGORY;
  }

  private allCategoriesSelected(): boolean {
    return this.selectedCategoryMask() === ALL_CATEGORY;
  }

  private categorySelected(category: number): boolean {
    return (this.selectedCategoryMask() & category) !== 0;
  }

  private emitCategoryMask(mask: number): void {
    const next = mask === ALL_CATEGORY ? GalleryCategory.None : mask;
    this.categoryDraft = next;
    this.onSearchCategoryChange(next);
  }

  private toggleAllCategories(): void {
    this.emitCategoryMask(this.allCategoriesSelected() ? 0 : ALL_CATEGORY);
  }

  private toggleCategory(category: number): void {
    const mask = this.selectedCategoryMask();
    const next = (mask & category) !== 0 ? (mask & ~category) : (mask | category);
    this.emitCategoryMask(next);
  }

  private ratingLevel(): number {
    if (this.minRatingDraft <= 0) {
      return 1;
    }
    return Math.max(1, Math.min(5, this.minRatingDraft));
  }

  private setRatingLevel(level: number): void {
    const next = level <= 1 ? -1 : level;
    this.minRatingDraft = next;
    this.onMinRatingChange(next);
  }

  private setAdvancedEnabledDraft(enabled: boolean): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedEnabledDraft = enabled;
    });
    this.onAdvancedEnabledChange(enabled);
  }

  private flagOn(flag: number): boolean {
    if (!this.searchFilterEnabled && isDefaultFilterDisableFlag(flag)) {
      return true;
    }
    return (this.advanceSearchDraft & flag) !== 0;
  }

  private setFlag(flag: number, enabled: boolean): void {
    if (!this.searchFilterEnabled && isDefaultFilterDisableFlag(flag)) {
      return;
    }
    const next = enabled ? (this.advanceSearchDraft | flag) : (this.advanceSearchDraft & ~flag);
    this.advanceSearchDraft = next;
    this.onAdvanceSearchChange(next);
  }

  @Builder
  private sectionTitle(title: string) {
    Text(uiText(title))
      .fontSize(12)
      .fontColor(themeSecondaryText())
      .fontWeight(FontWeight.Medium)
      .margin({ top: 4 })
  }

  @Builder
  private optionsContent() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        ForEach(this.searchModeOptions(), (option: SearchModeOption) => {
          SearchModeSegmentButton({
            label: option.label,
            selected: option.mode === this.modeDraft,
            onSelect: () => {
              if (option.mode === this.modeDraft) {
                return;
              }
              this.modeDraft = option.mode;
              this.onSearchModeChange(option.mode);
            }
          })
        }, (option: SearchModeOption) => option.mode.toString() + '-' + this.languageRevision.toString())
      }
      .width('100%')

      if (this.modeHintText().length > 0) {
        Text(this.modeHintText())
          .fontSize(12)
          .lineHeight(18)
          .fontColor(themeSecondaryText())
          .width('100%')
          .margin({ top: 4 })
      }
      if (this.showsCategoryPicker()) {
        Text(tagTranslationOptionText('Categories', '分类'))
        .fontSize(12)
        .fontColor(themeSecondaryText())
        .fontWeight(FontWeight.Medium)
        .margin({ top: 4 })
      Button(tagTranslationOptionText('All categories', '全部分类'),
        { type: ButtonType.Capsule, stateEffect: true })
        .height(34)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.allCategoriesSelected() ? Color.White : themeSecondaryText())
        .backgroundColor(uiCapsuleButtonBackground(this.allCategoriesSelected(), themePrimaryColor()))
        .animation({ duration: 180, curve: Curve.EaseInOut })
        .width('100%')
        .borderRadius(uiPillRadius(17))
        .onClick(() => {
          this.toggleAllCategories();
        })
      Column({ space: 8 }) {
        ForEach(this.categoryRows(), (row: SearchCategoryOption[]) => {
          Row({ space: 8 }) {
            ForEach(row, (option: SearchCategoryOption) => {
              SearchCategoryChip({
                label: option.label,
                category: option.category,
                selected: this.categorySelected(option.category),
                onToggle: (category: number) => {
                  this.toggleCategory(category);
                }
              })
            }, (option: SearchCategoryOption) => option.category.toString())
          }
          .width('100%')
        }, (row: SearchCategoryOption[], index: number) => index.toString() + row.map((option: SearchCategoryOption) => option.category.toString()).join('-'))
      }
      .width('100%')
      }

      Row() {
        Text(uiText('Advanced'))
        .fontSize(14)
        .fontColor(themePrimaryText())
        Blank()
        EhSwitch({
          isOn: this.advancedEnabledDraft,
          trackColor: themeAccentTextColor(),
          onToggle: (isOn: boolean) => {
            this.setAdvancedEnabledDraft(isOn);
          }
        })
      }
      .width('100%')
      .height(42)
      .padding({ left: 10, right: 10 })
      .backgroundColor(uiCapsuleButtonBackground())
      .borderRadius(uiPillRadius(21))

      if (this.advancedEnabledDraft) {
        Column({ space: 10 }) {
          this.sectionTitle('Search galleries')
          Row({ space: 8 }) {
            SearchFlagChip({ label: 'Name', isOn: this.flagOn(0x1), onToggle: (isOn: boolean) => { this.setFlag(0x1, isOn); } })
            SearchFlagChip({ label: 'Tags', isOn: this.flagOn(0x2), onToggle: (isOn: boolean) => { this.setFlag(0x2, isOn); } })
          }
          Row({ space: 8 }) {
            SearchFlagChip({ label: 'Description', isOn: this.flagOn(0x4), onToggle: (isOn: boolean) => { this.setFlag(0x4, isOn); } })
            SearchFlagChip({ label: 'Torrent', isOn: this.flagOn(0x8), onToggle: (isOn: boolean) => { this.setFlag(0x8, isOn); } })
          }

          this.sectionTitle('Options')
          Row({ space: 8 }) {
            SearchFlagChip({ label: 'Has torrent', isOn: this.flagOn(0x10), onToggle: (isOn: boolean) => { this.setFlag(0x10, isOn); } })
            SearchFlagChip({ label: 'Low power', isOn: this.flagOn(0x20), onToggle: (isOn: boolean) => { this.setFlag(0x20, isOn); } })
          }
          Row({ space: 8 }) {
            SearchFlagChip({ label: 'Downvoted', isOn: this.flagOn(0x40), onToggle: (isOn: boolean) => { this.setFlag(0x40, isOn); } })
            SearchFlagChip({ label: 'Expunged', isOn: this.flagOn(0x80), onToggle: (isOn: boolean) => { this.setFlag(0x80, isOn); } })
          }

          this.sectionTitle('Disable default filter')
          Row({ space: 8 }) {
            SearchFlagChip({ label: 'No lang filter', isOn: this.flagOn(0x100), isEnabled: this.searchFilterEnabled, onToggle: (isOn: boolean) => { this.setFlag(0x100, isOn); } })
            SearchFlagChip({ label: 'No uploader filter', isOn: this.flagOn(0x200), isEnabled: this.searchFilterEnabled, onToggle: (isOn: boolean) => { this.setFlag(0x200, isOn); } })
          }
          Row({ space: 8 }) {
            SearchFlagChip({ label: 'No tag filter', isOn: this.flagOn(0x400), isEnabled: this.searchFilterEnabled, onToggle: (isOn: boolean) => { this.setFlag(0x400, isOn); } })
            Blank().layoutWeight(1)
          }

          this.sectionTitle('Rating')
          RatingStarBar({
            level: this.ratingLevel(),
            onSelect: (level: number) => {
              this.setRatingLevel(level);
            }
          })

          this.sectionTitle('Pages')
          Row({ space: 8 }) {
            TextInput({ text: this.pageFromDraft >= 0 ? this.pageFromDraft.toString() : '',
              placeholder: uiText('From page') })
              .layoutWeight(1)
              .height(uiSearchFieldHeight())
              .type(InputType.Number)
              .inputFilter('[0-9]*')
              .fontSize(14)
              .fontColor(themePrimaryText())
              .placeholderColor(themeSecondaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                const parsed = Number.parseInt(value, 10);
                this.pageFromDraft = Number.isFinite(parsed) ? Math.max(0, parsed) : -1;
                this.onPageFromChange(this.pageFromDraft);
              })
            Text('–').fontColor(themeSecondaryText())
            TextInput({ text: this.pageToDraft >= 0 ? this.pageToDraft.toString() : '',
              placeholder: uiText('To page') })
              .layoutWeight(1)
              .height(uiSearchFieldHeight())
              .type(InputType.Number)
              .inputFilter('[0-9]*')
              .fontSize(14)
              .fontColor(themePrimaryText())
              .placeholderColor(themeSecondaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                const parsed = Number.parseInt(value, 10);
                this.pageToDraft = Number.isFinite(parsed) ? Math.max(0, parsed) : -1;
                this.onPageToChange(this.pageToDraft);
              })
          }
          .width('100%')
        }
        .width('100%')
        .clip(true)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: -8 }))
          .animation({ duration: 180, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
  }

  build() {
    Column() {
      if (this.embedded) {
        this.optionsContent()
      } else {
        this.popupContent()
      }
    }
    .width('100%')
  }

  @Builder
  private popupContent() {
    Column() {
      Scroll() {
        this.optionsContent()
      }
      .width('100%')
      .constraintSize({ maxHeight: Math.max(320, this.panelMaxHeight - 64) })

      Column() {
        Button(uiText('Search'), { type: ButtonType.Capsule, stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([themeOnPrimaryText()])
            Text(uiText('Search'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(themeOnPrimaryText())
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .width('100%')
        }
        .height(44)
        .backgroundColor(themePrimaryColor())
        .width('100%')
        .borderRadius(uiPillRadius(22))
        .backgroundEffect(uiFloatingButtonBackgroundEffect(themePrimaryColor()))
        .onClick(() => {
          this.onSearch();
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(isHarmonyUiStyle() ? Color.Transparent : themeSurface())
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .backgroundColor(uiMaterialBackground(uiPopupMaterialBackground(themeSurface())))
    .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
    .shadow(isHarmonyMaterialEnabled() ? {
      radius: 0,
      color: Color.Transparent,
      offsetX: 0,
      offsetY: 0
    } : {
      radius: 12,
      color: themeShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
    .clip(true)
    .borderRadius(uiRadius(8))
    .systemMaterial(uiPanelMaterial())
  }

  private categoryRows(): SearchCategoryOption[][] {
    const options = this.categoryOptions();
    const rows: SearchCategoryOption[][] = [];
    for (let i = 0; i < options.length; i += 2) {
      rows.push(options.slice(i, i + 2));
    }
    return rows;
  }
}

@Component
export struct QuickActionColumn {
  @Prop expanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop accountFilterEnabled: boolean = true;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop canImageSearch: boolean = false;
  @Prop canBookmark: boolean = false;
  @Prop showTranslationButton: boolean = true;
  @Prop translationEnabled: boolean = false;
  @Prop maxExpandedHeight: number = 360;
  @Prop side: string = FLOATING_ACTION_SIDE_RIGHT;
  onToggle: () => void = () => {};
  onFilter: () => void = () => {};
  onJump: () => void = () => {};
  onRefresh: () => void = () => {};
  onRandom: () => void = () => {};
  onImageSearch: () => void = () => {};
  onBookmark: () => void = () => {};
  onTranslate: () => void = () => {};
  onSideChange: (side: string) => void = (_side: string) => {};
  @State activeActionIndex: number = -1;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private sideDragDetected: boolean = false;

  private isLeftSide(): boolean {
    return normalizeFloatingActionSide(this.side) === FLOATING_ACTION_SIDE_LEFT;
  }

  private toggleExpanded(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.onToggle();
    });
  }

  private actionCount(): number {
    if (!this.expanded) {
      return 0;
    }
    return this.randomActionIndex() + 1;
  }

  private primaryIndex(): number {
    return this.actionCount();
  }

  private expandedActionsHeight(): number {
    return floatingActionGridHeight(this.actionCount(), this.maxExpandedHeight);
  }

  private expandedActionsWidth(): number {
    return floatingActionGridWidth(this.actionCount(), this.maxExpandedHeight);
  }

  private toolbarWidth(): number {
    return floatingActionToolbarWidth(this.actionCount(), this.maxExpandedHeight);
  }

  private visualActionColumns(): number[] {
    return floatingActionVisualColumns(this.actionCount(), this.maxExpandedHeight, this.side);
  }

  private actionIndexesForColumn(column: number): number[] {
    return floatingActionIndexesForColumn(column, this.actionCount(), this.maxExpandedHeight);
  }

  private bookmarkActionIndex(): number {
    return this.canBookmark ? this.optionalActionStartIndex() : -1;
  }

  private imageSearchActionIndex(): number {
    return this.canImageSearch ? this.optionalActionStartIndex() + (this.canBookmark ? 1 : 0) : -1;
  }

  private randomActionIndex(): number {
    return this.optionalActionStartIndex() + (this.canBookmark ? 1 : 0) + (this.canImageSearch ? 1 : 0);
  }

  private translationActionIndex(): number {
    return this.showTranslationButton ? 3 : -1;
  }

  private optionalActionStartIndex(): number {
    return this.showTranslationButton ? 4 : 3;
  }

  private hitActionIndex(x: number, y: number): number {
    return floatingActionHitIndex(x, y, this.actionCount(), this.maxExpandedHeight, this.side, true);
  }

  private touchX(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].x;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].x;
    }
    return -1;
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].y;
    }
    return -1;
  }

  private updateActiveAction(event: TouchEvent): void {
    const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
    if (index !== this.activeActionIndex) {
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
        this.activeActionIndex = index;
      });
    }
  }

  private triggerAction(index: number): void {
    if (index < 0) {
      return;
    }
    if (index === this.primaryIndex()) {
      this.toggleExpanded();
      return;
    }
    if (index === 0) {
      this.onFilter();
    } else if (index === 1 && this.canJump) {
      this.onJump();
    } else if (index === 2) {
      this.onRefresh();
    } else if (index === this.translationActionIndex()) {
      this.onTranslate();
    } else if (index === this.bookmarkActionIndex()) {
      this.onBookmark();
    } else if (index === this.imageSearchActionIndex()) {
      this.onImageSearch();
    } else if (index === this.randomActionIndex() && this.canRandom) {
      this.onRandom();
    }
  }

  private handleToolbarTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.touchStartX = this.touchX(event);
      this.touchStartY = this.touchY(event);
      this.sideDragDetected = false;
      this.updateActiveAction(event);
    } else if (event.type === TouchType.Move) {
      const offsetX = this.touchX(event) - this.touchStartX;
      const offsetY = this.touchY(event) - this.touchStartY;
      if (floatingActionSideFromDrag(offsetX, offsetY).length > 0) {
        this.sideDragDetected = true;
        this.activeActionIndex = -1;
      } else if (!this.sideDragDetected) {
        this.updateActiveAction(event);
      }
    } else if (event.type === TouchType.Up) {
      if (this.sideDragDetected) {
        const offsetX = this.touchX(event) - this.touchStartX;
        const offsetY = this.touchY(event) - this.touchStartY;
        const targetSide = floatingActionSideFromDrag(offsetX, offsetY);
        this.sideDragDetected = false;
        this.activeActionIndex = -1;
        if (targetSide.length > 0) {
          this.onSideChange(targetSide);
        }
        return;
      }
      const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
      const fallbackIndex = index >= 0 ? index : this.activeActionIndex;
      this.activeActionIndex = -1;
      this.triggerAction(fallbackIndex);
    } else if (event.type === TouchType.Cancel) {
      this.sideDragDetected = false;
      this.activeActionIndex = -1;
    }
  }

  private actionLabel(index: number): string {
    if (index === 0) return this.accountFilterEnabled ? uiText('Filter On') : uiText('Filter');
    if (index === 1) return uiText('Jump');
    if (index === 2) return uiText('Refresh');
    if (index === this.translationActionIndex()) {
      return this.translationEnabled ? uiText('Show original titles') : uiText('Translate titles');
    }
    if (index === this.bookmarkActionIndex()) return uiText('Add bookmark');
    if (index === this.imageSearchActionIndex()) return uiText('Image search');
    if (index === this.randomActionIndex()) return uiText('Random');
    return '';
  }

  private actionIcon(index: number): Resource {
    if (index === 0) return $r('sys.symbol.funnel');
    if (index === 1) return $r('sys.symbol.chevron_forward');
    if (index === 2) return $r('sys.symbol.play_arrow_triangle_2_circlepath');
    if (index === this.translationActionIndex()) return $r('sys.symbol.translate');
    if (index === this.bookmarkActionIndex()) return $r('sys.symbol.bookmark');
    if (index === this.imageSearchActionIndex()) return $r('sys.symbol.magnifyingglass');
    if (index === this.randomActionIndex()) return $r('sys.symbol.play_fill');
    return $r('sys.symbol.more');
  }

  private actionEnabled(index: number): boolean {
    if (index === 1) return this.canJump;
    if (index === this.randomActionIndex()) return this.canRandom;
    return index >= 0 && index < this.actionCount();
  }

  @Builder
  private actionBubble(index: number) {
    ActionBubble({
      label: this.actionLabel(index),
      symbolIcon: this.actionIcon(index),
      isEnabled: this.actionEnabled(index),
      checked: (index === 0 && this.accountFilterEnabled) ||
        (index === this.translationActionIndex() && this.translationEnabled),
      active: this.activeActionIndex === index,
      side: this.side,
      directTap: false
    })
  }

  build() {
    Column() {
      if (this.expanded) {
        Row({ space: FLOATING_ACTION_GAP }) {
          ForEach(this.visualActionColumns(), (column: number) => {
            Column({ space: FLOATING_ACTION_GAP }) {
              ForEach(this.actionIndexesForColumn(column), (index: number) => {
                Row() {
                  this.actionBubble(index)
                }
                .width(FLOATING_ACTION_SIZE)
                .height(FLOATING_ACTION_SIZE)
                .justifyContent(this.isLeftSide() ? FlexAlign.Start : FlexAlign.End)
                .clip(false)
              }, (index: number) => index.toString())
            }
            .width(FLOATING_ACTION_SIZE)
            .alignItems(this.isLeftSide() ? HorizontalAlign.Start : HorizontalAlign.End)
          }, (column: number) => column.toString())
        }
        .width(this.expandedActionsWidth())
        .height(this.expandedActionsHeight())
        .alignItems(VerticalAlign.Top)
        .alignSelf(ItemAlign.Center)
        .margin({ bottom: FLOATING_ACTION_PRIMARY_GAP })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 180, curve: Curve.EaseOut }))
      }

      ActionBubble({
        label: uiText('Actions'),
        symbolIcon: this.expanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        isEnabled: true,
        primary: true,
        active: this.activeActionIndex === this.primaryIndex(),
        side: this.side,
        directTap: false
      })
    }
    .width(this.toolbarWidth())
    // 展开的网格宽度和一级按钮 54vp 不等，贴 Start/End 会让两者错开半格。
    // 统一居中，左右两侧都以一级按钮为轴。
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((event: TouchEvent) => {
      this.handleToolbarTouch(event);
    })
  }
}

@Component
export struct SearchActionColumn {
  @Prop showTranslationButton: boolean = false;
  @Prop translationEnabled: boolean = false;
  @Prop side: string = FLOATING_ACTION_SIDE_RIGHT;
  onSearch: () => void = () => {};
  onTranslate: () => void = () => {};
  onSideChange: (side: string) => void = (_side: string) => {};
  @State activeActionIndex: number = -1;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private sideDragDetected: boolean = false;

  private isLeftSide(): boolean {
    return normalizeFloatingActionSide(this.side) === FLOATING_ACTION_SIDE_LEFT;
  }

  private actionCount(): number {
    return this.showTranslationButton ? 1 : 0;
  }

  private primaryIndex(): number {
    return this.actionCount();
  }

  private toolbarHeight(): number {
    return this.showTranslationButton ?
      FLOATING_ACTION_SIZE + FLOATING_ACTION_PRIMARY_GAP + FLOATING_ACTION_PRIMARY_SIZE :
      FLOATING_ACTION_PRIMARY_SIZE;
  }

  private touchX(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].x;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].x;
    }
    return -1;
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].y;
    }
    return -1;
  }

  private hitActionIndex(x: number, y: number): number {
    return floatingActionHitIndex(x, y, this.actionCount(), FLOATING_ACTION_SIZE, this.side, true);
  }

  private updateActiveAction(event: TouchEvent): void {
    const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
    if (index !== this.activeActionIndex) {
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
        this.activeActionIndex = index;
      });
    }
  }

  private triggerAction(index: number): void {
    if (index === this.primaryIndex()) {
      this.onSearch();
    } else if (this.showTranslationButton && index === 0) {
      this.onTranslate();
    }
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.touchStartX = this.touchX(event);
      this.touchStartY = this.touchY(event);
      this.sideDragDetected = false;
      this.updateActiveAction(event);
    } else if (event.type === TouchType.Move) {
      const offsetX = this.touchX(event) - this.touchStartX;
      const offsetY = this.touchY(event) - this.touchStartY;
      if (floatingActionSideFromDrag(offsetX, offsetY).length > 0) {
        this.sideDragDetected = true;
        this.activeActionIndex = -1;
      } else if (!this.sideDragDetected) {
        this.updateActiveAction(event);
      }
    } else if (event.type === TouchType.Up) {
      if (this.sideDragDetected) {
        const targetSide = floatingActionSideFromDrag(
          this.touchX(event) - this.touchStartX, this.touchY(event) - this.touchStartY);
        this.sideDragDetected = false;
        this.activeActionIndex = -1;
        if (targetSide.length > 0) {
          this.onSideChange(targetSide);
        }
        return;
      }
      const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
      const fallbackIndex = index >= 0 ? index : this.activeActionIndex;
      this.activeActionIndex = -1;
      this.triggerAction(fallbackIndex);
    } else if (event.type === TouchType.Cancel) {
      this.sideDragDetected = false;
      this.activeActionIndex = -1;
    }
  }

  build() {
    Column() {
      if (this.showTranslationButton) {
        ActionBubble({
          label: this.translationEnabled ? uiText('Show original titles') : uiText('Translate titles'),
          symbolIcon: $r('sys.symbol.translate'),
          isEnabled: true,
          checked: this.translationEnabled,
          active: this.activeActionIndex === 0,
          side: this.side,
          directTap: false
        })
          .margin({ bottom: FLOATING_ACTION_PRIMARY_GAP })
      }
      ActionBubble({
        label: uiText('Search'),
        symbolIcon: $r('sys.symbol.magnifyingglass'),
        isEnabled: true,
        primary: true,
        active: this.activeActionIndex === this.primaryIndex(),
        side: this.side,
        directTap: false
      })
    }
    .width(FLOATING_ACTION_PRIMARY_SIZE)
    .height(this.toolbarHeight())
    // 子按钮 44vp、一级按钮 54vp，贴 Start/End 会让子按钮整体偏 5vp。
    // 统一居中，左右两侧同一根轴线。
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event);
    })
  }
}

@Component
export struct ActionBubble {
  @Prop label: string = '';
  @Prop symbolIcon: Resource = $r('sys.symbol.plus');
  @Prop isEnabled: boolean = true;
  @Prop active: boolean = false;
  @Prop checked: boolean = false;
  @Prop side: string = FLOATING_ACTION_SIDE_RIGHT;
  @Prop showLabel: boolean = false;
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;
  primary: boolean = false;
  directTap: boolean = true;
  onTapAction: () => void = () => {};
  // 点按光效：和底部胶囊同一套，按下即亮、圆心跟触点、松手 130ms 散开。
  @State private glowX: number = -1000;
  @State private glowY: number = -1000;
  @State private glowOpacity: number = 0;
  @State private glowScale: number = 1;

  private buttonSize(): number {
    return this.primary ? 54 : 44;
  }

  // 光斑比按钮大，裁在圆里之后整颗发亮、边缘自然收暗（和底栏同一个做法）。
  private glowDiameter(): number {
    return this.buttonSize() * 1.5;
  }

  private isLeftSide(): boolean {
    return normalizeFloatingActionSide(this.side) === FLOATING_ACTION_SIDE_LEFT;
  }

  private buttonColor(): string {
    return this.primary || this.checked ? themePrimaryColor() : themeControlNeutralBackground();
  }

  @Builder
  private labelBubble() {
    Text(this.label)
      .fontSize(12)
      .fontColor(themePrimaryText())
      // 与展开出来的子按钮同一套玻璃，否则气泡是实心块、按钮是玻璃，展开时一眼看出两代材质。
      .backgroundColor(uiPopupEffectBackground(themeSurface()))
      .backgroundEffect(uiGlassFloatingButtonEffect())
      .border(uiDockHighlightBorder())
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(uiRadius(15))
      .constraintSize({ maxWidth: 214 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ x: this.isLeftSide() ? -10 : 10 }))
        .animation({ duration: 160, curve: Curve.EaseOut }))
  }

  @Builder
  private buttonBubble() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.symbolIcon)
        .fontSize(this.primary ? 26 : 20)
        .fontColor([this.isEnabled ?
          (this.checked ? themeSelectedButtonTextColor() : floatingActionForeground()) : themeInactiveActionText()])

      if (this.glowOpacity > 0.01) {
        Column()
          .width(this.glowDiameter())
          .height(this.glowDiameter())
          .borderRadius(this.glowDiameter() / 2)
          .radialGradient({
            center: ['50%', '50%'],
            radius: '46%',
            colors: isDarkTheme()
              ? [['rgba(255,255,255,0.72)', 0], ['rgba(255,255,255,0.36)', 0.45],
                 ['rgba(255,255,255,0.12)', 0.72], ['rgba(255,255,255,0.00)', 1]]
              : [['rgba(58,78,96,0.32)', 0], ['rgba(58,78,96,0.20)', 0.45],
                 ['rgba(58,78,96,0.08)', 0.72], ['rgba(58,78,96,0.00)', 1]]
          })
          .opacity(this.glowOpacity)
          .scale({ x: this.glowScale, y: this.glowScale })
          .translate({
            x: this.glowX - this.buttonSize() / 2,
            y: this.glowY - this.buttonSize() / 2
          })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.buttonSize())
    .height(this.buttonSize())
    .borderRadius(uiRadius(this.primary ? 27 : 22))
    // 与顶栏、底部胶囊、抽屉同一套玻璃：底透明 + 统一模糊与薄纱。
    // 主按钮吃过主题色实底，自适应主题色下会变成黑/白实心球，这里一并交给玻璃。
    .backgroundColor(this.isEnabled
      ? uiPopupEffectBackground(this.buttonColor())
      : uiMaterialBackground(themeControlMutedBackground()))
    // 和底部胶囊、顶栏同一套玻璃参数（同一薄纱浓度、同一饱和度），
    // 只把模糊半径从 64 降到 26：圆的直径才 54vp，64 会把它糊成一块纯色。
    // 反向薄纱（浅色叠暗纱）会让按钮发灰，与底栏不是同一种材质。
    .backgroundEffect(uiGlassFloatingButtonEffect())
    // 深色界面里 1px 单色描边压不住深底，改用和底部胶囊同一套切面高光（上亮下暗），
    // 浅色/深色各有一套取值，两种显示模式下都能勾出轮廓。
    // 选中态才描边。平时 1px 亮边 + 顶部渐变叠在一起，观感就是"一颗凸起的按钮"，
    // 而这里要的是浮在内容上的一层玻璃。
    // 边和底栏用同一条切面高光：玻璃本身在白底上没有对比，
    // 全靠这条 1px 的亮/暗边勾出轮廓，底栏也是这么立住的。
    .border(this.checked
      ? { width: 2, color: themeOnPrimaryText() }
      : uiDockHighlightBorder())
    // 玻璃底色透明后，浅色界面压在白卡片上只剩一圈细边，加一层随主题明暗切换的投影找轮廓：
    // 浅色用淡灰投影，深色用重投影 + 边框高光。
    // 投影收紧：radius 12 的散光和整颗圆差不多大，糊在底下像一张贴纸。
    // 收到 8、上抬 3，边缘才是“压在页面上”的接触阴影。
    .shadow({
      radius: 6,
      color: themeShadowColor(),
      offsetX: 0,
      offsetY: 2
    })
    // 光斑要裁在圆里，否则会糊到旁边的按钮上。
    .clip(true)
    .onTouch((event: TouchEvent) => {
      if (event.touches.length === 0) {
        return;
      }
      const x = event.touches[0].x;
      const y = event.touches[0].y;
      if (event.type === TouchType.Down) {
        this.glowX = x;
        this.glowY = y;
        this.glowScale = 1;
        this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
          this.glowOpacity = 0.95;
        });
      } else if (event.type === TouchType.Move) {
        this.glowX = x;
        this.glowY = y;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.getUIContext().animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
          this.glowOpacity = 0;
          this.glowScale = 1.12;
        });
      }
    })
    .scale({ x: this.active ? 0.92 : 1, y: this.active ? 0.92 : 1 })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(() => {
      if (this.directTap && this.isEnabled) {
        this.onTapAction();
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buttonBubble()
      if ((this.active || this.showLabel) && this.label.length > 0) {
        Row() {
          this.labelBubble()
        }
        .width(214)
        .height(this.buttonSize())
        .position({ x: this.isLeftSide() ? this.buttonSize() + 8 : -222, y: 0 })
        .alignItems(VerticalAlign.Center)
        .justifyContent(this.isLeftSide() ? FlexAlign.Start : FlexAlign.End)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width(this.buttonSize())
    .height(this.buttonSize())
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@Component
export struct SearchModeSegmentButton {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onSelect: () => void = () => {};

  build() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Text(uiText(this.label))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selected ? themeAccentTextColor() : themeSecondaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .height(uiTabHeight())
    .layoutWeight(1)
    .padding({ left: 4, right: 4 })
    .backgroundColor(uiCapsuleButtonBackground(this.selected))
    .animation({ duration: 180, curve: Curve.EaseInOut })
    .borderRadius(uiPillRadius(uiTabHeight() / 2))
    .onClick(() => {
      this.onSelect();
    })
  }
}

@Component
export struct SearchFlagChip {
  label: string = '';
  @Prop isOn: boolean = false;
  @Prop isEnabled: boolean = true;
  onToggle: (isOn: boolean) => void = (_isOn: boolean) => {};

  build() {
    Button(uiText(this.label), { type: ButtonType.Capsule, stateEffect: true })
      .height(34)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isOn ? themeAccentTextColor() :
        (this.isEnabled ? themeSecondaryText() : themeInactiveActionText()))
      .backgroundColor(uiCapsuleButtonBackground(this.isOn))
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .opacity(this.isEnabled ? 1 : 0.72)
      .enabled(this.isEnabled)
      .layoutWeight(1)
      .borderRadius(uiPillRadius(17))
      .onClick(() => {
        this.onToggle(!this.isOn);
      })
  }
}

@Component
export struct SearchCategoryChip {
  @Prop label: string = '';
  @Prop category: number = GalleryCategory.Unknown;
  @Prop selected: boolean = false;
  onToggle: (category: number) => void = (_category: number) => {};

  private selectedColor(): string {
    switch (this.category) {
      case GalleryCategory.Doujinshi:
        return '#F0D0A8';
      case GalleryCategory.Manga:
        return '#D8CDF1';
      case GalleryCategory.ArtistCg:
        return '#C8E1EA';
      case GalleryCategory.GameCg:
        return '#E1CEAA';
      case GalleryCategory.ImageSet:
        return '#C5E1D1';
      case GalleryCategory.Cosplay:
        return '#E8C4D1';
      case GalleryCategory.AsianPorn:
        return '#E1C9B5';
      case GalleryCategory.NonH:
        return '#CBDDEA';
      case GalleryCategory.Western:
        return '#D1DCBE';
      case GalleryCategory.Misc:
        return '#D6D9DE';
      default:
        return themeSurfaceVariant();
    }
  }

  private categoryChipBackground(): string {
    const accent = categoryColor(this.category);
    if (this.selected) {
      return accent;
    }
    return isDarkTheme() ? '#52' + accent.substring(1) : this.selectedColor();
  }

  private categoryChipForeground(): string {
    if (this.selected) {
      return '#FFFFFF';
    }
    return isDarkTheme() ? this.selectedColor() : categoryColor(this.category);
  }

  build() {
    Button(this.label, { type: ButtonType.Capsule, stateEffect: true })
      .height(34)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.categoryChipForeground())
      .backgroundColor(this.categoryChipBackground())
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .layoutWeight(1)
      .borderRadius(uiPillRadius(17))
      .onClick(() => {
        this.onToggle(this.category);
      })
  }
}

@Component
export struct RatingStarBar {
  @Prop level: number = 1;
  onSelect: (level: number) => void = (_level: number) => {};

  private starActive(index: number): boolean {
    return index <= this.level;
  }

  private labelText(): string {
    return this.level <= 1 ? 'No rating limit' : this.level.toString() + ' stars and up';
  }
  build() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        ForEach([1, 2, 3, 4, 5], (index: number) => {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.starActive(index) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
              .fontSize(22)
              .fontColor([uiMaterialForegroundColor(this.starActive(index) ? '#D28A1E' : '#9AA8B4')])
          }
          .width(36)
          .height(36)
          .backgroundColor(uiMaterialBackground(this.starActive(index) ? '#6E521F' : themeSurfaceVariant()))
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.onSelect(index);
          })
        }, (index: number) => index.toString())
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      Text(uiText(this.labelText()))
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
