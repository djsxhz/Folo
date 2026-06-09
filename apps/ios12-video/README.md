# Flo (iOS 12 视频订阅版)

一个为 **iPad Air 1（A7 / 1GB 内存 / iOS 12.5）** 打造的极简原生视频订阅 App。
只做一件事：订阅 YouTube / Bilibili 频道并播放视频。沿用 Folo 品牌橙 `#FF5C00` 与原图标。

零第三方依赖（纯 UIKit + URLSession + XMLParser + WKWebView），为低内存设备优化。

---

## 功能

- 订阅 YouTube 频道、Bilibili UP 主
- 每个订阅下浏览最新视频（缩略图 + 标题 + 日期）
- 点击视频用内嵌官方播放器播放（YouTube / Bilibili）
- 下拉刷新
- 「仅未读」筛选
- 「全部标为已读」
- 进入播放即自动标记已读，订阅列表显示未读数
- 可选登录 Bilibili（仅用于解锁 720P/1080P 高清晰度）

> 已按需求去掉：AI、收藏、推送、阅读历史等。
> Bilibili 登录是可选的：未登录可正常播放，但清晰度被 B 站限制在 360P/480P；
> 登录后（设置 → Bilibili 登录，扫码或短信）才能播放 720P/1080P。登录态仅保存在本机。

---

## 技术约束（为什么是原生而不是原 RN App）

原 Folo 移动端基于 Expo SDK 54 / React Native 0.81 / React 19，要求 **iOS 15.1+**，
无法运行在 iPad Air 1（系统上限 iOS 12.5.7）。因此本目录是一个**全新的原生工程**，
与 monorepo 其它部分独立，不参与 pnpm / Turbo 构建。

- UI：UIKit（纯代码，无 Storyboard except LaunchScreen）— SwiftUI 需 iOS 13+
- 最低系统：iOS 12.0
- 抓取：`URLSession`
- 解析：`XMLParser`（系统自带，支持 YouTube Atom 与 RSSHub RSS）
- 播放：`WKWebView` 内嵌官方播放器（RSS 不提供视频流），关闭页面即释放
- 存储：Documents 下的 JSON 文件 + `UserDefaults`

---

## 订阅源格式

### YouTube
- 频道链接：`https://www.youtube.com/channel/UCxxxxxxxx`
- 或直接频道 ID：`UCxxxxxxxx`

> `@handle` / `/c/` / `/user/` 形式无法离线推导出 channel_id，请使用 `/channel/UC...` 链接或频道 ID。
> 频道页「关于」或源代码中可找到 `UC` 开头的频道 ID。

YouTube 使用官方订阅源 `youtube.com/feeds/videos.xml?channel_id=UC...`，无需 API key。

### Bilibili
- UP 主空间链接：`https://space.bilibili.com/<UID>`
- 或直接 UID（纯数字）

Bilibili 通过 **RSSHub** 获取（`/bilibili/user/video/<UID>`）。默认实例为 `https://rsshub.app`。
如该实例不可用，可在 `UserDefaults` 中设置 `rsshub_base` 指向自建实例（后续可加设置入口）。

---

## 构建（GitHub Actions 云打包）

你无需本地 Mac。推送改动后，CI 会自动产出**未签名 .ipa**。

1. 把本仓库推到 GitHub。
2. 任意改动 `apps/ios12-video/**` 并推送，或在 Actions 页面手动触发
   **Build Flo (iOS 12)** 工作流（`workflow_dispatch`）。
3. 工作流使用 `macos-14` runner，锁定 **Xcode 15.4**（Xcode 16 已抬高最低部署目标，
   无法再编到 iOS 12），用 XcodeGen 生成工程后编译并打包。
4. 运行结束后，在该次 run 的 **Artifacts** 区下载 `Flo-unsigned-ipa`（内含 `Flo.ipa`）。

---

## 安装到未越狱的 iPad（Windows 即可）

未签名的 `.ipa` 需要用你的 Apple ID 重新签名后才能装。推荐 **Sideloadly**（有 Windows 版）：

1. 在 Windows 上安装 [Sideloadly](https://sideloadly.io/) 和 iTunes（提供驱动）。
2. 用数据线连接 iPad，信任电脑。
3. 打开 Sideloadly，把 `Flo.ipa` 拖进去。
4. 填入你的 **Apple ID**（建议用小号），点击 **Start**，按提示输入密码 / 双重验证码。
5. 安装完成后，在 iPad 上：**设置 → 通用 → VPN与设备管理 → 信任你的开发者证书**。
6. 回到主屏幕打开 **Flo**。

### 关于 7 天过期
免费 Apple ID 签名的 App **7 天后过期**，需要重新用 Sideloadly 安装一次（数据保留在设备上）。
若有付费开发者账号则为 1 年。

---

## 目录结构

```
apps/ios12-video/
├── project.yml                  # XcodeGen 工程定义（部署目标 iOS 12）
├── Sources/
│   ├── AppDelegate.swift        # 纯代码启动（无 SceneDelegate，iOS 12 友好）
│   ├── Theme.swift              # Folo 橙 + 适配明暗的颜色
│   ├── Models/                  # Subscription / VideoEntry
│   ├── Services/                # 存储、抓取、解析、缩略图加载
│   ├── Player/                  # WKWebView 播放器
│   └── Scenes/                  # 订阅列表 / 添加订阅 / 视频列表 + cells
└── Resources/
    ├── Info.plist
    ├── LaunchScreen.storyboard
    └── Assets.xcassets/         # 复用 Folo 图标
```
