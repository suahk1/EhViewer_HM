import { ehTranslationService } from '../services/EhTranslationService';

@Component
export struct TranslationText {
  @Prop @Watch('onSourceChanged') sourceText: string = '';
  @Prop @Watch('onEnabledChanged') translationEnabled: boolean = false;
  @Prop @Watch('onPriorityChanged') translationPriority: number = 2;
  @Prop contentKind: string = 'gallery title';
  @Prop fontSizeValue: number = 15;
  @Prop fontColorValue: ResourceColor = Color.Black;
  @Prop fontWeightValue: number = FontWeight.Regular;
  @Prop maxLinesValue: number = 3;
  @Prop lineHeightValue: number = 20;
  @Prop textAlignValue: TextAlign = TextAlign.Start;
  @Prop selectable: boolean = false;
  @State translatedText: string = '';
  private requestVersion: number = 0;

  aboutToAppear(): void {
    this.resetTranslation();
  }

  onSourceChanged(): void {
    this.resetTranslation();
  }

  onEnabledChanged(): void {
    this.resetTranslation();
  }

  onPriorityChanged(): void {
    this.requestTranslationIfNeeded();
  }

  private resetTranslation(): void {
    this.requestVersion++;
    this.translatedText = '';
    this.requestTranslationIfNeeded();
  }

  private requestTranslationIfNeeded(): void {
    // F-124 诊断日志：定位「列表标题不翻译」（临时，定位后移除）。
    console.info('[TranslationDiag] request gate: enabled=' + this.translationEnabled.toString() +
      ' priority=' + this.translationPriority.toString() +
      ' sourceLen=' + this.sourceText.trim().length.toString() +
      ' kind=' + this.contentKind);
    if (!this.translationEnabled || this.translationPriority <= 0 || this.sourceText.trim().length === 0) {
      return;
    }
    if (this.translatedText.length > 0) {
      return;
    }
    this.requestVersion++;
    const version = this.requestVersion;
    const request = this.contentKind === 'gallery comment' ?
      ehTranslationService.translateComment(this.sourceText, this.translationPriority) :
      ehTranslationService.translateTitle(this.sourceText, this.translationPriority);
    request.then((translated: string) => {
      if (version === this.requestVersion && this.translationEnabled) {
        this.translatedText = translated;
      }
    }).catch((error: Error) => {
      console.info('[TranslationDiag] request failed: ' + error.message);
      if (version !== this.requestVersion) {
        return;
      }
      // F-124 用户反馈「点了翻译没作用」：六源降级后仍失败多为限流抖动，
      // 静默放弃会让整列表维持原文。可见条目（优先级 2）延迟 3 秒重试一次。
      if (this.translationPriority >= 2) {
        setTimeout(() => {
          if (version !== this.requestVersion || !this.translationEnabled ||
            this.translatedText.length > 0) {
            return;
          }
          this.requestVersion++;
          const retryVersion = this.requestVersion;
          // force=true：绕过首个请求的 pending key，强制重发（失败不缓存）。
          const retry = ehTranslationService.translate(this.sourceText, this.contentKind,
            this.translationPriority, true, false, true);
          retry.then((translated: string) => {
            if (retryVersion === this.requestVersion && this.translationEnabled) {
              this.translatedText = translated;
            }
          }).catch(() => {
            if (retryVersion === this.requestVersion && this.translatedText.length === 0) {
              this.translatedText = '';
            }
          });
        }, 3000);
      } else if (this.translatedText.length === 0) {
        this.translatedText = '';
      }
    });
  }

  private displayText(): string {
    return this.translationEnabled && this.translatedText.length > 0 ? this.translatedText : this.sourceText;
  }

  build() {
    Text(this.displayText())
      .fontSize(this.fontSizeValue)
      .fontColor(this.fontColorValue)
      .fontWeight(this.fontWeightValue)
      .lineHeight(this.lineHeightValue)
      .textAlign(this.textAlignValue)
      .maxLines(this.maxLinesValue)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .copyOption(this.selectable ? CopyOptions.LocalDevice : CopyOptions.None)
      .width('100%')
  }
}
