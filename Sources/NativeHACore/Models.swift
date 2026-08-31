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

/// The minimal current-user shape needed to evaluate Lovelace view
/// visibility. Authentication, credentials, names, and MFA metadata remain
/// owned by the existing Home Assistant connection/bootstrap path.
public struct HACurrentUser: Decodable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct HAEntityRegistryDisplayResponse: Decodable, Equatable {
    public let entities: [HAEntityRegistryDisplayEntry]

    public init(entities: [HAEntityRegistryDisplayEntry]) {
        self.entities = entities
    }
}

public struct HAEntityRegistryDisplayEntry: Decodable, Equatable {
    public let entityID: String
    public let displayPrecision: Int?

    private enum CodingKeys: String, CodingKey {
        case entityID = "ei"
        case displayPrecision = "dp"
    }

    public init(entityID: String, displayPrecision: Int? = nil) {
        self.entityID = entityID
        self.displayPrecision = displayPrecision
    }
}

public struct HAFrontendUserDataResponse<Value: Decodable & Equatable>: Decodable, Equatable {
    public let value: Value?

    public init(value: Value?) {
        self.value = value
    }
}

public struct HAFrontendLocalePreferences: Decodable, Equatable {
    public let language: String
    public let numberFormat: String
    public let timeFormat: String
    public let dateFormat: String
    public let firstWeekday: String
    public let timeZone: String

    private enum CodingKeys: String, CodingKey {
        case language
        case numberFormat = "number_format"
        case timeFormat = "time_format"
        case dateFormat = "date_format"
        case firstWeekday = "first_weekday"
        case timeZone = "time_zone"
    }

    public init(
        language: String,
        numberFormat: String,
        timeFormat: String,
        dateFormat: String,
        firstWeekday: String,
        timeZone: String
    ) {
        self.language = language
        self.numberFormat = numberFormat
        self.timeFormat = timeFormat
        self.dateFormat = dateFormat
        self.firstWeekday = firstWeekday
        self.timeZone = timeZone
    }
}

public struct HAState: Decodable, Equatable, Identifiable {
    public var id: String { entityId }

    public let entityId: String
    public let state: String
    public let attributes: [String: JSONValue]
    public let context: HAContext?
    public let lastChanged: String?
    public let lastUpdated: String?

    private enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
        case context
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    public init(
        entityId: String,
        state: String,
        attributes: [String: JSONValue] = [:],
        context: HAContext? = nil,
        lastChanged: String? = nil,
        lastUpdated: String? = nil
    ) {
        self.entityId = entityId
        self.state = state
        self.attributes = attributes
        self.context = context
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }
}

/// Home Assistant's state context. Entity-stream compression may send either
/// this complete object or only its `id`; keeping it on `HAState` preserves the
/// typed stream without changing the existing display surface.
public struct HAContext: Codable, Equatable {
    public let id: String?
    public let parentID: String?
    public let userID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case userID = "user_id"
    }

    public init(id: String?, parentID: String? = nil, userID: String? = nil) {
        self.id = id
        self.parentID = parentID
        self.userID = userID
    }
}

/// One typed `subscribe_entities` event. Structural decoding happens before
/// any owner is allowed to mutate its accepted entity snapshot.
public struct HAEntitySubscriptionPayload: Decodable, Equatable {
    public let additions: [String: HACompressedEntityState]?
    public let removals: [String]?
    public let changes: [String: HACompressedEntityChange]?

    private enum CodingKeys: String, CodingKey {
        case additions = "a"
        case removals = "r"
        case changes = "c"
    }

    public init(
        additions: [String: HACompressedEntityState]? = nil,
        removals: [String]? = nil,
        changes: [String: HACompressedEntityChange]? = nil
    ) {
        self.additions = additions
        self.removals = removals
        self.changes = changes
    }
}

public struct HACompressedEntityState: Decodable, Equatable {
    public let state: String
    public let attributes: [String: JSONValue]
    public let context: HACompressedContext
    public let lastChanged: Double
    public let lastUpdated: Double?

    private enum CodingKeys: String, CodingKey {
        case state = "s"
        case attributes = "a"
        case context = "c"
        case lastChanged = "lc"
        case lastUpdated = "lu"
    }

    public init(
        state: String,
        attributes: [String: JSONValue],
        context: HACompressedContext,
        lastChanged: Double,
        lastUpdated: Double? = nil
    ) {
        self.state = state
        self.attributes = attributes
        self.context = context
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }
}

public enum HACompressedContext: Decodable, Equatable {
    case id(String)
    case object(HAContext)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) {
            self = .id(id)
        } else {
            let context = try container.decode(HAContext.self)
            guard context.id != nil else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "A full compressed context object requires id"
                )
            }
            self = .object(context)
        }
    }

    public var value: HAContext {
        switch self {
        case let .id(id):
            return HAContext(id: id)
        case let .object(context):
            return context
        }
    }
}

public struct HACompressedEntityChange: Decodable, Equatable {
    public let additions: HACompressedEntityPatch?
    public let removals: HACompressedEntityPatchRemoval?

    private enum CodingKeys: String, CodingKey {
        case additions = "+"
        case removals = "-"
    }

    public init(
        additions: HACompressedEntityPatch? = nil,
        removals: HACompressedEntityPatchRemoval? = nil
    ) {
        self.additions = additions
        self.removals = removals
    }
}

public struct HACompressedEntityPatch: Decodable, Equatable {
    public let state: String?
    public let attributes: [String: JSONValue]?
    public let context: HACompressedContextPatch?
    public let lastChanged: Double?
    public let lastUpdated: Double?

    private enum CodingKeys: String, CodingKey {
        case state = "s"
        case attributes = "a"
        case context = "c"
        case lastChanged = "lc"
        case lastUpdated = "lu"
    }

    public init(
        state: String? = nil,
        attributes: [String: JSONValue]? = nil,
        context: HACompressedContextPatch? = nil,
        lastChanged: Double? = nil,
        lastUpdated: Double? = nil
    ) {
        self.state = state
        self.attributes = attributes
        self.context = context
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }
}

/// Entity deltas may provide only part of a context object. Unlike a full
/// compressed entity context, this shape deliberately keeps every field
/// optional so the store can merge present values over the prior context,
/// matching `Object.assign({}, entityState.context, toAdd.c)` in entities.js.
public enum HACompressedContextPatch: Decodable, Equatable {
    case id(String)
    case object(HAContextObjectPatch)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) {
            self = .id(id)
        } else {
            self = .object(try container.decode(HAContextObjectPatch.self))
        }
    }
}

public struct HAContextObjectPatch: Decodable, Equatable {
    public let id: HAContextPatchField
    public let parentID: HAContextPatchField
    public let userID: HAContextPatchField

    private enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case userID = "user_id"
    }

    public init(
        id: HAContextPatchField = .absent,
        parentID: HAContextPatchField = .absent,
        userID: HAContextPatchField = .absent
    ) {
        self.id = id
        self.parentID = parentID
        self.userID = userID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.contains(.id)
            ? .value(try container.decodeIfPresent(String.self, forKey: .id))
            : .absent
        parentID = container.contains(.parentID)
            ? .value(try container.decodeIfPresent(String.self, forKey: .parentID))
            : .absent
        userID = container.contains(.userID)
            ? .value(try container.decodeIfPresent(String.self, forKey: .userID))
            : .absent
    }
}

public enum HAContextPatchField: Equatable {
    case absent
    case value(String?)
}

public struct HACompressedEntityPatchRemoval: Decodable, Equatable {
    public let attributes: [String]?

    private enum CodingKeys: String, CodingKey { case attributes = "a" }

    public init(attributes: [String]? = nil) {
        self.attributes = attributes
    }
}

/// Transient proof that a series reused an exact slice of its immediate
/// predecessor. Render caches may consume it only when the predecessor
/// revision still matches; the metadata is intentionally not encoded.
public struct HAHistorySeriesCacheLineage: Equatable, Sendable {
    public let predecessorRevision: UInt64
    public let oldStart: Int
    public let newStart: Int
    public let count: Int

    public init(predecessorRevision: UInt64, oldStart: Int, newStart: Int, count: Int) {
        self.predecessorRevision = predecessorRevision
        self.oldStart = oldStart
        self.newStart = newStart
        self.count = count
    }
}

public struct HAHistorySeries: Equatable, Identifiable, Codable {
    public var id: String { entityID }

    public let entityID: String
    public let points: [HAHistoryPoint]
    /// A source-content revision token. Standalone values default to a
    /// deterministic digest; an owner that has already proven an exact rolling
    /// overlap may supply its monotonic generation instead of re-hashing the
    /// complete long window. Render caches use the token instead of assuming
    /// that equal counts/endpoints imply equal data.
    public let contentRevision: UInt64
    public let cacheLineage: HAHistorySeriesCacheLineage?

    public init(
        entityID: String,
        points: [HAHistoryPoint],
        contentRevision: UInt64? = nil,
        cacheLineage: HAHistorySeriesCacheLineage? = nil
    ) {
        self.entityID = entityID
        self.points = points
        self.contentRevision = contentRevision ?? Self.revision(entityID: entityID, points: points)
        self.cacheLineage = cacheLineage
    }

    private enum CodingKeys: String, CodingKey {
        case entityID
        case points
        case contentRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(String.self, forKey: .entityID)
        points = try container.decode([HAHistoryPoint].self, forKey: .points)
        contentRevision = try container.decode(UInt64.self, forKey: .contentRevision)
        cacheLineage = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entityID, forKey: .entityID)
        try container.encode(points, forKey: .points)
        try container.encode(contentRevision, forKey: .contentRevision)
    }

    private static func revision(entityID: String, points: [HAHistoryPoint]) -> UInt64 {
        var digest: UInt64 = 14_695_981_039_346_656_037
        digest.append(entityID)
        for point in points {
            digest.append(point.entityId ?? "")
            digest.append(point.state)
            if point.hasNativeTimestamps {
                digest.append(point.lastChangedSeconds)
                digest.append(point.lastUpdatedSeconds)
            } else {
                digest.append(point.lastChanged ?? "")
                digest.append(point.lastUpdated ?? "")
            }
            digest.append(point.attributes)
        }
        return digest
    }
}

public struct HAHistoryPoint: Codable, Equatable {
    public let entityId: String?
    public let state: String
    public let attributes: [String: JSONValue]?
    private let storedLastChanged: String?
    private let storedLastUpdated: String?
    public let lastChangedSeconds: Double?
    public let lastUpdatedSeconds: Double?

    public var lastChanged: String? {
        storedLastChanged ?? lastChangedSeconds.map(HAHistoryPointTimestampFormatter.string)
    }

    public var lastUpdated: String? {
        storedLastUpdated ?? lastUpdatedSeconds.map(HAHistoryPointTimestampFormatter.string)
    }

    var hasNativeTimestamps: Bool {
        lastChangedSeconds != nil || lastUpdatedSeconds != nil
    }

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
        storedLastChanged = lastChanged
        storedLastUpdated = lastUpdated
        lastChangedSeconds = nil
        lastUpdatedSeconds = nil
    }

    public init(
        entityId: String?,
        state: String,
        attributes: [String: JSONValue]?,
        lastChangedSeconds: Double?,
        lastUpdatedSeconds: Double?
    ) {
        self.entityId = entityId
        self.state = state
        self.attributes = attributes
        storedLastChanged = nil
        storedLastUpdated = nil
        self.lastChangedSeconds = lastChangedSeconds
        self.lastUpdatedSeconds = lastUpdatedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityId = try container.decodeIfPresent(String.self, forKey: .entityId)
        state = try container.decode(String.self, forKey: .state)
        attributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .attributes)
        storedLastChanged = try container.decodeIfPresent(String.self, forKey: .lastChanged)
        storedLastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        lastChangedSeconds = nil
        lastUpdatedSeconds = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(entityId, forKey: .entityId)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(attributes, forKey: .attributes)
        try container.encodeIfPresent(lastChanged, forKey: .lastChanged)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
    }

    public static func == (lhs: HAHistoryPoint, rhs: HAHistoryPoint) -> Bool {
        lhs.entityId == rhs.entityId &&
            lhs.state == rhs.state &&
            lhs.attributes == rhs.attributes &&
            lhs.lastChanged == rhs.lastChanged &&
            lhs.lastUpdated == rhs.lastUpdated
    }
}

private enum HAHistoryPointTimestampFormatter {
    private static let lock = NSLock()
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(_ seconds: Double) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
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

    mutating func append(_ value: Double?) {
        guard let value = value else {
            append("<nil-double>")
            return
        }
        var bits = value.bitPattern
        for _ in 0..<8 {
            self ^= bits & 0xff
            self &*= 1_099_511_628_211
            bits >>= 8
        }
        self ^= 0xfe
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
