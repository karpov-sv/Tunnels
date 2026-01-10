import SwiftUI

struct TunnelEditorView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss

    let hostId: UUID
    let tunnel: TunnelSpec?

    @State private var type: TunnelType
    @State private var localPort: String
    @State private var remoteHost: String
    @State private var remotePort: String

    init(hostId: UUID, tunnel: TunnelSpec?) {
        self.hostId = hostId
        self.tunnel = tunnel
        _type = State(initialValue: tunnel?.type ?? .local)
        _localPort = State(initialValue: tunnel.map { String($0.localPort) } ?? "")
        _remoteHost = State(initialValue: tunnel?.remoteHost ?? "")
        _remotePort = State(initialValue: tunnel.flatMap { $0.remotePort }.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tunnel == nil ? "Add Tunnel" : "Edit Tunnel")
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
                Button("Save") {
                    saveTunnel()
                }
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360)
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
        guard let local = Int(localPort) else { return }
        let trimmedHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = Int(remotePort)

        let spec = TunnelSpec(
            id: tunnel?.id ?? UUID(),
            type: type,
            localPort: local,
            remoteHost: type == .dynamic ? nil : trimmedHost,
            remotePort: type == .dynamic ? nil : remote,
            isActive: false
        )

        if let tunnel {
            manager.updateTunnel(hostId: hostId, tunnelId: tunnel.id, updated: spec)
        } else {
            manager.addTunnel(hostId: hostId, spec: spec)
        }
        dismiss()
    }
}
