import { motion } from '@kit.MultimodalAwarenessKit';

const HOLDING_HAND_SIDE_LEFT: string = 'Left';
const HOLDING_HAND_SIDE_RIGHT: string = 'Right';
const HOLDING_HAND_SIDE_NONE: string = '';

// 传感器在手上稍微挪一下就报状态切换，直接跟随会让 FAB 左右乱跑。
// 候选侧必须稳定这么久才应用，两次切换之间还要有较长冷却，宁可慢也不要抖。
const SIDE_SETTLE_DELAY_MS: number = 2200;
const SIDE_MIN_SWITCH_INTERVAL_MS: number = 4500;

export function holdingHandSwitchDelay(elapsedSinceLastSwitchMs: number): number {
  return Math.max(SIDE_SETTLE_DELAY_MS,
    SIDE_MIN_SWITCH_INTERVAL_MS - Math.max(0, elapsedSinceLastSwitchMs));
}

function floatingActionSideForHoldingHand(status: motion.HoldingHandStatus): string {
  if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
    return HOLDING_HAND_SIDE_LEFT;
  }
  if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
    return HOLDING_HAND_SIDE_RIGHT;
  }
  return HOLDING_HAND_SIDE_NONE;
}

/**
 * 只按「握持手」换边，不再参考「操作手」。
 *
 * 以前这里同时订阅 operatingHandChanged，并把它当握持手的回落值：
 * - 左手握着手机、右手在屏幕上划 → 操作手报 Right → FAB 跳到右边；
 * - 手机放在桌上（没有握持）→ 握持状态为空 → 操作手接管 → 手一动就换边。
 * 这两种情况用户都描述为「没动它自己左右挪」。
 *
 * 现在：只有明确上报 LEFT_HELD / RIGHT_HELD 才换边，双手、未知、无握持一律保持原样。
 */
export function subscribeHoldingHandSide(onChange: (side: string) => void): () => void {
  let subscribed = false;
  let appliedSide = HOLDING_HAND_SIDE_NONE;
  let pendingSide = HOLDING_HAND_SIDE_NONE;
  let pendingTimer = -1;
  let lastAppliedAt = 0;

  const cancelPending = (): void => {
    if (pendingTimer !== -1) {
      clearTimeout(pendingTimer);
      pendingTimer = -1;
    }
    pendingSide = HOLDING_HAND_SIDE_NONE;
  };

  const applySide = (side: string): void => {
    appliedSide = side;
    lastAppliedAt = Date.now();
    onChange(side);
  };

  const scheduleSide = (side: string): void => {
    if (side === appliedSide) {
      cancelPending();
      return;
    }
    // 同一候选侧在等待期内重复上报，不再重置计时；换了方向才重来。
    if (pendingSide === side && pendingTimer !== -1) {
      return;
    }
    cancelPending();
    pendingSide = side;
    const wait = holdingHandSwitchDelay(Date.now() - lastAppliedAt);
    pendingTimer = setTimeout((): void => {
      pendingTimer = -1;
      if (pendingSide === side && side !== appliedSide) {
        applySide(side);
      }
      pendingSide = HOLDING_HAND_SIDE_NONE;
    }, wait);
  };

  const holdingCallback = (status: motion.HoldingHandStatus): void => {
    if (status === motion.HoldingHandStatus.BOTH_HANDS_HELD ||
      status === motion.HoldingHandStatus.UNKNOWN_STATUS) {
      return;
    }
    const side = floatingActionSideForHoldingHand(status);
    // 没有明确握持就保持当前边，不切、也不回落到其它信号。
    if (side.length === 0) {
      return;
    }
    scheduleSide(side);
  };

  try {
    motion.on('holdingHandChanged', holdingCallback);
    subscribed = true;
  } catch (error) {
    return (): void => {};
  }
  return (): void => {
    cancelPending();
    if (subscribed) {
      subscribed = false;
      try {
        motion.off('holdingHandChanged', holdingCallback);
      } catch (error) {
      }
    }
  };
}
