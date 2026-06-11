import Foundation

/// XMLParser-based RSS 2.0 + Atom parser that pulls per-article fields used by
/// the reader (title, link, author, published, summary, full content HTML,
/// thumbnail).
///
/// Differences from the video-app parser this was forked from:
/// - The content-priority order is explicit (`content:encoded` > Atom
///   `<content>` > `<description>` / `<summary>`), instead of "first non-empty".
/// - Atom `<content type="html">` is captured as the article body (the video
///   parser only treated `<content>` as a thumbnail carrier via `media:content`).
/// - Relative image URLs in the content HTML and in thumbnail attributes are
///   resolved against the article link, so the reader webview can load them.
final class FeedParser: NSObject {
    /// Result of a parse: the feed's own metadata plus its entries.
    struct ParseResult {
        var feedTitle: String?
        var feedIconURL: String?
        var entries: [ArticleEntry]
    }

    private let subscriptionID: String
    /// Used as the base when normalising relative URLs found at feed scope
    /// (e.g. the feed `<logo>` / channel `<image><url>`).
    private let feedBaseURL: URL?

    // Parser state.
    private var feedTitle: String?
    private var feedIconURL: String?
    private var entries: [ArticleEntry] = []

    private var capturedFeedTitle = false
    private var inFeedImage = false

    private var elementStack: [String] = []
    private var currentText = ""

    // Current item being built.
    private var inItem = false
    private var curTitle: String?
    private var curLink: String?
    private var curAuthor: String?
    private var curThumbnail: String?
    private var curPublished: String?
    private var curSummary: String?
    private var curAtomContent: String?
    private var curContentEncoded: String?
    private var curDescription: String?
    private var curGUID: String?

    // Whether the current `<content>` element is the Atom article-body form
    // (anything that is NOT `media:content`). Decided at didStartElement so we
    // know what to do with the text in didEndElement.
    private var atomContentIsBody = false
    // Within an Atom `<author>` block, the author name is in a nested `<name>`.
    private var inAtomAuthor = false

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    init(subscriptionID: String, feedBaseURL: URL? = nil) {
        self.subscriptionID = subscriptionID
        self.feedBaseURL = feedBaseURL
    }

    /// Parse the given feed data. Returns `nil` if the XML is malformed.
    func parse(_ data: Data) -> ParseResult? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }
        return ParseResult(feedTitle: feedTitle, feedIconURL: feedIconURL, entries: entries)
    }
}

extension FeedParser: XMLParserDelegate {
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        elementStack.append(elementName)
        currentText = ""

        let lower = elementName.lowercased()

        switch lower {
        case "entry", "item":
            inItem = true
            curTitle = nil
            curLink = nil
            curAuthor = nil
            curThumbnail = nil
            curPublished = nil
            curSummary = nil
            curAtomContent = nil
            curContentEncoded = nil
            curDescription = nil
            curGUID = nil
            atomContentIsBody = false
            inAtomAuthor = false
        case "image":
            if !inItem { inFeedImage = true }
        case "author":
            if inItem { inAtomAuthor = true }
        default:
            break
        }

        // Thumbnails from `<media:thumbnail>` / `<media:content medium=image>` /
        // `<enclosure type="image/...">`.
        if let thumbnailURL = Self.thumbnailURL(for: elementName, attributes: attributeDict) {
            if inItem, curThumbnail == nil {
                curThumbnail = thumbnailURL
            } else if !inItem, feedIconURL == nil {
                feedIconURL = thumbnailURL
            }
        }

        switch lower {
        case "enclosure":
            if let type = attributeDict["type"], type.hasPrefix("image"),
               let url = normalizedURL(attributeDict["url"]),
               curThumbnail == nil {
                curThumbnail = url
            }
        case "link":
            // Atom `<link href=... rel=...>`: the article URL is the
            // `rel="alternate"` (or unspecified) one. Skip enclosures /
            // self / related links.
            if inItem, let href = attributeDict["href"] {
                let rel = (attributeDict["rel"] ?? "alternate").lowercased()
                if rel == "alternate" || rel.isEmpty, curLink == nil {
                    curLink = href
                }
            }
        case "content":
            // Distinguish Atom `<content>` (article body) from
            // `<media:content>` (thumbnail carrier). qName preserves the
            // namespace prefix; if there's a prefix it's media-style.
            let qLower = (qName ?? elementName).lowercased()
            let isMedia = qLower.hasSuffix(":content") || qLower == "media:content"
            atomContentIsBody = inItem && !isMedia
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = elementName.lowercased()
        let qLower = (qName ?? elementName).lowercased()

        switch lower {
        case "title":
            if inItem {
                if curTitle == nil { curTitle = text }
            } else if !inFeedImage, !capturedFeedTitle, !text.isEmpty {
                feedTitle = text
                capturedFeedTitle = true
            }
        case "logo", "icon":
            if !inItem, feedIconURL == nil {
                feedIconURL = normalizedURL(text)
            }
        case "url":
            if !inItem, inFeedImage, feedIconURL == nil {
                feedIconURL = normalizedURL(text)
            }
        case "link":
            // RSS `<link>text</link>` form.
            if inItem, curLink == nil, !text.isEmpty {
                curLink = text
            }
        case "guid", "id":
            if inItem, curGUID == nil, !text.isEmpty {
                curGUID = text
            }
        case "published", "pubdate", "updated", "dc:date":
            if inItem, curPublished == nil, !text.isEmpty {
                curPublished = text
            }
        case "author", "dc:creator":
            // RSS `<author>name</author>` or Dublin Core creator. Atom
            // `<author>` is a wrapper and the `<name>` child below populates
            // curAuthor; if we land here with text and curAuthor is still nil
            // (RSS form) it's safe to use.
            if inItem, curAuthor == nil, !text.isEmpty {
                curAuthor = text
            }
            if lower == "author" { inAtomAuthor = false }
        case "name":
            if inItem, inAtomAuthor, curAuthor == nil, !text.isEmpty {
                curAuthor = text
            }
        case "description":
            if inItem, curDescription == nil, !text.isEmpty {
                curDescription = text
            }
        case "summary":
            if inItem, curSummary == nil, !text.isEmpty {
                curSummary = text
            }
        case "content":
            if inItem, atomContentIsBody, curAtomContent == nil, !text.isEmpty {
                curAtomContent = text
            }
            atomContentIsBody = false
        case "content:encoded":
            if inItem, curContentEncoded == nil, !text.isEmpty {
                curContentEncoded = text
            }
        case "entry", "item":
            finishCurrentItem()
            inItem = false
        case "image":
            if !inItem { inFeedImage = false }
        default:
            // Also handle the qualified-name variants for content:encoded.
            if inItem, qLower == "content:encoded", curContentEncoded == nil, !text.isEmpty {
                curContentEncoded = text
            }
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
        currentText = ""
    }

    private func finishCurrentItem() {
        let pageURL = curLink ?? ""
        guard !pageURL.isEmpty else { return }

        let itemBase = URL(string: pageURL) ?? feedBaseURL

        // Content priority: content:encoded > Atom <content> > <description>.
        // <summary> is a separate (typically shorter) field used for the list cell.
        let body = curContentEncoded ?? curAtomContent ?? curDescription
        let resolvedBody = body.map { resolveImageSources(in: $0, base: itemBase) }

        // Best-effort summary for the list cell:
        //   1. explicit <summary> (Atom)
        //   2. plain text derived from the body
        let summarySource = curSummary ?? body
        let summary = summarySource.map { Self.plainTextSnippet(from: $0) }

        // Thumbnail fallback: try the first <img> in the body.
        var thumb = curThumbnail
        if thumb == nil, let html = body {
            thumb = firstImageURL(in: html, base: itemBase)
        }

        let id = (curGUID?.isEmpty == false ? curGUID! : pageURL)

        let entry = ArticleEntry(
            id: id,
            subscriptionID: subscriptionID,
            title: curTitle ?? "Untitled",
            author: curAuthor,
            link: pageURL,
            thumbnailURL: thumb,
            published: Self.parseDate(curPublished),
            summary: summary,
            contentHTML: resolvedBody,
            isRead: false
        )
        entries.append(entry)
    }

    // MARK: - Helpers

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if let d = iso8601.date(from: raw) { return d }
        if let d = iso8601Fractional.date(from: raw) { return d }
        if let d = rfc822.date(from: raw) { return d }
        return nil
    }

    /// Extract a short plain-text snippet from an HTML fragment for the list cell.
    private static func plainTextSnippet(from html: String, limit: Int = 160) -> String {
        // Strip tags, decode a few common entities, collapse whitespace.
        var text = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > limit {
            let end = text.index(text.startIndex, offsetBy: limit)
            text = String(text[..<end]) + "…"
        }
        return text
    }

    /// Rewrite relative `src=` URLs in an HTML fragment to absolute URLs using
    /// the article link as the base. Absolute URLs are left untouched.
    private func resolveImageSources(in html: String, base: URL?) -> String {
        guard base != nil else { return html }
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*(['"])([^'"]+)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }
        let nsHtml = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
        guard !matches.isEmpty else { return html }

        var result = ""
        var cursor = 0
        for match in matches {
            let srcNSRange = match.range(at: 2)
            guard srcNSRange.location != NSNotFound else { continue }
            let raw = nsHtml.substring(with: srcNSRange)
            guard let resolved = absoluteURLString(raw, base: base), resolved != raw else { continue }

            // Copy [cursor, srcStart), then the rewritten src, then advance.
            let srcStart = srcNSRange.location
            let srcEnd = srcStart + srcNSRange.length
            result += nsHtml.substring(with: NSRange(location: cursor, length: srcStart - cursor))
            result += resolved
            cursor = srcEnd
        }
        if cursor < nsHtml.length {
            result += nsHtml.substring(with: NSRange(location: cursor, length: nsHtml.length - cursor))
        }
        return result
    }

    /// Extracts the first `<img src="...">` URL from an HTML fragment, resolving
    /// relative URLs against `base`.
    private func firstImageURL(in html: String, base: URL?) -> String? {
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*(['"])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges >= 3,
              let srcRange = Range(match.range(at: 2), in: html)
        else { return nil }
        let raw = String(html[srcRange])
        return absoluteURLString(raw, base: base)
    }

    /// Returns an absolute `http(s)://` URL string. Handles:
    /// - absolute `http://`, `https://`
    /// - protocol-relative `//cdn.example.com/x.png`
    /// - root-relative `/img/x.png`
    /// - path-relative `img/x.png`
    private func absoluteURLString(_ raw: String, base: URL?) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            // Prefer the base scheme; default to https when no base.
            let scheme = base?.scheme ?? "https"
            return "\(scheme):\(trimmed)"
        }
        guard let base = base else { return nil }
        if let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL {
            let scheme = resolved.scheme?.lowercased() ?? ""
            if scheme == "http" || scheme == "https" {
                return resolved.absoluteString
            }
        }
        return nil
    }

    private func normalizedURL(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        return absoluteURLString(raw, base: feedBaseURL)
    }

    private static func thumbnailURL(for elementName: String, attributes: [String: String]) -> String? {
        if isThumbnailElement(elementName) {
            return rawURL(attributes["url"] ?? attributes["href"])
        }
        guard isMediaContentElement(elementName) else { return nil }
        let type = attributes["type"]?.lowercased()
        let medium = attributes["medium"]?.lowercased()
        guard type?.hasPrefix("image") == true || medium == "image" else { return nil }
        return rawURL(attributes["url"] ?? attributes["href"])
    }

    private static func rawURL(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isThumbnailElement(_ elementName: String) -> Bool {
        let lower = elementName.lowercased()
        return lower == "thumbnail" || lower.hasSuffix(":thumbnail")
    }

    private static func isMediaContentElement(_ elementName: String) -> Bool {
        let lower = elementName.lowercased()
        // Bare `<content>` may also be `media:content` when the prefix is
        // collapsed in some feeds; we only care about media here, the body
        // capture path in `didEndElement` handles bare `<content>` text.
        return lower.hasSuffix(":content") && lower != "content:encoded"
    }
}
