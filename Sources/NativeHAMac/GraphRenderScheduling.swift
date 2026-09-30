import Combine
import CoreGraphics
import Foundation
import NativeHACore

/// Lossless handoff at the accepted history-publication boundary. SwiftUI may
/// coalesce `@Published` view invalidations, so charts subscribe here instead
/// of treating body evaluation as the revision stream.
@MainActor
final class GraphHistoryRevisionFeed {
    struct Event {
        let series: [HAHistorySeries]
        let resetPreparedState: Bool
    }

    typealias Observer = (Event) -> Void

    let generation = UUID()
    private var observers: [UUID: Observer] = [:]
    private var latestEvent: Event?

    var observerCount: Int { observers.count }

    @discardableResult
    func subscribe(_ observer: @escaping Observer) -> UUID {
        let token = UUID()
        observers[token] = observer
        if let latestEvent = latestEvent {
            observer(latestEvent)
        }
        return token
    }

    func unsubscribe(_ token: UUID?) {
        guard let token = token else { return }
        observers.removeValue(forKey: token)
    }

    func publish(_ series: [HAHistorySeries], resetPreparedState: Bool) {
        let event = Event(series: series, resetPreparedState: resetPreparedState)
        latestEvent = event
        for observer in observers.values {
            observer(event)
        }
    }
}

/// Mounted chart state whose lifetime can be ended synchronously by dashboard
/// reconciliation, before SwiftUI delivers `onDisappear` for an obsolete card.
@MainActor
final class GraphChartMountedLifecycle: ObservableObject {
    let coordinator: GraphChartRenderCoordinator
    private var subscribedFeed: GraphHistoryRevisionFeed?
    private var feedSubscription: UUID?
    private(set) var isInvalidated = false

    init(coordinator: GraphChartRenderCoordinator = GraphChartRenderCoordinator()) {
        self.coordinator = coordinator
    }

    func connect(
        feed: GraphHistoryRevisionFeed?,
        inputs: [GraphRenderSeriesInput],
        unit: String
    ) {
        guard !isInvalidated else { return }
        guard subscribedFeed?.generation != feed?.generation else { return }
        subscribedFeed?.unsubscribe(feedSubscription)
        coordinator.reset()
        subscribedFeed = feed
        feedSubscription = feed?.subscribe { [weak self] event in
            guard let self = self, !self.isInvalidated else { return }
            if event.resetPreparedState {
                self.coordinator.reset()
            }
            let byEntity = Dictionary(uniqueKeysWithValues: event.series.map { ($0.entityID, $0) })
            let acceptedInputs = inputs.compactMap { template -> GraphRenderSeriesInput? in
                guard let history = byEntity[template.entityID] else { return nil }
                return template.replacingHistory(history)
            }
            guard !acceptedInputs.isEmpty else { return }
            self.coordinator.submitAcceptedRevision(inputs: acceptedInputs, unit: unit)
        }
    }

    func disconnect() {
        subscribedFeed?.unsubscribe(feedSubscription)
        subscribedFeed = nil
        feedSubscription = nil
        coordinator.reset()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        disconnect()
    }
}

@MainActor
final class DashboardGraphChartMountRegistry {
    private struct WeakMount {
        weak var value: GraphChartMountedLifecycle?
    }

    private var mounts: [String: [UUID: WeakMount]] = [:]

    func mount(
        ownerID: String,
        lifecycle: GraphChartMountedLifecycle
    ) -> DashboardGraphChartMountLease {
        removeReleasedMounts()
        let token = UUID()
        mounts[ownerID, default: [:]][token] = WeakMount(value: lifecycle)
        return DashboardGraphChartMountLease(
            registry: self,
            lifecycle: lifecycle,
            ownerID: ownerID,
            token: token
        )
    }

    func invalidateOwners(notIn desiredOwnerIDs: Set<String>) {
        removeReleasedMounts()
        let obsolete = mounts.keys.filter { !desiredOwnerIDs.contains($0) }
        for ownerID in obsolete {
            let ownerMounts = mounts.removeValue(forKey: ownerID) ?? [:]
            for mount in ownerMounts.values {
                mount.value?.invalidate()
            }
        }
    }

    func unmount(ownerID: String, token: UUID) {
        mounts[ownerID]?.removeValue(forKey: token)
        if mounts[ownerID]?.isEmpty == true {
            mounts.removeValue(forKey: ownerID)
        }
    }

    func liveMountCount(ownerID: String? = nil) -> Int {
        removeReleasedMounts()
        if let ownerID = ownerID {
            return mounts[ownerID]?.count ?? 0
        }
        return mounts.values.reduce(0) { $0 + $1.count }
    }

    private func removeReleasedMounts() {
        for ownerID in Array(mounts.keys) {
            mounts[ownerID] = mounts[ownerID]?.filter { $0.value.value != nil }
            if mounts[ownerID]?.isEmpty == true {
                mounts.removeValue(forKey: ownerID)
            }
        }
    }
}

@MainActor
final class DashboardGraphChartMountLease {
    private weak var registry: DashboardGraphChartMountRegistry?
    private weak var lifecycle: GraphChartMountedLifecycle?
    private let ownerID: String
    private let token: UUID
    private var isCancelled = false

    init(
        registry: DashboardGraphChartMountRegistry,
        lifecycle: GraphChartMountedLifecycle,
        ownerID: String,
        token: UUID
    ) {
        self.registry = registry
        self.lifecycle = lifecycle
        self.ownerID = ownerID
        self.token = token
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        registry?.unmount(ownerID: ownerID, token: token)
        lifecycle?.disconnect()
    }
}

struct GraphChartVisualRequest {
    let token: String
    let inputs: [GraphRenderSeriesInput]
    let unit: String
    let size: CGSize
    let scale: CGFloat
    let zoomScale: CGFloat
    let panFraction: Double
    let engine: GraphRenderEngine
}

struct GraphChartCoordinatorStatistics: Equatable {
    fileprivate(set) var acceptedRevisionCount = 0
    fileprivate(set) var consumedRevisionCount = 0
    fileprivate(set) var requestedVisualCount = 0
    fileprivate(set) var renderedVisualCount = 0
    fileprivate(set) var replacedVisualCount = 0
    fileprivate(set) var staleDeliveryCount = 0
    fileprivate(set) var maximumConcurrentCount = 0
}

/// One stable same-key owner for both lossless prepared-state advancement and
/// latest-only visual rendering. Expensive work runs on its private serial
/// queue; only current-generation results return to the main actor.
final class GraphChartRenderCoordinator: ObservableObject {
    typealias Preparer = (GraphRenderSeriesInput, String) -> Void
    typealias Renderer = (GraphChartVisualRequest) -> GraphRenderResult?
    typealias Completion = (String, GraphRenderResult?) -> Void

    private struct RevisionWork {
        let generation: UInt64
        let inputs: [GraphRenderSeriesInput]
        let unit: String
    }

    private struct DataIdentity: Equatable {
        let cacheScope: String
        let entityID: String
        let contentRevision: UInt64
        let pointCount: Int

        init(_ input: GraphRenderSeriesInput) {
            cacheScope = input.cacheScope
            entityID = input.entityID
            contentRevision = input.history.contentRevision
            pointCount = input.history.points.count
        }
    }

    private struct VisualWork {
        let generation: UInt64
        let sequence: UInt64
        let request: GraphChartVisualRequest
        let completion: Completion
        #if DEBUG
        let submittedAt = DispatchTime.now().uptimeNanoseconds
        #endif
    }

    private let queue: DispatchQueue
    private let lock = NSLock()
    private let preparer: Preparer
    private let renderer: Renderer
    private let ownerID = UUID().uuidString
    private var generation: UInt64 = 0
    private var revisions: [RevisionWork] = []
    private var revisionHead = 0
    private var latestAcceptedData: [DataIdentity]?
    private var latestVisual: VisualWork?
    private var latestRequestedVisualSequence: UInt64 = 0
    private var lastDeliveredVisualSequence: UInt64 = 0
    private var inFlightVisualSequence: UInt64?
    private var workerRunning = false
    private var concurrentCount = 0
    private var statisticsStorage = GraphChartCoordinatorStatistics()

    init(
        label: String = "com.nativeha.graphChartCoordinator",
        preparer: @escaping Preparer = { input, displayUnit in
            _ = GraphBitmapRenderer.preparedSeriesForTesting(input, displayUnit: displayUnit)
        },
        renderer: @escaping Renderer = { request in
            GraphBitmapRenderer.render(
                inputs: request.inputs,
                unit: request.unit,
                size: request.size,
                scale: request.scale,
                zoomScale: request.zoomScale,
                panFraction: request.panFraction,
                engine: request.engine
            )
        }
    ) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
        self.preparer = preparer
        self.renderer = renderer
    }

    var statistics: GraphChartCoordinatorStatistics {
        lock.lock()
        defer { lock.unlock() }
        return statisticsStorage
    }

    var pendingWorkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return max(revisions.count - revisionHead, 0) + (latestVisual == nil ? 0 : 1) +
            (inFlightVisualSequence == nil ? 0 : 1)
    }

    func submitAcceptedRevision(inputs: [GraphRenderSeriesInput], unit: String) {
        precondition(Thread.isMainThread)
        lock.lock()
        let activeGeneration = generation
        let acceptedInputs = scoped(inputs, generation: activeGeneration)
        latestAcceptedData = acceptedInputs.map(DataIdentity.init)
        revisions.append(RevisionWork(
            generation: activeGeneration,
            inputs: acceptedInputs,
            unit: unit
        ))
        statisticsStorage.acceptedRevisionCount += 1
        startWorkerIfNeededLocked()
        lock.unlock()
    }

    func requestVisual(_ request: GraphChartVisualRequest, completion: @escaping Completion) {
        precondition(Thread.isMainThread)
        lock.lock()
        let activeGeneration = generation
        latestRequestedVisualSequence &+= 1
        let sequence = latestRequestedVisualSequence
        if latestVisual != nil || inFlightVisualSequence != nil {
            statisticsStorage.replacedVisualCount += 1
        }
        latestVisual = VisualWork(
            generation: activeGeneration,
            sequence: sequence,
            request: GraphChartVisualRequest(
                token: request.token,
                inputs: scoped(request.inputs, generation: activeGeneration),
                unit: request.unit,
                size: request.size,
                scale: request.scale,
                zoomScale: request.zoomScale,
                panFraction: request.panFraction,
                engine: request.engine
            ),
            completion: completion
        )
        statisticsStorage.requestedVisualCount += 1
        startWorkerIfNeededLocked()
        lock.unlock()
    }

    func reset() {
        precondition(Thread.isMainThread)
        lock.lock()
        generation &+= 1
        revisions.removeAll(keepingCapacity: true)
        revisionHead = 0
        latestAcceptedData = nil
        latestVisual = nil
        inFlightVisualSequence = nil
        lock.unlock()
    }

    private func scoped(
        _ inputs: [GraphRenderSeriesInput],
        generation: UInt64
    ) -> [GraphRenderSeriesInput] {
        inputs.map {
            $0.replacingHistory(
                $0.history,
                cacheScope: "\($0.cacheScope)\u{1F}owner:\(ownerID):\(generation)"
            )
        }
    }

    private func startWorkerIfNeededLocked() {
        guard !workerRunning else { return }
        workerRunning = true
        concurrentCount += 1
        statisticsStorage.maximumConcurrentCount = max(
            statisticsStorage.maximumConcurrentCount,
            concurrentCount
        )
        queue.async { [weak self] in self?.drain() }
    }

    private func drain() {
        while true {
            let revision: RevisionWork?
            let visual: VisualWork?
            lock.lock()
            if revisionHead < revisions.count {
                revision = revisions[revisionHead]
                revisionHead += 1
                visual = nil
            } else {
                if revisionHead > 0 {
                    revisions.removeAll(keepingCapacity: true)
                    revisionHead = 0
                }
                revision = nil
                visual = latestVisual
                latestVisual = nil
                inFlightVisualSequence = visual?.sequence
            }

            if revision == nil, visual == nil {
                workerRunning = false
                concurrentCount = max(concurrentCount - 1, 0)
                lock.unlock()
                return
            }
            lock.unlock()

            if let revision = revision {
                for input in revision.inputs {
                    preparer(input, revision.unit)
                }
                lock.lock()
                if revision.generation == generation {
                    statisticsStorage.consumedRevisionCount += 1
                }
                lock.unlock()
                continue
            }

            guard let visual = visual else { continue }
            lock.lock()
            // A visual queued before the accepted-publication boundary may
            // still contain old data. Never send it back through the cache
            // after FIFO preparation has advanced. This uses exact owner-local
            // identity, not numerical ordering of content digests or timestamps.
            let canRender = visual.generation == generation &&
                (latestAcceptedData == nil ||
                 latestAcceptedData == visual.request.inputs.map(DataIdentity.init))
            if !canRender {
                if inFlightVisualSequence == visual.sequence {
                    inFlightVisualSequence = nil
                }
                statisticsStorage.staleDeliveryCount += 1
            }
            lock.unlock()
            guard canRender else {
                AppLog("GraphFrame sequence=\(visual.sequence) skipped before rendering: history or generation advanced", severity: .debug, category: .rendering)
                continue
            }
            #if DEBUG
            let renderStartedAt = DispatchTime.now().uptimeNanoseconds
            #endif
            let result = renderer(visual.request)
            #if DEBUG
            let renderFinishedAt = DispatchTime.now().uptimeNanoseconds
            #endif
            lock.lock()
            if inFlightVisualSequence == visual.sequence {
                inFlightVisualSequence = nil
            }
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                // Input can arrive faster than a frame can be drawn. Deliver
                // completed frames in order within the current generation;
                // coalesce the pending request without starving an active gesture.
                let current = visual.generation == self.generation &&
                    visual.sequence > self.lastDeliveredVisualSequence
                if current {
                    self.lastDeliveredVisualSequence = visual.sequence
                    self.statisticsStorage.renderedVisualCount += 1
                } else {
                    self.statisticsStorage.staleDeliveryCount += 1
                }
                self.lock.unlock()
                #if DEBUG
                let responseMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - visual.submittedAt) / 1_000_000
                AppLog(
                    "GraphFrame sequence=\(visual.sequence) delivered=\(current) response_ms=\(responseMilliseconds) queue_ms=\(Double(renderStartedAt - visual.submittedAt) / 1_000_000) render_ms=\(Double(renderFinishedAt - renderStartedAt) / 1_000_000) zoom=\(visual.request.zoomScale) pan=\(visual.request.panFraction)",
                    severity: .debug, category: .rendering
                )
                #endif
                if current {
                    visual.completion(visual.request.token, result)
                }
            }
        }
    }
}

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
