import Foundation

/// Fetches and resolves subscription feeds. Pure `URLSession`, no dependencies.
enum FeedService {
    /// The default RSSHub instance used to build Bilibili feeds.
    /// Can be overridden by the user in settings (stored in `UserDefaults`).
    static var rsshubBase: String {
        get {
            let v = UserDefaults.standard.string(forKey: "rsshub_base")
            return (v?.isEmpty == false ? v! : "https://rsshub.app")
        }
        set { UserDefaults.standard.set(newValue, forKey: "rsshub_base") }
    }

    enum FeedError: Error, LocalizedError {
        case invalidInput
        case network(String)
        case parse

        var errorDescription: String? {
            switch self {
            case .invalidInput: return "无法识别该链接,请粘贴 RSS / Atom 源地址、rsshub:// 路由,或 YouTube 频道 / Bilibili UP 主链接"
            case .network(let msg): return "网络错误:\(msg)"
            case .parse: return "订阅源解析失败"
            }
        }
    }

    /// Resolved feed descriptor derived from user input.
    struct Resolved {
        let platform: Platform
        let feedURL: String
    }

    // MARK: - Input resolution

    /// Resolve arbitrary user input (a pasted URL or raw id) into a feed URL.
    ///
    /// Supported, in priority order:
    /// 1. `rsshub://route/...` — expanded against the configured RSSHub instance.
    /// 2. A direct feed URL (YouTube `feeds/videos.xml`, any other http(s) RSS/Atom).
    /// 3. A YouTube channel URL / `UC...` channel id.
    /// 4. A Bilibili space URL / raw numeric UID.
    static func resolve(input raw: String) -> Resolved? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // --- rsshub:// protocol ---
        // e.g. rsshub://youtube/user/@handle  ->  <rsshubBase>/youtube/user/@handle
        if let r = input.range(of: "rsshub://", options: [.caseInsensitive, .anchored]) {
            let route = String(input[r.upperBound...])
            guard !route.isEmpty else { return nil }
            let base = rsshubBase.hasSuffix("/") ? String(rsshubBase.dropLast()) : rsshubBase
            let path = route.hasPrefix("/") ? route : "/" + route
            let platform = inferPlatform(fromRoute: route)
            return Resolved(platform: platform, feedURL: base + path)
        }

        // --- YouTube channel id form: UCxxxxxxxx ---
        if input.hasPrefix("UC"), input.count >= 20, !input.contains(" "), !input.contains("/") {
            return Resolved(
                platform: .youtube,
                feedURL: "https://www.youtube.com/feeds/videos.xml?channel_id=\(input)"
            )
        }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let host = url.host?.lowercased() ?? ""

            // A YouTube channel page: try to derive its Atom feed.
            if host.contains("youtube.com") || host == "youtu.be" {
                if let yt = resolveYouTube(url) { return yt }
                // Not a /channel/ URL (e.g. a direct feeds/videos.xml or a
                // /@handle page). Fall through to generic handling below.
            }

            // A Bilibili space page: route through RSSHub.
            if host.contains("bilibili.com") {
                if let bili = resolveBilibili(url) { return bili }
            }

            // Any other http(s) link is treated as a direct RSS/Atom feed URL.
            // This covers self-hosted feeds, RSSHub routes pasted as full URLs,
            // and YouTube's own feeds/videos.xml endpoint.
            let platform = inferPlatform(fromURL: url)
            return Resolved(platform: platform, feedURL: input)
        }

        // --- Raw Bilibili UID (all digits) ---
        if input.allSatisfy({ $0.isNumber }) {
            return Resolved(
                platform: .bilibili,
                feedURL: "\(rsshubBase)/bilibili/user/video/\(input)"
            )
        }

        return nil
    }

    /// Best-effort platform guess from an RSSHub route (e.g. "youtube/user/...").
    private static func inferPlatform(fromRoute route: String) -> Platform {
        let lower = route.lowercased()
        if lower.hasPrefix("youtube") || lower.hasPrefix("/youtube") { return .youtube }
        if lower.hasPrefix("bilibili") || lower.hasPrefix("/bilibili") { return .bilibili }
        return .rss
    }

    /// Best-effort platform guess from a direct feed URL so the player knows
    /// how to embed entries.
    private static func inferPlatform(fromURL url: URL) -> Platform {
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtube.com") || host == "youtu.be" { return .youtube }
        if host.contains("bilibili.com") { return .bilibili }
        return .rss
    }

    private static func resolveYouTube(_ url: URL) -> Resolved? {
        let path = url.path
        // .../channel/UCxxxx
        if let r = path.range(of: "/channel/") {
            let id = String(path[r.upperBound...]).split(separator: "/").first.map(String.init) ?? ""
            if !id.isEmpty {
                return Resolved(
                    platform: .youtube,
                    feedURL: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"
                )
            }
        }
        // For @handle or /user/ or /c/ forms we cannot derive the channel_id
        // without a network lookup; fall back to feeding the handle through
        // YouTube's feed endpoint which only accepts channel_id. Signal failure
        // so the UI can ask the user for the channel id / channel URL instead.
        return nil
    }

    private static func resolveBilibili(_ url: URL) -> Resolved? {
        // https://space.bilibili.com/<uid>
        let comps = url.path.split(separator: "/").map(String.init)
        if let uid = comps.first(where: { $0.allSatisfy { $0.isNumber } }) {
            return Resolved(
                platform: .bilibili,
                feedURL: "\(rsshubBase)/bilibili/user/video/\(uid)"
            )
        }
        return nil
    }

    // MARK: - Fetching

    /// Fetch and parse a subscription's entries.
    static func fetchEntries(
        for subscription: Subscription,
        completion: @escaping (Result<FeedParser.ParseResult, FeedError>) -> Void
    ) {
        guard let url = URL(string: subscription.feedURL) else {
            completion(.failure(.invalidInput))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (compatible; Flo/1.0)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let data = data else {
                completion(.failure(.parse))
                return
            }
            let parser = FeedParser(subscriptionID: subscription.id, platform: subscription.platform)
            guard let result = parser.parse(data) else {
                completion(.failure(.parse))
                return
            }
            completion(.success(result))
        }.resume()
    }

    /// Fetch just the feed title (used when adding a subscription to get its name).
    static func probeTitle(
        platform: Platform,
        feedURL: String,
        completion: @escaping (String?) -> Void
    ) {
        let probe = Subscription(title: "", platform: platform, feedURL: feedURL)
        fetchEntries(for: probe) { result in
            switch result {
            case .success(let parsed): completion(parsed.feedTitle)
            case .failure: completion(nil)
            }
        }
    }
}
