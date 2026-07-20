import CoreGraphics
import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class GraphRenderingBenchmarkTests: XCTestCase {
    func testProductionShapedHundredThousandPointSettledAppendPipeline() async throws {
        let entityIDs = (0..<4).map { "sensor.pipeline_\($0)" }
        let pointsPerEntity = 25_000
        let baseTimestamp = 1_700_000_000.0
        var initialStates: [String: [HACompactHistoryState]] = [:]
        for (entity, entityID) in entityIDs.enumerated() {
            initialStates[entityID] = (0..<pointsPerEntity).map { index in
                pipelineState(entity: entity, index: index, baseTimestamp: baseTimestamp)
            }
        }
        let chunks: [HAHistoryStreamMessage] = (0..<20).map { chunk -> HAHistoryStreamMessage in
            var states: [String: [HACompactHistoryState]] = [:]
            for (entity, entityID) in entityIDs.enumerated() {
                states[entityID] = (0..<5).map { offset in
                    let index = pointsPerEntity + chunk * 5 + offset
                    return pipelineState(entity: entity, index: index, baseTimestamp: baseTimestamp)
                }
            }
            return HAHistoryStreamMessage(states: states)
        }
        let clock = GraphBenchmarkClock(Date(timeIntervalSince1970: baseTimestamp + 25_000))
        var accumulator = HAHistoryStreamAccumulator(
            range: 24_999.25,
            now: { clock.now() }
        )
        let projectionStore = HAHistoryProjectionStore(orderedEntityIDs: entityIDs)
        GraphBitmapRenderer.resetPreparedSeriesCache()

        var accumulatorNanoseconds: UInt64 = 0
        var projectionNanoseconds: UInt64 = 0
        var preparationNanoseconds: UInt64 = 0
        var coalescedResetCount = 0
        var deliveredNormalCount = 0

        let initialStart = DispatchTime.now().uptimeNanoseconds
        let initial = accumulator.processPublication(HAHistoryStreamMessage(states: initialStates))
        accumulatorNanoseconds += DispatchTime.now().uptimeNanoseconds - initialStart
        let initialPublication = HAHistoryStreamPublication(accumulation: initial, ownerGeneration: 1)
        let initialProjectionStart = DispatchTime.now().uptimeNanoseconds
        let initialProjected = await projectionStore.series(from: initialPublication)
        var latestSeries = try XCTUnwrap(initialProjected)
        projectionNanoseconds += DispatchTime.now().uptimeNanoseconds - initialProjectionStart
        let initialPreparationStart = DispatchTime.now().uptimeNanoseconds
        try preparePipelineSeries(latestSeries)
        preparationNanoseconds += DispatchTime.now().uptimeNanoseconds - initialPreparationStart

        var pending: HAHistoryStreamPublication?
        for (index, chunk) in chunks.enumerated() {
            clock.advance(by: 5)
            let accumulatorStart = DispatchTime.now().uptimeNanoseconds
            let accumulation = accumulator.processPublication(chunk)
            accumulatorNanoseconds += DispatchTime.now().uptimeNanoseconds - accumulatorStart
            let publication = HAHistoryStreamPublication(accumulation: accumulation, ownerGeneration: 1)
            if let previous = pending {
                pending = HAHistoryStreamCoordinator.coalescing(previous, with: publication)
            } else {
                pending = publication
            }

            guard (index + 1).isMultiple(of: 4), let delivery = pending else { continue }
            pending = nil
            switch delivery.transition {
            case .reset, .outOfOrderReset:
                coalescedResetCount += 1
            case .normal:
                deliveredNormalCount += 1
            case .unchanged:
                break
            }
            let projectionStart = DispatchTime.now().uptimeNanoseconds
            let projected = await projectionStore.series(from: delivery)
            latestSeries = try XCTUnwrap(projected)
            projectionNanoseconds += DispatchTime.now().uptimeNanoseconds - projectionStart
            let preparationStart = DispatchTime.now().uptimeNanoseconds
            try preparePipelineSeries(latestSeries)
            preparationNanoseconds += DispatchTime.now().uptimeNanoseconds - preparationStart
        }

        let finalHistory = accumulator.combinedHistory
        let oracle = HAHistoryProjection.series(from: finalHistory, orderedEntityIDs: entityIDs)
        XCTAssertEqual(latestSeries.map(\.points), oracle.map(\.points))
        let accumulatorStatistics = accumulator.statistics()
        let projectionStatistics = await projectionStore.statistics()
        let preparationStatistics = GraphBitmapRenderer.preparedSeriesCacheStatistics()
        XCTAssertEqual(coalescedResetCount, 0)
        XCTAssertEqual(deliveredNormalCount, 5)
        XCTAssertEqual(accumulatorStatistics.resetPublicationCount, 1)
        XCTAssertEqual(accumulatorStatistics.normalPublicationCount, 20)
        XCTAssertEqual(accumulatorStatistics.outOfOrderResetPublicationCount, 0)
        XCTAssertEqual(accumulatorStatistics.fullEntityRebuildCount, 0)
        XCTAssertEqual(accumulatorStatistics.reusableEntityPathCount, 80)
        XCTAssertEqual(projectionStatistics.fullEntityProjectionCount, 4)
        XCTAssertEqual(projectionStatistics.incrementalEntityProjectionCount, 20)
        XCTAssertEqual(preparationStatistics.fullPreparationCount, 4)
        XCTAssertEqual(preparationStatistics.incrementalPreparationCount, 20)
        let totalMilliseconds = Double(
            accumulatorNanoseconds + projectionNanoseconds + preparationNanoseconds
        ) / 1_000_000
        print(
            "GRAPH_SETTLED_PIPELINE entities=4 points=\(latestSeries.reduce(0) { $0 + $1.points.count }) " +
            "updates=20 deliveries=5 coalesced_resets=\(coalescedResetCount) " +
            "delivered_normals=\(deliveredNormalCount) " +
            "accumulator_full_fallbacks=\(accumulatorStatistics.fullEntityRebuildCount) " +
            "accumulator_reusable=\(accumulatorStatistics.reusableEntityPathCount) " +
            "projection_full=\(projectionStatistics.fullEntityProjectionCount) " +
            "projection_incremental=\(projectionStatistics.incrementalEntityProjectionCount) " +
            "prepared_full=\(preparationStatistics.fullPreparationCount) " +
            "prepared_incremental=\(preparationStatistics.incrementalPreparationCount) " +
            "accumulator_ms=\(formatMilliseconds(accumulatorNanoseconds)) " +
            "projection_ms=\(formatMilliseconds(projectionNanoseconds)) " +
            "prepared_minmax_ms=\(formatMilliseconds(preparationNanoseconds)) " +
            "total_ms=\(String(format: "%.3f", totalMilliseconds))"
        )
    }

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

private final class GraphBenchmarkClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private func preparePipelineSeries(_ series: [HAHistorySeries]) throws {
    for (index, history) in series.enumerated() {
        let input = GraphRenderSeriesInput(
            entityID: history.entityID,
            name: history.entityID,
            unit: "µg/m³",
            color: GraphColor(
                red: CGFloat(index + 1) / CGFloat(series.count + 1),
                green: 0.6,
                blue: 0.9,
                alpha: 1
            ),
            history: history
        )
        let prepared = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(input, displayUnit: "µg/m³")
        )
        let cache = try XCTUnwrap(prepared.minMaxCache)
        _ = cache.downsample(in: 0..<prepared.points.count, target: 442)
    }
}

private func formatMilliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
}

private func pipelineState(
    entity: Int,
    index: Int,
    baseTimestamp: Double
) -> HACompactHistoryState {
    HACompactHistoryState(
        state: String((entity * 17 + index) % 500),
        lastChangedSeconds: baseTimestamp + Double(index) + 0.125,
        lastUpdatedSeconds: baseTimestamp + Double(index) + 0.625
    )
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
        engine: .coreGraphics,
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
        contentsOfFile: AppConfig.tokenFilePath,
        encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let configured = environment["HA_BASE_URL"].flatMap(URL.init(string:))
    let baseURLs = [configured].compactMap { $0 } + AppConfig.baseURLs

    var lastError: Error?
    var attempted: Set<URL> = []
    for baseURL in baseURLs where attempted.insert(baseURL).inserted {
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
