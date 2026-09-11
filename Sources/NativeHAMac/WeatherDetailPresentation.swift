import Foundation
import NativeHACore

enum WeatherDetailMeasurementKind: Equatable {
    case pressure
    case humidity
    case wind
    case visibility

    var label: String {
        switch self {
        case .pressure: return "Pressure"
        case .humidity: return "Humidity"
        case .wind: return "Wind speed"
        case .visibility: return "Visibility"
        }
    }

    var symbolName: String {
        switch self {
        case .pressure: return "gauge"
        case .humidity: return "humidity.fill"
        case .wind: return "wind"
        case .visibility: return "eye.fill"
        }
    }
}

struct WeatherDetailMeasurement: Equatable, Identifiable {
    var id: WeatherDetailMeasurementKind { kind }
    let kind: WeatherDetailMeasurementKind
    let value: String
}

enum WeatherDetailSecondaryKind: Equatable {
    case extrema
    case precipitation
    case humidity

    var symbolName: String? {
        switch self {
        case .extrema: return nil
        case .precipitation: return "cloud.rain.fill"
        case .humidity: return "humidity.fill"
        }
    }
}

struct WeatherDetailSecondary: Equatable {
    let kind: WeatherDetailSecondaryKind
    let value: String
}

struct WeatherDetailForecastItem: Equatable, Identifiable {
    let id: Int
    let label: String
    let icon: WeatherIconPresentation?
    let high: String
    let low: String?
}

struct WeatherDetailForecastGroup: Equatable, Identifiable {
    let id: String
    let header: String?
    let items: [WeatherDetailForecastItem]
}

struct WeatherDetailForecastPresentation: Equatable {
    let selectedType: HAWeatherForecastType
    let groups: [WeatherDetailForecastGroup]
    let isLoading: Bool

    var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }
}

struct WeatherDetailPresentation: Equatable {
    let entityID: String
    let condition: String
    let icon: WeatherIconPresentation
    let relativeLastChanged: String
    let timestampHelp: String
    let temperature: String?
    let secondary: WeatherDetailSecondary?
    let measurements: [WeatherDetailMeasurement]
    let supportedTypes: [HAWeatherForecastType]
    let forecast: WeatherDetailForecastPresentation?
    let attribution: String?
}

enum WeatherDetailPresentationResolver {
    static func resolve(
        state: HAState,
        selectedType: HAWeatherForecastType?,
        modernEvent: HAWeatherForecastEvent?,
        serverUnitSystem: HAUnitSystem?,
        serverTimeZone: String?,
        preferences: HAFrontendLocalePreferences?,
        now: Date = Date(),
        hostCalendar: Calendar = .current,
        symbolAvailability: WeatherIconResolver.SymbolAvailability = WeatherIconResolver.defaultSymbolAvailability
    ) -> WeatherDetailPresentation {
        let supportedTypes = HAWeatherForecastFeatures.supportedTypes(in: state.attributes)
        let chosen = forecast(
            state: state,
            selectedType: selectedType,
            modernEvent: modernEvent
        )
        let relativeChanged = WeatherRelativeTimeFormatter.string(
            from: parseDate(state.lastChanged),
            to: now,
            preferences: preferences,
            calendar: relativeCalendar(preferences: preferences)
        )
        let relativeUpdated = WeatherRelativeTimeFormatter.string(
            from: parseDate(state.lastUpdated),
            to: now,
            preferences: preferences,
            calendar: relativeCalendar(preferences: preferences)
        )

        let sentinel = state.state == "unknown" || state.state == "unavailable"
        let icon: WeatherIconPresentation
        if state.state == "unknown" {
            icon = WeatherIconResolver.unknown(symbolAvailability: symbolAvailability)
        } else if state.state == "unavailable" {
            icon = WeatherIconResolver.unavailable(symbolAvailability: symbolAvailability)
        } else {
            icon = WeatherIconResolver.resolve(
                condition: state.state,
                symbolAvailability: symbolAvailability
            )
        }

        return WeatherDetailPresentation(
            entityID: state.entityId,
            condition: sentinel
                ? (state.state == "unknown" ? "Unknown" : "Unavailable")
                : WeatherPresentationResolver.conditionLabel(state.state),
            icon: icon,
            relativeLastChanged: relativeChanged,
            timestampHelp: "Last changed: \(relativeChanged)\nLast updated: \(relativeUpdated)",
            temperature: WeatherPresentationResolver.formattedAttribute(
                "temperature",
                state: state,
                serverUnitSystem: serverUnitSystem,
                preferences: preferences,
                maximumFractionDigits: 2
            ),
            secondary: secondary(
                state: state,
                forecast: chosen?.entries,
                serverUnitSystem: serverUnitSystem,
                preferences: preferences,
                now: now,
                hostCalendar: hostCalendar
            ),
            measurements: measurements(
                state: state,
                serverUnitSystem: serverUnitSystem,
                preferences: preferences
            ),
            supportedTypes: supportedTypes,
            forecast: selectedType.map { type in
                let entries = chosen?.entries
                let displayedType = chosen?.type ?? type
                let groups = entries.map {
                    forecastGroups(
                        entries: $0,
                        type: displayedType,
                        state: state,
                        serverUnitSystem: serverUnitSystem,
                        serverTimeZone: serverTimeZone,
                        preferences: preferences,
                        hostCalendar: hostCalendar,
                        symbolAvailability: symbolAvailability
                    )
                } ?? []
                return WeatherDetailForecastPresentation(
                    selectedType: type,
                    groups: groups,
                    isLoading: entries == nil || groups.isEmpty
                )
            },
            attribution: stringAttribute("attribution", state: state).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    static func legacyForecast(in state: HAState) -> (type: HAWeatherForecastType, entries: [HAWeatherForecast])? {
        guard case let .array(rawEntries)? = state.attributes["forecast"] else { return nil }
        let entries = rawEntries.compactMap(decodeLegacyForecast)
        guard entries.count > 2 else { return nil }
        return (inferLegacyType(entries), entries)
    }

    static func forecast(
        state: HAState,
        selectedType: HAWeatherForecastType?,
        modernEvent: HAWeatherForecastEvent?
    ) -> (type: HAWeatherForecastType, entries: [HAWeatherForecast])? {
        if let selectedType = selectedType,
           modernEvent?.type == selectedType,
           let modern = modernEvent?.forecast,
           modern.count > 2 {
            return (selectedType, modern)
        }
        return legacyForecast(in: state)
    }

    private static func decodeLegacyForecast(_ raw: JSONValue) -> HAWeatherForecast? {
        guard case let .object(object) = raw,
              case let .string(datetime)? = object["datetime"]
        else { return nil }
        return HAWeatherForecast(
            datetime: datetime,
            temperature: finiteNumber(object["temperature"]),
            temperatureLow: finiteNumber(object["templow"]),
            precipitation: finiteNumber(object["precipitation"]),
            precipitationProbability: finiteNumber(object["precipitation_probability"]),
            humidity: finiteNumber(object["humidity"]),
            condition: string(object["condition"]),
            isDaytime: bool(object["is_daytime"]),
            pressure: finiteNumber(object["pressure"]),
            windSpeed: scalarString(object["wind_speed"])
        )
    }

    private static func inferLegacyType(_ entries: [HAWeatherForecast]) -> HAWeatherForecastType {
        guard entries.count > 2,
              let second = parseDate(entries[1].datetime),
              let third = parseDate(entries[2].datetime)
        else { return .daily }
        let hours = abs(third.timeIntervalSince(second)) / 3_600
        if hours < 8 { return .hourly }
        if hours < 24 { return .twiceDaily }
        return .daily
    }

    private static func secondary(
        state: HAState,
        forecast: [HAWeatherForecast]?,
        serverUnitSystem: HAUnitSystem?,
        preferences: HAFrontendLocalePreferences?,
        now: Date,
        hostCalendar: Calendar
    ) -> WeatherDetailSecondary? {
        if let forecast = forecast,
           let extrema = currentHostDayExtrema(
               forecast,
               now: now,
               calendar: hostCalendar
           ) {
            let high = extrema.high.map {
                formattedForecastTemperature(
                    $0,
                    state: state,
                    serverUnitSystem: serverUnitSystem,
                    preferences: preferences
                )
            }
            let low = extrema.low.map {
                formattedForecastTemperature(
                    $0,
                    state: state,
                    serverUnitSystem: serverUnitSystem,
                    preferences: preferences
                )
            }
            let value = [high, low].compactMap { $0 }.joined(separator: " / ")
            if !value.isEmpty { return WeatherDetailSecondary(kind: .extrema, value: value) }
        }

        if let precipitation = forecast?.first?.precipitation {
            let value = WeatherPresentationResolver.formatNumber(
                roundedToOneDecimal(precipitation),
                preferences: preferences,
                maximumFractionDigits: 1
            ) + WeatherPresentationResolver.unitSuffix(
                WeatherPresentationResolver.weatherUnit(
                    "precipitation",
                    state: state,
                    serverUnitSystem: serverUnitSystem
                ),
                preferences: preferences
            )
            return WeatherDetailSecondary(kind: .precipitation, value: value)
        }

        if let humidity = finiteNumber(state.attributes["humidity"]) {
            let value = WeatherPresentationResolver.formatNumber(
                roundedToOneDecimal(humidity),
                preferences: preferences,
                maximumFractionDigits: 1
            ) + WeatherPresentationResolver.unitSuffix("%", preferences: preferences)
            return WeatherDetailSecondary(kind: .humidity, value: value)
        }
        return nil
    }

    private static func currentHostDayExtrema(
        _ forecast: [HAWeatherForecast],
        now: Date,
        calendar: Calendar
    ) -> (high: Double?, low: Double?)? {
        let day = calendar.component(.day, from: now)
        var high: Double?
        var low: Double?
        for item in forecast {
            guard let date = parseDate(item.datetime), calendar.component(.day, from: date) == day else {
                break
            }
            if let temperature = item.temperature {
                high = max(high ?? temperature, temperature)
                if item.temperatureLow == nil {
                    low = min(low ?? temperature, temperature)
                }
            }
            if let temperatureLow = item.temperatureLow {
                low = min(low ?? temperatureLow, temperatureLow)
            }
        }
        guard high != nil || low != nil else { return nil }
        return (high, low)
    }

    private static func measurements(
        state: HAState,
        serverUnitSystem: HAUnitSystem?,
        preferences: HAFrontendLocalePreferences?
    ) -> [WeatherDetailMeasurement] {
        var result: [WeatherDetailMeasurement] = []
        if let value = WeatherPresentationResolver.formattedAttribute(
            "pressure", state: state, serverUnitSystem: serverUnitSystem,
            preferences: preferences, maximumFractionDigits: 2
        ) {
            result.append(WeatherDetailMeasurement(kind: .pressure, value: value))
        }
        if let value = WeatherPresentationResolver.formattedAttribute(
            "humidity", state: state, serverUnitSystem: serverUnitSystem,
            preferences: preferences, maximumFractionDigits: 2
        ) {
            result.append(WeatherDetailMeasurement(kind: .humidity, value: value))
        }
        if state.attributes["wind_speed"] != nil,
           state.attributes["wind_speed"] != .null {
            let speed = WeatherPresentationResolver.formattedAttribute(
                "wind_speed", state: state, serverUnitSystem: serverUnitSystem,
                preferences: preferences, maximumFractionDigits: 2
            )
            if let speed = speed {
                let bearing = WeatherPresentationResolver.windBearing(state.attributes["wind_bearing"])
                result.append(WeatherDetailMeasurement(
                    kind: .wind,
                    value: bearing.map { "\(speed) (\($0))" } ?? speed
                ))
            }
        }
        if let value = WeatherPresentationResolver.formattedAttribute(
            "visibility", state: state, serverUnitSystem: serverUnitSystem,
            preferences: preferences, maximumFractionDigits: 2
        ) {
            result.append(WeatherDetailMeasurement(kind: .visibility, value: value))
        }
        return result
    }

    private static func forecastGroups(
        entries: [HAWeatherForecast],
        type: HAWeatherForecastType,
        state: HAState,
        serverUnitSystem: HAUnitSystem?,
        serverTimeZone: String?,
        preferences: HAFrontendLocalePreferences?,
        hostCalendar: Calendar,
        symbolAvailability: WeatherIconResolver.SymbolAvailability
    ) -> [WeatherDetailForecastGroup] {
        let visible = entries.enumerated().compactMap { index, item -> (Int, HAWeatherForecast, Date)? in
            guard item.temperature != nil || item.temperatureLow != nil,
                  let date = parseDate(item.datetime)
            else { return nil }
            return (index, item, date)
        }
        guard !visible.isEmpty else { return [] }

        var grouped: [(key: String, date: Date, values: [(Int, HAWeatherForecast, Date)])] = []
        for value in visible {
            let components = hostCalendar.dateComponents([.year, .month, .day], from: value.2)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
            if let lastIndex = grouped.indices.last, grouped[lastIndex].key == key {
                grouped[lastIndex].values.append(value)
            } else {
                grouped.append((key, value.2, [value]))
            }
        }

        let displayCalendar = configuredCalendar(
            serverTimeZone: serverTimeZone,
            preferences: preferences
        )
        let groupsToRender: [(String, Date, [(Int, HAWeatherForecast, Date)])]
        if type == .daily {
            groupsToRender = visible.map { ("daily-\($0.0)", $0.2, [$0]) }
        } else {
            groupsToRender = grouped.map { ($0.key, $0.date, $0.values) }
        }

        return groupsToRender.map { key, date, values in
            let items: [WeatherDetailForecastItem] = values.map { value in
                let (index, item, itemDate) = value
                let label: String
                switch type {
                case .daily:
                    label = weekday(date: itemDate, calendar: displayCalendar, preferences: preferences)
                case .hourly:
                    label = time(date: itemDate, calendar: displayCalendar, preferences: preferences)
                case .twiceDaily:
                    label = item.isDaytime == false ? "Night" : "Day"
                }
                return WeatherDetailForecastItem(
                    id: index,
                    label: label,
                    icon: item.condition.map {
                        WeatherIconResolver.resolveForecast(
                            condition: $0,
                            isNight: type == .twiceDaily && item.isDaytime == false,
                            symbolAvailability: symbolAvailability
                        )
                    },
                    high: item.temperature.map {
                        WeatherPresentationResolver.formatNumber(
                            $0, preferences: preferences, maximumFractionDigits: 2
                        ) + "°"
                    } ?? "—",
                    low: item.temperatureLow.map {
                        WeatherPresentationResolver.formatNumber(
                            $0, preferences: preferences, maximumFractionDigits: 2
                        ) + "°"
                    }
                )
            }
            return WeatherDetailForecastGroup(
                id: key,
                header: type == .daily
                    ? nil
                    : weekday(date: date, calendar: displayCalendar, preferences: preferences),
                items: items
            )
        }
    }

    private static func configuredCalendar(
        serverTimeZone: String?,
        preferences: HAFrontendLocalePreferences?
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: preferences?.language ?? "en")
        let configured = preferences?.timeZone
        if let identifier = configured, identifier != "local", let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        } else if let identifier = serverTimeZone, let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        }
        return calendar
    }

    private static func relativeCalendar(preferences: HAFrontendLocalePreferences?) -> Calendar {
        var calendar = Calendar.current
        switch preferences?.firstWeekday {
        case "monday": calendar.firstWeekday = 2
        case "saturday": calendar.firstWeekday = 7
        case "sunday": calendar.firstWeekday = 1
        default: break
        }
        return calendar
    }

    private static func weekday(
        date: Date,
        calendar: Calendar,
        preferences: HAFrontendLocalePreferences?
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: preferences?.language ?? "en")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private static func time(
        date: Date,
        calendar: Calendar,
        preferences: HAFrontendLocalePreferences?
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: preferences?.language ?? "en")
        switch preferences?.timeFormat {
        case "24": formatter.dateFormat = "HH:mm"
        case "12": formatter.dateFormat = "h:mm a"
        default: formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private static func formattedForecastTemperature(
        _ value: Double,
        state: HAState,
        serverUnitSystem: HAUnitSystem?,
        preferences: HAFrontendLocalePreferences?
    ) -> String {
        WeatherPresentationResolver.formatNumber(
            value, preferences: preferences, maximumFractionDigits: 2
        ) + WeatherPresentationResolver.unitSuffix(
            WeatherPresentationResolver.weatherUnit(
                "temperature", state: state, serverUnitSystem: serverUnitSystem
            ),
            preferences: preferences
        )
    }

    private static func roundedToOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func stringAttribute(_ name: String, state: HAState) -> String? {
        string(state.attributes[name])
    }

    private static func finiteNumber(_ value: JSONValue?) -> Double? {
        guard let value = value,
              let number = WeatherPresentationResolver.numericValue(value),
              number.isFinite
        else { return nil }
        return number
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case let .string(result)? = value else { return nil }
        return result
    }

    private static func bool(_ value: JSONValue?) -> Bool? {
        guard case let .bool(result)? = value else { return nil }
        return result
    }

    private static func scalarString(_ value: JSONValue?) -> String? {
        switch value {
        case let .string(value)?: return value
        case let .int(value)?: return String(value)
        case let .double(value)? where value.isFinite: return String(value)
        default: return nil
        }
    }
}

enum WeatherRelativeTimeFormatter {
    static func string(
        from: Date?,
        to: Date,
        preferences: HAFrontendLocalePreferences?,
        calendar: Calendar
    ) -> String {
        guard let from = from else { return "Never" }
        let seconds = from.timeIntervalSince(to)
        if abs(seconds) < 59 { return phrase(Int(seconds.rounded()), unit: "second") }
        let minutes = seconds / 60
        if abs(minutes) < 59 { return phrase(Int(minutes.rounded()), unit: "minute") }
        let hours = minutes / 60
        if abs(hours) < 22 { return phrase(Int(hours.rounded()), unit: "hour") }

        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        let days = calendar.dateComponents([.day], from: toDay, to: fromDay).day ?? 0
        if days == 0 { return phrase(Int(hours.rounded()), unit: "hour") }
        if abs(days) < 5 { return phrase(days, unit: "day") }

        let fromWeek = startOfWeek(fromDay, calendar: calendar)
        let toWeek = startOfWeek(toDay, calendar: calendar)
        let weeks = calendar.dateComponents([.weekOfYear], from: toWeek, to: fromWeek).weekOfYear ?? 0
        if weeks == 0 { return phrase(days, unit: "day") }
        if abs(weeks) < 4 { return phrase(weeks, unit: "week") }

        let components = calendar.dateComponents([.year, .month], from: toDay, to: fromDay)
        let months = (components.year ?? 0) * 12 + (components.month ?? 0)
        let years = calendar.component(.year, from: fromDay) - calendar.component(.year, from: toDay)
        if months == 0 { return phrase(weeks, unit: "week") }
        if abs(months) < 11 || years == 0 { return phrase(months, unit: "month") }
        return phrase(years, unit: "year")
    }

    private static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: date) ?? date
    }

    private static func phrase(_ value: Int, unit: String) -> String {
        if value == 0 { return "Now" }
        if unit == "day", value == -1 { return "Yesterday" }
        if unit == "day", value == 1 { return "Tomorrow" }
        let quantity = abs(value)
        let word = quantity == 1 ? unit : "\(unit)s"
        return value < 0 ? "\(quantity) \(word) ago" : "in \(quantity) \(word)"
    }
}
