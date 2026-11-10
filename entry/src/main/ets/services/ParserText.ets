import { decodeHtmlEntities } from '../shared/HtmlEntitySupport';

// 抓取结果的纯文本清洗：去标签、解实体、压缩空白。
// 五个解析器各抄了一份完全相同的实现，而它们各自的 decodeHtml 处理范围又不一样
// （有的解 &nbsp;，有的解 &#038;），同一段 HTML 会得出不同文本。统一走完整实体解码。
export function cleanText(value: string): string {
  return decodeHtmlEntities(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}
