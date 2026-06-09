import UIKit

/// Minimal settings screen. Its only job today is the optional Bilibili login,
/// which unlocks higher playback resolutions (720P/1080P) by carrying a
/// `SESSDATA` cookie into the embedded player.
final class SettingsVC: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGroupedCompat)
    private var loggedIn = false

    /// `UIColor.systemRed` is iOS 13+. Use a fixed red so the destructive
    /// "log out" row renders correctly on the iOS 12 deployment target.
    private static let destructiveRed: UIColor = {
        if #available(iOS 13.0, *) { return .systemRed }
        return UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        view.backgroundColor = Theme.groupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        setupTableView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authDidChange),
            name: BilibiliAuth.didChangeNotification,
            object: nil
        )

        refreshLoginState()
    }

    private func setupTableView() {
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = Theme.groupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
    }

    private func refreshLoginState() {
        BilibiliAuth.isLoggedIn { [weak self] loggedIn in
            self?.loggedIn = loggedIn
            self?.tableView.reloadData()
        }
    }

    @objc private func authDidChange() {
        refreshLoginState()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func presentLogin() {
        let loginVC = BilibiliLoginVC()
        loginVC.onLogin = { [weak self] in
            self?.refreshLoginState()
        }
        let nav = UINavigationController(rootViewController: loginVC)
        Theme.apply(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func confirmLogout() {
        let alert = UIAlertController(
            title: "退出登录",
            message: "退出后 Bilibili 将回到未登录画质上限（360P/480P）。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
            BilibiliAuth.logout { self?.refreshLoginState() }
        })
        present(alert, animated: true)
    }
}

extension SettingsVC: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Bilibili"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if loggedIn {
            return "已登录 Bilibili 账号。如需切换账号，可先退出登录，然后在任意视频页面重新登录。"
        } else {
            return "在任意 Bilibili 视频页面点击登录按钮即可登录账号，解锁 720P/1080P 等更高清晰度。"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.textColor = Theme.label
        if loggedIn {
            cell.textLabel?.text = "退出登录"
            cell.textLabel?.textColor = SettingsVC.destructiveRed
            cell.accessoryType = .none
            cell.detailTextLabel?.text = nil
        } else {
            cell.textLabel?.text = "未登录"
            cell.textLabel?.textColor = Theme.secondaryLabel
            cell.accessoryType = .none
            cell.selectionStyle = .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if loggedIn {
            confirmLogout()
        }
        // If not logged in, do nothing - user should login via video page
    }
}
