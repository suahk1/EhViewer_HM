import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { galleryStatusStore } from './GalleryStatusStore';
import { preferences } from '@kit.ArkData';
import { GalleryCategory, GalleryDetail, GalleryInfo, GalleryTagGroup } from '../model/GalleryModels';

import { syncTombstoneStore } from './SyncTombstoneStore';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import {
  cloneGalleryTagGroups,
  cloneStringArrayRequired,
  galleryDetailLanguage,
  galleryDetailTags, storedToGalleryTagGroups, StoredGalleryTagGroup} from '../shared/GalleryTagSupport';

const PREFERENCES_NAME: string = 'ehviewer_downloads';
const SYNC_SECTION_DOWNLOAD_LABELS: string = 'downloadLabels';
export const SYNC_SECTION_DOWNLOADS: string = 'downloads';
const VALUES_KEY: string = 'items';
const LABELS_KEY: string = 'labels';
const DOWNLOAD_NOTIFY_DEBOUNCE_MS: number = 50;
const DOWNLOAD_SAVE_DEBOUNCE_MS: number = 500;
// 本地图档（服务器无记录）的合成 gid 空间，避开 EH 真实 gid 的取值区间。
const LOCAL_GALLERY_GID_BASE: number = 7300000000;
const LOCAL_GALLERY_GID_RANGE: number = 100000000;

// 图册身份归一：去掉目录名前的 gid、大小写、符号与下划线的差异，
// 只留下可用于判重的实质字符。同一图册无论来自 DB 还是本地目录都能对上。
function normalizeGalleryIdentity(title: string): string {
  let value = title.trim().toLowerCase();
  value = value.replace(/^\d{4,}-/, '');
  value = value.replace(/[\s_~～]+/g, ' ');
  value = value.replace(/[^a-z0-9\u4e00-\u9fff ]+/g, '');
  value = value.replace(/\s+/g, ' ').trim();
  return value;
}

function lastPathSegment(path: string): string {
  const normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  const slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}

function normalizeDirectoryPath(path: string): string {
  let value = path.trim();
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

export enum DownloadState {
  Invalid = 'invalid',
  None = 'none',
  Wait = 'wait',
  Downloading = 'downloading',
  Finish = 'finish',
  Failed = 'failed',
  Update = 'update',
  // 记录显示已完成，但本地目录里一张图都没有（典型是只导入了记录、没带图片）。
  Missing = 'missing'
}

export interface DownloadQueueCounts {
  downloading: number;
  waiting: number;
  finished: number;
  failed: number;
}

// 云端可用性：'' 未知 / 'ok' 云端仍在 / 'gone' 云端已删除（DB 有记录、列表里标红云）。
export const CLOUD_STATE_OK: string = 'ok';
export const CLOUD_STATE_GONE: string = 'gone';

export interface DownloadInfo extends GalleryInfo {
  state: DownloadState;
  cloudState?: string;
  legacy: number;
  time: number;
  label: string;
  archiveUri: string;
  speed: number;
  remaining: number;
  finished: number;
  downloaded: number;
  total: number;
  fileSize: number;
}

export interface DownloadLabel {
  label: string;
  time: number;
}

type DownloadStoreListener = (items: DownloadInfo[], labels: DownloadLabel[]) => void;

export interface DownloadProgress {
  gid: number;
  finished: number;
  downloaded: number;
  total: number;
  speed: number;
  remaining: number;
  fileSize: number;
  archiveUri: string;
}

type DownloadProgressListener = (updates: DownloadProgress[]) => void;

interface DownloadStoreSubscription {
  listener: DownloadStoreListener;
  onProgress?: DownloadProgressListener;
}

interface StoredDownloadInfo {
  gid?: number;
  token?: string;
  title?: string;
  titleJpn?: string;
  thumb?: string;
  category?: number;
  posted?: string;
  uploader?: string;
  rating?: number;
  rated?: boolean;
  simpleLanguage?: string;
  simpleTags?: string[];
  pages?: number;
  thumbWidth?: number;
  thumbHeight?: number;
  favoriteSlot?: number;
  favoriteName?: string;
  tagList?: string[];
  detailTags?: StoredGalleryTagGroup[];
  detailLanguage?: string;
  state?: string;
  cloudState?: string;
  legacy?: number;
  time?: number;
  label?: string;
  archiveUri?: string;
  speed?: number;
  remaining?: number;
  finished?: number;
  downloaded?: number;
  total?: number;
  fileSize?: number;
}


interface StoredDownloadLabel {
  label?: string;
  time?: number;
}

export class EhDownloadStore {
  private context: common.UIAbilityContext | undefined = undefined;
  private items: DownloadInfo[] = [];
  private labels: DownloadLabel[] = [];
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;
  private listeners: DownloadStoreSubscription[] = [];
  private pendingProgress: Map<number, DownloadInfo> = new Map();
  private cachedItemIndexes: Map<number, number> = new Map();
  private notifyTimer: number = -1;
  private saveRevision: number = 0;
  private savePromise: Promise<void> | null = null;

  subscribe(listener: DownloadStoreListener, onProgress?: DownloadProgressListener): () => void {
    const subscription: DownloadStoreSubscription = { listener: listener, onProgress: onProgress };
    this.listeners.push(subscription);
    listener(this.getItems(), this.getLabels());
    return () => {
      const next: DownloadStoreSubscription[] = [];
      for (let i = 0; i < this.listeners.length; i++) {
        if (this.listeners[i] !== subscription) {
          next.push(this.listeners[i]);
        }
      }
      this.listeners = next;
    };
  }

  getItems(): DownloadInfo[] {
    return cloneDownloadInfos(this.items);
  }

  getGalleryIds(): number[] {
    return this.items.map((item: DownloadInfo) => item.gid);
  }

  getLabels(): DownloadLabel[] {
    return cloneDownloadLabels(this.labels);
  }

  contains(gid: number): boolean {
    return this.findIndex(gid) >= 0;
  }

  addGallery(gallery: GalleryInfo, label: string = '', time: number = 0): DownloadInfo | null {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return null;
    }

    const index = this.findIndex(gallery.gid);
    if (index >= 0) {
      const updated = galleryToDownloadInfo(gallery, this.items[index].label);
      updated.state = this.items[index].state;
      updated.legacy = this.items[index].legacy;
      updated.time = time > 0 ? time : this.items[index].time;
      updated.archiveUri = this.items[index].archiveUri;
      updated.speed = this.items[index].speed;
      updated.remaining = this.items[index].remaining;
      updated.finished = this.items[index].finished;
      updated.downloaded = this.items[index].downloaded;
      updated.total = this.items[index].total;
      updated.fileSize = this.items[index].fileSize;
      this.items[index] = updated;
      this.notifyChanged();
      return cloneDownloadInfo(updated);
    }

    const item = galleryToDownloadInfo(gallery, label);
    if (time > 0) {
      item.time = time;
    }
    this.items.unshift(item);
    this.notifyChanged();
    return cloneDownloadInfo(item);
  }

  // 本地图档：磁盘上存在、服务器与数据库里都没有对应记录的图册。
  // token 为空是判别条件；gid 由目录路径派生，只用于本地列表去重与排序。
  addLocalGallery(title: string, directory: string, thumb: string, pages: number, fileSize: number,
    time: number = 0): DownloadInfo | null {
    const normalizedTitle = title.trim();
    if (normalizedTitle.length === 0 || directory.length === 0) {
      return null;
    }
    const total = Math.max(0, pages);
    // 同一个目录/同名本地图册已经登记过就就地更新，绝不重复插入。
    // 扫描本地图册会反复跑，没有这一步会把同一个文件夹反复加进列表。
    const existingIndex = this.findLocalGalleryIndex(normalizedTitle, directory);
    if (existingIndex >= 0) {
      const prev = this.items[existingIndex];
      prev.title = normalizedTitle;
      prev.pages = total;
      prev.finished = total;
      prev.downloaded = total;
      prev.total = total;
      prev.fileSize = fileSize;
      prev.archiveUri = directory;
      if (thumb.length > 0) {
        prev.thumb = thumb;
      }
      if (time > 0) {
        prev.time = time;
      }
      this.notifyChanged();
      return cloneDownloadInfo(prev);
    }
    const item: DownloadInfo = {
      gid: this.localGalleryGid(normalizedTitle, directory),
      token: '',
      title: normalizedTitle,
      titleJpn: '',
      thumb: thumb,
      category: GalleryCategory.Unknown,
      posted: '',
      uploader: '',
      rating: -1,
      rated: false,
      simpleLanguage: '',
      simpleTags: [],
      pages: total,
      thumbWidth: 0,
      thumbHeight: 0,
      favoriteSlot: -2,
      favoriteName: '',
      tagList: [],
      detailTags: [],
      detailLanguage: '',
      state: DownloadState.Finish,
      legacy: 0,
      time: time > 0 ? time : Date.now(),
      label: '',
      archiveUri: directory,
      speed: 0,
      remaining: 0,
      finished: total,
      downloaded: total,
      total: total,
      fileSize: fileSize
    };
    this.items.unshift(item);
    this.notifyChanged();
    return cloneDownloadInfo(item);
  }

  // 本地图档的页数/体积只能在磁盘上数出来。早期扫描没写 pages 的记录会一直显示 "-"，
  // 详情页也拿不到真实页数；扫描到已登记目录时统一回填，不必删除重导。
  // gid 是记录主键，按它定位最可靠；目录路径只作为兜底（导入时记录还没有可用的目录）。
  // 只按 archiveUri 精确比对不够：记录里的路径与磁盘真实目录一旦不同（改名、分卷、
  // 长标题被截断），回填就静默返回 false，列表页数永远停在旧值。
  refreshLocalGalleryMeta(directory: string, pages: number, fileSize: number, thumb: string = '',
    gid: number = -1): boolean {
    let index = gid > 0 ? this.findIndex(gid) : -1;
    if (index < 0) {
      index = this.findLocalGalleryIndex('', directory);
    }
    if (index < 0) {
      return false;
    }
    const item = this.items[index];
    let changed = false;
    if (pages > 0 && (item.pages !== pages || item.total !== pages || item.finished !== pages ||
      item.downloaded !== pages)) {
      item.pages = pages;
      item.total = pages;
      item.finished = pages;
      item.downloaded = pages;
      changed = true;
    }
    if (fileSize > 0 && item.fileSize !== fileSize) {
      item.fileSize = fileSize;
      changed = true;
    }
    if (thumb.length > 0 && item.thumb !== thumb) {
      item.thumb = thumb;
      changed = true;
    }
    if (changed) {
      this.notifyChanged();
    }
    return changed;
  }

  // 只按目录路径去重。同名不同目录是磁盘上真实存在的两份数据（导入复制留下的），
  // 按标题合并会把它们压成一条，用户导入 205 个目录却只看到 70 条。
  private findLocalGalleryIndex(title: string, directory: string): number {
    const target = normalizeDirectoryPath(directory);
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.token.length > 0) {
        continue;
      }
      if (normalizeDirectoryPath(item.archiveUri) === target) {
        return i;
      }
    }
    return -1;
  }

  hasLocalGalleryDirectory(directory: string): boolean {
    return this.findLocalGalleryIndex('', directory) >= 0;
  }

  hasLocalGalleryTitle(title: string): boolean {
    const normalized = title.trim().toLowerCase();
    if (normalized.length === 0) {
      return false;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].token.length === 0 && this.items[i].title.trim().toLowerCase() === normalized) {
        return true;
      }
    }
    return false;
  }

  private localGalleryGid(title: string, directory: string): number {
    // 只用目录名参与哈希：同一目录不管传绝对路径还是相对路径，gid 都要稳定，
    // 否则反复扫描会给同一个文件夹生成新的 gid，列表里越扫越多。
    const key = directory.length > 0 ? lastPathSegment(directory) : title;
    let hash = 5381;
    for (let i = 0; i < key.length; i++) {
      hash = ((hash * 33) ^ key.charCodeAt(i)) & 0x7fffffff;
    }
    let gid = LOCAL_GALLERY_GID_BASE + (hash % LOCAL_GALLERY_GID_RANGE);
    while (this.findIndex(gid) >= 0) {
      gid++;
    }
    return gid;
  }

  importDownload(item: DownloadInfo): boolean {
    return this.mergeImportedItem(item) !== 'skipped';
  }

  // 导入一条记录（DB / 备份 / 同步都走这里），按「云端身份 gid → 本地标题身份」两路查重：
  // 命中云端的就地更新并保留本机目录与进度；命中本地图档的升级成云端记录（目录留在本机）；
  // 都不命中才新增。返回 added / merged / skipped 便于统计。
  mergeImportedItem(item: DownloadInfo): string {
    const incoming = storedToDownloadInfo(item as StoredDownloadInfo);
    if (incoming.gid <= 0) {
      return 'skipped';
    }
    if (incoming.token.length === 0) {
      // 纯本地图档：没有云端身份，靠目录/标题判重。备份迁移时这些记录必须能带过来，
      // 否则新设备上本地图册会整批消失。
      if (incoming.archiveUri.length > 0 && this.hasLocalGalleryDirectory(incoming.archiveUri)) {
        return 'skipped';
      }
      const localIndex = this.findIdentityIndex(incoming.title);
      if (localIndex >= 0) {
        const existing = this.items[localIndex];
        if (existing.archiveUri.length === 0 && incoming.archiveUri.length > 0) {
          this.items[localIndex].archiveUri = incoming.archiveUri;
          this.items[localIndex].state = DownloadState.Finish;
          this.notifyChanged();
        }
        return 'merged';
      }
      this.items.unshift(cloneDownloadInfo(incoming));
      this.notifyChanged();
      return 'added';
    }
    const byGid = this.findIndex(incoming.gid);
    if (byGid >= 0) {
      const existing = this.items[byGid];
      const merged = cloneDownloadInfo(incoming);
      // 本机已有的目录、进度、完成态优先，避免备份里的旧状态覆盖掉真实文件。
      if (existing.archiveUri.length > 0) {
        merged.archiveUri = existing.archiveUri;
      }
      if (existing.state === DownloadState.Finish || existing.finished > 0) {
        merged.state = existing.state === DownloadState.Missing ? DownloadState.Finish : existing.state;
        merged.finished = existing.finished > 0 ? existing.finished : merged.finished;
        merged.downloaded = Math.max(existing.downloaded, merged.downloaded);
        merged.total = existing.total > 0 ? existing.total : merged.total;
      }
      if (existing.fileSize > 0) {
        merged.fileSize = existing.fileSize;
      }
      if (existing.cloudState !== undefined && existing.cloudState.length > 0 &&
        (merged.cloudState === undefined || merged.cloudState.length === 0)) {
        merged.cloudState = existing.cloudState;
      }
      this.items[byGid] = merged;
      this.notifyChanged();
      return 'merged';
    }
    // 标题身份：本机已有同名的「纯本地图档」（服务器当初查不到，gid 是合成号），
    // 直接升级这一条，别再加一份重复记录。
    const localIndex = this.findLocalIdentityIndex(incoming.title);
    if (localIndex >= 0) {
      const existing = this.items[localIndex];
      const merged = cloneDownloadInfo(incoming);
      merged.archiveUri = existing.archiveUri;
      merged.title = incoming.title.length > 0 ? incoming.title : existing.title;
      merged.state = existing.state === DownloadState.Missing ? incoming.state : existing.state;
      merged.finished = existing.finished > 0 ? existing.finished : merged.finished;
      merged.downloaded = Math.max(existing.downloaded, merged.downloaded);
      merged.total = existing.total > 0 ? existing.total : merged.total;
      merged.fileSize = existing.fileSize;
      merged.time = existing.time;
      this.items[localIndex] = merged;
      this.notifyChanged();
      return 'merged';
    }
    this.items.unshift(cloneDownloadInfo(incoming));
    this.notifyChanged();
    return 'added';
  }

  // 本地文件夹导入匹配到服务器后走这里：把真实目录绑到已有记录上（本地记录升级成云端记录），
  // 没有同名记录才新增。返回 added / merged / skipped。
  bindMatchedGallery(gallery: GalleryInfo, directory: string, pageCount: number, size: number,
    time: number): string {
    const item: DownloadInfo = {
      gid: gallery.gid,
      token: gallery.token,
      title: gallery.title,
      titleJpn: gallery.titleJpn,
      thumb: gallery.thumb,
      category: gallery.category,
      posted: gallery.posted,
      uploader: gallery.uploader,
      rating: gallery.rating,
      rated: gallery.rated,
      simpleLanguage: gallery.simpleLanguage,
      simpleTags: gallery.simpleTags,
      pages: gallery.pages,
      thumbWidth: gallery.thumbWidth,
      thumbHeight: gallery.thumbHeight,
      favoriteSlot: gallery.favoriteSlot,
      favoriteName: gallery.favoriteName,
      tagList: gallery.tagList,
      detailTags: galleryDetailTags(gallery),
      detailLanguage: galleryDetailLanguage(gallery),
      state: DownloadState.Finish,
      cloudState: CLOUD_STATE_OK,
      legacy: 0,
      time: time,
      label: '',
      archiveUri: directory,
      speed: 0,
      remaining: 0,
      finished: pageCount,
      downloaded: 0,
      total: pageCount > 0 ? pageCount : gallery.pages,
      fileSize: size
    };
    return this.mergeImportedItem(item);
  }

  // 纯本地图档（token 为空）里按规范化标题找同一条目。
  findLocalIdentityIndex(title: string): number {
    const identity = normalizeGalleryIdentity(title);
    if (identity.length === 0) {
      return -1;
    }
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.token.length > 0) {
        continue;
      }
      if (normalizeGalleryIdentity(item.title) === identity) {
        return i;
      }
    }
    return -1;
  }

  // 任何记录（云端或本地）里按规范化标题找，用于把真实目录绑到已有记录上。
  findIdentityIndex(title: string): number {
    const identity = normalizeGalleryIdentity(title);
    if (identity.length === 0) {
      return -1;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (normalizeGalleryIdentity(this.items[i].title) === identity) {
        return i;
      }
    }
    return -1;
  }

  // 备份迁移专用入口：旧设备写进 JSON 的 archiveUri 在新设备上一定失效，
  // 先丢掉再看本机有没有对应目录，有就绑上并归位完成，没有则标记缺失（红/蓝云角标表达）。
  importBackupItem(item: DownloadInfo): string {
    const incoming = storedToDownloadInfo(item as StoredDownloadInfo);
    incoming.archiveUri = '';
    incoming.speed = 0;
    incoming.remaining = 0;
    incoming.downloaded = 0;
    const outcome = this.mergeImportedItem(incoming);
    if (outcome === 'skipped' || this.context === undefined) {
      return outcome;
    }
    const index = this.findIndex(incoming.gid);
    if (index < 0) {
      return outcome;
    }
    const target = this.items[index];
    const resolved = ehDownloadFileStore.resolveGalleryDirectory(this.context, target.gid, target.title, '');
    if (resolved.length > 0) {
      target.archiveUri = resolved;
      target.fileSize = ehDownloadFileStore.directorySizeByPath(resolved);
      // 解析到目录不等于下完：按目录里真实的页数归位，
      // 否则导出时只下了 3/6 页的失败项会被写成「已下载」。
      const pages = target.total > 0 ? target.total : target.pages;
      const images = ehDownloadFileStore.listPageImages(this.context, target).length;
      if (pages > 0) {
        target.finished = images > pages ? pages : images;
        target.state = images >= pages ? DownloadState.Finish : DownloadState.Failed;
      } else if (images > 0) {
        target.total = images;
        target.finished = images;
        target.state = DownloadState.Finish;
      }
    } else if (target.token.length > 0) {
      target.state = DownloadState.Missing;
    }
    this.notifyChanged();
    return outcome;
  }

  // 记录级查重：同一图册（云端 gid 相同或标题身份相同）只保留一条。
  // 优先保留带云端身份、且目录里有图的那条；其余合并掉的目录信息不丢。
  dedupeRecords(): number {
    const kept: DownloadInfo[] = [];
    const byKey: Map<string, number> = new Map();
    let removed = 0;
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      const key = item.gid > 0 && item.token.length > 0 ?
        'g' + item.gid.toString() : 't' + normalizeGalleryIdentity(item.title);
      if (key === 't' || key.length <= 1) {
        kept.push(cloneDownloadInfo(item));
        continue;
      }
      const existingIndex = byKey.get(key);
      if (existingIndex === undefined) {
        byKey.set(key, kept.length);
        kept.push(cloneDownloadInfo(item));
        continue;
      }
      const current = kept[existingIndex];
      const merged = this.mergeDuplicatePair(current, item);
      kept[existingIndex] = merged;
      removed++;
    }
    if (removed > 0) {
      this.items = kept;
      this.notifyChanged();
    }
    return removed;
  }

  private mergeDuplicatePair(left: DownloadInfo, right: DownloadInfo): DownloadInfo {
    // 有云端身份的一条做底（保留 gid/token/云端元数据）。
    const base = left.token.length > 0 ? left : right;
    const other = base === left ? right : left;
    const merged = cloneDownloadInfo(base);
    const baseHasImages = this.directoryHasImages(merged.archiveUri);
    const otherHasImages = this.directoryHasImages(other.archiveUri);
    if (!baseHasImages && otherHasImages) {
      merged.archiveUri = other.archiveUri;
      merged.fileSize = other.fileSize;
      merged.state = DownloadState.Finish;
      merged.finished = other.finished > 0 ? other.finished : merged.finished;
    }
    if (merged.archiveUri.length === 0 && other.archiveUri.length > 0) {
      merged.archiveUri = other.archiveUri;
    }
    if (merged.token.length === 0 && other.token.length > 0) {
      merged.gid = other.gid;
      merged.token = other.token;
    }
    merged.total = Math.max(merged.total, other.total);
    merged.finished = Math.max(merged.finished, other.finished);
    if ((merged.cloudState === undefined || merged.cloudState.length === 0) &&
      other.cloudState !== undefined && other.cloudState.length > 0) {
      merged.cloudState = other.cloudState;
    }
    return merged;
  }

  setCloudState(gid: number, state: string): boolean {
    const index = this.findIndex(gid);
    if (index < 0 || this.items[index].cloudState === state) {
      return false;
    }
    this.items[index].cloudState = state;
    this.notifyChanged();
    return true;
  }

  removeGallery(gid: number): void {
    const next: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid !== gid) {
        next.push(cloneDownloadInfo(this.items[i]));
      }
    }
    this.items = next;
    syncTombstoneStore.recordDeletion(this.context, SYNC_SECTION_DOWNLOADS, gid.toString());
    this.notifyChanged();
  }

  // 下载列表同步：去掉速度、剩余时间、本地归档路径等只在本机有意义的数据。
  // 本地图档（token 为空）只存在于本机，不参与同步。
  getSyncItems(): DownloadInfo[] {
    const all = this.getItems();
    const items: DownloadInfo[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].token.length === 0) {
        continue;
      }
      all[i].speed = 0;
      all[i].remaining = 0;
      all[i].archiveUri = '';
      all[i].legacy = 0;
      items.push(all[i]);
    }
    return items;
  }

  // 合并另一台设备的下载列表：按 gid 匹配，较新的记录更新元数据，同时保留本机状态与进度。
  mergeSyncItems(items: DownloadInfo[]): number {
    if (!Array.isArray(items)) {
      return 0;
    }
    let changed = 0;
    for (let i = 0; i < items.length; i++) {
      const raw = items[i];
      if (raw === null || raw === undefined || typeof raw.gid !== 'number' || raw.gid <= 0 ||
        typeof raw.token !== 'string' || raw.token.length === 0) {
        continue;
      }
      const incoming = cloneDownloadInfo(raw);
      incoming.speed = 0;
      incoming.remaining = 0;
      incoming.archiveUri = '';
      incoming.legacy = 0;
      if (typeof incoming.time !== 'number' || incoming.time <= 0) {
        incoming.time = 0;
      }
      const index = this.findIndex(incoming.gid);
      if (index < 0) {
        incoming.speed = 0;
        incoming.remaining = 0;
        incoming.archiveUri = '';
        if (incoming.state !== DownloadState.Finish) {
          incoming.state = DownloadState.None;
        }
        this.items.unshift(incoming);
        changed++;
        continue;
      }
      const local = this.items[index];
      const incomingFinished = incoming.state === DownloadState.Finish;
      const localFinished = local.state === DownloadState.Finish;
      if (incoming.time > local.time || (incomingFinished && !localFinished && incoming.time >= local.time)) {
        incoming.state = local.state;
        incoming.speed = local.speed;
        incoming.remaining = local.remaining;
        incoming.finished = local.finished;
        incoming.downloaded = local.downloaded;
        incoming.total = local.total > 0 ? local.total : incoming.total;
        incoming.archiveUri = local.archiveUri;
        this.items[index] = incoming;
        changed++;
      }
    }
    if (changed > 0) {
      this.notifyChanged();
    }
    return changed;
  }

  setState(gid: number, state: DownloadState): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    this.items[index].state = state;
    this.notifyChanged();
  }

  updateGallery(gallery: GalleryInfo): void {
    const index = this.findIndex(gallery.gid);
    if (index < 0) {
      return;
    }
    const previous = this.items[index];
    const updated = galleryToDownloadInfo(gallery, previous.label);
    updated.state = previous.state;
    updated.legacy = previous.legacy;
    updated.time = previous.time;
    updated.archiveUri = previous.archiveUri;
    updated.speed = previous.speed;
    updated.remaining = previous.remaining;
    updated.finished = previous.finished;
    updated.downloaded = previous.downloaded;
    updated.total = previous.total > 0 ? previous.total : updated.total;
    updated.fileSize = previous.fileSize;
    this.items[index] = updated;
    this.notifyChanged();
  }

  setProgress(gid: number, finished: number, total: number, downloaded: number = 0): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    const item = this.items[index];
    if (item.finished === finished && item.downloaded === downloaded && item.total === total) {
      return;
    }
    item.finished = finished;
    item.downloaded = downloaded;
    item.total = total;
    this.scheduleNotifyChanged(item);
  }

  setTransfer(gid: number, speed: number, remaining: number): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    const normalizedSpeed = Math.max(0, speed);
    const normalizedRemaining = Math.max(0, remaining);
    const item = this.items[index];
    if (item.speed === normalizedSpeed && item.remaining === normalizedRemaining) {
      return;
    }
    item.speed = normalizedSpeed;
    item.remaining = normalizedRemaining;
    this.scheduleNotifyChanged(item);
  }

  setStorage(gid: number, archiveUri: string, fileSize: number): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    const item = this.items[index];
    if (item.archiveUri === archiveUri && item.fileSize === fileSize) {
      return;
    }
    item.archiveUri = archiveUri;
    item.fileSize = fileSize;
    this.scheduleNotifyChanged(item);
  }

  setLabel(gid: number, label: string): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    const normalized = normalizeLabel(label);
    if (normalized.length > 0 && !this.hasLabel(normalized)) {
      return;
    }
    if (this.items[index].label === normalized) {
      return;
    }
    this.items[index].label = normalized;
    this.notifyChanged();
  }

  setLabels(gids: number[], label: string): number {
    const normalized = normalizeLabel(label);
    if (normalized.length > 0 && !this.hasLabel(normalized)) {
      return 0;
    }
    let changed = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (gids.indexOf(this.items[i].gid) >= 0 && this.items[i].label !== normalized) {
        this.items[i].label = normalized;
        changed++;
      }
    }
    if (changed > 0) {
      this.notifyChanged();
    }
    return changed;
  }

  addLabel(label: string, recordClear: boolean = true): boolean {
    const normalized = normalizeLabel(label);
    if (normalized.length === 0 || normalized.toLowerCase() === 'default' ||
      normalized.toLowerCase() === 'all' || normalized === '__all__' || normalized === '__ask__' ||
      this.hasLabel(normalized)) {
      return false;
    }
    if (recordClear) {
      syncTombstoneStore.recordClear(this.context, SYNC_SECTION_DOWNLOAD_LABELS, normalized);
    }
    this.labels.push({ label: normalized, time: Date.now() });
    this.notifyChanged();
    return true;
  }

  renameLabel(label: string, nextLabel: string): boolean {
    const normalized = normalizeLabel(label);
    const next = normalizeLabel(nextLabel);
    if (normalized.length === 0 || next.length === 0 || next.toLowerCase() === 'default' ||
      next.toLowerCase() === 'all' || next === '__all__' || next === '__ask__' ||
      normalized === next || this.hasLabel(next)) {
      return false;
    }
    let found = false;
    for (let i = 0; i < this.labels.length; i++) {
      if (this.labels[i].label === normalized) {
        this.labels[i].label = next;
        found = true;
        break;
      }
    }
    if (!found) {
      return false;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].label === normalized) {
        this.items[i].label = next;
      }
    }
    this.notifyChanged();
    return true;
  }

  moveLabel(fromIndex: number, toIndex: number): boolean {
    if (fromIndex < 0 || toIndex < 0 || fromIndex >= this.labels.length || toIndex >= this.labels.length ||
      fromIndex === toIndex) {
      return false;
    }
    const moved = this.labels.splice(fromIndex, 1);
    if (moved.length === 0) {
      return false;
    }
    this.labels.splice(toIndex, 0, moved[0]);
    this.notifyChanged();
    return true;
  }

  removeLabel(label: string): number {
    const normalized = normalizeLabel(label);
    const next: DownloadLabel[] = [];
    let removed = false;
    for (let i = 0; i < this.labels.length; i++) {
      if (this.labels[i].label !== normalized) {
        next.push(cloneDownloadLabel(this.labels[i]));
      } else {
        removed = true;
      }
    }
    if (!removed) {
      return 0;
    }
    this.labels = next;
    syncTombstoneStore.recordDeletion(this.context, SYNC_SECTION_DOWNLOAD_LABELS, normalized);
    let resetCount = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].label === normalized) {
        this.items[i].label = '';
        resetCount++;
      }
    }
    this.notifyChanged();
    return resetCount;
  }

  hasLabel(label: string): boolean {
    const normalized = normalizeLabel(label);
    for (let i = 0; i < this.labels.length; i++) {
      if (this.labels[i].label === normalized) {
        return true;
      }
    }
    return false;
  }

  labelItemCount(label: string): number {
    const normalized = normalizeLabel(label);
    let count = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].label === normalized) {
        count++;
      }
    }
    return count;
  }

  startAll(): void {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.None || this.items[i].state === DownloadState.Failed ||
        this.items[i].state === DownloadState.Finish) {
        this.items[i].state = DownloadState.Wait;
      }
    }
    this.notifyChanged();
  }

  // 入队。已完成（Finish）的项不再入队 —— 否则“全部下载”会把已经下完的画廊
  // 重新拉一遍详情和页列表，列表看上去像被清空重下。
  startGallery(gid: number): boolean {
    const index = this.findIndex(gid);
    if (index < 0) {
      return false;
    }
    const state = this.items[index].state;
    if (state === DownloadState.Finish || state === DownloadState.Wait || state === DownloadState.Downloading) {
      return false;
    }
    this.items[index].state = DownloadState.Wait;
    this.items[index].speed = 0;
    this.items[index].remaining = 0;
    this.notifyChanged();
    return true;
  }

  // 批量入队，返回真正进入队列的数量，供调用方给出反馈。
  // 注意：这里一次性改完再 notify 一次，避免逐条通知导致「队列结算」在过渡状态上取快照。
  startGalleries(gids: number[]): number {
    let queued = 0;
    let changed = false;
    for (let i = 0; i < gids.length; i++) {
      const index = this.findIndex(gids[i]);
      if (index < 0) {
        continue;
      }
      const state = this.items[index].state;
      if (state === DownloadState.Finish || state === DownloadState.Wait || state === DownloadState.Downloading) {
        continue;
      }
      this.items[index].state = DownloadState.Wait;
      this.items[index].speed = 0;
      this.items[index].remaining = 0;
      queued++;
      changed = true;
    }
    if (changed) {
      this.notifyChanged();
    }
    return queued;
  }

  // 队列概览：正在下载 / 等待 / 已完成，用于列表上方的实时反馈。
  queueCounts(): DownloadQueueCounts {
    const counts: DownloadQueueCounts = { downloading: 0, waiting: 0, finished: 0, failed: 0 };
    for (let i = 0; i < this.items.length; i++) {
      const state = this.items[i].state;
      if (state === DownloadState.Downloading) {
        counts.downloading++;
      } else if (state === DownloadState.Wait) {
        counts.waiting++;
      } else if (state === DownloadState.Finish) {
        counts.finished++;
      } else if (state === DownloadState.Failed) {
        counts.failed++;
      }
    }
    return counts;
  }

  stopGallery(gid: number): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    if (this.items[index].state === DownloadState.Wait || this.items[index].state === DownloadState.Downloading) {
      this.items[index].state = DownloadState.None;
      this.notifyChanged();
    }
  }

  stopAll(): void {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.Wait || this.items[i].state === DownloadState.Downloading) {
        this.items[i].state = DownloadState.None;
      }
    }
    this.notifyChanged();
  }

  clearFinished(): void {
    const next: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state !== DownloadState.Finish) {
        next.push(cloneDownloadInfo(this.items[i]));
      } else {
        syncTombstoneStore.recordDeletion(this.context, SYNC_SECTION_DOWNLOADS, this.items[i].gid.toString());
      }
    }
    this.items = next;
    this.notifyChanged();
  }

  load(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loadPromise !== null) {
      return this.loadPromise;
    }
    const pending = this.loadNow(context).then(() => {
      this.loaded = true;
    }).finally(() => {
      if (this.loadPromise === pending) {
        this.loadPromise = null;
      }
    });
    this.loadPromise = pending;
    return pending;
  }

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loaded) {
      return;
    }
    await this.load(context);
  }

  private async loadNow(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      const rawLabels = await prefs.get(LABELS_KEY, '');
      this.items = [];
      this.labels = [];
      if (typeof raw !== 'string' || raw.length === 0) {
        this.loadLabels(rawLabels);
        this.notifyChanged();
        return;
      }

      const parsed = JSON.parse(raw) as StoredDownloadInfo[];
      if (!Array.isArray(parsed)) {
        return;
      }

      for (let i = 0; i < parsed.length; i++) {
        const item = storedToDownloadInfo(parsed[i]);
        // 本地图档没有 token，靠合成 gid 区分，不能当作脏数据丢掉。
        const isLocalGallery = item.token.length === 0 && item.gid >= LOCAL_GALLERY_GID_BASE;
        if (item.gid > 0 && (item.token.length > 0 || isLocalGallery)) {
          this.items.push(item);
        }
      }
      const reconciled = this.reconcileCompletedStates();
      this.loadLabels(rawLabels);
      this.notifyChanged();
      if (reconciled) {
        await prefs.put(VALUES_KEY, JSON.stringify(this.items));
        await prefs.flush();
      }
    } catch (error) {
      throw new Error(String(error));
    }
  }

  // 配额保护（509）曾把「文件已全部下完但 state 误标」的项标成 failed/wait/downloading，
  // 加载时按 finished>=total 归位为 Finish，避免下载列表误显示失败、点缩略图无法直接阅读。
  private reconcileCompletedStates(): boolean {
    let changed = false;
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.total > 0 && item.finished >= item.total && item.state !== DownloadState.Finish &&
        item.state !== DownloadState.Missing) {
        item.state = DownloadState.Finish;
        changed = true;
      }
    }
    // 进程重启后不可能还有活跃下载：残留的 downloading 归为等待，避免列表顶部
    // 长期显示“下载中 N”却没有任何字节在动。
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.state === DownloadState.Downloading) {
        item.state = DownloadState.Wait;
        item.speed = 0;
        item.remaining = 0;
        changed = true;
      }
    }
    // 标着「已完成」但目录空了（导入只带记录没带图片、或文件被清理），改成「文件缺失」，
    // 否则点进去会读到空目录、阅读器一直转圈，或者退化成别的图。
    // 判缺失前先按 gid / 标题到下载根下找真实目录：安卓 DB 里的 ARCHIVE_URI 是旧手机路径，
    // 直接判缺失会把本机明明存在的图册误标成缺失。
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.state !== DownloadState.Finish) {
        continue;
      }
      if (this.directoryHasImages(item.archiveUri)) {
        continue;
      }
      const bound = this.bindExistingDirectory(item);
      if (bound) {
        changed = true;
        continue;
      }
      item.state = DownloadState.Missing;
      item.speed = 0;
      item.remaining = 0;
      changed = true;
    }
    // 本地图册（服务器没有记录）只要目录是空的就整条移除：它没有任何内容可看，
    // 留着只会让列表里全是点开没图的条目。只删记录，不动磁盘。
    for (let i = this.items.length - 1; i >= 0; i--) {
      const item = this.items[i];
      if (item.token.length === 0 && item.state === DownloadState.Missing) {
        this.items.splice(i, 1);
        changed = true;
      }
    }
    return changed;
  }

  // 记录指向的目录无效时，按 gid / 标题到下载根下找真实目录并绑上；找到返回 true。
  private bindExistingDirectory(item: DownloadInfo): boolean {
    if (this.context === undefined) {
      return false;
    }
    try {
      const resolved = ehDownloadFileStore.resolveGalleryDirectory(this.context, item.gid, item.title,
        item.archiveUri);
      if (resolved.length === 0 || !this.directoryHasImages(resolved)) {
        return false;
      }
      item.archiveUri = resolved;
      item.fileSize = ehDownloadFileStore.directorySizeByPath(resolved);
      return true;
    } catch (error) {
      return false;
    }
  }

  private directoryHasImages(directory: string): boolean {
    if (directory.length === 0) {
      return false;
    }
    try {
      const names: string[] = fs.listFileSync(directory);
      for (let i = 0; i < names.length; i++) {
        const lower = names[i].toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
          lower.endsWith('.webp') || lower.endsWith('.gif')) {
          return true;
        }
      }
      return false;
    } catch (error) {
      // 读不到目录时不判定缺失，避免把真在的数据误标。
      return true;
    }
  }

  save(context: common.UIAbilityContext): Promise<void> {
    this.saveRevision++;
    if (this.savePromise !== null) {
      return this.savePromise;
    }
    const pending = this.saveLatest(context).catch((error: Error) => {
      throw new Error(String(error));
    }).finally(() => {
      if (this.savePromise === pending) {
        this.savePromise = null;
      }
    });
    this.savePromise = pending;
    return pending;
  }

  private async saveLatest(context: common.UIAbilityContext): Promise<void> {
    let savedRevision = -1;
    while (savedRevision !== this.saveRevision) {
      await delay(DOWNLOAD_SAVE_DEBOUNCE_MS);
      const targetRevision = this.saveRevision;
      const values = JSON.stringify(this.items);
      const labels = JSON.stringify(this.labels);
      try {
        const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
        await prefs.put(VALUES_KEY, values);
        await prefs.put(LABELS_KEY, labels);
        await prefs.flush();
      } catch (error) {
        throw new Error(String(error));
      }
      savedRevision = targetRevision;
    }
  }

  private loadLabels(rawLabels: preferences.ValueType): void {
    if (typeof rawLabels !== 'string' || rawLabels.length === 0) {
      return;
    }
    const parsed = JSON.parse(rawLabels) as StoredDownloadLabel[];
    if (!Array.isArray(parsed)) {
      return;
    }
    for (let i = 0; i < parsed.length; i++) {
      const label = storedToDownloadLabel(parsed[i]);
      if (label.label.length > 0 && !this.hasLabel(label.label)) {
        this.labels.push(label);
      }
    }
  }

  private findIndex(gid: number): number {
    const cached = this.cachedItemIndexes.get(gid);
    if (cached !== undefined && cached < this.items.length && this.items[cached].gid === gid) {
      return cached;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        this.cachedItemIndexes.set(gid, i);
        return i;
      }
    }
    return -1;
  }

  private notifyChanged(): void {
    this.cachedItemIndexes.clear();
    if (this.notifyTimer >= 0) {
      clearTimeout(this.notifyTimer);
      this.notifyTimer = -1;
    }
    this.pendingProgress.clear();
    this.emitChanged();
  }

  private scheduleNotifyChanged(item: DownloadInfo): void {
    this.pendingProgress.set(item.gid, item);
    if (this.notifyTimer >= 0) {
      return;
    }
    this.notifyTimer = setTimeout(() => {
      this.notifyTimer = -1;
      this.emitProgress();
    }, DOWNLOAD_NOTIFY_DEBOUNCE_MS) as number;
  }

  private emitChanged(): void {
    galleryStatusStore.syncDownloads(this.items.map((item: DownloadInfo) => item.gid));
    const items = this.getItems();
    const labels = this.getLabels();
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].listener(items, labels);
    }
  }

  private emitProgress(): void {
    const updates: DownloadProgress[] = [];
    this.pendingProgress.forEach((item: DownloadInfo) => {
      updates.push({ gid: item.gid, finished: item.finished, downloaded: item.downloaded, total: item.total,
        speed: item.speed, remaining: item.remaining, fileSize: item.fileSize, archiveUri: item.archiveUri });
    });
    this.pendingProgress.clear();
    let legacyItems: DownloadInfo[] | undefined = undefined;
    let legacyLabels: DownloadLabel[] = [];
    for (const subscription of this.listeners) {
      if (subscription.onProgress !== undefined) {
        subscription.onProgress(updates);
      } else {
        // Preserve the existing API for consumers that require full snapshots.
        if (legacyItems === undefined) {
          legacyItems = this.getItems();
          legacyLabels = this.getLabels();
        }
        subscription.listener(legacyItems, legacyLabels);
      }
    }
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, milliseconds);
  });
}

function galleryToDownloadInfo(gallery: GalleryInfo, label: string): DownloadInfo {
  const tags = galleryDetailTags(gallery);
  const language = galleryDetailLanguage(gallery);
  return {
    gid: gallery.gid,
    token: gallery.token,
    title: gallery.title,
    titleJpn: gallery.titleJpn,
    thumb: gallery.thumb,
    category: gallery.category,
    posted: gallery.posted,
    uploader: gallery.uploader,
    rating: gallery.rating,
    rated: gallery.rated,
    simpleLanguage: gallery.simpleLanguage,
    simpleTags: gallery.simpleTags,
    pages: gallery.pages,
    thumbWidth: gallery.thumbWidth,
    thumbHeight: gallery.thumbHeight,
    favoriteSlot: gallery.favoriteSlot,
    favoriteName: gallery.favoriteName,
    tagList: gallery.tagList,
    detailTags: cloneGalleryTagGroups(tags),
    detailLanguage: language,
    state: DownloadState.None,
    legacy: 0,
    time: Date.now(),
    label: label,
    archiveUri: '',
    speed: 0,
    remaining: 0,
    finished: 0,
    downloaded: 0,
    total: gallery.pages,
    fileSize: -1
  };
}

function storedToDownloadInfo(item: StoredDownloadInfo): DownloadInfo {
  return {
    gid: typeof item.gid === 'number' ? item.gid : 0,
    token: typeof item.token === 'string' ? item.token : '',
    title: typeof item.title === 'string' ? item.title : '',
    titleJpn: item.titleJpn,
    thumb: item.thumb,
    category: typeof item.category === 'number' ? item.category : GalleryCategory.Unknown,
    posted: item.posted,
    uploader: item.uploader,
    rating: typeof item.rating === 'number' ? item.rating : -1,
    rated: typeof item.rated === 'boolean' ? item.rated : false,
    simpleLanguage: item.simpleLanguage,
    simpleTags: item.simpleTags,
    pages: typeof item.pages === 'number' ? item.pages : 0,
    thumbWidth: typeof item.thumbWidth === 'number' ? item.thumbWidth : 0,
    thumbHeight: typeof item.thumbHeight === 'number' ? item.thumbHeight : 0,
    favoriteSlot: typeof item.favoriteSlot === 'number' ? item.favoriteSlot : -2,
    favoriteName: item.favoriteName,
    tagList: item.tagList,
    detailTags: storedToGalleryTagGroups(item.detailTags),
    detailLanguage: item.detailLanguage,
    state: normalizeDownloadState(item.state),
    cloudState: typeof item.cloudState === 'string' ? item.cloudState : '',
    legacy: typeof item.legacy === 'number' ? item.legacy : 0,
    time: typeof item.time === 'number' ? item.time : Date.now(),
    label: typeof item.label === 'string' ? item.label : '',
    archiveUri: typeof item.archiveUri === 'string' ? item.archiveUri : '',
    speed: typeof item.speed === 'number' ? item.speed : 0,
    remaining: typeof item.remaining === 'number' ? item.remaining : 0,
    finished: typeof item.finished === 'number' ? item.finished : 0,
    downloaded: typeof item.downloaded === 'number' ? item.downloaded : 0,
    total: typeof item.total === 'number' ? item.total : (typeof item.pages === 'number' ? item.pages : 0),
    fileSize: typeof item.fileSize === 'number' ? item.fileSize : -1
  };
}

function normalizeDownloadState(value: string | undefined): DownloadState {
  if (value === DownloadState.Wait || value === DownloadState.Downloading || value === DownloadState.Finish ||
    value === DownloadState.Failed || value === DownloadState.Update || value === DownloadState.Invalid) {
    return value as DownloadState;
  }
  return DownloadState.None;
}

function storedToDownloadLabel(item: StoredDownloadLabel): DownloadLabel {
  return {
    label: typeof item.label === 'string' ? normalizeLabel(item.label) : '',
    time: typeof item.time === 'number' ? item.time : Date.now()
  };
}

function normalizeLabel(label: string): string {
  const normalized = label.replace(/\s+/g, ' ').trim();
  if (normalized === 'Default') {
    return '';
  }
  return normalized.length > 40 ? normalized.substring(0, 40).trim() : normalized;
}

function cloneDownloadInfos(items: DownloadInfo[]): DownloadInfo[] {
  const cloned: DownloadInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    cloned.push(cloneDownloadInfo(items[i]));
  }
  return cloned;
}

function cloneDownloadInfo(item: DownloadInfo): DownloadInfo {
  const tags = galleryDetailTags(item);
  const language = galleryDetailLanguage(item);
  return {
    gid: item.gid,
    token: item.token,
    title: item.title,
    titleJpn: item.titleJpn,
    thumb: item.thumb,
    category: item.category,
    posted: item.posted,
    uploader: item.uploader,
    rating: item.rating,
    rated: item.rated,
    simpleLanguage: item.simpleLanguage,
    simpleTags: item.simpleTags,
    pages: item.pages,
    thumbWidth: item.thumbWidth,
    thumbHeight: item.thumbHeight,
    favoriteSlot: item.favoriteSlot,
    favoriteName: item.favoriteName,
    tagList: item.tagList,
    detailTags: cloneGalleryTagGroups(tags),
    detailLanguage: language,
    state: item.state,
    cloudState: item.cloudState,
    legacy: item.legacy,
    time: item.time,
    label: item.label,
    archiveUri: item.archiveUri,
    speed: item.speed,
    remaining: item.remaining,
    finished: item.finished,
    downloaded: item.downloaded,
    total: item.total,
    fileSize: item.fileSize
  };
}

function cloneDownloadLabels(labels: DownloadLabel[]): DownloadLabel[] {
  const cloned: DownloadLabel[] = [];
  for (let i = 0; i < labels.length; i++) {
    cloned.push(cloneDownloadLabel(labels[i]));
  }
  return cloned;
}

function cloneDownloadLabel(label: DownloadLabel): DownloadLabel {
  return {
    label: label.label,
    time: label.time
  };
}

export const ehDownloadStore: EhDownloadStore = new EhDownloadStore();
