import UIKit

/// A Folo-like video card: large 16:9 thumbnail, title, relative date, and an
/// unread dot. Used in the video grid.
final class VideoCell: UICollectionViewCell {
    static let reuseID = "VideoCell"

    private let thumbnail = UIImageView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let unreadDot = UIView()

    private var thumbnailURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        backgroundColor = Theme.background
        contentView.backgroundColor = Theme.background

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 4
        thumbnail.backgroundColor = Theme.separator
        contentView.addSubview(thumbnail)

        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.backgroundColor = Theme.accent
        unreadDot.layer.cornerRadius = 4
        contentView.addSubview(unreadDot)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = Theme.label
        contentView.addSubview(titleLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = Theme.secondaryLabel
        contentView.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),

            unreadDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            unreadDot.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 11),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: unreadDot.trailingAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    func configure(with entry: VideoEntry) {
        titleLabel.text = entry.title
        dateLabel.text = Self.relativeDate(entry.published)
        unreadDot.isHidden = entry.isRead

        titleLabel.textColor = entry.isRead ? Theme.secondaryLabel : Theme.label

        thumbnail.image = nil
        thumbnailURL = entry.thumbnailURL
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func relativeDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "\u{521A}\u{521A}" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) \u{5206}\u{949F}\u{524D}" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) \u{5C0F}\u{65F6}\u{524D}" }
        let days = hours / 24
        if days < 30 { return "\(days) \u{5929}\u{524D}" }
        return dateFormatter.string(from: date)
    }
}
