# iOS 12 Reader 实施计划

仓库里已有 `apps/ios12-video`（Flo）——一个纯 Swift UIKit、零第三方依赖、部署目标 iOS 12.0 的视频订阅 app，架构和需求几乎完全吻合。以它为蓝本，新建一个并列的文章阅读专版 `apps/ios12-reader`，把视频、播放器、B 站登录全部去掉，换成文章列表 + 文章阅读页。

下面是完整计划。

## 总体方案

- 新建 `apps/ios12-reader/`，作为独立 app，不动现有的 `ios12-video`。代号 `Rolo`，bundle id 为 `app.flo.reader`（沿用 `app.flo` 前缀，与视频版 `app.flo.video` 并列），可与视频版共存安装。
- 技术栈与约束完全沿用现有专版：UIKit 纯代码 + URLSession + XMLParser + WKWebView，零第三方依赖，部署目标 iOS 12.0（覆盖 iPad Air 1 等机型的最终系统 iOS 12.5.7），XcodeGen `objectVersion: 56` + CI 用 Xcode 15.4 构建未签名 ipa，Sideloadly 侧载。
  - 注意 `objectVersion: 56` 只是写在 `project.yml` 里还不够：CI runner 上的 XcodeGen 总会生成 `objectVersion 77`，必须在工作流里用 `sed` 把它改回 56，Xcode 15.4 才能打开工程（见步骤 5）。
- 功能严格收敛：只有「订阅管理 + 文章列表 + 阅读页」，外加一个仅含 RSSHub 实例地址的极简设置页（这是支持 `rsshub://` 必需的）。

## 订阅源支持（核心需求）

复用并简化 `FeedService.resolve()`，支持：

| 输入形式 | 处理方式 |
| --- | --- |
| `https://...` 任意 RSS/Atom 地址 | 直接订阅 |
| `http://...`（本地/局域网，如自建 FreshRSS、本地 RSSHub） | 直接订阅；`Info.plist` 已有 `NSAllowsArbitraryLoads: true` 的先例，沿用即可放行明文 HTTP |
| `rsshub://route/...` | 按设置中的 RSSHub 实例地址展开（默认 `https://rsshub.app`，可改成本地 http 实例，如 `http://192.168.1.x:1200`） |

去掉 YouTube 频道 ID / Bilibili UID 这些视频专属的特判，`Platform` 枚举整个删掉。

## 文件规划

```text
apps/ios12-reader/
├── project.yml                 # 仿 ios12-video：name 改为 Rolo、bundle id 改 app.flo.reader，保持 objectVersion 56
├── CLAUDE.md                   # 沿用 ios12-video 的硬约束说明
├── Resources/                  # Info.plist、LaunchScreen、图标（复用 Folo 素材）
└── Sources/
    ├── AppDelegate.swift       # 无 SceneDelegate，iOS 12 方式
    ├── Theme.swift / Scenes/UIKitCompat.swift   # 直接复制（颜色与 iOS 12 兼容 shim）
    ├── Models/
    │   ├── Subscription.swift  # id/title/feedURL/iconURL，无 platform
    │   └── ArticleEntry.swift  # title/link/author/published/summary/contentHTML/read
    ├── Services/
    │   ├── FeedService.swift   # 简化版输入解析（rsshub:// 展开 + http/https 直连）+ 抓取
    │   ├── FeedParser.swift    # 在现有 RSS2.0/Atom 解析器上扩展文章字段（均为新增逻辑）：
    │   │                       #   按 content:encoded > content > description 优先级取正文
    │   │                       #     —— 现状是「按文档顺序取第一个非空」，不分优先级，需改写
    │   │                       #   Atom <content type="html"> 正文 —— 现状被当成缩略图元素忽略，需单独捕获
    │   │                       #   相对 URL 补全 —— 现状 normalizedHTTPURL 直接丢弃相对路径，
    │   │                       #     需把文章 link 作为 base 传入；CDATA、首图缩略图已支持
    │   ├── SubscriptionStore.swift  # JSON-in-Documents，每源保留最近 ~100 条防爆内存
    │   │                            #   注意：现状 mergeEntries 无限保留旧条目，条数上限是新增；
    │   │                            #   且 VideoEntry→ArticleEntry 后，存储类型与 persist/load 需整体改写
    │   └── ImageLoader.swift   # 复制（列表缩略图/源图标）
    └── Scenes/
        ├── SubscriptionsVC.swift    # 首页：订阅列表（+未读数）、添加、删除、设置入口
        ├── AddSubscriptionVC.swift  # 粘贴任意地址 → 探测标题/图标 → 确认订阅
        ├── ArticleListVC.swift      # 单源文章列表：标题/摘要/缩略图/时间，下拉刷新、
        │                            # 未读筛选、全部已读；进入阅读自动标已读
        ├── ArticleReaderVC.swift    # WKWebView 加载本地拼装的 HTML 模板：
        │                            #   注入正文 + 阅读样式 CSS（可调字号；明暗用 App 内手动
        │                            #     切换，不能跟随系统——iOS 12 无系统深色模式，Theme 在
        │                            #     12 上一律回退浅色）、去 script、图片宽度自适应；
        │                            #   工具栏提供“打开原文”
        └── SettingsVC.swift         # 仅 RSSHub 实例地址一项
```

## 实施步骤

1. 脚手架：建目录，复制改写 `project.yml`、`Info.plist`、`LaunchScreen`、`Assets`、`AppDelegate`、`Theme`、`UIKitCompat`。
2. 数据层：写 `Subscription` / `ArticleEntry` 模型 + `SubscriptionStore`（JSON 持久化、条目上限）。
3. 抓取解析：简化 `FeedService`（三类输入），扩展 `FeedParser` 抽全文 HTML 与首图。
4. 界面：四个 VC + cell，逐个实现（订阅页 → 添加页 → 列表页 → 阅读页 → 设置页）。
5. CI：复制 `.github/workflows/build-ios12.yml` 为 `build-ios12-reader.yml`，产出独立的未签名 ipa。复制后必须改写以下所有 `Flo` 相关项，否则工作流必挂：
   - `name:` → `Build Rolo (iOS 12)`
   - `paths:` 触发器 `apps/ios12-video/**` → `apps/ios12-reader/**`，以及工作流自身路径
   - `working-directory: apps/ios12-video` → `apps/ios12-reader`
   - `-project Flo.xcodeproj` / `-scheme Flo` → `Rolo.xcodeproj` / `Rolo`
   - `sed ... Flo.xcodeproj/project.pbxproj` 中的 `Flo.xcodeproj` → `Rolo.xcodeproj`（这步 objectVersion 77→56 的兜底必须保留）
   - 打包段 `Flo.xcarchive` / `Flo.app` / `Flo.ipa` 与 artifact 名 `Flo-unsigned-ipa` → 对应 `Rolo`
   - 上传路径 `apps/ios12-video/build/Flo.ipa` → `apps/ios12-reader/build/Rolo.ipa`
6. 验证：本机（Windows）无法编译 Swift，按既有流程推送后跑 GitHub Actions 验证编译。每个改动文件推送前人工静态检查 iOS 13+ API（`#available` 守卫、不用 SF Symbols / `.systemBackground` / `.insetGrouped` 等）。

## 关键风险点

- 正文渲染的内存：目标设备是 1GB 内存的老 iPad，阅读页 WKWebView 用完即释放；正文 HTML 不做全文缓存索引，只存原始字符串并设条目上限。
- 明文 HTTP：`NSAllowsArbitraryLoads` 解决 URLSession 抓取和 WKWebView 内图片混载，视频版已验证可行。
- `rsshub://` + 本地实例：展开逻辑现成，只需保证设置页允许填 `http://` 地址。

## 确认

新建独立 `apps/ios12-reader`，而非改造现有视频版
