import Foundation
import XCTest
@testable import NativeHACore

final class HomeAssistantWebSocketPerformanceTests: XCTestCase {
    func testWarmPredecodedDispatchMetrics() {
        guard let fixture = makeDispatchFixtureForMeasurement() else { return }
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        // Warm the actual event-routing and callback-delivery path once outside
        // XCTest's measured region, then discard all warm-up output.
        runMeasuredAsync {
            try await fixture.runPredecodedIteration()
            await fixture.accumulator.reset()
            try await fixture.requireIdleDelivery()
        }

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            runMeasuredAsync {
                try await fixture.runPredecodedIteration()
            }
        }

        runMeasuredAsync { await fixture.cancelAndDisconnect() }
    }

    func testDecodeAndDispatchMetrics() {
        guard let fixture = makeDispatchFixtureForMeasurement() else { return }
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            runMeasuredAsync {
                try await fixture.runDecodeAndDispatchIteration()
            }
        }

        runMeasuredAsync { await fixture.cancelAndDisconnect() }
    }

    func testRepeatedLifecycleMetrics() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            runMeasuredAsync {
                let transports = (0...10).map { _ in
                    ScriptedWebSocketTransport(
                        automaticAuthentication: true,
                        automaticSubscriptionAcknowledgement: true
                    )
                }
                let factory = ScriptedTransportFactory(transports)
                let connection = HomeAssistantWebSocketConnection(
                    accessToken: "performance-token",
                    commandTimeoutNanoseconds: 5_000_000_000,
                    deliveryCapacity: 64,
                    maximumConcurrentCallbackTasks: 4,
                    reconnectDelayNanoseconds: { _ in 0 },
                    transportFactory: factory.make
                )
                try await connection.connect()

                for cycle in 0..<10 {
                    let subscription = try await connection.subscribeRaw([
                        "type": .string("subscribe_events"),
                        "event_type": .string("performance_lifecycle_\(cycle)"),
                    ]) { _ in }
                    try await Self.requireOwnership(
                        connection,
                        subscriptions: 1,
                        wireSubscriptions: 1,
                        deliveryOwners: 1,
                        receiveLoops: 1
                    )
                    await subscription.cancel()
                    try await Self.requireOwnership(
                        connection,
                        subscriptions: 0,
                        wireSubscriptions: 0,
                        deliveryOwners: 0,
                        receiveLoops: 1
                    )

                    await transports[cycle].pushFailure()
                    try await waitUntil(iterations: 1_000_000) {
                        guard factory.count() == cycle + 2 else { return false }
                        return await connection.debugSnapshot().state == .ready
                    }
                    try await Self.requireOwnership(
                        connection,
                        subscriptions: 0,
                        wireSubscriptions: 0,
                        deliveryOwners: 0,
                        receiveLoops: 1
                    )
                }

                await connection.disconnect()
                try await Self.requireOwnership(
                    connection,
                    subscriptions: 0,
                    wireSubscriptions: 0,
                    deliveryOwners: 0,
                    receiveLoops: 0
                )
            }
        }
    }

    private func makeDispatchFixtureForMeasurement() -> WebSocketDispatchPerformanceFixture? {
        let fixtureBox = LockedPerformanceFixtureBox()
        runMeasuredAsync {
            fixtureBox.set(try await Self.makeDispatchFixture())
        }
        guard let fixture = fixtureBox.get() else {
            XCTFail("Failed to construct dispatch performance fixture")
            return nil
        }
        return fixture
    }

    private static func makeDispatchFixture() async throws -> WebSocketDispatchPerformanceFixture {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([transport])
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "performance-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            deliveryCapacity: 64,
            maximumConcurrentCallbackTasks: 4,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: factory.make
        )
        try await connection.connect()

        let accumulator = PerformanceDeliveryAccumulator()
        var subscriptions: [HAWebSocketSubscription] = []
        for owner in 0..<250 {
            let subscription = try await connection.subscribeRaw([
                "type": .string("subscribe_events"),
                "event_type": .string("performance_\(owner)"),
            ]) { payload in
                guard
                    case let .object(object) = payload,
                    let value = object["value"]?.testInt
                else {
                    return
                }
                await accumulator.append(value)
            }
            subscriptions.append(subscription)
        }

        var messages: [JSONValue] = []
        messages.reserveCapacity(10_000)
        var expectedChecksum = 0
        for sequence in 0..<40 {
            for (owner, subscription) in subscriptions.enumerated() {
                let value = owner * 1_000 + sequence
                expectedChecksum += value
                messages.append(.object([
                    "id": .int(subscription.id),
                    "type": .string("event"),
                    "event": .object(["value": .int(value)]),
                ]))
            }
        }
        let data = try JSONEncoder().encode(JSONValue.array(messages))
        let frame = HAWebSocketFrame.string(String(decoding: data, as: UTF8.self))

        return WebSocketDispatchPerformanceFixture(
            connection: connection,
            subscriptions: subscriptions,
            accumulator: accumulator,
            messages: messages,
            frame: frame,
            expectedChecksum: expectedChecksum
        )
    }

    private static func requireOwnership(
        _ connection: HomeAssistantWebSocketConnection,
        subscriptions: Int,
        wireSubscriptions: Int,
        deliveryOwners: Int,
        receiveLoops: Int
    ) async throws {
        let snapshot = await connection.debugSnapshot()
        guard
            snapshot.pendingCommandCount == 0,
            snapshot.subscriptionCount == subscriptions,
            snapshot.wireSubscriptionCount == wireSubscriptions,
            snapshot.receiveLoopCount == receiveLoops,
            snapshot.deliveryOwnerCount == deliveryOwners,
            snapshot.bufferedDeliveryCount == 0,
            snapshot.activeDeliveryTaskCount == 0,
            snapshot.activeTerminationTaskCount == 0,
            snapshot.pendingTerminationCount == 0,
            snapshot.droppedTerminationCount == 0
        else {
            throw WebSocketPerformanceError.lifecycleStorageMismatch
        }
    }

    private func runMeasuredAsync(
        timeout: TimeInterval = 30,
        _ operation: @escaping @Sendable () async throws -> Void
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = LockedPerformanceErrorBox()
        Task.detached {
            do {
                try await operation()
            } catch {
                errorBox.set(error)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            XCTFail("Measured async operation timed out after \(timeout) seconds")
        } else if let error = errorBox.get() {
            XCTFail("Measured async operation failed: \(error)")
        }
    }
}

private final class WebSocketDispatchPerformanceFixture: @unchecked Sendable {
    let connection: HomeAssistantWebSocketConnection
    let subscriptions: [HAWebSocketSubscription]
    let accumulator: PerformanceDeliveryAccumulator
    let messages: [JSONValue]
    let frame: HAWebSocketFrame
    let expectedChecksum: Int

    init(
        connection: HomeAssistantWebSocketConnection,
        subscriptions: [HAWebSocketSubscription],
        accumulator: PerformanceDeliveryAccumulator,
        messages: [JSONValue],
        frame: HAWebSocketFrame,
        expectedChecksum: Int
    ) {
        self.connection = connection
        self.subscriptions = subscriptions
        self.accumulator = accumulator
        self.messages = messages
        self.frame = frame
        self.expectedChecksum = expectedChecksum
    }

    func runPredecodedIteration() async throws {
        await accumulator.reset()
        try await connection.dispatchPredecodedMessages(messages)
        try await requireCompleteIteration()
    }

    func runDecodeAndDispatchIteration() async throws {
        await accumulator.reset()
        try await connection.decodeAndDispatchFrame(frame)
        try await requireCompleteIteration()
    }

    func requireIdleDelivery() async throws {
        try await waitUntil(iterations: 1_000_000) {
            let snapshot = await self.connection.debugSnapshot()
            return snapshot.bufferedDeliveryCount == 0 &&
                snapshot.activeDeliveryTaskCount == 0
        }
    }

    private func requireCompleteIteration() async throws {
        try await waitUntil(iterations: 1_000_000) {
            (await self.accumulator.snapshot()).count >= self.messages.count
        }
        let result = await accumulator.snapshot()
        guard result.count == messages.count, result.checksum == expectedChecksum else {
            throw WebSocketPerformanceError.deliveryMismatch(
                count: result.count,
                checksum: result.checksum
            )
        }
        try await requireIdleDelivery()
    }

    func cancelAndDisconnect() async {
        for subscription in subscriptions {
            await subscription.cancel()
        }
        await connection.disconnect()
    }
}

private actor PerformanceDeliveryAccumulator {
    private var count = 0
    private var checksum = 0

    func append(_ value: Int) {
        count += 1
        checksum += value
    }

    func reset() {
        count = 0
        checksum = 0
    }

    func snapshot() -> (count: Int, checksum: Int) {
        (count, checksum)
    }
}

private final class LockedPerformanceErrorBox: @unchecked Sendable {
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

private final class LockedPerformanceFixtureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var fixture: WebSocketDispatchPerformanceFixture?

    func set(_ fixture: WebSocketDispatchPerformanceFixture) {
        lock.lock()
        self.fixture = fixture
        lock.unlock()
    }

    func get() -> WebSocketDispatchPerformanceFixture? {
        lock.lock()
        defer { lock.unlock() }
        return fixture
    }
}

private enum WebSocketPerformanceError: Error {
    case deliveryMismatch(count: Int, checksum: Int)
    case lifecycleStorageMismatch
}
