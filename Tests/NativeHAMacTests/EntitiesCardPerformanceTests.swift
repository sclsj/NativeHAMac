import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class EntitiesCardPerformanceTests: XCTestCase {
    func testFiveHundredMixedRowsColdAndWarmPresentationPerformance() {
        let fixture = makeFixture(count: 500)
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let presentations = fixture.rows.map {
                EntityRowPresentationResolver.resolve(
                    row: $0,
                    cardStateColor: true,
                    states: fixture.states,
                    registryDisplayPrecisions: fixture.precisions,
                    registryIcons: fixture.icons,
                    preferences: fixture.preferences,
                    serverTimeZone: "UTC",
                    now: Date(timeIntervalSince1970: 1_788_225_600),
                    symbolAvailability: { _ in true }
                )
            }
            XCTAssertEqual(presentations.count, 500)
            XCTAssertEqual(presentations.filter(\.isSupported).count, 500)
        }
        print("MODULE06_PERF scenario=500-mixed-rows iterations=3 cache=none")
    }

    func testOneHundredOfFiveHundredStateUpdatePresentationPerformance() {
        var fixture = makeFixture(count: 500)
        let changedRows = Array(fixture.rows.prefix(100))
        for index in 0..<100 {
            let entityID = "sensor.value_\(index)"
            fixture.states[entityID] = HAState(
                entityId: entityID,
                state: "\(index).750",
                attributes: [
                    "friendly_name": .string("Updated \(index)"),
                    "unit_of_measurement": .string(index.isMultiple(of: 2) ? "%" : "W"),
                ]
            )
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let updated = changedRows.map {
                EntityRowPresentationResolver.resolve(
                    row: $0,
                    cardStateColor: nil,
                    states: fixture.states,
                    registryDisplayPrecisions: fixture.precisions,
                    registryIcons: fixture.icons,
                    preferences: fixture.preferences,
                    serverTimeZone: "UTC",
                    now: Date(timeIntervalSince1970: 1_788_225_600),
                    symbolAvailability: { _ in true }
                )
            }
            XCTAssertEqual(updated.count, 100)
            XCTAssertEqual(updated[99].name, "Updated 99")
        }
        print("MODULE06_PERF scenario=100-of-500-state-update iterations=5 cache=none")
    }

    private func makeFixture(count: Int) -> Fixture {
        var rows: [LovelacePresentationRow] = []
        var states: [String: HAState] = [:]
        var precisions: [String: Int] = [:]
        var icons: [String: String] = [:]
        for index in 0..<count {
            let entityID = "sensor.value_\(index)"
            let raw: JSONValue = index.isMultiple(of: 3)
                ? .string(entityID)
                : .object([
                    "entity": .string(entityID),
                    "secondary_info": .string(index.isMultiple(of: 2) ? "entity-id" : "state"),
                ])
            let source = LovelaceEntityRef(rawValue: raw, diagnosticPath: "rows[\(index)]")
            let path = LovelaceSourcePath().appending("entities", index: index)
            rows.append(LovelacePresentationRow(
                source: source,
                identity: LovelaceResolvedIdentity(sourcePath: path, rawValue: raw),
                isSynthetic: false
            ))
            states[entityID] = HAState(
                entityId: entityID,
                state: "\(index).250",
                attributes: [
                    "friendly_name": .string("Value \(index)"),
                    "unit_of_measurement": .string(index.isMultiple(of: 2) ? "%" : "W"),
                ]
            )
            if index.isMultiple(of: 4) { precisions[entityID] = 2 }
            if index.isMultiple(of: 5) { icons[entityID] = "mdi:thermometer" }
        }
        return Fixture(
            rows: rows,
            states: states,
            precisions: precisions,
            icons: icons,
            preferences: HAFrontendLocalePreferences(
                language: "en_US_POSIX",
                numberFormat: "none",
                timeFormat: "24",
                dateFormat: "system",
                firstWeekday: "monday",
                timeZone: "server"
            )
        )
    }
}

private struct Fixture {
    let rows: [LovelacePresentationRow]
    var states: [String: HAState]
    let precisions: [String: Int]
    let icons: [String: String]
    let preferences: HAFrontendLocalePreferences
}
