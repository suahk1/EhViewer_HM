// 下载进度以「页 × 1000」为单位存储，避免浮点误差。
// 这个刻度原来在 DownloadScene / DownloadZipImportService / EhDownloadManager /
// WifiMigrationService 各写一份，改一处就会和另外三处对不上，统一放这里。
export const DOWNLOAD_PAGE_PROGRESS_SCALE: number = 1000;
