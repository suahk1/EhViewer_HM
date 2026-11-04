import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryInfo, GallerySite } from '../model/GalleryModels';
import { ehDownloadFileStore, RestoredDownloadGallery } from './EhDownloadFileStore';
import { DownloadInfo, DownloadState, ehDownloadStore } from './EhDownloadStore';
import { ehHistoryStore } from './EhHistoryStore';
import { ehCookieStore } from './EhCookieStore';
import { EhHttpClient, GalleryListLoadResult } from './EhHttpClient';
import { ListUrlBuilder } from './EhUrl';
import { rebuildRestoredDownloadMetadata } from './DownloadMetadataRestore';
import { gallerySiteCandidates } from './EhUrl';
import { ensureLocalThumbnail, flushScanLog, logScan } from './LocalFolderImportService';
import { appKeepAlive } from './AppKeepAlive';
import {
  directoryModifiedTimeMs,
  ensureDirectory,
  exists,
  isDirectory
} from '../shared/FileUtils';
import { DOWNLOAD_PAGE_PROGRESS_SCALE } from '../shared/DownloadLimits';

const ZIP_EXTENSION: string = '.zip';
const MAX_METADATA_SEARCH_DEPTH: number = 5;
const MAX_ZIP_UNCOMPRESSED_BYTES: number = 16 * 1024 * 1024 * 1024;

export interface DownloadZipImportResult {
  found: number;
  processed: number;
  skipped: number;
  processedPaths: string[];
  importedGalleries: RestoredDownloadGallery[];
}

export interface DownloadRestoreResult {
  restored: number;
  added: number;
  updated: number;
  skipped: number;
  migrated: number;
  localOnly: number;
  totalBytes: number;
  metadataRebuilt: number;
  metadataFetched: number;
  archives: DownloadZipImportResult;
}

export async function importPublicDownloadArchives(context: common.UIAbilityContext, site: GallerySite,
  selectedPaths?: string[], seedGallery?: GalleryInfo): Promise<DownloadZipImportResult> {
  const paths = selectedPaths === undefined ? listPublicZipFiles(context) : filterZipFiles(selectedPaths);
  const result: DownloadZipImportResult = {
    found: paths.length,
    processed: 0,
    skipped: 0,
    processedPaths: [],
    importedGalleries: []
  };
  if (paths.length <= 0) {
    return result;
  }

  await ehCookieStore.ensureLoaded(context);
  await ehHistoryStore.ensureLoaded(context);
  const client = new EhHttpClient();
  for (let i = 0; i < paths.length; i++) {
    const imported = await importOneArchive(context, paths[i], site, client, seedGallery);
    if (imported.length <= 0) {
      result.skipped++;
      continue;
    }
    result.processed++;
    result.processedPaths.push(paths[i]);
    appendUniqueRestored(result.importedGalleries, imported);
  }
  return result;
}

export async function importDownloadedArchiveAndRegister(context: common.UIAbilityContext, zipPath: string,
  site: GallerySite, gallery: GalleryInfo): Promise<number> {
  const result = await importPublicDownloadArchives(context, site, [zipPath], gallery);
  if (result.importedGalleries.length <= 0) {
    return 0;
  }
  await rebuildRestoredDownloadMetadata(context, result.importedGalleries, site);
  let restored = 0;
  for (let i = 0; i < result.importedGalleries.length; i++) {
    const imported = result.importedGalleries[i];
    const item = ehDownloadStore.addGallery(imported.gallery, '', directoryModifiedTimeMs(imported.directory));
    if (item === null) {
      continue;
    }
    const total = Math.max(imported.total, imported.finished);
    ehDownloadStore.setState(item.gid, total > 0 && imported.finished >= total ?
      DownloadState.Finish : DownloadState.None);
    ehDownloadStore.setProgress(item.gid, imported.finished, total,
      imported.finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
    ehDownloadStore.setStorage(item.gid, imported.directory, imported.fileSize);
    restored++;
  }
  await ehDownloadStore.save(context);
  return restored;
}

export async function restoreDownloadedItemsAndArchives(context: common.UIAbilityContext, site: GallerySite,
  scanPublicArchives: boolean): Promise<DownloadRestoreResult> {
  // 扫描成百上千个目录同样可能跑很久，挂长时任务保证切后台不被冻结。
  await appKeepAlive.acquire(context);
  try {
    return await restoreDownloadedItemsAndArchivesInner(context, site, scanPublicArchives);
  } finally {
    await appKeepAlive.release();
  }
}

async function restoreDownloadedItemsAndArchivesInner(context: common.UIAbilityContext, site: GallerySite,
  scanPublicArchives: boolean): Promise<DownloadRestoreResult> {
  await ehDownloadStore.load(context);
  const archives: DownloadZipImportResult = scanPublicArchives ?
    await importPublicDownloadArchives(context, site) : emptyZipImportResult();
  const restored = ehDownloadFileStore.restoreDownloadedGalleries(context);
  // 这里是纯登记：磁盘上有、记录里没有的图册补进列表。
  // 已有记录一律不动 —— 不重建队列、不重算状态、不改进度、不刷新元数据、不联网。
  let added = 0;
  let skipped = 0;
  let migrated = 0;
  let localOnly = 0;
  let totalBytes = 0;
  for (let i = 0; i < restored.length; i++) {
    const source = restored[i];
    logScan('scan dir=' + pathBaseName(source.directory) + ' images=' + source.finished.toString() +
      ' total=' + source.total.toString() + ' gid=' + source.gallery.gid.toString() +
      ' token=' + (source.gallery.token.length > 0 ? 'yes' : 'no'));
    const existing = source.gallery.gid > 0 ? findDownloadItem(source.gallery.gid) : null;
    if (existing !== null) {
      logScan('  -> skip (record exists gid=' + source.gallery.gid.toString() + ')');
      // 记录已在，只修正指向已失效目录的路径，其余字段一律不动。
      if (!pathExists(existing.archiveUri)) {
        ehDownloadStore.setStorage(existing.gid, source.directory, source.fileSize);
      }
      skipped++;
      continue;
    }
    if (source.gallery.token.length > 0) {
      const item = ehDownloadStore.addGallery(source.gallery, '', directoryModifiedTimeMs(source.directory));
      if (item === null) {
        continue;
      }
      const total = Math.max(source.total, source.finished);
      ehDownloadStore.setState(item.gid, total > 0 && source.finished >= total ?
        DownloadState.Finish : DownloadState.None);
      ehDownloadStore.setProgress(item.gid, source.finished, total,
        source.finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
      ehDownloadStore.setStorage(item.gid, source.directory, source.fileSize);
      totalBytes += source.fileSize;
      if (source.migrated === true) {
        migrated++;
      }
      added++;
      continue;
    }
    // 没有元数据、也匹配不到服务器：登记为本地图档，用目录名和本地缩略图显示。
    const title = source.gallery.title.length > 0 ? source.gallery.title : pathBaseName(source.directory);
    if (ehDownloadStore.hasLocalGalleryTitle(title)) {
      logScan('  -> skip (same title already registered)');
      skipped++;
      continue;
    }
    const thumb = ensureLocalThumbnail(context, source.directory, title);
    const localItem = ehDownloadStore.addLocalGallery(title, source.directory, thumb, source.finished,
      source.fileSize, directoryModifiedTimeMs(source.directory));
    if (localItem === null) {
      continue;
    }
    totalBytes += source.fileSize;
    localOnly++;
    added++;
  }
  await ehDownloadStore.save(context);
  flushScanLog(context, 'restore scan: dirs=' + restored.length.toString() + ' added=' + added.toString() +
    ' skipped=' + skipped.toString() + ' localOnly=' + localOnly.toString());
  return {
    restored: restored.length,
    added: added,
    updated: 0,
    skipped: skipped,
    migrated: migrated,
    localOnly: localOnly,
    totalBytes: totalBytes,
    metadataRebuilt: 0,
    metadataFetched: 0,
    archives: archives
  };
}

function emptyZipImportResult(): DownloadZipImportResult {
  return {
    found: 0,
    processed: 0,
    skipped: 0,
    processedPaths: [],
    importedGalleries: []
  };
}

function findDownloadItem(gid: number): DownloadInfo | null {
  const items = ehDownloadStore.getItems();
  for (let i = 0; i < items.length; i++) {
    if (items[i].gid === gid) {
      return items[i];
    }
  }
  return null;
}

function pathExists(path: string): boolean {
  if (path.length === 0) {
    return false;
  }
  try {
    fs.accessSync(path);
    return true;
  } catch (_error) {
    return false;
  }
}

function listPublicZipFiles(context: common.UIAbilityContext): string[] {
  try {
    const root = ehDownloadFileStore.publicArchiveDownloadRoot(context);
    const names = fs.listFileSync(root);
    const paths: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const path = root + '/' + names[i];
      if (names[i].toLowerCase().endsWith(ZIP_EXTENSION) && !isDirectory(path)) {
        paths.push(path);
      }
    }
    paths.sort();
    return paths;
  } catch (error) {
    return [];
  }
}

function filterZipFiles(paths: string[]): string[] {
  const filtered: string[] = [];
  for (let i = 0; i < paths.length; i++) {
    if (paths[i].toLowerCase().endsWith(ZIP_EXTENSION) && exists(paths[i]) && !isDirectory(paths[i])) {
      filtered.push(paths[i]);
    }
  }
  return filtered;
}

async function importOneArchive(context: common.UIAbilityContext, zipPath: string, site: GallerySite,
  client: EhHttpClient, seedGallery?: GalleryInfo): Promise<RestoredDownloadGallery[]> {
  const workRoot = context.cacheDir + '/download_zip_import_' + Date.now().toString() + '_' +
    Math.floor(Math.random() * 100000).toString();
  const sandboxZip = workRoot + '/archive.zip';
  const extractedRoot = workRoot + '/extracted';
  removeDirectoryTree(workRoot);
  ensureDirectory(extractedRoot);
  try {
    // 先量体积再决定是否复制：旧顺序是先把整个 ZIP 拷进缓存再判断大小，
    // 几百 MB 的包在主线程同步复制就是几秒白卡（B-01 的 ZIP 分支）。
    let compressedSize = 0;
    try {
      compressedSize = fs.statSync(zipPath).size;
    } catch (error) {
      return [];
    }
    if (compressedSize <= 0) {
      return [];
    }
    const originalSize = await zlib.getOriginalSize(zipPath);
    if (originalSize <= 0 || originalSize > MAX_ZIP_UNCOMPRESSED_BYTES) {
      return [];
    }
    fs.copyFileSync(zipPath, sandboxZip);
    const options: zlib.Options = {
      pathSeparatorStrategy: zlib.PathSeparatorStrategy.PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH
    };
    await zlib.decompressFile(sandboxZip, extractedRoot, options);
    const metadataRoots: string[] = [];
    findMetadataRoots(extractedRoot, 0, metadataRoots);
    if (metadataRoots.length > 0) {
      return importMetadataRoots(context, metadataRoots);
    }

    const gid = galleryIdFromArchiveName(pathBaseName(zipPath));
    if (gid <= 0) {
      return [];
    }
    const imageRoot = findSingleImageRoot(extractedRoot);
    if (imageRoot.length === 0) {
      return [];
    }
    const gallery = await resolveArchiveGallery(client, site, gid, pathBaseName(zipPath), seedGallery);
    if (gallery === null || gallery.token.length === 0) {
      return [];
    }
    const target = ehDownloadFileStore.importGalleryDirectory(context, imageRoot, gallery);
    const restored = ehDownloadFileStore.inspectRestoredGalleryDirectory(target);
    return restored === null ? [] : [restored];
  } catch (error) {
    return [];
  } finally {
    removeDirectoryTree(workRoot);
  }
}

function importMetadataRoots(context: common.UIAbilityContext, roots: string[]): RestoredDownloadGallery[] {
  const imported: RestoredDownloadGallery[] = [];
  for (let i = 0; i < roots.length; i++) {
    const source = ehDownloadFileStore.inspectRestoredGalleryDirectory(roots[i]);
    if (source === null || source.gallery.gid <= 0 || source.gallery.token.length === 0) {
      continue;
    }
    const target = ehDownloadFileStore.importGalleryDirectory(context, roots[i], source.gallery);
    const restored = ehDownloadFileStore.inspectRestoredGalleryDirectory(target);
    if (restored !== null) {
      appendUniqueRestored(imported, [restored]);
    }
  }
  return imported;
}

function findMetadataRoots(directory: string, depth: number, roots: string[]): void {
  if (depth > MAX_METADATA_SEARCH_DEPTH || !isDirectory(directory)) {
    return;
  }
  if (ehDownloadFileStore.inspectRestoredGalleryDirectory(directory) !== null) {
    roots.push(directory);
    return;
  }
  try {
    const names = fs.listFileSync(directory);
    for (let i = 0; i < names.length; i++) {
      const child = directory + '/' + names[i];
      if (isDirectory(child)) {
        findMetadataRoots(child, depth + 1, roots);
      }
    }
  } catch (error) {
  }
}

function findSingleImageRoot(root: string): string {
  const candidates: string[] = [];
  collectImageRoots(root, 0, candidates);
  return candidates.length === 1 ? candidates[0] : '';
}

function collectImageRoots(directory: string, depth: number, roots: string[]): void {
  if (depth > MAX_METADATA_SEARCH_DEPTH || !isDirectory(directory)) {
    return;
  }
  let imageCount = 0;
  try {
    const names = fs.listFileSync(directory);
    for (let i = 0; i < names.length; i++) {
      if (isSupportedImageFile(names[i])) {
        imageCount++;
      }
    }
    if (imageCount > 0) {
      roots.push(directory);
      return;
    }
    for (let i = 0; i < names.length; i++) {
      const child = directory + '/' + names[i];
      if (isDirectory(child)) {
        collectImageRoots(child, depth + 1, roots);
      }
    }
  } catch (error) {
  }
}

async function resolveArchiveGallery(client: EhHttpClient, site: GallerySite,
  gid: number, archiveName: string, seedGallery?: GalleryInfo): Promise<GalleryInfo | null> {
  if (seedGallery !== undefined && seedGallery.gid === gid && seedGallery.token.length > 0) {
    return seedGallery;
  }
  const local = findLocalGallery(gid);
  if (local !== null && local.token.length > 0) {
    return local;
  }

  const candidates = gallerySiteCandidates(site);
  const gidResult = await searchGalleryCandidates(client, candidates, 'gid:' + gid.toString(), gid);
  if (gidResult !== null) {
    return gidResult;
  }
  let title = archiveSearchTitle(archiveName, gid);
  if (title.length > 120) {
    title = title.substring(0, 120).trim();
  }
  if (title.length <= 0) {
    return null;
  }
  return searchGalleryCandidates(client, candidates, title, gid);
}

async function searchGalleryCandidates(client: EhHttpClient, sites: GallerySite[], keyword: string,
  gid: number): Promise<GalleryInfo | null> {
  for (let i = 0; i < sites.length; i++) {
    const gallery = await searchGallery(client, sites[i], keyword, gid);
    if (gallery !== null) {
      return gallery;
    }
  }
  return null;
}

function findLocalGallery(gid: number): GalleryInfo | null {
  const downloads = ehDownloadStore.getItems();
  for (let i = 0; i < downloads.length; i++) {
    if (downloads[i].gid === gid) {
      return downloads[i];
    }
  }
  const history = ehHistoryStore.getItems();
  for (let i = 0; i < history.length; i++) {
    if (history[i].gid === gid) {
      return history[i];
    }
  }
  return null;
}

async function searchGallery(client: EhHttpClient, site: GallerySite, keyword: string,
  gid: number): Promise<GalleryInfo | null> {
  const builder = new ListUrlBuilder();
  builder.keyword = keyword;
  const result: GalleryListLoadResult = await client.loadGalleryList(builder, site);
  if (!result.ok) {
    return null;
  }
  for (let i = 0; i < result.galleries.length; i++) {
    if (result.galleries[i].gid === gid && result.galleries[i].token.length > 0) {
      return result.galleries[i];
    }
  }
  return null;
}

function galleryIdFromArchiveName(name: string): number {
  const match = /\((\d{4,})\)\s*\.zip$/i.exec(name);
  if (match === null) {
    return 0;
  }
  const gid = Number.parseInt(match[1], 10);
  return Number.isNaN(gid) ? 0 : gid;
}

function archiveSearchTitle(name: string, gid: number): string {
  let title = name.replace(/\.zip$/i, '');
  title = title.replace(new RegExp('\\s*\\(' + gid.toString() + '\\)\\s*$'), '');
  title = title.replace(/^\[\d{4}(?:[.\-]\d{1,2})?\]\s*/, '');
  return title.trim();
}

function appendUniqueRestored(target: RestoredDownloadGallery[], source: RestoredDownloadGallery[]): void {
  for (let i = 0; i < source.length; i++) {
    let index = -1;
    for (let j = 0; j < target.length; j++) {
      if (target[j].gallery.gid === source[i].gallery.gid) {
        index = j;
        break;
      }
    }
    if (index >= 0) {
      target[index] = source[i];
    } else {
      target.push(source[i]);
    }
  }
}

function isSupportedImageFile(name: string): boolean {
  const lower = name.toLowerCase();
  return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
    lower.endsWith('.webp') || lower.endsWith('.gif');
}

function pathBaseName(path: string): string {
  const normalized = path.replace(/\\/g, '/');
  const slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}

function removeDirectoryTree(path: string): void {
  try {
    const stat = fs.statSync(path);
    if (!stat.isDirectory()) {
      fs.unlinkSync(path);
      return;
    }
    const names = fs.listFileSync(path);
    for (let i = 0; i < names.length; i++) {
      removeDirectoryTree(path + '/' + names[i]);
    }
    fs.rmdirSync(path);
  } catch (error) {
  }
}
