import { GalleryTagInfo } from '../model/GalleryModels';
import { SearchSuggestionItem } from '../components/GallerySearchScenes';

// 标签信息深拷贝。详情页与标签页各有一份完全相同的实现。
export function cloneTagInfo(info: GalleryTagInfo): GalleryTagInfo {
  return {
    id: info.id,
    namespace: info.namespace,
    tag: info.tag,
    fullTag: info.fullTag,
    voteUpEd: info.voteUpEd,
    voteDownEd: info.voteDownEd
  };
}

// 搜索建议深拷贝。筛选面板、我的标签、详情标签各有一份完全相同的实现。
export function cloneSearchSuggestions(suggestions: SearchSuggestionItem[]): SearchSuggestionItem[] {
  const result: SearchSuggestionItem[] = [];
  for (let i = 0; i < suggestions.length; i++) {
    result.push({
      kind: suggestions[i].kind,
      title: suggestions[i].title,
      subtitle: suggestions[i].subtitle,
      query: suggestions[i].query,
      translated: suggestions[i].translated,
      namespace: suggestions[i].namespace
    });
  }
  return result;
}
