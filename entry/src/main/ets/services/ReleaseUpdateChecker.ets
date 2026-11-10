import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReleaseInfo, parseGitHubRelease, parseGitHubReleasePage, findGitHubHapLink } from './GitHubReleaseParser';
import {
  APP_VERSION_CODE,
  APP_VERSION_NAME,
  EH_RELEASE_TAG,
  EH_REPOSITORY_NAME,
  EH_REPOSITORY_URL
} from './AppBuildInfo';
import {
  applyEhNetworkOptions,
  createEhRequestPlan,
  EhRequestPlan,
  ensureEhHostRules,
  recordEhRequestOutcome
} from './NetworkConfig';
import { acquireHttpRequest, markHttpRequestVolatile, retireHttpRequest } from './HttpRequestLifecycle';

export { ReleaseInfo } from './GitHubReleaseParser';

export interface AppVersionInfo {
  versionName: string;
  versionCode: number;
  releaseTag: string;
}

export interface UpdateCheckResult {
  checked: boolean;
  hasUpdate: boolean;
  current: AppVersionInfo;
  latest: ReleaseInfo | null;
  message: string;
}

interface GitHubReleaseRequestHeader {
  'Host': string;
  'User-Agent': string;
  'Accept': string;
  'Accept-Language': string;
  'Cache-Control': string;
}

const LATEST_RELEASE_API: string = 'https://api.github.com/repos/' + EH_REPOSITORY_NAME + '/releases/latest';
const LATEST_RELEASE_PAGE: string = EH_REPOSITORY_URL + '/releases/latest';
const REQUEST_TIMEOUT_MS: number = 12000;
// 整次检查的总上限：API 失败会再走 release 页面兜底，单次请求 12s 叠加后可能拖到一分钟以上。
// 用户点「检查更新」后必须在一个可感知的时间内看到结果，不能无限转。
const UPDATE_CHECK_TIMEOUT_MS: number = 15000;
const SUCCESS_CACHE_MS: number = 60000;
const API_RETRY_DELAY_MS: number = 60000;
const LOG_DOMAIN: number = 0xD004001;
const LOG_TAG: string = 'ReleaseUpdateChecker';
let apiRetryAt: number = 0;
let cachedRelease: ReleaseInfo | null = null;
let cachedReleaseUntil: number = 0;

class ReleaseUpdateChecker {
  private pending: Promise<UpdateCheckResult> | null = null;

  async checkLatestRelease(): Promise<UpdateCheckResult> {
    if (this.pending !== null) {
      return this.pending;
    }
    this.pending = this.checkLatestReleaseInternal();
    try {
      return await this.pending;
    } finally {
      this.pending = null;
    }
  }

  private async checkLatestReleaseInternal(): Promise<UpdateCheckResult> {
    const current = await getCurrentAppVersion();
    try {
      const latest = await withTimeout(fetchLatestRelease(), UPDATE_CHECK_TIMEOUT_MS);
      const hasUpdate = isVersionNewer(latest.tagName, current.releaseTag);
      return {
        checked: true,
        hasUpdate: hasUpdate,
        current: current,
        latest: latest,
        message: hasUpdate ? 'New version available' : 'No updates available'
      };
    } catch (error) {
      return {
        checked: false,
        hasUpdate: false,
        current: current,
        latest: null,
        message: 'Check for updates failed: ' + errorMessage(error)
      };
    }
  }
}

export const releaseUpdateChecker: ReleaseUpdateChecker = new ReleaseUpdateChecker();

async function getCurrentAppVersion(): Promise<AppVersionInfo> {
  try {
    const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    if (info.versionName.length > 0 && info.versionCode > 0) {
      return {
        versionName: info.versionName,
        versionCode: info.versionCode,
        releaseTag: 'v' + info.versionName
      };
    }
  } catch (error) {
  }
  return {
    versionName: APP_VERSION_NAME,
    versionCode: APP_VERSION_CODE,
    releaseTag: EH_RELEASE_TAG
  };
}

function withTimeout<T>(task: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve: (value: T) => void, reject: (error: Error) => void) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error('timeout after ' + ms.toString() + 'ms'));
      }
    }, ms);
    task.then((value: T) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(value);
      }
    }).catch((error: Error) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(error);
      }
    });
  });
}

async function fetchLatestRelease(): Promise<ReleaseInfo> {
  if (cachedRelease !== null && Date.now() < cachedReleaseUntil) {
    return cachedRelease;
  }
  let apiFailure = 'GitHub API cooling down';
  if (Date.now() >= apiRetryAt) {
    try {
      const response = await fetchReleaseResponse(LATEST_RELEASE_API, 'application/vnd.github+json');
      const status = Number(response.responseCode);
      if (status === 403 || status === 429) {
        apiRetryAt = githubRetryAt(response.header, Date.now());
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'GitHub API HTTP %{public}d, remaining=%{public}s; using release page',
          status, githubHeaderValue(response.header, 'x-ratelimit-remaining'));
      }
      requireSuccess(response);
      const release = parseGitHubRelease(response.result as string);
      if (release === null) {
        throw new Error('Unable to parse GitHub release');
      }
      return cacheRelease(release);
    } catch (error) {
      apiFailure = errorMessage(error);
      apiRetryAt = Math.max(apiRetryAt, Date.now() + API_RETRY_DELAY_MS);
    }
  }
  try {
    const response = await fetchReleaseResponse(LATEST_RELEASE_PAGE, 'text/html');
    requireSuccess(response);
    const release = parseGitHubReleasePage(response.result as string);
    if (release === null) {
      throw new Error('Unable to parse GitHub release page');
    }
    if (release.hapDownloadUrl === release.htmlUrl) {
      // Assets are lazy-loaded on GitHub. A missing asset list must not discard valid version information.
      try {
        const assets = await fetchReleaseResponse(EH_REPOSITORY_URL + '/releases/expanded_assets/' +
          encodeURIComponent(release.tagName), 'text/html');
        requireSuccess(assets);
        release.hapDownloadUrl = findGitHubHapLink(assets.result as string, release.tagName, release.htmlUrl);
      } catch (_error) {
        // Keep the verified official release page as the safe download destination.
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Release page fallback succeeded: %{public}s', release.tagName);
    return cacheRelease(release);
  } catch (error) {
    throw new Error('GitHub API: ' + apiFailure + '; release page: ' + errorMessage(error));
  }
}

function cacheRelease(release: ReleaseInfo): ReleaseInfo {
  cachedRelease = release;
  cachedReleaseUntil = Date.now() + SUCCESS_CACHE_MS;
  return release;
}

function githubHeaderValue(header: Object, name: string): string {
  try {
    const values = (typeof header === 'string' ? JSON.parse(header) : header) as Record<string, string>;
    const keys = Object.keys(values);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === name) {
        return String(values[keys[i]]);
      }
    }
  } catch (_error) {
  }
  return '';
}

function githubRetryAt(header: Object, now: number): number {
  let retryAt = now + API_RETRY_DELAY_MS;
  const retryAfter = githubHeaderValue(header, 'retry-after');
  if (retryAfter.length > 0) {
    const seconds = Number(retryAfter);
    const time = Number.isFinite(seconds) ? now + seconds * 1000 : Date.parse(retryAfter);
    if (Number.isFinite(time)) {
      retryAt = Math.max(retryAt, time);
    }
  }
  if (githubHeaderValue(header, 'x-ratelimit-remaining') === '0') {
    const reset = Number(githubHeaderValue(header, 'x-ratelimit-reset')) * 1000;
    if (Number.isFinite(reset)) {
      retryAt = Math.max(retryAt, reset);
    }
  }
  return retryAt;
}

function requireSuccess(response: http.HttpResponse): void {
  const status = Number(response.responseCode);
  if (status < 200 || status >= 300) {
    throw new Error('HTTP ' + status.toString());
  }
}

async function fetchReleaseResponse(url: string, accept: string): Promise<http.HttpResponse> {
  await ensureEhHostRules();
  const request = acquireHttpRequest();
  const plan = createEhRequestPlan(url);
  const startedAt = Date.now();
  let outcomeRecorded = false;
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: buildGitHubReleaseHeader(plan, accept),
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS,
      maxLimit: 1024 * 1024
    };
    applyEhNetworkOptions(options, plan);
    if (plan.fronted) {
      markHttpRequestVolatile(request);
    }
    const response = await request.request(plan.url, options);
    const statusCode = Number(response.responseCode);
    recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
    outcomeRecorded = true;
    return response;
  } catch (error) {
    if (!outcomeRecorded) {
      recordEhRequestOutcome(plan, false, Date.now() - startedAt);
    }
    throw new Error(errorMessage(error as Object));
  } finally {
    retireHttpRequest(request);
  }
}

function buildGitHubReleaseHeader(plan: EhRequestPlan, accept: string): GitHubReleaseRequestHeader {
  return {
    'Host': plan.host,
    'User-Agent': 'EhViewerHarmony/' + APP_VERSION_NAME,
    'Accept': accept,
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Cache-Control': 'no-cache'
  };
}

function isVersionNewer(latestTag: string, currentTag: string): boolean {
  const latest = parseVersionParts(latestTag);
  const current = parseVersionParts(currentTag);
  const maxLength = Math.max(latest.length, current.length);
  for (let i = 0; i < maxLength; i++) {
    const latestPart = i < latest.length ? latest[i] : 0;
    const currentPart = i < current.length ? current[i] : 0;
    if (latestPart > currentPart) {
      return true;
    }
    if (latestPart < currentPart) {
      return false;
    }
  }
  return false;
}

function parseVersionParts(tag: string): number[] {
  const match = /(\d+(?:\.\d+)*)/.exec(tag);
  if (match === null) {
    return [0];
  }
  const rawParts = match[1].split('.');
  const parts: number[] = [];
  for (let i = 0; i < rawParts.length; i++) {
    const value = Number.parseInt(rawParts[i]);
    parts.push(Number.isNaN(value) ? 0 : value);
  }
  return parts.length === 0 ? [0] : parts;
}

function errorMessage(error: Object): string {
  // ArkTS 里 catch 到的是 Object；BusinessError 的真实原因在 code 与 message 上，
  // 直接 String() 只会得到 "[object Object]"，于是所有网络失败都显示成同一句废话。
  if (error === null || error === undefined) {
    return 'Network request failed';
  }
  const fields = error as Record<string, Object>;
  const rawCode = fields['code'];
  const rawMessage = fields['message'];
  const code = rawCode === undefined || rawCode === null ? '' : String(rawCode);
  let message = rawMessage === undefined || rawMessage === null ? '' : String(rawMessage);
  if (message.length === 0) {
    message = String(error);
  }
  if (message === '[object Object]' || message === 'undefined' || message === 'null') {
    message = '';
  }
  if (message.indexOf('Error: ') === 0) {
    message = message.substring(7);
  }
  if (code.length > 0 && code !== '0') {
    return message.length > 0 ? (code + ': ' + message) : ('Error code ' + code);
  }
  return message.length > 0 ? message : 'Network request failed';
}
