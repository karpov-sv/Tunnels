import AppKit
import SwiftUI

final class PreferencesTabController: NSTabViewController {
    private let manager: TunnelManager
    private var tabs: [PreferencesTab: NSTabViewItem] = [:]
    var onSelectTab: ((PreferencesTab) -> Void)?
    private var isSyncingSelection = false

    init(manager: TunnelManager) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        isSyncingSelection = true
        tabStyle = .segmentedControlOnTop

        let general = makeItem(
            tab: .general,
            label: "General",
            systemImage: "gearshape",
            view: GeneralPreferencesView().environmentObject(manager)
        )
        let hosts = makeItem(
            tab: .hosts,
            label: "Hosts",
            systemImage: "server.rack",
            view: HostsPreferencesView().environmentObject(manager)
        )
        let logs = makeItem(
            tab: .logs,
            label: "Logs",
            systemImage: "doc.text.magnifyingglass",
            view: LogsPreferencesView().environmentObject(manager)
        )
        let about = makeItem(
            tab: .about,
            label: "About",
            systemImage: "info.circle",
            view: AboutPreferencesView().environmentObject(manager)
        )

        tabViewItems = [general, hosts, logs, about]
        tabs = [.general: general, .hosts: hosts, .logs: logs, .about: about]
        if let item = tabs[manager.preferencesTab] {
            tabView.selectTabViewItem(item)
        }
        isSyncingSelection = false
    }

    func select(tab: PreferencesTab) {
        guard let item = tabs[tab], tabView.selectedTabViewItem != item else { return }
        isSyncingSelection = true
        tabView.selectTabViewItem(item)
        isSyncingSelection = false
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard !isSyncingSelection else { return }
        guard let id = tabViewItem?.identifier as? String,
              let tab = PreferencesTab(rawValue: id) else {
            return
        }
        onSelectTab?(tab)
    }

    private func makeItem(tab: PreferencesTab, label: String, systemImage: String, view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.identifier = tab.rawValue
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: label) {
            item.image = image
        }
        return item
    }
}

struct PreferencesTabControllerRepresentable: NSViewControllerRepresentable {
    @ObservedObject var manager: TunnelManager

    func makeNSViewController(context: Context) -> PreferencesTabController {
        let controller = PreferencesTabController(manager: manager)
        controller.onSelectTab = { tab in
            if manager.preferencesTab != tab {
                manager.preferencesTab = tab
            }
        }
        return controller
    }

    func updateNSViewController(_ nsViewController: PreferencesTabController, context: Context) {
        nsViewController.select(tab: manager.preferencesTab)
    }
}
