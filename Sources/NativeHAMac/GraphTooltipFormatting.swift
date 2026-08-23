import Foundation
import NativeHACore

enum GraphTooltipTimePrecision: Equatable, Hashable {
    case homeAssistant
    case minute
    case second
    case fractionalSeconds(Int)

    var clampedFractionalSeconds: Int {
        switch self {
        case .homeAssistant, .second, .minute:
            return 0
        case let .fractionalSeconds(digits):
            return min(max(digits, 0), 9)
        }
    }
}

struct GraphTooltipFormattingPolicy: Equatable {
    let timePrecision: GraphTooltipTimePrecision
    let numericDigits: Int?
    let entityNumericDigits: [String: Int]

    init(
        timePrecision: GraphTooltipTimePrecision = .homeAssistant,
        numericDigits: Int? = nil,
        entityNumericDigits: [String: Int] = [:]
    ) {
        self.timePrecision = timePrecision
        self.numericDigits = numericDigits.map(Self.clampDigits)
        self.entityNumericDigits = entityNumericDigits.mapValues(Self.clampDigits)
    }

    func configuredDigits(for entityID: String) -> Int? {
        entityNumericDigits[entityID] ?? numericDigits
    }

    static func clampDigits(_ digits: Int) -> Int {
        min(max(digits, 0), 15)
    }
}

struct GraphTooltipFormattingMetadata: Equatable, Hashable {
    let minimumFractionDigits: Int
    let maximumFractionDigits: Int
    let usesCanonicalValueDigits: Bool
    let numberLocaleIdentifier: String
    let timeLocaleIdentifier: String
    let usesGroupingSeparator: Bool
    let timePrecision: GraphTooltipTimePrecision
    let timeFormatPreference: String
    let timeZoneIdentifier: String

    static var platformDefault: GraphTooltipFormattingMetadata {
        GraphTooltipFormattingMetadata(
            minimumFractionDigits: 0,
            maximumFractionDigits: 2,
            usesCanonicalValueDigits: false,
            numberLocaleIdentifier: Locale.current.identifier,
            timeLocaleIdentifier: Locale.current.identifier,
            usesGroupingSeparator: true,
            timePrecision: .homeAssistant,
            timeFormatPreference: "system",
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }

    var cacheKey: String {
        [
            String(minimumFractionDigits),
            String(maximumFractionDigits),
            usesCanonicalValueDigits ? "canonical" : "fixed",
            numberLocaleIdentifier,
            timeLocaleIdentifier,
            usesGroupingSeparator ? "group" : "plain",
            String(describing: timePrecision),
            timeFormatPreference,
            timeZoneIdentifier,
        ].joined(separator: "\u{1E}")
    }

    func formatNumber(_ value: Double, unit: String) -> String {
        let digits = usesCanonicalValueDigits ? Self.canonicalFractionDigits(value) : nil
        let minimum = digits ?? minimumFractionDigits
        let maximum = digits ?? maximumFractionDigits
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: numberLocaleIdentifier)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = usesGroupingSeparator
        formatter.minimumFractionDigits = minimum
        formatter.maximumFractionDigits = maximum
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(value)
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    func formatTime(_ timestamp: Double) -> String {
        let locale = Locale(identifier: timeLocaleIdentifier)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        let hourTemplate: String
        switch timeFormatPreference {
        case "12":
            hourTemplate = "h"
        case "24":
            hourTemplate = "HH"
        default:
            hourTemplate = "j"
        }

        let template: String
        switch timePrecision {
        case .minute:
            template = "yMMMMd\(hourTemplate)mm"
        case .homeAssistant, .second:
            template = "yMMMMd\(hourTemplate)mmss"
        case .fractionalSeconds:
            template = "yMMMMd\(hourTemplate)mmss" +
                String(repeating: "S", count: timePrecision.clampedFractionalSeconds)
        }
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: template,
            options: 0,
            locale: locale
        )
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    func formatAxisTime(_ timestamp: Double) -> String {
        let locale = Locale(identifier: timeLocaleIdentifier)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let hourTemplate = timeFormatPreference == "12" ? "h" :
            (timeFormatPreference == "24" ? "HH" : "j")
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "\(hourTemplate)mm",
            options: 0,
            locale: locale
        )
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func canonicalFractionDigits(_ value: Double) -> Int {
        let canonical = String(value)
        guard let decimal = canonical.firstIndex(of: ".") else { return 0 }
        return GraphTooltipFormattingPolicy.clampDigits(
            canonical[canonical.index(after: decimal)...].count
        )
    }
}

enum GraphTooltipFormattingResolver {
    static func metadata(
        entityID: String,
        state: HAState?,
        registryDisplayPrecision: Int?,
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?,
        policy: GraphTooltipFormattingPolicy
    ) -> GraphTooltipFormattingMetadata {
        let explicitDigits = policy.configuredDigits(for: entityID)
            ?? registryDisplayPrecision.map(GraphTooltipFormattingPolicy.clampDigits)
        let digits: (minimum: Int, maximum: Int, canonical: Bool)
        if let explicitDigits = explicitDigits {
            digits = (explicitDigits, explicitDigits, false)
        } else if hasIntegerStepAndState(state) {
            digits = (0, 0, false)
        } else {
            digits = (0, 15, true)
        }

        let numberLocale = numberLocale(preferences: preferences)
        let timeLocale = timeLocale(preferences: preferences)
        return GraphTooltipFormattingMetadata(
            minimumFractionDigits: digits.minimum,
            maximumFractionDigits: digits.maximum,
            usesCanonicalValueDigits: digits.canonical,
            numberLocaleIdentifier: numberLocale.identifier,
            timeLocaleIdentifier: timeLocale.identifier,
            usesGroupingSeparator: preferences?.numberFormat != "none",
            timePrecision: policy.timePrecision,
            timeFormatPreference: resolvedTimeFormatPreference(preferences: preferences),
            timeZoneIdentifier: resolvedTimeZoneIdentifier(
                preferences: preferences,
                serverTimeZone: serverTimeZone
            )
        )
    }

    private static func hasIntegerStepAndState(_ state: HAState?) -> Bool {
        guard
            let state = state,
            let numericState = Double(state.state),
            numericState.rounded() == numericState,
            let step = state.attributes["step"]
        else {
            return false
        }
        let numericStep: Double?
        switch step {
        case let .int(value):
            numericStep = Double(value)
        case let .double(value):
            numericStep = value
        case let .string(value):
            numericStep = Double(value)
        default:
            numericStep = nil
        }
        guard let numericStep = numericStep else { return false }
        return numericStep.rounded() == numericStep
    }

    private static func numberLocale(
        preferences: HAFrontendLocalePreferences?
    ) -> Locale {
        switch preferences?.numberFormat {
        case "comma_decimal":
            return Locale(identifier: "en_US")
        case "decimal_comma":
            return Locale(identifier: "de_DE")
        case "space_comma":
            return Locale(identifier: "fr_FR")
        case "quote_decimal":
            return Locale(identifier: "de_CH")
        case "none":
            return Locale(identifier: "en_US")
        case "system":
            return .current
        default:
            guard let language = preferences?.language, !language.isEmpty else {
                return .current
            }
            return Locale(identifier: language)
        }
    }

    private static func timeLocale(
        preferences: HAFrontendLocalePreferences?
    ) -> Locale {
        guard let language = preferences?.language, !language.isEmpty else {
            return .current
        }
        return Locale(identifier: language)
    }

    private static func resolvedTimeFormatPreference(
        preferences: HAFrontendLocalePreferences?
    ) -> String {
        switch preferences?.timeFormat {
        case "12", "24":
            return preferences?.timeFormat ?? "24"
        case "language":
            return "language"
        default:
            let pattern = DateFormatter.dateFormat(
                fromTemplate: "j",
                options: 0,
                locale: .current
            ) ?? ""
            return pattern.contains("a") ? "12" : "24"
        }
    }

    private static func resolvedTimeZoneIdentifier(
        preferences: HAFrontendLocalePreferences?,
        serverTimeZone: String?
    ) -> String {
        if
            preferences?.timeZone == "server",
            let serverTimeZone = serverTimeZone,
            TimeZone(identifier: serverTimeZone) != nil
        {
            return serverTimeZone
        }
        return TimeZone.current.identifier
    }
}
