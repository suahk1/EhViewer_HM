import { common } from '@kit.AbilityKit';
import { curves, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { GalleryRoute } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  buildDailyCheckInInspectionScript,
  DAILY_CHECK_IN_FOREGROUND_REVISION_KEY,
  dailyCheckInFailureResult,
  parseEhDailyCheckInWebResult,
  EhDailyCheckInResult
} from '../services/EhDailyCheckInService';
import { ehDownloadStore } from '../services/EhDownloadStore';
import { appLog } from '../services/AppLogService';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { appSettingsStore } from '../services/AppSettingsStore';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import { releaseUpdateChecker, ReleaseInfo, UpdateCheckResult } from '../services/ReleaseUpdateChecker';
import { EhUrl } from '../services/EhUrl';
import {
  EH_WEB_COMPATIBILITY_SCRIPTS,
  loadEhWebUrlWithAndroidCompatibility
} from '../services/WebRuntimeSupport';
import { TRANSLATION_ERROR_MESSAGE_KEY, TRANSLATION_ERROR_REVISION_KEY } from '../services/EhTranslationService';
import {
  peekPendingContinuationSnapshot,
  rememberContinuationRoute,
  takePendingContinuationSnapshot
} from '../services/DistributedContinuationService';
import { EhDrawer } from '../components/NavigationComponents';
import { RemoteSyncDetailOverlay } from '../components/RemoteSyncDetailOverlay';
import { REMOTE_SYNC_DETAIL_VISIBLE_KEY } from '../services/RemoteStorageSyncService';
import { ConfirmActionOverlay } from '../components/ConfirmActionOverlay';
import { FloatingDock, DockMoreMenu, APP_DOCK_BAR_HEIGHT, DOCK_MORE_MENU_HEIGHT,
  appDockBottomGap } from '../components/FloatingDock';
import { ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { resetAppChromeHidden, reportAppOverlayHidden, APP_CHROME_HIDDEN_KEY, APP_OVERLAY_HIDDEN_KEY,
  ZIP_DELETE_ASK_VISIBLE_KEY, ZIP_DELETE_ASK_MESSAGE_KEY, ZIP_DELETE_ASK_PATH_KEY,
  clearZipDeleteAsk } from '../services/AppChromeSignal';
import { UpdatePromptOverlay } from '../components/UpdatePromptOverlay';
import { PopupScrim } from '../components/PopupScrim';
import {
  applyAppChromeImmersiveMode,
  EMBEDDED_READER_ACTIVE_KEY,
  isEmbeddedReaderActive
} from '../services/WindowChromeController';
import { prepareSplitPaneRouteTransition, SPLIT_PANE_MODAL_Z_INDEX } from '../components/SplitPaneSupport';
import { GalleryListScene } from '../components/GalleryScenes';
import { HistoryScene } from '../components/HistoryScene';
import { TopListScene } from '../components/TopListScene';
import { DownloadScene } from '../components/DownloadScene';
import { MigrationScene } from '../components/MigrationScene';
import { SessionScene } from '../components/SessionScene';
import { SettingsScene } from '../components/SettingsScene';
import {
  captureEhAccountWebCookiesAsync as captureEhAccountWebCookies,
  configureWebCookieAccess,
  syncCookieHeaderToWebViewAsync as syncCookieHeaderToWebView
} from '../components/SessionScene';
import {
  BOTTOM_AVOID_HEIGHT_KEY,
  LANGUAGE_REVISION_KEY,
  IDENTITY_AUTH_LOCKED_KEY,
  STATUS_BAR_HEIGHT_KEY,
  THEME_REVISION_KEY,
  ROUTE_RESET_REVISION_KEY,
  getAbilityContext,
  launchRouteFromSetting,
  runActiveBackHandler,
  uiStatusText,
  uiText
} from '../shared/AppRuntime';
import {
  themePageBackground,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor
} from '../shared/AppPalette';

// ----------------------------------------------------------------
// Root page: full-screen immersive shell with slide-in side drawer
// ----------------------------------------------------------------
interface RootNavigationCache {
  initialized: boolean;
  activeRoute: GalleryRoute;
  routeResetVersion: number;
}

let rootNavigationCache: RootNavigationCache = {
  initialized: false,
  activeRoute: GalleryRoute.Home,
  routeResetVersion: 0
};

const DAILY_CHECK_IN_RETRY_INTERVAL_MS: number = 5 * 60 * 1000;
const DAILY_CHECK_IN_WEB_TIMEOUT_MS: number = 30000;
const DAILY_CHECK_IN_WEB_INSPECTION_DELAY_MS: number = 250;
const DAILY_CHECK_IN_WEB_VERIFICATION_RETRY_MS: number = 1500;

@Entry
@Component
struct Index {
  @State activeRoute: GalleryRoute = GalleryRoute.Home;
  // 登录/迁移这类"子页面"没有自己的返回栈，回退要回到进来时的那个页面。
  private previousRoute: GalleryRoute = GalleryRoute.Home;
  @State drawerVisible: boolean = false;
  // 底坞右箭头的展开面板：渲染在页面层，不受胶囊高度裁剪。
  @State dockMoreVisible: boolean = false;
  @State dockBarWidth: number = 0;
  @State viewportWidth: number = 0;
  @State drawerOffsetX: number = -264;
  @State drawerOverlayOpacity: number = 0;
  @State settingsReady: boolean = false;
  @State routeResetVersion: number = 0;
  @State updateDialogVisible: boolean = false;
  @State updateCurrentVersion: string = '';
  @State updateRelease: ReleaseInfo | null = null;
  @StorageProp(ZIP_DELETE_ASK_VISIBLE_KEY) zipDeleteAskVisible: boolean = false;
  @StorageProp(ZIP_DELETE_ASK_MESSAGE_KEY) zipDeleteAskMessage: string = '';
  @StorageProp(ZIP_DELETE_ASK_PATH_KEY) zipDeleteAskPath: string = '';
  @State dailyCheckInDialogVisible: boolean = false;
  @State dailyCheckInMessage: string = '';
  @State dailyCheckInWebMounted: boolean = false;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;
  // 列表下滑时各场景上报收起，底坞跟着滑出屏幕底缘；回滚或到顶时复位。
  @StorageProp(APP_CHROME_HIDDEN_KEY) chromeHidden: boolean = false;
  @StorageProp(APP_OVERLAY_HIDDEN_KEY) overlayHidden: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;
  @StorageProp(IDENTITY_AUTH_LOCKED_KEY) identityAuthLocked: boolean = false;
  // 阅读器激活状态必须走 @StorageProp 订阅：isEmbeddedReaderActive() 只是读 AppStorage，
  // 状态翻转不会触发 Index 重建，本地图册内嵌阅读时底坞就会留在屏幕上遮住画面。
  @StorageProp(EMBEDDED_READER_ACTIVE_KEY) embeddedReaderActive: boolean = false;
  @StorageProp(REMOTE_SYNC_DETAIL_VISIBLE_KEY) remoteSyncDetailVisible: boolean = false;
  @StorageProp(TRANSLATION_ERROR_REVISION_KEY) @Watch('onTranslationErrorRevision') translationErrorRevision: number = 0;
  @StorageProp(DAILY_CHECK_IN_FOREGROUND_REVISION_KEY) @Watch('onDailyCheckInForeground')
  dailyCheckInForegroundRevision: number = 0;
  private dailyCheckInPending: boolean = false;
  private dailyCheckInLastAttemptAt: number = 0;
  private dailyCheckInWebController: webview.WebviewController = new webview.WebviewController();
  private dailyCheckInWebAttached: boolean = false;
  private dailyCheckInWebLoading: boolean = false;
  private dailyCheckInStartedAt: number = 0;
  private dailyCheckInWebTimeoutTimer: number = -1;
  private dailyCheckInWebInspectionTimer: number = -1;
  onTranslationErrorRevision(): void {
    const message = AppStorage.get<string>(TRANSLATION_ERROR_MESSAGE_KEY);
    if (message === undefined || message.length === 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (_error) {
    }
  }

  onDailyCheckInForeground(): void {
    if (!this.settingsReady) {
      return;
    }
    this.requestDailyCheckIn('foreground');
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeight);
  }

  private currentPageBackground(): string {
    // Read the revision on a stable node so theme changes update colors
    // without replacing the active route component tree.
    if (this.themeRevision >= 0) {
      return themePageBackground();
    }
    return themePageBackground();
  }

  private openExternalUrl(url: string): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    }).catch(() => {});
  }

  // 被 back handler 消费、但路由没动的连续次数。第一次照常信任（多数情况是关了个弹层），
  // 连续第二次还这样就不再信，往下走根路由兜底，避免返回键一直空按。
  private backMissCount: number = 0;

  onBackPress(): boolean {
    if (this.drawerVisible) {
      this.closeDrawer();
      return true;
    }
    // 说明：这里不能再按「路由是否变化」决定是否兜底。设置子面板、详情页弹层关闭时
    // activeRoute 本来就不变，一累计就会 setRootRoute，表现为「设置→界面，侧滑一次直接跳主页」。
    // 现在的规则：handler 消费 → 到此为止；没人消费 → 回根路由（不交回系统，避免退桌面）。
    if (runActiveBackHandler()) {
      // handler 消费了这次返回就到此为止，不再叠加任何「兜底跳根路由」。
      // 之前那里按「路由是否变化」计数，而设置子面板、详情页弹层关掉时 activeRoute 本来就不变，
      // 一旦计数攒到 2 就会直接 setRootRoute —— 表现为「设置→界面，侧滑一次直接跳回主页」。
      this.backMissCount = 0;
      return true;
    }
    this.backMissCount = 0;
    const launchRoute = this.routeAfterSignIn();
    if (this.activeRoute !== launchRoute) {
      this.setRootRoute(launchRoute);
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.syncWindowAvoidArea();
    this.restoreRootRoute();
    this.applyContinuationRouteIfPresent();
    const context = getAbilityContext();
    if (context === undefined) {
      this.setRootRoute(GalleryRoute.Home);
      return;
    }
    ehSpiderInfoStore.load(context).catch(() => {});
    ehDownloadStore.load(context).catch(() => {});
    ehHistoryStore.load(context).catch(() => {});
    ehSearchHistoryStore.load(context).catch(() => {});
    appSettingsStore.ensureLoaded(context).then(() => {
      ehTagTranslationStore.preload(context).catch(() => {});
      this.settingsReady = true;
      this.loadSessionRoute(context);
      // 接手自维护后暂时关闭启动自动更新检查（不再弹"发现新版本"），恢复时取消注释即可。
      // this.checkForUpdatesOnStartup();
    }).catch(() => {
      this.settingsReady = true;
      this.loadSessionRoute(context);
      // 接手自维护后暂时关闭启动自动更新检查（不再弹"发现新版本"），恢复时取消注释即可。
      // this.checkForUpdatesOnStartup();
    });
  }

  // Ability 侧读 avoidArea 常常拿到 0（系统还没算完），页面这时窗口一定就绪，自己再读一次。
  // 底栏位置和列表留白都吃这个值，首帧读准了就不用等用户点一下才回正。
  private syncWindowAvoidArea(): void {
    this.readWindowAvoidAreaOnce();
    // 布局完成后系统可能才把避让区补上，再兜一次（只兜一次，不递归）。
    setTimeout(() => {
      this.readWindowAvoidAreaOnce();
    }, 320);
  }

  private readWindowAvoidAreaOnce(): void {
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        let bottomPx = 0;
        try {
          bottomPx = Math.max(bottomPx,
            win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height);
        } catch (error) {
        }
        try {
          bottomPx = Math.max(bottomPx,
            win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
        } catch (error) {
        }
        if (bottomPx <= 0) {
          return;
        }
        const bottomVp = win.getUIContext().px2vp(bottomPx);
        hilog.info(0x0000, 'DockInset', 'avoidPx=%{public}d avoidVp=%{public}f finalGapVp=%{public}f',
          bottomPx, bottomVp, appDockBottomGap(bottomVp));
        if (bottomVp > 0 && bottomVp !== this.bottomAvoidHeight) {
          AppStorage.setOrCreate<number>(BOTTOM_AVOID_HEIGHT_KEY, bottomVp);
        }
      }).catch(() => {
      });
    } catch (error) {
    }
  }

  aboutToDisappear(): void {
    this.clearDailyCheckInWebTimers();
    this.dailyCheckInPending = false;
    this.dailyCheckInWebMounted = false;
    this.dailyCheckInWebAttached = false;
    this.dailyCheckInWebLoading = false;
  }

  private checkForUpdatesOnStartup(): void {
    if (appSettingsStore.getValue('close_auto_updates', 'Off') === 'On') {
      return;
    }
    releaseUpdateChecker.checkLatestRelease().then((result: UpdateCheckResult) => {
      if (result.hasUpdate && result.latest !== null) {
        this.updateCurrentVersion = result.current.versionName;
        this.updateRelease = result.latest;
        this.updateDialogVisible = true;
      }
    }).catch(() => {});
  }

  private loadSessionRoute(ctx: common.UIAbilityContext): void {
    ehCookieStore.ensureLoaded(ctx).then(() => {
      this.applyInitialRoute();
      this.requestDailyCheckIn('startup');
    }).catch(() => {
      this.applyInitialRoute();
      this.requestDailyCheckIn('startup');
    });
  }

  private requestDailyCheckIn(reason: string, force: boolean = false): void {
    if (this.dailyCheckInPending) {
      return;
    }
    if (!ehCookieStore.hasCookies()) {
      this.logDailyCheckInInfo('Skipped: no login session');
      return;
    }
    if (appSettingsStore.getValue('show_eh_events', 'On') !== 'On') {
      this.logDailyCheckInInfo('Skipped: automatic check-in is disabled');
      return;
    }
    const now = Date.now();
    if (!force && now - this.dailyCheckInLastAttemptAt < DAILY_CHECK_IN_RETRY_INTERVAL_MS) {
      return;
    }
    this.dailyCheckInPending = true;
    this.dailyCheckInLastAttemptAt = now;
    this.dailyCheckInStartedAt = now;
    this.dailyCheckInWebController = new webview.WebviewController();
    this.dailyCheckInWebAttached = false;
    this.dailyCheckInWebLoading = false;
    this.dailyCheckInWebMounted = true;
    this.logDailyCheckInInfo('Background Web requested, reason=' + reason);
  }

  private async handleDailyCheckInWebAttached(): Promise<void> {
    this.dailyCheckInWebAttached = true;
    if (!this.dailyCheckInPending || this.dailyCheckInWebLoading) {
      return;
    }
    const startedAt = this.dailyCheckInStartedAt;
    this.dailyCheckInWebLoading = true;
    try {
      this.dailyCheckInWebTimeoutTimer = setTimeout(() => {
        this.finishDailyCheckIn(dailyCheckInFailureResult(
          'Background news page timed out', 'web-timeout'));
      }, DAILY_CHECK_IN_WEB_TIMEOUT_MS);
      await this.prepareDailyCheckInWebCookies();
      if (!this.dailyCheckInPending || startedAt !== this.dailyCheckInStartedAt) {
        return;
      }
      loadEhWebUrlWithAndroidCompatibility(this.dailyCheckInWebController, EhUrl.getNewsUrl());
      this.logDailyCheckInInfo('Background Web loading news.php');
    } catch (error) {
      if (this.dailyCheckInPending && startedAt === this.dailyCheckInStartedAt) {
        this.finishDailyCheckIn(dailyCheckInFailureResult(String(error), 'web-start-failed'));
      }
    }
  }

  private async prepareDailyCheckInWebCookies(): Promise<void> {
    configureWebCookieAccess();
    const cookieHeader = ehCookieStore.getStoredCookieHeader();
    await syncCookieHeaderToWebView(EhUrl.HOST_E, cookieHeader, false, false);
    await syncCookieHeaderToWebView(EhUrl.HOST_EX, cookieHeader, false, false);
    await syncCookieHeaderToWebView(EhUrl.FORUM_ORIGIN, cookieHeader, false, false);
    await webview.WebCookieManager.configCookie(EhUrl.HOST_E, 'nw=1; path=/', false, false);
    await webview.WebCookieManager.configCookie(EhUrl.HOST_EX, 'nw=1; path=/', false, false);
    await webview.WebCookieManager.saveCookieAsync();
  }

  private handleDailyCheckInWebPageEnd(url: string): void {
    if (!this.dailyCheckInPending || !this.dailyCheckInWebAttached) {
      return;
    }
    this.clearDailyCheckInInspectionTimer();
    this.dailyCheckInWebInspectionTimer = setTimeout(() => {
      if (!this.dailyCheckInPending || !this.dailyCheckInWebAttached) {
        return;
      }
      this.dailyCheckInWebController.runJavaScript(buildDailyCheckInInspectionScript())
        .then((raw: string) => {
          return this.handleDailyCheckInWebInspection(url, parseEhDailyCheckInWebResult(raw));
        }).catch((error: Error) => {
          this.finishDailyCheckIn(dailyCheckInFailureResult(error.message, 'inspection-failed'));
        });
    }, DAILY_CHECK_IN_WEB_INSPECTION_DELAY_MS);
  }

  private async handleDailyCheckInWebInspection(url: string, result: EhDailyCheckInResult): Promise<void> {
    if (!this.dailyCheckInPending) {
      return;
    }
    if (result.ok && result.responseKind === 'site-verification') {
      this.logDailyCheckInInfo('Site verification is running in background Web');
      this.clearDailyCheckInInspectionTimer();
      this.dailyCheckInWebInspectionTimer = setTimeout(() => {
        this.handleDailyCheckInWebPageEnd(url);
      }, DAILY_CHECK_IN_WEB_VERIFICATION_RETRY_MS);
      return;
    }
    const startedAt = this.dailyCheckInStartedAt;
    await this.captureDailyCheckInWebCookies(url).catch(() => {});
    if (this.dailyCheckInPending && startedAt === this.dailyCheckInStartedAt) {
      this.finishDailyCheckIn(result);
    }
  }

  private async captureDailyCheckInWebCookies(url: string): Promise<void> {
    const startedAt = this.dailyCheckInStartedAt;
    if (!await captureEhAccountWebCookies(url,
      () => this.dailyCheckInPending && startedAt === this.dailyCheckInStartedAt)) {
      return;
    }
    const context = getAbilityContext();
    if (context !== undefined) {
      await ehCookieStore.save(context).catch(() => {});
    }
  }

  private finishDailyCheckIn(result: EhDailyCheckInResult): void {
    if (!this.dailyCheckInPending) {
      return;
    }
    const elapsedMs = Date.now() - this.dailyCheckInStartedAt;
    this.clearDailyCheckInWebTimers();
    this.dailyCheckInPending = false;
    this.dailyCheckInWebLoading = false;
    this.dailyCheckInWebAttached = false;
    this.dailyCheckInWebMounted = false;
    if (!result.ok) {
      this.logDailyCheckInWarn('Background Web failed, elapsedMs=' + elapsedMs.toString() +
        ', kind=' + result.responseKind + ', message=' + result.message);
      return;
    }
    if (result.event !== null) {
      this.logDailyCheckInInfo('Background Web succeeded, elapsedMs=' + elapsedMs.toString() +
        ', dailyEvent=present, bodyLength=' + result.bodyLength.toString() +
        ', paragraphs=' + result.eventParagraphCount.toString());
      this.dailyCheckInMessage = result.event.message;
      this.dailyCheckInDialogVisible = true;
      return;
    }
    this.logDailyCheckInInfo('Background Web succeeded, elapsedMs=' + elapsedMs.toString() +
      ', dailyEvent=absent, kind=' + result.responseKind + ', bodyLength=' +
      result.bodyLength.toString() + ', paragraphs=' + result.eventParagraphCount.toString());
  }

  private clearDailyCheckInInspectionTimer(): void {
    if (this.dailyCheckInWebInspectionTimer >= 0) {
      clearTimeout(this.dailyCheckInWebInspectionTimer);
      this.dailyCheckInWebInspectionTimer = -1;
    }
  }

  private clearDailyCheckInWebTimers(): void {
    this.clearDailyCheckInInspectionTimer();
    if (this.dailyCheckInWebTimeoutTimer >= 0) {
      clearTimeout(this.dailyCheckInWebTimeoutTimer);
      this.dailyCheckInWebTimeoutTimer = -1;
    }
  }

  private logDailyCheckInInfo(message: string): void {
    appLog.info(getAbilityContext(), 'DailyCheckIn', message);
  }

  private logDailyCheckInWarn(message: string): void {
    appLog.warn(getAbilityContext(), 'DailyCheckIn', message);
  }

  private handleSignedIn(): void {
    this.setRootRoute(this.routeAfterSignIn());
    this.requestDailyCheckIn('signed-in', true);
  }

  private restoreRootRoute(): void {
    if (!rootNavigationCache.initialized) {
      return;
    }
    this.activeRoute = rootNavigationCache.activeRoute;
    this.routeResetVersion = rootNavigationCache.routeResetVersion;
  }

  private applyContinuationRouteIfPresent(): void {
    const snapshot = peekPendingContinuationSnapshot();
    if (snapshot === null || snapshot.route.length === 0) {
      return;
    }
    const routes: GalleryRoute[] = [GalleryRoute.Home, GalleryRoute.Subscription, GalleryRoute.WhatsHot,
      GalleryRoute.TopLists, GalleryRoute.Favorites, GalleryRoute.History, GalleryRoute.Downloads,
      GalleryRoute.Session, GalleryRoute.Migration, GalleryRoute.Settings];
    if (routes.indexOf(snapshot.route as GalleryRoute) >= 0) {
      this.setRootRoute(snapshot.route as GalleryRoute);
      if (snapshot.kind === 'main') {
        takePendingContinuationSnapshot();
      }
    }
  }

  private applyInitialRoute(): void {
    if (rootNavigationCache.initialized) {
      this.restoreRootRoute();
      return;
    }
    this.setRootRoute(this.routeAfterSignIn());
  }

  private routeAfterSignIn(): GalleryRoute {
    return launchRouteFromSetting(appSettingsStore.getValue('launch_page', 'Homepage'));
  }

  selectRoute(route: GalleryRoute): void {
    applyAppChromeImmersiveMode();
    if (route === this.activeRoute) {
      this.closeDrawer();
      return;
    }
    this.dockMoreVisible = false;
    this.setRootRoute(route);
    this.closeDrawer();
  }

  private setRootRoute(route: GalleryRoute): void {
    prepareSplitPaneRouteTransition();
    // 新页面从常驻位开始：底坞必须是可见的，各场景滚动帧里再按需上报收起。
    resetAppChromeHidden();
    // 浮层信号一并复位：设置子面板、搜索结果这类「占满整页」的状态在切页之后不再成立，
    // 不复位就会出现切到别的页面底坞仍然收着、只能重启才能回来。
    reportAppOverlayHidden(false);
    if (route !== GalleryRoute.Session && route !== GalleryRoute.Migration) {
      this.previousRoute = this.activeRoute;
    }
    this.activeRoute = route;
    rememberContinuationRoute(route.toString());
    this.routeResetVersion++;
    // 通知列表场景清掉详情/阅读器/弹层等临时层，否则切回来仍停在上一本的详情。
    const resetRevision = AppStorage.get<number>(ROUTE_RESET_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(ROUTE_RESET_REVISION_KEY, resetRevision + 1);
    rootNavigationCache = {
      initialized: true,
      activeRoute: this.activeRoute,
      routeResetVersion: this.routeResetVersion
    };
  }

  openDrawer(): void {
    this.drawerVisible = true;
    this.getUIContext().animateTo({ curve: curves.springMotion(0.5, 0.85) }, () => {
      this.drawerOffsetX = 0;
      this.drawerOverlayOpacity = 0.45;
    });
  }

  closeDrawer(): void {
    this.getUIContext().animateTo({ curve: curves.springMotion(0.45, 0.9) }, () => {
      this.drawerOffsetX = -264;
      this.drawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.drawerOffsetX < -200) {
        this.drawerVisible = false;
      }
    }, 260);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.dailyCheckInWebMounted) {
        Web({ src: '', controller: this.dailyCheckInWebController, incognitoMode: false })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptOnDocumentStart(EH_WEB_COMPATIBILITY_SCRIPTS)
          .onControllerAttached(() => {
            this.handleDailyCheckInWebAttached();
          })
          .onPageEnd((event: OnPageEndEvent) => {
            this.handleDailyCheckInWebPageEnd(event.url);
          })
          .onRenderExited(() => {
            this.finishDailyCheckIn(dailyCheckInFailureResult(
              'Background Web render process exited', 'web-render-exited'));
          })
          .width(2)
          .height(2)
          .clip(true)
          .opacity(0.01)
          .hitTestBehavior(HitTestMode.None)
          .zIndex(0)
      }

      // ---- Main content ----
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.settingsReady) {
          this.RouteContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.currentPageBackground())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // ---- Scrim + drawer ----
      if (this.drawerVisible) {
        PopupScrim({
          showCutout: true,
          positionedCutout: true,
          cutoutX: this.drawerOffsetX,
          cutoutY: 0,
          cutoutWidth: 264,
          cutoutHeight: '100%',
          cutoutRadius: 0,
          scrimOpacity: this.drawerOverlayOpacity,
          onDismiss: () => { this.closeDrawer(); }
        })
          .zIndex(8)

        EhDrawer({
          activeRoute: this.activeRoute,
          statusBarHeight: this.statusBarVp(),
          onSelect: (route: GalleryRoute) => { this.selectRoute(route); }
        })
          .translate({ x: this.drawerOffsetX })
          .zIndex(9)
          .shadow({ radius: 32, color: themeShadowColor(), offsetX: 8, offsetY: 0 })
      }

      // 展开面板的点击遮罩：铺满整屏，点任意位置收起，不改变页面状态。
      // 遮罩必须是可命中区域：完全透明的容器在部分版本上收不到点击，
      // 用 1% 不透明度 + Block 命中模式，保证点外部任何位置都能收起。
      if (this.dockMoreVisible) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor('#01FFFFFF')
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.dockMoreVisible = false;
          })
          .zIndex(7)
      }

      if (this.shouldShowDock()) {
        Row() {
          FloatingDock({
            activeRoute: this.activeRoute,
            moreExpanded: this.dockMoreVisible,
            onMoreRequest: () => {
              this.dockMoreVisible = !this.dockMoreVisible;
            },
            onDockWidthChange: (width: number) => {
              this.dockBarWidth = width;
            },
            onSelect: (route: GalleryRoute) => {
              this.selectRoute(route);
            },
            onReselect: () => {
              // 点当前 tab：只让当前场景回到根部，其他路由的缓存现场不动。
              this.routeResetVersion += 1;
            }
          })
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: this.dockTranslateY() })
        // 收起/回位都走弹簧，跟列表滚动同拍。
        .animation({ curve: curves.springMotion(0.38, 0.92) })
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(8)
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.move(TransitionEdge.BOTTOM).combine(TransitionEffect.OPACITY)
            .animation({ curve: curves.springMotion(0.4, 0.9) }),
          TransitionEffect.move(TransitionEdge.BOTTOM).combine(TransitionEffect.OPACITY)
            .animation({ duration: 150, curve: Curve.EaseIn })
        ))
      }

      // 展开面板：绝对定位叠在胶囊上方，不参与底栏布局，因此不会被 60vp 的胶囊裁掉。
      if (this.shouldShowDock() && this.dockMoreVisible) {
        Row() {
          DockMoreMenu({
            activeRoute: this.activeRoute,
            onSelect: (route: GalleryRoute) => {
              this.dockMoreVisible = false;
              this.selectRoute(route);
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: this.dockMenuRightInset() })
        // 外层是整屏宽的容器，不设 Transparent 时它会把菜单左右的空白区一起吃掉，
        // 表现为点上下能收起、点左右没反应。
        .hitTestBehavior(HitTestMode.Transparent)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.viewportWidth = Number.parseFloat(newArea.width.toString());
        })
        .position({ x: 0, y: '100%' })
        .translate({ y: this.dockTranslateY() - 8 - DOCK_MORE_MENU_HEIGHT })
        .zIndex(9)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 10 }))
          .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
          .animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.updateDialogVisible && this.updateRelease !== null) {
        UpdatePromptOverlay({
          release: this.updateRelease,
          currentVersion: this.updateCurrentVersion,
          onCancel: () => {
            this.updateDialogVisible = false;
          },
          onUpdate: () => {
            const release = this.updateRelease;
            this.updateDialogVisible = false;
            if (release !== null) {
              this.openExternalUrl(release.hapDownloadUrl);
            }
          }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.dailyCheckInDialogVisible) {
        ConfirmActionOverlay({
          title: 'Daily check-in',
          message: this.dailyCheckInMessage,
          confirmLabel: 'OK',
          danger: false,
          showCancel: false,
          onCancel: () => { this.dailyCheckInDialogVisible = false; },
          onConfirm: () => { this.dailyCheckInDialogVisible = false; }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX + 1)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.zipDeleteAskVisible) {
        ConfirmActionOverlay({
          title: uiText('ZIP archives processed'),
          message: this.zipDeleteAskMessage,
          confirmLabel: uiText('Delete'),
          altLabel: uiText('Keep'),
          showCancel: false,
          danger: true,
          onAlt: () => {
            clearZipDeleteAsk();
          },
          onCancel: () => {
            clearZipDeleteAsk();
          },
          onConfirm: () => {
            const archivePath = this.zipDeleteAskPath;
            clearZipDeleteAsk();
            ehDownloadFileStore.removeFiles([archivePath]);
          }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX + 1)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.remoteSyncDetailVisible) {
        RemoteSyncDetailOverlay({
          onClose: () => {
            AppStorage.setOrCreate<boolean>(REMOTE_SYNC_DETAIL_VISIBLE_KEY, false);
          }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX + 2)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.identityAuthLocked) {
        Column() {
          Text(uiText('Identity authentication required'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(themePrimaryText())
          Text(uiText('Unlock to continue using EhViewer'))
            .fontSize(14)
            .fontColor(themeSecondaryText())
            .margin({ top: 10 })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .backgroundColor(themePageBackground())
        .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    // 不再有左滑开抽屉手势：底部标签栏主导航，抽屉只从各页菜单按钮进入，
    // 避免底部上滑收起 chrome 与右滑手势互相抢事件。
  }

  // 底坞只在四个主入口显示：抽屉展开、锁屏、嵌入式阅读时让位给内容。
  private shouldShowDock(): boolean {
    if (this.drawerVisible || this.identityAuthLocked ||
      this.embeddedReaderActive || isEmbeddedReaderActive()) {
      return false;
    }
    // 底坞右箭头展开的四项同样属于主导航：切过去必须保留底坞，否则只能靠返回键退出。
    return this.activeRoute === GalleryRoute.Home || this.activeRoute === GalleryRoute.Favorites ||
      this.activeRoute === GalleryRoute.Downloads || this.activeRoute === GalleryRoute.Settings ||
      this.activeRoute === GalleryRoute.Subscription || this.activeRoute === GalleryRoute.WhatsHot ||
      this.activeRoute === GalleryRoute.TopLists || this.activeRoute === GalleryRoute.History;
  }

  // 展开面板贴着胶囊右端：胶囊在视口居中，右端到视口右侧的距离就是这段缩进。
  private dockMenuRightInset(): number {
    if (this.viewportWidth <= 0 || this.dockBarWidth <= 0) {
      return 24;
    }
    return Math.max(12, (this.viewportWidth - this.dockBarWidth) / 2);
  }

  // 底栏常驻位 = 胶囊高度 + 手势条避让（bottomAvoidHeight 已是 vp）；
  // 列表下滑时直接回到 translate 0，整条滑出屏幕底缘。
  private dockTranslateY(): number {
    if (this.chromeHidden || this.overlayHidden) {
      return 0;
    }
    // 与列表留白共用 appDockBottomGap：胶囊位置和内容留白永远同一个值。
    return -(APP_DOCK_BAR_HEIGHT + appDockBottomGap(this.bottomAvoidHeight));
  }

  // 底部标签切换用淡入上浮，不做横向滑入：横向位移对同层 tab 是错误语义。
  private routeTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
        .animation({ curve: curves.springMotion(0.42, 0.85) }),
      TransitionEffect.OPACITY.animation({ duration: 80, curve: Curve.EaseIn })
    );
  }

  @Builder
  private RouteContent() {
    if (this.activeRoute === GalleryRoute.Home) {
      GalleryListScene({
        sceneTitle: 'Homepage',
        listMode: 'Search',
        sourceRoute: GalleryRoute.Home,
        resetVersion: this.routeResetVersion,
        onMenu: () => { this.openDrawer(); }
      })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.Subscription) {
      GalleryListScene({
        sceneTitle: 'Subscription',
        listMode: 'Watched tags',
        sourceRoute: GalleryRoute.Subscription,
        resetVersion: this.routeResetVersion,
        onMenu: () => { this.openDrawer(); }
      })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.WhatsHot) {
      GalleryListScene({
        sceneTitle: 'What\'s Hot',
        listMode: 'Popular',
        sourceRoute: GalleryRoute.WhatsHot,
        resetVersion: this.routeResetVersion,
        onMenu: () => { this.openDrawer(); }
      })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.TopLists) {
      TopListScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.Favorites) {
      GalleryListScene({
        sceneTitle: 'Favourite',
        listMode: 'Favorites',
        sourceRoute: GalleryRoute.Favorites,
        resetVersion: this.routeResetVersion,
        onMenu: () => { this.openDrawer(); }
      })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.History) {
      HistoryScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.Downloads) {
      DownloadScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.Session) {
      SessionScene({
        onSignedIn: () => { this.handleSignedIn(); },
        // 必须传 onBack：没有它，登录页进去后没有出口。
        onBack: () => { this.selectRoute(this.previousRoute); }
      })
        .transition(this.routeTransition())
    } else if (this.activeRoute === GalleryRoute.Migration) {
      MigrationScene()
        .transition(this.routeTransition())
    } else {
      SettingsScene({
        resetVersion: this.routeResetVersion,
        onMenu: () => { this.openDrawer(); },
        onSignedIn: () => { this.handleSignedIn(); }
      })
        .transition(this.routeTransition())
    }
  }
}
