import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ensureDownloadNotificationEnabled } from './DownloadNotificationSupport';
import { appLog } from './AppLogService';

const KEEPALIVE_NOTIFICATION_ID: number = 20261030;

// 长任务期间保活：导入、扫描、下载这类批处理都靠它，避免切后台被系统冻结。
// 用引用计数，多个任务同时申请只保留一个长时任务；若下载已经申请过，这里只计数不重复申请。
class AppKeepAlive {
  private holders: number = 0;
  private running: boolean = false;
  private ownsTask: boolean = false;
  private context: common.UIAbilityContext | null = null;

  async acquire(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.holders++;
    if (this.running) {
      return;
    }
    try {
      const tasks: backgroundTaskManager.ContinuousTaskInfo[] =
        await backgroundTaskManager.getAllContinuousTasks(context);
      for (let i = 0; i < tasks.length; i++) {
        if (tasks[i].abilityName === 'EntryAbility' &&
          tasks[i].backgroundModes.indexOf('dataTransfer') >= 0) {
          // 下载队列已经在跑长时任务，复用它。
          this.running = true;
          this.ownsTask = false;
          console.info('[IFSM][KeepAlive] reuse existing continuous task');
          return;
        }
      }
    } catch (error) {
      appLog.warn(context, 'KeepAlive', 'Query continuous tasks failed: ' + String(error));
    }
    try {
      // 通知只是让用户看到「正在运行」，拿不到也照样申请长时任务，后台保活不能被通知权限卡死。
      await ensureDownloadNotificationEnabled(context).catch(() => false);
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            // bundleName 必须取当前应用的实际包名：写死旧包名（yt.ehviewer.huawei）
            // 会让 wantAgent 指向不存在的应用，长时任务申请直接失败（Invalid wantAgent
            // object），后台保活整个失效。
            bundleName: context.abilityInfo !== undefined ? context.abilityInfo.bundleName : '',
            moduleName: 'entry',
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: KEEPALIVE_NOTIFICATION_ID,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(agentInfo);
      await backgroundTaskManager.startBackgroundRunning(context, ['dataTransfer'], agent);
      this.running = true;
      this.ownsTask = true;
      console.info('[IFSM][KeepAlive] continuous task started');
      appLog.info(context, 'KeepAlive', 'Continuous task started for batch job');
    } catch (error) {
      this.running = false;
      this.ownsTask = false;
      appLog.error(context, 'KeepAlive', 'Continuous task start failed: ' + String(error));
    }
  }

  async release(): Promise<void> {
    this.holders = Math.max(0, this.holders - 1);
    if (this.holders > 0) {
      return;
    }
    const owned = this.ownsTask;
    const context = this.context;
    this.running = false;
    this.ownsTask = false;
    if (!owned || context === null) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
    } catch (error) {
      appLog.warn(context, 'KeepAlive', 'Stop continuous task failed: ' + String(error));
    }
  }
}

export const appKeepAlive: AppKeepAlive = new AppKeepAlive();
