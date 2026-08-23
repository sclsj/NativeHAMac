import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class HistoryStreamIntegrationTests: XCTestCase {
    func testVisibleCardsAreIsolatedUseTypedGlobalRangeAndPreserveRawHours() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "view-model-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let firstCard = LovelaceCard(
            type: "history-graph",
            title: "First",
            entities: [
                LovelaceEntityRef(entity: "sensor.a"),
                LovelaceEntityRef(entity: "sensor.shared"),
            ],
            hoursToShow: 12
        )
        let secondCard = LovelaceCard(
            type: "history-graph",
            title: "Second",
            entities: [
                LovelaceEntityRef(entity: "sensor.shared"),
                LovelaceEntityRef(entity: "sensor.b"),
            ],
            hoursToShow: 3
        )
        let states = [
            "sensor.a": HAState(entityId: "sensor.a", state: "1"),
            "sensor.shared": HAState(entityId: "sensor.shared", state: "2"),
            "sensor.b": HAState(entityId: "sensor.b", state: "3"),
        ]
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: states,
            initialViews: [LovelaceView(title: "Home", path: "default_view", cards: [firstCard, secondCard])],
            historyNow: { Date(timeIntervalSince1970: 10_000) }
        )

        await model.synchronizeHistorySubscriptionsForTesting()
        try await integrationWait {
            await transport.historyCommands().count == 2
        }
        XCTAssertEqual(model.homeCards.map(\.hoursToShow), [12, 3])
        XCTAssertEqual(AppConfig.graphTimeRangePolicy.scope, .global)
        XCTAssertEqual(AppConfig.graphTimeRangePolicy.availableSelections.map(\.hours), [1, 3, 6, 12])
        XCTAssertEqual(model.selectedGraphHours, 1)
        let firstKey = model.historyKey(for: model.homeCards[0])
        let secondKey = model.historyKey(for: model.homeCards[1])
        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertTrue(firstKey.contains("sensor.a,sensor.shared"))
        XCTAssertTrue(secondKey.contains("sensor.shared,sensor.b"))

        let commands = await transport.historyCommands()
        let firstCommand = try XCTUnwrap(commands.first { commandEntities($0) == ["sensor.a", "sensor.shared"] })
        let secondCommand = try XCTUnwrap(commands.first { commandEntities($0) == ["sensor.shared", "sensor.b"] })
        let firstID = try XCTUnwrap(firstCommand["id"]?.historyTestInt)
        let secondID = try XCTUnwrap(secondCommand["id"]?.historyTestInt)
        let firstGraphFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: model.homeCards[0]))
        var firstGraphResetFlags: [Bool] = []
        let firstGraphFeedToken = firstGraphFeed.subscribe { event in
            firstGraphResetFlags.append(event.resetPreparedState)
        }
        try await transport.pushHistory(id: firstID, states: [
            "sensor.a": [compact("10", 9_900)],
            "sensor.shared": [compact("20", 9_901)],
        ])
        try await integrationWait { await MainActor.run { model.histories[firstKey] != nil } }
        XCTAssertEqual(firstGraphResetFlags, [true], "Initial/reset projection must re-key graph preparation")
        try await transport.pushHistory(id: firstID, states: [
            "sensor.a": [compact("11", 9_902)],
            "sensor.shared": [compact("21", 9_903)],
        ])
        try await integrationWait { await MainActor.run { firstGraphResetFlags.count == 2 } }
        XCTAssertEqual(firstGraphResetFlags, [true, false], "Normal ordered updates must preserve graph lineage")
        try await transport.pushHistory(id: firstID, states: [
            "sensor.a": [compact("9", 9_800)],
            "sensor.shared": [compact("19", 9_801)],
        ])
        try await integrationWait { await MainActor.run { firstGraphResetFlags.count == 3 } }
        XCTAssertEqual(firstGraphResetFlags, [true, false, true], "Out-of-order reset must re-key graph preparation")
        firstGraphFeed.unsubscribe(firstGraphFeedToken)
        XCTAssertNil(model.histories[secondKey])
        try await transport.pushHistory(id: secondID, states: [
            "sensor.shared": [compact("21", 9_902)],
            "sensor.b": [compact("30", 9_903)],
        ])
        try await integrationWait { await MainActor.run { model.histories[secondKey] != nil } }
        XCTAssertEqual(model.histories[firstKey]?.map(\.entityID), ["sensor.a", "sensor.shared"])
        XCTAssertEqual(model.histories[secondKey]?.map(\.entityID), ["sensor.shared", "sensor.b"])

        let firstBeforeStateChange = model.histories[firstKey]
        model.states["sensor.a"] = HAState(entityId: "sensor.a", state: "999")
        XCTAssertEqual(model.histories[firstKey], firstBeforeStateChange, "state_changed must not double-append stream history")

        model.selectedGraphHours = 3
        await model.synchronizeHistorySubscriptionsForTesting()
        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return await transport.historyCommands().count == 4 && snapshot.subscriptionCount == 2
        }
        let newFirstKey = model.historyKey(for: model.homeCards[0])
        XCTAssertNotEqual(newFirstKey, firstKey)
        XCTAssertNil(model.histories[firstKey])
        XCTAssertEqual(model.homeCards.map(\.hoursToShow), [12, 3])

        model.loadDetailHistory(entityID: "sensor.a", hours: 1)
        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            let commands = await transport.historyCommands()
            return snapshot.subscriptionCount == 3 && commands.contains {
                self.commandEntities($0) == ["sensor.a"] &&
                    self.commandRangeHours($0, now: 10_000) == 24
            }
        }
        let detailCommands = await transport.historyCommands()
        XCTAssertTrue(detailCommands.contains {
            commandEntities($0) == ["sensor.a"] && commandRangeHours($0, now: 10_000) == 24
        })
        model.unloadDetailHistory(entityID: "sensor.a", hours: 24)
        try await integrationWait { await connection.debugSnapshot().subscriptionCount == 2 }

        model.loadDetailHistory(entityID: "sensor.b", hours: 24)
        model.unloadDetailHistory(entityID: "sensor.b", hours: 24)
        for _ in 0..<100 { await Task.yield() }
        let afterImmediateDetailDismissal = await connection.debugSnapshot()
        XCTAssertEqual(afterImmediateDetailDismissal.subscriptionCount, 2)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await model.synchronizeHistorySubscriptionsForTesting()
        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 && snapshot.deliveryOwnerCount == 0
        }
        await connection.disconnect()
    }

    func testStableIdentityIncludesOrderedEntitiesAndEffectiveRange() {
        let model = DashboardViewModel()
        let first = LovelaceCard(
            type: "history-graph",
            title: "Stable",
            entities: [LovelaceEntityRef(entity: "sensor.a"), LovelaceEntityRef(entity: "sensor.b")],
            hoursToShow: 12
        )
        let rebuilt = LovelaceCard(
            type: "history-graph",
            title: "Stable",
            entities: [LovelaceEntityRef(entity: "sensor.a"), LovelaceEntityRef(entity: "sensor.b")],
            hoursToShow: 12
        )
        let reversed = LovelaceCard(
            type: "history-graph",
            title: "Stable",
            entities: [LovelaceEntityRef(entity: "sensor.b"), LovelaceEntityRef(entity: "sensor.a")],
            hoursToShow: 12
        )

        XCTAssertEqual(model.historyKey(for: first), model.historyKey(for: rebuilt))
        XCTAssertNotEqual(model.historyKey(for: first), model.historyKey(for: reversed))
        XCTAssertEqual(first.hoursToShow, 12)

        let dashboard = DashboardViewModel(initialViews: [
            LovelaceView(title: "Home", path: "default_view", cards: [first, rebuilt]),
        ])
        XCTAssertEqual(
            dashboard.homeCards.map { $0.identity.sourcePath.description },
            ["views[0].cards[0]", "views[0].cards[1]"]
        )
        XCTAssertNotEqual(
            dashboard.historyKey(for: dashboard.homeCards[0]),
            dashboard.historyKey(for: dashboard.homeCards[1]),
            "Identical card occurrences must remain isolated owners"
        )
        let oneHour = model.historyKey(for: first)
        model.selectedGraphHours = 12
        XCTAssertNotEqual(model.historyKey(for: first), oneHour)
        XCTAssertEqual(first.hoursToShow, 12)
    }

    func testProductionHistoryProcessingGateAllowsDismissalAndCancellationSuppressesLatePublication() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "view-model-gate-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let processingGate = HistoryProcessingGate()
        let card = LovelaceCard(
            type: "history-graph",
            title: "Gated",
            entities: [LovelaceEntityRef(entity: "sensor.gated")]
        )
        var model: DashboardViewModel? = DashboardViewModel(
            webSocketClient: client,
            initialStates: ["sensor.gated": HAState(entityId: "sensor.gated", state: "0")],
            initialViews: [LovelaceView(title: "Home", path: "default_view", cards: [card])],
            historyNow: { Date(timeIntervalSince1970: 30_000) },
            historyProcessingHook: { await processingGate.wait() }
        )
        weak var weakModel = model

        await model?.synchronizeHistorySubscriptionsForTesting()
        let command = try await integrationHistoryCommand(transport, count: 1)
        let commandID = try XCTUnwrap(command["id"]?.historyTestInt)
        let largeReplay = (0..<20_000).map { index in
            HACompactHistoryState(
                state: "\(index)",
                lastUpdatedSeconds: 10_000 + Double(index)
            )
        }
        try await transport.pushHistory(
            id: commandID,
            states: ["sensor.gated": largeReplay]
        )
        try await integrationWait { await processingGate.waitingCount() == 1 }

        model?.openDetails(entityID: "sensor.unrelated")
        model?.showEntityIDs.toggle()
        model?.closeDetails()
        XCTAssertNil(model?.selectedEntityID, "Unrelated main-actor work must complete before gate release")
        let waitingBeforeCancellation = await processingGate.waitingCount()
        XCTAssertEqual(waitingBeforeCancellation, 1, "The production path must still be gated")

        let oldKey = try XCTUnwrap(model.map { $0.historyKey(for: $0.homeCards[0]) })
        await model?.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await model?.synchronizeHistorySubscriptionsForTesting()
        let cancelledBeforeRelease = await connection.debugSnapshot()
        XCTAssertEqual(cancelledBeforeRelease.pendingCommandCount, 0)
        XCTAssertEqual(cancelledBeforeRelease.subscriptionCount, 0)
        XCTAssertEqual(cancelledBeforeRelease.wireSubscriptionCount, 0)
        XCTAssertEqual(cancelledBeforeRelease.deliveryOwnerCount, 0)
        XCTAssertEqual(cancelledBeforeRelease.bufferedDeliveryCount, 0)
        XCTAssertNil(model?.histories[oldKey])

        await processingGate.open()
        for _ in 0..<10_000 { await Task.yield() }
        XCTAssertNil(model?.histories[oldKey], "A cancelled generation must not recreate stale history")
        XCTAssertNil(model?.historyStatuses[oldKey])

        model = nil
        try await integrationWait { weakModel == nil }
        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.pendingCommandCount == 0 &&
                snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0 &&
                snapshot.bufferedDeliveryCount == 0 &&
                snapshot.activeDeliveryTaskCount == 0 &&
                snapshot.activeTerminationTaskCount == 0 &&
                snapshot.pendingTerminationCount == 0 &&
                snapshot.receiveLoopCount == 0
        }
        let metrics = await transport.metrics()
        XCTAssertEqual(metrics.activeReceives, 0)
    }

    func testRapidRangeReconciliationSerializesAndUsesLatestRangeAfterDelayedAcknowledgement() async throws {
        let transport = HistoryViewModelTransport()
        await transport.setHistoryAcknowledgementsHeld(true)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "view-model-range-race-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let card = LovelaceCard(
            type: "history-graph",
            title: "Range race",
            entities: [LovelaceEntityRef(entity: "sensor.range_race")]
        )
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: ["sensor.range_race": HAState(entityId: "sensor.range_race", state: "0")],
            initialViews: [LovelaceView(title: "Home", path: "default_view", cards: [card])],
            historyNow: { Date(timeIntervalSince1970: 100_000) }
        )

        let initialSynchronization = Task {
            await model.synchronizeHistorySubscriptionsForTesting()
        }
        let oneHourCommand = try await integrationHistoryCommand(transport, count: 1)
        let oneHourID = try XCTUnwrap(oneHourCommand["id"]?.historyTestInt)
        let oneHourKey = model.historyKey(for: model.homeCards[0])
        var oneHourFeed: GraphHistoryRevisionFeed? = model.graphHistoryRevisionFeed(for: model.homeCards[0])
        weak var weakOneHourFeed = oneHourFeed

        model.setGraphHours(3)
        model.setGraphHours(12)
        let twelveHourKey = model.historyKey(for: model.homeCards[0])
        for _ in 0..<100 { await Task.yield() }
        let heldCommands = await transport.historyCommands()
        XCTAssertEqual(heldCommands.count, 1)

        oneHourFeed = nil
        try await transport.resolveHistoryAcknowledgement(id: oneHourID, success: true)
        let twelveHourCommand = try await integrationHistoryCommand(transport, count: 2)
        let twelveHourID = try XCTUnwrap(twelveHourCommand["id"]?.historyTestInt)

        XCTAssertEqual(commandRangeHours(oneHourCommand, now: 100_000), 1)
        XCTAssertEqual(commandRangeHours(twelveHourCommand, now: 100_000), 12)
        XCTAssertNotEqual(oneHourKey, twelveHourKey)
        let rangeCommands = await transport.historyCommands()
        XCTAssertEqual(rangeCommands.count, 2, "Queued range work must read the latest selection at execution")

        try await transport.resolveHistoryAcknowledgement(id: twelveHourID, success: true)
        await initialSynchronization.value

        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 1 &&
                snapshot.wireSubscriptionCount == 1 &&
                weakOneHourFeed == nil
        }
        XCTAssertNil(model.histories[oneHourKey])
        XCTAssertNil(model.historyStatuses[oneHourKey])
        XCTAssertNil(weakOneHourFeed)
        XCTAssertNotNil(model.graphHistoryRevisionFeed(for: model.homeCards[0]))

        try await transport.pushHistory(id: twelveHourID, states: [
            "sensor.range_race": [compact("12", 99_900)],
        ])
        try await integrationWait {
            await MainActor.run {
                model.histories[twelveHourKey] != nil && model.historyStatuses[twelveHourKey] == .ready
            }
        }
        XCTAssertEqual(model.histories.keys.sorted(), [twelveHourKey])
        XCTAssertEqual(model.historyStatuses.keys.sorted(), [twelveHourKey])

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await model.synchronizeHistorySubscriptionsForTesting()
        await connection.disconnect()
    }

    func testRejectedRefreshCannotRestoreRemovedOwnerState() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "view-model-refresh-race-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let card = LovelaceCard(
            type: "history-graph",
            title: "Refresh race",
            entities: [LovelaceEntityRef(entity: "sensor.refresh_race")]
        )
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: ["sensor.refresh_race": HAState(entityId: "sensor.refresh_race", state: "0")],
            initialViews: [LovelaceView(title: "Home", path: "default_view", cards: [card])],
            historyNow: { Date(timeIntervalSince1970: 200_000) }
        )

        await model.synchronizeHistorySubscriptionsForTesting()
        let initialCommand = try await integrationHistoryCommand(transport, count: 1)
        let initialID = try XCTUnwrap(initialCommand["id"]?.historyTestInt)
        let oldKey = model.historyKey(for: model.homeCards[0])
        try await transport.pushHistory(id: initialID, states: [
            "sensor.refresh_race": [compact("1", 199_900)],
        ])
        try await integrationWait {
            await MainActor.run {
                model.histories[oldKey] != nil && model.historyStatuses[oldKey] == .ready
            }
        }
        var oldFeed: GraphHistoryRevisionFeed? = model.graphHistoryRevisionFeed(for: model.homeCards[0])
        weak var weakOldFeed = oldFeed

        await transport.setHistoryAcknowledgementsHeld(true)
        model.refreshHistories()
        let refreshCommand = try await integrationHistoryCommand(transport, count: 2)
        let refreshID = try XCTUnwrap(refreshCommand["id"]?.historyTestInt)

        let removalApply = Task {
            await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.homeView?.title, "Home")
        XCTAssertNotNil(model.histories[oldKey])

        try await transport.resolveHistoryAcknowledgement(id: refreshID, success: false)
        await removalApply.value
        await model.synchronizeHistorySubscriptionsForTesting()
        oldFeed = nil
        XCTAssertNil(model.histories[oldKey])
        XCTAssertNil(model.historyStatuses[oldKey])

        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0 &&
                weakOldFeed == nil
        }
        for _ in 0..<1_000 { await Task.yield() }
        XCTAssertTrue(model.histories.isEmpty)
        XCTAssertTrue(model.historyStatuses.isEmpty)
        XCTAssertNil(weakOldFeed)
        XCTAssertNil(model.errorMessage)
        let historyCommandCount = await transport.historyCommands().count
        XCTAssertEqual(historyCommandCount, 2)

        await connection.disconnect()
    }

    func testPendingOwnerSurvivesReconciliationThatOnlyRemovesSibling() async throws {
        let transport = HistoryViewModelTransport()
        await transport.setHistoryAcknowledgementsHeld(true)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "view-model-surviving-owner-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let survivingCard = LovelaceCard(
            type: "history-graph",
            title: "Surviving",
            entities: [LovelaceEntityRef(entity: "sensor.surviving")]
        )
        let removedCard = LovelaceCard(
            type: "history-graph",
            title: "Removed",
            entities: [LovelaceEntityRef(entity: "sensor.removed")]
        )
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [
                "sensor.surviving": HAState(entityId: "sensor.surviving", state: "0"),
                "sensor.removed": HAState(entityId: "sensor.removed", state: "0"),
            ],
            initialViews: [
                LovelaceView(
                    title: "Home",
                    path: "default_view",
                    cards: [survivingCard, removedCard]
                ),
            ],
            historyNow: { Date(timeIntervalSince1970: 300_000) }
        )

        let initialSynchronization = Task {
            await model.synchronizeHistorySubscriptionsForTesting()
        }
        let survivingCommand = try await integrationHistoryCommand(transport, count: 1)
        let survivingID = try XCTUnwrap(survivingCommand["id"]?.historyTestInt)
        let survivingKey = model.historyKey(for: model.homeCards[0])

        let siblingRemovalApply = Task {
            await model.applyLovelaceConfigForTesting(LovelaceConfig(views: [
                LovelaceView(title: "Home", path: "default_view", cards: [survivingCard]),
            ]))
        }
        for _ in 0..<100 { await Task.yield() }
        let heldCommands = await transport.historyCommands()
        XCTAssertEqual(heldCommands.count, 1)

        try await transport.resolveHistoryAcknowledgement(id: survivingID, success: true)
        await initialSynchronization.value
        await siblingRemovalApply.value
        await model.synchronizeHistorySubscriptionsForTesting()

        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 1 && snapshot.wireSubscriptionCount == 1
        }
        let historyCommands = await transport.historyCommands()
        XCTAssertEqual(historyCommands.count, 1, "The removed sibling must never start after reconciliation")
        XCTAssertEqual(commandEntities(historyCommands[0]), ["sensor.surviving"])
        XCTAssertNotNil(model.graphHistoryRevisionFeed(for: model.homeCards[0]))
        XCTAssertEqual(model.historyStatuses[survivingKey], .loading)

        try await transport.pushHistory(id: survivingID, states: [
            "sensor.surviving": [compact("1", 299_900)],
        ])
        try await integrationWait {
            await MainActor.run {
                model.histories[survivingKey] != nil && model.historyStatuses[survivingKey] == .ready
            }
        }

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await model.synchronizeHistorySubscriptionsForTesting()
        await connection.disconnect()
    }

    func testInitialOwnerRejectionRetiresPendingOwnershipAndExplicitRefreshRecovers() async throws {
        let transport = HistoryViewModelTransport()
        await transport.setHistoryAcknowledgementsHeld(true)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "view-model-initial-retry-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let card = LovelaceCard(
            type: "history-graph",
            title: "Initial retry",
            entities: [LovelaceEntityRef(entity: "sensor.initial_retry")]
        )
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: ["sensor.initial_retry": HAState(entityId: "sensor.initial_retry", state: "0")],
            initialViews: [LovelaceView(title: "Home", path: "default_view", cards: [card])],
            historyNow: { Date(timeIntervalSince1970: 400_000) }
        )

        let initialSynchronization = Task {
            await model.synchronizeHistorySubscriptionsForTesting()
        }
        let rejectedCommand = try await integrationHistoryCommand(transport, count: 1)
        let rejectedID = try XCTUnwrap(rejectedCommand["id"]?.historyTestInt)
        let key = model.historyKey(for: model.homeCards[0])
        try await transport.resolveHistoryAcknowledgement(id: rejectedID, success: false)
        await initialSynchronization.value

        guard case .error = model.historyStatuses[key] else {
            return XCTFail("Initial rejection must remain visible as owner-local status")
        }
        XCTAssertNil(model.graphHistoryRevisionFeed(for: model.homeCards[0]))
        XCTAssertNil(model.histories[key])
        let rejectedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(rejectedSnapshot.subscriptionCount, 0)
        XCTAssertEqual(rejectedSnapshot.deliveryOwnerCount, 0)

        model.refreshHistories()
        let retryCommand = try await integrationHistoryCommand(transport, count: 2)
        let retryID = try XCTUnwrap(retryCommand["id"]?.historyTestInt)
        try await transport.resolveHistoryAcknowledgement(id: retryID, success: true)
        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 1 && snapshot.wireSubscriptionCount == 1
        }
        XCTAssertEqual(model.historyStatuses[key], .loading)
        XCTAssertNotNil(model.graphHistoryRevisionFeed(for: model.homeCards[0]))

        try await transport.pushHistory(id: retryID, states: [
            "sensor.initial_retry": [compact("1", 399_900)],
        ])
        try await integrationWait {
            await MainActor.run {
                model.histories[key] != nil && model.historyStatuses[key] == .ready
            }
        }
        let historyCommandCount = await transport.historyCommands().count
        XCTAssertEqual(historyCommandCount, 2, "Retry must be explicit rather than an automatic busy loop")

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await model.synchronizeHistorySubscriptionsForTesting()
        await connection.disconnect()
    }

    func testLovelaceIdenticalRefreshReusesOwnerAndReplacementRejectsLatePublication() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "lovelace-owner-reconcile-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func config(title: String) -> LovelaceConfig {
            return LovelaceConfig(views: [
                LovelaceView(title: "Home", path: "default_view", cards: [
                    LovelaceCard(
                        type: "history-graph",
                        title: title,
                        entities: [LovelaceEntityRef(entity: "sensor.config_owner")],
                        hoursToShow: 12
                    ),
                ]),
            ])
        }
        let initial = config(title: "Initial")
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: ["sensor.config_owner": HAState(entityId: "sensor.config_owner", state: "0")],
            initialViews: initial.views,
            historyNow: { Date(timeIntervalSince1970: 500_000) }
        )

        await model.synchronizeHistorySubscriptionsForTesting()
        let initialCommand = try await integrationHistoryCommand(transport, count: 1)
        let initialID = try XCTUnwrap(initialCommand["id"]?.historyTestInt)
        let initialKey = model.historyKey(for: model.homeCards[0])
        var initialFeed: GraphHistoryRevisionFeed? = try XCTUnwrap(
            model.graphHistoryRevisionFeed(for: model.homeCards[0])
        )
        weak var weakInitialFeed = initialFeed
        let initialGeneration = initialFeed?.generation

        await model.applyLovelaceConfigForTesting(config(title: "Initial"))
        let identicalCommandCount = await transport.historyCommands().count
        XCTAssertEqual(identicalCommandCount, 1, "Identical config must not churn wire ownership")
        XCTAssertTrue(model.graphHistoryRevisionFeed(for: model.homeCards[0]) === initialFeed)
        XCTAssertEqual(model.graphHistoryRevisionFeed(for: model.homeCards[0])?.generation, initialGeneration)
        XCTAssertEqual(model.historyKey(for: model.homeCards[0]), initialKey)

        await model.applyLovelaceConfigForTesting(config(title: "Replacement"))
        let replacementCommand = try await integrationHistoryCommand(transport, count: 2)
        let replacementID = try XCTUnwrap(replacementCommand["id"]?.historyTestInt)
        let replacementKey = model.historyKey(for: model.homeCards[0])
        XCTAssertNotEqual(replacementKey, initialKey)
        XCTAssertNil(model.histories[initialKey])
        XCTAssertNil(model.historyStatuses[initialKey])
        XCTAssertFalse(model.graphHistoryRevisionFeed(for: model.homeCards[0]) === initialFeed)
        initialFeed = nil
        try await integrationWait { weakInitialFeed == nil }
        let replacementSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(replacementSnapshot.subscriptionCount, 1)
        XCTAssertEqual(replacementSnapshot.wireSubscriptionCount, 1)

        try await transport.pushHistory(id: initialID, states: [
            "sensor.config_owner": [compact("stale", 499_800)],
        ])
        for _ in 0..<1_000 { await Task.yield() }
        XCTAssertNil(model.histories[initialKey])
        XCTAssertNil(model.histories[replacementKey], "Old subscription delivery cannot publish into replacement owner")

        try await transport.pushHistory(id: replacementID, states: [
            "sensor.config_owner": [compact("fresh", 499_900)],
        ])
        try await integrationWait {
            await MainActor.run { model.histories[replacementKey]?.first?.points.last?.state == "fresh" }
        }

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0
        }
        await connection.disconnect()
    }

    func testLovelaceInsertRemoveAndReorderRekeysOnlyAffectedPathOwners() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "lovelace-path-reconcile-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func card(_ name: String) -> LovelaceCard {
            LovelaceCard(
                type: "history-graph",
                title: name,
                entities: [LovelaceEntityRef(entity: "sensor.\(name.lowercased())")]
            )
        }
        func config(_ names: [String]) -> LovelaceConfig {
            var cards: [LovelaceCard] = []
            for name in names {
                cards.append(card(name))
            }
            return LovelaceConfig(views: [
                LovelaceView(title: "Home", path: "default_view", cards: cards),
            ])
        }
        let initial = config(["A", "B", "C"])
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: Dictionary(uniqueKeysWithValues: ["a", "b", "c", "x"].map {
                ("sensor.\($0)", HAState(entityId: "sensor.\($0)", state: "0"))
            }),
            initialViews: initial.views,
            historyNow: { Date(timeIntervalSince1970: 600_000) }
        )
        await model.synchronizeHistorySubscriptionsForTesting()
        try await integrationWait { await transport.historyCommands().count == 3 }
        let stableAFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: model.homeCards[0]))
        var oldBFeed: GraphHistoryRevisionFeed? = model.graphHistoryRevisionFeed(for: model.homeCards[1])
        var oldCFeed: GraphHistoryRevisionFeed? = model.graphHistoryRevisionFeed(for: model.homeCards[2])
        weak var weakOldBFeed = oldBFeed
        weak var weakOldCFeed = oldCFeed

        await model.applyLovelaceConfigForTesting(config(["A", "X", "B", "C"]))
        try await integrationWait { await transport.historyCommands().count == 6 }
        XCTAssertTrue(model.graphHistoryRevisionFeed(for: model.homeCards[0]) === stableAFeed)
        XCTAssertFalse(model.graphHistoryRevisionFeed(for: model.homeCards[2]) === oldBFeed)
        XCTAssertFalse(model.graphHistoryRevisionFeed(for: model.homeCards[3]) === oldCFeed)
        oldBFeed = nil
        oldCFeed = nil
        try await integrationWait { weakOldBFeed == nil && weakOldCFeed == nil }
        let insertedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(insertedSnapshot.subscriptionCount, 4)

        let insertedXFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: model.homeCards[1]))
        await model.applyLovelaceConfigForTesting(config(["A", "B", "C"]))
        try await integrationWait { await transport.historyCommands().count == 8 }
        XCTAssertTrue(model.graphHistoryRevisionFeed(for: model.homeCards[0]) === stableAFeed)
        XCTAssertFalse(model.graphHistoryRevisionFeed(for: model.homeCards[1]) === insertedXFeed)
        let removedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(removedSnapshot.subscriptionCount, 3)

        let beforeReorderB = try XCTUnwrap(model.graphHistoryRevisionFeed(for: model.homeCards[1]))
        let beforeReorderC = try XCTUnwrap(model.graphHistoryRevisionFeed(for: model.homeCards[2]))
        await model.applyLovelaceConfigForTesting(config(["A", "C", "B"]))
        try await integrationWait { await transport.historyCommands().count == 10 }
        XCTAssertTrue(model.graphHistoryRevisionFeed(for: model.homeCards[0]) === stableAFeed)
        XCTAssertFalse(model.graphHistoryRevisionFeed(for: model.homeCards[1]) === beforeReorderC)
        XCTAssertFalse(model.graphHistoryRevisionFeed(for: model.homeCards[2]) === beforeReorderB)
        let reorderedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(reorderedSnapshot.subscriptionCount, 3)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        try await integrationWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 && snapshot.deliveryOwnerCount == 0
        }
        await connection.disconnect()
    }

    func testConcurrentDistinctConfigsSerializeBehindGatedCancellationAndInstallOnlyLatest() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "serialized-config-cancel-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func config(_ name: String) -> LovelaceConfig {
            LovelaceConfig(views: [
                LovelaceView(title: name, path: "default_view", cards: [
                    LovelaceCard(
                        type: "history-graph",
                        title: name,
                        entities: [LovelaceEntityRef(entity: "sensor.\(name.lowercased())")]
                    ),
                ]),
            ])
        }
        let initial = config("Initial")
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [
                "sensor.initial": HAState(entityId: "sensor.initial", state: "0"),
                "sensor.middle": HAState(entityId: "sensor.middle", state: "0"),
                "sensor.latest": HAState(entityId: "sensor.latest", state: "0"),
            ],
            initialViews: initial.views
        )
        await model.synchronizeHistorySubscriptionsForTesting()
        try await integrationWait { await transport.historyCommands().count == 1 }
        await transport.setUnsubscribeAcknowledgementsHeld(true)

        let middleApply = Task { await model.applyLovelaceConfigForTesting(config("Middle")) }
        try await integrationWait { await transport.unsubscribeCommands().count == 1 }
        let latestApply = Task { await model.applyLovelaceConfigForTesting(config("Latest")) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.homeView?.title, "Initial")
        let historyCountWhileCancellationHeld = await transport.historyCommands().count
        XCTAssertEqual(historyCountWhileCancellationHeld, 1)

        let unsubscribeCommands = await transport.unsubscribeCommands()
        let unsubscribe = try XCTUnwrap(unsubscribeCommands.first)
        let unsubscribeID = try XCTUnwrap(unsubscribe["id"]?.historyTestInt)
        await transport.setUnsubscribeAcknowledgementsHeld(false)
        try await transport.resolveUnsubscribeAcknowledgement(id: unsubscribeID)
        await middleApply.value
        await latestApply.value
        try await integrationWait { await transport.historyCommands().count == 2 }
        XCTAssertEqual(model.homeView?.title, "Latest")
        let finalCommands = await transport.historyCommands()
        XCTAssertEqual(commandEntities(try XCTUnwrap(finalCommands.last)), ["sensor.latest"])
        let latestSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(latestSnapshot.subscriptionCount, 1)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    func testExternalRangeLoadWaitsForHeldConfigCancellationAndStartsOnlyLatestOwner() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "serialized-external-range-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func config(_ name: String) -> LovelaceConfig {
            LovelaceConfig(views: [
                LovelaceView(title: name, path: "default_view", cards: [
                    LovelaceCard(
                        type: "history-graph",
                        title: name,
                        entities: [LovelaceEntityRef(entity: "sensor.\(name.lowercased())")]
                    ),
                ]),
            ])
        }
        let initial = config("Initial")
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [
                "sensor.initial": HAState(entityId: "sensor.initial", state: "0"),
                "sensor.latest": HAState(entityId: "sensor.latest", state: "0"),
            ],
            initialViews: initial.views,
            historyNow: { Date(timeIntervalSince1970: 100_000) }
        )
        await model.synchronizeHistorySubscriptionsForTesting()
        let initialCommand = try await integrationHistoryCommand(transport, count: 1)
        let initialCommandID = try XCTUnwrap(initialCommand["id"]?.historyTestInt)
        let initialCard = try XCTUnwrap(model.homeCards.first)
        let initialKey = model.historyKey(for: initialCard)
        let initialFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: initialCard))
        try await transport.pushHistory(id: initialCommandID, states: [
            "sensor.initial": [compact("1", 99_900)],
        ])
        try await integrationWait { await MainActor.run { model.histories[initialKey] != nil } }
        let lifecycle = GraphChartMountedLifecycle()
        lifecycle.connect(feed: initialFeed, inputs: [], unit: "°C")
        let lease = model.graphChartMountRegistry.mount(
            ownerID: initialCard.nativeID,
            lifecycle: lifecycle
        )

        await transport.setUnsubscribeAcknowledgementsHeld(true)
        let latestApply = Task { await model.applyLovelaceConfigForTesting(config("Latest")) }
        try await integrationWait { await transport.unsubscribeCommands().count == 1 }

        model.setGraphHours(3)
        let externalLoad = Task { await model.synchronizeHistorySubscriptionsForTesting() }
        for _ in 0..<100 { await Task.yield() }
        let heldHistoryCommandCount = await transport.historyCommands().count
        XCTAssertEqual(heldHistoryCommandCount, 1)
        XCTAssertEqual(model.homeView?.title, "Initial")
        XCTAssertNotNil(model.histories[initialKey])
        XCTAssertNotNil(model.historyStatuses[initialKey])
        XCTAssertEqual(initialFeed.observerCount, 1)
        XCTAssertFalse(lifecycle.isInvalidated)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 1)

        let unsubscribeCommands = await transport.unsubscribeCommands()
        let unsubscribeID = try XCTUnwrap(unsubscribeCommands.first?["id"]?.historyTestInt)
        await transport.setUnsubscribeAcknowledgementsHeld(false)
        try await transport.resolveUnsubscribeAcknowledgement(id: unsubscribeID)
        await latestApply.value
        await externalLoad.value
        let latestCommand = try await integrationHistoryCommand(transport, count: 2)
        for _ in 0..<100 { await Task.yield() }

        let finalCommands = await transport.historyCommands()
        XCTAssertEqual(finalCommands.count, 2)
        XCTAssertEqual(commandEntities(latestCommand), ["sensor.latest"])
        XCTAssertEqual(commandRangeHours(latestCommand, now: 100_000), 3)
        XCTAssertEqual(model.homeView?.title, "Latest")
        XCTAssertNil(model.histories[initialKey])
        XCTAssertNil(model.historyStatuses[initialKey])
        XCTAssertEqual(initialFeed.observerCount, 0)
        XCTAssertTrue(lifecycle.isInvalidated)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 0)
        let latestSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(latestSnapshot.subscriptionCount, 1)
        XCTAssertEqual(latestSnapshot.wireSubscriptionCount, 1)
        XCTAssertEqual(latestSnapshot.deliveryOwnerCount, 1)

        try await transport.pushHistory(id: initialCommandID, states: [
            "sensor.initial": [compact("99", 99_950)],
        ])
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(model.histories[initialKey], "Late Initial delivery must remain suppressed")

        lease.cancel()
        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    func testConfigWaitsBehindEarlierHeldRangeCancellationBeforePublishingLatestOwner() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "serialized-range-before-config-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func config(_ name: String) -> LovelaceConfig {
            LovelaceConfig(views: [
                LovelaceView(title: name, path: "default_view", cards: [
                    LovelaceCard(
                        type: "history-graph",
                        title: name,
                        entities: [LovelaceEntityRef(entity: "sensor.\(name.lowercased())")]
                    ),
                ]),
            ])
        }
        let initial = config("Initial")
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [
                "sensor.initial": HAState(entityId: "sensor.initial", state: "0"),
                "sensor.latest": HAState(entityId: "sensor.latest", state: "0"),
            ],
            initialViews: initial.views,
            historyNow: { Date(timeIntervalSince1970: 100_000) }
        )
        await model.synchronizeHistorySubscriptionsForTesting()
        _ = try await integrationHistoryCommand(transport, count: 1)

        await transport.setUnsubscribeAcknowledgementsHeld(true)
        model.setGraphHours(3)
        try await integrationWait { await transport.unsubscribeCommands().count == 1 }
        let latestApply = Task { await model.applyLovelaceConfigForTesting(config("Latest")) }
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(model.homeView?.title, "Initial")
        let heldCommands = await transport.historyCommands()
        XCTAssertEqual(heldCommands.count, 1)

        let unsubscribeCommands = await transport.unsubscribeCommands()
        let unsubscribeID = try XCTUnwrap(unsubscribeCommands.first?["id"]?.historyTestInt)
        await transport.setUnsubscribeAcknowledgementsHeld(false)
        try await transport.resolveUnsubscribeAcknowledgement(id: unsubscribeID)
        await latestApply.value
        let latestCommand = try await integrationHistoryCommand(transport, count: 2)
        for _ in 0..<100 { await Task.yield() }

        let finalCommands = await transport.historyCommands()
        XCTAssertEqual(finalCommands.count, 2)
        XCTAssertEqual(commandEntities(latestCommand), ["sensor.latest"])
        XCTAssertEqual(commandRangeHours(latestCommand, now: 100_000), 3)
        XCTAssertEqual(model.homeView?.title, "Latest")
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.subscriptionCount, 1)
        XCTAssertEqual(snapshot.wireSubscriptionCount, 1)
        XCTAssertEqual(snapshot.deliveryOwnerCount, 1)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    func testConfigWaitsForExternalInFlightStartupAcknowledgementAndCancellation() async throws {
        let transport = HistoryViewModelTransport()
        await transport.setHistoryAcknowledgementsHeld(true)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "serialized-external-start-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func config(_ name: String) -> LovelaceConfig {
            LovelaceConfig(views: [
                LovelaceView(title: name, path: "default_view", cards: [
                    LovelaceCard(
                        type: "history-graph",
                        title: name,
                        entities: [LovelaceEntityRef(entity: "sensor.\(name.lowercased())")]
                    ),
                ]),
            ])
        }
        let initial = config("External")
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [
                "sensor.external": HAState(entityId: "sensor.external", state: "0"),
                "sensor.latest": HAState(entityId: "sensor.latest", state: "0"),
            ],
            initialViews: initial.views
        )
        let externalStartup = Task { await model.synchronizeHistorySubscriptionsForTesting() }
        let initialCommand = try await integrationHistoryCommand(transport, count: 1)
        let initialID = try XCTUnwrap(initialCommand["id"]?.historyTestInt)
        let latestApply = Task { await model.applyLovelaceConfigForTesting(config("Latest")) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.homeView?.title, "External")
        let historyCountWhileStartupHeld = await transport.historyCommands().count
        XCTAssertEqual(historyCountWhileStartupHeld, 1)

        await transport.setUnsubscribeAcknowledgementsHeld(true)
        await transport.setHistoryAcknowledgementsHeld(false)
        try await transport.resolveHistoryAcknowledgement(id: initialID, success: true)
        try await integrationWait { await transport.unsubscribeCommands().count == 1 }
        XCTAssertEqual(model.homeView?.title, "External")
        let countWhileStartupCancellationHeld = await transport.historyCommands().count
        XCTAssertEqual(countWhileStartupCancellationHeld, 1)
        let cancellationCommands = await transport.unsubscribeCommands()
        let cancellationID = try XCTUnwrap(cancellationCommands.first?["id"]?.historyTestInt)
        await transport.setUnsubscribeAcknowledgementsHeld(false)
        try await transport.resolveUnsubscribeAcknowledgement(id: cancellationID)
        await externalStartup.value
        await latestApply.value
        try await integrationWait { await transport.historyCommands().count == 2 }
        XCTAssertEqual(model.homeView?.title, "Latest")
        let finalCommands = await transport.historyCommands()
        XCTAssertEqual(commandEntities(try XCTUnwrap(finalCommands.last)), ["sensor.latest"])
        let latestSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(latestSnapshot.subscriptionCount, 1)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    func testConcurrentIdenticalConfigAppliesCoalesceDuringGatedStartup() async throws {
        let transport = HistoryViewModelTransport()
        await transport.setHistoryAcknowledgementsHeld(true)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "coalesced-identical-config-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let config = LovelaceConfig(views: [
            LovelaceView(title: "Identical", path: "default_view", cards: [
                LovelaceCard(
                    type: "history-graph",
                    title: "Identical",
                    entities: [LovelaceEntityRef(entity: "sensor.identical")]
                ),
            ]),
        ])
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: ["sensor.identical": HAState(entityId: "sensor.identical", state: "0")]
        )
        let firstApply = Task { await model.applyLovelaceConfigForTesting(config) }
        let command = try await integrationHistoryCommand(transport, count: 1)
        let commandID = try XCTUnwrap(command["id"]?.historyTestInt)
        let secondApply = Task { await model.applyLovelaceConfigForTesting(config) }
        for _ in 0..<100 { await Task.yield() }
        let heldCommandCount = await transport.historyCommands().count
        XCTAssertEqual(heldCommandCount, 1)

        await transport.setHistoryAcknowledgementsHeld(false)
        try await transport.resolveHistoryAcknowledgement(id: commandID, success: true)
        await firstApply.value
        await secondApply.value
        XCTAssertEqual(model.homeView?.title, "Identical")
        let finalCommandCount = await transport.historyCommands().count
        XCTAssertEqual(finalCommandCount, 1)
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.subscriptionCount, 1)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    func testSupersededStartupRetainsUnaffectedOwnerAndCancelsOnlyReplacedOwner() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "serialized-affected-only-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func historyCard(_ name: String) -> LovelaceCard {
            LovelaceCard(
                type: "history-graph",
                title: name,
                entities: [LovelaceEntityRef(entity: "sensor.\(name.lowercased())")]
            )
        }
        func config(title: String, changing: String?) -> LovelaceConfig {
            var cards = [historyCard("Stable")]
            if let changing = changing { cards.append(historyCard(changing)) }
            return LovelaceConfig(views: [
                LovelaceView(title: title, path: "default_view", cards: cards),
            ])
        }
        let initial = config(title: "Initial", changing: nil)
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: ["stable", "middle", "latest"].reduce(into: [:]) {
                $0["sensor.\($1)"] = HAState(entityId: "sensor.\($1)", state: "0")
            },
            initialViews: initial.views
        )
        await model.synchronizeHistorySubscriptionsForTesting()
        try await integrationWait { await transport.historyCommands().count == 1 }
        let stableFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: model.homeCards[0]))

        await transport.setHistoryAcknowledgementsHeld(true)
        let middleApply = Task {
            await model.applyLovelaceConfigForTesting(config(title: "Middle", changing: "Middle"))
        }
        let middleCommand = try await integrationHistoryCommand(transport, count: 2)
        let middleID = try XCTUnwrap(middleCommand["id"]?.historyTestInt)
        let latestApply = Task {
            await model.applyLovelaceConfigForTesting(config(title: "Latest", changing: "Latest"))
        }
        for _ in 0..<100 { await Task.yield() }
        let heldCommandCount = await transport.historyCommands().count
        XCTAssertEqual(heldCommandCount, 2)

        await transport.setHistoryAcknowledgementsHeld(false)
        try await transport.resolveHistoryAcknowledgement(id: middleID, success: true)
        await middleApply.value
        await latestApply.value
        try await integrationWait { await transport.historyCommands().count == 3 }
        XCTAssertEqual(model.homeView?.title, "Latest")
        XCTAssertTrue(model.graphHistoryRevisionFeed(for: model.homeCards[0]) === stableFeed)
        let finalCommands = await transport.historyCommands()
        XCTAssertEqual(commandEntities(try XCTUnwrap(finalCommands.last)), ["sensor.latest"])
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.subscriptionCount, 2)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    func testExactRevertRestoresOwnershipAndCoalescedCallerAwaitsStableLatestTail() async throws {
        let transport = HistoryViewModelTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "serialized-exact-revert-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        func config(_ name: String) -> LovelaceConfig {
            LovelaceConfig(views: [
                LovelaceView(title: name, path: "default_view", cards: [
                    LovelaceCard(
                        type: "history-graph",
                        title: name,
                        entities: [LovelaceEntityRef(entity: "sensor.\(name.lowercased())")]
                    ),
                ]),
            ])
        }
        let initial = config("Initial")
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [
                "sensor.initial": HAState(entityId: "sensor.initial", state: "0"),
                "sensor.middle": HAState(entityId: "sensor.middle", state: "0"),
            ],
            initialViews: initial.views,
            historyNow: { Date(timeIntervalSince1970: 2_000) }
        )
        await model.synchronizeHistorySubscriptionsForTesting()
        try await integrationWait { await transport.historyCommands().count == 1 }
        let initialCard = try XCTUnwrap(model.homeCards.first)
        let initialKey = model.historyKey(for: initialCard)
        let initialFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: initialCard))
        let initialCommands = await transport.historyCommands()
        let initialCommandID = try XCTUnwrap(initialCommands.first?["id"]?.historyTestInt)
        try await transport.pushHistory(id: initialCommandID, states: [
            "sensor.initial": [compact("1", 1_900)],
        ])
        try await integrationWait { await MainActor.run { model.histories[initialKey] != nil } }
        let lifecycle = GraphChartMountedLifecycle()
        lifecycle.connect(feed: initialFeed, inputs: [], unit: "°C")
        let lease = model.graphChartMountRegistry.mount(
            ownerID: initialCard.nativeID,
            lifecycle: lifecycle
        )
        XCTAssertEqual(initialFeed.observerCount, 1)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 1)

        await transport.setUnsubscribeAcknowledgementsHeld(true)
        let middleApply = Task { await model.applyLovelaceConfigForTesting(config("Middle")) }
        try await integrationWait { await transport.unsubscribeCommands().count == 1 }
        XCTAssertEqual(model.homeView?.title, "Initial")
        XCTAssertNotNil(model.histories[initialKey], "Visible data must remain installed while cancellation is held")
        XCTAssertFalse(lifecycle.isInvalidated)

        var coalescedReturned = false
        let coalescedMiddleApply = Task { @MainActor in
            await model.applyLovelaceConfigForTesting(config("Middle"))
            coalescedReturned = true
        }
        let initialRevert = Task { await model.applyLovelaceConfigForTesting(initial) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(coalescedReturned)

        await transport.setHistoryAcknowledgementsHeld(true)
        let unsubscribeCommands = await transport.unsubscribeCommands()
        let unsubscribeID = try XCTUnwrap(unsubscribeCommands.first?["id"]?.historyTestInt)
        await transport.setUnsubscribeAcknowledgementsHeld(false)
        try await transport.resolveUnsubscribeAcknowledgement(id: unsubscribeID)
        let restoredCommand = try await integrationHistoryCommand(transport, count: 2)
        let restoredID = try XCTUnwrap(restoredCommand["id"]?.historyTestInt)
        XCTAssertEqual(model.homeView?.title, "Initial")
        XCTAssertFalse(coalescedReturned, "Coalesced caller must await the stable latest tail")
        XCTAssertFalse(lifecycle.isInvalidated)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 1)

        await transport.setHistoryAcknowledgementsHeld(false)
        try await transport.resolveHistoryAcknowledgement(id: restoredID, success: true)
        await middleApply.value
        await coalescedMiddleApply.value
        await initialRevert.value
        XCTAssertTrue(coalescedReturned)
        XCTAssertEqual(model.homeView?.title, "Initial")
        let restoredCard = try XCTUnwrap(model.homeCards.first)
        let restoredFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: restoredCard))
        XCTAssertFalse(restoredFeed === initialFeed)
        lifecycle.connect(feed: restoredFeed, inputs: [], unit: "°C")
        XCTAssertEqual(initialFeed.observerCount, 0)
        XCTAssertEqual(restoredFeed.observerCount, 1)
        XCTAssertFalse(lifecycle.isInvalidated)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 1)
        let finalSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(finalSnapshot.subscriptionCount, 1)
        XCTAssertEqual(finalSnapshot.wireSubscriptionCount, 1)

        lease.cancel()
        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    func testSupersededRetirementPreservesMountedVisualsForLaterSameOwnerRestart() async throws {
        let transport = HistoryViewModelTransport()
        await transport.setHistoryAcknowledgementsHeld(true)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "serialized-stale-retire-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        try await connection.connect()
        let client = HomeAssistantWebSocketClient(connection: connection)
        let stableCard = LovelaceCard(
            type: "history-graph",
            title: "Stable",
            entities: [LovelaceEntityRef(entity: "sensor.stable")]
        )
        let gatedCard = LovelaceCard(
            type: "history-graph",
            title: "Gated",
            entities: [LovelaceEntityRef(entity: "sensor.gated")]
        )
        func config(_ title: String, cards: [LovelaceCard]) -> LovelaceConfig {
            LovelaceConfig(views: [
                LovelaceView(title: title, path: "default_view", cards: cards),
            ])
        }
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [
                "sensor.stable": HAState(entityId: "sensor.stable", state: "0"),
                "sensor.gated": HAState(entityId: "sensor.gated", state: "0"),
            ],
            historyNow: { Date(timeIntervalSince1970: 400_000) }
        )

        let bApply = Task {
            await model.applyLovelaceConfigForTesting(config("B", cards: [stableCard, gatedCard]))
        }
        let stableCommand = try await integrationHistoryCommand(transport, count: 1)
        let stableID = try XCTUnwrap(stableCommand["id"]?.historyTestInt)
        try await transport.resolveHistoryAcknowledgement(id: stableID, success: true)
        let gatedCommand = try await integrationHistoryCommand(transport, count: 2)
        let gatedID = try XCTUnwrap(gatedCommand["id"]?.historyTestInt)
        let publishedStableCard = try XCTUnwrap(model.homeCards.first)
        let stableKey = model.historyKey(for: publishedStableCard)
        let oldFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: publishedStableCard))
        try await transport.pushHistory(id: stableID, states: [
            "sensor.stable": [compact("1", 399_900)],
        ])
        try await integrationWait { await MainActor.run { model.histories[stableKey] != nil } }
        let lifecycle = GraphChartMountedLifecycle()
        lifecycle.connect(feed: oldFeed, inputs: [], unit: "°C")
        let lease = model.graphChartMountRegistry.mount(
            ownerID: publishedStableCard.nativeID,
            lifecycle: lifecycle
        )

        let cApply = Task {
            await model.applyLovelaceConfigForTesting(config("C", cards: []))
        }
        await transport.setUnsubscribeAcknowledgementsHeld(true)
        try await transport.resolveHistoryAcknowledgement(id: gatedID, success: true)
        try await integrationWait { await transport.unsubscribeCommands().count == 1 }
        let gatedUnsubscribe = await transport.unsubscribeCommands()
        let gatedUnsubscribeID = try XCTUnwrap(gatedUnsubscribe.first?["id"]?.historyTestInt)
        try await transport.resolveUnsubscribeAcknowledgement(id: gatedUnsubscribeID)
        try await integrationWait { await transport.unsubscribeCommands().count == 2 }

        let dApply = Task {
            await model.applyLovelaceConfigForTesting(config("D", cards: [stableCard]))
        }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.homeView?.title, "B", "Intermediate C must never publish")
        XCTAssertNotNil(model.histories[stableKey])
        XCTAssertNotNil(model.historyStatuses[stableKey])
        XCTAssertEqual(oldFeed.observerCount, 1)
        XCTAssertFalse(lifecycle.isInvalidated)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 1)
        let heldHistoryCommands = await transport.historyCommands()
        XCTAssertEqual(heldHistoryCommands.count, 2)

        let retireUnsubscribes = await transport.unsubscribeCommands()
        let stableUnsubscribeID = try XCTUnwrap(retireUnsubscribes.last?["id"]?.historyTestInt)
        await transport.setUnsubscribeAcknowledgementsHeld(false)
        try await transport.resolveUnsubscribeAcknowledgement(id: stableUnsubscribeID)
        let restartedStableCommand = try await integrationHistoryCommand(transport, count: 3)
        let restartedStableID = try XCTUnwrap(restartedStableCommand["id"]?.historyTestInt)
        XCTAssertEqual(commandEntities(restartedStableCommand), ["sensor.stable"])
        try await transport.resolveHistoryAcknowledgement(id: restartedStableID, success: true)

        await bApply.value
        await cApply.value
        await dApply.value
        XCTAssertEqual(model.homeView?.title, "D")
        let stableCommands = await transport.historyCommands().filter {
            commandEntities($0) == ["sensor.stable"]
        }
        XCTAssertEqual(stableCommands.count, 2, "Stable owner must restart exactly once")
        let finalCard = try XCTUnwrap(model.homeCards.first)
        XCTAssertEqual(finalCard.nativeID, publishedStableCard.nativeID)
        let newFeed = try XCTUnwrap(model.graphHistoryRevisionFeed(for: finalCard))
        XCTAssertFalse(newFeed === oldFeed)
        lifecycle.connect(feed: newFeed, inputs: [], unit: "°C")
        XCTAssertEqual(oldFeed.observerCount, 0)
        XCTAssertEqual(newFeed.observerCount, 1)
        XCTAssertFalse(lifecycle.isInvalidated)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 1)
        let finalSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(finalSnapshot.subscriptionCount, 1)
        XCTAssertEqual(finalSnapshot.wireSubscriptionCount, 1)
        XCTAssertEqual(finalSnapshot.deliveryOwnerCount, 1)

        let acceptedBeforeLateDelivery = model.histories[stableKey]
        try await transport.pushHistory(id: stableID, states: [
            "sensor.stable": [compact("99", 399_950)],
        ])
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.histories[stableKey], acceptedBeforeLateDelivery)

        lease.cancel()
        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        await connection.disconnect()
    }

    private func integrationHistoryCommand(
        _ transport: HistoryViewModelTransport,
        count: Int
    ) async throws -> [String: JSONValue] {
        try await integrationWait { await transport.historyCommands().count >= count }
        let commands = await transport.historyCommands()
        return try XCTUnwrap(commands.last)
    }

    private func commandEntities(_ command: [String: JSONValue]) -> [String] {
        guard case let .array(values)? = command["entity_ids"] else { return [] }
        return values.compactMap {
            guard case let .string(value) = $0 else { return nil }
            return value
        }
    }

    private func commandRangeHours(_ command: [String: JSONValue], now: Double) -> Int? {
        guard
            case let .string(start)? = command["start_time"],
            let date = ISO8601DateFormatter.historyFractional.date(from: start)
                ?? ISO8601DateFormatter().date(from: start)
        else { return nil }
        return Int((now - date.timeIntervalSince1970) / 3_600)
    }

    private func compact(_ state: String, _ timestamp: Double) -> HACompactHistoryState {
        HACompactHistoryState(state: state, lastUpdatedSeconds: timestamp)
    }
}

private actor HistoryViewModelTransport: HomeAssistantWebSocketTransport {
    private var connected = false
    private var inbound: [Result<HAWebSocketFrame, Error>] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var sent: [[String: JSONValue]] = []
    private var activeReceives = 0
    private var historyAcknowledgementsHeld = false
    private var unsubscribeAcknowledgementsHeld = false

    func connect() async throws {
        connected = true
        try deliver(object: ["type": .string("auth_required")])
    }

    func send(_ frame: HAWebSocketFrame) async throws {
        let object = try decode(frame)
        sent.append(object)
        if object["type"] == .string("auth") {
            try deliver(object: ["type": .string("auth_ok"), "ha_version": .string("2025.7.0")])
        } else if
            let id = object["id"]?.historyTestInt,
            object["type"] == .string("history/stream")
        {
            guard !historyAcknowledgementsHeld else { return }
            try deliver(object: [
                "id": .int(id),
                "type": .string("result"),
                "success": .bool(true),
                "result": .null,
            ])
        } else if
            let id = object["id"]?.historyTestInt,
            object["type"] == .string("unsubscribe_events")
        {
            guard !unsubscribeAcknowledgementsHeld else { return }
            try deliver(object: [
                "id": .int(id),
                "type": .string("result"),
                "success": .bool(true),
                "result": .null,
            ])
        }
    }

    func receive() async throws -> HAWebSocketFrame {
        guard connected else { throw HomeAssistantWebSocketError.disconnected }
        if !inbound.isEmpty { return try inbound.removeFirst().get() }
        activeReceives += 1
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }

    func disconnect() async {
        connected = false
        if let receiver = receiver {
            self.receiver = nil
            activeReceives -= 1
            receiver.resume(throwing: HomeAssistantWebSocketError.disconnected)
        }
    }

    func historyCommands() -> [[String: JSONValue]] {
        sent.filter { $0["type"] == .string("history/stream") }
    }

    func setHistoryAcknowledgementsHeld(_ held: Bool) {
        historyAcknowledgementsHeld = held
    }

    func setUnsubscribeAcknowledgementsHeld(_ held: Bool) {
        unsubscribeAcknowledgementsHeld = held
    }

    func unsubscribeCommands() -> [[String: JSONValue]] {
        sent.filter { $0["type"] == .string("unsubscribe_events") }
    }

    func resolveUnsubscribeAcknowledgement(id: Int) throws {
        try deliver(object: [
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": .null,
        ])
    }

    func resolveHistoryAcknowledgement(id: Int, success: Bool) throws {
        var result: [String: JSONValue] = [
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(success),
            "result": .null,
        ]
        if !success {
            result["error"] = .object([
                "code": .string("test_rejected"),
                "message": .string("Rejected by deterministic history test gate"),
            ])
        }
        try deliver(object: result)
    }

    func pushHistory(id: Int, states: [String: [HACompactHistoryState]]) throws {
        let data = try JSONEncoder().encode(HAHistoryStreamMessage(states: states))
        let payload = try JSONDecoder().decode(JSONValue.self, from: data)
        try deliver(object: ["id": .int(id), "type": .string("event"), "event": payload])
    }

    func metrics() -> (activeReceives: Int, sentCount: Int) {
        (activeReceives, sent.count)
    }

    private func deliver(object: [String: JSONValue]) throws {
        let data = try JSONEncoder().encode(JSONValue.object(object))
        let frame = HAWebSocketFrame.string(String(decoding: data, as: UTF8.self))
        if let receiver = receiver {
            self.receiver = nil
            activeReceives -= 1
            receiver.resume(returning: frame)
        } else {
            inbound.append(.success(frame))
        }
    }

    private func decode(_ frame: HAWebSocketFrame) throws -> [String: JSONValue] {
        let data: Data
        switch frame {
        case let .string(value): data = Data(value.utf8)
        case let .data(value): data = value
        }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case let .object(object) = value else { throw HomeAssistantWebSocketError.invalidMessage }
        return object
    }
}

private actor HistoryProcessingGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitingCount() -> Int { waiters.count }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private enum HistoryIntegrationWaitError: Error { case timedOut }

private func integrationWait(
    iterations: Int = 100_000,
    _ condition: @escaping () async -> Bool
) async throws {
    for _ in 0..<iterations {
        if await condition() { return }
        await Task.yield()
    }
    throw HistoryIntegrationWaitError.timedOut
}

private extension JSONValue {
    var historyTestInt: Int? {
        guard case let .int(value) = self else { return nil }
        return value
    }

    var historyTestString: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}

private extension ISO8601DateFormatter {
    static let historyFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
