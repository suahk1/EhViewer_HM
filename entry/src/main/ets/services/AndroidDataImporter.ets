import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryCategory, GalleryInfo, GallerySite } from '../model/GalleryModels';
import { rebuildImportedHistoryMetadata } from './DownloadMetadataRestore';
import { SearchBookmarkBackupInfo, ehBookmarkStore } from './EhBookmarkStore';
import { DownloadInfo, DownloadState, ehDownloadStore } from './EhDownloadStore';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { ehFilterStore } from './EhFilterStore';
import { ehHistoryStore } from './EhHistoryStore';
import { ehLocalFavoritesStore } from './EhLocalFavoritesStore';
import { HISTORY_INFO_SIZE_KEY, appSettingsStore, historyInfoSizeLimitFromValue } from './AppSettingsStore';
import { ehSearchHistoryStore } from './EhSearchHistoryStore';
import { appKeepAlive } from './AppKeepAlive';
import { ListMode } from './EhUrl';
import { normalizeSubmittedSearchKeywordValue } from './SearchKeywordNormalization';
import {
  CommentBlacklistBackupEntry,
  ehCommentBlacklistStore
} from './EhCommentBlacklistStore';

const SQLITE_HEADER: string = 'SQLite format 3';
const ANDROID_IMPORT_DB_NAME: string = 'ehviewer_android_import.db';

const ANDROID_DOWNLOAD_STATE_INVALID: number = -1;
const ANDROID_DOWNLOAD_STATE_WAIT: number = 1;
const ANDROID_DOWNLOAD_STATE_DOWNLOAD: number = 2;
const ANDROID_DOWNLOAD_STATE_FINISH: number = 3;
const ANDROID_DOWNLOAD_STATE_FAILED: number = 4;
const ANDROID_DOWNLOAD_STATE_UPDATE: number = 5;

export interface AndroidDataImportSummary {
  history: number;
  historySkipped: number;
  // 库里没有 gid 或 token 的记录：导入端无法建出可打开的画廊，只能丢弃。
  // 单独计数，否则「历史 3 条进 2 条、跳过 0」会让人以为数据没丢。
  historyInvalid: number;
  historyMetadata: number;
  historyMetadataFetched: number;
  downloads: number;
  downloadsSkipped: number;
  downloadsMerged: number;
  downloadsLocal: number;
  downloadsLocalSkipped: number;
  localFavorites: number;
  labels: number;
  filters: number;
  searches: number;
  bookmarks: number;
  blacklist: number;
}

interface AndroidHistoryImportResult {
  count: number;
  skipped: number;
  invalid: number;
  items: GalleryInfo[];
}

interface AndroidDownloadImportResult {
  added: number;
  skipped: number;
  merged: number;
  // 安卓端本地图册（DB 里只有标题+gid，没有 token）：按标题反查到本机目录才登记。
  localAdded: number;
  localSkipped: number;
}

export function isAndroidDatabaseBackup(data: Uint8Array): boolean {
  if (data.length < SQLITE_HEADER.length) {
    return false;
  }
  for (let i = 0; i < SQLITE_HEADER.length; i++) {
    if (data[i] !== SQLITE_HEADER.charCodeAt(i)) {
      return false;
    }
  }
  return true;
}

export async function importAndroidDatabaseBackup(context: common.UIAbilityContext,
  data: Uint8Array): Promise<AndroidDataImportSummary> {
  // 导入几千个图册可能跑几分钟，必须挂长时任务，否则切后台就被冻住。
  await appKeepAlive.acquire(context);
  try {
    writeImportDatabase(context, data);
    return await importPreparedDatabase(context);
  } finally {
    await appKeepAlive.release();
  }
}

/**
 * 从文件路径导入：按 1MiB 分块拷贝到临时库，避免把整个备份读进内存。
 * 安卓版数据库通常几 MB，但用户手里可能有上百 MB 的，一次性读会 OOM。
 */
export async function importAndroidDatabaseBackupFromUri(context: common.UIAbilityContext,
  uri: string): Promise<AndroidDataImportSummary> {
  await appKeepAlive.acquire(context);
  try {
    copyFileToImportDatabase(context, uri);
    return await importPreparedDatabase(context);
  } finally {
    await appKeepAlive.release();
  }
}

/** 只读文件头判断是不是 SQLite 备份，不加载整个文件。 */
export function isAndroidDatabaseFile(uri: string): boolean {
  let fd = -1;
  try {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    fd = file.fd;
    const head = new ArrayBuffer(SQLITE_HEADER.length);
    const read = fs.readSync(fd, head, { offset: 0, length: SQLITE_HEADER.length });
    if (read < SQLITE_HEADER.length) {
      return false;
    }
    const bytes = new Uint8Array(head);
    for (let i = 0; i < SQLITE_HEADER.length; i++) {
      if (bytes[i] !== SQLITE_HEADER.charCodeAt(i)) {
        return false;
      }
    }
    return true;
  } catch (error) {
    return false;
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

async function importPreparedDatabase(context: common.UIAbilityContext): Promise<AndroidDataImportSummary> {
  const config: relationalStore.StoreConfig = {
    name: ANDROID_IMPORT_DB_NAME,
    securityLevel: relationalStore.SecurityLevel.S1
  };

  let store: relationalStore.RdbStore | null = null;
  try {
    store = await relationalStore.getRdbStore(context, config);
    await ehHistoryStore.load(context);
    await ehDownloadStore.load(context);
    await ehFilterStore.load(context);
    await ehLocalFavoritesStore.ensureLoaded(context);
    await ehBookmarkStore.ensureLoaded(context);
    await appSettingsStore.load(context);
    await ehSearchHistoryStore.load(context);
    await ehCommentBlacklistStore.ensureLoaded(context);

    const historyResult = await importHistory(store);
    const labels = await importDownloadLabels(store);
    const downloadResult = await importDownloads(store, context);
    const localFavorites = await importLocalFavorites(store);
    const historyMetadata = await rebuildImportedHistoryMetadata(context, historyResult.items, currentImportGallerySite());
    const summary: AndroidDataImportSummary = {
      history: historyResult.count,
      historySkipped: historyResult.skipped,
      historyInvalid: historyResult.invalid,
      historyMetadata: historyMetadata.rebuilt,
      historyMetadataFetched: historyMetadata.fetched,
      labels: labels,
      downloads: downloadResult.added,
      downloadsSkipped: downloadResult.skipped,
      downloadsMerged: downloadResult.merged,
      downloadsLocal: downloadResult.localAdded,
      downloadsLocalSkipped: downloadResult.localSkipped,
      localFavorites: localFavorites,
      filters: await importFilters(store),
      searches: 0,
      bookmarks: await importQuickSearch(store),
      blacklist: await importCommentBlacklist(store)
    };
    summary.searches = summary.bookmarks;

    await Promise.all([
      ehHistoryStore.save(context),
      ehDownloadStore.save(context),
      ehFilterStore.save(context),
      ehLocalFavoritesStore.save(context),
      ehBookmarkStore.save(context),
      ehCommentBlacklistStore.save(context)
    ]);
    return summary;
  } catch (error) {
    throw new Error(String(error));
  } finally {
    if (store !== null) {
      try {
        await store.close();
      } catch (error) {
      }
    }
    await deleteImportStoreQuietly(context, config);
  }
}

async function importHistory(store: relationalStore.RdbStore): Promise<AndroidHistoryImportResult> {
  if (!await tableExists(store, 'HISTORY')) {
    return { count: 0, skipped: 0, invalid: 0, items: [] };
  }
  let count = 0;
  let skipped = 0;
  let invalid = 0;
  const items: GalleryInfo[] = [];
  const historyLimit = historyInfoSizeLimitFromValue(appSettingsStore.getValue(HISTORY_INFO_SIZE_KEY, '100'));
  const historySql = await galleryColumnsSelectSql(store, 'HISTORY');
  await queryEach(store, historySql, (row: relationalStore.ResultSet) => {
    const gallery = readGalleryInfo(row);
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      // 没有 gid/token 就拼不出画廊地址，进来也点不开，只能丢；但要报数。
      invalid++;
      return;
    }
    if (ehHistoryStore.contains(gallery.gid)) {
      skipped++;
      return;
    }
    ehHistoryStore.addGallery(gallery, historyLimit);
    items.push(gallery);
    count++;
  });
  return { count: count, skipped: skipped, invalid: invalid, items: items };
}

async function importDownloadLabels(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'DOWNLOAD_LABELS')) {
    return 0;
  }
  let count = 0;
  await queryEach(store, 'SELECT * FROM "DOWNLOAD_LABELS" ORDER BY "TIME" ASC', (row: relationalStore.ResultSet) => {
    const label = getStringColumn(row, 'LABEL', '').trim();
    if (label.length > 0) {
      if (ehDownloadStore.addLabel(label)) {
        count++;
      }
    }
  });
  return count;
}

async function importDownloads(store: relationalStore.RdbStore,
  context: common.UIAbilityContext): Promise<AndroidDownloadImportResult> {
  const result: AndroidDownloadImportResult = { added: 0, skipped: 0, merged: 0, localAdded: 0, localSkipped: 0 };
  if (!await tableExists(store, 'DOWNLOADS')) {
    return result;
  }
  const downloadsSql = await galleryColumnsSelectSql(store, 'DOWNLOADS');
  await queryEach(store, downloadsSql, (row: relationalStore.ResultSet) => {
    const gallery = readGalleryInfo(row);
    if (gallery.gid <= 0) {
      return;
    }
    if (gallery.token.length === 0) {
      // 安卓端的本地图册：DB 里只有标题 + gid，没有 token。安卓的目录布局和我们不同，
      // 不能照路径搬，只能按标题（含 "数字-标题" 形式）到本机下载根反查。
      // 反查不到就不登记——没有文件的纯记录只会变成点开没内容的一条。
      const localDir = ehDownloadFileStore.resolveGalleryDirectory(context, gallery.gid, gallery.title, '');
      if (localDir.length === 0) {
        result.localSkipped++;
        return;
      }
      const images = ehDownloadFileStore.listPageImages(context, gallery).length;
      if (images <= 0) {
        result.localSkipped++;
        return;
      }
      const localItem: DownloadInfo = {
        gid: gallery.gid,
        token: '',
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
        pages: images,
        thumbWidth: gallery.thumbWidth,
        thumbHeight: gallery.thumbHeight,
        favoriteSlot: gallery.favoriteSlot,
        favoriteName: gallery.favoriteName,
        tagList: gallery.tagList,
        detailTags: gallery.detailTags,
        detailLanguage: gallery.detailLanguage,
        state: DownloadState.Finish,
        legacy: 0,
        time: getNumberColumn(row, 'TIME', Date.now()),
        label: getStringColumn(row, 'LABEL', ''),
        archiveUri: localDir,
        speed: 0,
        remaining: 0,
        finished: images,
        downloaded: 0,
        total: images,
        fileSize: ehDownloadFileStore.directorySizeByPath(localDir)
      };
      const localOutcome = ehDownloadStore.mergeImportedItem(localItem);
      if (localOutcome === 'skipped') {
        result.localSkipped++;
      } else {
        result.localAdded++;
      }
      return;
    }
    const state = getNumberColumn(row, 'STATE', 0);
    const downloadState = mapAndroidDownloadState(state);
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
      detailTags: gallery.detailTags,
      detailLanguage: gallery.detailLanguage,
      state: downloadState,
      legacy: getNumberColumn(row, 'LEGACY', 0),
      time: getNumberColumn(row, 'TIME', Date.now()),
      label: getStringColumn(row, 'LABEL', ''),
      archiveUri: getStringColumn(row, 'ARCHIVE_URI', ''),
      speed: 0,
      remaining: 0,
      finished: downloadState === DownloadState.Finish ? gallery.pages : 0,
      downloaded: 0,
      total: gallery.pages,
      fileSize: -1
    };
    // 目录绑定：安卓备份里的 ARCHIVE_URI 是旧手机路径，本机无效。
    // 按 gid / 标题到本机下载根下找真实目录，找到就绑上并按真实页数归位；
    // 找不到就清掉无效路径，状态留给红云/蓝云角标去表达（不再无脑打 ×）。
    const resolved = ehDownloadFileStore.resolveGalleryDirectory(context, item.gid, item.title, '');
    if (resolved.length > 0) {
      item.archiveUri = resolved;
      // 以前这里直接把 finished 写成库里的总页数，等于伪造进度：
      // 目录里只有几页也会显示「已下载 20/20」。按实际图片数判定。
      const images = ehDownloadFileStore.listPageImages(context, item).length;
      const pages = gallery.pages > 0 ? gallery.pages : images;
      item.total = pages;
      item.finished = images;
      item.state = pages > 0 && images >= pages ? DownloadState.Finish : DownloadState.Failed;
    } else {
      item.archiveUri = '';
      if (item.state === DownloadState.Finish) {
        item.state = DownloadState.Missing;
      }
    }
    // 双轨查重：同 gid 或同标题（本机纯本地图档）都合并成一条，不重复、不丢云端身份。
    const outcome = ehDownloadStore.mergeImportedItem(item);
    if (outcome === 'skipped') {
      result.skipped++;
    } else if (outcome === 'added') {
      result.added++;
    } else {
      result.merged++;
    }
  });
  return result;
}

async function importLocalFavorites(store: relationalStore.RdbStore): Promise<number> {
  if (await tableExists(store, 'LOCAL_FAVORITES')) {
    return importLocalFavoritesFromTable(store, 'LOCAL_FAVORITES');
  }
  if (await tableExists(store, 'local_favourite')) {
    return importLegacyLocalFavorites(store);
  }
  return 0;
}

async function importLocalFavoritesFromTable(store: relationalStore.RdbStore, table: string): Promise<number> {
  let count = 0;
  const favoritesSql = await galleryColumnsSelectSql(store, table);
  await queryEach(store, favoritesSql, (row: relationalStore.ResultSet) => {
    const gallery = readGalleryInfo(row);
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }
    gallery.favoriteSlot = -1;
    gallery.favoriteName = undefined;
    if (ehLocalFavoritesStore.importGallery(gallery, getNumberColumn(row, 'TIME', Date.now()))) {
      count++;
    }
  });
  return count;
}

async function importLegacyLocalFavorites(store: relationalStore.RdbStore): Promise<number> {
  let count = 0;
  const legacySql = await galleryColumnsSelectSql(store, 'local_favourite');
  await queryEach(store, legacySql, (row: relationalStore.ResultSet) => {
    const gallery = readGalleryInfo(row);
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }
    gallery.favoriteSlot = -1;
    gallery.favoriteName = undefined;
    if (ehLocalFavoritesStore.importGallery(gallery, getNumberColumn(row, 'TIME', Date.now()))) {
      count++;
    }
  });
  return count;
}

async function importFilters(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'FILTER')) {
    return 0;
  }
  let count = 0;
  await queryEach(store, 'SELECT * FROM "FILTER" ORDER BY "_id" ASC', (row: relationalStore.ResultSet) => {
    const mode = getNumberColumn(row, 'MODE', 0);
    const text = getStringColumn(row, 'TEXT', '').trim();
    const enabled = getNumberColumn(row, 'ENABLE', 1) !== 0;
    if (text.length > 0 && ehFilterStore.addRule(mode, text, enabled)) {
      count++;
    }
  });
  return count;
}

async function importQuickSearch(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'QUICK_SEARCH')) {
    return 0;
  }
  let count = 0;
  await queryEach(store, 'SELECT * FROM "QUICK_SEARCH" ORDER BY "TIME" ASC', (row: relationalStore.ResultSet) => {
    const mode = getNumberColumn(row, 'MODE', 0);
    let sourceKeyword = getStringColumn(row, 'KEYWORD', '').trim();
    // 原安卓应用旧库的 uploader 模式关键词会带前缀，导入时按官方迁移逻辑去掉。
    if (mode === ListMode.Uploader && sourceKeyword.startsWith('uploader:')) {
      sourceKeyword = sourceKeyword.substring('uploader:'.length).trim();
    }
    const keyword = normalizeSubmittedSearchKeywordValue(sourceKeyword);
    if (keyword.length > 0) {
      ehSearchHistoryStore.record(keyword);
    }
    const bookmark: SearchBookmarkBackupInfo = {
      name: normalizedAndroidBookmarkName(getStringColumn(row, 'NAME', '').trim(), sourceKeyword, keyword),
      mode: mode,
      category: getNumberColumn(row, 'CATEGORY', GalleryCategory.None),
      keyword: keyword,
      advanceSearch: getNumberColumn(row, 'ADVANCE_SEARCH', -1),
      minRating: getNumberColumn(row, 'MIN_RATING', -1),
      pageFrom: getNumberColumn(row, 'PAGE_FROM', -1),
      pageTo: getNumberColumn(row, 'PAGE_TO', -1),
      time: getNumberColumn(row, 'TIME', Date.now())
    };
    if (ehBookmarkStore.importBookmark(bookmark)) {
      count++;
    }
  });
  return count;
}

function normalizedAndroidBookmarkName(name: string, sourceKeyword: string, keyword: string): string {
  // Let EhBookmarkStore derive a mode-specific fallback name for empty
  // subscription/home bookmarks instead of rejecting them as unnamed.
  if (name.length === 0) {
    return keyword.length > 0 ? keyword : name;
  }
  if (name === sourceKeyword && keyword.length > 0) {
    return keyword;
  }
  return name;
}

async function importCommentBlacklist(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'Black_List')) {
    return 0;
  }
  const items: CommentBlacklistBackupEntry[] = [];
  await queryEach(store, 'SELECT * FROM "Black_List" ORDER BY "_id" ASC',
    (row: relationalStore.ResultSet) => {
      const user = getStringColumn(row, 'BADGAYNAME', '').trim();
      if (user.length === 0) {
        return;
      }
      const sourceComment = getStringColumn(row, 'ANGRYWITH', '').trim();
      const addTime = getStringColumn(row, 'ADD_TIME', '').trim();
      const parsedTime = Date.parse(addTime);
      items.push({
        user: user,
        reason: getStringColumn(row, 'REASON', '').trim(),
        sourceComment: sourceComment === '/手动添加/' ? '' : sourceComment,
        addedAt: Number.isFinite(parsedTime) ? parsedTime : Date.now()
      });
    });
  return ehCommentBlacklistStore.importBackupItems(items);
}

function currentImportGallerySite(): GallerySite {
  return appSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? GallerySite.Ex : GallerySite.E;
}

async function tableExists(store: relationalStore.RdbStore, table: string): Promise<boolean> {
  let resultSet: relationalStore.ResultSet | null = null;
  try {
    resultSet = await store.querySql('SELECT name FROM sqlite_master WHERE type = ? AND name = ?', ['table', table]);
    return resultSet.goToFirstRow();
  } catch (error) {
    return false;
  } finally {
    closeResultSetQuietly(resultSet);
  }
}

async function hasColumn(store: relationalStore.RdbStore, table: string, column: string): Promise<boolean> {
  let resultSet: relationalStore.ResultSet | null = null;
  try {
    resultSet = await store.querySql('SELECT * FROM "' + table + '" LIMIT 1');
    return resultSet.getColumnIndex(column) >= 0;
  } catch (error) {
    return false;
  } finally {
    closeResultSetQuietly(resultSet);
  }
}

// 新版规范化库（HISTORY / DOWNLOADS / LOCAL_FAVORITES 只存 GID，画廊详情在 GALLERIES 表）缺少
// TOKEN/TITLE 等列，需要 JOIN GALLERIES 才能还原；旧版去规范化库自带这些列，直接全量读取即可。
async function galleryColumnsSelectSql(store: relationalStore.RdbStore, table: string): Promise<string> {
  if (await hasColumn(store, table, 'TOKEN')) {
    return 'SELECT * FROM "' + table + '" ORDER BY "TIME" ASC';
  }
  if (await tableExists(store, 'GALLERIES')) {
    const a = table.toLowerCase();
    return 'SELECT ' + a + '.*, ' +
      'g."TOKEN" AS "TOKEN", g."TITLE" AS "TITLE", g."TITLE_JPN" AS "TITLE_JPN", ' +
      'g."THUMB" AS "THUMB", g."CATEGORY" AS "CATEGORY", g."POSTED" AS "POSTED", ' +
      'g."UPLOADER" AS "UPLOADER", g."RATING" AS "RATING", ' +
      'g."SIMPLE_LANGUAGE" AS "SIMPLE_LANGUAGE", g."PAGES" AS "PAGES", ' +
      'g."SIMPLE_TAGS" AS "SIMPLE_TAGS", g."FAVORITE_SLOT" AS "FAVORITE_SLOT" ' +
      'FROM "' + table + '" ' + a + ' JOIN "GALLERIES" g ON g."GID" = ' + a + '."GID" ' +
      'ORDER BY ' + a + '."TIME" ASC';
  }
  return 'SELECT * FROM "' + table + '" ORDER BY "TIME" ASC';
}

async function queryEach(store: relationalStore.RdbStore, sql: string,
  visitor: (row: relationalStore.ResultSet) => void): Promise<void> {
  let resultSet: relationalStore.ResultSet | null = null;
  try {
    resultSet = await store.querySql(sql);
    while (resultSet.goToNextRow()) {
      visitor(resultSet);
    }
  } catch (error) {
    throw new Error(String(error));
  } finally {
    closeResultSetQuietly(resultSet);
  }
}

function readGalleryInfo(row: relationalStore.ResultSet): GalleryInfo {
  return {
    gid: getNumberColumn(row, 'GID', 0),
    token: getStringColumn(row, 'TOKEN', ''),
    title: getStringColumn(row, 'TITLE', ''),
    titleJpn: getOptionalStringColumn(row, 'TITLE_JPN'),
    thumb: getOptionalStringColumn(row, 'THUMB'),
    category: getNumberColumn(row, 'CATEGORY', GalleryCategory.Unknown),
    posted: getOptionalStringColumn(row, 'POSTED'),
    uploader: getOptionalStringColumn(row, 'UPLOADER'),
    rating: getNumberColumn(row, 'RATING', -1),
    rated: false,
    simpleLanguage: getOptionalStringColumn(row, 'SIMPLE_LANGUAGE'),
    pages: getNumberColumn(row, 'PAGES', 0),
    simpleTags: parseSimpleTags(getOptionalStringColumn(row, 'SIMPLE_TAGS')),
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: getNumberColumn(row, 'FAVORITE_SLOT', -2)
  };
}

function parseSimpleTags(raw: string | undefined): string[] | undefined {
  if (raw === undefined || raw.length === 0) {
    return undefined;
  }
  const parts: string[] = [];
  const chunks = raw.split(',');
  for (let i = 0; i < chunks.length; i++) {
    const tag = chunks[i].trim();
    if (tag.length > 0) {
      parts.push(tag);
    }
  }
  return parts.length > 0 ? parts : undefined;
}

function mapAndroidDownloadState(state: number): DownloadState {
  if (state === ANDROID_DOWNLOAD_STATE_INVALID) {
    return DownloadState.Invalid;
  }
  if (state === ANDROID_DOWNLOAD_STATE_WAIT) {
    return DownloadState.Wait;
  }
  if (state === ANDROID_DOWNLOAD_STATE_DOWNLOAD) {
    return DownloadState.Downloading;
  }
  if (state === ANDROID_DOWNLOAD_STATE_FINISH) {
    return DownloadState.Finish;
  }
  if (state === ANDROID_DOWNLOAD_STATE_FAILED) {
    return DownloadState.Failed;
  }
  if (state === ANDROID_DOWNLOAD_STATE_UPDATE) {
    return DownloadState.Update;
  }
  return DownloadState.None;
}

function getOptionalStringColumn(row: relationalStore.ResultSet, name: string): string | undefined {
  const value = getStringColumn(row, name, '');
  return value.length > 0 ? value : undefined;
}

function getStringColumn(row: relationalStore.ResultSet, name: string, fallback: string): string {
  try {
    const index = row.getColumnIndex(name);
    if (index < 0 || row.isColumnNull(index)) {
      return fallback;
    }
    return row.getString(index);
  } catch (error) {
    return fallback;
  }
}

function getNumberColumn(row: relationalStore.ResultSet, name: string, fallback: number): number {
  try {
    const index = row.getColumnIndex(name);
    if (index < 0 || row.isColumnNull(index)) {
      return fallback;
    }
    return row.getDouble(index);
  } catch (error) {
    return fallback;
  }
}

const IMPORT_COPY_CHUNK: number = 1024 * 1024;
const IMPORT_MAX_BYTES: number = 512 * 1024 * 1024;

function copyFileToImportDatabase(context: common.UIAbilityContext, uri: string): void {
  const dbDir = context.databaseDir + '/rdb';
  ensureDirectory(dbDir);
  const dbPath = dbDir + '/' + ANDROID_IMPORT_DB_NAME;
  let srcFd = -1;
  let dstFd = -1;
  try {
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    srcFd = src.fd;
    const size = fs.statSync(srcFd).size;
    if (size <= 0) {
      throw new Error('empty backup file');
    }
    if (size > IMPORT_MAX_BYTES) {
      throw new Error('backup file too large: ' + size.toString());
    }
    const dst = fs.openSync(dbPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    dstFd = dst.fd;
    const chunk = new ArrayBuffer(IMPORT_COPY_CHUNK);
    let copied = 0;
    while (copied < size) {
      const want = Math.min(IMPORT_COPY_CHUNK, size - copied);
      const read = fs.readSync(srcFd, chunk, { offset: copied, length: want });
      if (read <= 0) {
        break;
      }
      fs.writeSync(dstFd, chunk, { length: read });
      copied += read;
    }
    if (copied !== size) {
      throw new Error('backup file truncated: ' + copied.toString() + '/' + size.toString());
    }
  } finally {
    if (srcFd >= 0) {
      try {
        fs.closeSync(srcFd);
      } catch (error) {
      }
    }
    if (dstFd >= 0) {
      try {
        fs.closeSync(dstFd);
      } catch (error) {
      }
    }
  }
}

function writeImportDatabase(context: common.UIAbilityContext, data: Uint8Array): void {
  const dbDir = context.databaseDir + '/rdb';
  ensureDirectory(dbDir);
  const dbPath = dbDir + '/' + ANDROID_IMPORT_DB_NAME;
  let fd = -1;
  try {
    const file = fs.openSync(dbPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    fs.writeSync(fd, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
  } catch (error) {
    throw new Error(String(error));
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

async function deleteImportStoreQuietly(context: common.UIAbilityContext,
  config: relationalStore.StoreConfig): Promise<void> {
  try {
    await relationalStore.deleteRdbStore(context, config);
  } catch (error) {
  }
}

function ensureDirectory(path: string): void {
  try {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  } catch (error) {
    try {
      fs.mkdirSync(path, true);
    } catch (innerError) {
    }
  }
}

function closeResultSetQuietly(resultSet: relationalStore.ResultSet | null): void {
  if (resultSet === null) {
    return;
  }
  try {
    resultSet.close();
  } catch (error) {
  }
}
