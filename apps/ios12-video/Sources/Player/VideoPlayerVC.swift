import UIKit
import WebKit

/// Full-screen video player that embeds the official YouTube / Bilibili
/// players inside a `WKWebView`. The web view is created on `viewDidLoad`
/// and torn down on `deinit` / dismissal to release memory promptly — this
/// matters a lot on a 1GB iPad Air 1.
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = entry.title

        // Close button (we are presented modally).
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        setupWebView()
        setupActivity()
        load()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Allow autoplay without a user gesture so the embed starts immediately.
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
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

    private func load() {
        guard let embed = Self.embedURL(pageURL: entry.pageURL, platform: platform),
              let url = URL(string: embed) else {
            showError()
            return
        }
        var request = URLRequest(url: url)
        // Bilibili's player checks the referer.
        if platform == .bilibili {
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        }
        webView?.load(request)
    }

    private func showError() {
        activity.stopAnimating()
        let label = UILabel()
        label.text = "无法播放该视频"
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
        // Stop loading and detach to free the web content process quickly.
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    // MARK: - Embed URL (ported from the web app's transformVideoUrl)

    /// Builds the embeddable player URL for a given video page URL.
    static func embedURL(pageURL: String, platform: Platform) -> String? {
        switch platform {
        case .youtube:
            guard let id = youtubeID(from: pageURL) else { return nil }
            return "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&playsinline=1"
        case .bilibili:
            guard let bvid = bilibiliBVID(from: pageURL) else { return nil }
            var comps = URLComponents(string: "https://player.bilibili.com/player.html")!
            comps.queryItems = [
                URLQueryItem(name: "isOutside", value: "true"),
                URLQueryItem(name: "autoplay", value: "true"),
                URLQueryItem(name: "danmaku", value: "true"),
                URLQueryItem(name: "highQuality", value: "true"),
                URLQueryItem(name: "bvid", value: bvid),
            ]
            return comps.url?.absoluteString
        case .rss:
            // Generic feeds have no embeddable player; open the entry's own page.
            return pageURL.hasPrefix("http") ? pageURL : nil
        }
    }

    private static func youtubeID(from url: String) -> String? {
        // watch?v=ID
        if let comps = URLComponents(string: url),
           let v = comps.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        // youtu.be/ID  or  /shorts/ID  or  /embed/ID
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
