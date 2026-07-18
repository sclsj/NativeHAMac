import CoreGraphics
import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class GraphRenderingBenchmarkTests: XCTestCase {
    func testAdversarialMinMaxMatchesScalarOracle() {
        let points = (0..<100_000).map { index -> GraphRenderedPoint in
            var value = sin(Double(index) / 37) * 4 + cos(Double(index) / 113)
            if index == 4_321 { value = 900 }
            if index == 76_543 { value = -700 }
            return GraphRenderedPoint(t: Double(index), y: value, display: String(value))
        }
        let cache = GraphMinMaxCache(points: points)
        let windows = [
            0..<points.count,
            3_000..<8_000,
            4_000..<80_000,
            70_000..<90_000,
        ]

        for window in windows {
            let expected = scalarMinMax(points, in: window, target: 442)
            let actual = cache.downsample(in: window, target: 442)
            XCTAssertEqual(actual, expected, "Min/max output changed for \(window)")
        }
    }

    @MainActor
    func testEightMillisecondSchedulerCadence() {
        let renderLatency = 0.020
        let eventInterval = 0.008
        let eventCount = 24
        let scheduler = GraphViewportRenderScheduler { _ in
            Thread.sleep(forTimeInterval: renderLatency)
            return nil
        }
        let start = ProcessInfo.processInfo.systemUptime
        var publicationTimes: [Double] = []
        var tokens: [String] = []

        for index in 0..<eventCount {
            scheduler.schedule(benchmarkRequest(token: "token-\(index)")) { delivery in
                tokens.append(delivery.request.token)
                publicationTimes.append(ProcessInfo.processInfo.systemUptime - start)
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: eventInterval))
        }

        let gestureDuration = ProcessInfo.processInfo.systemUptime - start
        let publicationsDuringGesture = publicationTimes.filter { $0 < gestureDuration }.count
        let strictLatestPublicationsDuringGesture = (0..<eventCount).filter { index in
            let completion = Double(index) * eventInterval + renderLatency
            guard completion < Double(eventCount) * eventInterval else { return false }
            let desiredIndexAtCompletion = min(Int(completion / eventInterval), eventCount - 1)
            return desiredIndexAtCompletion == index
        }.count
        let deadline = Date(timeIntervalSinceNow: 1)
        while tokens.last != "token-\(eventCount - 1)", Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }

        XCTAssertGreaterThanOrEqual(publicationsDuringGesture, 3)
        XCTAssertEqual(strictLatestPublicationsDuringGesture, 0)
        XCTAssertEqual(tokens.last, "token-\(eventCount - 1)")
        XCTAssertEqual(scheduler.statistics.maximumConcurrentCount, 1)
        XCTAssertLessThan(scheduler.statistics.startedCount, eventCount)
        print(
            "GRAPH_SCHEDULER events=\(eventCount) interval_ms=8 render_ms=20 " +
            "started=\(scheduler.statistics.startedCount) " +
            "completed=\(scheduler.statistics.completedCount) " +
            "replaced_pending=\(scheduler.statistics.replacedPendingCount) " +
            "published_during_gesture=\(publicationsDuringGesture) " +
            "strict_latest_published_during_gesture=\(strictLatestPublicationsDuringGesture) " +
            "max_concurrent=\(scheduler.statistics.maximumConcurrentCount)"
        )
    }
}

final class GraphRenderingLiveBenchmarkTests: XCTestCase {
    func testLiveSPS30OneAndTwentyFourHourPipeline() async throws {
        guard ProcessInfo.processInfo.environment["NATIVEHA_LIVE_GRAPH_BENCHMARK"] == "1" else {
            throw XCTSkip("Set NATIVEHA_LIVE_GRAPH_BENCHMARK=1 for the read-only live benchmark")
        }

        let client = try await liveClient()
        let entityIDs = benchmarkEntityIDs()
        let iterations = max(
            Int(ProcessInfo.processInfo.environment["NATIVEHA_GRAPH_BENCH_ITERATIONS"] ?? "") ?? 30,
            5
        )

        let machineName = Host.current().localizedName ?? "unknown"
        print("GRAPH_LIVE machine=\(machineName) iterations=\(iterations)")
        print("GRAPH_LIVE entities=\(entityIDs.joined(separator: ","))")

        for hours in [1, 24] {
            let fetchStart = ProcessInfo.processInfo.systemUptime
            let history = try await client.fetchHistory(entityIDs: entityIDs, hoursToShow: hours)
                .sorted { $0.entityID < $1.entityID }
            let fetchMilliseconds = (ProcessInfo.processInfo.systemUptime - fetchStart) * 1_000
            let encodedBytes = try JSONEncoder().encode(history).count
            let inputs = graphInputs(history)
            let pointCount = history.reduce(0) { $0 + $1.points.count }

            XCTAssertEqual(inputs.count, entityIDs.count)
            print(
                "GRAPH_LIVE_DATA hours=\(hours) series=\(inputs.count) points=\(pointCount) " +
                "decoded_json_bytes=\(encodedBytes) fetch_ms=\(format(fetchMilliseconds))"
            )

            var scaleResults: [CGFloat: GraphRenderResult] = [:]
            for scale: CGFloat in [1, 2] {
                GraphBitmapRenderer.resetPreparedSeriesCache()
                let cold = try measuredRender(
                    inputs: inputs,
                    scale: scale,
                    zoomScale: 4,
                    panFraction: 0.50
                )
                scaleResults[scale] = cold.result

                _ = try measuredRender(
                    inputs: inputs,
                    scale: scale,
                    zoomScale: 4,
                    panFraction: 0.50
                )
                var warm: [GraphRenderMetrics] = []
                warm.reserveCapacity(iterations)
                for index in 0..<iterations {
                    let pan = Double(index % 19) / 18
                    warm.append(try measuredRender(
                        inputs: inputs,
                        scale: scale,
                        zoomScale: 4,
                        panFraction: pan
                    ).metrics)
                }

                printMetrics(hours: hours, scale: scale, cold: cold.metrics, warm: warm)
            }

            let oneX = try XCTUnwrap(scaleResults[1])
            let twoX = try XCTUnwrap(scaleResults[2])
            XCTAssertEqual(oneX.series.map(\.points), twoX.series.map(\.points))
            XCTAssertEqual(oneX.axis.min, twoX.axis.min)
            XCTAssertEqual(oneX.axis.max, twoX.axis.max)
            XCTAssertEqual(oneX.xTicks, twoX.xTicks)
            XCTAssertEqual(oneX.visibleStart, twoX.visibleStart)
            XCTAssertEqual(oneX.visibleEnd, twoX.visibleEnd)
            print("GRAPH_FIDELITY hours=\(hours) scale_1x_2x_points_axes_bounds_equal=yes")
        }
    }
}

private struct MeasuredRender {
    let result: GraphRenderResult
    let metrics: GraphRenderMetrics
}

private func measuredRender(
    inputs: [GraphRenderSeriesInput],
    scale: CGFloat,
    zoomScale: CGFloat,
    panFraction: Double
) throws -> MeasuredRender {
    var captured: GraphRenderMetrics?
    let result = try XCTUnwrap(GraphBitmapRenderer.render(
        inputs: inputs,
        unit: "μg/m³",
        size: CGSize(width: 496, height: 178),
        scale: scale,
        zoomScale: zoomScale,
        panFraction: panFraction,
        metrics: { captured = $0 }
    ))
    return MeasuredRender(result: result, metrics: try XCTUnwrap(captured))
}

private func printMetrics(
    hours: Int,
    scale: CGFloat,
    cold: GraphRenderMetrics,
    warm: [GraphRenderMetrics]
) {
    print(
        "GRAPH_COLD hours=\(hours) scale=\(Int(scale)) points_in=\(cold.inputPointCount) " +
        "points_drawn=\(cold.renderedPointCount) bitmap_bytes=\(cold.bitmapByteCount) " +
        "prepare_ms=\(milliseconds(cold.seriesPreparationNanoseconds)) " +
        "viewport_ms=\(milliseconds(cold.viewportPreparationNanoseconds)) " +
        "total_ms=\(milliseconds(cold.totalNanoseconds))"
    )
    print(
        "GRAPH_WARM hours=\(hours) scale=\(Int(scale)) samples=\(warm.count) " +
        "total_median_ms=\(summary(warm.map(\.totalNanoseconds)).median) " +
        "total_p95_ms=\(summary(warm.map(\.totalNanoseconds)).p95) " +
        "prepare_ms=\(summary(warm.map(\.seriesPreparationNanoseconds)).median) " +
        "viewport_ms=\(summary(warm.map(\.viewportPreparationNanoseconds)).median) " +
        "allocation_ms=\(summary(warm.map(\.bitmapAllocationNanoseconds)).median) " +
        "context_ms=\(summary(warm.map(\.contextSetupNanoseconds)).median) " +
        "background_ms=\(summary(warm.map(\.backgroundFillNanoseconds)).median) " +
        "path_ms=\(summary(warm.map(\.pathConstructionNanoseconds)).median) " +
        "stroke_ms=\(summary(warm.map(\.pathStrokeNanoseconds)).median) " +
        "snapshot_ms=\(summary(warm.map(\.imageSnapshotNanoseconds)).median)"
    )
}

private func graphInputs(_ history: [HAHistorySeries]) -> [GraphRenderSeriesInput] {
    let colors = [
        GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1),
        GraphColor(red: 0.93, green: 0.66, blue: 0.22, alpha: 1),
        GraphColor(red: 0.40, green: 0.86, blue: 0.82, alpha: 1),
        GraphColor(red: 0.95, green: 0.32, blue: 0.50, alpha: 1),
    ]
    return history.enumerated().map { index, series in
        GraphRenderSeriesInput(
            entityID: series.entityID,
            name: series.entityID,
            unit: "μg/m³",
            color: colors[index % colors.count],
            history: series
        )
    }
}

private func liveClient() async throws -> HomeAssistantRESTClient {
    let environment = ProcessInfo.processInfo.environment
    let token = try environment["HA_TOKEN"] ?? String(
        contentsOfFile: "/Users/jin/Documents/Computer/ha_apikey.txt",
        encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let configured = environment["HA_BASE_URL"].flatMap(URL.init(string:))
    let baseURLs = [configured].compactMap { $0 } + [
        "http://joyj.me:8123",
        "http://172.20.200.123:8123",
        "http://192.168.71.18:8123",
    ].compactMap(URL.init(string:))

    var lastError: Error?
    for baseURL in baseURLs {
        let configuration = HomeAssistantConfiguration(
            baseURL: baseURL,
            accessToken: token,
            timeout: 60
        )
        let client = HomeAssistantRESTClient(configuration: configuration)
        do {
            _ = try await client.fetchConfig()
            return client
        } catch {
            lastError = error
        }
    }
    throw lastError ?? URLError(.cannotConnectToHost)
}

private func benchmarkEntityIDs() -> [String] {
    if let raw = ProcessInfo.processInfo.environment["NATIVEHA_GRAPH_BENCH_ENTITY_IDS"] {
        return raw.split(separator: ",").map(String.init)
    }
    return [
        "sensor.sps30_pm4_0",
        "sensor.sps30_pm10",
        "sensor.sps30_pm2_5",
        "sensor.sps30_pm1_0",
    ]
}

private func benchmarkRequest(token: String) -> GraphViewportRenderRequest {
    GraphViewportRenderRequest(
        token: token,
        dataToken: "stable-live-data",
        inputs: [],
        unit: "μg/m³",
        size: CGSize(width: 496, height: 178),
        scale: 2,
        zoomScale: 4,
        panFraction: 0.5
    )
}

private func scalarMinMax(
    _ points: [GraphRenderedPoint],
    in range: Range<Int>,
    target: Int
) -> [GraphRenderedPoint] {
    let count = range.count
    guard count > target, target > 2 else { return Array(points[range]) }
    let bucketCount = max(target / 2, 1)
    let bucketSize = Double(count) / Double(bucketCount)
    var output: [GraphRenderedPoint] = []
    output.reserveCapacity(target + 2)

    for bucket in 0..<bucketCount {
        let start = range.lowerBound + Int(Double(bucket) * bucketSize)
        let end = min(range.lowerBound + Int(Double(bucket + 1) * bucketSize), range.upperBound)
        guard start < end else { continue }
        var minIndex = start
        var maxIndex = start
        for index in (start + 1)..<end {
            if points[index].y < points[minIndex].y { minIndex = index }
            if points[index].y > points[maxIndex].y { maxIndex = index }
        }
        for index in [minIndex, maxIndex].sorted() where output.last != points[index] {
            output.append(points[index])
        }
    }
    if output.first != points[range.lowerBound] { output.insert(points[range.lowerBound], at: 0) }
    if output.last != points[range.upperBound - 1] { output.append(points[range.upperBound - 1]) }
    return output.removingConsecutiveDuplicatesForBenchmark()
}

private struct TimingSummary {
    let median: String
    let p95: String
}

private func summary(_ nanoseconds: [UInt64]) -> TimingSummary {
    let sorted = nanoseconds.sorted()
    let median = sorted[sorted.count / 2]
    let p95Index = min(Int((Double(sorted.count) * 0.95).rounded(.up)) - 1, sorted.count - 1)
    return TimingSummary(median: milliseconds(median), p95: milliseconds(sorted[max(p95Index, 0)]))
}

private func milliseconds(_ nanoseconds: UInt64) -> String {
    format(Double(nanoseconds) / 1_000_000)
}

private func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}

private extension Array where Element == GraphRenderedPoint {
    func removingConsecutiveDuplicatesForBenchmark() -> [GraphRenderedPoint] {
        var result: [GraphRenderedPoint] = []
        result.reserveCapacity(count)
        for point in self where result.last != point { result.append(point) }
        return result
    }
}
