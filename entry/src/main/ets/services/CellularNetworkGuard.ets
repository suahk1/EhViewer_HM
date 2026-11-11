import { connection } from '@kit.NetworkKit';
import { appSettingsStore } from './AppSettingsStore';

const CELLULAR_WARNING_CONFIRMED_KEY: string = 'ehviewer_cellular_warning_confirmed';

export function cellularNetworkWarningEnabled(): boolean {
  return appSettingsStore.getValue('cellular_network_warning', 'Off') === 'On';
}

export function hasConfirmedCellularNetworkWarning(): boolean {
  return AppStorage.get<boolean>(CELLULAR_WARNING_CONFIRMED_KEY) === true;
}

export function confirmCellularNetworkWarningForSession(): void {
  AppStorage.setOrCreate<boolean>(CELLULAR_WARNING_CONFIRMED_KEY, true);
}

export function resetCellularNetworkWarningConfirmation(): void {
  AppStorage.setOrCreate<boolean>(CELLULAR_WARNING_CONFIRMED_KEY, false);
}

export function shouldWarnForCellularNetwork(): boolean {
  if (!cellularNetworkWarningEnabled()) {
    return false;
  }
  return isDefaultNetworkCellular();
}

export function shouldConfirmCellularNetworkOperation(): boolean {
  return shouldWarnForCellularNetwork() && !hasConfirmedCellularNetworkWarning();
}

// 当前是否有默认网络（WiFi 或蜂窝）。netId 为 0 表示没有可用网络。
// 判断失败时按「有网」处理：宁可让下载自然失败并报原因，也不要误报「网络不可用」。
export function isNetworkOnline(): boolean {
  try {
    return connection.getDefaultNetSync().netId !== 0;
  } catch (error) {
    return true;
  }
}

export function isDefaultNetworkCellular(): boolean {
  try {
    const netHandle = connection.getDefaultNetSync();
    if (netHandle.netId === 0) {
      return false;
    }
    const capabilities = connection.getNetCapabilitiesSync(netHandle);
    const bearerTypes = capabilities.bearerTypes;
    const cellular = bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR);
    const wifi = bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
    // VPN 隧道作为默认网络时 bearer 只带 CELLULAR 不带 WIFI（即便底层是 WiFi），
    // 按原逻辑会误报「移动网络警告」。VPN 下无法判定真实链路，宁可少警告也不误报。
    const vpn = bearerTypes.includes(connection.NetBearType.BEARER_VPN);
    if (vpn) {
      return false;
    }
    return cellular && !wifi;
  } catch (error) {
    return false;
  }
}
