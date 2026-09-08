import AppKit

enum WeatherIconColorRole: Equatable {
    case sun
    case moon
    case cloud
    case rain
    case snow
    case wind
    case warning
    case unavailable
}

struct WeatherIconPresentation: Equatable {
    let symbolName: String?
    let fallbackText: String?
    let semanticLabel: String
    let colorRole: WeatherIconColorRole
}

enum WeatherIconResolver {
    typealias SymbolAvailability = (String) -> Bool

    /// Exact, finite Home Assistant weather-state mapping. Keeping this table
    /// isolated prevents the SF Symbols approximation from becoming model or
    /// ownership policy.
    static func resolve(
        condition: String,
        symbolAvailability: SymbolAvailability = defaultSymbolAvailability
    ) -> WeatherIconPresentation {
        let requested: (symbol: String, label: String, color: WeatherIconColorRole)
        switch condition {
        case "clear-night": requested = ("moon.stars.fill", "Clear night", .moon)
        case "cloudy": requested = ("cloud.fill", "Cloudy", .cloud)
        case "fog": requested = ("cloud.fog.fill", "Fog", .cloud)
        case "hail": requested = ("cloud.hail.fill", "Hail", .rain)
        case "lightning": requested = ("cloud.bolt.fill", "Lightning", .warning)
        case "lightning-rainy": requested = ("cloud.bolt.rain.fill", "Lightning rainy", .warning)
        case "partlycloudy": requested = ("cloud.sun.fill", "Partly cloudy", .cloud)
        case "pouring": requested = ("cloud.heavyrain.fill", "Pouring", .rain)
        case "rainy": requested = ("cloud.rain.fill", "Rainy", .rain)
        case "snowy": requested = ("cloud.snow.fill", "Snowy", .snow)
        case "snowy-rainy": requested = ("cloud.sleet.fill", "Snowy rainy", .snow)
        case "sunny": requested = ("sun.max.fill", "Sunny", .sun)
        case "windy": requested = ("wind", "Windy", .wind)
        case "windy-variant": requested = ("wind.circle.fill", "Windy variant", .wind)
        case "exceptional": requested = ("exclamationmark.triangle.fill", "Exceptional", .warning)
        default:
            // Never make an unrecognized state look sunny.
            requested = ("cloud.fill", "Unknown weather condition", .cloud)
        }
        return availablePresentation(
            preferred: requested.symbol,
            semanticLabel: requested.label,
            colorRole: requested.color,
            symbolAvailability: symbolAvailability
        )
    }

    static func missing(
        symbolAvailability: SymbolAvailability = defaultSymbolAvailability
    ) -> WeatherIconPresentation {
        availablePresentation(
            preferred: "questionmark.square.dashed",
            semanticLabel: "Missing weather entity",
            colorRole: .unavailable,
            symbolAvailability: symbolAvailability
        )
    }

    static func unknown(
        symbolAvailability: SymbolAvailability = defaultSymbolAvailability
    ) -> WeatherIconPresentation {
        availablePresentation(
            preferred: "questionmark.circle",
            semanticLabel: "Unknown weather state",
            colorRole: .unavailable,
            symbolAvailability: symbolAvailability
        )
    }

    static func unavailable(
        symbolAvailability: SymbolAvailability = defaultSymbolAvailability
    ) -> WeatherIconPresentation {
        availablePresentation(
            preferred: "exclamationmark.triangle.fill",
            semanticLabel: "Unavailable weather entity",
            colorRole: .unavailable,
            symbolAvailability: symbolAvailability
        )
    }

    private static func availablePresentation(
        preferred: String,
        semanticLabel: String,
        colorRole: WeatherIconColorRole,
        symbolAvailability: SymbolAvailability
    ) -> WeatherIconPresentation {
        if symbolAvailability(preferred) {
            return WeatherIconPresentation(
                symbolName: preferred,
                fallbackText: nil,
                semanticLabel: semanticLabel,
                colorRole: colorRole
            )
        }
        if symbolAvailability("cloud.fill") {
            return WeatherIconPresentation(
                symbolName: "cloud.fill",
                fallbackText: nil,
                semanticLabel: semanticLabel,
                colorRole: colorRole == .sun ? .cloud : colorRole
            )
        }
        return WeatherIconPresentation(
            symbolName: nil,
            fallbackText: "?",
            semanticLabel: semanticLabel,
            colorRole: colorRole == .sun ? .cloud : colorRole
        )
    }

    static func defaultSymbolAvailability(_ symbol: String) -> Bool {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }
}
