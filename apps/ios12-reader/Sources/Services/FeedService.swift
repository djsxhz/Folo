import Foundation

/// Fetches and resolves subscription feeds. Pure `URLSession`, no dependencies.
///
/// The reader accepts only three input shapes:
///   1. `rsshub://route/...` — expanded against the configured RSSHub instance.
///   2. `https://...` — any RSS / Atom URL, used directly.
///   3. `http://...` — same, allowed because `NSAllowsArbitraryLoads` is on
///      (so a self-hosted FreshRSS / local RSSHub on the LAN works).
enum FeedService {
    /// The RSSHub instance used to expand `rsshub://` URLs. Defaults to the
    /// public instance but can be overridden in settings — including to a
    /// plain-http LAN address.
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
            case .invalidInput:
                return "无法识别该链接,请粘贴 http(s) 开头的 RSS / Atom 源地址,或 rsshub:// 路由"
            case .network(let msg):
                return "网络错误:\(msg)"
            case .parse:
                return "订阅源解析失败"
            }
        }
    }

    /// Resolved feed descriptor derived from user input.
    struct Resolved {
        let feedURL: String
    }

    /// Feed-level metadata discovered while probing a subscription.
    struct FeedMetadata {
        let title: String?
        let iconURL: String?
    }

    // MARK: - Input resolution

    /// Resolve arbitrary user input (a pasted URL) into a feed URL.
    static func resolve(input raw: String) -> Resolved? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // --- rsshub:// protocol ---
        // e.g. rsshub://github/issues/foo/bar  ->  <rsshubBase>/github/issues/foo/bar
        let scheme = "rsshub://"
        if input.lowercased().hasPrefix(scheme) {
            let route = String(input.dropFirst(scheme.count))
            guard !route.isEmpty else { return nil }
            let base = rsshubBase.hasSuffix("/") ? String(rsshubBase.dropLast()) : rsshubBase
            let path = route.hasPrefix("/") ? route : "/" + route
            return Resolved(feedURL: base + path)
        }

        // --- http(s):// direct feed URL ---
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return Resolved(feedURL: input)
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
        // A real-browser UA gets us past a few feeds that block default UAs.
        request.setValue(
            "Mozilla/5.0 (iPad; CPU OS 12_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let data = data else {
                completion(.failure(.parse))
                return
            }
            let parser = FeedParser(subscriptionID: subscription.id, feedBaseURL: url)
            guard let result = parser.parse(data) else {
                completion(.failure(.parse))
                return
            }
            completion(.success(result))
        }.resume()
    }

    /// Fetch feed metadata used when adding a subscription to get its name and icon.
    static func probeMetadata(
        feedURL: String,
        completion: @escaping (FeedMetadata) -> Void
    ) {
        let probe = Subscription(title: "", feedURL: feedURL)
        fetchEntries(for: probe) { result in
            switch result {
            case .success(let parsed):
                completion(FeedMetadata(title: parsed.feedTitle, iconURL: parsed.feedIconURL))
            case .failure:
                completion(FeedMetadata(title: nil, iconURL: nil))
            }
        }
    }
}
