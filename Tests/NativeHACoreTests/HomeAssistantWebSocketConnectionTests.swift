import XCTest
@testable import NativeHACore

final class HomeAssistantWebSocketConnectionTests: XCTestCase {
    func testAuthenticationWaitsForAuthRequiredAndStartsOneSteadyReceiver() async throws {
        let transport = ScriptedWebSocketTransport()
        let connection = makeConnection(transports: [transport])
        let connectTask = Task {
            try await connection.connect()
        }

        try await waitUntil {
            await transport.metrics().receiveCalls == 1
        }
        let initiallySent = await transport.sentObjects()
        XCTAssertTrue(initiallySent.isEmpty)

        try await transport.push(["type": .string("auth_required")])
        try await waitUntil {
            await transport.sentObjects().contains { $0["type"] == .string("auth") }
        }
        let authMessages = await transport.sentObjects()
        let auth = try XCTUnwrap(authMessages.first)
        XCTAssertEqual(auth["access_token"], .string("token-for-test"))
        XCTAssertNil(auth["id"])

        try await transport.push([
            "type": .string("auth_ok"),
            "ha_version": .string("2025.7.0"),
        ])
        try await connectTask.value

        let sent = await transport.sentObjects()
        let features = try XCTUnwrap(sent.first { $0["type"] == .string("supported_features") })
        XCTAssertEqual(features["id"], .int(1))
        XCTAssertEqual(features["features"], .object(["coalesce_messages": .int(1)]))
        try await waitUntil {
            await transport.metrics().activeReceives == 1
        }
        let connectedMetrics = await transport.metrics()
        let connectedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(connectedMetrics.maximumConcurrentReceives, 1)
        XCTAssertEqual(connectedSnapshot.receiveLoopCount, 1)

        await connection.disconnect()
        let disconnectedMetrics = await transport.metrics()
        let disconnectedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(disconnectedMetrics.activeReceives, 0)
        XCTAssertEqual(disconnectedSnapshot.receiveLoopCount, 0)
    }

    func testAuthenticationRejectsInvalidCredentials() async throws {
        let transport = ScriptedWebSocketTransport()
        let connection = makeConnection(transports: [transport])
        let task = Task {
            try await connection.connect()
        }

        try await waitUntil { await transport.metrics().receiveCalls == 1 }
        try await transport.push(["type": .string("auth_required")])
        try await waitUntil { !(await transport.sentObjects()).isEmpty }
        try await transport.push([
            "type": .string("auth_invalid"),
            "message": .string("bad token"),
        ])

        do {
            try await task.value
            XCTFail("Expected authentication to fail")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .authenticationFailed("bad token"))
        }
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.state, .authenticationFailed("bad token"))
    }

    func testConcurrentConnectCallsShareOneAuthenticationAndReceiver() async throws {
        let transport = ScriptedWebSocketTransport()
        let connection = makeConnection(transports: [transport])
        let first = Task { try await connection.connect() }
        let second = Task { try await connection.connect() }

        try await waitUntil { await transport.metrics().receiveCalls == 1 }
        try await transport.push(["type": .string("auth_required")])
        try await waitUntil {
            await transport.sentObjects().filter { $0["type"] == .string("auth") }.count == 1
        }
        try await transport.push([
            "type": .string("auth_ok"),
            "ha_version": .string("2025.7.0"),
        ])
        try await first.value
        try await second.value

        let sent = await transport.sentObjects()
        XCTAssertEqual(sent.filter { $0["type"] == .string("auth") }.count, 1)
        XCTAssertEqual(sent.filter { $0["type"] == .string("supported_features") }.count, 1)
        let metrics = await transport.metrics()
        XCTAssertEqual(metrics.maximumConcurrentReceives, 1)
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.receiveLoopCount, 1)
        await connection.disconnect()
    }

    func testEarlyEventAndCoalescedOutOfOrderResultsRouteToTheirOwners() async throws {
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let connection = makeConnection(transports: [transport])
        try await connection.connect()

        let deliveries = JSONValueLog()
        let subscriptionTask = Task {
            try await connection.subscribeRaw([
                "type": .string("subscribe_events"),
                "event_type": .string("state_changed"),
            ]) { value in
                await deliveries.append(value)
            }
        }
        let subscriptionCommand = try await waitForSentMessage(transport) {
            $0["type"] == .string("subscribe_events")
        }
        let subscriptionID = try XCTUnwrap(subscriptionCommand["id"]?.testInt)

        try await transport.push([
            "id": .int(subscriptionID),
            "type": .string("event"),
            "event": .object(["sequence": .int(0)]),
        ])
        try await transport.push(result(id: subscriptionID, value: .null))
        let subscription = try await subscriptionTask.value

        let first = Task {
            try await connection.callRaw([
                "type": .string("test/first"),
                "private": .string("must-not-appear-in-errors"),
            ])
        }
        let second = Task {
            try await connection.callRaw(["type": .string("test/second")])
        }
        let firstMessage = try await waitForSentMessage(transport) {
            $0["type"] == .string("test/first")
        }
        let secondMessage = try await waitForSentMessage(transport) {
            $0["type"] == .string("test/second")
        }
        let firstID = try XCTUnwrap(firstMessage["id"]?.testInt)
        let secondID = try XCTUnwrap(secondMessage["id"]?.testInt)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertGreaterThan(firstID, subscriptionID)
        XCTAssertGreaterThan(secondID, subscriptionID)

        try await transport.pushGroup([
            result(id: secondID, value: .string("second-result")),
            [
                "id": .int(subscriptionID),
                "type": .string("event"),
                "event": .object(["sequence": .int(1)]),
            ],
            [
                "id": .int(99_999),
                "type": .string("result"),
                "success": .bool(true),
                "result": .string("unknown-owner"),
            ],
            [
                "id": .int(firstID),
                "type": .string("result"),
                "success": .bool(true),
            ],
        ])

        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, .null)
        XCTAssertEqual(secondValue, .string("second-result"))
        try await waitUntil { await deliveries.snapshot().count == 2 }
        let deliveredValues = await deliveries.snapshot()
        XCTAssertEqual(deliveredValues, [
            .object(["sequence": .int(0)]),
            .object(["sequence": .int(1)]),
        ])

        await cancel(subscription, transport: transport)
        await connection.disconnect()
    }

    func testServerErrorPreservesCodeAndMessageWithoutCommandPayload() async throws {
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let connection = makeConnection(transports: [transport])
        try await connection.connect()

        let call = Task {
            try await connection.callRaw([
                "type": .string("test/failure"),
                "secret_field": .string("do-not-log-this"),
            ])
        }
        let command = try await waitForSentMessage(transport) {
            $0["type"] == .string("test/failure")
        }
        let id = try XCTUnwrap(command["id"]?.testInt)
        try await transport.push([
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(false),
            "error": .object([
                "code": .string("invalid_format"),
                "message": .string("The request was invalid"),
            ]),
        ])

        do {
            _ = try await call.value
            XCTFail("Expected a server error")
        } catch {
            XCTAssertEqual(
                error as? HomeAssistantWebSocketError,
                .commandFailed(code: "invalid_format", message: "The request was invalid")
            )
            XCTAssertFalse(error.localizedDescription.contains("do-not-log-this"))
        }
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.pendingCommandCount, 0)
        await connection.disconnect()
    }

    func testCancellationIsIdempotentAndUsesCurrentSubscriptionWireID() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let deliveries = JSONValueLog()
        let subscription = try await connection.subscribeRaw([
            "type": .string("weather/subscribe_forecast"),
            "entity_id": .string("weather.home"),
        ]) { value in
            await deliveries.append(value)
        }

        await subscription.cancel()
        let sentAfterFirstCancel = await transport.sentObjects()
        let unsubscribe = try XCTUnwrap(sentAfterFirstCancel.first {
            $0["type"] == .string("unsubscribe_events")
        })
        XCTAssertEqual(unsubscribe["subscription"], .int(subscription.id))

        await subscription.cancel()
        let afterSecondCancel = await transport.sentObjects()
        XCTAssertEqual(
            afterSecondCancel.filter { $0["type"] == .string("unsubscribe_events") }.count,
            1
        )
        try await transport.push([
            "id": .int(subscription.id),
            "type": .string("event"),
            "event": .object(["late": .bool(true)]),
        ])
        for _ in 0..<20 { await Task.yield() }
        let lateDeliveries = await deliveries.snapshot()
        XCTAssertTrue(lateDeliveries.isEmpty)
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.pendingCommandCount, 0)
        XCTAssertEqual(snapshot.subscriptionCount, 0)
        XCTAssertEqual(snapshot.wireSubscriptionCount, 0)
        await connection.disconnect()
    }

    func testTimeoutTaskCancellationAndDisconnectEachCleanPendingStorageOnce() async throws {
        let timeoutTransport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let timeoutConnection = makeConnection(
            transports: [timeoutTransport],
            timeoutNanoseconds: 1_000_000
        )
        try await timeoutConnection.connect()
        do {
            _ = try await timeoutConnection.callRaw(["type": .string("test/timeout")])
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .timedOut)
        }
        let timeoutSnapshot = await timeoutConnection.debugSnapshot()
        XCTAssertEqual(timeoutSnapshot.pendingCommandCount, 0)
        await timeoutConnection.disconnect()

        let cancelTransport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let cancelConnection = makeConnection(transports: [cancelTransport])
        try await cancelConnection.connect()
        let cancelledCall = Task {
            try await cancelConnection.callRaw(["type": .string("test/cancel")])
        }
        _ = try await waitForSentMessage(cancelTransport) {
            $0["type"] == .string("test/cancel")
        }
        cancelledCall.cancel()
        do {
            _ = try await cancelledCall.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .cancelled)
        }
        let cancelledSnapshot = await cancelConnection.debugSnapshot()
        XCTAssertEqual(cancelledSnapshot.pendingCommandCount, 0)

        let disconnectedCall = Task {
            try await cancelConnection.callRaw(["type": .string("test/disconnect")])
        }
        _ = try await waitForSentMessage(cancelTransport) {
            $0["type"] == .string("test/disconnect")
        }
        await cancelConnection.disconnect()
        do {
            _ = try await disconnectedCall.value
            XCTFail("Expected disconnect")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .disconnected)
        }
        let final = await cancelConnection.debugSnapshot()
        XCTAssertEqual(final.pendingCommandCount, 0)
        XCTAssertEqual(final.subscriptionCount, 0)
        XCTAssertEqual(final.receiveLoopCount, 0)
    }

    func testReconnectResubscribesGenericOwnersAndDropsHistoryOptOut() async throws {
        let firstTransport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let secondTransport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([firstTransport, secondTransport])
        let connection = makeConnection(factory: factory, reconnectDelay: { _ in 0 })
        let stateLog = ConnectionStateLog()
        let statusStream = await connection.statusUpdates()
        let statusTask = Task {
            for await state in statusStream {
                await stateLog.append(state)
            }
        }
        try await connection.connect()

        let history = try await connection.subscribeRaw([
            "type": .string("history/stream"),
            "start_time": .string("fresh-at-owner"),
        ], resubscribe: false) { _ in }
        let generic = try await connection.subscribeRaw([
            "type": .string("subscribe_events"),
            "event_type": .string("state_changed"),
        ]) { _ in }

        await firstTransport.pushFailure()
        try await waitUntil {
            guard factory.count() == 2 else { return false }
            return await connection.debugSnapshot().state == .ready
        }

        let reconnectMessages = await secondTransport.sentObjects()
        XCTAssertEqual(
            reconnectMessages.filter { $0["type"] == .string("subscribe_events") }.count,
            1
        )
        XCTAssertFalse(reconnectMessages.contains { $0["type"] == .string("history/stream") })
        let reconnectedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(reconnectedSnapshot.subscriptionCount, 1)
        try await waitUntil { await stateLog.readyCount() == 2 }
        let lifecycleStates = await stateLog.snapshot()
        XCTAssertTrue(lifecycleStates.contains(.disconnected))
        XCTAssertTrue(lifecycleStates.contains(.reconnecting(attempt: 0)))

        await history.cancel()
        await generic.cancel()
        let resubscribe = try XCTUnwrap(reconnectMessages.first {
            $0["type"] == .string("subscribe_events")
        })
        let currentWireID = try XCTUnwrap(resubscribe["id"]?.testInt)
        let afterCancel = await secondTransport.sentObjects()
        let unsubscribe = try XCTUnwrap(afterCancel.first {
            $0["type"] == .string("unsubscribe_events")
        })
        XCTAssertNotEqual(generic.id, currentWireID)
        XCTAssertEqual(unsubscribe["subscription"], .int(currentWireID))
        let cancelledSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(cancelledSnapshot.subscriptionCount, 0)
        XCTAssertEqual(cancelledSnapshot.pendingCommandCount, 0)
        await connection.disconnect()
        statusTask.cancel()
        await statusTask.value
        let disconnectedMetrics = await secondTransport.metrics()
        XCTAssertEqual(disconnectedMetrics.activeReceives, 0)
    }

    func testMalformedFrameAndSendFailureTakeControlledReconnectPaths() async throws {
        let malformedTransport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let replacement = ScriptedWebSocketTransport(automaticAuthentication: true)
        let malformedFactory = ScriptedTransportFactory([malformedTransport, replacement])
        let malformedConnection = makeConnection(factory: malformedFactory, reconnectDelay: { _ in 0 })
        try await malformedConnection.connect()
        await malformedTransport.pushMalformedJSON()
        try await waitUntil {
            guard malformedFactory.count() == 2 else { return false }
            return await malformedConnection.debugSnapshot().state == .ready
        }
        let malformedSnapshot = await malformedConnection.debugSnapshot()
        XCTAssertEqual(malformedSnapshot.receiveLoopCount, 1)
        await malformedConnection.disconnect()

        let failedSendTransport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let failedSendReplacement = ScriptedWebSocketTransport(automaticAuthentication: true)
        let failedSendFactory = ScriptedTransportFactory([failedSendTransport, failedSendReplacement])
        let failedSendConnection = makeConnection(factory: failedSendFactory, reconnectDelay: { _ in 0 })
        try await failedSendConnection.connect()
        await failedSendTransport.arrangeNextSendFailure()
        do {
            _ = try await failedSendConnection.callRaw(["type": .string("test/send-failure")])
            XCTFail("Expected send failure")
        } catch {
            XCTAssertTrue(error is ScriptedTransportError)
        }
        try await waitUntil {
            guard failedSendFactory.count() == 2 else { return false }
            return await failedSendConnection.debugSnapshot().state == .ready
        }
        let failedSendSnapshot = await failedSendConnection.debugSnapshot()
        XCTAssertEqual(failedSendSnapshot.pendingCommandCount, 0)
        await failedSendConnection.disconnect()
    }

    private func result(id: Int, value: JSONValue) -> [String: JSONValue] {
        [
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": value,
        ]
    }

    private func makeConnection(
        transports: [ScriptedWebSocketTransport],
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        reconnectDelay: @escaping (Int) -> UInt64 = { _ in 60_000_000_000 }
    ) -> HomeAssistantWebSocketConnection {
        makeConnection(
            factory: ScriptedTransportFactory(transports),
            timeoutNanoseconds: timeoutNanoseconds,
            reconnectDelay: reconnectDelay
        )
    }

    private func makeConnection(
        factory: ScriptedTransportFactory,
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        reconnectDelay: @escaping (Int) -> UInt64 = { _ in 60_000_000_000 }
    ) -> HomeAssistantWebSocketConnection {
        HomeAssistantWebSocketConnection(
            accessToken: "token-for-test",
            commandTimeoutNanoseconds: timeoutNanoseconds,
            reconnectDelayNanoseconds: reconnectDelay,
            transportFactory: factory.make
        )
    }

    private func waitForSentMessage(
        _ transport: ScriptedWebSocketTransport,
        matching predicate: @escaping ([String: JSONValue]) -> Bool
    ) async throws -> [String: JSONValue] {
        try await waitUntil {
            await transport.sentObjects().contains(where: predicate)
        }
        let messages = await transport.sentObjects()
        return try XCTUnwrap(messages.first(where: predicate))
    }

    private func cancel(
        _ subscription: HAWebSocketSubscription,
        transport: ScriptedWebSocketTransport
    ) async {
        let task = Task {
            await subscription.cancel()
        }
        do {
            let unsubscribe = try await waitForSentMessage(transport) {
                $0["type"] == .string("unsubscribe_events")
            }
            if let id = unsubscribe["id"]?.testInt {
                try await transport.push(result(id: id, value: .null))
            }
        } catch {
            XCTFail("Unable to complete cancellation: \(error)")
        }
        await task.value
    }
}
