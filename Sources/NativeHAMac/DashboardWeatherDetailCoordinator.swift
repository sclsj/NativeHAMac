import Foundation
import NativeHACore

enum WeatherDetailForecastPhase: Equatable {
    case omitted
    case loading
    case subscribed
    case reconnecting
    case terminalFailure
}

struct WeatherDetailOwnerCandidate: Equatable {
    let entityID: String
    let type: HAWeatherForecastType
    let presentationGeneration: UUID
    let appGeneration: UInt64
    let configGeneration: UInt64
}

struct WeatherDetailDetachedOwnership {
    let startup: Task<Void, Never>?
    let subscription: HAWebSocketSubscription?

    static let empty = WeatherDetailDetachedOwnership(startup: nil, subscription: nil)

    func finish() async {
        await startup?.value
        await subscription?.cancel()
    }
}

struct WeatherDetailTransition {
    let detached: WeatherDetailDetachedOwnership
    let candidate: WeatherDetailOwnerCandidate?
}

@MainActor
final class DashboardWeatherDetailCoordinator: ObservableObject {
    @Published private(set) var selectedType: HAWeatherForecastType?
    @Published private(set) var supportedTypes: [HAWeatherForecastType] = []
    @Published private(set) var modernEvent: HAWeatherForecastEvent?
    @Published private(set) var phase: WeatherDetailForecastPhase = .omitted

    private(set) var selectedEntityID: String?
    private let lifetimeAuthority: DashboardLifetimeAuthority
    private let subscriptionInstallHook: @Sendable () async -> Void
    private var presentationGeneration = UUID()
    private var attemptGeneration = UUID()
    private var desiredCandidate: WeatherDetailOwnerCandidate?
    private var startup: Task<Void, Never>?
    private var subscription: HAWebSocketSubscription?
    private var currentAttemptFailed = false
    private var preAcknowledgementReconnectPending = false
    private var terminationOwnershipHandler: ((WeatherDetailDetachedOwnership) -> Void)?

    init(
        lifetimeAuthority: DashboardLifetimeAuthority,
        subscriptionInstallHook: @escaping @Sendable () async -> Void = {}
    ) {
        self.lifetimeAuthority = lifetimeAuthority
        self.subscriptionInstallHook = subscriptionInstallHook
    }

    var hasStartup: Bool { startup != nil }
    var hasSubscription: Bool { subscription != nil }
    var ownerCount: Int { (startup == nil ? 0 : 1) + (subscription == nil ? 0 : 1) }

    func setTerminationOwnershipHandler(
        _ handler: @escaping (WeatherDetailDetachedOwnership) -> Void
    ) {
        terminationOwnershipHandler = handler
    }

    func open(
        entityID: String,
        state: HAState,
        appGeneration: UInt64,
        configGeneration: UInt64
    ) -> WeatherDetailTransition {
        let detached = invalidateAndDetach()
        presentationGeneration = UUID()
        selectedEntityID = entityID
        supportedTypes = HAWeatherForecastFeatures.supportedTypes(in: state.attributes)
        selectedType = supportedTypes.first
        modernEvent = nil
        phase = selectedType == nil ? .omitted : .loading
        desiredCandidate = selectedType.map {
            WeatherDetailOwnerCandidate(
                entityID: entityID,
                type: $0,
                presentationGeneration: presentationGeneration,
                appGeneration: appGeneration,
                configGeneration: configGeneration
            )
        }
        return WeatherDetailTransition(detached: detached, candidate: desiredCandidate)
    }

    func updateState(
        _ state: HAState,
        appGeneration: UInt64,
        configGeneration: UInt64
    ) -> WeatherDetailTransition? {
        guard selectedEntityID == state.entityId else { return nil }
        supportedTypes = HAWeatherForecastFeatures.supportedTypes(in: state.attributes)
        // The pinned frontend keeps an established selected owner even when an
        // ordinary state update removes that feature bit.
        guard selectedType == nil,
              startup == nil,
              subscription == nil,
              let defaultType = supportedTypes.first
        else { return nil }
        selectedType = defaultType
        phase = .loading
        let candidate = WeatherDetailOwnerCandidate(
            entityID: state.entityId,
            type: defaultType,
            presentationGeneration: presentationGeneration,
            appGeneration: appGeneration,
            configGeneration: configGeneration
        )
        desiredCandidate = candidate
        return WeatherDetailTransition(detached: .empty, candidate: candidate)
    }

    func select(
        _ type: HAWeatherForecastType,
        appGeneration: UInt64,
        configGeneration: UInt64
    ) -> WeatherDetailTransition? {
        guard supportedTypes.contains(type),
              let entityID = selectedEntityID,
              selectedType != type
        else { return nil }
        let detached = invalidateAndDetach()
        presentationGeneration = UUID()
        selectedEntityID = entityID
        selectedType = type
        modernEvent = nil
        phase = .loading
        let candidate = WeatherDetailOwnerCandidate(
            entityID: entityID,
            type: type,
            presentationGeneration: presentationGeneration,
            appGeneration: appGeneration,
            configGeneration: configGeneration
        )
        desiredCandidate = candidate
        return WeatherDetailTransition(detached: detached, candidate: candidate)
    }

    func close() -> WeatherDetailDetachedOwnership {
        let detached = invalidateAndDetach()
        presentationGeneration = UUID()
        selectedEntityID = nil
        selectedType = nil
        supportedTypes = []
        modernEvent = nil
        phase = .omitted
        return detached
    }

    func connectionChanged(_ state: HAWebSocketConnectionState) {
        guard desiredCandidate != nil else { return }
        switch state {
        case .disconnected, .connecting, .reconnecting:
            if subscription != nil {
                phase = .reconnecting
            }
        case .ready:
            if subscription != nil {
                phase = modernEvent == nil ? .loading : .subscribed
            }
        case .authenticationFailed:
            break
        }
    }

    func startupForReadyBoundary() -> Task<Void, Never>? {
        startup
    }

    func reconnectCandidateIfNeeded() -> WeatherDetailOwnerCandidate? {
        guard preAcknowledgementReconnectPending,
              startup == nil,
              subscription == nil,
              let candidate = desiredCandidate
        else { return nil }
        preAcknowledgementReconnectPending = false
        phase = .loading
        return candidate
    }

    func isCurrent(_ candidate: WeatherDetailOwnerCandidate) -> Bool {
        lifetimeAuthority.acceptsWork &&
            desiredCandidate == candidate &&
            selectedEntityID == candidate.entityID &&
            selectedType == candidate.type
    }

    @discardableResult
    func start(
        _ candidate: WeatherDetailOwnerCandidate,
        using client: HomeAssistantWebSocketClient
    ) -> Task<Void, Never>? {
        guard isCurrent(candidate), startup == nil, subscription == nil else { return nil }
        attemptGeneration = UUID()
        let attempt = attemptGeneration
        currentAttemptFailed = false
        preAcknowledgementReconnectPending = false
        phase = .loading
        let weakCoordinator = WeakWeatherDetailCoordinatorBox(self)
        let installHook = subscriptionInstallHook
        let task = Task { @MainActor [weak self, client, weakCoordinator, installHook] in
            do {
                let owner = try await client.subscribeWeatherForecast(
                    entityID: candidate.entityID,
                    type: candidate.type,
                    onTermination: { [weakCoordinator] error in
                        await MainActor.run {
                            weakCoordinator.value?.handleTermination(
                                error,
                                candidate: candidate,
                                attempt: attempt
                            )
                        }
                    },
                    onForecast: { [weakCoordinator] event in
                        await MainActor.run {
                            weakCoordinator.value?.accept(
                                event,
                                candidate: candidate,
                                attempt: attempt
                            )
                        }
                    }
                )
                guard let self = self else {
                    await owner.cancel()
                    return
                }
                guard !Task.isCancelled,
                      self.isCurrentAttempt(candidate, attempt: attempt)
                else {
                    await owner.cancel()
                    return
                }
                self.startup = nil
                self.subscription = owner
                // Installation is atomic with the subscribe continuation. The
                // test hook intentionally runs only after the coordinator owns
                // the handle, so terminal cancellation can always detach it.
                await installHook()
                guard !Task.isCancelled,
                      self.isCurrentAttempt(candidate, attempt: attempt),
                      self.subscription === owner
                else { return }
                self.phase = self.modernEvent == nil ? .loading : .subscribed
            } catch is CancellationError {
                self?.finishCancelledStartup(candidate: candidate, attempt: attempt)
            } catch {
                self?.handleStartupFailure(error, candidate: candidate, attempt: attempt)
            }
        }
        startup = task
        return task
    }

    func debugSnapshot() -> WeatherDetailOwnerDebugSnapshot {
        WeatherDetailOwnerDebugSnapshot(
            selectedEntityID: selectedEntityID,
            selectedType: selectedType,
            supportedTypes: supportedTypes,
            desired: desiredCandidate != nil,
            startupActive: startup != nil,
            subscriptionActive: subscription != nil,
            hasModernEvent: modernEvent != nil,
            phase: phase,
            presentationGeneration: presentationGeneration,
            currentAttemptFailed: currentAttemptFailed
        )
    }

    private func accept(
        _ event: HAWeatherForecastEvent,
        candidate: WeatherDetailOwnerCandidate,
        attempt: UUID
    ) {
        guard isCurrentAttempt(candidate, attempt: attempt),
              event.type == candidate.type
        else { return }
        modernEvent = event
        phase = (event.forecast?.count ?? 0) > 2 ? .subscribed : .loading
    }

    private func handleTermination(
        _ error: Error,
        candidate: WeatherDetailOwnerCandidate,
        attempt: UUID
    ) {
        guard isCurrentAttempt(candidate, attempt: attempt) else { return }
        // A typed decoding failure is delivered from inside Module 02's
        // callback owner. Invalidate synchronously, then hand the captured
        // logical ownership to the view model for immediate tracked retirement;
        // awaiting cancellation here would wait on the callback that is
        // currently executing.
        attemptGeneration = UUID()
        preAcknowledgementReconnectPending = false
        let detached = WeatherDetailDetachedOwnership(
            startup: startup,
            subscription: subscription
        )
        startup = nil
        subscription = nil
        failOnce(error)
        terminationOwnershipHandler?(detached)
    }

    private func handleStartupFailure(
        _ error: Error,
        candidate: WeatherDetailOwnerCandidate,
        attempt: UUID
    ) {
        guard isCurrentAttempt(candidate, attempt: attempt) else { return }
        startup = nil
        subscription = nil
        if isReconnectLoss(error) {
            preAcknowledgementReconnectPending = true
            phase = .reconnecting
            return
        }
        attemptGeneration = UUID()
        failOnce(error)
    }

    private func finishCancelledStartup(
        candidate: WeatherDetailOwnerCandidate,
        attempt: UUID
    ) {
        guard isCurrentAttempt(candidate, attempt: attempt) else { return }
        startup = nil
    }

    private func failOnce(_ error: Error) {
        guard !currentAttemptFailed else { return }
        currentAttemptFailed = true
        phase = .terminalFailure
        AppLog(
            "Weather detail forecast ended; entity=\(selectedEntityID ?? "none") " +
                "type=\(selectedType?.rawValue ?? "none"): \(String(reflecting: error))",
            severity: .warning,
            category: .webSocket
        )
    }

    private func isReconnectLoss(_ error: Error) -> Bool {
        if case HomeAssistantWebSocketError.disconnected = error { return true }
        return false
    }

    private func isCurrentAttempt(
        _ candidate: WeatherDetailOwnerCandidate,
        attempt: UUID
    ) -> Bool {
        isCurrent(candidate) && attemptGeneration == attempt
    }

    private func invalidateAndDetach() -> WeatherDetailDetachedOwnership {
        desiredCandidate = nil
        attemptGeneration = UUID()
        currentAttemptFailed = false
        preAcknowledgementReconnectPending = false
        modernEvent = nil
        let detached = WeatherDetailDetachedOwnership(
            startup: startup,
            subscription: subscription
        )
        startup?.cancel()
        startup = nil
        subscription = nil
        return detached
    }
}

struct WeatherDetailOwnerDebugSnapshot: Equatable {
    let selectedEntityID: String?
    let selectedType: HAWeatherForecastType?
    let supportedTypes: [HAWeatherForecastType]
    let desired: Bool
    let startupActive: Bool
    let subscriptionActive: Bool
    let hasModernEvent: Bool
    let phase: WeatherDetailForecastPhase
    let presentationGeneration: UUID
    let currentAttemptFailed: Bool

    var ownerCount: Int { (startupActive ? 1 : 0) + (subscriptionActive ? 1 : 0) }
}

private final class WeakWeatherDetailCoordinatorBox: @unchecked Sendable {
    weak var value: DashboardWeatherDetailCoordinator?

    init(_ value: DashboardWeatherDetailCoordinator) {
        self.value = value
    }
}
