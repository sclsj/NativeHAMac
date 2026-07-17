import Foundation

public final class HomeAssistantWebSocketClient {
    public let connection: HomeAssistantWebSocketConnection

    public init(
        configuration: HomeAssistantConfiguration,
        session: URLSession = .shared,
        commandTimeout: TimeInterval? = nil,
        subscriptionDeliveryCapacity: Int = 256,
        maximumConcurrentCallbackTasks: Int = 4
    ) {
        connection = HomeAssistantWebSocketConnection(
            configuration: configuration,
            session: session,
            commandTimeout: commandTimeout,
            deliveryCapacity: subscriptionDeliveryCapacity,
            maximumConcurrentCallbackTasks: maximumConcurrentCallbackTasks
        )
    }

    init(connection: HomeAssistantWebSocketConnection) {
        self.connection = connection
    }

    public func connect() async throws {
        try await connection.connect()
    }

    public func disconnect() async {
        await connection.disconnect()
    }

    public func fetchLovelaceConfig() async throws -> LovelaceConfig {
        try await connection.call(
            ["type": .string("lovelace/config")],
            as: LovelaceConfig.self
        )
    }

    public func subscribeToStateChanges(
        _ onState: @escaping @Sendable (HAState) async -> Void
    ) async throws -> HAWebSocketSubscription {
        try await connection.subscribeEvents(
            eventType: "state_changed",
            as: HAStateChangedEvent.self
        ) { event in
            if let state = event.data.newState {
                await onState(state)
            }
        }
    }

    public func subscribeHistoryStatesTimeWindow(
        entityIDs: [String],
        hoursToShow: Int,
        currentStates: [String: HAState],
        now: @escaping @Sendable () -> Date = { Date() },
        onStatus: @escaping @Sendable (HAHistoryStreamOwnerStatus) async -> Void = { _ in },
        onHistory: @escaping @Sendable ([String: [HACompactHistoryState]]) async -> Void
    ) async throws -> HAHistoryStreamSubscription {
        let coordinator = HAHistoryStreamCoordinator(
            connection: connection,
            entityIDs: entityIDs,
            range: TimeInterval(max(hoursToShow, 1) * 60 * 60),
            currentStates: currentStates,
            now: now,
            onUpdate: onHistory,
            onStatus: onStatus
        )
        try await coordinator.start()
        return HAHistoryStreamSubscription(coordinator: coordinator)
    }
}

private struct HAStateChangedEvent: Decodable {
    let data: DataPayload

    struct DataPayload: Decodable {
        let newState: HAState?

        private enum CodingKeys: String, CodingKey {
            case newState = "new_state"
        }
    }
}
