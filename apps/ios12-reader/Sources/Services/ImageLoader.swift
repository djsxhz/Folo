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
        cache.totalCostLimit = 16 * 1024 * 1024 // ~16 MB

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 32 * 1024 * 1024,
            diskPath: "rolo_img"
        )
        session = URLSession(configuration: config)
    }

    /// Loads an image for `urlString`. The completion is always called on the
    /// main thread. Returns the underlying data task so callers can cancel it
    /// when a cell is reused.
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

        let task = session.dataTask(with: URLRequest(url: url)) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.cache.setObject(image, forKey: key, cost: data.count)
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }
}
