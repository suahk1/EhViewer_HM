import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { getAbilityContext } from '../shared/AppRuntime';

// 应用内下载 hap 到用户选择的目录（默认「下载」），不尝试安装：
// 系统没有 hap 安装器，安装交给 HDC 或调试助手。
export class UpdateSaveResult {
  ok: boolean = false;
  path: string = '';
  message: string = '';
}

function pickFileName(url: string): string {
  const slash = url.lastIndexOf('/');
  const raw = slash >= 0 ? url.substring(slash + 1) : 'update.hap';
  const clean = raw.split('?')[0];
  return clean.length > 0 ? clean : 'update.hap';
}

export async function saveUpdateHap(url: string,
  onProgress: (received: number) => void): Promise<UpdateSaveResult> {
  const result = new UpdateSaveResult();
  const context = getAbilityContext();
  if (context === undefined) {
    result.message = 'No ability context';
    return result;
  }
  if (url.length === 0) {
    result.message = 'Update URL is empty';
    return result;
  }
  const fileName = pickFileName(url);
  let request: http.HttpRequest | null = null;
  try {
    request = http.createHttp();
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 20000,
      readTimeout: 300000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
    if (Number(response.responseCode) !== 200) {
      result.message = 'HTTP ' + response.responseCode;
      return result;
    }
    const bytes = response.result as ArrayBuffer;
    onProgress(bytes.byteLength);

    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    const viewPicker = new picker.DocumentViewPicker(context);
    const uris = await viewPicker.save(options);
    if (uris.length === 0) {
      result.message = 'Save cancelled';
      return result;
    }
    const file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, bytes);
    fs.closeSync(file);
    result.ok = true;
    result.path = fileName;
    return result;
  } catch (error) {
    const err = error as BusinessError;
    result.message = err.code + ' ' + (err.message ?? '');
    return result;
  } finally {
    if (request !== null) {
      request.destroy();
    }
  }
}
