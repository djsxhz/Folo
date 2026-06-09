import UIKit

/// A subscription row: platform-tinted icon, title, platform name, and an
/// unread-count badge in Folo orange.
final class SubscriptionCell: UITableViewCell {

    static let reuseID = "SubscriptionCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badge = BadgeView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = Theme.cardBackground
        accessoryType = .disclosureIndicator

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 8
        iconView.clipsToBounds = true
        contentView.addSubview(iconView)

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
        titleLabel.text = subscription.title.isEmpty ? subscription.platform.displayName : subscription.title
        subtitleLabel.text = subscription.platform.displayName
        badge.count = unread

        // Platform-tinted placeholder icon.
        let symbolName = "play.rectangle.fill"
        if #available(iOS 13.0, *), let image = UIImage(systemName: symbolName) {
            iconView.image = image
        } else {
            iconView.image = nil
            iconView.backgroundColor = subscription.platform == .youtube
                ? UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
                : UIColor(red: 0.0, green: 0.63, blue: 0.84, alpha: 1.0)
        }
        iconView.tintColor = subscription.platform == .youtube
            ? UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
            : UIColor(red: 0.0, green: 0.63, blue: 0.84, alpha: 1.0)

        // Load remote icon if available.
        if let iconURL = subscription.iconURL {
            ImageLoader.shared.load(iconURL) { [weak self] image in
                if let image = image { self?.iconView.image = image }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        iconView.backgroundColor = .clear
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
