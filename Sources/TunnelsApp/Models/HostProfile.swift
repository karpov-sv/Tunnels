import Foundation

struct HostProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var alias: String
    var hostname: String
    var tunnels: [TunnelSpec]
    var respectsConfigForwardings: Bool

    init(
        id: UUID = UUID(),
        alias: String,
        hostname: String? = nil,
        tunnels: [TunnelSpec] = [],
        respectsConfigForwardings: Bool = false
    ) {
        self.id = id
        self.alias = alias
        self.hostname = hostname ?? alias
        self.tunnels = tunnels
        self.respectsConfigForwardings = respectsConfigForwardings
    }

    enum CodingKeys: String, CodingKey {
        case id
        case alias
        case hostname
        case tunnels
        case respectsConfigForwardings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        alias = try container.decode(String.self, forKey: .alias)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? alias
        tunnels = try container.decodeIfPresent([TunnelSpec].self, forKey: .tunnels) ?? []
        respectsConfigForwardings = try container.decodeIfPresent(Bool.self, forKey: .respectsConfigForwardings) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(alias, forKey: .alias)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(tunnels, forKey: .tunnels)
        try container.encode(respectsConfigForwardings, forKey: .respectsConfigForwardings)
    }
}
