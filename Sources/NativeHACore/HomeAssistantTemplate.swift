import Foundation

public struct HATemplateListeners: Codable, Equatable {
    public let all: Bool
    public let domains: [String]
    public let entities: [String]
    public let time: Bool
    public init(all: Bool, domains: [String], entities: [String], time: Bool) {
        self.all = all; self.domains = domains; self.entities = entities; self.time = time
    }
    public static let empty = HATemplateListeners(all: false, domains: [], entities: [], time: false)
}

public struct HATemplateResult: Codable, Equatable {
    public let result: String
    public let listeners: HATemplateListeners
    public init(result: String, listeners: HATemplateListeners = .empty) {
        self.result = result
        self.listeners = listeners
    }
}

public enum HATemplateErrorLevel: String, Codable { case error = "ERROR", warning = "WARNING" }

public enum HATemplateEvent: Decodable, Equatable {
    case result(HATemplateResult)
    case error(String, HATemplateErrorLevel)

    private enum CodingKeys: String, CodingKey { case error, level }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.error) {
            self = .error(try container.decode(String.self, forKey: .error),
                          try container.decode(HATemplateErrorLevel.self, forKey: .level))
        } else {
            self = .result(try HATemplateResult(from: decoder))
        }
    }
}

public extension HomeAssistantWebSocketClient {
    func subscribeRenderTemplate(
        card: LovelaceCard,
        userName: String,
        preview: Bool = false,
        onTermination: (@Sendable (Error) async -> Void)? = nil,
        onEvent: @escaping @Sendable (HATemplateEvent) async -> Void
    ) async throws -> HAWebSocketSubscription {
        var message: [String: JSONValue] = [
            "type": .string("render_template"),
            "template": .string(card.content ?? ""),
            "variables": .object(["config": card.rawValue, "user": .string(userName)]),
            "strict": .bool(true), "report_errors": .bool(preview),
        ]
        message["entity_ids"] = card.templateEntityIDs
        return try await connection.subscribeMessage(
            message, as: HATemplateEvent.self, resubscribe: true,
            onTermination: onTermination, onMessage: onEvent
        )
    }
}
