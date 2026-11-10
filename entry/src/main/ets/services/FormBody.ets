// 表单编码。EhHttpClient 与 EhMyTagsService 各有一份完全相同的实现。

export interface FormField {
  key: string;
  value: string;
}

export function buildFormBody(fields: FormField[]): string {
  const parts: string[] = [];
  for (let i = 0; i < fields.length; i++) {
    parts.push(encodeURIComponent(fields[i].key) + '=' + encodeURIComponent(fields[i].value));
  }
  return parts.join('&');
}
