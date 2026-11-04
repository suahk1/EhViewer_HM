import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

import { GalleryInfo, GallerySite } from '../model/GalleryModels';
import { reportAppOverlayHidden } from '../services/AppChromeSignal';
import { ehBookmarkStore } from '../services/EhBookmarkStore';
import { BrowsePositionsBackupInfo, ehBrowsePositionStore } from '../services/EhBrowsePositionStore';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
  DownloadMigrationProgress,
  ehDownloadFileStore
} from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { verifyMissingCloudGalleries } from '../services/DownloadCloudStateService';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { RemoteStorageProfile, remoteStorageProfileStore } from '../services/RemoteStorageProfiles';
import { remoteStorageSyncService } from '../services/RemoteStorageSyncService';
import { syncTombstoneStore } from '../services/SyncTombstoneStore';

import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import {
  DownloadMetadataRestoreResult,
  rebuildImportedHistoryMetadata,
} from '../services/DownloadMetadataRestore';
import {
  DownloadRestoreResult,
  DownloadZipImportResult,
  restoreDownloadedItemsAndArchives,
} from '../services/DownloadZipImportService';
import {
  importLocalGalleryFolder,
  LocalImportProgress,
  LocalImportReport,
} from '../services/LocalFolderImportService';
import {
  FLOATING_ACTION_HOLDING_HAND_REVISION_KEY,
  FLOATING_ACTION_HOLDING_HAND_SETTING_KEY,
  MULTI_DEVICE_CONTINUATION_SETTING_KEY,
  HISTORY_INFO_SIZE_KEY,
  appSettingsStore,
  historyInfoSizeLimitFromValue,
  normalizeHistoryInfoSizeOption,
  SettingImportResult,
  SettingEntry,
  defaultSettingEntries,
} from '../services/AppSettingsStore';
import {
  SavedTranslationApi,
  cloneSavedTranslationApis,
  createSavedTranslationApi,
  findSavedTranslationApi,
  parseCustomTranslationPromptProfiles,
  parseSavedTranslationApis,
  serializeSavedTranslationApis,
  TranslationPromptProfile,
  uniqueTranslationApiName,
} from '../services/TranslationSupport';
import {
  allReaderPresetProfiles,
  applyReaderPresetValues,
  findReaderPresetProfile,
  parseCustomReaderPresetProfiles,
  READER_CUSTOM_PRESETS_SETTING_KEY,
  ReaderPresetProfile,
} from '../services/ReaderPresetSupport';
import { EhHttpClient, NetworkDiagnosticResult } from '../services/EhHttpClient';
import {
  currentDnsOverHttpsStatusText,
  ensureEhHostRules,
  isEhDirectConnectionProbeEnabled,
  socks5ProxySupported,
  startEhDirectConnectionProbe,
  startEhFrontingBenchmark,
} from '../services/NetworkConfig';
import { EhUrl } from '../services/EhUrl';
import { saveUpdateHap, UpdateSaveResult } from '../services/UpdateDownloader';
import { releaseUpdateChecker, ReleaseInfo, UpdateCheckResult } from '../services/ReleaseUpdateChecker';
import {
  ehTagTranslationStore,
  EhTagTranslationUpdatePhase,
  EhTagTranslationUpdateResult,
} from '../services/EhTagTranslationStore';
import {
  activeTranslationProvider,
  ehTranslationService,
} from '../services/EhTranslationService';
import {
  TRANSLATION_CONVERSATION_LOG_SETTING_KEY,
  translationConversationLog,
} from '../services/TranslationConversationLog';
import {
  READER_OCR_DEBUG_LOG_SETTING_KEY,
  readerOcrDebugLog,
} from '../services/ReaderOcrDebugLog';
import { galleryPageCache } from '../services/GalleryPageCache';
import { CacheClearResult, CachePruneResult, readerImageCache } from '../services/ReaderImageCache';
import { galleryThumbnailDecodeCache } from '../services/GalleryThumbnailDecodeCache';
import { FilterRule, FILTER_MODE_RATING, FILTER_MODE_TITLE, FILTER_RULE_REVISION_KEY, ehFilterStore } from '../services/EhFilterStore';
import { ehCommentBlacklistStore } from '../services/EhCommentBlacklistStore';
import {
  applyAppChromeImmersiveMode,
  applyAppColorMode,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp,
} from '../services/WindowChromeController';
import { applyWindowPrivacyMode } from '../services/WindowPrivacy';
import { appLog } from '../services/AppLogService';
import { applyMissionContinuationSetting } from '../services/DistributedContinuationService';
import { parseErrorBodyStore, ParseErrorBodyEntry } from '../services/ParseErrorBodyStore';
import {
  AndroidDataImportSummary,
  importAndroidDatabaseBackup,
  isAndroidDatabaseBackup,
  isAndroidDatabaseFile,
  importAndroidDatabaseBackupFromUri,
} from '../services/AndroidDataImporter';
import {
  APP_VERSION_CODE,
  APP_VERSION_NAME,
  APP_AUTHOR_NAME,
  APP_AUTHOR_URL,
  EH_ISSUES_URL,
  EH_RELEASE_URL,
  EH_DONATE_URL,
  EH_REPOSITORY_CONFIGURED,
  EH_REPOSITORY_URL,
  TARGET_PLATFORM,
} from '../services/AppBuildInfo';
import {
  IDENTITY_AUTH_LOCKED_KEY,
  LANGUAGE_REVISION_KEY,
  notifyGalleryTitleChanged,
  notifyLanguageChanged,
  notifyThemeChanged,
  diagnosticTimestamp
} from '../shared/AppRuntime';
import {
  currentThemeName,
  themePageBackground,
  themeAccentTextColor,
  themeSecondaryText,
} from '../shared/AppPalette';
import { EhBackupBundle, SessionMode, SettingsRowItem, SettingsPanel, SETTINGS_HEADERS, uiText, uiStatusText, setActiveBackHandler, padTwo, getAbilityContext, downloadSizeText, settingEntryValue, cloneStringOptions, isValidProxyHostText, isValidProxyPortText, normalizeProxyOption, formatNetworkDiagnostics, normalizeIdentityAuthenticationOption, normalizeReaderCacheSizeOption } from '../shared/AppRuntime';
import { FilterPanel } from './FilterPanel';
import { BlockingBusyOverlay } from './BlockingBusyOverlay';
import { ConfirmActionOverlay } from './ConfirmActionOverlay';
import { DonateOverlay } from './DonateOverlay';
import { ResultOverlay } from './ResultOverlay';
import { MyTagsPanel } from './MyTagsPanel';
import { ReaderPresetPanel } from './ReaderPresetPanel';
import {
  captureEhAccountWebCookies,
  clearWebSessionCookies,
  prepareEhAccountWebViewCookies,
  SessionScene,
} from './SessionScene';
import { UpdatePromptOverlay } from './UpdatePromptOverlay';
import { WifiMigrationPanel } from './WifiMigrationPanel';
import { RemoteStoragePanel } from './RemoteStoragePanel';
import { CommentBlacklistPanel } from './CommentBlacklistPanel';
import {
  areaDimensionToVp,
  markCurrentRouteRightPane,
  normalizeSplitPaneFocus,
  saveSplitPaneRatio,
  SPLIT_PANE_BREAKPOINT,
  SPLIT_PANE_FOCUS_LEFT,
  SPLIT_PANE_FOCUS_RIGHT,
  SPLIT_PANE_MODAL_Z_INDEX,
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
  DIAGNOSTIC_LOG_TAG,
  EH_LICENSE_URL,
  isDirectTranslationApiKey,
  cleanErrorMessage,
  isCustomTranslationApiField,
  isTranslationSettingKey,
  normalizeSettingsDownloadLocation,
  pickDownloadsOutputPath,
  writeTextFileChunked,
  isNetworkSettingKey,
  normalizeProxyExclusionListText,
  proxyDiagnosticText,
  settingDisplayValueForStatus,
  feedbackIssueUrl,
  errorText,
} from './SettingsSupport';
import {
  ProxySettingsOverlay,
  DownloadMigrationConfirmOverlay,
  TranslationPromptPanel,
} from './SettingsOverlays';
import {
  SettingsHomePanel,
  SettingsAccountWebPanel,
  SettingsSubToolbar,
  SettingsDetailPanel,
  SettingsOptionPanel,
} from './SettingsPanels';

const SYNC_SECTION_READER_PRESETS: string = 'readerPresets';
const SYNC_SECTION_TRANSLATION_PROMPTS: string = 'translationPrompts';

function cloneSettingsPanelStack(stack: SettingsPanel[]): SettingsPanel[] {
  const result: SettingsPanel[] = [];
  for (let i = 0; i < stack.length; i++) {
    result.push(stack[i]);
  }
  return result;
}

interface SettingsNavigationCache {
  activeSplitPane: string;
  panel: SettingsPanel;
  panelStack: SettingsPanel[];
  webViewUrl: string;
  webViewTitle: string;
  filterNewText: string;
  filterNewMode: number;
  sessionInitialMode: SessionMode;
  homeScrollOffset: number;
  detailScrollOffsets: Map<string, number>;
}

let settingsNavigationCache: SettingsNavigationCache | null = null;
let settingsHomeScrollOffset: number = 0;
const settingsDetailScrollOffsets: Map<string, number> = new Map<string, number>();


@Component
export struct SettingsScene {
  @State panel: SettingsPanel = SettingsPanel.Main;
  @State panelStack: SettingsPanel[] = [SettingsPanel.Main];
  @State signedIn: boolean = ehCookieStore.hasCookies();
  @State statusText: string = '';
  @State blockingBusyVisible: boolean = false;
  // 长任务在跑标记：重复点击直接忽略，避免清理类操作被执行两次（R8）
  private runningAction: string = '';
  @State blockingBusyMessage: string = 'Loading...';
  @State blockingBusyProgressText: string = '';
  @State blockingBusyProgressCurrent: number = -1;
  @State blockingBusyProgressTotal: number = -1;
  @State themeName: string = 'Light';
  @State settingEntries: SettingEntry[] = defaultSettingEntries();
  @State optionPickerOpen: boolean = false;
  @State optionKey: string = '';
  @State optionTitle: string = '';
  @State optionSummary: string = '';
  @State optionValue: string = '';
  @State optionOptions: string[] = [];
  @State optionDescriptions: string[] = [];
  @State optionAllowCustomInput: boolean = false;
  @State proxySettingsOpen: boolean = false;
  @State downloadMigrationDialogOpen: boolean = false;
  @State downloadMigrationCurrent: string = DOWNLOAD_LOCATION_APP_FILES;
  @State downloadMigrationTarget: string = DOWNLOAD_LOCATION_APP_FILES;
  @State signOutConfirmationVisible: boolean = false;
  // 结果弹窗：功能跑完后必须让用户看清结果并点确认（点弹窗外也可关闭）。
  @State resultVisible: boolean = false;
  @State resultTitle: string = '';
  @State resultMessage: string = '';
  @State resultAltLabel: string = '';
  @State resultConfirmLabel: string = 'OK';
  private resultAltAction: () => void = () => {};
  private resultConfirmAction: () => void = () => {};
  @State webViewUrl: string = '';
  @State webViewTitle: string = '';
  @State filterRules: FilterRule[] = [];
  @State filterNewText: string = '';
  @State filterNewMode: number = FILTER_MODE_TITLE;
  @State settingsRenderRevision: number = 0;
  @State sceneContentWidth: number = 0;
  @State splitListRatio: number = splitPaneCurrentRatio();
  @State splitDragging: boolean = false;
  @State activeSplitPane: string = SPLIT_PANE_FOCUS_LEFT;
  @State restorePanelWithFade: boolean = false;
  @State updateDialogVisible: boolean = false;
  @State donateVisible: boolean = false;
  @State updateCurrentVersion: string = '';
  @State updateRelease: ReleaseInfo | null = null;
  @State sessionInitialMode: SessionMode = SessionMode.Password;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  private client: EhHttpClient = new EhHttpClient();
  private splitDragStartWidth: number = 0;
  private modelPickerRequestVersion: number = 0;
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
  onMenu: () => void = () => {};
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.syncSceneContentWidthFromWindow();
    this.restoreNavigationCache();
    // 缓存里可能停在子面板，恢复后要按实际面板上报，否则底坞会压在子面板上。
    reportAppOverlayHidden(this.panel !== SettingsPanel.Main);
    markCurrentRouteRightPane(this.useSplitLayout());
    setActiveBackHandler(() => this.handleSystemBack());
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.ensureLoaded(context).then(() => {
        this.signedIn = ehCookieStore.hasCookies();
        this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      }).catch((error: Error) => {
        this.statusText = 'Cookie load failed: ' + errorText(error);
      });
      appSettingsStore.ensureLoaded(context).then(() => {
        this.settingEntries = appSettingsStore.getEntries();
        this.themeName = currentThemeName();
      }).catch((error: Error) => {
        this.statusText = 'Settings load failed: ' + errorText(error);
      });
      ehDownloadStore.ensureLoaded(context).then(() => {
        this.settingsRenderRevision++;
      }).catch(() => {
      });
    } else {
      this.signedIn = ehCookieStore.hasCookies();
      this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      this.settingEntries = appSettingsStore.getEntries();
      this.themeName = currentThemeName();
    }
  }

  aboutToDisappear(): void {
    this.saveNavigationCache();
    // 离开设置页时浮层状态一并归还，避免底坞停在收起位。
    reportAppOverlayHidden(false);
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.blockingBusyVisible) {
      return true;
    }
    if (this.signOutConfirmationVisible) {
      this.signOutConfirmationVisible = false;
      return true;
    }
    if (this.proxySettingsOpen) {
      this.closeProxySettings();
      return true;
    }
    if (this.optionPickerOpen) {
      this.closeOptionPicker();
      return true;
    }
    if (this.downloadMigrationDialogOpen) {
      this.closeDownloadMigrationDialog();
      return true;
    }
    if (this.updateDialogVisible) {
      this.updateDialogVisible = false;
      return true;
    }
    if (this.panel !== SettingsPanel.Main) {
      this.closePanel();
      return true;
    }
    return false;
  }

  private resetToTopLevel(): void {
    this.optionPickerOpen = false;
    this.proxySettingsOpen = false;
    this.downloadMigrationDialogOpen = false;
    this.signOutConfirmationVisible = false;
    this.updateDialogVisible = false;
    this.webViewUrl = '';
    this.webViewTitle = '';
    this.sessionInitialMode = SessionMode.Password;
    this.panel = SettingsPanel.Main;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.panelStack = [SettingsPanel.Main];
    this.restorePanelWithFade = false;
    markCurrentRouteRightPane(false);
    this.restoreBackHandler();
    this.clearNavigationCache();
  }

  private openPanel(panel: SettingsPanel): void {
    this.restorePanelWithFade = false;
    // 子面板铺满整页，底坞继续浮在上面会压住内容，和列表滚动收起用同一个信号。
    reportAppOverlayHidden(panel !== SettingsPanel.Main);
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.optionPickerOpen = false;
    this.proxySettingsOpen = false;
    if (this.panel === panel) {
      return;
    }
    const nextStack: SettingsPanel[] = [];
    for (let i = 0; i < this.panelStack.length; i++) {
      nextStack.push(this.panelStack[i]);
    }
    nextStack.push(panel);
    this.panelStack = nextStack;
    this.panel = panel;
    markCurrentRouteRightPane(this.useSplitLayout());
    this.saveNavigationCache();
    this.restoreBackHandler();
  }

  private openPrimaryPanel(panel: SettingsPanel): void {
    this.restorePanelWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.optionPickerOpen = false;
    this.proxySettingsOpen = false;
    if (splitPaneModeEnabled() && this.sceneContentWidth >= SPLIT_PANE_BREAKPOINT) {
      this.panelStack = [SettingsPanel.Main, panel];
      this.panel = panel;
      markCurrentRouteRightPane(this.useSplitLayout());
      this.saveNavigationCache();
      this.restoreBackHandler();
      return;
    }
    this.openPanel(panel);
  }

  private closePanel(): void {
    this.restorePanelWithFade = false;
    this.optionPickerOpen = false;
    if (this.panelStack.length <= 1) {
      this.panelStack = [SettingsPanel.Main];
      this.panel = SettingsPanel.Main;
      this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    } else {
      const nextStack: SettingsPanel[] = [];
      for (let i = 0; i < this.panelStack.length - 1; i++) {
        nextStack.push(this.panelStack[i]);
      }
      this.panelStack = nextStack.length > 0 ? nextStack : [SettingsPanel.Main];
      this.panel = this.panelStack[this.panelStack.length - 1];
    }
    this.signedIn = ehCookieStore.hasCookies();
    // 必须在 panel 改成目标值之后上报：用旧 panel 上报会让底坞一直保持收起。
    reportAppOverlayHidden(this.panel !== SettingsPanel.Main);
    markCurrentRouteRightPane(this.useSplitLayout());
    this.saveNavigationCache();
    this.restoreBackHandler();
  }

  private restoreNavigationCache(): void {
    if (settingsNavigationCache === null) {
      return;
    }
    this.panel = settingsNavigationCache.panel;
    this.activeSplitPane = normalizeSplitPaneFocus(settingsNavigationCache.activeSplitPane,
      settingsNavigationCache.panel !== SettingsPanel.Main);
    this.panelStack = cloneSettingsPanelStack(settingsNavigationCache.panelStack);
    this.webViewUrl = settingsNavigationCache.webViewUrl;
    this.webViewTitle = settingsNavigationCache.webViewTitle;
    this.filterNewText = settingsNavigationCache.filterNewText;
    this.filterNewMode = settingsNavigationCache.filterNewMode;
    this.sessionInitialMode = settingsNavigationCache.sessionInitialMode;
    settingsHomeScrollOffset = Math.max(0, settingsNavigationCache.homeScrollOffset);
    settingsDetailScrollOffsets.clear();
    settingsNavigationCache.detailScrollOffsets.forEach((offset: number, key: string) => {
      settingsDetailScrollOffsets.set(key, Math.max(0, offset));
    });
    this.restorePanelWithFade = this.settingsDetailLayerPanel() !== SettingsPanel.Main && shouldFadeRestoredRightPane();
  }

  private saveNavigationCache(): void {
    settingsNavigationCache = {
      activeSplitPane: this.activeSplitPane,
      panel: this.panel,
      panelStack: cloneSettingsPanelStack(this.panelStack),
      webViewUrl: this.webViewUrl,
      webViewTitle: this.webViewTitle,
      filterNewText: this.filterNewText,
      filterNewMode: this.filterNewMode,
      sessionInitialMode: this.sessionInitialMode,
      homeScrollOffset: settingsHomeScrollOffset,
      detailScrollOffsets: new Map<string, number>(settingsDetailScrollOffsets)
    };
  }

  private updateHomeScrollOffset(offset: number): void {
    settingsHomeScrollOffset = Math.max(0, offset);
    this.saveNavigationCache();
  }

  private updateDetailScrollOffset(panel: SettingsPanel, offset: number): void {
    settingsDetailScrollOffsets.set(panel, Math.max(0, offset));
    this.saveNavigationCache();
  }

  private clearNavigationCache(): void {
    settingsNavigationCache = null;
    settingsHomeScrollOffset = 0;
    settingsDetailScrollOffsets.clear();
  }

  private restoreBackHandler(): void {
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private settingsDetailLayerPanel(): SettingsPanel {
    for (let i = this.panelStack.length - 1; i >= 0; i--) {
      // Keep the ordinary settings list mounted while a deeper page covers it.
      for (let j = 0; j < SETTINGS_HEADERS.length; j++) {
        if (this.panelStack[i] === SETTINGS_HEADERS[j].panel) {
          return this.panelStack[i];
        }
      }
    }
    return SettingsPanel.Main;
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
    rememberMainContentWidthVp(normalized);
    markCurrentRouteRightPane(this.useSplitLayout());
  }

  private syncSceneContentWidthFromWindow(): void {
    const width = mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    if (width >= 240) {
      this.updateSceneContentWidth(width);
    }
  }

  onSplitPaneRatioRevisionChange(): void {
    if (!this.splitDragging) {
      this.splitListRatio = splitPaneCurrentRatio();
    }
  }

  private useSplitLayout(): boolean {
    return splitPaneModeEnabled() && this.sceneContentWidth >= SPLIT_PANE_BREAKPOINT &&
      this.settingsDetailLayerPanel() !== SettingsPanel.Main;
  }

  private splitListPaneWidth(): number {
    return splitPaneListWidth(this.sceneContentWidth, this.splitListRatio);
  }

  private splitSidePaneWidth(): number {
    if (!this.useSplitLayout()) {
      return this.sceneContentWidth > 0 ? this.sceneContentWidth : 0;
    }
    return splitPaneSideWidth(this.sceneContentWidth, this.splitListPaneWidth());
  }

  private settingsLayerWidth(): number | string {
    return this.useSplitLayout() ? this.splitSidePaneWidth() : '100%';
  }

  private settingsLayerTranslateX(): number {
    return this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0;
  }

  private updateSplitPaneByOffset(offsetX: number): void {
    const targetWidth = splitPaneWidthFromDrag(this.sceneContentWidth, this.splitDragStartWidth, offsetX);
    const nextSplitRatio = splitPaneRatioForWidth(this.sceneContentWidth, targetWidth);
    if (Math.abs(nextSplitRatio - this.splitListRatio) < 0.0005) {
      return;
    }
    this.splitListRatio = nextSplitRatio;
  }

  private finishSplitPaneDrag(): void {
    this.splitDragging = false;
    saveSplitPaneRatio(this.splitListRatio);
  }

  private currentGallerySite(): GallerySite {
    return appSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? GallerySite.Ex : GallerySite.E;
  }

  private signOut(): void {
    this.signOutConfirmationVisible = false;
    clearWebSessionCookies(false);
    clearWebSessionCookies(true);
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clear();
      this.signedIn = false;
      this.statusText = 'Signed out in memory';
      return;
    }

    ehCookieStore.clearPersisted(context).then(() => {
      this.signedIn = false;
      this.statusText = 'Signed out';
    }).catch((error: Error) => {
      this.statusText = 'Sign out failed: ' + errorText(error);
    });
  }

  private saveSettingValue(key: string, value: string): void {
    if (key === 'download_location') {
      if (value === 'Remote server') {
        this.commitSettingValue(key, value);
        return;
      }
      this.requestDownloadLocationChange(value);
      return;
    }
    this.commitSettingValue(key, value);
  }

  private updateSettingDraft(key: string, value: string): void {
    if (isDirectTranslationApiKey(key)) {
      appSettingsStore.setValue(key, value);
    }
  }

  private commitSettingValue(key: string, value: string): void {
    if (this.updateCustomTranslationApiField(key, value)) {
      return;
    }
    if (key === 'proxy_host' && !isValidProxyHostText(value)) {
      this.statusText = 'Invalid proxy host: ' + value;
      return;
    }
    if (key === 'proxy_port' && value.length > 0 && !isValidProxyPortText(value)) {
      this.statusText = 'Invalid proxy port: ' + value;
      return;
    }
    const normalizedValue = this.normalizedSettingValue(key, value);
    const previousValue = appSettingsStore.getValue(key, '');
    appSettingsStore.setValue(key, normalizedValue);
    if (key === MULTI_DEVICE_CONTINUATION_SETTING_KEY) {
      applyMissionContinuationSetting(getAbilityContext());
    }
    if (key === FLOATING_ACTION_HOLDING_HAND_SETTING_KEY && normalizedValue !== previousValue) {
      const revision = AppStorage.get<number>(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY) ?? 0;
      AppStorage.setOrCreate<number>(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY, revision + 1);
    }
    if (key === TRANSLATION_CONVERSATION_LOG_SETTING_KEY && normalizedValue !== 'On') {
      translationConversationLog.clear(getAbilityContext());
    }
    if (key === READER_OCR_DEBUG_LOG_SETTING_KEY && normalizedValue !== 'On') {
      readerOcrDebugLog.clear(getAbilityContext());
    }
    if (key === 'translation_ai_provider' && normalizedValue === 'Custom API') {
      this.ensureCustomTranslationApi();
    }
    if (key === 'translation_buttons_enabled' && normalizedValue !== 'On') {
      ehTranslationService.setEnabled(false);
    }
    if (key === 'translation_buttons_enabled' && normalizedValue === 'On' && previousValue !== 'On') {
      this.showToast('The translation toggle is in the lower-right toolbar');
    }
    if (isTranslationSettingKey(key)) {
      ehTranslationService.clearCache();
    }
    if (key === 'reading_direction' && normalizedValue === 'Top to bottom' &&
      appSettingsStore.getValue('adaptive_dual_page', 'Off') !== 'On') {
      appSettingsStore.setValue('screen_rotation', 'Default');
      appSettingsStore.setValue('page_scaling', 'Fixed scale');
    }
    this.settingEntries = appSettingsStore.getEntries();
    this.themeName = currentThemeName();
    if (key === this.optionKey) {
      this.optionValue = normalizedValue;
    }
    if (key === 'app_language' || key === 'show_tag_translations') {
      notifyLanguageChanged();
    }
    if (key === 'app_language') {
      this.showFloatingStatus(uiText('Restart the app to apply the new language'));
    }
    if (key === 'show_jpn_title') {
      notifyGalleryTitleChanged();
    }
    if (key === 'display_mode' || key === 'theme_color') {
      notifyThemeChanged();
      this.settingsRenderRevision++;
      applyAppChromeImmersiveMode();
      applyAppColorMode(getAbilityContext());
    }
    if (key === 'pattern_protection') {
      if (normalizedValue === 'Off') {
        AppStorage.setOrCreate<boolean>(IDENTITY_AUTH_LOCKED_KEY, false);
      }
      this.statusText = normalizedValue === 'Off'
        ? 'Identity authentication disabled'
        : 'Identity authentication mode: ' + normalizedValue;
    }
    if (key === 'enable_secure') {
      applyWindowPrivacyMode(value === 'On', (status: string) => {
        this.statusText = status;
      }, getAbilityContext());
    }
    if (isNetworkSettingKey(key)) {
      this.refreshNetworkRuntime();
    }
    const context = getAbilityContext();
    if (context === undefined) {
      if (key === HISTORY_INFO_SIZE_KEY) {
        ehHistoryStore.trim(historyInfoSizeLimitFromValue(normalizedValue));
      }
      const displayValue = settingDisplayValueForStatus(key, normalizedValue);
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting in memory: ' + key + ' = ' + displayValue +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved in memory: ' + key + ' = ' + displayValue;
      return;
    }
    let cachePrune: Promise<CachePruneResult | null> = Promise.resolve(null);
    if (key === 'read_cache_size') {
      cachePrune = readerImageCache.pruneAsync(context);
      this.settingsRenderRevision++;
    }
    if (key === HISTORY_INFO_SIZE_KEY) {
      ehHistoryStore.ensureLoaded(context).then(() => {
        ehHistoryStore.trim(historyInfoSizeLimitFromValue(normalizedValue));
        ehHistoryStore.save(context).catch(() => {});
      }).catch(() => {});
    }
    appSettingsStore.save(context).then(() => cachePrune).then((pruned: CachePruneResult | null) => {
      const displayValue = settingDisplayValueForStatus(key, normalizedValue);
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting: ' + key + ' = ' + displayValue +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved: ' + key + ' = ' + displayValue;
      if (key === 'display_mode' || key === 'theme_color') {
        this.statusText = 'Theme refreshed';
      }
      if (pruned !== null && key === 'read_cache_size') {
        this.settingsRenderRevision++;
        this.statusText = 'Cache limit saved: ' + normalizedValue + '. Cleared oldest cache: ' +
          downloadSizeText(pruned.bytes) + '.';
      }
    }).catch((error: Error) => {
      this.statusText = 'Save failed: ' + errorText(error);
    });
  }

  private normalizedSettingValue(key: string, value: string): string {
    const adaptiveDualPage = key === 'adaptive_dual_page' ? value === 'On' :
      settingEntryValue(this.settingEntries, 'adaptive_dual_page', 'Off') === 'On';
    if (adaptiveDualPage && key === 'screen_rotation' && value === 'Match image') {
      return 'Default';
    }
    if (adaptiveDualPage && key === 'reading_direction' && value === 'Top to bottom') {
      return 'Right to left';
    }
    if (adaptiveDualPage && key === 'page_scaling') {
      return 'Fit screen';
    }
    if (key === 'screen_rotation' &&
      settingEntryValue(this.settingEntries, 'reading_direction', 'Right to left') === 'Top to bottom' &&
      value === 'Match image') {
      return 'Default';
    }
    if (key === 'page_scaling' &&
      settingEntryValue(this.settingEntries, 'reading_direction', 'Right to left') === 'Top to bottom' &&
      (value === 'Fit height' || value === 'Fit screen')) {
      return 'Fixed scale';
    }
    if (key === 'pattern_protection') {
      return normalizeIdentityAuthenticationOption(value);
    }
    if (key === 'read_cache_size') {
      return normalizeReaderCacheSizeOption(value);
    }
    if (key === HISTORY_INFO_SIZE_KEY) {
      return normalizeHistoryInfoSizeOption(value);
    }
    if (key === 'detail_size') {
      if (value === 'Default') {
        return 'Medium';
      }
      if (value === 'Compact' || value === 'Medium' || value === 'Loose') {
        return value;
      }
      if (value === 'Large') {
        return 'Loose';
      }
      return 'Medium';
    }
    if (key === 'thumb_size') {
      if (value === 'Small' || value === 'Medium' || value === 'Large' || value === 'XLarge') {
        return value;
      }
      return 'Medium';
    }
    if (key === 'proxy') {
      return normalizeProxyOption(value);
    }
    if (key === 'proxy_host') {
      return value.trim();
    }
    if (key === 'proxy_port') {
      return value.trim();
    }
    if (key === 'proxy_exclusion_list') {
      return normalizeProxyExclusionListText(value);
    }
    return value;
  }

  private requestDownloadLocationChange(value: string): void {
    const target = normalizeSettingsDownloadLocation(value);
    const current = normalizeSettingsDownloadLocation(appSettingsStore.getValue('download_location', DOWNLOAD_LOCATION_APP_FILES));
    if (target === current) {
      this.commitSettingValue('download_location', target);
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download location needs app context';
      return;
    }
    this.statusText = target === DOWNLOAD_LOCATION_DOWNLOADS ? 'Preparing public Downloads access...' :
      'Preparing app internal storage...';
    this.prepareDownloadLocationTarget(context, target).then((ready: boolean) => {
      if (!ready) {
        return;
      }
      this.showDownloadLocationMigrationDialog(current, target);
    }).catch((error: Error) => {
      this.statusText = 'Download location change failed: ' + errorText(error);
    });
  }

  private async prepareDownloadLocationTarget(context: common.UIAbilityContext, target: string): Promise<boolean> {
    return this.ensureDownloadLocationAccess(context, target);
  }

  private async ensureDownloadLocationAccess(context: common.UIAbilityContext, location: string): Promise<boolean> {
    const normalized = normalizeSettingsDownloadLocation(location);
    if (normalized === DOWNLOAD_LOCATION_APP_FILES) {
      return true;
    }
    if (ehDownloadFileStore.canUseLocation(context, normalized)) {
      return true;
    }
    const pickedRoot = await this.pickDownloadDirectoryRoot(context);
    if (pickedRoot.length > 0) {
      ehDownloadFileStore.rememberPublicDownloadRoot(pickedRoot);
      if (ehDownloadFileStore.canUseLocation(context, normalized)) {
        return true;
      }
    }
    this.statusText = 'Downloads access was not granted';
    return false;
  }

  private async pickDownloadDirectoryRoot(context: common.UIAbilityContext): Promise<string> {
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

  private showDownloadLocationMigrationDialog(current: string, target: string): void {
    this.downloadMigrationCurrent = current;
    this.downloadMigrationTarget = target;
    this.downloadMigrationDialogOpen = true;
  }

  private closeDownloadMigrationDialog(): void {
    this.downloadMigrationDialogOpen = false;
  }

  private applyDownloadLocationChange(context: common.UIAbilityContext, current: string, target: string,
    migrate: boolean): void {
    this.applyDownloadLocationChangeAsync(context, current, target, migrate).catch((error: Error) => {
      this.hideBlockingBusy();
      this.statusText = 'Download migration failed: ' + errorText(error);
    });
  }

  private chooseDownloadLocationMigration(migrate: boolean): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download location needs app context';
      return;
    }
    this.applyDownloadLocationChange(context, this.downloadMigrationCurrent, this.downloadMigrationTarget, migrate);
  }

  private async applyDownloadLocationChangeAsync(context: common.UIAbilityContext, current: string, target: string,
    migrate: boolean): Promise<void> {
    this.closeDownloadMigrationDialog();
    this.showBlockingBusy(migrate ? 'Migrating downloaded files...' : 'Switching download location...');
    if (migrate) {
      try {
        if (!await this.ensureDownloadLocationAccess(context, current)) {
          this.hideBlockingBusy();
          return;
        }
        if (!await this.ensureDownloadLocationAccess(context, target)) {
          this.hideBlockingBusy();
          return;
        }
        const result = await ehDownloadFileStore.migrateDownloadLocation(context, current, target,
          (progress: DownloadMigrationProgress) => {
            this.updateDownloadMigrationProgress(progress);
          });
        this.hideBlockingBusy();
        this.showFloatingStatus(result.cleanupIncomplete
          ? 'Downloads copied; new location selected. Some old files remain and can be cleaned up manually.'
          : 'Migrated downloads: ' + result.files.toString() + ' files, ' + downloadSizeText(result.bytes) + '.');
      } catch (error) {
        this.hideBlockingBusy();
        this.showFloatingStatus('Download migration failed: ' + String(error));
        return;
      }
    } else {
      this.hideBlockingBusy();
      this.showFloatingStatus('Download location switched without migration');
    }
    this.commitSettingValue('download_location', target);
  }

  private cycleSetting(row: SettingsRowItem): void {
    if (row.key === undefined) {
      this.statusText = row.title + ' is not available';
      return;
    }
    // 诊断用：确认点击是否进到这里、动作有没有被消费、有没有可选项。
    // 排查「点了没反应」时先看 hilog 里有没有这行。
    const statusBefore = this.statusText;
    const actionHandled = this.runSettingAction(row.key);
    console.info('[SettingsTap] key=' + row.key + ' type=' + row.type +
      ' options=' + (row.options === undefined ? -1 : row.options.length) +
      ' action=' + actionHandled);
    if (actionHandled) {
      // 多数 action 只把结果写进 statusText，而这个字段在界面上没有渲染位置，
      // 表现为「点了没反应」。这里统一把新产生的状态提示出来。
      if (this.statusText !== statusBefore && this.statusText.length > 0) {
        this.showToast(this.statusText);
      }
      return;
    }
    if (row.type === 'model') {
      this.openTranslationModelPicker(row);
      return;
    }
    // 开关行没有 options，若先判 options 就会被“暂不可用”吃掉，永远切不动。
    if (row.type === 'switch') {
      this.saveSettingValue(row.key, row.value === 'On' ? 'Off' : 'On');
      return;
    }
    if (row.options === undefined || row.options.length === 0) {
      console.info('[SettingsTap] no options, showing status only: ' + row.key);
      this.statusText = row.title + ' is not available yet';
      this.showToast(this.statusText);
      return;
    }
    this.openOptionPicker(row);
  }

  private openOptionPicker(row: SettingsRowItem): void {
    console.info('[SettingsTap] openOptionPicker ' + (row.key ?? ''));
    if (row.key === undefined || row.options === undefined || row.options.length === 0) {
      this.statusText = row.title + ' is not available';
      return;
    }
    this.optionKey = row.key;
    this.optionTitle = row.title;
    this.optionSummary = row.summary;
    this.optionValue = row.value;
    this.optionOptions = cloneStringOptions(row.options);
    this.optionDescriptions = row.optionDescriptions === undefined ? [] : cloneStringOptions(row.optionDescriptions);
    this.optionAllowCustomInput = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.optionPickerOpen = true;
    this.statusText = '';
  }

  private openAccountWebPage(title: string, url: string): void {
    this.prepareAccountWebViewCookies(url);
    this.webViewUrl = url;
    this.webViewTitle = title;
    this.openPanel(SettingsPanel.WebView);
  }

  private prepareAccountWebViewCookies(url: string): void {
    prepareEhAccountWebViewCookies(url);
  }

  private captureAccountWebCookies(url: string): void {
    if (!captureEhAccountWebCookies(url)) {
      return;
    }

    this.signedIn = ehCookieStore.hasCookies();
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehCookieStore.save(context).catch(() => {
    });
  }

  private closeOptionPicker(): void {
    this.modelPickerRequestVersion++;
    this.optionPickerOpen = false;
    this.optionKey = '';
    this.optionTitle = '';
    this.optionSummary = '';
    this.optionValue = '';
    this.optionOptions = [];
    this.optionDescriptions = [];
    this.optionAllowCustomInput = false;
    this.restoreBackHandler();
  }

  private selectOptionValue(value: string): void {
    if (this.optionKey.length === 0) {
      this.statusText = 'No setting is selected';
      return;
    }
    if (this.optionKey === 'translation_custom_api_selected' && value === 'New...') {
      this.createAndSelectCustomTranslationApi();
    } else {
      this.saveSettingValue(this.optionKey, value);
    }
    this.closeOptionPicker();
  }

  private openTranslationModelPicker(row: SettingsRowItem): void {
    if (row.key === undefined) {
      return;
    }
    const provider = activeTranslationProvider();
    const requestVersion = ++this.modelPickerRequestVersion;
    this.optionKey = row.key;
    this.optionTitle = row.title;
    this.optionSummary = row.summary;
    this.optionValue = row.value;
    this.optionOptions = row.value.trim().length > 0 ? [row.value.trim()] : [];
    this.optionDescriptions = [];
    this.optionAllowCustomInput = true;
    this.optionPickerOpen = true;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.showFloatingStatus('Loading available models...');
    ehTranslationService.fetchAvailableModels(provider).then((models: string[]) => {
      if (requestVersion !== this.modelPickerRequestVersion || !this.optionPickerOpen ||
        this.optionKey !== row.key) {
        return;
      }
      const options: string[] = [];
      if (row.value.trim().length > 0) {
        options.push(row.value.trim());
      }
      for (let i = 0; i < models.length; i++) {
        if (options.indexOf(models[i]) < 0) {
          options.push(models[i]);
        }
      }
      this.optionOptions = options;
      this.showFloatingStatus(models.length > 0 ? 'Available models loaded: ' + models.length.toString() :
        'No available models were returned');
    }).catch((error: Error) => {
      if (requestVersion !== this.modelPickerRequestVersion || !this.optionPickerOpen ||
        this.optionKey !== row.key) {
        return;
      }
      const message = cleanErrorMessage(error);
      if (message === 'Translation API key is missing' || message === 'No custom translation API is selected') {
        this.showFloatingStatus(message);
      } else {
        this.showFloatingStatus('Model list request failed: ' + message);
      }
    });
  }

  private customTranslationApis(): SavedTranslationApi[] {
    return parseSavedTranslationApis(appSettingsStore.getValue('translation_custom_apis', '[]'));
  }

  private ensureCustomTranslationApi(): void {
    const items = this.customTranslationApis();
    const selectedName = appSettingsStore.getValue('translation_custom_api_selected', '');
    const selected = findSavedTranslationApi(items, selectedName);
    if (selected !== null) {
      if (selectedName !== selected.name) {
        appSettingsStore.setValue('translation_custom_api_selected', selected.name);
      }
      return;
    }
    const created = createSavedTranslationApi(items);
    items.push(created);
    appSettingsStore.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
    appSettingsStore.setValue('translation_custom_api_selected', created.name);
  }

  private createAndSelectCustomTranslationApi(): void {
    const items = this.customTranslationApis();
    const created = createSavedTranslationApi(items);
    items.push(created);
    appSettingsStore.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
    appSettingsStore.setValue('translation_custom_api_selected', created.name);
    this.finishCustomTranslationApiSave('Created API: ' + created.name);
  }

  private updateCustomTranslationApiField(key: string, value: string): boolean {
    if (!isCustomTranslationApiField(key)) {
      return false;
    }
    const items = cloneSavedTranslationApis(this.customTranslationApis());
    const selectedName = appSettingsStore.getValue('translation_custom_api_selected', '');
    const selected = findSavedTranslationApi(items, selectedName);
    if (selected === null) {
      this.statusText = 'No custom translation API is selected';
      return true;
    }
    let nextSelectedName = selected.name;
    if (key === 'translation_custom_api_name') {
      nextSelectedName = uniqueTranslationApiName(items, value, selected.name);
      selected.name = nextSelectedName;
    } else if (key === 'translation_custom_api_base_url') {
      selected.baseUrl = value.trim();
    } else if (key === 'translation_custom_api_key') {
      selected.apiKey = value;
    } else if (key === 'translation_custom_api_model') {
      selected.model = value.trim();
    }
    appSettingsStore.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
    appSettingsStore.setValue('translation_custom_api_selected', nextSelectedName);
    this.finishCustomTranslationApiSave('Custom API saved');
    return true;
  }

  private finishCustomTranslationApiSave(status: string): void {
    this.settingEntries = appSettingsStore.getEntries();
    ehTranslationService.clearCache();
    this.statusText = status;
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch((error: Error) => {
        this.statusText = 'Save failed: ' + errorText(error);
      });
    }
  }

  private runSettingAction(key: string): boolean {
    if (key === 'identity_cookie') {
      this.sessionInitialMode = SessionMode.Cookie;
      this.openPanel(SettingsPanel.Session);
      return true;
    }
    if (key === 'network_diagnostics') {
      this.runNetworkDiagnostics();
      return true;
    }
    if (key === 'proxy_settings') {
      this.openProxySettings();
      return true;
    }
    if (key === 'remote_storage') {
      this.openPanel(SettingsPanel.RemoteStorage);
      return true;
    }
    if (key === 'restore_download_items') {
      this.restoreDownloadItems();
      return true;
    }
    if (key === 'import_local_folder') {
      this.importLocalGalleryFolder();
      return true;
    }
    if (key === 'verify_cloud_state') {
      this.verifyCloudStates();
      return true;
    }
    if (key === 'clean_redundancy') {
      this.cleanDownloadRedundancy();
      return true;
    }
    if (key === 'clear_download_path_cache') {
      this.refreshDownloadPathCache();
      return true;
    }
    if (key === 'clear_memory_cache') {
      this.clearMemoryCache();
      return true;
    }
    if (key === 'clear_app_log') {
      this.clearAppLog();
      return true;
    }
    if (key === 'declaration') {
      this.openExternalUrl(EH_REPOSITORY_URL, 'repository');
      return true;
    }
    if (key === 'author') {
      this.openExternalUrl(APP_AUTHOR_URL, APP_AUTHOR_NAME);
      return true;
    }
    if (key === 'latest_release') {
      this.openExternalUrl(EH_RELEASE_URL, 'version');
      return true;
    }
    if (key === 'issue_help') {
      this.openExternalUrl(feedbackIssueUrl(), 'issue tracker');
      return true;
    }
    if (key === 'github_repo') {
      this.openExternalUrl(EH_REPOSITORY_URL, 'repository');
      return true;
    }
    if (key === 'license') {
      this.openExternalUrl(EH_LICENSE_URL, 'license');
      return true;
    }
    if (key === 'check_for_updates') {
      this.checkForUpdatesManually();
      return true;
    }
    if (key === 'update_tag_translation_database') {
      this.updateTagTranslationDatabase();
      return true;
    }
    if (key === 'translation_test') {
      this.testTranslationProvider();
      return true;
    }
    if (key === 'translation_ai_log_export') {
      this.exportTranslationRecords();
      return true;
    }
    if (key === 'reader_ocr_debug_export') {
      this.exportReaderOcrDebugRecords();
      return true;
    }
    if (key === 'translation_prompt_settings') {
      this.openPanel(SettingsPanel.TranslationPrompt);
      return true;
    }
    if (key === 'reader_presets') {
      this.openPanel(SettingsPanel.ReaderPresets);
      return true;
    }
    if (key === 'clear_search_history') {
      ehSearchHistoryStore.clearAll();
      this.showResult('Clear search history', uiText('Search history cleared'));
      return true;
    }
    if (key === 'donate') {
      // 赞赏码直接弹层展示，支持一键拉起微信扫一扫。
      this.donateVisible = true;
      return true;
    }
    if (key === 'dump_logcat') {
      this.exportAppLog();
      return true;
    }
    if (key === 'u_config') {
      if (!this.signedIn) {
        this.statusText = 'UConfig requires a signed-in session';
        return true;
      }
      const isEx = appSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai';
      this.openAccountWebPage('UConfig', isEx ? 'https://exhentai.org/uconfig.php' : 'https://e-hentai.org/uconfig.php');
      return true;
    }
    if (key === 'my_tags') {
      if (!this.signedIn) {
        this.statusText = 'My Tags requires a signed-in session';
        return true;
      }
      this.openPanel(SettingsPanel.MyTags);
      return true;
    }
    if (key === 'filter') {
      const context = getAbilityContext();
      if (context !== undefined) {
        ehFilterStore.ensureLoaded(context).then(() => {
          this.filterRules = ehFilterStore.getRules();
          this.openPanel(SettingsPanel.Filter);
        }).catch((error: Error) => {
          this.filterRules = ehFilterStore.getRules();
          this.openPanel(SettingsPanel.Filter);
          this.statusText = 'Filter load warning: ' + errorText(error);
        });
      } else {
        this.filterRules = ehFilterStore.getRules();
        this.openPanel(SettingsPanel.Filter);
      }
      return true;
    }
    if (key === 'comment_blacklist') {
      const context = getAbilityContext();
      if (context === undefined) {
        this.openPanel(SettingsPanel.CommentBlacklist);
        return true;
      }
      ehCommentBlacklistStore.ensureLoaded(context).then(() => {
        this.openPanel(SettingsPanel.CommentBlacklist);
      }).catch((error: Error) => {
        this.openPanel(SettingsPanel.CommentBlacklist);
        this.statusText = 'Comment blacklist load warning: ' + errorText(error);
      });
      return true;
    }
    if (key === 'export_data') {
      this.exportData();
      return true;
    }
    if (key === 'import_data') {
      this.importData();
      return true;
    }
    if (key === 'wifi_transfer') {
      this.openPanel(SettingsPanel.WifiTransfer);
      return true;
    }
    return false;
  }

  private testTranslationProvider(): void {
    this.statusText = uiText('Testing translation...');
    this.showFloatingStatus(uiText('Testing translation...'));
    ehTranslationService.clearCache();
    ehTranslationService.testTranslation('Hello, world.').then((translated: string) => {
      this.statusText = uiText('Translation test succeeded') + ': ' + translated;
      this.showResult('Test translation', this.statusText);
      this.showToast(this.statusText);
    }).catch((error: Error) => {
      this.statusText = uiText('Translation test failed') + ': ' + errorText(error);
      this.showResult('Test translation', this.statusText);
      this.showToast(this.statusText);
    });
  }

  private recordProfileTombstones(section: string, previousIds: string[], nextIds: string[]): void {
    const context = getAbilityContext();
    for (let i = 0; i < previousIds.length; i++) {
      if (nextIds.indexOf(previousIds[i]) < 0) {
        syncTombstoneStore.recordDeletion(context, section, previousIds[i]);
      }
    }
    for (let i = 0; i < nextIds.length; i++) {
      if (previousIds.indexOf(nextIds[i]) < 0) {
        syncTombstoneStore.recordClear(context, section, nextIds[i]);
      }
    }
  }

  private saveTranslationPrompt(selectedId: string, customProfiles: string, status: string): void {
    const previousPromptIds = parseCustomTranslationPromptProfiles(
      appSettingsStore.getValue('translation_prompt_custom_profiles', '[]'))
      .map((profile: TranslationPromptProfile): string => profile.id);
    const nextPromptIds = parseCustomTranslationPromptProfiles(customProfiles)
      .map((profile: TranslationPromptProfile): string => profile.id);
    this.recordProfileTombstones(SYNC_SECTION_TRANSLATION_PROMPTS, previousPromptIds, nextPromptIds);
    appSettingsStore.setValue('translation_prompt_selected', selectedId);
    appSettingsStore.setValue('translation_prompt_custom_profiles', customProfiles);
    this.settingEntries = appSettingsStore.getEntries();
    ehTranslationService.clearCache();
    this.showFloatingStatus(status);
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + errorText(error));
      });
    }
  }

  private saveReaderPresets(customProfiles: string, status: string): void {
    const previousPresetIds = parseCustomReaderPresetProfiles(
      appSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]'))
      .map((profile: ReaderPresetProfile): string => profile.id);
    const nextPresetIds = parseCustomReaderPresetProfiles(customProfiles)
      .map((profile: ReaderPresetProfile): string => profile.id);
    this.recordProfileTombstones(SYNC_SECTION_READER_PRESETS, previousPresetIds, nextPresetIds);
    appSettingsStore.setValue(READER_CUSTOM_PRESETS_SETTING_KEY, customProfiles);
    this.settingEntries = appSettingsStore.getEntries();
    this.showFloatingStatus(status);
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + errorText(error));
      });
    }
  }

  private applyReaderPreset(profileId: string): void {
    const customProfiles = appSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]');
    const profile = findReaderPresetProfile(allReaderPresetProfiles(customProfiles), profileId);
    if (profile === null) {
      return;
    }
    applyReaderPresetValues(profile.values);
    this.settingEntries = appSettingsStore.getEntries();
    this.settingsRenderRevision++;
    this.showFloatingStatus('Reading preset applied');
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + errorText(error));
      });
    }
  }

  private openExternalUrl(url: string, label: string): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Open link failed: Ability context is not ready';
      return;
    }
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    }).then(() => {
      this.statusText = 'Opening browser: ' + label;
    }).catch((error: Error) => {
      this.statusText = 'Open link failed: ' + errorText(error);
    });
  }

  private exportData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Export needs an ability context');
      return;
    }
    this.showFloatingStatus('Preparing export...');
    const now = new Date();
    const stamp = now.getFullYear().toString() +
      padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
      padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
    const fileName = 'ehviewer_backup_' + stamp + '.json';

    Promise.all([
      ehCookieStore.ensureLoaded(context),
      appSettingsStore.ensureLoaded(context),
      ehHistoryStore.ensureLoaded(context),
      ehSearchHistoryStore.load(context),
      ehDownloadStore.load(context),
      ehFilterStore.ensureLoaded(context),
      ehLocalFavoritesStore.ensureLoaded(context),
      ehBookmarkStore.ensureLoaded(context),
      ehCommentBlacklistStore.ensureLoaded(context),
      ehBrowsePositionStore.ensureLoaded(context),
      remoteStorageProfileStore.ensureLoaded(context)
    ]).then(() => {
      const bundle: EhBackupBundle = {
        version: 2,
        exportedAt: now.toISOString(),
        cookies: ehCookieStore.getTransferCookieHeader(),
        settings: appSettingsStore.getTransferEntries(),
        history: ehHistoryStore.getItems(),
        readingProgress: ehHistoryStore.getReadingProgressBackupItems(),
        searchHistory: ehSearchHistoryStore.getKeywords(),
        browsePositions: ehBrowsePositionStore.getBackupInfo(),
        downloadItems: exportableDownloadItems(),
        downloadLabels: ehDownloadStore.getLabels(),
        filterRules: ehFilterStore.getRules(),
        localFavorites: ehLocalFavoritesStore.getBackupItems(),
        bookmarks: ehBookmarkStore.getBackupItems(),
        commentBlacklist: ehCommentBlacklistStore.getBackupItems(),
        remoteStorage: remoteStorageProfileStore.getProfiles()
      };
      const json = JSON.stringify(bundle, null, 2);

      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save(saveOptions).then((uris: string[]) => {
        if (uris.length === 0) {
          this.showFloatingStatus('Export cancelled');
          return;
        }
        const uri = uris[0];
        try {
          const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, json);
          fs.closeSync(file.fd);
          this.showResult('Export data', uiText('Export saved') + '\n' + uri);
        } catch (error) {
          this.showResult('Export data', uiText('Export write failed') + ': ' + String(error));
        }
      }).catch((error: Error) => {
        this.showFloatingStatus('Export picker failed: ' + errorText(error));
      });
    }).catch((error: Error) => {
      this.showFloatingStatus('Export load failed: ' + errorText(error));
    });
  }

  private checkForUpdatesManually(): void {
    if (this.runningAction.length > 0) {
      return;
    }
    this.runningAction = 'update';
    // 仓库地址还是占位值时，别去打 GitHub（必然 404），直接说明更新源未配置。
    if (!EH_REPOSITORY_CONFIGURED) {
      const pending = uiText('Update source is not configured yet');
      this.statusText = pending;
      this.showResult('Check for updates', pending);
      return;
    }
    this.statusText = uiText('Checking for updates...');
    this.showFloatingStatus(uiText('Checking for updates...'));
    releaseUpdateChecker.checkLatestRelease().then((result: UpdateCheckResult) => {
      if (result.hasUpdate && result.latest !== null) {
        this.updateCurrentVersion = result.current.versionName;
        this.updateRelease = result.latest;
        this.updateDialogVisible = true;
        this.statusText = uiText('New version found') + ': ' + result.latest.tagName;
      } else {
        this.statusText = result.message;
        this.runningAction = '';
        this.showResult('Check for updates', result.message);
      }
    }).catch((error: Error) => {
      this.statusText = 'Check for updates failed: ' + errorText(error);
      this.runningAction = '';
      this.showResult('Check for updates', this.statusText);
    });
  }

  // 下载安装包到本地，不尝试安装：系统没有 hap 安装器，安装交给 HDC 或调试助手。
  private async saveUpdatePackage(): Promise<void> {
    const release = this.updateRelease;
    if (release === null || release.hapDownloadUrl.length === 0) {
      this.statusText = uiText('Update download link is unavailable');
      return;
    }
    this.blockingBusyVisible = true;
    this.blockingBusyMessage = uiText('Downloading package');
    this.blockingBusyProgressText = '';
    this.blockingBusyProgressCurrent = 0;
    this.blockingBusyProgressTotal = 0;
    const result: UpdateSaveResult = await saveUpdateHap(release.hapDownloadUrl, (received: number) => {
      this.blockingBusyProgressCurrent = received;
      this.blockingBusyProgressText = downloadSizeText(received);
    });
    this.blockingBusyVisible = false;
    if (!result.ok) {
      this.statusText = result.message;
      return;
    }
    this.statusText = uiText('Package saved') + ': ' + result.path + ' — ' + uiText('install via HDC or debug assistant');
  }

  private exportAppLog(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Export log needs an ability context');
      return;
    }
    const now = new Date();
    const stamp = now.getFullYear().toString() +
      padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
      padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
    const fileName = 'ehviewer_log_' + stamp + '.txt';
    const content = this.createAppLogExport(context);
    if (content.trim().length === 0) {
      this.showResult('Export log', uiText('No saved log yet'));
      return;
    }
    this.writeTextToDownloads(context, fileName, content).then((path: string) => {
      this.statusText = 'Log exported: ' + path;
      this.showResult('Export log', uiText('Log exported') + '\n' + path);
    }).catch((error: Error) => {
      this.statusText = 'Log export failed: ' + errorText(error);
      this.showResult('Export log', this.statusText);
      appLog.error(context, DIAGNOSTIC_LOG_TAG, 'Log export failed: ' + errorText(error));
    });
  }

  private async writeTextToDownloads(context: common.UIAbilityContext, fileName: string, content: string): Promise<string> {
    const path = await pickDownloadsOutputPath(context, fileName);
    if (path.length === 0) {
      throw new Error('Export cancelled');
    }
    await writeTextFileChunked(path, content);
    return path;
  }

  private showFloatingStatus(message: string): void {
    this.statusText = message;
    this.showToast(message);
  }

  // 统一的结果弹窗：居中毛玻璃卡片，必须点确定（或点弹窗外）才关。
  // 带 altLabel 时多一个次要动作，例如「补下载缺失」。
  private showResult(title: string, message: string, altLabel: string = '',
    altAction?: () => void, confirmLabel: string = 'OK'): void {
    this.resultTitle = uiText(title);
    this.resultMessage = uiStatusText(message);
    this.resultAltLabel = altLabel;
    this.resultAltAction = altAction === undefined ? () => {} : altAction;
    this.resultConfirmLabel = confirmLabel;
    this.resultConfirmAction = () => {};
    this.resultVisible = true;
  }

  private showBlockingBusy(message: string): void {
    this.blockingBusyMessage = message;
    this.blockingBusyProgressText = '';
    this.blockingBusyProgressCurrent = -1;
    this.blockingBusyProgressTotal = -1;
    this.blockingBusyVisible = true;
  }

  private hideBlockingBusy(): void {
    this.blockingBusyVisible = false;
    this.blockingBusyMessage = 'Loading...';
    this.blockingBusyProgressText = '';
    this.blockingBusyProgressCurrent = -1;
    this.blockingBusyProgressTotal = -1;
  }

  private updateDownloadMigrationProgress(progress: DownloadMigrationProgress): void {
    if (progress.phase === 'scanning') {
      this.blockingBusyMessage = 'Scanning downloaded files...';
      this.blockingBusyProgressText = '';
      this.blockingBusyProgressCurrent = -1;
      this.blockingBusyProgressTotal = -1;
      return;
    }
    const countText = progress.files.toString() + ' / ' + progress.totalFiles.toString();
    const sizeText = downloadSizeText(progress.bytes) + ' / ' + downloadSizeText(progress.totalBytes);
    this.blockingBusyProgressText = countText + ' · ' + sizeText;
    if (progress.phase === 'cleaning') {
      this.blockingBusyMessage = 'Cleaning migrated source files...';
      this.blockingBusyProgressCurrent = progress.totalBytes > 0 ? progress.totalBytes : progress.totalFiles;
      this.blockingBusyProgressTotal = progress.totalBytes > 0 ? progress.totalBytes : progress.totalFiles;
      return;
    }
    this.blockingBusyMessage = 'Migrating downloaded files...';
    this.blockingBusyProgressCurrent = progress.totalBytes > 0 ? progress.bytes : progress.files;
    this.blockingBusyProgressTotal = progress.totalBytes > 0 ? progress.totalBytes : progress.totalFiles;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (error) {
    }
  }

  private clearAppLog(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Clear log needs an ability context';
      return;
    }
    appLog.clear(context);
    parseErrorBodyStore.clear(context);
    this.statusText = 'Saved log cleared';
    this.showResult('Clear saved log', uiText('Saved log cleared'));
  }

  private importData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Import needs an ability context');
      return;
    }
    this.showFloatingStatus('Select backup file to import...');

    const selectOptions = new picker.DocumentSelectOptions();
    const documentPicker = new picker.DocumentViewPicker(context);
    documentPicker.select(selectOptions).then((uris: string[]) => {
      if (uris.length === 0) {
        this.showFloatingStatus('Import cancelled');
        return;
      }
      const uri = uris[0];
      try {
        // 只读文件头判断类型：安卓备份可能有上百 MB，整读会 OOM。
        if (isAndroidDatabaseFile(uri)) {
          // 安卓备份只有记录没有图片：直接导完，列表里会是一堆「仅云端」。
          // 先讲清楚，并引导用户接着导入本地图册目录，否则等于把图片重新下一遍。
          this.showResultDialog('Android backup detected',
            uiText('This file only carries records, not images. Import the gallery folders from the old phone afterwards, otherwise every entry has to be downloaded again.'),
            [uiText('Cancel'), uiText('Continue import')],
            (choice: number) => {
              if (choice !== 1) {
                return;
              }
              this.runAndroidDatabaseImportFromUri(context, uri);
            });
          return;
        }
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        fs.closeSync(file.fd);
        const bytes = new Uint8Array(buf);
        const decoder = util.TextDecoder.create('utf-8');
        const json = decoder.decodeToString(bytes);
        const bundle = JSON.parse(json) as EhBackupBundle;

        if (typeof bundle.version !== 'number') {
          this.showFloatingStatus('Import failed: not a valid EhViewer backup file');
          return;
        }

        const saves: Promise<void>[] = [];

        if (typeof bundle.cookies === 'string') {
          const importedCookies = bundle.cookies;
          saves.push(ehCookieStore.ensureLoaded(context).then(() => {
            ehCookieStore.setTransferCookieHeader(importedCookies);
            this.signedIn = ehCookieStore.hasCookies();
            return ehCookieStore.save(context);
          }));
        }

        if (Array.isArray(bundle.settings)) {
          const settingResult: SettingImportResult = appSettingsStore.importEntries(bundle.settings);
          saves.push(appSettingsStore.save(context));
          this.settingEntries = appSettingsStore.getEntries();
          this.themeName = currentThemeName();
          if (settingResult.languageChanged) {
            notifyLanguageChanged();
          }
          if (settingResult.themeChanged) {
            notifyThemeChanged();
            applyAppChromeImmersiveMode();
          }
          if (settingResult.titleChanged) {
            notifyGalleryTitleChanged();
          }
          saves.push(readerImageCache.pruneAsync(context).then(() => {}));
          this.settingsRenderRevision++;
        }

        let importedHistory: GalleryInfo[] = [];
        let importedHistoryLimit = historyInfoSizeLimitFromValue(appSettingsStore.getValue(HISTORY_INFO_SIZE_KEY, '100'));
        if (Array.isArray(bundle.history)) {
          for (let i = 0; i < bundle.history.length; i++) {
            const imported = bundle.history[i] as GalleryInfo;
            if (typeof imported.gid === 'number' && imported.gid > 0 && typeof imported.token === 'string' &&
              imported.token.length > 0) {
              importedHistory.push(imported);
            }
          }
        }
        const importedReadingProgress = Array.isArray(bundle.readingProgress) ? bundle.readingProgress : [];

        let downloadsChanged = false;
        // 导入前下载列表是否为空：为空说明是换机首装，导入后可以直接开始串行补下载。
        const downloadsEmptyBefore = ehDownloadStore.getItems().length === 0;
        let importedDownloadsAdded = 0;
        let importedDownloadsMerged = 0;
        let importedDownloadsSkipped = 0;
        if (Array.isArray(bundle.downloadLabels)) {
          for (let i = 0; i < bundle.downloadLabels.length; i++) {
            const lbl = bundle.downloadLabels[i] as DownloadLabel;
            if (typeof lbl.label === 'string') {
              ehDownloadStore.addLabel(lbl.label);
              downloadsChanged = true;
            }
          }
        }

        if (Array.isArray(bundle.downloadItems)) {
          for (let i = 0; i < bundle.downloadItems.length; i++) {
            const dl = bundle.downloadItems[i] as DownloadInfo;
            if (typeof dl.gid === 'number' && dl.gid > 0 && typeof dl.token === 'string') {
              // 迁移专用：旧设备的 archiveUri 一律作废，按 gid/标题在本机重新绑定目录；
              // 本地图档（token 为空）也会照常带过来，不再被丢掉。
              const outcome = ehDownloadStore.importBackupItem(dl);
              if (outcome === 'added') {
                importedDownloadsAdded++;
              } else if (outcome === 'merged') {
                importedDownloadsMerged++;
              } else {
                importedDownloadsSkipped++;
              }
              downloadsChanged = true;
            }
          }
        }
        if (downloadsChanged) {
          saves.push(ehDownloadStore.save(context));
          this.showFloatingStatus(uiText('Downloads') + ': +' + importedDownloadsAdded.toString() +
            ' · ' + uiText('merged') + ' ' + importedDownloadsMerged.toString() +
            ' · ' + uiText('skipped') + ' ' + importedDownloadsSkipped.toString());
        }

        if (importedHistory.length > 0 || importedReadingProgress.length > 0) {
          saves.push(ehHistoryStore.ensureLoaded(context).then(async () => {
            ehHistoryStore.importHistoryBackupItems(importedHistory, importedHistoryLimit);
            ehHistoryStore.importReadingProgressBackupItems(importedReadingProgress);
            if (importedHistory.length === 0) {
              await ehHistoryStore.save(context);
              return;
            }
            this.showBlockingBusy('Rebuilding imported history metadata...');
            const result: DownloadMetadataRestoreResult = await rebuildImportedHistoryMetadata(context,
              importedHistory, this.currentGallerySite());
            this.hideBlockingBusy();
            if (result.rebuilt > 0 || result.fetched > 0) {
              this.showFloatingStatus('Imported history metadata rebuilt: ' + result.rebuilt.toString() +
                ', fetched ' + result.fetched.toString());
            }
          }).catch((error: Error) => {
            this.hideBlockingBusy();
            throw error;
          }));
        }

        if (Array.isArray(bundle.filterRules)) {
          for (let i = 0; i < bundle.filterRules.length; i++) {
            const r = bundle.filterRules[i] as FilterRule;
            if (typeof r.text === 'string' && typeof r.mode === 'number') {
              ehFilterStore.addRule(r.mode, r.text, typeof r.enabled === 'boolean' ? r.enabled : true);
            }
          }
          saves.push(ehFilterStore.save(context));
          this.filterRules = ehFilterStore.getRules();
        }

        if (Array.isArray(bundle.localFavorites)) {
          const localFavorites = bundle.localFavorites;
          saves.push(ehLocalFavoritesStore.ensureLoaded(context).then(() => {
            ehLocalFavoritesStore.importBackupItems(localFavorites);
            return ehLocalFavoritesStore.save(context);
          }));
        }

        if (Array.isArray(bundle.bookmarks)) {
          const bookmarks = bundle.bookmarks;
          saves.push(ehBookmarkStore.ensureLoaded(context).then(() => {
            ehBookmarkStore.importBackupItems(bookmarks);
            return ehBookmarkStore.save(context);
          }));
        }

        if (Array.isArray(bundle.searchHistory)) {
          const searchHistory = bundle.searchHistory;
          saves.push(ehSearchHistoryStore.load(context).then(() => {
            ehSearchHistoryStore.importKeywords(searchHistory);
            return ehSearchHistoryStore.save(context);
          }));
        }

        if (bundle.browsePositions !== undefined && bundle.browsePositions !== null &&
          typeof bundle.browsePositions === 'object') {
          const browsePositions = bundle.browsePositions as BrowsePositionsBackupInfo;
          saves.push(ehBrowsePositionStore.ensureLoaded(context).then(() => {
            ehBrowsePositionStore.importBackupInfo(browsePositions);
            return ehBrowsePositionStore.save(context);
          }));
        }

        if (Array.isArray(bundle.commentBlacklist)) {
          const commentBlacklist = bundle.commentBlacklist;
          saves.push(ehCommentBlacklistStore.ensureLoaded(context).then(() => {
            ehCommentBlacklistStore.importBackupItems(commentBlacklist);
            return ehCommentBlacklistStore.save(context);
          }));
        }

        if (Array.isArray(bundle.remoteStorage)) {
          const remoteProfiles = bundle.remoteStorage;
          saves.push(remoteStorageProfileStore.ensureLoaded(context).then(async () => {
            for (let i = 0; i < remoteProfiles.length; i++) {
              await remoteStorageProfileStore.upsert(context, remoteProfiles[i] as RemoteStorageProfile);
            }
          }));
        }

        Promise.all(saves).then(() => {
          remoteStorageSyncService.refreshConfiguration();
          const missing = this.missingDownloadGids().length;
          const lines: string[] = [];
          lines.push(uiText('Downloads') + ': +' + importedDownloadsAdded.toString() +
            ' / ' + uiText('merged') + ' ' + importedDownloadsMerged.toString() +
            ' / ' + uiText('skipped') + ' ' + importedDownloadsSkipped.toString());
          if (importedHistory.length > 0) {
            lines.push(uiText('History') + ' ' + importedHistory.length.toString());
          }
          if (missing > 0) {
            lines.push(uiText('Missing files') + ' ' + missing.toString());
          }
          const message = lines.join('\n');
          const actions: string[] = missing > 0 ?
            [uiText('OK'), uiText('Download missing')] : [uiText('OK')];
          this.showResultDialog('Import finished', message, actions, (index: number) => {
            if (index === 1) {
              this.startSerialResumeIfNeeded(missing);
            }
          });
          // 换机首装（导入前列表是空的）：不用等用户点，直接排队串行补下载，
          // 一条下完再下一条，不会瞬间吃掉配额。
          if (downloadsEmptyBefore && missing > 0) {
            this.startSerialResumeIfNeeded(missing);
          }
        }).catch((error: Error) => {
          this.showResultDialog('Import failed', 'Save failed: ' + errorText(error), [uiText('OK')], (_i: number) => {
          });
        });

      } catch (error) {
        this.showFloatingStatus('Import failed: ' + String(error));
      }
    }).catch((error: Error) => {
      this.showFloatingStatus('Import picker failed: ' + errorText(error));
    });
  }

  private restoreDownloadItems(): void {
    if (this.runningAction.length > 0) {
      return;
    }
    this.runningAction = 'scan';
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore download items needs an ability context';
      return;
    }
    const currentLocation = normalizeSettingsDownloadLocation(appSettingsStore.getValue('download_location',
      DOWNLOAD_LOCATION_APP_FILES));
    this.statusText = currentLocation === DOWNLOAD_LOCATION_APP_FILES ? 'Preparing public Downloads access...' :
      'Scanning downloaded folders...';
    // 点击即刻出「扫描中」：后面可能先弹系统权限框/目录授权，没有即时反馈用户会反复点。
    this.showBlockingBusy('Scanning downloaded folders...');
    Promise.resolve().then(async () => {
      let downloadsAccess = true;
      if (currentLocation === DOWNLOAD_LOCATION_APP_FILES) {
        downloadsAccess = await this.ensureDownloadLocationAccess(context, DOWNLOAD_LOCATION_DOWNLOADS);
      }
      this.statusText = 'Scanning ZIP archives...';
      this.showBlockingBusy('Scanning ZIP archives...');
      const result: DownloadRestoreResult = await restoreDownloadedItemsAndArchives(context,
        this.currentGallerySite(), downloadsAccess);
      this.hideBlockingBusy();
      this.runningAction = '';
      const parts: string[] = [];
      parts.push(uiText('Added') + ' ' + result.added.toString());
      parts.push(uiText('Already registered') + ' ' + result.skipped.toString());
      if (result.localOnly > 0) {
        parts.push(uiText('Kept as local') + ' ' + result.localOnly.toString());
      }
      if (result.migrated > 0) {
        parts.push(uiText('Migrated') + ' ' + result.migrated.toString());
      }
      parts.push(uiText('Total size') + ' ' + downloadSizeText(result.totalBytes));
      let message = uiText('Scan finished') + ' · ' + parts.join(' · ');
      if (result.archives.found > 0) {
        message += result.archives.processed > 0 ?
          ' · ' + uiText('ZIP archives processed') + ' ' + result.archives.processed.toString() +
            ' / ' + uiText('skipped') + ' ' + result.archives.skipped.toString() :
          ' · ' + uiText('Unprocessed ZIP archives') + ' ' + result.archives.skipped.toString();
      }
      if (!downloadsAccess) {
        message += ' · ' + uiText('Downloads access was not granted; scanned app files only');
      }
      this.showFloatingStatus(message);
      this.showResultDialog('Scan download folder', message, [uiText('OK')], (_i: number) => {
      });
      if (result.archives.processed > 0) {
        this.showDeleteProcessedZipDialog(result.archives);
      }
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.runningAction = '';
      this.showFloatingStatus('Restore downloads failed: ' + errorText(error));
    });
  }

  private importLocalGalleryFolder(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Import needs an ability context');
      return;
    }
    this.showFloatingStatus('Select the folder that holds the galleries...');
    const options = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    const documentPicker = new picker.DocumentViewPicker(context);
    documentPicker.select(options).then((uris: string[]) => {
      if (uris.length === 0) {
        this.showFloatingStatus('Import cancelled');
        return;
      }
      let folderPath = '';
      try {
        folderPath = new fileUri.FileUri(uris[0]).path;
      } catch (error) {
        folderPath = uris[0];
      }
      this.showBlockingBusy('Scanning local galleries...');
      importLocalGalleryFolder(context, folderPath, this.currentGallerySite(),
        (progress: LocalImportProgress) => {
          this.blockingBusyMessage = 'Scanning local galleries...';
          this.blockingBusyProgressText = progress.current.toString() + ' / ' + progress.total.toString() +
            ' · ' + progress.name;
          this.blockingBusyProgressCurrent = progress.current;
          this.blockingBusyProgressTotal = progress.total;
        }).then((report: LocalImportReport) => {
          this.hideBlockingBusy();
          this.showLocalImportReport(report);
        }).catch((error: Error) => {
          this.hideBlockingBusy();
          this.showFloatingStatus('Local gallery import failed: ' + errorText(error));
        });
    }).catch((error: Error) => {
      this.showFloatingStatus('Folder picker failed: ' + errorText(error));
    });
  }

  private showLocalImportReport(report: LocalImportReport): void {
    const parts: string[] = [];
    parts.push(uiText('Folders found') + ' ' + report.folders.toString());
    parts.push(uiText('Added') + ' ' + report.added.toString());
    parts.push(uiText('Matched on server') + ' ' + report.matched.toString());
    parts.push(uiText('Kept as local') + ' ' + report.localOnly.toString());
    parts.push(uiText('Already in list') + ' ' + report.duplicated.toString());
    parts.push(uiText('Without images') + ' ' + report.empty.toString());
    if (report.failed > 0) {
      parts.push(uiText('Failed') + ' ' + report.failed.toString());
    }
    parts.push(uiText('Total size') + ' ' + downloadSizeText(report.bytes));
    const message = parts.join(' · ');
    this.showFloatingStatus(message);
    this.showImportReportDialog('Local gallery import', message);
  }

  // 安卓 DB 导入主体：导完弹模态结果（新增/跳过/合并 + 缺失条数），可一键串行补下载。
  private runAndroidDatabaseImport(context: common.UIAbilityContext, bytes: Uint8Array): void {
    this.runAndroidImportTask(importAndroidDatabaseBackup(context, bytes));
  }

  // 走路径导入：按块拷贝，不再把整个 DB 读进内存。
  private runAndroidDatabaseImportFromUri(context: common.UIAbilityContext, uri: string): void {
    this.runAndroidImportTask(importAndroidDatabaseBackupFromUri(context, uri));
  }

  private runAndroidImportTask(task: Promise<AndroidDataImportSummary>): void {
    this.showBlockingBusy('Importing Android data...');
    task.then((summary: AndroidDataImportSummary) => {
      this.hideBlockingBusy();
      this.filterRules = ehFilterStore.getRules();
      const parts: string[] = [];
      let historyLine = uiText('History') + ' ' + summary.history.toString() + '（' +
        uiText('skipped') + ' ' + summary.historySkipped.toString();
      if (summary.historyInvalid > 0) {
        historyLine += ' · ' + uiText('no identity') + ' ' + summary.historyInvalid.toString();
      }
      historyLine += '）';
      parts.push(historyLine);
      parts.push(uiText('Downloads') + ' +' + summary.downloads.toString() + ' / ' + uiText('merged') + ' ' +
        summary.downloadsMerged.toString() + ' / ' + uiText('skipped') + ' ' +
        summary.downloadsSkipped.toString());
      if (summary.downloadsLocal > 0 || summary.downloadsLocalSkipped > 0) {
        parts.push(uiText('Local') + ' +' + summary.downloadsLocal.toString() + ' / ' +
          uiText('skipped') + ' ' + summary.downloadsLocalSkipped.toString());
      }
      parts.push(uiText('Local favorites') + ' ' + summary.localFavorites.toString());
      parts.push(uiText('Labels') + ' ' + summary.labels.toString());
      parts.push(uiText('Filters') + ' ' + summary.filters.toString());
      parts.push(uiText('Bookmarks') + ' ' + summary.bookmarks.toString());
      parts.push(uiText('Comment blacklist') + ' ' + summary.blacklist.toString());
      const missing = this.missingDownloadGids().length;
      if (missing > 0) {
        parts.push(uiText('Missing files') + ' ' + missing.toString());
      }
      const message = parts.join('\n');
      const actions: string[] = missing > 0 ?
        [uiText('OK'), uiText('Download missing')] : [uiText('OK')];
      this.showResultDialog('Android data imported', message, actions, (index: number) => {
        if (index === 1) {
          this.startSerialResumeIfNeeded(missing);
        }
      });
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.showResultDialog('Import failed', 'Android data: ' + errorText(error), [uiText('OK')], (_i: number) => {
      });
    });
  }

  private showImportReportDialog(title: string, message: string): void {
    this.showResultDialog(title, message, [uiText('OK')], (_index: number) => {
    });
  }

  // 居中模态结果框：必须点按钮才消失，可带最多两个动作（导入后补下载那种）。
  // 以前的浮动提示 1 秒就没了、也没有数量，导入结果根本看不清。
  private showResultDialog(title: string, message: string, actions: string[],
    onAction: (index: number) => void): void {
    if (actions.length <= 1) {
      this.showResult(title, message);
      onAction(0);
      return;
    }
    // 两个动作：第一个作为次要键（取消/稍后），最后一个作为主键（继续/补下载）。
    // 主键文案必须跟着最后一个动作走：以前写死 'OK'，结果两个按钮都显示「确定」。
    const primaryLabel = actions.length > 0 ? actions[actions.length - 1] : 'OK';
    this.showResult(title, message, actions[0], () => {
      onAction(0);
    }, primaryLabel);
    this.resultConfirmAction = () => {
      onAction(actions.length - 1);
    };
  }

  // 导入后「本机没有文件」的记录：有云端身份的才值得补下载。
  private missingDownloadGids(): number[] {
    const gids: number[] = [];
    const items = ehDownloadStore.getItems();
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.token.length > 0 && item.state === DownloadState.Missing) {
        gids.push(item.gid);
      }
    }
    return gids;
  }

  // 补下载：串行排队，一条下完再下一条，避免一次吃掉配额。
  private startSerialResumeIfNeeded(missing: number): void {
    if (missing <= 0) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const queued = ehDownloadManager.startSerialResume(context, this.missingDownloadGids());
    this.showFloatingStatus(uiText('Queued') + ' ' + queued.toString() + ' ' + uiText('for download'));
  }

  private exportTranslationRecords(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('AI translation record export needs an ability context');
      return;
    }
    const content = translationConversationLog.read(context);
    if (content.trim().length === 0) {
      this.showResult('Export AI conversation records', uiText('No AI translation records yet'));
      return;
    }
    const fileName = 'ehviewer_translation_' + diagnosticTimestamp(new Date()) + '.txt';
    this.writeTextToDownloads(context, fileName, content).then((path: string) => {
      this.statusText = uiText('AI translation records exported') + ': ' + path;
      this.showResult('Export AI conversation records', this.statusText);
    }).catch((error: Error) => {
      this.showResult('Export AI conversation records',
        uiText('AI translation record export failed') + ': ' + errorText(error));
    });
  }

  private exportReaderOcrDebugRecords(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Comic OCR debug export needs an ability context');
      return;
    }
    const content = readerOcrDebugLog.read(context);
    if (content.trim().length === 0) {
      this.showFloatingStatus('No comic OCR debug records yet');
      return;
    }
    const fileName = 'ehviewer_reader_ocr_debug_' + diagnosticTimestamp(new Date()) + '.txt';
    this.writeTextToDownloads(context, fileName, content).then((path: string) => {
      this.statusText = uiText('Comic OCR debug data exported') + ': ' + path;
      this.showToast('Comic OCR debug data exported');
    }).catch((error: Error) => {
      this.showFloatingStatus(uiText('Comic OCR debug export failed') + ': ' + errorText(error));
    });
  }

  private updateTagTranslationDatabase(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Tag translation database update needs an ability context');
      return;
    }
    this.showBlockingBusy('Checking tag translation database...');
    ehTagTranslationStore.update(context, (phase: EhTagTranslationUpdatePhase) => {
      this.blockingBusyMessage = phase === 'downloading' ? 'Downloading tag translation database...' :
        'Checking tag translation database...';
    }).then((result: EhTagTranslationUpdateResult) => {
      this.hideBlockingBusy();
      if (result.updated) {
        notifyLanguageChanged();
        this.settingsRenderRevision++;
        this.showResult('Update tag translation database',
          uiText('Tag translation database updated') + ': ' + result.count.toString() + ' tags');
      } else {
        this.showResult('Update tag translation database', uiText('Tag translation database is up to date'));
      }
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.showResult('Update tag translation database', 'Failed: ' + errorText(error));
    });
  }

  private openProxySettings(): void {
    this.optionPickerOpen = false;
    this.proxySettingsOpen = true;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.statusText = '';
  }

  private closeProxySettings(): void {
    this.proxySettingsOpen = false;
    this.restoreBackHandler();
  }

  private saveProxySettings(type: string, host: string, port: string, username: string, password: string,
    exclusions: string, socksDns: string): void {
    const normalizedType = normalizeProxyOption(type);
    if (normalizedType === 'SOCKS' && !socks5ProxySupported()) {
      this.showFloatingStatus('SOCKS5 requires HarmonyOS API 26 or later');
      return;
    }
    const normalizedHost = host.trim();
    const normalizedPort = port.trim();
    if (normalizedType === 'HTTP' || normalizedType === 'SOCKS') {
      if (normalizedHost.length === 0 || !isValidProxyHostText(normalizedHost)) {
        this.showFloatingStatus(normalizedHost.length === 0 ? 'Proxy host is required' :
          'Invalid proxy host: ' + normalizedHost);
        return;
      }
      if (!isValidProxyPortText(normalizedPort)) {
        this.showFloatingStatus('Proxy port is invalid');
        return;
      }
    }
    appSettingsStore.setValue('proxy', normalizedType);
    appSettingsStore.setValue('proxy_host', normalizedHost);
    appSettingsStore.setValue('proxy_port', normalizedPort);
    appSettingsStore.setValue('proxy_username', username.trim());
    appSettingsStore.setValue('proxy_password', password);
    appSettingsStore.setValue('proxy_exclusion_list', normalizeProxyExclusionListText(exclusions));
    appSettingsStore.setValue('proxy_socks_dns', socksDns === 'System' ? 'System' : 'Proxy');
    this.settingEntries = appSettingsStore.getEntries();
    this.settingsRenderRevision++;
    this.closeProxySettings();
    this.refreshNetworkRuntime();
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + errorText(error));
      });
    }
    this.showFloatingStatus('Proxy settings saved');
  }

  private showDeleteProcessedZipDialog(result: DownloadZipImportResult): void {
    const message = uiStatusText('ZIP import summary: processed ' + result.processed.toString() + ', skipped ' +
      result.skipped.toString() + '. Delete processed archives?');
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('ZIP archives processed'),
      message: message,
      buttons: [
        {
          text: uiText('Keep'),
          color: themeSecondaryText()
        },
        {
          text: uiText('Delete'),
          color: themeAccentTextColor()
        }
      ]
    }).then((data) => {
      if (data.index !== 1) {
        return;
      }
      const removed = ehDownloadFileStore.removeFiles(result.processedPaths);
      this.showFloatingStatus('Deleted processed ZIP archives: ' + removed.toString());
    }).catch(() => {});
  }

  private createAppLogExport(context: common.UIAbilityContext): string {
    const logDump = appLog.read(context);
    const parseBodies = parseErrorBodyStore.list(context);
    if (logDump.trim().length === 0 && parseBodies.length === 0) {
      return '';
    }
    const lines: string[] = [];
    lines.push('EhViewer OHOS Diagnostic Log');
    lines.push('ExportedAt: ' + new Date().toISOString());
    lines.push('Version: ' + APP_VERSION_NAME + ' (' + APP_VERSION_CODE.toString() + ')');
    lines.push('Target: ' + TARGET_PLATFORM);
    lines.push('SaveCrashLog: ' + appSettingsStore.getValue('save_crash_log', 'Off'));
    lines.push('SaveParseErrorBody: ' + appSettingsStore.getValue('save_parse_error_body', 'Off'));
    lines.push('');
    lines.push('[App Log]');
    lines.push(logDump.trim().length > 0 ? logDump : '(empty)');
    lines.push('');
    lines.push('[Parse Error Bodies]');
    if (parseBodies.length === 0) {
      lines.push('(none)');
    } else {
      for (let i = 0; i < parseBodies.length; i++) {
        const entry: ParseErrorBodyEntry = parseBodies[i];
        lines.push((i + 1).toString() + '. ' + entry.name);
        lines.push('   Path: ' + entry.path);
        lines.push('   Size: ' + downloadSizeText(entry.size));
        lines.push('   Modified: ' + new Date(entry.modifiedTime).toISOString());
      }
    }
    return lines.join('\n');
  }

  // 校验「只有云端记录、本机没有文件」的图册在服务器上还在不在：还在标蓝云，已删标红云。
  private verifyCloudStates(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Verify cloud records needs an ability context');
      return;
    }
    ehDownloadStore.load(context).then(async () => {
      this.showBlockingBusy('Verifying cloud records...');
      try {
        const result = await verifyMissingCloudGalleries(this.currentGallerySite(),
          (checked: number, total: number) => {
            this.blockingBusyMessage = 'Verifying cloud records...';
            this.blockingBusyProgressText = checked.toString() + ' / ' + total.toString();
            this.blockingBusyProgressCurrent = checked;
            this.blockingBusyProgressTotal = total;
          });
        await ehDownloadStore.save(context);
        this.hideBlockingBusy();
        this.settingsRenderRevision++;
        if (result.checked === 0) {
          this.showResult('Verify cloud records', uiText('No cloud-only records to verify'));
          return;
        }
        this.showResult('Verify cloud records', uiText('Cloud verified') + ': ' +
          uiText('online') + ' ' + result.online.toString() + ' · ' +
          uiText('removed') + ' ' + result.gone.toString() + ' · ' +
          uiText('skipped') + ' ' + result.skipped.toString());
      } catch (error) {
        this.hideBlockingBusy();
        this.showResult('Verify cloud records', 'Failed: ' + errorText(error));
      }
    }).catch((error: Error) => {
      this.showResult('Verify cloud records', 'Failed: ' + errorText(error));
    });
  }

  private cleanDownloadRedundancy(): void {
    if (this.runningAction.length > 0) {
      return;
    }
    this.runningAction = 'clean';
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Clean redundancy needs an ability context');
      return;
    }
    // 先出"清理中"，再干活：查重与孤儿目录清理是同步树遍历，
    // 不给即时反馈用户会以为没点到而反复点（B-02）。
    this.showBlockingBusy('Cleaning redundant files...');
    ehDownloadStore.load(context).then(async () => {
      // 1) 记录级查重：同一图册（同 gid 或同标题）只留一条，云端身份与本地目录合并。
      const mergedRecords = ehDownloadStore.dedupeRecords();
      if (mergedRecords > 0) {
        await ehDownloadStore.save(context);
      }
      // 2) 目录级查重：同一图册的多份目录（"gid-标题" 与 "标题"）合并成一份。
      const mergedDirs = ehDownloadFileStore.mergeDuplicateDirectories(context);
      // 3) 孤儿目录：既没有记录、也没有 gid 归属的目录。
      const items = ehDownloadStore.getItems();
      const keepGids: number[] = [];
      const keepNames: string[] = [];
      for (let i = 0; i < items.length; i++) {
        keepGids.push(items[i].gid);
        const name = basenameOf(items[i].archiveUri);
        if (name.length > 0) {
          keepNames.push(name);
        }
      }
      const orphans = ehDownloadFileStore.cleanRedundantDirectories(context, keepGids, keepNames);
      const directories = mergedDirs.directories + orphans.directories;
      const files = mergedDirs.files + orphans.files;
      const bytes = mergedDirs.bytes + orphans.bytes;
      this.settingsRenderRevision++;
      this.hideBlockingBusy();
      this.runningAction = '';
      if (mergedRecords <= 0 && directories <= 0 && files <= 0) {
        this.showResult('Clean redundancy', uiText('No redundant downloaded galleries'));
        return;
      }
      this.showResult('Clean redundancy', uiText('Cleaned') + ': ' +
        uiText('merged') + ' ' + mergedRecords.toString() + ' · ' +
        directories.toString() + ' ' + uiText('duplicate folders') + ' · ' +
        files.toString() + ' ' + uiText('files') + ' · ' + downloadSizeText(bytes));
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.runningAction = '';
      this.showResult('Clean redundancy', 'Failed: ' + errorText(error));
    });
  }

  private refreshDownloadPathCache(): void {
    if (this.runningAction.length > 0) {
      return;
    }
    this.runningAction = 'pathcache';
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download path cache needs an ability context';
      return;
    }
    this.showBlockingBusy('Clearing download path cache...');
    ehDownloadStore.load(context).then(() => {
      const items = ehDownloadStore.getItems();
      let updated = 0;
      let totalBytes = 0;
      for (let i = 0; i < items.length; i++) {
        const size = ehDownloadFileStore.directorySize(context, items[i]);
        if (size > 0) {
          ehDownloadStore.setStorage(items[i].gid, ehDownloadFileStore.galleryDirectory(context, items[i]), size);
          totalBytes += size;
          updated++;
        }
      }
      return ehDownloadStore.save(context).then(() => {
        this.statusText = 'Download path cache cleared: ' + updated.toString() + ' items, ' +
          downloadSizeText(totalBytes);
        this.hideBlockingBusy();
        this.runningAction = '';
        this.showResult('Clear download path cache', this.statusText);
      });
    }).catch((error: Error) => {
      this.statusText = 'Clear download path cache failed: ' + errorText(error);
      this.hideBlockingBusy();
      this.runningAction = '';
      this.showResult('Clear download path cache', this.statusText);
    });
  }

  private clearMemoryCache(): void {
    galleryThumbnailDecodeCache.clear();
    const pageCount = galleryPageCache.clear();
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Cleared page cache: ' + pageCount.toString() + ' entries.';
      return;
    }
    readerImageCache.clearAsync(context).then((imageResult: CacheClearResult) => {
      this.settingsRenderRevision++;
      this.statusText = 'Cleared cache: ' + pageCount.toString() + ' pages, ' +
        imageResult.files.toString() + ' images, ' + downloadSizeText(imageResult.bytes) + '.';
      this.showResult('Clear cache', this.statusText);
    }).catch((error: Error) => {
      this.statusText = 'Clear cache failed: ' + errorText(error);
      this.showResult('Clear cache', this.statusText);
    });
  }

  private runNetworkDiagnostics(): void {
    this.showFloatingStatus('Running network diagnostics...');
    const context = getAbilityContext();
    this.refreshNetworkRuntime();
    this.client.runNetworkDiagnostics().then((results: NetworkDiagnosticResult[]) => {
      const summary = formatNetworkDiagnostics(results);
      this.statusText = summary;
      if (context === undefined) {
        this.showResult('Network diagnostics', summary);
        return;
      }
      const content = this.createNetworkDiagnosticLog(results, summary);
      const fileName = 'ehviewer_network_' + diagnosticTimestamp(new Date()) + '.txt';
      this.writeTextToDownloads(context, fileName, content).then((path: string) => {
        this.statusText = 'Network diagnostics exported: ' + path;
        this.showResult('Network diagnostics', summary + '\n' + uiText('Log saved to') + ' ' + path);
      }).catch((error: Error) => {
        this.statusText = 'Network diagnostics export failed: ' + errorText(error);
        this.showResult('Network diagnostics', summary + '\n' + this.statusText);
        appLog.error(context, DIAGNOSTIC_LOG_TAG, 'Network diagnostics export failed: ' + errorText(error));
      });
    }).catch((error: Error) => {
      this.showResult('Network diagnostics', uiText('Network diagnostics failed') + ': ' + errorText(error));
      if (context !== undefined) {
        appLog.error(context, DIAGNOSTIC_LOG_TAG, 'Network diagnostics failed: ' + errorText(error));
      }
    });
  }

  private createNetworkDiagnosticLog(results: NetworkDiagnosticResult[], summary: string): string {
    const lines: string[] = [];
    lines.push('EhViewer OHOS Network Diagnostics');
    lines.push('Time: ' + new Date().toISOString());
    lines.push('Version: ' + APP_VERSION_NAME + ' (' + APP_VERSION_CODE.toString() + ')');
    lines.push('Target: ' + TARGET_PLATFORM);
    lines.push('Gallery site: ' + appSettingsStore.getValue('gallery_site', 'E-Hentai'));
    lines.push('Proxy: ' + proxyDiagnosticText());
    lines.push('Built-in hosts: ' + appSettingsStore.getValue('built_in_hosts', 'Off'));
    lines.push('Built EX hosts: ' + appSettingsStore.getValue('built_ex_hosts', 'Off'));
    lines.push('Domain fronting: ' + appSettingsStore.getValue('domain_fronting', 'Off'));
    lines.push('DNS over HTTPS: ' + currentDnsOverHttpsStatusText());
    lines.push('Direct connection check: ' + appSettingsStore.getValue('auto_direct_connection', 'Off'));
    lines.push('');
    lines.push(summary);
    lines.push('');
    for (let i = 0; i < results.length; i++) {
      const item = results[i];
      lines.push(item.label + ':');
      lines.push('  URL: ' + item.url);
      lines.push('  OK: ' + (item.ok ? 'true' : 'false'));
      lines.push('  Status: ' + (item.statusCode > 0 ? item.statusCode.toString() : 'ERR'));
      lines.push('  Elapsed: ' + item.elapsedMs.toString() + 'ms');
      lines.push('  Message: ' + item.message);
    }
    return lines.join('\n') + '\n';
  }

  private refreshNetworkRuntime(): void {
    const context = getAbilityContext();
    if (!isEhDirectConnectionProbeEnabled()) {
      ensureEhHostRules().then(() => {
        startEhFrontingBenchmark(context);
      }).catch(() => {});
      return;
    }
    startEhDirectConnectionProbe(context).then((directAvailable: boolean) => {
      if (!directAvailable) {
        this.showFloatingStatus('Direct connection unavailable, domain fronting enabled');
        startEhFrontingBenchmark(context);
        return;
      }
      this.showFloatingStatus('Direct connection available, domain fronting disabled');
    }).catch(() => {
      this.showFloatingStatus('Direct connection unavailable, domain fronting enabled');
      startEhFrontingBenchmark(context);
    });
  }

  private addFilterRule(mode: number, draftText: string): boolean {
    const text = draftText.trim();
    if (text.length === 0) {
      this.statusText = 'Enter a filter text first';
      this.showToast(this.statusText);
      return false;
    }
    const added = ehFilterStore.addRule(mode, text);
    if (!added) {
      this.statusText = 'Rule already exists: ' + text;
      this.showToast(this.statusText);
      return false;
    }
    this.filterRules = ehFilterStore.getRules();
    this.filterNewText = '';
    this.filterNewMode = mode;
    this.statusText = 'Filter rule added: ' + text;
    this.showToast(this.statusText);
    this.saveFilterRules();
    return true;
  }

  private removeFilterRule(id: number): void {
    ehFilterStore.removeRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.statusText = 'Filter rule removed';
    this.showToast(this.statusText);
    this.saveFilterRules();
  }

  private toggleFilterRule(id: number): void {
    ehFilterStore.toggleRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.saveFilterRules();
  }

  private setRatingFilterRule(level: number): void {
    const rules = ehFilterStore.getRules();
    for (let i = 0; i < rules.length; i++) {
      if (rules[i].mode === FILTER_MODE_RATING) {
        ehFilterStore.removeRule(rules[i].id);
      }
    }
    if (level > 1) {
      ehFilterStore.addRule(FILTER_MODE_RATING, level.toString());
      this.statusText = 'Filter rule added: ' + level.toString();
    } else {
      this.statusText = 'Filter rule removed';
    }
    this.filterRules = ehFilterStore.getRules();
    this.showToast(this.statusText);
    this.saveFilterRules();
  }

  private saveFilterRules(): void {
    const revision = AppStorage.get<number>(FILTER_RULE_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(FILTER_RULE_REVISION_KEY, revision + 1);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehFilterStore.save(context).catch((error: Error) => {
        this.statusText = 'Filter save failed: ' + errorText(error);
      });
    }
  }


  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Main panel always rendered at the bottom so sub-panels can slide over it
      // and returning to Main requires no enter animation — it's already there.
      SettingsHomePanel({
        onMenu: this.onMenu,
        initialScrollOffset: settingsHomeScrollOffset,
        onScrollPositionChange: (offset: number) => {
          this.updateHomeScrollOffset(offset);
        },
        onOpen: (panel: SettingsPanel) => {
          this.openPrimaryPanel(panel);
        }
      })
        .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
        .height('100%')
        .onTouch((event: TouchEvent) => {
          if (shouldUpdateSplitPaneFocus(event)) {
            this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
          }
        })
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })

      if (this.settingsDetailLayerPanel() !== SettingsPanel.Main) {
        SplitPaneDivider({
          x: this.useSplitLayout() ? this.splitListPaneWidth() : 0,
          dividerVisible: this.useSplitLayout(),
          dragging: this.splitDragging,
          fadeTransition: this.restorePanelWithFade,
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

      // Ordinary settings panels stay underneath deeper panels. This keeps EH/Advanced
      // visually fixed while account session, web config, filters, or migration slide over it.
      if (this.settingsDetailLayerPanel() !== SettingsPanel.Main) {
        SettingsDetailPanel({
          panel: this.settingsDetailLayerPanel(),
          signedIn: this.signedIn,
          themeName: this.themeName,
          renderRevision: this.settingsRenderRevision,
          settingEntries: this.settingEntries,
          initialScrollOffset: settingsDetailScrollOffsets.get(this.settingsDetailLayerPanel()) ?? 0,
          onScrollPositionChange: (offset: number) => {
            this.updateDetailScrollOffset(this.settingsDetailLayerPanel(), offset);
          },
          onBack: () => {
            this.closePanel();
          },
          onOpenSession: () => {
            this.sessionInitialMode = SessionMode.Password;
            this.openPanel(SettingsPanel.Session);
          },
          onSignOut: () => {
            this.signOutConfirmationVisible = true;
          },
          onCycleSetting: (row: SettingsRowItem) => {
            this.cycleSetting(row);
          },
          onSetSetting: (key: string, value: string) => {
            this.saveSettingValue(key, value);
          },
          onTextDraftChange: (key: string, value: string) => {
            this.updateSettingDraft(key, value);
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
          .transition(this.restorePanelWithFade ?
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
            TransitionEffect.asymmetric(
              TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }),
              TransitionEffect.move(TransitionEdge.END).animation({ duration: 240, curve: Curve.EaseIn })))
      }

      // Deeper panels slide over the ordinary settings panel instead of replacing it.
      if (this.panel === SettingsPanel.CommentBlacklist) {
        CommentBlacklistPanel({
          onBack: () => {
            this.closePanel();
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.Filter) {
        FilterPanel({
          rules: this.filterRules,
          newText: this.filterNewText,
          newMode: this.filterNewMode,
          onBack: () => {
            this.closePanel();
          },
          onNewModeChange: (mode: number) => {
            this.filterNewMode = mode;
          },
          onAddText: (mode: number, text: string): boolean => {
            return this.addFilterRule(mode, text);
          },
          onRatingSelect: (level: number) => {
            this.setRatingFilterRule(level);
          },
          onRemove: (id: number) => {
            this.removeFilterRule(id);
          },
          onToggle: (id: number) => {
            this.toggleFilterRule(id);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.WifiTransfer) {
        WifiMigrationPanel({
          onBack: () => {
            this.closePanel();
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.RemoteStorage) {
        RemoteStoragePanel({
          onBack: () => {
            this.closePanel();
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.WebView) {
        SettingsAccountWebPanel({
          title: this.webViewTitle,
          url: this.webViewUrl,
          onBack: () => {
            this.closePanel();
          },
          onPageEnd: (url: string) => {
            this.captureAccountWebCookies(url);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.MyTags) {
        Column() {
          SettingsSubToolbar({
            title: uiText('My Tags'),
            showAction: true,
            actionIcon: $r('sys.symbol.share'),
            onBack: () => {
              this.closePanel();
            },
            onAction: () => {
              const site = this.currentGallerySite();
              this.openAccountWebPage('My Tags', EhUrl.getHost(site) + 'mytags');
            }
          })
          MyTagsPanel({ site: this.currentGallerySite() })
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(themePageBackground())
        .width(this.settingsLayerWidth())
        .position({ x: this.settingsLayerTranslateX(), y: 0 })
        .onTouch((event: TouchEvent) => {
          if (shouldUpdateSplitPaneFocus(event)) {
            this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
          }
        })
        .zIndex(10)
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.TranslationPrompt) {
        TranslationPromptPanel({
          selectedId: settingEntryValue(this.settingEntries, 'translation_prompt_selected', 'preset_faithful'),
          customProfiles: settingEntryValue(this.settingEntries, 'translation_prompt_custom_profiles', '[]'),
          onBack: () => {
            this.closePanel();
          },
          onSave: (selectedId: string, customProfiles: string, status: string) => {
            this.saveTranslationPrompt(selectedId, customProfiles, status);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.ReaderPresets) {
        ReaderPresetPanel({
          customProfiles: settingEntryValue(this.settingEntries, READER_CUSTOM_PRESETS_SETTING_KEY, '[]'),
          onBack: () => {
            this.closePanel();
          },
          onApply: (profileId: string) => {
            this.applyReaderPreset(profileId);
          },
          onSave: (customProfiles: string, status: string) => {
            this.saveReaderPresets(customProfiles, status);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.Session) {
        SessionScene({
          initialMode: this.sessionInitialMode,
          onBack: () => {
            this.closePanel();
          },
          onSignedIn: () => {
            this.signedIn = ehCookieStore.hasCookies();
            this.statusText = this.signedIn ? 'Signed in' : 'Guest mode';
            this.closePanel();
            this.onSignedIn();
          }
        })
        .width(this.settingsLayerWidth())
        .height('100%')
        .position({ x: this.settingsLayerTranslateX(), y: 0 })
        .onTouch((event: TouchEvent) => {
          if (shouldUpdateSplitPaneFocus(event)) {
            this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
          }
        })
        .zIndex(10)
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
      }

      // Option picker floats on top of everything.
      if (this.proxySettingsOpen) {
        ProxySettingsOverlay({
          initialType: normalizeProxyOption(appSettingsStore.getValue('proxy', 'System')),
          initialHost: appSettingsStore.getValue('proxy_host', ''),
          initialPort: appSettingsStore.getValue('proxy_port', ''),
          initialUsername: appSettingsStore.getValue('proxy_username', ''),
          initialPassword: appSettingsStore.getValue('proxy_password', ''),
          initialExclusions: appSettingsStore.getValue('proxy_exclusion_list', ''),
          initialSocksDns: appSettingsStore.getValue('proxy_socks_dns', 'Proxy'),
          socksSupported: socks5ProxySupported(),
          onCancel: () => {
            this.closeProxySettings();
          },
          onSave: (type: string, host: string, port: string, username: string, password: string,
            exclusions: string, socksDns: string) => {
            this.saveProxySettings(type, host, port, username, password, exclusions, socksDns);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(26)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }

      if (this.optionPickerOpen) {
        SettingsOptionPanel({
          title: this.optionTitle,
          summary: this.optionSummary,
          value: this.optionValue,
          options: this.optionOptions,
          optionDescriptions: this.optionDescriptions,
          allowCustomInput: this.optionAllowCustomInput,
          onBack: () => {
            this.closeOptionPicker();
          },
          onSelect: (value: string) => {
            this.selectOptionValue(value);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(25)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }

      if (this.downloadMigrationDialogOpen) {
        DownloadMigrationConfirmOverlay({
          current: this.downloadMigrationCurrent,
          target: this.downloadMigrationTarget,
          onCancel: () => {
            this.closeDownloadMigrationDialog();
            this.statusText = 'Download location change cancelled';
          },
          onSwitchOnly: () => {
            this.chooseDownloadLocationMigration(false);
          },
          onMigrate: () => {
            this.chooseDownloadLocationMigration(true);
          }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.donateVisible) {
        DonateOverlay({
          onClose: () => {
            this.donateVisible = false;
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(30)
      }

      if (this.resultVisible) {
        ResultOverlay({
          title: this.resultTitle,
          message: this.resultMessage,
          confirmLabel: this.resultConfirmLabel,
          altLabel: this.resultAltLabel,
          onConfirm: () => {
            const action = this.resultConfirmAction;
            this.resultVisible = false;
            this.resultAltLabel = '';
            this.resultConfirmLabel = 'OK';
            this.resultAltAction = () => {};
            this.resultConfirmAction = () => {};
            action();
          },
          onAlt: () => {
            const action = this.resultAltAction;
            this.resultVisible = false;
            this.resultAltLabel = '';
            this.resultConfirmLabel = 'OK';
            this.resultAltAction = () => {};
            action();
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(29)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }

      if (this.signOutConfirmationVisible) {
        ConfirmActionOverlay({
          title: 'Sign out',
          message: 'The saved login session will be removed.',
          confirmLabel: 'Sign out',
          onCancel: () => {
            this.signOutConfirmationVisible = false;
          },
          onConfirm: () => {
            this.signOut();
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(28)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }

      if (this.updateDialogVisible && this.updateRelease !== null) {
        UpdatePromptOverlay({
          release: this.updateRelease,
          currentVersion: this.updateCurrentVersion,
          onCancel: () => {
            this.updateDialogVisible = false;
          },
          onUpdate: () => {
            this.updateDialogVisible = false;
            this.saveUpdatePackage();
          }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.blockingBusyVisible) {
        BlockingBusyOverlay({
          message: this.blockingBusyMessage,
          progressText: this.blockingBusyProgressText,
          progressCurrent: this.blockingBusyProgressCurrent,
          progressTotal: this.blockingBusyProgressTotal
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
          .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateSceneContentWidth(areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value)));
    })
  }
}

export {
  SettingsHomePanel,
  SettingsAccountWebPanel,
  SettingsSubToolbar,
  SettingsHeaderRow,
  SettingsTextBlock,
  SettingsDetailPanel,
  SettingsOptionPanel,
  SettingsActionRow,
  SettingsStaticRow,
} from './SettingsPanels';

function basenameOf(path: string): string {
  if (path.length === 0) {
    return '';
  }
  const normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  const slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}


// 导出下载列表时去掉只在本机有效的字段：archiveUri 是设备绝对路径，
// 换设备必然失效；导入端会按 gid/标题重新绑定目录。其余元数据与云端状态全部保留，
// 这样红云/蓝云/本地三态也能跟着迁移。
function exportableDownloadItems(): DownloadInfo[] {
  const items = ehDownloadStore.getItems();
  const exported: DownloadInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    const source = items[i];
    const copy: DownloadInfo = {
      gid: source.gid,
      token: source.token,
      title: source.title,
      titleJpn: source.titleJpn,
      thumb: source.thumb,
      category: source.category,
      posted: source.posted,
      uploader: source.uploader,
      rating: source.rating,
      rated: source.rated,
      simpleLanguage: source.simpleLanguage,
      simpleTags: source.simpleTags,
      pages: source.pages,
      thumbWidth: source.thumbWidth,
      thumbHeight: source.thumbHeight,
      favoriteSlot: source.favoriteSlot,
      favoriteName: source.favoriteName,
      tagList: source.tagList,
      detailTags: source.detailTags,
      detailLanguage: source.detailLanguage,
      state: source.state,
      cloudState: source.cloudState,
      legacy: source.legacy,
      time: source.time,
      label: source.label,
      archiveUri: '',
      speed: 0,
      remaining: 0,
      finished: source.finished,
      downloaded: source.downloaded,
      total: source.total,
      fileSize: source.fileSize
    };
    exported.push(copy);
  }
  return exported;
}

