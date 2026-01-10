import SwiftUI

struct HostDetailsView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @Binding var hostId: UUID?
    @State private var isLoading = false
    @State private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if isLoading {
                ProgressView("Inspecting ssh config...")
            }

            ScrollView {
                Text(output.isEmpty ? "No config data." : output)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240)

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
        .task(id: hostId) {
            await loadDetails()
        }
    }

    private var title: String {
        if let host = selectedHost {
            return "Host Details: \(host.alias)"
        }
        return "Host Details"
    }

    private var selectedHost: HostProfile? {
        guard let hostId else { return nil }
        return manager.hostProfile(id: hostId)
    }

    private func loadDetails() async {
        guard let hostId else {
            output = "No host selected."
            return
        }
        isLoading = true
        defer { isLoading = false }
        guard let result = await manager.inspectConfig(for: hostId) else {
            output = "Unable to inspect host config."
            return
        }
        let text = result.combinedOutput.isEmpty ? "No output from ssh -G." : result.combinedOutput
        output = text
    }

}
