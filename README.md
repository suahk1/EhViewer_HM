<h1 align="center">EhViewer HM</h1>

<p align="center">
HarmonyOS NEXT 原生 E-Hentai 客户端 · ArkTS / ArkUI 全重写
<br/>
<img src="https://img.shields.io/badge/HarmonyOS-NEXT-000000?style=flat-square" alt="Platform" />
<img src="https://img.shields.io/badge/API-12%2B-000000?style=flat-square" alt="API" />
<img src="https://img.shields.io/badge/License-GPL--3.0-000000?style=flat-square" alt="License" />
</p>

---

EhViewer HM 是 Android 版 EhViewer 的鸿蒙原生重写版本，不是套壳移植：全部界面与逻辑用 ArkTS / ArkUI 重新实现，一套代码自适应手机、折叠屏、平板与 PC 自由窗口。

<p align="center">
  <img src="docs/images/home.jpg" width="150" alt="主页" />
  <img src="docs/images/detail.jpg" width="150" alt="详情页" />
  <img src="docs/images/downloads.jpg" width="150" alt="下载管理" />
  <img src="docs/images/reader.jpg" width="150" alt="阅读器" />
</p>

## 特色

**复杂网络环境可用**
- 内置 Hosts + 安全 DNS（DoH）+ 域名前置组合，可直连被按 SNI 阻断的线路
- 直连失败自动检测回退；开启 VPN 时自动让位、按域名交由 VPN 分流，互不打架
- 网络诊断面板一键检查主站 / EX / Forums / 更新源连通性

**全功能覆盖**
- 浏览与搜索：主页、订阅、热门、排行、云端收藏、本地收藏、历史；关键词、多标签、上传者、分类、评分、页码区间组合检索；封面搜索与相似图搜索
- 详情与互动：收藏夹、评分、评论、预览图、Torrent、标签订阅 / 屏蔽 / 投票
- 下载：多线程并发、慢节点自动跳过、断点续传、失败重试、批量管理、云端与本地双位置、ZIP 导入导出
- 阅读器：翻页与连续滚动、一屏双页（自适应分配）、方向适配、手势缩放、白边裁切、进度记忆、音量键翻页

**阅读体验**
- 十一项色彩与明暗调节（亮度 / 对比度 / 清晰度 / 锐化 / 高光 / 阴影等）
- Core Vision 图片超分、SDR 转 HDR
- 漫画内文字翻译：内置 OCR 识别 + 网页翻译 / DeepSeek / OpenAI / Gemini / 自定义接口
- 4.4 万+ 标签中文翻译库，支持在线更新

**数据自主**
- 从 Android 版按项迁移：历史、收藏、下载队列、本地图册、标签、过滤规则、搜索记录
- 下载目录直接复制即可恢复，无需重新下载
- JSON 备份 / Wi-Fi 直连传输 / WebDAV、NAS 同步
- 设置一键恢复默认（二次确认，不动 Cookie、下载与历史等个人数据）

**安全与隐私**
- 应用锁与图案保护、隐私模式（禁止截图录屏）
- 界面 / 阅读器 / 翻译全部本地化中文显示

## 安装

从 [Releases](../../releases) 下载 `EhViewer_HM_0.1.0.hap`。

系统未提供 HAP 安装器，可用 [小白调试助手](https://github.com/likuai2010/auto-installer) 或 `hdc install` 安装。

## 构建

1. DevEco Studio 打开工程
2. 参照 `build-profile.json5.example` 配置本地签名
3. `hvigorw assembleHap` 或 IDE 直接构建

## 免责声明

本应用仅为客户端，不提供、不托管任何内容；请在遵守所在地区法律法规与目标网站服务条款的前提下使用。

## License

[GPL-3.0](LICENSE)
