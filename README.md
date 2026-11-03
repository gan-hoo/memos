# Memos for iOS

基于开源项目 [Memos](https://github.com/usememos/memos) 的 iOS 客户端（SwiftUI + WKWebView）。
首次打开输入你自托管的 Memos 服务器地址，即可在 App 中使用完整的 Memos 功能，登录状态会被保存。

## 功能

- 首次启动配置服务器地址（支持 `https://` 与局域网 `http://`）
- 登录 Cookie 持久化，免重复登录
- 下拉刷新、左右滑动前进/后退
- 外部链接自动用 Safari 打开
- 支持图片/文件上传（相机、相册）
- 左下角菜单：首页 / 刷新 / 在 Safari 打开 / 更换服务器

## 获取 IPA

每次推送都会由 GitHub Actions（macOS runner）自动构建 **未签名** 的 `Memos-unsigned.ipa`：

- 仓库的 **Releases → Latest build** 下载；或
- **Actions → Build IPA →** 对应运行的 Artifacts 下载。

未签名 IPA 需要自行签名安装，例如使用 AltStore / SideStore / Sideloadly（Apple ID 免费签名）或 TrollStore。

## 本地构建

```bash
brew install xcodegen
xcodegen generate
open Memos.xcodeproj   # 在 Xcode 中选择你的 Team 后运行到真机
```

## 部署 Memos 服务器

```bash
docker run -d --name memos -p 5230:5230 -v ~/.memos:/var/opt/memos neosmemo/memos:stable
```

## License

本客户端代码以 MIT 协议发布。Memos 本身遵循其仓库中的 MIT 协议。
