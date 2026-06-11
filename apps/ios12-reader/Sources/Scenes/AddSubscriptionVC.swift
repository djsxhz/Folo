import UIKit

/// Add-subscription screen. Paste any http(s) RSS/Atom URL or a `rsshub://` route.
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
        textField.placeholder = "粘贴 RSS / Atom 链接或 rsshub:// 路由"
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
        • https:// 开头的 RSS / Atom 源
        • http:// 开头的本地 / 局域网源(如自建 FreshRSS、本地 RSSHub)
        • rsshub:// 路由(如 rsshub://github/issues/owner/repo),将按设置中的 RSSHub 实例展开
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
        FeedService.probeMetadata(feedURL: resolved.feedURL) { [weak self] metadata in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setLoading(false)

                let fallbackTitle = URL(string: resolved.feedURL)?.host ?? "订阅"
                let resolvedTitle = (metadata.title?.isEmpty == false) ? metadata.title! : fallbackTitle
                let sub = Subscription(
                    title: resolvedTitle,
                    feedURL: resolved.feedURL,
                    iconURL: metadata.iconURL
                )
                self.store.addSubscription(sub)

                FeedService.fetchEntries(for: sub) { result in
                    if case .success(let parsed) = result {
                        self.store.mergeEntries(parsed.entries, for: sub.id)
                        self.store.updateIconURL(parsed.feedIconURL, for: sub.id)
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
