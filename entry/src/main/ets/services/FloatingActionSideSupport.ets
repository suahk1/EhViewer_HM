import { FLOATING_ACTION_SIDE_RIGHT, normalizeFloatingActionSide } from '../components/FloatingActionLayoutSupport';
import { getAbilityContext } from '../shared/AppRuntime';
import { subscribeHoldingHandSide } from './HoldingHandSupport';
import {
  FLOATING_ACTION_HOLDING_HAND_REVISION_KEY,
  FLOATING_ACTION_HOLDING_HAND_SETTING_KEY,
  FLOATING_ACTION_SIDE_REVISION_KEY,
  FLOATING_ACTION_SIDE_SETTING_KEY,
  appSettingsStore
} from './AppSettingsStore';

/**
 * 同步读取已持久化的侧位。页面 @State 的初始值必须用它，不能用常量 RIGHT 兜底：
 * 常量兜底会让「存的是 Left」的设备先按右侧渲染一次，再被 syncFromSettings 弹到左侧，
 * 表现就是切页面时 FAB 从中间往边上飞一下。
 */
export function storedFloatingActionSide(): string {
  return normalizeFloatingActionSide(
    appSettingsStore.getValue(FLOATING_ACTION_SIDE_SETTING_KEY, FLOATING_ACTION_SIDE_RIGHT));
}

/**
 * Shared floating-action side binding for every gallery-style page. It owns the holding-hand
 * subscription, the persisted manual side and the precedence between them, so pages only have to
 * provide the animation callback for their own action dock.
 */
export class FloatingActionSideController {
  private holdingSide: string = '';
  private unsubscribe: () => void = () => {};
  private readonly applySide: (side: string) => void;

  constructor(applySide: (side: string) => void) {
    this.applySide = applySide;
  }

  syncFromSettings(): void {
    // 智感握持刚判出的那一侧要留着：切页面每个页面都会 sync 一次，
    // 先弹回手动位再等传感器重判，用户看到的就是按钮来回跳两下。
    const settledSide = this.holdingSide;
    this.dispose();
    this.applySide(settledSide.length > 0 ? settledSide : this.storedSide());
    // 默认关闭：传感器在手上稍微挪动就会报换手，开着会让 FAB 左右乱跑，
    // 还会把手动拖到的那一边覆盖掉。要自动跟随的用户去设置里显式开启。
    if (appSettingsStore.getValue(FLOATING_ACTION_HOLDING_HAND_SETTING_KEY, 'Off') !== 'On') {
      return;
    }
    this.holdingSide = settledSide;
    this.unsubscribe = subscribeHoldingHandSide((side: string) => {
      this.applyHoldingSide(side);
    });
  }

  handleManualSettingChanged(): void {
    if (this.holdingSide.length > 0) {
      return;
    }
    this.applySide(this.storedSide());
  }

  handleManualSide(side: string): void {
    // 手动拖过就以手动为准：退订传感器并把「智感握持」置 Off。
    // 不置 Off 的话切一次页面会重新订阅，把用户刚摆好的位置拽回去。
    this.dispose();
    const normalized = normalizeFloatingActionSide(side);
    appSettingsStore.setValue(FLOATING_ACTION_SIDE_SETTING_KEY, normalized);
    appSettingsStore.setValue(FLOATING_ACTION_HOLDING_HAND_SETTING_KEY, 'Off');
    const revision = AppStorage.get<number>(FLOATING_ACTION_SIDE_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(FLOATING_ACTION_SIDE_REVISION_KEY, revision + 1);
    // 开关被同步关掉了，必须通知设置页刷新，否则界面上仍显示「开启」，与实际不符。
    const holdingRevision = AppStorage.get<number>(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY, holdingRevision + 1);
    const context = getAbilityContext();
    if (context !== undefined) {
      appSettingsStore.save(context).catch(() => {});
    }
    this.applySide(normalized);
  }

  dispose(): void {
    this.unsubscribe();
    this.unsubscribe = () => {};
    this.holdingSide = '';
  }

  private storedSide(): string {
    return storedFloatingActionSide();
  }

  private applyHoldingSide(side: string): void {
    if (side.length === 0) {
      return;
    }
    this.holdingSide = normalizeFloatingActionSide(side);
    this.applySide(this.holdingSide);
  }
}
