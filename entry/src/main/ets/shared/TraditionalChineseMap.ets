import { i18n } from '@kit.LocalizationKit';

interface TraditionalTerminology {
  source: string;
  target: string;
}

// ICU performs the character conversion. These replacements keep common UI terms
// consistent with Traditional Chinese software terminology afterwards.
const TRADITIONAL_TERMINOLOGY: TraditionalTerminology[] = [
  { source: '文件夾', target: '資料夾' },
  { source: '使用者名', target: '使用者名稱' },
  { source: '用戶名', target: '使用者名稱' },
  { source: '設置', target: '設定' },
  { source: '默認', target: '預設' },
  { source: '軟件', target: '軟體' },
  { source: '視頻', target: '影片' },
  { source: '網絡', target: '網路' },
  { source: '登錄', target: '登入' },
  { source: '退出登入', target: '登出' },
  { source: '信息', target: '資訊' },
  { source: '數據', target: '資料' },
  { source: '緩存', target: '快取' },
  { source: '添加', target: '新增' },
  { source: '搜索', target: '搜尋' },
  { source: '導入', target: '匯入' },
  { source: '導出', target: '匯出' },
  { source: '服務器', target: '伺服器' },
  { source: '鏈接', target: '連結' },
  { source: '線程', target: '執行緒' },
  { source: '程序', target: '程式' },
  { source: '屏幕', target: '螢幕' },
  { source: '窗口', target: '視窗' },
  { source: '文本', target: '文字' },
  { source: '文件', target: '檔案' },
  { source: '質量', target: '品質' },
  { source: '刷新', target: '重新整理' }
];

let traditionalTransliterator: i18n.Transliterator | null = null;
let transliteratorInitialized: boolean = false;
const TRADITIONAL_TEXT_CACHE_LIMIT: number = 1024;
const traditionalTextCache: Map<string, string> = new Map<string, string>();

function applyTraditionalTerminology(text: string): string {
  let result = text;
  for (let i = 0; i < TRADITIONAL_TERMINOLOGY.length; i++) {
    const terminology = TRADITIONAL_TERMINOLOGY[i];
    result = result.split(terminology.source).join(terminology.target);
  }
  return result;
}

function fallbackTraditionalCharacters(text: string): string {
  const simplified = '后台与个为书云仅从众优会传体余侧价份伪储儿关兴养内写击删别务动区历压发变号后启听员图圆场处复头奖妇学实导层属并开异归当录径忆态总户执扩扫换据数断无时显条标样档桥检权来极构枪柜栏树样检楼欢步毁毕气汉浏测济浏点热爱状现画盘码确离种称移稳签简类级终组经统维网置联获览觉触订认议记设译试话该详语误说请账质输过进连选释里鉴长门间阅队际页顾预领题验高麦黄齐龙';
  const traditional = '後臺與個為書雲僅從眾優會傳體餘側價份偽儲兒關興養內寫擊刪別務動區歷壓發變號後啟聽員圖圓場處復頭獎婦學實導層屬並開異歸當錄徑憶態總戶執擴掃換據數斷無時顯條標樣檔橋檢權來極構槍櫃欄樹樣檢樓歡步毀畢氣漢瀏測濟瀏點熱愛狀現畫盤碼確離種稱移穩簽簡類級終組經統維網置聯獲覽覺觸訂認議記設譯試話該詳語誤說請賬質輸過進連選釋裡鑑長門間閱隊際頁顧預領題驗高麥黃齊龍';
  let result = '';
  for (let i = 0; i < text.length; i++) {
    const character = text.charAt(i);
    const index = simplified.indexOf(character);
    result += index >= 0 ? traditional.charAt(index) : character;
  }
  return result;
}

export function traditionalChineseText(text: string): string {
  if (text.length === 0) {
    return text;
  }
  const cached = traditionalTextCache.get(text);
  if (cached !== undefined) {
    return cached;
  }
  let result: string;
  if (!transliteratorInitialized) {
    transliteratorInitialized = true;
    try {
      traditionalTransliterator = i18n.Transliterator.getInstance('Simplified-Traditional');
    } catch (error) {
      traditionalTransliterator = null;
    }
  }
  if (traditionalTransliterator !== null) {
    try {
      result = applyTraditionalTerminology(traditionalTransliterator.transform(text));
      if (traditionalTextCache.size >= TRADITIONAL_TEXT_CACHE_LIMIT) {
        traditionalTextCache.clear();
      }
      traditionalTextCache.set(text, result);
      return result;
    } catch (error) {
      traditionalTransliterator = null;
    }
  }
  result = applyTraditionalTerminology(fallbackTraditionalCharacters(text));
  if (traditionalTextCache.size >= TRADITIONAL_TEXT_CACHE_LIMIT) {
    traditionalTextCache.clear();
  }
  traditionalTextCache.set(text, result);
  return result;
}
