import Foundation

public enum HAWebSocketFrame {
    case string(String)
    case data(Data)
}

public struct HomeAssistantWebSocketReceivePolicy: Equatable {
    public let maximumMessageBytes: Int

    public init(maximumMessageBytes: Int) {
        precondition(maximumMessageBytes > 0, "WebSocket receive size must be positive")
        self.maximumMessageBytes = maximumMessageBytes
    }

    public static let platformDefault = HomeAssistantWebSocketReceivePolicy(
        maximumMessageBytes: 1_048_576
    )
}

public protocol HomeAssistantWebSocketTransport: AnyObject {
    func connect() async throws
    func send(_ frame: HAWebSocketFrame) async throws
    func receive() async throws -> HAWebSocketFrame
    func disconnect() async
}

final class HomeAssistantWebSocketSendTicket {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    func value() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let result = result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resolve(with result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

/// Browser WebSockets enqueue synchronously in the same JavaScript turn that
/// allocates a Home Assistant command ID. Native URLSession sends are async,
/// so preserve that wire-order guarantee explicitly before crossing `await`.
final class HomeAssistantWebSocketSendSerializer {
    private struct Request {
        let id: UUID
        let frame: HAWebSocketFrame
        let shouldSend: @Sendable () async -> Bool
        let ticket: HomeAssistantWebSocketSendTicket
    }

    private struct Payload {
        let transport: HomeAssistantWebSocketTransport
        let frame: HAWebSocketFrame
    }

    private let transport: HomeAssistantWebSocketTransport
    private let lock = NSLock()
    private var queued: [Request] = []
    private var active: Request?
    private var stoppedError: Error?

    init(transport: HomeAssistantWebSocketTransport) {
        self.transport = transport
    }

    func isFor(_ transport: HomeAssistantWebSocketTransport) -> Bool {
        self.transport === transport
    }

    /// This method is intentionally synchronous. The connection actor calls it
    /// immediately after allocating an ID, so queue insertion cannot be
    /// overtaken by actor reentrancy.
    func enqueue(
        _ frame: HAWebSocketFrame,
        shouldSend: @escaping @Sendable () async -> Bool
    ) -> HomeAssistantWebSocketSendTicket {
        let ticket = HomeAssistantWebSocketSendTicket()
        let request = Request(
            id: UUID(),
            frame: frame,
            shouldSend: shouldSend,
            ticket: ticket
        )

        lock.lock()
        if let stoppedError = stoppedError {
            lock.unlock()
            ticket.resolve(with: .failure(stoppedError))
            return ticket
        }
        queued.append(request)
        let next = takeNextLocked()
        lock.unlock()

        if let next = next {
            start(next)
        }
        return ticket
    }

    func stop(with error: Error = HomeAssistantWebSocketError.disconnected) {
        lock.lock()
        guard stoppedError == nil else {
            lock.unlock()
            return
        }
        stoppedError = error
        let abandoned = queued + (active.map { [$0] } ?? [])
        queued.removeAll(keepingCapacity: false)
        active = nil
        lock.unlock()

        for request in abandoned {
            request.ticket.resolve(with: .failure(error))
        }
    }

    private func takeNextLocked() -> Request? {
        guard active == nil, stoppedError == nil, !queued.isEmpty else {
            return nil
        }
        let next = queued.removeFirst()
        active = next
        return next
    }

    private func start(_ request: Request) {
        let requestID = request.id
        let shouldSend = request.shouldSend
        Task { [weak self] in
            guard await shouldSend() else {
                self?.complete(requestID, result: .success(()))
                return
            }
            guard let payload = self?.payload(for: requestID) else {
                return
            }
            do {
                try await payload.transport.send(payload.frame)
                self?.complete(requestID, result: .success(()))
            } catch {
                self?.complete(requestID, result: .failure(error))
            }
        }
    }

    private func payload(for requestID: UUID) -> Payload? {
        lock.lock()
        defer { lock.unlock() }
        guard let active = active, active.id == requestID, stoppedError == nil else {
            return nil
        }
        return Payload(transport: transport, frame: active.frame)
    }

    private func complete(_ requestID: UUID, result: Result<Void, Error>) {
        lock.lock()
        guard let request = active, request.id == requestID else {
            lock.unlock()
            return
        }
        active = nil
        var abandoned: [Request] = []
        if case let .failure(error) = result, stoppedError == nil {
            stoppedError = error
            abandoned = queued
            queued.removeAll(keepingCapacity: false)
        }
        let next = takeNextLocked()
        lock.unlock()

        request.ticket.resolve(with: result)
        if case let .failure(error) = result {
            for pending in abandoned {
                pending.ticket.resolve(with: .failure(error))
            }
        }
        if let next = next {
            start(next)
        }
    }
}

protocol URLSessionWebSocketTaskAdapter: AnyObject {
    var maximumMessageSize: Int { get set }

    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(
        _ message: URLSessionWebSocketTask.Message,
        completionHandler: @escaping (Error?) -> Void
    )
    func receive(
        completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    )
}

extension URLSessionWebSocketTask: URLSessionWebSocketTaskAdapter {}

final class URLSessionHomeAssistantWebSocketTransport: HomeAssistantWebSocketTransport {
    private struct PendingReceive {
        let id: UUID
        let continuation: CheckedContinuation<HAWebSocketFrame, Error>
    }

    private let taskFactory: () -> URLSessionWebSocketTaskAdapter
    private let receivePolicy: HomeAssistantWebSocketReceivePolicy
    private let lock = NSLock()
    private var task: URLSessionWebSocketTaskAdapter?
    private var pendingReceive: PendingReceive?

    init(
        url: URL,
        session: URLSession,
        receivePolicy: HomeAssistantWebSocketReceivePolicy = .platformDefault
    ) {
        self.receivePolicy = receivePolicy
        taskFactory = { session.webSocketTask(with: url) }
    }

    init(
        receivePolicy: HomeAssistantWebSocketReceivePolicy = .platformDefault,
        taskFactory: @escaping () -> URLSessionWebSocketTaskAdapter
    ) {
        self.receivePolicy = receivePolicy
        self.taskFactory = taskFactory
    }

    deinit {
        let cleanup = takeCleanupState()
        cleanup.task?.cancel(with: .goingAway, reason: nil)
        cleanup.receive?.continuation.resume(throwing: HomeAssistantWebSocketError.disconnected)
    }

    func connect() async throws {
        lock.lock()
        guard task == nil else {
            lock.unlock()
            return
        }
        let task = taskFactory()
        task.maximumMessageSize = receivePolicy.maximumMessageBytes
        self.task = task
        task.resume()
        lock.unlock()
    }

    func send(_ frame: HAWebSocketFrame) async throws {
        lock.lock()
        let currentTask = task
        lock.unlock()
        guard let currentTask = currentTask else {
            throw HomeAssistantWebSocketError.disconnected
        }

        let message: URLSessionWebSocketTask.Message
        switch frame {
        case let .string(value):
            message = .string(value)
        case let .data(value):
            message = .data(value)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            currentTask.send(message) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func receive() async throws -> HAWebSocketFrame {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<HAWebSocketFrame, Error>) in
            let receiveID = UUID()

            lock.lock()
            guard let currentTask = task else {
                lock.unlock()
                continuation.resume(throwing: HomeAssistantWebSocketError.disconnected)
                return
            }
            guard pendingReceive == nil else {
                lock.unlock()
                continuation.resume(throwing: HomeAssistantWebSocketError.invalidMessage)
                return
            }
            pendingReceive = PendingReceive(id: receiveID, continuation: continuation)
            lock.unlock()

            currentTask.receive { [weak self] result in
                self?.completeReceive(id: receiveID, result: result)
            }
        }
    }

    func disconnect() async {
        let cleanup = takeCleanupState()
        cleanup.task?.cancel(with: .goingAway, reason: nil)
        cleanup.receive?.continuation.resume(throwing: HomeAssistantWebSocketError.disconnected)
    }

    func debugPendingReceiveCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingReceive == nil ? 0 : 1
    }

    private func completeReceive(
        id: UUID,
        result: Result<URLSessionWebSocketTask.Message, Error>
    ) {
        lock.lock()
        guard let pendingReceive = pendingReceive, pendingReceive.id == id else {
            lock.unlock()
            return
        }
        self.pendingReceive = nil
        lock.unlock()

        switch result {
        case let .success(.string(value)):
            pendingReceive.continuation.resume(returning: .string(value))
        case let .success(.data(value)):
            pendingReceive.continuation.resume(returning: .data(value))
        case let .failure(error):
            pendingReceive.continuation.resume(throwing: error)
        @unknown default:
            pendingReceive.continuation.resume(throwing: HomeAssistantWebSocketError.invalidMessage)
        }
    }

    private func takeCleanupState() -> (
        task: URLSessionWebSocketTaskAdapter?,
        receive: PendingReceive?
    ) {
        lock.lock()
        let cleanup = (task, pendingReceive)
        task = nil
        pendingReceive = nil
        lock.unlock()
        return cleanup
    }
}
