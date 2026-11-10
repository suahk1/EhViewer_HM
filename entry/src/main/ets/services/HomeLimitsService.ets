import { GallerySite } from '../model/GalleryModels';
import { escapeRegExp } from './TextMatch';
import { EhHttpClient } from './EhHttpClient';
import { EhUrl } from './EhUrl';

export interface HomeLimits {
  used: number;
  total: number;
  resetCost: number;
  fromGalleryVisits: number;
  fromTorrentCompletions: number;
  fromArchiveDownloads: number;
  fromHentaiAtHome: number;
}

export interface HomeLimitsResult {
  ok: boolean;
  statusCode: number;
  message: string;
  limits: HomeLimits | null;
}

const EMPTY_LIMITS: HomeLimits = {
  used: 0,
  total: 0,
  resetCost: 0,
  fromGalleryVisits: 0,
  fromTorrentCompletions: 0,
  fromArchiveDownloads: 0,
  fromHentaiAtHome: 0
};

class HomeLimitsService {
  private client: EhHttpClient = new EhHttpClient();
  private cachedLimits: HomeLimits | null = null;
  private pendingLoad: Promise<HomeLimitsResult> | null = null;
  private pendingReset: Promise<HomeLimitsResult> | null = null;

  getCached(): HomeLimits | null {
    if (this.cachedLimits === null) {
      return null;
    }
    return cloneLimits(this.cachedLimits);
  }

  async load(force: boolean = false): Promise<HomeLimitsResult> {
    // A forced refresh must replace the cached value, but it must not create another native HTTP task while the
    // previous refresh is still running. The panel can be rebuilt while a request is in flight on large screens.
    if (this.pendingLoad !== null) {
      return this.pendingLoad;
    }
    if (this.pendingReset !== null) {
      return this.pendingReset;
    }
    if (!force && this.cachedLimits !== null) {
      return successResult(this.cachedLimits);
    }

    const pending = this.requestLimits(false);
    this.pendingLoad = pending;
    try {
      return await pending;
    } finally {
      if (this.pendingLoad === pending) {
        this.pendingLoad = null;
      }
    }
  }

  async reset(): Promise<HomeLimitsResult> {
    if (this.pendingReset !== null) {
      return this.pendingReset;
    }
    const pending = this.resetAfterPendingLoad();
    this.pendingReset = pending;
    try {
      return await pending;
    } finally {
      if (this.pendingReset === pending) {
        this.pendingReset = null;
      }
    }
  }

  private async resetAfterPendingLoad(): Promise<HomeLimitsResult> {
    const inFlight = this.pendingLoad;
    if (inFlight !== null) {
      return inFlight.then(() => this.requestLimits(true));
    }
    return this.requestLimits(true);
  }

  private async requestLimits(reset: boolean): Promise<HomeLimitsResult> {
    const url = EhUrl.getHomeUrl(GallerySite.E);
    const referer = EhUrl.getReferer(GallerySite.E);
    try {
      const response = reset ?
        await this.client.postForm(url, 'reset_imagelimit=Reset+Limit', referer, referer) :
        await this.client.getText(url, referer, 0);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return failureResult(response.statusCode, 'HTTP ' + response.statusCode.toString());
      }
      const limits = parseEhHomeLimits(response.body);
      if (limits === null) {
        return failureResult(response.statusCode, 'EH limits were not found in the account page');
      }
      this.cachedLimits = cloneLimits(limits);
      return successResult(limits, response.statusCode);
    } catch (error) {
      return failureResult(0, String(error));
    }
  }

}

export function parseEhHomeLimits(body: string): HomeLimits | null {
  if (!/<h2[^>]*>\s*Image Limits\s*<\/h2>/i.test(body)) {
    return null;
  }

  const limits = cloneLimits(EMPTY_LIMITS);
  const imagePattern = /You are currently at\s*<strong>([\d,]+)<\/strong>[\s\S]*?limit of\s*<strong>([\d,]+)<\/strong>[\s\S]*?(?:Reset Cost:|spending)\s*<strong>([\d,]+)<\/strong>/i;
  const imageMatch = imagePattern.exec(body);
  if (imageMatch !== null) {
    limits.used = parseNumber(imageMatch[1]);
    limits.total = parseNumber(imageMatch[2]);
    limits.resetCost = parseNumber(imageMatch[3]);
  }

  limits.fromGalleryVisits = parseGpRow(body, 'gallery visits');
  limits.fromTorrentCompletions = parseGpRow(body, 'torrent completions');
  limits.fromArchiveDownloads = parseGpRow(body, 'archive downloads');
  limits.fromHentaiAtHome = parseGpRow(body, 'Hentai@Home');
  return limits;
}

function parseGpRow(body: string, label: string): number {
  const pattern = new RegExp('<td[^>]*>\\s*([\\d,]+)\\s*<\\/td>\\s*<td[^>]*>\\s*GP from ' +
    escapeRegExp(label) + '\\s*<\\/td>', 'i');
  const match = pattern.exec(body);
  return match === null ? 0 : parseNumber(match[1]);
}

function parseNumber(value: string): number {
  const parsed = Number.parseInt(value.replace(/,/g, ''));
  return Number.isFinite(parsed) ? parsed : 0;
}

function successResult(limits: HomeLimits, statusCode: number = 200): HomeLimitsResult {
  return { ok: true, statusCode: statusCode, message: '', limits: cloneLimits(limits) };
}

function failureResult(statusCode: number, message: string): HomeLimitsResult {
  return { ok: false, statusCode: statusCode, message: message, limits: null };
}

function cloneLimits(limits: HomeLimits): HomeLimits {
  return {
    used: limits.used,
    total: limits.total,
    resetCost: limits.resetCost,
    fromGalleryVisits: limits.fromGalleryVisits,
    fromTorrentCompletions: limits.fromTorrentCompletions,
    fromArchiveDownloads: limits.fromArchiveDownloads,
    fromHentaiAtHome: limits.fromHentaiAtHome
  };
}

export const homeLimitsService = new HomeLimitsService();
