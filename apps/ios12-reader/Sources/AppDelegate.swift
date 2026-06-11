import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)

        let rootViewController: UIViewController
        if UIDevice.current.userInterfaceIdiom == .pad {
            rootViewController = ReaderSplitVC(nibName: nil, bundle: nil)
        } else {
            let root = SubscriptionsVC()
            let nav = UINavigationController(rootViewController: root)
            Theme.apply(to: nav.navigationBar)
            rootViewController = nav
        }

        window.rootViewController = rootViewController
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
