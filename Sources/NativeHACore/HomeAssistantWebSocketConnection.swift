import Foundation

public enum HomeAssistantWebSocketError: Error, Equatable {
    case invalidURL
    case invalidMessage
    case authenticationFailed(String)
    case commandFailed(code: String?, message: String)
    case disconnected
    case timedOut
    case cancelled
    case deliveryOverflow(subscriptionID: Int)
}

extension HomeAssistantWebSocketError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Home Assistant WebSocket URL"
        case .invalidMessage:
            return "Invalid Home Assistant WebSocket message"
        case let .authenticationFailed(message):
            return "Home Assistant authentication failed: \(message)"
        case let .commandFailed(code, message):
            if let code = code, !code.isEmpty {
                return "Home Assistant command failed (\(code)): \(message)"
            }
            return "Home Assistant command failed: \(message)"
        case .disconnected:
            return "Home Assistant WebSocket disconnected"
        case .timedOut:
            return "Home Assistant WebSocket command timed out"
        case .cancelled:
            return "Home Assistant WebSocket command was cancelled"
        case let .deliveryOverflow(subscriptionID):
            return "Home Assistant subscription \(subscriptionID) exceeded its delivery capacity"
        }
    }
}

public enum HAWebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case reconnecting(attempt: Int)
    case ready
    case authenticationFailed(String)
}

public struct HAWebSocketDebugSnapshot: Equatable {
    public let state: HAWebSocketConnectionState
    public let pendingCommandCount: Int
    public let subscriptionCount: Int
    public let wireSubscriptionCount: Int
    public let receiveLoopCount: Int
    public let nextCommandID: Int
    public let deliveryOwnerCount: Int
    public let bufferedDeliveryCount: Int
    public let activeDeliveryTaskCount: Int
    public let activeTerminationTaskCount: Int
    public let pendingTerminationCount: Int
    public let droppedTerminationCount: Int
}

public final class HAWebSocketSubscription {
    public let id: Int

    private let logicalID: UUID
    private let connection: HomeAssistantWebSocketConnection

    fileprivate init(id: Int, logicalID: UUID, connection: HomeAssistantWebSocketConnection) {
        self.id = id
        self.logicalID = logicalID
        self.connection = connection
    }

    public func cancel() async {
        await connection.cancelSubscription(logicalID)
    }
}

public actor HomeAssistantWebSocketConnection {
    public typealias TransportFactory = () throws -> HomeAssistantWebSocketTransport

    private struct PendingCommand {
        let logicalID: UUID
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeoutTask: Task<Void, Never>
    }

    private struct SubscriptionRecord {
        let logicalID: UUID
        let originalID: Int
        var wireID: Int?
        let message: [String: JSONValue]
        let resubscribe: Bool
        let termination: (@Sendable (Error) async -> Void)?
        var acknowledgement: CheckedContinuation<Void, Error>?
        var timeoutTask: Task<Void, Never>?
    }

    private let accessToken: String
    private let commandTimeoutNanoseconds: UInt64
    private let deliveryCapacity: Int
    private let callbackCoordinator: HAWebSocketCallbackCoordinator
    private let transportFactory: TransportFactory
    private let reconnectDelayNanoseconds: (Int) -> UInt64

    private var transport: HomeAssistantWebSocketTransport?
    private var outboundSender: HomeAssistantWebSocketSendSerializer?
    private var connectionTask: Task<Void, Error>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var generation = 0
    private var receiveLoopCount = 0
    private var nextID = 1
    private var state: HAWebSocketConnectionState = .disconnected
    private var disconnectRequested = true
    private var pendingCommands: [Int: PendingCommand] = [:]
    private var registeringCommandIDs: Set<UUID> = []
    private var cancelledBeforeCommandRegistration: Set<UUID> = []
    private var subscriptions: [UUID: SubscriptionRecord] = [:]
    private var wireSubscriptions: [Int: UUID] = [:]
    private var registeringSubscriptionIDs: Set<UUID> = []
    private var cancelledBeforeSubscriptionRegistration: Set<UUID> = []
    private var statusListeners: [UUID: AsyncStream<HAWebSocketConnectionState>.Continuation] = [:]

    public init(
        configuration: HomeAssistantConfiguration,
        session: URLSession = .shared,
        commandTimeout: TimeInterval? = nil,
        receivePolicy: HomeAssistantWebSocketReceivePolicy = .platformDefault,
        deliveryCapacity: Int = 256,
        maximumConcurrentCallbackTasks: Int = 4
    ) {
        accessToken = configuration.accessToken
        commandTimeoutNanoseconds = Self.nanoseconds(from: commandTimeout ?? configuration.timeout)
        self.deliveryCapacity = max(deliveryCapacity, 1)
        callbackCoordinator = HAWebSocketCallbackCoordinator(
            maximumConcurrentDeliveryTasks: maximumConcurrentCallbackTasks,
            maximumPendingTerminations: deliveryCapacity
        )
        reconnectDelayNanoseconds = { attempt in
            UInt64(min(max(attempt, 0), 5)) * 1_000_000_000
        }
        transportFactory = {
            let url = try Self.webSocketURL(from: configuration.baseURL)
            return URLSessionHomeAssistantWebSocketTransport(
                url: url,
                session: session,
                receivePolicy: receivePolicy
            )
        }
    }

    init(
        accessToken: String,
        commandTimeoutNanoseconds: UInt64,
        deliveryCapacity: Int = 256,
        maximumConcurrentCallbackTasks: Int = 4,
        reconnectDelayNanoseconds: @escaping (Int) -> UInt64 = { _ in 0 },
        transportFactory: @escaping TransportFactory
    ) {
        self.accessToken = accessToken
        self.commandTimeoutNanoseconds = max(commandTimeoutNanoseconds, 1)
        self.deliveryCapacity = max(deliveryCapacity, 1)
        callbackCoordinator = HAWebSocketCallbackCoordinator(
            maximumConcurrentDeliveryTasks: maximumConcurrentCallbackTasks,
            maximumPendingTerminations: deliveryCapacity
        )
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
        self.transportFactory = transportFactory
    }

    public func connect() async throws {
        AppLog("WebSocket connect() called", category: .network)
        if state == .ready {
            return
        }

        if let connectionTask = connectionTask {
            try await connectionTask.value
            return
        }

        let task = Task {
            try await self.performInitialConnection()
        }
        connectionTask = task
        do {
            try await task.value
            connectionTask = nil
        } catch {
            connectionTask = nil
            throw error
        }
    }

    private func performInitialConnection() async throws {
        if state == .ready {
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        disconnectRequested = false
        transition(to: .connecting)

        do {
            try await establishConnection()
        } catch {
            disconnectRequested = true
            await abandonCurrentTransport()
            if case let HomeAssistantWebSocketError.authenticationFailed(message) = error {
                transition(to: .authenticationFailed(message))
            } else {
                transition(to: .disconnected)
            }
            throw error
        }
    }

    public func disconnect() async {
        AppLog("WebSocket disconnect() called", category: .network)
        disconnectRequested = true
        connectionTask?.cancel()
        connectionTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        receiveLoopCount = 0

        let oldTransport = transport
        transport = nil
        let oldSender = outboundSender
        outboundSender = nil
        oldSender?.stop()
        await oldTransport?.disconnect()

        failAllPending(with: HomeAssistantWebSocketError.disconnected)
        registeringCommandIDs.removeAll()
        cancelledBeforeCommandRegistration.removeAll()
        let records = Array(subscriptions.values)
        subscriptions.removeAll()
        wireSubscriptions.removeAll()
        registeringSubscriptionIDs.removeAll()
        cancelledBeforeSubscriptionRegistration.removeAll()
        await callbackCoordinator.removeAllOwners()
        for record in records {
            record.timeoutTask?.cancel()
            record.acknowledgement?.resume(throwing: HomeAssistantWebSocketError.disconnected)
            if record.acknowledgement == nil {
                await callbackCoordinator.submitTermination(
                    record.termination,
                    error: HomeAssistantWebSocketError.disconnected
                )
            }
        }
        transition(to: .disconnected)
    }

    public func reconnect() async {
        guard !disconnectRequested, transport != nil else {
            return
        }
        await handleConnectionFailure(HomeAssistantWebSocketError.disconnected, generation: generation)
    }

    public func statusUpdates() -> AsyncStream<HAWebSocketConnectionState> {
        let listenerID = UUID()
        let connection = self
        return AsyncStream { continuation in
            statusListeners[listenerID] = continuation
            continuation.yield(state)
            continuation.onTermination = { _ in
                Task {
                    await connection.removeStatusListener(listenerID)
                }
            }
        }
    }

    public func callRaw(_ message: [String: JSONValue]) async throws -> JSONValue {
        guard state == .ready, transport != nil else {
            throw HomeAssistantWebSocketError.disconnected
        }

        let logicalID = UUID()
        let commandGeneration = generation
        registeringCommandIDs.insert(logicalID)

        return try await withTaskCancellationHandler(
            handler: {
                Task {
                    await self.cancelPendingCommand(logicalID)
                }
            },
            operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<JSONValue, Error>) in
                    Task {
                        await self.registerAndSendPendingCommand(
                            message,
                            logicalID: logicalID,
                            generation: commandGeneration,
                            continuation: continuation
                        )
                    }
                }
            }
        )
    }

    public func call<T: Decodable>(
        _ message: [String: JSONValue],
        as type: T.Type = T.self
    ) async throws -> T {
        let result = try await callRaw(message)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(type, from: data)
    }

    public func subscribeRaw(
        _ message: [String: JSONValue],
        resubscribe: Bool = true,
        onTermination: (@Sendable (Error) async -> Void)? = nil,
        onMessage: @escaping @Sendable (JSONValue) async -> Void
    ) async throws -> HAWebSocketSubscription {
        guard state == .ready, transport != nil else {
            throw HomeAssistantWebSocketError.disconnected
        }

        let logicalID = UUID()
        let commandGeneration = generation
        registeringSubscriptionIDs.insert(logicalID)

        try await withTaskCancellationHandler(
            handler: {
                Task {
                    await self.cancelSubscription(logicalID)
                }
            },
            operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    Task {
                        await self.registerAndSendPendingSubscription(
                            logicalID,
                            message: message,
                            resubscribe: resubscribe,
                            callback: onMessage,
                            termination: onTermination,
                            generation: commandGeneration,
                            continuation: continuation
                        )
                    }
                }
            }
        )

        guard let record = subscriptions[logicalID], let wireID = record.wireID else {
            throw HomeAssistantWebSocketError.cancelled
        }

        return HAWebSocketSubscription(id: wireID, logicalID: logicalID, connection: self)
    }

    public func subscribeMessage<T: Decodable>(
        _ message: [String: JSONValue],
        as type: T.Type = T.self,
        resubscribe: Bool = true,
        onTermination: (@Sendable (Error) async -> Void)? = nil,
        onMessage: @escaping @Sendable (T) async -> Void
    ) async throws -> HAWebSocketSubscription {
        try await subscribeRaw(
            message,
            resubscribe: resubscribe,
            onTermination: onTermination
        ) { payload in
            guard
                let data = try? JSONEncoder().encode(payload),
                let value = try? JSONDecoder().decode(type, from: data)
            else {
                return
            }
            await onMessage(value)
        }
    }

    public func subscribeEvents<T: Decodable>(
        eventType: String? = nil,
        as type: T.Type = T.self,
        resubscribe: Bool = true,
        onTermination: (@Sendable (Error) async -> Void)? = nil,
        onEvent: @escaping @Sendable (T) async -> Void
    ) async throws -> HAWebSocketSubscription {
        var message: [String: JSONValue] = ["type": .string("subscribe_events")]
        if let eventType = eventType {
            message["event_type"] = .string(eventType)
        }
        return try await subscribeMessage(
            message,
            as: type,
            resubscribe: resubscribe,
            onTermination: onTermination,
            onMessage: onEvent
        )
    }

    public func debugSnapshot() async -> HAWebSocketDebugSnapshot {
        let callbackSnapshot = await callbackCoordinator.snapshot()
        return HAWebSocketDebugSnapshot(
            state: state,
            pendingCommandCount: pendingCommands.count,
            subscriptionCount: subscriptions.count,
            wireSubscriptionCount: wireSubscriptions.count,
            receiveLoopCount: receiveLoopCount,
            nextCommandID: nextID,
            deliveryOwnerCount: callbackSnapshot.ownerCount,
            bufferedDeliveryCount: callbackSnapshot.bufferedDeliveryCount,
            activeDeliveryTaskCount: callbackSnapshot.activeDeliveryTaskCount,
            activeTerminationTaskCount: callbackSnapshot.activeTerminationTaskCount,
            pendingTerminationCount: callbackSnapshot.pendingTerminationCount,
            droppedTerminationCount: callbackSnapshot.droppedTerminationCount
        )
    }

    fileprivate func cancelSubscription(_ logicalID: UUID) async {
        guard let record = subscriptions.removeValue(forKey: logicalID) else {
            if registeringSubscriptionIDs.contains(logicalID) {
                cancelledBeforeSubscriptionRegistration.insert(logicalID)
            }
            await callbackCoordinator.remove(ownerID: logicalID)
            return
        }

        record.timeoutTask?.cancel()
        record.acknowledgement?.resume(throwing: HomeAssistantWebSocketError.cancelled)
        if let wireID = record.wireID {
            wireSubscriptions.removeValue(forKey: wireID)
        }
        await callbackCoordinator.remove(ownerID: logicalID)

        guard state == .ready, let wireID = record.wireID else {
            return
        }
        _ = try? await callRaw([
            "type": .string("unsubscribe_events"),
            "subscription": .int(wireID),
        ])
    }

    private func establishConnection() async throws {
        generation += 1
        let connectionGeneration = generation
        let newTransport = try transportFactory()
        transport = newTransport
        outboundSender = HomeAssistantWebSocketSendSerializer(transport: newTransport)
        try await newTransport.connect()

        let version = try await authenticate(on: newTransport)
        nextID = 1
        if supportsCoalescing(version: version) {
            let featureID = allocateID()
            try await sendObject([
                "id": .int(featureID),
                "type": .string("supported_features"),
                "features": .object(["coalesce_messages": .int(1)]),
            ], over: newTransport)
        }

        startReceiveLoop(transport: newTransport, generation: connectionGeneration)
        try await resubscribeStoredSubscriptions(over: newTransport)
        transition(to: .ready)
    }

    private func authenticate(on transport: HomeAssistantWebSocketTransport) async throws -> String? {
        var sentAuthentication = false

        while true {
            let frame = try await transport.receive()
            let messages = try decodeFrame(frame)
            for message in messages {
                guard case let .object(object) = message else {
                    throw HomeAssistantWebSocketError.invalidMessage
                }
                switch object["type"]?.stringValue {
                case "auth_required":
                    guard !sentAuthentication else {
                        continue
                    }
                    sentAuthentication = true
                    try await sendObject([
                        "type": .string("auth"),
                        "access_token": .string(accessToken),
                    ], over: transport)
                case "auth_ok":
                    guard sentAuthentication else {
                        throw HomeAssistantWebSocketError.invalidMessage
                    }
                    return object["ha_version"]?.stringValue
                case "auth_invalid":
                    let message = object["message"]?.stringValue ?? "Authentication rejected"
                    throw HomeAssistantWebSocketError.authenticationFailed(message)
                default:
                    continue
                }
            }
        }
    }

    private func startReceiveLoop(
        transport: HomeAssistantWebSocketTransport,
        generation: Int
    ) {
        receiveTask?.cancel()
        receiveLoopCount = 1
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop(transport: transport, generation: generation)
        }
    }

    private func runReceiveLoop(
        transport: HomeAssistantWebSocketTransport,
        generation: Int
    ) async {
        do {
            while !Task.isCancelled {
                let frame = try await transport.receive()
                try await decodeAndDispatchFrame(frame)
            }
        } catch {
            if !Task.isCancelled {
                await handleConnectionFailure(error, generation: generation)
            }
        }
    }

    func dispatchPredecodedMessages(_ messages: [JSONValue]) async throws {
        for message in messages {
            try await dispatch(message)
        }
    }

    func decodeAndDispatchFrame(_ frame: HAWebSocketFrame) async throws {
        try await dispatchPredecodedMessages(decodeFrame(frame))
    }

    private func dispatch(_ value: JSONValue) async throws {
        guard case let .object(message) = value else {
            throw HomeAssistantWebSocketError.invalidMessage
        }

        let id = message["id"]?.intValue
        switch message["type"]?.stringValue {
        case "result":
            guard let id = id else {
                throw HomeAssistantWebSocketError.invalidMessage
            }
            if let pending = pendingCommands.removeValue(forKey: id) {
                pending.timeoutTask.cancel()
                if message["success"]?.boolValue == true {
                    pending.continuation.resume(returning: message["result"] ?? .null)
                } else {
                    pending.continuation.resume(throwing: commandError(from: message))
                }
                return
            }

            guard
                let logicalID = wireSubscriptions[id],
                var record = subscriptions[logicalID]
            else {
                return
            }
            record.timeoutTask?.cancel()
            record.timeoutTask = nil
            if message["success"]?.boolValue == true {
                record.acknowledgement?.resume(returning: ())
                record.acknowledgement = nil
                subscriptions[logicalID] = record
            } else {
                let error = commandError(from: message)
                wireSubscriptions.removeValue(forKey: id)
                subscriptions.removeValue(forKey: logicalID)
                if let acknowledgement = record.acknowledgement {
                    acknowledgement.resume(throwing: error)
                } else {
                    await callbackCoordinator.submitTermination(record.termination, error: error)
                }
                await callbackCoordinator.remove(ownerID: logicalID)
            }

        case "event":
            guard
                let id = id,
                let logicalID = wireSubscriptions[id],
                let record = subscriptions[logicalID]
            else {
                return
            }
            let accepted = await callbackCoordinator.enqueue(
                ownerID: logicalID,
                value: message["event"] ?? .null
            )
            if !accepted {
                await overflowSubscription(logicalID, record: record)
            }

        case "pong":
            guard let id = id, let pending = pendingCommands.removeValue(forKey: id) else {
                return
            }
            pending.timeoutTask.cancel()
            pending.continuation.resume(returning: .null)

        default:
            return
        }
    }

    private func overflowSubscription(_ logicalID: UUID, record: SubscriptionRecord) async {
        guard subscriptions.removeValue(forKey: logicalID) != nil else {
            return
        }
        if let wireID = record.wireID {
            wireSubscriptions.removeValue(forKey: wireID)
        }
        record.timeoutTask?.cancel()
        let error = HomeAssistantWebSocketError.deliveryOverflow(subscriptionID: record.originalID)
        if let acknowledgement = record.acknowledgement {
            acknowledgement.resume(throwing: error)
        } else {
            await callbackCoordinator.submitTermination(record.termination, error: error)
        }
        await callbackCoordinator.remove(ownerID: logicalID)
    }

    private func sendPendingCommand(_ command: [String: JSONValue], id: Int, generation: Int) async {
        guard pendingCommands[id] != nil, self.generation == generation, let transport = transport else {
            failPendingCommand(id, with: HomeAssistantWebSocketError.disconnected)
            return
        }

        do {
            try await sendObject(
                command,
                over: transport,
                shouldSend: { [weak self] in
                    await self?.canSendPendingCommand(id, generation: generation) == true
                }
            )
        } catch {
            failPendingCommand(id, with: error)
            await handleConnectionFailure(error, generation: generation)
        }
    }

    private func registerAndSendPendingCommand(
        _ command: [String: JSONValue],
        logicalID: UUID,
        generation: Int,
        continuation: CheckedContinuation<JSONValue, Error>
    ) async {
        registeringCommandIDs.remove(logicalID)
        if cancelledBeforeCommandRegistration.remove(logicalID) != nil {
            continuation.resume(throwing: HomeAssistantWebSocketError.cancelled)
            return
        }
        let id = allocateID()
        let timeout = commandTimeoutNanoseconds
        let connection = self
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            await connection.timeoutPendingCommand(id)
        }
        pendingCommands[id] = PendingCommand(
            logicalID: logicalID,
            continuation: continuation,
            timeoutTask: timeoutTask
        )
        var commandToSend = command
        commandToSend["id"] = .int(id)
        await sendPendingCommand(commandToSend, id: id, generation: generation)
    }

    private func registerAndSendPendingSubscription(
        _ logicalID: UUID,
        message: [String: JSONValue],
        resubscribe: Bool,
        callback: @escaping @Sendable (JSONValue) async -> Void,
        termination: (@Sendable (Error) async -> Void)?,
        generation: Int,
        continuation: CheckedContinuation<Void, Error>
    ) async {
        if cancelledBeforeSubscriptionRegistration.remove(logicalID) != nil {
            registeringSubscriptionIDs.remove(logicalID)
            continuation.resume(throwing: HomeAssistantWebSocketError.cancelled)
            await callbackCoordinator.remove(ownerID: logicalID)
            return
        }
        await callbackCoordinator.register(
            ownerID: logicalID,
            capacity: deliveryCapacity,
            callback: callback
        )
        registeringSubscriptionIDs.remove(logicalID)
        if cancelledBeforeSubscriptionRegistration.remove(logicalID) != nil {
            continuation.resume(throwing: HomeAssistantWebSocketError.cancelled)
            await callbackCoordinator.remove(ownerID: logicalID)
            return
        }
        guard self.generation == generation, state == .ready, transport != nil else {
            continuation.resume(throwing: HomeAssistantWebSocketError.disconnected)
            await callbackCoordinator.remove(ownerID: logicalID)
            return
        }

        let wireID = allocateID()
        let timeout = commandTimeoutNanoseconds
        let connection = self
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            await connection.timeoutSubscription(logicalID)
        }
        let record = SubscriptionRecord(
            logicalID: logicalID,
            originalID: wireID,
            wireID: wireID,
            message: message,
            resubscribe: resubscribe,
            termination: termination,
            acknowledgement: continuation,
            timeoutTask: timeoutTask
        )
        subscriptions[logicalID] = record
        wireSubscriptions[wireID] = logicalID
        await sendPendingSubscription(logicalID, wireID: wireID, generation: generation)
    }

    private func sendPendingSubscription(_ logicalID: UUID, wireID: Int, generation: Int) async {
        guard
            let record = subscriptions[logicalID],
            record.wireID == wireID,
            self.generation == generation,
            let transport = transport
        else {
            await failSubscription(logicalID, with: HomeAssistantWebSocketError.disconnected)
            return
        }

        var command = record.message
        command["id"] = .int(wireID)
        do {
            try await sendObject(
                command,
                over: transport,
                shouldSend: { [weak self] in
                    await self?.canSendPendingSubscription(
                        logicalID,
                        wireID: wireID,
                        generation: generation
                    ) == true
                }
            )
        } catch {
            await failSubscription(logicalID, with: error)
            await handleConnectionFailure(error, generation: generation)
        }
    }

    private func resubscribeStoredSubscriptions(
        over transport: HomeAssistantWebSocketTransport
    ) async throws {
        let resubscribeGeneration = generation
        let logicalIDs = subscriptions.keys.sorted { $0.uuidString < $1.uuidString }
        for logicalID in logicalIDs {
            guard var record = subscriptions[logicalID], record.resubscribe else {
                continue
            }
            let wireID = allocateID()
            record.wireID = wireID
            subscriptions[logicalID] = record
            wireSubscriptions[wireID] = logicalID
            var command = record.message
            command["id"] = .int(wireID)
            try await sendObject(
                command,
                over: transport,
                shouldSend: { [weak self] in
                    await self?.canSendPendingSubscription(
                        logicalID,
                        wireID: wireID,
                        generation: resubscribeGeneration
                    ) == true
                }
            )
        }
    }

    private func canSendPendingCommand(_ id: Int, generation: Int) -> Bool {
        pendingCommands[id] != nil
            && self.generation == generation
            && transport != nil
    }

    private func canSendPendingSubscription(
        _ logicalID: UUID,
        wireID: Int,
        generation: Int
    ) -> Bool {
        guard let record = subscriptions[logicalID] else {
            return false
        }
        return record.wireID == wireID
            && self.generation == generation
            && transport != nil
    }

    private func handleConnectionFailure(_ error: Error, generation: Int) async {
        guard generation == self.generation, !disconnectRequested else {
            return
        }

        self.generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        receiveLoopCount = 0
        let oldTransport = transport
        transport = nil
        let oldSender = outboundSender
        outboundSender = nil
        oldSender?.stop()
        await oldTransport?.disconnect()

        failAllPending(with: HomeAssistantWebSocketError.disconnected)
        wireSubscriptions.removeAll()

        let records = Array(subscriptions.values)
        for var record in records {
            record.timeoutTask?.cancel()
            record.timeoutTask = nil
            record.wireID = nil
            if let acknowledgement = record.acknowledgement {
                acknowledgement.resume(throwing: HomeAssistantWebSocketError.disconnected)
                await callbackCoordinator.remove(ownerID: record.logicalID)
                subscriptions.removeValue(forKey: record.logicalID)
            } else if record.resubscribe {
                subscriptions[record.logicalID] = record
            } else {
                await callbackCoordinator.remove(ownerID: record.logicalID)
                await callbackCoordinator.submitTermination(
                    record.termination,
                    error: HomeAssistantWebSocketError.disconnected
                )
                subscriptions.removeValue(forKey: record.logicalID)
            }
        }

        transition(to: .disconnected)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil, !disconnectRequested else {
            return
        }
        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        var attempt = 0
        while !disconnectRequested, !Task.isCancelled {
            transition(to: .reconnecting(attempt: attempt))
            let delay = reconnectDelayNanoseconds(attempt)
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    break
                }
            }

            do {
                try await establishConnection()
                reconnectTask = nil
                return
            } catch let error as HomeAssistantWebSocketError {
                await abandonCurrentTransport()
                if case let .authenticationFailed(message) = error {
                    transition(to: .authenticationFailed(message))
                    reconnectTask = nil
                    return
                }
            } catch {
                await abandonCurrentTransport()
            }
            attempt += 1
        }
        reconnectTask = nil
    }

    private func abandonCurrentTransport() async {
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        receiveLoopCount = 0
        let oldTransport = transport
        transport = nil
        let oldSender = outboundSender
        outboundSender = nil
        oldSender?.stop()
        await oldTransport?.disconnect()
    }

    private func cancelPendingCommand(_ logicalID: UUID) {
        if registeringCommandIDs.contains(logicalID) {
            cancelledBeforeCommandRegistration.insert(logicalID)
            return
        }
        if let key = pendingCommands.first(where: { $1.logicalID == logicalID })?.key {
            failPendingCommand(key, with: HomeAssistantWebSocketError.cancelled)
        }
    }

    private func timeoutPendingCommand(_ id: Int) {
        failPendingCommand(id, with: HomeAssistantWebSocketError.timedOut)
    }

    private func failPendingCommand(_ id: Int, with error: Error) {
        guard let pending = pendingCommands.removeValue(forKey: id) else {
            return
        }
        pending.timeoutTask.cancel()
        pending.continuation.resume(throwing: error)
    }

    private func failAllPending(with error: Error) {
        let current = pendingCommands
        pendingCommands.removeAll()
        for pending in current.values {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: error)
        }
    }

    private func timeoutSubscription(_ logicalID: UUID) async {
        await failSubscription(logicalID, with: HomeAssistantWebSocketError.timedOut)
    }

    private func failSubscription(_ logicalID: UUID, with error: Error) async {
        guard let record = subscriptions.removeValue(forKey: logicalID) else {
            return
        }
        if let wireID = record.wireID {
            wireSubscriptions.removeValue(forKey: wireID)
        }
        record.timeoutTask?.cancel()
        if let acknowledgement = record.acknowledgement {
            acknowledgement.resume(throwing: error)
        } else {
            await callbackCoordinator.submitTermination(record.termination, error: error)
        }
        await callbackCoordinator.remove(ownerID: logicalID)
    }

    private func allocateID() -> Int {
        let id = nextID
        nextID += 1
        return id
    }

    private func sendObject(
        _ object: [String: JSONValue],
        over transport: HomeAssistantWebSocketTransport,
        shouldSend: @escaping @Sendable () async -> Bool = { true }
    ) async throws {
        let data = try JSONEncoder().encode(JSONValue.object(object))
        guard let text = String(data: data, encoding: .utf8) else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        AppLog(
            "WebSocket send type=\(object["type"]?.stringValue ?? "unknown") "
                + "id=\(object["id"]?.intValue.map(String.init) ?? "none") bytes=\(data.count)",
            severity: .debug,
            category: .network
        )
        guard let outboundSender = outboundSender, outboundSender.isFor(transport) else {
            throw HomeAssistantWebSocketError.disconnected
        }
        let ticket = outboundSender.enqueue(.string(text), shouldSend: shouldSend)
        try await ticket.value()
    }

    private func decodeFrame(_ frame: HAWebSocketFrame) throws -> [JSONValue] {
        let data: Data
        switch frame {
        case let .string(value):
            data = Data(value.utf8)
            AppLog("WebSocket receive text bytes=\(data.count)", severity: .debug, category: .network)
        case let .data(value):
            data = value
            AppLog("WebSocket receive: \(value.count) bytes", severity: .debug, category: .network)
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        switch decoded {
        case .object:
            return [decoded]
        case let .array(values):
            guard values.allSatisfy({ value in
                if case .object = value { return true }
                return false
            }) else {
                throw HomeAssistantWebSocketError.invalidMessage
            }
            return values
        default:
            throw HomeAssistantWebSocketError.invalidMessage
        }
    }

    private func commandError(from message: [String: JSONValue]) -> HomeAssistantWebSocketError {
        guard case let .object(error)? = message["error"] else {
            return .commandFailed(code: nil, message: "Unknown server error")
        }
        return .commandFailed(
            code: error["code"]?.stringValue,
            message: error["message"]?.stringValue ?? "Unknown server error"
        )
    }

    private func transition(to newState: HAWebSocketConnectionState) {
        AppLog("WebSocket connection state transitioned to: \(newState)", category: .network)
        state = newState
        for continuation in statusListeners.values {
            continuation.yield(newState)
        }
    }

    private func removeStatusListener(_ id: UUID) {
        statusListeners.removeValue(forKey: id)
    }

    private func supportsCoalescing(version: String?) -> Bool {
        guard let version = version else {
            return false
        }
        let components = version.split(separator: ".").compactMap { Int($0) }
        guard let year = components.first else {
            return false
        }
        let month = components.count > 1 ? components[1] : 0
        return year > 2022 || (year == 2022 && month >= 9)
    }

    private static func nanoseconds(from seconds: TimeInterval) -> UInt64 {
        let clamped = max(seconds, 0.001)
        return UInt64(clamped * 1_000_000_000)
    }

    private static func webSocketURL(from baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HomeAssistantWebSocketError.invalidURL
        }

        switch components.scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            throw HomeAssistantWebSocketError.invalidURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "api", "websocket"]
            .filter { !$0.isEmpty }
            .joined(separator: "/"))

        guard let url = components.url else {
            throw HomeAssistantWebSocketError.invalidURL
        }
        return url
    }
}

private actor HAWebSocketCallbackCoordinator {
    struct Snapshot {
        let ownerCount: Int
        let bufferedDeliveryCount: Int
        let activeDeliveryTaskCount: Int
        let activeTerminationTaskCount: Int
        let pendingTerminationCount: Int
        let droppedTerminationCount: Int
    }

    private struct Owner {
        let capacity: Int
        let callback: @Sendable (JSONValue) async -> Void
        var buffer: [JSONValue] = []
        var activeTaskID: UUID?
    }

    private struct TerminationWork {
        let callback: @Sendable (Error) async -> Void
        let error: Error
    }

    private let maximumConcurrentDeliveryTasks: Int
    private let maximumPendingTerminations: Int
    private var owners: [UUID: Owner] = [:]
    private var ownerOrder: [UUID] = []
    private var activeDeliveryTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingTerminations: [TerminationWork] = []
    private var activeTerminationTasks: [UUID: Task<Void, Never>] = [:]
    private var droppedTerminationCount = 0

    init(maximumConcurrentDeliveryTasks: Int, maximumPendingTerminations: Int) {
        self.maximumConcurrentDeliveryTasks = max(maximumConcurrentDeliveryTasks, 1)
        self.maximumPendingTerminations = max(maximumPendingTerminations, 1)
    }

    func register(
        ownerID: UUID,
        capacity: Int,
        callback: @escaping @Sendable (JSONValue) async -> Void
    ) {
        if let activeTaskID = owners[ownerID]?.activeTaskID {
            activeDeliveryTasks[activeTaskID]?.cancel()
        }
        if owners[ownerID] == nil {
            ownerOrder.append(ownerID)
        }
        owners[ownerID] = Owner(
            capacity: max(capacity, 1),
            callback: callback
        )
    }

    func enqueue(ownerID: UUID, value: JSONValue) -> Bool {
        guard var owner = owners[ownerID], owner.buffer.count < owner.capacity else {
            return false
        }
        owner.buffer.append(value)
        owners[ownerID] = owner
        scheduleDeliveries()
        return true
    }

    func remove(ownerID: UUID) {
        guard let owner = owners.removeValue(forKey: ownerID) else {
            return
        }
        ownerOrder.removeAll { $0 == ownerID }
        if let activeTaskID = owner.activeTaskID {
            // Cancellation is requested, but the task remains explicitly owned and
            // counted until an arbitrary subscriber callback actually returns.
            activeDeliveryTasks[activeTaskID]?.cancel()
        }
        scheduleDeliveries()
    }

    func removeAllOwners() {
        for owner in owners.values {
            if let activeTaskID = owner.activeTaskID {
                activeDeliveryTasks[activeTaskID]?.cancel()
            }
        }
        owners.removeAll(keepingCapacity: false)
        ownerOrder.removeAll(keepingCapacity: false)
    }

    func submitTermination(
        _ callback: (@Sendable (Error) async -> Void)?,
        error: Error
    ) {
        guard let callback = callback else {
            return
        }
        guard pendingTerminations.count < maximumPendingTerminations else {
            droppedTerminationCount += 1
            return
        }
        pendingTerminations.append(TerminationWork(callback: callback, error: error))
        scheduleTerminations()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            ownerCount: owners.count,
            bufferedDeliveryCount: owners.values.reduce(0) { $0 + $1.buffer.count },
            activeDeliveryTaskCount: activeDeliveryTasks.count,
            activeTerminationTaskCount: activeTerminationTasks.count,
            pendingTerminationCount: pendingTerminations.count,
            droppedTerminationCount: droppedTerminationCount
        )
    }

    private func scheduleDeliveries() {
        while activeDeliveryTasks.count < maximumConcurrentDeliveryTasks {
            guard
                let ownerID = ownerOrder.first(where: { ownerID in
                    guard let owner = owners[ownerID] else { return false }
                    return owner.activeTaskID == nil && !owner.buffer.isEmpty
                }),
                var owner = owners[ownerID]
            else {
                return
            }

            let value = owner.buffer.removeFirst()
            let callback = owner.callback
            let taskID = UUID()
            owner.activeTaskID = taskID
            owners[ownerID] = owner
            let coordinator = self
            activeDeliveryTasks[taskID] = Task.detached {
                await callback(value)
                await coordinator.deliveryCompleted(ownerID: ownerID, taskID: taskID)
            }
        }
    }

    private func deliveryCompleted(ownerID: UUID, taskID: UUID) {
        activeDeliveryTasks.removeValue(forKey: taskID)
        if var owner = owners[ownerID], owner.activeTaskID == taskID {
            owner.activeTaskID = nil
            owners[ownerID] = owner
        }
        scheduleDeliveries()
    }

    private func scheduleTerminations() {
        let maximumConcurrentTerminationTasks = 1
        while
            activeTerminationTasks.count < maximumConcurrentTerminationTasks,
            !pendingTerminations.isEmpty
        {
            let work = pendingTerminations.removeFirst()
            let taskID = UUID()
            let coordinator = self
            activeTerminationTasks[taskID] = Task.detached {
                await work.callback(work.error)
                await coordinator.terminationCompleted(taskID: taskID)
            }
        }
    }

    private func terminationCompleted(taskID: UUID) {
        activeTerminationTasks.removeValue(forKey: taskID)
        scheduleTerminations()
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}
