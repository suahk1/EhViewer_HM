import { GalleryPage } from '../model/GalleryModels';
import { parseFirst, normalizeImageUrl, isImageUrlCandidate } from './GalleryPageImages';

const API_IMAGE_URL_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*style/i;
const API_IMAGE_CONTAINER_SRC_PATTERN: RegExp =
  /<div[^>]*id=["']i3["'][^>]*>[\s\S]*?<img[^>]*src=["']([^"']+)["'][^>]*>/i;
const API_IMAGE_ID_SRC_PATTERN: RegExp = /<img[^>]*id=["']img["'][^>]*src=["']([^"']+)["'][^>]*>/i;
const API_IMAGE_SRC_ID_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*id=["']img["'][^>]*>/i;
const API_IMAGE_SRC_ACTION_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*(onclick|onerror|alt|title)=/i;
const API_IMAGE_LINK_PATTERN: RegExp = /<a[^>]+href=["']([^"']+)["'][^>]*>\s*<img/i;
const API_SKIP_HATH_KEY_PATTERN: RegExp = /onclick=["']return nl\(['"]([^'")]+)['"]\)/i;
const API_ORIGIN_IMAGE_URL_PATTERN: RegExp = /<a[^>]+href=["']([^"']*fullimg[^"']*)["'][^>]*>/i;
const API_ORIGIN_IMAGE_PROMPT_PATTERN: RegExp = /prompt\(['"]Copy the URL below\.['"],\s*['"]([^'"]+)['"]\)/i;

export interface GalleryPageApiParseResult {
  page: GalleryPage | null;
  warning: string;
}

interface GalleryPageApiBody {
  error?: string;
  i3?: string;
  i6?: string;
  i7?: string | null;
}

export function parseGalleryPageApi(body: string, pageUrl: string, showKey: string): GalleryPageApiParseResult {
  let parsed: GalleryPageApiBody;
  try {
    parsed = JSON.parse(body) as GalleryPageApiBody;
  } catch (error) {
    return { page: null, warning: 'Cannot parse showpage JSON' };
  }

  if (typeof parsed.error === 'string' && parsed.error.length > 0) {
    return { page: null, warning: parsed.error };
  }

  const imageHtml = typeof parsed.i3 === 'string' ? parsed.i3 : '';
  const actionHtml = typeof parsed.i6 === 'string' ? parsed.i6 : '';
  const originHtml = typeof parsed.i7 === 'string' ? parsed.i7 : actionHtml;
  const imageUrl = parseImageUrl(imageHtml);
  const fallbackUrl = parseFirst(actionHtml, API_ORIGIN_IMAGE_PROMPT_PATTERN);
  const displayUrl = imageUrl.length > 0 ? imageUrl : fallbackUrl;
  if (displayUrl.length === 0) {
    return { page: null, warning: 'No image URL parsed from showpage API' };
  }

  return {
    page: {
      pageUrl: pageUrl,
      imageUrl: displayUrl,
      skipHathKey: parseFirst(actionHtml, API_SKIP_HATH_KEY_PATTERN),
      originImageUrl: parseOriginUrl(originHtml, actionHtml),
      showKey: showKey
    },
    warning: ''
  };
}

function parseOriginUrl(primaryHtml: string, fallbackHtml: string): string {
  const primary = parseFirst(primaryHtml, API_ORIGIN_IMAGE_URL_PATTERN);
  if (primary.length > 0) {
    return primary;
  }
  return parseFirst(fallbackHtml, API_ORIGIN_IMAGE_URL_PATTERN);
}

function parseImageUrl(body: string): string {
  const container = API_IMAGE_CONTAINER_SRC_PATTERN.exec(body);
  if (container !== null && isImageUrlCandidate(normalizeImageUrl(container[1]))) {
    return normalizeImageUrl(container[1]);
  }

  const idBeforeSrc = API_IMAGE_ID_SRC_PATTERN.exec(body);
  if (idBeforeSrc !== null && isImageUrlCandidate(normalizeImageUrl(idBeforeSrc[1]))) {
    return normalizeImageUrl(idBeforeSrc[1]);
  }

  const srcBeforeId = API_IMAGE_SRC_ID_PATTERN.exec(body);
  if (srcBeforeId !== null && isImageUrlCandidate(normalizeImageUrl(srcBeforeId[1]))) {
    return normalizeImageUrl(srcBeforeId[1]);
  }

  const primary = API_IMAGE_URL_PATTERN.exec(body);
  if (primary !== null && isImageUrlCandidate(normalizeImageUrl(primary[1]))) {
    return normalizeImageUrl(primary[1]);
  }

  const actionImage = API_IMAGE_SRC_ACTION_PATTERN.exec(body);
  if (actionImage !== null && isImageUrlCandidate(normalizeImageUrl(actionImage[1]))) {
    return normalizeImageUrl(actionImage[1]);
  }

  const imageLink = API_IMAGE_LINK_PATTERN.exec(body);
  if (imageLink !== null && isImageUrlCandidate(normalizeImageUrl(imageLink[1]))) {
    return normalizeImageUrl(imageLink[1]);
  }

  return '';
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

