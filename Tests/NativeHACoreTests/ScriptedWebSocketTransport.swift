import Foundation
@testable import NativeHACore

enum ScriptedTransportError: Error {
    case injectedFailure
    case exhaustedFactory
}

actor ScriptedWebSocketTransport: HomeAssistantWebSocketTransport {
    private var inbound: [Result<HAWebSocketFrame, Error>] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var sent: [[String: JSONValue]] = []
    private var connected = false
    private var activeReceives = 0
    private var maximumConcurrentReceives = 0
    private var receiveCalls = 0
    private var disconnectCalls = 0
    private var failNextSend = false

    let automaticAuthentication: Bool
    let automaticSubscriptionAcknowledgement: Bool
    let version: String

    init(
        automaticAuthentication: Bool = false,
        automaticSubscriptionAcknowledgement: Bool = false,
        version: String = "2025.7.0"
    ) {
        self.automaticAuthentication = automaticAuthentication
        self.automaticSubscriptionAcknowledgement = automaticSubscriptionAcknowledgement
        self.version = version
    }

    func connect() async throws {
        connected = true
        if automaticAuthentication {
            deliver(.success(try frame(for: ["type": .string("auth_required")])))
        }
    }

    func send(_ frame: HAWebSocketFrame) async throws {
        guard connected else {
            throw HomeAssistantWebSocketError.disconnected
        }
        if failNextSend {
            failNextSend = false
            throw ScriptedTransportError.injectedFailure
        }

        let object = try decodeObject(frame)
        sent.append(object)

        if automaticAuthentication, object["type"] == .string("auth") {
            deliver(.success(try self.frame(for: [
                "type": .string("auth_ok"),
                "ha_version": .string(version),
            ])))
        }

        if automaticSubscriptionAcknowledgement,
           let id = object["id"]?.testInt,
           ["subscribe_events", "history/stream", "weather/subscribe_forecast", "unsubscribe_events"]
               .contains(object["type"]?.testString ?? "")
        {
            deliver(.success(try self.frame(for: [
                "id": .int(id),
                "type": .string("result"),
                "success": .bool(true),
                "result": .null,
            ])))
        }
    }

    func receive() async throws -> HAWebSocketFrame {
        guard connected else {
            throw HomeAssistantWebSocketError.disconnected
        }
        precondition(receiver == nil, "The connection started more than one receive on one transport")
        receiveCalls += 1
        activeReceives += 1
        maximumConcurrentReceives = max(maximumConcurrentReceives, activeReceives)

        if !inbound.isEmpty {
            activeReceives -= 1
            return try inbound.removeFirst().get()
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<HAWebSocketFrame, Error>) in
            receiver = continuation
        }
    }

    func disconnect() async {
        disconnectCalls += 1
        connected = false
        if let receiver = receiver {
            self.receiver = nil
            activeReceives -= 1
            receiver.resume(throwing: HomeAssistantWebSocketError.disconnected)
        }
    }

    func push(_ object: [String: JSONValue]) throws {
        deliver(.success(try frame(for: object)))
    }

    func pushGroup(_ objects: [[String: JSONValue]]) throws {
        let data = try JSONEncoder().encode(JSONValue.array(objects.map(JSONValue.object)))
        deliver(.success(.string(String(decoding: data, as: UTF8.self))))
    }

    func pushMalformedJSON() {
        deliver(.success(.string("{not-json")))
    }

    func pushFailure(_ error: Error = ScriptedTransportError.injectedFailure) {
        deliver(.failure(error))
    }

    func arrangeNextSendFailure() {
        failNextSend = true
    }

    func sentObjects() -> [[String: JSONValue]] {
        sent
    }

    func metrics() -> (receiveCalls: Int, maximumConcurrentReceives: Int, activeReceives: Int, disconnectCalls: Int) {
        (receiveCalls, maximumConcurrentReceives, activeReceives, disconnectCalls)
    }

    private func deliver(_ result: Result<HAWebSocketFrame, Error>) {
        if let receiver = receiver {
            self.receiver = nil
            activeReceives -= 1
            receiver.resume(with: result)
        } else {
            inbound.append(result)
        }
    }

    private func frame(for object: [String: JSONValue]) throws -> HAWebSocketFrame {
        let data = try JSONEncoder().encode(JSONValue.object(object))
        return .string(String(decoding: data, as: UTF8.self))
    }

    private func decodeObject(_ frame: HAWebSocketFrame) throws -> [String: JSONValue] {
        let data: Data
        switch frame {
        case let .string(value):
            data = Data(value.utf8)
        case let .data(value):
            data = value
        }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case let .object(object) = value else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        return object
    }
}

final class ScriptedTransportFactory {
    private let lock = NSLock()
    private var transports: [ScriptedWebSocketTransport]
    private(set) var createdCount = 0

    init(_ transports: [ScriptedWebSocketTransport]) {
        self.transports = transports
    }

    func make() throws -> HomeAssistantWebSocketTransport {
        lock.lock()
        defer { lock.unlock() }
        guard !transports.isEmpty else {
            throw ScriptedTransportError.exhaustedFactory
        }
        createdCount += 1
        return transports.removeFirst()
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return createdCount
    }
}

actor JSONValueLog {
    private var values: [JSONValue] = []

    func append(_ value: JSONValue) {
        values.append(value)
    }

    func snapshot() -> [JSONValue] {
        values
    }
}

actor WebSocketErrorLog {
    private var errors: [HomeAssistantWebSocketError] = []

    func append(_ error: Error) {
        if let error = error as? HomeAssistantWebSocketError {
            errors.append(error)
        }
    }

    func snapshot() -> [HomeAssistantWebSocketError] {
        errors
    }
}

actor ConnectionStateLog {
    private var states: [HAWebSocketConnectionState] = []

    func append(_ state: HAWebSocketConnectionState) {
        states.append(state)
    }

    func readyCount() -> Int {
        states.filter { $0 == .ready }.count
    }

    func snapshot() -> [HAWebSocketConnectionState] {
        states
    }
}

actor IntegerDeliveryLog {
    private var valuesBySubscription: [Int: [Int]] = [:]

    func append(subscription: Int, value: Int) {
        valuesBySubscription[subscription, default: []].append(value)
    }

    func count() -> Int {
        valuesBySubscription.values.reduce(0) { $0 + $1.count }
    }

    func checksum() -> Int {
        valuesBySubscription.reduce(0) { partial, item in
            partial + item.value.reduce(0, +)
        }
    }

    func values(for subscription: Int) -> [Int] {
        valuesBySubscription[subscription] ?? []
    }
}

actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitingCount() -> Int {
        waiters.count
    }

    func open() {
        isOpen = true
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

enum AsyncTestWaitError: Error {
    case conditionNotMet
}

func waitUntil(
    iterations: Int = 50_000,
    _ condition: @escaping () async -> Bool
) async throws {
    for _ in 0..<iterations {
        if await condition() {
            return
        }
        await Task.yield()
    }
    throw AsyncTestWaitError.conditionNotMet
}

extension JSONValue {
    var testInt: Int? {
        if case let .int(value) = self { return value }
        return nil
    }

    var testString: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}
