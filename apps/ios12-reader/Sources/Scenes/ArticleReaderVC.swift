import UIKit
import WebKit

/// Renders an article inside a `WKWebView` from a locally assembled HTML
/// template — injected reading styles, adjustable font size, and a manual
/// light/sepia/dark theme toggle (iOS 12 has no system dark mode, so the
/// reader does its own theming via CSS).
final class ArticleReaderVC: UIViewController {

    enum ReaderTheme: String, CaseIterable {
        case light, sepia, dark
    }

    private let entry: ArticleEntry
    private let subscriptionTitle: String

    private var webView: WKWebView!
    private let activity = UIActivityIndicatorView(style: .gray)

    // Persisted reading prefs (shared across articles).
    private static let fontSizeKey = "reader_font_size"
    private static let themeKey = "reader_theme"

    private var fontSize: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.fontSizeKey)
            return stored == 0 ? 18 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.fontSizeKey) }
    }

    private var readerTheme: ReaderTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: Self.themeKey),
               let theme = ReaderTheme(rawValue: raw) {
                return theme
            }
            return .light
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.themeKey) }
    }

    init(entry: ArticleEntry, subscriptionTitle: String) {
        self.entry = entry
        self.subscriptionTitle = subscriptionTitle
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        // Release the WKWebView eagerly. On the 1 GB iPad Air 1, holding on
        // to a fully-rendered article page is the heaviest part of the reader.
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColor(for: readerTheme)
        title = ""

        setupNavigationItems()
        setupWebView()
        renderContent()
    }

    private func setupNavigationItems() {
        let openOriginal = UIBarButtonItem(
            title: "原文",
            style: .plain,
            target: self,
            action: #selector(openOriginalTapped)
        )
        let aA = UIBarButtonItem(
            title: "Aa",
            style: .plain,
            target: self,
            action: #selector(typographyTapped)
        )
        navigationItem.rightBarButtonItems = [openOriginal, aA]
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.backgroundColor = backgroundColor(for: readerTheme)
        webView.isOpaque = false
        view.addSubview(webView)

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.hidesWhenStopped = true
        view.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        activity.startAnimating()
    }

    // MARK: - Rendering

    private func renderContent() {
        let html = composeHTML()
        let baseURL = URL(string: entry.link)
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func composeHTML() -> String {
        let bodyHTML = sanitize(entry.contentHTML ?? "<p>(无正文)</p>")
        let css = readerCSS(theme: readerTheme, fontSize: fontSize)

        let title = htmlEscape(entry.title)
        let meta = htmlEscape(metaLine())

        return """
        <!DOCTYPE html>
        <html lang="zh-Hans">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <title>\(title)</title>
        <style>\(css)</style>
        </head>
        <body>
        <article>
        <h1>\(title)</h1>
        <p class="meta">\(meta)</p>
        <div class="body">\(bodyHTML)</div>
        </article>
        </body>
        </html>
        """
    }

    private func metaLine() -> String {
        var parts: [String] = [subscriptionTitle]
        if let author = entry.author, !author.isEmpty { parts.append(author) }
        if let date = entry.published {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            parts.append(f.string(from: date))
        }
        return parts.joined(separator: " · ")
    }

    /// Remove `<script>` and `<style>` blocks. The web view also wouldn't run
    /// inline event handlers under the local base URL, but stripping the
    /// elements outright also avoids visible CSS bleeding into the reader
    /// theme.
    private func sanitize(_ html: String) -> String {
        var result = html
        for tag in ["script", "style"] {
            let pattern = "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    private func htmlEscape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Toolbar actions

    @objc private func openOriginalTapped() {
        guard let url = URL(string: entry.link) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc private func typographyTapped() {
        let sheet = UIAlertController(title: "阅读样式", message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "字号 +", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.fontSize = min(self.fontSize + 2, 28)
            self.renderContent()
        })
        sheet.addAction(UIAlertAction(title: "字号 -", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.fontSize = max(self.fontSize - 2, 12)
            self.renderContent()
        })

        for theme in ReaderTheme.allCases {
            let title: String
            switch theme {
            case .light: title = "浅色"
            case .sepia: title = "护眼"
            case .dark: title = "深色"
            }
            let prefix = (theme == readerTheme) ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: prefix + title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.readerTheme = theme
                self.view.backgroundColor = self.backgroundColor(for: theme)
                self.webView.backgroundColor = self.backgroundColor(for: theme)
                self.renderContent()
            })
        }

        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(sheet, animated: true)
    }

    // MARK: - Theme

    private func backgroundColor(for theme: ReaderTheme) -> UIColor {
        switch theme {
        case .light: return UIColor.white
        case .sepia: return UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1.0)
        case .dark:  return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        }
    }

    private func readerCSS(theme: ReaderTheme, fontSize: Int) -> String {
        let palette = self.palette(for: theme)
        return """
        :root { color-scheme: \(theme == .dark ? "dark" : "light"); }
        html, body {
            margin: 0; padding: 0;
            background: \(palette.background);
            color: \(palette.text);
            -webkit-text-size-adjust: 100%;
        }
        article {
            padding: 16px 18px 48px;
            max-width: 720px;
            margin: 0 auto;
            font: \(fontSize)px/1.65 -apple-system, "PingFang SC", "Helvetica Neue", Helvetica, Arial, sans-serif;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        h1 {
            font-size: 1.45em;
            line-height: 1.3;
            margin: 0 0 12px;
            color: \(palette.heading);
        }
        .meta {
            color: \(palette.muted);
            font-size: 0.82em;
            margin: 0 0 24px;
        }
        .body img, .body video, .body iframe {
            max-width: 100%;
            height: auto;
            display: block;
            margin: 12px auto;
            border-radius: 4px;
        }
        .body figure { margin: 16px 0; }
        .body p { margin: 0 0 1em; }
        .body a { color: \(palette.link); text-decoration: underline; }
        .body blockquote {
            margin: 16px 0;
            padding: 4px 14px;
            border-left: 3px solid \(palette.accent);
            color: \(palette.muted);
            background: \(palette.quoteBackground);
            border-radius: 2px;
        }
        .body pre, .body code {
            font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            background: \(palette.codeBackground);
            color: \(palette.text);
            border-radius: 4px;
        }
        .body code { padding: 0 4px; }
        .body pre {
            padding: 10px 12px;
            overflow-x: auto;
            font-size: 0.9em;
        }
        .body hr { border: none; border-top: 1px solid \(palette.separator); margin: 24px 0; }
        .body table {
            border-collapse: collapse;
            max-width: 100%;
            display: block;
            overflow-x: auto;
        }
        .body th, .body td {
            border: 1px solid \(palette.separator);
            padding: 6px 10px;
        }
        """
    }

    private struct Palette {
        let background, text, heading, muted, link, accent, quoteBackground, codeBackground, separator: String
    }

    private func palette(for theme: ReaderTheme) -> Palette {
        switch theme {
        case .light:
            return Palette(
                background: "#ffffff",
                text: "#1c1c1e",
                heading: "#000000",
                muted: "#6c6c70",
                link: "#FF5C00",
                accent: "#FF5C00",
                quoteBackground: "#f6f6f8",
                codeBackground: "#f2f2f4",
                separator: "#e2e2e6"
            )
        case .sepia:
            return Palette(
                background: "#f5eedc",
                text: "#3a2f1b",
                heading: "#221a07",
                muted: "#7b6a4e",
                link: "#c14a00",
                accent: "#c14a00",
                quoteBackground: "#ece2c5",
                codeBackground: "#e8dec2",
                separator: "#d8cba6"
            )
        case .dark:
            return Palette(
                background: "#1b1b1d",
                text: "#e7e7e9",
                heading: "#ffffff",
                muted: "#a0a0a4",
                link: "#FF7A33",
                accent: "#FF7A33",
                quoteBackground: "#262629",
                codeBackground: "#2a2a2e",
                separator: "#3a3a3e"
            )
        }
    }
}

extension ArticleReaderVC: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activity.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activity.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activity.stopAnimating()
    }

    /// Intercept link clicks: open external pages in Safari instead of replacing
    /// the article content. The initial `loadHTMLString` is `navigationType`
    /// `.other`, which we always allow.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
