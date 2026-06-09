import UIKit
import WebKit

/// Embeds Bilibili's official login page in a `WKWebView` so the user can sign
/// in (QR scan / SMS / password). We do not handle credentials ourselves — the
/// official page sets the `SESSDATA` cookie into the shared persistent cookie
/// store, which the video player then reuses to unlock higher resolutions.
final class BilibiliLoginVC: UIViewController {

    /// Called (on the main queue) after a successful login is detected.
    var onLogin: (() -> Void)?

    private var webView: WKWebView!
    private let activity = UIActivityIndicatorView(style: .gray)
    private var pollTimer: Timer?
    private var didDetectLogin = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登录 Bilibili"
        view.backgroundColor = Theme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        setupWebView()
        setupActivity()
        load()
        startPolling()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // Use the SAME persistent store the player uses, so the SESSDATA cookie
        // set here is visible to player.bilibili.com later.
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)
    }

    private func setupActivity() {
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.hidesWhenStopped = true
        activity.startAnimating()
        view.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func load() {
        // The mobile login page works well inside the embedded web view.
        guard let url = URL(string: "https://passport.bilibili.com/login") else { return }
        webView.load(URLRequest(url: url))
    }

    /// Poll the cookie store; the official page sets SESSDATA via JS/redirects
    /// that don't always trigger a navigation we can hook, so polling is the
    /// most reliable cross-flow (QR / SMS / password) detector.
    private func startPolling() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkLogin()
        }
        pollTimer = timer
    }

    private func checkLogin() {
        guard !didDetectLogin else { return }
        BilibiliAuth.isLoggedIn { [weak self] loggedIn in
            guard let self = self, loggedIn, !self.didDetectLogin else { return }
            self.didDetectLogin = true
            self.pollTimer?.invalidate()
            self.pollTimer = nil
            BilibiliAuth.notifyChanged()
            self.onLogin?()
            self.dismiss(animated: true)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    deinit {
        pollTimer?.invalidate()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
    }
}

extension BilibiliLoginVC: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activity.stopAnimating()
        // Re-check on every page settle (covers the post-login redirect).
        checkLogin()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activity.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activity.stopAnimating()
    }
}
