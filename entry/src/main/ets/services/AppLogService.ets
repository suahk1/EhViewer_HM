import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { appSettingsStore } from './AppSettingsStore';

const LOG_FILE_NAME: string = 'ehviewer_app.log';
const MAX_LOG_BYTES: number = 512 * 1024;
const LOG_DOMAIN: number = 0x3200;
const LOG_TAG: string = 'EhViewer';

export class AppLog {
  info(context: common.UIAbilityContext | undefined, tag: string, message: string): void {
    this.write(context, 'INFO', tag, message);
  }

  warn(context: common.UIAbilityContext | undefined, tag: string, message: string): void {
    this.write(context, 'WARN', tag, message);
  }

  error(context: common.UIAbilityContext | undefined, tag: string, message: string): void {
    this.write(context, 'ERROR', tag, message);
  }

  write(context: common.UIAbilityContext | undefined, level: string, tag: string, message: string): void {
    const line = new Date().toISOString() + ' [' + level + '] ' + tag + ': ' + message + '\n';
    // 先无条件落 hilog：以前没开「保存崩溃日志」或拿不到 context 时这里直接 return，
    // 日志一条都不留，出问题只能靠猜。hilog 至少能用 hdc 抓，开关只决定是否额外落盘。
    this.writeHilog(level, tag, message);
    if (context === undefined || appSettingsStore.getValue('save_crash_log', 'Off') !== 'On') {
      return;
    }
    const path = this.logPath(context);
    let fd = -1;
    try {
      this.trimIfNeeded(path);
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      fd = file.fd;
      fs.writeSync(fd, line);
    } catch (error) {
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (error) {
        }
      }
    }
  }

  private writeHilog(level: string, tag: string, message: string): void {
    // 统一用 %{public}s 占位，消息里带 % 也不会被当成格式化符。
    const text: string = '[' + tag + '] ' + message;
    if (level === 'ERROR') {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', text);
    } else if (level === 'WARN') {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', text);
    } else {
      hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', text);
    }
  }

  read(context: common.UIAbilityContext): string {
    try {
      return fs.readTextSync(this.logPath(context));
    } catch (error) {
      return '';
    }
  }

  clear(context: common.UIAbilityContext): void {
    try {
      fs.unlinkSync(this.logPath(context));
    } catch (error) {
    }
  }

  logPath(context: common.UIAbilityContext): string {
    return context.filesDir + '/' + LOG_FILE_NAME;
  }

  size(context: common.UIAbilityContext): number {
    try {
      return fs.statSync(this.logPath(context)).size;
    } catch (error) {
      return 0;
    }
  }

  private trimIfNeeded(path: string): void {
    try {
      const stat = fs.statSync(path);
      if (stat.size <= MAX_LOG_BYTES) {
        return;
      }
      const text = fs.readTextSync(path);
      const keep = text.length > 200000 ? text.substring(text.length - 200000) : text;
      this.writeTextReplacing(path, keep);
    } catch (error) {
    }
  }

  private writeTextReplacing(path: string, text: string): void {
    let fd = -1;
    try {
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fd = file.fd;
      fs.writeSync(fd, text);
    } catch (error) {
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (error) {
        }
      }
    }
  }
}

export const appLog: AppLog = new AppLog();
