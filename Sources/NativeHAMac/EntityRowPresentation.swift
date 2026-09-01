import AppKit
import Foundation
import NativeHACore

enum EntityRowKind: Equatable {
    case generic
    case deferredSpecialized
    case unsupported(String)
}

enum EntityStatePresentationKind: Equatable {
    case value
    case missing
    case unknown
    case unavailable
}

enum EntityStateColorRole: Equatable {
    case normal
    case unavailable
    case inactive
    case active
    case batteryHigh
    case batteryMedium
    case batteryLow
}

struct EntityIconPresentation: Equatable {
    let symbolName: String?
    let fallbackText: String?
    let semanticLabel: String
    let requestedIdentifier: String?
    let warning: String?
}

struct EntitySecondaryPresentation: Equatable {
    let visibleText: String
    let accessibilityLabel: String
    let accessibilityValue: String
}

enum EntityPrimaryAction: Equatable {
    case details(entityID: String)
    case toggle(isOn: Bool)
    case none
    case unsupported
}

struct EntityPowerRoute: Equatable {
    let domain: String
    let service: String
}

struct EntityRowPresentation: Equatable {
    let kind: EntityRowKind
    let entityID: String?
    let name: String
    let stateText: String
    let stateKind: EntityStatePresentationKind
    let icon: EntityIconPresentation
    let colorRole: EntityStateColorRole
    let secondary: EntitySecondaryPresentation?
    let primaryAction: EntityPrimaryAction
    let showsPowerControl: Bool
    let powerIsOn: Bool
    let warningText: String?

    var isSupported: Bool {
        if case .unsupported = kind { return false }
        return true
    }
}

enum EntityRowPresentationResolver {
    typealias SymbolAvailability = (String) -> Bool

    static let headerToggleDomains: Set<String> = [
        "fan", "input_boolean", "light", "switch", "group", "automation",
        "humidifier", "valve",
    ]

    static let implicitToggleDomains: Set<String> = [
        "alert", "automation", "fan", "input_boolean", "light",
        "remote", "siren", "switch", "vacuum",
    ]

    static let implicitSpecializedDomains: Set<String> = [
        "button", "cover", "date", "datetime", "event", "group", "humidifier",
        "input_button", "input_datetime", "input_number", "input_select", "input_text",
        "lock", "media_player", "number", "scene", "script", "select", "text", "time",
        "timer", "update", "valve", "water_heater",
    ]

    static let rowPowerDomains: Set<String> = [
        "alert", "automation", "cover", "fan", "group", "humidifier",
        "input_boolean", "light", "lock", "remote", "siren", "switch",
        "vacuum", "valve",
    ]

    static let statesOff: Set<String> = ["closed", "locked", "off"]

    static func resolve(
        row: LovelacePresentationRow,
        cardStateColor: Bool?,
        states: [String: HAState],
        registryDisplayPrecisions: [String: Int],
        registryIcons: [String: String],
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?,
        now: Date = Date(),
        symbolAvailability: SymbolAvailability = defaultSymbolAvailability
    ) -> EntityRowPresentation {
        let source = row.source
        let entityID = source.entity?.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = entityID.map(domainForEntityID) ?? ""
        let state = entityID.flatMap { states[$0] }
        let kind = rowKind(source: source, entityID: entityID, domain: domain)

        guard case .unsupported(let reason) = kind else {
            let resolvedName = name(
                source: source,
                entityID: entityID ?? "",
                state: state
            )
            let display = EntityStateFormatter.display(
                state: state,
                entityID: entityID ?? "",
                registryDisplayPrecision: entityID.flatMap { registryDisplayPrecisions[$0] },
                preferences: preferences,
                serverTimeZone: serverTimeZone,
                now: now
            )
            let icon = resolveIcon(
                source: source,
                entityID: entityID ?? "",
                state: state,
                registryIcon: entityID.flatMap { registryIcons[$0] },
                name: resolvedName.value,
                symbolAvailability: symbolAvailability
            )
            let effectiveStateColor: Bool? = {
                if let rowValue = source.stateColor { return rowValue }
                if source.type == nil || source.type == "conditional" { return cardStateColor }
                return nil
            }()
            let color = stateColorRole(
                state: state,
                domain: domain,
                effectiveSetting: effectiveStateColor
            )
            let secondary = secondaryPresentation(
                source.secondaryInfo,
                state: state,
                displayState: display.text,
                preferences: preferences,
                serverTimeZone: serverTimeZone,
                now: now
            )
            let canRenderPower = rendersPowerControl(source: source, domain: domain, state: state)
            let actions = actionPresentation(
                source: source,
                rowEntityID: entityID,
                canRenderPower: canRenderPower,
                powerIsOn: state?.state == "on"
            )
            let warnings = [resolvedName.warning, icon.warning, actions.warning].compactMap { $0 }
            let primaryAction: EntityPrimaryAction = kind == .deferredSpecialized
                ? .none
                : (state == nil ? .none : actions.action)
            return EntityRowPresentation(
                kind: kind,
                entityID: entityID,
                name: resolvedName.value,
                stateText: display.text,
                stateKind: display.kind,
                icon: icon,
                colorRole: color,
                secondary: secondary,
                primaryAction: primaryAction,
                showsPowerControl: canRenderPower,
                powerIsOn: state?.state == "on",
                warningText: warnings.isEmpty ? nil : warnings.joined(separator: "; ")
            )
        }

        let unsupportedName = entityID.map { fallbackName(entityID: $0, state: state) }
            ?? "Unsupported entity row"
        let icon = resolvedSymbol(
            preferred: "questionmark.square",
            semanticLabel: "Unsupported entity row icon",
            requestedIdentifier: source.icon,
            warning: nil,
            symbolAvailability: symbolAvailability
        )
        return EntityRowPresentation(
            kind: .unsupported(reason),
            entityID: entityID,
            name: unsupportedName,
            stateText: reason,
            stateKind: state == nil ? .missing : .value,
            icon: icon,
            colorRole: .normal,
            secondary: nil,
            primaryAction: .none,
            showsPowerControl: false,
            powerIsOn: false,
            warningText: reason
        )
    }

    static func displayName(entityID: String, state: HAState?) -> String {
        fallbackName(entityID: entityID, state: state)
    }

    static func headerConfiguredIntent(card: LovelacePresentationCard) -> Bool {
        let object = card.source.rawValue.objectValue ?? [:]
        if let explicit = object["show_header_toggle"] {
            return explicit.javascriptBoolean
        }
        guard object["title"] != nil else { return false }
        let count = (card.rows ?? []).reduce(into: 0) { result, row in
            guard let entityID = row.source.entity else { return }
            if headerToggleDomains.contains(domainForEntityID(entityID)) {
                result += 1
            }
        }
        return count >= 2
    }

    static func headerCandidates(
        card: LovelacePresentationCard,
        states: [String: HAState]
    ) -> [String] {
        var seen = Set<String>()
        return (card.rows ?? []).compactMap { row in
            guard let entityID = row.source.entity,
                  states[entityID] != nil,
                  headerToggleDomains.contains(domainForEntityID(entityID)),
                  seen.insert(entityID).inserted
            else { return nil }
            return entityID
        }
    }

    static func headerChecked(candidates: [String], states: [String: HAState]) -> Bool {
        candidates.contains { states[$0]?.state == "on" }
    }

    static func headerTransitionTargets(
        candidates: [String],
        states: [String: HAState],
        isOn: Bool
    ) -> [String] {
        candidates.filter { entityID in
            guard let state = states[entityID],
                  state.state != "unknown", state.state != "unavailable"
            else { return false }
            return isOn ? statesOff.contains(state.state) : !statesOff.contains(state.state)
        }
    }

    static func rowPowerRoute(entityID: String, isOn: Bool) -> EntityPowerRoute? {
        let domain = domainForEntityID(entityID)
        guard rowPowerDomains.contains(domain) else { return nil }
        switch (domain, isOn) {
        case ("cover", true): return EntityPowerRoute(domain: domain, service: "open_cover")
        case ("cover", false): return EntityPowerRoute(domain: domain, service: "close_cover")
        case ("lock", true): return EntityPowerRoute(domain: domain, service: "unlock")
        case ("lock", false): return EntityPowerRoute(domain: domain, service: "lock")
        case ("valve", true): return EntityPowerRoute(domain: domain, service: "open_valve")
        case ("valve", false): return EntityPowerRoute(domain: domain, service: "close_valve")
        case ("group", true): return EntityPowerRoute(domain: "homeassistant", service: "turn_on")
        case ("group", false): return EntityPowerRoute(domain: "homeassistant", service: "turn_off")
        default: return EntityPowerRoute(domain: domain, service: isOn ? "turn_on" : "turn_off")
        }
    }

    static func headerPowerRoute(isOn: Bool) -> EntityPowerRoute {
        EntityPowerRoute(domain: "homeassistant", service: isOn ? "turn_on" : "turn_off")
    }

    static func equivalentPowerRoutes(entityID: String) -> [EntityPowerRoute] {
        var routes = [headerPowerRoute(isOn: true), headerPowerRoute(isOn: false)]
        for isOn in [true, false] {
            guard let route = rowPowerRoute(entityID: entityID, isOn: isOn),
                  !routes.contains(route)
            else { continue }
            routes.append(route)
        }
        return routes
    }

    private static func rowKind(
        source: LovelaceEntityRef,
        entityID: String?,
        domain: String
    ) -> EntityRowKind {
        guard let entityID = entityID, !entityID.isEmpty else {
            return .unsupported("Entity row has no nonempty entity")
        }
        guard hasValidTypedFieldsExceptName(source.rawValue) else {
            return .unsupported("Entity row has malformed typed fields")
        }
        if let type = source.type {
            switch type {
            case "simple-entity", "sensor-entity": return .generic
            case "toggle-entity":
                return rowPowerDomains.contains(domain)
                    ? .generic
                    : .unsupported("toggle-entity has no safe native route for \(entityID)")
            default: return .unsupported("Unsupported entity row type: \(type)")
            }
        }
        if domain == "climate" || domain == "weather" { return .deferredSpecialized }
        if implicitSpecializedDomains.contains(domain) {
            return .unsupported("Unsupported specialized entity row domain: \(domain)")
        }
        return .generic
    }

    private static func hasValidTypedFieldsExceptName(_ raw: JSONValue) -> Bool {
        if case .string = raw { return true }
        guard case let .object(object) = raw else { return false }
        for key in ["entity", "type", "color", "icon", "secondary_info"] {
            if let value = object[key], case .string = value {} else if object[key] != nil { return false }
        }
        guard object["entity"] != nil else { return false }
        for key in ["state_color", "show_name", "show_icon"] {
            if let value = object[key], case .bool = value {} else if object[key] != nil { return false }
        }
        return true
    }

    private static func name(
        source: LovelaceEntityRef,
        entityID: String,
        state: HAState?
    ) -> (value: String, warning: String?) {
        guard case let .object(object) = source.rawValue,
              let rawName = object["name"], rawName != .null
        else {
            return (source.name ?? fallbackName(entityID: entityID, state: state), nil)
        }
        if case let .string(value) = rawName { return (value, nil) }
        let items: [JSONValue]
        if case let .array(values) = rawName { items = values } else { items = [rawName] }
        if items.isEmpty { return ("", nil) }
        var parts: [String] = []
        var unsupportedItems: [String] = []
        for item in items {
            guard case let .object(value) = item,
                  case let .string(type)? = value["type"]
            else {
                unsupportedItems.append("invalid")
                continue
            }
            switch type {
            case "text":
                if case let .string(text)? = value["text"] {
                    parts.append(text)
                } else {
                    unsupportedItems.append("text")
                }
            case "entity":
                let component = fallbackName(entityID: entityID, state: state)
                if !component.isEmpty { parts.append(component) }
            case "device", "area", "floor":
                unsupportedItems.append(type)
            default:
                unsupportedItems.append(type)
            }
        }
        let name = parts.isEmpty
            ? fallbackName(entityID: entityID, state: state)
            : parts.joined(separator: " ")
        let warning = unsupportedItems.isEmpty
            ? nil
            : "Unsupported structured name item: \(unsupportedItems.joined(separator: ", "))"
        return (name, warning)
    }

    private static func fallbackName(entityID: String, state: HAState?) -> String {
        if let value = state?.attributes["friendly_name"] {
            switch value {
            case .null: return ""
            case let .string(value): return value
            case let .int(value): return String(value)
            case let .double(value): return String(value)
            case let .bool(value): return value ? "true" : "false"
            case .array, .object: break
            }
        }
        return entityID.split(separator: ".", maxSplits: 1).last
            .map { String($0).replacingOccurrences(of: "_", with: " ") }
            ?? entityID
    }

    private static func rendersPowerControl(
        source: LovelaceEntityRef,
        domain: String,
        state: HAState?
    ) -> Bool {
        let selected = source.type == "toggle-entity" ||
            (source.type == nil && implicitToggleDomains.contains(domain))
        guard selected, let state = state else { return false }
        return state.state == "on" || state.state == "off" ||
            state.state == "unknown" || state.state == "unavailable"
    }

    private static func actionPresentation(
        source: LovelaceEntityRef,
        rowEntityID: String?,
        canRenderPower: Bool,
        powerIsOn: Bool
    ) -> (action: EntityPrimaryAction, warning: String?) {
        let tap = classifyTapAction(
            source.tapAction,
            rowEntityID: rowEntityID,
            canRenderPower: canRenderPower,
            powerIsOn: powerIsOn
        )
        var unsupported: [String] = []
        if tap.action == .unsupported { unsupported.append("tap_action") }
        if isUnsupportedSecondaryGesture(source.holdAction) { unsupported.append("hold_action") }
        if isUnsupportedSecondaryGesture(source.doubleTapAction) { unsupported.append("double_tap_action") }
        return (
            tap.action,
            unsupported.isEmpty ? nil : "Unsupported action: \(unsupported.joined(separator: ", "))"
        )
    }

    private static func classifyTapAction(
        _ raw: JSONValue?,
        rowEntityID: String?,
        canRenderPower: Bool,
        powerIsOn: Bool
    ) -> (action: EntityPrimaryAction, recognized: Bool) {
        guard let raw = raw else {
            return (rowEntityID.map(EntityPrimaryAction.details) ?? .none, true)
        }
        guard case let .object(object) = raw,
              object["confirmation"] == nil,
              case let .string(action)? = object["action"]
        else { return (.unsupported, false) }
        switch action {
        case "none": return (.none, true)
        case "more-info":
            let target: String?
            if case let .string(value)? = object["entity"] { target = value } else { target = rowEntityID }
            return (target.map(EntityPrimaryAction.details) ?? .none, true)
        case "toggle":
            return canRenderPower ? (.toggle(isOn: !powerIsOn), true) : (.unsupported, false)
        default: return (.unsupported, false)
        }
    }

    private static func isUnsupportedSecondaryGesture(_ raw: JSONValue?) -> Bool {
        guard let raw = raw else { return false }
        guard case let .object(object) = raw,
              object["confirmation"] == nil,
              case let .string(action)? = object["action"]
        else { return true }
        return action != "none"
    }

    private static func resolveIcon(
        source: LovelaceEntityRef,
        entityID: String,
        state: HAState?,
        registryIcon: String?,
        name: String,
        symbolAvailability: SymbolAvailability
    ) -> EntityIconPresentation {
        let stateIcon = state?.attributes["icon"]?.stringValue
        let request = source.icon ?? registryIcon ?? stateIcon
        let direct = request.flatMap(directIconSymbol)
        let unsupported = request != nil && direct == nil
        let preferred = direct ?? semanticIcon(entityID: entityID, state: state)
        let warning = unsupported ? "Unsupported icon identifier: \(request!)" : nil
        return resolvedSymbol(
            preferred: preferred,
            semanticLabel: "\(name.isEmpty ? entityID : name) icon",
            requestedIdentifier: request,
            warning: warning,
            symbolAvailability: symbolAvailability
        )
    }

    private static func directIconSymbol(_ identifier: String) -> String? {
        switch identifier {
        case "mdi:thermometer": return "thermometer"
        case "mdi:water-percent", "mdi:humidity": return "drop"
        case "mdi:battery": return "battery.100"
        case "mdi:home": return "house"
        case "mdi:map-marker": return "location"
        case "mdi:toggle-switch": return "switch.2"
        case "mdi:cog": return "gearshape.2"
        case "mdi:update": return "arrow.triangle.2.circlepath"
        default: return nil
        }
    }

    private static func semanticIcon(entityID: String, state: HAState?) -> String {
        guard let state = state else { return "questionmark.square" }
        if state.state == "unavailable" { return "exclamationmark.triangle" }
        if state.state == "unknown" { return "questionmark.circle" }
        let domain = domainForEntityID(entityID)
        let deviceClass = state.attributes["device_class"]?.stringValue
        if deviceClass == "temperature" { return "thermometer" }
        if deviceClass == "humidity" { return "drop" }
        if deviceClass == "battery" || domain == "battery" {
            guard let value = Double(state.state) else { return "battery.100" }
            return value >= 70 ? "battery.100" : (value >= 30 ? "battery.50" : "battery.25")
        }
        if domain == "device_tracker" || domain == "person" {
            return state.state == "home" ? "house" : "location"
        }
        switch domain {
        case "sensor": return "gauge"
        case "binary_sensor": return "sensor"
        case "switch", "input_boolean": return "switch.2"
        case "automation": return "gearshape.2"
        case "weather": return "cloud.sun"
        case "climate": return "thermometer"
        case "fan": return "fanblades"
        case "button": return "circle"
        case "zone": return "mappin.and.ellipse"
        case "number": return "number.square"
        case "script": return "scroll"
        case "select": return "list.bullet.rectangle"
        case "update": return "arrow.triangle.2.circlepath"
        default: return "circle.grid.2x2"
        }
    }

    private static func resolvedSymbol(
        preferred: String,
        semanticLabel: String,
        requestedIdentifier: String?,
        warning: String?,
        symbolAvailability: SymbolAvailability
    ) -> EntityIconPresentation {
        if symbolAvailability(preferred) {
            return EntityIconPresentation(
                symbolName: preferred,
                fallbackText: nil,
                semanticLabel: semanticLabel,
                requestedIdentifier: requestedIdentifier,
                warning: warning
            )
        }
        if symbolAvailability("circle.grid.2x2") {
            return EntityIconPresentation(
                symbolName: "circle.grid.2x2",
                fallbackText: nil,
                semanticLabel: semanticLabel,
                requestedIdentifier: requestedIdentifier,
                warning: warning
            )
        }
        return EntityIconPresentation(
            symbolName: nil,
            fallbackText: "?",
            semanticLabel: semanticLabel,
            requestedIdentifier: requestedIdentifier,
            warning: warning
        )
    }

    private static func stateColorRole(
        state: HAState?,
        domain: String,
        effectiveSetting: Bool?
    ) -> EntityStateColorRole {
        let enabled = effectiveSetting ?? (domain == "light")
        guard enabled else { return .normal }
        guard let state = state else { return .normal }
        if state.state == "unavailable" { return .unavailable }
        if state.attributes["device_class"]?.stringValue == "battery",
           let value = Double(state.state)
        {
            return value >= 70 ? .batteryHigh : (value >= 30 ? .batteryMedium : .batteryLow)
        }
        if state.state == "unknown" { return .inactive }
        guard coloredDomains.contains(domain) else { return .normal }
        let active: Bool
        switch domain {
        case "alarm_control_panel": active = state.state != "disarmed"
        case "alert": active = state.state != "idle"
        case "cover", "valve": active = state.state != "closed"
        case "lock": active = state.state != "locked"
        case "device_tracker", "person": active = state.state != "not_home"
        case "lawn_mower": active = state.state != "docked" && state.state != "paused"
        case "media_player": active = state.state != "standby"
        case "vacuum": active = !["idle", "docked", "paused"].contains(state.state)
        case "plant": active = state.state == "problem"
        case "timer": active = state.state == "active"
        case "camera": active = state.state == "streaming"
        case "group": active = ["on", "home", "open", "locked", "problem"].contains(state.state)
        default: active = state.state != "off"
        }
        return active ? .active : .inactive
    }

    private static let coloredDomains: Set<String> = [
        "alarm_control_panel", "alert", "automation", "binary_sensor", "calendar",
        "camera", "climate", "cover", "device_tracker", "fan", "group", "humidifier",
        "input_boolean", "lawn_mower", "light", "lock", "media_player", "person",
        "plant", "remote", "schedule", "script", "siren", "sun", "switch", "timer",
        "update", "vacuum", "valve", "water_heater", "weather",
    ]

    private static func secondaryPresentation(
        _ kind: String?,
        state: HAState?,
        displayState: String,
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?,
        now: Date
    ) -> EntitySecondaryPresentation? {
        guard let kind = kind, let state = state else { return nil }
        switch kind {
        case "entity-id":
            return EntitySecondaryPresentation(
                visibleText: state.entityId,
                accessibilityLabel: "Entity ID",
                accessibilityValue: state.entityId
            )
        case "state":
            return EntitySecondaryPresentation(
                visibleText: displayState,
                accessibilityLabel: "State",
                accessibilityValue: displayState
            )
        case "position", "tilt-position":
            let key = kind == "position" ? "current_position" : "current_tilt_position"
            guard let value = state.attributes[key]?.scalarString else { return nil }
            let label = kind == "position" ? "Position" : "Tilt position"
            return EntitySecondaryPresentation(
                visibleText: "\(label): \(value)",
                accessibilityLabel: label,
                accessibilityValue: value
            )
        case "brightness":
            guard let raw = state.attributes["brightness"]?.numericValue, raw > 0 else { return nil }
            let percent = Int((raw / 255 * 100).rounded())
            return EntitySecondaryPresentation(
                visibleText: "\(percent) %",
                accessibilityLabel: "Brightness",
                accessibilityValue: "\(percent) percent"
            )
        case "last-triggered":
            guard let value = state.attributes["last_triggered"]?.stringValue else {
                return EntitySecondaryPresentation(
                    visibleText: "Never triggered",
                    accessibilityLabel: "Last triggered",
                    accessibilityValue: "Never triggered"
                )
            }
            return timestampSecondary(
                value: value, label: "Last triggered", preferences: preferences,
                serverTimeZone: serverTimeZone, now: now
            )
        case "last-changed":
            guard let value = state.lastChanged else { return nil }
            return timestampSecondary(
                value: value, label: "Last changed", preferences: preferences,
                serverTimeZone: serverTimeZone, now: now
            )
        case "last-updated":
            guard let value = state.lastUpdated else { return nil }
            return timestampSecondary(
                value: value, label: "Last updated", preferences: preferences,
                serverTimeZone: serverTimeZone, now: now
            )
        default: return nil
        }
    }

    private static func timestampSecondary(
        value: String,
        label: String,
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?,
        now: Date
    ) -> EntitySecondaryPresentation? {
        guard let date = EntityStateFormatter.parseISO8601(value) else { return nil }
        let locale = Locale(identifier: preferences?.language ?? Locale.current.identifier)
        let relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.unitsStyle = .full
        let visible = relative.localizedString(for: date, relativeTo: now)
        let accessibility = EntityStateFormatter.dateTimeFormatter(
            preferences: preferences,
            serverTimeZone: serverTimeZone
        ).string(from: date)
        return EntitySecondaryPresentation(
            visibleText: visible,
            accessibilityLabel: label,
            accessibilityValue: accessibility
        )
    }

    private static func domainForEntityID(_ entityID: String) -> String {
        String(entityID.split(separator: ".", maxSplits: 1).first ?? "")
    }

    private static func defaultSymbolAvailability(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

enum EntityStateFormatter {
    struct Display: Equatable {
        let text: String
        let kind: EntityStatePresentationKind
    }

    static func display(
        state: HAState?,
        entityID: String,
        registryDisplayPrecision: Int?,
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?,
        now: Date
    ) -> Display {
        guard let state = state else { return Display(text: "Missing entity", kind: .missing) }
        if state.state == "unknown" { return Display(text: "Unknown", kind: .unknown) }
        if state.state == "unavailable" { return Display(text: "Unavailable", kind: .unavailable) }
        let domain = String(entityID.split(separator: ".", maxSplits: 1).first ?? "")
        let deviceClass = state.attributes["device_class"]?.stringValue
        let numeric = state.attributes["unit_of_measurement"] != nil ||
            state.attributes["state_class"] != nil ||
            ["counter", "input_number", "number"].contains(domain) ||
            (domain == "sensor" && numericSensorDeviceClasses.contains(deviceClass ?? ""))
        if numeric, let value = Double(state.state) {
            if deviceClass == "duration",
               let unit = state.attributes["unit_of_measurement"]?.stringValue,
               ["min", "h", "d"].contains(unit)
            {
                return Display(
                    text: duration(value, unit: unit, precision: registryDisplayPrecision),
                    kind: .value
                )
            }
            if deviceClass == "monetary",
               let currency = state.attributes["unit_of_measurement"]?.stringValue
            {
                let formatter = numberFormatter(
                    state: state,
                    precision: registryDisplayPrecision,
                    preferences: preferences
                )
                formatter.numberStyle = .currency
                formatter.currencyCode = currency
                return Display(text: formatter.string(from: NSNumber(value: value)) ?? state.state, kind: .value)
            }
            let formatter = numberFormatter(
                state: state,
                precision: registryDisplayPrecision,
                preferences: preferences
            )
            let valueText = formatter.string(from: NSNumber(value: value)) ?? state.state
            guard let unit = state.attributes["unit_of_measurement"]?.stringValue, !unit.isEmpty else {
                return Display(text: valueText, kind: .value)
            }
            return Display(
                text: valueText + blankBeforeUnit(unit, language: preferences?.language) + unit,
                kind: .value
            )
        }
        if ["date", "input_datetime", "time"].contains(domain),
           let formatted = timezoneAgnosticDateTime(
               state.state, preferences: preferences, now: now
           )
        {
            return Display(text: formatted, kind: .value)
        }
        if timestampStateDomains.contains(domain) ||
            (domain == "sensor" && ["timestamp", "uptime"].contains(deviceClass ?? ""))
        {
            if let date = parseISO8601(state.state) {
                return Display(
                    text: dateTimeFormatter(
                        preferences: preferences,
                        serverTimeZone: serverTimeZone
                    ).string(from: date),
                    kind: .value
                )
            }
        }
        return Display(text: state.state, kind: .value)
    }

    static func dateTimeFormatter(
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?
    ) -> DateFormatter {
        let formatter = DateFormatter()
        let locale = Locale(identifier: preferences?.language ?? Locale.current.identifier)
        formatter.locale = locale
        formatter.timeZone = resolvedTimeZone(preferences: preferences, serverTimeZone: serverTimeZone)
        let hour = preferences?.timeFormat == "12" ? "h" :
            (preferences?.timeFormat == "24" ? "HH" : "j")
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "yMMMd\(hour)mm",
            options: 0,
            locale: locale
        )
        return formatter
    }

    static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func numberFormatter(
        state: HAState,
        precision: Int?,
        preferences: HAFrontendLocalePreferences?
    ) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = numberLocale(preferences)
        formatter.usesGroupingSeparator = preferences?.numberFormat != "none"
        if let precision = precision {
            let digits = min(max(precision, 0), 15)
            formatter.minimumFractionDigits = digits
            formatter.maximumFractionDigits = digits
        } else if let step = state.attributes["step"]?.numericValue,
                  step.rounded() == step,
                  let value = Double(state.state), value.rounded() == value
        {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        } else {
            let digits = fractionDigits(in: state.state)
            formatter.minimumFractionDigits = digits
            formatter.maximumFractionDigits = digits
        }
        return formatter
    }

    private static func numberLocale(_ preferences: HAFrontendLocalePreferences?) -> Locale {
        switch preferences?.numberFormat {
        case "comma_decimal", "none": return Locale(identifier: "en_US")
        case "decimal_comma": return Locale(identifier: "de_DE")
        case "space_comma": return Locale(identifier: "fr_FR")
        case "quote_decimal": return Locale(identifier: "de_CH")
        case "system": return .current
        default:
            return Locale(identifier: preferences?.language ?? Locale.current.identifier)
        }
    }

    private static func fractionDigits(in raw: String) -> Int {
        guard let decimal = raw.firstIndex(of: ".") else { return 0 }
        let suffix = raw[raw.index(after: decimal)...]
        let digits = suffix.prefix { $0.isNumber }.count
        return min(digits, 15)
    }

    private static func duration(_ value: Double, unit: String, precision: Int?) -> String {
        let multiplier = pow(10.0, Double(min(max(precision ?? 15, 0), 15)))
        let rounded = (value * multiplier).rounded() / multiplier
        let seconds: TimeInterval
        let allowedUnits: NSCalendar.Unit
        switch unit {
        case "d":
            seconds = rounded * 86_400
            allowedUnits = [.day, .hour]
        case "h":
            seconds = rounded * 3_600
            allowedUnits = [.hour, .minute]
        default:
            seconds = rounded * 60
            allowedUnits = [.minute, .second]
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = allowedUnits
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? String(value)
    }

    private static func timezoneAgnosticDateTime(
        _ value: String,
        preferences: HAFrontendLocalePreferences?,
        now: Date
    ) -> String? {
        let locale = Locale(identifier: preferences?.language ?? Locale.current.identifier)
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(secondsFromGMT: 0)
        let output = DateFormatter()
        output.locale = locale
        output.timeZone = TimeZone(secondsFromGMT: 0)
        if value.contains(" ") {
            input.dateFormat = value.split(separator: ":").count > 2
                ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
            guard let date = input.date(from: value) else { return nil }
            let hour = preferences?.timeFormat == "12" ? "h" : "HH"
            output.dateFormat = DateFormatter.dateFormat(fromTemplate: "yMMMd\(hour)mm", options: 0, locale: locale)
            return output.string(from: date)
        }
        if value.contains("-") {
            input.dateFormat = "yyyy-MM-dd"
            guard let date = input.date(from: value) else { return nil }
            output.dateFormat = DateFormatter.dateFormat(fromTemplate: "yMMMd", options: 0, locale: locale)
            return output.string(from: date)
        }
        if value.contains(":") {
            input.dateFormat = value.split(separator: ":").count > 2 ? "HH:mm:ss" : "HH:mm"
            guard let date = input.date(from: value) else { return nil }
            let hour = preferences?.timeFormat == "12" ? "h" : "HH"
            output.dateFormat = DateFormatter.dateFormat(fromTemplate: "\(hour)mm", options: 0, locale: locale)
            return output.string(from: date)
        }
        return nil
    }

    private static func resolvedTimeZone(
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?
    ) -> TimeZone {
        if preferences?.timeZone == "server",
           let serverTimeZone = serverTimeZone,
           let timeZone = TimeZone(identifier: serverTimeZone)
        {
            return timeZone
        }
        return .current
    }

    private static func blankBeforeUnit(_ unit: String, language: String?) -> String {
        if unit == "°" { return "" }
        if unit == "%" {
            let code = language?.split(separator: "-").first.map(String.init) ?? ""
            return ["cs", "de", "fi", "fr", "sk", "sv"].contains(code) ? " " : ""
        }
        return " "
    }

    private static let numericSensorDeviceClasses: Set<String> = [
        "apparent_power", "aqi", "atmospheric_pressure", "battery", "carbon_dioxide",
        "carbon_monoxide", "conductivity", "current", "data_rate", "data_size",
        "distance", "duration", "energy", "energy_distance", "energy_storage",
        "frequency", "gas", "humidity", "illuminance", "irradiance", "moisture",
        "monetary", "nitrogen_dioxide", "nitrogen_monoxide", "nitrous_oxide",
        "ozone", "ph", "pm1", "pm10", "pm25", "power", "power_factor",
        "precipitation", "precipitation_intensity", "pressure", "reactive_energy",
        "reactive_power", "signal_strength", "sound_pressure", "speed", "sulphur_dioxide",
        "temperature", "volatile_organic_compounds", "volatile_organic_compounds_parts",
        "voltage", "volume", "volume_flow_rate", "volume_storage", "water", "weight",
        "wind_direction", "wind_speed",
    ]

    private static let timestampStateDomains: Set<String> = [
        "ai_task", "button", "conversation", "event", "image", "infrared",
        "input_button", "notify", "radio_frequency", "scene", "stt", "tag",
        "tts", "wake_word", "datetime",
    ]
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var scalarString: String? {
        switch self {
        case let .string(value): return value
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return ""
        case .array, .object: return nil
        }
    }

    var numericValue: Double? {
        switch self {
        case let .int(value): return Double(value)
        case let .double(value): return value
        case let .string(value): return Double(value)
        default: return nil
        }
    }

    var javascriptBoolean: Bool {
        switch self {
        case .null: return false
        case let .bool(value): return value
        case let .int(value): return value != 0
        case let .double(value): return value != 0 && !value.isNaN
        case let .string(value): return !value.isEmpty
        case .array, .object: return true
        }
    }
}
