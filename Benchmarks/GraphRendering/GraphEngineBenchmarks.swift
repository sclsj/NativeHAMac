import AppKit
import CoreGraphics
import MetalKit
import SwiftUI
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class GraphEngineBenchmarks: XCTestCase {
    private let size = CGSize(width: 496, height: 178)
    private let scale: CGFloat = 2
    private let zoomScale: CGFloat = 4
    private let warmupCount = 3

    func testPureRenderAndPresentReadyLatencyForAllEnginesAndWindows() async throws {
        guard ProcessInfo.processInfo.environment["NATIVEHA_LIVE_GRAPH_BENCHMARK"] == "1" else {
            throw XCTSkip("Set NATIVEHA_LIVE_GRAPH_BENCHMARK=1 for the read-only engine benchmark")
        }

        let iterations = max(
            Int(ProcessInfo.processInfo.environment["NATIVEHA_GRAPH_BENCH_ITERATIONS"] ?? "") ?? 20,
            5
        )
        let client = try await engineBenchmarkLiveClient()
        let entityIDs = engineBenchmarkEntityIDs()
        let engines: [GraphRenderEngine] = [.metal, .coreGraphics, .canvas]

        print(
            "GRAPH_ENGINE_CONFIG machine=\(Host.current().localizedName ?? "unknown") " +
            "build=release size=496x178 scale=2 zoom=4 warmup=\(warmupCount) " +
            "samples=\(iterations) endpoint=present-ready compositor_scanout=excluded"
        )

        for hours in [1, 24] {
            let history = try await client.fetchHistory(
                entityIDs: entityIDs,
                hoursToShow: hours
            ).sorted { $0.entityID < $1.entityID }
            let frames = try makeConsecutiveFrames(
                history: history,
                hours: hours,
                frameCount: warmupCount + iterations
            )
            let pointCount = history.reduce(0) { $0 + $1.points.count }
            let encodedBytes = try JSONEncoder().encode(history).count

            XCTAssertEqual(history.count, entityIDs.count)
            XCTAssertEqual(frames.count, warmupCount + iterations)
            print(
                "GRAPH_ENGINE_DATA hours=\(hours) series=\(history.count) " +
                "points=\(pointCount) decoded_json_bytes=\(encodedBytes) " +
                "logical_frames=\(frames.count) source=live_rest"
            )

            for engine in engines {
                let harness = try GraphEnginePresentReadyHarness(
                    engine: engine,
                    size: size,
                    scale: scale
                )
                defer { harness.close() }

                let pure = try measurePureRender(
                    engine: engine,
                    harness: harness,
                    frames: frames,
                    iterations: iterations
                )
                let total = try await measurePresentReady(
                    engine: engine,
                    harness: harness,
                    frames: frames,
                    iterations: iterations
                )

                XCTAssertEqual(pure.latencies.count, iterations)
                XCTAssertEqual(total.totalLatencies.count, iterations)
                XCTAssertEqual(total.completedFrameIDs, Array(warmupCount..<frames.count))
                XCTAssertGreaterThan(pure.accumulatedWork, 0)
                XCTAssertGreaterThan(total.accumulatedWork, 0)

                let pureSummary = TimingDistribution(pure.latencies)
                let totalSummary = TimingDistribution(total.totalLatencies)
                print(
                    "GRAPH_ENGINE_RESULT hours=\(hours) engine=\(engine.benchmarkName) " +
                    "pure_samples=\(pureSummary.count) " +
                    "pure_p50_ms=\(pureSummary.p50Milliseconds) " +
                    "pure_p95_ms=\(pureSummary.p95Milliseconds) " +
                    "pure_max_ms=\(pureSummary.maxMilliseconds) " +
                    "present_ready_samples=\(totalSummary.count) " +
                    "present_ready_p50_ms=\(totalSummary.p50Milliseconds) " +
                    "present_ready_p95_ms=\(totalSummary.p95Milliseconds) " +
                    "present_ready_max_ms=\(totalSummary.maxMilliseconds)"
                )
                print(
                    "GRAPH_ENGINE_STAGES hours=\(hours) engine=\(engine.benchmarkName) " +
                    "preparation_p50_ms=\(TimingDistribution(total.preparation).p50Milliseconds) " +
                    "downsample_geometry_p50_ms=\(TimingDistribution(total.viewport).p50Milliseconds) " +
                    "renderer_p50_ms=\(TimingDistribution(total.renderer).p50Milliseconds) " +
                    "scheduling_waiting_p50_ms=\(TimingDistribution(total.schedulingAndWaiting).p50Milliseconds)"
                )
            }
        }
    }

    private func measurePureRender(
        engine: GraphRenderEngine,
        harness: GraphEnginePresentReadyHarness,
        frames: [EngineLogicalFrame],
        iterations: Int
    ) throws -> PureRenderMeasurements {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        var latencies: [UInt64] = []
        var accumulatedWork = 0

        for (index, frame) in frames.enumerated() {
            let prepared = try XCTUnwrap(GraphBitmapRenderer.prepareViewportData(
                inputs: frame.inputs,
                unit: frame.unit,
                size: size,
                scale: scale,
                zoomScale: zoomScale,
                panFraction: frame.panFraction
            )?.result)
            let start = DispatchTime.now().uptimeNanoseconds
            let artifact = try XCTUnwrap(harness.render(prepared: prepared))
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            accumulatedWork &+= try artifact.validatedWorkCount()
            if index >= warmupCount {
                latencies.append(elapsed)
            }
        }

        XCTAssertEqual(latencies.count, iterations)
        assertConsecutivePreparationStatistics(frames: frames)
        return PureRenderMeasurements(
            latencies: latencies,
            accumulatedWork: accumulatedWork
        )
    }

    private func measurePresentReady(
        engine: GraphRenderEngine,
        harness: GraphEnginePresentReadyHarness,
        frames: [EngineLogicalFrame],
        iterations: Int
    ) async throws -> PresentReadyMeasurements {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        var measured = PresentReadyMeasurements()

        for (index, frame) in frames.enumerated() {
            let submissionStart = DispatchTime.now().uptimeNanoseconds
            let benchmarkSize = size
            let benchmarkScale = scale
            let benchmarkZoomScale = zoomScale
            let pipeline = await Task.detached(priority: .userInitiated) { () -> EnginePipelineOutput in
                let workStart = DispatchTime.now().uptimeNanoseconds
                var metrics: GraphRenderMetrics?
                let result = GraphBitmapRenderer.render(
                    inputs: frame.inputs,
                    unit: frame.unit,
                    size: benchmarkSize,
                    scale: benchmarkScale,
                    zoomScale: benchmarkZoomScale,
                    panFraction: frame.panFraction,
                    engine: engine,
                    metrics: { metrics = $0 }
                )
                return EnginePipelineOutput(
                    workStart: workStart,
                    result: result,
                    metrics: metrics
                )
            }.value

            let result = try XCTUnwrap(pipeline.result)
            let metrics = try XCTUnwrap(pipeline.metrics)
            let artifact: GraphEngineRenderArtifact
            let rendererNanoseconds: UInt64
            switch engine {
            case .coreGraphics, .metal:
                artifact = .bitmap(try XCTUnwrap(result.image))
                rendererNanoseconds = metrics.rendererNanoseconds
            case .canvas:
                let rendererStart = DispatchTime.now().uptimeNanoseconds
                artifact = try XCTUnwrap(harness.render(prepared: result))
                rendererNanoseconds = DispatchTime.now().uptimeNanoseconds - rendererStart
            }
            let completion = DispatchTime.now().uptimeNanoseconds
            let work = try artifact.validatedWorkCount()

            guard index >= warmupCount else { continue }
            let total = completion - submissionStart
            let knownStages = saturatingAdd(
                metrics.seriesPreparationNanoseconds,
                metrics.viewportPreparationNanoseconds,
                rendererNanoseconds
            )
            measured.totalLatencies.append(total)
            measured.preparation.append(metrics.seriesPreparationNanoseconds)
            measured.viewport.append(metrics.viewportPreparationNanoseconds)
            measured.renderer.append(rendererNanoseconds)
            measured.schedulingAndWaiting.append(
                total > knownStages ? total - knownStages : 0
            )
            measured.completedFrameIDs.append(frame.id)
            measured.accumulatedWork &+= work
            XCTAssertGreaterThanOrEqual(pipeline.workStart, submissionStart)
        }

        XCTAssertEqual(measured.totalLatencies.count, iterations)
        assertConsecutivePreparationStatistics(frames: frames)
        return measured
    }

    private func assertConsecutivePreparationStatistics(frames: [EngineLogicalFrame]) {
        let seriesCount = frames.first?.inputs.count ?? 0
        XCTAssertEqual(
            GraphBitmapRenderer.preparedSeriesCacheStatistics(),
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: seriesCount,
                incrementalPreparationCount: seriesCount * max(frames.count - 1, 0),
                cacheHitCount: 0
            ),
            "Every benchmark frame after the initial build must exercise consecutive incremental preparation."
        )
    }

    private func makeConsecutiveFrames(
        history: [HAHistorySeries],
        hours: Int,
        frameCount: Int
    ) throws -> [EngineLogicalFrame] {
        XCTAssertFalse(history.isEmpty)
        for series in history {
            XCTAssertGreaterThan(
                series.points.count,
                frameCount,
                "Every live series must have enough points for consecutive rolling frames."
            )
        }

        let parser = GraphDateParser()
        let end = try XCTUnwrap(history.compactMap { series in
            series.points.last.flatMap { parser.timestamp(from: $0) }
        }.max())
        let start = end - Double(hours * 3_600)
        let colors = [
            GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1),
            GraphColor(red: 0.93, green: 0.66, blue: 0.22, alpha: 1),
            GraphColor(red: 0.40, green: 0.86, blue: 0.82, alpha: 1),
            GraphColor(red: 0.95, green: 0.32, blue: 0.50, alpha: 1),
        ]

        return (0..<frameCount).map { frameIndex in
            let inputs = history.enumerated().map { seriesIndex, series -> GraphRenderSeriesInput in
                let retainedCount = series.points.count - frameCount + 1
                let framePoints = Array(
                    series.points[frameIndex..<(frameIndex + retainedCount)]
                )
                let revision = series.contentRevision &+ UInt64(frameIndex)
                let lineage: HAHistorySeriesCacheLineage?
                if frameIndex == 0 {
                    lineage = nil
                } else {
                    lineage = HAHistorySeriesCacheLineage(
                        predecessorRevision: revision &- 1,
                        oldStart: 1,
                        newStart: 0,
                        count: retainedCount - 1
                    )
                }
                return GraphRenderSeriesInput(
                    cacheScope: "engine-benchmark-\(hours)h",
                    entityID: series.entityID,
                    name: series.entityID,
                    unit: "µg/m³",
                    color: colors[seriesIndex % colors.count],
                    history: HAHistorySeries(
                        entityID: series.entityID,
                        points: framePoints,
                        contentRevision: revision,
                        cacheLineage: lineage
                    ),
                    windowStart: start,
                    windowEnd: end
                )
            }
            let denominator = max(frameCount - 1, 1)
            let pan = 0.1 + 0.8 * Double((frameIndex * 7) % frameCount) / Double(denominator)
            return EngineLogicalFrame(
                id: frameIndex,
                inputs: inputs,
                unit: "µg/m³",
                panFraction: pan
            )
        }
    }
}

private struct EngineLogicalFrame {
    let id: Int
    let inputs: [GraphRenderSeriesInput]
    let unit: String
    let panFraction: Double
}

private struct EnginePipelineOutput {
    let workStart: UInt64
    let result: GraphRenderResult?
    let metrics: GraphRenderMetrics?
}

private struct PureRenderMeasurements {
    let latencies: [UInt64]
    let accumulatedWork: Int
}

private struct PresentReadyMeasurements {
    var totalLatencies: [UInt64] = []
    var preparation: [UInt64] = []
    var viewport: [UInt64] = []
    var renderer: [UInt64] = []
    var schedulingAndWaiting: [UInt64] = []
    var completedFrameIDs: [Int] = []
    var accumulatedWork = 0
}

private enum GraphEngineRenderArtifact {
    case bitmap(CGImage)
    case canvas(NSBitmapImageRep)

    func validatedWorkCount() throws -> Int {
        switch self {
        case .bitmap(let image):
            XCTAssertGreaterThan(image.width, 0)
            XCTAssertGreaterThan(image.height, 0)
            return image.width * image.height
        case .canvas(let bitmap):
            let nontransparent = canvasNontransparentSampleCount(bitmap)
            XCTAssertGreaterThan(nontransparent, 0)
            return nontransparent
        }
    }
}

@MainActor
private final class GraphEnginePresentReadyHarness {
    private let engine: GraphRenderEngine
    private let size: CGSize
    private let scale: CGFloat
    private var canvas: GraphCanvasOffscreenRenderer?
    private var metal: GraphMetalRenderer?

    init(engine: GraphRenderEngine, size: CGSize, scale: CGFloat) throws {
        self.engine = engine
        self.size = size
        self.scale = scale
        switch engine {
        case .coreGraphics:
            break
        case .canvas:
            canvas = GraphCanvasOffscreenRenderer(size: size, scale: scale)
        case .metal:
            let device = try XCTUnwrap(
                MTLCreateSystemDefaultDevice(),
                "Metal is required for the all-engine benchmark."
            )
            let renderer = GraphMetalRenderer()
            renderer.setup(device: device)
            metal = renderer
        }
    }

    func render(prepared: GraphRenderResult) -> GraphEngineRenderArtifact? {
        switch engine {
        case .coreGraphics:
            guard let result = GraphBitmapRenderer
                .renderPreparedCoreGraphicsForBenchmark(prepared),
                  let image = result.image else {
                return nil
            }
            return .bitmap(image)
        case .canvas:
            guard let bitmap = canvas?.render(prepared) else { return nil }
            return .canvas(bitmap)
        case .metal:
            guard let image = metal?.renderToCGImage(
                rendered: prepared
            ) else {
                return nil
            }
            return .bitmap(image)
        }
    }

    func close() {
        canvas?.close()
        canvas = nil
        metal = nil
    }
}

@MainActor
private final class GraphCanvasOffscreenRenderer {
    private let size: CGSize
    private let scale: CGFloat
    private let hostingView: NSHostingView<AnyView>
    private let window: NSWindow

    init(size: CGSize, scale: CGFloat) {
        _ = NSApplication.shared
        self.size = size
        self.scale = scale
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderBack(nil)
    }

    func render(_ prepared: GraphRenderResult) -> NSBitmapImageRep? {
        hostingView.rootView = AnyView(
            GraphCanvasPlot(rendered: prepared)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
                .environment(\.displayScale, scale)
        )
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.needsDisplay = true
        hostingView.displayIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            return nil
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

private struct TimingDistribution {
    let count: Int
    let p50: UInt64
    let p95: UInt64
    let maximum: UInt64

    init(_ values: [UInt64]) {
        precondition(!values.isEmpty)
        let sorted = values.sorted()
        count = sorted.count
        p50 = sorted[sorted.count / 2]
        let p95Index = min(
            max(Int(ceil(Double(sorted.count) * 0.95)) - 1, 0),
            sorted.count - 1
        )
        p95 = sorted[p95Index]
        maximum = sorted[sorted.count - 1]
    }

    var p50Milliseconds: String { benchmarkMilliseconds(p50) }
    var p95Milliseconds: String { benchmarkMilliseconds(p95) }
    var maxMilliseconds: String { benchmarkMilliseconds(maximum) }
}

private extension GraphRenderEngine {
    var benchmarkName: String {
        switch self {
        case .metal: return "metal"
        case .coreGraphics: return "core-graphics"
        case .canvas: return "canvas"
        }
    }
}

private func saturatingAdd(_ values: UInt64...) -> UInt64 {
    values.reduce(0) { partial, value in
        let (sum, overflow) = partial.addingReportingOverflow(value)
        return overflow ? UInt64.max : sum
    }
}

private func benchmarkMilliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
}

private func canvasNontransparentSampleCount(_ bitmap: NSBitmapImageRep) -> Int {
    var count = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
            if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                count += 1
            }
        }
    }
    return count
}

private func engineBenchmarkLiveClient() async throws -> HomeAssistantRESTClient {
    let environment = ProcessInfo.processInfo.environment
    let token: String
    if let supplied = environment["HA_TOKEN"] {
        token = supplied
    } else {
        token = try String(contentsOfFile: AppConfig.tokenFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let configured = environment["HA_BASE_URL"].flatMap(URL.init(string:))
    let candidates = [configured].compactMap { $0 } + AppConfig.baseURLs
    var lastError: Error?
    var attempted: Set<URL> = []
    for baseURL in candidates where attempted.insert(baseURL).inserted {
        let client = HomeAssistantRESTClient(configuration: HomeAssistantConfiguration(
            baseURL: baseURL,
            accessToken: token,
            timeout: 60
        ))
        do {
            _ = try await client.fetchConfig()
            return client
        } catch {
            lastError = error
        }
    }
    throw lastError ?? URLError(.cannotConnectToHost)
}

private func engineBenchmarkEntityIDs() -> [String] {
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
