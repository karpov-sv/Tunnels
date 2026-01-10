import Foundation

enum TunnelType: String, Codable, CaseIterable {
    case local
    case remote
    case dynamic

    var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .remote:
            return "Remote"
        case .dynamic:
            return "Dynamic"
        }
    }
}

struct TunnelSpec: Identifiable, Codable, Equatable {
    let id: UUID
    var type: TunnelType
    var localPort: Int
    var remoteHost: String?
    var remotePort: Int?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        type: TunnelType,
        localPort: Int,
        remoteHost: String? = nil,
        remotePort: Int? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.type = type
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case localPort
        case remoteHost
        case remotePort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(TunnelType.self, forKey: .type)
        localPort = try container.decode(Int.self, forKey: .localPort)
        remoteHost = try container.decodeIfPresent(String.self, forKey: .remoteHost)
        remotePort = try container.decodeIfPresent(Int.self, forKey: .remotePort)
        isActive = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(localPort, forKey: .localPort)
        try container.encodeIfPresent(remoteHost, forKey: .remoteHost)
        try container.encodeIfPresent(remotePort, forKey: .remotePort)
    }

    var displaySummary: String {
        switch type {
        case .dynamic:
            return "D \(localPort)"
        case .local:
            return "L \(localPort) -> \(remoteHost ?? "?"):\(remotePort.map(String.init) ?? "?")"
        case .remote:
            return "R \(remotePort.map(String.init) ?? "?") -> \(remoteHost ?? "?"):\(localPort)"
        }
    }
}
