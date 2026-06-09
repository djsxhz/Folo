import UIKit

/// A single video row: thumbnail, title, relative date, and an unread dot.
final class VideoCell: UITableViewCell {
    static let reuseID = "VideoCell"

    private let thumbnail = UIImageView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let unreadDot = UIView()

    /// The thumbnail URL this cell is currently loading, used to guard against
    /// stale completions when cells are recycled.
    private var thumbnailURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        backgroundColor = Theme.background

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 6
        thumbnail.backgroundColor = Theme.separator
        contentView.addSubview(thumbnail)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = Theme.label
        contentView.addSubview(titleLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = Theme.secondaryLabel
        contentView.addSubview(dateLabel)

        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.backgroundColor = Theme.accent
        unreadDot.layer.cornerRadius = 4
        contentView.addSubview(unreadDot)

        // Thumbnail keeps a 16:9 aspect ratio, ~140pt wide.
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 140),
            thumbnail.heightAnchor.constraint(equalToConstant: 78),

            unreadDot.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 10),
            unreadDot.centerYAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: -4),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.leadingAnchor.constraint(equalTo: unreadDot.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 2),

            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            dateLabel.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 4),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: thumbnail.bottomAnchor),
        ])
    }

    func configure(with entry: VideoEntry) {
        titleLabel.text = entry.title
        dateLabel.text = Self.relativeDate(entry.published)
        unreadDot.isHidden = entry.isRead

        // Read entries get dimmed titles, like Folo's read state.
        titleLabel.textColor = entry.isRead ? Theme.secondaryLabel : Theme.label

        thumbnail.image = nil
        thumbnailURL = entry.thumbnailURL
        if let urlString = entry.thumbnailURL {
            ImageLoader.shared.load(urlString) { [weak self] image in
                // Guard against cell reuse: only apply if still the same URL.
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// A compact relative date string (e.g. "3 天前"), falling back to an absolute date.
    private static func relativeDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
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
