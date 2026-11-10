import { GalleryDetail, GalleryInfo, GalleryTagGroup } from '../model/GalleryModels';

// 图册标签的拷贝与读取。
// 这几个函数在 EhDownloadFileStore / EhDownloadStore / EhHistoryStore / EhLocalFavoritesStore
// 里各写一份，签名略有出入但逻辑一致。抄多份的代价是：修 undefined 处理时要改四处。

export function cloneStringArray(values: string[] | undefined): string[] | undefined {
  if (values === undefined) {
    return undefined;
  }
  const next: string[] = [];
  for (let i = 0; i < values.length; i++) {
    next.push(values[i]);
  }
  return next;
}

export function cloneStringArrayRequired(values: string[] | undefined): string[] {
  const next: string[] = [];
  if (values === undefined) {
    return next;
  }
  for (let i = 0; i < values.length; i++) {
    next.push(values[i]);
  }
  return next;
}

export function cloneGalleryTagGroups(groups: GalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined) {
    return undefined;
  }
  const next: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    next.push({
      namespace: groups[i].namespace,
      tags: cloneStringArrayRequired(groups[i].tags)
    });
  }
  return next;
}

export function galleryDetailTags(item: GalleryInfo): GalleryTagGroup[] | undefined {
  const detail = item as GalleryDetail;
  if (detail.tags !== undefined && Array.isArray(detail.tags) && detail.tags.length > 0) {
    return detail.tags;
  }
  return item.detailTags;
}

export function galleryDetailLanguage(item: GalleryInfo): string | undefined {
  const detail = item as GalleryDetail;
  if (detail.language !== undefined && detail.language.length > 0) {
    return detail.language;
  }
  return item.detailLanguage;
}

// 本地持久化的标签分组转运行时结构。下载库与历史库各有一份相同实现；
// 三处 StoredGalleryTagGroup 接口定义也完全一样，这里收敛为同一份。
export interface StoredGalleryTagGroup {
  namespace?: string;
  tags?: string[];
}

export function storedToGalleryTagGroups(groups: StoredGalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined || !Array.isArray(groups)) {
    return undefined;
  }
  const next: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    const namespace: string = typeof group.namespace === 'string' ? group.namespace : '';
    const tags: string[] = Array.isArray(group.tags) ? group.tags as string[] : [];
    if (namespace.length > 0 && tags.length > 0) {
      next.push({ namespace: namespace, tags: cloneStringArrayRequired(tags) });
    }
  }
  return next;
}
