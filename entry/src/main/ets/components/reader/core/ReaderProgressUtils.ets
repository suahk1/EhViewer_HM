import { ImageDownloadProgress } from '../../../services/ReaderImageCache';

// 下载进度百分比；总字节未知时返回 -1，调用方据此隐藏进度环。
export function readerDownloadProgressPercent(progress: ImageDownloadProgress): number {
  if (progress.totalBytes <= 0) {
    return -1;
  }
  return Math.max(0, Math.min(100, Math.floor(progress.receivedBytes * 100 / progress.totalBytes)));
}
