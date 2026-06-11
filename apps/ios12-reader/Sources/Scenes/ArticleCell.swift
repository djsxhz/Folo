import UIKit

/// A row in the article list: thumbnail (optional), title, summary, meta line
/// (author / relative date), and an unread dot.
final class ArticleCell: UITableViewCell {
    static let reuseID = "ArticleCell"

    private let thumbnail = UIImageView()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let metaLabel = UILabel()
    private let unreadDot = UIView()

    private var thumbnailURL: String?
    private var thumbnailWidth: NSLayoutConstraint!
    private var thumbnailLeading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        backgroundColor = Theme.cardBackground
        selectionStyle = .default

        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.backgroundColor = Theme.accent
        unreadDot.layer.cornerRadius = 4
        contentView.addSubview(unreadDot)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = Theme.label
        contentView.addSubview(titleLabel)

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.numberOfLines = 2
        summaryLabel.font = .systemFont(ofSize: 13)
        summaryLabel.textColor = Theme.secondaryLabel
        contentView.addSubview(summaryLabel)

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.numberOfLines = 1
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = Theme.secondaryLabel
        contentView.addSubview(metaLabel)

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 6
        thumbnail.backgroundColor = Theme.separator
        contentView.addSubview(thumbnail)

        thumbnailWidth = thumbnail.widthAnchor.constraint(equalToConstant: 88)
        thumbnailLeading = thumbnail.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12)

        NSLayoutConstraint.activate([
            unreadDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            unreadDot.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.leadingAnchor.constraint(equalTo: unreadDot.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            summaryLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 6),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metaLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            thumbnail.heightAnchor.constraint(equalToConstant: 66),
            thumbnailWidth,
            thumbnailLeading,
        ])
    }

    func configure(with entry: ArticleEntry) {
        titleLabel.text = entry.title
        titleLabel.textColor = entry.isRead ? Theme.secondaryLabel : Theme.label
        summaryLabel.text = entry.summary
        summaryLabel.isHidden = (entry.summary?.isEmpty ?? true)
        metaLabel.text = Self.metaText(for: entry)
        unreadDot.isHidden = entry.isRead

        thumbnail.image = nil
        thumbnailURL = entry.thumbnailURL
        let hasThumbnail = entry.thumbnailURL != nil
        thumbnail.isHidden = !hasThumbnail
        thumbnailWidth.constant = hasThumbnail ? 88 : 0
        thumbnailLeading.constant = hasThumbnail ? 12 : 0

        if let urlString = entry.thumbnailURL {
            ImageLoader.shared.load(urlString) { [weak self] image in
                guard let self = self, self.thumbnailURL == urlString else { return }
                self.thumbnail.image = image
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnail.image = nil
        thumbnailURL = nil
    }

    private static func metaText(for entry: ArticleEntry) -> String {
        var parts: [String] = []
        if let author = entry.author, !author.isEmpty { parts.append(author) }
        if let relative = relativeDate(entry.published) { parts.append(relative) }
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func relativeDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "刚刚" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        if days < 30 { return "\(days) 天前" }
        return dateFormatter.string(from: date)
    }
}
