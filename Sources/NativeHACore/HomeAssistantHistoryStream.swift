import Foundation

public struct HACompactHistoryState: Codable, Equatable {
    public let state: String
    public let attributes: [String: JSONValue]
    public let lastChangedSeconds: Double?
    public let lastUpdatedSeconds: Double

    public init(
        state: String,
        attributes: [String: JSONValue] = [:],
        lastChangedSeconds: Double? = nil,
        lastUpdatedSeconds: Double
    ) {
        self.state = state
        self.attributes = attributes
        self.lastChangedSeconds = lastChangedSeconds
        self.lastUpdatedSeconds = lastUpdatedSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case state = "s"
        case attributes = "a"
        case lastChangedSeconds = "lc"
        case lastUpdatedSeconds = "lu"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(String.self, forKey: .state)
        attributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .attributes) ?? [:]
        lastChangedSeconds = try container.decodeIfPresent(Double.self, forKey: .lastChangedSeconds)
        lastUpdatedSeconds = try container.decode(Double.self, forKey: .lastUpdatedSeconds)
    }
}

public struct HAHistoryStreamMessage: Codable, Equatable {
    public let states: [String: [HACompactHistoryState]]
    public let startTime: Double?
    public let endTime: Double?

    public init(
        states: [String: [HACompactHistoryState]],
        startTime: Double? = nil,
        endTime: Double? = nil
    ) {
        self.states = states
        self.startTime = startTime
        self.endTime = endTime
    }

    private enum CodingKeys: String, CodingKey {
        case states
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

public struct HAHistoryStreamEntityOverlap: Equatable, Sendable {
    public let oldStart: Int
    public let newStart: Int
    public let count: Int

    public init(oldStart: Int, newStart: Int, count: Int) {
        self.oldStart = oldStart
        self.newStart = newStart
        self.count = count
    }
}

public enum HAHistoryStreamTransition: Equatable, Sendable {
    case reset
    case unchanged
    case normal([String: HAHistoryStreamEntityOverlap])
    case outOfOrderReset
}

public struct HAHistoryStreamAccumulation: Equatable {
    public let history: [String: [HACompactHistoryState]]
    public let transition: HAHistoryStreamTransition
}

public struct HAHistoryStreamPublication: Equatable {
    public let history: [String: [HACompactHistoryState]]
    public let transition: HAHistoryStreamTransition
    public let ownerGeneration: UInt64

    public init(
        history: [String: [HACompactHistoryState]],
        transition: HAHistoryStreamTransition,
        ownerGeneration: UInt64
    ) {
        self.history = history
        self.transition = transition
        self.ownerGeneration = ownerGeneration
    }
}

public struct HAHistoryStreamAccumulator {
    public private(set) var combinedHistory: [String: [HACompactHistoryState]] = [:]

    private let range: TimeInterval?
    private let now: @Sendable () -> Date

    public init(
        range: TimeInterval? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.range = range
        self.now = now
    }

    @discardableResult
    public mutating func process(
        _ message: HAHistoryStreamMessage
    ) -> [String: [HACompactHistoryState]] {
        processPublication(message).history
    }

    @discardableResult
    public mutating func processPublication(
        _ message: HAHistoryStreamMessage
    ) -> HAHistoryStreamAccumulation {
        if combinedHistory.isEmpty {
            combinedHistory = message.states
            return HAHistoryStreamAccumulation(history: combinedHistory, transition: .reset)
        }
        guard !message.states.isEmpty else {
            return HAHistoryStreamAccumulation(history: combinedHistory, transition: .unchanged)
        }

        let cutoff = range.map { now().timeIntervalSince1970 - $0 }
        var merged: [String: [HACompactHistoryState]] = [:]
        merged.reserveCapacity(combinedHistory.count + message.states.count)
        var overlaps: [String: HAHistoryStreamEntityOverlap] = [:]
        var requiresOutOfOrderReset = false

        for entityID in combinedHistory.keys {
            let result = process(
                entityID: entityID,
                incoming: message.states[entityID],
                cutoff: cutoff
            )
            merged[entityID] = result.states
            if let overlap = result.overlap {
                overlaps[entityID] = overlap
            }
            requiresOutOfOrderReset = requiresOutOfOrderReset || result.requiresOutOfOrderReset
        }
        for entityID in message.states.keys where combinedHistory[entityID] == nil {
            // Reference behavior returns before trimming a newly introduced
            // entity. It becomes eligible on the next message.
            merged[entityID] = message.states[entityID] ?? []
        }

        combinedHistory = merged
        return HAHistoryStreamAccumulation(
            history: combinedHistory,
            transition: requiresOutOfOrderReset ? .outOfOrderReset : .normal(overlaps)
        )
    }

    private struct EntityProcessResult {
        let states: [HACompactHistoryState]
        let overlap: HAHistoryStreamEntityOverlap?
        let requiresOutOfOrderReset: Bool
    }

    private func process(
        entityID: String,
        incoming: [HACompactHistoryState]?,
        cutoff: Double?
    ) -> EntityProcessResult {
        let existing = combinedHistory[entityID] ?? []
        var states = existing
        var requiresOutOfOrderReset = false

        if let incoming = incoming {
            states.append(contentsOf: incoming)
            if
                let incomingFirst = incoming.first,
                let existingLast = existing.last,
                incomingFirst.lastUpdatedSeconds < existingLast.lastUpdatedSeconds
            {
                requiresOutOfOrderReset = true
                if isTimestampSorted(existing), isTimestampSorted(incoming) {
                    states = stableMerge(existing, incoming)
                } else {
                    states = states.enumerated().sorted { left, right in
                        if left.element.lastUpdatedSeconds == right.element.lastUpdatedSeconds {
                            return left.offset < right.offset
                        }
                        return left.element.lastUpdatedSeconds < right.element.lastUpdatedSeconds
                    }.map(\.element)
                }
            }
        }

        guard let cutoff = cutoff else {
            return EntityProcessResult(
                states: states,
                overlap: normalOverlap(
                    existingCount: existing.count,
                    oldStart: 0,
                    newStart: 0,
                    requiresOutOfOrderReset: requiresOutOfOrderReset
                ),
                requiresOutOfOrderReset: requiresOutOfOrderReset
            )
        }

        var kept: [HACompactHistoryState] = []
        kept.reserveCapacity(states.count)
        var lastExpired: HACompactHistoryState?
        var firstRetainedExistingIndex: Int?
        var retainedExistingCount = 0
        for (index, state) in states.enumerated() {
            if state.lastUpdatedSeconds < cutoff {
                lastExpired = state
            } else {
                if index < existing.count {
                    retainedExistingCount += 1
                    if firstRetainedExistingIndex == nil {
                        firstRetainedExistingIndex = index
                    }
                }
                kept.append(state)
            }
        }

        // The reference preserves an already-unsorted existing array unless
        // the incoming first timestamp is older than its last timestamp. In
        // that shape, filtering can retain noncontiguous existing indices.
        // Only a contiguous retained suffix maps to one reusable slice.
        let retainedExistingSuffixStart = firstRetainedExistingIndex.flatMap { start in
            retainedExistingCount == existing.count - start ? start : nil
        }

        guard let expired = lastExpired else {
            return EntityProcessResult(
                states: states,
                overlap: normalOverlap(
                    existingCount: existing.count,
                    oldStart: 0,
                    newStart: 0,
                    requiresOutOfOrderReset: requiresOutOfOrderReset
                ),
                requiresOutOfOrderReset: requiresOutOfOrderReset
            )
        }
        if kept.first?.lastUpdatedSeconds == cutoff {
            return EntityProcessResult(
                states: kept,
                overlap: retainedExistingSuffixStart.flatMap {
                    normalOverlap(
                        existingCount: existing.count,
                        oldStart: $0,
                        newStart: 0,
                        requiresOutOfOrderReset: requiresOutOfOrderReset
                    )
                },
                requiresOutOfOrderReset: requiresOutOfOrderReset
            )
        }
        kept.insert(
            HACompactHistoryState(
                state: expired.state,
                attributes: expired.attributes,
                lastChangedSeconds: nil,
                lastUpdatedSeconds: cutoff
            ),
            at: 0
        )
        return EntityProcessResult(
            states: kept,
            overlap: retainedExistingSuffixStart.flatMap {
                normalOverlap(
                    existingCount: existing.count,
                    oldStart: $0,
                    newStart: 1,
                    requiresOutOfOrderReset: requiresOutOfOrderReset
                )
            },
            requiresOutOfOrderReset: requiresOutOfOrderReset
        )
    }

    private func normalOverlap(
        existingCount: Int,
        oldStart: Int,
        newStart: Int,
        requiresOutOfOrderReset: Bool
    ) -> HAHistoryStreamEntityOverlap? {
        let count = existingCount - oldStart
        guard !requiresOutOfOrderReset, oldStart >= 0, count > 0 else {
            return nil
        }
        return HAHistoryStreamEntityOverlap(
            oldStart: oldStart,
            newStart: newStart,
            count: count
        )
    }

    private func isTimestampSorted(_ states: [HACompactHistoryState]) -> Bool {
        guard states.count > 1 else { return true }
        for index in 1..<states.count where
            states[index].lastUpdatedSeconds < states[index - 1].lastUpdatedSeconds
        {
            return false
        }
        return true
    }

    private func stableMerge(
        _ existing: [HACompactHistoryState],
        _ incoming: [HACompactHistoryState]
    ) -> [HACompactHistoryState] {
        var output: [HACompactHistoryState] = []
        output.reserveCapacity(existing.count + incoming.count)
        var existingIndex = 0
        var incomingIndex = 0
        while existingIndex < existing.count, incomingIndex < incoming.count {
            // The reference's stable sort preserves concatenated existing
            // entries before incoming entries at equal timestamps.
            if existing[existingIndex].lastUpdatedSeconds <= incoming[incomingIndex].lastUpdatedSeconds {
                output.append(existing[existingIndex])
                existingIndex += 1
            } else {
                output.append(incoming[incomingIndex])
                incomingIndex += 1
            }
        }
        if existingIndex < existing.count {
            output.append(contentsOf: existing[existingIndex...])
        }
        if incomingIndex < incoming.count {
            output.append(contentsOf: incoming[incomingIndex...])
        }
        return output
    }
}

public enum HAHistoryAttributePolicy {
    public static let domainsNeedingAttributes: Set<String> = [
        "climate",
        "humidifier",
        "input_datetime",
        "water_heater",
        "person",
        "device_tracker",
    ]

    public static func needsAttributes(entityID: String, currentStates: [String: HAState]) -> Bool {
        currentStates[entityID] == nil || domainsNeedingAttributes.contains(domain(entityID))
    }

    public static func noAttributes(entityIDs: [String], currentStates: [String: HAState]) -> Bool {
        !entityIDs.contains { needsAttributes(entityID: $0, currentStates: currentStates) }
    }

    private static func domain(_ entityID: String) -> String {
        String(entityID.split(separator: ".", maxSplits: 1).first ?? "")
    }
}

public enum HAHistoryProjection {
    private static let domainsUsingLastUpdated: Set<String> = [
        "climate", "humidifier", "water_heater",
    ]
    private static let lineAttributes: Set<String> = [
        "temperature", "current_temperature", "target_temp_low",
        "target_temp_high", "hvac_action", "humidity", "mode", "action",
        "current_humidity",
    ]

    public static func series(
        from history: [String: [HACompactHistoryState]],
        orderedEntityIDs: [String],
        currentStates: [String: HAState] = [:]
    ) -> [HAHistorySeries] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var seen = Set<String>()
        let order = orderedEntityIDs + history.keys.sorted().filter { !orderedEntityIDs.contains($0) }
        return order.compactMap { entityID in
            guard seen.insert(entityID).inserted, let compact = history[entityID] else {
                return nil
            }
            let context = projectionContext(
                entityID: entityID,
                compact: compact,
                currentStates: currentStates
            )
            return HAHistorySeries(
                entityID: entityID,
                points: compact.map {
                    project($0, entityID: entityID, context: context, formatter: formatter)
                }
            )
        }
    }

    fileprivate static func projectionContext(
        entityID: String,
        compact: [HACompactHistoryState],
        currentStates: [String: HAState]
    ) -> HAHistoryProjectionContext {
        let firstAttributes = compact.first(where: { !$0.attributes.isEmpty })?.attributes
        return HAHistoryProjectionContext(
            fallbackAttributes: firstAttributes ?? currentStates[entityID]?.attributes,
            useLastUpdated: domainsUsingLastUpdated.contains(domain(entityID))
        )
    }

    fileprivate static func project(
        _ state: HACompactHistoryState,
        entityID: String,
        context: HAHistoryProjectionContext,
        formatter: ISO8601DateFormatter
    ) -> HAHistoryPoint {
        let timestamp = context.useLastUpdated
            ? state.lastUpdatedSeconds
            : (state.lastChangedSeconds ?? state.lastUpdatedSeconds)
        let attributes: [String: JSONValue]?
        if context.useLastUpdated {
            let source = state.attributes.isEmpty
                ? (context.fallbackAttributes ?? [:])
                : state.attributes
            let retained = source.filter { lineAttributes.contains($0.key) }
            attributes = retained.isEmpty ? nil : retained
        } else if !state.attributes.isEmpty {
            attributes = state.attributes
        } else {
            attributes = context.fallbackAttributes
        }
        return HAHistoryPoint(
            entityId: entityID,
            state: state.state,
            attributes: attributes,
            lastChanged: formatter.string(from: Date(timeIntervalSince1970: timestamp)),
            lastUpdated: formatter.string(from: Date(timeIntervalSince1970: state.lastUpdatedSeconds))
        )
    }

    private static func domain(_ entityID: String) -> String {
        String(entityID.split(separator: ".", maxSplits: 1).first ?? "")
    }

}

fileprivate struct HAHistoryProjectionContext: Equatable {
    let fallbackAttributes: [String: JSONValue]?
    let useLastUpdated: Bool
}

public struct HAHistoryProjectionStoreStatistics: Equatable {
    public let fullEntityProjectionCount: Int
    public let incrementalEntityProjectionCount: Int
    public let reusedEntityProjectionCount: Int
}

/// Reuses the immutable projected prefix/suffix of rolling history. A live
/// tail normally changes only the cutoff boundary and appends a few states;
/// rebuilding every ISO-8601 string for the entire window on each tail event
/// is unnecessary and can permanently saturate a core for long windows.
public actor HAHistoryProjectionStore {
    private struct Entry {
        let compact: [HACompactHistoryState]
        let context: HAHistoryProjectionContext
        let series: HAHistorySeries
    }

    private let orderedEntityIDs: [String]
    private let currentStates: [String: HAState]
    private let formatter: ISO8601DateFormatter
    private var entries: [String: Entry] = [:]
    private var highestOwnerGeneration: UInt64?
    private var fullEntityProjectionCount = 0
    private var incrementalEntityProjectionCount = 0
    private var reusedEntityProjectionCount = 0

    public init(
        orderedEntityIDs: [String],
        currentStates: [String: HAState] = [:]
    ) {
        self.orderedEntityIDs = orderedEntityIDs
        self.currentStates = currentStates
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func series(
        from history: [String: [HACompactHistoryState]]
    ) -> [HAHistorySeries] {
        // Raw/manual callers provide no trusted transition. Clear all lineage
        // and take the safe full-projection path.
        highestOwnerGeneration = nil
        entries.removeAll(keepingCapacity: true)
        return project(history: history, transition: .reset)
    }

    public func series(
        from publication: HAHistoryStreamPublication
    ) -> [HAHistorySeries]? {
        if let highestOwnerGeneration = highestOwnerGeneration {
            guard publication.ownerGeneration >= highestOwnerGeneration else {
                return nil
            }
            if publication.ownerGeneration > highestOwnerGeneration {
                self.highestOwnerGeneration = publication.ownerGeneration
                entries.removeAll(keepingCapacity: true)
                return project(history: publication.history, transition: .reset)
            }
        } else {
            highestOwnerGeneration = publication.ownerGeneration
            entries.removeAll(keepingCapacity: true)
            return project(history: publication.history, transition: .reset)
        }

        switch publication.transition {
        case .reset, .outOfOrderReset:
            entries.removeAll(keepingCapacity: true)
            return project(history: publication.history, transition: .reset)
        case .unchanged, .normal:
            return project(history: publication.history, transition: publication.transition)
        }
    }

    private func project(
        history: [String: [HACompactHistoryState]],
        transition: HAHistoryStreamTransition
    ) -> [HAHistorySeries] {
        var seen = Set<String>()
        let order = orderedEntityIDs + history.keys.sorted().filter { !orderedEntityIDs.contains($0) }
        var output: [HAHistorySeries] = []
        output.reserveCapacity(order.count)

        for entityID in order {
            guard seen.insert(entityID).inserted, let compact = history[entityID] else {
                continue
            }
            if case .unchanged = transition, let cached = entries[entityID] {
                reusedEntityProjectionCount += 1
                output.append(cached.series)
                continue
            }
            let context = HAHistoryProjection.projectionContext(
                entityID: entityID,
                compact: compact,
                currentStates: currentStates
            )
            let entry: Entry
            if
                case .normal(let overlaps) = transition,
                let overlap = overlaps[entityID],
                let cached = entries[entityID],
                cached.context == context,
                let incremental = incrementallyProject(
                    entityID: entityID,
                    compact: compact,
                    context: context,
                    cached: cached,
                    overlap: overlap
                )
            {
                incrementalEntityProjectionCount += 1
                entry = incremental
            } else {
                fullEntityProjectionCount += 1
                entry = fullProjection(
                    entityID: entityID,
                    compact: compact,
                    context: context
                )
            }
            entries[entityID] = entry
            output.append(entry.series)
        }

        entries = entries.filter { history[$0.key] != nil }
        return output
    }

    public func statistics() -> HAHistoryProjectionStoreStatistics {
        HAHistoryProjectionStoreStatistics(
            fullEntityProjectionCount: fullEntityProjectionCount,
            incrementalEntityProjectionCount: incrementalEntityProjectionCount,
            reusedEntityProjectionCount: reusedEntityProjectionCount
        )
    }

    /// Starts a new owner generation. Statistics remain cumulative, but no
    /// exact-overlap proof is allowed to bridge refresh/reconnect ownership.
    public func reset() {
        entries.removeAll(keepingCapacity: true)
        highestOwnerGeneration = nil
    }

    private func fullProjection(
        entityID: String,
        compact: [HACompactHistoryState],
        context: HAHistoryProjectionContext
    ) -> Entry {
        let points = compact.map {
            HAHistoryProjection.project(
                $0,
                entityID: entityID,
                context: context,
                formatter: formatter
            )
        }
        return Entry(
            compact: compact,
            context: context,
            series: HAHistorySeries(entityID: entityID, points: points)
        )
    }

    private func incrementallyProject(
        entityID: String,
        compact: [HACompactHistoryState],
        context: HAHistoryProjectionContext,
        cached: Entry,
        overlap: HAHistoryStreamEntityOverlap
    ) -> Entry? {
        guard
            cached.compact.count == cached.series.points.count,
            overlap.oldStart >= 0,
            overlap.newStart >= 0,
            overlap.count > 0,
            overlap.oldStart <= cached.compact.count,
            overlap.count <= cached.compact.count - overlap.oldStart,
            overlap.newStart <= compact.count,
            overlap.count <= compact.count - overlap.newStart,
            cached.compact[overlap.oldStart] == compact[overlap.newStart],
            cached.compact[overlap.oldStart + overlap.count - 1] ==
                compact[overlap.newStart + overlap.count - 1]
        else { return nil }

        var points: [HAHistoryPoint] = []
        points.reserveCapacity(compact.count)
        for state in compact[..<overlap.newStart] {
            points.append(HAHistoryProjection.project(
                state,
                entityID: entityID,
                context: context,
                formatter: formatter
            ))
        }
        points.append(contentsOf: cached.series.points[
            overlap.oldStart..<(overlap.oldStart + overlap.count)
        ])
        let suffixStart = overlap.newStart + overlap.count
        if suffixStart < compact.count {
            for state in compact[suffixStart...] {
                points.append(HAHistoryProjection.project(
                    state,
                    entityID: entityID,
                    context: context,
                    formatter: formatter
                ))
            }
        }
        guard points.count == compact.count else { return nil }

        return Entry(
            compact: compact,
            context: context,
            series: HAHistorySeries(
                entityID: entityID,
                points: points,
                contentRevision: cached.series.contentRevision &+ 1,
                cacheLineage: HAHistorySeriesCacheLineage(
                    predecessorRevision: cached.series.contentRevision,
                    oldStart: overlap.oldStart,
                    newStart: overlap.newStart,
                    count: overlap.count
                )
            )
        )
    }

}

public enum HAHistoryStreamOwnerStatus: Equatable {
    case loading
    case ready
    case error(String)
}

public final class HAHistoryStreamSubscription {
    private let coordinator: HAHistoryStreamCoordinator

    init(coordinator: HAHistoryStreamCoordinator) {
        self.coordinator = coordinator
    }

    public func cancel() async {
        await coordinator.cancel()
    }

    public func refresh() async throws {
        try await coordinator.refresh()
    }
}

actor HAHistoryStreamCoordinator {
    typealias Update = @Sendable (HAHistoryStreamPublication) async -> Void
    typealias Status = @Sendable (HAHistoryStreamOwnerStatus) async -> Void

    private let connection: HomeAssistantWebSocketConnection
    private let entityIDs: [String]
    private let range: TimeInterval
    private let currentStates: [String: HAState]
    private let now: @Sendable () -> Date
    private let onUpdate: Update
    private let onStatus: Status

    private var wireSubscription: HAWebSocketSubscription?
    private var statusTask: Task<Void, Never>?
    private var publicationTask: Task<Void, Never>?
    private var publicationTaskID: UUID?
    private var pendingPublication: PendingPublication?
    private var accumulator: HAHistoryStreamAccumulator?
    private var generation: UInt64 = 0
    private var awaitingReconnect = false
    private var disposed = false
    private var started = false
    private var lastConnectionState: HAWebSocketConnectionState = .ready

    private struct PendingPublication {
        let publication: HAHistoryStreamPublication
    }

    init(
        connection: HomeAssistantWebSocketConnection,
        entityIDs: [String],
        range: TimeInterval,
        currentStates: [String: HAState],
        now: @escaping @Sendable () -> Date,
        onUpdate: @escaping Update,
        onStatus: @escaping Status
    ) {
        self.connection = connection
        self.entityIDs = entityIDs
        self.range = range
        self.currentStates = currentStates
        self.now = now
        self.onUpdate = onUpdate
        self.onStatus = onStatus
    }

    func start() async throws {
        guard !started else { return }
        started = true
        await onStatus(.loading)
        do {
            try await subscribeFresh()
        } catch {
            started = false
            await onStatus(.error(error.localizedDescription))
            throw error
        }

        let connection = connection
        statusTask = Task { [weak self] in
            let stream = await connection.statusUpdates()
            for await state in stream {
                guard !Task.isCancelled else { return }
                await self?.connectionChanged(state)
            }
        }
    }

    func refresh() async throws {
        guard !disposed else { throw HomeAssistantWebSocketError.cancelled }
        generation &+= 1
        cancelPublication()
        let old = wireSubscription
        wireSubscription = nil
        accumulator = nil
        await old?.cancel()
        guard lastConnectionState == .ready else {
            awaitingReconnect = true
            return
        }
        await onStatus(.loading)
        try await subscribeFresh()
    }

    func cancel() async {
        guard !disposed else { return }
        disposed = true
        generation &+= 1
        cancelPublication()
        statusTask?.cancel()
        statusTask = nil
        let old = wireSubscription
        wireSubscription = nil
        accumulator = nil
        await old?.cancel()
    }

    private func subscribeFresh() async throws {
        guard !disposed else { throw HomeAssistantWebSocketError.cancelled }
        generation &+= 1
        let ownerGeneration = generation
        accumulator = HAHistoryStreamAccumulator(range: range, now: now)
        let command = Self.command(
            entityIDs: entityIDs,
            range: range,
            currentStates: currentStates,
            now: now()
        )
        let owner = self
        let subscription = try await connection.subscribeMessage(
            command,
            as: HAHistoryStreamMessage.self,
            resubscribe: false,
            onTermination: { error in
                await owner.terminated(error, generation: ownerGeneration)
            },
            onMessage: { message in
                await owner.received(message, generation: ownerGeneration)
            }
        )
        guard !disposed, generation == ownerGeneration else {
            await subscription.cancel()
            return
        }
        wireSubscription = subscription
        awaitingReconnect = false
    }

    private func connectionChanged(_ state: HAWebSocketConnectionState) async {
        guard !disposed else { return }
        lastConnectionState = state
        switch state {
        case .disconnected, .reconnecting:
            if !awaitingReconnect {
                generation &+= 1
                cancelPublication()
                wireSubscription = nil
                accumulator = nil
            }
            awaitingReconnect = true
        case .ready:
            guard awaitingReconnect else { return }
            awaitingReconnect = false
            await onStatus(.loading)
            do {
                try await subscribeFresh()
            } catch {
                await onStatus(.error(error.localizedDescription))
            }
        case .authenticationFailed(let message):
            awaitingReconnect = false
            await onStatus(.error("Authentication failed: \(message)"))
        case .connecting:
            break
        }
    }

    private func received(_ message: HAHistoryStreamMessage, generation ownerGeneration: UInt64) async {
        guard !disposed, generation == ownerGeneration, var accumulator = accumulator else {
            return
        }
        let accumulation = accumulator.processPublication(message)
        self.accumulator = accumulator
        let publication = HAHistoryStreamPublication(
            history: accumulation.history,
            transition: accumulation.transition,
            ownerGeneration: ownerGeneration
        )
        if let pendingPublication = pendingPublication {
            self.pendingPublication = PendingPublication(
                publication: Self.coalescing(pendingPublication.publication, with: publication)
            )
        } else {
            pendingPublication = PendingPublication(publication: publication)
        }
        startPublicationTaskIfNeeded()
    }

    private func terminated(_ error: Error, generation ownerGeneration: UInt64) async {
        guard !disposed, generation == ownerGeneration else { return }
        if let socketError = error as? HomeAssistantWebSocketError,
           socketError == .disconnected || socketError == .cancelled {
            return
        }
        cancelPublication()
        wireSubscription = nil
        await onStatus(.error(error.localizedDescription))
    }

    private func startPublicationTaskIfNeeded() {
        guard publicationTask == nil, pendingPublication != nil else { return }
        let taskID = UUID()
        publicationTaskID = taskID
        publicationTask = Task { [weak self] in
            await self?.drainPublications(taskID: taskID)
        }
    }

    private func drainPublications(taskID: UUID) async {
        while
            !Task.isCancelled,
            let publication = pendingPublication,
            !disposed,
            generation == publication.publication.ownerGeneration
        {
            pendingPublication = nil
            await onUpdate(publication.publication)
            guard
                !Task.isCancelled,
                !disposed,
                generation == publication.publication.ownerGeneration
            else { break }
            await onStatus(.ready)
        }

        guard publicationTaskID == taskID else { return }
        publicationTask = nil
        publicationTaskID = nil
        if pendingPublication != nil {
            startPublicationTaskIfNeeded()
        }
    }

    static func coalescing(
        _ pending: HAHistoryStreamPublication,
        with next: HAHistoryStreamPublication
    ) -> HAHistoryStreamPublication {
        guard pending.ownerGeneration == next.ownerGeneration else {
            return HAHistoryStreamPublication(
                history: next.history,
                transition: .reset,
                ownerGeneration: next.ownerGeneration
            )
        }
        switch (pending.transition, next.transition) {
        case (_, .unchanged):
            return pending
        case (.unchanged, _):
            return next
        case (_, .reset), (_, .outOfOrderReset):
            return next
        case (.reset, _), (.outOfOrderReset, _), (.normal, .normal):
            return HAHistoryStreamPublication(
                history: next.history,
                transition: .reset,
                ownerGeneration: next.ownerGeneration
            )
        }
    }

    private func cancelPublication() {
        pendingPublication = nil
        publicationTask?.cancel()
        publicationTask = nil
        publicationTaskID = nil
    }

    static func command(
        entityIDs: [String],
        range: TimeInterval,
        currentStates: [String: HAState],
        now: Date
    ) -> [String: JSONValue] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [
            "type": .string("history/stream"),
            "entity_ids": .array(entityIDs.map(JSONValue.string)),
            "start_time": .string(formatter.string(from: now.addingTimeInterval(-range))),
            "minimal_response": .bool(true),
            "significant_changes_only": .bool(true),
            "no_attributes": .bool(
                HAHistoryAttributePolicy.noAttributes(
                    entityIDs: entityIDs,
                    currentStates: currentStates
                )
            ),
        ]
    }
}
