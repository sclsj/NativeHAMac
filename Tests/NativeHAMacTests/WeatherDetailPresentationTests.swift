import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class WeatherDetailPresentationTests: XCTestCase {
    private let preferences = HAFrontendLocalePreferences(
        language: "en_US_POSIX",
        numberFormat: "comma_decimal",
        timeFormat: "24",
        dateFormat: "language",
        firstWeekday: "monday",
        timeZone: "Asia/Shanghai"
    )

    func testCompleteAndSentinelDetailsRetainOnlyValidPresentMeasurements() {
        for condition in ["partlycloudy", "unknown", "unavailable"] {
            let state = weatherState(condition: condition, attributes: [
                "supported_features": .int(3),
                "temperature": .double(22.34),
                "temperature_unit": .string("°C"),
                "pressure": .double(1010.5),
                "pressure_unit": .string("hPa"),
                "humidity": .int(78),
                "wind_speed": .double(10.8),
                "wind_speed_unit": .string("km/h"),
                "wind_bearing": .double(2.8),
                "visibility": .int(10),
                "visibility_unit": .string("km"),
                "attribution": .string("Weather data by Home Assistant"),
                "malformed": .object(["never": .string("render")]),
            ])
            let result = resolve(state, selected: .daily)
            XCTAssertEqual(result.temperature, "22.34 °C", condition)
            XCTAssertEqual(result.measurements.map(\.kind), [.pressure, .humidity, .wind, .visibility])
            XCTAssertEqual(result.measurements[2].value, "10.8 km/h (N)")
            XCTAssertEqual(result.attribution, "Weather data by Home Assistant")
            XCTAssertEqual(result.supportedTypes, [.daily, .hourly])
            XCTAssertEqual(result.forecast?.selectedType, .daily)
            XCTAssertTrue(result.forecast?.isLoading == true)
            XCTAssertTrue(result.timestampHelp.contains("Last updated:"))
            if condition == "unknown" { XCTAssertEqual(result.condition, "Unknown") }
            if condition == "unavailable" { XCTAssertEqual(result.condition, "Unavailable") }
        }

        let sparse = resolve(weatherState(condition: "sunny", attributes: [
            "pressure": .null,
            "humidity": .object([:]),
            "wind_speed": .array([]),
            "visibility": .bool(true),
        ]), selected: nil)
        XCTAssertNil(sparse.temperature)
        XCTAssertTrue(sparse.measurements.isEmpty)
        XCTAssertNil(sparse.forecast)
        XCTAssertNil(sparse.attribution)
    }

    func testSecondaryPriorityIsHostDayExtremaThenPrecipitationThenHumidity() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
        let entries = [
            HAWeatherForecast(datetime: "2026-09-09T01:00:00Z", temperature: 20, temperatureLow: 12, precipitation: 1.2),
            HAWeatherForecast(datetime: "2026-09-09T13:00:00Z", temperature: 24, temperatureLow: 11),
            HAWeatherForecast(datetime: "2026-09-10T00:00:00Z", temperature: 99, temperatureLow: -10),
        ]
        let state = weatherState(condition: "sunny", attributes: baseAttributes.merging([
            "supported_features": .int(1),
            "humidity": .int(78),
        ]) { _, new in new })
        let extrema = WeatherDetailPresentationResolver.resolve(
            state: state,
            selectedType: .daily,
            modernEvent: .init(type: .daily, forecast: entries),
            serverUnitSystem: .init(temperature: "°C", length: "km"),
            serverTimeZone: "UTC",
            preferences: preferences,
            now: now,
            hostCalendar: utc,
            symbolAvailability: { _ in true }
        )
        XCTAssertEqual(extrema.secondary, .init(kind: .extrema, value: "24 °C / 11 °C"))
        XCTAssertNil(extrema.secondary?.kind.symbolName)

        let precipitation = resolve(
            state,
            selected: .daily,
            event: .init(type: .daily, forecast: [
                .init(datetime: "2026-09-10T00:00:00Z", temperature: 20, precipitation: 1.24),
                .init(datetime: "2026-09-11T00:00:00Z", temperature: 21),
                .init(datetime: "2026-09-12T00:00:00Z", temperature: 22),
            ]),
            now: now,
            calendar: utc
        )
        XCTAssertEqual(precipitation.secondary, .init(kind: .precipitation, value: "1.2 mm"))

        let humidity = resolve(state, selected: .daily, event: .init(type: .daily, forecast: nil))
        XCTAssertEqual(humidity.secondary, .init(kind: .humidity, value: "78%"))
    }

    func testLegacyInferenceModernPrecedenceNullShortAndMismatchFallback() {
        for (hours, expected) in [(1, HAWeatherForecastType.hourly), (12, .twiceDaily), (24, .daily)] {
            let legacy = legacyArray(gapHours: hours, count: 6)
            let state = weatherState(condition: "cloudy", attributes: baseAttributes.merging([
                "supported_features": .int(7),
                "forecast": legacy,
            ]) { _, new in new })
            XCTAssertEqual(WeatherDetailPresentationResolver.legacyForecast(in: state)?.type, expected)
        }

        let state = weatherState(condition: "cloudy", attributes: baseAttributes.merging([
            "supported_features": .int(3),
            "forecast": legacyArray(gapHours: 1, count: 6),
        ]) { _, new in new })
        let nullResult = resolve(state, selected: .daily, event: .init(type: .daily, forecast: nil))
        XCTAssertEqual(nullResult.forecast?.itemCount, 6)
        XCTAssertFalse(nullResult.forecast?.isLoading ?? true)

        let short = resolve(state, selected: .daily, event: .init(type: .daily, forecast: [
            .init(datetime: "2026-09-09T00:00:00Z", temperature: 1),
            .init(datetime: "2026-09-10T00:00:00Z", temperature: 2),
        ]))
        XCTAssertEqual(short.forecast?.itemCount, 6)

        let modern = (0..<8).map {
            HAWeatherForecast(datetime: "2026-09-1\(($0 % 8) + 1)T00:00:00Z", temperature: Double(30 + $0))
        }
        let modernResult = resolve(state, selected: .daily, event: .init(type: .daily, forecast: modern))
        XCTAssertEqual(modernResult.forecast?.itemCount, 8)
        let mismatch = resolve(state, selected: .daily, event: .init(type: .hourly, forecast: modern))
        XCTAssertEqual(mismatch.forecast?.itemCount, 6)
    }

    func testForecastPreservesAllPayloadEntriesTemperatureRulesAndDayNightIcons() {
        let state = weatherState(condition: "partlycloudy", attributes: baseAttributes.merging([
            "supported_features": .int(4),
        ]) { _, new in new })
        let forecast: [HAWeatherForecast] = [
            .init(datetime: "2026-09-09T06:00:00+08:00", temperature: 25, condition: "partlycloudy", isDaytime: true),
            .init(datetime: "2026-09-09T18:00:00+08:00", temperatureLow: 18, condition: "partlycloudy", isDaytime: false),
            .init(datetime: "2026-09-10T06:00:00+08:00", temperature: 26, temperatureLow: 19, condition: "partlycloudy"),
            .init(datetime: "2026-09-10T18:00:00+08:00", condition: "rainy"),
            .init(datetime: "2026-09-11T06:00:00+08:00", temperature: 27),
            .init(datetime: "2026-09-11T18:00:00+08:00", temperature: 20),
        ]
        let result = resolve(
            state,
            selected: .twiceDaily,
            event: .init(type: .twiceDaily, forecast: forecast)
        )
        let items = result.forecast?.groups.flatMap(\.items) ?? []
        XCTAssertEqual(items.count, 5, "Only the entry missing both high and low is omitted")
        XCTAssertEqual(items.map(\.id), [0, 1, 2, 4, 5], "Payload order and original identities remain intact")
        XCTAssertEqual(items[0].label, "Day")
        XCTAssertEqual(items[1].label, "Night")
        XCTAssertEqual(items[2].label, "Day", "Absent is_daytime is Day")
        XCTAssertEqual(items[1].high, "—")
        XCTAssertEqual(items[1].low, "18°")
        XCTAssertNil(items[0].low)
        XCTAssertEqual(items[0].icon?.symbolName, "cloud.sun.fill")
        XCTAssertEqual(items[1].icon?.symbolName, "cloud.moon.fill")
    }

    func testHostGroupingAndConfiguredTimezoneLabelsRemainSeparate() {
        var host = Calendar(identifier: .gregorian)
        host.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        let state = weatherState(condition: "sunny", attributes: baseAttributes.merging([
            "supported_features": .int(2),
        ]) { _, new in new })
        let entries = [
            HAWeatherForecast(datetime: "2026-09-09T07:30:00Z", temperature: 20),
            HAWeatherForecast(datetime: "2026-09-09T08:30:00Z", temperature: 21),
            HAWeatherForecast(datetime: "2026-09-09T09:30:00Z", temperature: 22),
        ]
        let result = WeatherDetailPresentationResolver.resolve(
            state: state,
            selectedType: .hourly,
            modernEvent: .init(type: .hourly, forecast: entries),
            serverUnitSystem: .init(temperature: "°C", length: "km"),
            serverTimeZone: "UTC",
            preferences: preferences,
            now: Date(),
            hostCalendar: host,
            symbolAvailability: { _ in true }
        )
        XCTAssertEqual(result.forecast?.groups.count, 2, "Grouping uses host calendar midnight")
        XCTAssertEqual(result.forecast?.groups.flatMap(\.items).map(\.label), ["15:30", "16:30", "17:30"], "Labels use configured Asia/Shanghai")
    }

    func testRelativeThresholdsNeverAndCalendarBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
        XCTAssertEqual(WeatherRelativeTimeFormatter.string(from: nil, to: now, preferences: preferences, calendar: calendar), "Never")
        XCTAssertEqual(relative(seconds: -58, now: now, calendar: calendar), "58 seconds ago")
        XCTAssertEqual(relative(seconds: -59, now: now, calendar: calendar), "1 minute ago")
        XCTAssertEqual(relative(seconds: -58 * 60, now: now, calendar: calendar), "58 minutes ago")
        XCTAssertEqual(relative(seconds: -59 * 60, now: now, calendar: calendar), "1 hour ago")
        XCTAssertEqual(relative(seconds: -21 * 3_600, now: now, calendar: calendar), "21 hours ago")
        XCTAssertEqual(relative(seconds: -22 * 3_600, now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(relative(dateComponent: .day, value: -4, now: now, calendar: calendar), "4 days ago")
        XCTAssertEqual(relative(dateComponent: .day, value: -5, now: now, calendar: calendar), "1 week ago")
        XCTAssertEqual(relative(dateComponent: .weekOfYear, value: -3, now: now, calendar: calendar), "3 weeks ago")
        XCTAssertEqual(relative(dateComponent: .weekOfYear, value: -4, now: now, calendar: calendar), "4 weeks ago")
        XCTAssertEqual(relative(dateComponent: .month, value: -10, now: now, calendar: calendar), "10 months ago")
        XCTAssertEqual(relative(dateComponent: .month, value: -11, now: now, calendar: calendar), "1 year ago")
        XCTAssertEqual(relative(seconds: 0, now: now, calendar: calendar), "Now")

        let boundaryNow = ISO8601DateFormatter().date(from: "2026-09-13T12:00:00Z")!
        let boundaryFrom = ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z")!
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        XCTAssertEqual(
            WeatherRelativeTimeFormatter.string(
                from: boundaryFrom, to: boundaryNow, preferences: preferences, calendar: mondayFirst
            ),
            "5 days ago"
        )
        XCTAssertEqual(
            WeatherRelativeTimeFormatter.string(
                from: boundaryFrom, to: boundaryNow, preferences: preferences, calendar: sundayFirst
            ),
            "1 week ago"
        )
    }

    private var baseAttributes: [String: JSONValue] {
        ["temperature_unit": .string("°C"), "precipitation_unit": .string("mm")]
    }

    private func resolve(
        _ state: HAState,
        selected: HAWeatherForecastType?,
        event: HAWeatherForecastEvent? = nil,
        now: Date = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!,
        calendar: Calendar = .current
    ) -> WeatherDetailPresentation {
        WeatherDetailPresentationResolver.resolve(
            state: state,
            selectedType: selected,
            modernEvent: event,
            serverUnitSystem: .init(temperature: "°C", length: "km"),
            serverTimeZone: "Asia/Shanghai",
            preferences: preferences,
            now: now,
            hostCalendar: calendar,
            symbolAvailability: { _ in true }
        )
    }

    private func weatherState(
        condition: String,
        attributes: [String: JSONValue]
    ) -> HAState {
        HAState(
            entityId: "weather.home",
            state: condition,
            attributes: attributes,
            lastChanged: "2026-09-09T11:55:00Z",
            lastUpdated: "2026-09-09T11:57:00Z"
        )
    }

    private func legacyArray(gapHours: Int, count: Int) -> JSONValue {
        .array((0..<count).map { index in
            .object([
                "datetime": .string(String(format: "2026-09-%02dT00:00:00Z", 9 + (index * gapHours / 24))
                    .replacingOccurrences(of: "T00", with: String(format: "T%02d", (index * gapHours) % 24))),
                "temperature": .double(Double(20 + index)),
            ])
        })
    }

    private func relative(seconds: TimeInterval, now: Date, calendar: Calendar) -> String {
        WeatherRelativeTimeFormatter.string(
            from: now.addingTimeInterval(seconds),
            to: now,
            preferences: preferences,
            calendar: calendar
        )
    }

    private func relative(
        dateComponent: Calendar.Component,
        value: Int,
        now: Date,
        calendar: Calendar
    ) -> String {
        WeatherRelativeTimeFormatter.string(
            from: calendar.date(byAdding: dateComponent, value: value, to: now),
            to: now,
            preferences: preferences,
            calendar: calendar
        )
    }
}
