import Foundation

/// A single video entry parsed from a subscription's feed.
struct VideoEntry: Codable, Equatable {
    /// Stable unique identifier (platform video id, or the entry link as fallback).
    let id: String
    /// The subscription this entry belongs to.
    let subscriptionID: String
    /// Video title.
    let title: String
    /// The canonical web page URL of the video (used to derive the embed player URL).
    let pageURL: String
    /// Optional thumbnail image URL.
    var thumbnailURL: String?
    /// Publish date, if the feed provided one.
    var published: Date?
    /// Whether the user has watched / read this entry.
    var isRead: Bool

    init(
        id: String,
        subscriptionID: String,
        title: String,
        pageURL: String,
        thumbnailURL: String? = nil,
        published: Date? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.title = title
        self.pageURL = pageURL
        self.thumbnailURL = thumbnailURL
        self.published = published
        self.isRead = isRead
    }
}
