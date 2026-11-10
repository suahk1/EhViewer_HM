
import { GallerySite } from '../model/GalleryModels';
import { CLOUD_STATE_GONE, CLOUD_STATE_OK, DownloadInfo, DownloadState, ehDownloadStore } from './EhDownloadStore';
import { EhHttpClient } from './EhHttpClient';

export interface CloudStateVerifyResult {
  checked: number;
  online: number;
  gone: number;
  skipped: number;
}

// 只校验「有云端身份、本机没有文件」的记录：它们要么云端还在（蓝云，联网可读），
// 要么云端已经被删（红云，只能当历史记录）。有本地文件的不必花请求去问。
const VERIFY_INTERVAL_MS: number = 1200;
const MAX_CONSECUTIVE_FAILURES: number = 5;

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

export async function verifyMissingCloudGalleries(site: GallerySite,
  onProgress?: (checked: number, total: number) => void): Promise<CloudStateVerifyResult> {
  const result: CloudStateVerifyResult = { checked: 0, online: 0, gone: 0, skipped: 0 };
  const targets: DownloadInfo[] = [];
  const items = ehDownloadStore.getItems();
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (item.token.length === 0) {
      continue;
    }
    if (item.state !== DownloadState.Missing) {
      continue;
    }
    targets.push(item);
  }
  if (targets.length === 0) {
    return result;
  }
  const client = new EhHttpClient();
  let consecutiveFailures = 0;
  for (let i = 0; i < targets.length; i++) {
    if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
      // 连续失败基本是网络/登录问题，再问下去只会刷屏，剩下的留到下次。
      result.skipped += targets.length - i;
      break;
    }
    const item = targets[i];
    const loaded = await client.loadGalleryDetail(item.gid, item.token, 0, site, '');
    result.checked++;
    if (onProgress !== undefined) {
      onProgress(result.checked, targets.length);
    }
    if (loaded.ok && loaded.detail !== null) {
      ehDownloadStore.setCloudState(item.gid, CLOUD_STATE_OK);
      result.online++;
      consecutiveFailures = 0;
    } else if (loaded.statusCode === 404) {
      ehDownloadStore.setCloudState(item.gid, CLOUD_STATE_GONE);
      result.gone++;
      consecutiveFailures = 0;
    } else {
      consecutiveFailures++;
    }
    await delay(VERIFY_INTERVAL_MS);
  }
  return result;
}
