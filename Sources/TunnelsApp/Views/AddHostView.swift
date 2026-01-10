import SwiftUI

struct AddHostView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add SSH Host")
                .font(.headline)
            Text("Enter an alias defined in ~/.ssh/config.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Host alias", text: $alias)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    manager.addHost(alias: alias)
                    dismiss()
                }
                .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
