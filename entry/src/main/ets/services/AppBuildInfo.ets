import { bundleManager } from '@kit.AbilityKit';

// 这两项只作为兜底：界面显示一律走 appVersionName() / appVersionCode()，
// 从 BundleInfo 运行时读取，避免改了 app.json5 却忘了改常量（曾经出现过
// 关于页显示 0.1.0、实际安装包是 0.1.1 的情况）。
export const APP_VERSION_NAME: string = '0.1.0';
export const APP_VERSION_CODE: number = 100100;
export const TARGET_PLATFORM: string = 'HarmonyOS 26.0.0 / compatible API 6.0.0(20)';
// 制作者信息：应用由 IFSM 维护，上游为 EhViewer（Android）开源项目。
export const APP_AUTHOR_NAME: string = 'IFSM';
export const APP_AUTHOR_URL: string = '';
// 检查更新、反馈、GitHub 外链都从这里取地址。换仓库只改这一处。
export const EH_REPOSITORY_NAME: string = 'suahk1/EhViewer_HM';
export const EH_REPOSITORY_URL: string = 'https://github.com/' + EH_REPOSITORY_NAME;
export const EH_REPOSITORY_CONFIGURED: boolean = true;
export const EH_RELEASE_TAG: string = 'v' + APP_VERSION_NAME;
export const EH_RELEASE_URL: string = EH_REPOSITORY_URL + '/releases/tag/' + EH_RELEASE_TAG;
export const EH_ISSUES_URL: string = EH_REPOSITORY_URL + '/issues';
// 捐赠页地址。留空时「关于 → 捐赠」只显示提示，不跳转。
export const EH_DONATE_URL: string = '';

export function appVersionName(): string {
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    const name = info.versionName;
    return name !== undefined && name.length > 0 ? name : APP_VERSION_NAME;
  } catch (error) {
    return APP_VERSION_NAME;
  }
}

export function appVersionCode(): number {
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return info.versionCode > 0 ? info.versionCode : APP_VERSION_CODE;
  } catch (error) {
    return APP_VERSION_CODE;
  }
}
