import { common } from '@kit.AbilityKit';
import { GallerySite, GalleryInfo } from '../model/GalleryModels';
import { CLOUD_STATE_GONE, ehDownloadStore } from './EhDownloadStore';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { appKeepAlive } from './AppKeepAlive';
import { EhHttpClient, EhTextRequestOptions, GalleryListLoadResult } from './EhHttpClient';
import { ListUrlBuilder, gallerySiteCandidates, EhUrl } from './EhUrl';
import { galleryIdFromName } from './LocalFolderImportService';

// F-115：下载页后台云端匹配服务（全局单例）。
//
// 目标（用户定稿的方案）：
// 1. 扫描导入只做本地登记（不联网），进入下载页自动触发本服务补云端身份；
// 2. 匹配成功 → 云端数据回写，列表实时刷新；云端确认删除 → 转手机图标纯本地；
// 3. 网络波动 ≠ 云端删除：失败保留待重试，轮次收敛（本轮失败集进下一轮，
//    直到全部成功 / 拿到「云端不存在」的决定性证据 / 达到轮次上限）；
// 4. 任务挂在模块级单例上，切到其它界面、应用切后台（continuous task 保活）
//    都不中断；进度经 AppStorage 广播，下载页弹窗只是它的观察者。

export const DOWNLOAD_MATCH_STATE_KEY: string = 'downloadMatchState';
// 最小化状态跨组件挂载存活（后台锁定，F-124）：切界面回来不重新弹窗。
export const MATCH_DIALOG_MINIMIZED_KEY: string = 'downloadMatchDialogMinimized';
export const DOWNLOAD_MATCH_PROGRESS_KEY: string = 'downloadMatchProgress';
export const DOWNLOAD_MATCH_REPORT_KEY: string = 'downloadMatchReport';

// state: '' 空闲 / 'matching' 进行中 / 'done' 完成
export interface DownloadMatchProgress {
  state: string;
  current: number;
  total: number;
  round: number;
  phase: string;
}

function buildMatchProgress(state: string, current: number, total: number, round: number,
  phase: string): DownloadMatchProgress {
  const p: DownloadMatchProgress = {
    state: state,
    current: current,
    total: total,
    round: round,
    phase: phase
  };
  return p;
}

function buildMatchReport(total: number, matched: number, cloudGone: number, unchanged: number,
  pendingNetwork: number, rounds: number): DownloadMatchReport {
  const r: DownloadMatchReport = {
    total: total,
    matched: matched,
    cloudGone: cloudGone,
    unchanged: unchanged,
    pendingNetwork: pendingNetwork,
    rounds: rounds
  };
  return r;
}

export interface DownloadMatchReport {
  // 候选总数：与弹窗进度里的 total 同源，报告/弹窗数据一致性由它保证。
  total: number;
  matched: number;
  cloudGone: number;
  unchanged: number;
  pendingNetwork: number;
  rounds: number;
}

const MATCH_MAX_ROUNDS: number = 5;
// 探测请求专用选项：短超时 + 不重试（默认每请求 3 次重试会把「停止」拖到 2 分钟）。
// 单请求 ≤18s，一条候选最多 4 请求 ≈ 72s 封顶，「停止」按钮快速生效（F-116）。
const MATCH_PROBE_OPTIONS: EhTextRequestOptions = {
  connectTimeoutMs: 8000,
  readTimeoutMs: 10000,
  attempts: 1,
  includeUConfig: true
};

// 云端探测结果：found=画廊还在；definitiveGone=拿到 404/Not found 决定性证据。
export interface GalleryProbeResult {
  found: boolean;
  definitiveGone: boolean;
}

// ArkTS 禁止对象字面量当返回值，统一走显式构造。
export class GalleryProbeResultFix {
  static foundResult(): GalleryProbeResult {
    const r: GalleryProbeResult = { found: true, definitiveGone: false };
    return r;
  }

  static goneResult(): GalleryProbeResult {
    const r: GalleryProbeResult = { found: false, definitiveGone: true };
    return r;
  }

  static networkFailure(): GalleryProbeResult {
    const r: GalleryProbeResult = { found: false, definitiveGone: false };
    return r;
  }
}

class DownloadMatchService {
  private running: boolean = false;
  private forceMode: boolean = false;
  // 用户可手动停止（弹窗停止按钮）：置位后循环在下一候选前退出。
  private stopRequested: boolean = false;
  private wasStoppedFlag: boolean = false;
  // 进程内自动触发守卫（F-116）：切界面回下载页时不再自动重跑——否则上轮
  // 有待重试候选时，用户每回一次下载页就重跑一遍，表现为「匹配重新开始」。
  private autoRanThisSession: boolean = false;

  hasAutoRanThisSession(): boolean {
    return this.autoRanThisSession;
  }

  wasStopped(): boolean {
    return this.wasStoppedFlag;
  }
  private progress: DownloadMatchProgress = {
    state: '', current: 0, total: 0, round: 0, phase: ''
  };

  isRunning(): boolean {
    return this.running;
  }

  requestStop(): void {
    this.stopRequested = true;
    this.wasStoppedFlag = true;
  }

  currentProgress(): DownloadMatchProgress {
    return this.progress;
  }

  private publish(state: string, current: number, total: number, round: number, phase: string): void {
    this.progress = buildMatchProgress(state, current, total, round, phase);
    AppStorage.setOrCreate<DownloadMatchProgress>(DOWNLOAD_MATCH_PROGRESS_KEY, this.progress);
    const revision = AppStorage.get<number>(DOWNLOAD_MATCH_STATE_KEY) ?? 0;
    AppStorage.setOrCreate<number>(DOWNLOAD_MATCH_STATE_KEY, revision + 1);
  }

  private static lastMatchFailureWasNotFound: boolean = false;

  // 按 gid 探测云端：区分「确认不存在（决定性证据）」与「网络失败（待重试）」。
  // 关键规则（F-115 教训）：单个站点 404 不能判定 gone——Ex 站未登录/无权限也会 404。
  // 必须所有候选站点都返回明确的 Not found，才算决定性证据；其余一律按待重试处理。
  private static async probeGalleryOnServer(client: EhHttpClient, site: GallerySite,
    gid: number): Promise<GalleryProbeResult> {
    const sites = gallerySiteCandidates(site);
    for (let i = 0; i < sites.length; i++) {
      const builder = new ListUrlBuilder();
      builder.keyword = 'gid:' + gid.toString();
      let result: GalleryListLoadResult;
      try {
        result = await client.loadGalleryList(builder, sites[i], false, MATCH_PROBE_OPTIONS);
      } catch (error) {
        continue;
      }
      if (!result.ok) {
        continue;
      }
      for (let j = 0; j < result.galleries.length; j++) {
        if (result.galleries[j].gid === gid && result.galleries[j].token.length > 0) {
          return GalleryProbeResultFix.foundResult();
        }
      }
    }
    // 搜索命不中时逐站开 /g/{gid}/：站点对已删除画廊返回 404 + Not found 文案。
    // 全部站点都明确 Not found 才算决定性证据；任何一站给出其它响应（403/登录页）
    // 都说明「查不到 ≠ 不存在」，按待重试处理，绝不误清用户的云端身份。
    let sawExplicitNotFound = false;
    let sawAnyResponse = false;
    for (let i = 0; i < sites.length; i++) {
      try {
        const detailResult = await client.loadGalleryDetailByGid(gid, sites[i],
          EhUrl.getReferer(sites[i]), MATCH_PROBE_OPTIONS);
        sawAnyResponse = true;
        if (detailResult.ok && detailResult.detail !== null && detailResult.detail.token.length > 0) {
          return GalleryProbeResultFix.foundResult();
        }
        if (detailResult.message.indexOf('Not found') >= 0 || detailResult.statusCode === 404) {
          sawExplicitNotFound = true;
          continue;
        }
        // 非明确 404 的其它失败（403/登录跳转/限流）：单站如此就不足以判定 gone。
        sawExplicitNotFound = false;
        break;
      } catch (error) {
        sawExplicitNotFound = false;
        break;
      }
    }
    if (sawAnyResponse && sawExplicitNotFound) {
      return GalleryProbeResultFix.goneResult();
    }
    return GalleryProbeResultFix.networkFailure();
  }

  // 主入口：幂等，重复调用直接复用进行中的任务。
  // force=false（自动触发）只处理从未校验过的记录；force=true（手动）全量重校验。
  async startMatch(context: common.UIAbilityContext, force: boolean = false): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.forceMode = force;
    this.stopRequested = false;
    this.wasStoppedFlag = false;
    this.autoRanThisSession = true;
    await appKeepAlive.acquire(context);
    try {
      await this.runRounds(context);
    } finally {
      this.running = false;
      await appKeepAlive.release();
    }
  }

  private async runRounds(context: common.UIAbilityContext): Promise<void> {
    // force 模式重置探测标记（archiveUri 有效的记录）：修复误判 / 重试待重试候选时，
    // 用户点一次「重新匹配」即可自愈——重置后它们重新进入候选，probe 修正后自动恢复。
    if (this.forceMode) {
      const snapshotForReset = ehDownloadStore.getItems();
      for (let i = 0; i < snapshotForReset.length; i++) {
        const item = snapshotForReset[i];
        const marked = item.cloudState === CLOUD_STATE_GONE || item.cloudState === 'probed';
        if (marked && item.archiveUri.length > 0) {
          ehDownloadStore.setCloudState(item.gid, '');
        }
      }
    }
    let matched = 0;
    let cloudGone = 0;
    let unchanged = 0;
    let pendingNetwork = 0;
    let round = 0;
    let lastRoundFailures = -1;
    let totalCandidates = 0;
    let processed = 0;

    while (round < MATCH_MAX_ROUNDS) {
      round++;
      const site: GallerySite = this.currentSite();
      const client = new EhHttpClient();

      // ---- 候选集 1：纯本地（token 空）补云端身份 ----
      // 已拿到「云端确认删除」证据（cloudState=gone）的不再重复探测，否则无限循环。
      const snapshot = ehDownloadStore.getItems();
      const localCandidates: Number[] = [];
      for (let i = 0; i < snapshot.length; i++) {
        const item = snapshot[i];
        if (item.token.length > 0 || item.archiveUri.length === 0 ||
          item.cloudState === CLOUD_STATE_GONE) {
          continue;
        }
        const separator = Math.max(item.archiveUri.lastIndexOf('/'), item.archiveUri.lastIndexOf('\\'));
        const directoryName = separator >= 0 ? item.archiveUri.substring(separator + 1) : item.archiveUri;
        if (galleryIdFromName(directoryName) > 0) {
          localCandidates.push(item.gid);
        }
      }

      // ---- 候选集 2：云朵（token 非空）校验云端存在性 ----
      // 自动模式只校验从未校验过的（cloudState 为空）；已标记 ok/gone 的不再反复探测。
      const cloudCandidates: Number[] = [];
      for (let i = 0; i < snapshot.length; i++) {
        const item = snapshot[i];
        if (item.token.length === 0) {
          continue;
        }
        const unverified = item.cloudState === undefined || item.cloudState.length === 0;
        if (this.forceMode || unverified) {
          if (!unverified || item.cloudState !== CLOUD_STATE_GONE) {
            cloudCandidates.push(item.gid);
          }
        }
      }

      const total = localCandidates.length + cloudCandidates.length;
      totalCandidates += total;
      console.info('[DownloadMatch] round ' + round.toString() + ' start, candidates=' +
        localCandidates.length.toString() + ' local + ' + cloudCandidates.length.toString() + ' cloud');
      if (total === 0) {
        console.info('[DownloadMatch] no candidates left, rounds finished');
        break;
      }
      pendingNetwork = 0;
      let current = 0;
      let roundFailures = 0;
      const matchedAtRoundStart = matched;
      const goneAtRoundStart = cloudGone;

      for (let i = 0; i < localCandidates.length; i++) {
        if (this.stopRequested) {
          break;
        }
        current++;
        this.publish('matching', current, total, round, 'local');
        const gid = Number(localCandidates[i]);
        const probe = await DownloadMatchService.probeGalleryOnServer(client, site, gid);
        if (!probe.found) {
          if (probe.definitiveGone) {
            // 决定性证据：云端确认没有。纯本地记录打 GONE 标记：后续轮次与
            // 自动触发都不再探测它，否则这批候选每次打开应用都全量重跑。
            ehDownloadStore.setCloudState(gid, CLOUD_STATE_GONE);
            unchanged++;
          } else {
            // 网络失败：打 probed 标记（已尝试过但无结论）。自动触发不再重跑，
            // 用户点「重新匹配」（force）时统一重置重试。
            ehDownloadStore.setCloudState(gid, 'probed');
            unchanged++;
            pendingNetwork++;
            roundFailures++;
          }
          continue;
        }
        // 拉到 token：绑定云端身份（本机目录/进度/封面保留，mergeImportedItem 已按本机优先处理）。
        const item = ehDownloadStore.getItemByGid(gid);
        if (item === undefined) {
          unchanged++;
          continue;
        }
        const tokenProbe = await this.fetchGalleryInfo(client, site, gid);
        if (tokenProbe === null) {
          ehDownloadStore.setCloudState(gid, 'probed');
          unchanged++;
          pendingNetwork++;
          roundFailures++;
          continue;
        }
        const pageCount = item.total > 0 ? item.total : item.pages;
        const outcome = ehDownloadStore.bindMatchedGallery(tokenProbe, item.archiveUri, pageCount,
          item.fileSize, item.time);
        if (outcome === 'added' || outcome === 'merged') {
          matched++;
        } else {
          unchanged++;
        }
      }

      for (let i = 0; i < cloudCandidates.length; i++) {
        if (this.stopRequested) {
          break;
        }
        current++;
        this.publish('matching', current, total, round, 'cloud');
        const gid = Number(cloudCandidates[i]);
        const probe = await DownloadMatchService.probeGalleryOnServer(client, site, gid);
        if (this.stopRequested) {
          break;
        }
        if (!probe.found) {
          if (probe.definitiveGone && this.forceMode) {
            // F-125 用户反馈「云端有数据被识别成本地」：自动模式下探测受网络
            // 环境（未登录镜像站 404 等）干扰可能误判 GONE，一旦清身份数据
            // 就降级且用户无感知。收紧策略：清云端身份（GONE 降级）只在用户
            // 手动「扫描与匹配」（force）时执行；自动模式打 probed 标记保留
            // 云端身份，绝不降级。
            ehDownloadStore.setCloudState(gid, CLOUD_STATE_GONE);
            ehDownloadStore.clearCloudIdentity(gid);
            cloudGone++;
          } else if (probe.definitiveGone) {
            ehDownloadStore.setCloudState(gid, 'probed');
          } else {
            pendingNetwork++;
            roundFailures++;
          }
          continue;
        }
        // 云端还在：拉完整详情回写列表元数据（上传者/评分/分类此前一直是
        // DP 迁移的空值，详情页明明能看到云端数据，列表却不更新——就在这里补齐），
        // 并把云朵状态标为 OK（有依据，不再是空标记）。
        const galleryInfo = await this.fetchGalleryInfo(client, site, gid);
        if (galleryInfo !== null) {
          ehDownloadStore.updateGallery(galleryInfo);
        }
        ehDownloadStore.setCloudState(gid, 'ok');
      }

      console.info('[DownloadMatch] round ' + round.toString() + ' done: matched+=' +
        (matched - matchedAtRoundStart).toString() + ' gone+=' + (cloudGone - goneAtRoundStart).toString() +
        ' networkFail=' + roundFailures.toString());
      // 收敛判定只看网络失败数：GONE/成功都是结论，不驱动重试。
      // 本轮零网络失败 → 完成；网络失败数未下降 → 连续网络问题，停止等下次进入。
      await ehDownloadStore.save(context);
      if (this.stopRequested) {
        break;
      }
      if (roundFailures === 0) {
        break;
      }
      if (lastRoundFailures >= 0 && roundFailures >= lastRoundFailures) {
        break;
      }
      lastRoundFailures = roundFailures;
    }

    // 报告 total 与弹窗进度 total 同源（各轮候选累计），保证「弹窗 30 · 报告共 30」。
    const report: DownloadMatchReport = buildMatchReport(totalCandidates, matched, cloudGone,
      unchanged, pendingNetwork, round);
    AppStorage.setOrCreate<DownloadMatchReport>(DOWNLOAD_MATCH_REPORT_KEY, report);
    this.publish('done', 0, 0, round, '');
  }

  private async fetchGalleryInfo(client: EhHttpClient, site: GallerySite,
    gid: number): Promise<GalleryInfo | null> {
    const sites = gallerySiteCandidates(site);
    for (let i = 0; i < sites.length; i++) {
      try {
        const detailResult = await client.loadGalleryDetailByGid(gid, sites[i]);
        if (detailResult.ok && detailResult.detail !== null && detailResult.detail.token.length > 0) {
          return detailResult.detail;
        }
        if (detailResult.message.indexOf('Not found') >= 0) {
          return null;
        }
      } catch (error) {
        continue;
      }
    }
    return null;
  }

  private currentSite(): GallerySite {
    const value = AppStorage.get<number>('currentGallerySiteIndex') ?? 0;
    return value === 1 ? GallerySite.Ex : GallerySite.E;
  }

  // 进入下载页时判断是否需要自动触发：有待匹配候选且任务未在跑。
  // 已探测过的记录（ok / gone / probed）都不算待匹配——否则每次打开应用都全量重跑。
  hasPendingWork(): boolean {
    const snapshot = ehDownloadStore.getItems();
    for (let i = 0; i < snapshot.length; i++) {
      const item = snapshot[i];
      if (item.token.length > 0 &&
        (item.cloudState === undefined || item.cloudState.length === 0)) {
        return true;
      }
      // 纯本地：只有从未探测过（cloudState 为空）的才算待匹配。
      if (item.token.length === 0 && item.archiveUri.length > 0 &&
        (item.cloudState === undefined || item.cloudState.length === 0)) {
        const separator = Math.max(item.archiveUri.lastIndexOf('/'), item.archiveUri.lastIndexOf('\\'));
        const directoryName = separator >= 0 ? item.archiveUri.substring(separator + 1) : item.archiveUri;
        if (galleryIdFromName(directoryName) > 0) {
          return true;
        }
      }
    }
    return false;
  }
}

export const downloadMatchService: DownloadMatchService = new DownloadMatchService();
