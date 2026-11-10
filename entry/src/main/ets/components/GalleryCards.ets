import { image } from '@kit.ImageKit';
import { GalleryCategory, GalleryInfo, GallerySite } from '../model/GalleryModels';
import { DecodedGalleryThumbnail, GalleryThumbnailLease } from '../services/GalleryThumbnailDecodeCache';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { GALLERY_STATUS_REVISION_KEY, galleryStatusStore } from '../services/GalleryStatusStore';
import { remoteStorageDownloadDeletionService } from '../services/RemoteStorageDownloadDeletionService';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import {
  acquireThumbnailImage,
  categoryColor,
  categoryDisplayName,
  createEmptyGallery,
  galleryDetailCardBaseHeight,
  galleryDetailCardHeight,
  galleryDetailCardThumbWidth,
  gallerySimpleLanguage,
  galleryDisplayTitle,
  galleryListMode,
  currentGallerySite,
  GALLERY_TITLE_REVISION_KEY,
  HISTORY_READ_REVISION_KEY,
  LANGUAGE_REVISION_KEY,
  readerLocalImageSource,
  showGalleryLanguage,
  showGalleryPages,
  showGalleryRating,
  shouldShowTagTranslations,
  uiText,
  getAbilityContext
} from '../shared/AppRuntime';
import {
  themeDividerColor,
  themeDownloadStateActiveColor,
  themeDangerBackground,
  themeFavoriteText,
  themeOnPrimaryText,
  themePlaceholderColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedIndicatorColor,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/AppPalette';
import {
  uiCardRadius,
  uiControlRadius,
  uiListItemBackground,
  uiListItemBorderColor,
  uiListItemSelectedBackground
} from '../shared/AppSurfaceStyle';
import { TranslationText } from './TranslationComponents';

const GALLERY_THUMB_ASPECT_RATIO_CACHE: Map<string, number> = new Map<string, number>();

interface GalleryImageCompleteEvent {
  width: number;
  height: number;
  componentWidth: number;
  componentHeight: number;
  loadingStatus: number;
}

export function normalizedThumbnailAspectRatio(width: number, height: number): number {
  if (width <= 0 || height <= 0) {
    return 0.75;
  }
  const ratio = width / height;
  if (Number.isNaN(ratio) || ratio <= 0) {
    return 0.75;
  }
  return Math.max(0.3, Math.min(2.5, ratio));
}

function thumbnailHost(url: string): string {
  const scheme = url.indexOf('://');
  const start = scheme >= 0 ? scheme + 3 : 0;
  let end = url.indexOf('/', start);
  if (end < 0) {
    end = url.length;
  }
  const authority = url.substring(start, end).toLowerCase();
  const port = authority.indexOf(':');
  return port >= 0 ? authority.substring(0, port) : authority;
}

function thumbnailRequiresExHentai(url: string): boolean {
  const host = thumbnailHost(url);
  return host === 'exhentai.org' || host.endsWith('.exhentai.org');
}

let galleryListScrolling: boolean = false;
let galleryScrollSettleTimer: number = -1;

// 列表滚动期间冻结卡片比例修正，避免图片加载完成后在滚动中改高度引起网格抖动。
export function markGalleryListScrolling(): void {
  galleryListScrolling = true;
  if (galleryScrollSettleTimer >= 0) {
    clearTimeout(galleryScrollSettleTimer);
  }
  galleryScrollSettleTimer = setTimeout(() => {
    galleryScrollSettleTimer = -1;
    galleryListScrolling = false;
  }, 180) as number;
}

export function rememberGalleryThumbAspectRatio(url: string, aspectRatio: number): void {
  if (url.length > 0 && aspectRatio > 0) {
    GALLERY_THUMB_ASPECT_RATIO_CACHE.set(url, aspectRatio);
  }
}

export function galleryThumbnailAspectRatio(gallery: GalleryInfo): number {
  if (gallery.thumbWidth > 0 && gallery.thumbHeight > 0) {
    return normalizedThumbnailAspectRatio(gallery.thumbWidth, gallery.thumbHeight);
  }
  const thumbnailUrl = gallery.thumb === undefined ? '' : gallery.thumb;
  const cachedRatio = GALLERY_THUMB_ASPECT_RATIO_CACHE.get(thumbnailUrl);
  if (cachedRatio !== undefined) {
    return cachedRatio;
  }
  return 0.75;
}

@Component
@Reusable
export struct GalleryListRow {
  @Prop gallery: GalleryInfo = createEmptyGallery();

  // 复用节点时必须接收新的数据。缺这个方法时，列表删除一条后
  // 后续卡片会沿用上一条的缩略图与标题，表现为「图和实际图册不匹配」。
  aboutToReuse(params: Record<string, Object>): void {
    const next = params.gallery;
    if (next !== undefined) {
      this.gallery = next as GalleryInfo;
    }
    // 回调不是状态变量，复用池取出的节点会**保留上一次绑定的闭包**。
    // 只重设 gallery 时，显示的标题是对的、点下去执行的却是该节点上次承载的条目，
    // 表现为「随机货不对板」。这类数据必须自己在 aboutToReuse 里从 params 重设。
    const reader = params.onOpenReader;
    if (reader !== undefined) {
      this.onOpenReader = reader as (gallery: GalleryInfo) => void;
    }
    const detail = params.onOpenDetail;
    if (detail !== undefined) {
      this.onOpenDetail = detail as (gallery: GalleryInfo) => void;
    }
    const longPress = params.onLongPress;
    if (longPress !== undefined) {
      this.onLongPress = longPress as (gallery: GalleryInfo) => void;
    }
    // 角标与进度也一并重设，避免复用后还挂着上一条的状态。
    this.selected = params.selected === true;
    this.translateTitle = params.translateTitle === true;
    const priority = params.translationPriority;
    if (typeof priority === 'number') {
      this.translationPriority = priority;
    }
    this.localOnly = params.localOnly === true;
    this.cloudOnly = params.cloudOnly === true;
    this.cloudGone = params.cloudGone === true;
    const progress = params.progressLabel;
    if (progress !== undefined) {
      this.progressLabel = progress as string;
    }
  }
  @Prop selected: boolean = false;
  @Prop translateTitle: boolean = false;
  @Prop translationPriority: number = 2;
  @Prop localOnly: boolean = false;
  // 云端记录但本机没有文件：蓝云=云端仍在，红云=云端已删除。
  @Prop cloudOnly: boolean = false;
  @Prop cloudGone: boolean = false;
  // 下载列表用它把“阅读进度”换成“下载进度/已下载”。
  @Prop progressLabel: string = '';
  onLongPress: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onOpenReader: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onOpenDetail: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  @StorageProp(HISTORY_READ_REVISION_KEY) historyReadRevision: number = 0;
  @StorageProp(GALLERY_TITLE_REVISION_KEY) galleryTitleRevision: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State pressed: boolean = false;

  private cardHeight(): number {
    return galleryDetailCardHeight();
  }

  private detailAreaHeight(): number {
    return galleryDetailCardBaseHeight();
  }

  private cardGap(): number {
    return this.isLooseLayout() ? 8 : 6;
  }

  private metaGap(): number {
    return this.isLooseLayout() ? 6 : 3;
  }

  private titleMaxLines(): number {
    if (this.isSmallThumb()) {
      return 2;
    }
    return this.isLooseLayout() ? 3 : 2;
  }

  private titleLineHeight(): number {
    if (this.isSmallThumb()) {
      return 17;
    }
    return this.isLooseLayout() ? 21 : 20;
  }

  private titleHeight(): number {
    return this.titleLineHeight() * this.titleMaxLines();
  }

  private isSmallThumb(): boolean {
    return galleryDetailCardThumbWidth() <= 70 || this.detailAreaHeight() <= 100;
  }

  private isLooseLayout(): boolean {
    return galleryDetailCardThumbWidth() >= 104;
  }

  private cardThumbWidth(): number {
    return galleryDetailCardThumbWidth();
  }

  private titleFontSize(): number {
    if (this.isSmallThumb()) {
      return 13;
    }
    return this.isLooseLayout() ? 16 : 15;
  }

  private uploaderFontSize(): number {
    if (this.isSmallThumb()) {
      return 11;
    }
    return this.isLooseLayout() ? 14 : 12;
  }

  private metaFontSize(): number {
    if (this.isSmallThumb()) {
      return 11;
    }
    return this.isLooseLayout() ? 14 : 13;
  }

  private metaLineHeight(): number {
    if (this.isSmallThumb()) {
      return 15;
    }
    return this.isLooseLayout() ? 20 : 18;
  }

  private ratingHeight(): number {
    if (this.isSmallThumb()) {
      return 14;
    }
    return this.isLooseLayout() ? 18 : 16;
  }

  private ratingWidth(): number {
    if (this.isSmallThumb()) {
      return 64;
    }
    return this.isLooseLayout() ? 88 : 72;
  }

  private categoryFontSize(): number {
    if (this.isSmallThumb()) {
      return 12;
    }
    return this.isLooseLayout() ? 14 : 13;
  }

  private categoryHeight(): number {
    if (this.isSmallThumb()) {
      return 21;
    }
    return this.isLooseLayout() ? 25 : 23;
  }

  private tagFontSize(): number {
    return this.isLooseLayout() ? 14 : 12;
  }

  private tagRowHeight(): number {
    return this.isLooseLayout() ? 25 : 21;
  }

  private isExtendedMode(): boolean {
    return galleryListMode() === 'Extended';
  }

  private previewTags(): string[] {
    const tags: string[] = [];
    if (this.gallery.simpleTags !== undefined) {
      for (let i = 0; i < this.gallery.simpleTags.length && tags.length < 8; i++) {
        this.appendPreviewTag(tags, this.gallery.simpleTags[i]);
      }
    }
    if (this.gallery.tagList !== undefined) {
      for (let i = 0; i < this.gallery.tagList.length && tags.length < 8; i++) {
        this.appendPreviewTag(tags, this.gallery.tagList[i]);
      }
    }
    if (this.gallery.detailTags !== undefined) {
      for (let i = 0; i < this.gallery.detailTags.length && tags.length < 8; i++) {
        const group = this.gallery.detailTags[i];
        for (let j = 0; j < group.tags.length && tags.length < 8; j++) {
          const value = group.namespace.length > 0 ? group.namespace + ':' + group.tags[j] : group.tags[j];
          this.appendPreviewTag(tags, value);
        }
      }
    }
    return tags;
  }

  private appendPreviewTag(tags: string[], value: string): void {
    const normalized = value.trim().toLowerCase();
    if (normalized.length === 0 || normalized.indexOf('language:') === 0) {
      return;
    }
    for (let i = 0; i < tags.length; i++) {
      if (tags[i].trim().toLowerCase() === normalized) {
        return;
      }
    }
    tags.push(value.trim());
  }

  private readPageText(): string {
    if (this.progressLabel.length > 0) {
      return this.progressLabel;
    }
    if (this.historyReadRevision < 0) {
      return '';
    }
    if (this.gallery.pages <= 0) {
      return '';
    }
    const readIndex = ehHistoryStore.getReadPage(this.gallery.gid);
    if (readIndex > 0) {
      const readPages = Math.min(this.gallery.pages, readIndex + 1);
      return readPages.toString() + '/' + this.gallery.pages.toString() + ' P';
    }
    // 没读过就只报总页数，不写 “0/44 P” 这种看着像进度的东西。
    return this.gallery.pages.toString() + ' P';
  }

  private showReadPageText(): boolean {
    if (this.progressLabel.length > 0) {
      return true;
    }
    // 页数是列表的基础信息，和安卓版一致，默认就显示，不再挂在设置项后面。
    return this.gallery.pages > 0;
  }

  private languageText(): string {
    const language = gallerySimpleLanguage(this.gallery);
    if (language.length > 0) {
      return language;
    }
    // 纯本地图册没有服务器语言标记，写 "-" 会让人以为是页数缺失，直接标“本地”。
    return this.localOnly ? uiText('Local') : '-';
  }

  private tagColor(index: number): string {
    const colors: string[] = ['#D8EEF7', '#E6E0F4', '#DDEFD9', '#F7E3C7', '#F6DDE7', '#DDE7F5'];
    return colors[index % colors.length];
  }

  private tagTextColor(index: number): string {
    const colors: string[] = ['#205E78', '#594596', '#2F6841', '#8A5A1F', '#8A3858', '#3A567D'];
    return colors[index % colors.length];
  }

  private tagDisplayText(tag: string): string {
    const colon = tag.indexOf(':');
    const namespace = colon > 0 ? tag.substring(0, colon).trim() : '';
    const value = colon >= 0 && colon < tag.length - 1 ? tag.substring(colon + 1).trim() : tag.trim();
    if (shouldShowTagTranslations()) {
      const translated = ehTagTranslationStore.translate(namespace, value);
      if (translated.length > 0) {
        return translated;
      }
    }
    return value;
  }

  @Builder
  private detailMetadata() {
    // 对齐安卓版：作者一行；下面左右两列——左边评分/分类，右边页数/时间。
    Column({ space: this.metaGap() }) {
      Text(this.gallery.uploader === undefined || this.gallery.uploader.length === 0 ?
        uiText('unknown uploader') : this.gallery.uploader)
        .fontSize(this.uploaderFontSize())
        .fontColor(themeSecondaryText())
        .lineHeight(this.metaLineHeight())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 6 }) {
        // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
        GalleryRatingStars({
          rating: this.gallery.rating,
          widthValue: this.ratingWidth(),
          heightValue: this.ratingHeight()
        })
        Blank()
        Text(this.languageText())
          .fontSize(this.metaFontSize())
          .fontColor(themeSecondaryText())
          .maxLines(1)
          .flexShrink(0)
        if (this.showReadPageText()) {
          Text(this.readPageText())
            .fontSize(this.metaFontSize())
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .flexShrink(0)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
        CategoryBadge({
          category: this.gallery.category,
          fontSizeValue: this.categoryFontSize() - 1,
          heightValue: this.categoryHeight() - 2,
          horizontalPadding: this.isLooseLayout() ? 9 : 7
        })
        Blank()
        Text(this.gallery.posted === undefined ? '' : this.gallery.posted)
          .fontSize(this.metaFontSize() - 1)
          .fontColor(themeTertiaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private detailArea() {
    Row() {
      Stack({ alignContent: Alignment.BottomStart }) {
        // GalleryThumb owns the async URL fallback state and cannot be a @Builder.
        // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
        GalleryThumb({
          url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
          widthValue: this.cardThumbWidth(),
          heightValue: this.detailAreaHeight(),
          radiusValue: 6
        })
          .height('100%')
        // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
        if (this.localOnly) {
          LocalOnlyBadge()
            .margin({ left: 4, bottom: 4 })
        } else if (this.cloudGone) {
          // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
          CloudStateBadge({ gone: true })
            .margin({ left: 4, bottom: 4 })
        } else if (this.cloudOnly) {
          // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
          CloudStateBadge({ gone: false })
            .margin({ left: 4, bottom: 4 })
        } else {
          // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
          GalleryStatusBadges({ gallery: this.gallery })
            .margin({ left: 4, bottom: 4 })
        }
      }
      .width(this.cardThumbWidth())
      .height('100%')
      .onClick(() => {
        this.onOpenReader(this.gallery);
      })

      Column({ space: 4 }) {
        Column() {
          // TranslationText is a shared component with its own async translation state.
          // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
          TranslationText({
            sourceText: galleryDisplayTitle(this.gallery),
            translationEnabled: this.translateTitle,
            translationPriority: this.translationPriority,
            fontSizeValue: this.titleFontSize(),
            fontWeightValue: FontWeight.Medium,
            fontColorValue: themePrimaryText(),
            lineHeightValue: this.titleLineHeight(),
            maxLinesValue: this.titleMaxLines()
          })
        }
        .width('100%')
        .height(this.titleHeight())
        .clip(true)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)

        this.detailMetadata()
      }
      .height('100%')
      .layoutWeight(1)
      .padding({
        left: this.isLooseLayout() ? 12 : (this.isSmallThumb() ? 8 : 10),
        right: this.isLooseLayout() ? 10 : (this.isSmallThumb() ? 6 : 8),
        top: this.isLooseLayout() ? 8 : (this.isSmallThumb() ? 5 : this.cardGap()),
        bottom: this.isLooseLayout() ? 8 : (this.isSmallThumb() ? 5 : this.cardGap())
      })
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.onOpenDetail(this.gallery);
      })
    }
    .width('100%')
    .height(this.detailAreaHeight())
  }

  @Builder
  private extendedTagArea() {
    Scroll() {
      Row({ space: this.isLooseLayout() ? 6 : 4 }) {
        ForEach(this.previewTags(), (tag: string, index: number) => {
          // GalleryTagChip is exported and reused outside the card list as well.
          // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
          GalleryTagChip({
            text: this.tagDisplayText(tag),
            backgroundColorValue: this.tagColor(index),
            color: this.tagTextColor(index),
            fontSizeValue: this.tagFontSize(),
            heightValue: this.tagRowHeight(),
            horizontalPadding: this.isLooseLayout() ? 9 : 7
          })
            .flexShrink(0)
        }, (tag: string, index: number) => tag + ':' + index.toString())
      }
      .padding({
        left: this.isLooseLayout() ? 10 : 6,
        right: this.isLooseLayout() ? 10 : 6
      })
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .padding({
      top: this.isLooseLayout() ? 6 : 4,
      bottom: this.isLooseLayout() ? 6 : 4
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.detailArea()
        if (this.isExtendedMode()) {
          this.extendedTagArea()
        }
      }
      .width('100%')
      .height('100%')

      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(24)
          .fontColor([themeSelectedIndicatorColor()])
          .margin({ top: 6, left: 6 })
      }
    }
    .width('100%')
    .height(this.cardHeight())
    .backgroundColor(this.selected ? uiListItemSelectedBackground(themeSelectedBackground()) :
      uiListItemBackground(themeSurface()))
    .border({ width: 1, color: uiListItemBorderColor(themeDividerColor()) })
    .borderRadius(uiCardRadius(16))
    .clip(true)
    .scale({ x: this.pressed ? 0.98 : 1, y: this.pressed ? 0.98 : 1 })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress(this.gallery);
        })
    )
  }
}

@Component
export struct GalleryTagChip {
  @Prop text: string = '';
  @Prop backgroundColorValue: string = '#D8EEF7';
  @Prop color: string = '#205E78';
  @Prop fontSizeValue: number = 12;
  @Prop heightValue: number = 21;
  @Prop horizontalPadding: number = 7;

  build() {
    Text(this.text)
      .fontSize(this.fontSizeValue)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.color)
      .height(this.heightValue)
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
      .backgroundColor(this.backgroundColorValue)
      .borderRadius(uiControlRadius(3))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}

@Component
export struct GalleryThumb {
  @Prop @Watch('onUrlChange') url: string = '';
  widthValue: number = 86;
  heightValue: number = 118;
  radiusValue: number = 4;
  onImageAspectRatio: (aspectRatio: number) => void = (_aspectRatio: number) => {};

  @State thumbnailSource: string | image.PixelMap = '';
  @State loadFailed: boolean = false;
  private cachedUrl: string = '';
  private imageRetryCount: number = 0;
  private thumbnailLease: GalleryThumbnailLease | null = null;
  private thumbnailRequest: number = 0;
  private retryTimer: number = -1;
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.cacheThumb();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.releaseThumbnail();
  }

  onUrlChange(): void {
    if (this.mounted) {
      this.cacheThumb();
    }
  }

  private releaseThumbnail(): void {
    this.thumbnailRequest++;
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    this.thumbnailSource = '';
    if (this.thumbnailLease !== null) {
      this.thumbnailLease.release();
      this.thumbnailLease = null;
    }
  }

  private cacheThumb(): void {
    if (this.cachedUrl === this.url && this.thumbnailLease !== null) {
      return;
    }
    const urlChanged = this.cachedUrl !== this.url;
    this.releaseThumbnail();
    this.cachedUrl = this.url;
    if (urlChanged) {
      this.imageRetryCount = 0;
    }
    const url = this.url;
    this.loadFailed = url.length === 0;
    if (this.loadFailed) {
      return;
    }
    // 本地图档的缩略图是沙箱内的真实文件，直接交给 Image 渲染，不走网络缓存。
    if (url.startsWith('/') || url.startsWith('file://')) {
      this.thumbnailSource = readerLocalImageSource(url);
      return;
    }
    const request = this.thumbnailRequest;
    const lease = acquireThumbnailImage(url);
    this.thumbnailLease = lease;
    if (lease.ready !== null) {
      // A warmed cover can appear immediately, without a file decode or the old
      // global 48 ms per-thumbnail delivery queue.
      this.applyThumbnail(lease.ready, url, request);
      return;
    }
    lease.pending.then((result: DecodedGalleryThumbnail | null) => {
      this.applyThumbnail(result, url, request);
    });
  }

  private applyThumbnail(result: DecodedGalleryThumbnail | null, url: string, request: number): void {
    if (!this.mounted || request !== this.thumbnailRequest || url !== this.url) {
      return;
    }
    if (result === null && url.startsWith('http')) {
      // 应用网络层（缓存下载+解码）全失败：回退系统 Image 直连网络 URL。
      // 系统网络栈与应用的 DoH/hosts 选路完全独立，是最后一条没试过的路。
      this.thumbnailSource = url;
      this.networkFallbackActive = true;
      return;
    }
    this.loadFailed = result === null;
    if (result !== null) {
      this.thumbnailSource = result.pixelMap === undefined ? readerLocalImageSource(result.path) : result.pixelMap;
      // Metadata updates are deferred even on memory-cache hits, never from build.
      this.reportThumbnailAspectRatio(result.width, result.height, url, request);
    }
  }

  private reportThumbnailAspectRatio(width: number, height: number, url: string, request: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const aspectRatio = normalizedThumbnailAspectRatio(width, height);
    rememberGalleryThumbAspectRatio(url, aspectRatio);
    setTimeout(() => {
      if (this.mounted && request === this.thumbnailRequest && url === this.url) {
        this.onImageAspectRatio(aspectRatio);
      }
    }, 0);
  }

  private onThumbnailError(): void {
    const request = this.thumbnailRequest;
    if (this.networkFallbackActive) {
      // 系统直连也失败：无路可走，显示重试占位
      this.networkFallbackActive = false;
      this.loadFailed = true;
      return;
    }
    if (this.retryTimer !== -1) {
      return;
    }
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      if (!this.mounted || request !== this.thumbnailRequest) {
        return;
      }
      if (this.thumbnailLease !== null) {
        this.thumbnailLease.invalidate();
      }
      if (this.imageRetryCount < 2 && this.url.length > 0) {
        this.imageRetryCount++;
        this.releaseThumbnail();
        this.cacheThumb();
      } else {
        this.loadFailed = true;
      }
    }, 120) as number;
  }

  private networkFallbackActive: boolean = false;

  private hasSiteMismatch(): boolean {
    return thumbnailRequiresExHentai(this.url) && currentGallerySite() !== GallerySite.Ex;
  }

  private showSiteMismatchHint(): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: uiText('This cover belongs to ExHentai. Switch the gallery site to ExHentai and retry.')
      });
    } catch (error) {
    }
  }

  private handleLoadErrorTap(): void {
    if (this.hasSiteMismatch()) {
      this.showSiteMismatchHint();
      return;
    }
    if (this.url.length > 0) {
      this.imageRetryCount = 0;
      if (this.thumbnailLease !== null) {
        this.thumbnailLease.invalidate();
      }
      this.releaseThumbnail();
      this.cacheThumb();
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeSurfaceVariant())
        .borderRadius(uiControlRadius(this.radiusValue))

      if (this.loadFailed) {
        Column({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(22)
            .fontColor([themePlaceholderColor()])
          Text(uiText(this.hasSiteMismatch() ? 'Switch site' : 'Retry'))
            .fontSize(9)
            .fontColor(themePlaceholderColor())
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 3, right: 3 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.handleLoadErrorTap();
        })
      } else if (this.thumbnailSource !== '') {
        Image(this.thumbnailSource)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          // Static covers already hold decoded pixels; format/animation fallbacks
          // must also avoid synchronous decoding in the scrolling layout pass.
          .syncLoad(false)
          .borderRadius(uiControlRadius(this.radiusValue))
          .onComplete((event?: GalleryImageCompleteEvent) => {
            if (event !== undefined && event.loadingStatus === 0) {
              this.reportThumbnailAspectRatio(event.width, event.height, this.url, this.thumbnailRequest);
            }
          })
          .onError(() => this.onThumbnailError())
      } else {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(themePlaceholderColor())
      }
    }
    .width(this.widthValue > 0 ? this.widthValue : '100%')
    .height(this.heightValue > 0 ? this.heightValue : '100%')
  }
}

@Component
@Reusable
export struct GalleryThumbCard {
  @Prop @Watch('onGalleryChange') gallery: GalleryInfo = createEmptyGallery();

  // 同 GalleryListRow：复用后必须换数据并重算宽高比，否则缩略图会串到下一条。
  aboutToReuse(params: Record<string, Object>): void {
    const next = params.gallery;
    if (next !== undefined) {
      this.gallery = next as GalleryInfo;
    }
    // 同上：回调不走状态机制，必须显式重设，否则点击落到该节点上一次的条目上。
    const reader = params.onOpenReader;
    if (reader !== undefined) {
      this.onOpenReader = reader as (gallery: GalleryInfo) => void;
    }
    const detail = params.onOpenDetail;
    if (detail !== undefined) {
      this.onOpenDetail = detail as (gallery: GalleryInfo) => void;
    }
    const longPress = params.onLongPress;
    if (longPress !== undefined) {
      this.onLongPress = longPress as (gallery: GalleryInfo) => void;
    }
    this.selected = params.selected === true;
    this.translateTitle = params.translateTitle === true;
    const priority = params.translationPriority;
    if (typeof priority === 'number') {
      this.translationPriority = priority;
    }
    this.localOnly = params.localOnly === true;
    this.cloudOnly = params.cloudOnly === true;
    this.cloudGone = params.cloudGone === true;
    this.syncThumbnailAspectRatio();
  }
  @Prop selected: boolean = false;
  @Prop translateTitle: boolean = false;
  @Prop translationPriority: number = 2;
  @Prop localOnly: boolean = false;
  // 云端记录但本机没有文件：蓝云=云端仍在，红云=云端已删除。
  @Prop cloudOnly: boolean = false;
  @Prop cloudGone: boolean = false;
  onLongPress: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onOpenReader: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onOpenDetail: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  @StorageProp(HISTORY_READ_REVISION_KEY) historyReadRevision: number = 0;
  @StorageProp(GALLERY_TITLE_REVISION_KEY) galleryTitleRevision: number = 0;
  @State resolvedThumbnailAspectRatio: number = 0.75;
  @State pressed: boolean = false;

  aboutToAppear(): void {
    this.syncThumbnailAspectRatio();
  }

  onGalleryChange(): void {
    this.syncThumbnailAspectRatio();
  }

  private syncThumbnailAspectRatio(): void {
    this.resolvedThumbnailAspectRatio = galleryThumbnailAspectRatio(this.gallery);
  }

  private updateThumbnailAspectRatio(aspectRatio: number): void {
    rememberGalleryThumbAspectRatio(this.gallery.thumb === undefined ? '' : this.gallery.thumb, aspectRatio);
    if (galleryListScrolling) {
      return;
    }
    if (this.gallery.thumbWidth > 0 && this.gallery.thumbHeight > 0) {
      return;
    }
    if (Math.abs(this.resolvedThumbnailAspectRatio - aspectRatio) < 0.001) {
      return;
    }
    this.resolvedThumbnailAspectRatio = aspectRatio;
  }

  private readPageText(): string {
    if (this.historyReadRevision < 0) {
      return '';
    }
    if (this.gallery.pages <= 0) {
      return '';
    }
    const readIndex = ehHistoryStore.getReadPage(this.gallery.gid);
    const readPages = readIndex >= 0 ? Math.min(this.gallery.pages, readIndex + 1) : 0;
    return readPages.toString() + '/' + this.gallery.pages.toString() + ' P';
  }

  private showReadPageText(): boolean {
    return showGalleryPages() && this.gallery.pages > 0;
  }

  private languageText(): string {
    const language = gallerySimpleLanguage(this.gallery);
    if (language.length > 0) {
      return language;
    }
    // 纯本地图册没有服务器语言标记，写 "-" 会让人以为是页数缺失，直接标“本地”。
    return this.localOnly ? uiText('Local') : '-';
  }

  @Builder
  private thumbnailRightMetadata() {
    Column({ space: 6 }) {
      if (showGalleryLanguage() && showGalleryRating() && this.showReadPageText()) {
        Text(this.languageText())
          .fontSize(14)
          .lineHeight(18)
          .fontColor(themeTertiaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.showReadPageText()) {
        Row({ space: 6 }) {
          if (showGalleryLanguage() && !showGalleryRating()) {
            Text(this.languageText())
              .fontSize(14)
              .lineHeight(18)
              .fontColor(themeTertiaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(this.readPageText())
            .fontSize(14)
            .lineHeight(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(themeTertiaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      } else if (showGalleryLanguage()) {
        Text(this.languageText())
          .fontSize(14)
          .lineHeight(18)
          .fontColor(themeTertiaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.End)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Stack({ alignContent: Alignment.BottomStart }) {
          // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
          GalleryThumb({
            url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
            widthValue: 0,
            heightValue: 0,
            onImageAspectRatio: (aspectRatio: number) => {
              this.updateThumbnailAspectRatio(aspectRatio);
            }
          })
            .width('100%')
            .height('100%')
          if (this.localOnly) {
            LocalOnlyBadge()
              .margin({ left: 4, bottom: 4 })
          } else if (this.cloudGone) {
            CloudStateBadge({ gone: true })
              .margin({ left: 4, bottom: 4 })
          } else if (this.cloudOnly) {
            CloudStateBadge({ gone: false })
              .margin({ left: 4, bottom: 4 })
          } else {
            // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
            GalleryStatusBadges({ gallery: this.gallery })
              .margin({ left: 4, bottom: 4 })
          }
        }
        .width('100%')
        .aspectRatio(this.resolvedThumbnailAspectRatio)
        .onClick(() => {
          this.onOpenReader(this.gallery);
        })

        Column() {
          Column() {
            // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
            TranslationText({
              sourceText: galleryDisplayTitle(this.gallery),
              translationEnabled: this.translateTitle,
              translationPriority: this.translationPriority,
              fontSizeValue: 15,
              lineHeightValue: 19,
              fontWeightValue: FontWeight.Medium,
              fontColorValue: themePrimaryText(),
              maxLinesValue: 5
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)

          Row() {
            Column({ space: 6 }) {
              if (showGalleryRating()) {
                // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
                GalleryRatingStars({ rating: this.gallery.rating, widthValue: 86, heightValue: 16 })
              }
              // eslint-disable-next-line @performance/hp-arkui-replace-nested-reusable-component-by-builder
              CategoryBadge({ category: this.gallery.category })
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            this.thumbnailRightMetadata()
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .margin({ top: 6 })
        }
        .padding({ left: 8, right: 8, top: 7, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.onOpenDetail(this.gallery);
        })
      }

      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(24)
          .fontColor([themeSelectedIndicatorColor()])
          .margin({ top: 6, left: 6 })
      }
    }
    .backgroundColor(this.selected ? uiListItemSelectedBackground(themeSelectedBackground()) :
      uiListItemBackground(themeSurface()))
    .border({ width: 1, color: uiListItemBorderColor(themeDividerColor()) })
    .borderRadius(uiCardRadius(16))
    .clip(true)
    .scale({ x: this.pressed ? 0.97 : 1, y: this.pressed ? 0.97 : 1 })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress(this.gallery);
        })
    )
  }
}

@Component
struct GalleryStatusBadges {
  @Prop gallery: GalleryInfo = createEmptyGallery();
  @StorageProp(GALLERY_STATUS_REVISION_KEY) statusRevision: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private hasDownload(): boolean {
    return this.statusRevision >= 0 && galleryStatusStore.hasDownload(this.gallery.gid);
  }

  private isCloudOnly(): boolean {
    if (this.statusRevision < 0 || !this.hasDownload()) {
      return false;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return false;
    }
    return !remoteStorageDownloadDeletionService.hasLocalCopy(context, this.gallery.gid);
  }

  private isFavorite(): boolean {
    return this.statusRevision >= 0 && galleryStatusStore.isFavorite(this.gallery);
  }

  build() {
    Row({ space: 3 }) {
      if (this.hasDownload()) {
        // 角标语义固定三档，不允许再用「下箭头」冒充云端：
        // 本地有文件=手机图标，仅云端记录=云朵，记录与文件都缺=云朵加斜线。
        if (this.isCloudOnly()) {
          CloudStateBadge({ gone: false })
        } else {
          LocalOnlyBadge()
        }
      }
      if (this.isFavorite()) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.heart_fill'))
            .fontSize(14)
            .fontColor([themeOnPrimaryText()])
        }
        .width(22)
        .height(22)
        .backgroundColor(themeFavoriteText())
        .borderRadius(11)
        .accessibilityText(uiText('Favorited'))
      }
    }
    .hitTestBehavior(HitTestMode.None)
  }
}

// 云端状态角标：蓝底=云端仍在（仅云端可读），红底=DB 有记录但云端已删除、本地也没有。
@Component
struct CloudStateBadge {
  gone: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.cloud'))
        .fontSize(15)
        .fontColor([themeOnPrimaryText()])
      if (this.gone) {
        // 斜线：云端记录在，但本地与云端都取不到内容。
        Row()
          .width(16)
          .height(2)
          .backgroundColor(themeOnPrimaryText())
          .rotate({ angle: -45 })
      }
    }
    .width(22)
    .height(22)
    .backgroundColor(this.gone ? themeDangerBackground() : themeDownloadStateActiveColor())
    .borderRadius(11)
    .accessibilityText(this.gone ? uiText('Cloud record removed') : uiText('Cloud only'))
  }
}

@Component
struct LocalOnlyBadge {
  build() {
    // 手机图形（竖长机身 + 底部横条），与云端角标同一套蓝底白图形。
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.ic_local_phone'))
        .width(13)
        .height(13)
        .fillColor(themeOnPrimaryText())
        .objectFit(ImageFit.Contain)
    }
    .width(22)
    .height(22)
    .backgroundColor(themeDownloadStateActiveColor())
    .borderRadius(11)
    .clip(true)
    .accessibilityText(uiText('Local'))
  }
}

@Component
struct GalleryRatingStars {
  @Prop rating: number = 0;
  @Prop widthValue: number = 86;
  @Prop heightValue: number = 16;

  private filledWidth(): number {
    const normalized = Number.isNaN(this.rating) ? 0 : Math.max(0, Math.min(5, this.rating));
    return this.widthValue * normalized / 5;
  }

  @Builder
  private starRow(filled: boolean) {
    Row({ space: 0 }) {
      ForEach([0, 1, 2, 3, 4], (_index: number) => {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(this.heightValue)
          .fontColor([filled ? '#F4C43F' : '#B8BEC6'])
          .width(this.widthValue / 5)
          .height(this.heightValue)
      }, (index: number) => index.toString())
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .flexShrink(0)
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      this.starRow(false)
      Row() {
        this.starRow(true)
      }
      .width(this.filledWidth())
      .height(this.heightValue)
      .clip(true)
      .alignItems(VerticalAlign.Center)
    }
    .width(this.widthValue)
    .height(this.heightValue)
  }
}

@Component
export struct CategoryBadge {
  @Prop category: number = GalleryCategory.Unknown;
  @Prop fontSizeValue: number = 14;
  @Prop heightValue: number = 24;
  @Prop horizontalPadding: number = 8;

  build() {
    Text(categoryDisplayName(this.category))
      .fontSize(this.fontSizeValue)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .height(this.heightValue)
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding, top: 2, bottom: 2 })
      .backgroundColor(categoryColor(this.category))
      .borderRadius(uiControlRadius(3))
  }
}

// WaterFlow cell keeps the first-row top inset as reactive props so a resolution
// change re-applies the toolbar placeholder margin to every column that moved
// into the first row (reused FlowItems keep stale margins otherwise).
@Component
export struct GalleryWaterFlowCell {
  @Prop gallery: GalleryInfo = createEmptyGallery();
  @Prop index: number = 0;
  @Prop columnCount: number = 1;
  @Prop topSpacing: number = 0;
  @Prop translateTitle: boolean = false;
  @Prop translationPriority: number = 2;
  onLongPress: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onSelect: (gallery: GalleryInfo, event?: ClickEvent) => void =
    (_gallery: GalleryInfo, _event?: ClickEvent) => {
    };
  onAreaObserved: (gallery: GalleryInfo, area: Area) => void =
    (_gallery: GalleryInfo, _area: Area) => {
    };

  @State pressed: boolean = false;

  build() {
    FlowItem() {
      GalleryThumbCard({
        gallery: this.gallery,
        translateTitle: this.translateTitle,
        translationPriority: this.translationPriority,
        onLongPress: (pressed: GalleryInfo) => {
          this.onLongPress(pressed);
        }
      })
        .width('100%')
        .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
        .animation({ duration: 160, curve: Curve.EaseOut })
        .onClick((event?: ClickEvent) => {
          this.onSelect(this.gallery, event);
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressed = false;
          }
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.onAreaObserved(this.gallery, newArea);
        })
    }
    .width('100%')
    .margin({ top: this.index < this.columnCount ? this.topSpacing : 0 })
    .reuseId('gallery-thumb-flow-item')
    .animation({ duration: 220, curve: Curve.EaseOut })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }
}
