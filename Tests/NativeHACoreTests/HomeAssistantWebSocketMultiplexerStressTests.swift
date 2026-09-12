import XCTest
@testable import NativeHACore

final class HomeAssistantWebSocketMultiplexerStressTests: XCTestCase {
    func testTenThousandInterleavedMessagesAcrossTwoHundredFiftyOwners() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([transport])
        let connection = makeConnection(factory: factory, deliveryCapacity: 256)
        try await connection.connect()

        let deliveryLog = IntegerDeliveryLog()
        var subscriptions: [HAWebSocketSubscription] = []
        var subscriptionIDs: [Int] = []
        for subscriptionIndex in 0..<250 {
            let subscription = try await connection.subscribeRaw([
                "type": .string("subscribe_events"),
                "event_type": .string("stress_\(subscriptionIndex)"),
            ]) { payload in
                guard
                    case let .object(object) = payload,
                    let value = object["value"]?.testInt
                else {
                    return
                }
                await deliveryLog.append(subscription: subscriptionIndex, value: value)
            }
            subscriptions.append(subscription)
            subscriptionIDs.append(subscription.id)
        }

        let commandTasks: [Task<JSONValue, Error>] = (0..<250).map { commandIndex in
            Task {
                try await connection.callRaw([
                    "type": .string("stress/command"),
                    "index": .int(commandIndex),
                ])
            }
        }
        try await waitUntil {
            let sent = await transport.sentObjects()
            return sent.filter { $0["type"] == .string("stress/command") }.count == 250
        }
        let sentCommands = await transport.sentObjects()
            .filter { $0["type"] == .string("stress/command") }
        let commandPairs: [(Int, Int)] = sentCommands.compactMap { message in
            guard
                let index = message["index"]?.testInt,
                let id = message["id"]?.testInt
            else {
                return nil
            }
            return (index, id)
        }
        let commandIDsByIndex = Dictionary(uniqueKeysWithValues: commandPairs)
        XCTAssertEqual(commandIDsByIndex.count, 250)

        var script: [[String: JSONValue]] = []
        script.reserveCapacity(10_000)
        var expectedChecksum = 0
        var nextCommandResult = 0
        for sequence in 0..<39 {
            for subscriptionIndex in 0..<250 {
                let value = subscriptionIndex * 1_000 + sequence
                expectedChecksum += value
                script.append([
                    "id": .int(subscriptionIDs[subscriptionIndex]),
                    "type": .string("event"),
                    "event": .object(["value": .int(value)]),
                ])
            }

            let resultCount = sequence < 16 ? 7 : 6
            for _ in 0..<resultCount where nextCommandResult < 250 {
                let index = nextCommandResult
                script.append([
                    "id": .int(try XCTUnwrap(commandIDsByIndex[index])),
                    "type": .string("result"),
                    "success": .bool(true),
                    "result": .int(index),
                ])
                nextCommandResult += 1
            }
        }
        while nextCommandResult < 250 {
            let index = nextCommandResult
            script.append([
                "id": .int(try XCTUnwrap(commandIDsByIndex[index])),
                "type": .string("result"),
                "success": .bool(true),
                "result": .int(index),
            ])
            nextCommandResult += 1
        }
        XCTAssertEqual(script.count, 10_000)

        try await transport.pushGroup(script)
        for (index, task) in commandTasks.enumerated() {
            let value = try await task.value
            XCTAssertEqual(value, .int(index))
        }
        try await waitUntil(iterations: 500_000) {
            await deliveryLog.count() == 9_750
        }
        let deliveryCount = await deliveryLog.count()
        let checksum = await deliveryLog.checksum()
        XCTAssertEqual(deliveryCount, 9_750)
        XCTAssertEqual(checksum, expectedChecksum)
        for subscriptionIndex in 0..<250 {
            let values = await deliveryLog.values(for: subscriptionIndex)
            XCTAssertEqual(values.count, 39)
            XCTAssertEqual(values, (0..<39).map { subscriptionIndex * 1_000 + $0 })
        }

        for subscription in subscriptions {
            await subscription.cancel()
        }
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.pendingCommandCount, 0)
        XCTAssertEqual(snapshot.subscriptionCount, 0)
        XCTAssertEqual(snapshot.wireSubscriptionCount, 0)
        await connection.disconnect()
        let finalSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(finalSnapshot.receiveLoopCount, 0)
        let finalMetrics = await awaitMetrics(transport)
        XCTAssertEqual(finalMetrics.activeReceives, 0)
    }

    func testStalledSubscriberUsesBoundedOverflowWithoutBlockingOtherOwners() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([transport])
        let connection = makeConnection(factory: factory, deliveryCapacity: 5)
        try await connection.connect()

        let gate = AsyncTestGate()
        let terminationGate = AsyncTestGate()
        let slowLog = JSONValueLog()
        let fastLog = JSONValueLog()
        let terminationLog = WebSocketErrorLog()
        let slowEventType = "slow-\(UUID())"
        let slow = try await connection.subscribeRaw([
            "type": .string("subscribe_events"),
            "event_type": .string(slowEventType),
        ], onTermination: { error in
            await terminationLog.append(error)
            await terminationGate.wait()
        }) { value in
            await slowLog.append(value)
            await gate.wait()
        }
        let fast = try await connection.subscribeRaw([
            "type": .string("subscribe_events"),
            "event_type": .string("fast"),
        ]) { value in
            await fastLog.append(value)
        }

        try await transport.push([
            "id": .int(slow.id),
            "type": .string("event"),
            "event": .int(0),
        ])
        try await waitUntil(iterations: 500_000) { await gate.waitingCount() == 1 }

        let command = Task {
            try await connection.callRaw(["type": .string("stress/not-blocked")])
        }
        try await waitUntil(iterations: 500_000) {
            await transport.sentObjects().contains { $0["type"] == .string("stress/not-blocked") }
        }
        let sent = await transport.sentObjects()
        let commandMessage = try XCTUnwrap(sent.first { $0["type"] == .string("stress/not-blocked") })
        let commandID = try XCTUnwrap(commandMessage["id"]?.testInt)

        var messages: [[String: JSONValue]] = []
        for sequence in 1...6 {
            messages.append([
                "id": .int(slow.id),
                "type": .string("event"),
                "event": .int(sequence),
            ])
            if sequence <= 5 {
                messages.append([
                    "id": .int(fast.id),
                    "type": .string("event"),
                    "event": .int(sequence),
                ])
            }
        }
        messages.append([
            "id": .int(commandID),
            "type": .string("result"),
            "success": .bool(true),
            "result": .string("still-routed"),
        ])
        try await transport.pushGroup(messages)

        let commandResult = try await command.value
        XCTAssertEqual(commandResult, .string("still-routed"))
        try await waitUntil(iterations: 500_000) { await fastLog.snapshot().count == 5 }
        let fastValues = await fastLog.snapshot()
        XCTAssertEqual(fastValues, (1...5).map(JSONValue.int))
        try await waitUntil(iterations: 500_000) {
            await connection.debugSnapshot().subscriptionCount == 1
        }
        // Registry removal precedes the independently scheduled callback.
        // Wait for its existing gate before inspecting termination side effects.
        try await waitUntil { await terminationGate.waitingCount() == 1 }
        let overflowSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(overflowSnapshot.pendingCommandCount, 0)
        XCTAssertEqual(overflowSnapshot.subscriptionCount, 1)
        XCTAssertEqual(overflowSnapshot.wireSubscriptionCount, 1)
        let terminations = await terminationLog.snapshot()
        XCTAssertEqual(terminations, [.deliveryOverflow(subscriptionID: slow.id)])
        XCTAssertEqual(overflowSnapshot.activeTerminationTaskCount, 1)
        XCTAssertEqual(overflowSnapshot.pendingTerminationCount, 0)
        let overflowDiagnostics = try persistedDiagnosticMessages(containing: slowEventType)
            .filter { $0.contains("subscription overflow") }
        XCTAssertEqual(overflowDiagnostics.count, 1)
        XCTAssertTrue(overflowDiagnostics.first?.contains("capacity=5") == true)

        await gate.open()
        await terminationGate.open()
        try await waitUntil {
            await connection.debugSnapshot().activeTerminationTaskCount == 0
        }
        await slow.cancel()
        await fast.cancel()
        await connection.disconnect()
        let finalSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(finalSnapshot.pendingCommandCount, 0)
        XCTAssertEqual(finalSnapshot.subscriptionCount, 0)
        XCTAssertEqual(finalSnapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(finalSnapshot.receiveLoopCount, 0)
    }

    func testOneHundredReconnectCyclesRetainOneReceiverAndEndWithZeroStorage() async throws {
        let transports = (0...100).map { _ in
            ScriptedWebSocketTransport(
                automaticAuthentication: true,
                automaticSubscriptionAcknowledgement: true
            )
        }
        let factory = ScriptedTransportFactory(transports)
        let connection = makeConnection(factory: factory, deliveryCapacity: 16)
        try await connection.connect()
        let subscription = try await connection.subscribeRaw([
            "type": .string("subscribe_events"),
            "event_type": .string("state_changed"),
        ]) { _ in }

        for cycle in 0..<100 {
            await transports[cycle].pushFailure()
            try await waitUntil(iterations: 100_000) {
                guard factory.count() == cycle + 2 else { return false }
                return await connection.debugSnapshot().state == .ready
            }
            let snapshot = await connection.debugSnapshot()
            XCTAssertEqual(snapshot.subscriptionCount, 1)
            XCTAssertEqual(snapshot.wireSubscriptionCount, 1)
            XCTAssertEqual(snapshot.receiveLoopCount, 1)
        }

        for transport in transports {
            let metrics = await transport.metrics()
            XCTAssertLessThanOrEqual(metrics.maximumConcurrentReceives, 1)
        }

        await subscription.cancel()
        await connection.disconnect()
        let finalSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(finalSnapshot.pendingCommandCount, 0)
        XCTAssertEqual(finalSnapshot.subscriptionCount, 0)
        XCTAssertEqual(finalSnapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(finalSnapshot.receiveLoopCount, 0)
        for transport in transports {
            let metrics = await transport.metrics()
            XCTAssertEqual(metrics.activeReceives, 0)
        }
    }

    func testEightNonReturningOwnersRemainObservableAndGloballyBoundedAcrossCancellation() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([transport])
        let connection = makeConnection(
            factory: factory,
            deliveryCapacity: 4,
            maximumConcurrentCallbackTasks: 4
        )
        try await connection.connect()

        let gate = AsyncTestGate()
        var firstWave: [(HAWebSocketSubscription, WeakRetentionPayloadBox)] = []
        for owner in 0..<8 {
            firstWave.append(try await makeRetainingOwner(
                owner: owner,
                connection: connection,
                gate: gate
            ))
        }
        for (subscription, _) in firstWave {
            try await transport.push([
                "id": .int(subscription.id),
                "type": .string("event"),
                "event": .int(subscription.id),
            ])
        }
        try await waitUntil { await gate.waitingCount() == 4 }

        for (subscription, _) in firstWave {
            await subscription.cancel()
        }
        let firstCancellation = await connection.debugSnapshot()
        XCTAssertEqual(firstCancellation.subscriptionCount, 0)
        XCTAssertEqual(firstCancellation.deliveryOwnerCount, 0)
        XCTAssertEqual(firstCancellation.bufferedDeliveryCount, 0)
        XCTAssertEqual(firstCancellation.activeDeliveryTaskCount, 4)
        XCTAssertEqual(firstWave.filter { $0.1.value != nil }.count, 4)

        var secondWave: [(HAWebSocketSubscription, WeakRetentionPayloadBox)] = []
        for owner in 8..<16 {
            secondWave.append(try await makeRetainingOwner(
                owner: owner,
                connection: connection,
                gate: gate
            ))
        }
        for (subscription, _) in secondWave {
            try await transport.push([
                "id": .int(subscription.id),
                "type": .string("event"),
                "event": .int(subscription.id),
            ])
        }
        try await waitUntil {
            await connection.debugSnapshot().bufferedDeliveryCount == 8
        }
        let repeatedWaitingCount = await gate.waitingCount()
        XCTAssertEqual(repeatedWaitingCount, 4)
        for (subscription, _) in secondWave {
            await subscription.cancel()
        }

        let repeatedCancellation = await connection.debugSnapshot()
        XCTAssertEqual(repeatedCancellation.deliveryOwnerCount, 0)
        XCTAssertEqual(repeatedCancellation.bufferedDeliveryCount, 0)
        XCTAssertEqual(repeatedCancellation.activeDeliveryTaskCount, 4)
        XCTAssertEqual(secondWave.filter { $0.1.value != nil }.count, 0)
        XCTAssertEqual(firstWave.filter { $0.1.value != nil }.count, 4)

        await gate.open()
        try await waitUntil {
            await connection.debugSnapshot().activeDeliveryTaskCount == 0
        }
        XCTAssertEqual(firstWave.filter { $0.1.value != nil }.count, 0)
        await connection.disconnect()
    }

    private func makeConnection(
        factory: ScriptedTransportFactory,
        deliveryCapacity: Int,
        maximumConcurrentCallbackTasks: Int = 4
    ) -> HomeAssistantWebSocketConnection {
        HomeAssistantWebSocketConnection(
            accessToken: "stress-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            deliveryCapacity: deliveryCapacity,
            maximumConcurrentCallbackTasks: maximumConcurrentCallbackTasks,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: factory.make
        )
    }

    private func makeRetainingOwner(
        owner: Int,
        connection: HomeAssistantWebSocketConnection,
        gate: AsyncTestGate
    ) async throws -> (HAWebSocketSubscription, WeakRetentionPayloadBox) {
        let payload = RetentionPayload(owner: owner)
        let weakBox = WeakRetentionPayloadBox(payload)
        let subscription = try await connection.subscribeRaw([
            "type": .string("subscribe_events"),
            "event_type": .string("retention_\(owner)"),
        ]) { _ in
            _ = payload.bytes.count
            await gate.wait()
        }
        return (subscription, weakBox)
    }

    private func awaitMetrics(
        _ transport: ScriptedWebSocketTransport
    ) async -> (receiveCalls: Int, maximumConcurrentReceives: Int, activeReceives: Int, disconnectCalls: Int) {
        await transport.metrics()
    }
}

private final class RetentionPayload {
    let bytes: [UInt8]

    init(owner: Int) {
        bytes = [UInt8](repeating: UInt8(owner), count: 2 * 1_024 * 1_024)
    }
}

private final class WeakRetentionPayloadBox {
    weak var value: RetentionPayload?

    init(_ value: RetentionPayload) {
        self.value = value
    }
}
