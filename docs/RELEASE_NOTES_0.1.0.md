# v0.1.0

第一版。

## 功能

- 浏览与搜索：主页、订阅、热门、排行、云端收藏、本地收藏、历史、下载；关键词、多标签、上传者、分类、评分、页码区间组合检索；封面搜索与相似图搜索。
- 详情与互动：收藏与自定义收藏夹、评分、分享、Torrent、存档与 H@H、评论、预览图、标签订阅 / 屏蔽 / 投票。
- 阅读器：翻页与连续阅读、一屏双页、方向适配、双击与手势缩放、白边裁切、阅读预设、覆盖式与全屏两种形态、页面预加载、进度记忆。
- 图像处理：十一项色彩与明暗调节、Core Vision 超分、SDR 转 HDR。
- 翻译：列表标题、详情标题、评论、漫画内文字；网页翻译、DeepSeek、OpenAI、Gemini 与自定义接口。
- 下载：优先级调度、并发与速度控制、断点续传、批量操作、云端与本地双位置、ZIP 导入导出。
- 数据：安卓数据库导入、旧下载目录恢复、JSON 备份、Wi-Fi 直连传输、WebDAV / NAS 同步。
- 外观：明暗主题与主题色、可拖动分栏、浮岛导航、沉浸滚动、自定义阅读背景。

## 从 Android 版迁移

历史、收藏与收藏夹、下载队列、本地图册、标签、过滤规则、搜索记录、评论黑名单按项导入，结束后给出每项条数。下载目录可直接复制后运行「恢复下载项」，已完成图册原地登记，不重新下载。

入口：设置 → 隐私与数据 → Import data。

限制：图片缓存不迁移；登录 Cookie 遇到 Cloudflare 二次验证需在应用内网页登录一次；安卓版第三方脚本与模块没有对应实现。

## 安装

下载 `EhViewer_HM_0.1.0.hap`，用调试助手或 `hdc install` 安装。

- 目标 API 26.0.0，最低 API 20
- 安装体积约 16 MB

## 应用内更新与反馈

设置 → 关于 → 检查更新，或启动时自动检查（可在同一页关闭）。反馈入口自动填入版本与平台，直接打开新建 Issue。

## 致谢

- [EhViewer](https://github.com/seven332/EhViewer) — seven332
- [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) — xiaojieonly
- [Ehviewer_OHOS](https://github.com/suibianqwe/Ehviewer_OHOS) — suibianqwe
- [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database)

## 许可

GPL-3.0，与上游一致。
