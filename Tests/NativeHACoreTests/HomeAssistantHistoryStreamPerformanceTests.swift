import Foundation
import XCTest
@testable import NativeHACore

final class HomeAssistantHistoryStreamPerformanceTests: XCTestCase {
    func testReferenceScaleDecodeMetrics() throws {
        let fixture = referenceReplay()
        let encoded = try JSONEncoder().encode(fixture)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let consumer = HistoryPerformanceConsumer()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            do {
                let decoded = try JSONDecoder().decode(HAHistoryStreamMessage.self, from: encoded)
                consumer.consume(decoded.states)
            } catch {
                XCTFail("Reference-scale decode failed: \(error)")
            }
        }
        XCTAssertEqual(consumer.lastCount, 25_000)
        XCTAssertNotEqual(consumer.lastChecksum, 0)
    }

    func testReferenceScaleColdReplayMergeMetrics() {
        let replay = referenceReplay()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let consumer = HistoryPerformanceConsumer()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            var accumulator = HAHistoryStreamAccumulator(range: nil)
            consumer.consume(accumulator.process(replay))
        }
        XCTAssertEqual(consumer.lastCount, 25_000)
        XCTAssertNotEqual(consumer.lastChecksum, 0)
    }

    func testReferenceScaleWarmTwentyChunkMergeMetrics() {
        let replay = referenceReplay()
        let chunks = referenceIncrementalChunks()
        var baseline = HAHistoryStreamAccumulator(range: nil)
        _ = baseline.process(replay)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let consumer = HistoryPerformanceConsumer()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            var accumulator = baseline
            var result: [String: [HACompactHistoryState]] = [:]
            for chunk in chunks {
                result = accumulator.process(chunk)
            }
            consumer.consume(result)
        }
        XCTAssertEqual(consumer.lastCount, 26_000)
        XCTAssertNotEqual(consumer.lastChecksum, 0)
    }

    func testRescueScaleOutOfOrderMergeMetrics() {
        let replay = rescueReplay(count: 20_000)
        let outOfOrder = rescueOutOfOrderChunks()
        var baseline = HAHistoryStreamAccumulator(range: nil)
        _ = baseline.process(replay)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let consumer = HistoryPerformanceConsumer()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            var accumulator = baseline
            var result: [String: [HACompactHistoryState]] = [:]
            for chunk in outOfOrder {
                result = accumulator.process(chunk)
            }
            consumer.consume(result)
        }
        XCTAssertEqual(consumer.lastCount, 40_000)
        XCTAssertNotEqual(consumer.lastChecksum, 0)
    }

    func testRescueScaleRollingTrimMetricsAndBroaderFixtureIsUnchanged() {
        let broader = rescueReplay(count: 20_000)
        let originalCount = broader.states["sensor.rescue"]?.count
        let now = Date(timeIntervalSince1970: 30_000)
        var baseline = HAHistoryStreamAccumulator(range: 3_600, now: { now })
        _ = baseline.process(broader)
        let trigger = HAHistoryStreamMessage(states: ["sensor.rescue": []])
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let consumer = HistoryPerformanceConsumer()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            var accumulator = baseline
            consumer.consume(accumulator.process(trigger))
        }
        XCTAssertEqual(broader.states["sensor.rescue"]?.count, originalCount)
        XCTAssertGreaterThan(consumer.lastCount, 0)
        XCTAssertLessThan(consumer.lastCount, 20_000)
    }

    private func referenceReplay() -> HAHistoryStreamMessage {
        var states: [String: [HACompactHistoryState]] = [:]
        for entity in 0..<5 {
            let entityID = "sensor.reference_\(entity)"
            states[entityID] = (0..<5_000).map { index in
                compact(entity: entity, sequence: index, timestamp: Double(10_000 + index))
            }
        }
        return HAHistoryStreamMessage(states: states, startTime: 10_000, endTime: 15_000)
    }

    private func referenceIncrementalChunks() -> [HAHistoryStreamMessage] {
        (0..<20).map { chunk in
            var states: [String: [HACompactHistoryState]] = [:]
            for entity in 0..<5 {
                let entityID = "sensor.reference_\(entity)"
                states[entityID] = (0..<10).map { offset in
                    let sequence = 5_000 + chunk * 10 + offset
                    return compact(
                        entity: entity,
                        sequence: sequence,
                        timestamp: Double(15_000 + chunk * 10 + offset)
                    )
                }
            }
            return HAHistoryStreamMessage(states: states)
        }
    }

    private func rescueReplay(count: Int) -> HAHistoryStreamMessage {
        HAHistoryStreamMessage(states: [
            "sensor.rescue": (0..<count).map { index in
                compact(entity: 0, sequence: index, timestamp: Double(10_000 + index))
            },
        ])
    }

    private func rescueOutOfOrderChunks() -> [HAHistoryStreamMessage] {
        (0..<100).map { chunk in
            let base = 29_900 - chunk * 200
            return HAHistoryStreamMessage(states: [
                "sensor.rescue": (0..<200).map { offset in
                    compact(
                        entity: 0,
                        sequence: 20_000 + chunk * 200 + offset,
                        timestamp: Double(base + offset)
                    )
                },
            ])
        }
    }

    private func compact(entity: Int, sequence: Int, timestamp: Double) -> HACompactHistoryState {
        HACompactHistoryState(
            state: "\(entity)-\(sequence)",
            attributes: sequence % 1_000 == 0 ? ["sequence": .int(sequence)] : [:],
            lastChangedSeconds: sequence % 3 == 0 ? timestamp - 0.125 : nil,
            lastUpdatedSeconds: timestamp + 0.625
        )
    }
}

private final class HistoryPerformanceConsumer {
    private(set) var lastCount = 0
    private(set) var lastChecksum: UInt64 = 0

    func consume(_ history: [String: [HACompactHistoryState]]) {
        var count = 0
        var checksum: UInt64 = 14_695_981_039_346_656_037
        for entityID in history.keys.sorted() {
            for byte in entityID.utf8 {
                checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211
            }
            for state in history[entityID] ?? [] {
                count += 1
                checksum ^= state.lastUpdatedSeconds.bitPattern
                checksum &*= 1_099_511_628_211
                if let first = state.state.utf8.first {
                    checksum ^= UInt64(first)
                }
            }
        }
        lastCount = count
        lastChecksum = checksum
    }
}
