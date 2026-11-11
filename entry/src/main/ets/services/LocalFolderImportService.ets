import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryInfo, GallerySite } from '../model/GalleryModels';
import { ehDownloadFileStore, galleryImageNames, RestoredDownloadGallery } from './EhDownloadFileStore';
import { DownloadState, ehDownloadStore, normalizeGalleryIdentity } from './EhDownloadStore';
import { EhHttpClient, GalleryListLoadResult } from './EhHttpClient';
import { ListUrlBuilder, gallerySiteCandidates } from './EhUrl';
import { appKeepAlive } from './AppKeepAlive';
import {
  directoryModifiedTimeMs,
  ensureDirectory,
  exists,
  isDirectory
} from '../shared/FileUtils';

const MAX_SCAN_DEPTH: number = 3;
const MAX_SCAN_DIRECTORIES: number = 600;
const PROGRESS_SCALE: number = 1000;
const LOCAL_THUMB_ROOT: string = 'local_thumbs';

const SCAN_LOG_NAME: string = 'download_scan.log';
let scanLogBuffer: string[] = [];

export function logScan(line: string): void {
  scanLogBuffer.push(new Date().toISOString() + ' ' + line);
  if (scanLogBuffer.length > 5000) {
    scanLogBuffer.splice(0, 1000);
  }
  // 同步打 hilog：诊断导入误匹配必须能离线看到每个目录的判定链路
  // （应用沙箱日志 hdc 读不到，hilog 是唯一通道）。
  console.info('[LocalImport] ' + line);
}

export function flushScanLog(context: common.UIAbilityContext, header: string): string {
  const text = '=== ' + header + ' ' + new Date().toISOString() + ' ===\n' + scanLogBuffer.join('\n') + '\n';
  try {
    const path = context.filesDir + '/' + SCAN_LOG_NAME;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
    fs.closeSync(file.fd);
    return path;
  } catch (error) {
    return '';
  }
}

export interface LocalImportReport {
  folders: number;
  added: number;
  matched: number;
  localOnly: number;
  duplicated: number;
  merged: number;
  empty: number;
  failed: number;
  bytes: number;
}

export interface LocalImportProgress {
  current: number;
  total: number;
  name: string;
}

interface LocalGalleryDirectory {
  path: string;
  name: string;
}

// 扫描用户选定的文件夹，把其中的图册登记进下载列表。
// 有服务器记录的按正常图册登记；没有记录的登记为本地图档（本地缩略图 + 目录名）。
export async function importLocalGalleryFolder(context: common.UIAbilityContext, folderUri: string,
  site: GallerySite, onProgress?: (progress: LocalImportProgress) => void): Promise<LocalImportReport> {
  await appKeepAlive.acquire(context);
  try {
    return await importLocalGalleryFolderInner(context, folderUri, site, onProgress);
  } finally {
    await appKeepAlive.release();
  }
}

async function importLocalGalleryFolderInner(context: common.UIAbilityContext, folderUri: string,
  site: GallerySite, onProgress?: (progress: LocalImportProgress) => void): Promise<LocalImportReport> {
  const report: LocalImportReport = {
    folders: 0,
    added: 0,
    matched: 0,
    localOnly: 0,
    duplicated: 0,
    merged: 0,
    empty: 0,
    failed: 0,
    bytes: 0
  };
  if (folderUri.length === 0) {
    return report;
  }
  const folderPath = normalizeFolderPath(folderUri);
  await ehDownloadStore.load(context);
  const directories = collectGalleryDirectories(folderPath);
  report.folders = directories.length;
  if (directories.length <= 0) {
    return report;
  }
  const client = new EhHttpClient();
  // 扫描是同步 IO 密集操作（每目录 listFileSync + 封面复制）。每 5 个目录让出
  // 一次主线程，否则大库扫描期间 UI 完全冻结（F-118：卡顿后闪退的缓解项）。
  let yieldCounter = 0;
  for (let i = 0; i < directories.length; i++) {
    if (onProgress !== undefined) {
      onProgress({ current: i + 1, total: directories.length, name: directories[i].name });
    }
    await importOneDirectory(context, directories[i], site, client, report);
    yieldCounter++;
    if (yieldCounter >= 5) {
      yieldCounter = 0;
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 0);
      });
    }
  }
  await ehDownloadStore.save(context);
  flushScanLog(context, 'local folder import: folders=' + report.folders.toString() +
    ' added=' + report.added.toString() + ' matched=' + report.matched.toString() +
    ' local=' + report.localOnly.toString() + ' dup=' + report.duplicated.toString() +
    ' empty=' + report.empty.toString() + ' failed=' + report.failed.toString() +
    ' root=' + folderPath);
  return report;
}

async function importOneDirectory(context: common.UIAbilityContext, source: LocalGalleryDirectory,
  site: GallerySite, client: EhHttpClient, report: LocalImportReport): Promise<void> {
  const images = listImageNames(source.path);
  if (images.length <= 0) {
    logScan('dir=' + source.name + ' images=0 -> empty, skipped');
    report.empty++;
    return;
  }

  // 目录里已经有 .ehviewer / .ehviewer.json 时直接采用其中的 token，不必联网。
  const inspected = ehDownloadFileStore.inspectRestoredGalleryDirectory(source.path);
  const localToken = inspected === null ? '' : inspected.gallery.token;
  let gid = inspected === null ? galleryIdFromName(source.name) : inspected.gallery.gid;
  if (gid <= 0) {
    gid = galleryIdFromName(source.name);
  }
  if (gid > 0 && ehDownloadStore.contains(gid)) {
    // 同 gid 记录已存在。换机/迁移后记录里的目录可能已失效（列表有名字、
    // 无预览图、详情无图）：这份真实目录若有效就绑回去，空壳记录恢复阅读。
    const thumb = ensureLocalThumbnail(context, source.path, source.name);
    const rebound = ehDownloadStore.rebindMissingDirectory(gid, source.path, images.length, thumb);
    logScan('dir=' + source.name + ' gid=' + gid.toString() + ' -> duplicated' +
      (rebound ? ' -> rebound missing directory' : ' -> existing directory intact'));
    report.duplicated++;
    return;
  }

  // F-115：扫描阶段一律不联网（459 个目录逐个联网是 20 分钟扫描的根因）。
  // 有 .ehviewer 元数据的按元数据登记云端身份，其余纯本地登记；
  // 云端身份统一交给下载页的后台匹配任务自动补齐。
  if (localToken.length > 0 && inspected !== null && inspected.gallery.gid > 0 &&
    inspected.gallery.token.length > 0) {
    addMatchedGallery(context, source, inspected.gallery, images.length, report);
    return;
  }

  const title = localTitle(source.name, inspected);
  logScan('dir=' + source.name + ' images=' + images.length.toString() + ' gid=' + gid.toString() +
    ' token=' + localToken + ' -> local title=' + title);
  addLocalGallery(context, source, title, images.length, report);
}

function addMatchedGallery(context: common.UIAbilityContext, source: LocalGalleryDirectory, gallery: GalleryInfo,
  pageCount: number, report: LocalImportReport): void {
  try {
    // 同上：源已在下载根目录里就别再“复制到 gid-标题”，否则会把源删掉再复制（源==目标）。
    const root = ehDownloadFileStore.currentDownloadRoot(context);
    const alreadyInRoot = source.path === root || source.path.startsWith(root + '/');
    const target = alreadyInRoot ? source.path :
      ehDownloadFileStore.importGalleryDirectory(context, source.path, gallery);
    const size = ehDownloadFileStore.directorySizeByPath(target);
    // 已有同 gid 的记录（典型是先导了 DB）：把真实目录绑上去，归位完成，不再重复登记。
    // 已有同标题的纯本地记录：就地升级成云端记录，目录仍指向本机这份文件。
    const outcome = ehDownloadStore.bindMatchedGallery(gallery, target, pageCount, size,
      directoryModifiedTimeMs(source.path));
    report.bytes += size;
    report.matched++;
    if (outcome === 'added') {
      report.added++;
    } else if (outcome === 'merged') {
      report.merged++;
    } else {
      report.duplicated++;
      return;
    }
    logScan('  -> matched gid=' + gallery.gid.toString() + ' outcome=' + outcome + ' dir=' + target);
  } catch (error) {
    report.failed++;
  }
}

function addLocalGallery(context: common.UIAbilityContext, source: LocalGalleryDirectory, title: string,
  pageCount: number, report: LocalImportReport): void {
  try {
    // 源目录已经在下载根目录里时就地登记，不要再复制一份纯标题目录。
    // 复制出来的那份没有元数据，下次“扫描本地图册”会把它当成新图册再登记一次，
    // 列表里同一个图册就出现两条，封面也各取各的。
    const root = ehDownloadFileStore.currentDownloadRoot(context);
    const alreadyInRoot = source.path === root || source.path.startsWith(root + '/');
    const target = alreadyInRoot ? source.path :
      ehDownloadFileStore.importLocalGalleryDirectory(context, source.path, title);
    if (ehDownloadStore.hasLocalGalleryDirectory(target)) {
      // 已经登记过也不能直接跳过：早期记录的 pages 是 0，列表里页数一直显示 "-"，
      // 详情页也读不到真实页数。这里按磁盘实际图片数就地回填。
      ehDownloadStore.refreshLocalGalleryMeta(target, pageCount,
        ehDownloadFileStore.directorySizeByPath(target),
        ensureLocalThumbnail(context, target, title));
      logScan('  -> duplicated (already registered, meta refreshed) ' + target);
      report.duplicated++;
      return;
    }
    const size = ehDownloadFileStore.directorySizeByPath(target);
    // 同标题的记录已经存在（常见是 DB 先导入、记录了这条云端图册）：把这份本地文件绑到
    // 那条记录上，别再新增一条纯本地记录，否则同一图册在列表里出现两次。
    const identityIndex = ehDownloadStore.findIdentityIndex(title);
    if (identityIndex >= 0) {
      const existing = ehDownloadStore.getItems()[identityIndex];
      // 本地封面必须一起换上：原记录的 thumb 多半是失效的云端 URL（DP 迁移），
      // 只绑目录不换封面，列表缩略图会一直显示 X 重试。
      const localThumb = ensureLocalThumbnail(context, target, title);
      ehDownloadStore.setStorage(existing.gid, target, size);
      ehDownloadStore.refreshLocalGalleryMeta(target, pageCount, size, localThumb, existing.gid);
      ehDownloadStore.setState(existing.gid, DownloadState.Finish);
      ehDownloadStore.setProgress(existing.gid, pageCount, pageCount, pageCount * PROGRESS_SCALE);
      logScan('  -> merged into existing gid=' + existing.gid.toString() + ' dir=' + target);
      report.merged++;
      return;
    }
    const thumb = ensureLocalThumbnail(context, target, title);
    const item = ehDownloadStore.addLocalGallery(title, target, thumb, pageCount, size,
      directoryModifiedTimeMs(source.path));
    if (item === null) {
      report.failed++;
      return;
    }
    report.bytes += size;
    report.localOnly++;
    report.added++;
  } catch (error) {
    report.failed++;
  }
}

// 本地图档的缩略图取目录里的第一页，复制到应用私有目录，避免影响阅读器页序。
export function ensureLocalThumbnail(context: common.UIAbilityContext, directory: string, key: string): string {
  const images = listImageNames(directory);
  if (images.length <= 0) {
    return '';
  }
  const root = context.filesDir + '/' + LOCAL_THUMB_ROOT;
  ensureDirectory(root);
  // 键里带上首图文件名：排序规则一变（字典序 → 自然序），首图就换人，
  // 只按目录名做键会命中上一次生成的那张，封面和第一页永远对不上。
  // 另做一次大小校验，源图被替换但文件名没变时也能重建。
  const folderKey = directory.substring(directory.lastIndexOf('/') + 1);
  const baseKey = folderKey.length > 0 ? folderKey : key;
  const source = joinPath(directory, images[0]);
  const target = root + '/' + sanitizeKey(baseKey) + '-' + shortKeyHash(images[0]) +
    extensionOf(images[0]);
  if (!pathExists(target) || fileSizeOf(target) !== fileSizeOf(source)) {
    try {
      fs.copyFileSync(source, target);
    } catch (error) {
      return '';
    }
  }
  return target;
}

// 目录内最早修改文件的 mtime：跨机拷贝的目录 mtime 全等于拷贝时刻，
// 按它回填的下载时间无法区分先后（F-120 用户反馈时间排序失效）。
// 文件级 mtime 拷贝时通常保留，取最早文件的修改时间 ≈ 原始下载时间。
function earliestFileTimeMs(directory: string): number {
  const images = listImageNames(directory);
  let earliest = 0;
  // 只抽查前 3 张（首图最早下载），避免大目录全量 stat。
  const sample = images.slice(0, 3);
  for (let i = 0; i < sample.length; i++) {
    try {
      const stat = fs.statSync(joinPath(directory, sample[i]));
      const mtimeMs = stat.mtime > 0 ? Math.round(stat.mtime * 1000) : 0;
      if (mtimeMs > 0 && (earliest === 0 || mtimeMs < earliest)) {
        earliest = mtimeMs;
      }
    } catch (error) {
      continue;
    }
  }
  return earliest;
}

function fileSizeOf(path: string): number {
  try {
    return fs.statSync(path).size;
  } catch (error) {
    return -1;
  }
}
function sanitizeKey(value: string): string {
  let result = value.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim();
  if (result.length === 0) {
    result = 'local';
  }
  if (result.length > 80) {
    // 截断会让同系列图册撞同一个键（前 80 字往往一模一样），尾巴补原文哈希保证唯一。
    result = result.substring(0, 72).trim() + '-' + shortKeyHash(value);
  }
  return result;
}

function shortKeyHash(value: string): string {
  let hash = 5381;
  for (let i = 0; i < value.length; i++) {
    hash = ((hash * 33) ^ value.charCodeAt(i)) & 0x7fffffff;
  }
  return hash.toString(36);
}

function extensionOf(fileName: string): string {
  const match = /\.([a-zA-Z0-9]+)$/.exec(fileName);
  return match === null ? '.jpg' : '.' + match[1].toLowerCase();
}

function collectGalleryDirectories(rootUri: string): LocalGalleryDirectory[] {
  const result: LocalGalleryDirectory[] = [];
  if (!isDirectoryPath(rootUri)) {
    return result;
  }
  appendChildGalleries(rootUri, 0, result);
  if (result.length <= 0 && listImageNames(rootUri).length > 0) {
    result.push({ path: rootUri, name: pathBaseName(rootUri) });
  }
  return result;
}

function appendChildGalleries(directory: string, depth: number, result: LocalGalleryDirectory[]): void {
  if (depth > MAX_SCAN_DEPTH || result.length >= MAX_SCAN_DIRECTORIES) {
    return;
  }
  let names: string[] = [];
  try {
    names = fs.listFileSync(directory);
  } catch (error) {
    return;
  }
  names.sort();
  for (let i = 0; i < names.length; i++) {
    const name = names[i];
    if (name.startsWith('.')) {
      continue;
    }
    const child = joinPath(directory, name);
    if (!isDirectoryPath(child)) {
      continue;
    }
    if (listImageNames(child).length > 0) {
      result.push({ path: child, name: name });
      continue;
    }
    appendChildGalleries(child, depth + 1, result);
  }
}

// 与阅读器取页共用 EhDownloadFileStore.galleryImageNames 的筛选规则：
// 目录里的 thumb.webp 是客户端封面，不算正文页。两边各写一套就一定会数出两个结果。
function listImageNames(directory: string): string[] {
  try {
    const images = galleryImageNames(fs.listFileSync(directory));
    images.sort((left: string, right: string) => left.localeCompare(right, undefined, { numeric: true }));
    return images;
  } catch (error) {
    return [];
  }
}

// 供下载页「重新匹配云端身份」复用：按 gid 联网找回画廊详情。
export async function matchGalleryOnServer(client: EhHttpClient, site: GallerySite, gid: number): Promise<GalleryInfo | null> {
  const sites = gallerySiteCandidates(site);
  for (let i = 0; i < sites.length; i++) {
    const builder = new ListUrlBuilder();
    builder.keyword = 'gid:' + gid.toString();
    let result: GalleryListLoadResult;
    try {
      result = await client.loadGalleryList(builder, sites[i]);
    } catch (error) {
      continue;
    }
    if (!result.ok) {
      continue;
    }
    for (let j = 0; j < result.galleries.length; j++) {
      const gallery = result.galleries[j];
      if (gallery.gid === gid && gallery.token.length > 0) {
        return gallery;
      }
    }
  }
  // 搜索命不中（被 expunge、索引没收录、站点限制搜索）时，直接开 /g/{gid}/：
  // 站点会 302 到带 token 的正式地址，拿到的详情含标题、上传者、页数、评分。
  for (let i = 0; i < sites.length; i++) {
    try {
      const detailResult = await client.loadGalleryDetailByGid(gid, sites[i]);
      if (detailResult.ok && detailResult.detail !== null && detailResult.detail.token.length > 0) {
        return detailResult.detail;
      }
    } catch (error) {
      continue;
    }
  }
  return null;
}

function localTitle(directoryName: string, inspected: RestoredDownloadGallery | null): string {
  if (inspected !== null && inspected.gallery.title.length > 0) {
    return inspected.gallery.title;
  }
  let title = directoryName.trim();
  title = title.replace(/^\[[^\]]*\]\s*/, '');
  title = title.replace(/\s*\(\d{4,}\)\s*$/, '');
  title = title.replace(/^\d{4,}[-_\s]+/, '');
  title = title.replace(/_/g, ' ').trim();
  return title.length > 0 ? title : directoryName;
}

export function galleryIdFromName(name: string): number {
  const patterns: RegExp[] = [/\((\d{4,})\)/, /^\s*(\d{4,})[-_\s]/, /\[(\d{4,})\]/];
  for (let i = 0; i < patterns.length; i++) {
    const match = patterns[i].exec(name);
    if (match !== null) {
      const gid = Number.parseInt(match[1], 10);
      if (!Number.isNaN(gid)) {
        return gid;
      }
    }
  }
  return 0;
}

export interface ReconcileReport {
  ok: number;
  fixed: number;
  removed: number;
}

// 对账修复：下载列表记录与磁盘目录逐条核对。
// 记录目录有效 → ok；失效 → 按目录 gid 或规范化标题找回真实目录绑定
// （DP 迁移记录的 gid 是旧值，标题能对上时用目录的正确 gid 重登）；
// 找不到任何对应目录的死壳记录清理出列表。
export async function reconcileDownloadRecords(context: common.UIAbilityContext,
  onProgress?: (progress: LocalImportProgress) => void): Promise<ReconcileReport> {
  const report: ReconcileReport = { ok: 0, fixed: 0, removed: 0 };
  const root = ehDownloadFileStore.currentDownloadRoot(context);
  if (root.length === 0) {
    return report;
  }
  await ehDownloadStore.load(context);
  const directories = collectGalleryDirectories(root);
  const gidMap = new Map<number, LocalGalleryDirectory>();
  const titleMap = new Map<string, LocalGalleryDirectory>();
  for (let i = 0; i < directories.length; i++) {
    const dir = directories[i];
    if (listImageNames(dir.path).length <= 0) {
      continue;
    }
    const gid = galleryIdFromName(dir.name);
    if (gid > 0 && !gidMap.has(gid)) {
      gidMap.set(gid, dir);
    }
    const identity = normalizeGalleryIdentity(localTitle(dir.name, null));
    if (identity.length > 0 && !titleMap.has(identity)) {
      titleMap.set(identity, dir);
    }
  }
  const snapshot = ehDownloadStore.getItems().slice();
  // 同扫描：每 5 条让出主线程，避免大库对账期间 UI 冻结（F-118）。
  let yieldCounter = 0;
  for (let i = 0; i < snapshot.length; i++) {
    const item = snapshot[i];
    if (onProgress !== undefined) {
      onProgress({ current: i + 1, total: snapshot.length, name: item.title });
    }
    yieldCounter++;
    if (yieldCounter >= 5) {
      yieldCounter = 0;
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 0);
      });
    }
    if (item.archiveUri.length > 0 && listImageNames(item.archiveUri).length > 0) {
      // 目录有效但封面还是云端 URL（此前只绑目录没换封面的合并残留）：
      // 换成本地生成的封面，列表缩略图不再依赖网络。
      const currentThumb = item.thumb ?? '';
      if (!(currentThumb.startsWith('/') || currentThumb.startsWith('file://'))) {
        const localThumb = ensureLocalThumbnail(context, item.archiveUri, item.title);
        if (localThumb.length > 0) {
          ehDownloadStore.refreshLocalGalleryMeta(item.archiveUri, 0, 0, localThumb, item.gid);
        }
      }
      // 回填真实下载时间：跨机拷贝的目录 mtime 全等于拷贝时刻，改取目录内
      // 最早文件的 mtime（文件级 mtime 拷贝保留）≈ 原始下载时间（F-120）。
      const recoveredTime = earliestFileTimeMs(item.archiveUri);
      if (recoveredTime > 0) {
        ehDownloadStore.setTime(item.gid, recoveredTime);
      }
      // 云端已确认删除（GONE）且本地目录有效：清掉失效云端身份转纯本地，
      // 详情页改走本地面板，底部预览和阅读不再挂在失效的云端请求上。
      if (item.token.length > 0 && item.cloudState === 'gone') {
        ehDownloadStore.clearCloudIdentity(item.gid);
        logScan('  -> cloud gone, converted to local-only gid=' + item.gid.toString());
      }
      report.ok++;
      continue;
    }
    logScan('reconcile broken: gid=' + item.gid.toString() + ' token=' + item.token +
      ' title=' + item.title + ' archive=' + item.archiveUri);
    let target: LocalGalleryDirectory | null = null;
    if (item.gid > 0 && gidMap.has(item.gid)) {
      target = gidMap.get(item.gid) ?? null;
    }
    if (target === null) {
      const identity = normalizeGalleryIdentity(item.title);
      if (identity.length > 0 && titleMap.has(identity)) {
        target = titleMap.get(identity) ?? null;
      }
    }
    if (target === null) {
      // 目录都找不到：云端身份即使有效也没有本地内容，详情只剩 Not found。
      // 云端还活着的以后可以重新导入，这里清掉死壳。
      ehDownloadStore.removeGallery(item.gid);
      logScan('  -> removed (no matching directory)');
      report.removed++;
      continue;
    }
    const images = listImageNames(target.path).length;
    const realGid = galleryIdFromName(target.name);
    const thumb = ensureLocalThumbnail(context, target.path, item.title);
    const size = ehDownloadFileStore.directorySizeByPath(target.path);
    if (realGid > 0 && realGid === item.gid) {
      ehDownloadStore.rebindMissingDirectory(item.gid, target.path, images, thumb);
      logScan('  -> rebound gid=' + item.gid.toString() + ' dir=' + target.name);
    } else {
      // 记录 gid 与目录 gid 不一致（DP 旧值）：删旧记录，按目录真实 gid 重登。
      ehDownloadStore.removeGallery(item.gid);
      if (realGid <= 0 || !ehDownloadStore.contains(realGid)) {
        ehDownloadStore.addLocalGallery(item.title, target.path, thumb, images, size, 0);
        logScan('  -> re-registered gid=' + realGid.toString() + ' dir=' + target.name);
      } else {
        logScan('  -> dropped stale record, real gid=' + realGid.toString() + ' already registered');
      }
    }
    report.fixed++;
  }
  await ehDownloadStore.save(context);
  return report;
}

function joinPath(directory: string, name: string): string {
  return directory.endsWith('/') ? directory + name : directory + '/' + name;
}

// 选择器可能返回 file://docs/... 形式的 URI，统一转成文件系统路径。
function normalizeFolderPath(value: string): string {
  let path = value.trim();
  if (path.indexOf('file://') === 0) {
    path = decodeURIComponent(path.substring(7));
    const slash = path.indexOf('/', 1);
    path = slash >= 0 ? path.substring(slash) : path;
  }
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

function pathBaseName(path: string): string {
  const normalized = path.replace(/\\/g, '/');
  const trimmed = normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
  const slash = trimmed.lastIndexOf('/');
  return slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
}

function isDirectoryPath(path: string): boolean {
  try {
    return fs.statSync(path).isDirectory();
  } catch (error) {
    return false;
  }
}

function pathExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

function isSupportedImageFile(name: string): boolean {
  const lower = name.toLowerCase();
  return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
    lower.endsWith('.webp') || lower.endsWith('.gif');
}
