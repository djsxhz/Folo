import UIKit
import WebKit

/// Full-screen video player that embeds the official YouTube / Bilibili
/// players inside a `WKWebView`.
final class VideoPlayerVC: UIViewController {
    private let entry: VideoEntry
    private let platform: Platform
    private var webView: WKWebView?
    private let activity = UIActivityIndicatorView(style: .whiteLarge)

    init(entry: VideoEntry, platform: Platform) {
        self.entry = entry
        self.platform = platform
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { return true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupWebView()
        setupActivity()
        setupGestures()
        load()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        view.addSubview(webView)
        self.webView = webView
    }

    private func setupActivity() {
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.startAnimating()
        view.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupGestures() {
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipe.direction = .right
        view.addGestureRecognizer(swipe)

        let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(close))
        edgeSwipe.edges = .left
        view.addGestureRecognizer(edgeSwipe)
    }

    private func load() {
        let resolvedPlatform = Self.resolvePlatform(pageURL: entry.pageURL, fallback: platform)
        guard let embed = Self.embedURL(pageURL: entry.pageURL, platform: resolvedPlatform),
              let url = URL(string: embed) else {
            showError()
            return
        }
        var request = URLRequest(url: url)
        switch resolvedPlatform {
        case .youtube:
            let origin = Self.origin(from: url) ?? "https://www.youtube-nocookie.com"
            request.setValue(origin, forHTTPHeaderField: "Referer")
            request.setValue(origin, forHTTPHeaderField: "Origin")
        case .bilibili:
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        case .rss:
            break
        }
        webView?.load(request)
    }

    private func showError() {
        activity.stopAnimating()
        let label = UILabel()
        label.text = "\u{65E0}\u{6CD5}\u{64AD}\u{653E}\u{8BE5}\u{89C6}\u{9891}"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    deinit {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    // MARK: - Embed URL

    static func embedURL(pageURL: String, platform: Platform) -> String? {
        switch platform {
        case .youtube:
            guard let id = youtubeID(from: pageURL) else { return nil }
            return "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&playsinline=1"
        case .bilibili:
            guard let bvid = bilibiliBVID(from: pageURL) else { return nil }
            var comps = URLComponents(string: "https://www.bilibili.com/blackboard/newplayer.html")!
            comps.queryItems = [
                URLQueryItem(name: "isOutside", value: "true"),
                URLQueryItem(name: "autoplay", value: "true"),
                URLQueryItem(name: "danmaku", value: "true"),
                URLQueryItem(name: "muted", value: "false"),
                URLQueryItem(name: "highQuality", value: "true"),
                URLQueryItem(name: "bvid", value: bvid),
            ]
            return comps.url?.absoluteString
        case .rss:
            return pageURL.hasPrefix("http") ? pageURL : nil
        }
    }

    /// Matches Folo's behavior: prefer the entry URL shape when it is a known
    /// video URL, even if the subscription itself was added as a generic RSS feed.
    private static func resolvePlatform(pageURL: String, fallback: Platform) -> Platform {
        if youtubeID(from: pageURL) != nil { return .youtube }
        if bilibiliBVID(from: pageURL) != nil { return .bilibili }
        return fallback
    }

    private static func origin(from url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return "\(scheme)://\(host)"
    }

    private static func youtubeID(from url: String) -> String? {
        if let comps = URLComponents(string: url),
           let v = comps.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        for marker in ["youtu.be/", "/shorts/", "/embed/"] {
            if let r = url.range(of: marker) {
                let rest = url[r.upperBound...]
                let id = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                if !id.isEmpty { return String(id) }
            }
        }
        return nil
    }

    private static func bilibiliBVID(from url: String) -> String? {
        guard let r = url.range(of: "/video/") else { return nil }
        let rest = url[r.upperBound...]
        let bvid = rest.prefix { $0.isLetter || $0.isNumber }
        return bvid.hasPrefix("BV") ? String(bvid) : nil
    }
}

extension VideoPlayerVC: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activity.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activity.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activity.stopAnimating()
    }
}
