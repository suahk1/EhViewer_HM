import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getAbilityContext } from '../shared/AppRuntime';
import { appLog } from './AppLogService';

const DOMAIN: number = 0x0000;
const TAG: string = 'RemoteStorage';

export function logRemoteStorageInfo(message: string): void {
  hilog.info(DOMAIN, TAG, message);
  const context: common.UIAbilityContext | undefined = getAbilityContext();
  if (context !== undefined) {
    appLog.info(context, TAG, message);
  }
}

export function logRemoteStorageWarn(message: string): void {
  hilog.warn(DOMAIN, TAG, message);
  const context: common.UIAbilityContext | undefined = getAbilityContext();
  if (context !== undefined) {
    appLog.warn(context, TAG, message);
  }
}

export function logRemoteStorageError(message: string): void {
  hilog.error(DOMAIN, TAG, message);
  const context: common.UIAbilityContext | undefined = getAbilityContext();
  if (context !== undefined) {
    appLog.error(context, TAG, message);
  }
}
