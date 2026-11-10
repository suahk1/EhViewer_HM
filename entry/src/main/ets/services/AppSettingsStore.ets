import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  SavedTranslationApi,
  parseSavedTranslationApis,
  serializeSavedTranslationApis,
  uniqueTranslationApiName
} from './TranslationSupport';

const PREFERENCES_NAME: string = 'ehviewer_settings';
const VALUES_KEY: string = 'values';
export const HISTORY_INFO_SIZE_KEY: string = 'history_info_size';
export const DEFAULT_HISTORY_INFO_SIZE: string = '100';
export const TRANSLATION_BUTTONS_VISIBLE_KEY: string = 'ehviewer_translation_buttons_visible';
export const READER_TRANSLATION_BUTTON_VISIBLE_KEY: string = 'ehviewer_reader_translation_button_visible';
export const DEFAULT_FAVORITE_SLOT_SETTING_KEY: string = 'default_fav_slot';
export const DEFAULT_FAVORITE_SLOT_ASK: string = 'Ask';
export const DEFAULT_DOWNLOAD_LABEL_SETTING_KEY: string = 'default_download_label';
export const DEFAULT_DOWNLOAD_LABEL_ASK: string = '__ask__';
export const FLOATING_ACTION_SIDE_SETTING_KEY: string = 'floating_action_side';
export const FLOATING_ACTION_SIDE_REVISION_KEY: string = 'floatingActionSideRevision';
export const FLOATING_ACTION_HOLDING_HAND_SETTING_KEY: string = 'floating_action_holding_hand';
// 一次性迁移标记：早期版本默认开启智感握持，需要强制关掉一次。
const HOLDING_HAND_MIGRATION_KEY: string = 'floating_action_holding_hand_migrated_off';
export const FLOATING_ACTION_HOLDING_HAND_REVISION_KEY: string = 'floatingActionHoldingHandRevision';
export const MULTI_DEVICE_CONTINUATION_SETTING_KEY: string = 'multi_device_continuation';
export const REMOTE_SYNC_WIFI_ONLY_KEY: string = 'remote_sync_wifi_only';
const HISTORY_INFO_SIZE_OPTIONS: string[] = ['100', '500', '1000', '5000', '10000', '20000'];
const DEVICE_LOCAL_SETTING_KEYS: string[] = ['download_location', 'download_public_root_path'];

export interface SettingEntry {
  key: string;
  value: string;
}

export interface SettingImportResult {
  imported: number;
  languageChanged: boolean;
  themeChanged: boolean;
  titleChanged: boolean;
}

interface StoredSettingEntry {
  key?: string;
  value?: string;
}

export function defaultSettingEntries(): SettingEntry[] {
  return [
    { key: 'gallery_site', value: 'E-Hentai' },
    { key: 'use_account_default_filter', value: 'On' },
    // 默认跟随系统：冷启动的启动页只能按系统深浅出图，应用主题若与系统相反，
    // 会先闪一下深/浅色再切成应用主题。默认跟随后，绝大多数用户不会遇到这次错配。
    { key: 'display_mode', value: 'Follow' },
    { key: 'theme_color', value: 'Adaptive' },
    { key: 'ui_style', value: 'Harmony' },
    { key: 'ui_style_default_harmony_20260826', value: 'Applied' },
    { key: 'launch_page', value: 'Homepage' },
    { key: 'list_mode', value: 'Detail' },
    { key: 'detail_size', value: 'Medium' },
    { key: 'thumb_size', value: 'Medium' },
    { key: HISTORY_INFO_SIZE_KEY, value: DEFAULT_HISTORY_INFO_SIZE },
    { key: 'show_jpn_title', value: 'Off' },
    { key: DEFAULT_FAVORITE_SLOT_SETTING_KEY, value: DEFAULT_FAVORITE_SLOT_ASK },
    { key: DEFAULT_DOWNLOAD_LABEL_SETTING_KEY, value: DEFAULT_DOWNLOAD_LABEL_ASK },
    { key: 'show_gallery_pages', value: 'On' },
    { key: 'show_gallery_rating', value: 'On' },
    { key: 'show_gallery_language', value: 'On' },
    { key: 'show_tag_translations', value: 'On' },
    { key: 'split_screen_mode', value: 'Off' },
    { key: 'split_screen_ratio', value: '0.42' },
    { key: 'show_eh_events', value: 'On' },
    { key: 'show_eh_limits', value: 'On' },
    { key: 'translation_buttons_enabled', value: 'On' },
    { key: FLOATING_ACTION_SIDE_SETTING_KEY, value: 'Right' },
    { key: FLOATING_ACTION_HOLDING_HAND_SETTING_KEY, value: 'Off' },
    { key: 'reader_translation_enabled', value: 'Off' },
    { key: 'reader_ocr_debug_log', value: 'Off' },
    { key: 'reader_translation_button_side', value: 'Right' },
    { key: 'reader_translation_button_y_ratio', value: '0.35' },
    { key: 'translation_provider', value: 'Google Web' },
    { key: 'translation_machine_provider', value: 'Google Web' },
    { key: 'translation_batch_enabled', value: 'On' },
    { key: 'translation_ai_enabled', value: 'Off' },
    { key: 'translation_ai_provider', value: 'DeepSeek' },
    { key: 'translation_ai_thinking_enabled', value: 'Off' },
    { key: 'translation_ai_conversation_log', value: 'Off' },
    { key: 'translation_target_language', value: 'Simplified Chinese' },
    { key: 'translation_timeout', value: '15s' },
    { key: 'translation_deepseek_api_key', value: '' },
    { key: 'translation_deepseek_model', value: 'deepseek-v4-flash' },
    { key: 'translation_openai_api_key', value: '' },
    { key: 'translation_openai_base_url', value: 'https://api.openai.com/v1' },
    { key: 'translation_openai_model', value: 'gpt-4o-mini' },
    { key: 'translation_official_openai_api_key', value: '' },
    { key: 'translation_official_openai_model', value: 'gpt-4.1-mini' },
    { key: 'translation_gemini_api_key', value: '' },
    { key: 'translation_gemini_model', value: 'gemini-3.5-flash' },
    { key: 'translation_custom_apis', value: '[]' },
    { key: 'translation_custom_api_selected', value: '' },
    { key: 'translation_prompt_selected', value: 'preset_faithful' },
    { key: 'translation_prompt_custom_profiles', value: '[]' },
    { key: 'translation_provider_split_20260714', value: 'Applied' },
    // 用移动数据做大量网络操作前先提示，避免误耗流量
    { key: 'cellular_network_warning', value: 'On' },
    { key: 'screen_rotation', value: 'Default' },
    { key: 'reading_direction', value: 'Right to left' },
    { key: 'page_scaling', value: 'Fit screen' },
    { key: 'adaptive_dual_page', value: 'Off' },
    { key: 'reader_crop_white_borders', value: 'Off' },
    { key: 'reader_image_super_resolution', value: 'Off' },
    { key: 'reader_super_resolution_engine', value: 'Detail enhancer' },
    { key: 'reader_sdr_to_hdr', value: 'Off' },
    { key: 'reader_image_adjustment', value: 'Off' },
    { key: 'reader_image_contrast', value: '0' },
    { key: 'reader_image_clarity', value: '0' },
    { key: 'reader_image_sharpening', value: '0' },
    { key: 'reader_image_exposure', value: '0' },
    { key: 'reader_image_brightness', value: '0' },
    { key: 'reader_image_highlights', value: '0' },
    { key: 'reader_image_shadows', value: '0' },
    { key: 'reader_image_hue', value: '0' },
    { key: 'reader_image_saturation', value: '0' },
    { key: 'reader_image_vibrance', value: '0' },
    { key: 'reader_image_temperature', value: '0' },
    { key: 'reader_image_grayscale', value: '0' },
    { key: 'reader_settings_tab', value: '0' },
    { key: 'reader_custom_presets', value: '[]' },
    { key: 'start_position', value: 'Center' },
    { key: 'start_transfer_time', value: '5s' },
    { key: 'reader_standalone', value: 'Off' },
    { key: MULTI_DEVICE_CONTINUATION_SETTING_KEY, value: 'Off' },
    { key: REMOTE_SYNC_WIFI_ONLY_KEY, value: 'Off' },
    { key: 'keep_screen_on', value: 'On' },
    { key: 'gallery_show_clock', value: 'On' },
    { key: 'gallery_show_progress', value: 'On' },
    { key: 'gallery_show_battery', value: 'On' },
    { key: 'volume_page', value: 'Off' },
    { key: 'reverse_volume_page', value: 'Off' },
    { key: 'reading_fullscreen', value: 'On' },
    { key: 'reader_background', value: 'Deep gray' },
    { key: 'screen_lightness', value: '50%' },
    { key: 'custom_screen_lightness', value: 'Off' },
    { key: 'ultra_dark_mode', value: 'Off' },
    { key: 'ultra_dark_lightness', value: '50%' },
    { key: 'download_location', value: 'App files' },
    { key: 'download_public_root_path', value: '' },
    { key: 'download_thread', value: '5' },
    { key: 'download_sort_mode', value: 'Default' },
    // H@H 单节点实测 12s 超时，预载 5 张会抢占带宽拖慢当前页
    { key: 'preload_image', value: '3' },
    // 实测 5 线程 14.6 页/分钟 vs 3 线程 0.6-1.2 页/分钟（184 页大本子），
    // 瓶颈是线程数不足导致的节点利用率低；上面 download_thread 已改为 5
    { key: 'image_size', value: 'Auto' },
    { key: 'download_origin_image', value: 'Off' },
    { key: 'download_timeout', value: '30s' },
    { key: 'download_order_asc', value: 'On' },
    { key: 'pattern_protection', value: 'Off' },
    { key: 'enable_secure', value: 'Off' },
    { key: 'save_parse_error_body', value: 'Off' },
    { key: 'save_crash_log', value: 'Off' },
    { key: 'read_cache_size', value: '160 MB' },
    { key: 'app_language', value: 'System' },
    // 默认直连（Off）：「跟随系统」会把请求送进系统代理，而系统代理可能指向
    // 已失效的隧道（接口在但无流量），表现为标签库更新超时、评论发不出。
    // 直连模式下走内置 hosts + 独立 IP，主页/详情/标签库都能跑通。
    { key: 'proxy', value: 'Off' },
    { key: 'proxy_host', value: '' },
    { key: 'proxy_port', value: '' },
    { key: 'proxy_username', value: '' },
    { key: 'proxy_password', value: '' },
    { key: 'proxy_exclusion_list', value: '' },
    { key: 'proxy_socks_dns', value: 'Proxy' },
    // 首次安装的联网默认值：直连被污染/阻断时这套组合可用（实测）。
    // e-hentai 解析到污染 IP → 内置 hosts 强制解析；ehgt 图床走前置；
    // DoH 只对 EH 域名生效（外部域名交回系统 DNS，避免 GitHub 解析失败）。
    // 用户自行改过之后以用户设置为准，这里只管新装。
    { key: 'built_in_hosts', value: 'On' },
    { key: 'built_ex_hosts', value: 'On' },
    { key: 'dns_over_https', value: 'On' },
    { key: 'dns_over_https_provider', value: 'Yandex' },
    // 默认开：这条线路按 SNI 精确阻断 e-hentai（带 SNI 立刻被重置，不带 SNI 直连 IP 返回 200）。
    // 关掉它请求会退回域名请求，主页/搜索/下载全部报 TLS 连接失败。
    { key: 'domain_fronting', value: 'On' },
    { key: 'auto_fronting', value: 'On' },
    // 直连检测默认开：开了 VPN/Clash 时域名能直连，就不必再套 hosts IP（套了反而绕过代理）；
    // 不开 VPN 时探测失败，自动退回 hosts，两种状态都能用。
    { key: 'auto_direct_connection', value: 'On' },
    { key: 'close_auto_updates', value: 'Off' },
    { key: 'network_defaults_20260612', value: 'Applied' },
    { key: 'network_runtime_20260613', value: 'Applied' },
    { key: 'network_proxy_20260613', value: 'Applied' },
    { key: 'network_proxy_20260707', value: 'Applied' },
    { key: 'network_passthrough_20260714', value: 'Applied' },
    { key: 'network_defaults_20261109', value: 'Applied' },
    { key: 'network_defaults_20261110', value: 'Applied' }
  ];
}

export class AppSettingsStore {
  private entries: SettingEntry[] = defaultSettingEntries();
  private valueByKey: Map<string, string> = new Map<string, string>();
  private indexByKey: Map<string, number> = new Map<string, number>();
  private loaded: boolean = false;
  private ensurePromise: Promise<void> | null = null;

  constructor() {
    this.rebuildLookup();
  }

  getEntries(): SettingEntry[] {
    return cloneEntries(this.entries);
  }

  getTransferEntries(): SettingEntry[] {
    const entries: SettingEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      if (!containsString(DEVICE_LOCAL_SETTING_KEYS, this.entries[i].key)) {
        entries.push({ key: this.entries[i].key, value: this.entries[i].value });
      }
    }
    return entries;
  }

  getValue(key: string, fallback: string = ''): string {
    const value = this.valueByKey.get(key);
    return value === undefined ? fallback : value;
  }

  importEntries(entries: SettingEntry[]): SettingImportResult {
    const result: SettingImportResult = {
      imported: 0,
      languageChanged: false,
      themeChanged: false,
      titleChanged: false
    };
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (typeof entry.key !== 'string' || typeof entry.value !== 'string') {
        continue;
      }
      if (containsString(DEVICE_LOCAL_SETTING_KEYS, entry.key)) {
        continue;
      }
      const value = normalizeImportedSettingValue(entry.key, entry.value);
      const previous = this.getValue(entry.key, '');
      if ((entry.key === 'app_language' || entry.key === 'show_tag_translations') && previous !== value) {
        result.languageChanged = true;
      }
      if ((entry.key === 'display_mode' || entry.key === 'theme_color' || entry.key === 'ui_style') &&
        previous !== value) {
        result.themeChanged = true;
      }
      if (entry.key === 'show_jpn_title' && previous !== value) {
        result.titleChanged = true;
      }
      this.setValue(entry.key, value);
      result.imported++;
    }
    return result;
  }

  setValue(key: string, value: string): void {
    const storedValue = key === 'ui_style' && value === 'HarmonyOS 7' ? 'Harmony' : value;
    const index = this.indexByKey.get(key);
    if (index === undefined) {
      this.entries.push({ key: key, value: storedValue });
      this.indexByKey.set(key, this.entries.length - 1);
    } else {
      this.entries[index].value = storedValue;
    }
    this.valueByKey.set(key, storedValue);
    this.enforceAdaptiveDualPageConstraints();
    if (key === 'translation_buttons_enabled') {
      this.syncTranslationButtonVisibility();
    }
    if (key === 'reader_translation_enabled') {
      this.syncReaderTranslationButtonVisibility();
    }
  }

  private enforceAdaptiveDualPageConstraints(): void {
    if (this.getValue('adaptive_dual_page', 'Off') !== 'On') {
      return;
    }
    this.replaceEntryValue('page_scaling', 'Fit screen');
    if (this.getValue('reading_direction', 'Right to left') === 'Top to bottom') {
      this.replaceEntryValue('reading_direction', 'Right to left');
    }
    if (this.getValue('screen_rotation', 'Default') === 'Match image') {
      this.replaceEntryValue('screen_rotation', 'Default');
    }
  }

  private replaceEntryValue(key: string, value: string): void {
    const index = this.indexByKey.get(key);
    if (index === undefined) {
      this.entries.push({ key: key, value: value });
      this.indexByKey.set(key, this.entries.length - 1);
    } else {
      this.entries[index].value = value;
    }
    this.valueByKey.set(key, value);
  }

  private rebuildLookup(): void {
    this.valueByKey.clear();
    this.indexByKey.clear();
    for (let i = 0; i < this.entries.length; i++) {
      this.valueByKey.set(this.entries[i].key, this.entries[i].value);
      this.indexByKey.set(this.entries[i].key, i);
    }
  }

  syncTranslationButtonVisibility(): void {
    AppStorage.setOrCreate<boolean>(TRANSLATION_BUTTONS_VISIBLE_KEY,
      this.getValue('translation_buttons_enabled', 'On') === 'On');
  }

  syncReaderTranslationButtonVisibility(): void {
    AppStorage.setOrCreate<boolean>(READER_TRANSLATION_BUTTON_VISIBLE_KEY,
      this.getValue('reader_translation_enabled', 'Off') === 'On');
  }

  // 早期版本把「智感握持」的默认值写成 On，老用户设置里已经存了 On，
  // 光改默认值救不回来，FAB 会一直被传感器拽着左右跑。这里做一次性迁移改成 Off。
  migrateHoldingHandDefault(): boolean {
    const flag = this.getValue(HOLDING_HAND_MIGRATION_KEY, '');
    if (flag === '1') {
      return false;
    }
    this.setValue(FLOATING_ACTION_HOLDING_HAND_SETTING_KEY, 'Off');
    this.setValue(HOLDING_HAND_MIGRATION_KEY, '1');
    return true;
  }

  ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return Promise.resolve();
    }
    if (this.ensurePromise !== null) {
      return this.ensurePromise;
    }
    const pending: Promise<void> = this.load(context).then(() => {
      this.loaded = true;
      if (this.migrateHoldingHandDefault()) {
        this.save(context).catch(() => {});
      }
    }).finally(() => {
      if (this.ensurePromise === pending) this.ensurePromise = null;
    });
    this.ensurePromise = pending;
    return pending;
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      this.entries = defaultSettingEntries();
      this.rebuildLookup();
      if (typeof raw !== 'string' || raw.length === 0) {
        this.migrateHoldingHandDefault();
        return;
      }

      const parsed = JSON.parse(raw) as StoredSettingEntry[];
      if (!Array.isArray(parsed)) {
        return;
      }

      let hasNetworkMigration = false;
      let hasRuntimeMigration = false;
      let hasProxyMigration = false;
      let hasProxyApi24Migration = false;
      let hasPassthroughMigration = false;
      let hasTranslationProviderSplit = false;
      let hasLegacyHarmonyUiStyle = false;
      let hasHarmonyUiDefaultMigration = false;
      let hasReaderStandaloneMigration = false;
      let hasDefaults20261109 = false;
      let hasDefaults20261110 = false;
      let hasDisplayModeMigration = false;
      let hasAdaptiveAccentMigration = false;
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i];
        if (typeof item.key === 'string' && typeof item.value === 'string') {
          if (item.key === 'display_mode_migration_20261031') {
            hasDisplayModeMigration = true;
          }
          if (item.key === 'theme_color_adaptive_20261031') {
            hasAdaptiveAccentMigration = true;
          }
          if (item.key === 'network_defaults_20260612') {
            hasNetworkMigration = true;
          }
          if (item.key === 'network_runtime_20260613') {
            hasRuntimeMigration = true;
          }
          if (item.key === 'network_proxy_20260613') {
            hasProxyMigration = true;
          }
          if (item.key === 'network_proxy_20260707') {
            hasProxyApi24Migration = true;
          }
          if (item.key === 'network_defaults_20261109') {
            hasDefaults20261109 = true;
          }
          if (item.key === 'network_defaults_20261110') {
            hasDefaults20261110 = true;
          }
          if (item.key === 'network_passthrough_20260714') {
            hasPassthroughMigration = true;
          }
          if (item.key === 'translation_provider_split_20260714') {
            hasTranslationProviderSplit = true;
          }
          if (item.key === 'ui_style' && item.value === 'HarmonyOS 7') {
            hasLegacyHarmonyUiStyle = true;
          }
          if (item.key === 'ui_style_default_harmony_20260826') {
            hasHarmonyUiDefaultMigration = true;
          }
          if (item.key === 'reader_standalone_default_20261027') {
            hasReaderStandaloneMigration = true;
          }
          this.setValue(item.key, item.value);
        }
      }

      // 「主题 + 跟随系统深色模式」合并为「显示模式」三档：浅色 / 深色 / 跟随系统。
      // 旧的两档深色（暗色、黑色）合并为深色，统一用纯黑色板。
      if (!hasDisplayModeMigration) {
        const legacyFollow = this.getValue('follow_system_dark_mode', 'Off');
        const legacyTheme = this.getValue('theme', 'Light');
        const migratedMode = legacyFollow === 'On' ? 'Follow' :
          (legacyTheme === 'Dark' || legacyTheme === 'Black' ? 'Dark' : 'Light');
        this.setValue('display_mode', migratedMode);
        this.setValue('display_mode_migration_20261031', 'Applied');
      }

      // 默认强调色改为「自适应」：此前从未改过主题色的用户留的都是默认值 Blue。
      if (!hasAdaptiveAccentMigration) {
        if (this.getValue('theme_color', 'Blue') === 'Blue') {
          this.setValue('theme_color', 'Adaptive');
        }
        this.setValue('theme_color_adaptive_20261031', 'Applied');
      }

      if (!hasHarmonyUiDefaultMigration) {
        this.setValue('ui_style', 'Harmony');
        this.setValue('ui_style_default_harmony_20260826', 'Applied');
      }

      // 默认改为内置阅读器（不再用独立窗口打开阅读器）。
      if (!hasReaderStandaloneMigration) {
        this.setValue('reader_standalone', 'Off');
        this.setValue('reader_standalone_default_20261027', 'Applied');
      }

      if (!hasNetworkMigration) {
        this.setValue('built_in_hosts', 'On');
        this.setValue('built_ex_hosts', 'On');
        this.setValue('network_defaults_20260612', 'Applied');
      }
      if (!hasDefaults20261109) {
        // 域名前置必须开：这条线路按 SNI 阻断 e-hentai，关掉它主页/搜索/下载全挂
        this.setValue('domain_fronting', 'On');
        this.setValue('cellular_network_warning', 'On');
        this.setValue('preload_image', '3');
        this.setValue('download_thread', '5');
        this.setValue('show_gallery_pages', 'On');
        this.setValue('keep_screen_on', 'On');
        this.setValue('network_defaults_20261109', 'Applied');
      }
      if (!hasDefaults20261110) {
        // 20261109 键在这批默认值定稿前就已被部分安装消费，导致 show_gallery_pages /
        // keep_screen_on 没套上；用新键补一次（幂等，只跑一遍）。
        this.setValue('show_gallery_pages', 'On');
        this.setValue('keep_screen_on', 'On');
        this.setValue('network_defaults_20261110', 'Applied');
      }
      if (!hasRuntimeMigration) {
        this.setValue('network_runtime_20260613', 'Applied');
      }
      if (!hasProxyMigration) {
        if (this.getValue('proxy', 'System') === 'Off') {
          this.setValue('proxy', 'System');
        }
        this.setValue('network_proxy_20260613', 'Applied');
      }
      if (!hasProxyApi24Migration) {
        this.setValue('network_proxy_20260707', 'Applied');
      }
      if (!hasPassthroughMigration) {
        const legacyAutomaticNetworkConfig = hasNetworkMigration &&
          this.getValue('built_in_hosts', 'Off') === 'On' &&
          this.getValue('built_ex_hosts', 'Off') === 'On' &&
          this.getValue('dns_over_https', 'Off') === 'Off' &&
          this.getValue('domain_fronting', 'Off') === 'On' &&
          this.getValue('auto_direct_connection', 'Off') === 'On';
        if (legacyAutomaticNetworkConfig) {
          this.setValue('built_in_hosts', 'Off');
          this.setValue('built_ex_hosts', 'Off');
          this.setValue('domain_fronting', 'Off');
          this.setValue('auto_direct_connection', 'Off');
        }
        this.setValue('network_passthrough_20260714', 'Applied');
      }
      if (this.getValue('download_location', 'App files') !== 'Downloads') {
        this.setValue('download_location', 'App files');
      }
      if (this.getValue('download_timeout', '30s') === 'Default') {
        this.setValue('download_timeout', '30s');
      }
      if (this.getValue('detail_size', 'Medium') === 'Default') {
        this.setValue('detail_size', 'Medium');
      }
      if (this.getValue('detail_size', 'Medium') === 'Large') {
        this.setValue('detail_size', 'Loose');
      }
      this.migrateLegacyTranslationApi();
      if (!hasTranslationProviderSplit) {
        this.migrateTranslationProviderSplit();
      }
      if (!hasPassthroughMigration || !hasTranslationProviderSplit || hasLegacyHarmonyUiStyle ||
        !hasHarmonyUiDefaultMigration || !hasReaderStandaloneMigration) {
        try {
          await prefs.put(VALUES_KEY, JSON.stringify(this.entries));
          await prefs.flush();
        } catch (error) {
        }
      }
    } catch (error) {
      throw new Error(String(error));
    } finally {
      this.syncTranslationButtonVisibility();
      this.syncReaderTranslationButtonVisibility();
    }
  }

  private migrateLegacyTranslationApi(): void {
    const legacyProvider = this.getValue('translation_provider', 'Google Web');
    const legacyBaseUrl = this.getValue('translation_openai_base_url', 'https://api.openai.com/v1').trim();
    const legacyApiKey = this.getValue('translation_openai_api_key', '');
    const legacyModel = this.getValue('translation_openai_model', 'gpt-4o-mini').trim();
    const items = parseSavedTranslationApis(this.getValue('translation_custom_apis', '[]'));
    if (items.length === 0 && (legacyProvider === 'OpenAI compatible' || legacyApiKey.length > 0 ||
      legacyBaseUrl !== 'https://api.openai.com/v1')) {
      const name = uniqueTranslationApiName(items, 'Imported API');
      const imported: SavedTranslationApi = {
        name: name,
        baseUrl: legacyBaseUrl.length > 0 ? legacyBaseUrl : 'https://api.openai.com/v1',
        apiKey: legacyApiKey,
        model: legacyModel
      };
      items.push(imported);
      this.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
      this.setValue('translation_custom_api_selected', name);
    }
    if (legacyProvider === 'OpenAI compatible') {
      this.setValue('translation_provider', 'Custom API');
    }
  }

  private migrateTranslationProviderSplit(): void {
    const provider = this.getValue('translation_provider', 'Google Web');
    if (isServiceTranslationProvider(provider)) {
      this.setValue('translation_ai_enabled', 'On');
      this.setValue('translation_ai_provider', provider);
    } else {
      this.setValue('translation_ai_enabled', 'Off');
      this.setValue('translation_machine_provider', isMachineTranslationProvider(provider) ? provider : 'Google Web');
    }
    this.setValue('translation_provider_split_20260714', 'Applied');
  }

  // 恢复默认设置：把所有非迁移键重置为出厂默认值。
  // 迁移标记键（*_2026xxxx）刻意跳过：恢复后不应让旧迁移重跑覆盖用户刚选的值。
  // Cookie、下载记录、历史等数据存于其他存储，不受影响。
  async resetToDefaults(context: common.UIAbilityContext): Promise<void> {
    const defaults = defaultSettingEntries();
    for (let i = 0; i < defaults.length; i++) {
      const entry = defaults[i];
      if (entry.key.indexOf('_2026') >= 0) {
        continue;
      }
      this.setValue(entry.key, entry.value);
    }
    // 不在默认表里、但通过常量引用的散键也要重置（history_info_size 用常量读写，
    // 否则恢复默认后它没被重置，历史记录数量停在用户改过的值上）
    this.setValue(HISTORY_INFO_SIZE_KEY, '100');
    await this.save(context);
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(this.entries));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }
}

function isServiceTranslationProvider(provider: string): boolean {
  return provider === 'DeepSeek' || provider === 'OpenAI' || provider === 'Gemini' || provider === 'Custom API';
}

function isMachineTranslationProvider(provider: string): boolean {
  return provider === 'Google Web' || provider === 'Bing Web' || provider === 'Baidu Web' ||
    provider === 'Youdao Web' || provider === 'MyMemory' || provider === 'Lingva';
}

export function historyInfoSizeOptions(): string[] {
  return HISTORY_INFO_SIZE_OPTIONS.slice();
}

export function normalizeHistoryInfoSizeOption(value: string): string {
  const size = Number.parseInt(value);
  if (Number.isNaN(size)) {
    return DEFAULT_HISTORY_INFO_SIZE;
  }
  if (size <= 100) {
    return '100';
  }
  if (size <= 500) {
    return '500';
  }
  if (size <= 1000) {
    return '1000';
  }
  if (size <= 5000) {
    return '5000';
  }
  if (size <= 10000) {
    return '10000';
  }
  return '20000';
}

export function normalizeImportedSettingValue(key: string, value: string): string {
  if (key === 'display_mode') {
    return value === 'Dark' || value === 'Follow' ? value : 'Light';
  }
  if (key === 'ui_style') {
    return value === 'Harmony' || value === 'HarmonyOS 7' ? 'Harmony' : 'Classic';
  }
  if (key === 'read_cache_size') {
    if (value === '40 MB' || value === '80 MB') {
      return '160 MB';
    }
    if (value === '160 MB' || value === '320 MB' || value === '640 MB' || value === '1 GB' || value === '2 GB') {
      return value;
    }
    return '160 MB';
  }
  if (key === HISTORY_INFO_SIZE_KEY) {
    return normalizeHistoryInfoSizeOption(value);
  }
  if (key === 'pattern_protection') {
    if (value === 'On' || value === 'Fingerprint first') {
      return 'Fingerprint first';
    }
    if (value === 'Face first' || value === 'Password first') {
      return value;
    }
    return 'Off';
  }
  return value;
}

export function historyInfoSizeLimitFromValue(value: string): number {
  return Number.parseInt(normalizeHistoryInfoSizeOption(value));
}

export function parseDefaultFavoriteSlot(value: string): number | null {
  if (value === DEFAULT_FAVORITE_SLOT_ASK || value.length === 0) {
    return null;
  }
  const parsed = Number.parseInt(value);
  if (Number.isNaN(parsed) || parsed < -1 || parsed > 9) {
    return null;
  }
  return parsed;
}

export function defaultFavoriteSlotSettingValue(slot: number | null): string {
  if (slot === null || slot < -1 || slot > 9) {
    return DEFAULT_FAVORITE_SLOT_ASK;
  }
  return slot.toString();
}

function cloneEntries(entries: SettingEntry[]): SettingEntry[] {
  const cloned: SettingEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    cloned.push({ key: entries[i].key, value: entries[i].value });
  }
  return cloned;
}

function containsString(values: string[], value: string): boolean {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === value) {
      return true;
    }
  }
  return false;
}

export const appSettingsStore: AppSettingsStore = new AppSettingsStore();
