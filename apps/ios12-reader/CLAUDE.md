# CLAUDE.md — apps/ios12-reader (Rolo)

This subdirectory is a **standalone native iOS app**, codename **Rolo**. It lives inside the Folo monorepo but is otherwise independent. These rules apply only here; do not assume monorepo conventions carry over. Rolo is the article-reading sibling of `apps/ios12-video` (Flo).

## What it is

A minimal native RSS/Atom article reader for **old iPads (iPad Air 1 / A7 / 1GB RAM / iOS 12.5)**. It subscribes to arbitrary RSS/Atom feeds (including `rsshub://` routes and plain http:// local instances) and shows the full article inside a sandboxed `WKWebView`. Brand orange `#FF5C00`.

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
- Verification path: push, then run the **Build Rolo (iOS 12)** GitHub Actions workflow (`macos-14` runner, pinned **Xcode 15.4**, XcodeGen → build → unsigned `.ipa`). Compile errors surface there.
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
├── Models/                    # Subscription, ArticleEntry
├── Services/
│   ├── FeedService.swift      # input resolution (http/https/rsshub://) + fetch
│   ├── FeedParser.swift       # XMLParser-based Atom + RSS 2.0 parser, captures article HTML + first image
│   ├── SubscriptionStore.swift# JSON-in-Documents persistence, per-feed entry cap (~100)
│   └── ImageLoader.swift      # thumbnail / feed-icon loading
└── Scenes/
    ├── UIKitCompat.swift      # iOS 12 compatibility shims (e.g. .insetGroupedCompat)
    ├── SubscriptionsVC.swift  # home list (+ settings gear, add button, unread counts)
    ├── AddSubscriptionVC.swift# add-feed UI (paste any RSS/Atom/rsshub:// URL)
    ├── ArticleListVC.swift    # per-subscription article list with unread filter / mark-all
    ├── ArticleReaderVC.swift  # WKWebView reader with injected styles + font/theme controls
    ├── SettingsVC.swift       # only field: RSSHub instance URL
    └── *Cell.swift            # table cells
```

Persistence: JSON files under `Documents/` + `UserDefaults`. No database.

## Domain notes

- **Three input shapes** are accepted in `FeedService.resolve()`:
  - `https://...` — any RSS/Atom URL, used directly.
  - `http://...` — same, but allowed only because `NSAllowsArbitraryLoads` is on (so self-hosted FreshRSS / local RSSHub on the LAN work).
  - `rsshub://route/...` — expanded against the configured RSSHub instance (`UserDefaults` key `rsshub_base`, default `https://rsshub.app`, may be overridden to `http://192.168.x.x:1200` etc.).
- `FeedParser` is XMLParser-based and supports Atom and RSS 2.0. It captures `content:encoded` > `content` > `description` (in that priority), Atom `<content type="html">`, CDATA, and resolves relative image URLs against the article link.
- Per-subscription entry storage is capped (~100) to bound memory on a 1GB device. The WKWebView in `ArticleReaderVC` is released on dismiss.
- Theme/font choices in the reader are app-local (manually toggled). On iOS 12 there is no system dark mode, so `Theme.background` returns white and the reader page CSS does its own theming.

## Style

- Match the surrounding code: small focused VCs, comments in the existing bilingual style (English doc comments are common; user-facing strings are Simplified Chinese).
- Keep memory/CPU footprint low — this targets a 1GB device. Release the WKWebView on dismiss; avoid retaining large buffers.
