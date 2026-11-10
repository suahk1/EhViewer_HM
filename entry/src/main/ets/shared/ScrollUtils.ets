// 列表滚动位置归一化。
// 下载页与榜单页各有一份完全相同的实现，合并到这里。

// 小于等于 1 的偏移一律归零：那多半是「回到了顶部」的残留值，不是真实位置。
export function normalizeSceneScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}
