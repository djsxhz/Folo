import Foundation

/// The video platform a subscription belongs to.
enum Platform: String, Codable {
    case youtube
    case bilibili

    /// Display name shown in the UI.
    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .bilibili: return "Bilibili"
        }
    }
}

/// A single video subscription (a YouTube channel or a Bilibili UP host).
struct Subscription: Codable, Equatable {
    /// Stable unique identifier.
    let id: String
    /// User-facing title (channel / UP name). Falls back to the feed title.
    var title: String
    /// Which platform this subscription targets.
    let platform: Platform
    /// The RSS/Atom feed URL used to fetch entries.
    let feedURL: String
    /// Optional avatar / icon URL for the subscription.
    var iconURL: String?
    /// When the subscription was added (used for stable ordering).
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        platform: Platform,
        feedURL: String,
        iconURL: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.platform = platform
        self.feedURL = feedURL
        self.iconURL = iconURL
        self.createdAt = createdAt
    }
}
