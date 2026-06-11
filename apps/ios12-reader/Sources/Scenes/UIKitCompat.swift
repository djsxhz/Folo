import UIKit

extension UITableView.Style {
    /// `.insetGrouped` on iOS 13+, falling back to `.grouped` on iOS 12.
    static var insetGroupedCompat: UITableView.Style {
        if #available(iOS 13.0, *) { return .insetGrouped }
        return .grouped
    }
}

extension UIView {
    /// `safeAreaLayoutGuide` on iOS 11+. Available on iOS 12, so this is a
    /// thin alias kept for naming clarity across the codebase.
    var safeAreaLayoutGuideCompat: UILayoutGuide {
        return safeAreaLayoutGuide
    }
}
