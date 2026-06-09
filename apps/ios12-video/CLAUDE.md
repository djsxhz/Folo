# CLAUDE.md — apps/ios12-video (Flo)

This subdirectory is a **standalone native iOS app**, codename **Flo**. It lives inside the Folo monorepo but is otherwise independent. These rules apply only here; do not assume monorepo conventions carry over.

## What it is

A minimal native video-subscription app for **old iPads (iPad Air 1 / A7 / 1GB RAM / iOS 12.5)**. It subscribes to YouTube / Bilibili (and arbitrary RSS) feeds and plays videos via embedded official players. Brand orange `#FF5C00`.

Pure **UIKit + URLSession + XMLParser + WKWebView**. **Zero third-party dependencies.** Keep it that way — no SPM/CocoaPods/Carthage, no new frameworks.

## Hard constraints (read before writing code)

- **Deployment target is iOS 12.0.** Any API introduced in iOS 13+ MUST be guarded with `if #available(iOS 13.0, *)` and given a 12.0 fallback.
  - No SwiftUI (needs iOS 13+). UIKit only, in code — no Storyboards except `LaunchScreen`.
  - Common 13+ traps: `UIColor.systemRed`/`.label`/`.systemBackground` etc., `UITableView.Style.insetGrouped`, `UIImage(systemName:)` (SF Symbols), scene/`UIScene` APIs.
  - Use the existing helpers instead of raw 13+ APIs: colors via `Theme` (`Sources/Theme.swift`), adaptive table styles via `UIKitCompat` (`.insetGroupedCompat`). Add to those helpers rather than scattering `#available` checks.
- **Do not change `project.yml`'s `objectVersion: 56`** — it pins the file format so the CI's Xcode 15.4 can open it. Xcode 16 raises the minimum deployment target and can no longer build for iOS 12.
- XcodeGen generates the Xcode project from `project.yml`. `sources: - path: Sources` collects files **automatically** — new `.swift` files under `Sources/` need no manual registration.

## Building & verifying

- **You cannot build locally on Windows** (no Xcode toolchain). Don't claim a change compiles based on a local build — it didn't happen.
- Verification path: push, then run the **Build Flo (iOS 12)** GitHub Actions workflow (`macos-14` runner, pinned **Xcode 15.4**, XcodeGen → build → unsigned `.ipa`). Compile errors surface there.
- The output is an **unsigned** `.ipa` the user sideloads/re-signs (Sideloadly) onto the iPad. No signing happens in CI.
- Before pushing, statically check iOS 12 compatibility of every touched file — that is the main class of bug this project hits.

## Git

- Repo is a fork: `origin = github.com/djsxhz/Folo.git`, `upstream = github.com/RSSNext/Folo.git`.
- Working branch: **`codex/local-reader-mvp`**. Monorepo main branch is **`dev`** — open PRs against `dev`.
- This machine has no standalone `git` on PATH; pushing goes through GitHub Desktop's bundled git + a Clash proxy. Don't assume `git push` works from a plain shell here.

## Architecture map

```
Sources/
├── AppDelegate.swift          # code-only launch, no SceneDelegate (iOS 12 friendly)
├── Theme.swift                # Folo orange + adaptive (light/dark) colors — use this for colors
├── Models/                    # Subscription (+ Platform enum), VideoEntry
├── Services/
│   ├── FeedService.swift      # input resolution + fetch
│   ├── FeedParser.swift       # XMLParser-based Atom + RSS 2.0 parser
│   ├── SubscriptionStore.swift# JSON-in-Documents + UserDefaults persistence
│   ├── ImageLoader.swift      # thumbnail loading
│   └── BilibiliAuth.swift     # optional Bilibili login state (shared WKWebsiteDataStore cookies)
├── Player/
│   └── VideoPlayerVC.swift    # WKWebView embed player (YouTube / Bilibili / RSS)
└── Scenes/
    ├── UIKitCompat.swift      # iOS 12 compatibility shims (e.g. .insetGroupedCompat)
    ├── SubscriptionsVC.swift  # home list (+ settings gear, add button)
    ├── AddSubscriptionVC.swift# add-feed UI
    ├── VideoListVC.swift      # per-subscription video list
    ├── SettingsVC.swift       # settings (optional Bilibili login entry)
    ├── BilibiliLoginVC.swift  # embedded official Bilibili login page
    └── *Cell.swift            # table cells
```

Persistence: JSON files under `Documents/` + `UserDefaults`. No database.

## Domain notes

- **Bilibili login is optional and exists only to unlock resolution.** Without it Bilibili caps playback at 360P/480P; a valid `SESSDATA` cookie unlocks 720P/1080P (`qn=80` on the player embed). Login is performed via the official page inside a `WKWebView`; we never handle credentials. The login screen, `BilibiliAuth`, and `VideoPlayerVC` all share `WKWebsiteDataStore.default()` so the cookie flows between them and survives relaunch. Other login-gated features (AI, sync, etc.) are intentionally **not** built.
- **YouTube** uses the official feed `youtube.com/feeds/videos.xml?channel_id=UC...` (no API key) and the `youtube-nocookie.com` embed player.
- Embedded players autoplay inline: WebView sets `allowsInlineMediaPlayback = true` and `mediaTypesRequiringUserActionForPlayback = []`. Don't reintroduce a tap-to-play gate.
- All player/RSSHub endpoints are HTTPS but `NSAllowsArbitraryLoads` is on so embeds work.

## Style

- Match the surrounding code: small focused VCs, comments in the existing bilingual style (English doc comments are common; user-facing strings are Simplified Chinese).
- Keep memory/CPU footprint low — this targets a 1GB device. Release the WKWebView on dismiss; avoid retaining large buffers.
