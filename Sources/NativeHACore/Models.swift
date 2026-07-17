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

public struct HAHistorySeries: Equatable, Identifiable, Codable {
    public var id: String { entityID }

    public let entityID: String
    public let points: [HAHistoryPoint]
    /// A deterministic digest of the complete source content. Render caches use
    /// this instead of assuming that equal counts/endpoints imply equal data.
    public let contentRevision: UInt64

    public init(entityID: String, points: [HAHistoryPoint], contentRevision: UInt64? = nil) {
        self.entityID = entityID
        self.points = points
        self.contentRevision = contentRevision ?? Self.revision(entityID: entityID, points: points)
    }

    private static func revision(entityID: String, points: [HAHistoryPoint]) -> UInt64 {
        var digest: UInt64 = 14_695_981_039_346_656_037
        digest.append(entityID)
        for point in points {
            digest.append(point.entityId ?? "")
            digest.append(point.state)
            digest.append(point.lastChanged ?? "")
            digest.append(point.lastUpdated ?? "")
            digest.append(point.attributes)
        }
        return digest
    }
}

public struct HAHistoryPoint: Codable, Equatable {
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

private extension UInt64 {
    mutating func append(_ value: String) {
        for byte in value.utf8 {
            self ^= UInt64(byte)
            self &*= 1_099_511_628_211
        }
        self ^= 0xff
        self &*= 1_099_511_628_211
    }

    mutating func append(_ attributes: [String: JSONValue]?) {
        guard let attributes = attributes else {
            append("<nil>")
            return
        }
        for key in attributes.keys.sorted() {
            append(key)
            append(attributes[key]!)
        }
    }

    mutating func append(_ value: JSONValue) {
        switch value {
        case let .string(item):
            append("s")
            append(item)
        case let .int(item):
            append("i\(item)")
        case let .double(item):
            append("d\(item.bitPattern)")
        case let .bool(item):
            append(item ? "b1" : "b0")
        case let .object(item):
            append("{")
            append(item)
            append("}")
        case let .array(items):
            append("[")
            for item in items {
                append(item)
            }
            append("]")
        case .null:
            append("n")
        }
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
    /// Native-only deterministic traversal identity assigned by the dashboard
    /// owner. It is not decoded from or written back into Lovelace config.
    public var nativeOwnerID: String? = nil

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
        content: String? = nil,
        nativeOwnerID: String? = nil
    ) {
        self.type = type
        self.title = title
        self.entity = entity
        self.entities = entities
        self.cards = cards
        self.hoursToShow = hoursToShow
        self.showForecast = showForecast
        self.content = content
        self.nativeOwnerID = nativeOwnerID
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
