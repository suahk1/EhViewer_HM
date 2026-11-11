import { common } from '@kit.AbilityKit';
import { normalizeSceneScrollOffset } from '../shared/ScrollUtils';
import { curves } from '@kit.ArkUI';
import { fileUri, picker } from '@kit.CoreFileKit';
import {
  GalleryCategory,
  GalleryDetail,
  GalleryInfo,
  GalleryRoute,
  GallerySite,
} from '../model/GalleryModels';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
  ehDownloadFileStore,
} from '../services/EhDownloadFileStore';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { EhHttpClient } from '../services/EhHttpClient';
import { remoteStorageDownloadDeletionService } from '../services/RemoteStorageDownloadDeletionService';
import { REMOTE_STORAGE_PURPOSE_DOWNLOADS, remoteStorageProfileStore } from '../services/RemoteStorageProfiles';
import { FloatingActionSideController, storedFloatingActionSide } from '../services/FloatingActionSideSupport';
import { BrowsePosition, ehBrowsePositionStore } from '../services/EhBrowsePositionStore';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { CLOUD_STATE_GONE, DownloadInfo, DownloadLabel, DownloadProgress, DownloadState, ehDownloadStore, normalizeGalleryIdentity } from '../services/EhDownloadStore';
import { LocalImportProgress, LocalImportReport, ReconcileReport, ensureLocalThumbnail,
  galleryIdFromName, importLocalGalleryFolder, logScan, matchGalleryOnServer,
  reconcileDownloadRecords } from '../services/LocalFolderImportService';
import { DOWNLOAD_MATCH_PROGRESS_KEY, DOWNLOAD_MATCH_REPORT_KEY, DOWNLOAD_MATCH_STATE_KEY, MATCH_DIALOG_MINIMIZED_KEY, DownloadMatchProgress,
  DownloadMatchReport, downloadMatchService } from '../services/DownloadMatchService';
import {
  FLOATING_ACTION_HOLDING_HAND_REVISION_KEY,
  FLOATING_ACTION_SIDE_REVISION_KEY,
  TRANSLATION_BUTTONS_VISIBLE_KEY,
  appSettingsStore,
} from '../services/AppSettingsStore';
import {
  TRANSLATION_ENABLED_KEY,
  ehTranslationService,
  translationPriorityForIndex,
} from '../services/EhTranslationService';
import {
  DownloadZipImportResult
} from '../services/DownloadZipImportService';
import {
  confirmCellularNetworkWarningForSession,
  isNetworkOnline,
  shouldConfirmCellularNetworkOperation,
} from '../services/CellularNetworkGuard';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, ListMode } from '../services/EhUrl';
import { galleryMatchesLocalSearch, LocalGallerySearchOptions } from '../services/LocalGallerySearch';
import { createGalleryDetailLinkFromUrl, DetailSearchRequest } from '../services/GalleryDetailSupport';
import { CoverSearchSource } from '../model/GalleryModels';
import {
  createEmptyGalleryDetailLink,
  createGalleryDetailLink,
  createGalleryDetailLinkFromGallery,
  GalleryDetailLink,
  initialDetailForLink,
  startDownloadReaderSession,
  startDownloadReaderSessionAt,
} from '../services/GalleryDetailSupport';
import {
  applyAppChromeImmersiveMode,
  isEmbeddedReaderActive,
  leaveEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp,
  setMainWindowKeepScreenOn,
} from '../services/WindowChromeController';
import {
  peekPendingContinuationSnapshot,
  takePendingContinuationSnapshot,
} from '../services/DistributedContinuationService';
import { readerSessionStore } from '../services/ReaderSessionStore';
import { DOWNLOAD_SORT_OPTIONS, DOWNLOAD_SORT_SETTING_KEY, normalizeDownloadSortMode } from '../services/DownloadSortSupport';
import { applyDownloadProgressUpdates, collectFailedDownloads, DownloadListProjection, hasAnyFailedDownload } from '../services/DownloadListProjection';
import { SettingsOptionPanel } from './SettingsPanels';
import {  PENDING_DETAIL_RESTORE_REVISION_KEY,
  PENDING_DETAIL_RESTORE_ROUTE_KEY,
  PENDING_DETAIL_RESTORE_SITE_KEY,
  PENDING_DETAIL_RESTORE_URL_KEY,
  REMEMBERED_DETAIL_ROUTE_KEY,
  REMEMBERED_DETAIL_SITE_KEY,
  REMEMBERED_DETAIL_URL_KEY,
 BOTTOM_AVOID_HEIGHT_KEY, LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, runDetailBackHandler, setActiveBackHandler,  showTranslationToggleFeedback,  showRaisedToast } from '../shared/AppRuntime';
import { sortedStringKey, toggleStringValue } from '../shared/AppRuntime';
import { APP_DOCK_BAR_HEIGHT, APP_DOCK_FAB_RESERVE, appDockBottomInset } from './FloatingDock';
import { appLog } from '../services/AppLogService';
import { reportAppChromeHidden, resetAppChromeHidden } from '../services/AppChromeSignal';
import { GalleryCardScrollAnchor } from '../shared/GalleryCardScrollAnchor';
import {
  galleryListColumnCount,
  galleryListColumnsTemplate,
  galleryListHorizontalPadding,
  galleryListTopInset,
  galleryListViewportHeight,
} from '../shared/AdaptiveGalleryListLayout';
import {
  clearActiveBackHandler,
  cloneGalleryDetail,
  cloneGalleryInfo,
  createEmptyDetail,
  createEmptyDownloadInfo,
  currentGallerySite,
  defaultDownloadLabelChoice,
  DownloadDisplayState,
  downloadDisplayState,
  downloadProgressText,
  downloadSizeText,
  DOWNLOAD_STATUS_FILTER_OPTIONS,
  filterDownloadItems,
  galleryDetailCardPreferredWidth,
  galleryListMode,
  galleryThumbnailPreferredColumnWidth,
  getAbilityContext,
  saveDefaultDownloadLabelChoice,
  uiText,
  uiStatusText,
} from '../shared/AppRuntime';
import {
  themeAccentTextColor,
  themeDangerBackground,
  themeDangerText,
  themeDividerColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText,
} from '../shared/AppPalette';
import {
  uiAdaptiveToolbarHeight,
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiListGap,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiSearchFieldHeight,
  uiDialogSurfaceBackground,
  uiDialogBlurStyle,
  uiDialogBlurOptions,
  uiDialogMaterial,
  uiDialogSurfaceShadow,
  uiButtonHighlightBorderColor,
  uiPopupEffectBackground,
  uiGlassFloatingButtonEffect,
  uiDockHighlightBorder,
} from '../shared/AppSurfaceStyle';
import { GalleryHomeNavBarHost, GalleryToolbarOffset, GalleryToolbarOffsetBinding } from './GalleryNavHosts';
import { PopupScrim } from './PopupScrim';
import { GalleryListRow, GalleryThumbCard, markGalleryListScrolling } from './GalleryCards';
import { GalleryListScene } from './GalleryScenes';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { LocalGalleryDetailScene } from './LocalGalleryDetailScene';
import { ReaderSessionScene } from './ReaderHostScene';
import { BlockingBusyOverlay } from './BlockingBusyOverlay';
import {
  DOWNLOAD_LABEL_FILTER_ALL,
  DOWNLOAD_LABEL_OPTION_ASK,
  DownloadLabelDrawer,
  DownloadLabelEditDialog,
  DownloadLabelManagerScene,
  DownloadLabelSelectionDialog,
  DownloadDeleteConfirmDialog,
} from './DownloadLabelComponents';
import { ConfirmActionOverlay } from './ConfirmActionOverlay';
import {
  RightSidePanelLayer,
  SIDE_PANEL_WIDTH,
  sidePanelLeft,
  shouldOpenSidePanel,
} from './SidePanelComponents';
import {
  applyTagSuggestionToKeyword,
  buildSearchSuggestions,
  FloatingActionDock,
  normalizeSubmittedSearchKeyword,
  recordSearchHistory,
  SearchActionColumn,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip,
} from './GallerySearchScenes';
import { floatingActionAvailableHeight } from './FloatingActionLayoutSupport';
import {
  areaDimensionToVp,
  markCurrentRouteRightPane,
  normalizeSplitPaneFocus,
  saveSplitPaneRatio,
  SPLIT_PANE_BREAKPOINT,
  SPLIT_PANE_FOCUS_LEFT,
  SPLIT_PANE_FOCUS_RIGHT,
  SPLIT_PANE_RATIO_REVISION_KEY,
  shouldFadeRestoredRightPane,
  splitPaneCurrentRatio,
  SplitPaneDivider,
  splitPaneListWidth,
  splitPaneModeEnabled,
  splitPaneRatioForWidth,
  splitPaneSideWidth,
  splitPaneWidthFromDrag,
  shouldUpdateSplitPaneFocus,
} from './SplitPaneSupport';

import {
  DownloadStatusFilterOverlay,
  DownloadToolColumn,
  DownloadCardStatus,
  DownloadCardState,
} from './DownloadComponents';
import { DOWNLOAD_PAGE_PROGRESS_SCALE } from '../shared/DownloadLimits';

async function pickDownloadDirectoryRoot(context: common.UIAbilityContext): Promise<string> {
  try {
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const documentPicker = new picker.DocumentViewPicker(context);
    const result = await documentPicker.save(saveOptions);
    if (result.length === 0 || result[0].length === 0) {
      return '';
    }
    return new fileUri.FileUri(result[0]).path;
  } catch (error) {
    return '';
  }
}

function normalizeDownloadSceneLocation(value: string): string {
  return value === DOWNLOAD_LOCATION_DOWNLOADS ? DOWNLOAD_LOCATION_DOWNLOADS : DOWNLOAD_LOCATION_APP_FILES;
}

const DOWNLOAD_JUMP_PAGE_SIZE: number = 25;
// 启动时补页数只在后台做一批，避免几百个本地目录一次性扫盘把首屏拖住。
// 本地元数据回填每批处理的目录数：全量跑，但分片让出主线程。
const LOCAL_META_BACKFILL_BATCH: number = 8;
// 回填只做一次：进下载页全量扫描 200 多个目录会让切页明显卡顿。
const LOCAL_BACKFILL_DONE_KEY: string = 'localGalleryBackfillDone';
const LOCAL_GALLERY_LOG_TAG: string = 'LocalGallery';

interface DownloadNavigationCache {
  activeSplitPane: string;
  showDetail: boolean;
  restoreDetailWithFade: boolean;
  detailLink: GalleryDetailLink;
  detail: GalleryDetail;
  detailRequestUrl: string;
  localDetailGid?: number;
  showTagSearch: boolean;
  tagSearchTitle: string;
  tagSearchKeyword: string;
  tagSearchMode: ListMode;
  tagSearchCategory?: number;
  tagSearchImagePath: string;
  tagSearchCoverSource?: CoverSearchSource;
  tagSearchImageUseSimilarity: boolean;
  tagSearchImageOnlyCovers: boolean;
  tagSearchImageShowExpunged: boolean;
}

let downloadNavigationCache: DownloadNavigationCache | null = null;

// 把下载失败的原始报错归类成用户能看懂的中文原因（返回翻译键）。
function downloadFailureReasonKey(message: string): string {
  const m = message.toLowerCase();
  if (m.indexOf('not found') >= 0 || m.indexOf('may have been removed') >= 0 || m.indexOf('404') >= 0) {
    return 'Server removed gallery';
  }
  if (m.indexOf('509') >= 0 || m.indexOf('image limit') >= 0 || m.indexOf('bandwidth') >= 0) {
    return 'Download quota reached';
  }
  if (m.indexOf('429') >= 0 || m.indexOf('too many requests') >= 0) {
    return 'Too many requests';
  }
  if (m.indexOf('403') >= 0 || m.indexOf('access denied') >= 0 || m.indexOf('captcha') >= 0 ||
    m.indexOf('cloudflare') >= 0 || m.indexOf('verification') >= 0) {
    return 'Access denied for download';
  }
  if (m.indexOf('network') >= 0 || m.indexOf('timeout') >= 0 || m.indexOf('timed out') >= 0 ||
    m.indexOf('connect') >= 0 || m.indexOf('offline') >= 0 || m.indexOf('socket') >= 0 ||
    m.indexOf('dns') >= 0 || m.indexOf('request failed') >= 0 || m.indexOf('http') >= 0) {
    return 'Network error for download';
  }
  return 'Download failed';
}

function cloneDownloadDetailLink(link: GalleryDetailLink): GalleryDetailLink {
  return {
    gid: link.gid,
    token: link.token,
    url: link.url,
    referer: link.referer,
    site: link.site,
    seed: cloneGalleryInfo(link.seed)
  };
}


@Component
export struct DownloadScene {
  private unsubscribeStore: () => void = () => {};
  private unsubscribeDownloadManager: () => void = () => {};
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
  @State labels: DownloadLabel[] = [];
  @State visibleItems: DownloadInfo[] = [];
  @State selectedDownloadLabel: string = DOWNLOAD_LABEL_FILTER_ALL;
  @State downloadLabelDrawerVisible: boolean = false;
  @State downloadLabelDrawerOffsetX: number = SIDE_PANEL_WIDTH;
  @State downloadLabelDrawerOverlayOpacity: number = 0;
  @State downloadLabelManagerVisible: boolean = false;
  @State defaultDownloadLabelDialogVisible: boolean = false;
  @State moveDownloadLabelDialogVisible: boolean = false;
  @State downloadLabelEditDialogVisible: boolean = false;
  @State downloadLabelEditValue: string = '';
  @State query: string = '';
  @State searchMode: ListMode = ListMode.Normal;
  @State searchCategory: number = GalleryCategory.None;
  @State advancedSearchEnabled: boolean = false;
  @State advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @State minRating: number = -1;
  @State searchSubmitted: boolean = true;
  @State searchBarVisible: boolean = false;
  @State advancedPanelVisible: boolean = false;
  @State advancedPopupHeight: number = 0;
  @State searchSuggestionItems: SearchSuggestionItem[] = [];
  @State searchSuggestionRevision: number = 0;
  @State selectedTagNamespaces: string[] = [];
  @State statusFilters: string[] = DOWNLOAD_STATUS_FILTER_OPTIONS.slice();
  @State statusFilterDraft: string[] = DOWNLOAD_STATUS_FILTER_OPTIONS.slice();
  @State statusFilterPanelVisible: boolean = false;
  @State sortMode: string = 'Default';
  @State sortPanelVisible: boolean = false;
  @State categoryFilter: string = 'All';
  @State statusText: string = 'Downloads: idle';
  @State showDetail: boolean = false;
  // 稳定的返回处理器闭包：所有注册点共用同一引用，卸载时才能做守卫式清槽。
  private boundSystemBack: () => boolean = () => this.handleSystemBack();
  @State detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailRequestUrl: string = '';
  // 纯本地图册没有服务器详情可拉，右栏改挂本地详情面板，用 gid 定位（合成号段）。
  @State localDetailGid: number = -1;
  @State showReader: boolean = false;
  private readerClosing: boolean = false;
  @State restoreDetailWithFade: boolean = false;
  @State showTagSearch: boolean = false;
  @State tagSearchTitle: string = 'Search';
  @State tagSearchKeyword: string = '';
  @State tagSearchMode: ListMode = ListMode.Tag;
  @State tagSearchCategory: number = GalleryCategory.None;
  @State tagSearchImagePath: string = '';
  @State tagSearchCoverSource: CoverSearchSource | undefined = undefined;
  @State tagSearchImageUseSimilarity: boolean = false;
  @State tagSearchImageOnlyCovers: boolean = false;
  @State tagSearchImageShowExpunged: boolean = false;
  @State downloadContentWidth: number = 0;
  @State sceneContentWidth: number = 0;
  @State splitListRatio: number = splitPaneCurrentRatio();
  @State splitDragging: boolean = false;
  @State activeSplitPane: string = SPLIT_PANE_FOCUS_LEFT;
  @State selectedDownloadGids: string = '';
  private toolbarOffsetY: number = 0;
  @State private toolbarOffsetBinding: GalleryToolbarOffsetBinding = new GalleryToolbarOffsetBinding();

  private toolbarState(): GalleryToolbarOffset {
    return this.toolbarOffsetBinding.state();
  }

  private syncToolbarOffsetState(): void {
    this.toolbarOffsetBinding.set(this.toolbarOffsetY);
  }

  // 底栏常驻，FAB 始终抬到胶囊之上。
  private dockFabReserve(): number {
    return APP_DOCK_FAB_RESERVE;
  }
  @State downloadActionsExpanded: boolean = false;
  @State floatingActionSide: string = storedFloatingActionSide();
  @State statusHintText: string = '';
  @State statusHintVisible: boolean = false;
  // 一轮下载的汇总：队列从「有活动」回到「空闲」时只弹一次结果，而不是每失败一个弹一次。
  private runStartFailed: number = 0;
  private runStartFinished: number = 0;
  private lastQueueActive: boolean = false;
  private suppressSettleReport: boolean = false;
  private runFailureReasons: Map<string, number> = new Map();
  @State settleSummaryVisible: boolean = false;
  @State settleSummaryTitle: string = '';
  @State settleSummaryLines: string[] = [];
  @State blockingBusyVisible: boolean = false;
  @State blockingBusyMessage: string = 'Loading...';
  // 进度数字独立一行：拼进 message 会把弹窗首行塞爆，出现截断（F-113）。
  @State blockingBusyProgressText: string = '';
  // 后台云端匹配（F-115）：弹窗是全局服务的观察者，匹配中/完成态都不可 Back 取消。
  @StorageProp(DOWNLOAD_MATCH_PROGRESS_KEY) @Watch('onDownloadMatchProgress') downloadMatchProgress: DownloadMatchProgress = {
    state: '', current: 0, total: 0, round: 0, phase: ''
  };
  @StorageProp(DOWNLOAD_MATCH_REPORT_KEY) downloadMatchReport: DownloadMatchReport = {
    total: 0, matched: 0, cloudGone: 0, unchanged: 0, pendingNetwork: 0, rounds: 0
  };
  @State matchDialogVisible: boolean = false;
  @State matchDialogDone: boolean = false;

  onDownloadMatchProgress(): void {
    this.syncMatchDialogFromService();
    // 匹配期间强制亮屏：进度跑几分钟到十几分钟，息屏会中断观察（F-115）。
    setMainWindowKeepScreenOn(this.downloadMatchProgress.state === 'matching').catch(() => {});
  }

  // 按全局服务当前进度同步弹窗：切界面回来组件重挂载时立刻恢复，不等下一次广播。
  private syncMatchDialogFromService(): void {
    // 最小化状态下不展开：进度只在右上角圆点上体现，用户点圆点才恢复。
    if (this.matchDialogMinimized) {
      this.matchDialogDone = this.downloadMatchProgress.state === 'done';
      return;
    }
    // 已点过「知道了」的完成报告不再重复弹（F-118：重进下载页烦人的旧报告）。
    const revision = AppStorage.get<number>(DOWNLOAD_MATCH_STATE_KEY) ?? 0;
    if (this.downloadMatchProgress.state === 'done' && this.matchDoneConfirmedRevision === revision) {
      return;
    }
    if (this.downloadMatchProgress.state === 'matching') {
      this.matchDialogVisible = true;
      this.matchDialogDone = false;
      this.blockingBusyMessage = this.downloadMatchProgress.phase === 'cloud' ?
        'Matching cloud identity...' : 'Matching local galleries...';
      // 进度行直接用中文拼（BlockingBusyOverlay 的 progressText 不走 uiStatusText）。
      this.blockingBusyProgressText = this.downloadMatchProgress.current.toString() + ' / ' +
        this.downloadMatchProgress.total.toString() + ' · 第 ' +
        this.downloadMatchProgress.round.toString() + ' 轮';
    } else if (this.downloadMatchProgress.state === 'done') {
      this.matchDialogVisible = true;
      this.matchDialogDone = true;
      // 报告 total 与弹窗进度 total 同源（候选总数），数量口径一致不再「对不上」。
      const stoppedPrefix = downloadMatchService.wasStopped() ? 'Stopped. ' : '';
      this.blockingBusyMessage = stoppedPrefix + 'Total ' + this.downloadMatchReport.total.toString() +
        ' · matched ' + this.downloadMatchReport.matched.toString() +
        ' · cloud gone ' + this.downloadMatchReport.cloudGone.toString() +
        ' · unchanged ' + this.downloadMatchReport.unchanged.toString() +
        ' · pending network ' + this.downloadMatchReport.pendingNetwork.toString() +
        ' · rounds ' + this.downloadMatchReport.rounds.toString();
      this.blockingBusyProgressText = '';
    } else {
      this.matchDialogVisible = false;
      this.matchDialogDone = false;
    }
  }

  // 弹窗最小化（F-118）：AppStorage 持久化——组件重挂载（切界面回来）时
  // 状态不丢，后台锁定不被「回下载页自动弹窗」破坏（F-124 用户反馈）。
  @StorageProp(MATCH_DIALOG_MINIMIZED_KEY) matchDialogMinimized: boolean = false;
  // 已确认的完成报告 revision：dismissed 后重进页面不再重复弹同一份报告。
  private matchDoneConfirmedRevision: number = -1;

  minimizeMatchDialog(): void {
    this.matchDialogVisible = false;
    AppStorage.setOrCreate<boolean>(MATCH_DIALOG_MINIMIZED_KEY, true);
  }

  restoreMatchDialog(): void {
    AppStorage.setOrCreate<boolean>(MATCH_DIALOG_MINIMIZED_KEY, false);
    this.syncMatchDialogFromService();
    this.matchDialogVisible = true;
  }

  dismissMatchDialog(): void {
    this.matchDialogVisible = false;
    this.matchDialogDone = false;
    AppStorage.setOrCreate<boolean>(MATCH_DIALOG_MINIMIZED_KEY, false);
    // 记录已确认的报告版本：重进下载页不再重复弹同一份完成报告。
    this.matchDoneConfirmedRevision = AppStorage.get<number>(DOWNLOAD_MATCH_STATE_KEY) ?? 0;
    setMainWindowKeepScreenOn(false).catch(() => {});
  }

  // ---- 手动查重（F-116）：按规范化标题分组，重复组由用户勾选处理 ----
  @State dedupePanelVisible: boolean = false;
  @State dedupeGroups: DownloadInfo[][] = [];
  // 待删除的 gid（默认组内除第一条外全部标记，用户可点行切换）
  @State dedupeMarked: string[] = [];
  // gid → 已有分组 key 映射：同 gid 多条记录直接归并同组（多维判定第一维度）。
  private gidToDedupeKey: Map<number, string> = new Map<number, string>();
  // 从查重点条目进详情后，关闭详情时自动恢复查重弹窗。
  @State dedupeRestoreOnDetailClose: boolean = false;

  private openDedupePanel(): void {
    this.downloadActionsExpanded = false;
    this.buildDedupeGroups();
    this.dedupeRestoreOnDetailClose = false;
    this.dedupePanelVisible = true;
  }

  private closeDedupePanel(): void {
    this.dedupePanelVisible = false;
    this.dedupeRestoreOnDetailClose = false;
    this.dedupeGroups = [];
    this.dedupeMarked = [];
  }

  // 点条目看详情：只隐藏弹窗（保留分组与勾选），详情关闭后自动恢复（F-123
  // 用户要求：能对比图册）。数据不清，回来继续处理。
  private hideDedupeForDetail(): void {
    this.dedupePanelVisible = false;
    this.dedupeRestoreOnDetailClose = true;
  }

  // 头部统计行：组数 / 标记数，让用户不看列表也知道进度。
  private dedupeHeaderSummary(): string {
    const groups = this.dedupeGroups.length.toString();
    const marked = this.dedupeMarked.length.toString();
    return 'Duplicate groups ' + groups + ' · marked ' + marked;
  }

  private buildDedupeGroups(): void {
    // F-123 用户反馈「完全是乱查重」：旧逻辑只按标题归一化分组——同一作者的
    // 系列作品、同名不同本（无修正/汉化变体）全部误判为重复。
    // 修复：分组 key = 标题归一化 + 页数。真重复（同一本重复下载/镜像）页数
    // 必然一致；系列不同本页数几乎不可能相同，自然分开。
    // 多维度判定（F-124 用户要求）：① gid 相同直接成组（最可靠信号，同一本的
    // 镜像/重复记录）；② 标题归一化 + 页数 + 文件大小三维度一致才判重——
    // 同系列不同本页数/大小几乎不可能完全一致。
    const map = new Map<string, DownloadInfo[]>();
    const order: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      const pages = item.total > 0 ? item.total : item.pages;
      let identityKey = '';
      if (item.gid > 0) {
        const gidOwner = this.gidToDedupeKey.get(item.gid);
        if (gidOwner !== undefined) {
          identityKey = gidOwner;
        } else {
          identityKey = 'gid:' + item.gid.toString();
          this.gidToDedupeKey.set(item.gid, identityKey);
        }
      }
      if (identityKey.length === 0) {
        const identity = normalizeGalleryIdentity(item.title);
        if (identity.length === 0) {
          continue;
        }
        identityKey = identity + '#' + (pages > 0 ? pages.toString() : 'unknown') +
          '#' + (item.fileSize > 0 ? item.fileSize.toString() : 'unknown');
      }
      if (!map.has(identityKey)) {
        map.set(identityKey, []);
        order.push(identityKey);
      }
      map.get(identityKey)!.push(item);
    }
    const groups: DownloadInfo[][] = [];
    for (let i = 0; i < order.length; i++) {
      const members = map.get(order[i])!;
      if (members.length > 1) {
        groups.push(members);
      }
    }
    this.dedupeGroups = groups;
    this.gidToDedupeKey = new Map<number, string>();
    // 默认标记：每组除第一条（保留）外的其余全部选中
    const marked: string[] = [];
    for (let i = 0; i < groups.length; i++) {
      for (let j = 1; j < groups[i].length; j++) {
        marked.push(groups[i][j].gid.toString() + ':' + groups[i][j].archiveUri);
      }
    }
    this.dedupeMarked = marked;
  }

  private dedupeKeyOf(item: DownloadInfo): string {
    return item.gid.toString() + ':' + item.archiveUri;
  }

  private toggleDedupeMark(item: DownloadInfo): void {
    const key = this.dedupeKeyOf(item);
    const index = this.dedupeMarked.indexOf(key);
    if (index >= 0) {
      const next = this.dedupeMarked.slice();
      next.splice(index, 1);
      this.dedupeMarked = next;
    } else {
      this.dedupeMarked = this.dedupeMarked.concat([key]);
    }
  }

  private isDedupeMarked(item: DownloadInfo): boolean {
    return this.dedupeMarked.indexOf(this.dedupeKeyOf(item)) >= 0;
  }

  private applyDedupeDelete(): void {
    let removed = 0;
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (this.isDedupeMarked(item)) {
        // 查重副本没有保留价值：记录与重复文件一起清掉。
        this.removeItem(item);
        removed++;
      }
    }
    this.buildDedupeGroups();
    this.showFloatingStatus('Deduped: removed ' + removed.toString() + ' duplicate items', 6000);
  }
  @State downloadJumpPanelVisible: boolean = false;
  @State downloadJumpPopupHeight: number = 0;
  @State downloadJumpDraft: string = '1';
  @State downloadJumpPageIndex: number = 0;
  @State viewportHeight: number = 0;
  @State translationVisibleStart: number = -1;
  @State translationVisibleEnd: number = -1;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  @StorageLink(TRANSLATION_ENABLED_KEY) translationEnabled: boolean = false;
  @StorageProp(TRANSLATION_BUTTONS_VISIBLE_KEY) translationButtonsVisible: boolean = true;
  @StorageProp(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY) @Watch('onHoldingHandSettingChanged')
  holdingHandSettingRevision: number = 0;
  @StorageProp(FLOATING_ACTION_SIDE_REVISION_KEY) @Watch('onFloatingActionSideSettingChanged')
  floatingActionSideRevision: number = 0;
  private downloadScroller: Scroller = new Scroller();
  private cardScrollAnchor: GalleryCardScrollAnchor = new GalleryCardScrollAnchor();
  private cardAreaByKey: Map<string, number> = new Map<string, number>();
  private splitDragStartWidth: number = 0;
  private downloadScrollOffset: number = 0;
  private lastChromeScrollOffset: number = 0;
  private chromeRestoreUntil: number = 0;
  private downloadFirstVisibleIndex: number = 0;
  private downloadBrowsePositionLoaded: boolean = false;
  private downloadBrowsePositionRestored: boolean = false;
  private restoringDownloadBrowsePosition: boolean = false;
  private floatingActionSideController: FloatingActionSideController = new FloatingActionSideController(
    (side: string): void => {
      this.animateFloatingActionSide(side);
    });
  private cellularWarningDialogOpen: boolean = false;
  private deleteConfirmationDialogOpen: boolean = false;
  // 删除确认改用自绘浮层：系统 showDialog 不跟应用主题，观感不沉浸。
  @State deleteConfirmVisible: boolean = false;
  // 通用确认层：替代系统 showDialog（系统弹窗不跟主题、无法 customStyle）。
  @State askVisible: boolean = false;
  @State askTitle: string = '';
  @State askMessage: string = '';
  @State askPrimaryLabel: string = '';
  @State askSecondaryLabel: string = '';
  @State askDanger: boolean = true;
  @State askWithCancel: boolean = true;
  private askKind: string = '';
  private askTextPayload: string = '';
  private askPaths: string[] = [];
  private askContinue: (() => void) | null = null;
  @State deleteConfirmCount: number = 0;
  @State deleteConfirmCloudAvailable: boolean = false;
  private downloadCardStates: Map<number, DownloadCardState> = new Map<number, DownloadCardState>();
  private downloadItemsByGid: Map<number, DownloadInfo> = new Map();
  private downloadProjection: DownloadListProjection = new DownloadListProjection();
  private downloadSceneActive: boolean = false;
  private translationVisibleItems: number[] = [];

  aboutToAppear(): void {
    this.downloadSceneActive = true;
    // 上次离开时若确认层还开着（切 tab、被系统回收），这里清掉，避免下次进来直接弹。
    this.deleteConfirmVisible = false;
    this.deleteConfirmationDialogOpen = false;
    applyAppChromeImmersiveMode();
    this.restoreEmbeddedContinuationIfPresent();
    this.floatingActionSideController.syncFromSettings();
    this.restoreNavigationCache();
    this.consumePendingDetailRestore();
    this.syncSceneContentWidthFromWindow();
    this.syncDownloadContentWidthFromWindow();
    markCurrentRouteRightPane(this.useSplitLayout());
    setActiveBackHandler(this.boundSystemBack);
    // 进入下载页自动触发云端匹配（F-115）：任务在全局服务上跑，弹窗只是观察者；
    // 幂等，重复进入/切界面都不会叠加。
    const matchContext = getAbilityContext();
    if (matchContext !== undefined && !downloadMatchService.isRunning() &&
      !downloadMatchService.hasAutoRanThisSession() && downloadMatchService.hasPendingWork()) {
      downloadMatchService.startMatch(matchContext);
    }
    // 切界面回来时组件重新挂载，@State 弹窗态是初始值：必须按服务当前状态
    // 立即恢复弹窗，否则弹窗消失约 1 秒后等下一次进度广播才重新出现。
    this.syncMatchDialogFromService();
    this.unsubscribeStore = ehDownloadStore.subscribe((items: DownloadInfo[], labels: DownloadLabel[]) => {
      this.items = items;
      this.labels = labels;
      this.downloadProjection.clearKeys();
      this.syncDownloadCardStates(items);
      if (this.selectedDownloadLabel !== DOWNLOAD_LABEL_FILTER_ALL && this.selectedDownloadLabel.length > 0 &&
        !ehDownloadStore.hasLabel(this.selectedDownloadLabel)) {
        this.selectedDownloadLabel = DOWNLOAD_LABEL_FILTER_ALL;
      }
      this.refreshDownloadRows();
      this.reportQueueSettledIfNeeded();
    }, (updates: DownloadProgress[]) => { this.updateDownloadProgress(updates); });
    this.unsubscribeDownloadManager = ehDownloadManager.subscribe((status: string) => {
      this.statusText = status;
      if (status.indexOf('limit') >= 0) {
        // 配额限流比较罕见且需要用户等待，单独弹一次即可；完成/失败交给队列汇总弹一次。
        this.showStatusHint(uiStatusText(status), 3000);
      } else if (status.indexOf('failed') >= 0 || status.indexOf('Failed') >= 0) {
        const key = downloadFailureReasonKey(status);
        this.runFailureReasons.set(key, (this.runFailureReasons.get(key) ?? 0) + 1);
      }
    });
    this.refreshSearchSuggestions();
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.ensureLoaded(context).then(() => {
        this.sortMode = normalizeDownloadSortMode(appSettingsStore.getValue(DOWNLOAD_SORT_SETTING_KEY, 'Default'));
        this.refreshDownloadRows();
      }).catch(() => {});
      ehSearchHistoryStore.load(context).then(() => {
        this.refreshSearchSuggestions();
      }).catch(() => {});
    }
    this.prepareDownloadBrowsePosition();
    this.loadDownloads();
    setTimeout(() => {
      this.syncSceneContentWidthFromWindow();
      this.syncDownloadContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    // 单槽守卫清空：否则残留闭包里 showDetail 冻结为 true，会吞掉全局返回点恢复
    // 之前的所有返回键（F-105 问题3 场景4 的根因）。
    clearActiveBackHandler(this.boundSystemBack);
    // dock 切走时正开着云端详情：记入全局返回点（F-105 问题3 简单全局版）。
    // 必须挂卸载钩子：Index 用 if/else 条件渲染场景，切走即卸载，@Prop/@StorageProp
    // 的变化回调和卸载竞态不可靠，aboutToDisappear 是唯一保证执行的时机。
    if (this.showDetail && this.detailLink.url.length > 0) {
      AppStorage.setOrCreate(REMEMBERED_DETAIL_URL_KEY, this.detailLink.url);
      AppStorage.setOrCreate(REMEMBERED_DETAIL_SITE_KEY, this.detailLink.site === GallerySite.Ex ? 1 : 0);
      AppStorage.setOrCreate(REMEMBERED_DETAIL_ROUTE_KEY, GalleryRoute.Downloads.toString());
    }
    this.stopDownloadListWork();
    this.rememberDownloadScrollOffset();
    ehBrowsePositionStore.flush();
    this.cardScrollAnchor.clear();
    this.saveNavigationCache();
    this.unsubscribeStore();
    this.unsubscribeDownloadManager();
    this.floatingActionSideController.dispose();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  @StorageProp(PENDING_DETAIL_RESTORE_REVISION_KEY) @Watch('onPendingDetailRestoreChange') pendingDetailRestoreRevision: number = 0;

  onPendingDetailRestoreChange(): void {
    this.consumePendingDetailRestore();
  }

  // 全局返回点恢复：pending 目标是下载页才消费；本地面板（无云端链接）不在记忆范围。
  private consumePendingDetailRestore(): void {
    const pendingRoute = AppStorage.get<string>(PENDING_DETAIL_RESTORE_ROUTE_KEY) ?? '';
    if (pendingRoute !== GalleryRoute.Downloads.toString()) {
      return;
    }
    const pendingUrl = AppStorage.get<string>(PENDING_DETAIL_RESTORE_URL_KEY) ?? '';
    AppStorage.setOrCreate(PENDING_DETAIL_RESTORE_URL_KEY, '');
    AppStorage.setOrCreate(PENDING_DETAIL_RESTORE_ROUTE_KEY, '');
    if (pendingUrl.length === 0) {
      return;
    }
    const siteIndex = AppStorage.get<number>(PENDING_DETAIL_RESTORE_SITE_KEY) ?? 0;
    this.openDetailFromUrl(pendingUrl, siteIndex);
  }

  // 按 URL 重建云端详情层，状态设置与 openDetailNow 的云端分支一致。
  private openDetailFromUrl(url: string, siteIndex: number): void {
    const link = createGalleryDetailLinkFromUrl(url, siteIndex === 1 ? GallerySite.Ex : GallerySite.E);
    if (link === null) {
      return;
    }
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.localDetailGid = -1;
    this.showDetail = true;
    this.syncDownloadContentWidthForCurrentLayout();
    markCurrentRouteRightPane(this.useSplitLayout());
    this.detailLink = link;
    this.detail = initialDetailForLink(link);
    this.detailRequestUrl = link.url;
    this.saveNavigationCache();
  }

  private handleSystemBack(): boolean {
    // 云端匹配弹窗不允许取消：任务必须跑到收敛，Back 直接吞掉（F-115 用户要求）。
    if (this.matchDialogVisible) {
      return true;
    }
    // 详情从查重面板进入时，Back 先关详情回到查重面板（F-120 用户要求：
    // 点条目直达详情、侧滑返回回到查重），详情关闭后查重面板仍然在。
    if (this.showDetail) {
      if (runDetailBackHandler()) {
        return true;
      }
      this.closeDetail();
      return true;
    }
    // 查重面板开着时 Back 只关面板。
    if (this.dedupePanelVisible) {
      this.closeDedupePanel();
      return true;
    }
    // 自绘确认层要先吃掉返回，否则会直接退出页面、状态还留着。
    if (this.deleteConfirmVisible) {
      this.closeDeleteConfirm();
      return true;
    }
    if (this.sortPanelVisible) {
      this.sortPanelVisible = false;
      return true;
    }
    if (this.downloadLabelEditDialogVisible) {
      this.downloadLabelEditDialogVisible = false;
      return true;
    }
    if (this.defaultDownloadLabelDialogVisible) {
      this.defaultDownloadLabelDialogVisible = false;
      return true;
    }
    if (this.moveDownloadLabelDialogVisible) {
      this.moveDownloadLabelDialogVisible = false;
      return true;
    }
    if (this.downloadLabelManagerVisible) {
      this.closeDownloadLabelManager();
      return true;
    }
    if (this.downloadLabelDrawerVisible) {
      this.closeDownloadLabelDrawer();
      return true;
    }
    if (this.statusFilterPanelVisible) {
      this.closeDownloadStatusPanel();
      return true;
    }
    if (this.advancedPanelVisible) {
      this.closeAdvancedPanel();
      return true;
    }
    if (this.downloadJumpPanelVisible) {
      this.downloadJumpPanelVisible = false;
      return true;
    }
    if (this.showReader) {
      this.closeEmbeddedReader();
      return true;
    }
    if (this.useSplitLayout() && this.activeSplitPane === SPLIT_PANE_FOCUS_RIGHT && this.showDetail) {
      if (runDetailBackHandler()) {
        return true;
      }
      this.closeDetail();
      return true;
    }
    if (this.downloadSelectionCount() > 0) {
      this.clearDownloadSelection();
      return true;
    }
    if (this.searchBarVisible) {
      this.closeDownloadSearchBar();
      return true;
    }
    if (this.showTagSearch) {
      this.closeTagSearch();
      return true;
    }
    if (this.showDetail) {
      if (runDetailBackHandler()) {
        return true;
      }
      this.closeDetail();
      return true;
    }
    return false;
  }

  private resetToTopLevel(): void {
    if (this.showReader) {
      leaveEmbeddedReaderFullscreen();
    }
    this.clearDownloadSelection();
    this.searchBarVisible = false;
    this.advancedPanelVisible = false;
    this.downloadActionsExpanded = false;
    this.statusFilterPanelVisible = false;
    this.sortPanelVisible = false;
    this.downloadLabelDrawerVisible = false;
    this.downloadLabelDrawerOffsetX = SIDE_PANEL_WIDTH;
    this.downloadLabelDrawerOverlayOpacity = 0;
    this.downloadLabelManagerVisible = false;
    this.defaultDownloadLabelDialogVisible = false;
    this.moveDownloadLabelDialogVisible = false;
    this.downloadLabelEditDialogVisible = false;
    this.downloadJumpPanelVisible = false;
    this.showTagSearch = false;
    this.showReader = false;
    this.showDetail = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.restoreDetailWithFade = false;
    this.syncDownloadContentWidthForCurrentLayout();
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailRequestUrl = '';
    this.tagSearchTitle = 'Search';
    this.tagSearchKeyword = '';
    this.tagSearchMode = ListMode.Tag;
    this.tagSearchCategory = GalleryCategory.None;
    this.tagSearchImagePath = '';
    this.tagSearchCoverSource = undefined;
    this.tagSearchImageUseSimilarity = false;
    this.tagSearchImageOnlyCovers = false;
    this.tagSearchImageShowExpunged = false;
    this.restoreBackHandler();
    this.clearNavigationCache();
  }

  private toggleAdvancedPanel(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = !this.advancedPanelVisible;
    });
  }

  private closeAdvancedPanel(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = false;
    });
  }

  private restoreNavigationCache(): void {
    if (downloadNavigationCache === null) {
      return;
    }
    const cache = downloadNavigationCache;
    this.showDetail = cache.showDetail;
    this.activeSplitPane = normalizeSplitPaneFocus(cache.activeSplitPane, cache.showDetail);
    this.restoreDetailWithFade = cache.showDetail && shouldFadeRestoredRightPane();
    this.detailLink = cloneDownloadDetailLink(cache.detailLink);
    this.detail = cloneGalleryDetail(cache.detail);
    this.detailRequestUrl = cache.detailRequestUrl;
    this.localDetailGid = cache.localDetailGid === undefined ? -1 : cache.localDetailGid;
    this.showTagSearch = cache.showTagSearch;
    this.tagSearchTitle = cache.tagSearchTitle;
    this.tagSearchKeyword = cache.tagSearchKeyword;
    this.tagSearchMode = cache.tagSearchMode;
    this.tagSearchCategory = cache.tagSearchCategory === undefined ? GalleryCategory.None : cache.tagSearchCategory;
    this.tagSearchImagePath = cache.tagSearchImagePath;
    this.tagSearchCoverSource = cache.tagSearchCoverSource;
    this.tagSearchImageUseSimilarity = cache.tagSearchImageUseSimilarity;
    this.tagSearchImageOnlyCovers = cache.tagSearchImageOnlyCovers;
    this.tagSearchImageShowExpunged = cache.tagSearchImageShowExpunged;
  }

  private saveNavigationCache(): void {
    downloadNavigationCache = {
      activeSplitPane: this.activeSplitPane,
      showDetail: this.showDetail,
      restoreDetailWithFade: this.restoreDetailWithFade,
      detailLink: cloneDownloadDetailLink(this.detailLink),
      detail: cloneGalleryDetail(this.detail),
      detailRequestUrl: this.detailRequestUrl,
      localDetailGid: this.localDetailGid,
      showTagSearch: this.showTagSearch,
      tagSearchTitle: this.tagSearchTitle,
      tagSearchKeyword: this.tagSearchKeyword,
      tagSearchMode: this.tagSearchMode,
      tagSearchCategory: this.tagSearchCategory,
      tagSearchImagePath: this.tagSearchImagePath,
      tagSearchCoverSource: this.tagSearchCoverSource,
      tagSearchImageUseSimilarity: this.tagSearchImageUseSimilarity,
      tagSearchImageOnlyCovers: this.tagSearchImageOnlyCovers,
      tagSearchImageShowExpunged: this.tagSearchImageShowExpunged
    };
  }

  private clearNavigationCache(): void {
    downloadNavigationCache = null;
  }

  private clearDownloadSelection(): void {
    this.selectedDownloadGids = '';
    this.downloadActionsExpanded = false;
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private floatingToolbarHeight(): number {
    return this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth);
  }

  private downloadContentStartOffset(): number {
    return galleryListTopInset(this.floatingToolbarHeight());
  }

  private downloadQueueCounts(): number[] {
    let downloading = 0;
    let waiting = 0;
    let done = 0;
    let total = 0;
    let speed = 0;
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      const display = downloadDisplayState(item);
      if (display !== DownloadDisplayState.Active && display !== DownloadDisplayState.Queued) {
        continue;
      }
      if (display === DownloadDisplayState.Active) {
        downloading++;
        speed += Math.max(0, item.speed);
      } else {
        waiting++;
      }
      const itemTotal = item.total > 0 ? item.total : item.pages;
      done += Math.max(0, item.finished);
      total += Math.max(0, itemTotal);
    }
    return [downloading, waiting, done, total, speed];
  }

  // 队列从「有活动」回到「空闲」时，用这一轮的状态差值弹一次汇总，避免逐条失败刷屏。
  private reportQueueSettledIfNeeded(): void {
    const counts = this.downloadQueueCounts();
    const active = counts[0] + counts[1] > 0;
    let failed = 0;
    let finished = 0;
    for (let i = 0; i < this.items.length; i++) {
      const display = downloadDisplayState(this.items[i]);
      if (display === DownloadDisplayState.Failed) {
        failed++;
      } else if (display === DownloadDisplayState.Done) {
        finished++;
      }
    }
    if (active && !this.lastQueueActive) {
      this.runStartFailed = failed;
      this.runStartFinished = finished;
      this.runFailureReasons.clear();
      this.suppressSettleReport = false;
    } else if (!active && this.lastQueueActive) {
      const newFailed = failed - this.runStartFailed;
      const newFinished = finished - this.runStartFinished;
      if (!this.suppressSettleReport && (newFailed > 0 || newFinished > 0)) {
        // 末条失败的原因在其 setState 之后才 publish，稍等一拍再取，避免漏掉最后一条。
        setTimeout(() => {
          this.showSettleSummary(newFinished, newFailed);
        }, 80);
      }
    }
    this.lastQueueActive = active;
  }

  private showSettleSummary(finished: number, failed: number): void {
    const parts: string[] = [];
    if (finished > 0) {
      parts.push(uiText('Download completed') + ' ' + finished.toString());
    }
    if (failed > 0) {
      parts.push(uiText('Failed') + ' ' + failed.toString());
    }
    this.settleSummaryTitle = parts.join(' · ');
    const lines: string[] = [];
    this.runFailureReasons.forEach((count: number, key: string) => {
      lines.push(uiText(key) + ' ×' + count.toString());
    });
    this.settleSummaryLines = lines;
    this.settleSummaryVisible = true;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.settleSummaryVisible = false;
      });
    }, 4200);
  }

  private downloadQueueSummary(): string {
    const counts = this.downloadQueueCounts();
    const parts: string[] = [];
    if (counts[0] > 0) {
      parts.push(uiText('Downloading') + ' ' + counts[0].toString());
    }
    if (counts[1] > 0) {
      parts.push(uiText('Waiting') + ' ' + counts[1].toString());
    }
    return parts.join(' · ');
  }

  private downloadQueueProgress(): number {
    const counts = this.downloadQueueCounts();
    if (counts[3] <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round(counts[2] * 100 / counts[3])));
  }

  private downloadQueueSpeedText(): string {
    const counts = this.downloadQueueCounts();
    return counts[4] > 0 ? downloadSizeText(counts[4]) + '/s' : '';
  }

  // 下载行上的进度文案：完成打勾，未完成显示「已下/总数」，其余仍显示阅读进度。
  private downloadRowProgressLabel(item: DownloadInfo): string {
    const display = downloadDisplayState(item);
    if (display === DownloadDisplayState.Missing) {
      return uiText('Files missing');
    }
    if (display === DownloadDisplayState.Done) {
      const pageTotal = item.total > 0 ? item.total : item.pages;
      // 本地图册没有语言/评分这些元数据，只写一个 "✓" 等于什么都没说，页数在这里补上。
      if (item.token.length === 0 && pageTotal > 0) {
        return '✓ · ' + pageTotal.toString() + ' P';
      }
      return '✓';
    }
    if (display === DownloadDisplayState.Queued || display === DownloadDisplayState.Active ||
      display === DownloadDisplayState.Failed) {
      const total = item.total > 0 ? item.total : item.pages;
      if (total <= 0) {
        return '';
      }
      return Math.max(0, item.finished).toString() + '/' + total.toString();
    }
    return '';
  }

  private downloadListViewportHeight(): number {
    return galleryListViewportHeight(this.viewportHeight);
  }

  private advancedPanelMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 520;
    }
    return Math.max(360, this.viewportHeight - this.floatingToolbarHeight() - 28);
  }

  private downloadToolActionsMaxHeight(): number {
    const reservedTop = this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth) + 8;
    const reservedBottom = APP_DOCK_FAB_RESERVE + this.bottomAvoidHeight;
    return floatingActionAvailableHeight(this.viewportHeight, reservedTop, reservedBottom);
  }

  onHoldingHandSettingChanged(): void {
    this.floatingActionSideController.syncFromSettings();
  }

  private restoreEmbeddedContinuationIfPresent(): void {
    const pending = peekPendingContinuationSnapshot();
    if (pending === null || pending.kind !== 'embedded_reader' ||
      pending.route !== GalleryRoute.Downloads.toString() || pending.readerSession === undefined) {
      return;
    }
    const session = pending.readerSession;
    if (session.detail.gid <= 0 || session.detail.token.length === 0) {
      return;
    }
    readerSessionStore.setSession(session);
    this.detail = cloneGalleryDetail(session.detail);
    this.detailLink = createGalleryDetailLink(session.detail.gid, session.detail.token,
      session.detail.title, session.site, session.detailRequestUrl);
    this.detailRequestUrl = session.detailRequestUrl;
    this.statusText = session.statusText;
    this.showDetail = true;
    this.showReader = true;
    takePendingContinuationSnapshot();
  }

  onFloatingActionSideSettingChanged(): void {
    this.floatingActionSideController.handleManualSettingChanged();
  }

  private animateFloatingActionSide(side: string): void {
    if (side === this.floatingActionSide) {
      return;
    }
    // 与画廊工具栏使用同一停靠动效，连续换手时继承当前动画速度。
    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 1) }, () => {
      this.floatingActionSide = side;
    });
  }

  private updateToolbarForScrollFrame(scrollOffset: number): number {
    // 顶栏常驻，不再跟随滚动位移。
    return scrollOffset;
  }

  private loadDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.items = ehDownloadStore.getItems();
      this.downloadProjection.clearKeys();
      this.syncDownloadCardStates();
      this.refreshDownloadRows();
      return;
    }

    ehDownloadStore.ensureLoaded(context).then(() => {
      this.refreshDownloadRows();
      this.statusText = this.items.length.toString() + ' download items';
      this.backfillLocalGalleryPages(context);
      if (ehDownloadManager.hasWaitingDownloads()) {
        this.startGlobalDownloadQueue();
      }
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
      this.downloadProjection.clearKeys();
      this.syncDownloadCardStates();
      this.refreshDownloadRows();
    });
  }

  private persistDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehDownloadStore.save(context).catch((error: Error) => {
      this.statusText = 'Download save failed: ' + error.message;
    });
  }

  private showFloatingStatus(message: string, durationMs: number = 2200): void {
    this.statusText = message;
    showRaisedToast(this.getUIContext(), uiStatusText(message), durationMs);
  }

  private prepareDownloadBrowsePosition(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehBrowsePositionStore.ensureLoaded(context).then(() => {
      const position = ehBrowsePositionStore.getDownloadPosition();
      this.downloadScrollOffset = position.offset;
      this.downloadFirstVisibleIndex = position.anchorIndex;
      this.downloadBrowsePositionLoaded = true;
      this.restoreDownloadScrollOffset();
    }).catch(() => {});
  }

  private openDownloadLabelDrawer(): void {
    if (this.downloadLabelDrawerVisible) {
      return;
    }
    this.downloadActionsExpanded = false;
    this.downloadLabelDrawerVisible = true;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.downloadLabelDrawerOffsetX = 0;
      this.downloadLabelDrawerOverlayOpacity = 0.45;
    });
  }

  private closeDownloadLabelDrawer(): void {
    if (!this.downloadLabelDrawerVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.downloadLabelDrawerOffsetX = SIDE_PANEL_WIDTH;
      this.downloadLabelDrawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.downloadLabelDrawerOffsetX > SIDE_PANEL_WIDTH - 40) {
        this.downloadLabelDrawerVisible = false;
      }
    }, 220);
  }

  private downloadLabelDrawerLeft(): number {
    return sidePanelLeft(this.downloadListOverlayWidth(), this.windowContentWidthVp());
  }

  private downloadListOverlayWidth(): number {
    return this.useSplitLayout() ? this.splitListPaneWidth() : this.availableSceneWidth();
  }

  private downloadSideOverlayWidth(): number {
    return this.useSplitLayout() ? this.splitSidePaneWidth() : this.availableSceneWidth();
  }

  private downloadSideOverlayLeft(): number {
    return this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0;
  }

  private handleOpenDownloadLabelDrawerPan(event: GestureEvent | undefined): void {
    if (this.downloadLabelDrawerVisible || this.showReader || this.showTagSearch) {
      return;
    }
    if (shouldOpenSidePanel(event)) {
      this.openDownloadLabelDrawer();
    }
  }

  private selectDownloadLabel(label: string): void {
    this.selectedDownloadLabel = label;
    this.downloadJumpPageIndex = 0;
    this.downloadScrollOffset = 0;
    this.refreshDownloadRows();
    this.closeDownloadLabelDrawer();
  }

  private openDefaultDownloadLabelDialog(): void {
    this.closeDownloadLabelDrawer();
    this.defaultDownloadLabelDialogVisible = true;
  }

  private selectDefaultDownloadLabel(label: string): void {
    saveDefaultDownloadLabelChoice(label === DOWNLOAD_LABEL_OPTION_ASK ? DOWNLOAD_LABEL_OPTION_ASK : label);
    this.defaultDownloadLabelDialogVisible = false;
    this.showFloatingStatus('Default download label updated');
  }

  private openDownloadLabelManager(): void {
    this.closeDownloadLabelDrawer();
    this.downloadLabelManagerVisible = true;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.syncDownloadContentWidthForCurrentLayout();
  }

  private closeDownloadLabelManager(): void {
    this.downloadLabelManagerVisible = false;
    this.activeSplitPane = this.showDetail ? SPLIT_PANE_FOCUS_RIGHT : SPLIT_PANE_FOCUS_LEFT;
    this.syncDownloadContentWidthForCurrentLayout();
  }

  private openAddDownloadLabel(): void {
    this.downloadLabelEditValue = '';
    this.downloadLabelEditDialogVisible = true;
  }

  private renameDownloadLabel(label: string, rawValue: string): void {
    const value = rawValue.trim();
    if (value.length === 0) {
      this.showFloatingStatus('Label name cannot be empty');
      return;
    }
    if (value === label) {
      return;
    }
    const selectedWasEditing = this.selectedDownloadLabel === label;
    const defaultWasEditing = defaultDownloadLabelChoice() === label;
    if (!ehDownloadStore.renameLabel(label, value)) {
      this.showFloatingStatus('Download label already exists');
      return;
    }
    if (selectedWasEditing) {
      this.selectedDownloadLabel = value;
    }
    if (defaultWasEditing) {
      saveDefaultDownloadLabelChoice(value);
    }
    this.persistDownloads();
  }

  private confirmDownloadLabelEdit(): void {
    const value = this.downloadLabelEditValue.trim();
    if (value.length === 0) {
      this.showFloatingStatus('Label name cannot be empty');
      return;
    }
    if (!ehDownloadStore.addLabel(value)) {
      this.showFloatingStatus('Download label already exists');
      return;
    }
    this.downloadLabelEditDialogVisible = false;
    this.persistDownloads();
  }

  private moveDownloadLabel(from: number, to: number): void {
    if (ehDownloadStore.moveLabel(from, to)) {
      this.persistDownloads();
    }
  }

  // ---- 自绘确认层 ----
  private askConfirm(kind: string, title: string, message: string, primary: string,
    secondary: string, danger: boolean, withCancel: boolean): void {
    this.askKind = kind;
    this.askTitle = title;
    this.askMessage = message;
    this.askPrimaryLabel = primary;
    this.askSecondaryLabel = secondary;
    this.askDanger = danger;
    this.askWithCancel = withCancel;
    this.askVisible = true;
  }

  private dismissAsk(): void {
    const kind = this.askKind;
    this.askVisible = false;
    this.askKind = '';
    this.askTextPayload = '';
    this.askPaths = [];
    this.askContinue = null;
    if (kind === 'removeLocalGallery') {
      this.deleteConfirmationDialogOpen = false;
    }
    if (kind === 'mobileData') {
      this.cellularWarningDialogOpen = false;
    }
  }

  private runAskPrimary(): void {
    const kind = this.askKind;
    const text = this.askTextPayload;
    const paths = this.askPaths;
    const cont = this.askContinue;
    this.dismissAsk();
    if (kind === 'deleteLabel') {
      this.applyDeleteDownloadLabel(text);
    } else if (kind === 'mobileData') {
      confirmCellularNetworkWarningForSession();
      if (cont !== null) {
        cont();
      }
    } else if (kind === 'clearFailed') {
      this.applyClearFailedDownloads();
    } else if (kind === 'removeLocalGallery') {
      this.applyRemoveLocalGalleryByGid(text);
    } else if (kind === 'zipDelete') {
      const removed = ehDownloadFileStore.removeFiles(paths);
      this.showFloatingStatus('Deleted processed ZIP archives: ' + removed.toString());
    }
  }

  private runAskSecondary(): void {
    const kind = this.askKind;
    const text = this.askTextPayload;
    this.dismissAsk();
    if (kind === 'mobileData') {
      this.statusText = 'Download waits for Wi-Fi or confirmation';
    } else if (kind === 'removeLocalGallery') {
      // 只删列表记录，本地文件保留（用户可重新扫描登记回来）。
      const gid = Number.parseInt(text);
      if (!Number.isNaN(gid)) {
        ehDownloadStore.removeGallery(gid);
        this.persistDownloads();
        this.closeDetail();
        this.showFloatingStatus('Removed 1 record (files kept)');
      }
    }
  }

  private runAskCancel(): void {
    const kind = this.askKind;
    this.dismissAsk();
    if (kind === 'mobileData') {
      this.statusText = 'Download waits for Wi-Fi or confirmation';
    }
  }

  private applyDeleteDownloadLabel(label: string): void {
    const wasDefault = defaultDownloadLabelChoice() === label;
    ehDownloadStore.removeLabel(label);
    if (this.selectedDownloadLabel === label) {
      this.selectedDownloadLabel = DOWNLOAD_LABEL_FILTER_ALL;
    }
    if (wasDefault) {
      saveDefaultDownloadLabelChoice(DOWNLOAD_LABEL_OPTION_ASK);
    }
    this.persistDownloads();
  }

  private applyClearFailedDownloads(): void {
    const failed = collectFailedDownloads(this.items);
    for (let i = 0; i < failed.length; i++) {
      this.removeItem(failed[i]);
    }
    this.clearDownloadSelection();
    this.showFloatingStatus('Cleared ' + failed.length.toString() + ' failed downloads');
  }

  private applyRemoveLocalGalleryByGid(gidText: string): void {
    const gid = Number.parseInt(gidText);
    let target: DownloadInfo | null = null;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        target = this.items[i];
        break;
      }
    }
    this.closeDetail();
    if (target !== null) {
      this.removeItem(target);
      this.showFloatingStatus('Removed 1 local gallery');
    }
  }

  private confirmDeleteDownloadLabel(label: string): void {
    const count = ehDownloadStore.labelItemCount(label);
    this.askTextPayload = label;
    this.askConfirm('deleteLabel', uiText('Delete label'),
      uiText('Downloads in this label will be moved to Default') + ' (' + count.toString() + ')',
      uiText('Delete'), '', true, true);
  }

  private openMoveSelectedDownloadLabel(): void {
    this.downloadActionsExpanded = false;
    this.moveDownloadLabelDialogVisible = true;
  }

  private moveSelectedDownloadsToLabel(label: string): void {
    const selected = this.selectedDownloadItems();
    const gids: number[] = [];
    for (let i = 0; i < selected.length; i++) {
      gids.push(selected[i].gid);
    }
    const changed = ehDownloadStore.setLabels(gids, label);
    this.moveDownloadLabelDialogVisible = false;
    this.clearDownloadSelection();
    this.persistDownloads();
    this.showFloatingStatus('Moved downloads to label: ' + changed.toString());
  }

  private showBlockingBusy(message: string): void {
    this.blockingBusyMessage = message;
    this.blockingBusyProgressText = '';
    this.blockingBusyVisible = true;
  }

  private hideBlockingBusy(): void {
    this.blockingBusyVisible = false;
    this.blockingBusyMessage = 'Loading...';
    this.blockingBusyProgressText = '';
  }

  private computeVisibleDownloadItems(revision: number): Promise<DownloadInfo[] | undefined> {
    const statusFilters = this.statusFilters.slice();
    const label = this.selectedDownloadLabel;
    const category = this.categoryFilter;
    const mode = this.sortMode;
    const options = this.downloadSearchOptions();
    const query = this.query;
    return this.downloadProjection.project(this.items, mode, revision, (chunk: DownloadInfo[]): DownloadInfo[] => {
      const candidates = filterDownloadItems(chunk, '', statusFilters, label, mode,
        category, false);
      return candidates.filter((item: DownloadInfo): boolean => galleryMatchesLocalSearch(item, query, options));
    });
  }

  private applyDownloadSort(value: string): void {
    this.sortMode = normalizeDownloadSortMode(value);
    this.sortPanelVisible = false;
    this.downloadJumpPageIndex = 0;
    this.downloadScrollOffset = 0;
    this.cardScrollAnchor.clear();
    this.refreshDownloadRows();
    this.downloadFirstVisibleIndex = 0;
    this.toolbarOffsetY = 0;
    setTimeout(() => {
      try {
        this.downloadScroller.scrollTo({ xOffset: 0, yOffset: 0 });
        this.rememberDownloadScrollOffset(0);
      } catch (_error) {
      }
    }, 0);
    appSettingsStore.setValue(DOWNLOAD_SORT_SETTING_KEY, this.sortMode);
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch(() => {});
    }
  }

  private downloadSearchOptions(): LocalGallerySearchOptions {
    return {
      mode: this.searchMode,
      category: this.searchCategory,
      advancedEnabled: this.advancedSearchEnabled,
      advancedPanelOpened: this.advancedPanelVisible || this.advancedSearchEnabled || this.searchCategory !== GalleryCategory.None ||
        this.minRating > 0,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating
    };
  }

  private applyDownloadSearch(): void {
    this.query = normalizeSubmittedSearchKeyword(this.query);
    this.searchSubmitted = true;
    this.downloadJumpPageIndex = 0;
    this.downloadScrollOffset = 0;
    // 下载页是本地过滤，没有网络请求可失败：把「过滤真的跑完且有命中」
    // 当作成功边界，避免把点错的空词写进历史。
    const submitted = this.query;
    this.refreshDownloadRows((items: DownloadInfo[]) => {
      if (submitted.length > 0 && items.length > 0) {
        recordSearchHistory(submitted);
      }
    });
  }

  private openDownloadSearchSuggestions(): void {
    this.searchSubmitted = false;
    this.downloadJumpPageIndex = 0;
    this.refreshSearchSuggestions();
  }

  private openDownloadSearchBar(): void {
    this.searchBarVisible = true;
    this.openDownloadSearchSuggestions();
  }

  private closeDownloadSearchBar(): void {
    this.searchBarVisible = false;
    this.searchSubmitted = true;
    this.advancedPanelVisible = false;
    this.clearDownloadSearchFilters();
    this.downloadJumpPageIndex = 0;
    this.refreshDownloadRows();
  }

  private showDownloadStatusHint(): void {
    this.showStatusHint(uiText('Current status filter') + ': ' + this.downloadStatusSummary(this.statusFilters), 1500);
  }

  private showStatusHint(message: string, durationMs: number = 1500): void {
    this.statusHintText = message;
    this.statusHintVisible = true;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.statusHintVisible = false;
      });
    }, durationMs);
  }

  private downloadStatusSummary(statuses: string[]): string {
    if (statuses.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length) {
      return uiText('All');
    }
    if (statuses.length === 0) {
      return '—';
    }
    const labels: string[] = [];
    for (let i = 0; i < DOWNLOAD_STATUS_FILTER_OPTIONS.length; i++) {
      const status = DOWNLOAD_STATUS_FILTER_OPTIONS[i];
      if (statuses.indexOf(status) >= 0) {
        labels.push(uiText(status));
      }
    }
    return labels.join(', ');
  }

  private openDownloadStatusPanel(): void {
    this.downloadActionsExpanded = false;
    this.downloadJumpPanelVisible = false;
    this.statusFilterDraft = this.statusFilters.slice();
    this.statusFilterPanelVisible = true;
  }

  private closeDownloadStatusPanel(): void {
    this.statusFilterPanelVisible = false;
  }

  private applyDownloadStatusFilter(): void {
    this.statusFilters = this.statusFilterDraft.slice();
    this.statusFilterPanelVisible = false;
    this.downloadJumpPageIndex = 0;
    this.downloadScrollOffset = 0;
    this.refreshDownloadRows();
    this.showDownloadStatusHint();
  }

  private clearDownloadSearchFilters(): void {
    this.query = '';
    this.searchMode = ListMode.Normal;
    this.searchCategory = GalleryCategory.None;
    this.advancedSearchEnabled = false;
    this.advanceSearch = DEFAULT_ADVANCE_SEARCH;
    this.minRating = -1;
    this.selectedTagNamespaces = [];
    this.refreshSearchSuggestions([]);
  }

  private updateDownloadKeyword(value: string): void {
    this.query = value;
    this.searchSubmitted = false;
    this.downloadJumpPageIndex = 0;
    this.refreshSearchSuggestions();
    this.refreshDownloadRows();
  }

  private refreshSearchSuggestions(namespaces: string[] = this.selectedTagNamespaces): void {
    this.searchSuggestionItems = buildSearchSuggestions(this.query, 0, namespaces);
    this.searchSuggestionRevision++;
  }

  private selectedTagNamespaceKey(): string {
    return sortedStringKey(this.selectedTagNamespaces);
  }

  private toggleTagNamespace(namespace: string): void {
    const next = toggleStringValue(this.selectedTagNamespaces, namespace);
    this.selectedTagNamespaces = next;
    this.refreshSearchSuggestions(next);
  }

  private applySearchSuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind === 'tag') {
      this.updateDownloadKeyword(applyTagSuggestionToKeyword(this.query, suggestion.query, suggestion.namespace));
      this.searchMode = ListMode.Tag;
      return;
    }
    this.updateDownloadKeyword(suggestion.query);
  }

  private downloadJumpTotalPages(): number {
    const count = this.visibleItems.length;
    return count <= 0 ? 0 : Math.ceil(count / DOWNLOAD_JUMP_PAGE_SIZE);
  }

  private syncDownloadJumpDraft(): void {
    const total = this.downloadJumpTotalPages();
    const safeIndex = total > 0 ? Math.max(0, Math.min(this.downloadJumpPageIndex, total - 1)) : 0;
    this.downloadJumpPageIndex = safeIndex;
    this.downloadJumpDraft = (safeIndex + 1).toString();
  }

  private openDownloadJumpPanel(): void {
    if (this.downloadJumpTotalPages() <= 1) {
      this.statusText = 'No other page to jump to';
      return;
    }
    this.downloadActionsExpanded = false;
    this.syncDownloadJumpDraft();
    this.downloadJumpPanelVisible = true;
  }

  private closeDownloadJumpPanel(): void {
    this.downloadJumpPanelVisible = false;
  }

  private submitDownloadJump(): void {
    const parsed = Number.parseInt(this.downloadJumpDraft);
    const total = this.downloadJumpTotalPages();
    if (Number.isNaN(parsed) || parsed <= 0 || total <= 0) {
      this.syncDownloadJumpDraft();
      return;
    }
    const targetPage = Math.max(1, Math.min(parsed, total));
    const targetItemIndex = (targetPage - 1) * DOWNLOAD_JUMP_PAGE_SIZE;
    const rowIndex = Math.floor(targetItemIndex / Math.max(1, this.downloadColumnCount()));
    this.downloadJumpPageIndex = targetPage - 1;
    this.downloadJumpDraft = targetPage.toString();
    this.downloadScrollOffset = 0;
    this.toolbarOffsetY = 0;
    this.syncToolbarOffsetState();
    try {
      this.downloadScroller.scrollToIndex(rowIndex + 1);
      this.statusText = 'Page ' + targetPage.toString() + '/' + total.toString();
    } catch (error) {
      this.statusText = 'Jump failed: ' + String(error);
    }
  }

  private selectedKey(gid: number): string {
    return '|' + gid.toString() + '|';
  }

  private downloadSelectionCount(): number {
    if (this.selectedDownloadGids.length === 0) {
      return 0;
    }
    const parts = this.selectedDownloadGids.split('|');
    let count = 0;
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        count++;
      }
    }
    return count;
  }

  private isDownloadSelected(gid: number): boolean {
    return this.selectedDownloadGids.indexOf(this.selectedKey(gid)) >= 0;
  }

  private toggleDownloadSelection(gid: number): void {
    const key = this.selectedKey(gid);
    const selected = this.selectedDownloadGids;
    const removing = selected.indexOf(key) >= 0;
    const next = removing ? selected.replace(key, '|') : selected + key;
    const hasSelection = /\d/.test(next);
    this.selectedDownloadGids = hasSelection ? next : '';
    if (!removing || !hasSelection) {
      this.downloadActionsExpanded = hasSelection;
    }
    if (hasSelection) {
      const count = this.downloadSelectionCount();
      this.showStatusHint(uiText('Selected') + ' ' + count.toString() + ' ' + uiText('items'), 1400);
    }
  }

  // 缩略图直达阅读器、标题进详情页；选中态优先切换勾选。
  // 本地文件已完整（state=Finish，或 finished>=total 但被配额保护误标成 failed/wait）才直接读，
  // 否则进详情页（还没下完，没有本地文件可读）。
  private handleDownloadCardTap(item: DownloadInfo, readDirectly: boolean): void {
    if (this.downloadSelectionCount() > 0) {
      this.toggleDownloadSelection(item.gid);
      return;
    }
    // 本地图册和云端保持同一套手势：点缩略图直接读，点标题才进详情。
    if (this.isLocalOnlyItem(item)) {
      const localComplete = downloadDisplayState(item) === DownloadDisplayState.Done;
      if (readDirectly && localComplete) {
        const site = currentGallerySite();
        startDownloadReaderSession(item, site, EhUrl.getReferer(site), () => {
          this.showReader = true;
        });
        return;
      }
      if (readDirectly && !localComplete) {
        this.showStatusHint(uiText('Files missing'), 1800);
      }
      if (!this.splitLayoutCapable()) {
        const localWindowY = this.cardAreaByKey.get(item.gid.toString());
        if (localWindowY !== undefined) {
          this.cardScrollAnchor.capture(item.gid.toString(), this.downloadColumnCount(), localWindowY);
        }
      }
      this.openDetail(item);
      return;
    }
    // 文件缺失的项进度还停在满格，必须排除掉，否则会去读一个空目录。
    const complete = downloadDisplayState(item) === DownloadDisplayState.Done;
    if (readDirectly && complete) {
      const site = currentGallerySite();
      startDownloadReaderSession(item, site, EhUrl.getReferer(site), () => {
        this.showReader = true;
      });
      return;
    }
    if (!this.splitLayoutCapable()) {
      const windowY = this.cardAreaByKey.get(item.gid.toString());
      if (windowY !== undefined) {
        this.cardScrollAnchor.capture(item.gid.toString(), this.downloadColumnCount(), windowY);
      }
    }
    this.openDetail(item);
  }

  private downloadCardWindowY(area: Area): number {
    const value = area.globalPosition.y;
    return value === undefined ? Number.NaN : Number.parseFloat(value.toString());
  }

  private observeDownloadCardAnchor(item: DownloadInfo, area: Area): void {
    if (this.splitLayoutCapable()) {
      return;
    }
    const key = item.gid.toString();
    this.cardAreaByKey.set(key, this.downloadCardWindowY(area));
    this.cardScrollAnchor.observe(key, this.downloadColumnCount(),
      this.downloadCardWindowY(area), (deltaY: number) => {
        this.downloadScroller.scrollBy(0, deltaY);
        setTimeout(() => {
          this.rememberDownloadScrollOffset();
        }, 0);
      });
  }

  private splitLayoutCapable(): boolean {
    return splitPaneModeEnabled() && this.availableSceneWidth() >= SPLIT_PANE_BREAKPOINT && !this.showTagSearch;
  }

  private selectedDownloadItems(): DownloadInfo[] {
    const selected: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.isDownloadSelected(this.items[i].gid)) {
        selected.push(this.items[i]);
      }
    }
    return selected;
  }

  private selectAllVisibleDownloads(): void {
    if (this.visibleItems.length === 0) {
      this.statusText = 'No downloads to select';
      return;
    }
    // 已全选时要能反选：原来只做全选，再点一次什么都不变，用户以为按钮坏了。
    let allSelected = true;
    for (let i = 0; i < this.visibleItems.length; i++) {
      if (!this.isDownloadSelected(this.visibleItems[i].gid)) {
        allSelected = false;
        break;
      }
    }
    if (allSelected) {
      this.selectedDownloadGids = '';
      this.downloadActionsExpanded = false;
      this.statusText = 'Selection cleared';
      this.showStatusHint(uiText('Selection cleared'), 1800);
      return;
    }
    let selected = '';
    for (let i = 0; i < this.visibleItems.length; i++) {
      selected += this.selectedKey(this.visibleItems[i].gid);
    }
    this.selectedDownloadGids = selected;
    this.downloadActionsExpanded = true;
    const message = uiText('Selected') + ' ' + this.visibleItems.length.toString() + ' ' + uiText('items');
    this.statusText = message;
    this.showStatusHint(message, 1800);
  }

  private downloadCardPreferredWidth(): number {
    if (galleryListMode() === 'Thumb') {
      return galleryThumbnailPreferredColumnWidth();
    }
    return galleryDetailCardPreferredWidth();
  }

  private downloadCardGap(): number {
    return uiListGap();
  }

  private downloadContentPadding(): number {
    return galleryListHorizontalPadding(this.downloadContentWidth);
  }

  private downloadColumnCount(): number {
    return this.downloadColumnCountForWidth(this.downloadContentWidth);
  }

  private downloadColumnCountForWidth(width: number): number {
    const availableWidth = Math.max(0, width - this.downloadContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return 1;
    }
    const preferred = this.downloadCardPreferredWidth();
    const gap = this.downloadCardGap();
    return galleryListColumnCount(width, preferred, gap);
  }

  private downloadWaterFlowColumnsTemplate(): string {
    return galleryListColumnsTemplate(this.downloadColumnCount());
  }

  private updateDownloadContentWidth(width: number): void {
    const normalizedWidth = Math.floor(width);
    if (normalizedWidth <= 0 || Number.isNaN(normalizedWidth) ||
      Math.abs(this.downloadContentWidth - normalizedWidth) < 1) {
      return;
    }
    this.downloadContentWidth = normalizedWidth;
  }

  private syncDownloadContentWidthFromWindow(): void {
    if (this.useSplitLayout()) {
      this.syncDownloadContentWidthForCurrentLayout();
      return;
    }
    this.updateDownloadContentWidth(mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  private syncDownloadContentWidthForCurrentLayout(): void {
    const width = this.useSplitLayout() ? this.splitListPaneWidth() : this.availableSceneWidth();
    if (width >= 240) {
      this.updateDownloadContentWidth(width);
    }
  }

  private updateDownloadContentWidthFromArea(width: number): void {
    const targetWidth = this.useSplitLayout() ? this.splitListPaneWidth() : this.availableSceneWidth();
    this.updateDownloadContentWidth(targetWidth >= 240 ? targetWidth : width);
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
    rememberMainContentWidthVp(normalized);
    this.syncDownloadContentWidthForCurrentLayout();
    markCurrentRouteRightPane(this.useSplitLayout());
  }

  onSplitPaneRatioRevisionChange(): void {
    if (!this.splitDragging) {
      this.splitListRatio = splitPaneCurrentRatio();
      this.syncDownloadContentWidthForCurrentLayout();
    }
  }

  private useSplitLayout(): boolean {
    return splitPaneModeEnabled() && this.availableSceneWidth() >= SPLIT_PANE_BREAKPOINT &&
      (this.showDetail || this.downloadLabelManagerVisible) && !this.showTagSearch;
  }

  private handleDownloadListDidScroll(): void {
    const yOffset = this.readDownloadScrollOffset();
    if (yOffset === undefined) {
      return;
    }
    markGalleryListScrolling();
    this.reportChromeForScroll(yOffset);
    this.rememberDownloadScrollOffset(yOffset);
  }

  // 底坞收起：向下滚隐藏，向上滚或回到顶部恢复；回滚后的惯性抖动不再把它带走。
  private reportChromeForScroll(yOffset: number): void {
    const delta = yOffset - this.lastChromeScrollOffset;
    this.lastChromeScrollOffset = yOffset;
    if (yOffset <= 4) {
      resetAppChromeHidden();
      return;
    }
    if (Math.abs(delta) > 240) {
      return;
    }
    if (delta < -1.5) {
      this.chromeRestoreUntil = Date.now() + 500;
      resetAppChromeHidden();
      return;
    }
    if (delta > 1.5 && Date.now() >= this.chromeRestoreUntil) {
      reportAppChromeHidden(true);
    }
  }

  private availableSceneWidth(): number {
    const windowWidth = this.windowContentWidthVp();
    if (this.sceneContentWidth > 0) {
      return this.sceneContentWidth;
    }
    return windowWidth;
  }

  private syncSceneContentWidthFromWindow(): void {
    const width = this.windowContentWidthVp();
    if (width >= 240) {
      this.updateSceneContentWidth(width);
    }
  }

  private windowContentWidthVp(): number {
    return mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
  }

  private splitListPaneWidth(): number {
    return splitPaneListWidth(this.availableSceneWidth(), this.splitListRatio);
  }

  private splitSidePaneWidth(): number {
    if (!this.useSplitLayout()) {
      return this.availableSceneWidth();
    }
    return splitPaneSideWidth(this.availableSceneWidth(), this.splitListPaneWidth());
  }

  private updateSplitPaneByOffset(offsetX: number): void {
    const sceneWidth = this.availableSceneWidth();
    const targetWidth = splitPaneWidthFromDrag(sceneWidth, this.splitDragStartWidth, offsetX);
    const nextSplitRatio = splitPaneRatioForWidth(sceneWidth, targetWidth);
    if (Math.abs(nextSplitRatio - this.splitListRatio) < 0.0005) {
      return;
    }
    this.splitListRatio = nextSplitRatio;
    this.syncDownloadContentWidthForCurrentLayout();
  }

  private finishSplitPaneDrag(): void {
    this.splitDragging = false;
    saveSplitPaneRatio(this.splitListRatio);
  }

  private refreshDownloadRows(onDone?: (items: DownloadInfo[]) => void): void {
    if (!this.downloadSceneActive) {
      return;
    }
    this.downloadProjection.cancelScheduledRefresh();
    const revision = this.downloadProjection.invalidate();
    this.computeVisibleDownloadItems(revision).then((items: DownloadInfo[] | undefined) => {
      if (items === undefined || !this.downloadSceneActive || !this.downloadProjection.isCurrent(revision)) {
        return;
      }
      this.visibleItems = items;
      if (onDone !== undefined) {
        onDone(items);
      }
      if (this.downloadBrowsePositionLoaded && !this.downloadBrowsePositionRestored) {
        setTimeout(() => { this.restoreDownloadScrollOffset(); }, 0);
      }
    }).catch(() => {});
  }

  private stopDownloadListWork(): void {
    this.downloadSceneActive = false;
    this.downloadProjection.dispose();
  }

  private updateDownloadProgress(updates: DownloadProgress[]): void {
    const sizeChanged = applyDownloadProgressUpdates(updates, this.downloadItemsByGid,
      (item: DownloadInfo, changed: boolean) => {
        if (changed) {
          this.downloadProjection.dropKey(item.gid);
        }
        this.downloadCardStateFor(item.gid).update(item.state, downloadProgressText(item),
          this.downloadProgressValue(item), this.downloadSpeedLabel(item), downloadDisplayState(item));
      });
    if (sizeChanged && this.sortMode.startsWith('Size')) {
      this.downloadProjection.scheduleRefresh(() => { this.refreshDownloadRows(); });
    }
  }

  private updateVisibleTranslationItem(index: number, visible: boolean): void {
    const existing = this.translationVisibleItems.indexOf(index);
    if (visible && existing < 0) {
      this.translationVisibleItems.push(index);
    } else if (!visible && existing >= 0) {
      this.translationVisibleItems.splice(existing, 1);
    }
    if (this.translationVisibleItems.length === 0) {
      this.translationVisibleStart = -1;
      this.translationVisibleEnd = -1;
      return;
    }
    let start = this.translationVisibleItems[0];
    let end = start;
    for (let i = 1; i < this.translationVisibleItems.length; i++) {
      start = Math.min(start, this.translationVisibleItems[i]);
      end = Math.max(end, this.translationVisibleItems[i]);
    }
    this.translationVisibleStart = start;
    this.translationVisibleEnd = end;
    this.downloadFirstVisibleIndex = start;
  }

  private setVisibleTranslationRange(start: number, end: number): void {
    this.translationVisibleItems = [];
    this.translationVisibleStart = start;
    this.translationVisibleEnd = end;
    if (start >= 0) {
      this.downloadFirstVisibleIndex = start;
    }
  }

  private translationPriorityFor(index: number): number {
    if (!this.translationEnabled) {
      return 0;
    }
    return translationPriorityForIndex(index, this.translationVisibleStart, this.translationVisibleEnd,
      this.downloadColumnCount());
  }

  private syncDownloadCardStates(items: DownloadInfo[] = this.items): void {
    const live: Map<number, DownloadCardState> = new Map<number, DownloadCardState>();
    this.downloadItemsByGid.clear();
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      this.downloadItemsByGid.set(item.gid, item);
      let cardState = this.downloadCardStates.get(item.gid);
      if (cardState === undefined) {
        cardState = new DownloadCardState();
      }
      cardState.update(item.state, downloadProgressText(item), this.downloadProgressValue(item),
        this.downloadSpeedLabel(item), downloadDisplayState(item));
      live.set(item.gid, cardState);
    }
    this.downloadCardStates = live;
  }

  private downloadCardStateFor(gid: number): DownloadCardState {
    let cardState = this.downloadCardStates.get(gid);
    if (cardState === undefined) {
      cardState = new DownloadCardState();
      this.downloadCardStates.set(gid, cardState);
    }
    return cardState;
  }

  private downloadProgressValue(item: DownloadInfo): number {
    const total = item.total > 0 ? item.total : item.pages;
    if (total <= 0 || item.state === DownloadState.Missing) {
      return 0;
    }
    const units = this.downloadProgressUnits(item);
    return Math.max(0, Math.min(100, Math.round(units * 100 / Math.max(1, total * DOWNLOAD_PAGE_PROGRESS_SCALE))));
  }

  private downloadProgressUnits(item: DownloadInfo): number {
    return Math.max(0, item.finished) * DOWNLOAD_PAGE_PROGRESS_SCALE;
  }

  private downloadSpeedLabel(item: DownloadInfo): string {
    if (item.speed <= 0) {
      return '';
    }
    return downloadSizeText(item.speed) + '/s';
  }

  private startSelectedOrFiltered(): void {
    const selected = this.selectedDownloadItems();
    const targets = selected.length > 0 ? selected : this.visibleItems;
    if (targets.length === 0) {
      this.statusText = 'No filtered downloads';
      return;
    }
    const gids: number[] = [];
    let finished = 0;
    let queuedBefore = 0;
    for (let i = 0; i < targets.length; i++) {
      const state = targets[i].state;
      if (state === DownloadState.Finish) {
        finished++;
      } else if (state === DownloadState.Wait || state === DownloadState.Downloading) {
        queuedBefore++;
      } else {
        gids.push(targets[i].gid);
      }
    }
    const queued = ehDownloadStore.startGalleries(gids);
    const parts: string[] = [];
    parts.push(queued > 0 ? uiText('Queued') + ' ' + queued.toString() : uiText('Nothing to download'));
    if (finished > 0) {
      parts.push(uiText('Skipped completed') + ' ' + finished.toString());
    }
    if (queuedBefore > 0) {
      parts.push(uiText('Already queued') + ' ' + queuedBefore.toString());
    }
    const message = parts.join(' · ');
    this.statusText = message;
    this.showStatusHint(message, 2800);
    if (selected.length > 0) {
      this.clearDownloadSelection();
    }
    this.persistDownloads();
    if (queued > 0) {
      this.startGlobalDownloadQueue();
    }
  }

  private stopSelectedOrFiltered(): void {
    const selected = this.selectedDownloadItems();
    const targets = selected.length > 0 ? selected : this.visibleItems;
    if (targets.length === 0) {
      this.statusText = 'No filtered downloads';
      return;
    }
    for (let i = 0; i < targets.length; i++) {
      ehDownloadManager.stopGallery(targets[i].gid);
    }
    // 用户主动停止：别再弹「失败 N」的队列结算汇总，只给停止提示。
    this.suppressSettleReport = true;
    const message = uiText('Stopped') + ' ' + targets.length.toString();
    this.statusText = message;
    this.showStatusHint(message, 2200);
    if (selected.length > 0) {
      this.clearDownloadSelection();
    }
    this.persistDownloads();
  }

  // FAB 扫描：等同设置里的「导入本地文件夹」，直接扫当前下载根。
  // 会逐条查服务器补云端身份，所以慢一点，但登记出来的图册能云端能本地，
  // 不再是以前那种「添加快、点开却读不出来」的纯本地登记。
  private restoreDownloadedItems(): void {
    this.runScanFlow().catch((error: Error) => {
      this.showStatusHint('Scan failed: ' + error.message, 2600);
    });
  }

  // 扫描磁盘登记（可 await：顶栏一条龙恢复流程复用）。
  // 防重入（F-118）：扫描进行中再点 FAB「扫描」会并发双扫描——保活互踩 +
  // store 并发写，是「卡顿后闪退」的直接嫌疑。进行中一律忽略并提示。
  private scanningInFlight: boolean = false;

  private async runScanFlow(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Scan needs app context';
      return;
    }
    if (this.scanningInFlight) {
      this.showFloatingStatus('Scan already running', 2600);
      return;
    }
    const root = ehDownloadFileStore.currentDownloadRoot(context);
    if (root.length === 0) {
      this.statusText = 'Download folder is not available';
      return;
    }
    this.scanningInFlight = true;
    this.showBlockingBusy('Scanning local galleries...');
    try {
      const report = await importLocalGalleryFolder(context, root, currentGallerySite(),
        (progress: LocalImportProgress) => {
          this.blockingBusyMessage = 'Scanning local galleries...';
          this.blockingBusyProgressText = progress.current.toString() + ' / ' + progress.total.toString();
        });
      await ehDownloadStore.save(context);
      this.hideBlockingBusy();
      this.statusText = 'Added ' + report.added.toString() + ' · matched ' + report.matched.toString() +
        ' · merged ' + report.merged.toString() + ' · local ' + report.localOnly.toString() +
        ' · skipped ' + report.duplicated.toString();
      this.showStatusHint(this.statusText, 3200);
    } catch (error) {
      this.hideBlockingBusy();
      throw error as Error;
    } finally {
      this.scanningInFlight = false;
    }
  }

  // 顶栏循环箭头（F-115）：一条龙恢复——扫描磁盘登记 → 本地对账 → 云端匹配。
  // 记录被误清/换机空库时，点这一个按钮就能从磁盘完整重建。
  private async runFullRecoveryFlow(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Recovery needs app context';
      return;
    }
    // 下载列表为空时先扫磁盘（有记录则跳过扫描，直接对账+匹配）。
    if (ehDownloadStore.getItems().length === 0) {
      await this.runScanFlow();
    }
    await this.rematchLocalGalleries();
  }

  // 「重新匹配」按钮（F-115）：阶段 1 本地对账（blocking 弹窗，快）；
  // 阶段 2 云端匹配交给全局服务（自动弹窗接管显示，切界面/切后台不中断）。
  private async rematchLocalGalleries(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Rematch needs app context';
      return;
    }
    // 防重入（F-118 举一反三）：对账+匹配链路与扫描一样禁止并发触发。
    if (this.scanningInFlight || downloadMatchService.isRunning()) {
      this.showFloatingStatus('Scan already running', 2600);
      return;
    }
    this.scanningInFlight = true;
    try {
      await this.rematchLocalGalleriesInner(context);
    } finally {
      this.scanningInFlight = false;
    }
  }

  private async rematchLocalGalleriesInner(context: common.UIAbilityContext): Promise<void> {
    let reconcileReport: ReconcileReport | null = null;
    this.showBlockingBusy('Reconciling local galleries...');
    try {
      reconcileReport = await reconcileDownloadRecords(context,
        (progress: LocalImportProgress) => {
          this.blockingBusyMessage = 'Reconciling local galleries...';
          this.blockingBusyProgressText = progress.current.toString() + ' / ' + progress.total.toString();
        });
    } catch (error) {
      this.hideBlockingBusy();
      this.showFloatingStatus('Reconcile failed: ' + error.message);
      return;
    }
    this.hideBlockingBusy();
    this.showFloatingStatus('Reconciled ok ' + reconcileReport.ok.toString() + ' · fixed ' +
      reconcileReport.fixed.toString() + ' · removed ' + reconcileReport.removed.toString(), 6000);
    // 手动触发 = 全量重校验（force）：已标记 ok/gone 的也重新探测一遍。
    if (!downloadMatchService.isRunning()) {
      await downloadMatchService.startMatch(context, true);
    }
  }

  private async ensurePublicDownloadAccess(context: common.UIAbilityContext): Promise<boolean> {
    if (ehDownloadFileStore.canUseLocation(context, DOWNLOAD_LOCATION_DOWNLOADS)) {
      return true;
    }
    const pickedRoot = await pickDownloadDirectoryRoot(context);
    if (pickedRoot.length > 0) {
      ehDownloadFileStore.rememberPublicDownloadRoot(pickedRoot);
      if (ehDownloadFileStore.canUseLocation(context, DOWNLOAD_LOCATION_DOWNLOADS)) {
        return true;
      }
    }
    return false;
  }

  private cycleItemState(item: DownloadInfo): void {
    if (item.state === DownloadState.Wait || item.state === DownloadState.Downloading) {
      this.stopItem(item);
      return;
    }
    this.startItem(item);
  }

  private toggleItemFromProgress(item: DownloadInfo): void {
    if (item.state === DownloadState.Finish) {
      return;
    }
    this.cycleItemState(item);
  }

  private findActiveItem(gid: number): DownloadInfo | undefined {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        return this.items[i];
      }
    }
    return undefined;
  }

  private startItem(item: DownloadInfo): void {
    ehDownloadManager.resumeGallery(item.gid);
    this.statusText = 'Queued: ' + item.title;
    // 点状态芯片（失败/已暂停那一条）是最看不出有没有生效的操作：不弹提示时，
    // 用户只能盯着一条不动的进度条猜。没网时直接把原因说出来，别让它安静地排着。
    this.showFloatingStatus(isNetworkOnline() ? this.statusText : 'Network unavailable, queued');
    this.persistDownloads();
    if (!ehDownloadManager.isQueueProcessing()) {
      this.startGlobalDownloadQueue();
    }
  }

  private stopItem(item: DownloadInfo): void {
    ehDownloadManager.stopGallery(item.gid);
    this.statusText = 'Stopped: ' + item.title;
    this.showFloatingStatus(this.statusText);
    this.persistDownloads();
  }

  private startGlobalDownloadQueue(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download needs app context';
      return;
    }
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
    this.askContinue = onContinue;
    this.askConfirm('mobileData', uiText('Mobile data warning'),
      uiText('You are using mobile data. Continue downloading?'),
      uiText('Continue'), '', false, true);
  }

  private removeItem(item: DownloadInfo): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      ehDownloadFileStore.removeGalleryDirectory(context, item);
    }
    ehDownloadStore.removeGallery(item.gid);
    // 原来只改了内存里的列表，没落盘：重启后会按磁盘上的旧数据恢复这条记录，
    // 而目录已经被删掉，于是列表里又冒出一条「本地文件缺失」。
    this.persistDownloads();
  }

  private hasFailedDownloads(): boolean {
    return hasAnyFailedDownload(this.items);
  }

  // 批量重试失败任务：失败项逐个走 resumeGallery（改回等待并踢队列），
  // 队列自身的防重入保证多次调用安全。
  private retryFailedDownloads(): void {
    const failed: DownloadInfo[] = collectFailedDownloads(this.items);
    if (failed.length === 0) {
      this.showFloatingStatus('No failed downloads to retry');
      return;
    }
    this.closeDownloadStatusPanel();
    for (let i = 0; i < failed.length; i++) {
      ehDownloadManager.resumeGallery(failed[i].gid);
    }
    this.showFloatingStatus('Retrying ' + failed.length.toString() + ' failed downloads');
  }

  private clearFailedDownloads(): void {
    const failed: DownloadInfo[] = collectFailedDownloads(this.items);
    if (failed.length === 0) {
      this.showFloatingStatus('No failed downloads to clear');
      return;
    }
    this.closeDownloadStatusPanel();
    this.askConfirm('clearFailed', uiText('Clear failed downloads'),
      uiStatusText('Remove ' + failed.length.toString() +
        ' failed download items and their partial files?'),
      uiText('Clear'), '', true, true);
  }

  private deleteSelectedDownloads(): void {
    const selected = this.selectedDownloadItems();
    if (selected.length === 0) {
      this.statusText = 'Long press cards to select downloads';
      return;
    }
    if (this.deleteConfirmationDialogOpen) {
      return;
    }
    // 打开自绘确认层，动作在用户点选后执行；期间用标记挡住重复触发。
    this.deleteConfirmCloudAvailable =
      remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_DOWNLOADS) !== null;
    this.deleteConfirmCount = selected.length;
    this.deleteConfirmationDialogOpen = true;
    this.deleteConfirmVisible = true;
  }

  private closeDeleteConfirm(): void {
    this.deleteConfirmVisible = false;
    this.deleteConfirmationDialogOpen = false;
  }

  private deleteSelectedLocalOnly(selected: DownloadInfo[]): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    for (let i = 0; i < selected.length; i++) {
      ehDownloadFileStore.removeGalleryDirectory(context, selected[i]);
    }
    this.clearDownloadSelection();
    this.statusText = 'Local copies removed; cloud copies are kept';
    this.persistDownloads();
  }

  private deleteSelectedFromCloud(selected: DownloadInfo[]): void {
    const context = getAbilityContext();
    const directories: string[] = [];
    if (context !== undefined) {
      for (let i = 0; i < selected.length; i++) {
        directories.push(remoteStorageDownloadDeletionService.localDirectoryName(context, selected[i].gid));
      }
    }
    for (let i = 0; i < selected.length; i++) {
      this.removeItem(selected[i]);
    }
    if (context !== undefined) {
      for (let i = 0; i < selected.length; i++) {
        remoteStorageDownloadDeletionService.recordCloudDeletion(context, selected[i].gid, directories[i]);
      }
      remoteStorageDownloadDeletionService.processPendingDeletions(context);
    }
    this.clearDownloadSelection();
    this.statusText = 'Deleted from all devices; cloud removal finishes when connected';
    this.persistDownloads();
  }

  // 只删记录，不动磁盘上的图册目录。
  private removeSelectedRecordsOnly(selected: DownloadInfo[]): void {
    for (let i = 0; i < selected.length; i++) {
      ehDownloadStore.removeGallery(selected[i].gid);
    }
    this.clearDownloadSelection();
    this.statusText = 'Removed ' + selected.length.toString() + ' download records; local files kept';
    this.showStatusHint('Removed ' + selected.length.toString() + ' records; local files kept', 2200);
    this.persistDownloads();
  }

  private removeSelectedDownloads(selected: DownloadInfo[]): void {
    for (let i = 0; i < selected.length; i++) {
      this.removeItem(selected[i]);
    }
    this.clearDownloadSelection();
    this.statusText = 'Removed ' + selected.length.toString() + ' download items';
    this.persistDownloads();
  }

  private exportSelectedDownloadsZip(): void {
    const selected = this.selectedDownloadItems();
    if (selected.length === 0) {
      this.statusText = 'Long press cards to select downloads';
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Export needs app context';
      return;
    }
    this.statusText = 'Exporting ' + selected.length.toString() + ' selected downloads...';
    this.ensurePublicDownloadAccess(context).then((ready: boolean) => {
      if (!ready) {
        throw new Error('Downloads access was not granted');
      }
      this.showBlockingBusy('Creating download archive...');
      return ehDownloadFileStore.exportGalleriesZip(context, selected);
    }).then((result) => {
      this.hideBlockingBusy();
      if (result === undefined) {
        return;
      }
      this.clearDownloadSelection();
      this.showFloatingStatus('Exported ' + result.folders.toString() + ' folders to ' + result.path + ' (' +
        downloadSizeText(result.bytes) + ')');
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.showFloatingStatus('Export failed: ' + error.message);
    });
  }

  private openDetail(item: DownloadInfo): void {
    // 仅云端画廊不再整册恢复：详情直接打开，图片在阅读器里按页从云端拉取。
    this.openDetailNow(item);
  }

  private openDetailNow(rawItem: DownloadInfo): void {
    const item = this.healedDownloadItem(rawItem);
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.showDetail = true;
    this.syncDownloadContentWidthForCurrentLayout();
    markCurrentRouteRightPane(this.useSplitLayout());
    if (this.isLocalOnlyItem(item)) {
      // 本地记录没有 token，拼不出云端详情地址；清空云端详情状态，右栏交给本地面板。
      this.localDetailGid = item.gid;
      this.detailLink = createEmptyGalleryDetailLink();
      this.detail = createEmptyDetail();
      this.detailRequestUrl = '';
      this.saveNavigationCache();
      return;
    }
    this.localDetailGid = -1;
    const detailLink = createGalleryDetailLinkFromGallery(item, currentGallerySite(),
      EhUrl.getReferer(currentGallerySite()));
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailRequestUrl = detailLink.url;
    this.saveNavigationCache();
  }

  // 按 gid 取当前下载条目；取不到时退回渲染时传入的那条。
  private itemByGid(gid: number, fallback: DownloadInfo): DownloadInfo {
    const cached = this.downloadItemsByGid.get(gid);
    if (cached !== undefined) {
      return cached;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        return this.items[i];
      }
    }
    return fallback;
  }

  private localDetailItem(): DownloadInfo {
    const cached = this.downloadItemsByGid.get(this.localDetailGid);
    if (cached !== undefined) {
      return cached;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === this.localDetailGid) {
        return this.items[i];
      }
    }
    return createEmptyDownloadInfo();
  }

  // 状态可能是旧值（迁移/换根后目录其实还在）。打开前按真实目录自愈一次：
  // 目录能解析出来就把 state 刷成完成并更新路径，避免"文件明明在却报缺失"（R10 复发形态）。
  private healedDownloadItem(item: DownloadInfo): DownloadInfo {
    if (item.state !== DownloadState.Missing) {
      return item;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return item;
    }
    const directory = ehDownloadFileStore.resolveGalleryDirectory(context, item.gid, item.title, item.archiveUri);
    if (directory.length === 0) {
      return item;
    }
    ehDownloadStore.setState(item.gid, DownloadState.Finish);
    ehDownloadStore.setStorage(item.gid, directory, item.fileSize);
    this.persistDownloads();
    for (let i = 0; i < this.visibleItems.length; i++) {
      if (this.visibleItems[i].gid === item.gid) {
        return this.visibleItems[i];
      }
    }
    return item;
  }

  private openLocalReader(rawItem: DownloadInfo, index: number): void {
    const item = this.healedDownloadItem(rawItem);
    if (item.gid <= 0 || item.state === DownloadState.Missing) {
      this.showStatusHint(uiText('Files missing'), 1800);
      return;
    }
    const site = currentGallerySite();
    startDownloadReaderSessionAt(item, site, EhUrl.getReferer(site), index, () => {
      this.showReader = true;
    });
  }

  private applyLocalMeta(item: DownloadInfo, pages: number, bytes: number): void {
    if (pages <= 0) {
      return;
    }
    const changed = ehDownloadStore.refreshLocalGalleryMeta(item.archiveUri, pages, bytes, '', item.gid);
    if (changed) {
      this.persistDownloads();
    }
  }

  private confirmRemoveLocalGallery(item: DownloadInfo): void {
    if (this.deleteConfirmationDialogOpen) {
      return;
    }
    this.deleteConfirmationDialogOpen = true;
    this.askTextPayload = item.gid.toString();
    // 与下载页删除弹窗同一套语义（F-114 追加）：主按钮删记录+文件，副按钮只删记录保留文件。
    this.askConfirm('removeLocalGallery', uiText('Remove'),
      uiText('Delete the list record only, or delete the local gallery with its files?'),
      uiText('Delete local gallery'), uiText('Remove record only'), true, true);
  }

  // 启动时按磁盘把本地图册的页数/体积/封面刷新一遍：老记录的 pages 是服务器页数，
  // 和磁盘实际张数经常差 1–2 张，列表显示 39 页、目录里其实有 40 张。
  // 这里全量对齐（不再限制前 40 条），分批跑，避免一次性 200 多个目录阻塞主线程。
  private backfillLocalGalleryPages(context: common.UIAbilityContext): void {
    if (AppStorage.get<boolean>(LOCAL_BACKFILL_DONE_KEY) === true) {
      return;
    }
    AppStorage.setOrCreate<boolean>(LOCAL_BACKFILL_DONE_KEY, true);
    const pending: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.token.length > 0) {
        continue;
      }
      // 本地项即使已经标了 Missing 也要再试一次：目录可能只是被挪走又放回来。
      pending.push(item);
    }
    if (pending.length === 0) {
      return;
    }
    this.backfillLocalBatch(context, pending, 0);
  }

  private backfillLocalBatch(context: common.UIAbilityContext, pending: DownloadInfo[], start: number): void {
    const end = Math.min(pending.length, start + LOCAL_META_BACKFILL_BATCH);
    let changed = false;
    for (let i = start; i < end; i++) {
      const item = pending[i];
      const directory = ehDownloadFileStore.downloadedGalleryDirectory(context, item);
      const paths = ehDownloadFileStore.listLocalPageImages(directory);
      if (paths.length === 0) {
        // 目录真的找不到：把状态标成文件缺失，列表就不会继续显示 “✓ · 29 P” 骗人。
        // 同时留一条记录——只写一次，避免每次启动刷屏；没这行就只能靠重新拉设备文件排查。
        if (item.state !== DownloadState.Missing) {
          appLog.warn(context, LOCAL_GALLERY_LOG_TAG,
            'directory not resolved gid=' + item.gid.toString() +
              ' pages=' + item.pages.toString() +
              ' archive=' + item.archiveUri +
              ' title=' + item.title.substring(0, 60));
          ehDownloadStore.setState(item.gid, DownloadState.Missing);
          changed = true;
        }
        continue;
      }
      if (item.state === DownloadState.Missing) {
        ehDownloadStore.setState(item.gid, DownloadState.Finish);
        changed = true;
      }
      // 已有封面文件就不重新生成：ensureLocalThumbnail 内部要做两次 stat，
      // 200 多个目录每次都做会拖慢列表加载。
      const stagedThumb = item.thumb !== undefined ? item.thumb : '';
      const thumb = stagedThumb.length > 0 && ehDownloadFileStore.localThumbExists(stagedThumb) ?
        stagedThumb : ensureLocalThumbnail(context, directory, item.title);
      if (ehDownloadStore.refreshLocalGalleryMeta(item.archiveUri, paths.length,
        ehDownloadFileStore.directorySizeByPath(directory), thumb, item.gid)) {
        changed = true;
      }
    }
    if (changed) {
      this.refreshDownloadRows();
      this.persistDownloads();
    }
    if (end < pending.length) {
      setTimeout(() => {
        this.backfillLocalBatch(context, pending, end);
      }, 32);
    }
  }

  private openRandomDownload(): void {
    if (this.visibleItems.length === 0) {
      this.showFloatingStatus('Random needs a loaded gallery list');
      return;
    }
    const index = Math.floor(Math.random() * this.visibleItems.length);
    this.openDetail(this.visibleItems[index]);
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.showDetail = false;
    // F-123：从查重点条目进详情，看完关详情自动回到查重弹窗（数据保留）。
    if (this.dedupeRestoreOnDetailClose && this.dedupeGroups.length > 0) {
      this.dedupeRestoreOnDetailClose = false;
      this.dedupePanelVisible = true;
    }
    this.localDetailGid = -1;
    this.syncDownloadContentWidthForCurrentLayout();
    markCurrentRouteRightPane(false);
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailRequestUrl = '';
    this.saveNavigationCache();
  }

  private closeTagSearch(): void {
    this.showTagSearch = false;
    this.tagSearchTitle = 'Search';
    this.tagSearchKeyword = '';
    this.tagSearchMode = ListMode.Tag;
    this.tagSearchCategory = GalleryCategory.None;
    this.tagSearchImagePath = '';
    this.tagSearchCoverSource = undefined;
    this.tagSearchImageUseSimilarity = false;
    this.tagSearchImageOnlyCovers = false;
    this.tagSearchImageShowExpunged = false;
    this.saveNavigationCache();
    setTimeout(() => {
      setActiveBackHandler(this.boundSystemBack);
    }, 0);
  }

  private openRemoteSearch(request: DetailSearchRequest): void {
    this.tagSearchTitle = request.title;
    this.tagSearchKeyword = request.keyword;
    this.tagSearchMode = request.mode;
    this.tagSearchCategory = request.category;
    this.tagSearchImagePath = request.imagePath;
    this.tagSearchCoverSource = request.coverSearchSource;
    this.tagSearchImageUseSimilarity = request.useSimilarityScan;
    this.tagSearchImageOnlyCovers = request.onlySearchCovers;
    this.tagSearchImageShowExpunged = request.showExpunged;
    this.showReader = false;
    this.showTagSearch = true;
    this.saveNavigationCache();
  }

  private closeEmbeddedReader(): void {
    if (this.readerClosing) {
      return;
    }
    this.readerClosing = true;
    this.restoreDetailWithFade = this.showDetail;
    if (!isEmbeddedReaderActive()) {
      this.showReader = false;
      this.restoreBackHandler();
      this.clearRestoreDetailFadeLater();
      this.readerClosing = false;
      return;
    }
    leaveEmbeddedReaderFullscreen().then(() => {
      this.showReader = false;
      this.restoreBackHandler();
      this.clearRestoreDetailFadeLater();
    }).finally(() => {
      this.readerClosing = false;
    });
  }

  private clearRestoreDetailFadeLater(): void {
    setTimeout(() => {
      if (!this.showReader) {
        this.restoreDetailWithFade = false;
      }
    }, 260);
  }

  private restoreBackHandler(): void {
    setTimeout(() => {
      setActiveBackHandler(this.boundSystemBack);
    }, 0);
  }

  @Builder
  private downloadSearchSuggestionPlaceholder() {
    Column({ space: 4 }) {
      SearchSummaryStrip({
        selectedTagNamespaces: this.selectedTagNamespaces,
        selectedTagNamespaceKey: this.selectedTagNamespaceKey(),
        revision: this.searchSuggestionRevision,
        onToggleTagNamespace: (namespace: string) => {
          this.toggleTagNamespace(namespace);
        }
      })
      if (this.searchSuggestionItems.length > 0) {
        SearchSuggestionList({
          suggestions: this.searchSuggestionItems,
          revision: this.searchSuggestionRevision,
          onSelect: (suggestion: SearchSuggestionItem) => {
            this.applySearchSuggestion(suggestion);
          }
        })
          .height(Math.max(240, this.downloadListViewportHeight() - 58))
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(28)
            .fontColor([themeTertiaryText()])
          Text(uiText('Search history appears before typing; tag tips appear while typing'))
            .fontSize(12)
            .fontColor(themeTertiaryText())
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(6))
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4 })
  }

  // 下载页角标口径（仅本页）：有云端身份 → 云朵（含下载中、已下载）；
  // 只有本地文件 → 手机；云端记录在但两边都缺 → 云朵+斜线（cloudGone）。
  // 不改动其它页面的角标（红线：角标语义只作用于下载界面）。
  private isCloudIdentityItem(item: DownloadInfo): boolean {
    if (item.token === undefined || item.token.length === 0) {
      return false;
    }
    return !this.isCloudGoneItem(item);
  }

  private isLocalOnlyItem(item: DownloadInfo): boolean {
    // 无档案本地图档：靠目录名扫描识别，db / 服务器均无记录（token 为空）。
    return item.token === undefined || item.token.length === 0;
  }

  // 有云端身份但本机没有文件：蓝云（云端仍在，可联网读）或红云（云端已删除）。
  private isCloudOnlyMissing(item: DownloadInfo): boolean {
    if (item.token === undefined || item.token.length === 0) {
      return false;
    }
    if (item.state !== DownloadState.Missing) {
      return false;
    }
    return item.cloudState !== CLOUD_STATE_GONE;
  }

  private isCloudGoneItem(item: DownloadInfo): boolean {
    if (item.token === undefined || item.token.length === 0) {
      return false;
    }
    return item.state === DownloadState.Missing && item.cloudState === CLOUD_STATE_GONE;
  }

  @Builder
  private downloadCardContent(item: DownloadInfo, index: number) {
    Column() {
      if (galleryListMode() === 'Thumb') {
        // Long-press selection is injected per page; keep the reusable card contract as-is.
        // eslint-disable-next-line @performance/hp-arkui-no-func-as-arg-for-reusable-component
        GalleryThumbCard({
          gallery: item,
          selected: this.isDownloadSelected(item.gid),
          translateTitle: this.translationEnabled,
          translationPriority: this.translationPriorityFor(index),
          localOnly: this.isLocalOnlyItem(item),
          cloudOnly: this.isCloudIdentityItem(item),
          cloudGone: this.isCloudGoneItem(item),
          onLongPress: (pressed: GalleryInfo) => {
            this.toggleDownloadSelection(pressed.gid);
          },
          // 卡片会被复用，闭包里的 item 可能是旧的；一律按回调给的 gid 重新取当前条目，
          // 否则删/改序后会「点第一条打开第三条」（货不对板）。
          onOpenReader: (pressed: GalleryInfo) => {
            this.handleDownloadCardTap(this.itemByGid(pressed.gid, item), true);
          },
          onOpenDetail: (pressed: GalleryInfo) => {
            this.handleDownloadCardTap(this.itemByGid(pressed.gid, item), false);
          }
        })
          .width('100%')
          .zIndex(2)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.observeDownloadCardAnchor(item, newArea);
          })
      } else {
        // eslint-disable-next-line @performance/hp-arkui-no-func-as-arg-for-reusable-component
        GalleryListRow({
          gallery: item,
          selected: this.isDownloadSelected(item.gid),
          translateTitle: this.translationEnabled,
          translationPriority: this.translationPriorityFor(index),
          localOnly: this.isLocalOnlyItem(item),
          cloudOnly: this.isCloudIdentityItem(item),
          cloudGone: this.isCloudGoneItem(item),
          progressLabel: this.downloadRowProgressLabel(item),
          onLongPress: (pressed: GalleryInfo) => {
            this.toggleDownloadSelection(pressed.gid);
          },
          // 卡片会被复用，闭包里的 item 可能是旧的；一律按回调给的 gid 重新取当前条目，
          // 否则删/改序后会「点第一条打开第三条」（货不对板）。
          onOpenReader: (pressed: GalleryInfo) => {
            this.handleDownloadCardTap(this.itemByGid(pressed.gid, item), true);
          },
          onOpenDetail: (pressed: GalleryInfo) => {
            this.handleDownloadCardTap(this.itemByGid(pressed.gid, item), false);
          }
        })
          .width('100%')
          .zIndex(2)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.observeDownloadCardAnchor(item, newArea);
          })
      }
      if (item.state !== DownloadState.Finish) {
        DownloadCardStatus({
          item: item,
          cardState: this.downloadCardStateFor(item.gid),
          onStatusTap: (downloadItem: DownloadInfo) => {
            const current = this.findActiveItem(downloadItem.gid);
            if (current !== undefined) {
              this.toggleItemFromProgress(current);
            }
          }
        })
          .margin({ top: 4 })
          .zIndex(1)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
            TransitionEffect.move(TransitionEdge.TOP)
              .animation({ duration: 180, curve: Curve.EaseIn })))
      }
    }
    .width('100%')
    .animation({ duration: 220, curve: Curve.EaseOut })
  }

  @Builder
  private downloadListEdgeSpacer() {
    Row()
      .width('100%')
      .height(this.downloadCardGap() +
        appDockBottomInset(this.bottomAvoidHeight, 0))
      .backgroundColor(themePageBackground())
  }

  @Builder
  private downloadListTopPlaceholder() {
    Row()
      .width('100%')
      .height(this.downloadContentStartOffset())
  }

  // 列表末尾的占位必须是内容的一部分，滚动时才不会被胶囊"截断"。
  // 用 List 的 padding 会让这块区域永远进不去内容，看着就像底部被压住。
  @Builder
  private downloadListBottomSpacer() {
    Row()
      .width('100%')
      .height(this.downloadCardGap() +
        appDockBottomInset(this.bottomAvoidHeight, 0))
  }

  @Builder
  private downloadStandardList() {
    List({ space: 0, scroller: this.downloadScroller }) {
      ListItemGroup({ header: this.downloadListTopPlaceholder(), footer: this.downloadListBottomSpacer() }) {
        ForEach(this.visibleItems, (item: DownloadInfo, index: number) => {
          ListItem() {
            this.downloadCardContent(item, index)
          }
          .margin({ bottom: this.downloadCardGap() })
          .reuseId('download-card-item')
          .onVisibleAreaChange([0.0, 0.01], (visible: boolean, _ratio: number) => {
            this.updateVisibleTranslationItem(index, visible);
          })
          .animation({ duration: 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
        // key 必须唯一到「一条下载记录」。只用 gid 时，同画廊的多条记录 key 重复，
      // 删除一条后 ForEach 会复用错节点，表现为缩略图与实际图册不匹配。
      }, (item: DownloadInfo) => item.gid.toString() + ':' + item.time.toString() + ':' + item.label)
      }
    }
    .width('100%')
    .height('100%')
    .lanes(this.downloadColumnCount(), this.downloadCardGap())
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
    .cachedCount(10)
    .scrollBar(BarState.Auto)
    .padding({
      left: this.downloadContentPadding(),
      right: this.downloadContentPadding()
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateDownloadContentWidthFromArea(newArea.width as number);
    })
    .onAppear(() => {
      this.restoreDownloadScrollOffset();
    })
    .onScrollFrameBegin((offset: number, _state: ScrollState) => {
      return { offsetRemain: this.updateToolbarForScrollFrame(offset) };
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
      this.handleDownloadListDidScroll();
    })
    .onScrollStop(() => {
      this.rememberDownloadScrollOffset();
    })
  }

  @Builder
  private downloadThumbnailWaterFlow() {
    WaterFlow({
      footer: this.downloadListEdgeSpacer(),
      scroller: this.downloadScroller,
      layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW
    }) {
      ForEach(this.visibleItems, (item: DownloadInfo, index: number) => {
        FlowItem() {
          this.downloadCardContent(item, index)
        }
        .width('100%')
        .margin({ top: index < this.downloadColumnCount() ? this.downloadContentStartOffset() : 0 })
        .reuseId('download-thumb-flow-item')
        .onVisibleAreaChange([0.0, 0.01], (visible: boolean, _ratio: number) => {
          this.updateVisibleTranslationItem(index, visible);
        })
        .animation({ duration: 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
      // key 必须唯一到「一条下载记录」。只用 gid 时，同画廊的多条记录 key 重复，
      // 删除一条后 ForEach 会复用错节点，表现为缩略图与实际图册不匹配。
      }, (item: DownloadInfo) => item.gid.toString() + ':' + item.time.toString() + ':' + item.label)
    }
    .columnsTemplate(this.downloadWaterFlowColumnsTemplate())
    .columnsGap(this.downloadCardGap())
    .rowsGap(this.downloadCardGap())
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
    .scrollBar(BarState.Auto)
    .width('100%')
    .height('100%')
    .cachedCount(10)
    .padding({
      left: this.downloadContentPadding(),
      right: this.downloadContentPadding()
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateDownloadContentWidthFromArea(newArea.width as number);
    })
    .onAppear(() => {
      this.restoreDownloadScrollOffset();
    })
    .onScrollFrameBegin((offset: number, _state: ScrollState) => {
      return { offsetRemain: this.updateToolbarForScrollFrame(offset) };
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
      this.handleDownloadListDidScroll();
    })
    .onScrollIndex((first: number, last: number) => {
      this.setVisibleTranslationRange(first, last);
    })
    .onScrollStop(() => {
      this.rememberDownloadScrollOffset();
    })
  }

  private restoreDownloadScrollOffset(): void {
    this.syncDownloadContentWidthFromWindow();
    if (!this.downloadBrowsePositionLoaded || this.downloadBrowsePositionRestored || this.visibleItems.length === 0) {
      return;
    }
    const position: BrowsePosition = ehBrowsePositionStore.getDownloadPosition();
    let targetIndex = -1;
    if (position.anchorId.length > 0) {
      for (let i = 0; i < this.visibleItems.length; i++) {
        if (this.visibleItems[i].gid.toString() === position.anchorId) {
          targetIndex = i;
          break;
        }
      }
    }
    if (targetIndex < 0) {
      targetIndex = Math.min(position.anchorIndex, this.visibleItems.length - 1);
    }
    this.downloadFirstVisibleIndex = targetIndex;
    this.downloadBrowsePositionRestored = true;
    this.restoringDownloadBrowsePosition = true;
    setTimeout(() => {
      if (targetIndex === position.anchorIndex && position.offset > 0) {
        this.downloadScroller.scrollTo({ xOffset: 0, yOffset: position.offset });
      } else if (targetIndex > 0) {
        const scrollIndex = galleryListMode() === 'Thumb' ? targetIndex :
          Math.floor(targetIndex / Math.max(1, this.downloadColumnCount())) + 1;
        this.downloadScroller.scrollToIndex(scrollIndex);
      }
      setTimeout(() => {
        this.restoringDownloadBrowsePosition = false;
      }, 80);
    }, 0);
  }

  private readDownloadScrollOffset(): number | undefined {
    try {
      // currentOffset() can return undefined after the List/WaterFlow is detached,
      // although its SDK return type omits it. Keep this path compatible with API 20.
      const offset: OffsetResult | undefined = this.downloadScroller.currentOffset();
      if (offset === undefined || offset === null || !Number.isFinite(offset.yOffset)) {
        return undefined;
      }
      return normalizeSceneScrollOffset(offset.yOffset);
    } catch (_error) {
      return undefined;
    }
  }

  private rememberDownloadScrollOffset(observedOffset?: number): void {
    if (this.restoringDownloadBrowsePosition) {
      return;
    }
    if (this.visibleItems.length === 0) {
      this.downloadScrollOffset = 0;
      if (this.downloadBrowsePositionLoaded) {
        ehBrowsePositionStore.updateDownloadPosition('', 0, 0);
      }
      return;
    }
    const offset = observedOffset === undefined ? this.readDownloadScrollOffset() : observedOffset;
    if (offset === undefined) {
      // onDidScroll/onScrollStop already saved the last valid position. During
      // teardown leave that snapshot intact for aboutToDisappear() to flush.
      return;
    }
    this.downloadScrollOffset = offset;
    if (!this.downloadBrowsePositionLoaded) {
      return;
    }
    const index = Math.max(0, Math.min(this.downloadFirstVisibleIndex, this.visibleItems.length - 1));
    const anchorId = this.visibleItems.length > 0 ? this.visibleItems[index].gid.toString() : '';
    ehBrowsePositionStore.updateDownloadPosition(anchorId, index, this.downloadScrollOffset);
  }

  // The scene owns the full window width; only this pane participates in split resizing.
  @Builder
  private downloadListPane() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (!this.searchSubmitted) {
          List({ space: 0 }) {
            ListItem() {
              Row().width('100%').height(this.floatingToolbarHeight() + 8)
            }
            ListItem() {
              this.downloadSearchSuggestionPlaceholder()
            }
          }
          .width('100%')
          .height('100%')
          .padding({
            left: this.downloadContentPadding(),
            right: this.downloadContentPadding()
          })
        } else if (this.visibleItems.length === 0) {
          Column() {
            Text(uiText('Downloads'))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(themePrimaryText())
            Text(this.items.length === 0 ? uiText('Download items will be shown here') :
              uiText('No items match the current filter'))
              .fontSize(14)
              .fontColor(themeSecondaryText())
              .margin({ top: 10 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          if (galleryListMode() === 'Thumb') {
            this.downloadThumbnailWaterFlow()
          } else {
            this.downloadStandardList()
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
      .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
        TransitionEffect.OPACITY.animation({ duration: 1, delay: 300, curve: Curve.Linear })))
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateDownloadContentWidthFromArea(newArea.width as number);
        const height = newArea.height as number;
        if (height > 0 && !Number.isNaN(height)) {
          this.viewportHeight = height;
        }
      })

      GalleryHomeNavBarHost({
        toolbarState: this.toolbarState(),
        statusBarHeight: this.statusBarVp(),
        title: this.selectedDownloadLabel === DOWNLOAD_LABEL_FILTER_ALL ? 'Downloads' :
          (this.selectedDownloadLabel.length === 0 ? 'Default' : this.selectedDownloadLabel),
        keyword: this.query,
        filterActive: this.advancedPanelVisible || this.advancedSearchEnabled ||
          this.searchCategory !== GalleryCategory.None || this.minRating > 0,
        showSearchButton: !this.searchBarVisible,
        showFavoriteButton: !this.searchBarVisible,
        showCloudMatchButton: !this.searchBarVisible,
        showBackButton: this.searchBarVisible,
        searchMode: this.searchBarVisible,
        searchPlaceholder: 'Search downloads',
        searchShowsAdvancedButton: true,
        toolbarHeight: uiAdaptiveToolbarHeight(this.downloadContentWidth),
        onMenu: () => {
          if (this.searchBarVisible) {
            this.closeDownloadSearchBar();
          } else {
            this.onMenu();
          }
        },
        onBack: () => {
          this.closeDownloadSearchBar();
        },
        onKeywordChange: (value: string) => {
          this.updateDownloadKeyword(value);
        },
        onSearchFocus: () => {
          this.openDownloadSearchSuggestions();
        },
        onSearch: () => {
          if (this.searchBarVisible) {
            this.applyDownloadSearch();
          } else {
            this.openDownloadSearchBar();
          }
        },
        onAdvanced: () => {
          this.toggleAdvancedPanel();
        },
        onFavoriteButton: () => {
          this.openDownloadLabelDrawer();
        },
        onCloudMatch: () => {
          this.runFullRecoveryFlow();
        }
      })

      // 原来这里有一条悬浮在列表上方的「下载中 N · x%」概览条：
      // zIndex(3) 压在列表上，遮住最后一项；hitTestBehavior(None) 点不进任何地方；
      // 而下载页本身就是队列列表，每项都带自己的进度 —— 这条纯属重复且挡路，已移除。

      if (this.advancedPanelVisible) {
        PopupScrim({
          showCutout: this.downloadContentWidth > 20 && this.advancedPopupHeight > 0,
          positionedCutout: true,
          cutoutX: 10,
          cutoutY: this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth) + 8,
          cutoutWidth: Math.max(0, this.downloadContentWidth - 20),
          cutoutHeight: this.advancedPopupHeight,
          cutoutRadius: uiRadius(8),
          onDismiss: () => {
            this.closeAdvancedPanel();
          }
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
          .zIndex(15)

        Stack({ alignContent: Alignment.Top }) {
          SearchAdvancedPanel({
            searchModeValue: this.searchMode,
            searchCategory: this.searchCategory,
            advancedSearchEnabled: this.advancedSearchEnabled,
            advanceSearch: this.advanceSearch,
            searchFilterEnabled: true,
            minRating: this.minRating,
            pageFrom: -1,
            pageTo: -1,
            panelMaxHeight: this.advancedPanelMaxHeight(),
            onSearchModeChange: (mode: ListMode) => {
              this.searchMode = mode;
              this.searchSubmitted = false;
              this.refreshDownloadRows();
            },
            onSearchCategoryChange: (category: number) => {
              this.searchCategory = category;
              this.searchSubmitted = false;
              this.refreshDownloadRows();
            },
            onAdvancedEnabledChange: (enabled: boolean) => {
              this.advancedSearchEnabled = enabled;
              this.searchSubmitted = false;
              this.refreshDownloadRows();
            },
            onAdvanceSearchChange: (flags: number) => {
              this.advanceSearch = flags;
              this.searchSubmitted = false;
              this.refreshDownloadRows();
            },
            onMinRatingChange: (rating: number) => {
              this.minRating = rating;
              this.searchSubmitted = false;
              this.refreshDownloadRows();
            },
            onClose: () => {
              this.closeAdvancedPanel();
            },
            onSearch: () => {
              this.closeAdvancedPanel();
              this.applyDownloadSearch();
            }
          })
            .constraintSize({ maxHeight: this.advancedPanelMaxHeight() })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.advancedPopupHeight = Number.parseFloat(newArea.height.toString());
            })
            .transition(TransitionEffect.move(TransitionEdge.TOP)
              .animation({ duration: 180, curve: Curve.EaseOut }))
        }
          .width('100%')
          .height('100%')
          .padding({
            top: this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth) + 8,
            left: 10,
            right: 10
          })
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(16)
      }

      FloatingActionDock({ side: this.floatingActionSide,
        extraBottomAvoid: this.dockFabReserve() }) {
        if (this.searchBarVisible && !this.searchSubmitted) {
          SearchActionColumn({
            side: this.floatingActionSide,
            onSearch: () => {
              this.applyDownloadSearch();
            },
            onSideChange: (side: string) => {
              this.floatingActionSideController.handleManualSide(side);
            }
          })
        } else {
          DownloadToolColumn({
            expanded: this.downloadActionsExpanded,
            hasSelection: this.downloadSelectionCount() > 0,
            canOperate: this.downloadSelectionCount() > 0 || this.visibleItems.length > 0,
            canJump: this.downloadJumpTotalPages() > 1,
            canRandom: this.visibleItems.length > 0,
            maxExpandedHeight: this.downloadToolActionsMaxHeight(),
            showTranslationButton: this.translationButtonsVisible,
            translationEnabled: this.translationEnabled,
            side: this.floatingActionSide,
            onToggle: () => {
              this.downloadActionsExpanded = !this.downloadActionsExpanded;
            },
            onStatus: () => {
              this.openDownloadStatusPanel();
            },
            onSort: () => {
              this.downloadActionsExpanded = false;
              this.sortPanelVisible = true;
            },
            onJump: () => {
              this.openDownloadJumpPanel();
            },
            onStart: () => {
              this.startSelectedOrFiltered();
            },
            onStop: () => {
              this.stopSelectedOrFiltered();
            },
            onRestore: () => {
              this.restoreDownloadedItems();
            },
            onRematch: () => {
              this.rematchLocalGalleries();
            },
            onDedupe: () => {
              this.openDedupePanel();
            },
            onRandom: () => {
              this.openRandomDownload();
            },
            onTranslate: () => {
              const nextTranslation = !this.translationEnabled;
                ehTranslationService.setEnabled(nextTranslation);
                showTranslationToggleFeedback(this.getUIContext(), nextTranslation);

              console.info('[TranslationDiag] FAB toggle: next=' + nextTranslation.toString() +
                ' storageReadback=' + (AppStorage.get<boolean>(TRANSLATION_ENABLED_KEY) ?? false).toString() +
                ' storageLinkReadback=' + this.translationEnabled.toString());
            },
            onSelectAll: () => {
              this.selectAllVisibleDownloads();
            },
            onDelete: () => {
              this.deleteSelectedDownloads();
            },
            onExportZip: () => {
              this.exportSelectedDownloadsZip();
            },
            onLabel: () => {
              this.openMoveSelectedDownloadLabel();
            },
            onSideChange: (side: string) => {
              this.floatingActionSideController.handleManualSide(side);
            }
          })
        }
      }

      if (this.statusHintVisible) {
        Row() {
          Text(this.statusHintText)
            .fontSize(12)
            .fontColor(themePrimaryText())
            .textAlign(TextAlign.Center)
            .backgroundColor(themeSurface())
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .borderRadius(uiRadius(16))
            .shadow({ radius: 8, color: themeShadowColor(), offsetX: 0, offsetY: 2 })
            .maxLines(2)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .position({
          x: 0,
          y: this.viewportHeight > 0 ? Math.max(140, this.viewportHeight * 0.46) : 420
        })
        .hitTestBehavior(HitTestMode.None)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 140, curve: Curve.EaseOut }))
        .zIndex(18)
      }

      if (this.settleSummaryVisible) {
        Row() {
          Column({ space: 6 }) {
            Text(this.settleSummaryTitle)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(themePrimaryText())
              .maxLines(2)
            if (this.settleSummaryLines.length > 0) {
              Divider()
                .color(themeDividerColor())
                .margin({ top: 2, bottom: 2 })
              ForEach(this.settleSummaryLines, (line: string) => {
                Text('· ' + line)
                  .fontSize(12)
                  .fontColor(themeSecondaryText())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }, (line: string) => line)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(themeSurface())
          .border({ width: 1, color: themeDividerColor() })
          .borderRadius(uiRadius(12))
          .shadow({ radius: 10, color: themeShadowColor(), offsetX: 0, offsetY: 3 })
          .constraintSize({ minWidth: 200, maxWidth: 340 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .position({
          x: 0,
          y: this.viewportHeight > 0 ? Math.max(120, this.viewportHeight * 0.38) : 380
        })
        .hitTestBehavior(HitTestMode.None)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 140, curve: Curve.EaseOut }))
        .zIndex(19)
      }

      if (this.downloadJumpPanelVisible) {
        PopupScrim({
          showCutout: this.downloadJumpPopupHeight > 0,
          positionedCutout: true,
          cutoutX: this.downloadContentWidth > 0 ? Math.max(12, this.downloadContentWidth - 244) : 100,
          cutoutY: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - 210) : 360,
          cutoutWidth: 220,
          cutoutHeight: this.downloadJumpPopupHeight,
          cutoutRadius: uiRadius(8),
          onDismiss: () => {
            this.closeDownloadJumpPanel();
          }
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
          .zIndex(20)

        Column({ space: 10 }) {
          Text(uiText('Jump'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.downloadJumpDraft, placeholder: (this.downloadJumpPageIndex + 1).toString() })
              .height(uiSearchFieldHeight())
              .layoutWeight(1)
              .type(InputType.Number)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .padding({ left: 10, right: 10 })
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.downloadJumpDraft = value;
              })
              .onSubmit(() => {
                this.submitDownloadJump();
                this.closeDownloadJumpPanel();
              })
            Text('/ ' + this.downloadJumpTotalPages().toString())
              .fontSize(13)
              .fontColor(themeSecondaryText())
          }

          Button(uiText('Jump'))
            .height(36)
            .width('100%')
            .fontSize(13)
            .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .borderRadius(uiRadius(4))
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(() => {
              this.submitDownloadJump();
              this.closeDownloadJumpPanel();
            })
        }
        .width(220)
        .padding(12)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(8))
        .shadow({
          radius: 12,
          color: themeShadowColor(),
          offsetX: 0,
          offsetY: 4
        })
        .position({
          x: this.downloadContentWidth > 0 ? Math.max(12, this.downloadContentWidth - 244) : 100,
          y: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - 210) : 360
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.downloadJumpPopupHeight = Number.parseFloat(newArea.height.toString());
        })
        .zIndex(21)
      }

      if (this.statusFilterPanelVisible) {
        DownloadStatusFilterOverlay({
          selectedStatuses: $statusFilterDraft,
          hasFailed: this.hasFailedDownloads(),
          onCancel: () => {
            this.closeDownloadStatusPanel();
          },
          onApply: () => {
            this.applyDownloadStatusFilter();
          },
          onClearFailed: () => {
            this.clearFailedDownloads();
          },
          onRetryFailed: () => {
            this.retryFailedDownloads();
          }
        })
          .zIndex(24)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }
      if (this.sortPanelVisible) {
        SettingsOptionPanel({
          title: 'Sort',
          summary: 'Author sorting uses artist tags; unknown authors are placed last.',
          value: this.sortMode,
          options: DOWNLOAD_SORT_OPTIONS,
          onBack: () => { this.sortPanelVisible = false; },
          onSelect: (value: string) => { this.applyDownloadSort(value); }
        })
          .zIndex(25)
      }
    }
    .id('download-list-pane')
    .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
    .height('100%')
    .backgroundColor(themePageBackground())
    .onTouch((event: TouchEvent) => {
      if (shouldUpdateSplitPaneFocus(event)) {
        this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
      }
    })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Left, distance: 28 })
        .onActionEnd((event: GestureEvent | undefined) => {
          this.handleOpenDownloadLabelDrawerPan(event);
        })
    )
    .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
  }

  build() {
    if (this.showTagSearch) {
      GalleryListScene({
        sceneTitle: this.tagSearchTitle.length > 0 ? this.tagSearchTitle : 'Search',
        listMode: 'Search',
        sourceRoute: GalleryRoute.Home,
        initialKeyword: this.tagSearchKeyword,
        initialSearchMode: this.tagSearchMode,
        initialSearchCategory: this.tagSearchCategory,
        initialAdvancedSearchEnabled: false,
        initialAdvanceSearch: DEFAULT_ADVANCE_SEARCH,
        initialSearchSubmitted: true,
        initialImagePath: this.tagSearchImagePath,
        initialCoverSearchSource: this.tagSearchCoverSource,
        initialImageUseSimilarityScan: this.tagSearchImageUseSimilarity,
        initialImageOnlySearchCovers: this.tagSearchImageOnlyCovers,
        initialImageShowExpunged: this.tagSearchImageShowExpunged,
        isSearchResultScene: true,
        onBack: () => {
          this.closeTagSearch();
        }
      })
        .transition(this.restoreDetailWithFade ?
          TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
          TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.downloadListPane()

        if (this.blockingBusyVisible) {
          BlockingBusyOverlay({ message: this.blockingBusyMessage,
            progressText: this.blockingBusyProgressText })
            .zIndex(40)
            .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
        }

        if (this.matchDialogVisible) {
          BlockingBusyOverlay({ message: this.blockingBusyMessage,
            progressText: this.blockingBusyProgressText,
            isDone: this.matchDialogDone,
            showStop: !this.matchDialogDone,
            showMinimize: !this.matchDialogDone,
            onStop: () => {
              downloadMatchService.requestStop();
            },
            onMinimize: () => {
              this.minimizeMatchDialog();
            },
            onDismiss: () => {
              this.dismissMatchDialog();
            },
            onScrimTap: () => {
              // F-120 红线：点弹窗外部=进行中切后台，完成态关闭（不放右上 ×）。
              if (this.matchDialogDone) {
                this.dismissMatchDialog();
              } else {
                this.minimizeMatchDialog();
              }
            } })
            .zIndex(40)
            .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
        }

        // 最小化圆点（F-120 重设计）：与 FAB 动作按钮同一套玻璃材质（44vp 圆、
        // 1px 高光边、接触阴影），进行中 spinner+百分比，完成态主题色对勾。
        if (this.matchDialogMinimized) {
          Stack({ alignContent: Alignment.Center }) {
            if (!this.matchDialogDone) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color(themePrimaryText())
              Text(Math.round(this.downloadMatchProgress.current * 100 /
                Math.max(1, this.downloadMatchProgress.total)).toString() + '%')
                .fontSize(9)
                .fontWeight(FontWeight.Medium)
                .fontColor(themePrimaryText())
                .position({ x: 0, y: 30 })
            } else {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor([themePrimaryColor()])
            }
          }
          .width(44)
          .height(44)
          .backgroundColor(uiPopupEffectBackground(themeSurface()))
          .backgroundEffect(uiGlassFloatingButtonEffect())
          .border(uiDockHighlightBorder())
          .shadow({ radius: 6, color: themeShadowColor(), offsetX: 0, offsetY: 2 })
          // 圆形（F-124 用户反馈：漏圆角成方块）+ 位置避开顶部搜索栏，
          // 悬浮在列表区右上（覆盖列表内容可接受，不覆盖功能控件）。
          .borderRadius(uiRadius(22))
          .clip(true)
          .position({ x: this.downloadContentWidth > 0 ? this.downloadContentWidth - 56 : 1160,
            y: this.statusBarVp() + 130 })
          .zIndex(40)
          .onClick(() => {
            this.restoreMatchDialog();
          })
        }

        if (this.showReader) {
          ReaderSessionScene({
            restoreAppChromeOnExit: true,
            onBack: () => {
              this.closeEmbeddedReader();
            }
          })
            .width('100%')
            .height('100%')
            .zIndex(50)
            .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))
        }
      if (this.showDetail || this.downloadLabelManagerVisible) {
        SplitPaneDivider({
          x: this.useSplitLayout() ? this.splitListPaneWidth() : 0,
          dividerVisible: this.useSplitLayout(),
          dragging: this.splitDragging,
          fadeTransition: this.restoreDetailWithFade,
          onSplitDragStart: () => {
            this.splitDragging = true;
            this.splitDragStartWidth = this.splitListPaneWidth();
          },
          onSplitDragUpdate: (offsetX: number) => {
            this.updateSplitPaneByOffset(offsetX);
          },
          onSplitDragEnd: () => {
            this.finishSplitPaneDrag();
          }
        })

      }

      if (this.dedupePanelVisible) {
        // F-123 非全屏卡片（用户要求）：普通用户直观的弹窗+列表+勾选。
        // 点弹窗外部关闭（红线）；点条目隐藏弹窗看图册，关详情自动恢复；
        // 底部按钮在卡片内，天然避开 dock 底栏。
        Stack({ alignContent: Alignment.Center }) {
          PopupScrim({
            onDismiss: () => {
              this.closeDedupePanel();
            }
          })

          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text(uiText('Duplicate check'))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(themePrimaryText())
              Blank()
              Text(uiStatusText(this.dedupeHeaderSummary()))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(themePrimaryText())
            }
            .width('100%')

            if (this.dedupeGroups.length === 0) {
              Text(uiText('No duplicates found'))
                .fontSize(13)
                .fontColor(themeSecondaryText())
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
            }

            Scroll() {
              Column({ space: 12 }) {
                ForEach(this.dedupeGroups, (members: DownloadInfo[]) => {
                  Column({ space: 6 }) {
                    ForEach(members, (member: DownloadInfo, memberIndex: number) => {
                      Row({ space: 8 }) {
                        // 行首勾选框（F-123 用户要求）：勾=标记删除，直观。
                        Checkbox({ name: this.dedupeKeyOf(member) })
                          .select(this.isDedupeMarked(member))
                          .selectedColor(themePrimaryColor())
                          .width(20)
                          .height(20)
                          .onChange((checked: boolean) => {
                            if (checked !== this.isDedupeMarked(member)) {
                              this.toggleDedupeMark(member);
                            }
                          })
                        Image(member.thumb)
                          .width(42)
                          .height(56)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(uiRadius(6))
                          .border({ width: 1, color: uiButtonHighlightBorderColor() })
                        Column({ space: 2 }) {
                          Text(member.title)
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(themePrimaryText())
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                          Text((member.total > 0 ? member.total : member.pages).toString() + 'P')
                            .fontSize(13)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(themeSecondaryText())
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                        // 行尾「查看」（F-123 用户要求：点列表中的图册即跳转）
                        Text(uiText('View'))
                          .fontSize(14)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(themePrimaryColor())
                          .flexShrink(0)
                      }
                      .width('100%')
                      .padding(8)
                      .borderRadius(uiRadius(8))
                      .backgroundColor(this.isDedupeMarked(member) ?
                        uiMaterialBackground(themeDangerBackground()) : themeSurface())
                      // 点条目主体 = 隐藏弹窗 → 打开图册详情（对比）→ 关详情自动恢复。
                      .onClick(() => {
                        this.hideDedupeForDetail();
                        this.openDetailNow(member);
                      })
                    }, (member: DownloadInfo) => this.dedupeKeyOf(member))
                  }
                  .width('100%')
                }, (members: DownloadInfo[]) => members[0].gid.toString())
              }
              .width('100%')
            }
            .constraintSize({ maxHeight: 330 })
            .width('100%')
            .scrollBar(BarState.Off)

            Row({ space: 10 }) {
              Button(uiText('Delete marked'))
                .layoutWeight(1)
                .height(40)
                .fontSize(13)
                .fontColor(uiMaterialForegroundColor(themeDangerText()))
                .backgroundColor(uiMaterialBackground(themeDangerBackground()))
                .enabled(this.dedupeMarked.length > 0)
                .onClick(() => {
                  this.applyDedupeDelete();
                })
              Button(uiText('Close'))
                .layoutWeight(1)
                .height(40)
                .fontSize(13)
                .fontColor(themePrimaryText())
                .backgroundColor(themeSurfaceVariant())
                .onClick(() => {
                  this.closeDedupePanel();
                })
            }
            .width('100%')
          }
          .width('92%')
          .constraintSize({ maxWidth: 480, maxHeight: '78%' })
          .padding(16)
          .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
          .shadow(uiDialogSurfaceShadow())
          .borderRadius(uiRadius(16))
          .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
          .systemMaterial(uiDialogMaterial())
          .zIndex(1)
        }
        .width('100%')
        .height('100%')
        .zIndex(30)
        .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }

      if (this.showDetail) {
        if (this.localDetailGid > 0) {
          LocalGalleryDetailScene({
            item: this.localDetailItem(),
            statusBarHeight: this.statusBarVp(),
            onBack: () => {
              this.closeDetail();
            },
            onRead: (index: number) => {
              this.openLocalReader(this.localDetailItem(), index);
            },
            onRemove: () => {
              this.confirmRemoveLocalGallery(this.localDetailItem());
            },
            onMetaRefreshed: (pages: number, bytes: number) => {
              this.applyLocalMeta(this.localDetailItem(), pages, bytes);
            }
          })
            // 详情面板按 gid 绑定身份：换一本图册必须重建组件，
            // 否则 @Prop 更新时机一慢，页面还停在上一本的预览与页数上（货不对板的另一半）。
            .id('local-detail-' + this.localDetailGid.toString())
            .width(this.useSplitLayout() ? this.splitSidePaneWidth() : '100%')
            .height('100%')
            .position({ x: this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0, y: 0 })
            .onTouch((event: TouchEvent) => {
              if (shouldUpdateSplitPaneFocus(event)) {
                this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
              }
            })
            .zIndex(5)
            .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
            .transition(this.restoreDetailWithFade ?
              TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
              TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
        } else {
          GalleryDetailHostScene({
            detailLink: this.detailLink,
            listRequestUrl: '',
            onBack: () => {
              this.closeDetail();
            },
            onShowEmbeddedReader: () => {
              this.showReader = true;
            },
            onOpenSearch: (request: DetailSearchRequest) => {
              this.openRemoteSearch(request);
            },
            onDetailLoaded: (detail: GalleryDetail) => {
              this.detail = detail;
              ehDownloadStore.updateGallery(detail);
              this.persistDownloads();
            }
          })
            .width(this.useSplitLayout() ? this.splitSidePaneWidth() : '100%')
            .height('100%')
            .position({ x: this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0, y: 0 })
            .onTouch((event: TouchEvent) => {
              if (shouldUpdateSplitPaneFocus(event)) {
                this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
              }
            })
            .zIndex(5)
            .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
            .transition(this.restoreDetailWithFade ?
              TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
              TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
        }
      }

      if (this.downloadLabelManagerVisible) {
        DownloadLabelManagerScene({
          labels: this.labels,
          statusBarHeight: this.statusBarVp(),
          onBack: () => {
            this.closeDownloadLabelManager();
          },
          onAdd: () => {
            this.openAddDownloadLabel();
          },
          onRename: (label: string, value: string) => {
            this.renameDownloadLabel(label, value);
          },
          onDelete: (label: string) => {
            this.confirmDeleteDownloadLabel(label);
          },
          onMove: (from: number, to: number) => {
            this.moveDownloadLabel(from, to);
          }
        })
          .width(this.useSplitLayout() ? this.splitSidePaneWidth() : '100%')
          .height('100%')
          .position({ x: this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0, y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          // F-120：从查重面板点条目进详情，详情层必须盖住查重面板(zIndex 30)。
          .zIndex(35)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 260, curve: Curve.EaseOut }),
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseIn })))
      }

      if (this.downloadLabelDrawerVisible) {
        RightSidePanelLayer({
          layerWidth: this.downloadListOverlayWidth(),
          drawerLeft: this.downloadLabelDrawerLeft(),
          drawerOffsetX: this.downloadLabelDrawerOffsetX,
          overlayOpacity: this.downloadLabelDrawerOverlayOpacity,
          layerZIndex: 30,
          onClose: () => {
            this.closeDownloadLabelDrawer();
          }
        }) {
          DownloadLabelDrawer({
            statusBarHeight: this.statusBarVp(),
            labels: this.labels,
            items: this.items,
            selectedLabel: this.selectedDownloadLabel,
            onSelect: (label: string) => {
              this.selectDownloadLabel(label);
            },
            onDefaultLabel: () => {
              this.openDefaultDownloadLabelDialog();
            },
            onSettings: () => {
              this.openDownloadLabelManager();
            }
          })
        }
      }

      if (this.defaultDownloadLabelDialogVisible) {
        DownloadLabelSelectionDialog({
          title: 'Default download label',
          labels: this.labels,
          selectedLabel: defaultDownloadLabelChoice() === DOWNLOAD_LABEL_OPTION_ASK ?
            DOWNLOAD_LABEL_OPTION_ASK : defaultDownloadLabelChoice(),
          includeAsk: true,
          panelMaxHeight: Math.max(320, this.viewportHeight - 24),
          onSelect: (label: string) => {
            this.selectDefaultDownloadLabel(label);
          },
          onClose: () => {
            this.defaultDownloadLabelDialogVisible = false;
          }
        })
          .width(this.downloadListOverlayWidth())
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(35)
      }

      if (this.moveDownloadLabelDialogVisible) {
        DownloadLabelSelectionDialog({
          title: 'Move to label',
          labels: this.labels,
          selectedLabel: '',
          includeAsk: false,
          showAddButton: true,
          panelMaxHeight: Math.max(320, this.viewportHeight - 24),
          onSelect: (label: string) => {
            this.moveSelectedDownloadsToLabel(label);
          },
          onAdd: () => {
            this.openAddDownloadLabel();
          },
          onClose: () => {
            this.moveDownloadLabelDialogVisible = false;
          }
        })
          .width(this.downloadListOverlayWidth())
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(35)
      }

      if (this.downloadLabelEditDialogVisible) {
        DownloadLabelEditDialog({
          title: 'New label',
          value: $downloadLabelEditValue,
          onConfirm: () => {
            this.confirmDownloadLabelEdit();
          },
          onClose: () => {
            this.downloadLabelEditDialogVisible = false;
          }
        })
          .width(this.moveDownloadLabelDialogVisible ?
            this.downloadListOverlayWidth() : this.downloadSideOverlayWidth())
          .height('100%')
          .position({
            x: this.moveDownloadLabelDialogVisible ? 0 : this.downloadSideOverlayLeft(),
            y: 0
          })
          .zIndex(36)
      }

      if (this.deleteConfirmVisible) {
        DownloadDeleteConfirmDialog({
          itemCount: this.deleteConfirmCount,
          cloudAvailable: this.deleteConfirmCloudAvailable,
          onRemoveRecords: () => {
            const selected = this.selectedDownloadItems();
            this.closeDeleteConfirm();
            this.removeSelectedRecordsOnly(selected);
          },
          onDeleteLocal: () => {
            const selected = this.selectedDownloadItems();
            this.closeDeleteConfirm();
            if (this.deleteConfirmCloudAvailable) {
              this.deleteSelectedLocalOnly(selected);
            } else {
              this.removeSelectedDownloads(selected);
            }
          },
          onDeleteCloud: () => {
            const selected = this.selectedDownloadItems();
            this.closeDeleteConfirm();
            this.deleteSelectedFromCloud(selected);
          },
          onClose: () => {
            this.closeDeleteConfirm();
          }
        })
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(70)
      }

      if (this.askVisible) {
        ConfirmActionOverlay({
          title: this.askTitle,
          message: this.askMessage,
          confirmLabel: this.askPrimaryLabel,
          altLabel: this.askSecondaryLabel,
          danger: this.askDanger,
          showCancel: this.askWithCancel,
          onCancel: () => {
            this.runAskCancel();
          },
          onConfirm: () => {
            this.runAskPrimary();
          },
          onAlt: () => {
            this.runAskSecondary();
          }
        })
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(72)
      }
      }
      .id('download-scene-root')
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateSceneContentWidth(areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value)));
      })
    }
  }

  private showDeleteProcessedZipDialog(result: DownloadZipImportResult): void {
    const message = uiStatusText('ZIP import summary: processed ' + result.processed.toString() + ', skipped ' +
      result.skipped.toString() + '. Delete processed archives?');
    this.askPaths = result.processedPaths;
    this.askConfirm('zipDelete', uiText('ZIP archives processed'), message,
      uiText('Delete'), uiText('Keep'), true, false);
  }
}

