import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Spoof User-Agent to make websites think we're on iOS 16.
        // This prevents YouTube/Bilibili from serving degraded experiences
        // for older devices.
        let modernUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"
        UserDefaults.standard.register(defaults: ["UserAgent": modernUA])

        let window = UIWindow(frame: UIScreen.main.bounds)

        let root = SubscriptionsVC()
        let nav = UINavigationController(rootViewController: root)
        Theme.apply(to: nav.navigationBar)

        window.rootViewController = nav
        if #available(iOS 13.0, *) {
            window.backgroundColor = .systemBackground
        } else {
            window.backgroundColor = .white
        }
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
