<table>
  <tr>
    <td valign="middle">
      <h1>EhViewer HM</h1>
      <p>HarmonyOS 原生画廊客户端 · ArkTS / ArkUI</p>
      <p>
        <img src="https://img.shields.io/badge/API-20%2B-000000?style=flat-square" alt="API" />
        <img src="https://img.shields.io/badge/HarmonyOS-26.0.0-000000?style=flat-square" alt="Platform" />
        <img src="https://img.shields.io/badge/License-GPL--3.0-000000?style=flat-square" alt="License" />
      </p>
    </td>
    <td align="right" valign="middle" width="150">
      <img src="AppScope/resources/base/media/app_icon.png" width="120" alt="EhViewer HM" />
    </td>
  </tr>
</table>

---

EhViewer HM 是 Android 版 EhViewer 的鸿蒙移植版本，用 ArkTS / ArkUI 重写，一套代码适配手机、折叠屏、平板与电脑窗口。

当前版本：`0.1.0`。本应用仅为客户端，不提供、不托管任何内容；使用前请确认所在地区的法律法规与目标网站的服务条款。

## 功能

**浏览与搜索**

主页、订阅、热门、排行、云端收藏、本地收藏、历史、下载列表。关键词、多标签、上传者、分类、评分、页码区间组合检索；搜索书签、搜索历史、封面搜索、相似图搜索。

**详情与互动**

收藏与自定义收藏夹、评分、系统分享、Torrent 磁力、存档与 H@H、评论查看与发布、预览图、相似画廊、标签订阅 / 屏蔽 / 投票。

**阅读器**

左右翻页与连续阅读、一屏双页自适应、方向适配、双击与手势缩放、白边裁切、阅读预设、内嵌覆盖与独立全屏两种形态、页面预加载、进度记忆。

**图像处理**

曝光、亮度、对比度、高光、阴影、清晰度、锐化、饱和度、自然饱和度、色相、色温、灰度共十一项；Core Vision 超分；SDR 转 HDR。处理顺序为图像调节 → 超分 → HDR。

**翻译**

列表标题、详情标题、评论、漫画内文字。支持网页翻译、DeepSeek、OpenAI、Gemini 与自定义兼容接口，可配置提示词、合并批量请求、记录译文。

**下载**

优先级调度、并发与速度控制、断点续传、进度通知、状态与标签筛选、批量操作、云端与本地双位置、ZIP 导入导出。

**数据**

安卓数据库导入、旧下载目录恢复、JSON 备份、Wi-Fi 直连设备间传输、WebDAV / NAS 远程存储与增量同步。

**外观**

明暗主题与主题色、可拖动分栏、浮岛导航、沉浸滚动、自定义阅读背景与亮度。

## 从 Android 版迁移

按项导入，结束后给出每项条数。

| 数据 | 方式 | 说明 |
| :--- | :--- | :--- |
| 浏览历史 | 安卓数据库 | 标题、页数、分类、时间 |
| 收藏与收藏夹 | 安卓数据库 | 含自定义收藏夹 |
| 下载队列 | 安卓数据库 | 已完成项按标题匹配本机目录，不重新下载 |
| 本地图册 | 扫描下载目录 | 离线登记磁盘上已有文件 |
| 标签、过滤规则、搜索记录 | 安卓数据库 | 原样导入 |
| 评论黑名单 | 安卓数据库 | 原样导入 |
| 登录状态 | Cookie 或网页登录 | 见下 |

入口：**设置 → 隐私与数据 → Import data**。

下载目录：把安卓端下载目录复制到鸿蒙设备的下载目录，运行 **设置 → 下载 → 恢复下载项**，已完成的图册原地登记。公共 Download 根目录下的未加密存档、应用导出包、外来画廊 ZIP 也可识别。

开始前需要知道的三点：

- 图片缓存不迁移，缩略图与原图会重新获取（本地图册除外）。
- 登录 Cookie 受 Cloudflare 影响，遇到二次验证时需在应用内网页登录一次。
- 安卓版的第三方脚本与模块没有对应实现。

## 安装

请在 [GitHub Releases](https://github.com/suahk1/EhViewer_HM/releases) 下载最新的 HAP，使用 [小白调试助手](https://github.com/likuai2010/auto-installer) 安装，无需 HDC 与数据线。

- 当前版本：`0.1.0`
- 安装包：`EhViewer_HM_0.1.0.hap`
- 目标 API：`26.0.0`
- 兼容 API：`6.0.0(20)`

小白调试助手：手机与电脑连接同一局域网，在电脑上启动助手，手机端确认配对，把 HAP 拖入窗口即开始安装。

也可以走开发者通道：

```bash
hdc install EhViewer_HM_0.1.0.hap
```

覆盖安装保留应用数据；卸载重装会清空登录状态、下载记录与阅读进度。

系统未提供 HAP 安装器，直接在手机上点击 HAP 无法安装；应用内「检查更新」只提示新版本并给出下载入口，不提供自动安装。

| 项 | 要求 |
| :--- | :--- |
| 目标 API | 26.0.0 |
| 最低 API | 20 |
| 安装体积 | 约 18 MB |

## 构建

需要 DevEco Studio 5.0 以上与 HarmonyOS SDK 26.0.0。

签名配置不进仓库，用 DevEco 的 **File → Project Structure → Signing Configs** 生成，或复制模板后填写。

```bash
cp build-profile.json5.example build-profile.json5
hvigorw assembleHap --mode module -p product=default
```

产物：`entry/build/default/outputs/default/`

## 反馈

提交 [Issue](https://github.com/suahk1/EhViewer_HM/issues)。应用内 **设置 → 关于 → 反馈** 会自动填入版本与平台。

请附复现步骤；翻译与 OCR 问题建议同时导出调试记录。日志中不要包含 Cookie、API Key 等凭据。


## 致谢

- [EhViewer](https://github.com/seven332/EhViewer) — seven332
- [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) — xiaojieonly
- [Ehviewer_OHOS](https://github.com/suibianqwe/Ehviewer_OHOS) — suibianqwe
- [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database)

## 许可

[GPL-3.0](LICENSE)，与上游一致。可自由使用、修改与分发（含商业用途）；分发修改后的版本需同样以 GPL-3.0 开源。
