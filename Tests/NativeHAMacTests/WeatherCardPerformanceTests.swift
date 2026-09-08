import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class WeatherCardPerformanceTests: XCTestCase {
    func testFiveHundredMixedCurrentPresentationsCanBeMeasuredCold() throws {
        let fixtures = try makeFixtures(revision: 0)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let results = zip(fixtures.cards, fixtures.states).map { card, state in
                WeatherPresentationResolver.resolve(
                    card: card,
                    state: state,
                    serverUnitSystem: fixtures.units,
                    preferences: fixtures.preferences,
                    symbolAvailability: { _ in true }
                )
            }
            XCTAssertEqual(results.count, 500)
            XCTAssertGreaterThan(results.reduce(0) { $0 + $1.condition.utf8.count }, 1_000)
        }
    }

    func testFiveHundredWarmStateReplacementsCanBeMeasuredWithoutOwners() throws {
        let initial = try makeFixtures(revision: 0)
        let updated = try makeFixtures(revision: 1)
        _ = zip(initial.cards, initial.states).map { card, state in
            WeatherPresentationResolver.resolve(
                card: card,
                state: state,
                serverUnitSystem: initial.units,
                preferences: initial.preferences,
                symbolAvailability: { _ in true }
            )
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let results = zip(initial.cards, updated.states).map { card, state in
                WeatherPresentationResolver.resolve(
                    card: card,
                    state: state,
                    serverUnitSystem: initial.units,
                    preferences: initial.preferences,
                    symbolAvailability: { _ in true }
                )
            }
            XCTAssertEqual(results.count, 500)
            XCTAssertTrue(results.contains { $0.condition == "Rainy" })
            XCTAssertTrue(results.allSatisfy(\.rendersCurrent))
        }
    }

    private func makeFixtures(revision: Int) throws -> (
        cards: [LovelacePresentationCard],
        states: [HAState],
        units: HAUnitSystem,
        preferences: HAFrontendLocalePreferences
    ) {
        let rawCards: [JSONValue] = (0..<500).map { index in
            var object: [String: JSONValue] = [
                "type": .string("weather-forecast"),
                "entity": .string("weather.fixture_\(index)"),
                "show_forecast": .bool(false),
            ]
            if index % 7 == 0 { object["round_temperature"] = .bool(true) }
            if index % 5 == 0 { object["secondary_info_attribute"] = .string("pressure") }
            return .object(object)
        }
        let config = try LovelaceConfig(rawValue: .object([
            "views": .array([.object([
                "title": .string("Weather"),
                "path": .string("default_view"),
                "cards": .array(rawCards),
            ])]),
        ]))
        let cards = LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        ).views[0].cards
        let conditions = ["sunny", "cloudy", "rainy", "clear-night", "fog"]
        let states: [HAState] = (0..<500).map { index in
            var attributes: [String: JSONValue] = [
                "friendly_name": .string("Weather fixture \(index)"),
                "temperature": index % 13 == 0
                    ? .string("malformed")
                    : .double(Double((index + revision) % 35) + 0.25),
                "temperature_unit": .string("°C"),
                "humidity": index % 11 == 0 ? .null : .int((index + revision) % 100),
                "pressure": .double(995 + Double(index % 30)),
            ]
            if index % 17 == 0 { attributes.removeValue(forKey: "temperature") }
            return HAState(
                entityId: "weather.fixture_\(index)",
                state: conditions[(index + revision) % conditions.count],
                attributes: attributes
            )
        }
        return (
            cards,
            states,
            HAUnitSystem(temperature: "°C", length: "km"),
            HAFrontendLocalePreferences(
                language: "en", numberFormat: "comma_decimal", timeFormat: "24",
                dateFormat: "language", firstWeekday: "language", timeZone: "server"
            )
        )
    }
}
