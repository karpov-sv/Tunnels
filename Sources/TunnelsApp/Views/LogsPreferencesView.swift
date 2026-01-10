import SwiftUI

struct LogsPreferencesView: View {
    @EnvironmentObject private var manager: TunnelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Logs") {
                VStack(alignment: .leading, spacing: 12) {
                    if manager.logs.isEmpty {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        LogTextView(entries: manager.logs)
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }

                    HStack {
                        Spacer()
                        Button("Clear Logs") {
                            manager.clearLogs()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
