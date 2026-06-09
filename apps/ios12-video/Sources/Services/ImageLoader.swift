import UIKit

/// A minimal async image loader with a bounded in-memory cache.
///
/// Tuned for the iPad Air 1 (1GB RAM): the cache is capped by both count and
/// total cost so thumbnails never accumulate without bound. No disk cache —
/// `URLSession`'s own URL cache handles HTTP-level reuse.
final class ImageLoader {

    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 80
        // ~16 MB worth of decoded thumbnails, approximated by byte cost below.
        cache.totalCostLimit = 16 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024, diskPath: "flo_img")
        session = URLSession(configuration: config)
    }

    /// Loads an image for `urlString`. The completion is always called on the
    /// main thread. Returns a token (the data task) so callers can cancel when
    /// a cell is reused.
    @discardableResult
    func load(_ urlString: String?, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            completion(nil)
            return nil
        }
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return nil
        }

        let task = session.dataTask(with: Self.request(for: url)) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let cost = data.count
            self?.cache.setObject(image, forKey: key, cost: cost)
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let host = url.host?.lowercased(), host.contains("hdslb.com") {
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        }
        request.setValue("Mozilla/5.0 (compatible; Flo/1.0)", forHTTPHeaderField: "User-Agent")
        return request
    }
}
