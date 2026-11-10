import { socket } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';

// DNS 与 TLS 全灭时的最后兜底：TCPSocket + TLSSocket 裸拉图片。
// 适用场景：移动网络对境外图片 CDN 的域名 SNI 做阻断（ClientHello 即被 RST），
// 而对「IP 作为 SNI」放行——此时 http 栈（URL=域名→SNI=域名；URL=IP→证书主机名校验失败）都走不通，
// 只能用本文件：IP 直连 + skipRemoteValidation + 手写 HTTP GET。
// 安全权衡：skipRemoteValidation 意味着不校验证书链与主机名，中间人可替换图片内容；
// 仅用于图片展示兜底（不承载任何账号数据），且只在常规路径全部失败后调用，风险可接受。
// API 约束：constructTLSSocketInstance(tcp) 要求 tcp 已建立连接（否则 2303602），
// 所以必须先 tcp.connect 建链，再构造 TLSSocket 升级。
const DEFAULT_CONNECT_TIMEOUT_MS: number = 8000;
const DEFAULT_TOTAL_TIMEOUT_MS: number = 25000;

interface DirectTlsFetchOptions {
  ip: string;
  host: string;
  path: string;
  referer: string;
  userAgent: string;
  connectTimeoutMs?: number;
  totalTimeoutMs?: number;
}

function appendChunk(chunks: Uint8Array[], data: ArrayBuffer): void {
  chunks.push(new Uint8Array(data.slice(0)));
}

function concatChunks(chunks: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let i = 0; i < chunks.length; i++) {
    total += chunks[i].length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (let i = 0; i < chunks.length; i++) {
    out.set(chunks[i], offset);
    offset += chunks[i].length;
  }
  return out;
}

function decodeAscii(bytes: Uint8Array, end: number): string {
  let text = '';
  for (let i = 0; i < end; i++) {
    text += String.fromCharCode(bytes[i]);
  }
  return text;
}

// 从原始 HTTP 响应里剥出 body：处理 Content-Length 与 chunked 两种形态。
// 返回 null 表示头不完整或状态码非 200。
export function extractHttpBody(raw: Uint8Array): Uint8Array | null {
  let headerEnd = -1;
  for (let i = 0; i + 3 < raw.length; i++) {
    if (raw[i] === 13 && raw[i + 1] === 10 && raw[i + 2] === 13 && raw[i + 3] === 10) {
      headerEnd = i;
      break;
    }
  }
  if (headerEnd < 0) {
    return null;
  }
  const headerText = decodeAscii(raw, headerEnd);
  const statusLine = headerText.split('\r\n')[0];
  if (statusLine.indexOf(' 200 ') < 0) {
    return null;
  }
  const lower = headerText.toLowerCase();
  const bodyStart = headerEnd + 4;
  if (lower.indexOf('transfer-encoding: chunked') >= 0) {
    // chunked：逐块解析（长度行 CRLF + 数据 CRLF），0 块结束
    const body: Uint8Array[] = [];
    let cursor = bodyStart;
    while (cursor < raw.length) {
      let lineEnd = -1;
      for (let i = cursor; i + 1 < raw.length; i++) {
        if (raw[i] === 13 && raw[i + 1] === 10) {
          lineEnd = i;
          break;
        }
      }
      if (lineEnd < 0) {
        return null;
      }
      const sizeText = decodeAscii(raw, lineEnd).split(';')[0].trim();
      const size = parseInt(sizeText, 16);
      if (Number.isNaN(size)) {
        return null;
      }
      if (size === 0) {
        let merged = 0;
        for (let i = 0; i < body.length; i++) {
          merged += body[i].length;
        }
        const out = new Uint8Array(merged);
        let offset = 0;
        for (let i = 0; i < body.length; i++) {
          out.set(body[i], offset);
          offset += body[i].length;
        }
        return out;
      }
      const dataStart = lineEnd + 2;
      if (dataStart + size > raw.length) {
        return null;
      }
      body.push(raw.slice(dataStart, dataStart + size));
      cursor = dataStart + size + 2;
    }
    return null;
  }
  const clKey = 'content-length:';
  const clIndex = lower.indexOf(clKey);
  if (clIndex >= 0) {
    let lineEnd = lower.indexOf('\r\n', clIndex);
    if (lineEnd < 0) {
      lineEnd = lower.length;
    }
    const valueText = lower.substring(clIndex + clKey.length, lineEnd).trim();
    const length = parseInt(valueText, 10);
    if (!Number.isNaN(length) && raw.length - bodyStart < length) {
      return null;
    }
    return raw.slice(bodyStart);
  }
  // 无 Content-Length 也无 chunked（Connection: close 语义）：剩余字节全算 body
  return raw.slice(bodyStart);
}

// 用 TLSSocket（IP 直连 + 跳过校验）拉取一张图片，返回字节。
export function fetchImageOverDirectTls(options: DirectTlsFetchOptions): Promise<Uint8Array> {
  return new Promise<Uint8Array>((resolve, reject) => {
    const tcp = socket.constructTCPSocketInstance();
    const chunks: Uint8Array[] = [];
    let tls: socket.TLSSocket | null = null;
    let settled = false;
    let connected = false;
    const totalTimeout = options.totalTimeoutMs !== undefined ? options.totalTimeoutMs : DEFAULT_TOTAL_TIMEOUT_MS;
    const connectTimeout = options.connectTimeoutMs !== undefined ?
      options.connectTimeoutMs : DEFAULT_CONNECT_TIMEOUT_MS;
    const finish = (error: Error | null, data?: Uint8Array): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(totalTimer);
      clearTimeout(connectTimer);
      if (tls !== null) {
        try {
          tls.off('message');
          tls.off('close');
          tls.off('error');
        } catch (ignore) {
        }
        try {
          tls.close();
        } catch (ignore) {
        }
      }
      try {
        tcp.close();
      } catch (ignore) {
      }
      if (error !== null) {
        reject(error);
      } else {
        resolve(data as Uint8Array);
      }
    };
    const totalTimer = setTimeout(() => {
      finish(new Error('DirectTls total timeout'));
    }, totalTimeout);
    const connectTimer = setTimeout(() => {
      if (!connected) {
        finish(new Error('DirectTls connect timeout'));
      }
    }, connectTimeout);
    const run = async (): Promise<void> => {
      await tcp.connect({
        address: { address: options.ip, port: 443, family: 1 },
        timeout: connectTimeout
      });
      const tlsInstance = socket.constructTLSSocketInstance(tcp);
      tls = tlsInstance;
      tlsInstance.on('message', (value: socket.SocketMessageInfo) => {
        appendChunk(chunks, value.message);
        // 头部已到且 Content-Length 满足时可提前结束，省等待
        if (chunks.length > 0) {
          const raw = concatChunks(chunks);
          const body = extractHttpBody(raw);
          if (body !== null) {
            finish(null, body);
          }
        }
      });
      tlsInstance.on('error', (error: Error) => {
        finish(new Error('DirectTls error: ' + error.message));
      });
      tlsInstance.on('close', () => {
        // 服务端按 Connection: close 收尾：用已收到的全部字节做最终提取
        if (chunks.length > 0) {
          const raw = concatChunks(chunks);
          const body = extractHttpBody(raw);
          if (body !== null) {
            finish(null, body);
            return;
          }
        }
        finish(new Error('DirectTls closed before body complete'));
      });
      await tlsInstance.connect({
        address: { address: options.ip, port: 443, family: 1 },
        secureOptions: { protocols: [socket.Protocol.TLSv12] },
        skipRemoteValidation: true
      });
      connected = true;
      clearTimeout(connectTimer);
      const request = 'GET ' + options.path + ' HTTP/1.1\r\n' +
        'Host: ' + options.host + '\r\n' +
        'User-Agent: ' + options.userAgent + '\r\n' +
        (options.referer.length > 0 ? 'Referer: ' + options.referer + '\r\n' : '') +
        'Accept: image/*,*/*;q=0.8\r\n' +
        'Connection: close\r\n\r\n';
      await tlsInstance.send(request);
    };
    run().catch((error: Error) => {
      finish(new Error('DirectTls connect failed: ' + error.message));
    });
  });
}

// 兜底入口：把 URL 拆解为 IP 直连请求，结果写入 destPath。
// 返回 destPath（成功）或 ''（失败，调用方继续原有失败流程）。
const DIRECT_TLS_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36 EhViewerHarmony/0.1';

export function fetchImageFileOverDirectTls(imageUrl: string, destPath: string,
  referer: string): Promise<string> {
  const schemeEnd = imageUrl.indexOf('://');
  if (schemeEnd < 0) {
    return Promise.resolve('');
  }
  const rest = imageUrl.substring(schemeEnd + 3);
  const slash = rest.indexOf('/');
  if (slash < 0) {
    return Promise.resolve('');
  }
  const host = rest.substring(0, slash);
  let path = rest.substring(slash);
  const hash = path.indexOf('#');
  if (hash >= 0) {
    path = path.substring(0, hash);
  }
  const ipCandidates: string[] = ['185.132.132.76'];
  if (host === 'upld.e-hentai.org') {
    ipCandidates.unshift('89.149.221.236');
  }
  const attemptWith = async (index: number): Promise<string> => {
    if (index >= ipCandidates.length) {
      return '';
    }
    let bytes: Uint8Array;
    try {
      bytes = await fetchImageOverDirectTls({
        ip: ipCandidates[index],
        host: host,
        path: path,
        referer: referer,
        userAgent: DIRECT_TLS_USER_AGENT
      });
    } catch (error) {
      console.info('[DirectTls] attempt ' + ipCandidates[index] + ' error: ' +
        (error instanceof Error ? error.message : String(error)));
      return attemptWith(index + 1);
    }
    if (bytes.length < 256) {
      console.info('[DirectTls] attempt ' + ipCandidates[index] + ' body too small: ' +
        bytes.length.toString() + ' bytes');
      return attemptWith(index + 1);
    }
    try {
      const file = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes.buffer);
      fs.closeSync(file.fd);
      return destPath;
    } catch (error) {
      console.info('[DirectTls] write file failed: ' +
        (error instanceof Error ? error.message : String(error)));
      return '';
    }
  };
  return attemptWith(0);
}
