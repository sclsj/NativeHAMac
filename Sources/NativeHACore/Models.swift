import Foundation

public struct HAConfig: Decodable, Equatable {
    public let latitude: Double?
    public let longitude: Double?
    public let elevation: Double?
    public let locationName: String?
    public let timeZone: String?
    public let components: [String]

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case elevation
        case locationName = "location_name"
        case timeZone = "time_zone"
        case components
    }

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        elevation: Double? = nil,
        locationName: String? = nil,
        timeZone: String? = nil,
        components: [String] = []
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.locationName = locationName
        self.timeZone = timeZone
        self.components = components
    }
}

public struct HAState: Decodable, Equatable, Identifiable {
    public var id: String { entityId }

    public let entityId: String
    public let state: String
    public let attributes: [String: JSONValue]
    public let lastChanged: String?
    public let lastUpdated: String?

    private enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    public init(
        entityId: String,
        state: String,
        attributes: [String: JSONValue] = [:],
        lastChanged: String? = nil,
        lastUpdated: String? = nil
    ) {
        self.entityId = entityId
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }
}

public struct HAHistorySeries: Equatable, Identifiable {
    public var id: String { entityID }

    public let entityID: String
    public let points: [HAHistoryPoint]

    public init(entityID: String, points: [HAHistoryPoint]) {
        self.entityID = entityID
        self.points = points
    }
}

public struct HAHistoryPoint: Decodable, Equatable {
    public let entityId: String?
    public let state: String
    public let attributes: [String: JSONValue]?
    public let lastChanged: String?
    public let lastUpdated: String?

    private enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    public init(
        entityId: String?,
        state: String,
        attributes: [String: JSONValue]?,
        lastChanged: String?,
        lastUpdated: String?
    ) {
        self.entityId = entityId
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }
}

public struct LovelaceConfig: Decodable, Equatable {
    public let views: [LovelaceView]
}

public struct LovelaceView: Decodable, Equatable, Identifiable {
    public var id: String { path ?? title }

    public let title: String
    public let path: String?
    public let cards: [LovelaceCard]
}

public struct LovelaceCard: Decodable, Equatable, Identifiable {
    public var id = UUID()

    public let type: String
    public let title: String?
    public let entity: String?
    public let entities: [LovelaceEntityRef]?
    public let cards: [LovelaceCard]?
    public let hoursToShow: Int?
    public let showForecast: Bool?
    public let content: String?

    public init(
        type: String,
        title: String? = nil,
        entity: String? = nil,
        entities: [LovelaceEntityRef]? = nil,
        cards: [LovelaceCard]? = nil,
        hoursToShow: Int? = nil,
        showForecast: Bool? = nil,
        content: String? = nil
    ) {
        self.type = type
        self.title = title
        self.entity = entity
        self.entities = entities
        self.cards = cards
        self.hoursToShow = hoursToShow
        self.showForecast = showForecast
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case entity
        case entities
        case cards
        case hoursToShow = "hours_to_show"
        case showForecast = "show_forecast"
        case content
    }
}

public struct LovelaceEntityRef: Decodable, Equatable, Identifiable {
    public var id: String { entity ?? name ?? type ?? rawID }

    public let entity: String?
    public let name: String?
    public let type: String?
    private let rawID: String

    public init(entity: String?, name: String? = nil, type: String? = nil) {
        self.entity = entity
        self.name = name
        self.type = type
        self.rawID = UUID().uuidString
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let entity = try? container.decode(String.self) {
            self.entity = entity
            self.name = nil
            self.type = nil
            self.rawID = entity
            return
        }

        let object = try decoder.container(keyedBy: CodingKeys.self)
        self.entity = try object.decodeIfPresent(String.self, forKey: .entity)
        self.name = try object.decodeIfPresent(String.self, forKey: .name)
        self.type = try object.decodeIfPresent(String.self, forKey: .type)
        self.rawID = entity ?? name ?? type ?? UUID().uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case entity
        case name
        case type
    }
}
