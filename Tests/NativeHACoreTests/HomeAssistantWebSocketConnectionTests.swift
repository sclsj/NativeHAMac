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

    func testConcurrentMixedCommandsAndSubscriptionsSendStrictlyIncreasingWireIDs() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true,
            automaticCommandAcknowledgement: true,
            requiresStrictlyIncreasingCommandIDs: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()

        let subscriptionTasks = (0..<64).map { index in
            Task {
                try await connection.subscribeRaw([
                    "type": .string("subscribe_events"),
                    "event_type": .string("strict-subscription-\(index)"),
                ]) { _ in }
            }
        }
        let commandTasks = (0..<64).map { index in
            Task {
                try await connection.callRaw([
                    "type": .string("strict/command"),
                    "sequence": .int(index),
                ])
            }
        }

        var subscriptions: [HAWebSocketSubscription] = []
        for task in subscriptionTasks {
            subscriptions.append(try await task.value)
        }
        for task in commandTasks {
            _ = try await task.value
        }
        for subscription in subscriptions {
            await subscription.cancel()
        }

        let wireIDs = await transport.sentObjects().compactMap { $0["id"]?.testInt }
        XCTAssertEqual(wireIDs.count, 1 + 64 + 64 + 64)
        XCTAssertTrue(
            zip(wireIDs, wireIDs.dropFirst()).allSatisfy(<),
            "Home Assistant rejects a command ID that does not increase in actual send order."
        )
        let strictMetrics = await transport.commandIDMetrics()
        XCTAssertEqual(strictMetrics.violationCount, 0)
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.pendingCommandCount, 0)
        XCTAssertEqual(snapshot.subscriptionCount, 0)
        XCTAssertEqual(snapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(snapshot.deliveryOwnerCount, 0)

        await connection.disconnect()
    }

    func testSuspendingTransportCannotReorderAllocatedWireIDs() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticCommandAcknowledgement: true,
            requiresStrictlyIncreasingCommandIDs: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        await transport.arrangeNextSendSuspension()

        let first = Task { () -> Error? in
            do {
                _ = try await connection.callRaw(["type": .string("test/first")])
                return nil
            } catch {
                return error
            }
        }
        try await waitUntil { await transport.hasSuspendedSend() }

        let second = Task { () -> Error? in
            do {
                _ = try await connection.callRaw(["type": .string("test/second")])
                return nil
            } catch {
                return error
            }
        }
        try await waitUntil {
            await connection.debugSnapshot().nextCommandID >= 4
        }
        let attemptedBeforeRelease = await transport.commandIDAttempts()
        XCTAssertEqual(
            attemptedBeforeRelease,
            [1, 2],
            "ID 3 must remain queued until the suspended send of ID 2 completes."
        )
        await transport.resumeSuspendedSend()

        let firstError = await first.value
        let secondError = await second.value
        let metrics = await transport.commandIDMetrics()
        XCTAssertEqual(
            metrics.violationCount,
            0,
            "An allocated ID must not be overtaken while an earlier native send is suspended."
        )
        XCTAssertNil(firstError)
        XCTAssertNil(secondError)

        await connection.disconnect()
    }

    func testSuspendedOldTransportDoesNotBlockReplacementGeneration() async throws {
        let firstTransport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticCommandAcknowledgement: true,
            requiresStrictlyIncreasingCommandIDs: true
        )
        let replacementTransport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticCommandAcknowledgement: true,
            requiresStrictlyIncreasingCommandIDs: true
        )
        let connection = makeConnection(
            transports: [firstTransport, replacementTransport],
            reconnectDelay: { _ in 0 }
        )
        try await connection.connect()
        await firstTransport.arrangeNextSendSuspension()

        let staleCall = Task {
            try await connection.callRaw(["type": .string("test/stale-generation")])
        }
        try await waitUntil { await firstTransport.hasSuspendedSend() }
        await firstTransport.pushFailure()
        try await waitUntil {
            let state = await connection.debugSnapshot().state
            let attempts = await replacementTransport.commandIDAttempts()
            return state == .ready && attempts == [1]
        }

        let replacementResult = try await connection.callRaw([
            "type": .string("test/replacement-generation"),
        ])
        XCTAssertEqual(replacementResult, .int(2))
        let replacementAttempts = await replacementTransport.commandIDAttempts()
        XCTAssertEqual(replacementAttempts, [1, 2])

        await firstTransport.resumeSuspendedSend()
        do {
            _ = try await staleCall.value
            XCTFail("The command owned by the disconnected generation should fail")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .disconnected)
        }

        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.pendingCommandCount, 0)
        XCTAssertEqual(snapshot.receiveLoopCount, 1)
        await connection.disconnect()
    }

    func testStoppedSerializerReleasesItselfWhenActiveTransportSendNeverReturns() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticCommandAcknowledgement: true
        )
        try await transport.connect()
        await transport.arrangeNextSendSuspension()

        var serializer: HomeAssistantWebSocketSendSerializer? =
            HomeAssistantWebSocketSendSerializer(transport: transport)
        weak var weakSerializer = serializer
        let ticket = serializer!.enqueue(
            .string(#"{"id":1,"type":"test/never-resumes"}"#),
            shouldSend: { true }
        )
        try await waitUntil { await transport.hasSuspendedSend() }

        serializer?.stop()
        do {
            try await ticket.value()
            XCTFail("Stopping the serializer must fail its active send ticket")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .disconnected)
        }
        serializer = nil

        XCTAssertNil(
            weakSerializer,
            "A transport send that never returns must not retain its retired serializer generation."
        )
    }

    func testCancelledCommandWaitingBehindSuspendedSendNeverReachesTransport() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticCommandAcknowledgement: true,
            requiresStrictlyIncreasingCommandIDs: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        await transport.arrangeNextSendSuspension()

        let first = Task {
            try await connection.callRaw(["type": .string("test/first")])
        }
        try await waitUntil { await transport.hasSuspendedSend() }

        let cancelled = Task {
            try await connection.callRaw(["type": .string("test/cancelled")])
        }
        try await waitUntil {
            await connection.debugSnapshot().nextCommandID >= 4
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Expected the queued command to be cancelled")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .cancelled)
        }

        await transport.resumeSuspendedSend()
        _ = try await first.value
        try await waitUntil {
            await connection.debugSnapshot().pendingCommandCount == 0
        }
        let attemptedIDs = await transport.commandIDAttempts()
        XCTAssertEqual(attemptedIDs, [1, 2])

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

    func testTypedSubscriptionDecodesLargeEventDirectlyAndPreservesAllSamples() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let log = TypedHistoryCountLog()
        let subscription = try await connection.subscribeMessage(
            ["type": .string("history/stream")],
            as: HAHistoryStreamMessage.self,
            resubscribe: false
        ) { message in
            await log.append(message.states.values.reduce(0) { $0 + $1.count })
        }

        let states = (0..<100_000).map { index in
            HACompactHistoryState(
                state: "\(index)",
                lastChangedSeconds: Double(index) + 0.125,
                lastUpdatedSeconds: Double(index) + 0.875
            )
        }
        let envelope = TypedHistoryEventEnvelope(
            id: subscription.id,
            event: HAHistoryStreamMessage(states: ["sensor.large": states])
        )
        let data = try JSONEncoder().encode(envelope)
        await transport.pushFrame(.string(String(decoding: data, as: UTF8.self)))

        try await waitUntil(iterations: 10_000_000) {
            await log.values() == [100_000]
        }
        try await waitUntil {
            await connection.debugSnapshot().activeDeliveryTaskCount == 0
        }
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.directTypedEventDecodeCount, 1)
        XCTAssertEqual(snapshot.bufferedDeliveryCount, 0)
        XCTAssertEqual(snapshot.activeDeliveryTaskCount, 0)

        await subscription.cancel()
        await connection.disconnect()
    }

    func testTypedCoalescedEventsRemainInWireOrder() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let log = TypedHistoryCountLog()
        let subscription = try await connection.subscribeMessage(
            [
                "type": .string("subscribe_events"),
                "event_type": .string("test_typed_order"),
            ],
            as: TypedSequencePayload.self
        ) { payload in
            await log.append(payload.sequence)
        }

        try await transport.pushGroup((0..<100).map { sequence in
            [
                "id": .int(subscription.id),
                "type": .string("event"),
                "event": .object(["sequence": .int(sequence)]),
            ]
        })
        try await waitUntil { await log.values().count == 100 }
        let orderedValues = await log.values()
        XCTAssertEqual(orderedValues, Array(0..<100))
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.directTypedEventDecodeCount, 100)

        await subscription.cancel()
        await connection.disconnect()
    }

    func testTypedDecodeDoesNotBlockConnectionActorAndCancellationSuppressesCallback() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let gate = BlockingDecodeGate()
        BlockingTypedPayload.install(gate)
        defer { BlockingTypedPayload.install(nil) }
        let log = TypedHistoryCountLog()
        let subscription = try await connection.subscribeMessage(
            [
                "type": .string("subscribe_events"),
                "event_type": .string("test_blocking_decode"),
            ],
            as: BlockingTypedPayload.self
        ) { payload in
            await log.append(payload.sequence)
        }

        try await transport.push([
            "id": .int(subscription.id),
            "type": .string("event"),
            "event": .object(["sequence": .int(9)]),
        ])
        try await waitUntil { gate.hasEntered }

        let cancellation = Task { await subscription.cancel() }
        _ = try await waitForSentMessage(transport) {
            $0["type"] == .string("unsubscribe_events")
        }
        await cancellation.value
        let responsiveSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(responsiveSnapshot.subscriptionCount, 0)
        XCTAssertEqual(responsiveSnapshot.wireSubscriptionCount, 0)

        gate.open()
        try await waitUntil {
            await connection.debugSnapshot().activeDeliveryTaskCount == 0
        }
        let cancelledValues = await log.values()
        XCTAssertEqual(cancelledValues, [])
        await connection.disconnect()
    }

    func testCancelledQueuedTypedSliceReleasesLargeCoalescedFrameBacking() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let connection = makeConnection(
            transports: [transport],
            deliveryCapacity: 4,
            maximumConcurrentCallbackTasks: 1
        )
        try await connection.connect()
        let callbackGate = AsyncTestGate()
        let subscription = try await connection.subscribeMessage(
            [
                "type": .string("subscribe_events"),
                "event_type": .string("test_slice_retention"),
            ],
            as: TypedSequencePayload.self
        ) { _ in
            await callbackGate.wait()
        }

        try await transport.push([
            "id": .int(subscription.id),
            "type": .string("event"),
            "event": .object(["sequence": .int(1)]),
        ])
        try await waitUntil { await callbackGate.waitingCount() == 1 }

        let releaseProbe = LargeFrameReleaseProbe()
        await pushLargeCoalescedTypedEvent(
            subscriptionID: subscription.id,
            releaseProbe: releaseProbe,
            on: transport
        )
        try await waitUntilDeadline(timeout: 5) {
            let snapshot = await connection.debugSnapshot()
            return snapshot.bufferedDeliveryCount == 1
                && snapshot.directTypedEventDecodeCount == 2
        }

        await subscription.cancel()
        try await waitUntilDeadline(timeout: 5) { releaseProbe.wasReleased }
        let cancelledSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(cancelledSnapshot.deliveryOwnerCount, 0)
        XCTAssertEqual(cancelledSnapshot.bufferedDeliveryCount, 0)
        XCTAssertEqual(
            cancelledSnapshot.activeDeliveryTaskCount,
            1,
            "The large frame must be releasable even while an unrelated cancelled callback has not returned."
        )

        await callbackGate.open()
        try await waitUntil {
            await connection.debugSnapshot().activeDeliveryTaskCount == 0
        }
        await connection.disconnect()
    }

    func testDetachedScanAndDecodeGuardsDropStaleGenerationEvents() async throws {
        for boundary in [
            HAWebSocketDetachedDecodeBoundary.envelopeScan,
            HAWebSocketDetachedDecodeBoundary.payloadDecode,
        ] {
            try await assertStaleDetachedEventIsDropped(after: boundary)
        }
    }

    func testMalformedTypedEventIsOwnerLocalAndRawSubscriptionKeepsGenericFallback() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let typedLog = TypedHistoryCountLog()
        let typed = try await connection.subscribeMessage(
            [
                "type": .string("subscribe_events"),
                "event_type": .string("test_typed"),
            ],
            as: TypedSequencePayload.self
        ) { payload in
            await typedLog.append(payload.sequence)
        }
        let rawLog = JSONValueLog()
        let raw = try await connection.subscribeRaw(
            [
                "type": .string("subscribe_events"),
                "event_type": .string("test_raw"),
            ]
        ) { value in
            await rawLog.append(value)
        }

        try await transport.push([
            "id": .int(typed.id),
            "type": .string("event"),
            "event": .object(["wrong": .bool(true)]),
        ])
        try await transport.push([
            "id": .int(raw.id),
            "type": .string("event"),
            "event": .object(["raw": .bool(true)]),
        ])
        try await transport.push([
            "id": .int(typed.id),
            "type": .string("event"),
            "event": .object(["sequence": .int(7)]),
        ])

        try await waitUntil {
            let typedValues = await typedLog.values()
            let rawValues = await rawLog.snapshot()
            return typedValues == [7] && rawValues.count == 1
        }
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.directTypedEventDecodeCount, 2)
        XCTAssertGreaterThan(snapshot.genericFrameDecodeCount, 0)
        let rawValues = await rawLog.snapshot()
        XCTAssertEqual(rawValues, [.object(["raw": .bool(true)])])

        await typed.cancel()
        await raw.cancel()
        await connection.disconnect()
    }

    private func result(id: Int, value: JSONValue) -> [String: JSONValue] {
        [
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": value,
        ]
    }

    func testTypedDisplayRegistryCommandDecodesCompressedPrecision() async throws {
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)

        let task = Task { try await client.fetchEntityRegistryDisplay() }
        let request = try await waitForSentMessage(transport) {
            $0["type"] == .string("config/entity_registry/list_for_display")
        }
        let id = try XCTUnwrap(request["id"]?.testInt)
        try await transport.push([
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": .object([
                "entities": .array([
                    .object(["ei": .string("sensor.pm2_5"), "lb": .array([]), "dp": .int(2)]),
                    .object(["ei": .string("sensor.unconfigured"), "lb": .array([])]),
                ]),
                "entity_categories": .object([:]),
            ]),
        ])

        let response = try await task.value
        XCTAssertEqual(response.entities, [
            HAEntityRegistryDisplayEntry(entityID: "sensor.pm2_5", displayPrecision: 2),
            HAEntityRegistryDisplayEntry(entityID: "sensor.unconfigured"),
        ])
        await connection.disconnect()
    }

    func testTypedFrontendLanguageCommandDecodesPreferencesAndNullFallback() async throws {
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)

        let task = Task { try await client.fetchFrontendLocalePreferences() }
        let request = try await waitForSentMessage(transport) {
            $0["type"] == .string("frontend/get_user_data")
        }
        XCTAssertEqual(request["key"], .string("language"))
        let id = try XCTUnwrap(request["id"]?.testInt)
        try await transport.push([
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": .object(["value": .null]),
        ])

        let preferences = try await task.value
        XCTAssertNil(preferences)
        await connection.disconnect()
    }

    func testTypedCurrentUserCommandDecodesOnlyRequiredIdentity() async throws {
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let connection = makeConnection(transports: [transport])
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)

        let task = Task { try await client.fetchCurrentUser() }
        let request = try await waitForSentMessage(transport) {
            $0["type"] == .string("auth/current_user")
        }
        XCTAssertEqual(Set(request.keys), ["id", "type"])
        let id = try XCTUnwrap(request["id"]?.testInt)
        try await transport.push([
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": .object([
                "id": .string("current-user-id"),
                "name": .string("Must not be retained"),
                "credentials": .array([.object(["auth_provider_type": .string("homeassistant")])]),
            ]),
        ])

        let currentUser = try await task.value
        XCTAssertEqual(currentUser, HACurrentUser(id: "current-user-id"))
        await connection.disconnect()
    }

    private func makeConnection(
        transports: [ScriptedWebSocketTransport],
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        deliveryCapacity: Int = 256,
        maximumConcurrentCallbackTasks: Int = 4,
        reconnectDelay: @escaping (Int) -> UInt64 = { _ in 60_000_000_000 },
        detachedDecodeBoundaryHook: (@Sendable (HAWebSocketDetachedDecodeBoundary) async -> Void)? = nil
    ) -> HomeAssistantWebSocketConnection {
        makeConnection(
            factory: ScriptedTransportFactory(transports),
            timeoutNanoseconds: timeoutNanoseconds,
            deliveryCapacity: deliveryCapacity,
            maximumConcurrentCallbackTasks: maximumConcurrentCallbackTasks,
            reconnectDelay: reconnectDelay,
            detachedDecodeBoundaryHook: detachedDecodeBoundaryHook
        )
    }

    private func makeConnection(
        factory: ScriptedTransportFactory,
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        deliveryCapacity: Int = 256,
        maximumConcurrentCallbackTasks: Int = 4,
        reconnectDelay: @escaping (Int) -> UInt64 = { _ in 60_000_000_000 },
        detachedDecodeBoundaryHook: (@Sendable (HAWebSocketDetachedDecodeBoundary) async -> Void)? = nil
    ) -> HomeAssistantWebSocketConnection {
        HomeAssistantWebSocketConnection(
            accessToken: "token-for-test",
            commandTimeoutNanoseconds: timeoutNanoseconds,
            deliveryCapacity: deliveryCapacity,
            maximumConcurrentCallbackTasks: maximumConcurrentCallbackTasks,
            reconnectDelayNanoseconds: reconnectDelay,
            detachedDecodeBoundaryHook: detachedDecodeBoundaryHook,
            transportFactory: factory.make
        )
    }

    private func assertStaleDetachedEventIsDropped(
        after boundary: HAWebSocketDetachedDecodeBoundary
    ) async throws {
        let firstTransport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let replacementTransport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([firstTransport, replacementTransport])
        let gate = DetachedDecodeBoundaryGate(target: boundary)
        let connection = makeConnection(
            factory: factory,
            reconnectDelay: { _ in 0 },
            detachedDecodeBoundaryHook: { boundary in
                await gate.pauseIfTargeted(boundary)
            }
        )
        try await connection.connect()
        let log = JSONValueLog()
        let subscription = try await connection.subscribeRaw([
            "type": .string("subscribe_events"),
            "event_type": .string("test_stale_detached_\(boundary)"),
        ]) { value in
            await log.append(value)
        }
        await gate.arm()

        try await firstTransport.push([
            "id": .int(subscription.id),
            "type": .string("event"),
            "event": .object(["generation": .string("stale")]),
        ])
        try await waitUntil { await gate.isPaused }

        await connection.reconnect()
        try await waitUntil {
            guard factory.count() == 2 else { return false }
            return await connection.debugSnapshot().state == .ready
        }
        await gate.resume()
        try await waitUntil {
            await connection.debugSnapshot().activeDeliveryTaskCount == 0
        }
        let valuesAfterStaleWork = await log.snapshot()
        XCTAssertEqual(
            valuesAfterStaleWork,
            [],
            "Detached work suspended after \(boundary) must not route into the replacement generation."
        )

        let replacementSubscribe = try await waitForSentMessage(replacementTransport) {
            $0["type"] == .string("subscribe_events")
        }
        let replacementID = try XCTUnwrap(replacementSubscribe["id"]?.testInt)
        try await replacementTransport.push([
            "id": .int(replacementID),
            "type": .string("event"),
            "event": .object(["generation": .string("replacement")]),
        ])
        try await waitUntil { await log.snapshot().count == 1 }
        let replacementValues = await log.snapshot()
        XCTAssertEqual(
            replacementValues,
            [.object(["generation": .string("replacement")])]
        )

        await subscription.cancel()
        await connection.disconnect()
    }

    private func pushLargeCoalescedTypedEvent(
        subscriptionID: Int,
        releaseProbe: LargeFrameReleaseProbe,
        on transport: ScriptedWebSocketTransport
    ) async {
        let padding = String(repeating: "x", count: 8 * 1_024 * 1_024)
        let json = "[{\"id\":\(subscriptionID),\"type\":\"event\",\"event\":{\"sequence\":2}},{\"id\":2147483647,\"type\":\"event\",\"event\":{\"padding\":\"\(padding)\"}}]"
        let byteCount = json.utf8.count
        guard let buffer = malloc(byteCount) else {
            XCTFail("Unable to allocate the large-frame retention fixture")
            return
        }
        Data(json.utf8).copyBytes(
            to: buffer.assumingMemoryBound(to: UInt8.self),
            count: byteCount
        )
        let data = Data(
            bytesNoCopy: buffer,
            count: byteCount,
            deallocator: .custom { pointer, _ in
                free(pointer)
                releaseProbe.markReleased()
            }
        )
        await transport.pushFrame(.data(data))
    }

    private func waitUntilDeadline(
        timeout: TimeInterval,
        _ condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            await Task.yield()
        }
        throw AsyncTestWaitError.conditionNotMet
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

private struct TypedSequencePayload: Decodable {
    let sequence: Int
}

private struct TypedHistoryEventEnvelope: Encodable {
    let id: Int
    let type = "event"
    let event: HAHistoryStreamMessage
}

private actor TypedHistoryCountLog {
    private var recorded: [Int] = []

    func append(_ value: Int) {
        recorded.append(value)
    }

    func values() -> [Int] {
        recorded
    }
}

private final class BlockingDecodeGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var opened = false

    var hasEntered: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    func enterAndWait() {
        condition.lock()
        entered = true
        condition.broadcast()
        while !opened {
            condition.wait()
        }
        condition.unlock()
    }

    func open() {
        condition.lock()
        opened = true
        condition.broadcast()
        condition.unlock()
    }
}

private struct BlockingTypedPayload: Decodable {
    let sequence: Int

    private static let lock = NSLock()
    private static var gate: BlockingDecodeGate?

    static func install(_ gate: BlockingDecodeGate?) {
        lock.lock()
        self.gate = gate
        lock.unlock()
    }

    init(from decoder: Decoder) throws {
        Self.lock.lock()
        let gate = Self.gate
        Self.lock.unlock()
        gate?.enterAndWait()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try container.decode(Int.self, forKey: .sequence)
    }

    private enum CodingKeys: String, CodingKey {
        case sequence
    }
}

private actor DetachedDecodeBoundaryGate {
    private let target: HAWebSocketDetachedDecodeBoundary
    private var armed = false
    private var paused = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(target: HAWebSocketDetachedDecodeBoundary) {
        self.target = target
    }

    var isPaused: Bool { paused }

    func arm() {
        armed = true
    }

    func pauseIfTargeted(_ boundary: HAWebSocketDetachedDecodeBoundary) async {
        guard armed, !paused, boundary == target else {
            return
        }
        paused = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private final class LargeFrameReleaseProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false

    var wasReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return released
    }

    func markReleased() {
        lock.lock()
        released = true
        lock.unlock()
    }
}
