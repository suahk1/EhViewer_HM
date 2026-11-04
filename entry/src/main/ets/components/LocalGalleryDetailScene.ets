import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { DownloadInfo } from '../services/EhDownloadStore';
import { ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import {
  BOTTOM_AVOID_HEIGHT_KEY,
  HISTORY_READ_REVISION_KEY,
  LANGUAGE_REVISION_KEY,
  createEmptyDownloadInfo,
  downloadSizeText,
  galleryDisplayTitle,
  getAbilityContext,
  uiText, padTwo} from '../shared/AppRuntime';
import {
  themeDividerColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeTertiaryText,
  themeSurface
} from '../shared/AppPalette';
import {
  uiButtonMaterial,
  uiMaterialBackground,
  uiRadius,
  uiTransparentButtonBackgroundEffect
} from '../shared/AppSurfaceStyle';
import { GalleryThumb } from './GalleryCards';
import { SidePanelManagerHeader } from './SidePanelComponents';
import { appDockBottomInset } from './FloatingDock';

// 详情页最多铺这么多页预览，长图册不会因为一次性解码上百张小图卡住。
const PREVIEW_THUMB_LIMIT: number = 12;

interface LocalInfoRow {
  label: string;
  value: string;
}

function localDateText(ms: number): string {
  if (ms <= 0) {
    return '-';
  }
  const date = new Date(ms);
  return date.getFullYear().toString() + '-' + padTwo(date.getMonth() + 1) + '-' + padTwo(date.getDate()) + ' ' +
    padTwo(date.getHours()) + ':' + padTwo(date.getMinutes());
}

// 目录里可能混着 jpg / png / webp，按扩展名统计一遍，详情页直接告诉用户这份图源是什么格式。
function localFormatLabel(paths: string[]): string {
  if (paths.length === 0) {
    return '';
  }
  const counts: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < paths.length; i++) {
    const dot = paths[i].lastIndexOf('.');
    const extension = dot >= 0 ? paths[i].substring(dot + 1).toLowerCase() : '';
    if (extension.length === 0) {
      continue;
    }
    counts.set(extension, (counts.get(extension) ?? 0) + 1);
  }
  const keys: string[] = [];
  counts.forEach((_value: number, key: string) => {
    keys.push(key);
  });
  keys.sort();
  const parts: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    parts.push(keys[i].toUpperCase() + ' ' + (counts.get(keys[i]) ?? 0).toString());
  }
  return parts.join(' · ');
}

// 本地图册的详情页：纯本地记录没有服务器详情可拉，信息全部从磁盘现算。
// 列表点开走这里，而不是直接进阅读器，否则图册只有“能读”这一种形态。
@Component
export struct LocalGalleryDetailScene {
  @Prop @Watch('onItemChanged') item: DownloadInfo = createEmptyDownloadInfo();
  @Prop statusBarHeight: number = 0;
  onBack: () => void = () => {};
  onRead: (index: number) => void = (_index: number) => {};
  onRemove: () => void = () => {};
  onMetaRefreshed: (pages: number, bytes: number) => void = (_pages: number, _bytes: number) => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;
  // 从阅读器退回详情时要立刻反映新的阅读进度，否则按钮上还写着进阅读器之前那一页。
  @StorageProp(HISTORY_READ_REVISION_KEY) @Watch('onHistoryReadChanged') historyReadRevision: number = 0;
  @State previewPaths: string[] = [];
  @State pageCount: number = 0;
  @State totalBytes: number = 0;
  @State formatLabel: string = '';
  @State pixelLabel: string = '';
  @State directory: string = '';
  @State readIndex: number = -1;
  @State folderMissing: boolean = false;
  @State copied: boolean = false;

  aboutToAppear(): void {
    this.reloadMeta();
  }

  onItemChanged(): void {
    this.reloadMeta();
  }

  onHistoryReadChanged(): void {
    this.readIndex = ehHistoryStore.getReadPage(this.item.gid);
  }

  private reloadMeta(): void {
    const context = getAbilityContext();
    this.previewPaths = [];
    this.pageCount = 0;
    this.totalBytes = 0;
    this.formatLabel = '';
    this.pixelLabel = '';
    if (context === undefined) {
      return;
    }
    // 一律走目录解析：长标题目录名在落盘时被截断，记录里的 archiveUri 可能直接不存在，
    // 拿它当目录用会得到 0 页、0 字节，看起来像“文件缺失”。
    let directory = ehDownloadFileStore.downloadedGalleryDirectory(context, this.item);
    this.folderMissing = directory.length === 0;
    if (directory.length === 0) {
      // 解析不出来时仍然把记录里的路径显示给用户，比一行 "-" 有用。
      directory = this.item.archiveUri;
    }
    this.directory = directory;
    if (this.folderMissing) {
      this.readIndex = -1;
      return;
    }
    const paths = ehDownloadFileStore.listLocalPageImages(directory);
    this.pageCount = paths.length;
    this.previewPaths = paths.slice(0, PREVIEW_THUMB_LIMIT);
    this.totalBytes = ehDownloadFileStore.directorySizeByPath(directory);
    this.formatLabel = localFormatLabel(paths);
    this.readIndex = ehHistoryStore.getReadPage(this.item.gid);
    this.measureFirstPage(paths.length > 0 ? paths[0] : '');
    // 磁盘才是本地图册的事实来源：记录里的页数可能是早期扫描留下的 0，
    // 顺手回填一次，列表和阅读器的总页数才对得上。
    if (this.pageCount > 0 && (this.item.pages !== this.pageCount || this.item.total !== this.pageCount)) {
      this.onMetaRefreshed(this.pageCount, this.totalBytes);
    }
  }

  private measureFirstPage(path: string): void {
    if (path.length === 0) {
      return;
    }
    // 沙箱里的绝对路径用 fd 打开最稳：file:// uri 在部分设备上 createImageSource 会解不出来。
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      if (source === undefined) {
        fs.closeSync(file.fd);
        return;
      }
      source.getImageInfo().then((info: image.ImageInfo) => {
        this.pixelLabel = info.size.width.toString() + ' × ' + info.size.height.toString();
        source.release();
        if (file !== null) {
          fs.closeSync(file.fd);
        }
      }).catch(() => {
        source.release();
        if (file !== null) {
          fs.closeSync(file.fd);
        }
      });
    } catch (error) {
      this.pixelLabel = '';
      if (file !== null) {
        try {
          fs.closeSync(file.fd);
        } catch (closeError) {
        }
      }
    }
  }

  private coverUrl(): string {
    if (this.item.thumb !== undefined && this.item.thumb.length > 0) {
      return this.item.thumb;
    }
    return this.previewPaths.length > 0 ? this.previewPaths[0] : '';
  }

  private titleText(): string {
    return galleryDisplayTitle(this.item);
  }

  private readProgressText(): string {
    if (this.pageCount <= 0) {
      return '-';
    }
    if (this.readIndex > 0) {
      return Math.min(this.pageCount, this.readIndex + 1).toString() + ' / ' + this.pageCount.toString();
    }
    return '0 / ' + this.pageCount.toString();
  }

  private readButtonText(): string {
    if (this.pageCount <= 0) {
      return uiText('Files missing');
    }
    if (this.readIndex > 0) {
      return uiText('Continue reading') + ' · ' + Math.min(this.pageCount, this.readIndex + 1).toString();
    }
    return uiText('Start reading');
  }

  private infoRows(): LocalInfoRow[] {
    const rows: LocalInfoRow[] = [];
    rows.push({
      label: uiText('Pages'),
      value: this.pageCount > 0 ? this.pageCount.toString() : '-'
    });
    rows.push({
      label: uiText('Size'),
      value: this.totalBytes > 0 ? downloadSizeText(this.totalBytes) : '-'
    });
    if (this.formatLabel.length > 0) {
      rows.push({ label: uiText('Image format'), value: this.formatLabel });
    }
    if (this.pixelLabel.length > 0) {
      rows.push({ label: uiText('First page'), value: this.pixelLabel });
    }
    rows.push({ label: uiText('Read progress'), value: this.readProgressText() });
    rows.push({ label: uiText('Imported'), value: localDateText(this.item.time) });
    if (this.item.label.length > 0) {
      rows.push({ label: uiText('Label'), value: this.item.label });
    }
    return rows;
  }

  private copyDirectory(): void {
    if (this.directory.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.directory);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.copied = true;
        setTimeout(() => {
          this.copied = false;
        }, 1600);
      }).catch(() => {
      });
    } catch (error) {
    }
  }

  @Builder
  private chip(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(themeSecondaryText())
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(themeFieldBackground())
      .borderRadius(uiRadius(4))
  }

  @Builder
  private heroCard() {
    Row({ space: 14 }) {
      GalleryThumb({
        url: this.coverUrl(),
        widthValue: 104,
        heightValue: 140,
        radiusValue: uiRadius(8)
      })

      Column({ space: 8 }) {
        Text(this.titleText())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(themePrimaryText())
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 8 }) {
          this.chip(uiText('Local'))
          if (this.pageCount > 0) {
            this.chip(this.pageCount.toString() + ' P')
          }
        }

        Blank()

        Text(uiText('Local only, no server record'))
          .fontSize(11)
          .fontColor(themeTertiaryText())
          .maxLines(2)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .height(140)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
    .borderRadius(uiRadius(8))
  }

  @Builder
  private infoCard() {
    Column() {
      ForEach(this.infoRows(), (row: LocalInfoRow, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .color(themeDividerColor())
              .margin({ left: 12, right: 12 })
          }
          Row() {
            Text(row.label)
              .fontSize(13)
              .fontColor(themeSecondaryText())
            Blank()
            Text(row.value)
              .fontSize(13)
              .fontColor(themePrimaryText())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
              .margin({ left: 12 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 11, bottom: 11 })
        }
        .width('100%')
      }, (row: LocalInfoRow, index: number) => row.label + ':' + index.toString())
    }
    .width('100%')
    .backgroundColor(themeSurface())
    .borderRadius(uiRadius(8))
    .clip(true)
  }

  @Builder
  private actionCard() {
    Column({ space: 10 }) {
      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(17)
            .fontColor([themeOnPrimaryText()])
          Text(this.readButtonText())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themeOnPrimaryText())
        }
      }
      .width('100%')
      .height(46)
      .backgroundColor(themePrimaryColor())
      .enabled(this.pageCount > 0)
      .onClick(() => {
        this.onRead(this.readIndex > 0 ? this.readIndex : 0);
      })

      Row({ space: 10 }) {
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Text(uiText('Start reading'))
            .fontSize(13)
            .fontColor(themePrimaryText())
        }
        .layoutWeight(1)
        .height(40)
        .backgroundColor(uiMaterialBackground(themeFieldBackground()))
        .backgroundEffect(uiTransparentButtonBackgroundEffect())
        .systemMaterial(uiButtonMaterial())
        .enabled(this.pageCount > 0)
        .onClick(() => {
          this.onRead(0);
        })

        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Text(this.copied ? uiText('Copied') : uiText('Copy path'))
            .fontSize(13)
            .fontColor(themePrimaryText())
        }
        .layoutWeight(1)
        .height(40)
        .backgroundColor(uiMaterialBackground(themeFieldBackground()))
        .backgroundEffect(uiTransparentButtonBackgroundEffect())
        .systemMaterial(uiButtonMaterial())
        .onClick(() => {
          this.copyDirectory();
        })
      }
      .width('100%')

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(15)
            .fontColor([themeSecondaryText()])
          Text(uiText('Remove'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
        }
      }
      .width('100%')
      .height(40)
      .backgroundColor(uiMaterialBackground(themeFieldBackground()))
      .backgroundEffect(uiTransparentButtonBackgroundEffect())
      .systemMaterial(uiButtonMaterial())
      .onClick(() => {
        this.onRemove();
      })
    }
    .width('100%')
  }

  @Builder
  private previewSection() {
    Column({ space: 8 }) {
      Row() {
        Text(uiText('Page preview'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
        Blank()
        if (this.pageCount > this.previewPaths.length) {
          Text('+' + (this.pageCount - this.previewPaths.length).toString())
            .fontSize(12)
            .fontColor(themeTertiaryText())
        }
      }
      .width('100%')

      if (this.previewPaths.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(26)
            .fontColor([themeTertiaryText()])
          Text(this.folderMissing ? uiText('Folder not found; it may have been moved or renamed') :
            uiText('No local images found'))
            .fontSize(12)
            .fontColor(themeTertiaryText())
            .textAlign(TextAlign.Center)
            .padding({ left: 18, right: 18 })
        }
        .width('100%')
        .height(110)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(8))
      } else {
        // 预览图与云端详情页保持一致：竖向自动换行，不做横向滚动。
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.previewPaths, (path: string, index: number) => {
            Column({ space: 4 }) {
              GalleryThumb({
                url: path,
                widthValue: 78,
                heightValue: 104,
                radiusValue: uiRadius(6)
              })
              Text((index + 1).toString())
                .fontSize(11)
                .fontColor(themeTertiaryText())
            }
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.onRead(index);
            })
          }, (path: string) => path)
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })
      }
    }
    .width('100%')
  }

  @Builder
  private directoryCard() {
    Column({ space: 6 }) {
      Text(uiText('Folder'))
        .fontSize(13)
        .fontColor(themeSecondaryText())
      Text(this.directory.length > 0 ? this.directory : '-')
        .fontSize(11)
        .fontColor(themeTertiaryText())
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(themeSurface())
    .borderRadius(uiRadius(8))
  }

  build() {
    Column() {
      SidePanelManagerHeader({
        statusBarHeight: this.statusBarHeight,
        title: 'Local gallery',
        onBack: () => {
          this.onBack();
        }
      })

      Scroll() {
        Column({ space: 12 }) {
          this.heroCard()
          this.infoCard()
          this.actionCard()
          this.previewSection()
          this.directoryCard()
          // 底部占位放进滚动内容里，滑到底时它能沉到胶囊下面，目录卡片才不会被切。
          Row()
            .width('100%')
            .height(appDockBottomInset(this.bottomAvoidHeight))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 4 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}
