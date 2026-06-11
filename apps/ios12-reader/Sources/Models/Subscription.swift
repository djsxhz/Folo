import Foundation

/// A single article-feed subscription (any RSS / Atom source).
struct Subscription: Codable, Equatable {
    /// Stable unique identifier.
    let id: String
    /// User-facing title (feed title or user-edited name).
    var title: String
    /// The RSS / Atom feed URL used to fetch entries.
    let feedURL: String
    /// Optional site / channel icon URL.
    var iconURL: String?
    /// When the subscription was added (used for stable ordering).
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        feedURL: String,
        iconURL: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.iconURL = iconURL
        self.createdAt = createdAt
    }
}
