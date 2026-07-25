import Combine
import CoreGraphics
import Foundation

struct GraphSynchronousRenderKey: Equatable {
    let dataToken: String
    let unit: String
    let size: CGSize
    let scale: CGFloat
    let zoomScale: CGFloat
    let panFraction: Double
    let engine: GraphRenderEngine
}

struct GraphSynchronousRenderRequest {
    let key: GraphSynchronousRenderKey
    let inputs: [GraphRenderSeriesInput]
    let unit: String
    let size: CGSize
    let zoomScale: CGFloat
    let panFraction: Double
}

/// Keeps synchronous viewport rendering exact while avoiding repeated work
/// when SwiftUI reevaluates a chart for hover or unrelated parent state.
final class GraphSynchronousRenderCache: ObservableObject {
    typealias Renderer = (GraphSynchronousRenderRequest) -> GraphRenderResult?

    private let renderer: Renderer
    private var cachedKey: GraphSynchronousRenderKey?
    private var cachedResult: GraphRenderResult?

    init(renderer: @escaping Renderer = GraphSynchronousRenderCache.productionRender) {
        self.renderer = renderer
    }

    func render(_ request: GraphSynchronousRenderRequest) -> GraphRenderResult? {
        precondition(Thread.isMainThread)
        if cachedKey == request.key {
            return cachedResult
        }

        let result = renderer(request)
        cachedKey = request.key
        cachedResult = result
        return result
    }

    private static func productionRender(
        _ request: GraphSynchronousRenderRequest
    ) -> GraphRenderResult? {
        GraphBitmapRenderer.render(
            inputs: request.inputs,
            unit: request.unit,
            size: request.size,
            scale: request.key.scale,
            zoomScale: request.zoomScale,
            panFraction: request.panFraction,
            engine: request.key.engine
        )
    }
}

/// Advances prepared-series lineage for every accepted data revision,
/// independently of whether that revision's visual frame is later rendered.
/// One scheduler is owned by one chart so submissions for that chart remain
/// FIFO without changing the shared cache's broader concurrency semantics.
final class GraphDataRevisionPreparationScheduler: ObservableObject {
    typealias Preparer = (GraphRenderSeriesInput, String) -> Void

    private let queue: DispatchQueue
    private let preparer: Preparer

    init(
        label: String = "com.nativeha.graphDataRevisionPreparation",
        preparer: @escaping Preparer = { input, displayUnit in
            _ = GraphBitmapRenderer.preparedSeriesForTesting(
                input,
                displayUnit: displayUnit
            )
        }
    ) {
        queue = DispatchQueue(label: label, qos: .utility)
        self.preparer = preparer
    }

    func submit(
        inputs: [GraphRenderSeriesInput],
        displayUnit: String,
        completion: (() -> Void)? = nil
    ) {
        let preparer = preparer
        queue.async {
            for input in inputs {
                preparer(input, displayUnit)
            }
            completion?()
        }
    }
}

struct GraphViewportRenderRequest {
    let token: String
    let dataToken: String
    let inputs: [GraphRenderSeriesInput]
    let unit: String
    let size: CGSize
    let scale: CGFloat
    let zoomScale: CGFloat
    let panFraction: Double
}

struct GraphViewportRenderDelivery {
    let request: GraphViewportRenderRequest
    let result: GraphRenderResult?
    let wasSuperseded: Bool
}

struct GraphViewportRenderSchedulerStatistics: Equatable {
    fileprivate(set) var scheduledCount = 0
    fileprivate(set) var startedCount = 0
    fileprivate(set) var completedCount = 0
    fileprivate(set) var replacedPendingCount = 0
    fileprivate(set) var maximumConcurrentCount = 0
}

/// Serializes viewport renders and retains only the newest request that arrives
/// while CoreGraphics is busy. A completed render is still delivered so the UI
/// can make progress during a continuous gesture; the owner decides whether its
/// data generation is still safe to install.
final class GraphViewportRenderScheduler: ObservableObject {
    typealias Renderer = (GraphViewportRenderRequest) -> GraphRenderResult?
    typealias Completion = (GraphViewportRenderDelivery) -> Void

    private struct Work {
        let request: GraphViewportRenderRequest
        let completion: Completion
    }

    private let renderer: Renderer
    private var pending: Work?
    private var inFlightTask: Task<Void, Never>?
    private var inFlightToken: String?
    private var generation: UInt64 = 0
    private var concurrentCount = 0
    private(set) var statistics = GraphViewportRenderSchedulerStatistics()

    init(renderer: @escaping Renderer = GraphViewportRenderScheduler.productionRender) {
        self.renderer = renderer
    }

    func schedule(
        _ request: GraphViewportRenderRequest,
        completion: @escaping Completion
    ) {
        precondition(Thread.isMainThread)
        statistics.scheduledCount += 1

        let work = Work(request: request, completion: completion)
        guard inFlightTask != nil else {
            start(work)
            return
        }

        if pending != nil {
            statistics.replacedPendingCount += 1
        }
        pending = work
    }

    func cancel() {
        precondition(Thread.isMainThread)
        generation &+= 1
        pending = nil
        inFlightTask?.cancel()
    }

    private func start(_ work: Work) {
        let activeGeneration = generation
        let renderer = renderer
        inFlightToken = work.request.token
        concurrentCount += 1
        statistics.startedCount += 1
        statistics.maximumConcurrentCount = max(
            statistics.maximumConcurrentCount,
            concurrentCount
        )

        inFlightTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else {
                RunLoop.main.perform(inModes: [.common]) { [weak self] in
                    self?.finish(
                        work: work,
                        result: nil,
                        generation: activeGeneration,
                        rendered: false
                    )
                }
                return
            }

            let result = renderer(work.request)
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                self?.finish(
                    work: work,
                    result: result,
                    generation: activeGeneration,
                    rendered: true
                )
            }
        }
    }

    private func finish(
        work: Work,
        result: GraphRenderResult?,
        generation activeGeneration: UInt64,
        rendered: Bool
    ) {
        precondition(Thread.isMainThread)
        guard inFlightToken == work.request.token else {
            return
        }

        inFlightTask = nil
        inFlightToken = nil
        concurrentCount = max(concurrentCount - 1, 0)

        if rendered, activeGeneration == generation {
            statistics.completedCount += 1
            work.completion(GraphViewportRenderDelivery(
                request: work.request,
                result: result,
                wasSuperseded: pending != nil
            ))
        }

        if let latest = pending {
            pending = nil
            start(latest)
        }
    }

    private static func productionRender(
        _ request: GraphViewportRenderRequest
    ) -> GraphRenderResult? {
        GraphBitmapRenderer.render(
            inputs: request.inputs,
            unit: request.unit,
            size: request.size,
            scale: request.scale,
            zoomScale: request.zoomScale,
            panFraction: request.panFraction
        )
    }
}
