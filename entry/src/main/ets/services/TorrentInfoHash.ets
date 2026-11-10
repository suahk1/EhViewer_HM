import { cryptoFramework } from '@kit.CryptoArchitectureKit';

// 从 .torrent 文件字节里算出真正的 info_hash（info 字典原始字节的 SHA1）。
// 注意：EH 种子链接里的 40 位是站点编号，不是 info_hash，不能直接拼磁力。

class LengthResult {
  length: number = -1;
  next: number = 0;
}

function readStringLength(data: Uint8Array, pos: number): LengthResult {
  const r = new LengthResult();
  let value = 0;
  let i = pos;
  while (i < data.length && data[i] >= 0x30 && data[i] <= 0x39) {
    value = value * 10 + (data[i] - 0x30);
    i++;
  }
  if (i < data.length && data[i] === 0x3A) { // ':'
    r.length = value;
    r.next = i + 1;
  } else {
    r.next = i;
  }
  return r;
}

// 跳过位于 pos 的一个 bencode 值，返回它的结束下标（不含）
function skipValue(data: Uint8Array, pos: number): number {
  if (pos >= data.length) {
    return data.length;
  }
  const c = data[pos];
  if (c === 0x69) { // i 整数
    let i = pos + 1;
    while (i < data.length && data[i] !== 0x65) { i++; }
    return Math.min(i + 1, data.length);
  }
  if (c >= 0x30 && c <= 0x39) { // 字符串
    const r = readStringLength(data, pos);
    if (r.length < 0) {
      return data.length;
    }
    return Math.min(r.next + r.length, data.length);
  }
  if (c === 0x6C) { // l 列表
    let i = pos + 1;
    while (i < data.length && data[i] !== 0x65) {
      i = skipValue(data, i);
    }
    return Math.min(i + 1, data.length);
  }
  if (c === 0x64) { // d 字典
    let i = pos + 1;
    while (i < data.length && data[i] !== 0x65) {
      i = skipValue(data, i); // key（字符串）
      i = skipValue(data, i); // value
    }
    return Math.min(i + 1, data.length);
  }
  return data.length;
}

function bytesToAscii(data: Uint8Array, start: number, end: number): string {
  let text = '';
  for (let i = start; i < end; i++) {
    text += String.fromCharCode(data[i]);
  }
  return text;
}

async function sha1Hex(bytes: Uint8Array): Promise<string> {
  const md = cryptoFramework.createMd('SHA1');
  await md.update({ data: bytes });
  const blob = await md.digest();
  let hex = '';
  const arr = new Uint8Array(blob.data);
  for (let i = 0; i < arr.length; i++) {
    hex += (arr[i] < 16 ? '0' : '') + arr[i].toString(16);
  }
  return hex;
}

// 返回 40 位小写 info_hash + 种子内声明的 tracker 列表；解析失败 hash 为空串
export class TorrentMeta {
  hash: string = '';
  trackers: string[] = [];
}

// 读位于 pos 的 bencode 字符串原文（含引号外的原始字节）
function readStringRaw(data: Uint8Array, pos: number): string {
  const r = readStringLength(data, pos);
  if (r.length < 0) {
    return '';
  }
  return bytesToAscii(data, r.next, r.next + r.length);
}

export async function extractTorrentMeta(bytes: ArrayBuffer): Promise<TorrentMeta> {
  const meta = new TorrentMeta();
  const data = new Uint8Array(bytes);
  // 顶层必须是字典
  if (data.length < 2 || data[0] !== 0x64) {
    return meta;
  }
  let i = 1;
  while (i < data.length && data[i] !== 0x65) {
    const key = readStringLength(data, i);
    if (key.length < 0) {
      return meta;
    }
    const keyText = bytesToAscii(data, key.next, key.next + key.length);
    const valueStart = key.next + key.length;
    if (keyText === 'info') {
      const valueEnd = skipValue(data, valueStart);
      if (valueEnd <= valueStart) {
        return meta;
      }
      meta.hash = await sha1Hex(data.subarray(valueStart, valueEnd));
    } else if (keyText === 'announce') {
      const valueEnd = skipValue(data, valueStart);
      const text = readStringRaw(data, valueStart);
      if (valueEnd > valueStart && text.length > 0 && meta.trackers.indexOf(text) < 0) {
        meta.trackers.push(text);
      }
    } else if (keyText === 'announce-list') {
      // announce-list = l (l <url> e)+ e
      let j = valueStart;
      if (j < data.length && data[j] === 0x6C) {
        j++;
        while (j < data.length && data[j] !== 0x65) {
          if (data[j] === 0x6C) {
            j++;
            while (j < data.length && data[j] !== 0x65) {
              const url = readStringRaw(data, j);
              const urlEnd = skipValue(data, j);
              if (url.length > 0 && meta.trackers.indexOf(url) < 0) {
                meta.trackers.push(url);
              }
              j = urlEnd;
            }
            j++;
          } else {
            j = skipValue(data, j);
          }
        }
      }
    }
    i = skipValue(data, valueStart);
  }
  return meta;
}

export async function extractInfoHash(bytes: ArrayBuffer): Promise<string> {
  const meta = await extractTorrentMeta(bytes);
  return meta.hash;
}
