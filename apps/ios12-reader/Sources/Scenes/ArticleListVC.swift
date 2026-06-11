import UIKit

/// Article list for a single subscription. Supports pull-to-refresh, an
/// "unread only" filter, "mark all as read", and opens the reader on tap
/// (marking the entry read).
final class ArticleListVC: UIViewController {

    private let subscription: Subscription
    private let usesCompactLayout: Bool
    private let store = SubscriptionStore.shared
    private let refreshControl = UIRefreshControl()

    private let tableView = UITableView(frame: .zero, style: .plain)

    private var unreadOnly = false
    private var selectedEntryID: String?
    private var didAutoSelectInitialArticle = false

    var onArticleSelected: ((ArticleEntry) -> Void)?
    var automaticallySelectsFirstArticle = false

    private var displayedEntries: [ArticleEntry] {
        let all = store.entries(for: subscription.id)
        return unreadOnly ? all.filter { !$0.isRead } : all
    }

    init(subscription: Subscription, usesCompactLayout: Bool = false) {
        self.subscription = subscription
        self.usesCompactLayout = usesCompactLayout
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = subscription.title
        if usesCompactLayout {
            navigationItem.largeTitleDisplayMode = .never
        }
        view.backgroundColor = Theme.background

        setupNavigationItems()
        setupTableView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: SubscriptionStore.didChangeNotification,
            object: nil
        )

        if store.entries(for: subscription.id).isEmpty {
            refresh()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadTablePreservingSelection()
        updateBackgroundView()
        selectInitialArticleIfNeeded()
    }

    private func setupNavigationItems() {
        let markAll = UIBarButtonItem(
            title: "全部已读",
            style: .plain,
            target: self,
            action: #selector(markAllReadTapped)
        )
        navigationItem.rightBarButtonItems = [markAll, unreadToggleItem()]
    }

    private func unreadToggleItem() -> UIBarButtonItem {
        return UIBarButtonItem(
            title: unreadOnly ? "显示全部" : "仅未读",
            style: .plain,
            target: self,
            action: #selector(toggleUnreadOnly)
        )
    }

    private func setupTableView() {
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.estimatedRowHeight = usesCompactLayout ? 96 : 110
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(ArticleCell.self, forCellReuseIdentifier: ArticleCell.reuseID)
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
                    self.store.updateIconURL(parsed.feedIconURL, for: self.subscription.id)
                case .failure(let error):
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func toggleUnreadOnly() {
        unreadOnly.toggle()
        navigationItem.rightBarButtonItems = [navigationItem.rightBarButtonItems![0], unreadToggleItem()]
        reloadTablePreservingSelection()
        updateBackgroundView()
        selectInitialArticleIfNeeded()
    }

    @objc private func markAllReadTapped() {
        store.markAllRead(in: subscription.id)
    }

    @objc private func storeDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.reloadTablePreservingSelection()
            self.updateBackgroundView()
            self.selectInitialArticleIfNeeded()
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func updateBackgroundView() {
        if displayedEntries.isEmpty {
            let label = UILabel()
            label.text = unreadOnly ? "没有未读文章" : "还没有文章,下拉刷新"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = Theme.secondaryLabel
            label.font = .systemFont(ofSize: 15)
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    private func reloadTablePreservingSelection() {
        tableView.reloadData()
        guard let selectedEntryID = selectedEntryID,
              let row = displayedEntries.firstIndex(where: { $0.id == selectedEntryID })
        else {
            selectedEntryID = nil
            return
        }
        tableView.selectRow(
            at: IndexPath(row: row, section: 0),
            animated: false,
            scrollPosition: .none
        )
    }

    private func selectInitialArticleIfNeeded() {
        guard automaticallySelectsFirstArticle,
              onArticleSelected != nil,
              !didAutoSelectInitialArticle,
              selectedEntryID == nil,
              let first = displayedEntries.first
        else { return }

        didAutoSelectInitialArticle = true
        selectEntry(first, animated: false)
    }

    private func selectEntry(_ entry: ArticleEntry, animated: Bool) {
        store.markRead(entryID: entry.id, in: subscription.id)

        if let onArticleSelected = onArticleSelected {
            selectedEntryID = entry.id
            if let row = displayedEntries.firstIndex(where: { $0.id == entry.id }) {
                tableView.selectRow(
                    at: IndexPath(row: row, section: 0),
                    animated: animated,
                    scrollPosition: .none
                )
            }
            onArticleSelected(entry)
            return
        }

        let reader = ArticleReaderVC(entry: entry, subscriptionTitle: subscription.title)
        navigationController?.pushViewController(reader, animated: true)
    }
}

extension ArticleListVC: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ArticleCell.reuseID, for: indexPath) as! ArticleCell
        cell.configure(with: displayedEntries[indexPath.row], compact: usesCompactLayout)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = displayedEntries[indexPath.row]
        if onArticleSelected == nil {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        selectEntry(entry, animated: true)
    }
}
