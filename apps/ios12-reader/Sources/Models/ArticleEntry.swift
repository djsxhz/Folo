import Foundation

/// A single article parsed from a subscription's feed.
struct ArticleEntry: Codable, Equatable {
    /// Stable unique identifier (entry id / guid / link).
    let id: String
    /// The subscription this entry belongs to.
    let subscriptionID: String
    /// Article title.
    let title: String
    /// Optional author / byline.
    var author: String?
    /// The canonical web page URL of the article (used for the "open original" action).
    let link: String
    /// Optional thumbnail image URL discovered for the list cell.
    var thumbnailURL: String?
    /// Publish date, if the feed provided one.
    var published: Date?
    /// Short plain-text summary shown under the title in the list.
    var summary: String?
    /// Full article HTML (best-effort: content:encoded > content > description).
    var contentHTML: String?
    /// Whether the user has read this entry.
    var isRead: Bool

    init(
        id: String,
        subscriptionID: String,
        title: String,
        author: String? = nil,
        link: String,
        thumbnailURL: String? = nil,
        published: Date? = nil,
        summary: String? = nil,
        contentHTML: String? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.title = title
        self.author = author
        self.link = link
        self.thumbnailURL = thumbnailURL
        self.published = published
        self.summary = summary
        self.contentHTML = contentHTML
        self.isRead = isRead
    }
}
