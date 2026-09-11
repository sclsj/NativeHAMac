import Foundation
import NativeHACore

struct WeatherCardConfiguration: Equatable {
    let entityID: String
    let rawName: JSONValue?
    let showCurrent: Bool?
    let showForecast: Bool?
    let forecastType: String?
    let forecastSlots: Int?
    let secondaryInfoAttribute: String?
    let roundTemperature: Bool?
    let tapAction: JSONValue?
    let holdAction: JSONValue?
    let doubleTapAction: JSONValue?

    init(card: LovelacePresentationCard) {
        entityID = card.entity ?? ""
        rawName = card.nameValue
        showCurrent = card.showCurrent
        showForecast = card.showForecast
        forecastType = card.forecastType
        forecastSlots = card.forecastSlots
        secondaryInfoAttribute = card.secondaryInfoAttribute
        roundTemperature = card.roundTemperature
        tapAction = card.tapAction
        holdAction = card.holdAction
        doubleTapAction = card.doubleTapAction
    }
}

enum WeatherStatePresentationKind: Equatable {
    case current
    case missing
    case unknown
    case unavailable
}

enum WeatherPrimaryAction: Equatable {
    case details(entityID: String)
    case none
    case unsupported
}

struct WeatherSecondaryPresentation: Equatable {
    let attribute: String
    let label: String
    let value: String

    var visibleText: String { value }
    var accessibilityValue: String { "\(label): \(value)" }
}

struct WeatherCardPresentation: Equatable {
    let configuration: WeatherCardConfiguration
    let cardIdentity: LovelaceResolvedIdentity
    let stateKind: WeatherStatePresentationKind
    let name: String
    let condition: String
    let icon: WeatherIconPresentation
    let temperature: String?
    let secondary: WeatherSecondaryPresentation?
    let primaryAction: WeatherPrimaryAction
    let warningText: String?

    /// Forecast is unavailable in this milestone, so hass-frontend's
    /// `!forecast || show_current !== false` is true for every flag matrix.
    var rendersCurrent: Bool { true }
    var isActionable: Bool {
        if case .details = primaryAction { return stateKind != .missing }
        return false
    }
}

enum WeatherPresentationResolver {
    typealias SymbolAvailability = WeatherIconResolver.SymbolAvailability

    static func resolve(
        card: LovelacePresentationCard,
        state: HAState?,
        serverUnitSystem: HAUnitSystem?,
        preferences: HAFrontendLocalePreferences?,
        symbolAvailability: SymbolAvailability = WeatherIconResolver.defaultSymbolAvailability
    ) -> WeatherCardPresentation {
        resolve(
            card: card,
            state: state,
            serverUnitSystem: serverUnitSystem,
            preferences: preferences,
            iconResolver: { condition in
                WeatherIconResolver.resolve(
                    condition: condition,
                    symbolAvailability: symbolAvailability
                )
            },
            missingIcon: { WeatherIconResolver.missing(symbolAvailability: symbolAvailability) },
            unknownIcon: { WeatherIconResolver.unknown(symbolAvailability: symbolAvailability) },
            unavailableIcon: { WeatherIconResolver.unavailable(symbolAvailability: symbolAvailability) }
        )
    }

    private static func resolve(
        card: LovelacePresentationCard,
        state: HAState?,
        serverUnitSystem: HAUnitSystem?,
        preferences: HAFrontendLocalePreferences?,
        iconResolver: (String) -> WeatherIconPresentation,
        missingIcon: () -> WeatherIconPresentation,
        unknownIcon: () -> WeatherIconPresentation,
        unavailableIcon: () -> WeatherIconPresentation
    ) -> WeatherCardPresentation {
        let config = WeatherCardConfiguration(card: card)
        let entityID = config.entityID
        let name = resolvedName(config: config, state: state)
        var warnings = card.source.advisories.map(\.message)
        let action = primaryAction(config: config)
        if action == .unsupported { warnings.append("unsupported weather tap_action") }
        if unsupportedSecondaryGesture(config.holdAction) {
            warnings.append("unsupported weather hold_action")
        }
        if unsupportedSecondaryGesture(config.doubleTapAction) {
            warnings.append("unsupported weather double_tap_action")
        }

        guard let state = state else {
            return WeatherCardPresentation(
                configuration: config,
                cardIdentity: card.identity,
                stateKind: .missing,
                name: name,
                condition: "Missing entity: \(entityID)",
                icon: missingIcon(),
                temperature: nil,
                secondary: nil,
                primaryAction: .none,
                warningText: warnings.isEmpty ? nil : warnings.joined(separator: "; ")
            )
        }

        if state.state == "unknown" || state.state == "unavailable" {
            let unavailable = state.state == "unavailable"
            return WeatherCardPresentation(
                configuration: config,
                cardIdentity: card.identity,
                stateKind: unavailable ? .unavailable : .unknown,
                name: name,
                condition: unavailable ? "Unavailable" : "Unknown",
                icon: unavailable ? unavailableIcon() : unknownIcon(),
                temperature: nil,
                secondary: nil,
                primaryAction: action,
                warningText: warnings.isEmpty ? nil : warnings.joined(separator: "; ")
            )
        }

        let temperature = formattedAttribute(
            "temperature",
            state: state,
            serverUnitSystem: serverUnitSystem,
            preferences: preferences,
            maximumFractionDigits: config.roundTemperature == true ? 0 : 2
        )
        let secondary = secondaryPresentation(
            configuredAttribute: config.secondaryInfoAttribute,
            state: state,
            serverUnitSystem: serverUnitSystem,
            preferences: preferences,
            roundTemperature: config.roundTemperature == true
        )
        return WeatherCardPresentation(
            configuration: config,
            cardIdentity: card.identity,
            stateKind: .current,
            name: name,
            condition: conditionLabel(state.state),
            icon: iconResolver(state.state),
            temperature: temperature,
            secondary: secondary,
            primaryAction: action,
            warningText: warnings.isEmpty ? nil : warnings.joined(separator: "; ")
        )
    }

    static func conditionLabel(_ raw: String) -> String {
        switch raw {
        case "clear-night": return "Clear night"
        case "cloudy": return "Cloudy"
        case "fog": return "Fog"
        case "hail": return "Hail"
        case "lightning": return "Lightning"
        case "lightning-rainy": return "Lightning rainy"
        case "partlycloudy": return "Partly cloudy"
        case "pouring": return "Pouring"
        case "rainy": return "Rainy"
        case "snowy": return "Snowy"
        case "snowy-rainy": return "Snowy rainy"
        case "sunny": return "Sunny"
        case "windy": return "Windy"
        case "windy-variant": return "Windy variant"
        case "exceptional": return "Exceptional"
        default:
            let cleaned = raw
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return raw }
            return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
    }

    static func primaryAction(config: WeatherCardConfiguration) -> WeatherPrimaryAction {
        guard let raw = config.tapAction else {
            return config.entityID.isEmpty ? .none : .details(entityID: config.entityID)
        }
        guard case let .object(object) = raw,
              object["confirmation"] == nil,
              case let .string(action)? = object["action"]
        else { return .unsupported }
        switch action {
        case "none":
            return .none
        case "more-info":
            if let target = object["entity"] {
                guard case let .string(entityID) = target, !entityID.isEmpty else {
                    return .unsupported
                }
                return .details(entityID: entityID)
            }
            return config.entityID.isEmpty ? .none : .details(entityID: config.entityID)
        default:
            return .unsupported
        }
    }

    private static func unsupportedSecondaryGesture(_ raw: JSONValue?) -> Bool {
        guard let raw = raw else { return false }
        guard case let .object(object) = raw,
              object["confirmation"] == nil,
              case let .string(action)? = object["action"]
        else { return true }
        return action != "none"
    }

    private static func resolvedName(config: WeatherCardConfiguration, state: HAState?) -> String {
        if case let .string(value)? = config.rawName { return value }
        if let friendlyName = state?.attributes["friendly_name"] {
            switch friendlyName {
            case .null: return ""
            case let .string(value): return value
            case let .int(value): return String(value)
            case let .double(value): return String(value)
            case let .bool(value): return value ? "true" : "false"
            case .array, .object: break
            }
        }
        return config.entityID.split(separator: ".", maxSplits: 1).last
            .map { String($0).replacingOccurrences(of: "_", with: " ") }
            ?? config.entityID
    }

    private static func secondaryPresentation(
        configuredAttribute: String?,
        state: HAState,
        serverUnitSystem: HAUnitSystem?,
        preferences: HAFrontendLocalePreferences?,
        roundTemperature: Bool
    ) -> WeatherSecondaryPresentation? {
        if let attribute = configuredAttribute {
            let label = attributeLabel(attribute)
            if attribute == "wind_speed" {
                let speedText: String
                if let raw = state.attributes[attribute], raw != .null {
                    if let speed = numericValue(raw), speed.isFinite {
                        speedText = formatNumber(
                            speed,
                            preferences: preferences,
                            maximumFractionDigits: 2
                        ) + unitSuffix(
                            weatherUnit(attribute, state: state, serverUnitSystem: serverUnitSystem),
                            preferences: preferences
                        )
                    } else if case let .string(value) = raw {
                        // Preserve the formatter's raw scalar fallback. A
                        // malformed present value must not be confused with a
                        // missing speed or fabricated into a number or unit.
                        speedText = value
                    } else {
                        speedText = "Unknown"
                    }
                } else {
                    speedText = "-"
                }
                let bearing = windBearing(state.attributes["wind_bearing"])
                return WeatherSecondaryPresentation(
                    attribute: attribute,
                    label: label,
                    value: bearing.map { "\(speedText) (\($0))" } ?? speedText
                )
            }
            guard let raw = state.attributes[attribute], raw != .null else {
                return WeatherSecondaryPresentation(attribute: attribute, label: label, value: "Unknown")
            }
            guard let value = formattedAttribute(
                attribute,
                state: state,
                serverUnitSystem: serverUnitSystem,
                preferences: preferences,
                maximumFractionDigits: roundTemperature && temperatureAttributes.contains(attribute) ? 0 : 2
            ) else {
                return WeatherSecondaryPresentation(attribute: attribute, label: label, value: "Unknown")
            }
            return WeatherSecondaryPresentation(attribute: attribute, label: label, value: value)
        }

        guard let raw = state.attributes["humidity"], raw != .null,
              numericValue(raw) != nil,
              let value = formattedAttribute(
                  "humidity",
                  state: state,
                  serverUnitSystem: serverUnitSystem,
                  preferences: preferences,
                  maximumFractionDigits: 1
              )
        else { return nil }
        return WeatherSecondaryPresentation(attribute: "humidity", label: "Humidity", value: value)
    }

    static func formattedAttribute(
        _ attribute: String,
        state: HAState,
        serverUnitSystem: HAUnitSystem?,
        preferences: HAFrontendLocalePreferences?,
        maximumFractionDigits: Int
    ) -> String? {
        guard let raw = state.attributes[attribute], raw != .null else { return nil }
        let valueText: String
        if let value = numericValue(raw), value.isFinite {
            valueText = formatNumber(
                value,
                preferences: preferences,
                maximumFractionDigits: maximumFractionDigits
            )
        } else if case let .string(value) = raw {
            valueText = value
        } else {
            return nil
        }
        let unit = weatherUnit(attribute, state: state, serverUnitSystem: serverUnitSystem)
        return valueText + unitSuffix(unit, preferences: preferences)
    }

    static func numericValue(_ value: JSONValue) -> Double? {
        switch value {
        case let .int(value): return Double(value)
        case let .double(value): return value
        case let .string(value): return Double(value)
        default: return nil
        }
    }

    static func weatherUnit(
        _ attribute: String,
        state: HAState,
        serverUnitSystem: HAUnitSystem?
    ) -> String {
        let length = serverUnitSystem?.length ?? ""
        switch attribute {
        case "visibility": return stringAttribute("visibility_unit", state: state) ?? length
        case "precipitation":
            return stringAttribute("precipitation_unit", state: state) ?? (length == "km" ? "mm" : "in")
        case "pressure":
            return stringAttribute("pressure_unit", state: state) ?? (length == "km" ? "hPa" : "inHg")
        case "temperature", "apparent_temperature", "dew_point", "templow":
            return stringAttribute("temperature_unit", state: state) ?? serverUnitSystem?.temperature ?? ""
        case "wind_speed": return stringAttribute("wind_speed_unit", state: state) ?? "\(length)/h"
        case "cloud_coverage", "humidity", "precipitation_probability": return "%"
        default: return ""
        }
    }

    private static func stringAttribute(_ name: String, state: HAState) -> String? {
        guard case let .string(value)? = state.attributes[name], !value.isEmpty else { return nil }
        return value
    }

    static func formatNumber(
        _ value: Double,
        preferences: HAFrontendLocalePreferences?,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = numberLocale(preferences)
        formatter.usesGroupingSeparator = preferences?.numberFormat != "none"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(0, maximumFractionDigits)
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func numberLocale(_ preferences: HAFrontendLocalePreferences?) -> Locale {
        switch preferences?.numberFormat {
        case "comma_decimal", "none": return Locale(identifier: "en_US")
        case "decimal_comma": return Locale(identifier: "de_DE")
        case "space_comma": return Locale(identifier: "fr_FR")
        case "quote_decimal": return Locale(identifier: "de_CH")
        case "system": return .current
        default: return Locale(identifier: preferences?.language ?? Locale.current.identifier)
        }
    }

    static func unitSuffix(
        _ unit: String,
        preferences: HAFrontendLocalePreferences?
    ) -> String {
        guard !unit.isEmpty else { return "" }
        if unit == "°" { return unit }
        if unit == "%" {
            let code = preferences?.language.split(separator: "-").first.map(String.init) ?? ""
            let space = ["cs", "de", "fi", "fr", "sk", "sv"].contains(code) ? " " : ""
            return space + unit
        }
        return " " + unit
    }

    static func windBearing(_ value: JSONValue?) -> String? {
        guard let value = value, value != .null else { return nil }
        let degrees: Double?
        switch value {
        case let .int(value): degrees = Double(value)
        case let .double(value): degrees = value
        case let .string(value):
            if let numeric = Double(value) { degrees = numeric } else { return value }
        default: return nil
        }
        guard let degrees = degrees, degrees.isFinite else { return nil }
        let directions = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
        ]
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return directions[Int((positive + 11.25) / 22.5) % 16]
    }

    private static func attributeLabel(_ attribute: String) -> String {
        switch attribute {
        case "apparent_temperature": return "Apparent temperature"
        case "cloud_coverage": return "Cloud coverage"
        case "dew_point": return "Dew point"
        case "humidity": return "Humidity"
        case "precipitation": return "Precipitation"
        case "precipitation_probability": return "Precipitation probability"
        case "pressure": return "Pressure"
        case "temperature": return "Temperature"
        case "uv_index": return "UV index"
        case "visibility": return "Visibility"
        case "wind_bearing": return "Wind bearing"
        case "wind_speed": return "Wind speed"
        default:
            return attribute.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static let temperatureAttributes: Set<String> = [
        "temperature", "apparent_temperature", "dew_point",
    ]
}
