import Foundation

/// Modern forecast streams supported by Home Assistant weather entities.
public enum HAWeatherForecastType: String, Codable, CaseIterable, Equatable, Hashable {
    case daily
    case twiceDaily = "twice_daily"
    case hourly

    public var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .twiceDaily: return "Twice daily"
        case .hourly: return "Hourly"
        }
    }
}

/// Home Assistant's weather supported-feature bits. The ordering is a UI
/// contract and intentionally differs from the numerical bit ordering.
public enum HAWeatherForecastFeatures {
    public static let daily = 1
    public static let hourly = 2
    public static let twiceDaily = 4

    public static func supportedTypes(in attributes: [String: JSONValue]) -> [HAWeatherForecastType] {
        let bits: Int
        switch attributes["supported_features"] {
        case let .int(value)?: bits = value
        case let .double(value)? where value.isFinite &&
            value.rounded() == value &&
            value >= Double(Int.min) &&
            value < Double(Int.max):
            bits = Int(value)
        case let .string(value)?: bits = Int(value) ?? 0
        default: bits = 0
        }

        var result: [HAWeatherForecastType] = []
        if bits & daily != 0 { result.append(.daily) }
        if bits & twiceDaily != 0 { result.append(.twiceDaily) }
        if bits & hourly != 0 { result.append(.hourly) }
        return result
    }
}

/// One forecast item. Numeric fields accept JSON numbers and finite numeric
/// strings used by integrations, but reject booleans and structured values.
public struct HAWeatherForecast: Decodable, Equatable {
    public let datetime: String
    public let temperature: Double?
    public let temperatureLow: Double?
    public let precipitation: Double?
    public let precipitationProbability: Double?
    public let humidity: Double?
    public let condition: String?
    public let isDaytime: Bool?
    public let pressure: Double?
    public let windSpeed: String?

    private enum CodingKeys: String, CodingKey {
        case datetime
        case temperature
        case temperatureLow = "templow"
        case precipitation
        case precipitationProbability = "precipitation_probability"
        case humidity
        case condition
        case isDaytime = "is_daytime"
        case pressure
        case windSpeed = "wind_speed"
    }

    public init(
        datetime: String,
        temperature: Double? = nil,
        temperatureLow: Double? = nil,
        precipitation: Double? = nil,
        precipitationProbability: Double? = nil,
        humidity: Double? = nil,
        condition: String? = nil,
        isDaytime: Bool? = nil,
        pressure: Double? = nil,
        windSpeed: String? = nil
    ) {
        self.datetime = datetime
        self.temperature = temperature
        self.temperatureLow = temperatureLow
        self.precipitation = precipitation
        self.precipitationProbability = precipitationProbability
        self.humidity = humidity
        self.condition = condition
        self.isDaytime = isDaytime
        self.pressure = pressure
        self.windSpeed = windSpeed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        datetime = try container.decode(String.self, forKey: .datetime)
        temperature = try container.decodeFiniteNumberIfPresent(forKey: .temperature)
        temperatureLow = try container.decodeFiniteNumberIfPresent(forKey: .temperatureLow)
        precipitation = try container.decodeFiniteNumberIfPresent(forKey: .precipitation)
        precipitationProbability = try container.decodeFiniteNumberIfPresent(
            forKey: .precipitationProbability
        )
        humidity = try container.decodeFiniteNumberIfPresent(forKey: .humidity)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        isDaytime = try container.decodeIfPresent(Bool.self, forKey: .isDaytime)
        pressure = try container.decodeFiniteNumberIfPresent(forKey: .pressure)
        if !container.contains(.windSpeed) {
            windSpeed = nil
        } else if try container.decodeNil(forKey: .windSpeed) {
            windSpeed = nil
        } else if let text = try? container.decode(String.self, forKey: .windSpeed) {
            windSpeed = text
        } else if let numeric = try? container.decode(Double.self, forKey: .windSpeed),
                  numeric.isFinite {
            windSpeed = String(numeric)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .windSpeed,
                in: container,
                debugDescription: "Weather forecast wind speed must be a finite scalar"
            )
        }
    }
}

public struct HAWeatherForecastEvent: Decodable, Equatable {
    public let type: HAWeatherForecastType
    public let forecast: [HAWeatherForecast]?

    public init(type: HAWeatherForecastType, forecast: [HAWeatherForecast]?) {
        self.type = type
        self.forecast = forecast
    }
}

private extension KeyedDecodingContainer {
    func decodeFiniteNumberIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let value: Double
        if let number = try? decode(Double.self, forKey: key) {
            value = number
        } else {
            let text = try decode(String.self, forKey: key)
            guard let number = Double(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Weather forecast field must be numeric"
                )
            }
            value = number
        }
        guard value.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Weather forecast field must be finite"
            )
        }
        return value
    }
}
