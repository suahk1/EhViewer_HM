import { TorrentInfo } from '../model/GalleryModels';
import { cleanText } from './ParserText';

// 旧结构：<form> 包裹的种子条目
const FORM_PATTERN: RegExp = /<form\b[^>]*>[\s\S]*?<\/form>/gi;
// 兼容两种链接：老式 /xxx/40hex.torrent，新式 /torrent/{gid}/{hash} 或带 hash 查询参数
const TORRENT_LINK_PATTERN: RegExp =
  /<a\b[^>]*href=["']([^"']*(?:\/torrent\/|\.torrent)[^"']*)["'][^>]*>([\s\S]*?)<\/a>/i;

export function parseTorrentList(body: string): TorrentInfo[] {
  const torrents: TorrentInfo[] = [];

  // 路径一：老结构，逐 form 块解析
  FORM_PATTERN.lastIndex = 0;
  let formMatch: RegExpExecArray | null = FORM_PATTERN.exec(body);
  while (formMatch !== null) {
    appendTorrent(torrents, formMatch[0]);
    formMatch = FORM_PATTERN.exec(body);
  }
  if (torrents.length > 0) {
    return torrents;
  }

  // 路径二：EH 现行种子列表是 table 行结构，按 <tr> 切块
  const rows: string[] = body.split(/<tr\b/i);
  for (let i = 0; i < rows.length; i++) {
    appendTorrent(torrents, rows[i]);
  }
  return torrents;
}

function appendTorrent(target: TorrentInfo[], block: string): void {
  const match: RegExpExecArray | null = TORRENT_LINK_PATTERN.exec(block);
  if (match === null) {
    return;
  }
  // 不能去掉 ?p=：那是下载种子用的通行证，去掉后服务器会返回网页而不是种子文件。
  const url = decodeHtml(match[1]).trim();
  const hash = torrentHash(url);
  if (hash.length === 0) {
    // 保留可诊断性：链接格式不认识时打一条，便于后续对照真实 HTML 修正
    console.warn('[torrent] hash unresolved url=' + url);
    return;
  }
  const name = cleanText(match[2]);
  target.push({
    url: url,
    magnetUrl: buildMagnet(hash, name),
    name: name,
    posted: parseTextField(block, 'Posted'),
    size: parseTextField(block, 'Size'),
    seeds: parseNumberField(block, 'Seeds'),
    peers: parseNumberField(block, 'Peers'),
    downloads: parseNumberField(block, 'Downloads')
  });
}

function buildMagnet(hash: string, name: string): string {
  const encoded = name.length > 0 ? encodeURIComponent(name) : hash;
  return 'magnet:?xt=urn:btih:' + hash + '&dn=' + encoded;
}

function parseTextField(block: string, label: string): string {
  const pattern = new RegExp('<span[^>]*>\\s*' + label + ':\\s*<\\/span>\\s*(?:<span[^>]*>)?([^<]+)', 'i');
  const match = pattern.exec(block);
  return match === null ? '' : cleanText(match[1]);
}

function parseNumberField(block: string, label: string): number {
  const value = parseTextField(block, label).replace(/,/g, '');
  const parsed = Number.parseInt(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

// 三层兜底：老格式 → 新式路径 → 查询参数，任一层命中即可
function torrentHash(url: string): string {
  let match: RegExpExecArray | null = /\/([a-f0-9]{40})\.torrent/i.exec(url);
  if (match !== null) {
    return match[1].toLowerCase();
  }
  match = /\/torrent\/\d+\/([a-f0-9]{40})/i.exec(url);
  if (match !== null) {
    return match[1].toLowerCase();
  }
  match = /[?&](?:hash|info_hash|ih)=([a-f0-9]{40})/i.exec(url);
  if (match !== null) {
    return match[1].toLowerCase();
  }
  return '';
}

function stripPrivatePasskey(url: string): string {
  const index = url.indexOf('?p=');
  return index < 0 ? url : url.substring(0, index);
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}
