import XCTest
@testable import NativeHACore

final class HistoryGraphSupportTests: XCTestCase {
    func testTimelineIncludesStateBeforeVisibleStartAndClipsIt() {
        let segments = HAHistoryTimelineBuilder.segments(
            from: [
                HAHistoryTimelinePoint(timestamp: 0, state: "off"),
                HAHistoryTimelinePoint(timestamp: 20, state: "on"),
            ],
            visibleStart: 10,
            visibleEnd: 30
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].state, "off")
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[0].end, 20)
        XCTAssertEqual(segments[0].clippedStart, 10)
        XCTAssertEqual(segments[0].clippedEnd, 20)
        XCTAssertEqual(segments[1].state, "on")
        XCTAssertEqual(segments[1].clippedStart, 20)
        XCTAssertEqual(segments[1].clippedEnd, 30)
    }

    func testTimelineCollapsesConsecutiveDuplicateStates() {
        let segments = HAHistoryTimelineBuilder.segments(
            from: [
                HAHistoryTimelinePoint(timestamp: 0, state: "off"),
                HAHistoryTimelinePoint(timestamp: 10, state: "off"),
                HAHistoryTimelinePoint(timestamp: 20, state: "on"),
            ],
            visibleStart: 0,
            visibleEnd: 30
        )

        XCTAssertEqual(segments.map(\.state), ["off", "on"])
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[0].end, 20)
    }

    func testTimestampParserPrefersLastChangedOverLastUpdated() throws {
        let point = HAHistoryPoint(
            entityId: "switch.test",
            state: "on",
            attributes: nil,
            lastChanged: "2026-01-01T00:00:10Z",
            lastUpdated: "2026-01-01T00:00:20Z"
        )

        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T00:00:10Z"))
        let timestamp = try XCTUnwrap(HAHistoryTimestampParser().timestamp(from: point))
        XCTAssertEqual(timestamp, expected.timeIntervalSince1970)
    }

    func testTimestampParserMatchesFoundationForUTCOffsetsAndFractionalSeconds() throws {
        let values = [
            "2026-01-01T00:00:10Z",
            "2026-01-01T00:00:10.125Z",
            "2026-01-01T08:00:10+08:00",
            "2025-12-31T18:30:10-05:30",
            "2026-01-01T08:00:10.125+08:00",
        ]
        let normal = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parser = HAHistoryTimestampParser()

        for value in values {
            let expected = try XCTUnwrap(fractional.date(from: value) ?? normal.date(from: value), value)
            let point = HAHistoryPoint(
                entityId: "sensor.timestamp",
                state: "1",
                attributes: nil,
                lastChanged: value,
                lastUpdated: nil
            )
            XCTAssertEqual(
                try XCTUnwrap(parser.timestamp(from: point), value),
                expected.timeIntervalSince1970,
                accuracy: 0.000_001,
                value
            )
        }
    }

    func testTimestampParserRejectsMalformedCanonicalFieldsAndTrailingInput() {
        let malformed = [
            "2026-13-01T00:00:10Z",
            "2026-02-30T00:00:10Z",
            "2026-01-01T24:00:10Z",
            "2026-01-01T00:60:10Z",
            "2026-01-01T00:00:60Z",
            "2026-01-01T00:00:10.Z",
            "2026-01-01T00:00:10Ztrailing",
            "2026-01-01T00:00:10+08:60",
        ]
        let parser = HAHistoryTimestampParser()

        for value in malformed {
            let point = HAHistoryPoint(
                entityId: "sensor.timestamp",
                state: "1",
                attributes: nil,
                lastChanged: value,
                lastUpdated: nil
            )
            XCTAssertNil(parser.timestamp(from: point), value)
        }
    }

    func testTimestampParserCanonicalFastPathPerformance() {
        let parser = HAHistoryTimestampParser()
        let points = (0..<20_000).map { index in
            HAHistoryPoint(
                entityId: "sensor.timestamp",
                state: "1",
                attributes: nil,
                lastChanged: String(format: "2026-01-01T00:%02d:%02d.%03dZ", (index / 60) % 60, index % 60, index % 1_000),
                lastUpdated: nil
            )
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            var checksum = 0.0
            for point in points {
                checksum += parser.timestamp(from: point) ?? 0
            }
            XCTAssertGreaterThan(checksum, 0)
        }
    }

    func testUnknownAndUnavailableRemainSegmentsWithDistinctColors() {
        let segments = HAHistoryTimelineBuilder.segments(
            from: [
                HAHistoryTimelinePoint(timestamp: 0, state: "unknown"),
                HAHistoryTimelinePoint(timestamp: 10, state: "unavailable"),
            ],
            visibleStart: 0,
            visibleEnd: 20
        )

        XCTAssertEqual(segments.map(\.state), ["unknown", "unavailable"])
        let unknown = HAHistoryTimelineColorResolver.color(for: "unknown", entityID: "switch.test")
        let unavailable = HAHistoryTimelineColorResolver.color(for: "unavailable", entityID: "switch.test")
        XCTAssertNotEqual(unknown.hex, unavailable.hex)
    }

    func testBinarySensorAndSwitchClassifyAsTimelines() {
        let binaryHistory = history(entityID: "binary_sensor.ultrasonic", states: ["off", "on"])
        let switchHistory = history(entityID: "switch.lamp", states: ["off", "on"])

        XCTAssertEqual(
            HAHistoryGraphClassifier.displayUnit(
                entityID: binaryHistory.entityID,
                currentUnit: nil,
                currentAttributes: nil,
                history: binaryHistory
            ),
            HAHistoryGraphClassifier.stateUnit
        )
        XCTAssertEqual(
            HAHistoryGraphClassifier.displayUnit(
                entityID: switchHistory.entityID,
                currentUnit: nil,
                currentAttributes: nil,
                history: switchHistory
            ),
            HAHistoryGraphClassifier.stateUnit
        )
    }

    func testNumericSensorWithUnitClassifiesAsLineGraph() {
        let sensorHistory = history(entityID: "sensor.temperature", states: ["20.1", "20.4"])
        let unit = HAHistoryGraphClassifier.displayUnit(
            entityID: sensorHistory.entityID,
            currentUnit: "°C",
            currentAttributes: ["unit_of_measurement": "°C"],
            history: sensorHistory
        )

        XCTAssertEqual(unit, "°C")
    }

    private func history(entityID: String, states: [String]) -> HAHistorySeries {
        HAHistorySeries(
            entityID: entityID,
            points: states.enumerated().map { index, state in
                HAHistoryPoint(
                    entityId: entityID,
                    state: state,
                    attributes: nil,
                    lastChanged: "2026-01-01T00:00:\(String(format: "%02d", index))Z",
                    lastUpdated: "2026-01-01T00:00:\(String(format: "%02d", index))Z"
                )
            }
        )
    }
}
