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
            case .invalidInput: return "无法识别该链接,请粘贴 YouTube 频道或 Bilibili UP 主链接"
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
    static func resolve(input raw: String) -> Resolved? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // --- YouTube ---
        // Direct channel id form: UCxxxxxxxx
        if input.hasPrefix("UC"), input.count >= 20, !input.contains(" "), !input.contains("/") {
            return Resolved(
                platform: .youtube,
                feedURL: "https://www.youtube.com/feeds/videos.xml?channel_id=\(input)"
            )
        }

        if let url = URL(string: input), let host = url.host?.lowercased() {
            if host.contains("youtube.com") || host == "youtu.be" {
                return resolveYouTube(url)
            }
            if host.contains("bilibili.com") {
                return resolveBilibili(url)
            }
        }

        // Raw Bilibili UID (all digits).
        if input.allSatisfy({ $0.isNumber }) {
            return Resolved(
                platform: .bilibili,
                feedURL: "\(rsshubBase)/bilibili/user/video/\(input)"
            )
        }

        return nil
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
