// 全局 chrome（顶栏 + 底坞）显隐信号。
// 列表与下载页各自在滚动帧里算自己的顶栏收起量，这里只把「该不该收」这一件事
// 广播给 Index 里的底坞，避免把回调一层层透传到根组件。
export const APP_CHROME_HIDDEN_KEY: string = 'appChromeHidden';

export function reportAppChromeHidden(hidden: boolean): void {
  // 滚动帧每帧都会走到这里，只有状态翻转时才写 AppStorage，避免逐帧重绘底坞。
  if (AppStorage.get<boolean>(APP_CHROME_HIDDEN_KEY) === hidden) {
    return;
  }
  console.info('AppChrome: hidden=' + hidden.toString());
  AppStorage.setOrCreate<boolean>(APP_CHROME_HIDDEN_KEY, hidden);
}

// 切页、下拉刷新、列表重载时都要把底坞拉回来，否则会出现「内容到顶了底坞还藏着」。
export function resetAppChromeHidden(): void {
  if (AppStorage.get<boolean>(APP_CHROME_HIDDEN_KEY) !== true) {
    return;
  }
  console.info('AppChrome: reset -> visible');
  AppStorage.setOrCreate<boolean>(APP_CHROME_HIDDEN_KEY, false);
}

// 浮层专用信号：搜索栏、设置子面板、图搜等铺满页面时，底坞也要收起。
// 单独一个键，是因为滚动逻辑里列表加载完成会 resetAppChromeHidden()，
// 和浮层共用同一个键会被它顺手清掉，面板开着底坞却又浮上来了。
export const APP_OVERLAY_HIDDEN_KEY: string = 'appOverlayHidden';

export function reportAppOverlayHidden(hidden: boolean): void {
  if (AppStorage.get<boolean>(APP_OVERLAY_HIDDEN_KEY) === hidden) {
    return;
  }
  AppStorage.setOrCreate<boolean>(APP_OVERLAY_HIDDEN_KEY, hidden);
}

// 公共下载（浏览器分享进来）完成后要问「是否删除已处理的压缩包」。
// 这条在 service 层触发，没有 UI 上下文，改成信号交给首页渲染自绘弹窗，
// 不再用系统 showDialog（样式不跟主题）。
export const ZIP_DELETE_ASK_VISIBLE_KEY: string = 'zipDeleteAskVisible';
export const ZIP_DELETE_ASK_MESSAGE_KEY: string = 'zipDeleteAskMessage';
export const ZIP_DELETE_ASK_PATH_KEY: string = 'zipDeleteAskPath';

export function requestZipDeleteAsk(message: string, archivePath: string): void {
  AppStorage.setOrCreate<string>(ZIP_DELETE_ASK_MESSAGE_KEY, message);
  AppStorage.setOrCreate<string>(ZIP_DELETE_ASK_PATH_KEY, archivePath);
  AppStorage.setOrCreate<boolean>(ZIP_DELETE_ASK_VISIBLE_KEY, true);
}

export function clearZipDeleteAsk(): void {
  AppStorage.setOrCreate<boolean>(ZIP_DELETE_ASK_VISIBLE_KEY, false);
}
