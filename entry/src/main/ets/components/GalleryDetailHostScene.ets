import { ehCookieStore } from '../services/EhCookieStore';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { ArchiveOption, ArchiverInfo, ArchiverOption, GalleryComment, GalleryDetail, GalleryPreview, GallerySite, HathArchiveList, TorrentInfo } from '../model/GalleryModels';
import { confirmCellularNetworkWarningForSession, shouldConfirmCellularNetworkOperation } from '../services/CellularNetworkGuard';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import { FILTER_MODE_TAG, ehFilterStore } from '../services/EhFilterStore';
import { ehMyTagsService } from '../services/EhMyTagsService';
import {
  ArchiverDownloadResult,
  ArchiverLoadResult,
  EhHttpClient,
  GalleryDetailLoadResult,
  HathArchiveListLoadResult,
  HathArchiveSubmitResult,
  RateGalleryResult,
  ToggleFavoriteResult,
  TorrentListLoadResult,
  VoteCommentResult,
  VoteTagResult
} from '../services/EhHttpClient';
import { PublicDownloadStartResult, startPublicDownload } from '../services/PublicDownloadService';
import { EhUrl } from '../services/EhUrl';
import { extractInfoHash } from '../services/TorrentInfoHash';
import { CommentPostResult, COMMENT_POST_UNCONFIRMED } from '../services/GalleryCommentSubmission';
import { FavoriteCategoryInfo } from '../services/GalleryListParser';
import { FavoriteSlotOption, favoriteSlotOptions } from '../services/FavoriteCollectionSupport';
import {
  archiveUnavailableReason,
  createCategorySearchRequest,
  createCoverSearchRequest,
  createSimilarGallerySearch,
  createTagSearchRequest,
  createUploaderSearchRequest,
  DetailSearchRequest,
  detailArchiveReferer
} from '../services/GalleryDetailSupport';
import {
  createDownloadReaderSessionState,
  detailDownloadButtonText,
  DetailDownloadToggleResult,
  findDetailDownloadItem,
  refreshDetailDownloadItem,
  toggleDetailDownloadTask
} from '../services/GalleryDetailSupport';
import {
  createEmptyGalleryDetailLink,
  createGalleryDetailLinkFromUrl,
  GalleryDetailLink,
  GalleryDetailModuleLoadResult,
  initialDetailForLink,
  loadGalleryDetailModule
} from '../services/GalleryDetailSupport';
import { DetailPreviewPager, loadGalleryPreviewPage, mergeGalleryPreviewSets, seedPreviewMap } from '../services/GalleryPreviewLoader';
import { createCoverSearchSource } from '../services/CoverSearchSupport';
import { AsyncRequestGate } from '../services/HttpRequestLifecycle';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { isDetailCloudOnlyDownload } from '../services/GalleryDetailSupport';
import { remoteStorageSyncService } from '../services/RemoteStorageSyncService';
import {
  DEFAULT_FAVORITE_SLOT_ASK,
  DEFAULT_FAVORITE_SLOT_SETTING_KEY,
  defaultFavoriteSlotSettingValue,
  appSettingsStore,
  parseDefaultFavoriteSlot
} from '../services/AppSettingsStore';
import {
  cloneGalleryDetail,
  cloneGalleryPreviews,
  categoryName,
  createEmptyDetail,
  createEmptyPage,
  defaultDownloadLabelChoice,
  galleryDisplayTitle,
  getAbilityContext,
  pushDetailBackHandler,
  readerStartIndex,
  readerStartIndexAsync,
  saveGalleryToHistory,
  saveDefaultDownloadLabelChoice,
  uiStatusText,
  uiText
} from '../shared/AppRuntime';
import {
  themeDividerColor,
  themeFieldBackground,
  themeAccentTextColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurfaceVariant
} from '../shared/AppPalette';
import {
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialForegroundColor,
  uiRadius,
  uiMaterialBackground
} from '../shared/AppSurfaceStyle';
import { PopupScrim } from './PopupScrim';
import { GalleryDetailOverlayScene } from './GalleryDetailScenes';
import {
  DOWNLOAD_LABEL_OPTION_ASK,
  DownloadLabelSelectionDialog
} from './DownloadLabelComponents';

interface DetailHostNavigationState {
  showInfo: boolean;
  showComments: boolean;
  commentGalleryLink: GalleryDetailLink;
}

const detailHostNavigationCache: Map<string, DetailHostNavigationState> = new Map<string, DetailHostNavigationState>();
const FAVORITE_SLOT_ROW_HEIGHT: number = 52;
const FAVORITE_SLOT_PANEL_CHROME_HEIGHT: number = 112;
// 网络慢是常态，但详情页不能无限转圈：10 秒还没拿到就报失败并给单块重试。
const DETAIL_SECTION_TIMEOUT_MS: number = 10000;

@Component
struct AddFavoriteDialog {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @Prop remember: boolean = false;
  @Prop panelMaxHeight: number = 680;
  @Prop categories: FavoriteCategoryInfo[] = [];
  onRememberChange: (remember: boolean) => void = (_remember: boolean) => {};
  onSelect: (slot: number) => void = (_slot: number) => {};
  onClose: () => void = () => {};

  private listHeight(): number {
    const contentHeight = favoriteSlotOptions(this.categories).length * FAVORITE_SLOT_ROW_HEIGHT;
    const availableHeight = Math.max(160, this.panelMaxHeight - FAVORITE_SLOT_PANEL_CHROME_HEIGHT);
    return Math.min(contentHeight, availableHeight);
  }

  private panelHeight(): number {
    return this.listHeight() + FAVORITE_SLOT_PANEL_CHROME_HEIGHT;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: () => {
          this.onClose();
        }
      })

      Column() {
        Row() {
          Text(uiText('Add to favorites'))
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([uiMaterialForegroundColor(themePrimaryText())])
          }
          .width(40)
          .height(40)
          .backgroundColor(uiMaterialBackground(themeFieldBackground()))
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 18, right: 12 })
        .alignItems(VerticalAlign.Center)

        Divider().color(themeDividerColor()).strokeWidth(0.5)

        List() {
          ForEach(favoriteSlotOptions(this.categories), (item: FavoriteSlotOption) => {
            ListItem() {
              Row() {
                Column() {
                  SymbolGlyph(item.slot === -1 ? $r('sys.symbol.heart') : $r('sys.symbol.folder'))
                    .fontSize(21)
                    .fontColor([themeAccentTextColor()])
                }
                .width(38)
                .height(38)
                .borderRadius(uiRadius(9))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(themeSurfaceVariant())

                Text(uiText(item.label))
                  .fontSize(15)
                  .fontColor(themePrimaryText())
                  .layoutWeight(1)
                  .margin({ left: 12 })
              }
              .width('100%')
              .height(52)
              .padding({ left: 18, right: 18 })
              .onClick(() => {
                this.onSelect(item.slot);
              })
            }
          }, (item: FavoriteSlotOption) => item.slot.toString() + ':' + item.label)
        }
        .width('100%')
        .height(this.listHeight())

        Divider().color(themeDividerColor()).strokeWidth(0.5)

        Row() {
          Checkbox()
            .select(this.remember)
            .selectedColor(themeAccentTextColor())
            .onChange((value: boolean) => {
              this.onRememberChange(value);
            })

          Text(uiText('Remember favorite collection'))
            .fontSize(14)
            .fontColor(themeSecondaryText())
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .height(54)
        .padding({ left: 18, right: 18 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onRememberChange(!this.remember);
        })
      }
      .width('78%')
      .height(this.panelHeight())
      .constraintSize({ maxWidth: 360, minWidth: 280, maxHeight: this.panelMaxHeight })
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
  }
}

function detailHostCacheKey(link: GalleryDetailLink): string {
  return link.site.toString() + '|' + link.gid.toString() + '|' + link.token + '|' + link.url;
}

function cloneDetailHostLink(link: GalleryDetailLink): GalleryDetailLink {
  return {
    gid: link.gid,
    token: link.token,
    url: link.url,
    referer: link.referer,
    site: link.site,
    seed: link.seed
  };
}

function detailPreviewPageSize(detail: GalleryDetail, currentPageSize: number): number {
  if (currentPageSize > 0) {
    return currentPageSize;
  }
  if (detail.previewPages > 1 && detail.pages > 0) {
    return Math.max(1, Math.ceil(detail.pages / detail.previewPages));
  }
  return Math.max(1, detail.previewSet.length);
}

function selectPreviewPage(previews: GalleryPreview[], pageIndex: number, pageSize: number): GalleryPreview[] {
  const start = Math.max(0, pageIndex) * Math.max(1, pageSize);
  const end = start + Math.max(1, pageSize);
  const selected: GalleryPreview[] = [];
  for (let i = 0; i < previews.length; i++) {
    if (previews[i].index >= start && previews[i].index < end) {
      selected.push(previews[i]);
    }
  }
  selected.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
  return cloneGalleryPreviews(selected);
}

function mergePreviewList(current: GalleryPreview[], loaded: GalleryPreview[]): GalleryPreview[] {
  const byIndex: Map<number, GalleryPreview> = new Map();
  for (let i = 0; i < current.length; i++) {
    byIndex.set(current[i].index, current[i]);
  }
  for (let i = 0; i < loaded.length; i++) {
    byIndex.set(loaded[i].index, loaded[i]);
  }
  const merged = Array.from(byIndex.values());
  merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
  return cloneGalleryPreviews(merged);
}

@Component
export struct GalleryDetailHostScene {
  @Prop @Watch('onDetailLinkChanged') detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  listRequestUrl: string = '';
  initialDetailScrollOffset: number = 0;
  onBack: () => void = () => {};
  onShowEmbeddedReader: () => void = () => {};
  onOpenSearch: (request: DetailSearchRequest) => void = (_request: DetailSearchRequest) => {};
  onDetailLoaded: (detail: GalleryDetail) => void = (_detail: GalleryDetail) => {};
  onDetailScrollUpdate: (offset: number) => void = (_offset: number) => {};

  private client: EhHttpClient = new EhHttpClient();
  private detailRequestGate: AsyncRequestGate = new AsyncRequestGate();
  private archiveRequestGate: AsyncRequestGate = new AsyncRequestGate();
  private favoriteCategoryRequestGate: AsyncRequestGate = new AsyncRequestGate();
  private commentPostGate: AsyncRequestGate = new AsyncRequestGate();
  private tagSubscriptionGate: AsyncRequestGate = new AsyncRequestGate();
  private tagSubscriptionSaving: boolean = false;
  private detailPreviewPager: DetailPreviewPager = new DetailPreviewPager();
  private previewMap: Map<number, GalleryPreview> = new Map();
  private previewPageSize: number = 0;
  private previewJumpSerial: number = 0;
  private previewJumpLoading: boolean = false;
  private unsubscribeDownloadStore: () => void = () => {};
  private unregisterDetailBackHandler: () => void = () => {};
  private cellularWarningDialogOpen: boolean = false;
  @State renderVersion: number = 0;
  @State showInfo: boolean = false;
  @State showComments: boolean = false;
  @State commentDraft: string = '';
  @State commentPosting: boolean = false;
  @State commentPostStatus: string = '';
  @State detail: GalleryDetail = createEmptyDetail();
  @State visiblePreviews: GalleryPreview[] = [];
  @State detailLoaded: boolean = false;
  @State detailStatus: string = '';
  @State detailRequestUrl: string = '';
  // 四个分区共用一次详情请求，所以失败/超时也是共用的；分区各自只负责把失败态画出来。
  @State sectionsFailed: boolean = false;
  @State sectionsMessage: string = '';
  private sectionsTimeoutTimer: number = -1;
  @State detailDownloadText: string = 'Download';
  private cloudRestoreInFlight: boolean = false;
  @State optimisticFavorite: boolean = false;
  @State favoriteBusy: boolean = false;
  @State addFavoriteDialogVisible: boolean = false;
  @State favoriteCategories: FavoriteCategoryInfo[] = [];
  @State rememberFavoriteSlot: boolean = false;
  @State downloadLabelDialogVisible: boolean = false;
  @State downloadLabelOptions: DownloadLabel[] = [];
  @State rememberDownloadLabel: boolean = false;
  @State archivePanelVisible: boolean = false;
  @State archivePanelMode: string = '';
  @State archivePanelStatus: string = '';
  @State archiveBusy: boolean = false;
  @State archiverInfo: ArchiverInfo = { funds: '', options: [] };
  @State hathArchiveList: HathArchiveList = { formParamOr: '', options: [] };
  @State torrentList: TorrentInfo[] = [];
  @State commentGalleryLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State viewportHeight: number = 0;
  @State detailScrollResetVersion: number = 0;
  @State detailStartScrollOffset: number = 0;

  aboutToAppear(): void {
    this.detailStartScrollOffset = this.initialDetailScrollOffset;
    this.loadDetailFromLink();
    this.unregisterDetailBackHandler = pushDetailBackHandler(() => this.handleDetailSystemBack());
    this.unsubscribeDownloadStore = ehDownloadStore.subscribe((_items: DownloadInfo[]) => {
      this.refreshDetailDownloadText();
    }, () => {});
  }

  aboutToDisappear(): void {
    this.commentPostGate.begin();
    this.tagSubscriptionGate.begin();
    this.favoriteCategoryRequestGate.begin();
    this.clearSectionsTimeout();
    this.saveNavigationState();
    this.unsubscribeDownloadStore();
    this.unregisterDetailBackHandler();
  }

  private clearSectionsTimeout(): void {
    if (this.sectionsTimeoutTimer >= 0) {
      clearTimeout(this.sectionsTimeoutTimer);
      this.sectionsTimeoutTimer = -1;
    }
  }

  private startSectionsTimeout(generation: number): void {
    this.clearSectionsTimeout();
    this.sectionsFailed = false;
    this.sectionsMessage = '';
    this.sectionsTimeoutTimer = setTimeout(() => {
      this.sectionsTimeoutTimer = -1;
      if (!this.detailRequestGate.isCurrent(generation) || this.detailLoaded) {
        return;
      }
      this.sectionsFailed = true;
      this.sectionsMessage = 'Timed out after 10s';
      this.detailStatus = 'Detail request timed out';
      this.renderVersion++;
    }, DETAIL_SECTION_TIMEOUT_MS);
  }

  private markSectionsFailed(message: string): void {
    this.clearSectionsTimeout();
    this.sectionsFailed = true;
    this.sectionsMessage = message;
    this.renderVersion++;
  }

  private retryDetailSections(section: string): void {
    this.sectionsFailed = false;
    this.sectionsMessage = '';
    this.detailStatus = 'Retrying ' + section + '...';
    this.renderVersion++;
    if (section === 'previews' && this.detailLoaded) {
      // 详情主体已经拿到，只是预览页没拉到：补拉下一页，不整页重刷。
      this.loadNextDetailPreviewPage().catch(() => {});
      return;
    }
    this.loadDetailFromLink();
  }

  onPageHide(): void {
    this.saveNavigationState();
  }

  onDetailLinkChanged(): void {
    if (this.detailLink.gid <= 0 || this.detailLink.token.length === 0) {
      return;
    }
    if (this.detail.gid === this.detailLink.gid && this.detail.token === this.detailLink.token) {
      return;
    }
    this.detailStartScrollOffset = 0;
    this.detailScrollResetVersion++;
    this.onDetailScrollUpdate(0);
    this.loadDetailFromLink();
  }

  private handleDetailSystemBack(): boolean {
    if (this.downloadLabelDialogVisible) {
      this.downloadLabelDialogVisible = false;
      this.renderVersion++;
      return true;
    }
    if (this.addFavoriteDialogVisible) {
      this.addFavoriteDialogVisible = false;
      this.renderVersion++;
      return true;
    }
    if (this.archivePanelVisible) {
      this.closeArchivePanel();
      this.renderVersion++;
      return true;
    }
    if (this.commentGalleryLink.gid > 0) {
      this.commentGalleryLink = createEmptyGalleryDetailLink();
      this.saveNavigationState();
      this.renderVersion++;
      return true;
    }
    if (this.showInfo) {
      this.showInfo = false;
      this.saveNavigationState();
      this.renderVersion++;
      return true;
    }
    if (this.showComments) {
      this.showComments = false;
      this.saveNavigationState();
      this.renderVersion++;
      return true;
    }
    return false;
  }

  private saveNavigationState(): void {
    if (this.detailLink.gid <= 0 || this.detailLink.token.length === 0) {
      return;
    }
    detailHostNavigationCache.set(detailHostCacheKey(this.detailLink), {
      showInfo: this.showInfo,
      showComments: this.showComments,
      commentGalleryLink: cloneDetailHostLink(this.commentGalleryLink)
    });
  }

  private restoreNavigationState(): DetailHostNavigationState {
    const saved = detailHostNavigationCache.get(detailHostCacheKey(this.detailLink));
    if (saved === undefined) {
      return {
        showInfo: false,
        showComments: false,
        commentGalleryLink: createEmptyGalleryDetailLink()
      };
    }
    return {
      showInfo: saved.showInfo === true,
      showComments: saved.showComments,
      commentGalleryLink: cloneDetailHostLink(saved.commentGalleryLink)
    };
  }

  private loadDetailFromLink(done?: () => void): void {
    this.commentPostGate.begin();
    this.tagSubscriptionGate.begin();
    this.commentPosting = false;
    if (this.detail.gid !== this.detailLink.gid || this.detail.token !== this.detailLink.token) {
      this.commentDraft = '';
      this.commentPostStatus = '';
    }
    if (this.detailLink.gid <= 0 || this.detailLink.token.length === 0) {
      this.detail = createEmptyDetail();
      this.detailStatus = 'No gallery loaded';
      this.detailLoaded = false;
      this.renderVersion++;
      if (done !== undefined) {
        done();
      }
      return;
    }
    const requestGeneration = this.detailRequestGate.begin();
    this.startSectionsTimeout(requestGeneration);
    const navigationState = this.restoreNavigationState();
    this.closeArchivePanel();
    this.detailPreviewPager.start();
    this.previewMap.clear();
    this.previewPageSize = 0;
    this.previewJumpSerial++;
    this.previewJumpLoading = false;
    this.visiblePreviews = [];
    this.showInfo = navigationState.showInfo;
    this.showComments = navigationState.showComments;
    this.commentGalleryLink = navigationState.commentGalleryLink;
    this.detail = initialDetailForLink(this.detailLink);
    this.detailRequestUrl = this.detailLink.url;
    this.detailStatus = 'Loading detail for gid ' + this.detailLink.gid.toString() + '...';
    this.detailDownloadText = detailDownloadButtonText(this.detailLink.gid);
    this.detailLoaded = false;
    this.optimisticFavorite = this.detail.favoriteSlot >= 0;
    this.syncLocalFavoriteState();
    this.favoriteBusy = false;
    const requestGid = this.detailLink.gid;
    this.renderVersion++;
    loadGalleryDetailModule(this.client, this.detailLink).then((result: GalleryDetailModuleLoadResult) => {
      if (!this.detailRequestGate.isCurrent(requestGeneration) || this.detailLink.gid !== requestGid ||
        this.detail.gid !== requestGid) {
        if (done !== undefined) {
          done();
        }
        return;
      }
      if (!result.ok) {
        this.detailRequestUrl = result.url;
        this.detailStatus = result.statusText;
        this.markSectionsFailed(result.statusText);
        this.renderVersion++;
        if (done !== undefined) {
          done();
        }
        return;
      }
      this.clearSectionsTimeout();
      this.sectionsFailed = false;
      this.sectionsMessage = '';
      this.detail = result.detail;
      this.visiblePreviews = cloneGalleryPreviews(this.detail.previewSet);
      this.detailRequestUrl = result.url;
      this.detailStatus = result.statusText;
      this.detailLoaded = true;
      this.previewPageSize = seedPreviewMap(this.previewMap, this.detail.previewSet, this.previewPageSize);
      this.optimisticFavorite = this.detail.isFavorited;
      this.syncLocalFavoriteState(true);
      refreshDetailDownloadItem(this.detail);
      this.detailDownloadText = detailDownloadButtonText(this.detail.gid);
      saveGalleryToHistory(this.detail);
      this.onDetailLoaded(this.detail);
      this.renderVersion++;
      if (done !== undefined) {
        done();
      }
    }).catch((error: Error) => {
      if (this.detailRequestGate.isCurrent(requestGeneration) && this.detailLink.gid === requestGid &&
        this.detail.gid === requestGid) {
        this.detailStatus = 'Detail load failed: ' + error.message;
        this.markSectionsFailed('Detail load failed: ' + error.message);
        this.renderVersion++;
      }
      if (done !== undefined) {
        done();
      }
    });
  }

  private refreshCurrentDetail(done: () => void): void {
    this.detailStatus = 'Refreshing detail...';
    this.renderVersion++;
    this.loadDetailFromLink(done);
  }

  private refreshDetailDownloadText(): void {
    if (this.detail.gid <= 0) {
      return;
    }
    this.detailDownloadText = detailDownloadButtonText(this.detail.gid);
    this.renderVersion++;
  }

  private displayDetail(): GalleryDetail {
    const detail = cloneGalleryDetail(this.detail);
    detail.previewSet = cloneGalleryPreviews(this.visiblePreviews);
    return detail;
  }

  private openComments(): void {
    if (!this.detailLoaded) {
      return;
    }
    this.showInfo = false;
    this.showComments = true;
    this.saveNavigationState();
    this.renderVersion++;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (error) {
    }
  }

  private openCommentGalleryLink(url: string): void {
    const site = url.indexOf('exhentai.org') >= 0 ? GallerySite.Ex :
      (url.indexOf('e-hentai.org') >= 0 ? GallerySite.E : this.detailLink.site);
    const link = createGalleryDetailLinkFromUrl(url, site, this.detailRequestUrl.length > 0 ?
      this.detailRequestUrl : this.detailLink.url);
    if (link === null) {
      return;
    }
    this.commentGalleryLink = link;
    this.saveNavigationState();
    this.renderVersion++;
  }

  private readDetail(): void {
    const downloadItem = findDetailDownloadItem(this.detail.gid);
    // 文件缺失（导入只带记录没带图片）不能走本地阅读，否则读到空目录一直转圈。
    if (downloadItem !== null && downloadItem.state !== DownloadState.Missing) {
      readerStartIndexAsync(this.detail).then((index: number) => {
        this.openDownloadedReaderAt(downloadItem, index);
      }).catch(() => {
        this.openDownloadedReaderAt(downloadItem, readerStartIndex(this.detail));
      });
      return;
    }
    readerStartIndexAsync(this.detail).then((index: number) => {
      this.openRemoteReaderAt(index);
    }).catch(() => {
      this.openRemoteReaderAt(readerStartIndex(this.detail));
    });
  }

  private openRemoteReaderAt(index: number): void {
    if (this.detail.gid <= 0 || (this.detail.pages <= 0 && this.detail.previewSet.length === 0)) {
      this.detailStatus = 'Read is waiting for preview pages';
      this.renderVersion++;
      return;
    }
    readerSessionStore.setSession(createReaderSessionState(this.detail, createEmptyPage(), 'Reader is ready',
      this.detailRequestUrl, this.listRequestUrl, this.detailLink.site, index));
    this.launchReader();
  }

  private openDownloadedReaderAt(item: DownloadInfo, requestedIndex: number): void {
    readerSessionStore.setSession(createDownloadReaderSessionState(item, requestedIndex, this.detailLink.site,
      this.detailRequestUrl, this.listRequestUrl, this.detail));
    this.launchReader();
  }

  private jumpPreviewPage(pageIndex: number): void {
    const total = this.detail.previewPages;
    if (total <= 0) {
      this.detailStatus = 'Preview pages are unavailable';
      this.renderVersion++;
      return;
    }
    const target = Math.max(0, Math.min(pageIndex, total - 1));
    const activeJumpSerial = ++this.previewJumpSerial;
    const pageSize = detailPreviewPageSize(this.detail, this.previewPageSize);
    this.previewPageSize = pageSize;
    this.detailPreviewPager.setNextPageIndex(target + 1);
    this.visiblePreviews = selectPreviewPage(this.detail.previewSet, target, pageSize);
    this.previewJumpLoading = target > 0;
    if (target === 0) {
      this.previewJumpLoading = false;
      this.detailStatus = 'Preview page ' + (target + 1).toString() + '/' + total.toString() + ' loaded';
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Loading preview page ' + (target + 1).toString() + '/' + total.toString() + '...';
    this.renderVersion++;
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.detailLink.referer;
    loadGalleryPreviewPage({
      client: this.client,
      site: this.detailLink.site,
      referer: referer,
      pageIndex: target,
      getDetail: () => this.detail,
      isCurrent: () => activeJumpSerial === this.previewJumpSerial && this.detail.gid === this.detailLink.gid,
      onMerge: (detail: GalleryDetail) => {
        const merged = mergeGalleryPreviewSets(this.detail, detail, this.previewMap, this.previewPageSize);
        this.detail = merged.detail;
        this.previewPageSize = merged.previewPageSize;
        this.visiblePreviews = cloneGalleryPreviews(detail.previewSet);
        this.previewJumpLoading = false;
        this.detailStatus = 'Preview page ' + (target + 1).toString() + '/' + total.toString() + ' loaded';
        this.onDetailLoaded(this.detail);
        this.renderVersion++;
      },
      onError: (message: string) => {
        if (activeJumpSerial !== this.previewJumpSerial) {
          return;
        }
        this.previewJumpLoading = false;
        this.detailStatus = 'Preview page load failed: ' + message;
        this.renderVersion++;
      }
    }).then((loaded: boolean) => {
      if (activeJumpSerial !== this.previewJumpSerial) {
        return;
      }
      this.previewJumpLoading = false;
      if (!loaded && this.detailStatus.indexOf('Preview page load failed') !== 0) {
        this.detailStatus = 'Preview page ' + (target + 1).toString() + '/' + total.toString() + ' unavailable';
        this.renderVersion++;
      }
    }).catch((error: Error) => {
      if (activeJumpSerial !== this.previewJumpSerial) {
        return;
      }
      this.previewJumpLoading = false;
      this.detailStatus = 'Preview page load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private launchReader(): void {
    if (appSettingsStore.getValue('reader_standalone', 'Off') !== 'On') {
      this.onShowEmbeddedReader();
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.detailStatus = 'Reader launch failed: Ability context is not ready';
      this.renderVersion++;
      return;
    }
    context.startAbility({
      bundleName: 'yt.ehviewer.huawei',
      moduleName: 'entry',
      abilityName: 'ReaderAbility'
    }).catch((error: Error) => {
      this.detailStatus = 'Reader launch failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private toggleDownloadDetail(): void {
    if (isDetailCloudOnlyDownload(this.detail.gid)) {
      this.startCloudRestoreToLocal();
      return;
    }
    if (findDetailDownloadItem(this.detail.gid) === null) {
      const labels = ehDownloadStore.getLabels();
      const defaultLabel = defaultDownloadLabelChoice();
      if (defaultLabel === DOWNLOAD_LABEL_OPTION_ASK && labels.length > 0) {
        this.downloadLabelOptions = labels;
        this.rememberDownloadLabel = false;
        this.downloadLabelDialogVisible = true;
        this.renderVersion++;
        return;
      }
      this.applyDownloadDetailToggle(defaultLabel === DOWNLOAD_LABEL_OPTION_ASK ? '' : defaultLabel);
      return;
    }
    this.applyDownloadDetailToggle('');
  }

  private startCloudRestoreToLocal(): void {
    const context = getAbilityContext();
    if (context === undefined || this.cloudRestoreInFlight) {
      return;
    }
    this.cloudRestoreInFlight = true;
    this.detailDownloadText = 'Downloading';
    this.detailStatus = uiText('Downloading from cloud');
    this.renderVersion++;
    remoteStorageSyncService.restoreCloudGallery(context, this.detail.gid).then((restored: boolean) => {
      this.cloudRestoreInFlight = false;
      this.refreshDetailDownloadText();
      this.detailStatus = restored ? uiText('Downloaded to local') : uiText('Download from cloud failed');
      this.renderVersion++;
    }).catch(() => {
      this.cloudRestoreInFlight = false;
      this.refreshDetailDownloadText();
      this.detailStatus = uiText('Download from cloud failed');
      this.renderVersion++;
    });
  }

  private applyDownloadDetailToggle(label: string): void {
    const result: DetailDownloadToggleResult = toggleDetailDownloadTask(this.detail, label);
    if (result.shouldStartQueue) {
      const context = getAbilityContext();
      if (context !== undefined) {
        this.startDownloadQueueWithCellularGuard(context);
      }
    }
    this.detailDownloadText = result.buttonText;
    this.detailStatus = result.statusText;
    this.renderVersion++;
  }

  private startDownloadQueueWithCellularGuard(context: common.UIAbilityContext): void {
    if (shouldConfirmCellularNetworkOperation()) {
      this.confirmMobileDataDownload(() => {
        ehDownloadManager.startQueue(context);
      });
      return;
    }
    ehDownloadManager.startQueue(context);
  }

  private confirmMobileDataDownload(onContinue: () => void): void {
    if (this.cellularWarningDialogOpen) {
      return;
    }
    this.cellularWarningDialogOpen = true;
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('Mobile data warning'),
      message: uiText('You are using mobile data. Continue downloading?'),
      buttons: [
        { text: uiText('Cancel'), color: themeSecondaryText() },
        { text: uiText('Continue'), color: themeAccentTextColor() }
      ]
    }).then((data) => {
      this.cellularWarningDialogOpen = false;
      if (data.index === 1) {
        confirmCellularNetworkWarningForSession();
        onContinue();
      } else {
        this.detailStatus = 'Download waits for Wi-Fi or confirmation';
        this.renderVersion++;
      }
    }).catch(() => {
      this.cellularWarningDialogOpen = false;
      this.detailStatus = 'Download waits for Wi-Fi or confirmation';
      this.renderVersion++;
    });
  }

  private setDetailStatus(message: string): void {
    this.detailStatus = message;
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0 || this.favoriteBusy) {
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    if (!wasFavorited) {
      this.showAddFavoriteDialog();
      return;
    }
    if (this.detail.favoriteSlot === -1) {
      const context = getAbilityContext();
      if (context === undefined) {
        this.setDetailStatus('Local favorites unavailable');
        return;
      }
      const targetGid = this.detail.gid;
      this.favoriteBusy = true;
      this.setDetailStatus('Removing from local favorites...');
      this.optimisticFavorite = false;
      this.applyDetailFavoriteState(false, -2);
      ehLocalFavoritesStore.ensureLoaded(context).then(() => {
        ehLocalFavoritesStore.removeGallery(targetGid);
        this.favoriteBusy = false;
        if (this.detail.gid !== targetGid) {
          return;
        }
        const removedMessage = 'Removed from local favorites';
        this.setDetailStatus(removedMessage);
        this.showToast(removedMessage);
      }).catch((error: Error) => {
        this.favoriteBusy = false;
        if (this.detail.gid !== targetGid) {
          return;
        }
        this.setDetailStatus('Favorite failed: ' + error.message);
        this.optimisticFavorite = true;
        this.applyDetailFavoriteState(true, -1);
      });
      return;
    }
    this.setDetailStatus('Removing from favorites...');
    this.favoriteBusy = true;
    this.optimisticFavorite = false;
    this.applyDetailFavoriteState(false, -2);
    this.removeLocalFavoriteIfNeeded();
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited, this.detailLink.site)
      .then((result: ToggleFavoriteResult) => {
        this.setDetailStatus(result.message);
        this.optimisticFavorite = result.ok ? result.nowFavorited : wasFavorited;
        this.applyDetailFavoriteState(this.optimisticFavorite, this.optimisticFavorite ? 0 : -2);
        this.favoriteBusy = false;
        if (result.ok) {
          this.showToast(result.message);
        }
      }).catch((error: Error) => {
        this.setDetailStatus('Favorite failed: ' + error.message);
        this.optimisticFavorite = wasFavorited;
        this.applyDetailFavoriteState(wasFavorited, wasFavorited ? Math.max(0, this.detail.favoriteSlot) : -2);
        this.favoriteBusy = false;
      });
  }

  private showAddFavoriteDialog(): void {
    const defaultSlot = parseDefaultFavoriteSlot(appSettingsStore.getValue(DEFAULT_FAVORITE_SLOT_SETTING_KEY,
      DEFAULT_FAVORITE_SLOT_ASK));
    if (defaultSlot !== null) {
      this.addFavoriteToSlot(defaultSlot);
      return;
    }
    this.rememberFavoriteSlot = false;
    this.favoriteCategories = [];
    this.addFavoriteDialogVisible = true;
    this.renderVersion++;
    const generation = this.favoriteCategoryRequestGate.begin();
    const gid = this.detail.gid;
    const token = this.detail.token;
    const site = this.detailLink.site;
    this.client.loadFavoriteCategories(site).then((categories: FavoriteCategoryInfo[]) => {
      if (this.favoriteCategoryRequestGate.isCurrent(generation) && this.addFavoriteDialogVisible &&
        this.detail.gid === gid && this.detail.token === token && this.detailLink.site === site) {
        this.favoriteCategories = categories;
      }
    }).catch(() => {
      // Keep local favorites and numbered slots usable when the site is temporarily unavailable.
    });
  }

  private confirmDetailDownloadLabel(label: string): void {
    if (this.rememberDownloadLabel) {
      saveDefaultDownloadLabelChoice(label);
    }
    this.downloadLabelDialogVisible = false;
    this.applyDownloadDetailToggle(label);
  }

  private addFavoriteDialogMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 620;
    }
    return Math.max(280, this.viewportHeight - 96);
  }

  private selectFavoriteSlot(slot: number): void {
    this.addFavoriteDialogVisible = false;
    if (this.rememberFavoriteSlot) {
      appSettingsStore.setValue(DEFAULT_FAVORITE_SLOT_SETTING_KEY, defaultFavoriteSlotSettingValue(slot));
    } else {
      appSettingsStore.setValue(DEFAULT_FAVORITE_SLOT_SETTING_KEY, DEFAULT_FAVORITE_SLOT_ASK);
    }
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch(() => {
      });
    }
    this.addFavoriteToSlot(slot);
  }

  private addFavoriteToSlot(slot: number): void {
    if (slot === -1) {
      this.addLocalFavorite();
    } else {
      this.addCloudFavorite(Math.max(0, Math.min(9, slot)));
    }
  }

  private addLocalFavorite(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.detailStatus = 'Local favorites unavailable';
      this.renderVersion++;
      return;
    }
    this.favoriteBusy = true;
    this.detailStatus = 'Adding to local favorites...';
    this.renderVersion++;
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      ehLocalFavoritesStore.addGallery(this.detail);
      this.optimisticFavorite = true;
      this.applyDetailFavoriteState(true, -1);
      this.detailStatus = 'Added to local favorites';
      this.favoriteBusy = false;
      this.showToast(this.detailStatus);
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
      this.favoriteBusy = false;
      this.renderVersion++;
    });
  }

  private addCloudFavorite(slot: number): void {
    this.detailStatus = 'Adding to favorites...';
    this.favoriteBusy = true;
    this.optimisticFavorite = true;
    this.applyDetailFavoriteState(true, slot);
    this.renderVersion++;
    this.client.toggleFavorite(this.detail.gid, this.detail.token, false, this.detailLink.site, slot)
      .then((result: ToggleFavoriteResult) => {
        this.detailStatus = result.message;
        this.optimisticFavorite = result.ok ? result.nowFavorited : false;
        this.applyDetailFavoriteState(this.optimisticFavorite, this.optimisticFavorite ? slot : -2);
        this.favoriteBusy = false;
        if (result.ok) {
          this.showToast(result.message);
        }
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Favorite failed: ' + error.message;
        this.optimisticFavorite = false;
        this.applyDetailFavoriteState(false, -2);
        this.favoriteBusy = false;
        this.renderVersion++;
      });
  }

  private removeLocalFavoriteIfNeeded(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      ehLocalFavoritesStore.removeGallery(this.detail.gid);
    }).catch(() => {});
  }

  private syncLocalFavoriteState(updateStoredGallery: boolean = false): void {
    const context = getAbilityContext();
    if (context === undefined || this.detail.gid <= 0) {
      return;
    }
    const targetGid = this.detail.gid;
    const loadedDetail = cloneGalleryDetail(this.detail);
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      if (this.detail.gid !== targetGid || !ehLocalFavoritesStore.contains(targetGid)) {
        return;
      }
      if (updateStoredGallery) {
        ehLocalFavoritesStore.updateGalleryIfPresent(loadedDetail);
      }
      this.applyDetailFavoriteState(true, -1);
      this.optimisticFavorite = true;
      this.renderVersion++;
    }).catch(() => {});
  }

  private applyDetailFavoriteState(isFavorited: boolean, favoriteSlot: number): void {
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.isFavorited = isFavorited;
    nextDetail.favoriteSlot = isFavorited ? favoriteSlot : -2;
    nextDetail.favoriteName = favoriteSlot === -1 ? undefined : nextDetail.favoriteName;
    this.detail = nextDetail;
  }

  private rateDetail(rating: number): void {
    if (this.detail.gid <= 0 || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      // 站点评分必须带会话凭据。Toast 在详情页经常看不见（被底部栏盖住/时机太快），
      // 改成弹窗，用户一定能看到。
      this.getUIContext().getPromptAction().showDialog({
        title: uiText('Sign in required'),
        message: uiText('Rating needs an E-Hentai account. Sign in from the side drawer, then come back.'),
        buttons: [{ text: uiText('Got it'), color: themeAccentTextColor() }]
      });
      this.detailStatus = 'Rating needs a signed-in session';
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Submitting rating...';
    this.renderVersion++;
    this.client.rateGallery(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, rating,
      this.detailLink.site).then((result: RateGalleryResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        const nextDetail = cloneGalleryDetail(this.detail);
        nextDetail.rating = result.rating;
        nextDetail.ratingCount = result.ratingCount > 0 ? result.ratingCount : nextDetail.ratingCount;
        nextDetail.rated = true;
        this.detail = nextDetail;
        this.showToast('Rating submitted');
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Rating failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private shareGallery(): void {
    const context = getAbilityContext();
    if (context === undefined || !this.detailLoaded) {
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, this.detailLink.site);
    const shareData = new systemShare.SharedData({
      utd: utd.UniformDataType.PLAIN_TEXT,
      content: url,
      title: galleryDisplayTitle(this.detail),
      description: 'EhViewer'
    });
    const controller = new systemShare.ShareController(shareData);
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    }).catch(() => {});
  }

  private openTorrentPanel(): void {
    // 详情页常能解析出种子数量、但取不到 torrent 链接；
    // 只要数量大于 0 就继续走加载流程，由客户端用 gid/token 兜底拼出种子页。
    if (!this.detailLoaded || (this.detail.torrentUrl.length === 0 && this.detail.torrentCount === 0)) {
      this.detailStatus = 'Torrent URL is unavailable';
      // 分三种情况讲清楚，别把「没登录」和「这页真没种子」混成一句话。
      if (!this.detailLoaded) {
        this.showBlockedDialog(uiText('Torrents unavailable'),
          uiText('The gallery is still loading. Please try again in a moment.'));
      } else if (!ehCookieStore.hasCookies()) {
        this.showBlockedDialog(uiText('Sign in to view torrents'),
          uiText('E-Hentai only shows the torrent list to signed-in accounts. Sign in from the side drawer, then try again.'));
      } else {
        this.showBlockedDialog(uiText('No torrents for this gallery'),
          uiText('This gallery has no torrent link on its page.'));
      }
      this.renderVersion++;
      return;
    }
    this.archivePanelVisible = true;
    this.archivePanelMode = 'torrent';
    this.archivePanelStatus = 'Loading...';
    this.archiveBusy = true;
    this.torrentList = [];
    const requestGeneration = this.archiveRequestGate.begin();
    this.renderVersion++;
    this.client.loadTorrentList(this.detail.torrentUrl, this.detail.gid, this.detail.token, this.detailLink.site)
      .then((result: TorrentListLoadResult) => {
        if (!this.archiveRequestCurrent(requestGeneration, 'torrent')) {
          return;
        }
        this.archiveBusy = false;
        this.archivePanelStatus = result.ok ? '' : result.message;
        this.torrentList = result.torrents;
        this.renderVersion++;
      }).catch((error: Error) => {
        if (!this.archiveRequestCurrent(requestGeneration, 'torrent')) {
          return;
        }
        this.archiveBusy = false;
        this.archivePanelStatus = 'Torrent failed: ' + error.message;
        this.renderVersion++;
      });
  }

  // 复制的是种子文件地址，不是磁力：EH 链接里的 40 位 hash 是站点自己的编号，
  // 不是 torrent 的 info_hash，拼成 magnet 后迅雷一类客户端无法解析。  // 下载种子文件本体：与安卓版一致，先落盘再交给迅雷一类的客户端。
  // 磁力行不通的原因：EH 链接里的 40 位是站点编号，不是 info_hash。  // 点击种子 = 复制真磁力。info_hash 必须从 .torrent 文件里算（应用内带 Cookie 下载），
  // 拼假的 hash 迅雷解析不出来。解析失败时退化为复制种子文件地址。
  private async downloadTorrent(torrent: TorrentInfo): Promise<void> {
    if (torrent.url.length === 0) {
      this.showToast('Torrent link unavailable');
      return;
    }
    const absolute = torrent.url.startsWith('http')
      ? torrent.url
      : (this.detailLink.site === GallerySite.Ex ? EhUrl.HOST_EX : EhUrl.HOST_E) + torrent.url.replace(/^\/+/, '');
    this.showToast('Fetching torrent');
    const bytes = await this.client.fetchTorrentBytes(absolute);
    if (bytes === null) {
      this.showToast('Torrent download failed');
      return;
    }
    let copied = '';
    const hash = await extractInfoHash(bytes);
    if (hash.length === 40) {
      const name = torrent.name.length > 0 ? torrent.name : ('torrent_' + this.detail.gid.toString());
      copied = 'magnet:?xt=urn:btih:' + hash + '&dn=' + encodeURIComponent(name);
    } else {
      copied = absolute;
      console.warn('[torrent] info_hash parse failed, fallback to url');
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, copied);
      await pasteboard.getSystemPasteboard().setData(data);
      this.closeArchivePanel();
      this.showToast(hash.length === 40 ? 'Magnet copied' : 'Torrent link copied');
      this.renderVersion++;
    } catch (error) {
      console.error('[torrent] copy failed ' + String(error));
      this.showToast('Copy failed');
    }
  }

  private closeArchivePanel(): void {
    this.archiveRequestGate.begin();
    this.archivePanelVisible = false;
    this.archivePanelMode = '';
    this.archivePanelStatus = '';
    this.archiveBusy = false;
    this.archiverInfo = { funds: '', options: [] };
    this.hathArchiveList = { formParamOr: '', options: [] };
    this.torrentList = [];
  }

  private archiveRequestCurrent(generation: number, mode: string): boolean {
    return this.archivePanelVisible && this.archivePanelMode === mode &&
      this.archiveRequestGate.isCurrent(generation);
  }

  private ensureArchiveSession(): boolean {
    const reason = archiveUnavailableReason(this.detailLoaded, this.detail);
    if (reason.length > 0) {
      this.detailStatus = reason;
      this.showBlockedDialog(uiText('Sign in required'),
        uiText('This action needs a signed-in E-Hentai account. Sign in from the side drawer, then come back.'));
      this.renderVersion++;
      return false;
    }
    return true;
  }

  // 统一的「点了但做不了」弹窗：说明原因，不再让按钮像坏的。
  private showBlockedDialog(title: string, message: string): void {
    this.getUIContext().getPromptAction().showDialog({
      title: title,
      message: message,
      buttons: [{ text: uiText('Got it'), color: themeAccentTextColor() }]
    });
  }

  private openArchiverPanel(): void {
    if (!this.ensureArchiveSession()) {
      return;
    }
    this.archivePanelVisible = true;
    this.archivePanelMode = 'archiver';
    this.archivePanelStatus = 'Loading...';
    this.archiveBusy = true;
    this.archiverInfo = { funds: '', options: [] };
    const requestGeneration = this.archiveRequestGate.begin();
    this.renderVersion++;
    this.client.loadArchiver(this.detail.gid, this.detail.token, this.detail.archiveUrl, this.detailLink.site)
      .then((result: ArchiverLoadResult) => {
        if (!this.archiveRequestCurrent(requestGeneration, 'archiver')) {
          return;
        }
        this.archiveBusy = false;
        this.archivePanelStatus = result.ok ? '' : 'Archive failed: ' + result.message;
        this.archiverInfo = result.info === null ? { funds: '', options: [] } : result.info;
        this.renderVersion++;
      }).catch((error: Error) => {
        if (!this.archiveRequestCurrent(requestGeneration, 'archiver')) {
          return;
        }
        this.archiveBusy = false;
        this.archivePanelStatus = 'Archive failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private openHathPanel(): void {
    if (!this.ensureArchiveSession()) {
      return;
    }
    this.archivePanelVisible = true;
    this.archivePanelMode = 'hath';
    this.archivePanelStatus = 'Loading...';
    this.archiveBusy = true;
    this.hathArchiveList = { formParamOr: '', options: [] };
    const requestGeneration = this.archiveRequestGate.begin();
    this.renderVersion++;
    this.client.loadHathArchiveList(this.detail.gid, this.detail.token, this.detail.archiveUrl, this.detailLink.site)
      .then((result: HathArchiveListLoadResult) => {
        if (!this.archiveRequestCurrent(requestGeneration, 'hath')) {
          return;
        }
        this.archiveBusy = false;
        this.archivePanelStatus = result.ok ? result.message : 'H@H failed: ' + result.message;
        this.hathArchiveList = result.list === null ? { formParamOr: '', options: [] } : result.list;
        this.renderVersion++;
      }).catch((error: Error) => {
        if (!this.archiveRequestCurrent(requestGeneration, 'hath')) {
          return;
        }
        this.archiveBusy = false;
        this.archivePanelStatus = 'H@H failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private submitArchiverOption(option: ArchiverOption): void {
    if (this.archiveBusy) {
      return;
    }
    this.archiveBusy = true;
    this.archivePanelStatus = 'Submitting...';
    const requestGeneration = this.archiveRequestGate.begin();
    this.renderVersion++;
    const referer = detailArchiveReferer(this.detail, this.detailLink.site);
    this.client.requestArchiverDownload(option, referer, this.detailLink.site).then((result: ArchiverDownloadResult) => {
      if (!this.archiveRequestCurrent(requestGeneration, 'archiver')) {
        return;
      }
      this.archivePanelStatus = result.message;
      if (result.ok && result.downloadUrl.length > 0) {
        this.startArchiveDownload(result.downloadUrl).then(() => {
          if (!this.archiveRequestCurrent(requestGeneration, 'archiver')) {
            return;
          }
          this.archiveBusy = false;
          this.closeArchivePanel();
          this.detailStatus = 'Archive download started';
          this.showToast('Archive download started');
          this.renderVersion++;
        }).catch((error: Error) => {
          if (!this.archiveRequestCurrent(requestGeneration, 'archiver')) {
            return;
          }
          this.archiveBusy = false;
          this.archivePanelStatus = 'Archive failed: ' + error.message;
          this.showToast('Archive download failed');
          this.renderVersion++;
        });
        return;
      }
      this.archiveBusy = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      if (!this.archiveRequestCurrent(requestGeneration, 'archiver')) {
        return;
      }
      this.archiveBusy = false;
      this.archivePanelStatus = 'Archive failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private async startArchiveDownload(url: string): Promise<PublicDownloadStartResult> {
    const context = getAbilityContext();
    if (context === undefined) {
      throw new Error('App context is unavailable');
    }
    const directory = await this.ensurePublicDownloadDirectory(context);
    const title = this.detail.title.length > 0 ? this.detail.title : this.detail.gid.toString();
    const fileName = title + ' (' + this.detail.gid.toString() + ').zip';
    return startPublicDownload(context, url, detailArchiveReferer(this.detail, this.detailLink.site), directory,
      fileName, title, this.detail, this.detailLink.site);
  }

  private async ensurePublicDownloadDirectory(context: common.UIAbilityContext): Promise<string> {
    try {
      return ehDownloadFileStore.publicArchiveDownloadRoot(context);
    } catch (error) {
    }
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const documentPicker = new picker.DocumentViewPicker(context);
    const result = await documentPicker.save(saveOptions);
    if (result.length === 0 || result[0].length === 0) {
      throw new Error('Downloads access was not granted');
    }
    const directory = new fileUri.FileUri(result[0]).path;
    ehDownloadFileStore.rememberPublicDownloadRoot(directory);
    await appSettingsStore.save(context);
    return ehDownloadFileStore.publicArchiveDownloadRoot(context);
  }

  private submitHathOption(option: ArchiveOption): void {
    if (this.archiveBusy) {
      return;
    }
    this.archiveBusy = true;
    this.archivePanelStatus = 'Submitting...';
    const requestGeneration = this.archiveRequestGate.begin();
    this.renderVersion++;
    this.client.submitHathArchive(this.detail.gid, this.detail.token, this.hathArchiveList.formParamOr, option.value,
      this.detailLink.site).then((result: HathArchiveSubmitResult) => {
      if (!this.archiveRequestCurrent(requestGeneration, 'hath')) {
        return;
      }
      this.archiveBusy = false;
      this.archivePanelStatus = result.message;
      this.detailStatus = result.message;
      if (result.ok) {
        this.closeArchivePanel();
        this.showToast('H@H download request submitted');
      } else {
        this.showToast(result.message);
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      if (!this.archiveRequestCurrent(requestGeneration, 'hath')) {
        return;
      }
      this.archiveBusy = false;
      this.archivePanelStatus = 'H@H failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private openSimilarGalleryList(): void {
    if (!this.detailLoaded || this.detail.gid <= 0) {
      this.detailStatus = 'Similar search needs a loaded gallery';
      this.renderVersion++;
      return;
    }
    const request = createSimilarGallerySearch(this.detail);
    if (request !== null) {
      this.onOpenSearch(request);
    }
  }

  private openUploaderGalleryList(): void {
    const uploader = this.detail.uploader === undefined ? '' : this.detail.uploader;
    const request = createUploaderSearchRequest(uploader);
    if (request !== null) {
      this.onOpenSearch(request);
    }
  }

  private openCategoryGalleryList(): void {
    const request = createCategorySearchRequest(this.detail.category, categoryName(this.detail.category));
    this.onOpenSearch(request);
  }

  private openCoverSearch(): void {
    const source = createCoverSearchSource(this.detail, this.detailLink.site, this.detailRequestUrl);
    if (source.previewPageUrl.length === 0 && source.thumb.length === 0) {
      this.detailStatus = 'Cover image is unavailable';
      this.renderVersion++;
      return;
    }
    // Present the search page in the click handler; its loader prepares and uploads the image.
    this.onOpenSearch(createCoverSearchRequest('', source));
  }

  private openTagSearch(namespace: string, tag: string): void {
    const request = createTagSearchRequest(namespace, tag);
    if (request !== null) {
      this.onOpenSearch(request);
    }
  }

  private voteDetailTag(fullTag: string, vote: number): void {
    if (!this.detailLoaded || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      this.detailStatus = 'Tag vote requires gallery API key';
      this.showToast(this.detailStatus);
      this.renderVersion++;
      return;
    }
    this.detailStatus = vote > 0 ? 'Submitting tag vote up...' : 'Submitting tag vote down...';
    this.renderVersion++;
    this.client.voteGalleryTag(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, fullTag, vote,
      this.detailLink.site).then((result: VoteTagResult) => {
      if (!result.ok) {
        this.detailStatus = 'Tag vote failed: ' + result.message;
        this.showToast(this.detailStatus);
        this.renderVersion++;
        return;
      }
      this.detailStatus = result.message;
      this.showToast('Tag vote submitted');
      this.reloadCurrentDetailAfterTagChange();
    }).catch((error: Error) => {
      this.detailStatus = 'Tag vote failed: ' + error.message;
      this.showToast(this.detailStatus);
      this.renderVersion++;
    });
  }

  private addDetailTag(fullTag: string): void {
    this.voteDetailTag(fullTag, 1);
  }

  private copyDetailTag(fullTag: string): void {
    if (fullTag.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, fullTag);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.showToast('Copied to clipboard');
      }).catch(() => {
        this.showToast('Copy failed');
      });
    } catch (error) {
      this.showToast('Copy failed');
    }
  }

  private blockDetailTag(fullTag: string): void {
    const context = getAbilityContext();
    if (context === undefined || fullTag.length === 0) {
      this.showToast('Unable to add local tag filter');
      return;
    }
    ehFilterStore.ensureLoaded(context).then(() => {
      if (!ehFilterStore.addRule(FILTER_MODE_TAG, fullTag)) {
        this.showToast('Rule already exists: ' + fullTag);
        return;
      }
      ehFilterStore.save(context).then(() => {
        this.showToast('Filter rule added: ' + fullTag);
      }).catch((error: Error) => {
        this.showToast('Local tag filter save failed: ' + error.message);
      });
    }).catch((error: Error) => {
      this.showToast('Local tag filter load failed: ' + error.message);
    });
  }

  private subscribeDetailTag(fullTag: string): void {
    this.saveAccountTag(fullTag, false);
  }

  private hideDetailTag(fullTag: string): void {
    this.saveAccountTag(fullTag, true);
  }

  private saveAccountTag(fullTag: string, hidden: boolean): void {
    const tag = fullTag.trim();
    if (tag.length === 0) return;
    if (this.tagSubscriptionSaving) {
      this.showToast('Updating account tag...');
      return;
    }
    const site = this.detailLink.site;
    const gid = this.detailLink.gid;
    const generation = this.tagSubscriptionGate.begin();
    this.tagSubscriptionSaving = true;
    this.showToast(hidden ? 'Blocking tag on account...' : 'Subscribing to tag...');
    const operation = hidden ? ehMyTagsService.hideTag(site, tag) : ehMyTagsService.watchTag(site, tag);
    operation.then((changed: boolean) => {
      if (this.tagSubscriptionGate.isCurrent(generation) && this.detailLink.gid === gid && this.detailLink.site === site) {
        this.showToast(hidden ? (changed ? 'Tag blocked on account' : 'Tag already blocked on account') :
          (changed ? 'Tag subscribed' : 'Tag already subscribed'));
      }
    }).catch((error: Error) => {
      if (this.tagSubscriptionGate.isCurrent(generation) && this.detailLink.gid === gid && this.detailLink.site === site) {
        this.showToast((hidden ? 'Account tag blocking failed: ' : 'Tag subscription failed: ') + error.message);
      }
    }).finally(() => { this.tagSubscriptionSaving = false; });
  }

  private reloadCurrentDetailAfterTagChange(): void {
    const requestGid = this.detail.gid;
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.detailLink.referer;
    this.client.loadGalleryDetail(this.detail.gid, this.detail.token, 0, this.detailLink.site, referer)
      .then((result: GalleryDetailLoadResult) => {
        if (this.detail.gid !== requestGid || result.detail === null) {
          this.renderVersion++;
          return;
        }
        if (!result.ok) {
          this.detailStatus = 'Tag refresh failed: ' + result.message;
          this.renderVersion++;
          return;
        }
        const next = cloneGalleryDetail(result.detail);
        next.previewSet = cloneGalleryPreviews(this.detail.previewSet);
        next.previewPages = Math.max(next.previewPages, this.detail.previewPages);
        this.detail = next;
        this.syncLocalFavoriteState(true);
        this.onDetailLoaded(this.detail);
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Tag refresh failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private openTagDefinition(fullTag: string): void {
    const name = fullTag.replace(/^[a-z]+:\s*/i, '').trim();
    if (name.length === 0) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.detailStatus = 'Tag definition unavailable';
      this.renderVersion++;
      return;
    }
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://ehwiki.org/wiki/' + encodeURIComponent(name).replace(/%20/g, '_'),
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    }).catch((error: Error) => {
      this.detailStatus = 'Tag definition failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private async loadNextDetailPreviewPage(): Promise<void> {
    if (this.previewJumpLoading) {
      return;
    }
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.detailLink.referer;
    await this.detailPreviewPager.loadNext({
      client: this.client,
      site: this.detailLink.site,
      referer: referer,
      getDetail: () => this.detail,
      isVisible: () => this.detail.gid === this.detailLink.gid,
      onMerge: (detail: GalleryDetail) => {
        const merged = mergeGalleryPreviewSets(this.detail, detail, this.previewMap, this.previewPageSize);
        this.detail = merged.detail;
        this.previewPageSize = merged.previewPageSize;
        this.visiblePreviews = mergePreviewList(this.visiblePreviews, detail.previewSet);
        this.renderVersion++;
      },
      onError: (message: string) => {
        this.detailStatus = 'Preview page load failed: ' + message;
        this.renderVersion++;
      }
    });
  }

  private async postDetailComment(): Promise<void> {
    if (this.commentPosting || !this.detailLoaded || this.commentDraft.trim().length === 0) {
      return;
    }
    const generation = this.commentPostGate.begin();
    const gid = this.detail.gid;
    const token = this.detail.token;
    const site = this.detailLink.site;
    this.commentPosting = true;
    this.commentPostStatus = '';
    try {
      const result: CommentPostResult = await this.client.postComment(gid, token, this.commentDraft, site);
      if (!this.commentPostGate.isCurrent(generation) || this.detail.gid !== gid ||
        this.detail.token !== token || this.detailLink.site !== site) {
        return;
      }
      this.commentPostStatus = result.message;
      if (result.ok) {
        const next = cloneGalleryDetail(this.detail);
        next.comments = result.comments;
        this.detail = next;
        this.commentDraft = '';
        this.onDetailLoaded(this.detail);
        this.showToast('Comment posted');
        this.renderVersion++;
      }
    } catch (_error) {
      if (this.commentPostGate.isCurrent(generation)) {
        this.commentPostStatus = COMMENT_POST_UNCONFIRMED;
      }
    } finally {
      if (this.commentPostGate.isCurrent(generation)) {
        this.commentPosting = false;
      }
    }
  }

  private voteDetailComment(comment: GalleryComment, vote: number): void {
    if (!this.detailLoaded || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      this.detailStatus = 'Comment vote requires gallery API key';
      this.renderVersion++;
      return;
    }
    this.client.voteComment(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, comment.id,
      vote, this.detailLink.site).then((result: VoteCommentResult) => {
      if (!result.ok) {
        this.detailStatus = 'Comment vote failed: ' + result.message;
        this.showToast(this.detailStatus);
        this.renderVersion++;
        return;
      }
      this.applyCommentVoteResult(result);
    }).catch((error: Error) => {
      this.detailStatus = 'Comment vote failed: ' + error.message;
      this.showToast(this.detailStatus);
      this.renderVersion++;
    });
  }

  private applyCommentVoteResult(result: VoteCommentResult): void {
    const targetId = result.commentId.length > 0 ? result.commentId : '';
    const next = cloneGalleryDetail(this.detail);
    let changed = false;
    for (let i = 0; i < next.comments.length; i++) {
      if (next.comments[i].id !== targetId) {
        continue;
      }
      next.comments[i].score = result.score;
      if (result.expectedVote > 0) {
        next.comments[i].voteUpEd = result.vote !== 0;
        next.comments[i].voteDownEd = false;
      } else {
        next.comments[i].voteDownEd = result.vote !== 0;
        next.comments[i].voteUpEd = false;
      }
      changed = true;
      break;
    }
    if (!changed) {
      this.detailStatus = 'Comment vote submitted';
      this.showToast(this.detailStatus);
      this.renderVersion++;
      return;
    }
    this.detail = next;
    this.detailStatus = 'Comment vote submitted';
    this.showToast(this.detailStatus);
    this.onDetailLoaded(this.detail);
    this.renderVersion++;
  }

  build() {
    Stack() {
      GalleryDetailOverlayScene({
        renderVersion: this.renderVersion,
        showInfo: this.showInfo,
        showComments: this.showComments,
        commentDraft: this.commentDraft,
        commentPosting: this.commentPosting,
        commentPostStatus: this.commentPostStatus,
        onCommentDraftChange: (value: string) => {
          if (!this.commentPosting) {
            this.commentDraft = value;
            this.commentPostStatus = '';
          }
        },
        onPostComment: () => { this.postDetailComment(); },
        detail: this.displayDetail(),
        isDetailLoaded: this.detailLoaded,
        sectionsFailed: this.sectionsFailed,
        sectionsMessage: this.sectionsMessage,
        onRetrySections: (section: string) => {
          this.retryDetailSections(section);
        },
        isFavorited: this.optimisticFavorite || this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: this.detailDownloadText,
        archivePanelVisible: this.archivePanelVisible,
        archivePanelMode: this.archivePanelMode,
        archivePanelStatus: this.archivePanelStatus,
        archiveBusy: this.archiveBusy,
        archiverInfo: this.archiverInfo,
        hathArchiveList: this.hathArchiveList,
        torrentList: this.torrentList,
        initialDetailScrollOffset: this.detailStartScrollOffset,
        detailScrollResetVersion: this.detailScrollResetVersion,
        onBack: this.onBack,
        onShowInfo: () => {
          this.showInfo = true;
          this.showComments = false;
          this.saveNavigationState();
          this.renderVersion++;
        },
        onCloseInfo: () => {
          this.showInfo = false;
          this.saveNavigationState();
          this.renderVersion++;
        },
        onCloseComments: () => {
          this.commentGalleryLink = createEmptyGalleryDetailLink();
          this.showComments = false;
          this.saveNavigationState();
          this.renderVersion++;
        },
        onDownload: () => { this.toggleDownloadDetail(); },
        onRead: () => { this.readDetail(); },
        onUploaderSearch: () => { this.openUploaderGalleryList(); },
        onCategorySearch: () => { this.openCategoryGalleryList(); },
        onSelectPreview: (preview: GalleryPreview) => {
          const item = findDetailDownloadItem(this.detail.gid);
          if (item !== null) {
            this.openDownloadedReaderAt(item, preview.index);
          } else {
            this.openRemoteReaderAt(preview.index);
          }
        },
        onJumpPreviewPage: (pageIndex: number) => {
          this.jumpPreviewPage(pageIndex);
        },
        onComments: () => { this.openComments(); },
        onVoteComment: (comment: GalleryComment, vote: number) => { this.voteDetailComment(comment, vote); },
        onOpenCommentGalleryLink: (url: string) => { this.openCommentGalleryLink(url); },
        onFavorite: () => { this.toggleFavoriteDetail(); },
        onShare: () => { this.shareGallery(); },
        onRate: (rating: number) => { this.rateDetail(rating); },
        onTorrent: () => { this.openTorrentPanel(); },
        onArchive: () => { this.openArchiverPanel(); },
        onHath: () => { this.openHathPanel(); },
        onSimilar: () => { this.openSimilarGalleryList(); },
        onSearchCover: () => { this.openCoverSearch(); },
        // 未就绪的按钮被点：解释原因，别静默无反应。
        onBlockedAction: () => {
          this.getUIContext().getPromptAction().showDialog({
            title: uiText(this.detailLoaded ? 'Sign in required' : 'Still loading'),
            message: uiText(this.detailLoaded ? 'This action needs a signed-in account.' : 'The gallery is still loading. Please try again in a moment.'),
            buttons: [{ text: uiText('Got it'), color: themeAccentTextColor() }]
          });
        },
        onCloseArchivePanel: () => { this.closeArchivePanel(); },
        onSelectArchiverOption: (option: ArchiverOption) => { this.submitArchiverOption(option); },
        onSelectHathOption: (option: ArchiveOption) => { this.submitHathOption(option); },
        onSelectTorrent: (torrent: TorrentInfo) => { this.downloadTorrent(torrent); },
        onLoadMorePreviews: () => {
          this.loadNextDetailPreviewPage();
        },
        onRefreshDetail: (done: () => void) => {
          this.refreshCurrentDetail(done);
        },
        onDetailScrollUpdate: this.onDetailScrollUpdate,
        onTagSearch: (namespace: string, tag: string) => { this.openTagSearch(namespace, tag); },
        onVoteTag: (fullTag: string, vote: number) => { this.voteDetailTag(fullTag, vote); },
        onAddTag: (fullTag: string) => { this.addDetailTag(fullTag); },
        onCopyTag: (fullTag: string) => { this.copyDetailTag(fullTag); },
        onSubscribeTag: (fullTag: string) => { this.subscribeDetailTag(fullTag); },
        onHideTag: (fullTag: string) => { this.hideDetailTag(fullTag); },
        onBlockTag: (fullTag: string) => { this.blockDetailTag(fullTag); },
        onShowTagDefinition: (fullTag: string) => { this.openTagDefinition(fullTag); }
      })

      if (this.commentGalleryLink.gid > 0) {
        GalleryDetailHostScene({
          detailLink: this.commentGalleryLink,
          listRequestUrl: this.detailRequestUrl,
          onBack: () => {
            this.commentGalleryLink = createEmptyGalleryDetailLink();
            this.saveNavigationState();
            this.renderVersion++;
          },
          onShowEmbeddedReader: this.onShowEmbeddedReader,
          onOpenSearch: this.onOpenSearch
        })
        .transition(TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseOut }))
        .zIndex(20)
      }

      if (this.addFavoriteDialogVisible) {
        AddFavoriteDialog({
          categories: this.favoriteCategories,
          remember: this.rememberFavoriteSlot,
          panelMaxHeight: this.addFavoriteDialogMaxHeight(),
          onRememberChange: (remember: boolean) => {
            this.rememberFavoriteSlot = remember;
            this.renderVersion++;
          },
          onSelect: (slot: number) => {
            this.selectFavoriteSlot(slot);
          },
          onClose: () => {
            this.addFavoriteDialogVisible = false;
            this.renderVersion++;
          }
        })
          .zIndex(40)
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }

      if (this.downloadLabelDialogVisible) {
        DownloadLabelSelectionDialog({
          title: 'Download labels',
          labels: this.downloadLabelOptions,
          selectedLabel: '',
          includeAsk: false,
          showRemember: true,
          panelMaxHeight: this.addFavoriteDialogMaxHeight(),
          onRememberChange: (remember: boolean) => {
            this.rememberDownloadLabel = remember;
          },
          onSelect: (label: string) => {
            this.confirmDetailDownloadLabel(label);
          },
          onClose: () => {
            this.downloadLabelDialogVisible = false;
            this.renderVersion++;
          }
        })
          .zIndex(41)
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const h = newArea.height as number;
      if (h > 0 && !Number.isNaN(h)) {
        this.viewportHeight = h;
      }
    })
  }
}
