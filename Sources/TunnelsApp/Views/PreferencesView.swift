import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var manager: TunnelManager

    var body: some View {
        PreferencesTabControllerRepresentable(manager: manager)
            .frame(minWidth: 760, minHeight: 520)
    }
}
