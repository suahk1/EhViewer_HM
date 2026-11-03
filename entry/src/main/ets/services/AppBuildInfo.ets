// 必须与 AppScope/app.json5 的 versionName / versionCode 保持一致。
// 改版本要同时改两处：app.json5 的 versionName / versionCode 与这里必须一致。
export const APP_VERSION_NAME: string = '0.1.5';
export const APP_VERSION_CODE: number = 100105;
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
