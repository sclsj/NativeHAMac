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
        if combinedHistory.isEmpty {
            combinedHistory = message.states
            return combinedHistory
        }
        guard !message.states.isEmpty else {
            return combinedHistory
        }

        let cutoff = range.map { now().timeIntervalSince1970 - $0 }
        var merged: [String: [HACompactHistoryState]] = [:]
        merged.reserveCapacity(combinedHistory.count + message.states.count)

        for entityID in combinedHistory.keys {
            process(
                entityID: entityID,
                incoming: message.states[entityID],
                cutoff: cutoff,
                into: &merged
            )
        }
        for entityID in message.states.keys where combinedHistory[entityID] == nil {
            // Reference behavior returns before trimming a newly introduced
            // entity. It becomes eligible on the next message.
            merged[entityID] = message.states[entityID] ?? []
        }

        combinedHistory = merged
        return combinedHistory
    }

    private func process(
        entityID: String,
        incoming: [HACompactHistoryState]?,
        cutoff: Double?,
        into merged: inout [String: [HACompactHistoryState]]
    ) {
        let existing = combinedHistory[entityID] ?? []
        var states = existing

        if let incoming = incoming {
            states.append(contentsOf: incoming)
            if
                let incomingFirst = incoming.first,
                let existingLast = existing.last,
                incomingFirst.lastUpdatedSeconds < existingLast.lastUpdatedSeconds
            {
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
            merged[entityID] = states
            return
        }

        var kept: [HACompactHistoryState] = []
        kept.reserveCapacity(states.count)
        var lastExpired: HACompactHistoryState?
        for state in states {
            if state.lastUpdatedSeconds < cutoff {
                lastExpired = state
            } else {
                kept.append(state)
            }
        }

        guard let expired = lastExpired else {
            merged[entityID] = states
            return
        }
        if kept.first?.lastUpdatedSeconds == cutoff {
            merged[entityID] = kept
            return
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
        merged[entityID] = kept
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
            let firstAttributes = compact.first(where: { !$0.attributes.isEmpty })?.attributes
            let fallbackAttributes = firstAttributes ?? currentStates[entityID]?.attributes
            let useLastUpdated = domainsUsingLastUpdated.contains(domain(entityID))
            let points = compact.map { state -> HAHistoryPoint in
                let timestamp = useLastUpdated
                    ? state.lastUpdatedSeconds
                    : (state.lastChangedSeconds ?? state.lastUpdatedSeconds)
                let attributes: [String: JSONValue]?
                if useLastUpdated {
                    let source = state.attributes.isEmpty ? (fallbackAttributes ?? [:]) : state.attributes
                    let retained = source.filter { lineAttributes.contains($0.key) }
                    attributes = retained.isEmpty ? nil : retained
                } else if !state.attributes.isEmpty {
                    attributes = state.attributes
                } else {
                    attributes = fallbackAttributes
                }
                return HAHistoryPoint(
                    entityId: entityID,
                    state: state.state,
                    attributes: attributes,
                    lastChanged: formatter.string(from: Date(timeIntervalSince1970: timestamp)),
                    lastUpdated: formatter.string(from: Date(timeIntervalSince1970: state.lastUpdatedSeconds))
                )
            }
            return HAHistorySeries(entityID: entityID, points: points)
        }
    }

    private static func domain(_ entityID: String) -> String {
        String(entityID.split(separator: ".", maxSplits: 1).first ?? "")
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
    typealias Update = @Sendable ([String: [HACompactHistoryState]]) async -> Void
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
        let generation: UInt64
        let history: [String: [HACompactHistoryState]]
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
        let history = accumulator.process(message)
        self.accumulator = accumulator
        pendingPublication = PendingPublication(
            generation: ownerGeneration,
            history: history
        )
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
            generation == publication.generation
        {
            pendingPublication = nil
            await onUpdate(publication.history)
            guard
                !Task.isCancelled,
                !disposed,
                generation == publication.generation
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
