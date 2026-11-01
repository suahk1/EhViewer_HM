import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const FILE_LOG_DOMAIN: number = 0x3200;
const FILE_LOG_TAG: string = 'FileIO';

// 建目录失败必须留痕：后面所有的写文件都会失败，但调用方只看到“没生成文件”。
// 删临时文件失败、探测存在性失败保持静默，那是预期内的。
function logFailure(operation: string, path: string, error: Object): void {
  hilog.warn(FILE_LOG_DOMAIN, FILE_LOG_TAG, '%{public}s failed: %{public}s (%{public}s)',
    operation, path, String(error));
}

// 文件系统的最小工具集。
// 这些函数原来在 EhDownloadFileStore / PreviewThumbnailCache / ReaderImageCache /
// DownloadZipImportService / LocalFolderImportService / ParseErrorBodyStore 里各写一份，
// 六份实现逐字相同。抄六遍的后果是改其中一份就漏掉另外五份，所以统一到这里。

export function exists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

export function isDirectory(path: string): boolean {
  try {
    return fs.statSync(path).isDirectory();
  } catch (error) {
    return false;
  }
}

export function ensureDirectory(path: string): void {
  if (exists(path)) {
    return;
  }
  try {
    fs.mkdirSync(path);
  } catch (error) {
    logFailure('mkdir', path, error as Object);
  }
}

export function removeFileQuietly(path: string): void {
  try {
    if (exists(path)) {
      fs.unlinkSync(path);
    }
  } catch (error) {
  }
}

export function writeTextFile(path: string, value: string): void {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    fs.writeSync(fd, value);
  } catch (error) {
    logFailure('write', path, error as Object);
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

export function directoryModifiedTimeMs(directory: string): number {
  try {
    const stat = fs.statSync(directory);
    return stat.mtime > 0 ? Math.round(stat.mtime * 1000) : 0;
  } catch (error) {
    return 0;
  }
}

// 文件字节数；读不到就按 0 处理，调用方用它做配额/清理判断。
export function fileSize(path: string): number {
  try {
    return fs.statSync(path).size;
  } catch (error) {
    return 0;
  }
}

// file:// 前缀剥离。阅读器的三条图片链路都各自抄过一份，统一到这里。
export function stripFileScheme(path: string): string {
  return path.indexOf('file://') === 0 ? path.substring('file://'.length) : path;
}

// 阅读器可用的本地图片：空路径、.part 残留、零字节文件都算不可用。
// ReaderCore 与 ReaderSceneSupport 各有一份相同实现。
export function usableReaderLocalPath(path: string): string {
  if (path.length === 0 || path.endsWith('.part')) {
    return '';
  }
  try {
    return fs.statSync(path).size > 0 ? path : '';
  } catch (error) {
    return '';
  }
}
