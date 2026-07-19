import Foundation
import XCTest
@testable import NativeHACore

final class HomeAssistantHistoryStreamTests: XCTestCase {
    func testCompactDecoderPreservesFieldsFractionalSecondsAndChunkMetadata() throws {
        let data = Data(#"""
        {
          "states": {
            "sensor.room": [
              {"s":"20.5","a":{"unit_of_measurement":"°C"},"lc":1767225600.125,"lu":1767225600.875},
              {"s":"20.6","lu":1767225601.625}
            ],
            "switch.empty": []
          },
          "start_time": 1767222000.25,
          "end_time": 1767225602.75
        }
        """#.utf8)

        let message = try JSONDecoder().decode(HAHistoryStreamMessage.self, from: data)
        let first = try XCTUnwrap(message.states["sensor.room"]?.first)
        XCTAssertEqual(first.state, "20.5")
        XCTAssertEqual(first.attributes["unit_of_measurement"], .string("°C"))
        XCTAssertEqual(first.lastChangedSeconds, 1_767_225_600.125)
        XCTAssertEqual(first.lastUpdatedSeconds, 1_767_225_600.875)
        XCTAssertEqual(message.states["sensor.room"]?[1].attributes, [:])
        XCTAssertEqual(message.states["switch.empty"], [])
        XCTAssertEqual(message.startTime, 1_767_222_000.25)
        XCTAssertEqual(message.endTime, 1_767_225_602.75)
    }

    func testCompactDecoderRejectsMissingOrMalformedRequiredFieldsAndRESTShapesStaySeparate() throws {
        for json in [
            #"{"states":{"sensor.bad":[{"lu":1}]}}"#,
            #"{"states":{"sensor.bad":[{"s":"1"}]}}"#,
            #"{"states":{"sensor.bad":[{"s":"1","lu":"bad"}]}}"#,
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(HAHistoryStreamMessage.self, from: Data(json.utf8))
            )
        }

        let compact = Data(#"{"s":"on","lu":1.25}"#.utf8)
        let rest = Data(#"{"state":"on","last_updated":"2026-01-01T00:00:00Z"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HAHistoryPoint.self, from: compact))
        XCTAssertThrowsError(try JSONDecoder().decode(HACompactHistoryState.self, from: rest))
        XCTAssertNoThrow(try JSONDecoder().decode(HAHistoryPoint.self, from: rest))
        XCTAssertNoThrow(try JSONDecoder().decode(HACompactHistoryState.self, from: compact))
    }

    func testAccumulatorConcatenatesStableSortsAndRetainsEqualTimestampsAndDuplicates() {
        let clock = LockedHistoryClock(Date(timeIntervalSince1970: 10_000))
        var accumulator = HAHistoryStreamAccumulator(range: nil, now: { clock.now() })
        let duplicate = state("duplicate", at: 30)
        _ = accumulator.process(message([
            "sensor.a": [state("first", at: 10), duplicate],
            "sensor.empty": [],
        ]))

        let result = accumulator.process(message([
            "sensor.a": [
                state("older", at: 20),
                state("equal-one", at: 30),
                duplicate,
                state("new", at: 40),
            ],
            "sensor.new": [state("introduced", at: 1)],
        ]))

        XCTAssertEqual(result["sensor.a"]?.map(\.state), [
            "first", "older", "duplicate", "equal-one", "duplicate", "new",
        ])
        XCTAssertEqual(result["sensor.empty"], [])
        XCTAssertEqual(result["sensor.new"]?.map(\.state), ["introduced"])
        XCTAssertEqual(result["sensor.a"]?.filter { $0 == duplicate }.count, 2)

        let afterEmpty = accumulator.process(message([:]))
        XCTAssertEqual(afterEmpty, result)
    }

    func testAccumulatorRollingBoundaryAndNewEntityEarlyReturnMatchReference() throws {
        let clock = LockedHistoryClock(Date(timeIntervalSince1970: 10_000))
        var accumulator = HAHistoryStreamAccumulator(range: 100, now: { clock.now() })
        _ = accumulator.process(message([
            "sensor.a": [state("old", at: 9_000, lc: 8_999), state("recent", at: 9_950)],
        ]))

        var result = accumulator.process(message([
            "sensor.a": [state("new", at: 9_975)],
            "sensor.new": [state("untrimmed", at: 1)],
        ]))
        let boundary = try XCTUnwrap(result["sensor.a"]?.first)
        XCTAssertEqual(boundary.state, "old")
        XCTAssertEqual(boundary.lastUpdatedSeconds, 9_900)
        XCTAssertNil(boundary.lastChangedSeconds)
        XCTAssertEqual(result["sensor.a"]?.map(\.state), ["old", "recent", "new"])
        XCTAssertEqual(result["sensor.new"]?.first?.lastUpdatedSeconds, 1)

        result = accumulator.process(message(["sensor.new": []]))
        XCTAssertEqual(result["sensor.new"]?.first?.lastUpdatedSeconds, 9_900)
        XCTAssertNil(result["sensor.new"]?.first?.lastChangedSeconds)

        var exact = HAHistoryStreamAccumulator(range: 100, now: { clock.now() })
        _ = exact.process(message(["sensor.a": [state("expired", at: 9_000), state("cutoff", at: 9_900)]]))
        let exactResult = exact.process(message(["sensor.a": []]))
        XCTAssertEqual(exactResult["sensor.a"]?.map(\.state), ["cutoff"])
    }

    func testAccumulatorClassifiesResetUnchangedNormalCutoffAndOutOfOrder() throws {
        let clock = LockedHistoryClock(Date(timeIntervalSince1970: 10_000))
        var accumulator = HAHistoryStreamAccumulator(range: 100, now: { clock.now() })
        let initial = accumulator.processPublication(message([
            "sensor.a": [
                state("old", at: 9_850),
                state("overlap-one", at: 9_920),
                state("overlap-two", at: 9_950),
            ],
        ]))
        XCTAssertEqual(initial.transition, .reset)

        let unchanged = accumulator.processPublication(message([:]))
        XCTAssertEqual(unchanged.transition, .unchanged)

        let normal = accumulator.processPublication(message([
            "sensor.a": [state("tail", at: 9_990)],
        ]))
        guard case .normal(let overlaps) = normal.transition else {
            return XCTFail("Expected trusted normal transition")
        }
        XCTAssertEqual(
            overlaps["sensor.a"],
            HAHistoryStreamEntityOverlap(oldStart: 1, newStart: 1, count: 2)
        )
        XCTAssertEqual(normal.history["sensor.a"]?.map(\.state), [
            "old", "overlap-one", "overlap-two", "tail",
        ])
        XCTAssertEqual(normal.history["sensor.a"]?.first?.lastUpdatedSeconds, 9_900)

        let outOfOrder = accumulator.processPublication(message([
            "sensor.a": [state("late-old", at: 9_930)],
        ]))
        XCTAssertEqual(outOfOrder.transition, .outOfOrderReset)
        XCTAssertEqual(outOfOrder.history["sensor.a"]?.map(\.state), [
            "old", "overlap-one", "late-old", "overlap-two", "tail",
        ])
    }

    func testUnsortedCutoffRetainedGapForcesExactFullProjection() async throws {
        let entityID = "sensor.unsorted_cutoff"
        var accumulator = HAHistoryStreamAccumulator(
            range: 15,
            now: { Date(timeIntervalSince1970: 40) }
        )
        let initial = accumulator.processPublication(message([
            entityID: [
                state("10", at: 10),
                state("30", at: 30),
                state("20", at: 20),
                state("40", at: 40),
            ],
        ]))
        let update = accumulator.processPublication(message([
            entityID: [state("40", at: 40)],
        ]))

        XCTAssertEqual(update.history[entityID]?.map(\.state), ["20", "30", "40", "40"])
        XCTAssertEqual(update.history[entityID]?.map(\.lastUpdatedSeconds), [25, 30, 40, 40])
        guard case .normal(let overlaps) = update.transition else {
            return XCTFail("The reference-compatible append stays a normal publication")
        }
        XCTAssertNil(
            overlaps[entityID],
            "Noncontiguous retained existing indices cannot describe one reusable slice"
        )

        let store = HAHistoryProjectionStore(orderedEntityIDs: [entityID])
        _ = await store.series(from: HAHistoryStreamPublication(
            history: initial.history,
            transition: initial.transition,
            ownerGeneration: 1
        ))
        let updatedProjection = await store.series(from: HAHistoryStreamPublication(
            history: update.history,
            transition: update.transition,
            ownerGeneration: 1
        ))
        let projected = try XCTUnwrap(updatedProjection?.first)
        let oracle = try XCTUnwrap(HAHistoryProjection.series(
            from: update.history,
            orderedEntityIDs: [entityID]
        ).first)

        XCTAssertEqual(projected.points, oracle.points)
        XCTAssertNil(projected.cacheLineage)
        let statistics = await store.statistics()
        XCTAssertEqual(
            statistics,
            HAHistoryProjectionStoreStatistics(
                fullEntityProjectionCount: 2,
                incrementalEntityProjectionCount: 0,
                reusedEntityProjectionCount: 0
            )
        )
    }

    func testCoordinatorCoalescingPreservesRelativeOverlapSafety() {
        let old = ["sensor.a": [state("old", at: 1)]]
        let middle = ["sensor.a": [state("middle", at: 2)]]
        let latest = ["sensor.a": [state("latest", at: 3)]]
        let reset = HAHistoryStreamPublication(
            history: old,
            transition: .reset,
            ownerGeneration: 7
        )
        let firstNormal = HAHistoryStreamPublication(
            history: middle,
            transition: .normal([
                "sensor.a": HAHistoryStreamEntityOverlap(oldStart: 0, newStart: 0, count: 1),
            ]),
            ownerGeneration: 7
        )
        let secondNormal = HAHistoryStreamPublication(
            history: latest,
            transition: .normal([
                "sensor.a": HAHistoryStreamEntityOverlap(oldStart: 0, newStart: 0, count: 1),
            ]),
            ownerGeneration: 7
        )
        let unchanged = HAHistoryStreamPublication(
            history: latest,
            transition: .unchanged,
            ownerGeneration: 7
        )

        let resetThenNormal = HAHistoryStreamCoordinator.coalescing(reset, with: firstNormal)
        XCTAssertEqual(resetThenNormal.history, middle)
        XCTAssertEqual(resetThenNormal.transition, .reset)

        let twoNormals = HAHistoryStreamCoordinator.coalescing(firstNormal, with: secondNormal)
        XCTAssertEqual(twoNormals.history, latest)
        XCTAssertEqual(twoNormals.transition, .reset)

        XCTAssertEqual(
            HAHistoryStreamCoordinator.coalescing(resetThenNormal, with: unchanged),
            resetThenNormal,
            "An empty update cannot erase a pending reset"
        )
    }

    func testRequestBuilderPinsWireParametersAndEveryAttributePolicyBranch() {
        let now = Date(timeIntervalSince1970: 1_767_225_600.5)
        let ordinary = HAState(entityId: "sensor.temperature", state: "20")
        let command = HAHistoryStreamCoordinator.command(
            entityIDs: ["sensor.temperature", "switch.lamp"],
            range: 3_600,
            currentStates: [
                ordinary.entityId: ordinary,
                "switch.lamp": HAState(entityId: "switch.lamp", state: "off"),
            ],
            now: now
        )

        XCTAssertEqual(command["type"], .string("history/stream"))
        XCTAssertEqual(command["entity_ids"], .array([.string("sensor.temperature"), .string("switch.lamp")]))
        XCTAssertEqual(command["minimal_response"], .bool(true))
        XCTAssertEqual(command["significant_changes_only"], .bool(true))
        XCTAssertEqual(command["no_attributes"], .bool(true))
        XCTAssertNil(command["end_time"])
        XCTAssertEqual(command["start_time"], .string("2025-12-31T23:00:00.500Z"))

        let requiredDomains = ["climate", "humidifier", "input_datetime", "water_heater", "person", "device_tracker"]
        for domain in requiredDomains {
            let entityID = "\(domain).test"
            XCTAssertTrue(HAHistoryAttributePolicy.needsAttributes(
                entityID: entityID,
                currentStates: [entityID: HAState(entityId: entityID, state: "on")]
            ))
        }
        XCTAssertTrue(HAHistoryAttributePolicy.needsAttributes(
            entityID: "sensor.missing",
            currentStates: [:]
        ))
        XCTAssertFalse(HAHistoryAttributePolicy.noAttributes(
            entityIDs: ["sensor.temperature", "person.joy"],
            currentStates: [
                "sensor.temperature": ordinary,
                "person.joy": HAState(entityId: "person.joy", state: "home"),
            ]
        ))
    }

    func testProjectionPreservesTimelineStatesUsesDomainTimestampRulesAndSparseAttributes() throws {
        let compact: [String: [HACompactHistoryState]] = [
            "switch.test": [
                state("off", at: 100, lc: 90, attributes: ["friendly_name": "Switch"]),
                state("unknown", at: 110),
                state("unavailable", at: 120),
                state("none", at: 130),
            ],
            "climate.room": [
                state("not-numeric", at: 200, lc: 150, attributes: [
                    "current_temperature": 21.5,
                    "ignored": "value",
                ]),
            ],
        ]
        let projected = HAHistoryProjection.series(
            from: compact,
            orderedEntityIDs: ["switch.test", "climate.room"],
            currentStates: [
                "switch.test": HAState(
                    entityId: "switch.test",
                    state: "none",
                    attributes: ["device_class": "switch"]
                ),
            ]
        )
        let timeline = try XCTUnwrap(projected.first)
        XCTAssertEqual(timeline.points.map(\.state), ["off", "unknown", "unavailable", "none"])
        XCTAssertEqual(timeline.points[1].attributes?["friendly_name"], .string("Switch"))
        let climate = try XCTUnwrap(projected.last)
        let timestamp = try XCTUnwrap(HAHistoryTimestampParser().timestamp(from: climate.points[0]))
        XCTAssertEqual(timestamp, 200, accuracy: 0.001)
        XCTAssertEqual(climate.points[0].attributes?["current_temperature"], .double(21.5))
        XCTAssertNil(climate.points[0].attributes?["ignored"])
        XCTAssertEqual(compact["switch.test"]?.count, 4, "Projection must not mutate compact storage")
    }

    func testProjectionStoreDoesNotReuseAcrossSameShapeMiddleCorrection() async throws {
        let entityID = "sensor.corrected"
        let initial = (0..<10).map { index in
            state("value-\(index)", at: Double(1_000 + index))
        }
        var corrected = initial
        corrected[5] = state("corrected", at: 1_005)
        let store = HAHistoryProjectionStore(orderedEntityIDs: [entityID])

        let firstProjection = await store.series(from: [entityID: initial])
        let replacementProjection = await store.series(from: [entityID: corrected])
        let first = try XCTUnwrap(firstProjection.first)
        let replacement = try XCTUnwrap(replacementProjection.first)
        let expected = try XCTUnwrap(HAHistoryProjection.series(
            from: [entityID: corrected],
            orderedEntityIDs: [entityID]
        ).first)
        let statistics = await store.statistics()

        XCTAssertEqual(replacement.points, expected.points)
        XCTAssertNotEqual(first.contentRevision, replacement.contentRevision)
        XCTAssertNil(first.cacheLineage)
        XCTAssertNil(replacement.cacheLineage)
        XCTAssertEqual(statistics.fullEntityProjectionCount, 2)
        XCTAssertEqual(statistics.incrementalEntityProjectionCount, 0)
    }

    func testProjectionStoreResetPreventsLineageAcrossOwnerGenerations() async throws {
        let entityID = "sensor.generation"
        let initial = [
            state("10", at: 1_000),
            state("20", at: 1_100),
            state("30", at: 1_200),
            state("40", at: 1_300),
        ]
        let rolling = [
            state("20", at: 1_150),
            initial[2],
            initial[3],
            state("50", at: 1_400),
        ]
        let store = HAHistoryProjectionStore(orderedEntityIDs: [entityID])

        let initialProjection = await store.series(from: HAHistoryStreamPublication(
            history: [entityID: initial],
            transition: .reset,
            ownerGeneration: 1
        ))
        let initialSeries = try XCTUnwrap(initialProjection?.first)
        let incrementalProjection = await store.series(from: HAHistoryStreamPublication(
            history: [entityID: rolling],
            transition: .normal([
                entityID: HAHistoryStreamEntityOverlap(oldStart: 2, newStart: 1, count: 2),
            ]),
            ownerGeneration: 1
        ))
        let incremental = try XCTUnwrap(incrementalProjection?.first)
        XCTAssertNil(initialSeries.cacheLineage)
        XCTAssertEqual(incremental.cacheLineage?.predecessorRevision, initialSeries.contentRevision)

        let freshProjection = await store.series(from: HAHistoryStreamPublication(
            history: [entityID: rolling],
            transition: .reset,
            ownerGeneration: 2
        ))
        let freshGeneration = try XCTUnwrap(freshProjection?.first)
        let stale = await store.series(from: HAHistoryStreamPublication(
            history: [entityID: initial],
            transition: .normal([
                entityID: HAHistoryStreamEntityOverlap(oldStart: 0, newStart: 0, count: 1),
            ]),
            ownerGeneration: 1
        ))
        let freshTail = rolling + [state("60", at: 1_500)]
        let afterStale = await store.series(from: HAHistoryStreamPublication(
            history: [entityID: freshTail],
            transition: .normal([
                entityID: HAHistoryStreamEntityOverlap(oldStart: 0, newStart: 0, count: 4),
            ]),
            ownerGeneration: 2
        ))
        let afterStaleSeries = try XCTUnwrap(afterStale?.first)
        let statistics = await store.statistics()
        XCTAssertNil(freshGeneration.cacheLineage)
        XCTAssertEqual(freshGeneration.points, incremental.points)
        XCTAssertNil(stale)
        XCTAssertEqual(
            afterStaleSeries.cacheLineage?.predecessorRevision,
            freshGeneration.contentRevision,
            "A rejected stale owner must not seed the fresh owner's lineage"
        )
        XCTAssertEqual(statistics.fullEntityProjectionCount, 2)
        XCTAssertEqual(statistics.incrementalEntityProjectionCount, 2)
    }

    func testHistorySeriesCodableDoesNotPersistTransientCacheLineage() throws {
        let points = [HAHistoryPoint(
            entityId: "sensor.codable",
            state: "1",
            attributes: nil,
            lastChanged: "2026-01-01T00:00:00Z",
            lastUpdated: "2026-01-01T00:00:00Z"
        )]
        let series = HAHistorySeries(
            entityID: "sensor.codable",
            points: points,
            contentRevision: 7,
            cacheLineage: HAHistorySeriesCacheLineage(
                predecessorRevision: 6,
                oldStart: 0,
                newStart: 0,
                count: 1
            )
        )

        let data = try JSONEncoder().encode(series)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(HAHistorySeries.self, from: data)

        XCTAssertFalse(encoded.contains("cacheLineage"))
        XCTAssertEqual(decoded.entityID, series.entityID)
        XCTAssertEqual(decoded.points, series.points)
        XCTAssertEqual(decoded.contentRevision, series.contentRevision)
        XCTAssertNil(decoded.cacheLineage)
    }

    func testCoordinatorUsesOneInitialOwnerFreshReconnectAccumulatorAndIdempotentCancellation() async throws {
        let first = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let second = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([first, second])
        let connection = makeConnection(factory)
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let clock = LockedHistoryClock(Date(timeIntervalSince1970: 10_000))
        let deliveries = HistoryPublicationLog()
        let statuses = HistoryStatusLog()

        let owner = try await client.subscribeHistoryStatesTimeWindow(
            entityIDs: ["sensor.a"],
            hoursToShow: 1,
            currentStates: ["sensor.a": HAState(entityId: "sensor.a", state: "1")],
            now: { clock.now() },
            onStatus: { await statuses.append($0) },
            onPublication: { await deliveries.append($0) }
        )
        let firstCommand = try await sentHistoryCommand(first)
        let firstSent = await first.sentObjects()
        XCTAssertEqual(firstSent.filter { $0["type"] == .string("history/stream") }.count, 1)
        let firstID = try XCTUnwrap(firstCommand["id"]?.testInt)
        try await first.push(historyEvent(id: firstID, states: ["sensor.a": [state("old", at: 9_900)]]))
        try await waitUntil { await deliveries.count() == 1 }

        clock.advance(by: 120)
        await first.pushFailure()
        try await waitUntil(iterations: 1_000_000) {
            guard factory.count() == 2 else { return false }
            return await connection.debugSnapshot().state == .ready
        }
        let secondCommand = try await sentHistoryCommand(second)
        let secondID = try XCTUnwrap(secondCommand["id"]?.testInt)
        XCTAssertNotEqual(firstCommand["start_time"], secondCommand["start_time"])
        let secondSent = await second.sentObjects()
        XCTAssertEqual(secondSent.filter { $0["type"] == .string("history/stream") }.count, 1)
        try await second.push(historyEvent(id: secondID, states: ["sensor.a": [state("fresh", at: 10_100)]]))
        try await waitUntil { await deliveries.count() == 2 }
        let snapshots = await deliveries.snapshot()
        XCTAssertEqual(snapshots[0].history["sensor.a"]?.map(\.state), ["old"])
        XCTAssertEqual(snapshots[1].history["sensor.a"]?.map(\.state), ["fresh"])
        XCTAssertEqual(snapshots[0].transition, .reset)
        XCTAssertEqual(snapshots[1].transition, .reset)
        XCTAssertGreaterThan(snapshots[1].ownerGeneration, snapshots[0].ownerGeneration)
        let statusSnapshot = await statuses.snapshot()
        XCTAssertTrue(statusSnapshot.contains(.ready))

        await owner.cancel()
        await owner.cancel()
        try await waitUntil {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0 &&
                snapshot.bufferedDeliveryCount == 0
        }
        await connection.disconnect()
        let final = await connection.debugSnapshot()
        XCTAssertEqual(final.pendingCommandCount, 0)
        XCTAssertEqual(final.receiveLoopCount, 0)
    }

    func testInitialSubscriptionRejectionSurfacesOwnerErrorAndLeavesNoOwnership() async throws {
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let factory = ScriptedTransportFactory([transport])
        let connection = makeConnection(factory)
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let statuses = HistoryStatusLog()
        let subscribe = Task {
            try await client.subscribeHistoryStatesTimeWindow(
                entityIDs: ["sensor.rejected"],
                hoursToShow: 1,
                currentStates: ["sensor.rejected": HAState(entityId: "sensor.rejected", state: "0")],
                onStatus: { await statuses.append($0) },
                onHistory: { _ in }
            )
        }
        let command = try await sentHistoryCommand(transport)
        let id = try XCTUnwrap(command["id"]?.testInt)
        try await transport.push([
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(false),
            "error": .object([
                "code": .string("invalid_format"),
                "message": .string("History unavailable"),
            ]),
        ])
        do {
            _ = try await subscribe.value
            XCTFail("Expected the initial history owner to fail")
        } catch {
            XCTAssertEqual(
                error as? HomeAssistantWebSocketError,
                .commandFailed(code: "invalid_format", message: "History unavailable")
            )
        }
        let statusSnapshot = await statuses.snapshot()
        XCTAssertTrue(statusSnapshot.contains(.error("Home Assistant command failed (invalid_format): History unavailable")))
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.subscriptionCount, 0)
        XCTAssertEqual(snapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(snapshot.deliveryOwnerCount, 0)
        await connection.disconnect()
    }

    func testReconnectRejectionIsOwnerLocalDoesNotBusyLoopAndExplicitRefreshRecoversFresh() async throws {
        let first = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let second = ScriptedWebSocketTransport(automaticAuthentication: true)
        let factory = ScriptedTransportFactory([first, second])
        let connection = makeConnection(factory)
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let clock = LockedHistoryClock(Date(timeIntervalSince1970: 20_000))
        let rejectedStatuses = HistoryStatusLog()
        let rejectedDeliveries = HistoryDeliveryLog()
        let liveStatuses = HistoryStatusLog()
        let liveDeliveries = HistoryDeliveryLog()

        var rejectedOwner: HAHistoryStreamSubscription? = try await client.subscribeHistoryStatesTimeWindow(
            entityIDs: ["sensor.rejected"],
            hoursToShow: 1,
            currentStates: ["sensor.rejected": HAState(entityId: "sensor.rejected", state: "0")],
            now: { clock.now() },
            onStatus: { await rejectedStatuses.append($0) },
            onHistory: { await rejectedDeliveries.append($0) }
        )
        var liveOwner: HAHistoryStreamSubscription? = try await client.subscribeHistoryStatesTimeWindow(
            entityIDs: ["sensor.live"],
            hoursToShow: 1,
            currentStates: ["sensor.live": HAState(entityId: "sensor.live", state: "0")],
            now: { clock.now() },
            onStatus: { await liveStatuses.append($0) },
            onHistory: { await liveDeliveries.append($0) }
        )
        weak var weakRejectedOwner = rejectedOwner
        weak var weakLiveOwner = liveOwner

        let initialCommands = try await sentHistoryCommands(first, count: 2)
        let initialRejected = try XCTUnwrap(initialCommands.first {
            commandEntityIDs($0) == ["sensor.rejected"]
        })
        let initialRejectedID = try XCTUnwrap(initialRejected["id"]?.testInt)
        try await first.push(historyEvent(
            id: initialRejectedID,
            states: ["sensor.rejected": [state("old", at: 19_900)]]
        ))
        try await waitUntil { await rejectedDeliveries.count() == 1 }

        clock.advance(by: 60)
        await first.pushFailure()
        try await waitUntil(iterations: 1_000_000) {
            guard factory.count() == 2 else { return false }
            return await connection.debugSnapshot().state == .ready
        }
        let reconnectCommands = try await sentHistoryCommands(second, count: 2)
        let rejectedReconnect = try XCTUnwrap(reconnectCommands.first {
            commandEntityIDs($0) == ["sensor.rejected"]
        })
        let liveReconnect = try XCTUnwrap(reconnectCommands.first {
            commandEntityIDs($0) == ["sensor.live"]
        })
        try await respond(
            to: rejectedReconnect,
            on: second,
            success: false,
            code: "history_unavailable",
            message: "Reconnect history unavailable"
        )
        try await respond(to: liveReconnect, on: second, success: true)

        let liveReconnectID = try XCTUnwrap(liveReconnect["id"]?.testInt)
        try await second.push(historyEvent(
            id: liveReconnectID,
            states: ["sensor.live": [state("still-live", at: 20_050)]]
        ))
        try await waitUntil {
            let statuses = await rejectedStatuses.snapshot()
            let liveCount = await liveDeliveries.count()
            return statuses.contains(.error(
                "Home Assistant command failed (history_unavailable): Reconnect history unavailable"
            )) && liveCount == 1
        }
        let liveStatusSnapshot = await liveStatuses.snapshot()
        XCTAssertFalse(liveStatusSnapshot.contains { status in
            if case .error = status { return true }
            return false
        })

        for _ in 0..<10_000 { await Task.yield() }
        let sentAfterRejection = await second.sentObjects()
        XCTAssertEqual(
            sentAfterRejection.filter { $0["type"] == .string("history/stream") }.count,
            2,
            "A reconnect rejection must not start a busy retry loop"
        )
        let afterRejection = await connection.debugSnapshot()
        XCTAssertEqual(afterRejection.pendingCommandCount, 0)
        XCTAssertEqual(afterRejection.subscriptionCount, 1)
        XCTAssertEqual(afterRejection.wireSubscriptionCount, 1)
        XCTAssertEqual(afterRejection.deliveryOwnerCount, 1)
        XCTAssertEqual(afterRejection.bufferedDeliveryCount, 0)

        clock.advance(by: 120)
        let refreshed = try await refreshAcknowledging(
            try XCTUnwrap(rejectedOwner),
            on: second,
            expectedHistoryCommandCount: 3
        )
        XCTAssertEqual(commandEntityIDs(refreshed), ["sensor.rejected"])
        XCTAssertNotEqual(rejectedReconnect["start_time"], refreshed["start_time"])
        let refreshedID = try XCTUnwrap(refreshed["id"]?.testInt)
        try await second.push(historyEvent(
            id: refreshedID,
            states: ["sensor.rejected": [state("fresh", at: 20_170)]]
        ))
        try await waitUntil { await rejectedDeliveries.count() == 2 }
        let rejectedHistory = await rejectedDeliveries.snapshot()
        XCTAssertEqual(rejectedHistory[0]["sensor.rejected"]?.map(\.state), ["old"])
        XCTAssertEqual(rejectedHistory[1]["sensor.rejected"]?.map(\.state), ["fresh"])

        try await cancelAcknowledging(rejectedOwner, on: second)
        try await cancelAcknowledging(liveOwner, on: second)
        rejectedOwner = nil
        liveOwner = nil
        try await waitUntil { weakRejectedOwner == nil && weakLiveOwner == nil }
        try await waitUntil {
            let snapshot = await connection.debugSnapshot()
            return snapshot.pendingCommandCount == 0 &&
                snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0 &&
                snapshot.bufferedDeliveryCount == 0 &&
                snapshot.activeDeliveryTaskCount == 0 &&
                snapshot.activeTerminationTaskCount == 0 &&
                snapshot.pendingTerminationCount == 0
        }
        await connection.disconnect()
        let final = await connection.debugSnapshot()
        XCTAssertEqual(final.pendingCommandCount, 0)
        XCTAssertEqual(final.subscriptionCount, 0)
        XCTAssertEqual(final.wireSubscriptionCount, 0)
        XCTAssertEqual(final.deliveryOwnerCount, 0)
        XCTAssertEqual(final.bufferedDeliveryCount, 0)
        XCTAssertEqual(final.receiveLoopCount, 0)
        XCTAssertEqual(final.activeDeliveryTaskCount, 0)
        XCTAssertEqual(final.activeTerminationTaskCount, 0)
        XCTAssertEqual(final.pendingTerminationCount, 0)
        let firstMetrics = await first.metrics()
        let secondMetrics = await second.metrics()
        XCTAssertEqual(firstMetrics.activeReceives, 0)
        XCTAssertEqual(secondMetrics.activeReceives, 0)
    }

    func testOneHundredHistoryReconnectCyclesHaveFreshStartsAndZeroFinalOwnership() async throws {
        let transports = (0...100).map { _ in
            ScriptedWebSocketTransport(
                automaticAuthentication: true,
                automaticSubscriptionAcknowledgement: true
            )
        }
        let factory = ScriptedTransportFactory(transports)
        let connection = makeConnection(factory)
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let clock = LockedHistoryClock(Date(timeIntervalSince1970: 50_000))
        var owner: HAHistoryStreamSubscription? = try await client.subscribeHistoryStatesTimeWindow(
            entityIDs: ["sensor.lifecycle"],
            hoursToShow: 1,
            currentStates: ["sensor.lifecycle": HAState(entityId: "sensor.lifecycle", state: "1")],
            now: { clock.now() },
            onHistory: { _ in }
        )
        weak var weakOwner = owner
        var starts: [JSONValue] = [try await sentHistoryCommand(transports[0])["start_time"]!]

        for cycle in 0..<100 {
            clock.advance(by: 1)
            await transports[cycle].pushFailure()
            try await waitUntil(iterations: 1_000_000) {
                guard factory.count() == cycle + 2 else { return false }
                return await connection.debugSnapshot().state == .ready
            }
            starts.append(try await sentHistoryCommand(transports[cycle + 1])["start_time"]!)
        }
        XCTAssertEqual(Set(starts.map { String(describing: $0) }).count, 101)

        await owner?.cancel()
        owner = nil
        try await waitUntil { weakOwner == nil }
        let beforeDisconnect = await connection.debugSnapshot()
        XCTAssertEqual(beforeDisconnect.subscriptionCount, 0)
        XCTAssertEqual(beforeDisconnect.wireSubscriptionCount, 0)
        XCTAssertEqual(beforeDisconnect.deliveryOwnerCount, 0)
        await connection.disconnect()
        let final = await connection.debugSnapshot()
        XCTAssertEqual(final.receiveLoopCount, 0)
        XCTAssertEqual(final.activeDeliveryTaskCount, 0)
        for transport in transports {
            let metrics = await transport.metrics()
            XCTAssertEqual(metrics.activeReceives, 0)
        }
    }

    func testOneHundredSubscribeCancelCyclesReleaseOwnersAndStorage() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([transport])
        let connection = makeConnection(factory)
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        weak var lastOwner: HAHistoryStreamSubscription?

        for cycle in 0..<100 {
            var owner: HAHistoryStreamSubscription? = try await client.subscribeHistoryStatesTimeWindow(
                entityIDs: ["sensor.cycle_\(cycle)"],
                hoursToShow: 1,
                currentStates: [
                    "sensor.cycle_\(cycle)": HAState(entityId: "sensor.cycle_\(cycle)", state: "0"),
                ],
                onHistory: { _ in }
            )
            lastOwner = owner
            await owner?.cancel()
            owner = nil
            try await waitUntil {
                let snapshot = await connection.debugSnapshot()
                return snapshot.subscriptionCount == 0 &&
                    snapshot.wireSubscriptionCount == 0 &&
                    snapshot.deliveryOwnerCount == 0 &&
                    snapshot.bufferedDeliveryCount == 0
            }
        }

        try await waitUntil { lastOwner == nil }
        await connection.disconnect()
        let final = await connection.debugSnapshot()
        XCTAssertEqual(final.pendingCommandCount, 0)
        XCTAssertEqual(final.subscriptionCount, 0)
        XCTAssertEqual(final.receiveLoopCount, 0)
        let metrics = await transport.metrics()
        XCTAssertEqual(metrics.activeReceives, 0)
    }

    private func makeConnection(_ factory: ScriptedTransportFactory) -> HomeAssistantWebSocketConnection {
        HomeAssistantWebSocketConnection(
            accessToken: "history-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            deliveryCapacity: 256,
            maximumConcurrentCallbackTasks: 4,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: factory.make
        )
    }

    private func sentHistoryCommand(
        _ transport: ScriptedWebSocketTransport
    ) async throws -> [String: JSONValue] {
        try await waitUntil(iterations: 1_000_000) {
            await transport.sentObjects().contains { $0["type"] == .string("history/stream") }
        }
        let sent = await transport.sentObjects()
        return try XCTUnwrap(sent.first {
            $0["type"] == .string("history/stream")
        })
    }

    private func sentHistoryCommands(
        _ transport: ScriptedWebSocketTransport,
        count: Int
    ) async throws -> [[String: JSONValue]] {
        try await waitUntil(iterations: 1_000_000) {
            await transport.sentObjects().filter {
                $0["type"] == .string("history/stream")
            }.count >= count
        }
        return await transport.sentObjects().filter {
            $0["type"] == .string("history/stream")
        }
    }

    private func commandEntityIDs(_ command: [String: JSONValue]) -> [String] {
        guard case let .array(values)? = command["entity_ids"] else { return [] }
        return values.compactMap(\.testString)
    }

    private func respond(
        to command: [String: JSONValue],
        on transport: ScriptedWebSocketTransport,
        success: Bool,
        code: String? = nil,
        message: String = ""
    ) async throws {
        let id = try XCTUnwrap(command["id"]?.testInt)
        var result: [String: JSONValue] = [
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(success),
            "result": .null,
        ]
        if !success {
            result["error"] = .object([
                "code": code.map(JSONValue.string) ?? .null,
                "message": .string(message),
            ])
        }
        try await transport.push(result)
    }

    private func cancelAcknowledging(
        _ owner: HAHistoryStreamSubscription?,
        on transport: ScriptedWebSocketTransport
    ) async throws {
        let previous = await transport.sentObjects().filter {
            $0["type"] == .string("unsubscribe_events")
        }.count
        let cancellation = Task { await owner?.cancel() }
        try await waitUntil(iterations: 1_000_000) {
            await transport.sentObjects().filter {
                $0["type"] == .string("unsubscribe_events")
            }.count > previous
        }
        let sent = await transport.sentObjects()
        let unsubscribe = try XCTUnwrap(sent.last {
            $0["type"] == .string("unsubscribe_events")
        })
        try await respond(to: unsubscribe, on: transport, success: true)
        await cancellation.value
    }

    private func refreshAcknowledging(
        _ owner: HAHistoryStreamSubscription,
        on transport: ScriptedWebSocketTransport,
        expectedHistoryCommandCount: Int
    ) async throws -> [String: JSONValue] {
        let refresh = Task { try await owner.refresh() }
        let commands = try await sentHistoryCommands(
            transport,
            count: expectedHistoryCommandCount
        )
        let command = commands[expectedHistoryCommandCount - 1]
        try await respond(to: command, on: transport, success: true)
        try await refresh.value
        return command
    }

    private func historyEvent(
        id: Int,
        states: [String: [HACompactHistoryState]]
    ) throws -> [String: JSONValue] {
        let payload = HAHistoryStreamMessage(states: states)
        let data = try JSONEncoder().encode(payload)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        return [
            "id": .int(id),
            "type": .string("event"),
            "event": value,
        ]
    }

    private func message(
        _ states: [String: [HACompactHistoryState]]
    ) -> HAHistoryStreamMessage {
        HAHistoryStreamMessage(states: states)
    }

    private func state(
        _ value: String,
        at timestamp: Double,
        lc: Double? = nil,
        attributes: [String: JSONValue] = [:]
    ) -> HACompactHistoryState {
        HACompactHistoryState(
            state: value,
            attributes: attributes,
            lastChangedSeconds: lc,
            lastUpdatedSeconds: timestamp
        )
    }
}

private final class LockedHistoryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}

private actor HistoryDeliveryLog {
    private var histories: [[String: [HACompactHistoryState]]] = []

    func append(_ history: [String: [HACompactHistoryState]]) {
        histories.append(history)
    }

    func count() -> Int { histories.count }
    func snapshot() -> [[String: [HACompactHistoryState]]] { histories }
}

private actor HistoryPublicationLog {
    private var publications: [HAHistoryStreamPublication] = []

    func append(_ publication: HAHistoryStreamPublication) {
        publications.append(publication)
    }

    func count() -> Int { publications.count }
    func snapshot() -> [HAHistoryStreamPublication] { publications }
}

private actor HistoryStatusLog {
    private var statuses: [HAHistoryStreamOwnerStatus] = []

    func append(_ status: HAHistoryStreamOwnerStatus) {
        statuses.append(status)
    }

    func snapshot() -> [HAHistoryStreamOwnerStatus] { statuses }
}
