import Foundation

public enum HAWebSocketFrame {
    case string(String)
    case data(Data)
}

public protocol HomeAssistantWebSocketTransport: AnyObject {
    func connect() async throws
    func send(_ frame: HAWebSocketFrame) async throws
    func receive() async throws -> HAWebSocketFrame
    func disconnect() async
}

protocol URLSessionWebSocketTaskAdapter: AnyObject {
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
    private let lock = NSLock()
    private var task: URLSessionWebSocketTaskAdapter?
    private var pendingReceive: PendingReceive?

    init(url: URL, session: URLSession) {
        taskFactory = { session.webSocketTask(with: url) }
    }

    init(taskFactory: @escaping () -> URLSessionWebSocketTaskAdapter) {
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
