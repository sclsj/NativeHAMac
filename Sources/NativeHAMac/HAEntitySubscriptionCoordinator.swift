import Foundation
import NativeHACore

enum HAEntitySubscriptionError: Error, Equatable {
    case stopped
    case terminated(String)
    case malformedPayload(String)
}

extension HAEntitySubscriptionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .stopped: return "Entity subscription stopped"
        case let .terminated(message): return "Entity subscription terminated: \(message)"
        case let .malformedPayload(message): return "Malformed entity subscription payload: \(message)"
        }
    }
}

struct HAEntitySubscriptionDebugSnapshot: Equatable {
    let generation: UInt64
    let acceptedLiveGeneration: UInt64?
    let hasSubscription: Bool
    let hasStatusTask: Bool
    let hasSubscriptionStartTask: Bool
    let acceptedFirstSnapshot: Bool
    let entityCount: Int
}

struct HAEntitySubscriptionInstallationProof: Equatable {
    let generation: UInt64
    let snapshot: [String: HAState]
}

struct HAEntitySubscriptionDetachedOwnership {
    let subscription: HAWebSocketSubscription?
    let statusTask: Task<Void, Never>?
    let subscriptionStartTask: Task<Void, Never>?

    func finish() async {
        statusTask?.cancel()
        subscriptionStartTask?.cancel()
        await subscription?.cancel()
        await statusTask?.value
        await subscriptionStartTask?.value
    }
}

/// App-lifetime owner for the modern entity stream. Transport resubscription is
/// disabled; every ready generation creates one wire owner whose first payload
/// atomically replaces the retained dictionary.
@MainActor
final class HAEntitySubscriptionCoordinator {
    typealias SnapshotHandler = @MainActor ([String: HAState]) -> Void
    typealias PhaseHandler = @MainActor (DashboardComponentPhase) -> Void

    private var client: HomeAssistantWebSocketClient?
    private var subscription: HAWebSocketSubscription?
    private var statusTask: Task<Void, Never>?
    private var subscriptionStartTask: Task<Void, Never>?
    private var subscriptionStartGeneration: UInt64?
    private var store = HAEntityStore()
    private var generation: UInt64 = 0
    private var acceptedFirstSnapshot = false
    private var acceptedLiveGeneration: UInt64?
    private var stopped = true
    private var firstSnapshotWaiter: (
        generation: UInt64,
        continuation: CheckedContinuation<[String: HAState], Error>
    )?
    #if DEBUG
    private var loggedUnknownEntityIDs = Set<String>()
    #endif
    private let onSnapshot: SnapshotHandler
    private let onPhase: PhaseHandler
    private let lifetimeAuthority: DashboardLifetimeAuthority
    private let taskObserver: ([Task<Void, Never>]) -> Void

    init(
        initialStates: [String: HAState] = [:],
        lifetimeAuthority: DashboardLifetimeAuthority = DashboardLifetimeAuthority(),
        taskObserver: @escaping ([Task<Void, Never>]) -> Void = { _ in },
        onSnapshot: @escaping SnapshotHandler,
        onPhase: @escaping PhaseHandler
    ) {
        // Retained values remain visible until the next owner's authoritative
        // first payload replaces them.
        self.store = HAEntityStore(snapshot: initialStates)
        self.lifetimeAuthority = lifetimeAuthority
        self.taskObserver = taskObserver
        self.onSnapshot = onSnapshot
        self.onPhase = onPhase
    }

    func start(using client: HomeAssistantWebSocketClient) async throws -> [String: HAState] {
        guard lifetimeAuthority.acceptsWork else { throw HAEntitySubscriptionError.stopped }
        let detached = detachSynchronously(markStopped: false)
        await cancel(detached)
        self.client = client
        onPhase(.loading)
        let snapshot = try await subscribeFresh()
        startStatusObservation(client: client)
        return snapshot
    }

    private func subscribeFresh() async throws -> [String: HAState] {
        guard lifetimeAuthority.acceptsWork,
              !stopped,
              let client = client
        else { throw HAEntitySubscriptionError.stopped }
        generation &+= 1
        let ownerGeneration = generation
        acceptedFirstSnapshot = false
        acceptedLiveGeneration = nil
        let oldSubscription = subscription
        subscription = nil
        firstSnapshotWaiter?.continuation.resume(throwing: HAEntitySubscriptionError.stopped)
        firstSnapshotWaiter = nil
        await oldSubscription?.cancel()
        guard lifetimeAuthority.acceptsWork,
              generation == ownerGeneration,
              !stopped,
              self.client === client
        else {
            throw HAEntitySubscriptionError.stopped
        }

        return try await withCheckedThrowingContinuation { continuation in
            firstSnapshotWaiter = (ownerGeneration, continuation)
            let weakCoordinator = WeakEntitySubscriptionCoordinatorBox(self)
            let authority = lifetimeAuthority
            let task = Task { @MainActor in
                guard authority.acceptsWork, !Task.isCancelled else {
                    weakCoordinator.value?.cancelSubscriptionStart(
                        generation: ownerGeneration,
                        client: client
                    )
                    weakCoordinator.value?.finishSubscriptionStart(generation: ownerGeneration)
                    return
                }
                do {
                    let candidate = try await client.subscribeEntities(
                        onTermination: { error in
                            await weakCoordinator.value?.terminated(
                                error,
                                generation: ownerGeneration,
                                client: client
                            )
                        },
                        { payload in
                            await weakCoordinator.value?.receive(
                                payload,
                                generation: ownerGeneration,
                                client: client
                            )
                        }
                    )
                    guard authority.acceptsWork,
                          !Task.isCancelled,
                          let coordinator = weakCoordinator.value,
                          coordinator.generation == ownerGeneration,
                          !coordinator.stopped,
                          coordinator.client === client
                    else {
                        await candidate.cancel()
                        weakCoordinator.value?.finishSubscriptionStart(generation: ownerGeneration)
                        return
                    }
                    coordinator.subscription = candidate
                } catch {
                    if authority.acceptsWork, !Task.isCancelled {
                        weakCoordinator.value?.failSubscriptionStart(
                            error,
                            generation: ownerGeneration,
                            client: client
                        )
                    } else {
                        weakCoordinator.value?.cancelSubscriptionStart(
                            generation: ownerGeneration,
                            client: client
                        )
                    }
                }
                weakCoordinator.value?.finishSubscriptionStart(generation: ownerGeneration)
            }
            subscriptionStartGeneration = ownerGeneration
            subscriptionStartTask = task
            notifyTaskObserver()
        }
    }

    private func finishSubscriptionStart(generation ownerGeneration: UInt64) {
        guard subscriptionStartGeneration == ownerGeneration else { return }
        subscriptionStartGeneration = nil
        subscriptionStartTask = nil
        notifyTaskObserver()
    }

    private func cancelSubscriptionStart(
        generation ownerGeneration: UInt64,
        client: HomeAssistantWebSocketClient
    ) {
        guard generation == ownerGeneration, self.client === client else { return }
        subscription = nil
        if firstSnapshotWaiter?.generation == ownerGeneration {
            let waiter = firstSnapshotWaiter?.continuation
            firstSnapshotWaiter = nil
            waiter?.resume(throwing: HAEntitySubscriptionError.stopped)
        }
    }

    private func receive(
        _ payload: HAEntitySubscriptionPayload,
        generation ownerGeneration: UInt64,
        client: HomeAssistantWebSocketClient
    ) async {
        guard lifetimeAuthority.acceptsWork,
              generation == ownerGeneration,
              !stopped,
              self.client === client
        else { return }
        let authoritative = !acceptedFirstSnapshot
        guard !authoritative || payload.additions != nil else {
            await failCurrentOwner(
                HAEntitySubscriptionError.malformedPayload(
                    "the first owner event must explicitly contain additions"
                ),
                generation: ownerGeneration,
                client: client
            )
            return
        }
        let base = store
        let prepared: (HAEntityStore, HAEntityStoreApplication) = await Task.detached(
            priority: .userInitiated
        ) { () -> (HAEntityStore, HAEntityStoreApplication) in
            var next = base
            let application = next.apply(payload, authoritative: authoritative)
            return (next, application)
        }.value
        guard lifetimeAuthority.acceptsWork,
              generation == ownerGeneration,
              !stopped,
              self.client === client
        else { return }

        store = prepared.0
        acceptedFirstSnapshot = true
        acceptedLiveGeneration = ownerGeneration
        #if DEBUG
        for entityID in prepared.1.unknownChangedEntityIDs
            where loggedUnknownEntityIDs.insert(entityID).inserted
        {
            AppLog(
                "Entity stream ignored a change for unknown entity \(entityID)",
                severity: .warning,
                category: .webSocket
            )
        }
        #endif
        // This one MainActor callback is the only observable publication for a
        // payload; the complete prepared dictionary is already immutable here.
        onSnapshot(prepared.1.snapshot)
        onPhase(.ready)
        if firstSnapshotWaiter?.generation == ownerGeneration {
            let waiter = firstSnapshotWaiter?.continuation
            firstSnapshotWaiter = nil
            waiter?.resume(returning: prepared.1.snapshot)
        }
    }

    private func failSubscriptionStart(
        _ error: Error,
        generation ownerGeneration: UInt64,
        client: HomeAssistantWebSocketClient
    ) {
        guard lifetimeAuthority.acceptsWork,
              generation == ownerGeneration,
              !stopped,
              self.client === client
        else { return }
        subscription = nil
        let message = error.localizedDescription
        onPhase(.failed(message))
        if firstSnapshotWaiter?.generation == ownerGeneration {
            let waiter = firstSnapshotWaiter?.continuation
            firstSnapshotWaiter = nil
            waiter?.resume(throwing: error)
        }
    }

    private func terminated(
        _ error: Error,
        generation ownerGeneration: UInt64,
        client: HomeAssistantWebSocketClient
    ) async {
        guard lifetimeAuthority.acceptsWork,
              generation == ownerGeneration,
              !stopped,
              self.client === client
        else { return }
        let phase: DashboardComponentPhase
        if let websocketError = error as? HomeAssistantWebSocketError,
           websocketError == .invalidMessage {
            phase = .failed("Malformed entity subscription payload")
        } else {
            phase = .disconnected
        }
        await failCurrentOwner(
            error,
            generation: ownerGeneration,
            client: client,
            phase: phase
        )
    }

    private func failCurrentOwner(
        _ error: Error,
        generation ownerGeneration: UInt64,
        client: HomeAssistantWebSocketClient,
        phase: DashboardComponentPhase? = nil
    ) async {
        guard lifetimeAuthority.acceptsWork,
              generation == ownerGeneration,
              !stopped,
              self.client === client
        else { return }
        generation &+= 1
        acceptedFirstSnapshot = false
        acceptedLiveGeneration = nil
        let detached = subscription
        subscription = nil
        if firstSnapshotWaiter?.generation == ownerGeneration {
            let waiter = firstSnapshotWaiter?.continuation
            firstSnapshotWaiter = nil
            waiter?.resume(throwing: error)
        }
        onPhase(phase ?? .failed(error.localizedDescription))
        await detached?.cancel()
    }

    private func startStatusObservation(client: HomeAssistantWebSocketClient) {
        guard lifetimeAuthority.acceptsWork else { return }
        statusTask?.cancel()
        let weakCoordinator = WeakEntitySubscriptionCoordinatorBox(self)
        let authority = lifetimeAuthority
        statusTask = Task {
            var isInitialStatus = true
            for await state in await client.connection.statusUpdates() {
                guard authority.acceptsWork, !Task.isCancelled else { return }
                // `statusUpdates()` first replays the connection's current
                // state. This owner was just installed on that same ready
                // connection, so the initial ready value is a baseline rather
                // than a reconnect transition. Ignoring only that replay keeps
                // a malformed-owner failure terminal until a real non-ready /
                // ready transition occurs. If the connection already became
                // non-ready before observation began, process it normally.
                if isInitialStatus {
                    isInitialStatus = false
                    if state == .ready { continue }
                }
                await weakCoordinator.value?.connectionChanged(state, client: client)
            }
        }
        notifyTaskObserver()
    }

    private func connectionChanged(
        _ state: HAWebSocketConnectionState,
        client: HomeAssistantWebSocketClient
    ) async {
        guard lifetimeAuthority.acceptsWork,
              !stopped,
              self.client === client
        else { return }
        switch state {
        case .ready:
            guard subscription == nil else { return }
            onPhase(.reconnecting)
            do {
                _ = try await subscribeFresh()
            } catch is CancellationError {
                return
            } catch {
                guard lifetimeAuthority.acceptsWork,
                      !stopped,
                      self.client === client
                else { return }
                onPhase(.failed(error.localizedDescription))
            }
        case .connecting, .reconnecting:
            await invalidateForConnectionLoss(phase: .reconnecting)
        case .disconnected:
            await invalidateForConnectionLoss(phase: .disconnected)
        case let .authenticationFailed(message):
            await invalidateForConnectionLoss(phase: .failed(message))
        }
    }

    private func invalidateForConnectionLoss(phase: DashboardComponentPhase) async {
        generation &+= 1
        acceptedFirstSnapshot = false
        acceptedLiveGeneration = nil
        let old = subscription
        subscription = nil
        if let waiter = firstSnapshotWaiter?.continuation {
            firstSnapshotWaiter = nil
            waiter.resume(throwing: HAEntitySubscriptionError.terminated("connection changed"))
        }
        onPhase(phase)
        await old?.cancel()
    }

    func stop() async {
        let detached = detachOwnershipSynchronously()
        await detached.finish()
        onPhase(.stopped)
    }

    /// Revokes every callback and wire-owner generation before returning. The
    /// detached handles can then be awaited by an explicit stop or by a
    /// deinitialization cleanup task without retaining the coordinator's
    /// former DashboardViewModel owner.
    func detachOwnershipSynchronously() -> HAEntitySubscriptionDetachedOwnership {
        let detached = detachSynchronously(markStopped: true)
        return HAEntitySubscriptionDetachedOwnership(
            subscription: detached.0,
            statusTask: detached.1,
            subscriptionStartTask: detached.2
        )
    }

    private func detachSynchronously(
        markStopped: Bool
    ) -> (HAWebSocketSubscription?, Task<Void, Never>?, Task<Void, Never>?) {
        generation &+= 1
        stopped = markStopped
        acceptedFirstSnapshot = false
        acceptedLiveGeneration = nil
        let detached = (subscription, statusTask, subscriptionStartTask)
        subscription = nil
        statusTask = nil
        subscriptionStartTask = nil
        subscriptionStartGeneration = nil
        client = nil
        detached.1?.cancel()
        detached.2?.cancel()
        notifyTaskObserver()
        if let waiter = firstSnapshotWaiter?.continuation {
            firstSnapshotWaiter = nil
            waiter.resume(throwing: HAEntitySubscriptionError.stopped)
        }
        return detached
    }

    private func cancel(
        _ detached: (HAWebSocketSubscription?, Task<Void, Never>?, Task<Void, Never>?)
    ) async {
        detached.1?.cancel()
        detached.2?.cancel()
        await detached.0?.cancel()
        await detached.1?.value
        await detached.2?.value
    }

    func debugSnapshot() -> HAEntitySubscriptionDebugSnapshot {
        HAEntitySubscriptionDebugSnapshot(
            generation: generation,
            acceptedLiveGeneration: acceptedLiveGeneration,
            hasSubscription: subscription != nil,
            hasStatusTask: statusTask != nil,
            hasSubscriptionStartTask: subscriptionStartTask != nil,
            acceptedFirstSnapshot: acceptedFirstSnapshot,
            entityCount: store.snapshot.count
        )
    }

    /// Produces the only snapshot that may cross the bootstrap installation
    /// boundary. Because the coordinator and DashboardViewModel are both
    /// MainActor-isolated, a successful proof and the caller's synchronous
    /// ownership assignment cannot be interleaved with a termination callback.
    func proveLiveGenerationForInstallation() throws -> HAEntitySubscriptionInstallationProof {
        guard lifetimeAuthority.acceptsWork,
              !stopped,
              client != nil,
              subscription != nil,
              firstSnapshotWaiter == nil,
              acceptedFirstSnapshot,
              acceptedLiveGeneration == generation
        else {
            throw HAEntitySubscriptionError.terminated(
                "candidate generation is no longer an accepted live subscription"
            )
        }
        return HAEntitySubscriptionInstallationProof(
            generation: generation,
            snapshot: store.snapshot
        )
    }

    private func notifyTaskObserver() {
        taskObserver([statusTask, subscriptionStartTask].compactMap { $0 })
    }
}

private final class WeakEntitySubscriptionCoordinatorBox: @unchecked Sendable {
    weak var value: HAEntitySubscriptionCoordinator?
    init(_ value: HAEntitySubscriptionCoordinator) { self.value = value }
}
