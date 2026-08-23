import Foundation

public struct LovelaceDiagnostic: Equatable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public enum LovelaceDecodeError: Error, Equatable, LocalizedError {
    case nonObjectRoot
    case missingViews
    case invalidViews

    public var errorDescription: String? {
        switch self {
        case .nonObjectRoot: return "Lovelace configuration root must be an object."
        case .missingViews: return "Lovelace configuration has no views array."
        case .invalidViews: return "Lovelace configuration views must be an array."
        }
    }
}

public struct LovelaceConfig: Decodable, Equatable {
    public let rawValue: JSONValue
    public let views: [LovelaceView]

    public init(views: [LovelaceView], rawValue: JSONValue? = nil) {
        self.views = views
        self.rawValue = rawValue ?? .object(["views": .array(views.map(\.rawValue))])
    }

    public init(rawValue: JSONValue) throws {
        guard case let .object(object) = rawValue else {
            throw LovelaceDecodeError.nonObjectRoot
        }
        guard let viewsValue = object["views"] else {
            throw LovelaceDecodeError.missingViews
        }
        guard case let .array(rawViews) = viewsValue else {
            throw LovelaceDecodeError.invalidViews
        }
        self.rawValue = rawValue
        self.views = rawViews.enumerated().map { index, value in
            LovelaceView(rawValue: value, sourceIndex: index)
        }
    }

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(JSONValue.self)
        try self.init(rawValue: rawValue)
    }
}

public struct LovelaceView: Equatable {
    public let rawValue: JSONValue
    public let sourceIndex: Int
    public let diagnostic: LovelaceDiagnostic?
    public let title: String
    public let path: String?
    public let icon: String?
    public let showIconAndTitle: Bool?
    public let visible: JSONValue?
    public let subview: Bool?
    public let backPath: String?
    public let panel: Bool?
    public let type: String?
    public let theme: JSONValue?
    public let background: JSONValue?
    public let cards: [LovelaceCard]
    public let sections: JSONValue?
    public let header: JSONValue?
    public let footer: JSONValue?

    public init(title: String, path: String? = nil, cards: [LovelaceCard], sourceIndex: Int = 0) {
        var object: [String: JSONValue] = [
            "title": .string(title),
            "cards": .array(cards.map(\.rawValue)),
        ]
        if let path = path { object["path"] = .string(path) }
        self.init(rawObject: object, sourceIndex: sourceIndex, cards: cards, diagnostic: nil)
    }

    init(rawValue: JSONValue, sourceIndex: Int) {
        let path = "views[\(sourceIndex)]"
        guard case let .object(object) = rawValue else {
            self.init(
                rawObject: [:],
                rawValue: rawValue,
                sourceIndex: sourceIndex,
                cards: [],
                diagnostic: LovelaceDiagnostic(path: path, message: "View must be an object.")
            )
            return
        }

        var diagnostics: [String] = []
        let title = object.optionalString("title", path: path, diagnostics: &diagnostics) ?? "Untitled"
        let routePath = object.optionalString("path", path: path, diagnostics: &diagnostics)
        _ = object.optionalString("icon", path: path, diagnostics: &diagnostics)
        _ = object.optionalBool("show_icon_and_title", path: path, diagnostics: &diagnostics)
        _ = object.optionalBool("subview", path: path, diagnostics: &diagnostics)
        _ = object.optionalString("back_path", path: path, diagnostics: &diagnostics)
        _ = object.optionalBool("panel", path: path, diagnostics: &diagnostics)
        _ = object.optionalString("type", path: path, diagnostics: &diagnostics)
        let cards: [LovelaceCard]
        if let rawCards = object["cards"] {
            if case let .array(values) = rawCards {
                cards = values.enumerated().map { index, value in
                    LovelaceCard(rawValue: value, diagnosticPath: "\(path).cards[\(index)]")
                }
            } else {
                cards = []
                diagnostics.append("cards must be an array")
            }
        } else {
            cards = []
        }
        self.init(
            rawObject: object,
            rawValue: rawValue,
            sourceIndex: sourceIndex,
            cards: cards,
            diagnostic: diagnostics.isEmpty ? nil : LovelaceDiagnostic(
                path: path,
                message: diagnostics.joined(separator: "; ")
            ),
            title: title,
            path: routePath
        )
    }

    private init(
        rawObject object: [String: JSONValue],
        rawValue: JSONValue? = nil,
        sourceIndex: Int,
        cards: [LovelaceCard],
        diagnostic: LovelaceDiagnostic?,
        title: String? = nil,
        path: String? = nil
    ) {
        self.rawValue = rawValue ?? .object(object)
        self.sourceIndex = sourceIndex
        self.diagnostic = diagnostic
        self.title = title ?? object.string("title") ?? "Untitled"
        self.path = path ?? object.string("path")
        icon = object.string("icon")
        showIconAndTitle = object.bool("show_icon_and_title")
        visible = object["visible"]
        subview = object.bool("subview")
        backPath = object.string("back_path")
        panel = object.bool("panel")
        type = object.string("type")
        theme = object["theme"]
        background = object["background"]
        self.cards = cards
        sections = object["sections"]
        header = object["header"]
        footer = object["footer"]
    }
}

public struct LovelaceCard: Equatable {
    public let rawValue: JSONValue
    public let diagnostic: LovelaceDiagnostic?
    public let type: String
    public let title: String?
    public let entity: String?
    public let entities: [LovelaceEntityRef]?
    public let cards: [LovelaceCard]?
    public let content: String?
    public let gridOptions: JSONValue?
    public let visibility: JSONValue?
    public let disabled: Bool?
    public let columns: Int?
    public let square: Bool?
    public let conditionalCard: JSONValue?
    public let conditions: JSONValue?
    public let showHeaderToggle: Bool?
    public let icon: String?
    public let stateColor: Bool?
    public let header: JSONValue?
    public let footer: JSONValue?
    public let hoursToShow: Int?
    public let showNames: Bool?
    public let logarithmicScale: Bool?
    public let minYAxis: Double?
    public let maxYAxis: Double?
    public let fitYData: Bool?
    public let splitDeviceClasses: Bool?
    public let expandLegend: Bool?
    public let showCurrent: Bool?
    public let showForecast: Bool?
    public let forecastType: String?
    public let forecastSlots: Int?
    public let secondaryInfoAttribute: String?
    public let roundTemperature: Bool?
    public let name: String?
    public let textOnly: Bool?
    public let cardSize: Int?
    public let entityIDs: [String]?
    public let entityID: String?
    public let showEmpty: Bool?
    public let tapAction: JSONValue?
    public let holdAction: JSONValue?
    public let doubleTapAction: JSONValue?

    public var isInvalid: Bool { diagnostic != nil }

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
        var object: [String: JSONValue] = ["type": .string(type)]
        if let title = title { object["title"] = .string(title) }
        if let entity = entity { object["entity"] = .string(entity) }
        if let entities = entities { object["entities"] = .array(entities.map(\.rawValue)) }
        if let cards = cards { object["cards"] = .array(cards.map(\.rawValue)) }
        if let hoursToShow = hoursToShow { object["hours_to_show"] = .int(hoursToShow) }
        if let showForecast = showForecast { object["show_forecast"] = .bool(showForecast) }
        if let content = content { object["content"] = .string(content) }
        self = LovelaceCard(rawValue: .object(object), diagnosticPath: "card")
    }

    init(rawValue: JSONValue, diagnosticPath: String) {
        let object: [String: JSONValue]
        var diagnostics: [String]
        if case let .object(value) = rawValue {
            object = value
            diagnostics = []
        } else {
            object = [:]
            diagnostics = ["Card must be an object."]
        }
        let type = object.optionalString("type", path: diagnosticPath, diagnostics: &diagnostics)
        if type == nil { diagnostics.append("type is required") }

        let entities: [LovelaceEntityRef]?
        if let value = object["entities"] {
            if case let .array(values) = value {
                entities = values.enumerated().map { index, row in
                    LovelaceEntityRef(rawValue: row, diagnosticPath: "\(diagnosticPath).entities[\(index)]")
                }
            } else {
                entities = []
                diagnostics.append("entities must be an array")
            }
        } else { entities = nil }

        let cards: [LovelaceCard]?
        if let value = object["cards"] {
            if case let .array(values) = value {
                cards = values.enumerated().map { index, card in
                    LovelaceCard(rawValue: card, diagnosticPath: "\(diagnosticPath).cards[\(index)]")
                }
            } else {
                cards = []
                diagnostics.append("cards must be an array")
            }
        } else { cards = nil }

        func string(_ key: String) -> String? {
            object.optionalString(key, path: diagnosticPath, diagnostics: &diagnostics)
        }
        func bool(_ key: String) -> Bool? {
            object.optionalBool(key, path: diagnosticPath, diagnostics: &diagnostics)
        }
        func int(_ key: String) -> Int? {
            object.optionalInt(key, path: diagnosticPath, diagnostics: &diagnostics)
        }
        func double(_ key: String) -> Double? {
            object.optionalDouble(key, path: diagnosticPath, diagnostics: &diagnostics)
        }

        let parsedTitle = string("title")
        let parsedEntity = string("entity")
        let parsedContent = string("content")
        let parsedDisabled = bool("disabled")
        let parsedColumns = int("columns")
        let parsedSquare = bool("square")
        let parsedShowHeaderToggle = bool("show_header_toggle")
        let parsedIcon = string("icon")
        let parsedStateColor = bool("state_color")
        let parsedHoursToShow = int("hours_to_show")
        let parsedShowNames = bool("show_names")
        let parsedLogarithmicScale = bool("logarithmic_scale")
        let parsedMinYAxis = double("min_y_axis")
        let parsedMaxYAxis = double("max_y_axis")
        let parsedFitYData = bool("fit_y_data")
        let parsedSplitDeviceClasses = bool("split_device_classes")
        let parsedExpandLegend = bool("expand_legend")
        let parsedShowCurrent = bool("show_current")
        let parsedShowForecast = bool("show_forecast")
        let parsedForecastType = string("forecast_type")
        let parsedForecastSlots = int("forecast_slots")
        let parsedSecondaryInfoAttribute = string("secondary_info_attribute")
        let parsedRoundTemperature = bool("round_temperature")
        let parsedName = string("name")
        let parsedTextOnly = bool("text_only")
        let parsedCardSize = int("card_size")
        let parsedEntityIDs: [String]?
        if let value = object["entity_ids"] {
            if case let .string(value) = value {
                parsedEntityIDs = [value]
            } else if case let .array(values) = value, values.allSatisfy({ if case .string = $0 { return true }; return false }) {
                parsedEntityIDs = values.compactMap { if case let .string(value) = $0 { return value }; return nil }
            } else {
                parsedEntityIDs = []
                diagnostics.append("entity_ids must be a string or string array")
            }
        } else { parsedEntityIDs = nil }
        let parsedEntityID = string("entity_id")
        let parsedShowEmpty = bool("show_empty")

        switch type {
        case "entities":
            if entities?.isEmpty != false {
                diagnostics.append("\(type ?? "card") requires a nonempty entities array")
            }
        case "history-graph":
            if entities?.isEmpty != false {
                diagnostics.append("history-graph requires a nonempty entities array")
            } else if entities?.contains(where: {
                $0.diagnostic == nil && $0.entity?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }) != true {
                diagnostics.append("history-graph requires at least one usable entity")
            }
        case "vertical-stack", "horizontal-stack", "grid":
            if cards == nil {
                diagnostics.append("\(type ?? "container") requires a cards array")
            }
        case "weather-forecast":
            if parsedEntity?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                diagnostics.append("weather-forecast requires a nonempty entity")
            }
        case "markdown":
            if parsedContent == nil {
                diagnostics.append("markdown requires content")
            }
        default:
            break
        }

        self.rawValue = rawValue
        diagnostic = diagnostics.isEmpty ? nil : LovelaceDiagnostic(
            path: diagnosticPath,
            message: diagnostics.joined(separator: "; ")
        )
        self.type = type ?? "invalid"
        title = parsedTitle
        entity = parsedEntity
        self.entities = entities
        self.cards = cards
        content = parsedContent
        gridOptions = object["grid_options"]
        visibility = object["visibility"]
        disabled = parsedDisabled
        columns = parsedColumns
        square = parsedSquare
        conditionalCard = object["card"]
        conditions = object["conditions"]
        showHeaderToggle = parsedShowHeaderToggle
        icon = parsedIcon
        stateColor = parsedStateColor
        header = object["header"]
        footer = object["footer"]
        hoursToShow = parsedHoursToShow
        showNames = parsedShowNames
        logarithmicScale = parsedLogarithmicScale
        minYAxis = parsedMinYAxis
        maxYAxis = parsedMaxYAxis
        fitYData = parsedFitYData
        splitDeviceClasses = parsedSplitDeviceClasses
        expandLegend = parsedExpandLegend
        showCurrent = parsedShowCurrent
        showForecast = parsedShowForecast
        forecastType = parsedForecastType
        forecastSlots = parsedForecastSlots
        secondaryInfoAttribute = parsedSecondaryInfoAttribute
        roundTemperature = parsedRoundTemperature
        name = parsedName
        textOnly = parsedTextOnly
        cardSize = parsedCardSize
        entityIDs = parsedEntityIDs
        entityID = parsedEntityID
        showEmpty = parsedShowEmpty
        tapAction = object["tap_action"]
        holdAction = object["hold_action"]
        doubleTapAction = object["double_tap_action"]
    }

}

public struct LovelaceEntityRef: Equatable {
    public let rawValue: JSONValue
    public let diagnostic: LovelaceDiagnostic?
    public let type: String?
    public let entity: String?
    public let name: String?
    public let color: String?
    public let icon: String?
    public let secondaryInfo: String?
    public let stateColor: Bool?
    public let showName: Bool?
    public let showIcon: Bool?
    public let tapAction: JSONValue?
    public let holdAction: JSONValue?
    public let doubleTapAction: JSONValue?

    public init(entity: String?, name: String? = nil, type: String? = nil) {
        var object: [String: JSONValue] = [:]
        if let entity = entity { object["entity"] = .string(entity) }
        if let name = name { object["name"] = .string(name) }
        if let type = type { object["type"] = .string(type) }
        self.init(rawValue: .object(object), diagnosticPath: "row")
    }

    init(rawValue: JSONValue, diagnosticPath: String) {
        if case let .string(entity) = rawValue {
            self.rawValue = rawValue
            diagnostic = nil
            type = nil
            self.entity = entity
            name = nil; color = nil; icon = nil; secondaryInfo = nil; stateColor = nil
            showName = nil; showIcon = nil; tapAction = nil; holdAction = nil; doubleTapAction = nil
            return
        }
        guard case let .object(object) = rawValue else {
            self.rawValue = rawValue
            diagnostic = LovelaceDiagnostic(path: diagnosticPath, message: "Entity row must be a string or object.")
            type = nil; entity = nil; name = nil; color = nil; icon = nil; secondaryInfo = nil
            stateColor = nil; showName = nil; showIcon = nil; tapAction = nil
            holdAction = nil; doubleTapAction = nil
            return
        }
        var diagnostics: [String] = []
        func string(_ key: String) -> String? { object.optionalString(key, path: diagnosticPath, diagnostics: &diagnostics) }
        func bool(_ key: String) -> Bool? { object.optionalBool(key, path: diagnosticPath, diagnostics: &diagnostics) }
        self.rawValue = rawValue
        type = string("type")
        entity = string("entity")
        name = string("name")
        color = string("color")
        icon = string("icon")
        secondaryInfo = string("secondary_info")
        stateColor = bool("state_color")
        showName = bool("show_name")
        showIcon = bool("show_icon")
        tapAction = object["tap_action"]
        holdAction = object["hold_action"]
        doubleTapAction = object["double_tap_action"]
        if entity == nil, type == nil {
            diagnostics.append("unsupported object row has no entity or type")
        }
        diagnostic = diagnostics.isEmpty ? nil : LovelaceDiagnostic(
            path: diagnosticPath,
            message: diagnostics.joined(separator: "; ")
        )
    }
}

public struct LovelacePathComponent: Hashable, Codable {
    public let container: String
    public let index: Int

    public init(container: String, index: Int) {
        self.container = container
        self.index = index
    }
}

public struct LovelaceSourcePath: Hashable, Codable, CustomStringConvertible {
    public let components: [LovelacePathComponent]

    public init(components: [LovelacePathComponent] = []) {
        self.components = components
    }

    public func appending(_ container: String, index: Int) -> LovelaceSourcePath {
        LovelaceSourcePath(components: components + [LovelacePathComponent(container: container, index: index)])
    }

    public var description: String {
        components.map { "\($0.container)[\($0.index)]" }.joined(separator: ".")
    }
}

public struct LovelaceResolvedIdentity: Hashable, CustomStringConvertible {
    public let sourcePath: LovelaceSourcePath
    public let canonicalSemanticValue: String

    public init(sourcePath: LovelaceSourcePath, rawValue: JSONValue) {
        self.sourcePath = sourcePath
        canonicalSemanticValue = rawValue.canonicalSemanticValue
    }

    public var description: String { sourcePath.description }

    public var ownerKey: String {
        sourcePath.description + "\u{1F}" + canonicalSemanticValue
    }
}

public struct LovelaceResolvedRow: Equatable, Identifiable {
    public var id: LovelaceResolvedIdentity { identity }
    public let source: LovelaceEntityRef
    public let identity: LovelaceResolvedIdentity

    public init(source: LovelaceEntityRef, identity: LovelaceResolvedIdentity) {
        self.source = source
        self.identity = identity
    }
}

public struct LovelaceResolvedCard: Equatable, Identifiable {
    public var id: LovelaceResolvedIdentity { identity }
    public let source: LovelaceCard
    public let identity: LovelaceResolvedIdentity
    public let rows: [LovelaceResolvedRow]?
    public let cards: [LovelaceResolvedCard]?

    public init(
        source: LovelaceCard,
        identity: LovelaceResolvedIdentity,
        rows: [LovelaceResolvedRow]?,
        cards: [LovelaceResolvedCard]?
    ) {
        self.source = source
        self.identity = identity
        self.rows = rows
        self.cards = cards
    }
}

public struct LovelaceResolvedView: Equatable, Identifiable {
    public var id: LovelaceResolvedIdentity { identity }
    public let source: LovelaceView
    public let identity: LovelaceResolvedIdentity
    public let cards: [LovelaceResolvedCard]
}

public struct LovelaceResolvedDashboard: Equatable {
    public let source: LovelaceConfig
    public let views: [LovelaceResolvedView]

    public init(source: LovelaceConfig) {
        self.source = source
        let root = LovelaceSourcePath()
        views = source.views.enumerated().map { index, view in
            let path = root.appending("views", index: index)
            return LovelaceResolvedView(
                source: view,
                identity: LovelaceResolvedIdentity(sourcePath: path, rawValue: view.rawValue),
                cards: Self.resolveCards(view.cards, parent: path)
            )
        }
    }

    private static func resolveCards(
        _ cards: [LovelaceCard],
        parent: LovelaceSourcePath
    ) -> [LovelaceResolvedCard] {
        cards.enumerated().map { index, card in
            let path = parent.appending("cards", index: index)
            let rows: [LovelaceResolvedRow]? = card.entities.map { entities in
                entities.enumerated().map { rowIndex, row in
                    let rowPath = path.appending("entities", index: rowIndex)
                    return LovelaceResolvedRow(
                        source: row,
                        identity: LovelaceResolvedIdentity(sourcePath: rowPath, rawValue: row.rawValue)
                    )
                }
            }
            let nested = card.cards.map { resolveCards($0, parent: path) }
            return LovelaceResolvedCard(
                source: card,
                identity: LovelaceResolvedIdentity(sourcePath: path, rawValue: card.rawValue),
                rows: rows,
                cards: nested
            )
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }

    func bool(_ key: String) -> Bool? {
        guard case let .bool(value)? = self[key] else { return nil }
        return value
    }

    func optionalString(_ key: String, path: String, diagnostics: inout [String]) -> String? {
        guard let value = self[key] else { return nil }
        guard case let .string(result) = value else {
            diagnostics.append("\(key) must be a string")
            return nil
        }
        return result
    }

    func optionalBool(_ key: String, path: String, diagnostics: inout [String]) -> Bool? {
        guard let value = self[key] else { return nil }
        guard case let .bool(result) = value else {
            diagnostics.append("\(key) must be a boolean")
            return nil
        }
        return result
    }

    func optionalInt(_ key: String, path: String, diagnostics: inout [String]) -> Int? {
        guard let value = self[key] else { return nil }
        guard case let .int(result) = value else {
            diagnostics.append("\(key) must be an integer")
            return nil
        }
        return result
    }

    func optionalDouble(_ key: String, path: String, diagnostics: inout [String]) -> Double? {
        guard let value = self[key] else { return nil }
        switch value {
        case let .int(result): return Double(result)
        case let .double(result): return result
        default:
            diagnostics.append("\(key) must be numeric")
            return nil
        }
    }
}
