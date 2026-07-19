import Foundation
import XCTest
@testable import NativeHACore

final class URLSessionHomeAssistantWebSocketTransportTests: XCTestCase {
    func testReceivePolicyIsAppliedBeforeResumeAndAcceptsFrameAbovePlatformDefault() throws {
        let rawTask = NonCompletingURLSessionWebSocketTask()
        let receiveRegistered = expectation(description: "raw receive registered")
        rawTask.onReceiveRegistered = { receiveRegistered.fulfill() }
        let receivePolicy = HomeAssistantWebSocketReceivePolicy(
            maximumMessageBytes: 2 * 1_024 * 1_024
        )
        let transport = URLSessionHomeAssistantWebSocketTransport(
            receivePolicy: receivePolicy,
            taskFactory: { rawTask }
        )

        let connected = expectation(description: "transport connected")
        Task {
            try? await transport.connect()
            connected.fulfill()
        }
        wait(for: [connected], timeout: 1)
        XCTAssertEqual(rawTask.maximumMessageSizeAtResume, receivePolicy.maximumMessageBytes)

        let receiveCompleted = expectation(description: "large receive completed")
        let receivedSize = LockedIntBox()
        Task {
            if case let .string(value)? = try? await transport.receive() {
                receivedSize.set(value.utf8.count)
            }
            receiveCompleted.fulfill()
        }
        wait(for: [receiveRegistered], timeout: 1)

        let payloadSize = HomeAssistantWebSocketReceivePolicy.platformDefault.maximumMessageBytes + 1
        rawTask.completeLate(with: .success(.string(String(repeating: "x", count: payloadSize))))
        wait(for: [receiveCompleted], timeout: 2)
        XCTAssertEqual(receivedSize.get(), payloadSize)
        XCTAssertEqual(transport.debugPendingReceiveCount(), 0)

        let disconnected = expectation(description: "transport disconnected")
        Task {
            await transport.disconnect()
            await transport.disconnect()
            disconnected.fulfill()
        }
        wait(for: [disconnected], timeout: 1)
        XCTAssertEqual(rawTask.cancelCount, 1)
        XCTAssertEqual(transport.debugPendingReceiveCount(), 0)
    }

    func testDisconnectExactlyOnceResumesPendingProductionAdapterReceive() {
        let rawTask = NonCompletingURLSessionWebSocketTask()
        let receiveRegistered = expectation(description: "raw receive registered")
        rawTask.onReceiveRegistered = {
            receiveRegistered.fulfill()
        }
        let transport = URLSessionHomeAssistantWebSocketTransport {
            rawTask
        }

        let connected = expectation(description: "transport connected")
        Task {
            try? await transport.connect()
            connected.fulfill()
        }
        wait(for: [connected], timeout: 1)

        let receiveCompleted = expectation(description: "pending receive resumed")
        let receiveError = LockedErrorBox()
        Task {
            do {
                _ = try await transport.receive()
            } catch {
                receiveError.set(error)
            }
            receiveCompleted.fulfill()
        }
        wait(for: [receiveRegistered], timeout: 1)
        XCTAssertEqual(transport.debugPendingReceiveCount(), 1)

        let disconnected = expectation(description: "transport disconnected")
        Task {
            await transport.disconnect()
            await transport.disconnect()
            disconnected.fulfill()
        }
        wait(for: [disconnected, receiveCompleted], timeout: 1)

        let capturedError = receiveError.get()
        XCTAssertEqual(capturedError as? HomeAssistantWebSocketError, .disconnected)
        XCTAssertEqual(transport.debugPendingReceiveCount(), 0)
        XCTAssertEqual(rawTask.cancelCount, 1)

        rawTask.completeLate(with: .success(.string("late")))
        XCTAssertEqual(transport.debugPendingReceiveCount(), 0)
    }
}

private final class LockedErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: Error?

    func set(_ error: Error) {
        lock.lock()
        self.error = error
        lock.unlock()
    }

    func get() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}

private final class LockedIntBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int?

    func set(_ value: Int) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class NonCompletingURLSessionWebSocketTask: URLSessionWebSocketTaskAdapter {
    private let lock = NSLock()
    private var receiveCompletion: ((Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
    private(set) var cancelCount = 0
    private(set) var maximumMessageSizeAtResume: Int?
    var maximumMessageSize = HomeAssistantWebSocketReceivePolicy.platformDefault.maximumMessageBytes
    var onReceiveRegistered: (() -> Void)?

    func resume() {
        lock.lock()
        maximumMessageSizeAtResume = maximumMessageSize
        lock.unlock()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.lock()
        cancelCount += 1
        lock.unlock()
    }

    func send(
        _ message: URLSessionWebSocketTask.Message,
        completionHandler: @escaping (Error?) -> Void
    ) {
        completionHandler(nil)
    }

    func receive(
        completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    ) {
        lock.lock()
        receiveCompletion = completionHandler
        let callback = onReceiveRegistered
        lock.unlock()
        callback?()
    }

    func completeLate(with result: Result<URLSessionWebSocketTask.Message, Error>) {
        lock.lock()
        let completion = receiveCompletion
        receiveCompletion = nil
        lock.unlock()
        completion?(result)
    }
}
