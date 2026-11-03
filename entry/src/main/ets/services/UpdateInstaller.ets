import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { getAbilityContext } from '../shared/AppRuntime';

// 应用商店之外的 hap 只能由系统安装器落地：应用负责把包下到本地，
// 再用 Want 拉起安装界面，用户确认后覆盖安装。

export class UpdateDownloadResult {
  path: string = '';
  ok: boolean = false;
  message: string = '';
}

function sanitizeFileName(raw: string): string {
  const name = raw.length > 0 ? raw : 'update.hap';
  return name.replace(/[\\/:*?"<>|]/g, '_');
}

export async function downloadUpdateHap(url: string, fileName: string,
  onProgress: (received: number, total: number) => void): Promise<UpdateDownloadResult> {
  const result = new UpdateDownloadResult();
  if (url.length === 0) {
    result.message = 'Update URL is empty';
    return result;
  }
  const context = getAbilityContext();
  if (context === undefined) {
    result.message = 'No ability context';
    return result;
  }
  const dir = context.filesDir + '/update';
  try {
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }
  } catch (error) {
    result.message = 'Cannot create update dir';
    return result;
  }
  const path = dir + '/' + sanitizeFileName(fileName);
  let request: http.HttpRequest | null = null;
  let file: fs.File | null = null;
  try {
    file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    request = http.createHttp();
    // 该 SDK 版本没有流式回调，18MB 包整体取回后一次写盘
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 20000,
      readTimeout: 300000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
    const statusCode = Number(response.responseCode);
    if (statusCode !== 200) {
      result.message = 'Download failed: HTTP ' + statusCode;
      return result;
    }
    const bytes = response.result as ArrayBuffer;
    fs.writeSync(file.fd, bytes);
    onProgress(bytes.byteLength, bytes.byteLength);
    fs.closeSync(file);
    file = null;
    result.path = path;
    result.ok = true;
    result.message = 'Downloaded';
    return result;
  } catch (error) {
    const err = error as BusinessError;
    result.message = 'Download failed: ' + err.code + ' ' + (err.message ?? '');
    return result;
  } finally {
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (_e) {
        // 关闭失败不影响结果
      }
    }
    if (request !== null) {
      request.destroy();
    }
  }
}

// 依次尝试安装器可接受的 Want，成功拉起返回 true
export function installHap(path: string): boolean {
  const context = getAbilityContext();
  if (context === undefined || path.length === 0) {
    return false;
  }
  const uri = fileUri.getUriFromPath(path);
  const wants: Want[] = [
    { action: 'ohos.want.action.install', uri: uri },
    { action: 'ohos.want.action.viewData', uri: uri, type: 'application/vnd.harmonyos.package' },
    { action: 'ohos.want.action.viewData', uri: uri, type: 'general.package' }
  ];
  for (let i = 0; i < wants.length; i++) {
    try {
      context.startAbility(wants[i]).catch(() => {});
      return true;
    } catch (_e) {
      // 换下一个
    }
  }
  return false;
}

export async function shareHap(path: string): Promise<void> {
  const context = getAbilityContext();
  if (context === undefined || path.length === 0) {
    return;
  }
  const shareData = new systemShare.SharedData({
    utd: utd.UniformDataType.FILE,
    uri: fileUri.getUriFromPath(path),
    title: 'EhViewer update'
  });
  const controller = new systemShare.ShareController(shareData);
  await controller.show(context, {
    selectionMode: systemShare.SelectionMode.SINGLE,
    previewMode: systemShare.SharePreviewMode.DETAIL
  });
}
