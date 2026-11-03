# Meow for iOS（离线版）

把开源笔记应用 [XuYouo/Meow](https://github.com/XuYouo/Meow) 打包成 iOS App（IPA）。**不需要服务器**，笔记保存在手机本地。

## 工作原理

```
┌──────────── iOS App ────────────┐
│ SwiftUI + WKWebView              │
│   └─ meow://app/  ◀── App 包内的 web/（Meow 前端 vite build 产物）
│        localStorage / IndexedDB 保存笔记（App 沙盒内，持久化）
└──────────────────────────────────┘
```

- Meow 本身是 React/Vite 网页应用，默认把数据存在浏览器本地存储。构建时把它的 `build/` 产物放进 App 包，由 `WKURLSchemeHandler` 以 `meow://app` 提供，得到固定的来源（origin），数据跨启动保留。
- 没有后端：`/api/*` 一律返回 404，前端会自动进入"本地模式"（无需登录密码）。
- 设置里的 D1 / Supabase 云同步、AI 对话、S3 等需要联网的功能照常可用（连接你自己配置的服务）。
- 导出数据、分享图片等下载会弹出 iOS 分享面板，可存到"文件"或发送到其他 App。
- 支持麦克风录制语音片段、相册/相机选图、后台继续播放音乐。

> 数据只在这台设备的 App 里。**删除 App 会清空笔记**，请定期在设置中"导出数据"备份，或启用云同步。

## 获取 IPA

推送 `meow/**` 的改动时，GitHub Actions（macOS runner）会自动构建 **未签名** IPA：

- 仓库 **Releases → `meow-latest`** 下载；或
- **Actions → Build Meow IPA →** 对应运行的 Artifacts 下载。

想换嵌入的 Meow 版本：Actions → Build Meow IPA → Run workflow，填写 `meow_ref`（分支 / tag / commit，默认 `main`）。

未签名 IPA 需自行签名安装，例如 AltStore / SideStore / Sideloadly（免费 Apple ID 即可）或 TrollStore。

## 本地构建（macOS）

```bash
cd meow
git clone --depth 1 https://github.com/XuYouo/Meow upstream
(cd upstream && npm install --ignore-scripts --include=dev && NODE_ENV=production npx vite build)
rm -rf web && cp -R upstream/build web
brew install xcodegen && xcodegen generate && open Meow.xcodeproj
```

## 目录

- `MeowApp/` — iOS App（SwiftUI + WKWebView）
  - `AppSchemeHandler.swift` — 以 `meow://app` 提供包内网页资源
  - `BrowserView.swift` — WebView、外链跳 Safari、下载→分享面板、麦克风授权、JS 弹窗
- `project.yml` — XcodeGen 工程描述
- `../.github/workflows/build-meow-ipa.yml` — 构建流程

## License

本目录代码 MIT。Meow 本身遵循其仓库中的 MIT 协议。
