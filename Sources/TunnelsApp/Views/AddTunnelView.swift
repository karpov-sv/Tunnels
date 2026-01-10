import SwiftUI

struct AddTunnelView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @Binding var hostId: UUID?

    @State private var type: TunnelType = .local
    @State private var localPort = ""
    @State private var remoteHost = ""
    @State private var remotePort = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Picker("Type", selection: $type) {
                ForEach(TunnelType.allCases, id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.segmented)

            TextField("Local port", text: $localPort)
                .textFieldStyle(.roundedBorder)

            if type != .dynamic {
                TextField(type == .local ? "Remote host" : "Target host", text: $remoteHost)
                    .textFieldStyle(.roundedBorder)
                TextField(type == .local ? "Remote port" : "Remote bind port", text: $remotePort)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    saveTunnel()
                }
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var title: String {
        if let host = selectedHost {
            return "Add Tunnel for \(host.alias)"
        }
        return "Add Tunnel"
    }

    private var selectedHost: HostProfile? {
        guard let hostId else { return nil }
        return manager.hostProfile(id: hostId)
    }

    private var isValid: Bool {
        guard let local = Int(localPort), (1...65535).contains(local) else { return false }
        if type == .dynamic {
            return true
        }
        guard !remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let remote = Int(remotePort), (1...65535).contains(remote) else { return false }
        return true
    }

    private func saveTunnel() {
        guard let hostId else { return }
        guard let local = Int(localPort) else { return }
        let trimmedHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = Int(remotePort)

        let spec = TunnelSpec(
            type: type,
            localPort: local,
            remoteHost: type == .dynamic ? nil : trimmedHost,
            remotePort: type == .dynamic ? nil : remote
        )
        manager.addTunnel(hostId: hostId, spec: spec)
        dismiss()
    }
}
