import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var manager: TunnelManager
    @State private var showingLastError = false

    var body: some View {
        PreferencesTabControllerRepresentable(manager: manager)
            .frame(minWidth: 760, minHeight: 520)
            .onAppear {
                showingLastError = manager.lastError != nil
            }
            .onChange(of: manager.lastError) { _, newValue in
                showingLastError = newValue != nil
            }
            .alert("Tunnels Error", isPresented: $showingLastError) {
                Button("OK") {
                    manager.clearLastError()
                }
            } message: {
                Text(manager.lastError ?? "An unknown error occurred.")
            }
    }
}
