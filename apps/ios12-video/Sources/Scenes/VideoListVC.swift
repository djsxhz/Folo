import UIKit

/// Video list for a single subscription. Supports:
/// - pull-to-refresh,
/// - "unread only" toggle,
/// - "mark all as read",
/// and opens the player on tap (marking the entry read).
final class VideoListVC: UIViewController {

    private let subscription: Subscription
    private let store = SubscriptionStore.shared
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()

    /// When true, only unread entries are shown.
    private var unreadOnly = false

    private var displayedEntries: [VideoEntry] {
        let all = store.entries(for: subscription.id)
        return unreadOnly ? all.filter { !$0.isRead } : all
    }

    init(subscription: Subscription) {
        self.subscription = subscription
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = subscription.title
        view.backgroundColor = Theme.background

        setupNavigationItems()
        setupTableView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: SubscriptionStore.didChangeNotification,
            object: nil
        )

        // Fetch on first appearance if we have nothing yet.
        if store.entries(for: subscription.id).isEmpty {
            refresh()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func setupNavigationItems() {
        let markAll = UIBarButtonItem(
            image: nil,
            style: .plain,
            target: self,
            action: #selector(markAllReadTapped)
        )
        markAll.title = "全部已读"

        navigationItem.rightBarButtonItems = [markAll, unreadToggleItem()]
    }

    private func unreadToggleItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: unreadOnly ? "显示全部" : "仅未读",
            style: .plain,
            target: self,
            action: #selector(toggleUnreadOnly)
        )
        return item
    }

    private func setupTableView() {
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 94
        tableView.separatorColor = Theme.separator
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.reuseID)
        view.addSubview(tableView)

        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    // MARK: - Actions

    @objc private func refresh() {
        FeedService.fetchEntries(for: subscription) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshControl.endRefreshing()
                switch result {
                case .success(let parsed):
                    self.store.mergeEntries(parsed.entries, for: self.subscription.id)
                case .failure(let error):
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func toggleUnreadOnly() {
        unreadOnly.toggle()
        navigationItem.rightBarButtonItems = [navigationItem.rightBarButtonItems![0], unreadToggleItem()]
        tableView.reloadData()
    }

    @objc private func markAllReadTapped() {
        store.markAllRead(in: subscription.id)
    }

    @objc private func storeDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension VideoListVC: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.reuseID, for: indexPath) as! VideoCell
        cell.configure(with: displayedEntries[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = displayedEntries[indexPath.row]
        store.markRead(entryID: entry.id, in: subscription.id)

        let player = VideoPlayerVC(entry: entry, platform: subscription.platform)
        let nav = UINavigationController(rootViewController: player)
        nav.modalPresentationStyle = .fullScreen
        Theme.apply(to: nav.navigationBar)
        present(nav, animated: true)
    }
}
