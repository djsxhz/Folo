import UIKit

/// Minimal settings screen. Its only field is the RSSHub instance URL used to
/// expand `rsshub://` routes. Allow `http://` LAN addresses (e.g. a local
/// RSSHub on `http://192.168.1.x:1200`) — the app already opts into arbitrary
/// loads via `NSAllowsArbitraryLoads`.
final class SettingsVC: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGroupedCompat)

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
    }

    private func setupTableView() {
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = Theme.groupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func editRSSHub() {
        let alert = UIAlertController(
            title: "RSSHub 实例",
            message: "用于展开 rsshub:// 路由。支持 https:// 公共实例或 http:// 局域网地址。",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = FeedService.rsshubBase
            tf.placeholder = "https://rsshub.app"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                FeedService.rsshubBase = "https://rsshub.app"
            } else if let url = URL(string: raw),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" {
                FeedService.rsshubBase = raw
            } else {
                self?.presentInvalid()
                return
            }
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func presentInvalid() {
        let alert = UIAlertController(
            title: "地址无效",
            message: "请填写以 http:// 或 https:// 开头的实例地址。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension SettingsVC: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return 1 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "RSSHub 实例"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "添加订阅时,rsshub://… 形式的输入会按该地址展开。默认为 https://rsshub.app。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // `.value1` is the only built-in style with both textLabel and a
        // right-aligned detail label, and is available on iOS 12.
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "rsshubValue")
        cell.textLabel?.text = "实例地址"
        cell.textLabel?.textColor = Theme.label
        cell.detailTextLabel?.text = FeedService.rsshubBase
        cell.detailTextLabel?.textColor = Theme.secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        editRSSHub()
    }
}
