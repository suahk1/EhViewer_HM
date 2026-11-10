import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { appLog } from './AppLogService';
import { appSettingsStore } from './AppSettingsStore';
import {
  acquireHttpRequest,
  hasActiveHttpRequests,
  markHttpRequestVolatile,
  retireHttpRequest
} from './HttpRequestLifecycle';

const YANDEX_DOH_URL: string = 'https://common.dot.dns.yandex.net/dns-query';
const CLOUDFLARE_DOH_URL: string = 'https://cloudflare-dns.com/dns-query';
const GOOGLE_DOH_URL: string = 'https://dns.google/dns-query';
const FRONTING_IP_CACHE_FILE_NAME: string = 'eh_fronting_ip_quality.json';
const FRONTING_IP_CACHE_VERSION: number = 1;
const FRONTING_PROBE_CONNECT_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_READ_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_DEADLINE_MS: number = 4500;
const FRONTING_PROBE_CONCURRENCY: number = 1;
const FRONTING_PREFERRED_IP_LIMIT: number = 3;
const FRONTING_TAIL_SAMPLE_RATE: number = 0.08;
const FRONTING_WEIGHT_SCORE_BASE: number = 500;
const DIRECT_PROBE_TIMEOUT_MS: number = 5000;
const DIRECT_HOST_FAILURE_THRESHOLD: number = 1;
const DIRECT_HOST_BLOCK_MS: number = 120000;
const IP_FAILURE_LATENCY_PENALTY_MS: number = 2500;
const IP_SUCCESS_LATENCY_BONUS_MS: number = 120;
const IP_RETRY_DEMOTE_THRESHOLD: number = 1;
const IP_UNTESTED_LATENCY_MS: number = 2200;
const IP_QUALITY_SAVE_THROTTLE_MS: number = 30000;
const IP_SLOW_RESPONSE_THRESHOLD_MS: number = 4000;
const IP_SLOW_LATENCY_PENALTY_MS: number = 350;
const NETWORK_CHANGE_DEBOUNCE_MS: number = 350;
const NETWORK_RECOVERY_SETTLE_MS: number = 2000;
const NETWORK_RECOVERY_IDLE_RETRY_MS: number = 1000;
const NETWORK_ENVIRONMENT_FALLBACK_INTERVAL_MS: number = 5000;
const FRESH_CONNECTION_WINDOW_MS: number = 5000;
const FRONTING_INITIAL_CONCURRENCY: number = 3;
const FRONTING_HEALTHY_CONCURRENCY: number = 6;
const FRONTING_DEGRADED_CONCURRENCY: number = 2;
const FRONTING_ROUTE_INITIAL_CONCURRENCY: number = 2;
const FRONTING_ROUTE_HEALTHY_CONCURRENCY: number = 4;
const FRONTING_ROUTE_DEGRADED_CONCURRENCY: number = 1;
const FRONTING_HEALTHY_SUCCESS_THRESHOLD: number = 6;
const FRONTING_ROUTE_HEALTHY_SUCCESS_THRESHOLD: number = 3;
const FRONTING_RESTRICTED_MS: number = 45000;
const FRONTING_INITIAL_START_SPACING_MS: number = 48;
const FRONTING_HEALTHY_START_SPACING_MS: number = 12;
const PROBE_FOREGROUND_IDLE_POLL_MS: number = 100;
const FRONTING_PROBE_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
const BUILT_IN_RULES: HostRule[] = [
  { host: 'e-hentai.org', ips: ['172.66.132.196'] },
  { host: 'repo.e-hentai.org', ips: ['172.66.132.196'] },
  // 论坛（forums）被 Cloudflare 强制人机验证，任何内置 IP 直连都返回 403
  // 「Site verification required」。这里保留 IP 只为解析速度，登录本身需要可用代理。
  { host: 'forums.e-hentai.org', ips: ['172.66.132.196'] },
  { host: 'upld.e-hentai.org', ips: ['89.149.221.236', '95.211.208.236'] },
  // ehtracker.org：种子下载专用域，DNS 被污染后 TLS 直连失败（实测 TLS connection failed）；
  // 37.48.92.183 为官方解析值，直连 443 + 原 SNI 可用（PC 实测 200/1.3s）。
  { host: 'ehtracker.org', ips: ['37.48.92.183'] },
  // 185.132.132.76 为实测可用的解析值（无 SNI 与带 SNI 均握手通过）；
  // 旧表里的 109.236.85.28 / 62.112.8.21 / 89.39.106.43 已全部超时，会让封面缩略图整片空白。
  { host: 'ehgt.org', ips: ['185.132.132.76', '109.236.85.28', '62.112.8.21', '89.39.106.43', '2a00:7c80:0:123::3a85', '2a00:7c80:0:12d::38a1', '2a00:7c80:0:13b::37a4'] },
  // e-hentai.org 主站：实测可用的 Cloudflare 边缘地址（应用自身测速记录，延迟 12~16s）。
  // 不加这条时 POST 会走 DoH 解析，Yandex 偶发解析失败（2300006），评论发送必挂。
  { host: 'e-hentai.org', ips: ['172.66.132.196'] },
  // GitHub 的美国段（140.82.112.x）在国内容易连不通，检查更新会整个失败；
  // 20.205.243.16x 是当前可用的亚洲边缘地址，旧地址留作兜底。
  { host: 'github.com', ips: ['20.205.243.166', '140.82.112.4', '140.82.113.4', '140.82.114.4', '140.82.121.4'] },
  { host: 'api.github.com', ips: ['20.205.243.168', '140.82.112.6', '140.82.113.6', '140.82.114.6', '140.82.121.6'] },
  { host: 'raw.githubusercontent.com', ips: ['151.101.0.133', '151.101.64.133', '151.101.128.133', '151.101.192.133'] },
  { host: 'objects.githubusercontent.com', ips: ['185.199.108.133', '185.199.109.133', '185.199.110.133', '185.199.111.133'] },
  { host: 'github-releases.githubusercontent.com', ips: ['185.199.108.154', '185.199.109.154', '185.199.110.154', '185.199.111.154'] }
];
const BUILT_EX_RULES: HostRule[] = [
  { host: 'exhentai.org', ips: ['178.175.128.251', '178.175.128.252', '178.175.128.253', '178.175.128.254', '178.175.129.251', '178.175.129.252', '178.175.129.253', '178.175.129.254', '178.175.132.19', '178.175.132.20', '178.175.132.21', '178.175.132.22'] },
  { host: 'upld.exhentai.org', ips: ['178.175.132.22', '178.175.129.254', '178.175.128.254'] },
  { host: 's.exhentai.org', ips: ['178.175.129.253', '178.175.129.254', '178.175.128.253', '178.175.128.254', '178.175.132.21', '178.175.132.22'] }
];
let appliedHostRulesKey: string = '';
let pendingHostRules: Promise<void> | null = null;
// 自动前置档位：网络对 SNI 做精确阻断时，直连必然失败（CURLcode 28/35）。
// 首次 TLS/连接失败后自动切到域名前置并记住，用户不需要自己找开关。
const AUTO_FRONTING_SETTING_KEY: string = 'auto_fronting';
let autoFrontingActive: boolean = false;
let autoFrontingLoaded: boolean = false;
let frontingLogBudget: number = 3;
const HOST_IP_QUALITIES: HostIpQuality[] = [];
let frontingProbeKey: string = '';
let frontingProbeNetworkEnvironmentKey: string = '';
let frontingProbeGeneration: number = 0;
let frontingProbePending: Promise<void> | null = null;
let frontingIpCachePath: string = '';
let frontingIpCacheLoadedKey: string = '';
let frontingIpCacheLoadedSuccessfully: boolean = false;
let frontingCachedNetworkEnvironmentKey: string = '';
let directProbeKey: string = '';
let directProbeGeneration: number = 0;
let directProbePending: Promise<boolean> | null = null;
let directProbePassed: boolean = false;
let observedNetworkEnvironmentKey: string = '';
let cachedNetworkEnvironmentKey: string = '';
let lastNetworkEnvironmentCheckAt: number = 0;
let networkRuntimeContext: common.UIAbilityContext | undefined = undefined;
let networkRuntimeConnection: connection.NetConnection | undefined = undefined;
// 系统层 VPN（Clash 一类）启用时不能做域名前置：代理按 SNI 分流，
// 把 URL 换成 IP 会让 TLS 与证书对不上，表现为 TLS connection failed。
let vpnTunnelActive: boolean = false;
let vpnProbeAt: number = 0;
// VPN 隧道流量采样间隔：太频繁拖慢请求，太疏则 VPN/前置切换慢
const VPN_PROBE_INTERVAL_MS: number = 15000;
let networkRuntimeRegistered: boolean = false;
let networkChangeTimer: number = -1;
let networkRecoveryTimer: number = -1;
let forceFreshConnectionsUntilMs: number = 0;
let lastIpQualitySaveAt: number = 0;
let previousFrontedHost: string = '';
const DIRECT_HOST_FAILURES: DirectHostFailure[] = [];
const FRONTING_ROUTE_RUNTIMES: FrontingRouteRuntime[] = [];
const WAITING_FRONTING_ADMISSIONS: FrontingAdmissionWaiter[] = [];
let activeForegroundEhRequests: number = 0;
let activeFrontingRequests: number = 0;
let frontingHealthySuccesses: number = 0;
let frontingRestrictedUntil: number = 0;
let frontingAdmissionSequence: number = 0;
let frontingNextStartAt: number = 0;
let frontingDispatchTimer: number = -1;
let activeFrontingProbeRequests: number = 0;

interface HostRule {
  host: string;
  ips: string[];
}

interface HostIpQuality {
  host: string;
  ip: string;
  ok: boolean;
  latencyMs: number;
  testedAt: number;
  successCount?: number;
  failureCount?: number;
  lastResultAt?: number;
}

interface HostIpProbeTarget {
  host: string;
  ip: string;
}

interface DirectHostFailure {
  host: string;
  failureCount: number;
  blockedUntil: number;
}

interface FrontingRouteRuntime {
  key: string;
  active: number;
  successes: number;
  failures: number;
  restrictedUntil: number;
}

interface FrontingAdmissionWaiter {
  key: string;
  priority: number;
  sequence: number;
  resolve: (admission: EhRequestAdmission) => void;
}

export interface EhRequestAdmission {
  fronted: boolean;
  key: string;
  released: boolean;
}

interface FrontingIpQualityCache {
  version?: number;
  key?: string;
  updatedAt?: number;
  networkEnvironmentKey?: string;
  qualities?: HostIpQuality[];
}

export interface EhRequestPlan {
  url: string;
  host: string;
  fronted: boolean;
}

/**
 * Coordinates only EH foreground traffic which can enter the same native curl multi loop.
 * Direct requests are admitted immediately. SNI/fronted requests use a short slow-start window and
 * automatically recover their full throughput after successful responses.
 */
export function acquireEhRequestAdmission(plan: EhRequestPlan, priority: number = 50): Promise<EhRequestAdmission> {
  if (!plan.fronted) {
    activeForegroundEhRequests++;
    const admission: EhRequestAdmission = { fronted: false, key: '', released: false };
    return Promise.resolve(admission);
  }
  const key = frontingRouteKey(plan);
  frontingRouteRuntime(key);
  return new Promise<EhRequestAdmission>((resolve: (value: EhRequestAdmission | PromiseLike<EhRequestAdmission>) =>
    void) => {
    WAITING_FRONTING_ADMISSIONS.push({
      key: key,
      priority: priority,
      sequence: frontingAdmissionSequence++,
      resolve: resolve
    });
    dispatchFrontingAdmissions();
  });
}

export function releaseEhRequestAdmission(admission: EhRequestAdmission | null): void {
  if (admission === null || admission.released) {
    return;
  }
  admission.released = true;
  activeForegroundEhRequests = Math.max(0, activeForegroundEhRequests - 1);
  if (admission.fronted) {
    activeFrontingRequests = Math.max(0, activeFrontingRequests - 1);
    const runtime = findFrontingRouteRuntime(admission.key);
    if (runtime !== null) {
      runtime.active = Math.max(0, runtime.active - 1);
    }
    dispatchFrontingAdmissions();
  }
}

export async function acquireEhProbeAdmission(): Promise<void> {
  while (activeFrontingProbeRequests > 0 || hasForegroundEhRequestPressure() || hasActiveHttpRequests()) {
    await waitNetworkAdmission(PROBE_FOREGROUND_IDLE_POLL_MS);
  }
  activeFrontingProbeRequests++;
}

export function releaseEhProbeAdmission(): void {
  activeFrontingProbeRequests = Math.max(0, activeFrontingProbeRequests - 1);
}


// 5 秒缓存一次，避免每个请求都查一次连接能力。
export async function refreshVpnTunnelState(): Promise<boolean> {
  // getAllNets+BEARER_VPN 在部分 Clash 类 VPN 上检测不到（隧道 0 流量仍报 false），
  // 改读 /proc/net/dev 的 vpn-tun 流量：
  // 接口存在且字节数在两次采样间增长 → 隧道真正在转发 → 按 VPN 策略走域名；
  // 接口不存在或流量停滞（死隧道）→ 保持前置路径兜底，浏览不受 VPN 故障影响。
  const now = Date.now();
  if (now - vpnProbeAt < VPN_PROBE_INTERVAL_MS) {
    return vpnTunnelActive;
  }
  vpnProbeAt = now;
  const readVpnBytes = (): number => {
    try {
      const content = fs.readTextSync('/proc/net/dev');
      for (const line of content.split('\n')) {
        if (line.indexOf('vpn-tun') < 0) {
          continue;
        }
        const parts = line.trim().split(/\s+/);
        if (parts.length >= 10) {
          const rx = parseInt(parts[1], 10);
          const tx = parseInt(parts[9], 10);
          if (!Number.isNaN(rx) && !Number.isNaN(tx)) {
            return rx + tx;
          }
        }
      }
    } catch (_e) {
      return -1;
    }
    return -1;
  };
  const first = readVpnBytes();
  if (first < 0) {
    vpnTunnelActive = false;
    return vpnTunnelActive;
  }
  await new Promise<void>((resolve: (v: void) => void) => setTimeout(resolve, 1500));
  const second = readVpnBytes();
  if (second < 0) {
    vpnTunnelActive = false;
    return vpnTunnelActive;
  }
  const detected: boolean = second > first;
  if (detected !== vpnTunnelActive) {
    appLog.info(undefined, 'NetworkConfig', 'vpn tunnel bytes ' + first.toString() + '->' +
      second.toString() + ' active=' + detected.toString());
  }
  vpnTunnelActive = detected;
  return vpnTunnelActive;
}

export function isVpnTunnelActive(): boolean {
  return vpnTunnelActive;
}

export function createEhRequestPlan(url: string): EhRequestPlan {
  // 异步刷新 VPN 状态，命中缓存时不产生额外开销。
  refreshVpnTunnelState().catch(() => {});
  const host = requestHost(url);
  const hostHeader = requestHostHeader(url);
  // 不再因为 vpnTunnelActive 就放弃 hosts：实测 VPN 隧道经常是「接口在、流量全丢」
  // （vpn-tun 收发 0 字节、dropped 持续增长），此时按域名请求会撞上被污染的 DNS。
  // 一律走 hosts IP + Host 头，这是当前网络下唯一稳定可用的路径。
  if (!isEhNetworkProcessingEnabled()) {
    return {
      url: url,
      host: hostHeader,
      fronted: false
    };
  }
  // 系统 VPN 生效时一律按域名请求：前置会把 URL 改写成 IP，代理按域名分流立即失效
  // （hosts 规则此时也已被 ensureEhHostRules 移除，解析与分流交给 VPN/代理）。
  // VPN 隧道若「接口在、流量全丢」，按域名请求会与用户直连一样失败——这是 VPN 自身的问题，
  // 此时改走前置只会更糟（流量同样进隧道）。保证 VPN 开启时仍可正常访问。
  if (vpnTunnelActive) {
    return {
      url: url,
      host: hostHeader,
      fronted: false
    };
  }
  let networkChanged = false;
  if (isEhDirectConnectionProbeEnabled() || isEhFrontingBenchmarkEnabled()) {
    networkChanged = refreshNetworkEnvironment();
  }
  ensureFrontingQualityCacheLoaded();
  if (networkChanged) {
    refreshNetworkRuntimeAfterChange();
  }
  if (shouldUseDirectConnection(host)) {
    return {
      url: url,
      host: hostHeader,
      fronted: false
    };
  }
  const exFrontingIp = exFrontingIpForUrl(url, host);
  if (exFrontingIp.length > 0) {
    return {
      url: replaceUrlHost(url, exFrontingIp),
      host: hostHeader,
      fronted: true
    };
  }
  const eFrontingIp = eFrontingIpForUrl(url, host);
  if (eFrontingIp.length === 0) {
    return {
      url: url,
      host: hostHeader,
      fronted: false
    };
  }
  return {
    url: replaceUrlHost(url, eFrontingIp),
    host: hostHeader,
    fronted: true
  };
}

// 前置只对 supportsDomainFrontingHost 白名单（ehgt.org / e-hentai.org / exhentai.org）生效，
// GitHub 的检查更新与标签库更新不在此列，不受影响。
export function isDomainFrontingActive(): boolean {
  return appSettingsStore.getValue('domain_fronting', 'Off') === 'On' || autoFrontingEnabled();
}

function autoFrontingEnabled(): boolean {
  if (!autoFrontingLoaded) {
    autoFrontingLoaded = true;
    autoFrontingActive = appSettingsStore.getValue(AUTO_FRONTING_SETTING_KEY, 'Off') === 'On';
  }
  return autoFrontingActive;
}

// 直连被 TLS/连接错误拒绝时调用：切到域名前置并持久化，调用方重试时即按前置发出。
export function escalateToDomainFronting(): boolean {
  if (isDomainFrontingActive()) {
    return false;
  }
  autoFrontingActive = true;
  autoFrontingLoaded = true;
  appSettingsStore.setValue(AUTO_FRONTING_SETTING_KEY, 'On');
  persistAutoFronting();
  appLog.info(undefined, 'NetworkConfig', 'auto fronting escalated');
  markFreshEhConnectionsRequired();
  return true;
}

function resetAutoFronting(): void {
  autoFrontingActive = false;
  autoFrontingLoaded = true;
  appSettingsStore.setValue(AUTO_FRONTING_SETTING_KEY, 'Off');
  persistAutoFronting();
}

function persistAutoFronting(): void {
  const context = networkRuntimeContext;
  if (context === undefined) {
    return;
  }
  appSettingsStore.save(context).catch(() => {
  });
}

function hasConfiguredProxy(): boolean {
  const type = appSettingsStore.getValue('proxy', 'System');
  if (type !== 'SOCKS' && type !== 'HTTP') {
    return false;
  }
  const host = appSettingsStore.getValue('proxy_host', '').trim();
  const port = parseProxyPort(appSettingsStore.getValue('proxy_port', ''));
  return host.length > 0 && isValidPort(port);
}

function isEhNetworkProcessingEnabled(): boolean {
  // 配了应用内代理时不再做 hosts 覆盖与前置：请求被改写成 IP 后代理拿不到原始域名，
  // SNI 与分流都会失败，表现就是「配了代理主页反而打不开」。
  if (hasConfiguredProxy()) {
    return false;
  }
  return appSettingsStore.getValue('built_in_hosts', 'Off') === 'On' ||
    appSettingsStore.getValue('built_ex_hosts', 'Off') === 'On' ||
    appSettingsStore.getValue('dns_over_https', 'Off') === 'On' ||
    isDomainFrontingActive() ||
    appSettingsStore.getValue('auto_direct_connection', 'Off') === 'On';
}

function ensureFrontingQualityCacheLoaded(): void {
  const key = frontingBenchmarkKey();
  if (key === 'Off') {
    return;
  }
  loadCachedIpQualities(key);
}

export function applyEhNetworkOptions(options: http.HttpRequestOptions, plan: EhRequestPlan,
  useDnsOverHttps: boolean = true): void {
  options.usingCache = false;
  // DoH 只为绕开 e-hentai / ehgt 的 DNS 污染而设。把它套到 GitHub 上，Yandex 解析不到
  // 就会直接失败（实测 2300006 Failed to resolve the host name），检查更新与标签库更新全挂。
  // 外部域名一律交回系统 DNS；走系统 VPN 时同样关掉 DoH，避免绕过代理 DNS。
  // VPN 下也要用 DoH：实测 Clash 开着时系统 DNS 仍把 e-hentai.org 解析到 31.13.87.9（污染），
  // 关掉 DoH 就等于放弃解析。DoH 请求本身走 VPN 隧道，能拿到干净的 172.66.x.x。
  // 前置请求的 URL 已经被改写成 IP，没有域名需要解析；此时再走 DoH 等于让 DoH 去解析一个 IP 字面量，
  // 实测会卡住到读超时（CURLcode 28），而同一请求直连 IP 是 200。所以前置时一律关闭 DoH。
  const dnsOverHttpsAllowed = useDnsOverHttps && isEhDomainHost(plan.host) && !plan.fronted;
  // 不指定 usingProtocol，由系统按目标站点能力自动协商协议并在需要时回退。
  applyConfiguredNetworkOptions(options, dnsOverHttpsAllowed);
  if (plan.fronted) {
    options.remoteValidation = 'skip';
    if (deviceInfo.apiAvailable('26.0.0')) {
      const currentHost = requestHost(plan.url);
      if (currentHost !== previousFrontedHost || shouldUseFreshFrontingConnection(plan)) {
        options.reuseConnections = false;
        previousFrontedHost = currentHost;
      }
    }
  } else if (Date.now() < forceFreshConnectionsUntilMs) {
    if (deviceInfo.apiAvailable('26.0.0')) {
      options.reuseConnections = false;
    }
  }
}

function isEhDomainHost(host: string): boolean {
  const h = host.toLowerCase();
  return h === 'e-hentai.org' || h.endsWith('.e-hentai.org') ||
    h === 'exhentai.org' || h.endsWith('.exhentai.org') ||
    h === 'ehgt.org' || h.endsWith('.ehgt.org') ||
    h === 'ehtracker.org' || h.endsWith('.ehtracker.org');
}

export function applyConfiguredNetworkOptions(options: http.HttpRequestOptions, useDnsOverHttps: boolean = true): void {
  applyConfiguredProxyOptions(options);
  if (useDnsOverHttps) {
    const dohUrl = currentDnsOverHttpsUrl();
    if (dohUrl.length > 0) {
      options.dnsOverHttps = dohUrl;
    }
  }
}

export function applyConfiguredProxyOptions(options: http.HttpRequestOptions): void {
  if (appSettingsStore.getValue('proxy', 'System') === 'SOCKS') {
    if (deviceInfo.apiAvailable('26.0.0')) {
      const host = appSettingsStore.getValue('proxy_host', '').trim();
      const port = parseProxyPort(appSettingsStore.getValue('proxy_port', ''));
      if (host.length > 0 && isValidPort(port)) {
        const socks5Proxy: http.Socks5Proxy = {
          host: host,
          port: port,
          dnsStrategy: appSettingsStore.getValue('proxy_socks_dns', 'Proxy') === 'System' ?
            connection.Socks5DnsStrategy.SYSTEM_MODE : connection.Socks5DnsStrategy.PROXY_MODE,
          exclusionList: parseProxyExclusionList(appSettingsStore.getValue('proxy_exclusion_list', ''))
        };
        const username = appSettingsStore.getValue('proxy_username', '').trim();
        if (username.length > 0) {
          socks5Proxy.username = username;
          socks5Proxy.password = appSettingsStore.getValue('proxy_password', '');
        }
        options.usingSocks5Proxy = socks5Proxy;
        return;
      }
    }
  }
  options.usingProxy = proxyOption();
}

/**
 * Connections can be left in an unusable state while an ability is suspended in background.
 * Do not destroy active requests during the lifecycle callback; make requests started shortly
 * after a real foreground resume use fresh connections instead. Keep this window short so normal
 * requests quickly return to HTTP/1.1 connection reuse after stale background connections are bypassed.
 */
export function refreshEhConnectionsAfterForeground(): void {
  forceFreshConnectionsUntilMs = Math.max(forceFreshConnectionsUntilMs,
    Date.now() + FRESH_CONNECTION_WINDOW_MS);
}

export function socks5ProxySupported(): boolean {
  return deviceInfo.apiAvailable('26.0.0');
}

export function startEhDirectConnectionProbe(context?: common.UIAbilityContext): Promise<boolean> {
  if (context !== undefined) {
    networkRuntimeContext = context;
    frontingIpCachePath = context.filesDir + '/' + FRONTING_IP_CACHE_FILE_NAME;
  }
  const key = directProbeKeyValue();
  if (key === 'Off') {
    directProbeGeneration++;
    directProbeKey = key;
    directProbePending = null;
    directProbePassed = false;
    clearDirectHostFailures();
    return Promise.resolve(false);
  }
  refreshNetworkEnvironment();
  if (directProbePending !== null && directProbeKey === key) {
    return directProbePending;
  }
  directProbeKey = key;
  directProbePassed = false;
  directProbeGeneration++;
  const generation = directProbeGeneration;
  const existingHostRuleTask = pendingHostRules;
  directProbePending = (existingHostRuleTask === null ? Promise.resolve() : existingHostRuleTask).then(() => {
    markFreshEhConnectionsRequired();
    return removeKnownHostRules();
  }).then(() => {
    return probeDirectSelectedSite();
  }).then(async (passed: boolean): Promise<boolean> => {
    if (generation === directProbeGeneration && directProbeKey === key) {
      directProbePassed = passed;
      if (passed) {
        clearDirectHostFailures();
        cancelFrontingBenchmark();
        appliedHostRulesKey = 'Direct';
      } else {
        await restoreConfiguredHostRules();
      }
      directProbePending = null;
    }
    return passed;
  }).catch(async (): Promise<boolean> => {
    if (generation === directProbeGeneration && directProbeKey === key) {
      directProbePassed = false;
      await restoreConfiguredHostRules();
      directProbePending = null;
    }
    return false;
  });
  return directProbePending;
}

export function isEhDirectConnectionProbeEnabled(): boolean {
  return appSettingsStore.getValue('auto_direct_connection', 'Off') === 'On';
}

export function isEhFrontingBenchmarkEnabled(): boolean {
  return frontingBenchmarkKey() !== 'Off';
}

export function recordEhRequestOutcome(plan: EhRequestPlan, ok: boolean, elapsedMs: number): void {
  if (!plan.fronted) {
    recordDirectRequestOutcome(plan, ok);
    return;
  }
  recordFrontingAdmissionOutcome(plan, ok);
  const ip = requestHost(plan.url);
  if (!isIpv4(ip)) {
    return;
  }
  const host = plan.host.split(':')[0].toLowerCase();
  if (host.length === 0 || !isKnownProbeTarget(host, ip)) {
    return;
  }
  const current = qualityForHostIp(host, ip);
  applyIpQualityMeasurement(current, ok, elapsedMs, Date.now());
  if (ok) {
    saveCachedIpQualitiesThrottled(frontingBenchmarkKey());
  } else {
    saveCachedIpQualities(frontingBenchmarkKey());
  }
}

function recordFrontingAdmissionOutcome(plan: EhRequestPlan, ok: boolean): void {
  const runtime = frontingRouteRuntime(frontingRouteKey(plan));
  const now = Date.now();
  if (ok) {
    runtime.successes++;
    runtime.failures = Math.max(0, runtime.failures - 1);
    frontingHealthySuccesses++;
  } else {
    runtime.successes = 0;
    runtime.failures++;
    runtime.restrictedUntil = Math.max(runtime.restrictedUntil, now + FRONTING_RESTRICTED_MS);
    frontingHealthySuccesses = 0;
    frontingRestrictedUntil = Math.max(frontingRestrictedUntil, now + FRONTING_RESTRICTED_MS);
  }
  dispatchFrontingAdmissions();
}

export function isEhRouteReachableStatus(statusCode: number): boolean {
  if (statusCode >= 200 && statusCode < 400) {
    return true;
  }
  // These responses are returned by the intended EH servers and still prove that the route is reachable.
  // Do not include generic 400/421 responses because they commonly indicate a wrong fronting endpoint.
  return statusCode === 401 || statusCode === 403 || statusCode === 404 || statusCode === 429 ||
    statusCode === 509;
}

function applyIpQualityMeasurement(current: HostIpQuality, ok: boolean, elapsedMs: number,
  now: number): void {
  const successCount = current.successCount === undefined ? 0 : current.successCount;
  const failureCount = current.failureCount === undefined ? 0 : current.failureCount;
  if (ok) {
    current.ok = true;
    current.successCount = successCount + 1;
    current.failureCount = Math.max(0, failureCount - 1);
    const measured = Math.max(1, elapsedMs);
    current.latencyMs = Math.max(1, Math.round((current.latencyMs * 2 + measured) / 3) -
      Math.min(IP_SUCCESS_LATENCY_BONUS_MS, current.successCount * 20));
    if (measured >= IP_SLOW_RESPONSE_THRESHOLD_MS) {
      current.latencyMs += Math.min(IP_SLOW_LATENCY_PENALTY_MS * 3,
        IP_SLOW_LATENCY_PENALTY_MS + Math.round((measured - IP_SLOW_RESPONSE_THRESHOLD_MS) / 20));
    }
  } else {
    current.failureCount = failureCount + 1;
    current.latencyMs = Math.max(current.latencyMs, Math.max(1, elapsedMs)) +
      IP_FAILURE_LATENCY_PENALTY_MS * Math.min(4, current.failureCount);
    current.ok = current.failureCount < IP_RETRY_DEMOTE_THRESHOLD ||
      (current.successCount !== undefined && current.successCount > current.failureCount);
  }
  current.testedAt = now;
  current.lastResultAt = now;
}

export function startEhFrontingBenchmark(context?: common.UIAbilityContext, forceRefresh: boolean = false): void {
  if (context !== undefined) {
    networkRuntimeContext = context;
    frontingIpCachePath = context.filesDir + '/' + FRONTING_IP_CACHE_FILE_NAME;
  }
  const key = frontingBenchmarkKey();
  if (key === 'Off') {
    cancelFrontingBenchmark();
    return;
  }
  const hasCachedBenchmark = loadCachedIpQualities(key);
  const currentEnvironmentKey = currentNetworkEnvironmentKey();
  if (observedNetworkEnvironmentKey.length === 0 && currentEnvironmentKey.length > 0) {
    observedNetworkEnvironmentKey = currentEnvironmentKey;
  }
  const cachedNetworkChanged = hasCachedBenchmark && currentEnvironmentKey.length > 0 &&
    frontingCachedNetworkEnvironmentKey !== currentEnvironmentKey;
  const preserveScores = forceRefresh || cachedNetworkChanged;
  if (key === frontingProbeKey && frontingProbePending !== null &&
    frontingProbeNetworkEnvironmentKey === currentEnvironmentKey) {
    return;
  }
  if (!preserveScores && (hasCachedBenchmark || hasUsableIpQualities())) {
    return;
  }
  frontingProbeKey = key;
  frontingProbeNetworkEnvironmentKey = currentEnvironmentKey;
  frontingProbeGeneration++;
  const generation = frontingProbeGeneration;
  frontingProbePending = runEhFrontingBenchmark(generation).then((results: HostIpQuality[]) => {
    if (generation === frontingProbeGeneration) {
      if (preserveScores) {
        mergeIpQualityMeasurements(results);
      } else {
        replaceIpQualities(results);
      }
      saveCachedIpQualities(key, true);
      frontingProbePending = null;
    }
  }).catch(() => {
    if (generation === frontingProbeGeneration) {
      frontingProbePending = null;
    }
  });
}

function cancelFrontingBenchmark(): void {
  frontingProbeGeneration++;
  frontingProbePending = null;
  frontingProbeKey = 'Off';
  frontingProbeNetworkEnvironmentKey = '';
}

export async function ensureEhHostRules(): Promise<void> {
  // 系统 VPN 生效时不要写 hosts：内置 IP 表会把域名钉到 Cloudflare 地址，
  // 代理按域名分流会立刻失败（实测 27ms TLS 报错）。交给代理解析即可。
  if (vpnTunnelActive) {
    if (appliedHostRulesKey !== 'Vpn') {
      await waitHostRuleTask(removeKnownHostRules(), 1200);
      appliedHostRulesKey = 'Vpn';
    }
    return;
  }
  if (directProbePending !== null && isEhDirectConnectionProbeEnabled()) {
    await directProbePending;
  }
  if (directProbePassed && appSettingsStore.getValue('auto_direct_connection', 'Off') === 'On') {
    const key = 'Direct';
    if (appliedHostRulesKey !== key) {
      if (appliedHostRulesKey.length > 0) {
        await waitHostRuleTask(removeKnownHostRules(), 1200);
      }
      appliedHostRulesKey = key;
    }
    return;
  }
  const key = appSettingsStore.getValue('built_in_hosts', 'Off') + ':' +
    appSettingsStore.getValue('built_ex_hosts', 'Off');
  if (key === 'Off:Off') {
    if (appliedHostRulesKey !== key) {
      await waitHostRuleTask(removeKnownHostRules(), 1200);
    }
    appliedHostRulesKey = key;
    return;
  }
  if (key === appliedHostRulesKey) {
    return;
  }
  if (pendingHostRules !== null) {
    await pendingHostRules;
    return;
  }

  pendingHostRules = applyHostRules(key);
  try {
    await pendingHostRules;
  } finally {
    pendingHostRules = null;
  }
}

function proxyOption(): boolean | http.HttpProxy {
  const proxyType = appSettingsStore.getValue('proxy', 'System');
  if (proxyType === 'Off') {
    return false;
  }
  if (proxyType === 'HTTP') {
    const host = appSettingsStore.getValue('proxy_host', '').trim();
    const port = parseProxyPort(appSettingsStore.getValue('proxy_port', ''));
    if (host.length > 0 && isValidPort(port)) {
      const proxy: http.HttpProxy = {
        host: host,
        port: port,
        exclusionList: parseProxyExclusionList(appSettingsStore.getValue('proxy_exclusion_list', ''))
      };
      const username = appSettingsStore.getValue('proxy_username', '').trim();
      const password = appSettingsStore.getValue('proxy_password', '');
      if (username.length > 0) {
        proxy.username = username;
        proxy.password = password;
      }
      return proxy;
    }
  }
  return true;
}

function eFrontingIpForUrl(url: string, host: string): string {
  if (shouldUseDirectConnection(host) || !isDomainFrontingActive() ||
    !isHttpsUrl(url) || host.length === 0 || !supportsDomainFrontingHost(host)) {
    return '';
  }
  const normalizedHost = host.toLowerCase();
  const ip = rotatingIpv4ForHost(normalizedHost, BUILT_IN_RULES);
  if (ip.length > 0) {
    if (frontingLogBudget > 0) {
      frontingLogBudget--;
      appLog.info(undefined, 'NetworkConfig', 'fronting ' + normalizedHost + ' -> ' + ip);
    }
    return ip;
  }
  return '';
}

function exFrontingIpForUrl(url: string, host: string): string {
  if (shouldUseDirectConnection(host) || !isDomainFrontingActive() ||
    !isHttpsUrl(url) || host.length === 0 || !supportsDomainFrontingHost(host)) {
    return '';
  }
  const normalizedHost = host.toLowerCase();
  const ip = rotatingIpv4ForHost(normalizedHost, BUILT_EX_RULES);
  if (ip.length > 0) {
    if (frontingLogBudget > 0) {
      frontingLogBudget--;
      appLog.info(undefined, 'NetworkConfig', 'fronting ' + normalizedHost + ' -> ' + ip);
    }
    return ip;
  }
  return '';
}

function rotatingIpv4ForHost(host: string, rules: HostRule[]): string {
  const ip = weightedIpv4ForHost(host, rules);
  if (ip.length > 0) {
    return ip;
  }
  const fallbackIps = ipv4ListForHost(host, rules);
  if (fallbackIps.length === 0) {
    return '';
  }
  return fallbackIps[Math.floor(Math.random() * fallbackIps.length)];
}

function ipv4ListForHost(host: string, rules: HostRule[]): string[] {
  const normalized = host.toLowerCase();
  const collect = (rule: HostRule): string[] => {
    const ips: string[] = [];
    for (let j = 0; j < rule.ips.length; j++) {
      if (isIpv4(rule.ips[j])) {
        ips.push(rule.ips[j]);
      }
    }
    return ips;
  };
  for (let i = 0; i < rules.length; i++) {
    if (rules[i].host === normalized) {
      return collect(rules[i]);
    }
  }
  // 子域继承父域 IP：图片走 xxx.ehgt.org 这类子域，原来精确匹配匹配不到 ehgt.org，
  // 结果图片只能走被污染的 DNS，图片全下不下来（下载 0/x、阅读器白图）。
  for (let i = 0; i < rules.length; i++) {
    const ruleHost = rules[i].host;
    if (ruleHost.length > 0 && normalized.endsWith('.' + ruleHost)) {
      const ips = collect(rules[i]);
      if (ips.length > 0) {
        return ips;
      }
    }
  }
  return [];
}

function weightedIpv4ForHost(host: string, rules: HostRule[]): string {
  const candidates = ipv4ListForHost(host, rules);
  if (candidates.length === 0) {
    return '';
  }

  const results: HostIpQuality[] = [];
  for (let i = 0; i < candidates.length; i++) {
    results.push(qualityForHostIp(host, candidates[i]));
  }
  if (results.length === 0) {
    return '';
  }

  results.sort((left: HostIpQuality, right: HostIpQuality) => {
    const leftScore = ipQualityScore(left);
    const rightScore = ipQualityScore(right);
    if (leftScore !== rightScore) {
      return leftScore - rightScore;
    }
    return left.ip.localeCompare(right.ip);
  });
  const preferredLimit = Math.min(FRONTING_PREFERRED_IP_LIMIT, results.length);
  if (results.length > preferredLimit && Math.random() < FRONTING_TAIL_SAMPLE_RATE) {
    return weightedRandomIp(results, preferredLimit, results.length);
  }
  return weightedRandomIp(results, 0, preferredLimit);
}

function weightedRandomIp(results: HostIpQuality[], start: number, end: number): string {
  if (start >= end) {
    return '';
  }
  const bestScore = ipQualityScore(results[0]);
  let totalWeight = 0;
  const weights: number[] = [];
  for (let i = start; i < end; i++) {
    const scoreDistance = Math.max(0, ipQualityScore(results[i]) - bestScore);
    const healthWeight = results[i].ok ? 1 : 0.15;
    const weight = healthWeight / (FRONTING_WEIGHT_SCORE_BASE + scoreDistance);
    weights.push(weight);
    totalWeight += weight;
  }
  if (totalWeight <= 0) {
    return results[start].ip;
  }
  let cursor = Math.random() * totalWeight;
  for (let i = 0; i < weights.length; i++) {
    cursor -= weights[i];
    if (cursor <= 0) {
      return results[start + i].ip;
    }
  }
  return results[end - 1].ip;
}

async function runEhFrontingBenchmark(generation: number): Promise<HostIpQuality[]> {
  const targets = collectFrontingProbeTargets();
  if (targets.length === 0) {
    return [];
  }
  let nextIndex = 0;
  const results: HostIpQuality[] = [];
  const workers: Promise<void>[] = [];
  const workerCount = Math.min(FRONTING_PROBE_CONCURRENCY, targets.length);
  for (let i = 0; i < workerCount; i++) {
    workers.push(new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
      runFrontingProbeWorker(targets, generation, () => {
        const index = nextIndex;
        nextIndex++;
        return index;
      }, results).then(() => {
        resolve();
      }).catch(() => {
        resolve();
      });
    }));
  }
  await Promise.all(workers);
  return results;
}

async function runFrontingProbeWorker(targets: HostIpProbeTarget[], generation: number,
  next: () => number, results: HostIpQuality[]): Promise<void> {
  while (generation === frontingProbeGeneration) {
    const index = next();
    if (index >= targets.length) {
      return;
    }
    const result = await probeFrontingIp(targets[index]);
    if (generation === frontingProbeGeneration) {
      results.push(result);
    }
  }
}

export function registerEhNetworkChangeListener(context: common.UIAbilityContext): void {
  networkRuntimeContext = context;
  cachedNetworkEnvironmentKey = readCurrentNetworkEnvironmentKey();
  lastNetworkEnvironmentCheckAt = Date.now();
  if (observedNetworkEnvironmentKey.length === 0) {
    observedNetworkEnvironmentKey = cachedNetworkEnvironmentKey;
  }
  if (networkRuntimeConnection !== undefined) {
    return;
  }
  const netConnection = connection.createNetConnection();
  networkRuntimeConnection = netConnection;
  netConnection.on('netAvailable', (_netHandle: connection.NetHandle) => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netLost', (_netHandle: connection.NetHandle) => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netUnavailable', () => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netCapabilitiesChange', (_info: connection.NetCapabilityInfo) => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netConnectionPropertiesChange', (_info: connection.NetConnectionPropertyInfo) => {
    scheduleNetworkRuntimeRefresh();
  });
  networkRuntimeRegistered = true;
  try {
    netConnection.register((error: BusinessError) => {
      if (error !== undefined && error.code !== 0) {
        networkRuntimeRegistered = false;
        networkRuntimeConnection = undefined;
        appLog.warn(context, 'NetworkConfig',
          'Register network listener failed: ' + error.code.toString() + ' ' + error.message);
      }
    });
  } catch (error) {
    networkRuntimeRegistered = false;
    networkRuntimeConnection = undefined;
    appLog.warn(context, 'NetworkConfig', 'Register network listener failed');
  }
}

export function unregisterEhNetworkChangeListener(): void {
  if (networkChangeTimer >= 0) {
    clearTimeout(networkChangeTimer);
    networkChangeTimer = -1;
  }
  if (networkRecoveryTimer >= 0) {
    clearTimeout(networkRecoveryTimer);
    networkRecoveryTimer = -1;
  }
  const netConnection = networkRuntimeConnection;
  networkRuntimeConnection = undefined;
  networkRuntimeRegistered = false;
  networkRuntimeContext = undefined;
  if (netConnection === undefined) {
    return;
  }
  try {
    netConnection.unregister((_error: BusinessError) => {
    });
  } catch (error) {
  }
}

async function probeFrontingIp(target: HostIpProbeTarget): Promise<HostIpQuality> {
  await acquireEhProbeAdmission();
  const request = acquireHttpRequest();
  markHttpRequestVolatile(request);
  const startedAt = Date.now();
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.HEAD,
      header: {
        'Host': target.host,
        'User-Agent': FRONTING_PROBE_USER_AGENT,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache'
      },
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      remoteValidation: 'skip',
      maxRedirects: 0,
      connectTimeout: FRONTING_PROBE_CONNECT_TIMEOUT_MS,
      readTimeout: FRONTING_PROBE_READ_TIMEOUT_MS
    };
    if (deviceInfo.apiAvailable('26.0.0')) {
      options.reuseConnections = false;
    }
    applyConfiguredNetworkOptions(options);
    const response = await requestProbeToCompletion(request, 'https://' + target.ip + '/', options);
    const statusCode = Number(response.responseCode);
    const ok = isEhRouteReachableStatus(statusCode);
    return {
      host: target.host,
      ip: target.ip,
      ok: ok,
      latencyMs: ok ? Math.max(1, Date.now() - startedAt) : FRONTING_PROBE_DEADLINE_MS,
      testedAt: Date.now()
    };
  } catch (error) {
    return {
      host: target.host,
      ip: target.ip,
      ok: false,
      latencyMs: FRONTING_PROBE_DEADLINE_MS,
      testedAt: Date.now()
    };
  } finally {
    retireHttpRequest(request);
    releaseEhProbeAdmission();
  }
}

async function requestProbeToCompletion(request: http.HttpRequest, url: string,
  options: http.HttpRequestOptions): Promise<http.HttpResponse> {
  try {
    return await request.request(url, options);
  } catch (error) {
    throw new Error(String(error));
  }
}

function collectFrontingProbeTargets(): HostIpProbeTarget[] {
  const targets: HostIpProbeTarget[] = [];
  if (!isDomainFrontingActive()) {
    return targets;
  }
  if (selectedGalleryHost() === 'e-hentai.org') {
    pushProbeTargets(targets, BUILT_IN_RULES);
  } else {
    pushProbeTargets(targets, BUILT_EX_RULES);
  }
  return targets;
}

function pushProbeTargets(targets: HostIpProbeTarget[], rules: HostRule[]): void {
  for (let i = 0; i < rules.length; i++) {
    if (!supportsDomainFrontingHost(rules[i].host)) {
      continue;
    }
    const ips = ipv4ListForHost(rules[i].host, rules);
    for (let j = 0; j < ips.length; j++) {
      if (!containsProbeTarget(targets, rules[i].host, ips[j])) {
        targets.push({ host: rules[i].host, ip: ips[j] });
      }
    }
  }
}

function containsProbeTarget(targets: HostIpProbeTarget[], host: string, ip: string): boolean {
  for (let i = 0; i < targets.length; i++) {
    if (targets[i].host === host && targets[i].ip === ip) {
      return true;
    }
  }
  return false;
}

function recordIpQuality(result: HostIpQuality): void {
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    if (HOST_IP_QUALITIES[i].host === result.host && HOST_IP_QUALITIES[i].ip === result.ip) {
      HOST_IP_QUALITIES[i] = result;
      return;
    }
  }
  HOST_IP_QUALITIES.push(result);
}

function qualityForHostIp(host: string, ip: string): HostIpQuality {
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    if (HOST_IP_QUALITIES[i].host === host && HOST_IP_QUALITIES[i].ip === ip) {
      return HOST_IP_QUALITIES[i];
    }
  }
  const quality: HostIpQuality = {
    host: host,
    ip: ip,
    ok: true,
    latencyMs: IP_UNTESTED_LATENCY_MS,
    testedAt: Date.now(),
    successCount: 0,
    failureCount: 0,
    lastResultAt: 0
  };
  HOST_IP_QUALITIES.push(quality);
  return quality;
}

function hasUsableIpQualities(): boolean {
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    if (HOST_IP_QUALITIES[i].ok && isKnownProbeTarget(HOST_IP_QUALITIES[i].host, HOST_IP_QUALITIES[i].ip)) {
      return true;
    }
  }
  return false;
}

function ipQualityScore(item: HostIpQuality): number {
  const successCount = item.successCount === undefined ? 0 : item.successCount;
  const failureCount = item.failureCount === undefined ? 0 : item.failureCount;
  const testedPenalty = item.lastResultAt === undefined || item.lastResultAt <= 0 ? 700 : 0;
  const okPenalty = item.ok ? 0 : IP_FAILURE_LATENCY_PENALTY_MS;
  return item.latencyMs + testedPenalty + okPenalty + failureCount * IP_FAILURE_LATENCY_PENALTY_MS -
    Math.min(1200, successCount * IP_SUCCESS_LATENCY_BONUS_MS);
}

function replaceIpQualities(results: HostIpQuality[]): boolean {
  const validResults: HostIpQuality[] = [];
  for (let i = 0; i < results.length; i++) {
    if (isKnownProbeTarget(results[i].host, results[i].ip)) {
      validResults.push(results[i]);
    }
  }
  if (validResults.length === 0) {
    return false;
  }
  clearIpQualities();
  for (let i = 0; i < validResults.length; i++) {
    recordIpQuality(validResults[i]);
  }
  return true;
}

function mergeIpQualityMeasurements(results: HostIpQuality[]): boolean {
  let merged = false;
  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    if (!isKnownProbeTarget(result.host, result.ip)) {
      continue;
    }
    const current = qualityForHostIp(result.host, result.ip);
    applyIpQualityMeasurement(current, result.ok, result.latencyMs, result.testedAt);
    merged = true;
  }
  return merged;
}

function clearIpQualities(): void {
  HOST_IP_QUALITIES.splice(0, HOST_IP_QUALITIES.length);
}

function loadCachedIpQualities(key: string): boolean {
  if (frontingIpCacheLoadedKey === key) {
    return frontingIpCacheLoadedSuccessfully;
  }
  clearIpQualities();
  frontingIpCacheLoadedKey = key;
  frontingIpCacheLoadedSuccessfully = false;
  frontingCachedNetworkEnvironmentKey = '';
  if (frontingIpCachePath.length === 0) {
    return false;
  }
  try {
    const parsed = JSON.parse(fs.readTextSync(frontingIpCachePath)) as FrontingIpQualityCache;
    if (!frontingCacheKeyMatches(parsed.key, key) || !Array.isArray(parsed.qualities)) {
      return false;
    }
    let loadedCount = 0;
    for (let i = 0; i < parsed.qualities.length; i++) {
      const item = parsed.qualities[i];
      if (isValidIpQuality(item)) {
        recordIpQuality({
          host: item.host,
          ip: item.ip,
          ok: item.ok,
          latencyMs: item.latencyMs,
          testedAt: item.testedAt,
          successCount: typeof item.successCount === 'number' ? item.successCount : 0,
          failureCount: typeof item.failureCount === 'number' ? item.failureCount : 0,
          lastResultAt: typeof item.lastResultAt === 'number' ? item.lastResultAt : item.testedAt
        });
        loadedCount++;
      }
    }
    frontingIpCacheLoadedSuccessfully = loadedCount > 0;
    frontingCachedNetworkEnvironmentKey = typeof parsed.networkEnvironmentKey === 'string' ?
      parsed.networkEnvironmentKey : '';
    return frontingIpCacheLoadedSuccessfully;
  } catch (error) {
    return false;
  }
}

function saveCachedIpQualities(key: string, benchmarkCompleted: boolean = false): void {
  if (frontingIpCachePath.length === 0) {
    return;
  }
  ensureKnownIpQualities();
  const qualities: HostIpQuality[] = [];
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    const item = HOST_IP_QUALITIES[i];
    if (isKnownProbeTarget(item.host, item.ip)) {
      qualities.push(item);
    }
  }
  let fd = -1;
  try {
    const file = fs.openSync(frontingIpCachePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    const networkEnvironmentKey = currentNetworkEnvironmentKey();
    if (benchmarkCompleted && networkEnvironmentKey.length > 0) {
      frontingCachedNetworkEnvironmentKey = networkEnvironmentKey;
    }
    const payload: FrontingIpQualityCache = {
      version: FRONTING_IP_CACHE_VERSION,
      key: key,
      updatedAt: Date.now(),
      networkEnvironmentKey: frontingCachedNetworkEnvironmentKey,
      qualities: qualities
    };
    fs.writeSync(fd, JSON.stringify(payload));
    frontingIpCacheLoadedKey = key;
    frontingIpCacheLoadedSuccessfully = qualities.length > 0;
  } catch (error) {
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function ensureKnownIpQualities(): void {
  const targets = collectFrontingProbeTargets();
  for (let i = 0; i < targets.length; i++) {
    qualityForHostIp(targets[i].host, targets[i].ip);
  }
}

function saveCachedIpQualitiesThrottled(key: string): void {
  if (key === 'Off') {
    return;
  }
  const now = Date.now();
  if (now - lastIpQualitySaveAt < IP_QUALITY_SAVE_THROTTLE_MS) {
    return;
  }
  lastIpQualitySaveAt = now;
  saveCachedIpQualities(key);
}

function isValidIpQuality(item: HostIpQuality): boolean {
  if (item === undefined || item === null) {
    return false;
  }
  if (typeof item.host !== 'string' || typeof item.ip !== 'string' || typeof item.ok !== 'boolean') {
    return false;
  }
  if (typeof item.latencyMs !== 'number' || typeof item.testedAt !== 'number') {
    return false;
  }
  return item.host.length > 0 && isIpv4(item.ip) && item.latencyMs > 0 &&
    isKnownProbeTarget(item.host, item.ip);
}

function shouldUseDirectConnection(host: string): boolean {
  // VPN 开启时直连探测会「假阳性」：探测请求其实走了代理隧道，看着能直连，
  // 于是这里返回 true 按域名请求，结果撞上被污染的 DNS（31.13.87.9）直接失败。
  // 所以 VPN 激活时一律不采信直连探测结果，继续用 hosts IP。
  if (vpnTunnelActive) {
    return false;
  }
  if (!directProbePassed || appSettingsStore.getValue('auto_direct_connection', 'Off') !== 'On') {
    return false;
  }
  const normalizedHost = host.toLowerCase();
  if (isDirectHostBlocked(normalizedHost)) {
    return false;
  }
  // repo.e-hentai.org 不再无条件直连：实测直连时该域名解析不出来（2300006），
  // 而它和主站共用同一组 Cloudflare 边缘 IP，走 hosts 覆盖反而稳定。
  const selectedHost = selectedGalleryHost();
  if (normalizedHost === selectedHost) {
    return true;
  }
  if (selectedHost === 'exhentai.org') {
    return normalizedHost.endsWith('.exhentai.org');
  }
  if (selectedHost === 'e-hentai.org') {
    return normalizedHost.endsWith('.e-hentai.org') || normalizedHost === 'ehgt.org';
  }
  return false;
}

function recordDirectRequestOutcome(plan: EhRequestPlan, ok: boolean): void {
  if (!directProbePassed || appSettingsStore.getValue('auto_direct_connection', 'Off') !== 'On') {
    return;
  }
  const host = plan.host.split(':')[0].toLowerCase();
  if (!isDirectCandidateHost(host)) {
    return;
  }
  if (ok) {
    clearDirectHostFailure(host);
    return;
  }
  const failure = directHostFailureFor(host);
  failure.failureCount++;
  if (failure.failureCount >= DIRECT_HOST_FAILURE_THRESHOLD) {
    failure.blockedUntil = Date.now() + DIRECT_HOST_BLOCK_MS;
  }
}

function isDirectCandidateHost(host: string): boolean {
  if (host === 'repo.e-hentai.org') {
    return true;
  }
  const selectedHost = selectedGalleryHost();
  if (host === selectedHost) {
    return true;
  }
  if (selectedHost === 'exhentai.org') {
    return host.endsWith('.exhentai.org');
  }
  if (selectedHost === 'e-hentai.org') {
    return host.endsWith('.e-hentai.org') || host === 'ehgt.org';
  }
  return false;
}

function isDirectHostBlocked(host: string): boolean {
  for (let i = DIRECT_HOST_FAILURES.length - 1; i >= 0; i--) {
    const item = DIRECT_HOST_FAILURES[i];
    if (item.blockedUntil > 0 && item.blockedUntil <= Date.now()) {
      DIRECT_HOST_FAILURES.splice(i, 1);
      continue;
    }
    if (item.host === host && item.blockedUntil > Date.now()) {
      return true;
    }
  }
  return false;
}

function directHostFailureFor(host: string): DirectHostFailure {
  for (let i = 0; i < DIRECT_HOST_FAILURES.length; i++) {
    if (DIRECT_HOST_FAILURES[i].host === host) {
      return DIRECT_HOST_FAILURES[i];
    }
  }
  const failure: DirectHostFailure = {
    host: host,
    failureCount: 0,
    blockedUntil: 0
  };
  DIRECT_HOST_FAILURES.push(failure);
  return failure;
}

function clearDirectHostFailure(host: string): void {
  for (let i = DIRECT_HOST_FAILURES.length - 1; i >= 0; i--) {
    if (DIRECT_HOST_FAILURES[i].host === host) {
      DIRECT_HOST_FAILURES.splice(i, 1);
    }
  }
}

function clearDirectHostFailures(): void {
  DIRECT_HOST_FAILURES.splice(0, DIRECT_HOST_FAILURES.length);
}

function directProbeKeyValue(): string {
  if (appSettingsStore.getValue('auto_direct_connection', 'Off') !== 'On') {
    return 'Off';
  }
  return appSettingsStore.getValue('gallery_site', 'E-Hentai') + ':' + proxySettingsKey() + ':' +
    dohSettingsKey() + ':' + currentNetworkEnvironmentKey();
}

function selectedGalleryHost(): string {
  return appSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? 'exhentai.org' : 'e-hentai.org';
}

async function probeDirectSelectedSite(): Promise<boolean> {
  await acquireEhProbeAdmission();
  const request = acquireHttpRequest();
  markHttpRequestVolatile(request);
  try {
    const host = selectedGalleryHost();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.HEAD,
      header: {
        'User-Agent': FRONTING_PROBE_USER_AGENT,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache'
      },
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      maxRedirects: 0,
      connectTimeout: DIRECT_PROBE_TIMEOUT_MS,
      readTimeout: DIRECT_PROBE_TIMEOUT_MS
    };
    if (deviceInfo.apiAvailable('26.0.0')) {
      options.reuseConnections = false;
    }
    applyConfiguredNetworkOptions(options);
    const response = await requestProbeToCompletion(request, 'https://' + host + '/', options);
    const statusCode = Number(response.responseCode);
    return statusCode >= 200 && statusCode < 400;
  } catch (error) {
    return false;
  } finally {
    retireHttpRequest(request);
    releaseEhProbeAdmission();
  }
}

function isKnownProbeTarget(host: string, ip: string): boolean {
  if (!isDomainFrontingActive()) {
    return false;
  }
  return ruleContainsHostIp(BUILT_IN_RULES, host, ip) || ruleContainsHostIp(BUILT_EX_RULES, host, ip);
}

function ruleContainsHostIp(rules: HostRule[], host: string, ip: string): boolean {
  for (let i = 0; i < rules.length; i++) {
    if (rules[i].host === host && rules[i].ips.indexOf(ip) >= 0) {
      return true;
    }
  }
  return false;
}

function frontingBenchmarkKey(): string {
  if (!isDomainFrontingActive()) {
    return 'Off';
  }
  return 'sni-v4-status-aware:' + selectedGalleryHost() + ':' +
    proxySettingsKey() + ':' +
    dohSettingsKey();
}

function frontingCacheKeyMatches(cachedKey: string | undefined, currentKey: string): boolean {
  if (cachedKey === undefined) {
    return false;
  }
  return cachedKey === currentKey || cachedKey.startsWith(currentKey + ':');
}

function refreshNetworkEnvironment(): boolean {
  const key = currentNetworkEnvironmentKey();
  if (key.length === 0) {
    return false;
  }
  if (observedNetworkEnvironmentKey.length === 0) {
    observedNetworkEnvironmentKey = key;
    return false;
  }
  if (observedNetworkEnvironmentKey === key) {
    return false;
  }
  observedNetworkEnvironmentKey = key;
  resetAutoFronting();
  directProbeGeneration++;
  directProbeKey = '';
  directProbePending = null;
  directProbePassed = false;
  clearDirectHostFailures();
  markFreshEhConnectionsRequired();
  return true;
}

function currentNetworkEnvironmentKey(): string {
  if (networkRuntimeRegistered && cachedNetworkEnvironmentKey.length > 0) {
    return cachedNetworkEnvironmentKey;
  }
  const now = Date.now();
  if (cachedNetworkEnvironmentKey.length > 0 &&
    now - lastNetworkEnvironmentCheckAt < NETWORK_ENVIRONMENT_FALLBACK_INTERVAL_MS) {
    return cachedNetworkEnvironmentKey;
  }
  cachedNetworkEnvironmentKey = readCurrentNetworkEnvironmentKey();
  lastNetworkEnvironmentCheckAt = now;
  return cachedNetworkEnvironmentKey;
}

function readCurrentNetworkEnvironmentKey(): string {
  try {
    const defaultNetwork = connection.getDefaultNetSync();
    if (defaultNetwork.netId <= 0) {
      return 'offline';
    }
    const capabilities = connection.getNetCapabilitiesSync(defaultNetwork);
    const bearerTypes: number[] = [];
    for (let i = 0; i < capabilities.bearerTypes.length; i++) {
      bearerTypes.push(capabilities.bearerTypes[i] as number);
    }
    bearerTypes.sort((left: number, right: number): number => left - right);
    const networkCapabilities: number[] = [];
    if (capabilities.networkCap !== undefined) {
      for (let i = 0; i < capabilities.networkCap.length; i++) {
        networkCapabilities.push(capabilities.networkCap[i] as number);
      }
    }
    networkCapabilities.sort((left: number, right: number): number => left - right);
    const properties = connection.getConnectionPropertiesSync(defaultNetwork);
    const dnses: string[] = [];
    for (let i = 0; i < properties.dnses.length; i++) {
      dnses.push(properties.dnses[i].address);
    }
    dnses.sort();
    const linkAddresses: string[] = [];
    for (let i = 0; i < properties.linkAddresses.length; i++) {
      linkAddresses.push(properties.linkAddresses[i].address.address + '/' +
        properties.linkAddresses[i].prefixLength.toString());
    }
    linkAddresses.sort();
    return defaultNetwork.netId.toString() + ':' + bearerTypes.join(',') + ':' +
      networkCapabilities.join(',') + ':' + properties.interfaceName + ':' +
      dnses.join(',') + ':' + linkAddresses.join(',');
  } catch (error) {
    return 'offline';
  }
}

function markFreshEhConnectionsRequired(): void {
  forceFreshConnectionsUntilMs = Date.now() + FRESH_CONNECTION_WINDOW_MS;
  previousFrontedHost = '';
  resetFrontingAdmissionHealth();
}

function scheduleNetworkRuntimeRefresh(): void {
  if (networkChangeTimer >= 0) {
    clearTimeout(networkChangeTimer);
  }
  networkChangeTimer = setTimeout(() => {
    networkChangeTimer = -1;
    cachedNetworkEnvironmentKey = readCurrentNetworkEnvironmentKey();
    lastNetworkEnvironmentCheckAt = Date.now();
    if (refreshNetworkEnvironment()) {
      refreshNetworkRuntimeAfterChange();
    }
  }, NETWORK_CHANGE_DEBOUNCE_MS);
}

function refreshNetworkRuntimeAfterChange(): void {
  if (networkRecoveryTimer >= 0) {
    clearTimeout(networkRecoveryTimer);
    networkRecoveryTimer = -1;
  }
  if (!isEhNetworkProcessingEnabled()) {
    return;
  }
  const environmentKey = currentNetworkEnvironmentKey();
  if (environmentKey === 'offline') {
    return;
  }
  networkRecoveryTimer = setTimeout(() => {
    runNetworkRuntimeRecoveryWhenIdle(environmentKey);
  }, NETWORK_RECOVERY_SETTLE_MS);
}

function runNetworkRuntimeRecoveryWhenIdle(environmentKey: string): void {
  networkRecoveryTimer = -1;
  if (environmentKey !== currentNetworkEnvironmentKey() || currentNetworkEnvironmentKey() === 'offline') {
    refreshNetworkRuntimeAfterChange();
    return;
  }
  // HarmonyOS 6.1 may migrate existing curl tasks during a network handover. Starting the direct probe and
  // fronting benchmark before those tasks settle can make several timeouts complete in the same native multi loop.
  // Wait for normal requests to become idle; cached scores and real request outcomes remain usable meanwhile.
  if (hasActiveHttpRequests()) {
    networkRecoveryTimer = setTimeout(() => {
      runNetworkRuntimeRecoveryWhenIdle(environmentKey);
    }, NETWORK_RECOVERY_IDLE_RETRY_MS);
    return;
  }
  if (isEhDirectConnectionProbeEnabled()) {
    startEhDirectConnectionProbe(networkRuntimeContext).then((directAvailable: boolean) => {
      if (!directAvailable) {
        startEhFrontingBenchmark(networkRuntimeContext, true);
      }
    }).catch(() => {
      startEhFrontingBenchmark(networkRuntimeContext, true);
    });
    return;
  }
  ensureEhHostRules().then(() => {
    startEhFrontingBenchmark(networkRuntimeContext, true);
  }).catch(() => {
  });
}

function dispatchFrontingAdmissions(): void {
  if (frontingDispatchTimer >= 0) {
    return;
  }
  const now = Date.now();
  if (now < frontingNextStartAt) {
    frontingDispatchTimer = setTimeout(() => {
      frontingDispatchTimer = -1;
      dispatchFrontingAdmissions();
    }, Math.max(1, frontingNextStartAt - now));
    return;
  }
  const totalLimit = currentFrontingConcurrencyLimit(now);
  if (activeFrontingRequests >= totalLimit || WAITING_FRONTING_ADMISSIONS.length === 0) {
    return;
  }
  let bestIndex = -1;
  for (let i = 0; i < WAITING_FRONTING_ADMISSIONS.length; i++) {
    const candidate = WAITING_FRONTING_ADMISSIONS[i];
    const runtime = frontingRouteRuntime(candidate.key);
    if (runtime.active >= currentFrontingRouteConcurrencyLimit(runtime, now)) {
      continue;
    }
    if (bestIndex < 0) {
      bestIndex = i;
      continue;
    }
    const best = WAITING_FRONTING_ADMISSIONS[bestIndex];
    if (candidate.priority > best.priority ||
      (candidate.priority === best.priority && candidate.sequence < best.sequence)) {
      bestIndex = i;
    }
  }
  if (bestIndex < 0) {
    return;
  }
  const next = WAITING_FRONTING_ADMISSIONS.splice(bestIndex, 1)[0];
  const runtime = frontingRouteRuntime(next.key);
  runtime.active++;
  activeFrontingRequests++;
  activeForegroundEhRequests++;
  frontingNextStartAt = now + currentFrontingStartSpacing(now);
  next.resolve({ fronted: true, key: next.key, released: false });
  if (activeFrontingRequests < totalLimit && WAITING_FRONTING_ADMISSIONS.length > 0) {
    dispatchFrontingAdmissions();
  }
}

function currentFrontingConcurrencyLimit(now: number): number {
  if (now < frontingRestrictedUntil) {
    return FRONTING_DEGRADED_CONCURRENCY;
  }
  return frontingHealthySuccesses >= FRONTING_HEALTHY_SUCCESS_THRESHOLD ?
    FRONTING_HEALTHY_CONCURRENCY : FRONTING_INITIAL_CONCURRENCY;
}

function currentFrontingRouteConcurrencyLimit(runtime: FrontingRouteRuntime, now: number): number {
  if (now < runtime.restrictedUntil) {
    return FRONTING_ROUTE_DEGRADED_CONCURRENCY;
  }
  return runtime.successes >= FRONTING_ROUTE_HEALTHY_SUCCESS_THRESHOLD ?
    FRONTING_ROUTE_HEALTHY_CONCURRENCY : FRONTING_ROUTE_INITIAL_CONCURRENCY;
}

function currentFrontingStartSpacing(now: number): number {
  if (now < frontingRestrictedUntil || frontingHealthySuccesses < FRONTING_HEALTHY_SUCCESS_THRESHOLD) {
    return FRONTING_INITIAL_START_SPACING_MS;
  }
  return FRONTING_HEALTHY_START_SPACING_MS;
}

function shouldUseFreshFrontingConnection(plan: EhRequestPlan): boolean {
  const now = Date.now();
  if (now < frontingRestrictedUntil || frontingHealthySuccesses < FRONTING_HEALTHY_SUCCESS_THRESHOLD) {
    return true;
  }
  const runtime = frontingRouteRuntime(frontingRouteKey(plan));
  return now < runtime.restrictedUntil || runtime.successes < FRONTING_ROUTE_HEALTHY_SUCCESS_THRESHOLD;
}

function frontingRouteRuntime(key: string): FrontingRouteRuntime {
  const existing = findFrontingRouteRuntime(key);
  if (existing !== null) {
    return existing;
  }
  const runtime: FrontingRouteRuntime = {
    key: key,
    active: 0,
    successes: 0,
    failures: 0,
    restrictedUntil: 0
  };
  FRONTING_ROUTE_RUNTIMES.push(runtime);
  return runtime;
}

function findFrontingRouteRuntime(key: string): FrontingRouteRuntime | null {
  for (let i = 0; i < FRONTING_ROUTE_RUNTIMES.length; i++) {
    if (FRONTING_ROUTE_RUNTIMES[i].key === key) {
      return FRONTING_ROUTE_RUNTIMES[i];
    }
  }
  return null;
}

function frontingRouteKey(plan: EhRequestPlan): string {
  return plan.host.toLowerCase() + '|' + requestHost(plan.url).toLowerCase();
}

function hasForegroundEhRequestPressure(): boolean {
  return activeForegroundEhRequests > 0 || WAITING_FRONTING_ADMISSIONS.length > 0;
}

function waitNetworkAdmission(delayMs: number): Promise<void> {
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    setTimeout(() => {
      resolve();
    }, delayMs);
  });
}

function resetFrontingAdmissionHealth(): void {
  frontingHealthySuccesses = 0;
  frontingRestrictedUntil = 0;
  frontingNextStartAt = 0;
  for (let i = 0; i < FRONTING_ROUTE_RUNTIMES.length; i++) {
    FRONTING_ROUTE_RUNTIMES[i].successes = 0;
    FRONTING_ROUTE_RUNTIMES[i].failures = 0;
    FRONTING_ROUTE_RUNTIMES[i].restrictedUntil = 0;
  }
  dispatchFrontingAdmissions();
}

// DNS 全灭时的最后回退：取内置 hosts 表里该域名的首个 IPv4，构造「IP 直连 + Host 头」请求。
// 零 DNS 依赖（不查 DoH 也不用系统 DNS），专治 DoH 服务器不可达 + 系统 DNS 被污染的设备。
// 没有内置 IP 的域名返回 null，调用方保持原选路。
export function builtInHostPlanForUrl(url: string): EhRequestPlan | null {
  const host = requestHost(url);
  if (host.length === 0) {
    return null;
  }
  const rules: HostRule[] = [];
  for (let i = 0; i < BUILT_IN_RULES.length; i++) {
    if (BUILT_IN_RULES[i].host === host) {
      rules.push(BUILT_IN_RULES[i]);
    }
  }
  for (let i = 0; i < BUILT_EX_RULES.length; i++) {
    if (BUILT_EX_RULES[i].host === host) {
      rules.push(BUILT_EX_RULES[i]);
    }
  }
  for (let i = 0; i < rules.length; i++) {
    for (let j = 0; j < rules[i].ips.length; j++) {
      const ip = rules[i].ips[j];
      // 只用 IPv4 字面量：IPv6 裸地址在 URL 里需要方括号转写，兼容面窄，不进回退链
      if (ip.indexOf(':') >= 0) {
        continue;
      }
      return {
        url: replaceUrlHost(url, ip),
        host: requestHostHeader(url),
        fronted: false
      };
    }
  }
  return null;
}

function requestHost(url: string): string {
  const match = /^https?:\/\/([^\/?#:]+)/i.exec(url);
  return match === null ? '' : match[1];
}

function requestHostHeader(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/i.exec(url);
  return match === null ? '' : match[1];
}

function replaceUrlHost(url: string, host: string): string {
  return url.replace(/^(https?:\/\/)([^\/?#]+)/i, '$1' + host);
}

function isIpv4(value: string): boolean {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(value);
}

function isHttpsUrl(url: string): boolean {
  return /^https:\/\//i.test(url);
}

function supportsDomainFrontingHost(host: string): boolean {
  const normalized = host.toLowerCase();
  return normalized === 'e-hentai.org' ||
    normalized.endsWith('.e-hentai.org') || normalized === 'exhentai.org' ||
    normalized.endsWith('.exhentai.org');
}

function waitHostRuleTask(task: Promise<void>, timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    let finished = false;
    const timer = setTimeout(() => {
      if (finished) {
        return;
      }
      finished = true;
      resolve();
    }, timeoutMs);
    task.then(() => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      resolve();
    }).catch(() => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      resolve();
    });
  });
}

function parseProxyPort(value: string): number {
  const port = Number.parseInt(value.trim());
  return Number.isNaN(port) ? -1 : port;
}

function isValidPort(port: number): boolean {
  return port > 0 && port <= 65535;
}

function parseProxyExclusionList(value: string): string[] {
  const result: string[] = [];
  const parts = value.split(',');
  for (let i = 0; i < parts.length; i++) {
    const item = parts[i].trim();
    if (item.length > 0 && result.indexOf(item) < 0) {
      result.push(item);
    }
  }
  return result;
}

function proxySettingsKey(): string {
  return appSettingsStore.getValue('proxy', 'System') + ':' +
    appSettingsStore.getValue('proxy_host', '') + ':' +
    appSettingsStore.getValue('proxy_port', '') + ':' +
    appSettingsStore.getValue('proxy_username', '') + ':' +
    hashText(appSettingsStore.getValue('proxy_password', '')) + ':' +
    appSettingsStore.getValue('proxy_exclusion_list', '') + ':' +
    appSettingsStore.getValue('proxy_socks_dns', 'Proxy');
}

export function currentDnsOverHttpsUrl(): string {
  if (appSettingsStore.getValue('dns_over_https', 'Off') !== 'On') {
    return '';
  }
  const provider = currentDnsOverHttpsProvider();
  if (provider === 'Cloudflare') {
    return CLOUDFLARE_DOH_URL;
  }
  if (provider === 'Google') {
    return GOOGLE_DOH_URL;
  }
  return YANDEX_DOH_URL;
}

export function currentDnsOverHttpsStatusText(): string {
  const url = currentDnsOverHttpsUrl();
  return url.length > 0 ? 'On ' + currentDnsOverHttpsProvider() + ' ' + url : 'Off';
}

function dohSettingsKey(): string {
  if (appSettingsStore.getValue('dns_over_https', 'Off') !== 'On') {
    return 'Off';
  }
  return 'On:' + currentDnsOverHttpsProvider();
}

function currentDnsOverHttpsProvider(): string {
  const provider = appSettingsStore.getValue('dns_over_https_provider', 'Yandex');
  return provider === 'Cloudflare' || provider === 'Google' ? provider : 'Yandex';
}

function hashText(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash = (hash ^ value.charCodeAt(i)) * 16777619;
  }
  return value.length.toString() + '-' + (hash >>> 0).toString(16);
}

async function applyHostRules(key: string): Promise<void> {
  try {
    await removeKnownHostRules();
    const rules: HostRule[] = [];
    if (appSettingsStore.getValue('built_in_hosts', 'Off') === 'On') {
      pushRules(rules, BUILT_IN_RULES);
    }
    if (appSettingsStore.getValue('built_ex_hosts', 'Off') === 'On') {
      pushRules(rules, BUILT_EX_RULES);
    }
    for (let i = 0; i < rules.length; i++) {
      await connection.addCustomDnsRule(rules[i].host, rules[i].ips);
    }
    appliedHostRulesKey = key;
  } catch (error) {
    appliedHostRulesKey = '';
  }
}

async function removeKnownHostRules(): Promise<void> {
  appliedHostRulesKey = '';
  const rules: HostRule[] = [];
  pushRules(rules, BUILT_IN_RULES);
  pushRules(rules, BUILT_EX_RULES);
  for (let i = 0; i < rules.length; i++) {
    try {
      await connection.removeCustomDnsRule(rules[i].host);
    } catch (error) {
    }
  }
}

async function restoreConfiguredHostRules(): Promise<void> {
  const key = appSettingsStore.getValue('built_in_hosts', 'Off') + ':' +
    appSettingsStore.getValue('built_ex_hosts', 'Off');
  if (key === 'Off:Off') {
    await removeKnownHostRules();
    appliedHostRulesKey = key;
    return;
  }
  await applyHostRules(key);
}

function pushRules(target: HostRule[], source: HostRule[]): void {
  for (let i = 0; i < source.length; i++) {
    target.push(source[i]);
  }
}
