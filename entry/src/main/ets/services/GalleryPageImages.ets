// 画廊页图片解析的公共部分：两个解析器（HTML 版与 API 版）各抄了一份，
// 函数体逐字相同，这里合并成唯一实现。

function decodePageHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

export function parseFirst(body: string, pattern: RegExp): string {
  const match = pattern.exec(body);
  return match === null ? '' : decodePageHtml(match[1]);
}

export function normalizeImageUrl(value: string): string {
  return decodePageHtml(value).trim();
}

export function isImageUrlCandidate(value: string): boolean {
  const lower = value.split('?')[0].toLowerCase();
  return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') ||
    lower.endsWith('.gif');
}
