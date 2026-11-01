import { common } from '@kit.AbilityKit';
import { diagnosticTimestamp } from '../shared/AppRuntime';
import { fileIo as fs } from '@kit.CoreFileKit';
import { appSettingsStore } from './AppSettingsStore';
import { appLog } from './AppLogService';
import {
  ensureDirectory,
  isDirectory,
  writeTextFile
} from '../shared/FileUtils';

const PARSE_ERROR_DIR: string = 'parse_error_bodies';
const MAX_PARSE_ERROR_FILES: number = 20;
const MAX_PARSE_ERROR_BYTES: number = 10 * 1024 * 1024;

export interface ParseErrorBodyEntry {
  name: string;
  path: string;
  size: number;
  modifiedTime: number;
}

export class ParseErrorBodyStore {
  save(source: string, url: string, statusCode: number, message: string, body: string): string {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined || appSettingsStore.getValue('save_parse_error_body', 'Off') !== 'On') {
      return '';
    }
    const directory = this.directoryPath(context);
    try {
      ensureDirectory(directory);
      const fileName = diagnosticTimestamp(new Date()) + '_' + sanitizeFileName(source) + '.html';
      const path = directory + '/' + fileName;
      const content = this.bodyFileContent(source, url, statusCode, message, body);
      writeTextFile(path, content);
      this.trim(directory);
      appLog.warn(context, 'ParseErrorBody', 'Saved ' + source + ' parse body: ' + path);
      return path;
    } catch (error) {
      appLog.error(context, 'ParseErrorBody', 'Save failed: ' + String(error));
      return '';
    }
  }

  list(context: common.UIAbilityContext): ParseErrorBodyEntry[] {
    const directory = this.directoryPath(context);
    try {
      const names = fs.listFileSync(directory);
      const entries: ParseErrorBodyEntry[] = [];
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        const path = directory + '/' + name;
        try {
          const stat = fs.statSync(path);
          if (!stat.isDirectory()) {
            entries.push({
              name: name,
              path: path,
              size: stat.size,
              modifiedTime: stat.mtime
            });
          }
        } catch (error) {
        }
      }
      entries.sort((a: ParseErrorBodyEntry, b: ParseErrorBodyEntry) => b.modifiedTime - a.modifiedTime);
      return entries;
    } catch (error) {
      return [];
    }
  }

  clear(context: common.UIAbilityContext): void {
    const entries = this.list(context);
    for (let i = 0; i < entries.length; i++) {
      try {
        fs.unlinkSync(entries[i].path);
      } catch (error) {
      }
    }
  }

  directoryPath(context: common.UIAbilityContext): string {
    return context.filesDir + '/' + PARSE_ERROR_DIR;
  }

  private bodyFileContent(source: string, url: string, statusCode: number, message: string, body: string): string {
    const lines: string[] = [];
    lines.push('<!--');
    lines.push('EhViewer OHOS parse error body');
    lines.push('Time: ' + new Date().toISOString());
    lines.push('Source: ' + source);
    lines.push('URL: ' + url);
    lines.push('Status: ' + statusCode.toString());
    lines.push('Message: ' + message.replace(/-->/g, '-- >'));
    lines.push('Body bytes: ' + body.length.toString());
    lines.push('-->');
    lines.push(body);
    return lines.join('\n');
  }

  private trim(directory: string): void {
    const entries = this.entriesForDirectory(directory);
    let total = 0;
    for (let i = 0; i < entries.length; i++) {
      total += entries[i].size;
    }
    for (let i = entries.length - 1; i >= 0; i--) {
      if (entries.length <= MAX_PARSE_ERROR_FILES && total <= MAX_PARSE_ERROR_BYTES) {
        return;
      }
      try {
        fs.unlinkSync(entries[i].path);
        total -= entries[i].size;
        entries.splice(i, 1);
      } catch (error) {
      }
    }
  }

  private entriesForDirectory(directory: string): ParseErrorBodyEntry[] {
    try {
      const names = fs.listFileSync(directory);
      const entries: ParseErrorBodyEntry[] = [];
      for (let i = 0; i < names.length; i++) {
        const path = directory + '/' + names[i];
        try {
          const stat = fs.statSync(path);
          if (!stat.isDirectory()) {
            entries.push({ name: names[i], path: path, size: stat.size, modifiedTime: stat.mtime });
          }
        } catch (error) {
        }
      }
      entries.sort((a: ParseErrorBodyEntry, b: ParseErrorBodyEntry) => b.modifiedTime - a.modifiedTime);
      return entries;
    } catch (error) {
      return [];
    }
  }
}

function sanitizeFileName(value: string): string {
  const normalized = value.trim().length > 0 ? value.trim() : 'parse';
  return normalized.replace(/[\\/:*?"<>|\s]+/g, '_').replace(/^_+|_+$/g, '').substring(0, 48);
}

export const parseErrorBodyStore: ParseErrorBodyStore = new ParseErrorBodyStore();
