import UIKit

/// Folo brand theme. Primary accent is Folo orange (#FF5C00).
enum Theme {
    /// Folo brand orange.
    static let accent = UIColor(red: 0xFF / 255.0, green: 0x5C / 255.0, blue: 0x00 / 255.0, alpha: 1.0)

    /// Adaptive primary background (white in light, black in dark).
    static var background: UIColor {
        if #available(iOS 13.0, *) { return .systemBackground }
        return .white
    }

    /// Adaptive grouped background used for list screens.
    static var groupedBackground: UIColor {
        if #available(iOS 13.0, *) { return .systemGroupedBackground }
        return UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
    }

    /// Adaptive secondary surface used for cards / cells.
    static var cardBackground: UIColor {
        if #available(iOS 13.0, *) { return .secondarySystemGroupedBackground }
        return .white
    }

    /// Primary label color.
    static var label: UIColor {
        if #available(iOS 13.0, *) { return .label }
        return .black
    }

    /// Secondary label color.
    static var secondaryLabel: UIColor {
        if #available(iOS 13.0, *) { return .secondaryLabel }
        return UIColor(white: 0.4, alpha: 1.0)
    }

    /// Separator color.
    static var separator: UIColor {
        if #available(iOS 13.0, *) { return .separator }
        return UIColor(white: 0.82, alpha: 1.0)
    }

    /// Apply Folo styling to a navigation bar.
    static func apply(to navigationBar: UINavigationBar) {
        navigationBar.tintColor = accent
        navigationBar.prefersLargeTitles = true

        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
        }
    }
}
