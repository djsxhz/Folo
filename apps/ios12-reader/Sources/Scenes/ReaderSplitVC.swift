import UIKit

/// iPad root: subscriptions and article list on the left, reader on the right.
/// Compact-width devices keep the regular single-column navigation path.
final class ReaderSplitVC: UISplitViewController {

    private let subscriptionsVC: SubscriptionsVC
    private let primaryNav: UINavigationController
    private let detailNav: UINavigationController

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        let subscriptionsVC = SubscriptionsVC()
        self.subscriptionsVC = subscriptionsVC
        primaryNav = UINavigationController(rootViewController: subscriptionsVC)
        detailNav = UINavigationController(rootViewController: EmptyReaderVC())
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        Theme.apply(to: primaryNav.navigationBar)
        Theme.apply(to: detailNav.navigationBar)
        primaryNav.navigationBar.prefersLargeTitles = false
        detailNav.navigationBar.prefersLargeTitles = false

        viewControllers = [primaryNav, detailNav]
        preferredDisplayMode = .allVisible
        preferredPrimaryColumnWidthFraction = 0.34
        minimumPrimaryColumnWidth = 320
        maximumPrimaryColumnWidth = 380
        delegate = self

        subscriptionsVC.navigationItem.largeTitleDisplayMode = .never
        subscriptionsVC.onSubscriptionSelected = { [weak self] subscription in
            self?.showArticles(for: subscription)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func showArticles(for subscription: Subscription) {
        let listVC = ArticleListVC(subscription: subscription, usesCompactLayout: true)
        listVC.automaticallySelectsFirstArticle = true
        listVC.onArticleSelected = { [weak self] entry in
            self?.showReader(entry: entry, subscription: subscription)
        }

        primaryNav.pushViewController(listVC, animated: true)

        if SubscriptionStore.shared.entries(for: subscription.id).isEmpty {
            showWaitingReader(subscriptionTitle: subscription.title)
        }
    }

    private func showReader(entry: ArticleEntry, subscription: Subscription) {
        let reader = ArticleReaderVC(
            entry: entry,
            subscriptionTitle: subscription.title,
            showsBackButton: false
        )
        detailNav.setViewControllers([reader], animated: false)
    }

    private func showWaitingReader(subscriptionTitle: String) {
        detailNav.setViewControllers(
            [EmptyReaderVC(message: "下拉刷新后选择文章", title: subscriptionTitle)],
            animated: false
        )
    }
}

extension ReaderSplitVC: UISplitViewControllerDelegate {
    func splitViewController(
        _ splitViewController: UISplitViewController,
        collapseSecondary secondaryViewController: UIViewController,
        onto primaryViewController: UIViewController
    ) -> Bool {
        return true
    }
}

private final class EmptyReaderVC: UIViewController {

    private let message: String

    init(message: String = "选择一篇文章开始阅读", title: String = "") {
        self.message = message
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.textAlignment = .center
        label.textColor = Theme.secondaryLabel
        label.font = .systemFont(ofSize: 17)
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
