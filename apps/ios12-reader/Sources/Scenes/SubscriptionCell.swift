import UIKit

/// A subscription row: icon (with fallback initial), title, host, unread badge.
final class SubscriptionCell: UITableViewCell {

    static let reuseID = "SubscriptionCell"

    private let iconView = UIImageView()
    private let fallbackLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badge = BadgeView()

    private var iconTask: URLSessionDataTask?
    private var iconURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = Theme.cardBackground
        accessoryType = .disclosureIndicator

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 8
        iconView.clipsToBounds = true
        contentView.addSubview(iconView)

        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.font = .systemFont(ofSize: 16, weight: .bold)
        fallbackLabel.textColor = .white
        fallbackLabel.textAlignment = .center
        iconView.addSubview(fallbackLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = Theme.label
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = Theme.secondaryLabel
        contentView.addSubview(subtitleLabel)

        badge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            fallbackLabel.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            fallbackLabel.trailingAnchor.constraint(equalTo: iconView.trailingAnchor),
            fallbackLabel.topAnchor.constraint(equalTo: iconView.topAnchor),
            fallbackLabel.bottomAnchor.constraint(equalTo: iconView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            badge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(with subscription: Subscription, unread: Int) {
        let title = subscription.title.isEmpty ? Self.host(for: subscription.feedURL) : subscription.title
        titleLabel.text = title
        subtitleLabel.text = Self.host(for: subscription.feedURL)
        badge.count = unread

        iconTask?.cancel()
        iconView.image = nil
        iconView.backgroundColor = Theme.accent
        fallbackLabel.text = Self.initial(from: title)
        fallbackLabel.isHidden = false

        iconURL = subscription.iconURL
        if let iconURL = subscription.iconURL {
            iconTask = ImageLoader.shared.load(iconURL) { [weak self] image in
                guard let self = self, self.iconURL == iconURL else { return }
                if let image = image {
                    self.iconView.image = image
                    self.fallbackLabel.isHidden = true
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconTask?.cancel()
        iconTask = nil
        iconURL = nil
        iconView.image = nil
        iconView.backgroundColor = .clear
        fallbackLabel.isHidden = true
    }

    private static func host(for feedURL: String) -> String {
        guard let url = URL(string: feedURL), let host = url.host else { return feedURL }
        return host
    }

    private static func initial(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

/// A small pill badge showing an unread count in Folo orange.
final class BadgeView: UIView {
    private let label = UILabel()

    var count: Int = 0 {
        didSet { update() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.accent
        layer.cornerRadius = 10
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 20),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func update() {
        isHidden = count <= 0
        label.text = count > 99 ? "99+" : "\(count)"
    }
}
