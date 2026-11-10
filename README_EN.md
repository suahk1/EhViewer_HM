<table>
  <tr>
    <td valign="middle">
      <h1>EhViewer HM</h1>
      <p>Native HarmonyOS gallery client · ArkTS / ArkUI</p>
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

English · [简体中文](README.md)

---

EhViewer HM is a HarmonyOS port of the Android EhViewer app, rewritten in ArkTS / ArkUI. One codebase covers phones, foldables, tablets and desktop windows.

Current version: `0.1.0`. This app is a client only and hosts no content. Check the laws of your region and the terms of service of the sites you use.

## Features

**Browse and search**

Home, subscriptions, what's hot, top lists, cloud favorites, local favorites, history, downloads. Combined search by keyword, tags, uploader, category, rating and page range; search bookmarks, search history, cover search, similar-image search.

**Details and interaction**

Favorites with custom folders, rating, system share, torrent magnet, archive and H@H, comments, previews, similar galleries, tag subscription / blocking / voting.

**Reader**

Paged and continuous reading, automatic two-page spread, direction adaptation, double-tap and pinch zoom, margin cropping, reading presets, embedded and standalone fullscreen modes, page prefetch, progress memory.

**Image processing**

Eleven adjustments (exposure, brightness, contrast, highlights, shadows, clarity, sharpening, saturation, vibrance, hue, temperature, grayscale), Core Vision upscaling, SDR to HDR. Processing order: adjustments, upscaling, HDR.

**Translation**

List titles, detail titles, comments and text inside pages. Supports web translation, DeepSeek, OpenAI, Gemini and custom compatible endpoints, with configurable prompts, merged batches and translation logs.

**Downloads**

Priority scheduling, concurrency and speed limits, resume, progress notifications, status and label filters, batch operations, cloud and local destinations, ZIP import and export.

**Data**

Android database import, old download-directory restore, JSON backup, direct device-to-device transfer over Wi-Fi, WebDAV / NAS remote storage with incremental sync.

**Appearance**

Light and dark themes with accent colors, draggable split layout, floating dock navigation, immersive scrolling, custom reader background and brightness.

## Migrating from Android

Data is imported item by item, and the report shows how many records landed in each category.

| Data | Method | Notes |
| :--- | :--- | :--- |
| Browsing history | Android database | Title, page count, category, timestamp |
| Favorites and folders | Android database | Includes custom folders |
| Download queue | Android database | Completed items matched to local folders, not re-downloaded |
| Local galleries | Download folder scan | Offline; registers files already on disk |
| Tags, filters, search history | Android database | Imported as-is |
| Comment blacklist | Android database | Imported as-is |
| Login state | Cookie or web sign-in | See below |

Path: **Settings → Privacy and data → Import data**.

Download folder: copy the Android download directory into the HarmonyOS download directory, then run **Settings → Downloads → Restore download items**. Finished galleries are registered in place. Unencrypted archives, app export packages and external gallery ZIPs under the public Download root are recognized too.

Three things to know before starting:

- Image caches are not migrated; thumbnails and pages are fetched again, except for local galleries.
- Login cookies depend on Cloudflare; if a second verification appears, pass it once in the in-app web sign-in.
- Third-party scripts and modules from the Android build have no counterpart here.

## Installation

Download the latest HAP from [GitHub Releases](https://github.com/suahk1/EhViewer_HM/releases) and install it with [Xiaobai Debug Assistant](https://github.com/likuai2010/auto-installer). No HDC and no cable required.

- Current version: `0.1.0`
- Package: `EhViewer_HM_0.1.0.hap`
- Target API: `26.0.0`
- Compatible API: `6.0.0(20)`

Xiaobai Debug Assistant: keep the phone and the computer on the same LAN, start the assistant on the computer, approve the pairing prompt on the phone, then drag the HAP into the window.

Alternatively use the developer channel:

```bash
hdc install EhViewer_HM_0.1.0.hap
```

Installing over an existing build keeps app data; uninstalling clears sign-in state, downloads and reading progress.

The system ships no HAP installer, so tapping a HAP on the phone does nothing. The in-app update check only reports a newer version and points to the download; it does not install anything.

| Item | Value |
| :--- | :--- |
| Target API | 26.0.0 |
| Minimum API | 20 |
| Install size | about 18 MB |

## Building

Requires DevEco Studio 5.0+ and HarmonyOS SDK 26.0.0.

Signing configuration is not in the repository. Generate it with **File → Project Structure → Signing Configs**, or copy the template and fill it in.

```bash
cp build-profile.json5.example build-profile.json5
hvigorw assembleHap --mode module -p product=default
```

Output: `entry/build/default/outputs/default/`

## Feedback

Open an [issue](https://github.com/suahk1/EhViewer_HM/issues). The in-app entry at **Settings → About → Feedback** fills in version and platform.

Include reproduction steps; for translation or OCR problems, export the debug records as well. Keep cookies, API keys and other credentials out of logs.


## Credits

- [EhViewer](https://github.com/seven332/EhViewer) — seven332
- [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) — xiaojieonly
- [Ehviewer_OHOS](https://github.com/suibianqwe/Ehviewer_OHOS) — suibianqwe
- [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database)

## License

[GPL-3.0](LICENSE), same as upstream. Use, modify and redistribute freely, including commercially; redistributed modified versions must stay under GPL-3.0.
