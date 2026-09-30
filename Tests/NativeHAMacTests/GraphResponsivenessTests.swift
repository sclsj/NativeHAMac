import AppKit
import SwiftUI
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class GraphResponsivenessTests: XCTestCase {
    func testDenseFilteredHistoryReusesExactLineageAndMatchesColdPreparation() throws {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let state = GraphResponsivenessState(hours: 12)
        var initialPoints = state.input.history.points
        let missingIndex = initialPoints.count / 2
        initialPoints[missingIndex] = HAHistoryPoint(
            entityId: state.input.entityID, state: "unavailable", attributes: nil,
            lastChangedSeconds: initialPoints[missingIndex].lastChangedSeconds, lastUpdatedSeconds: nil
        )
        state.input = state.input.replacingHistory(HAHistorySeries(
            entityID: state.input.entityID, points: initialPoints, contentRevision: 1
        ))
        _ = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(state.input, displayUnit: "°C"))
        var milliseconds: [Double] = []
        var actual: GraphRenderedSeries?
        for revision in 2...9 {
            state.input = state.nextInput(revision: UInt64(revision))
            let start = DispatchTime.now().uptimeNanoseconds
            actual = GraphBitmapRenderer.preparedSeriesForTesting(state.input, displayUnit: "°C")
            milliseconds.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let coldStart = DispatchTime.now().uptimeNanoseconds
        let oracle = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(
            state.input.replacingHistory(state.input.history, cacheScope: "dense-filtered-oracle"), displayUnit: "°C"
        ))
        let coldMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1_000_000
        XCTAssertEqual(try XCTUnwrap(actual).points, oracle.points)
        let statistics = GraphBitmapRenderer.preparedSeriesCacheStatistics()
        XCTAssertEqual(statistics.exactLineagePreparationCount, 8)
        XCTAssertEqual(statistics.alignmentFallbackCount, 0)
        print("GRAPH_FILTERED points=\(initialPoints.count) warm_median_ms=\(milliseconds.sorted()[4]) cold_ms=\(coldMilliseconds)")
    }

    func testQueuedViewportCannotRewindAcceptedHistoryPreparation() {
        let state = GraphResponsivenessState(hours: 1)
        let first = state.input
        let second = state.nextInput(revision: 2)
        let preparationStarted = expectation(description: "preparation started")
        let latestDelivered = expectation(description: "latest delivered")
        let gate = DispatchSemaphore(value: 0)
        let coordinator = GraphChartRenderCoordinator(preparer: { input, _ in
            if input.history.contentRevision == 1 {
                preparationStarted.fulfill()
                gate.wait()
            }
        }, renderer: { request in
            XCTAssertEqual(request.inputs.first?.history.contentRevision, 2,
                           "Rendering an older queued input would rewind the prepared cache")
            return nil
        })
        func request(_ input: GraphRenderSeriesInput) -> GraphChartVisualRequest {
            GraphChartVisualRequest(token: String(input.history.contentRevision), inputs: [input],
                                    unit: input.unit, size: CGSize(width: 496, height: 178), scale: 2,
                                    zoomScale: 2, panFraction: 1, engine: .coreGraphics)
        }
        coordinator.submitAcceptedRevision(inputs: [first], unit: first.unit)
        wait(for: [preparationStarted], timeout: 1)
        coordinator.requestVisual(request(first)) { _, _ in
            XCTFail("Old queued data must wait for the current history viewport")
        }
        coordinator.submitAcceptedRevision(inputs: [second], unit: second.unit)
        gate.signal()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        coordinator.requestVisual(request(second)) { _, _ in latestDelivered.fulfill() }
        wait(for: [latestDelivered], timeout: 1)
        XCTAssertEqual(coordinator.statistics.consumedRevisionCount, 2)
        XCTAssertEqual(coordinator.statistics.renderedVisualCount, 1)
    }

    func testContinuousGestureMakesProgressBeforeInputStops() {
        let input = makeGraphResponsivenessInput(revision: 1)
        let coordinator = GraphChartRenderCoordinator(preparer: { _, _ in }, renderer: { _ in
            // A controlled slow frame reproduces input outrunning rendering.
            Thread.sleep(forTimeInterval: 0.012)
            return nil
        })
        var delivered: [Int] = []
        var requested = 0
        var progressDuringInput = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.002, repeats: true) { _ in
            requested += 1
            let ordinal = requested
            coordinator.requestVisual(GraphChartVisualRequest(
                token: String(ordinal), inputs: [input], unit: input.unit,
                size: CGSize(width: 496, height: 178), scale: 2,
                zoomScale: CGFloat(ordinal), panFraction: 0.5, engine: .coreGraphics
            )) { _, _ in
                delivered.append(ordinal)
            }
            progressDuringInput = delivered.count
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        timer.invalidate()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertGreaterThan(progressDuringInput, 5, "Frames must arrive while the gesture is still changing")
        XCTAssertEqual(delivered.last, requested)
        XCTAssertEqual(delivered, delivered.sorted())
        XCTAssertEqual(coordinator.statistics.maximumConcurrentCount, 1)
        print("GRAPH_GESTURE requested=\(requested) delivered_during_input=\(progressDuringInput) delivered_total=\(delivered.count)")
    }

    func testMountedChartUsesCurrentHistoryAndViewportAfterPublication() throws {
        for hours in [1, 12] {
            try assertMountedRollingChart(hours: hours)
        }
    }

    private func assertMountedRollingChart(hours: Int) throws {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let state = GraphResponsivenessState(hours: hours)
        let feed = GraphHistoryRevisionFeed()
        let lifecycle = GraphChartMountedLifecycle()
        var frames: [GraphRenderResult] = []
        let host = NSHostingView(rootView: GraphResponsivenessHarness(
            state: state, feed: feed, lifecycle: lifecycle,
            delivered: { frames.append($0) }
        ))
        host.frame = CGRect(x: 0, y: 0, width: 496, height: 178)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }

        feed.publish([state.input.history], resetPreparedState: true)
        settle(host, until: { !frames.isEmpty })
        XCTAssertFalse(frames.isEmpty)
        for revision in 2...4 {
            let count = frames.count
            let next = state.nextInput(revision: UInt64(revision))
            // The production model publishes to the feed before its @Published history.
            feed.publish([next.history], resetPreparedState: false)
            state.input = next
            state.zoom = CGFloat(revision)
            settle(host, until: { frames.count > count })
            let frame = try XCTUnwrap(frames.last)
            XCTAssertEqual(frame.zoomScale, CGFloat(revision))
            XCTAssertEqual(frame.series.first?.points.last?.y, Double(revision * 10))
        }
        let statistics = GraphBitmapRenderer.preparedSeriesCacheStatistics()
        XCTAssertEqual(statistics.fullPreparationCount, 1, "Visual updates must not rewind the prepared cache")
        XCTAssertEqual(statistics.exactLineagePreparationCount, 3)
        print("GRAPH_MOUNTED hours=\(hours) cache=\(statistics) frames=\(frames.count)")
    }

    private func settle(_ host: NSView, until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
        XCTAssertTrue(condition(), "Mounted chart did not make progress")
    }
}

@MainActor
private final class GraphResponsivenessState: ObservableObject {
    @Published var input: GraphRenderSeriesInput
    @Published var zoom: CGFloat = 1

    init(hours: Int) {
        input = makeGraphResponsivenessInput(revision: 1, hours: hours)
    }

    func nextInput(revision: UInt64) -> GraphRenderSeriesInput {
        let timestamp = input.history.points.last!.lastChangedSeconds! + 1
        let points = Array(input.history.points.dropFirst()) + [HAHistoryPoint(
            entityId: input.entityID, state: String(revision * 10), attributes: nil,
            lastChangedSeconds: timestamp, lastUpdatedSeconds: nil
        )]
        return input.replacingHistory(HAHistorySeries(
            entityID: input.entityID, points: points, contentRevision: revision,
            cacheLineage: HAHistorySeriesCacheLineage(
                predecessorRevision: input.history.contentRevision,
                oldStart: 1, newStart: 0, count: points.count - 1
            )
        ))
    }
}

private func makeGraphResponsivenessInput(revision: UInt64, hours: Int = 1) -> GraphRenderSeriesInput {
    let entity = "sensor.responsiveness"
    return GraphRenderSeriesInput(
        cacheScope: "responsiveness", entityID: entity, name: "Responsiveness", unit: "°C",
        color: GraphColor(red: 0.2, green: 0.4, blue: 0.95, alpha: 1),
        history: HAHistorySeries(entityID: entity, points: (0..<(hours * 3600)).map { index in
            HAHistoryPoint(entityId: entity, state: String(revision * 10), attributes: nil,
                           lastChangedSeconds: 1_767_225_600 + Double(index), lastUpdatedSeconds: nil)
        }, contentRevision: revision),
        windowStart: 1_767_225_600, windowEnd: 1_767_225_600 + Double(hours * 3600 + 10)
    )
}

@MainActor
private struct GraphResponsivenessHarness: View {
    @ObservedObject var state: GraphResponsivenessState
    let feed: GraphHistoryRevisionFeed
    let lifecycle: GraphChartMountedLifecycle
    let delivered: (GraphRenderResult) -> Void

    var body: some View {
        BitmapLineChart(unit: "°C", inputs: [state.input], revisionFeed: feed,
                        mountedLifecycle: lifecycle, zoomScale: state.zoom, panFraction: 1,
                        hoverLocation: .constant(nil), onMagnify: { _, _, _ in }, onPan: { _ in },
                        onRenderReady: delivered)
            .frame(width: 496, height: 178)
    }
}
