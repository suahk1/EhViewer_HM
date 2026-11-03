import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryTagGroup } from '../model/GalleryModels';
import {
  ReaderPageTranslation,
  cloneReaderPageTranslation,
  cloneReaderPageTranslations
} from '../model/ReaderTranslationModels';
import { parseGalleryPageUrl } from './GalleryPageParser';
import { appSettingsStore } from './AppSettingsStore';
import {
  ensureDirectory,
  exists,
  isDirectory,
  removeFileQuietly,
  writeTextFile, fileSize} from '../shared/FileUtils';
import {
  cloneGalleryTagGroups,
  cloneStringArray,
  galleryDetailLanguage,
  galleryDetailTags
} from '../shared/GalleryTagSupport';

interface GalleryMetadata {
  version: number;
  gid: number;
  token: string;
  title: string;
  titleJpn: string;
  thumb: string;
  category: number;
  posted: string;
  uploader: string;
  rating: number;
  pages: number;
  previewPages: number;
  savedAt: number;
  simpleLanguage?: string;
  simpleTags?: string[];
  tagList?: string[];
  detailTags?: GalleryTagGroup[];
  detailLanguage?: string;
  language?: string;
  previewSet?: GalleryPreview[];
  readerTranslations?: ReaderPageTranslation[];
}

interface AndroidSpiderInfo {
  gid: number;
  token: string;
  pages: number;
  previewPages: number;
  previewPerPage: number;
}

interface RestoredGalleryData {
  gallery: GalleryInfo;
  total: number;
}

interface PageImageRenamePlan {
  temporaryPath: string;
  pageIndex: number;
  extension: string;
}

export interface RestoredDownloadGallery {
  gallery: GalleryInfo;
  directory: string;
  sourceDirectory?: string;
  fileSize: number;
  finished: number;
  total: number;
  migrated?: boolean;
}

export interface DownloadDirectoryScanResult {
  directories: number;
  files: number;
  bytes: number;
}

export interface DownloadMigrationResult extends DownloadDirectoryScanResult {
  cleanupIncomplete: boolean;
}

interface MigratedDownloadFile {
  source: string;
  target: string;
  size: number;
  mtime: number;
}

export type DownloadMigrationPhase = 'scanning' | 'copying' | 'cleaning';

export interface DownloadMigrationProgress {
  phase: DownloadMigrationPhase;
  files: number;
  bytes: number;
  totalFiles: number;
  totalBytes: number;
}

interface DownloadMigrationProgressState {
  files: number;
  bytes: number;
  totalFiles: number;
  totalBytes: number;
  lastReportedAt: number;
  copiedFiles: MigratedDownloadFile[];
  copiedDirectories: string[];
  onProgress?: (progress: DownloadMigrationProgress) => void;
}

export interface DownloadZipExportResult {
  path: string;
  folders: number;
  files: number;
  bytes: number;
}

export const DOWNLOAD_LOCATION_APP_FILES: string = 'App files';
export const DOWNLOAD_LOCATION_DOWNLOADS: string = 'Downloads';

const SUPPORTED_IMAGE_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
// 按页数兜底匹配时的标题前缀长度：太短会撞，太长扛不住分卷后缀差异。
const LOCAL_DIR_PREFIX_MIN: number = 40;
const ANDROID_SPIDER_INFO_FILENAME: string = '.ehviewer';
const OHOS_METADATA_FILENAME: string = '.ehviewer.json';

export class EhDownloadFileStore {
  appDownloadRoot(context: common.UIAbilityContext): string {
    return context.filesDir + '/downloads';
  }

  rootForLocation(context: common.UIAbilityContext, location: string): string {
    if (normalizeDownloadLocation(location) === DOWNLOAD_LOCATION_DOWNLOADS) {
      return this.publicDownloadRoot(context);
    }
    return this.appDownloadRoot(context);
  }

  publicDownloadRoot(_context: common.UIAbilityContext): string {
    const pickedRoot = appSettingsStore.getValue('download_public_root_path', '');
    if (pickedRoot.length > 0) {
      const normalized = normalizePublicDownloadRoot(pickedRoot);
      if (normalized !== pickedRoot) {
        if (migrateDuplicatePublicDownloadRoot(pickedRoot, normalized)) {
          appSettingsStore.setValue('download_public_root_path', normalized);
          return normalized;
        }
        return pickedRoot;
      }
      return normalized;
    }
    throw new Error('Download directory access needs picker selection');
  }

  publicArchiveDownloadRoot(context: common.UIAbilityContext): string {
    const galleryRoot = this.publicDownloadRoot(context);
    if (pathBaseName(galleryRoot).toLowerCase() !== 'ehviewer') {
      return galleryRoot;
    }
    const root = parentPath(galleryRoot);
    return root.length > 0 ? root : galleryRoot;
  }

  rememberPublicDownloadRoot(root: string): void {
    const normalized = normalizePublicDownloadRoot(root);
    if (normalized.length > 0) {
      appSettingsStore.setValue('download_public_root_path', normalized);
    }
  }

  canUseLocation(context: common.UIAbilityContext, location: string): boolean {
    try {
      ensureDirectory(this.rootForLocation(context, location));
      return true;
    } catch (error) {
      return false;
    }
  }

  async migrateDownloadLocation(context: common.UIAbilityContext, fromLocation: string,
    toLocation: string, onProgress?: (progress: DownloadMigrationProgress) => void):
    Promise<DownloadMigrationResult> {
    const source = normalizePath(this.rootForLocation(context, fromLocation));
    const target = normalizePath(this.rootForLocation(context, toLocation));
    if (source.length === 0 || target.length === 0 || source === '/' || target === '/') {
      throw new Error('Invalid download migration directory');
    }
    if (source === target || !exists(source)) {
      ensureDirectory(target);
      return { directories: 0, files: 0, bytes: 0, cleanupIncomplete: false };
    }
    if (source.startsWith(target + '/') || target.startsWith(source + '/')) {
      throw new Error('Download migration directories must not overlap');
    }
    ensureDirectory(target);
    if (onProgress !== undefined) {
      onProgress({ phase: 'scanning', files: 0, bytes: 0, totalFiles: 0, totalBytes: 0 });
    }
    const total = await scanDirectoryTreeAsync(source);
    const progressState: DownloadMigrationProgressState = {
      files: 0,
      bytes: 0,
      totalFiles: total.files,
      totalBytes: total.bytes,
      lastReportedAt: 0,
      copiedFiles: [],
      copiedDirectories: [],
      onProgress: onProgress
    };
    reportDownloadMigrationProgress(progressState, true);
    const copied = await copyDirectoryTreeAsync(source, target, progressState);
    if (onProgress !== undefined) {
      onProgress({
        phase: 'cleaning',
        files: copied.files,
        bytes: copied.bytes,
        totalFiles: total.files,
        totalBytes: total.bytes
      });
    }
    // Picker grants access to the contents, not necessarily deletion of the selected root.
    // Cleanup failures must not invalidate a fully copied destination or keep the old location active.
    const cleanupIncomplete = await cleanupMigratedDownloadFiles(progressState, source);
    return { directories: copied.directories, files: copied.files, bytes: copied.bytes,
      cleanupIncomplete: cleanupIncomplete };
  }

  // 种子归档目录：跟随「下载位置」设置，和画廊下载落在同一棵树里
  torrentsDirectory(context: common.UIAbilityContext): string {
    const dir = this.downloadRoot(context) + '/torrents';
    ensureDirectory(dir);
    return dir;
  }

  // 交给其它 App 的种子必须放在公共目录（沙箱路径外部应用读不到）；未配置公共目录返回空串
  shareableTorrentsDirectory(context: common.UIAbilityContext): string {
    let root = '';
    try {
      root = this.publicDownloadRoot(context);
    } catch (error) {
      return '';
    }
    if (root.length === 0) {
      return '';
    }
    const dir = root + '/torrents';
    ensureDirectory(dir);
    return dir;
  }

  // 判断某个路径是否落在应用沙箱里（外部 App 读不到）
  isAppPrivatePath(context: common.UIAbilityContext, path: string): boolean {
    const appRoot = this.appDownloadRoot(context);
    return appRoot.length > 0 && normalizePath(path).indexOf(normalizePath(appRoot)) === 0;
  }

  galleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const root = this.downloadRoot(context);
    // 本地图档没有 gid，目录名直接用标题，与 localGalleryDirectory 的命名保持一致。
    // 阅读器只拿到 GalleryInfo（没有 archiveUri），必须能靠这条规则重新找到目录。
    if (gallery.token.length === 0) {
      return root + '/' + sanitizePathSegment(gallery.title);
    }
    return root + '/' + sanitizePathSegment(gallery.gid.toString() + '-' + gallery.title);
  }

  downloadedGalleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const archiveUri = galleryArchiveUri(gallery);
    if (archiveUri.length > 0 && exists(archiveUri)) {
      return archiveUri;
    }
    if (archiveUri.length > 0) {
      // 文件夹选择器可能给出 /storage/Users/currentUser/... 这类应用内 fs.access 摸不到的
      // 虚拟路径。按最后一级目录名回当前下载根下找同名目录，老记录无需重新导入即可修复。
      const resolved = this.resolveArchiveUriIntoRoot(context, archiveUri);
      if (resolved.length > 0) {
        return resolved;
      }
    }
    const directory = this.galleryDirectory(context, gallery);
    if (exists(directory)) {
      return directory;
    }
    if (gallery.token.length === 0) {
      // 本地图档的真实目录常带真实 gid 前缀（4223710-标题），而记录里存的是合成 gid。
      // 按标题后缀回下载根下找，避免阅读器拿不到目录而永远转圈。
      const byTitle = this.findGalleryDirectoryByTitle(context, gallery.title);
      if (byTitle.length > 0) {
        return byTitle;
      }
      const byPages = this.findLocalDirectoryByPages(context, gallery);
      if (byPages.length > 0) {
        return byPages;
      }
    }
    return this.findGalleryDirectoryByGid(context, gallery.gid);
  }

  // 记录标题和磁盘目录名只差一个分卷后缀（"…2"）这类情况：标题前 40 字相同、页数在 15% 容差内、
  // 且候选唯一，才认。多个候选直接放弃，宁可报缺失也不绑错卷。
  private findLocalDirectoryByPages(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const title = sanitizePathSegment(gallery.title);
    if (title.length < LOCAL_DIR_PREFIX_MIN || gallery.pages <= 0) {
      return '';
    }
    const prefix = title.substring(0, LOCAL_DIR_PREFIX_MIN);
    const root = this.downloadRoot(context);
    let matched = '';
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const bare = sanitizePathSegment(stripLeadingGid(names[i]));
        if (!bare.startsWith(prefix)) {
          continue;
        }
        const count = sortedImagePaths(root + '/' + names[i]).length;
        if (count <= 0) {
          continue;
        }
        // 目录里可能少几张图，页数按容差比，避免差一两张就整本判缺失。
        const tolerance = Math.max(2, Math.round(gallery.pages * 0.15));
        if (Math.abs(count - gallery.pages) > tolerance) {
          continue;
        }
        if (matched.length > 0) {
          return '';
        }
        matched = root + '/' + names[i];
      }
    } catch (error) {
    }
    return matched;
  }

  // 在下载根下按标题匹配目录：完整相等或 "数字-标题" 后缀形式。
  private findGalleryDirectoryByTitle(context: common.UIAbilityContext, title: string): string {
    const target = sanitizePathSegment(title);
    if (target.length === 0) {
      return '';
    }
    const root = this.downloadRoot(context);
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (directoryNameMatches(name, target)) {
          return root + '/' + name;
        }
      }
    } catch (error) {
    }
    return '';
  }

  // 目录级查重：同一图册在根下有多份目录（典型是 "4223710-标题" 与 "标题" 并存）时，
  // 把分散的图片并到保留目录里，再删掉多余目录。保留图片最多的那份。
  mergeDuplicateDirectories(context: common.UIAbilityContext): DownloadDirectoryScanResult {
    const result: DownloadDirectoryScanResult = { directories: 0, files: 0, bytes: 0 };
    const root = this.downloadRoot(context);
    const groups: Map<string, string[]> = new Map();
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const path = root + '/' + names[i];
        if (!isDirectory(path)) {
          continue;
        }
        const identity = directoryIdentity(names[i]);
        if (identity.length === 0) {
          continue;
        }
        const bucket = groups.get(identity);
        if (bucket === undefined) {
          groups.set(identity, [path]);
        } else {
          bucket.push(path);
        }
      }
    } catch (error) {
      return result;
    }
    const keys = Array.from(groups.keys());
    for (let k = 0; k < keys.length; k++) {
      const paths = groups.get(keys[k]);
      if (paths === undefined || paths.length < 2) {
        continue;
      }
      let keeper = paths[0];
      let keeperImages = countImageFiles(keeper);
      for (let p = 1; p < paths.length; p++) {
        const images = countImageFiles(paths[p]);
        if (images > keeperImages) {
          keeper = paths[p];
          keeperImages = images;
        }
      }
      for (let p = 0; p < paths.length; p++) {
        const other = paths[p];
        if (other === keeper) {
          continue;
        }
        const otherImages = countImageFiles(other);
        if (otherImages > 0 && keeperImages > 0) {
          // 两份都有图：先把缺失的图片补进保留目录，避免直接删掉丢内容。
          copyDirectoryTree(other, keeper);
        }
        const stats = scanDirectoryTree(other);
        removeDirectoryTree(other);
        result.directories++;
        result.files += stats.files;
        result.bytes += stats.bytes;
      }
    }
    return result;
  }

  // 统一入口：给定记录（gid / 标题 / 已存路径），返回真实可读的图册目录；找不到返回 ''。
  // 供导入、对账、阅读共用，避免各处各写一套查找规则。
  resolveGalleryDirectory(context: common.UIAbilityContext, gid: number, title: string, archiveUri: string): string {
    if (archiveUri.length > 0 && isDirectory(archiveUri)) {
      return archiveUri;
    }
    if (archiveUri.length > 0) {
      const resolved = this.resolveArchiveUriIntoRoot(context, archiveUri);
      if (resolved.length > 0) {
        return resolved;
      }
    }
    const byGid = this.findGalleryDirectoryByGid(context, gid);
    if (byGid.length > 0) {
      return byGid;
    }
    const byTitle = this.findGalleryDirectoryByTitle(context, title);
    if (byTitle.length > 0) {
      return byTitle;
    }
    return '';
  }

  // 把虚拟 archiveUri 映射回真实下载根：按目录名在下载根下找同名目录。
  // 目录名全局唯一（扫描登记时已去重），命中即可信。
  private resolveArchiveUriIntoRoot(context: common.UIAbilityContext, archiveUri: string): string {
    const name = pathBaseName(archiveUri);
    if (name.length === 0 || name === '.' || name === '..') {
      return '';
    }
    const root = this.downloadRoot(context);
    const candidate = root + '/' + name;
    if (isDirectory(candidate)) {
      return candidate;
    }
    // archiveUri 记录的是被截断过的目录名（长标题会在 120 字符处切断），
    // 直接拼一定不存在，按去 gid 前缀后的前缀在根目录里找回真实目录。
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        if (directoryNameMatches(names[i], sanitizePathSegment(name))) {
          const resolved = root + '/' + names[i];
          if (isDirectory(resolved)) {
            return resolved;
          }
        }
      }
    } catch (error) {
    }
    return '';
  }

  async exportGalleriesZip(context: common.UIAbilityContext, galleries: GalleryInfo[],
    outputPath: string = ''): Promise<DownloadZipExportResult> {
    if (galleries.length <= 0) {
      throw new Error('No downloads selected');
    }

    const zipPath = outputPath.length > 0 ? outputPath :
      uniqueZipPath(this.zipExportRoot(context), 'EhViewer_downloads_' + zipTimestamp() + '.zip');
    const zipRoot = parentPath(zipPath);
    if (zipRoot.length > 0) {
      ensureDirectory(zipRoot);
    }
    const stagingRoot = context.cacheDir + '/download_zip_export_' + Date.now().toString();
    removeDirectoryTree(stagingRoot);
    ensureDirectory(stagingRoot);

    let folders = 0;
    let files = 0;
    try {
      for (let i = 0; i < galleries.length; i++) {
        const source = this.downloadedGalleryDirectory(context, galleries[i]);
        if (source.length === 0 || !isDirectory(source)) {
          continue;
        }
        const target = uniqueChildPath(stagingRoot, pathBaseName(source));
        const copied = copyDirectoryTree(source, target);
        if (copied.files > 0) {
          folders++;
          files += copied.files;
        } else {
          removeDirectoryTree(target);
        }
      }

      if (folders <= 0 || files <= 0) {
        throw new Error('Selected downloaded folders are missing');
      }

      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      };
      try {
        removeFileQuietly(zipPath);
        await zlib.compressFile(stagingRoot, zipPath, options);
      } catch (error) {
        throw new Error('Zip compression failed: ' + String(error));
      }
      const bytes = this.statFileSize(zipPath);
      return {
        path: zipPath,
        folders: folders,
        files: files,
        bytes: bytes
      };
    } finally {
      removeDirectoryTree(stagingRoot);
    }
  }

  findExistingGalleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const candidates: string[] = [];
    const archiveUri = galleryArchiveUri(gallery);
    appendDirectoryCandidate(candidates, archiveUri);
    appendDirectoryCandidate(candidates, this.galleryDirectory(context, gallery));

    const root = this.downloadRoot(context);
    const prefix = gallery.gid.toString() + '-';
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        if (names[i].startsWith(prefix)) {
          appendDirectoryCandidate(candidates, root + '/' + names[i]);
        }
      }
    } catch (error) {
    }

    let best = '';
    let bestImages = -1;
    let bestBytes = -1;
    for (let i = 0; i < candidates.length; i++) {
      const images = countImageFiles(candidates[i]);
      const bytes = this.directorySizeByPath(candidates[i]);
      if (images > bestImages || (images === bestImages && bytes > bestBytes)) {
        best = candidates[i];
        bestImages = images;
        bestBytes = bytes;
      }
    }
    return best;
  }

  prepareGallery(context: common.UIAbilityContext, detail: GalleryDetail, existingDirectory: string = ''): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    const target = this.galleryDirectory(context, detail);
    const source = existingDirectory.length > 0 && isDirectory(existingDirectory) ? existingDirectory : target;
    const directory = this.moveGalleryToCurrentDirectory(root, detail.gid, source, target);
    ensureDirectory(directory);
    normalizeKnownGalleryImageNames(directory);
    this.rewriteGalleryMetadataByDirectory(directory, detail);
    return directory;
  }

  rewriteGalleryMetadata(context: common.UIAbilityContext, detail: GalleryDetail): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    const directory = this.galleryDirectory(context, detail);
    ensureDirectory(directory);
    this.rewriteGalleryMetadataByDirectory(directory, detail);
    return directory;
  }

  private rewriteGalleryMetadataByDirectory(directory: string, detail: GalleryDetail): void {
    this.rewriteGalleryMetadataForDirectory(directory, detail);
  }

  rewriteGalleryMetadataForDirectory(directory: string, gallery: GalleryInfo): void {
    const previous = readMetadata(directory + '/' + OHOS_METADATA_FILENAME);
    const metadata = createMetadata(gallery, previous === null ? undefined : previous.readerTranslations);
    writeTextFile(directory + '/' + OHOS_METADATA_FILENAME, JSON.stringify(metadata));
    const detail = gallery as GalleryDetail;
    if (detail.previewSet !== undefined && Array.isArray(detail.previewSet)) {
      writeTextFile(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfo(detail));
    } else {
      writeTextFile(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfoFromMetadata(metadata));
    }
  }

  getReaderTranslation(context: common.UIAbilityContext, gallery: GalleryInfo,
    pageIndex: number): ReaderPageTranslation | null {
    const directory = this.findExistingGalleryDirectory(context, gallery);
    if (directory.length === 0) {
      return null;
    }
    const metadata = readMetadata(directory + '/' + OHOS_METADATA_FILENAME);
    if (metadata === null || metadata.readerTranslations === undefined) {
      return null;
    }
    const translations = cloneReaderPageTranslations(metadata.readerTranslations);
    for (let i = 0; i < translations.length; i++) {
      if (translations[i].pageIndex === pageIndex) {
        return cloneReaderPageTranslation(translations[i]);
      }
    }
    return null;
  }

  setReaderTranslation(context: common.UIAbilityContext, gallery: GalleryInfo,
    translation: ReaderPageTranslation): boolean {
    const directory = this.findExistingGalleryDirectory(context, gallery);
    if (directory.length === 0) {
      return false;
    }
    const metadataPath = directory + '/' + OHOS_METADATA_FILENAME;
    const metadata = readMetadata(metadataPath);
    if (metadata === null) {
      return false;
    }
    const current = cloneReaderPageTranslations(metadata.readerTranslations);
    const next: ReaderPageTranslation[] = [];
    let replaced = false;
    for (let i = 0; i < current.length; i++) {
      if (current[i].pageIndex === translation.pageIndex) {
        next.push(cloneReaderPageTranslation(translation));
        replaced = true;
      } else {
        next.push(cloneReaderPageTranslation(current[i]));
      }
    }
    if (!replaced) {
      next.push(cloneReaderPageTranslation(translation));
    }
    next.sort((left: ReaderPageTranslation, right: ReaderPageTranslation) => left.pageIndex - right.pageIndex);
    metadata.readerTranslations = next;
    metadata.savedAt = Date.now();
    writeTextFile(metadataPath, JSON.stringify(metadata));
    return true;
  }

  savePageImage(context: common.UIAbilityContext, detail: GalleryDetail, page: GalleryPage, index: number,
    cachedPath: string, downloadDirectory: string = ''): string {
    const directory = downloadDirectory.length > 0 && isDirectory(downloadDirectory) ?
      downloadDirectory : this.galleryDirectory(context, detail);
    ensureDirectory(directory);
    const destination = directory + '/' + pageFileName(index, imageExtension(page, cachedPath));
    try {
      fs.copyFileSync(cachedPath, destination);
    } catch (error) {
      throw new Error(String(error));
    }
    return destination;
  }

  findPageImage(context: common.UIAbilityContext, gallery: GalleryInfo, index: number,
    downloadDirectory: string = ''): string {
    const directory = downloadDirectory.length > 0 && isDirectory(downloadDirectory) ?
      downloadDirectory : this.downloadedGalleryDirectory(context, gallery);
    // 本地图册直接按排序位置取页：目录里序号可能断号（下载漏页、用户删过一张），
    // 按序号猜会“第 3 页显示成第 4 页、第 4 页再来一次”，页码和内容整体错位。
    // 排序位置是连续的，总页数就是张数，翻到第 N 页永远是第 N 张。
    if (gallery.token.length === 0 && index >= 0) {
      const images = cachedImagePaths(directory);
      return index < images.length ? images[index] : '';
    }
    for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
      const path = directory + '/' + pageFileName(index, SUPPORTED_IMAGE_EXTENSIONS[i]);
      if (exists(path)) {
        return path;
      }
    }
    return '';
  }

  // 判断已有封面文件是否还在：不在才重新生成，避免每次遍历都做文件 stat。
  localThumbExists(path: string): boolean {
    return path.length > 0 && exists(path);
  }

  // 目录内容被改动后主动失效，否则 3 秒内还会返回旧列表。
  invalidateDirectoryScan(directory: string): void {
    directoryScanCache.delete(directory);
  }

  removePageImage(context: common.UIAbilityContext, gallery: GalleryInfo, index: number): DownloadDirectoryScanResult {
    const path = this.findPageImage(context, gallery, index);
    if (path.length === 0) {
      return { directories: 0, files: 0, bytes: 0 };
    }
    return removeDirectoryTree(path);
  }

  listPageImages(context: common.UIAbilityContext, gallery: GalleryInfo): string[] {
    const directory = this.downloadedGalleryDirectory(context, gallery);
    const images: string[] = [];
    try {
      const names = galleryImageNames(fs.listFileSync(directory));
      names.sort((left: string, right: string) => left.localeCompare(right, undefined, { numeric: true }));
      for (let i = 0; i < names.length; i++) {
        images.push(directory + '/' + names[i]);
      }
    } catch (error) {
    }
    return images;
  }

  // 本地图档按目录直读页文件：和阅读器取页共用同一套自然排序，
  // 页数、首图、预览顺序才不会出现 "1, 10, 2" 这种字典序错位。
  listLocalPageImages(directory: string): string[] {
    if (directory.length === 0 || !isDirectory(directory)) {
      return [];
    }
    return cachedImagePaths(directory);
  }

  prepareTransferredGallery(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    const directory = this.galleryDirectory(context, gallery);
    ensureDirectory(directory);
    this.rewriteGalleryMetadataForDirectory(directory, gallery);
    return directory;
  }

  writeTransferredImageChunk(directory: string, fileName: string, offset: number, data: ArrayBuffer): number {
    const safeName = pathBaseName(fileName);
    if (safeName !== fileName || !isSupportedImageFile(safeName) || offset < 0) {
      throw new Error('Invalid transferred image path');
    }
    ensureDirectory(directory);
    const mode = offset === 0 ?
      fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE :
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE;
    let fd = -1;
    try {
      const file = fs.openSync(directory + '/' + safeName, mode);
      fd = file.fd;
      return fs.writeSync(fd, data, { offset: offset, length: data.byteLength });
    } catch (error) {
      throw new Error('Unable to write transferred image');
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (error) {
        }
      }
    }
  }

  listPageImageSlots(context: common.UIAbilityContext, gallery: GalleryInfo, total: number): string[] {
    const count = Math.max(0, total);
    const images: string[] = [];
    for (let i = 0; i < count; i++) {
      images.push(this.findPageImage(context, gallery, i));
    }
    return images;
  }

  directorySize(context: common.UIAbilityContext, gallery: GalleryInfo): number {
    const directory = this.downloadedGalleryDirectory(context, gallery);
    return this.directorySizeByPath(directory);
  }

  restoreDownloadedGalleries(context: common.UIAbilityContext): RestoredDownloadGallery[] {
    const currentLocation = normalizeDownloadLocation(appSettingsStore.getValue('download_location', DOWNLOAD_LOCATION_APP_FILES));
    if (currentLocation === DOWNLOAD_LOCATION_APP_FILES) {
      return this.restoreAppFileDownloads(context);
    }
    return this.scanRestoredDownloadRoot(this.downloadRoot(context));
  }

  inspectRestoredGalleryDirectory(directory: string): RestoredDownloadGallery | null {
    return this.restoredItemFromDirectory(directory, false, '');
  }

  importGalleryDirectory(context: common.UIAbilityContext, source: string, gallery: GalleryInfo): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    const target = this.galleryDirectory(context, gallery);
    ensureDirectory(target);
    removeGalleryImages(target);
    copyDirectoryTree(source, target);
    normalizeGalleryImageNames(target);
    this.rewriteGalleryMetadataForDirectory(target, gallery);
    return target;
  }

  currentDownloadRoot(context: common.UIAbilityContext): string {
    return this.downloadRoot(context);
  }

  // 本地图档没有 gid，目录名直接用标题，避免出现假的 “数字-标题” 前缀。
  localGalleryDirectory(context: common.UIAbilityContext, title: string): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    return root + '/' + sanitizePathSegment(title);
  }

  importLocalGalleryDirectory(context: common.UIAbilityContext, source: string, title: string): string {
    const target = this.localGalleryDirectory(context, title);
    ensureDirectory(target);
    removeGalleryImages(target);
    copyDirectoryTree(source, target);
    normalizeGalleryImageNames(target);
    return target;
  }

  removeFiles(paths: string[]): number {
    let removed = 0;
    for (let i = 0; i < paths.length; i++) {
      if (!exists(paths[i]) || isDirectory(paths[i])) {
        continue;
      }
      try {
        fs.unlinkSync(paths[i]);
        removed++;
      } catch (error) {
      }
    }
    return removed;
  }

  removeGalleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): DownloadDirectoryScanResult {
    return removeDirectoryTree(this.downloadedGalleryDirectory(context, gallery));
  }

  scanRedundantDirectories(context: common.UIAbilityContext, keepGids: number[]): DownloadDirectoryScanResult {
    return scanRedundantDownloadDirectories(this.downloadRoot(context), keepGids, false);
  }

  async scanRedundantDirectoriesAsync(context: common.UIAbilityContext,
    keepGids: number[]): Promise<DownloadDirectoryScanResult> {
    const root = this.downloadRoot(context);
    let directories = 0;
    let files = 0;
    let bytes = 0;
    const retained = new Set<number>(keepGids);
    try {
      const names = await fs.listFile(root);
      for (let i = 0; i < names.length; i++) {
        const directory = root + '/' + names[i];
        const restored = await readRestoredGalleryAsync(directory, names[i]);
        if (restored === null || retained.has(restored.gallery.gid)) {
          continue;
        }
        try {
          const result = await scanDirectoryTreeAsync(directory);
          directories += result.directories;
          files += result.files;
          bytes += result.bytes;
        } catch (_error) {
          // Downloads can be moved or removed while their size is being refreshed.
        }
      }
    } catch (_error) {
    }
    return { directories: directories, files: files, bytes: bytes };
  }

  // keepGids：记录里的 gid；keepNames：记录绑定的目录名。
  // 本地图档的 gid 是合成号，和目录名里的真实 gid 对不上，必须靠 keepNames 兜住，
  // 否则「清理冗余」会把本地图册的目录当成孤儿删掉。
  cleanRedundantDirectories(context: common.UIAbilityContext, keepGids: number[],
    keepNames: string[] = []): DownloadDirectoryScanResult {
    return scanRedundantDownloadDirectories(this.downloadRoot(context), keepGids, true, keepNames);
  }

  directorySizeByPath(directory: string): number {
    let total = 0;
    try {
      const names = fs.listFileSync(directory);
      for (let i = 0; i < names.length; i++) {
        const path = directory + '/' + names[i];
        total += this.statFileSize(path);
      }
    } catch (error) {
    }
    return total;
  }

  statFileSize(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (error) {
      return 0;
    }
  }

  private downloadRoot(context: common.UIAbilityContext): string {
    return this.rootForLocation(context, appSettingsStore.getValue('download_location', DOWNLOAD_LOCATION_APP_FILES));
  }

  private moveGalleryToCurrentDirectory(root: string, gid: number, source: string, target: string): string {
    const normalizedSource = normalizePath(source);
    const normalizedTarget = normalizePath(target);
    if (normalizedSource !== normalizedTarget && isDirectory(normalizedSource)) {
      normalizeKnownGalleryImageNames(normalizedSource);
      if (isDirectory(normalizedTarget) && countImageFiles(normalizedTarget) === 0 &&
        countImageFiles(normalizedSource) > 0) {
        removeDirectoryTree(normalizedTarget);
      }
      if (!isDirectory(normalizedTarget) && !renameDirectory(normalizedSource, normalizedTarget)) {
        ensureDirectory(normalizedTarget);
        mergeGalleryDirectory(normalizedSource, normalizedTarget);
      } else if (isDirectory(normalizedTarget) && isDirectory(normalizedSource)) {
        mergeGalleryDirectory(normalizedSource, normalizedTarget);
      }
    }

    ensureDirectory(normalizedTarget);
    normalizeKnownGalleryImageNames(normalizedTarget);
    this.mergeOtherGalleryDirectories(root, gid, normalizedTarget);
    return normalizedTarget;
  }

  private mergeOtherGalleryDirectories(root: string, gid: number, target: string): void {
    const prefix = gid.toString() + '-';
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const candidate = normalizePath(root + '/' + names[i]);
        if (!names[i].startsWith(prefix) || candidate === target || !isDirectory(candidate)) {
          continue;
        }
        normalizeKnownGalleryImageNames(candidate);
        mergeGalleryDirectory(candidate, target);
      }
    } catch (error) {
    }
  }

  private zipExportRoot(context: common.UIAbilityContext): string {
    try {
      return this.publicArchiveDownloadRoot(context);
    } catch (error) {
      throw new Error('Zip export needs Downloads access. Set Settings > EH > Download location to Downloads first.');
    }
  }

  private findGalleryDirectoryByGid(context: common.UIAbilityContext, gid: number): string {
    const root = this.downloadRoot(context);
    const prefix = gid.toString() + '-';
    try {
      const names = fs.listFileSync(root);
      let best = '';
      for (let i = 0; i < names.length; i++) {
        const path = root + '/' + names[i];
        if (names[i].startsWith(prefix) && isDirectory(path) && names[i].length > best.length) {
          best = path;
        }
      }
      return best;
    } catch (error) {
      return '';
    }
  }

  private restoreAppFileDownloads(context: common.UIAbilityContext): RestoredDownloadGallery[] {
    const appRoot = this.appDownloadRoot(context);
    ensureDirectory(appRoot);
    const appItems = this.scanRestoredDownloadRoot(appRoot);
    const publicItems = this.scanPublicDownloadedGalleries(context);
    if (publicItems.length <= 0) {
      return appItems;
    }

    const merged: RestoredDownloadGallery[] = [];
    for (let i = 0; i < appItems.length; i++) {
      merged.push(appItems[i]);
    }

    for (let i = 0; i < publicItems.length; i++) {
      this.mergePublicDownloadIntoApp(appRoot, merged, publicItems[i]);
    }
    return merged;
  }

  private scanPublicDownloadedGalleries(context: common.UIAbilityContext): RestoredDownloadGallery[] {
    try {
      const publicRoot = this.publicDownloadRoot(context);
      return this.scanRestoredDownloadRoot(publicRoot);
    } catch (error) {
      return [];
    }
  }

  private mergePublicDownloadIntoApp(appRoot: string, appItems: RestoredDownloadGallery[],
    publicItem: RestoredDownloadGallery): void {
    // 本地图档没有 gid，不能按 gid 匹配，直接追加，避免误删同名的其他目录。
    const existingIndex = publicItem.gallery.gid > 0 ?
      restoredIndexByGid(appItems, publicItem.gallery.gid) : -1;
    if (existingIndex >= 0 && appItems[existingIndex].fileSize >= publicItem.fileSize) {
      removeDirectoryTree(publicItem.directory);
      return;
    }

    const target = uniqueChildPath(appRoot, pathBaseName(publicItem.directory));

    const copied = copyDirectoryTree(publicItem.directory, target);
    if (copied.files <= 0) {
      return;
    }
    removeDirectoryTree(publicItem.directory);
    if (existingIndex >= 0) {
      removeDirectoryTree(appItems[existingIndex].directory);
    }
    const migrated = this.restoredItemFromDirectory(target, true, publicItem.directory);
    if (migrated === null) {
      return;
    }
    if (existingIndex >= 0) {
      appItems[existingIndex] = migrated;
    } else {
      appItems.push(migrated);
    }
  }

  private scanRestoredDownloadRoot(root: string): RestoredDownloadGallery[] {
    const restored: RestoredDownloadGallery[] = [];
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const item = this.restoredItemFromDirectory(root + '/' + names[i], false, '');
        if (item !== null) {
          restored.push(item);
        }
      }
    } catch (error) {
    }
    return restored;
  }

  private restoredItemFromDirectory(directory: string, migrated: boolean,
    sourceDirectory: string): RestoredDownloadGallery | null {
    const restoredGallery = readRestoredGallery(directory, pathBaseName(directory));
    if (restoredGallery === null) {
      return null;
    }
    return {
      gallery: restoredGallery.gallery,
      directory: directory,
      sourceDirectory: sourceDirectory.length > 0 ? sourceDirectory : undefined,
      fileSize: this.directorySizeByPath(directory),
      finished: countImageFiles(directory),
      total: Math.max(0, restoredGallery.total),
      migrated: migrated
    };
  }
}

function normalizePublicDownloadRoot(path: string): string {
  const normalized = normalizePath(path);
  const duplicateSuffix = '/ehviewer/ehviewer';
  if (normalized.toLowerCase().endsWith(duplicateSuffix)) {
    return normalized.substring(0, normalized.length - '/EhViewer'.length);
  }
  return normalized;
}

function migrateDuplicatePublicDownloadRoot(source: string, target: string): boolean {
  if (source === target || !isDirectory(source)) {
    return true;
  }
  try {
    ensureDirectory(target);
    const names = fs.listFileSync(source);
    for (let i = 0; i < names.length; i++) {
      const sourcePath = source + '/' + names[i];
      const targetPath = uniqueChildPath(target, names[i]);
      if (isDirectory(sourcePath)) {
        fs.moveDirSync(sourcePath, targetPath);
      } else {
        fs.moveFileSync(sourcePath, targetPath);
      }
    }
    fs.rmdirSync(source);
    return true;
  } catch (error) {
    return false;
  }
}

function restoredIndexByGid(items: RestoredDownloadGallery[], gid: number): number {
  for (let i = 0; i < items.length; i++) {
    if (items[i].gallery.gid === gid) {
      return i;
    }
  }
  return -1;
}

function scanRedundantDownloadDirectories(root: string, keepGids: number[], shouldRemove: boolean,
  keepNames: string[] = []): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const names = fs.listFileSync(root);
    for (let i = 0; i < names.length; i++) {
      const directory = root + '/' + names[i];
      const restoredGallery = readRestoredGallery(directory, names[i]);
      // gid 为 0 的是本地图档，清理冗余不能判断它是否已登记，一律保留。
      if (restoredGallery === null || restoredGallery.gallery.gid <= 0 ||
        containsNumber(keepGids, restoredGallery.gallery.gid) || containsName(keepNames, names[i])) {
        continue;
      }
      const result = shouldRemove ? removeDirectoryTree(directory) : scanDirectoryTree(directory);
      directories += result.directories;
      files += result.files;
      bytes += result.bytes;
    }
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

function normalizeDownloadLocation(location: string): string {
  return location === DOWNLOAD_LOCATION_DOWNLOADS ? DOWNLOAD_LOCATION_DOWNLOADS : DOWNLOAD_LOCATION_APP_FILES;
}

function createMetadata(gallery: GalleryInfo,
  readerTranslations: ReaderPageTranslation[] | undefined = undefined): GalleryMetadata {
  const detail = gallery as GalleryDetail;
  const tags = galleryDetailTags(gallery);
  const language = galleryDetailLanguage(gallery);
  return {
    version: 1,
    gid: gallery.gid,
    token: gallery.token,
    title: gallery.title,
    titleJpn: gallery.titleJpn === undefined ? '' : gallery.titleJpn,
    thumb: gallery.thumb === undefined ? '' : gallery.thumb,
    category: gallery.category,
    posted: gallery.posted === undefined ? '' : gallery.posted,
    uploader: gallery.uploader === undefined ? '' : gallery.uploader,
    rating: gallery.rating,
    pages: gallery.pages,
    previewPages: detail.previewPages === undefined ? 0 : detail.previewPages,
    savedAt: Date.now(),
    simpleLanguage: gallery.simpleLanguage,
    simpleTags: cloneStringArray(gallery.simpleTags),
    tagList: cloneStringArray(gallery.tagList),
    detailTags: cloneGalleryTagGroups(tags),
    detailLanguage: language,
    language: detail.language,
    previewSet: cloneGalleryPreviews(detail.previewSet),
    readerTranslations: cloneReaderPageTranslations(readerTranslations)
  };
}

function createAndroidSpiderInfo(detail: GalleryDetail): string {
  const lines: string[] = [];
  lines.push('VERSION2');
  lines.push('00000000');
  lines.push(detail.gid.toString());
  lines.push(detail.token);
  lines.push('1');
  lines.push(Math.max(0, detail.previewPages).toString());
  lines.push(previewPerPage(detail).toString());
  lines.push(Math.max(0, detail.pages).toString());
  for (let i = 0; i < detail.previewSet.length; i++) {
    const parsed = parseGalleryPageUrl(detail.previewSet[i].pageUrl);
    if (parsed !== null && parsed.pageToken.length > 0) {
      lines.push(parsed.pageIndex.toString() + ' ' + parsed.pageToken);
    }
  }
  return lines.join('\n') + '\n';
}

function previewPerPage(detail: GalleryDetail): number {
  if (detail.previewSet.length <= 0) {
    return 0;
  }
  if (detail.previewPages <= 1) {
    return detail.previewSet.length;
  }
  return Math.max(1, Math.ceil(detail.previewSet.length / detail.previewPages));
}

function readRestoredGallery(directory: string, directoryName: string): RestoredGalleryData | null {
  const metadata = readMetadata(directory + '/' + OHOS_METADATA_FILENAME);
  if (metadata !== null) {
    // 有元数据不等于有图：只带记录没带图片的目录、复制失败的空副本都会落到这里。
    // 目录里一张图都没有就不该登记成图册，否则列表里全是点开没内容的条目。
    if (countImageFiles(directory) <= 0) {
      return null;
    }
    writeTextFileQuietly(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfoFromMetadata(metadata));
    return {
      gallery: metadataToGallery(metadata),
      total: metadata.pages
    };
  }

  const oldJsonMetadata = readMetadata(directory + '/' + ANDROID_SPIDER_INFO_FILENAME);
  if (oldJsonMetadata !== null) {
    if (countImageFiles(directory) <= 0) {
      return null;
    }
    writeTextFileQuietly(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfoFromMetadata(oldJsonMetadata));
    writeTextFileQuietly(directory + '/' + OHOS_METADATA_FILENAME, JSON.stringify(oldJsonMetadata));
    return {
      gallery: metadataToGallery(oldJsonMetadata),
      total: oldJsonMetadata.pages
    };
  }

  const spiderInfo = readAndroidSpiderInfo(directory + '/' + ANDROID_SPIDER_INFO_FILENAME);
  if (spiderInfo === null) {
    // 无任何元数据文件：从目录名解析 gid，回退为“本地图片文件夹”。
    // 上层 rebuildRestoredDownloadMetadata 会按 gid 匹配已导入的历史/下载记录补全标题、token 等字段，
    // 因此即使 EH 服务器已删除该画廊，本地文件也能被扫描识别并显示名字。
    return restoredFromDirectoryNameFallback(directory, directoryName);
  }
  return {
    gallery: spiderInfoToGallery(spiderInfo, directoryName),
    total: spiderInfo.pages
  };
}

function restoredFromDirectoryNameFallback(directory: string, directoryName: string): RestoredGalleryData | null {
  const gid = galleryIdFromDirectoryName(directoryName);
  const images = countImageFiles(directory);
  if (images <= 0) {
    return null;
  }
  // 目录名里没有 gid 时不作废：当作本地图档登记（gid 0），标题取目录名。
  // 上层按 token 为空判断本地图档，再用合成 gid 入库。
  const localTitle = gid > 0 ? titleFromDirectoryName(directoryName, gid) : cleanedLocalTitle(directoryName);
  if (localTitle.length === 0) {
    return null;
  }
  return {
    gallery: {
      gid: gid > 0 ? gid : 0,
      token: '',
      title: localTitle,
      titleJpn: '',
      thumb: '',
      category: 0,
      posted: '',
      uploader: '',
      rating: 0,
      rated: false,
      pages: images,
      thumbWidth: 0,
      thumbHeight: 0,
      favoriteSlot: -1,
      favoriteName: ''
    },
    total: images
  };
}

function cleanedLocalTitle(directoryName: string): string {
  let title = directoryName.trim();
  title = title.replace(/^\[[^\]]*\]\s*/, '');
  title = title.replace(/\s*\(\d{4,}\)\s*$/, '');
  title = title.replace(/_/g, ' ').trim();
  return title.length > 0 ? title : directoryName.trim();
}

function galleryIdFromDirectoryName(name: string): number {
  const match = /^(\d{4,})/.exec(name);
  if (match === null) {
    return 0;
  }
  const gid = Number.parseInt(match[1], 10);
  return Number.isNaN(gid) ? 0 : gid;
}

// Statistics must neither migrate metadata nor block the UI with synchronous reads/writes.
async function readRestoredGalleryAsync(directory: string, directoryName: string): Promise<RestoredGalleryData | null> {
  for (const name of [OHOS_METADATA_FILENAME, ANDROID_SPIDER_INFO_FILENAME]) {
    try {
      const metadata = parseMetadata(await fs.readText(directory + '/' + name));
      if (metadata !== null) {
        return { gallery: metadataToGallery(metadata), total: metadata.pages };
      }
    } catch (_error) {
    }
  }
  try {
    const spiderInfo = parseAndroidSpiderInfo(await fs.readText(directory + '/' + ANDROID_SPIDER_INFO_FILENAME));
    return spiderInfo === null ? null : {
      gallery: spiderInfoToGallery(spiderInfo, directoryName), total: spiderInfo.pages
    };
  } catch (_error) {
    return null;
  }
}

function createAndroidSpiderInfoFromMetadata(metadata: GalleryMetadata): string {
  const lines: string[] = [];
  lines.push('VERSION2');
  lines.push('00000000');
  lines.push(metadata.gid.toString());
  lines.push(metadata.token);
  lines.push('1');
  lines.push(Math.max(0, metadata.previewPages).toString());
  lines.push('0');
  lines.push(Math.max(0, metadata.pages).toString());
  return lines.join('\n') + '\n';
}

function readMetadata(path: string): GalleryMetadata | null {
  try {
    return parseMetadata(fs.readTextSync(path));
  } catch (error) {
    return null;
  }
}

function parseMetadata(text: string): GalleryMetadata | null {
  try {
    const parsed = JSON.parse(text) as GalleryMetadata;
    if (parsed.gid <= 0 || parsed.token === undefined || parsed.token.length === 0 ||
      parsed.title === undefined || parsed.title.length === 0) {
      return null;
    }
    return parsed;
  } catch (error) {
    return null;
  }
}

function readAndroidSpiderInfo(path: string): AndroidSpiderInfo | null {
  try {
    return parseAndroidSpiderInfo(fs.readTextSync(path));
  } catch (error) {
    return null;
  }
}

function parseAndroidSpiderInfo(text: string): AndroidSpiderInfo | null {
  try {
    const lines = text.split(/\r?\n/);
    if (lines.length < 7) {
      return null;
    }
    let offset = 0;
    let version = 1;
    if (lines[0].startsWith('VERSION')) {
      version = parseInteger(lines[0].substring('VERSION'.length), -1);
      offset = 1;
    }
    if (version !== 1 && version !== 2) {
      return null;
    }
    if (lines.length <= offset + 6) {
      return null;
    }

    const gid = parseInteger(lines[offset + 1], -1);
    const token = lines[offset + 2];
    const previewPages = parseInteger(lines[offset + 4], 0);
    const previewPerPage = version === 2 ? parseInteger(lines[offset + 5], 0) : 0;
    const pages = parseInteger(lines[offset + 6], -1);
    if (gid <= 0 || token.length === 0 || pages <= 0) {
      return null;
    }
    return {
      gid: gid,
      token: token,
      pages: pages,
      previewPages: previewPages,
      previewPerPage: previewPerPage
    };
  } catch (error) {
    return null;
  }
}

function metadataToGallery(metadata: GalleryMetadata): GalleryInfo {
  return {
    gid: metadata.gid,
    token: metadata.token,
    title: metadata.title,
    titleJpn: metadata.titleJpn,
    thumb: metadata.thumb,
    category: metadata.category,
    posted: metadata.posted,
    uploader: metadata.uploader,
    rating: metadata.rating,
    rated: false,
    simpleLanguage: metadata.simpleLanguage,
    simpleTags: cloneStringArray(metadata.simpleTags),
    pages: metadata.pages,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -1,
    favoriteName: '',
    tagList: cloneStringArray(metadata.tagList),
    detailTags: cloneGalleryTagGroups(metadata.detailTags),
    detailLanguage: metadata.detailLanguage === undefined ? metadata.language : metadata.detailLanguage
  };
}

function cloneGalleryPreviews(previews: GalleryPreview[] | undefined): GalleryPreview[] | undefined {
  if (previews === undefined || !Array.isArray(previews)) {
    return undefined;
  }
  const cloned: GalleryPreview[] = [];
  for (let i = 0; i < previews.length; i++) {
    cloned.push({
      index: previews[i].index,
      pageUrl: previews[i].pageUrl,
      imageUrl: previews[i].imageUrl,
      width: previews[i].width,
      height: previews[i].height,
      xOffset: previews[i].xOffset,
      yOffset: previews[i].yOffset
    });
  }
  return cloned;
}

function spiderInfoToGallery(info: AndroidSpiderInfo, directoryName: string): GalleryInfo {
  return {
    gid: info.gid,
    token: info.token,
    title: titleFromDirectoryName(directoryName, info.gid),
    titleJpn: '',
    thumb: '',
    category: 0,
    posted: '',
    uploader: '',
    rating: 0,
    rated: false,
    pages: info.pages,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -1,
    favoriteName: ''
  };
}

function titleFromDirectoryName(name: string, gid: number): string {
  const prefix = gid.toString() + '-';
  if (name.startsWith(prefix) && name.length > prefix.length) {
    return name.substring(prefix.length);
  }
  return name.length > 0 ? name : gid.toString();
}

function parseInteger(value: string, fallback: number): number {
  const parsed = Number.parseInt(value);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function countImageFiles(directory: string): number {
  try {
    return galleryImageNames(fs.listFileSync(directory)).length;
  } catch (error) {
  }
  return 0;
}

function isSupportedImageFile(name: string): boolean {
  const lower = name.toLowerCase();
  for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
    if (lower.endsWith(SUPPORTED_IMAGE_EXTENSIONS[i])) {
      return true;
    }
  }
  return false;
}

function containsName(names: string[], target: string): boolean {
  for (let i = 0; i < names.length; i++) {
    if (names[i] === target) {
      return true;
    }
  }
  return false;
}

function containsNumber(values: number[], value: number): boolean {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === value) {
      return true;
    }
  }
  return false;
}

function appendDirectoryCandidate(candidates: string[], path: string): void {
  if (path.length === 0 || !isDirectory(path)) {
    return;
  }
  for (let i = 0; i < candidates.length; i++) {
    if (candidates[i] === path) {
      return;
    }
  }
  candidates.push(path);
}

function renameDirectory(source: string, target: string): boolean {
  if (source === target && isDirectory(source)) {
    return true;
  }
  try {
    fs.renameSync(source, target);
    return isDirectory(target);
  } catch (error) {
    return false;
  }
}

function mergeGalleryDirectory(source: string, target: string): boolean {
  if (source === target || !isDirectory(source)) {
    return true;
  }
  ensureDirectory(target);
  normalizeKnownGalleryImageNames(source);
  normalizeKnownGalleryImageNames(target);
  let complete = true;
  try {
    const names = fs.listFileSync(source);
    for (let i = 0; i < names.length; i++) {
      const sourcePath = source + '/' + names[i];
      if (names[i] === ANDROID_SPIDER_INFO_FILENAME || names[i] === OHOS_METADATA_FILENAME) {
        continue;
      }
      if (isDirectory(sourcePath)) {
        const childTarget = uniqueChildPath(target, names[i]);
        const sourceScan = scanDirectoryTree(sourcePath);
        const copied = copyDirectoryTree(sourcePath, childTarget);
        if (copied.files < sourceScan.files) {
          complete = false;
        }
        continue;
      }
      if (isSupportedImageFile(names[i])) {
        if (!mergeGalleryImageFile(sourcePath, target, names[i])) {
          complete = false;
        }
        continue;
      }
      const targetPath = exists(target + '/' + names[i]) ? uniqueChildPath(target, names[i]) : target + '/' + names[i];
      if (!copyFileVerified(sourcePath, targetPath)) {
        complete = false;
      }
    }
  } catch (error) {
    complete = false;
  }
  if (complete) {
    removeDirectoryTree(source);
  }
  return complete;
}

function mergeGalleryImageFile(sourcePath: string, targetDirectory: string, sourceName: string): boolean {
  const pageIndex = canonicalPageImageIndex(sourceName);
  let targetPath = targetDirectory + '/' + sourceName;
  if (pageIndex >= 0) {
    const existing = findCanonicalPageImage(targetDirectory, pageIndex);
    if (existing.length > 0) {
      if (fileSize(sourcePath) <= fileSize(existing)) {
        return true;
      }
      targetPath = targetDirectory + '/' + pageFileName(pageIndex, supportedImageExtension(sourceName));
      if (!copyFileVerified(sourcePath, targetPath)) {
        return false;
      }
      if (existing !== targetPath) {
        removeFileQuietly(existing);
      }
      return true;
    }
  } else if (exists(targetPath) && fileSize(sourcePath) <= fileSize(targetPath)) {
    return true;
  }
  return copyFileVerified(sourcePath, targetPath);
}

function copyFileVerified(source: string, target: string): boolean {
  try {
    fs.copyFileSync(source, target);
    return exists(target) && fileSize(target) === fileSize(source);
  } catch (error) {
    return false;
  }
}

function normalizeKnownGalleryImageNames(directory: string): void {
  try {
    const names = fs.listFileSync(directory).filter((name: string) => isSupportedImageFile(name));
    const numericNames: string[] = [];
    let zeroBasedPadded = false;
    let zeroBasedUnpadded = false;
    for (let i = 0; i < names.length; i++) {
      const number = numericImageFileNumber(names[i]);
      if (number < 0) {
        continue;
      }
      numericNames.push(names[i]);
      if (number === 0) {
        if (numericImageStemLength(names[i]) === 8) {
          zeroBasedPadded = true;
        } else {
          zeroBasedUnpadded = true;
        }
      }
    }

    const plans: PageImageRenamePlan[] = [];
    const marker = '.__ehviewer_normalize_' + Date.now().toString() + '_';
    for (let i = 0; i < numericNames.length; i++) {
      const number = numericImageFileNumber(numericNames[i]);
      const padded = numericImageStemLength(numericNames[i]) === 8;
      const zeroBased = padded ? zeroBasedPadded : zeroBasedUnpadded;
      const pageIndex = zeroBased ? number : number - 1;
      if (pageIndex < 0) {
        continue;
      }
      const extension = supportedImageExtension(numericNames[i]);
      const targetName = pageFileName(pageIndex, extension);
      if (numericNames[i] === targetName) {
        continue;
      }
      const temporaryPath = directory + '/' + marker + i.toString() + extension;
      try {
        fs.renameSync(directory + '/' + numericNames[i], temporaryPath);
        plans.push({ temporaryPath: temporaryPath, pageIndex: pageIndex, extension: extension });
      } catch (error) {
      }
    }

    for (let i = 0; i < plans.length; i++) {
      storeNormalizedPageImage(directory, plans[i]);
    }
  } catch (error) {
  }
}

function storeNormalizedPageImage(directory: string, plan: PageImageRenamePlan): void {
  const existing = findCanonicalPageImage(directory, plan.pageIndex);
  if (existing.length > 0 && fileSize(existing) >= fileSize(plan.temporaryPath)) {
    removeFileQuietly(plan.temporaryPath);
    return;
  }
  const target = directory + '/' + pageFileName(plan.pageIndex, plan.extension);
  try {
    if (existing === target) {
      if (copyFileVerified(plan.temporaryPath, target)) {
        removeFileQuietly(plan.temporaryPath);
      }
      return;
    }
    if (exists(target)) {
      removeFileQuietly(target);
    }
    fs.renameSync(plan.temporaryPath, target);
    if (existing.length > 0) {
      removeFileQuietly(existing);
    }
  } catch (error) {
    if (copyFileVerified(plan.temporaryPath, target)) {
      removeFileQuietly(plan.temporaryPath);
      if (existing.length > 0 && existing !== target) {
        removeFileQuietly(existing);
      }
    }
  }
}

function numericImageFileNumber(name: string): number {
  const extension = supportedImageExtension(name);
  const stem = name.substring(0, name.length - extension.length);
  if (!/^\d+$/.test(stem)) {
    return -1;
  }
  const value = Number.parseInt(stem, 10);
  return Number.isFinite(value) ? value : -1;
}

function numericImageStemLength(name: string): number {
  const extension = supportedImageExtension(name);
  return Math.max(0, name.length - extension.length);
}

function canonicalPageImageIndex(name: string): number {
  const extension = supportedImageExtension(name);
  const stem = name.substring(0, name.length - extension.length);
  if (!/^\d{8}$/.test(stem)) {
    return -1;
  }
  const value = Number.parseInt(stem, 10);
  return Number.isFinite(value) && value > 0 ? value - 1 : -1;
}

function findCanonicalPageImage(directory: string, pageIndex: number): string {
  for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
    const path = directory + '/' + pageFileName(pageIndex, SUPPORTED_IMAGE_EXTENSIONS[i]);
    if (exists(path)) {
      return path;
    }
  }
  return '';
}

function normalizeGalleryImageNames(directory: string): void {
  try {
    const names = galleryImageNames(fs.listFileSync(directory));
    names.sort((left: string, right: string) => left.localeCompare(right, undefined, { numeric: true }));
    const temporaryPaths: string[] = [];
    const extensions: string[] = [];
    const marker = '.__ehviewer_import_' + Date.now().toString() + '_';
    for (let i = 0; i < names.length; i++) {
      const extension = supportedImageExtension(names[i]);
      const temporary = directory + '/' + marker + i.toString() + extension;
      fs.moveFileSync(directory + '/' + names[i], temporary);
      temporaryPaths.push(temporary);
      extensions.push(extension);
    }
    for (let i = 0; i < temporaryPaths.length; i++) {
      const target = directory + '/' + pageFileName(i, extensions[i]);
      removeFileQuietly(target);
      fs.moveFileSync(temporaryPaths[i], target);
    }
  } catch (error) {
  }
}

function removeGalleryImages(directory: string): void {
  try {
    const names = fs.listFileSync(directory);
    for (let i = 0; i < names.length; i++) {
      if (isSupportedImageFile(names[i])) {
        removeFileQuietly(directory + '/' + names[i]);
      }
    }
  } catch (error) {
  }
}

function supportedImageExtension(name: string): string {
  const lower = name.toLowerCase();
  for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
    if (lower.endsWith(SUPPORTED_IMAGE_EXTENSIONS[i])) {
      return SUPPORTED_IMAGE_EXTENSIONS[i];
    }
  }
  return '.jpg';
}

function galleryArchiveUri(gallery: GalleryInfo): string {
  const downloadInfo = gallery as DownloadArchiveLocation;
  if (downloadInfo.archiveUri !== undefined && downloadInfo.archiveUri.length > 0) {
    return downloadInfo.archiveUri;
  }
  return '';
}

interface DownloadArchiveLocation extends GalleryInfo {
  archiveUri?: string;
}

// 目录名身份：去掉 gid 前缀、符号与下划线差异，用于判断两个目录是不是同一条图册。
function directoryIdentity(name: string): string {
  let value = name.trim().toLowerCase();
  value = value.replace(/^\d{4,}-/, '');
  value = value.replace(/[\s_~～]+/g, ' ');
  value = value.replace(/[^a-z0-9\u4e00-\u9fff ]+/g, '');
  return value.replace(/\s+/g, ' ').trim();
}

function sanitizePathSegment(value: string): string {
  let result = value
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/\s+/g, ' ')
    .trim();
  if (result.length === 0) {
    result = 'gallery';
  }
  if (result.length > 120) {
    result = result.substring(0, 120).trim();
  }
  return result;
}

// 下载根下的目录名常带 "2687378-" 这样的真实 gid 前缀。
function stripLeadingGid(name: string): string {
  return name.replace(/^\d{4,}[-_\s]+/, '');
}

// 长标题在 sanitizePathSegment 里被截到 120 字符，目录名与记录里的标题
// 不会逐字相等（archiveUri 甚至会在 "]" 前被切断），必须按去前缀后的前缀比对。
function directoryNameMatches(name: string, target: string): boolean {
  if (name === target) {
    return true;
  }
  const sanitized = sanitizePathSegment(name);
  if (sanitized === target) {
    return true;
  }
  const bare = sanitizePathSegment(stripLeadingGid(name));
  if (bare === target) {
    return true;
  }
  // 只有超长标题才会被截断，短名不做前缀匹配，避免 "Vol.1" 命中 "Vol.10"。
  const TRUNCATED_LENGTH: number = 100;
  return bare.length >= TRUNCATED_LENGTH && target.length >= TRUNCATED_LENGTH &&
    (bare.startsWith(target) || target.startsWith(bare));
}

function pathBaseName(path: string): string {  const normalized = normalizePath(path);
  const index = normalized.lastIndexOf('/');
  if (index >= 0 && index < normalized.length - 1) {
    return normalized.substring(index + 1);
  }
  return normalized.length > 0 ? normalized : 'downloads';
}

function uniqueChildPath(parent: string, childName: string): string {
  const safeName = sanitizePathSegment(childName);
  let candidate = parent + '/' + safeName;
  let index = 2;
  while (exists(candidate)) {
    candidate = parent + '/' + safeName + '-' + index.toString();
    index++;
  }
  return candidate;
}

function uniqueZipPath(parent: string, fileName: string): string {
  const dot = fileName.toLowerCase().endsWith('.zip') ? fileName.length - 4 : fileName.length;
  const base = sanitizePathSegment(fileName.substring(0, dot));
  let candidate = parent + '/' + base + '.zip';
  let index = 2;
  while (exists(candidate)) {
    candidate = parent + '/' + base + '-' + index.toString() + '.zip';
    index++;
  }
  return candidate;
}

function parentPath(path: string): string {
  const slash = path.lastIndexOf('/');
  if (slash <= 0) {
    return '';
  }
  return path.substring(0, slash);
}

function zipTimestamp(): string {
  const date = new Date();
  return date.getFullYear().toString() + padTwoDigits(date.getMonth() + 1) + padTwoDigits(date.getDate()) + '_' +
    padTwoDigits(date.getHours()) + padTwoDigits(date.getMinutes()) + padTwoDigits(date.getSeconds());
}

function padTwoDigits(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

// 目录内图片按自然顺序排列，供本地图档按页取图。
// 正文页筛选：目录里只要有数字命名的图片，就只认数字命名。
// 安卓版下载完会留一张 thumb.webp / cover.jpg 当封面，算成正文会让整本多一页：
// 列表比实际多 1，翻到最后是一张重复的封面小图。全应用只经这一处判断。
export function galleryImageNames(names: string[]): string[] {
  const all: string[] = [];
  const numbered: string[] = [];
  for (let i = 0; i < names.length; i++) {
    const name = names[i];
    if (!isSupportedImageFile(name)) {
      continue;
    }
    if (isCoverArtName(name)) {
      continue;
    }
    all.push(name);
    if (numericImageFileNumber(name) >= 0) {
      numbered.push(name);
    }
  }
  return numbered.length > 0 ? numbered : all;
}

// 下载目录里由客户端自己生成的封面缩略图，不属于正文。
function isCoverArtName(name: string): boolean {
  const extension = supportedImageExtension(name);
  const stem = name.substring(0, name.length - extension.length).toLowerCase();
  return stem === 'thumb' || stem === 'thumbnail' || stem === 'cover';
}

// 目录图片列表缓存。取页每次都全目录 listFileSync + 排序，翻 200 页就是扫 200 次目录，
// 这是翻页卡顿的直接原因。3 秒内复用同一份结果：正常翻页都在窗口内，目录变了也能很快反映。
interface DirectoryScanEntry {
  paths: string[];
  checkedAt: number;
}

const DIRECTORY_SCAN_TTL_MS: number = 3000;
const directoryScanCache: Map<string, DirectoryScanEntry> = new Map<string, DirectoryScanEntry>();

function cachedImagePaths(directory: string): string[] {
  const now = Date.now();
  const hit = directoryScanCache.get(directory);
  if (hit !== undefined && now - hit.checkedAt < DIRECTORY_SCAN_TTL_MS) {
    return hit.paths;
  }
  const paths = sortedImagePaths(directory);
  if (directoryScanCache.size > 64) {
    directoryScanCache.clear();
  }
  directoryScanCache.set(directory, { paths: paths, checkedAt: now });
  return paths;
}

function sortedImagePaths(directory: string): string[] {
  const paths: string[] = [];
  try {
    const names = galleryImageNames(fs.listFileSync(directory));
    names.sort((left: string, right: string) => left.localeCompare(right, undefined, { numeric: true }));
    for (let i = 0; i < names.length; i++) {
      paths.push(directory + '/' + names[i]);
    }
  } catch (error) {
  }
  return paths;
}

function pageFileName(index: number, extension: string): string {
  let value = Math.max(0, index + 1).toString();
  while (value.length < 8) {
    value = '0' + value;
  }
  return value + extension;
}

function imageExtension(page: GalleryPage, cachedPath: string): string {
  const source = cachedPath.length > 0 ? cachedPath : (page.originImageUrl.length > 0 ? page.originImageUrl : page.imageUrl);
  const clean = source.split('?')[0].toLowerCase();
  const dot = clean.lastIndexOf('.');
  if (dot >= 0) {
    const extension = clean.substring(dot);
    for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
      if (extension === SUPPORTED_IMAGE_EXTENSIONS[i]) {
        return extension;
      }
    }
  }
  return '.jpg';
}

function writeTextFileQuietly(path: string, value: string): void {
  try {
    writeTextFile(path, value);
  } catch (error) {
  }
}

function scanDirectoryTree(path: string): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const stat = fs.statSync(path);
    if (!stat.isDirectory()) {
      return { directories: 0, files: 1, bytes: stat.size };
    }
    directories++;
    const names = fs.listFileSync(path);
    for (let i = 0; i < names.length; i++) {
      const child = scanDirectoryTree(path + '/' + names[i]);
      directories += child.directories;
      files += child.files;
      bytes += child.bytes;
    }
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

function removeDirectoryTree(path: string): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const stat = fs.statSync(path);
    if (!stat.isDirectory()) {
      const size = stat.size;
      fs.unlinkSync(path);
      return { directories: 0, files: 1, bytes: size };
    }
    const names = fs.listFileSync(path);
    for (let i = 0; i < names.length; i++) {
      const removed = removeDirectoryTree(path + '/' + names[i]);
      directories += removed.directories;
      files += removed.files;
      bytes += removed.bytes;
    }
    fs.rmdirSync(path);
    directories++;
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

function copyDirectoryTree(source: string, target: string): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const stat = fs.statSync(source);
    if (!stat.isDirectory()) {
      if (exists(target)) {
        removeDirectoryTree(target);
      }
      fs.copyFileSync(source, target);
      return { directories: 0, files: 1, bytes: stat.size };
    }
    ensureDirectory(target);
    directories++;
    const names = fs.listFileSync(source);
    for (let i = 0; i < names.length; i++) {
      const copied = copyDirectoryTree(source + '/' + names[i], target + '/' + names[i]);
      directories += copied.directories;
      files += copied.files;
      bytes += copied.bytes;
    }
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

async function scanDirectoryTreeAsync(path: string): Promise<DownloadDirectoryScanResult> {
  try {
    const stat = await fs.stat(path);
    if (!stat.isDirectory()) {
      return { directories: 0, files: 1, bytes: stat.size };
    }
    let directories = 1;
    let files = 0;
    let bytes = 0;
    const names = await fs.listFile(path);
    for (let i = 0; i < names.length; i++) {
      const child = await scanDirectoryTreeAsync(path + '/' + names[i]);
      directories += child.directories;
      files += child.files;
      bytes += child.bytes;
    }
    return { directories: directories, files: files, bytes: bytes };
  } catch (error) {
    throw new Error('Download migration scan failed at ' + path + ': ' + String(error));
  }
}

async function copyDirectoryTreeAsync(source: string, target: string,
  progress: DownloadMigrationProgressState): Promise<DownloadDirectoryScanResult> {
  try {
    const stat = await fs.stat(source);
    if (!stat.isDirectory()) {
      if (exists(target)) {
        await removeDirectoryTreeAsync(target);
      }
      await fs.copyFile(source, target);
      const copiedStat = await fs.stat(target);
      const sourceAfterCopy = await fs.stat(source);
      if (copiedStat.size !== stat.size || sourceAfterCopy.size !== stat.size || sourceAfterCopy.mtime !== stat.mtime) {
        throw new Error('Download file changed or copy is incomplete');
      }
      progress.copiedFiles.push({ source: source, target: target, size: stat.size, mtime: stat.mtime });
      progress.files++;
      progress.bytes += stat.size;
      reportDownloadMigrationProgress(progress, progress.files >= progress.totalFiles);
      return { directories: 0, files: 1, bytes: stat.size };
    }
    if (exists(target) && !isDirectory(target)) {
      await removeDirectoryTreeAsync(target);
    }
    ensureDirectory(target);
    progress.copiedDirectories.push(source);
    let directories = 1;
    let files = 0;
    let bytes = 0;
    const names = await fs.listFile(source);
    for (let i = 0; i < names.length; i++) {
      const copied = await copyDirectoryTreeAsync(source + '/' + names[i], target + '/' + names[i], progress);
      directories += copied.directories;
      files += copied.files;
      bytes += copied.bytes;
    }
    return { directories: directories, files: files, bytes: bytes };
  } catch (error) {
    throw new Error('Download migration copy failed at ' + source + ': ' + String(error));
  }
}

async function removeDirectoryTreeAsync(path: string): Promise<DownloadDirectoryScanResult> {
  try {
    const stat = await fs.stat(path);
    if (!stat.isDirectory()) {
      await fs.unlink(path);
      return { directories: 0, files: 1, bytes: stat.size };
    }
    let directories = 1;
    let files = 0;
    let bytes = 0;
    const names = await fs.listFile(path);
    for (let i = 0; i < names.length; i++) {
      const removed = await removeDirectoryTreeAsync(path + '/' + names[i]);
      directories += removed.directories;
      files += removed.files;
      bytes += removed.bytes;
    }
    await fs.rmdir(path);
    return { directories: directories, files: files, bytes: bytes };
  } catch (error) {
    throw new Error('Download migration cleanup failed at ' + path + ': ' + String(error));
  }
}

async function cleanupMigratedDownloadFiles(progress: DownloadMigrationProgressState, sourceRoot: string): Promise<boolean> {
  let incomplete = false;
  // Only remove files from the verified copy snapshot, never new downloads created during migration.
  for (let i = 0; i < progress.copiedFiles.length; i++) {
    const file = progress.copiedFiles[i];
    try {
      const source = await fs.stat(file.source);
      const target = await fs.stat(file.target);
      if (source.size !== file.size || source.mtime !== file.mtime || target.size !== file.size) {
        incomplete = true;
        continue;
      }
      await fs.unlink(file.source);
    } catch (_error) {
      incomplete = true;
    }
  }
  for (let i = progress.copiedDirectories.length - 1; i >= 0; i--) {
    const directory = progress.copiedDirectories[i];
    try {
      const remaining = await fs.listFile(directory);
      if (remaining.length > 0) {
        incomplete = true;
      } else if (directory !== sourceRoot) {
        await fs.rmdir(directory);
      }
    } catch (_error) {
      incomplete = true;
    }
  }
  return incomplete;
}

function reportDownloadMigrationProgress(progress: DownloadMigrationProgressState, force: boolean): void {
  if (progress.onProgress === undefined) {
    return;
  }
  const now = Date.now();
  if (!force && now - progress.lastReportedAt < 100) {
    return;
  }
  progress.lastReportedAt = now;
  progress.onProgress({
    phase: 'copying',
    files: progress.files,
    bytes: progress.bytes,
    totalFiles: progress.totalFiles,
    totalBytes: progress.totalBytes
  });
}

function normalizePath(path: string): string {
  let result = path.trim();
  while (result.endsWith('/') && result.length > 1) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

export const ehDownloadFileStore: EhDownloadFileStore = new EhDownloadFileStore();
