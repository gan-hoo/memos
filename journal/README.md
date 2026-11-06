# 片刻 · 日记（iOS）

一个原生 SwiftUI 日记 App，功能参照 iOS 自带的日记类应用设计，数据只保存在本机。

## 功能

- **卡片式时间线**：按月份分组，照片拼图、录音、地图、标题和正文一目了然
- **写日记**：标题 + 正文，可改日期；附加照片（相册 / 拍照）、语音录音（带波形）、当前地点（带地图）
- **写作提示**：点「＋」可直接新建，或从 30 个反思类问题中挑一个开始
- **收藏、筛选**（全部 / 已收藏 / 照片 / 录音 / 地点）和全文搜索
- **回顾**：当前 / 最长连续记录天数、今年篇数与字数、照片和地点统计、日历视图（点日期查看当天日记）
- **锁定**：面容 ID / 触控 ID / 密码解锁，切到后台自动锁定，多任务界面隐藏内容
- **每日提醒**：自定义时间，通知里附带当天的写作提示
- 导出全部日记为 Markdown；数据在「文件」App → 我的 iPhone → 片刻

需要 iOS 17 或更高版本。

## 获取 IPA

推送 `journal/` 下的改动后，GitHub Actions 会自动构建未签名 IPA，发布在 Releases → `journal-latest`。用 AltStore / SideStore / Sideloadly / TrollStore 安装。

## 用 Xcode 开发

```bash
cd journal
brew install xcodegen
xcodegen generate
open Pianke.xcodeproj
```
