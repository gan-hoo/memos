# Memos for iOS（本地版）

把开源项目 [Memos](https://github.com/usememos/memos) **整个服务端直接打包进 iOS App**，在手机本地运行，**不需要任何服务器**。

## 工作原理

```
┌──────────────── iOS App ────────────────┐
│  SwiftUI + WKWebView  ── http://127.0.0.1 ──▶  Memos 服务端 (Go, gomobile 编译)
│        ▲                                   │      └─ SQLite: Documents/memos_prod.db
│        └── 自动创建本地账户并自动登录        │
└─────────────────────────────────────────┘
```

- 上游 Memos 的 Go 服务端 + Web 前端通过 `gomobile` 编译成 `Memosmobile.xcframework`，App 启动时在 `127.0.0.1` 上运行（只监听本机，不对外暴露）。
- 首次启动自动创建本地账户（用户名 `me`，随机密码）并自动登录，打开即用。
- 数据全部保存在手机上：`文件` App → 我的 iPhone → Memos → `memos_prod.db`，可直接拷贝备份。
- App 从后台恢复时如果 iOS 回收了本地服务，会自动重启并刷新。

## 功能

- 完整的 Memos 功能（与上游 Web 版一致）
- 下拉刷新、左右滑动前进/后退，外部链接用 Safari 打开
- 图片/文件附件（相机、相册）
- 左下角菜单：首页 / 刷新 / 重新自动登录 / 查看本地账户 / 关于与数据

## 获取 IPA

每次推送都会由 GitHub Actions（macOS runner）自动构建 **未签名** 的 `Memos-unsigned.ipa`：

- 仓库 **Releases → latest** 下载（每次构建都会重建，文件名带版本号和提交号）；或
- **Actions → Build IPA →** 对应运行的 Artifacts 下载。

未签名 IPA 需自行签名安装，例如 AltStore / SideStore / Sideloadly（免费 Apple ID 即可）或 TrollStore。

想换嵌入的 Memos 版本：Actions → Build IPA → Run workflow，填写 `memos_version`（如 `v0.31.0`）。

## 本地构建（macOS）

```bash
git clone --depth 1 --branch v0.31.0 https://github.com/usememos/memos upstream
(cd upstream/web && pnpm install && pnpm release)          # 需要 Node 24+
cp -R mobile upstream/ && cd upstream
go get golang.org/x/mobile/bind@latest
go install golang.org/x/mobile/cmd/gomobile@latest golang.org/x/mobile/cmd/gobind@latest
gomobile init
gomobile bind -target ios -iosversion 15.0 -o ../Frameworks/Memosmobile.xcframework ./mobile/memosmobile
cd .. && brew install xcodegen && xcodegen generate && open Memos.xcodeproj
```

## 目录

- `MemosApp/` — iOS App（SwiftUI）
- `mobile/memosmobile/` — Go 桥接层，构建时复制进上游 Memos 源码树后用 gomobile 编译
- `project.yml` — XcodeGen 工程描述
- `.github/workflows/build-ipa.yml` — 构建流程

## License

MIT。Memos 本身遵循其仓库中的 MIT 协议。
