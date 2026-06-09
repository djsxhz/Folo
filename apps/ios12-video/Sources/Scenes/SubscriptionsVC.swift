import UIKit

/// Home screen: the list of subscriptions. Tapping one opens its video list.
/// A "+" button in the navigation bar opens the add-subscription screen.
final class SubscriptionsVC: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGroupedCompat)
    private let store = SubscriptionStore.shared
    private let refreshControl = UIRefreshControl()

    private var subscriptions: [Subscription] { store.subscriptions }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "订阅"
        view.backgroundColor = Theme.groupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTapped)
        )

        setupTableView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: SubscriptionStore.didChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateBackgroundView()
    }

    private func setupTableView() {
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = Theme.groupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.register(SubscriptionCell.self, forCellReuseIdentifier: SubscriptionCell.reuseID)
        view.addSubview(tableView)

        refreshControl.addTarget(self, action: #selector(refreshAll), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    // MARK: - Actions

    @objc private func addTapped() {
        let addVC = AddSubscriptionVC()
        let nav = UINavigationController(rootViewController: addVC)
        Theme.apply(to: nav.navigationBar)
        present(nav, animated: true)
    }

    @objc private func storeDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
            self?.updateBackgroundView()
        }
    }

    /// Pull-to-refresh: fetch every subscription's feed.
    @objc private func refreshAll() {
        let subs = subscriptions
        guard !subs.isEmpty else {
            refreshControl.endRefreshing()
            return
        }
        let group = DispatchGroup()
        for sub in subs {
            group.enter()
            FeedService.fetchEntries(for: sub) { [weak self] result in
                if case .success(let parsed) = result {
                    self?.store.mergeEntries(parsed.entries, for: sub.id)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    private func updateBackgroundView() {
        if subscriptions.isEmpty {
            let label = UILabel()
            label.text = "还没有订阅\n点击右上角 + 添加 YouTube 或 Bilibili 频道"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = Theme.secondaryLabel
            label.font = .systemFont(ofSize: 15)
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }
}

extension SubscriptionsVC: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return subscriptions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionCell.reuseID, for: indexPath) as! SubscriptionCell
        let sub = subscriptions[indexPath.row]
        cell.configure(with: sub, unread: store.unreadCount(for: sub.id))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let sub = subscriptions[indexPath.row]
        let listVC = VideoListVC(subscription: sub)
        navigationController?.pushViewController(listVC, animated: true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let sub = subscriptions[indexPath.row]
        store.removeSubscription(id: sub.id)
    }

    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "删除"
    }
}
