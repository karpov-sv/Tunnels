import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var manager: TunnelManager

    var body: some View {
        TabView(selection: $manager.preferencesTab) {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(PreferencesTab.general)
            HostsPreferencesView()
                .tabItem {
                    Label("Hosts", systemImage: "server.rack")
                }
                .tag(PreferencesTab.hosts)
            LogsPreferencesView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
                .tag(PreferencesTab.logs)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
