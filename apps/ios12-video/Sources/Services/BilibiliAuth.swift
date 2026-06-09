import Foundation
import WebKit

/// Tracks Bilibili login state.
///
/// We rely on `WKWebsiteDataStore.default()` (the persistent, shared cookie
/// store). The login screen and the video player both use this same store, so
/// once the user logs in, the `SESSDATA` cookie is automatically sent to
/// `player.bilibili.com` and survives app relaunches — no Keychain or manual
/// cookie injection required.
///
/// Login is optional: without it Bilibili caps playback at 360P/480P; with a
/// valid `SESSDATA` cookie the player can request 720P/1080P.
enum BilibiliAuth {
    /// Bilibili domains whose cookies carry the login session.
    static let cookieDomain = ".bilibili.com"

    /// The cookie that proves an active login session.
    static let sessionCookieName = "SESSDATA"

    /// Posted (on the main queue) whenever login state changes.
    static let didChangeNotification = Notification.Name("BilibiliAuthDidChange")

    /// Checks whether a `SESSDATA` cookie currently exists in the shared store.
    /// Asynchronous because `WKHTTPCookieStore` is async.
    static func isLoggedIn(_ completion: @escaping (Bool) -> Void) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            let loggedIn = cookies.contains { cookie in
                cookie.name == sessionCookieName &&
                cookie.domain.contains("bilibili.com") &&
                !cookie.value.isEmpty
            }
            DispatchQueue.main.async { completion(loggedIn) }
        }
    }

    /// Removes all Bilibili cookies and website data, logging the user out.
    static func logout(_ completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        let cookieStore = store.httpCookieStore
        cookieStore.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies where cookie.domain.contains("bilibili.com") {
                group.enter()
                cookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                // Also clear cached site data so a fresh login starts clean.
                let types: Set<String> = [
                    WKWebsiteDataTypeCookies,
                    WKWebsiteDataTypeLocalStorage,
                    WKWebsiteDataTypeSessionStorage,
                ]
                store.fetchDataRecords(ofTypes: types) { records in
                    let biliRecords = records.filter { $0.displayName.contains("bilibili") }
                    store.removeData(ofTypes: types, for: biliRecords) {
                        NotificationCenter.default.post(name: didChangeNotification, object: nil)
                        completion()
                    }
                }
            }
        }
    }

    /// Notifies observers that login state may have changed (e.g. after the
    /// login screen detects a successful sign-in).
    static func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
