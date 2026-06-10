import UIKit
import WebKit

/// Bilibili video quality options
enum BilibiliQuality: Int, CaseIterable {
    case q360p = 16
    case q480p = 32
    case q720p = 64
    case q1080p = 80

    var displayName: String {
        switch self {
        case .q360p: return "360P"
        case .q480p: return "480P"
        case .q720p: return "720P"
        case .q1080p: return "1080P"
        }
    }

    static var defaultQuality: BilibiliQuality {
        let saved = UserDefaults.standard.integer(forKey: "bilibili_quality")
        return BilibiliQuality(rawValue: saved) ?? .q1080p
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "bilibili_quality")
    }
}

/// Full-screen video player that embeds the official YouTube / Bilibili
/// players inside a `WKWebView`.
final class VideoPlayerVC: UIViewController {
    private let entry: VideoEntry
    private let platform: Platform
    private var webView: WKWebView?
    private let activity = UIActivityIndicatorView(style: .whiteLarge)
    private var qualityButton: UIButton?
    private var currentQuality: BilibiliQuality = .defaultQuality

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
        setupQualityButton()
        load()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Share the persistent cookie store so a Bilibili login (SESSDATA)
        // performed in Settings unlocks higher resolutions here.
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        // Spoof User-Agent to match AppDelegate's setting
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"
        view.addSubview(webView)
        installCloseGestures(on: webView)
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
        installCloseGestures(on: view)
    }

    private func setupQualityButton() {
        // Quality button is no longer needed for Bilibili since we now load
        // the full web player which has its own quality selector.
        // Kept for potential future use with other platforms.
        return
    }

    @objc private func qualityButtonTapped() {
        let alert = UIAlertController(title: "画质选择", message: nil, preferredStyle: .actionSheet)

        for quality in BilibiliQuality.allCases {
            let title = quality == currentQuality ? "✓ \(quality.displayName)" : quality.displayName
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.changeQuality(to: quality)
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        // For iPad, set sourceView to avoid crash
        if let popover = alert.popoverPresentationController {
            popover.sourceView = qualityButton
            popover.sourceRect = qualityButton?.bounds ?? .zero
        }

        present(alert, animated: true)
    }

    private func changeQuality(to quality: BilibiliQuality) {
        currentQuality = quality
        quality.save()
        qualityButton?.setTitle(quality.displayName, for: .normal)

        // Reload the player with new quality
        webView?.stopLoading()
        activity.startAnimating()
        load()
    }

    private func installCloseGestures(on targetView: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleClosePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        targetView.addGestureRecognizer(pan)

        let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleClosePan(_:)))
        edgeSwipe.edges = .left
        edgeSwipe.delegate = self
        edgeSwipe.cancelsTouchesInView = false
        targetView.addGestureRecognizer(edgeSwipe)
    }

    private func load() {
        let resolvedPlatform = Self.resolvePlatform(pageURL: entry.pageURL, fallback: platform)

        // Try loading embed URLs directly without HTML wrapper
        guard let embed = Self.embedURL(pageURL: entry.pageURL, platform: resolvedPlatform, currentQuality: currentQuality),
              let url = URL(string: embed) else {
            showError()
            return
        }

        var request = URLRequest(url: url)
        switch resolvedPlatform {
        case .youtube:
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
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

    @objc private func handleClosePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)
        guard translation.x > 120,
              abs(translation.y) < 90,
              velocity.x > 250
        else { return }
        close()
    }

    deinit {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    // MARK: - Embed URL

    static func embedURL(pageURL: String, platform: Platform) -> String? {
        return embedURL(pageURL: pageURL, platform: platform, currentQuality: .defaultQuality)
    }

    static func embedURL(pageURL: String, platform: Platform, currentQuality: BilibiliQuality) -> String? {
        switch platform {
        case .youtube:
            guard let id = youtubeID(from: pageURL) else { return nil }
            return "https://m.youtube.com/watch?v=\(id)"
        case .bilibili:
            guard let bvid = bilibiliBVID(from: pageURL) else { return nil }
            var comps = URLComponents(string: "https://player.bilibili.com/player.html")!
            comps.queryItems = [
                URLQueryItem(name: "isOutside", value: "true"),
                URLQueryItem(name: "autoplay", value: "true"),
                URLQueryItem(name: "danmaku", value: "false"),
                URLQueryItem(name: "muted", value: "false"),
                URLQueryItem(name: "highQuality", value: "true"),
                URLQueryItem(name: "high_quality", value: "1"),
                // Request specific quality via qn parameter.
                // Only honored when a valid SESSDATA login cookie is present.
                URLQueryItem(name: "qn", value: "\(currentQuality.rawValue)"),
                URLQueryItem(name: "as_wide", value: "1"),
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

    private static func baseURL(for url: URL, platform: Platform) -> URL? {
        switch platform {
        case .youtube:
            return URL(string: "https://www.youtube-nocookie.com")
        case .bilibili:
            return URL(string: "https://www.bilibili.com")
        case .rss:
            return url
        }
    }

    private static func playerHTML(embedURL: String) -> String {
        let escapedURL = htmlEscaped(embedURL)
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: #000;
            }
            iframe {
              position: absolute;
              left: 0;
              top: 0;
              width: 100%;
              height: 100%;
              border: 0;
              background: #000;
            }
          </style>
        </head>
        <body>
          <iframe
            src="\(escapedURL)"
            allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
            allowfullscreen
            webkitallowfullscreen
            referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body>
        </html>
        """
    }

    private static func htmlEscaped(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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

extension VideoPlayerVC: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIScreenEdgePanGestureRecognizer { return true }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return velocity.x > abs(velocity.y) * 1.5 && velocity.x > 120
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
