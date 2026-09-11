import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class WeatherDetailPerformanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_955_200)
    private let preferences = HAFrontendLocalePreferences(
        language: "en_US_POSIX",
        numberFormat: "comma_decimal",
        timeFormat: "24",
        dateFormat: "language",
        firstWeekday: "monday",
        timeZone: "UTC"
    )

    func testDeterministicThousandItemForecastPreparationCanBeMeasured() {
        let state = weatherState()
        let fixtures: [(HAWeatherForecastType, [HAWeatherForecast])] = [
            (.daily, forecasts(count: 1_000, interval: 86_400)),
            (.hourly, forecasts(count: 1_000, interval: 3_600)),
            (.twiceDaily, forecasts(count: 1_000, interval: 43_200)),
        ]
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            var consumedItems = 0
            var consumedLabels = 0
            for (type, entries) in fixtures {
                let result = resolve(state: state, type: type, entries: entries)
                consumedItems += result.forecast?.itemCount ?? 0
                consumedLabels += result.forecast?.groups
                    .flatMap(\.items)
                    .reduce(0) { $0 + $1.label.utf8.count } ?? 0
            }
            XCTAssertEqual(consumedItems, 3_000)
            XCTAssertGreaterThan(consumedLabels, 3_000)
        }
    }

    func testWarmFortyEightItemPayloadReplacementCanBeMeasured() {
        let state = weatherState()
        let replacements = (0..<20).map { revision in
            forecasts(count: 48, interval: 3_600, temperatureOffset: Double(revision))
        }
        _ = resolve(state: state, type: .hourly, entries: replacements[0])
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            var consumed = 0
            for entries in replacements {
                consumed += resolve(state: state, type: .hourly, entries: entries)
                    .forecast?.itemCount ?? 0
            }
            XCTAssertEqual(consumed, 960)
        }
    }

    func testRepeatedOpenTypeReconnectCloseCyclesCanBeMeasuredWithoutLeakingOwners() {
        let state = weatherState()
        let authority = DashboardLifetimeAuthority()
        let coordinator = DashboardWeatherDetailCoordinator(lifetimeAuthority: authority)
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            var generations = Set<UUID>()
            for cycle in 0..<500 {
                let opened = coordinator.open(
                    entityID: state.entityId,
                    state: state,
                    appGeneration: UInt64(cycle),
                    configGeneration: 1
                )
                XCTAssertNotNil(opened.candidate)
                generations.insert(coordinator.debugSnapshot().presentationGeneration)

                _ = coordinator.select(
                    .hourly,
                    appGeneration: UInt64(cycle),
                    configGeneration: 1
                )
                coordinator.connectionChanged(.reconnecting(attempt: 1))
                coordinator.connectionChanged(.ready)
                _ = coordinator.close()
                XCTAssertEqual(coordinator.ownerCount, 0)
            }
            XCTAssertEqual(generations.count, 500)
            XCTAssertNil(coordinator.selectedEntityID)
        }
    }

    private func resolve(
        state: HAState,
        type: HAWeatherForecastType,
        entries: [HAWeatherForecast]
    ) -> WeatherDetailPresentation {
        WeatherDetailPresentationResolver.resolve(
            state: state,
            selectedType: type,
            modernEvent: HAWeatherForecastEvent(type: type, forecast: entries),
            serverUnitSystem: HAUnitSystem(temperature: "°C", length: "km"),
            serverTimeZone: "UTC",
            preferences: preferences,
            now: now,
            hostCalendar: utcCalendar,
            symbolAvailability: { _ in true }
        )
    }

    private func weatherState() -> HAState {
        HAState(
            entityId: "weather.performance",
            state: "partlycloudy",
            attributes: [
                "supported_features": .int(7),
                "temperature": .double(23.5),
                "temperature_unit": .string("°C"),
                "pressure": .double(1_012.4),
                "humidity": .int(68),
                "wind_speed": .double(8.5),
                "visibility": .double(10),
            ],
            lastChanged: "2026-09-09T11:58:00Z",
            lastUpdated: "2026-09-09T11:59:00Z"
        )
    }

    private func forecasts(
        count: Int,
        interval: TimeInterval,
        temperatureOffset: Double = 0
    ) -> [HAWeatherForecast] {
        let formatter = ISO8601DateFormatter()
        var result: [HAWeatherForecast] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let date = now.addingTimeInterval(Double(index) * interval)
            let temperature = 20 + Double(index % 10) + temperatureOffset
            let temperatureLow = 12 + Double(index % 7)
            let condition = index.isMultiple(of: 2) ? "partlycloudy" : "rainy"
            result.append(HAWeatherForecast(
                datetime: formatter.string(from: date),
                temperature: temperature,
                temperatureLow: temperatureLow,
                precipitation: Double(index % 9) / 10,
                condition: condition,
                isDaytime: !index.isMultiple(of: 2)
            ))
        }
        return result
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}
