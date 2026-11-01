// 解析与校验通用工具。
// 这些函数原先在 5 个 parser / service 里各复制一份，函数体完全一致，
// 改动时容易只改到其中一份，统一收在这里。

export function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function isValidSha(value: string): boolean {
  return /^[0-9a-f]{40}$/i.test(value.trim());
}
