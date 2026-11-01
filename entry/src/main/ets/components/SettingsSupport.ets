import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
} from '../services/EhDownloadFileStore';
import {
  APP_VERSION_CODE,
  APP_VERSION_NAME,
  EH_ISSUES_URL,
  TARGET_PLATFORM,
} from '../services/AppBuildInfo';
import {
  appSettingsStore,
} from '../services/AppSettingsStore';
import {
  socks5ProxySupported,
} from '../services/NetworkConfig';
import {
  TRANSLATION_CONVERSATION_LOG_SETTING_KEY,
} from '../services/TranslationConversationLog';
import { SettingsRowItem, uiText, uiValue, padTwo, normalizeProxyOption, normalizeAutoTransferTimeOption, normalizeBrightnessLevelOption, normalizeUltraDarkLightnessOption } from '../shared/AppRuntime';

export const DIAGNOSTIC_LOG_TAG: string = 'SettingsScene';
export const LOG_EXPORT_CHUNK_BYTES: number = 64 * 1024;
export const EH_LICENSE_URL: string = 'https://www.gnu.org/licenses/gpl-3.0.html';
export function settingsRowActionText(row: SettingsRowItem): string {
  if (row.value.length > 0) {
    return uiValue(row.value);
  }
  return uiText('Open');
}

export function isSecretSettingKey(key: string | undefined): boolean {
  return key === 'proxy_password' || key === 'translation_deepseek_api_key' ||
    key === 'translation_openai_api_key' || key === 'translation_official_openai_api_key' ||
    key === 'translation_custom_api_key' || key === 'translation_gemini_api_key';
}

export function isDirectTranslationApiKey(key: string): boolean {
  return key === 'translation_deepseek_api_key' || key === 'translation_official_openai_api_key' ||
    key === 'translation_gemini_api_key';
}

export function cleanErrorMessage(error: Error): string {
  let message = error.message.length > 0 ? error.message : String(error);
  while (message.indexOf('Error: ') === 0) {
    message = message.substring('Error: '.length);
  }
  return message;
}

export function isCustomTranslationApiField(key: string): boolean {
  return key === 'translation_custom_api_name' || key === 'translation_custom_api_base_url' ||
    key === 'translation_custom_api_key' || key === 'translation_custom_api_model';
}

export function isTranslationSettingKey(key: string): boolean {
  return key.indexOf('translation_') === 0 && key !== TRANSLATION_CONVERSATION_LOG_SETTING_KEY;
}

export function settingsSliderNumberValue(row: SettingsRowItem): number {
  if (row.key === 'start_transfer_time') {
    return Number.parseInt(normalizeAutoTransferTimeOption(row.value));
  }
  if (row.key === 'screen_lightness') {
    return Number.parseInt(normalizeBrightnessLevelOption(row.value));
  }
  // 超暗模式亮度也是滑块。这里曾经漏掉，导致它永远初始化为 0%，
  // 与已保存的值无关；拖一下才跳到拖到的位置。
  if (row.key === 'ultra_dark_lightness') {
    return Number.parseInt(normalizeUltraDarkLightnessOption(row.value));
  }
  return 0;
}

export function settingsSliderMin(row: SettingsRowItem): number {
  return row.key === 'start_transfer_time' || row.key === 'ultra_dark_lightness' ? 1 : 0;
}

export function settingsSliderMax(row: SettingsRowItem): number {
  return row.key === 'start_transfer_time' ? 20 : 100;
}

export function settingsSliderTextValue(row: SettingsRowItem, value: number): string {
  if (row.key === 'start_transfer_time') {
    return normalizeAutoTransferTimeOption(Math.max(1, Math.min(20, Math.round(value))).toString() + 's');
  }
  if (row.key === 'ultra_dark_lightness') {
    return normalizeUltraDarkLightnessOption(Math.round(value).toString() + '%');
  }
  return normalizeBrightnessLevelOption(Math.max(0, Math.min(100, Math.round(value))).toString() + '%');
}

export function settingsSliderDisplayText(row: SettingsRowItem, value: number): string {
  return uiValue(settingsSliderTextValue(row, value));
}

export function normalizeSettingsDownloadLocation(value: string): string {
  return value === DOWNLOAD_LOCATION_DOWNLOADS ? DOWNLOAD_LOCATION_DOWNLOADS : DOWNLOAD_LOCATION_APP_FILES;
}

export async function pickDownloadsOutputPath(context: common.UIAbilityContext, fileName: string): Promise<string> {
  const saveOptions = new picker.DocumentSaveOptions();
  saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
  const documentPicker = new picker.DocumentViewPicker(context);
  const result = await documentPicker.save(saveOptions);
  if (result.length === 0 || result[0].length === 0) {
    return '';
  }
  return new fileUri.FileUri(result[0] + '/' + sanitizeExportFileName(fileName)).path;
}

export function sanitizeExportFileName(fileName: string): string {
  return fileName.replace(/[\\/:*?"<>|]/g, '_');
}

export async function writeTextFileChunked(path: string, content: string): Promise<void> {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    for (let start = 0; start < content.length; start += LOG_EXPORT_CHUNK_BYTES) {
      fs.writeSync(fd, content.substring(start, Math.min(content.length, start + LOG_EXPORT_CHUNK_BYTES)));
      await yieldToUi();
    }
  } catch (error) {
    removeFileQuietly(path);
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

export function removeFileQuietly(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (error) {
  }
}

export function yieldToUi(): Promise<void> {
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    setTimeout(() => {
      resolve();
    }, 0);
  });
}

export function settingsRowRenderKey(row: SettingsRowItem): string {
  if (row.type === 'switch') {
    // A value change must update the existing Toggle, not replace it during onChange/theme refresh.
    return (row.key ?? row.title) + ':' + row.type + ':' + row.title;
  }
  if (row.type === 'slider') {
    return row.title + ':' + row.type;
  }
  return row.title + ':' + row.value + ':' + row.type;
}

export function isNetworkSettingKey(key: string): boolean {
  return key === 'proxy' || key === 'proxy_host' || key === 'proxy_port' || key === 'proxy_username' ||
    key === 'proxy_password' || key === 'proxy_exclusion_list' || key === 'proxy_socks_dns' ||
    key === 'built_in_hosts' ||
    key === 'built_ex_hosts' || key === 'dns_over_https' || key === 'dns_over_https_provider' ||
    key === 'domain_fronting' ||
    key === 'auto_direct_connection' || key === 'gallery_site';
}

export function normalizeProxyExclusionListText(value: string): string {
  const parts = value.split(',');
  const result: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const item = parts[i].trim();
    if (item.length > 0 && result.indexOf(item) < 0) {
      result.push(item);
    }
  }
  return result.join(',');
}

export function proxyDiagnosticText(): string {
  const proxy = normalizeProxyOption(appSettingsStore.getValue('proxy', 'System'));
  if (proxy !== 'HTTP' && proxy !== 'SOCKS') {
    return proxy;
  }
  const host = appSettingsStore.getValue('proxy_host', '').trim();
  const port = appSettingsStore.getValue('proxy_port', '').trim();
  const username = appSettingsStore.getValue('proxy_username', '').trim();
  const exclusions = appSettingsStore.getValue('proxy_exclusion_list', '').trim();
  let text = proxy + ' ' + (host.length > 0 ? host : '(missing host)') + ':' +
    (port.length > 0 ? port : '(missing port)');
  if (username.length > 0) {
    text += ' user=' + username + ' password=***';
  }
  if (exclusions.length > 0) {
    text += ' exclusions=' + exclusions;
  }
  if (proxy === 'SOCKS') {
    text += ' dns=' + appSettingsStore.getValue('proxy_socks_dns', 'Proxy');
    if (!socks5ProxySupported()) {
      text += ' unavailable(api<26)';
    }
  }
  return text;
}

export function settingDisplayValueForStatus(key: string, value: string): string {
  if (isSecretSettingKey(key) && value.length > 0) {
    return '***';
  }
  return value;
}

// GitHub Issues 的新建页支持用查询参数预填标题和正文。
// 反馈里天然带着版本与平台，用户不用手抄，我们也少一轮来回确认。
export function feedbackIssueUrl(): string {
  const body = '### 版本\n' + APP_VERSION_NAME + ' (' + APP_VERSION_CODE.toString() + ')\n\n' +
    '### 平台\n' + TARGET_PLATFORM + '\n\n' +
    '### 问题描述\n\n\n' +
    '### 复现步骤\n1. \n\n' +
    '### 期望结果\n\n';
  return EH_ISSUES_URL + '/new?title=' + encodeURIComponent('反馈：') +
    '&body=' + encodeURIComponent(body);
}

// ArkTS 里 catch 到的是 Object，直接取 .message 有时拿到的是对象本身，
// 弹窗就会显示 "Failed: [object Object]"。统一按 message → String 的顺序取。
export function errorText(error: Object): string {
  // String(Error) 会给出 "Error: 具体原因"，直接可用；
  // 普通对象才会得到 "[object Object]"，那时再取 message / code。
  let text = error === null || error === undefined ? '' : String(error);
  if (text.indexOf('Error: ') === 0) {
    text = text.substring(7);
  }
  if (text === '[object Object]' || text.length === 0) {
    const fields = error as Record<string, Object>;
    const message = fields['message'];
    if (message !== undefined && message !== null) {
      text = String(message);
    }
    if (text === '[object Object]' || text.length === 0) {
      const code = fields['code'];
      text = code !== undefined && code !== null ? 'code ' + String(code) : '';
    }
  }
  if (text === 'undefined' || text === 'null') {
    text = '';
  }
  return text.length > 0 ? text : 'Unknown error';
}
