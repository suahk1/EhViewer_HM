import { escapeRegExp } from './TextMatch';

// 按 class 名找到整段 HTML 块（含嵌套同名标签）。列表解析与详情解析各有一份相同实现。

function isVoidTag(tag: string): boolean {
  return tag === 'img' || tag === 'br' || tag === 'hr' || tag === 'input' || tag === 'meta' || tag === 'link';
}
export function findClassBlock(source: string, className: string): string {
  const startPattern = new RegExp("<[^>]+class=[\"'][^\"']*\\b" + escapeRegExp(className) + "\\b[^\"']*[\"'][^>]*>", 'i');
  const start = startPattern.exec(source);
  if (start === null) {
    return '';
  }

  const openTag = start[0];
  const tagMatch = /^<([a-z0-9]+)/i.exec(openTag);
  if (tagMatch === null) {
    return openTag;
  }

  const tag = tagMatch[1].toLowerCase();
  if (isVoidTag(tag)) {
    return openTag;
  }

  const startIndex = start.index;
  const afterStart = start.index + openTag.length;
  const tagPattern = new RegExp("<\\/?" + tag + "\\b[^>]*>", 'gi');
  tagPattern.lastIndex = afterStart;
  let depth = 1;
  let match: RegExpExecArray | null = tagPattern.exec(source);
  while (match !== null) {
    if (match[0].indexOf('</') === 0) {
      depth--;
      if (depth === 0) {
        return source.substring(startIndex, match.index + match[0].length);
      }
    } else if (!/\/>$/.test(match[0])) {
      depth++;
    }
    match = tagPattern.exec(source);
  }
  return source.substring(startIndex);
}
