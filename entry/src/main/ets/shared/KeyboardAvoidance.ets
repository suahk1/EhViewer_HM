import { KeyboardAvoidMode, UIContext } from '@kit.ArkUI';

// 全 app 统一用 RESIZE_WITH_CARET：
// - OFFSET（系统默认）会把整页往上推，系统安全键盘占屏很高，顶栏会被顶进状态栏；
// - RESIZE 只把根容器高度收到键盘上沿，标题栏不动，滚动容器自己把输入框带进可视区；
// - WITH_CARET 保证光标始终可见（多行输入、光标行变化时也会跟）。
export const APP_KEYBOARD_AVOID_MODE: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE_WITH_CARET;

export function applyAppKeyboardAvoidModeTo(uiContext: UIContext): void {
  try {
    uiContext.setKeyboardAvoidMode(APP_KEYBOARD_AVOID_MODE);
  } catch (_error) {
  }
}

// 需要临时覆盖的页面（弹层、输入页）在 aboutToAppear 里调用，拿到原值，离开时还原。
export function beginAppKeyboardAvoidance(uiContext: UIContext): KeyboardAvoidMode | null {
  try {
    const previous: KeyboardAvoidMode = uiContext.getKeyboardAvoidMode();
    uiContext.setKeyboardAvoidMode(APP_KEYBOARD_AVOID_MODE);
    return previous;
  } catch (_error) {
    return null;
  }
}

export function restoreAppKeyboardAvoidance(uiContext: UIContext,
  previous: KeyboardAvoidMode | null): void {
  if (previous === null) {
    return;
  }
  try {
    uiContext.setKeyboardAvoidMode(previous);
  } catch (_error) {
  }
}
