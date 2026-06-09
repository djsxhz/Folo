import UIKit

/// Add-subscription screen. The user pastes a YouTube channel URL / channel id
/// or a Bilibili UP host URL / UID. The platform is detected automatically.
final class AddSubscriptionVC: UIViewController {

    private let store = SubscriptionStore.shared

    private let textField = UITextField()
    private let hintLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .gray)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "添加订阅"
        view.backgroundColor = Theme.groupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    private func setupUI() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "粘贴 RSS / YouTube / Bilibili 链接"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.delegate = self
        textField.backgroundColor = Theme.cardBackground
        textField.textColor = Theme.label
        view.addSubview(textField)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.numberOfLines = 0
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = Theme.secondaryLabel
        hintLabel.text = """
        支持的格式:
        • 任意 RSS / Atom 源地址(http 或 https 开头)
        • rsshub:// 路由(如 rsshub://youtube/user/@handle)
        • YouTube 频道链接(.../channel/UC...)或频道 ID(UC 开头)
        • Bilibili UP 主空间链接(space.bilibili.com/UID)或 UID

        RSSHub 路由与 Bilibili 通过 RSSHub 实例获取,可在设置中更换实例。
        """
        view.addSubview(hintLabel)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("添加", for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.backgroundColor = Theme.accent
        addButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        addButton.layer.cornerRadius = 10
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        view.addSubview(addButton)

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.hidesWhenStopped = true
        view.addSubview(activity)

        let guide = view.safeAreaLayoutGuideCompat
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: guide.topAnchor, constant: 20),
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textField.heightAnchor.constraint(equalToConstant: 44),

            hintLabel.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            addButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 24),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            addButton.heightAnchor.constraint(equalToConstant: 50),

            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 24),
        ])
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func addTapped() {
        view.endEditing(true)
        let input = textField.text ?? ""
        guard let resolved = FeedService.resolve(input: input) else {
            showAlert(message: FeedService.FeedError.invalidInput.localizedDescription)
            return
        }

        if store.contains(feedURL: resolved.feedURL) {
            showAlert(message: "该订阅已存在")
            return
        }

        setLoading(true)
        // Probe the feed for its title so the subscription has a friendly name.
        FeedService.probeTitle(platform: resolved.platform, feedURL: resolved.feedURL) { [weak self] title in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setLoading(false)

                let resolvedTitle = (title?.isEmpty == false) ? title! : resolved.platform.displayName
                let sub = Subscription(
                    title: resolvedTitle,
                    platform: resolved.platform,
                    feedURL: resolved.feedURL
                )
                self.store.addSubscription(sub)

                // Fetch its entries in the background; the home screen will refresh.
                FeedService.fetchEntries(for: sub) { result in
                    if case .success(let parsed) = result {
                        self.store.mergeEntries(parsed.entries, for: sub.id)
                    }
                }

                self.dismiss(animated: true)
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            activity.startAnimating()
            addButton.isEnabled = false
            addButton.alpha = 0.5
        } else {
            activity.stopAnimating()
            addButton.isEnabled = true
            addButton.alpha = 1.0
        }
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension AddSubscriptionVC: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        addTapped()
        return true
    }
}
