import { curves, display } from '@kit.ArkUI';
import { GalleryRoute } from '../model/GalleryModels';
import {
  LANGUAGE_REVISION_KEY,
  THEME_REVISION_KEY,
  dockLabel,
  uiText
} from '../shared/AppRuntime';
import {
  isDarkTheme,
  themeAccentTextColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor
} from '../shared/AppPalette';
import { uiDockHighlightBorder, uiDockBackgroundEffect, uiGlassBarEffect, uiPopupEffectBackground,
  uiRadius } from '../shared/AppSurfaceStyle';

// 鸿蒙图库式浮起标签栏：白色胶囊、贴底居中、无通栏、无描边顶线。
export const APP_DOCK_BAR_HEIGHT: number = 60;
// 胶囊左右内边距（与 build 里的 padding 一致），白块定位必须扣掉它。
const DOCK_PADDING: number = 6;
// 列表末尾要留出的空间：胶囊高度 + 与内容的间距。
export const APP_DOCK_CONTENT_INSET: number = 84;
// 胶囊离屏幕底缘的最小间距：系统手势条通常占 12–16vp 且贴着底缘，
// 再留呼吸位，24vp 才能保证胶囊不会压在小横条上（读不到 avoidArea 时也成立）。
export const APP_DOCK_MIN_BOTTOM_GAP: number = 24;
// 手势条之上的呼吸位。
export const APP_DOCK_VISUAL_GAP: number = 8;

// 底栏离屏幕底缘的实际距离：手势条高度；冷启动 avoidArea 未上报时用最小间距兜底。
// 胶囊定位与列表留白都从这里取值，全应用只有这一套。
export function appDockBottomGap(bottomAvoid: number): number {
  // 系统避让只是"手势条多高"，胶囊不能压着它放：避让 + 呼吸位，且不低于按屏高算出的下限。
  // 有的设备只报 16vp，直接跟随就会出现"胶囊和小横条叠在一起"。
  return Math.max(bottomAvoid + APP_DOCK_VISUAL_GAP, dockMinBottomGap());
}

// 屏幕短边越高，间距按比例放大：手机 24vp 左右，平板不会显得贴底，小屏也不会挤。
export function dockMinBottomGap(): number {
  const heightVp = dockScreenHeightVp();
  const scaled = heightVp * 0.028;
  return Math.max(APP_DOCK_MIN_BOTTOM_GAP, Math.min(36, Math.round(scaled)));
}

function dockScreenHeightVp(): number {
  try {
    const info = display.getDefaultDisplaySync();
    if (info.densityPixels > 0) {
      return info.height / info.densityPixels;
    }
  } catch (error) {
  }
  return 800;
}

// 列表末尾的完整留白：胶囊高度 + 胶囊离底距离 + 内容间隙。
export function appDockBottomInset(bottomAvoid: number, extra: number = 0): number {
  return APP_DOCK_CONTENT_INSET + appDockBottomGap(bottomAvoid) + extra;
}
// FAB 抬到胶囊上沿之上。
export const APP_DOCK_FAB_RESERVE: number = 72;
// 选中态图标交叉淡化时长，对齐系统应用的点按反馈节奏。
const DOCK_FADE_MS: number = 180;

type DockIconKind = 'home' | 'favorites' | 'downloads' | 'settings' |
  'subscription' | 'whatshot' | 'toplist' | 'history';

interface DockEntry {
  route: GalleryRoute;
  label: string;
  icon: DockIconKind;
}

const DOCK_ENTRIES: DockEntry[] = [
  { route: GalleryRoute.Home, label: 'Homepage', icon: 'home' },
  { route: GalleryRoute.Favorites, label: 'Favourite', icon: 'favorites' },
  { route: GalleryRoute.Downloads, label: 'Download', icon: 'downloads' },
  { route: GalleryRoute.Settings, label: 'Settings', icon: 'settings' }
];

// 底栏放不下的四个一级入口，从右端的小箭头弹出。
export const DOCK_MORE_ENTRIES: DockEntry[] = [
  { route: GalleryRoute.Subscription, label: 'Subscription', icon: 'subscription' },
  { route: GalleryRoute.WhatsHot, label: "What's Hot", icon: 'whatshot' },
  { route: GalleryRoute.TopLists, label: 'Top Lists', icon: 'toplist' },
  { route: GalleryRoute.History, label: 'History', icon: 'history' }
];

// 右端箭头占的宽度。四项等分时要先扣掉这块，否则光斑和命中区都会偏。
const DOCK_ARROW_WIDTH: number = 34;

// 展开面板的实测高度：4 项 × 42 + 3 段间距 × 2 + 上下内边距 12。
// 面板用绝对定位叠在胶囊上方（不参与底栏布局），定位需要这个数值。
export const DOCK_MORE_MENU_HEIGHT: number = 186;

function dockSymbol(icon: DockIconKind, active: boolean): Resource {
  switch (icon) {
    case 'favorites':
      return active ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart');
    case 'downloads':
      return active ? $r('sys.symbol.arrow_down_to_line_circle_fill') : $r('sys.symbol.arrow_down_circle');
    case 'settings':
      return active ? $r('sys.symbol.gearshape_fill') : $r('sys.symbol.gearshape');
    case 'subscription':
      return $r('sys.symbol.book');
    case 'whatshot':
      return $r('sys.symbol.flame');
    case 'toplist':
      return $r('sys.symbol.list_number');
    case 'history':
      return $r('sys.symbol.clock');
    default:
      return active ? $r('sys.symbol.house_fill') : $r('sys.symbol.house');
  }
}

@Component
export struct FloatingDock {
  @Prop activeRoute: GalleryRoute = GalleryRoute.Home;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;
  @State private pressedRoute: string = '';
  @State private pressedScale: number = 1;
  @State private dragRoute: string = '';
  @State private dockWidth: number = 0;
  @State private dragX: number = -1;
  // 切换瞬间在目标项位置亮起的一团柔光（相册就是靠这个做反馈，不是常驻背景块）。
  @State private glowIndex: number = -1;
  @State private glowOpacity: number = 0;
  @State private glowScale: number = 0.86;
  @State private glowCenterX: number = -1;
  @State private glowCenterY: number = -1;
  @State private fingerGlowX: number = -1;
  @State private fingerGlowY: number = -1000;
  @State private fingerGlowOpacity: number = 0;
  @State private fingerGlowScale: number = 1;
  onSelect: (route: GalleryRoute) => void = (_route: GalleryRoute) => {};
  // 再次点击当前已选中的项：回到该路由的根部（列表），保留其他路由的现场。
  onReselect: () => void = () => {};
  // 菜单渲染在页面层（不受胶囊高度裁剪），这里只负责把「打开」的意图递出去。
  onMoreRequest: () => void = () => {};
  // 胶囊实测宽度上报给页面层：展开面板要贴着胶囊右端放。
  onDockWidthChange: (width: number) => void = (_width: number) => {};
  @Prop moreExpanded: boolean = false;
  private touchStartX: number = 0;
  // 手指一动就进入拖拽，不再等长按。
  private dragMoved: boolean = false;
  private suppressTap: boolean = false;

  private isActive(entry: DockEntry): boolean {
    return this.activeRoute === entry.route;
  }

  private routeKey(route: GalleryRoute): string {
    return route.toString();
  }

  // 拖动经过某项时不再改缩放：那会让 .animation() 每次进出槽都重放一遍，
  // 手指快速划过四个槽就是四次动画重启，看起来就是卡。拖动反馈交给图标变色和光斑。
  private iconScale(entry: DockEntry): number {
    return this.pressedRoute === this.routeKey(entry.route) ? this.pressedScale : 1;
  }

  // 胶囊左右各有 6vp 内边距，四个标签实际分的是 dockWidth - 12。
  private dockSlotWidth(): number {
    const usable = this.dockWidth - DOCK_PADDING * 2 - DOCK_ARROW_WIDTH;
    return DOCK_ENTRIES.length > 0 && usable > 0 ? usable / DOCK_ENTRIES.length : 0;
  }

  // 拖拽时跟手的柔光位置（扣掉胶囊内边距，夹在内容区内）。
  private dragGlowX(): number {
    const slot = this.dockSlotWidth();
    if (slot <= 0 || this.dragX < 0) {
      return 0;
    }
    const usable = slot * DOCK_ENTRIES.length;
    return Math.max(0, Math.min(usable - slot, this.dragX - DOCK_PADDING - slot / 2));
  }

  // 点按高光是正圆：直径不超过胶囊高度，也不超过一个槽位，
  // 用宽矩形画径向渐变会被横向拉长、上下被裁平，看着就是中间一条扁光。
  private glowDiameter(): number {
    const slot = this.dockSlotWidth();
    const slotLimit = slot > 0 ? slot * 1.3 : APP_DOCK_BAR_HEIGHT;
    return Math.max(46, Math.min(APP_DOCK_BAR_HEIGHT, slotLimit));
  }

  // 内容区坐标（不含胶囊左右内边距）：按下点、槽位中心都按这套算，
  // 真正定位时再由 glowLeft 补回内边距，圆心才和手指落在同一点上。
  private slotCenterX(index: number): number {
    return index * this.dockSlotWidth() + this.dockSlotWidth() / 2;
  }

  private glowLeft(centerX: number): number {
    return DOCK_PADDING + centerX - this.glowDiameter() / 2;
  }

  private glowTop(): number {
    return (APP_DOCK_BAR_HEIGHT - this.glowDiameter()) / 2;
  }

  // 圆心跟着触点的 y 走：点图标上半部分就亮在上面，不再固定在中线。
  // 只有 -1（还没按下过）才回退到居中；不能拿 < 0 当"没记录"——
  // 手指落在胶囊上边缘时触摸坐标本来就是负数，会被误判成未初始化、光斑跳回中间。
  private glowTopAt(centerY: number): number {
    // 只有"还没按下过"才回退居中。判断用明确的哨兵值，
    // 不能拿 < 0 当未初始化：手指落在胶囊上边缘时触摸坐标本来就是负数，
    // 会被误判、光斑直接跳回中间（顶部跳、底部不跳，就是这个原因）。
    if (centerY <= -999) {
      return this.glowTop();
    }
    return centerY - this.glowDiameter() / 2;
  }

  // 浅色主题的胶囊本身就是白玻璃，白色高光叠上去看不见；
  // 深色用白光，浅色改用主题色的淡雾，两种主题都能看出"点在哪亮在哪"。
  private glowColors(peak: number): Array<[ResourceColor, number]> {
    if (isDarkTheme()) {
      return [['rgba(255,255,255,' + peak.toString() + ')', 0],
        ['rgba(255,255,255,' + (peak * 0.55).toFixed(3) + ')', 0.40],
        ['rgba(255,255,255,' + (peak * 0.16).toFixed(3) + ')', 0.70],
        ['rgba(255,255,255,0.00)', 1.00]];
    }
    const hex = themePrimaryColor();
    const r = Number.parseInt(hex.substring(1, 3), 16);
    const g = Number.parseInt(hex.substring(3, 5), 16);
    const b = Number.parseInt(hex.substring(5, 7), 16);
    const prefix = 'rgba(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ',';
    const stops: Array<[ResourceColor, number]> = [
      [prefix + peak.toString() + ')', 0],
      [prefix + (peak * 0.52).toFixed(3) + ')', 0.40],
      [prefix + (peak * 0.14).toFixed(3) + ')', 0.70],
      [prefix + '0.00)', 1.00]
    ];
    return stops;
  }

  private indexOfEntry(entry: DockEntry): number {
    for (let i = 0; i < DOCK_ENTRIES.length; i++) {
      if (DOCK_ENTRIES[i].route === entry.route) {
        return i;
      }
    }
    return -1;
  }

  // 亮起比系统慢一点：系统电话底栏那一下是「点上去先亮、松手再散」，太快会像闪屏。
  // 圆心取按下点：落槽位中心会和手指错开半格，看起来就是"只会居中"。
  private flashGlow(index: number, centerX: number, centerY: number): void {
    if (index < 0) {
      return;
    }
    this.glowIndex = index;
    this.glowCenterX = centerX;
    this.glowCenterY = centerY;
    this.glowOpacity = 0.0;
    this.glowScale = 0.86;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.glowOpacity = 1.0;
      this.glowScale = 1.0;
    });
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 520, curve: Curve.EaseOut }, () => {
        this.glowOpacity = 0;
        this.glowScale = 1.35;
      });
    }, 210);
  }

  private glowCenterXFor(index: number): number {
    if (this.glowCenterX >= 0) {
      return this.glowCenterX;
    }
    return this.slotCenterX(Math.max(0, index));
  }

  // item 局部坐标 → 胶囊内坐标：item 宽度就是一个槽位，左边界 = index * 槽宽。
  // 不用冒泡到 Stack 的 touches 坐标，避免坐标被换算成另一套参考系。
  private pointerGlowAt(contentX: number, contentY: number, pressed: boolean): void {
    if (contentX < 0) {
      return;
    }
    this.fingerGlowX = contentX;
    this.fingerGlowY = contentY;
    if (pressed) {
      this.fingerGlowScale = 1;
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
        this.fingerGlowOpacity = 0.9;
      });
    }
  }

  private handleTap(entry: DockEntry): void {
    if (this.suppressTap) {
      return;
    }
    const index = this.indexOfEntry(entry);
    // 点当前已选中的项也要回一次光，否则手指按下去没有任何反馈，像没点上。
    this.flashGlow(index, this.fingerGlowX >= 0 ? this.fingerGlowX : this.slotCenterX(index),
      this.fingerGlowY);
    if (entry.route === this.activeRoute) {
      this.onReselect();
      return;
    }
    this.onSelect(entry.route);
  }

  private activeIndex(): number {
    for (let i = 0; i < DOCK_ENTRIES.length; i++) {
      if (DOCK_ENTRIES[i].route === this.activeRoute) {
        return i;
      }
    }
    return 0;
  }


  private indexAt(x: number): number {
    if (this.dockWidth <= 0) {
      return -1;
    }
    const itemWidth = (this.dockWidth - DOCK_PADDING * 2 - DOCK_ARROW_WIDTH) / DOCK_ENTRIES.length;
    if (itemWidth <= 0) {
      return -1;
    }
    const index = Math.floor(x / itemWidth);
    return Math.max(0, Math.min(DOCK_ENTRIES.length - 1, index));
  }

  private finishDrag(x: number): void {
    const index = this.indexAt(x);
    const target = index >= 0 ? DOCK_ENTRIES[index] : undefined;
    this.dragMoved = false;
    this.dragRoute = '';
    this.pressedRoute = '';
    this.pressedScale = 1;
    this.suppressTap = true;
    setTimeout(() => {
      this.suppressTap = false;
    }, 80);
    if (target === undefined || target.route === this.activeRoute) {
      return;
    }
    this.flashGlow(index, this.fingerGlowX >= 0 ? this.fingerGlowX : x, this.fingerGlowY);
    this.onSelect(target.route);
  }

  @Styles pressedDim(): void {
    .opacity(0.8)
  }

  // 颜色只跟选中态。以前拖动经过时还让字体/图标跟着变主题色，等于每划过一项就
  // 让 SymbolGlyph 重新生成一次字形位图，四个槽来回就是八次，滑快必卡。
  // 拖动反馈交给光斑，颜色只在真正切换后变。
  private isHighlighted(entry: DockEntry): boolean {
    return this.isActive(entry);
  }

  @Builder
  private dockItem(entry: DockEntry) {
    Column({ space: 3 }) {
      // 描边图标与填充图标叠放，切换选中时交叉淡化，避免符号资源硬替换的闪跳。
      // 判断里只留 isActive：以前还带 dragRoute.length === 0，拖动经过当前选中项时
      // 这个条件每帧在真/假之间翻，图标跟着来回交叉淡化，动画反复重放就是拖动掉帧的来源。
      Stack() {
        SymbolGlyph(dockSymbol(entry.icon, false))
          .fontSize(23)
          .fontColor([this.isActive(entry) ? themePrimaryText() : themeSecondaryText()])
          .opacity(this.isActive(entry) ? 0 : 1)

        SymbolGlyph(dockSymbol(entry.icon, true))
          .fontSize(23)
          .fontColor([themePrimaryText()])
          .opacity(this.isActive(entry) ? 1 : 0)
      }
      .width(26)
      .height(26)
      .scale({ x: this.iconScale(entry), y: this.iconScale(entry) })
      .animation({ duration: DOCK_FADE_MS, curve: Curve.EaseOut })

      // 英文标签（Homepage/Download 等）比中文宽，固定 11fp 会被裁成 Homepa/Downloa：
      // 先用 width('100%') 把 Text 约束进等分栏（否则 Text 按内容宽溢出、自适应不触发），
      // 再允许 9~11fp 自动缩字号，单行完整显示；中文仍以 11fp 渲染不受影响。
      Text(dockLabel(entry.label))
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontSize(11)
        .minFontSize(9)
        .maxFontSize(11)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(14)
        .fontWeight(this.isActive(entry) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.isActive(entry) ? themePrimaryText() : themeSecondaryText())
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(APP_DOCK_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .stateStyles({ pressed: this.pressedDim })
    .onTouch((event: TouchEvent) => {
      if (this.dragMoved) {
        return;
      }
      const key = this.routeKey(entry.route);
      if (event.type === TouchType.Down) {
        this.pressedRoute = key;
        this.getUIContext().animateTo({ curve: curves.springMotion(0.3, 0.7) }, () => {
          this.pressedScale = 0.9;
        });
      } else if ((event.type === TouchType.Up || event.type === TouchType.Cancel) &&
        this.pressedRoute === key) {
        this.pressedRoute = '';
        this.getUIContext().animateTo({ curve: curves.springMotion(0.3, 0.7) }, () => {
          this.pressedScale = 1;
        });
      }
    })
    .onClick(() => {
      this.handleTap(entry);
    })
  }

  // 右端小箭头：向内是"还有更多"，展开后翻成向下。
  // 用绝对位移而不是塞进 Row：Row 里四个 layoutWeight(1) 的图标会把定宽子项压成 0。
  @Builder
  private moreButton() {
    Column() {
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(15)
        .fontColor([themeSecondaryText()])
        .rotate({ angle: this.moreArrowAngle() })
        .animation({ duration: 180, curve: Curve.EaseOut })
    }
    .width(DOCK_ARROW_WIDTH)
    .height(APP_DOCK_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .translate({
      x: Math.max(0, this.dockWidth - DOCK_PADDING - DOCK_ARROW_WIDTH),
      y: 0
    })
    .zIndex(4)
    // 系统浮层（bindMenu）是实心底板，做不出玻璃，也会盖住胶囊的高光。
    // 菜单交给页面层渲染：那边不受 60vp 胶囊高度裁剪，还能和水波一样从箭头位置展开。
    .onClick(() => {
      this.onMoreRequest();
    })
  }

  // 箭头旋转跟着展开状态走，看起来像把面板拉出来。
  private moreArrowAngle(): number {
    return this.moreExpanded ? 0 : 180;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 顶部高光带：从顶端往下渐隐的一段。
      // 高光带必须铺满胶囊宽度——Stack 上的内边距会把渐变一起缩进去，
      // 边缘和自己的圆角就画出一道"框里套框"。
      Row()
        .width('100%')
        .height(APP_DOCK_BAR_HEIGHT)
        .linearGradient({
          angle: 180,
          colors: isDarkTheme()
            ? [['rgba(255,255,255,0.13)', 0], ['rgba(255,255,255,0.03)', 0.42],
               ['rgba(255,255,255,0.00)', 1]]
            : [['rgba(255,255,255,0.55)', 0], ['rgba(255,255,255,0.18)', 0.42],
               ['rgba(255,255,255,0.00)', 1]]
        })
        .borderRadius(APP_DOCK_BAR_HEIGHT / 2)
        .hitTestBehavior(HitTestMode.None)

      Row({ space: 0 }) {
        ForEach(DOCK_ENTRIES, (entry: DockEntry) => {
          this.dockItem(entry)
        }, (entry: DockEntry) => entry.route)
      }
      .height(APP_DOCK_BAR_HEIGHT)
      .width('100%')
      // 内边距从 Stack 挪到这里：高光带要铺满整条胶囊，不能被内边距缩进去。
      // 左右各 6vp，右端再留出箭头的 34vp，四项按剩余宽度等分。
      .padding({ left: DOCK_PADDING, right: DOCK_PADDING + DOCK_ARROW_WIDTH })

      this.moreButton()

      // 光晕必须叠在胶囊之上：放在 Row 下面会被磨砂背景盖住，一点都看不见。
      // 跟手柔光：按下就亮，手指移到哪跟到哪，松手淡出。不是只有拖动才有。
      if (this.fingerGlowOpacity > 0.01) {
        Column()
          .width(this.glowDiameter())
          .height(this.glowDiameter())
          .borderRadius(this.glowDiameter() / 2)
          .radialGradient({
            center: ['50%', '50%'],
            radius: '50%',
            colors: this.glowColors(isDarkTheme() ? 0.78 : 0.60)
          })
          .opacity(this.fingerGlowOpacity)
          .scale({ x: this.fingerGlowScale, y: this.fingerGlowScale })
          .translate({
            x: this.glowLeft(this.fingerGlowX),
            y: this.glowTopAt(this.fingerGlowY)
          })
          .hitTestBehavior(HitTestMode.None)
      }

      // 切换时的一次性柔光：中心白、边缘全透明，亮起后扩散淡出。
      // 相册里没有常驻高亮块，只有这一下光，选中态靠图标变色表达。
      if (this.glowOpacity > 0.01) {
        Column()
          .width(this.glowDiameter())
          .height(this.glowDiameter())
          .borderRadius(this.glowDiameter() / 2)
          .radialGradient({
            center: ['50%', '50%'],
            radius: '50%',
            colors: this.glowColors(0.62)
          })
          .opacity(this.glowOpacity)
          .scale({ x: this.glowScale, y: this.glowScale })
          .translate({
            x: this.glowLeft(this.glowCenterXFor(this.glowIndex)),
            y: this.glowTopAt(this.glowCenterY)
          })
          .hitTestBehavior(HitTestMode.None)
      }

    }
    .height(APP_DOCK_BAR_HEIGHT)
    // 自适应：宽度取屏宽 52%（对齐系统图库胶囊比例），四项等分；
    // 小屏兜底 236vp 保证四字标签不被压缩，大屏封顶 420vp 避免拉成长条。
    .width('52%')
    .constraintSize({ minWidth: 236, maxWidth: 420 })
    .borderRadius(APP_DOCK_BAR_HEIGHT / 2)
    // 光斑按 1.9 倍槽位宽画，不裁的话会漏到胶囊外面，尤其深色下一条白边非常显眼。
    .clip(true)
    // 材质与顶栏同族：模糊 + 提亮 + 饱和，颜色由背景效果自带，不再叠不透明底色。
    .backgroundEffect(uiDockBackgroundEffect())
    // 玻璃切面高光：上亮下暗，与顶栏圆形按钮同一套语言。
    .border(uiDockHighlightBorder())
    .shadow({
      radius: 30,
      color: themeShadowColor(),
      offsetX: 0,
      offsetY: 12
    })
    .opacity(1)
    // 胶囊是独立控件层：触摸必须止步于此，否则长按/拖动会穿透到下面的图册列表。
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.dockWidth = Number.parseFloat(newArea.width.toString());
      this.onDockWidthChange(this.dockWidth);
    })
    .onTouch((event: TouchEvent) => {
      const x = event.touches.length > 0 ? event.touches[0].x : 0;
      if (event.type === TouchType.Down) {
        this.touchStartX = x;
        this.dragMoved = false;
        this.dragRoute = '';
        this.dragX = -1;
        // 光效由整条胶囊驱动：箭头区、内边距、四角都算数，不再只有四个槽位能亮。
        this.pointerGlowAt(x, event.touches.length > 0 ? event.touches[0].y : 0, true);
      } else if (event.type === TouchType.Move) {
        // 移动也走整条胶囊的坐标，光斑才能一路跟到箭头区和边角。
        this.pointerGlowAt(x, event.touches.length > 0 ? event.touches[0].y : 0, false);
        // 按下后手指一动就开始跟随，不需要长按等待；6vp 阈值只用来吃掉抖动。
        if (!this.dragMoved && Math.abs(x - this.touchStartX) > 6) {
          this.dragMoved = true;
          this.pressedRoute = '';
          this.pressedScale = 1;
        }
        if (this.dragMoved) {
          this.dragX = x;
          const index = this.indexAt(x);
          if (index >= 0) {
            this.dragRoute = this.routeKey(DOCK_ENTRIES[index].route);
          }
        }
      } else if (event.type === TouchType.Up) {
        // 消失要快（130ms），同时向外轻微扩散，看着是"散开"而不是"被关掉"。
        this.getUIContext().animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
          this.fingerGlowOpacity = 0;
          this.fingerGlowScale = 1.12;
        });
        if (this.dragMoved) {
          this.dragX = x;
          this.finishDrag(x);
        } else {
          this.dragRoute = '';
        }
      } else if (event.type === TouchType.Cancel) {
        this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
          this.fingerGlowOpacity = 0;
          this.fingerGlowScale = 1.08;
        });
        this.dragMoved = false;
        this.dragRoute = '';
        this.dragX = -1;
      }
    })
  }
}

// 底坞右箭头展开的入口面板。
// 不挂在胶囊里：胶囊只有 60vp 高，自绘内容会被裁掉；这里由页面层组装，
// 材质与底坞、悬浮按钮同一套（玻璃 + 切面高光 + 接触阴影）。
@Component
export struct DockMoreMenu {
  @Prop activeRoute: GalleryRoute = GalleryRoute.Home;
  onSelect: (route: GalleryRoute) => void = (_route: GalleryRoute) => {};
  // 光效按整块面板算：一个光斑跟着手指在四项之间自由移动，
  // 拆成每项一个的话，手指一跨项光斑就断在边界上。
  @State private glowX: number = -1000;
  @State private glowY: number = -1000;
  @State private glowOpacity: number = 0;
  @State private glowScale: number = 1;

  private glowDiameter(): number {
    // 比行高（42）大，裁在面板里之后整行高度都发亮。
    return 76;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 2 }) {
        ForEach(DOCK_MORE_ENTRIES, (entry: DockEntry) => {
          Row({ space: 10 }) {
            SymbolGlyph(dockSymbol(entry.icon, entry.route === this.activeRoute))
              .fontSize(17)
              .fontColor([entry.route === this.activeRoute ? themePrimaryText() : themeSecondaryText()])
            Text(uiText(entry.label))
              .fontSize(13)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(entry.route === this.activeRoute ? themePrimaryText() : themeSecondaryText())
          }
          .width('100%')
          .height(42)
          .padding({ left: 12, right: 12 })
          .borderRadius(uiRadius(10))
          .onClick(() => {
            this.onSelect(entry.route);
          })
        }, (entry: DockEntry) => entry.route)
      }
      .width('100%')

      if (this.glowOpacity > 0.01) {
        Column()
          .width(this.glowDiameter())
          .height(this.glowDiameter())
          .borderRadius(this.glowDiameter() / 2)
          .radialGradient({
            center: ['50%', '50%'],
            radius: '46%',
            colors: isDarkTheme()
              ? [['rgba(255,255,255,0.70)', 0], ['rgba(255,255,255,0.34)', 0.45],
                 ['rgba(255,255,255,0.12)', 0.72], ['rgba(255,255,255,0.00)', 1]]
              : [['rgba(58,78,96,0.30)', 0], ['rgba(58,78,96,0.19)', 0.45],
                 ['rgba(58,78,96,0.08)', 0.72], ['rgba(58,78,96,0.00)', 1]]
          })
          .opacity(this.glowOpacity)
          .scale({ x: this.glowScale, y: this.glowScale })
          .translate({
            x: this.glowX - this.glowDiameter() / 2,
            y: this.glowY - this.glowDiameter() / 2
          })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(184)
    .padding(6)
    .borderRadius(uiRadius(18))
    // 光斑裁在面板里，不然会糊到底栏和页面上。
    .clip(true)
    .onTouch((event: TouchEvent) => {
      if (event.touches.length === 0) {
        return;
      }
      const x = event.touches[0].x;
      const y = event.touches[0].y;
      if (event.type === TouchType.Down) {
        this.glowX = x;
        this.glowY = y;
        this.glowScale = 1;
        this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
          this.glowOpacity = 0.95;
        });
      } else if (event.type === TouchType.Move) {
        this.glowX = x;
        this.glowY = y;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.getUIContext().animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
          this.glowOpacity = 0;
          this.glowScale = 1.12;
        });
      }
    })
    // 和底坞、悬浮按钮同一套玻璃：底色只提供一层薄纱，透出下面内容。
    .backgroundColor(uiPopupEffectBackground(themeFieldBackground()))
    .backgroundEffect(uiGlassBarEffect(26))
    .border(uiDockHighlightBorder())
    // 玻璃在白底上几乎没有对比，靠一层接触阴影把它从页面上托起来。
    .shadow({ radius: 18, color: themeShadowColor(), offsetY: 6 })
  }

}
