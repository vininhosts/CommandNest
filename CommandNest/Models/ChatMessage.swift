import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable, CaseIterable {
        case system
        case user
        case assistant
    }

    var id: UUID
    var role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}
