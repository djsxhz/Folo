import Foundation

/// Persists subscriptions and their video entries (including read state) to JSON
/// files in the app's Documents directory.
///
/// Designed to be lightweight for the iPad Air 1 (1 GB RAM): everything is kept
/// in memory as small arrays and flushed to disk on change. The data set is
/// expected to be small (a handful of subscriptions, dozens of entries each).
final class SubscriptionStore {

    static let shared = SubscriptionStore()

    /// Posted whenever subscriptions or entries change, so view controllers can refresh.
    static let didChangeNotification = Notification.Name("SubscriptionStoreDidChange")

    private let queue = DispatchQueue(label: "com.flo.store", qos: .utility)

    private(set) var subscriptions: [Subscription] = []
    /// Entries keyed by subscription id.
    private var entriesBySubscription: [String: [VideoEntry]] = [:]

    private let subscriptionsURL: URL
    private let entriesURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        subscriptionsURL = docs.appendingPathComponent("subscriptions.json")
        entriesURL = docs.appendingPathComponent("entries.json")
        load()
    }

    // MARK: - Loading / Saving

    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: subscriptionsURL),
            let list = try? decoder.decode([Subscription].self, from: data)
        {
            subscriptions = list
        }
        if let data = try? Data(contentsOf: entriesURL),
            let map = try? decoder.decode([String: [VideoEntry]].self, from: data)
        {
            entriesBySubscription = map
        }
    }

    private func persistSubscriptions() {
        let snapshot = subscriptions
        let url = subscriptionsURL
        queue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func persistEntries() {
        let snapshot = entriesBySubscription
        let url = entriesURL
        queue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: SubscriptionStore.didChangeNotification, object: nil)
    }

    // MARK: - Subscriptions

    /// Whether a feed URL is already subscribed.
    func contains(feedURL: String) -> Bool {
        return subscriptions.contains { $0.feedURL == feedURL }
    }

    func addSubscription(_ subscription: Subscription) {
        guard !contains(feedURL: subscription.feedURL) else { return }
        subscriptions.append(subscription)
        persistSubscriptions()
        notifyChange()
    }

    func removeSubscription(id: String) {
        subscriptions.removeAll { $0.id == id }
        entriesBySubscription[id] = nil
        persistSubscriptions()
        persistEntries()
        notifyChange()
    }

    func updateSubscription(_ subscription: Subscription) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
        subscriptions[index] = subscription
        persistSubscriptions()
        notifyChange()
    }

    // MARK: - Entries

    func entries(for subscriptionID: String) -> [VideoEntry] {
        return entriesBySubscription[subscriptionID] ?? []
    }

    func unreadCount(for subscriptionID: String) -> Int {
        return entries(for: subscriptionID).reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    /// Merges freshly fetched entries with stored ones, preserving read state and
    /// keeping the newest entries first. New entries default to unread.
    func mergeEntries(_ fetched: [VideoEntry], for subscriptionID: String) {
        var existing = entriesBySubscription[subscriptionID] ?? []
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var merged: [VideoEntry] = []
        var seen = Set<String>()

        for var entry in fetched {
            if let prior = existingByID[entry.id] {
                entry.isRead = prior.isRead
            }
            merged.append(entry)
            seen.insert(entry.id)
        }

        // Keep older stored entries that are no longer in the feed window.
        for entry in existing where !seen.contains(entry.id) {
            merged.append(entry)
        }

        merged.sort { lhs, rhs in
            (lhs.published ?? .distantPast) > (rhs.published ?? .distantPast)
        }

        existing = merged
        entriesBySubscription[subscriptionID] = existing
        persistEntries()
        notifyChange()
    }

    func markRead(entryID: String, in subscriptionID: String, read: Bool = true) {
        guard var list = entriesBySubscription[subscriptionID],
            let index = list.firstIndex(where: { $0.id == entryID })
        else { return }
        guard list[index].isRead != read else { return }
        list[index].isRead = read
        entriesBySubscription[subscriptionID] = list
        persistEntries()
        notifyChange()
    }

    func markAllRead(in subscriptionID: String) {
        guard var list = entriesBySubscription[subscriptionID] else { return }
        var changed = false
        for index in list.indices where !list[index].isRead {
            list[index].isRead = true
            changed = true
        }
        guard changed else { return }
        entriesBySubscription[subscriptionID] = list
        persistEntries()
        notifyChange()
    }
}
