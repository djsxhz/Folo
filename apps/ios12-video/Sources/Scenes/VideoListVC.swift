import UIKit

/// Video grid for a single subscription. Supports:
/// - pull-to-refresh,
/// - "unread only" toggle,
/// - "mark all as read",
/// and opens the player on tap (marking the entry read).
final class VideoListVC: UIViewController {

    private let subscription: Subscription
    private let store = SubscriptionStore.shared
    private let refreshControl = UIRefreshControl()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 22
        layout.minimumInteritemSpacing = 18
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.background
        view.alwaysBounceVertical = true
        view.dataSource = self
        view.delegate = self
        view.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseID)
        return view
    }()

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
        setupCollectionView()

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
        collectionView.reloadData()
        updateBackgroundView()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func setupNavigationItems() {
        let markAll = UIBarButtonItem(
            image: nil,
            style: .plain,
            target: self,
            action: #selector(markAllReadTapped)
        )
        markAll.title = "\u{5168}\u{90E8}\u{5DF2}\u{8BFB}"

        navigationItem.rightBarButtonItems = [markAll, unreadToggleItem()]
    }

    private func unreadToggleItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: unreadOnly ? "\u{663E}\u{793A}\u{5168}\u{90E8}" : "\u{4EC5}\u{672A}\u{8BFB}",
            style: .plain,
            target: self,
            action: #selector(toggleUnreadOnly)
        )
        return item
    }

    private func setupCollectionView() {
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)

        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl
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
        collectionView.reloadData()
        updateBackgroundView()
    }

    @objc private func markAllReadTapped() {
        store.markAllRead(in: subscription.id)
    }

    @objc private func storeDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.collectionView.reloadData()
            self?.updateBackgroundView()
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        present(alert, animated: true)
    }

    private func updateBackgroundView() {
        if displayedEntries.isEmpty {
            let label = UILabel()
            label.text = unreadOnly
                ? "\u{6CA1}\u{6709}\u{672A}\u{8BFB}\u{89C6}\u{9891}"
                : "\u{8FD8}\u{6CA1}\u{6709}\u{89C6}\u{9891}\u{FF0C}\u{4E0B}\u{62C9}\u{5237}\u{65B0}"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = Theme.secondaryLabel
            label.font = .systemFont(ofSize: 15)
            collectionView.backgroundView = label
        } else {
            collectionView.backgroundView = nil
        }
    }
}

extension VideoListVC: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return displayedEntries.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseID, for: indexPath) as! VideoCell
        cell.configure(with: displayedEntries[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let entry = displayedEntries[indexPath.item]
        store.markRead(entryID: entry.id, in: subscription.id)

        let player = VideoPlayerVC(entry: entry, platform: subscription.platform)
        player.modalPresentationStyle = .fullScreen
        present(player, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        return UIEdgeInsets(top: 14, left: 18, bottom: 24, right: 18)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let insets = self.collectionView(collectionView, layout: collectionViewLayout, insetForSectionAt: 0)
        let available = collectionView.bounds.width - insets.left - insets.right
        let columns = max(1, min(5, Int(available / 240)))
        let spacing = CGFloat(columns - 1) * 18
        let width = floor((available - spacing) / CGFloat(columns))
        let height = floor(width * 9.0 / 16.0) + 58
        return CGSize(width: width, height: height)
    }
}
