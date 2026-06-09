import Foundation

/// Parses YouTube Atom feeds and RSSHub RSS feeds into `VideoEntry` values
/// using the system `XMLParser` (zero third-party dependencies).
///
/// Supported shapes:
/// - YouTube Atom: `<feed><entry>` with `<yt:videoId>`, `<media:thumbnail>`, `<title>`, `<link>`, `<published>`.
/// - RSS 2.0 (RSSHub for Bilibili): `<rss><channel><item>` with `<title>`, `<link>`, `<pubDate>`,
///   and a thumbnail discovered from `<media:thumbnail>`, `<enclosure>`, or an `<img>` in the description.
final class FeedParser: NSObject {
    /// Result of a parse: the feed's own title plus its entries.
    struct ParseResult {
        var feedTitle: String?
        var entries: [VideoEntry]
    }

    private let subscriptionID: String
    private let platform: Platform

    // Parser state.
    private var feedTitle: String?
    private var entries: [VideoEntry] = []

    // Whether we have already captured the channel/feed-level title.
    private var capturedFeedTitle = false

    // Current element bookkeeping.
    private var elementStack: [String] = []
    private var currentText = ""

    // Current item being built.
    private var inItem = false
    private var curTitle: String?
    private var curLink: String?
    private var curVideoID: String?
    private var curThumbnail: String?
    private var curPublished: String?
    private var curDescription: String?

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    init(subscriptionID: String, platform: Platform) {
        self.subscriptionID = subscriptionID
        self.platform = platform
    }

    /// Parse the given feed data. Returns `nil` if the XML is malformed.
    func parse(_ data: Data) -> ParseResult? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }
        return ParseResult(feedTitle: feedTitle, entries: entries)
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

        switch elementName {
        case "entry", "item":
            inItem = true
            curTitle = nil
            curLink = nil
            curVideoID = nil
            curThumbnail = nil
            curPublished = nil
            curDescription = nil
        case "media:thumbnail", "media:content":
            if let url = attributeDict["url"], curThumbnail == nil {
                curThumbnail = url
            }
        case "enclosure":
            if let type = attributeDict["type"], type.hasPrefix("image"),
               let url = attributeDict["url"], curThumbnail == nil {
                curThumbnail = url
            }
        case "link":
            // Atom links carry the URL in an href attribute.
            if inItem, let href = attributeDict["href"], curLink == nil {
                curLink = href
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title":
            if inItem {
                if curTitle == nil { curTitle = text }
            } else if !capturedFeedTitle, !text.isEmpty {
                feedTitle = text
                capturedFeedTitle = true
            }
        case "yt:videoId":
            curVideoID = text
        case "link":
            // RSS `<link>text</link>` form.
            if inItem, curLink == nil, !text.isEmpty {
                curLink = text
            }
        case "published", "pubDate", "updated":
            if inItem, curPublished == nil, !text.isEmpty {
                curPublished = text
            }
        case "description", "content:encoded":
            if inItem, curDescription == nil, !text.isEmpty {
                curDescription = text
            }
        case "entry", "item":
            finishCurrentItem()
            inItem = false
        default:
            break
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
        currentText = ""
    }

    private func finishCurrentItem() {
        // Resolve the page URL.
        var pageURL = curLink ?? ""
        if let vid = curVideoID, pageURL.isEmpty {
            pageURL = "https://www.youtube.com/watch?v=\(vid)"
        }
        guard !pageURL.isEmpty else { return }

        // Resolve a stable id.
        let id = curVideoID ?? pageURL

        // Try to recover a thumbnail from the description HTML if none was found.
        var thumb = curThumbnail
        if thumb == nil, let desc = curDescription {
            thumb = Self.firstImageURL(in: desc)
        }

        let entry = VideoEntry(
            id: id,
            subscriptionID: subscriptionID,
            title: curTitle ?? "Untitled",
            pageURL: pageURL,
            thumbnailURL: thumb,
            published: Self.parseDate(curPublished),
            isRead: false
        )
        entries.append(entry)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if let d = iso8601.date(from: raw) { return d }
        if let d = rfc822.date(from: raw) { return d }
        return nil
    }

    /// Extracts the first `<img src="...">` URL from an HTML fragment.
    private static func firstImageURL(in html: String) -> String? {
        guard let range = html.range(of: "src=\"", options: .caseInsensitive) else { return nil }
        let rest = html[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let url = String(rest[..<end])
        return url.hasPrefix("http") ? url : nil
    }
}
