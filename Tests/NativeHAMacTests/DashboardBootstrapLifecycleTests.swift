import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class DashboardBootstrapLifecycleTests: XCTestCase {
    func testExplicitStopThenFreshRestartRejectsOldOwnershipAndReturnsToZero() async throws {
        let transport = DashboardBootstrapTransport(mode: .success, dashboardTitle: "Restart")
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "dashboard-restart-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        try await model.bootstrapDashboard(using: client)
        XCTAssertEqual(model.lifecycle.phase, .ready)
        await model.stop()
        XCTAssertEqual(model.lifecycle.phase, .stopped)
        let stopped = await connection.debugSnapshot()
        XCTAssertEqual(stopped.subscriptionCount, 0)
        XCTAssertEqual(stopped.receiveLoopCount, 0)

        try await model.bootstrapDashboard(using: client)
        XCTAssertEqual(model.lifecycle.phase, .ready)
        XCTAssertEqual(model.homeView?.title, "Restart")
        let restarted = await connection.debugSnapshot()
        XCTAssertEqual(restarted.subscriptionCount, 2)
        await model.stop()
        let final = await connection.debugSnapshot()
        XCTAssertEqual(final.subscriptionCount, 0)
        XCTAssertEqual(final.deliveryOwnerCount, 0)
        XCTAssertEqual(final.receiveLoopCount, 0)
    }

    func testLovelaceUpdateAndScopedRetryUseNormalThenForcedFetch() async throws {
        let transport = DashboardBootstrapTransport(mode: .success, dashboardTitle: "Updates")
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "lovelace-retry-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )
        try await model.bootstrapDashboard(using: client)
        let initialForces = await transport.lovelaceForces()
        XCTAssertEqual(initialForces, [false])

        try await transport.pushLovelaceUpdate()
        try await waitForBootstrapCondition { await transport.lovelaceForces().count == 2 }
        let updateForces = await transport.lovelaceForces()
        XCTAssertEqual(updateForces, [false, false])

        model.retryLovelace()
        try await waitForBootstrapCondition { await transport.lovelaceForces().count == 3 }
        try await waitForBootstrapCondition {
            await MainActor.run { model.lifecycle.components[.lovelace] == .ready }
        }
        let retryForces = await transport.lovelaceForces()
        XCTAssertEqual(retryForces, [false, false, true])
        XCTAssertEqual(model.lifecycle.components[.lovelace], .ready)
        await model.stop()
        let stoppedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(stoppedSnapshot.subscriptionCount, 0)
    }

    func testMalformedLovelaceBootstrapDisconnectsAuthenticatedClient() async throws {
        try await assertBootstrapFailureDisconnects(mode: .malformedLovelace)
    }

    func testRejectedStateSubscriptionDisconnectsAuthenticatedClient() async throws {
        try await assertBootstrapFailureDisconnects(mode: .rejectStateSubscription)
    }

    func testRejectedCurrentUserIsNonfatalAndHidesOnlyUserRestrictedNavigation() async throws {
        let transport = DashboardBootstrapTransport(mode: .rejectCurrentUser)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "dashboard-bootstrap-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        try await model.bootstrapDashboard(using: client)

        XCTAssertEqual(model.status, "Live")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.views.map(\.path), ["default_view", "restricted"])
        XCTAssertEqual(model.navigationItems.map(\.title), ["Public"])
        XCTAssertEqual(model.homeView?.path, "default_view")
        let messages = await transport.sentMessages()
        let currentUserCommands = messages.filter { $0["type"] == .string("auth/current_user") }
        XCTAssertEqual(currentUserCommands.count, 1)
        XCTAssertEqual(Set(try XCTUnwrap(currentUserCommands.first).keys), ["id", "type"])

        let beforeSwitch = await connection.debugSnapshot()
        XCTAssertEqual(beforeSwitch.subscriptionCount, 2)
        try await transport.pushState(entityID: "sensor.global", state: "before")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.states["sensor.global"]?.state, "before")
        await model.navigateToViewForTesting(path: "restricted")
        XCTAssertEqual(model.homeView?.path, "restricted")
        XCTAssertEqual(model.navigationItems.map(\.title), ["Public"])
        try await transport.pushState(entityID: "sensor.global", state: "after")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.states["sensor.global"]?.state, "after")
        XCTAssertEqual(model.status, "Live")
        let afterSwitch = await connection.debugSnapshot()
        XCTAssertEqual(afterSwitch.subscriptionCount, 2)
        XCTAssertEqual(afterSwitch.wireSubscriptionCount, 2)

        await client.disconnect()
    }

    func testLateCurrentUserFromObsoleteBootstrapCannotReviseLatestNavigation() async throws {
        let oldTransport = DashboardBootstrapTransport(mode: .holdCurrentUser)
        let latestTransport = DashboardBootstrapTransport(mode: .rejectCurrentUser)
        let oldConnection = HomeAssistantWebSocketConnection(
            accessToken: "old-bootstrap-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { oldTransport }
        )
        let latestConnection = HomeAssistantWebSocketConnection(
            accessToken: "latest-bootstrap-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { latestTransport }
        )
        let oldClient = HomeAssistantWebSocketClient(connection: oldConnection)
        let latestClient = HomeAssistantWebSocketClient(connection: latestConnection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        let oldTask = Task { try await model.bootstrapDashboard(using: oldClient) }
        for _ in 0..<100_000 {
            if await oldTransport.currentUserCommandCount() == 1 { break }
            await Task.yield()
        }
        let oldCurrentUserCommandCount = await oldTransport.currentUserCommandCount()
        XCTAssertEqual(oldCurrentUserCommandCount, 1)
        try await model.bootstrapDashboard(using: latestClient)
        XCTAssertEqual(model.navigationItems.map(\.title), ["Public"])
        XCTAssertEqual(model.views.map(\.path), ["default_view", "restricted"])

        try await oldTransport.resolveHeldCurrentUser(id: "obsolete-user")
        try await oldTask.value
        XCTAssertEqual(model.navigationItems.map(\.title), ["Public"])
        XCTAssertEqual(model.views.map(\.path), ["default_view", "restricted"])
        let oldSnapshot = await oldConnection.debugSnapshot()
        XCTAssertEqual(oldSnapshot.state, .disconnected)

        await latestClient.disconnect()
    }

    func testRegistryPrecisionAndIconInstallOnlyWithAcceptedBootstrapAndResetTogether() async throws {
        let obsoleteTransport = DashboardBootstrapTransport(
            mode: .holdCurrentUser,
            registryEntities: [
                .object(["ei": .string("sensor.obsolete"), "dp": .int(9), "ic": .string("mdi:home")]),
            ]
        )
        let acceptedTransport = DashboardBootstrapTransport(
            mode: .success,
            registryEntities: [
                .object(["ei": .string("sensor.accepted"), "dp": .int(3), "ic": .string("mdi:thermometer")]),
                .object(["ei": .string("switch.icon_only"), "ic": .string("mdi:toggle-switch")]),
            ]
        )
        let obsoleteConnection = HomeAssistantWebSocketConnection(
            accessToken: "obsolete-registry-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { obsoleteTransport }
        )
        let acceptedConnection = HomeAssistantWebSocketConnection(
            accessToken: "accepted-registry-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { acceptedTransport }
        )
        let obsoleteClient = HomeAssistantWebSocketClient(connection: obsoleteConnection)
        let acceptedClient = HomeAssistantWebSocketClient(connection: acceptedConnection)
        let model = DashboardViewModel(
            entityDisplayPrecisions: ["sensor.retained": 1],
            entityRegistryIcons: ["sensor.retained": "mdi:battery"],
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        let obsoleteTask = Task { try await model.bootstrapDashboard(using: obsoleteClient) }
        try await waitForBootstrapCondition {
            await obsoleteTransport.currentUserCommandCount() == 1
        }
        XCTAssertEqual(model.entityDisplayPrecisions, ["sensor.retained": 1])
        XCTAssertEqual(model.entityRegistryIcons, ["sensor.retained": "mdi:battery"])

        try await model.bootstrapDashboard(using: acceptedClient)
        XCTAssertEqual(model.entityDisplayPrecisions, ["sensor.accepted": 3])
        XCTAssertEqual(model.entityRegistryIcons, [
            "sensor.accepted": "mdi:thermometer",
            "switch.icon_only": "mdi:toggle-switch",
        ])

        try await obsoleteTransport.resolveHeldCurrentUser(id: "obsolete-user")
        try await obsoleteTask.value
        XCTAssertEqual(model.entityDisplayPrecisions, ["sensor.accepted": 3])
        XCTAssertEqual(model.entityRegistryIcons["sensor.accepted"], "mdi:thermometer")
        XCTAssertNil(model.entityRegistryIcons["sensor.obsolete"])

        await model.stop()
        XCTAssertTrue(model.entityDisplayPrecisions.isEmpty)
        XCTAssertTrue(model.entityRegistryIcons.isEmpty)
    }

    func testCurrentUserTimeoutIsNonfatalToPublicDashboardBootstrap() async throws {
        let transport = DashboardBootstrapTransport(mode: .holdCurrentUser)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "timeout-bootstrap-token",
            commandTimeoutNanoseconds: 5_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        try await model.bootstrapDashboard(using: client)
        XCTAssertEqual(model.status, "Live")
        XCTAssertEqual(model.navigationItems.map(\.title), ["Obsolete"])
        XCTAssertEqual(model.homeView?.path, "default_view")
        let commandCount = await transport.currentUserCommandCount()
        XCTAssertEqual(commandCount, 1)

        await client.disconnect()
    }

    func testSameClientOverlappingBootstrapKeepsLatestOwnershipAndNeverDisconnectsSharedClient() async throws {
        let transport = DashboardBootstrapTransport(
            mode: .holdFirstCurrentUser,
            dashboardTitle: "Latest Same Client",
            successfulUserID: "latest-user"
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "same-client-overlap-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        let obsolete = Task { try await model.bootstrapDashboard(using: client) }
        try await waitForBootstrapCondition {
            await transport.currentUserCommandCount() == 1
        }
        let latest = Task { try await model.bootstrapDashboard(using: client) }
        try await latest.value

        XCTAssertEqual(model.status, "Live")
        XCTAssertEqual(model.navigationItems.map(\.title), ["Latest Same Client", "Restricted Latest"])
        XCTAssertEqual(model.homeView?.title, "Latest Same Client")
        let liveSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(liveSnapshot.state, .ready)
        XCTAssertEqual(liveSnapshot.subscriptionCount, 2)
        XCTAssertEqual(liveSnapshot.wireSubscriptionCount, 2)

        try await transport.resolveHeldCurrentUser(commandOrdinal: 0, id: "obsolete-user")
        try await obsolete.value
        let metrics = await transport.metrics()
        XCTAssertEqual(metrics.disconnectCalls, 0, "Obsolete same-client bootstrap must not disconnect latest ownership")
        let finalSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(finalSnapshot.state, .ready)
        XCTAssertEqual(finalSnapshot.subscriptionCount, 2)
        XCTAssertEqual(finalSnapshot.wireSubscriptionCount, 2)

        try await transport.pushState(entityID: "sensor.latest", state: "accepted")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["sensor.latest"]?.state == "accepted" }
        }
        XCTAssertEqual(model.status, "Live")
        XCTAssertEqual(model.navigationItems.map(\.title), ["Latest Same Client", "Restricted Latest"])

        await client.disconnect()
    }

    func testPostFirstGuardHeldApplyCannotPublishObsoleteBootstrapCandidate() async throws {
        let gate = BootstrapCandidateGate()
        let oldTransport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Obsolete Apply"
        )
        let latestTransport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Latest Apply"
        )
        let oldConnection = HomeAssistantWebSocketConnection(
            accessToken: "held-apply-old-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { oldTransport }
        )
        let latestConnection = HomeAssistantWebSocketConnection(
            accessToken: "held-apply-latest-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { latestTransport }
        )
        let oldClient = HomeAssistantWebSocketClient(connection: oldConnection)
        let latestClient = HomeAssistantWebSocketClient(connection: latestConnection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            dashboardOwnerCandidateHook: { await gate.enterAndWait() }
        )

        let obsolete = Task { try await model.bootstrapDashboard(using: oldClient) }
        try await gate.waitForEntryCount(1)
        let latest = Task { try await model.bootstrapDashboard(using: latestClient) }
        try await waitForBootstrapCondition {
            await latestTransport.currentUserCommandCount() == 1
        }

        await gate.release(entry: 1)
        try await gate.waitForEntryCount(2)
        XCTAssertFalse(model.hasLoadedDashboard)
        XCTAssertTrue(model.views.isEmpty)
        XCTAssertTrue(model.navigationItems.isEmpty, "Obsolete candidate must not publish while the latest apply is held")

        await gate.release(entry: 2)
        try await obsolete.value
        try await latest.value

        XCTAssertTrue(model.hasLoadedDashboard)
        XCTAssertEqual(model.homeView?.title, "Latest Apply")
        XCTAssertEqual(model.navigationItems.map(\.title), ["Latest Apply", "Restricted Latest"])
        XCTAssertEqual(model.status, "Live")
        let oldMetrics = await oldTransport.metrics()
        let latestMetrics = await latestTransport.metrics()
        XCTAssertEqual(oldMetrics.disconnectCalls, 1)
        XCTAssertEqual(latestMetrics.disconnectCalls, 0)
        let oldSnapshot = await oldConnection.debugSnapshot()
        let latestSnapshot = await latestConnection.debugSnapshot()
        XCTAssertEqual(oldSnapshot.state, .disconnected)
        XCTAssertEqual(oldSnapshot.subscriptionCount, 0)
        XCTAssertEqual(latestSnapshot.state, .ready)
        XCTAssertEqual(latestSnapshot.subscriptionCount, 2)
        XCTAssertEqual(latestSnapshot.wireSubscriptionCount, 2)

        try await latestTransport.pushState(entityID: "sensor.latest", state: "current")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["sensor.latest"]?.state == "current" }
        }
        XCTAssertEqual(model.status, "Live")
        XCTAssertEqual(model.homeView?.title, "Latest Apply")

        await latestClient.disconnect()
    }

    func testAcceptedEntityDeltaDuringHeldBootstrapInstallsLatestCandidateStore() async throws {
        let gate = BootstrapCandidateGate()
        let transport = DashboardBootstrapTransport(mode: .success, dashboardTitle: "Delta Gap")
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "bootstrap-delta-gap-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            dashboardOwnerCandidateHook: { await gate.enterAndWait() }
        )

        let bootstrap = Task { try await model.bootstrapDashboard(using: client) }
        try await gate.waitForEntryCount(1)
        XCTAssertNil(model.states["sensor.preinstall"], "Candidate deltas remain private until atomic install")
        try await transport.pushState(entityID: "sensor.preinstall", state: "accepted-delta")
        try await waitForBootstrapCondition {
            await MainActor.run {
                guard let candidate = model.bootstrapCandidateEntityCoordinatorForTesting()
                else { return false }
                return (try? candidate.proveLiveGenerationForInstallation()
                    .snapshot["sensor.preinstall"]?.state) == "accepted-delta"
            }
        }
        XCTAssertNil(model.states["sensor.preinstall"])

        await gate.release(entry: 1)
        try await bootstrap.value
        XCTAssertEqual(model.states["sensor.preinstall"]?.state, "accepted-delta")
        XCTAssertEqual(model.lifecycle.phase, .ready)
        await model.stop()
    }

    func testMalformedEntityDeltaDuringHeldPreinstallCannotInstallDeadCandidate() async throws {
        let gate = BootstrapCandidateGate()
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Malformed Delta Gap"
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "bootstrap-malformed-delta-gap-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            dashboardOwnerCandidateHook: { await gate.enterAndWait() }
        )

        let bootstrap = Task { () -> Bool in
            do {
                try await model.bootstrapDashboard(using: client)
                return false
            } catch {
                return true
            }
        }
        try await gate.waitForEntryCount(1)
        var candidate: HAEntitySubscriptionCoordinator? = try XCTUnwrap(
            model.bootstrapCandidateEntityCoordinatorForTesting()
        )
        weak var weakCandidate = candidate
        let acceptedProof = try XCTUnwrap(candidate).proveLiveGenerationForInstallation()
        XCTAssertEqual(
            acceptedProof.generation,
            try XCTUnwrap(candidate).debugSnapshot().acceptedLiveGeneration
        )
        XCTAssertTrue(acceptedProof.snapshot.isEmpty)
        XCTAssertFalse(model.dashboardOwnerSnapshotForTesting().entityOwnerActive)

        try await transport.pushMalformedEntityDelta()
        try await waitForBootstrapCondition {
            await MainActor.run {
                guard let currentCandidate = model.bootstrapCandidateEntityCoordinatorForTesting()
                else { return false }
                let owner = currentCandidate.debugSnapshot()
                return !owner.hasSubscription &&
                    !owner.acceptedFirstSnapshot &&
                    owner.acceptedLiveGeneration == nil
            }
        }
        XCTAssertThrowsError(try candidate?.proveLiveGenerationForInstallation())
        XCTAssertFalse(model.dashboardOwnerSnapshotForTesting().entityOwnerActive)
        XCTAssertNotEqual(model.lifecycle.phase, .ready)
        let genericDecodesBeforeLatePayload = await connection.debugSnapshot()
            .genericFrameDecodeCount
        try await transport.pushState(entityID: "sensor.late-dead-owner", state: "rejected")
        try await waitForBootstrapCondition {
            await connection.debugSnapshot().genericFrameDecodeCount ==
                genericDecodesBeforeLatePayload + 1
        }
        XCTAssertNil(model.states["sensor.late-dead-owner"])

        await gate.release(entry: 1)
        let bootstrapFailed = await bootstrap.value
        XCTAssertTrue(bootstrapFailed, "A dead candidate must fail bootstrap installation")
        XCTAssertEqual(model.lifecycle.phase, .failed)
        XCTAssertNotEqual(model.status, "Live")
        XCTAssertTrue(model.states.isEmpty)
        let owners = model.dashboardOwnerSnapshotForTesting()
        XCTAssertFalse(owners.entityOwnerActive)
        XCTAssertFalse(owners.candidateEntityOwnerActive)
        XCTAssertFalse(owners.lovelaceSubscriptionActive)
        XCTAssertFalse(owners.connectionStatusTaskActive)
        XCTAssertFalse(owners.webSocketClientActive)
        XCTAssertFalse(owners.installedClientActive)

        let socket = await connection.debugSnapshot()
        XCTAssertEqual(socket.state, .disconnected)
        XCTAssertEqual(socket.subscriptionCount, 0)
        XCTAssertEqual(socket.deliveryOwnerCount, 0)
        XCTAssertEqual(socket.receiveLoopCount, 0)
        let metrics = await transport.metrics()
        XCTAssertEqual(metrics.disconnectCalls, 1)
        XCTAssertEqual(metrics.activeReceives, 0)

        candidate = nil
        for _ in 0..<100_000 where weakCandidate != nil { await Task.yield() }
        XCTAssertNil(weakCandidate)

        let retry = Task { try await model.bootstrapDashboard(using: client) }
        try await gate.waitForEntryCount(2)
        let retryCandidate = try XCTUnwrap(model.bootstrapCandidateEntityCoordinatorForTesting())
        XCTAssertNoThrow(try retryCandidate.proveLiveGenerationForInstallation())
        await gate.release(entry: 2)
        try await retry.value
        XCTAssertEqual(model.lifecycle.phase, .ready)
        let entitySubscriptionCount = await transport.entitySubscriptionCount()
        XCTAssertEqual(entitySubscriptionCount, 2)
        let retrySocket = await connection.debugSnapshot()
        XCTAssertEqual(retrySocket.state, .ready)
        XCTAssertEqual(retrySocket.subscriptionCount, 2)
        XCTAssertEqual(retrySocket.deliveryOwnerCount, 2)
        try await transport.pushState(entityID: "sensor.fresh-owner", state: "accepted")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["sensor.fresh-owner"]?.state == "accepted" }
        }

        await model.stop()
        let stoppedSocket = await connection.debugSnapshot()
        XCTAssertEqual(stoppedSocket.subscriptionCount, 0)
        XCTAssertEqual(stoppedSocket.deliveryOwnerCount, 0)
        XCTAssertEqual(stoppedSocket.receiveLoopCount, 0)
    }

    func testExplicitStopCancelsHeldCardHistoryStartupWithoutAckOrTimeout() async throws {
        let historyCard: JSONValue = .object([
            "type": .string("history-graph"),
            "title": .string("Held stop history"),
            "entities": .array([.string("sensor.held_stop")]),
        ])
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Held History Stop",
            dashboardCards: [historyCard],
            holdHistoryAcknowledgements: true
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "held-history-explicit-stop-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        var model: DashboardViewModel? = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )
        weak var weakModel = model

        try await model?.bootstrapDashboard(using: client)
        try await waitForBootstrapCondition {
            let commandReady = await transport.historyCommandCount() == 1
            let startupReady = await MainActor.run {
                model?.dashboardOwnerSnapshotForTesting().startupCount == 1
            }
            return commandReady && startupReady
        }
        let historyCommands = await transport.historyCommands()
        let historyCommand = try XCTUnwrap(historyCommands.first)
        let historyID = try XCTUnwrap(historyCommand["id"]?.dashboardTestInt)

        let stopTask = Task { [weak model] in await model?.stop() }
        try await waitForBootstrapCondition {
            await MainActor.run { model?.lifecycle.phase == .stopped }
        }
        await stopTask.value

        let owners = try XCTUnwrap(model?.dashboardOwnerSnapshotForTesting())
        XCTAssertEqual(owners.startupCount, 0)
        XCTAssertTrue(owners.subscriptionKeys.isEmpty)
        XCTAssertTrue(owners.generationKeys.isEmpty)
        XCTAssertFalse(owners.dashboardOwnerTailActive)
        let stopped = await connection.debugSnapshot()
        XCTAssertEqual(stopped.state, .disconnected)
        XCTAssertEqual(stopped.pendingCommandCount, 0)
        XCTAssertEqual(stopped.subscriptionCount, 0)
        XCTAssertEqual(stopped.wireSubscriptionCount, 0)
        XCTAssertEqual(stopped.deliveryOwnerCount, 0)
        XCTAssertEqual(stopped.bufferedDeliveryCount, 0)
        XCTAssertEqual(stopped.activeDeliveryTaskCount, 0)
        XCTAssertEqual(stopped.activeTerminationTaskCount, 0)
        XCTAssertEqual(stopped.pendingTerminationCount, 0)
        XCTAssertEqual(stopped.receiveLoopCount, 0)
        let metrics = await transport.metrics()
        XCTAssertEqual(metrics.activeReceives, 0)

        try await transport.resolveHistoryAcknowledgement(id: historyID, success: true)
        for _ in 0..<100 { await Task.yield() }
        let afterLateAck = await connection.debugSnapshot()
        XCTAssertEqual(afterLateAck, stopped, "A late held acknowledgement cannot recreate ownership")

        model = nil
        for _ in 0..<100_000 where weakModel != nil { await Task.yield() }
        XCTAssertNil(weakModel)
    }

    func testPublicStopCancelsHeldHistoryStartupHiddenBehindPredecessorThirtyTimes() async throws {
        let historyCard: JSONValue = .object([
            "type": .string("history-graph"),
            "title": .string("Hidden predecessor"),
            "entities": .array([.string("sensor.hidden_predecessor")]),
        ])

        for cycle in 1...30 {
            let transport = DashboardBootstrapTransport(
                mode: .success,
                dashboardTitle: "Hidden predecessor \(cycle)",
                dashboardCards: [historyCard],
                holdHistoryAcknowledgements: true
            )
            let connection = HomeAssistantWebSocketConnection(
                accessToken: "hidden-predecessor-stop-token",
                commandTimeoutNanoseconds: 5_000_000_000,
                transportFactory: { transport }
            )
            let client = HomeAssistantWebSocketClient(connection: connection)
            var model: DashboardViewModel? = DashboardViewModel(
                navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
            )
            weak var weakModel = model

            try await model?.bootstrapDashboard(using: client)
            try await waitForBootstrapCondition {
                let commandReady = await transport.historyCommandCount() == 1
                let ownerReady = await MainActor.run { () -> Bool in
                    guard let snapshot = model?.dashboardOwnerSnapshotForTesting() else {
                        return false
                    }
                    return snapshot.startupCount == 1 &&
                        snapshot.dashboardOwnerNodeCount == 1
                }
                return commandReady && ownerReady
            }
            let historyCommands = await transport.historyCommands()
            let historyCommand = try XCTUnwrap(historyCommands.first)
            let historyID = try XCTUnwrap(historyCommand["id"]?.dashboardTestInt)

            let remove = Task { @MainActor [weak model] in
                await model?.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
            }
            try await waitForBootstrapCondition {
                await MainActor.run { () -> Bool in
                    guard let snapshot = model?.dashboardOwnerSnapshotForTesting() else {
                        return false
                    }
                    return snapshot.startupCount == 0 &&
                        snapshot.dashboardOwnerNodeCount >= 2
                }
            }

            // Queue another node behind the predecessor that now owns the
            // detached held startup. Public stop must still reach that hidden
            // startup and may not wait for its five-second command timeout.
            model?.setGraphHours(3)
            try await waitForBootstrapCondition {
                await MainActor.run {
                    model?.dashboardOwnerSnapshotForTesting().dashboardOwnerNodeCount ?? 0 >= 3
                }
            }

            let stop = Task { @MainActor [weak model] in await model?.stop() }
            try await waitForBootstrapCondition {
                await MainActor.run { model?.lifecycle.phase == .stopped }
            }
            await stop.value
            await remove.value

            let owners = try XCTUnwrap(model?.dashboardOwnerSnapshotForTesting())
            XCTAssertEqual(owners.dashboardOwnerNodeCount, 0, "cycle \(cycle)")
            XCTAssertFalse(owners.dashboardOwnerTailActive, "cycle \(cycle)")
            XCTAssertEqual(owners.startupCount, 0, "cycle \(cycle)")
            XCTAssertTrue(owners.subscriptionKeys.isEmpty, "cycle \(cycle)")
            XCTAssertTrue(owners.generationKeys.isEmpty, "cycle \(cycle)")
            XCTAssertTrue(model?.histories.isEmpty == true, "cycle \(cycle)")
            XCTAssertTrue(model?.historyStatuses.isEmpty == true, "cycle \(cycle)")

            let stopped = await connection.debugSnapshot()
            XCTAssertEqual(stopped.state, .disconnected, "cycle \(cycle)")
            XCTAssertEqual(stopped.pendingCommandCount, 0, "cycle \(cycle)")
            XCTAssertEqual(stopped.subscriptionCount, 0, "cycle \(cycle)")
            XCTAssertEqual(stopped.wireSubscriptionCount, 0, "cycle \(cycle)")
            XCTAssertEqual(stopped.deliveryOwnerCount, 0, "cycle \(cycle)")
            XCTAssertEqual(stopped.receiveLoopCount, 0, "cycle \(cycle)")
            let metrics = await transport.metrics()
            XCTAssertEqual(metrics.disconnectCalls, 1, "cycle \(cycle)")

            try await transport.resolveHistoryAcknowledgement(id: historyID, success: true)
            for _ in 0..<100 { await Task.yield() }
            let afterLateAck = await connection.debugSnapshot()
            XCTAssertEqual(afterLateAck, stopped, "cycle \(cycle)")
            XCTAssertTrue(model?.histories.isEmpty == true, "cycle \(cycle)")

            await model?.stop()
            model = nil
            for _ in 0..<100_000 where weakModel != nil { await Task.yield() }
            XCTAssertNil(weakModel, "cycle \(cycle)")
        }
    }

    func testStoppedRetainedEntityDisablesControlUntilFreshBootstrapInstallsCaller() async throws {
        let transport = DashboardBootstrapTransport(mode: .success, dashboardTitle: "Service Caller")
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "service-caller-lifecycle-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        try await model.bootstrapDashboard(using: client)
        try await transport.pushState(entityID: "switch.retained_control", state: "off")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["switch.retained_control"]?.state == "off" }
        }
        model.states["climate.retained_control"] = HAState(
            entityId: "climate.retained_control",
            state: "heat",
            attributes: [
                "preset_mode": .string("home"),
                "temperature": .double(20),
            ]
        )
        XCTAssertTrue(model.canControlPower(entityID: "switch.retained_control"))

        await model.stop()
        XCTAssertEqual(model.states["switch.retained_control"]?.state, "off")
        XCTAssertFalse(model.canControlPower(entityID: "switch.retained_control"))
        XCTAssertFalse(model.canInvokeService(
            entityID: "switch.retained_control",
            domain: "switch",
            service: "turn_on"
        ))
        model.setPower(entityID: "switch.retained_control", isOn: true)
        model.setClimatePresetMode(
            entityID: "climate.retained_control",
            mode: "home",
            predictedTemperature: 24
        )
        XCTAssertEqual(model.states["switch.retained_control"]?.state, "off")
        XCTAssertEqual(model.states["climate.retained_control"]?.attributes["temperature"], .double(20))
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 0)
        XCTAssertEqual(model.lifecycle.phase, .stopped)

        try await model.bootstrapDashboard(using: client)
        try await transport.pushState(entityID: "switch.retained_control", state: "off")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["switch.retained_control"]?.state == "off" }
        }
        XCTAssertTrue(model.canControlPower(entityID: "switch.retained_control"))
        await model.stop()
    }

    func testStopDuringHeldBootstrapSynchronouslyDetachesCandidateEntityOwner() async throws {
        let gate = BootstrapCandidateGate()
        let transport = DashboardBootstrapTransport(mode: .success, dashboardTitle: "Held Stop")
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "bootstrap-held-stop-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            dashboardOwnerCandidateHook: { await gate.enterAndWait() }
        )

        let bootstrap = Task { try await model.bootstrapDashboard(using: client) }
        try await gate.waitForEntryCount(1)
        var candidate: HAEntitySubscriptionCoordinator? = model.bootstrapCandidateEntityCoordinatorForTesting()
        weak var weakCandidate = candidate
        XCTAssertNotNil(candidate)
        XCTAssertTrue(candidate?.debugSnapshot().hasSubscription == true)

        let stopTask = Task { await model.stop() }
        try await waitForBootstrapCondition {
            await MainActor.run {
                model.bootstrapCandidateEntityCoordinatorForTesting() == nil &&
                    candidate?.debugSnapshot().hasSubscription == false &&
                    candidate?.debugSnapshot().hasStatusTask == false
            }
        }
        XCTAssertNil(model.bootstrapCandidateEntityCoordinatorForTesting())
        XCTAssertFalse(candidate?.debugSnapshot().hasSubscription == true)
        XCTAssertFalse(candidate?.debugSnapshot().hasStatusTask == true)

        candidate = nil
        await gate.release(entry: 1)
        await stopTask.value
        try await bootstrap.value
        let stoppedSocket = await connection.debugSnapshot()
        XCTAssertEqual(stoppedSocket.subscriptionCount, 0)
        XCTAssertEqual(stoppedSocket.deliveryOwnerCount, 0)
        XCTAssertEqual(stoppedSocket.receiveLoopCount, 0)
        for _ in 0..<100_000 where weakCandidate != nil { await Task.yield() }
        XCTAssertNil(weakCandidate)
        XCTAssertEqual(model.lifecycle.phase, .stopped)
    }

    func testFatalReplacementBootstrapRevokesHeldServiceAuthorityUntilFreshInstall() async throws {
        let installedTransport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Installed"
        )
        let failingTransport = DashboardBootstrapTransport(mode: .malformedLovelace)
        let freshTransport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Fresh"
        )
        let installedConnection = HomeAssistantWebSocketConnection(
            accessToken: "installed-before-failure-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { installedTransport }
        )
        let failingConnection = HomeAssistantWebSocketConnection(
            accessToken: "replacement-failure-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { failingTransport }
        )
        let freshConnection = HomeAssistantWebSocketConnection(
            accessToken: "fresh-after-failure-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { freshTransport }
        )
        let installedClient = HomeAssistantWebSocketClient(connection: installedConnection)
        let failingClient = HomeAssistantWebSocketClient(connection: failingConnection)
        let freshClient = HomeAssistantWebSocketClient(connection: freshConnection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )
        let oldRecorder = BootstrapServiceCallRecorder()
        let newRecorder = BootstrapServiceCallRecorder()
        let oldCallGate = BootstrapServiceCallGate()

        try await model.bootstrapDashboard(using: installedClient)
        let initiallyInstalledSnapshot = await installedConnection.debugSnapshot()
        XCTAssertEqual(initiallyInstalledSnapshot.subscriptionCount, 2)
        try await installedTransport.pushState(entityID: "switch.fatal_retained", state: "off")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["switch.fatal_retained"]?.state == "off" }
        }
        model.states["climate.fatal_retained"] = HAState(
            entityId: "climate.fatal_retained",
            state: "heat",
            attributes: [
                "preset_mode": .string("home"),
                "temperature": .double(20),
            ]
        )
        model.installServiceCallerForTesting { domain, service, data in
            await oldRecorder.append(domain: domain, service: service, data: data)
            try await withTaskCancellationHandler(operation: {
                await oldCallGate.wait()
                throw URLError(.timedOut)
            }, onCancel: {
                Task { await oldCallGate.noteCancellation() }
            })
        }
        XCTAssertTrue(model.canControlPower(entityID: "switch.fatal_retained"))
        model.setPower(entityID: "switch.fatal_retained", isOn: true)
        try await waitForBootstrapCondition {
            let callHeld = await oldCallGate.isWaiting()
            let callCount = await oldRecorder.count()
            let taskOwned = await MainActor.run {
                model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 1
            }
            return callHeld && callCount == 1 && taskOwned
        }
        XCTAssertEqual(model.states["switch.fatal_retained"]?.state, "on")

        let failureTask = Task { () -> Error? in
            do {
                try await model.bootstrapDashboard(using: failingClient)
                return nil
            } catch {
                return error
            }
        }
        try await waitForBootstrapCondition {
            let cancellationObserved = await oldCallGate.cancellationCount() == 1
            let authorityDetached = await MainActor.run {
                model.lifecycle.phase == .failed &&
                    !model.canControlPower(entityID: "switch.fatal_retained") &&
                    !model.canInvokeService(
                        entityID: "climate.fatal_retained",
                        domain: "climate",
                        service: "set_preset_mode"
                    ) &&
                    model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0
            }
            return cancellationObserved && authorityDetached
        }

        let retainedSwitch = model.states["switch.fatal_retained"]
        let retainedClimate = model.states["climate.fatal_retained"]
        let fatalError = model.errorMessage
        model.setPower(entityID: "switch.fatal_retained", isOn: false)
        model.setClimatePresetMode(
            entityID: "climate.fatal_retained",
            mode: "home",
            predictedTemperature: 24
        )
        XCTAssertEqual(model.states["switch.fatal_retained"], retainedSwitch)
        XCTAssertEqual(model.states["climate.fatal_retained"], retainedClimate)
        let callsWhileFailed = (old: await oldRecorder.count(), new: await newRecorder.count())
        XCTAssertEqual(callsWhileFailed.old, 1)
        XCTAssertEqual(callsWhileFailed.new, 0)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 0)

        await oldCallGate.release()
        let replacementError = await failureTask.value
        XCTAssertTrue(replacementError is DecodingError || replacementError is LovelaceDecodeError)
        XCTAssertEqual(model.errorMessage, fatalError, "A cancelled old action cannot replace the fatal error")
        let callsAfterLateResult = (old: await oldRecorder.count(), new: await newRecorder.count())
        XCTAssertEqual(callsAfterLateResult.old, 1, "Failure must not retry the old service call")
        XCTAssertEqual(callsAfterLateResult.new, 0)

        let installedSnapshot = await installedConnection.debugSnapshot()
        let failingSnapshot = await failingConnection.debugSnapshot()
        XCTAssertEqual(installedSnapshot.state, .disconnected)
        XCTAssertEqual(installedSnapshot.pendingCommandCount, 0)
        XCTAssertEqual(installedSnapshot.subscriptionCount, 0)
        XCTAssertEqual(installedSnapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(installedSnapshot.deliveryOwnerCount, 0)
        XCTAssertEqual(installedSnapshot.bufferedDeliveryCount, 0)
        XCTAssertEqual(installedSnapshot.activeDeliveryTaskCount, 0)
        XCTAssertEqual(installedSnapshot.activeTerminationTaskCount, 0)
        XCTAssertEqual(installedSnapshot.pendingTerminationCount, 0)
        XCTAssertEqual(installedSnapshot.receiveLoopCount, 0)
        XCTAssertEqual(failingSnapshot.state, .disconnected)
        XCTAssertEqual(failingSnapshot.pendingCommandCount, 0)
        XCTAssertEqual(failingSnapshot.subscriptionCount, 0)
        XCTAssertEqual(failingSnapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(failingSnapshot.deliveryOwnerCount, 0)
        XCTAssertEqual(failingSnapshot.bufferedDeliveryCount, 0)
        XCTAssertEqual(failingSnapshot.activeDeliveryTaskCount, 0)
        XCTAssertEqual(failingSnapshot.activeTerminationTaskCount, 0)
        XCTAssertEqual(failingSnapshot.pendingTerminationCount, 0)
        XCTAssertEqual(failingSnapshot.receiveLoopCount, 0)
        let installedMetrics = await installedTransport.metrics()
        let failingMetrics = await failingTransport.metrics()
        XCTAssertEqual(installedMetrics.disconnectCalls, 1)
        XCTAssertEqual(installedMetrics.activeReceives, 0)
        XCTAssertEqual(failingMetrics.disconnectCalls, 1)
        XCTAssertEqual(failingMetrics.activeReceives, 0)

        try await model.bootstrapDashboard(using: freshClient)
        try await freshTransport.pushState(entityID: "switch.fatal_retained", state: "off")
        try await waitForBootstrapCondition {
            await MainActor.run {
                model.states["switch.fatal_retained"]?.state == "off" &&
                    model.canControlPower(entityID: "switch.fatal_retained")
            }
        }
        model.installServiceCallerForTesting { domain, service, data in
            await newRecorder.append(domain: domain, service: service, data: data)
        }
        model.setPower(entityID: "switch.fatal_retained", isOn: true)
        try await waitForBootstrapCondition {
            let newCallCount = await newRecorder.count()
            let taskSettled = await MainActor.run {
                model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0
            }
            return newCallCount == 1 && taskSettled
        }
        let callsAfterFreshAction = (old: await oldRecorder.count(), new: await newRecorder.count())
        XCTAssertEqual(callsAfterFreshAction.old, 1)
        XCTAssertEqual(callsAfterFreshAction.new, 1)
        XCTAssertEqual(model.states["switch.fatal_retained"]?.state, "on")

        await model.stop()
        let freshSnapshot = await freshConnection.debugSnapshot()
        let freshMetrics = await freshTransport.metrics()
        XCTAssertEqual(freshSnapshot.state, .disconnected)
        XCTAssertEqual(freshSnapshot.pendingCommandCount, 0)
        XCTAssertEqual(freshSnapshot.subscriptionCount, 0)
        XCTAssertEqual(freshSnapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(freshSnapshot.deliveryOwnerCount, 0)
        XCTAssertEqual(freshSnapshot.receiveLoopCount, 0)
        XCTAssertEqual(freshMetrics.disconnectCalls, 1)
        XCTAssertEqual(freshMetrics.activeReceives, 0)
    }

    func testSameClientIdenticalConfigHeldApplyInstallsOnlyLatestBootstrapGeneration() async throws {
        let gate = BootstrapCandidateGate()
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Shared Config"
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "same-client-held-apply-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            dashboardOwnerCandidateHook: { await gate.enterAndWait() }
        )

        let obsolete = Task { try await model.bootstrapDashboard(using: client) }
        try await gate.waitForEntryCount(1)
        let latest = Task { try await model.bootstrapDashboard(using: client) }
        try await waitForBootstrapCondition {
            await transport.currentUserCommandCount() == 2
        }

        await gate.release(entry: 1)
        try await gate.waitForEntryCount(2)
        XCTAssertFalse(model.hasLoadedDashboard)
        XCTAssertTrue(model.navigationItems.isEmpty)
        await gate.release(entry: 2)
        try await obsolete.value
        try await latest.value

        XCTAssertTrue(model.hasLoadedDashboard)
        XCTAssertEqual(model.homeView?.title, "Shared Config")
        XCTAssertEqual(model.status, "Live")
        let snapshot = await connection.debugSnapshot()
        let metrics = await transport.metrics()
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.subscriptionCount, 2)
        XCTAssertEqual(snapshot.wireSubscriptionCount, 2)
        XCTAssertEqual(metrics.disconnectCalls, 0)

        try await transport.pushState(entityID: "sensor.shared", state: "latest")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["sensor.shared"]?.state == "latest" }
        }
        await client.disconnect()
    }

    func testHeldStopDuplicateRetryCoalescesToOneFreshGenerationThirtyTimes() async throws {
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Retry Barrier"
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "duplicate-retry-transition-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            lifecycleBootstrapClientOverride: client
        )

        model.start()
        try await waitForBootstrapCondition {
            await MainActor.run {
                model.lifecycle.phase == .ready &&
                    !model.dashboardOwnerSnapshotForTesting().bootstrapTaskActive
            }
        }

        for cycle in 1...30 {
            let gate = BootstrapServiceCallGate()
            model.states["switch.retry_barrier"] = HAState(
                entityId: "switch.retry_barrier",
                state: "off"
            )
            model.installServiceCallerForTesting { _, _, _ in
                try await withTaskCancellationHandler(operation: {
                    await gate.wait()
                    throw URLError(.timedOut)
                }, onCancel: {
                    Task { await gate.noteCancellation() }
                })
            }
            model.setPower(entityID: "switch.retry_barrier", isOn: true)
            try await waitForBootstrapCondition {
                let held = await gate.isWaiting()
                let owned = await MainActor.run {
                    model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 1
                }
                return held && owned
            }

            let subscriptionsBeforeRetry = await transport.entitySubscriptionCount()
            model.retryBootstrap()
            try await waitForBootstrapCondition {
                let cancelled = await gate.cancellationCount() == 1
                let detached = await MainActor.run {
                    model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0
                }
                return cancelled && detached
            }
            model.retryBootstrap()
            for _ in 0..<100 { await Task.yield() }
            let countWhileHeld = await transport.entitySubscriptionCount()
            XCTAssertEqual(
                countWhileHeld,
                subscriptionsBeforeRetry,
                "A newer retry started before the held old stop in cycle \(cycle)"
            )

            await gate.release()
            await model.awaitLifecycleTransitionsForTesting()
            try await waitForBootstrapCondition {
                let exactlyOneFreshOwner = await transport.entitySubscriptionCount() ==
                    subscriptionsBeforeRetry + 1
                let modelReady = await MainActor.run { () -> Bool in
                    let owners = model.dashboardOwnerSnapshotForTesting()
                    return model.lifecycle.phase == .ready &&
                        !owners.bootstrapTaskActive &&
                        owners.entityOwnerActive &&
                        !owners.candidateEntityOwnerActive &&
                        owners.lovelaceSubscriptionActive &&
                        owners.connectionStatusTaskActive &&
                        owners.serviceTaskCount == 0 &&
                        owners.webSocketClientActive &&
                        owners.installedClientActive
                }
                return exactlyOneFreshOwner && modelReady
            }
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(
                model.lifecycle.phase,
                .ready,
                "An obsolete stopped publication overwrote cycle \(cycle)'s ready generation"
            )
            let finalCount = await transport.entitySubscriptionCount()
            XCTAssertEqual(finalCount, subscriptionsBeforeRetry + 1)
        }

        await model.stop()
        let stopped = await connection.debugSnapshot()
        XCTAssertEqual(stopped.subscriptionCount, 0)
        XCTAssertEqual(stopped.deliveryOwnerCount, 0)
        XCTAssertEqual(stopped.receiveLoopCount, 0)
    }

    func testHeldDisappearThenReappearSerializesOneFreshGenerationThirtyTimes() async throws {
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "View Lifecycle Barrier"
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "view-disappear-reappear-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            lifecycleBootstrapClientOverride: client
        )

        model.start()
        try await waitForBootstrapCondition {
            await MainActor.run {
                model.lifecycle.phase == .ready &&
                    !model.dashboardOwnerSnapshotForTesting().bootstrapTaskActive
            }
        }

        for cycle in 1...30 {
            let gate = BootstrapServiceCallGate()
            model.states["switch.view_barrier"] = HAState(
                entityId: "switch.view_barrier",
                state: "off"
            )
            model.installServiceCallerForTesting { _, _, _ in
                try await withTaskCancellationHandler(operation: {
                    await gate.wait()
                    throw URLError(.timedOut)
                }, onCancel: {
                    Task { await gate.noteCancellation() }
                })
            }
            model.setPower(entityID: "switch.view_barrier", isOn: true)
            try await waitForBootstrapCondition { await gate.isWaiting() }

            let subscriptionsBeforeDisappear = await transport.entitySubscriptionCount()
            // Exercise the exact synchronous callbacks used by DashboardView:
            // reappearance is queued in the same MainActor turn, before the
            // held disappearance teardown can begin.
            model.viewDidDisappear()
            model.viewDidAppear()
            try await waitForBootstrapCondition {
                await gate.cancellationCount() == 1
            }
            for _ in 0..<100 { await Task.yield() }
            let countWhileHeld = await transport.entitySubscriptionCount()
            XCTAssertEqual(
                countWhileHeld,
                subscriptionsBeforeDisappear,
                "Reappear started before disappear teardown completed in cycle \(cycle)"
            )

            await gate.release()
            await model.awaitLifecycleTransitionsForTesting()
            try await waitForBootstrapCondition {
                let exactlyOneFreshOwner = await transport.entitySubscriptionCount() ==
                    subscriptionsBeforeDisappear + 1
                let modelReady = await MainActor.run { () -> Bool in
                    let owners = model.dashboardOwnerSnapshotForTesting()
                    return model.lifecycle.phase == .ready &&
                        !owners.bootstrapTaskActive &&
                        owners.entityOwnerActive &&
                        !owners.candidateEntityOwnerActive &&
                        owners.lovelaceSubscriptionActive &&
                        owners.connectionStatusTaskActive &&
                        owners.serviceTaskCount == 0 &&
                        owners.webSocketClientActive &&
                        owners.installedClientActive
                }
                return exactlyOneFreshOwner && modelReady
            }
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(
                model.lifecycle.phase,
                .ready,
                "The old disappear stop overwrote cycle \(cycle)'s reappeared generation"
            )
            let finalCount = await transport.entitySubscriptionCount()
            XCTAssertEqual(
                finalCount,
                subscriptionsBeforeDisappear + 1
            )
        }

        await model.stop()
        let stopped = await connection.debugSnapshot()
        XCTAssertEqual(stopped.subscriptionCount, 0)
        XCTAssertEqual(stopped.deliveryOwnerCount, 0)
        XCTAssertEqual(stopped.receiveLoopCount, 0)
    }

    func testHeldReconnectRetryCancelsOldOwnerBeforeFreshGeneration() async throws {
        let transport = DashboardBootstrapTransport(
            mode: .holdSecondAuthentication,
            dashboardTitle: "Held reconnect"
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "held-reconnect-retry-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            lifecycleBootstrapClientOverride: client
        )

        model.viewDidAppear()
        try await waitForBootstrapCondition {
            await MainActor.run {
                model.lifecycle.phase == .ready &&
                    !model.dashboardOwnerSnapshotForTesting().bootstrapTaskActive
            }
        }
        let initialAuthenticationCount = await transport.authenticationCommandCount()
        let initialEntitySubscriptionCount = await transport.entitySubscriptionCount()
        XCTAssertEqual(initialAuthenticationCount, 1)
        XCTAssertEqual(initialEntitySubscriptionCount, 1)

        model.reconnectRealtime()
        try await waitForBootstrapCondition {
            let authenticationHeld = await transport.authenticationCommandCount() == 2
            let socketReconnecting: Bool
            switch await connection.debugSnapshot().state {
            case .reconnecting, .connecting:
                socketReconnecting = true
            default:
                socketReconnecting = false
            }
            let reconnectOwned = await MainActor.run {
                model.dashboardOwnerSnapshotForTesting().reconnectTaskActive
            }
            return authenticationHeld && socketReconnecting && reconnectOwned
        }

        model.retryBootstrap()
        await model.awaitLifecycleTransitionsForTesting()
        try await waitForBootstrapCondition {
            let freshAuthentication = await transport.authenticationCommandCount() == 3
            let freshEntityOwner = await transport.entitySubscriptionCount() == 2
            let socketReady = await connection.debugSnapshot().state == .ready
            let modelReady = await MainActor.run { () -> Bool in
                let owner = model.dashboardOwnerSnapshotForTesting()
                return model.lifecycle.phase == .ready &&
                    !owner.reconnectTaskActive &&
                    !owner.bootstrapTaskActive
            }
            return freshAuthentication && freshEntityOwner && socketReady && modelReady
        }

        try await transport.pushState(entityID: "sensor.fresh_reconnect", state: "accepted")
        try await waitForBootstrapCondition {
            await MainActor.run {
                model.states["sensor.fresh_reconnect"]?.state == "accepted"
            }
        }
        XCTAssertEqual(model.homeView?.title, "Held reconnect")
        XCTAssertEqual(model.status, "Live")

        await model.stop()
        let stopped = await connection.debugSnapshot()
        XCTAssertEqual(stopped.state, .disconnected)
        XCTAssertEqual(stopped.subscriptionCount, 0)
        XCTAssertEqual(stopped.wireSubscriptionCount, 0)
        XCTAssertEqual(stopped.deliveryOwnerCount, 0)
        XCTAssertEqual(stopped.receiveLoopCount, 0)
        XCTAssertFalse(model.dashboardOwnerSnapshotForTesting().reconnectTaskActive)
    }

    func testDeinitDuringActualHeldOwnedBootstrapReleasesModelAndDrainsCandidate() async throws {
        let candidateGate = BootstrapCandidateGate()
        let transport = DashboardBootstrapTransport(mode: .success, dashboardTitle: "Held deinit")
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "deinit-held-candidate-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        var model: DashboardViewModel? = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            dashboardOwnerCandidateHook: { await candidateGate.enterAndWait() },
            lifecycleBootstrapClientOverride: client
        )
        weak var weakModel = model

        model?.viewDidAppear()
        try await candidateGate.waitForEntryCount(1)
        XCTAssertTrue(model?.dashboardOwnerSnapshotForTesting().candidateEntityOwnerActive == true)
        XCTAssertTrue(model?.dashboardOwnerSnapshotForTesting().dashboardOwnerTailActive == true)

        model = nil
        for _ in 0..<100_000 where weakModel != nil { await Task.yield() }
        XCTAssertNil(weakModel, "A held bootstrap/candidate owner must not retain its dashboard model")

        await candidateGate.release(entry: 1)
        try await waitForBootstrapCondition {
            let socket = await connection.debugSnapshot()
            let metrics = await transport.metrics()
            return socket.state == .disconnected &&
                socket.pendingCommandCount == 0 &&
                socket.subscriptionCount == 0 &&
                socket.wireSubscriptionCount == 0 &&
                socket.deliveryOwnerCount == 0 &&
                socket.receiveLoopCount == 0 &&
                metrics.activeReceives == 0
        }
    }

    func testDeinitWithoutStopDrainsHeldServiceHistoryDetailFeedMountAndRender() async throws {
        let historyCard: JSONValue = .object([
            "type": .string("history-graph"),
            "title": .string("Emergency history"),
            "entities": .array([.string("sensor.emergency")]),
        ])
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Emergency cleanup",
            dashboardCards: [historyCard],
            holdHistoryAcknowledgements: true
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "deinit-complete-ownership-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let serviceGate = BootstrapServiceCallGate()
        let renderGate = DashboardEmergencyRenderGate()
        var model: DashboardViewModel? = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            lifecycleBootstrapClientOverride: client
        )
        weak var weakModel = model

        model?.viewDidAppear()
        try await waitForBootstrapCondition {
            let historyCount = await transport.historyCommandCount()
            let ready = await MainActor.run {
                model?.lifecycle.phase == .ready &&
                    model?.dashboardOwnerSnapshotForTesting().startupCount == 1
            }
            return historyCount == 1 && ready
        }
        let card = try XCTUnwrap(model?.homeCards.first)
        let feed = try XCTUnwrap(model?.graphHistoryRevisionFeed(for: card))

        model?.states["switch.emergency"] = HAState(entityId: "switch.emergency", state: "off")
        model?.installServiceCallerForTesting { _, _, _ in
            try await withTaskCancellationHandler(operation: {
                await serviceGate.wait()
                throw URLError(.timedOut)
            }, onCancel: {
                Task { await serviceGate.noteCancellation() }
            })
        }
        model?.setPower(entityID: "switch.emergency", isOn: true)
        model?.openDetails(entityID: "sensor.emergency")
        model?.loadDetailHistory(entityID: "sensor.emergency", hours: 1)
        try await waitForBootstrapCondition {
            let commands = await transport.historyCommandCount()
            let serviceHeld = await serviceGate.isWaiting()
            let ownershipHeld = await MainActor.run { () -> Bool in
                guard let snapshot = model?.dashboardOwnerSnapshotForTesting() else { return false }
                return snapshot.startupCount == 1 &&
                    snapshot.detailStartupCount == 1 &&
                    snapshot.serviceTaskCount == 1
            }
            return commands == 2 && serviceHeld && ownershipHeld
        }

        let coordinator = GraphChartRenderCoordinator(renderer: { request in
            renderGate.enterAndWait()
            return nil
        })
        var mountedLifecycle: GraphChartMountedLifecycle? = GraphChartMountedLifecycle(
            coordinator: coordinator
        )
        weak var weakMountedLifecycle = mountedLifecycle
        mountedLifecycle?.connect(
            feed: feed,
            inputs: [fullLifecycleRenderInput()],
            unit: "°C"
        )
        var mountLease: DashboardGraphChartMountLease? = model?.graphChartMountRegistry.mount(
            ownerID: card.nativeID,
            lifecycle: try XCTUnwrap(mountedLifecycle)
        )
        coordinator.requestVisual(
            GraphChartVisualRequest(
                token: "held-emergency-render",
                inputs: [fullLifecycleRenderInput()],
                unit: "°C",
                size: CGSize(width: 400, height: 180),
                scale: 2,
                zoomScale: 1,
                panFraction: 0,
                engine: .coreGraphics
            ),
            completion: { _, _ in XCTFail("A deinitialized owner cannot receive render completion") }
        )
        try await renderGate.waitForEntry()
        XCTAssertEqual(feed.observerCount, 1)
        XCTAssertEqual(model?.dashboardOwnerSnapshotForTesting().mountedOwnerCount, 1)

        model = nil
        for _ in 0..<100_000 where weakModel != nil { await Task.yield() }
        XCTAssertNil(weakModel, "Held service/history/detail/render work must not retain the dashboard model")
        try await waitForBootstrapCondition {
            let serviceCancelled = await serviceGate.cancellationCount() == 1
            let socket = await connection.debugSnapshot()
            let graphDetached = await MainActor.run {
                mountedLifecycle?.isInvalidated == true &&
                    feed.observerCount == 0 &&
                    coordinator.pendingWorkCount == 0
            }
            return serviceCancelled &&
                socket.state == .disconnected &&
                socket.pendingCommandCount == 0 &&
                socket.subscriptionCount == 0 &&
                socket.wireSubscriptionCount == 0 &&
                socket.deliveryOwnerCount == 0 &&
                socket.receiveLoopCount == 0 &&
                graphDetached
        }

        renderGate.release()
        await serviceGate.release()
        mountLease = nil
        mountedLifecycle = nil
        for _ in 0..<100_000 where weakMountedLifecycle != nil { await Task.yield() }
        XCTAssertNil(weakMountedLifecycle)
        _ = mountLease
    }

    func testOffMainFinalReleaseRevokesAcceptanceBeforeDelayedMainActorCleanup() async throws {
        let historyCard: JSONValue = .object([
            "type": .string("history-graph"),
            "title": .string("Off-main lifetime authority"),
            "entities": .array([.string("sensor.off_main_lifetime")]),
        ])
        let processingGate = BootstrapHistoryProcessingGate()
        let serviceGate = BootstrapServiceCallGate()
        let renderGate = DashboardEmergencyRenderGate()
        let renderCompletionCount = BootstrapLockedCounter()
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Off-main lifetime authority",
            dashboardCards: [historyCard]
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "off-main-lifetime-authority-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        var model: DashboardViewModel? = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore(),
            historyProcessingHook: { await processingGate.wait() }
        )
        weak var weakModel = model

        try await model?.bootstrapDashboard(using: client)
        try await waitForBootstrapCondition {
            let historyReady = await transport.historyCommandCount() == 1
            let ownerReady = await MainActor.run { () -> Bool in
                guard let snapshot = model?.dashboardOwnerSnapshotForTesting() else { return false }
                return snapshot.subscriptionKeys.count == 1 &&
                    snapshot.startupCount == 0 &&
                    snapshot.connectionStatusTaskActive
            }
            return historyReady && ownerReady
        }

        let card = try XCTUnwrap(model?.homeCards.first)
        let feed = try XCTUnwrap(model?.graphHistoryRevisionFeed(for: card))
        let mountRegistry = try XCTUnwrap(model?.graphChartMountRegistry)
        let authority = try XCTUnwrap(model?.lifetimeAuthorityForTesting)
        let entityCoordinator = try XCTUnwrap(model?.installedEntityCoordinatorForTesting())
        XCTAssertTrue(entityCoordinator.debugSnapshot().hasSubscription)
        XCTAssertTrue(entityCoordinator.debugSnapshot().hasStatusTask)

        let coordinator = GraphChartRenderCoordinator(renderer: { _ in
            renderGate.enterAndWait()
            return nil
        })
        var mountedLifecycle: GraphChartMountedLifecycle? = GraphChartMountedLifecycle(
            coordinator: coordinator
        )
        weak var weakMountedLifecycle = mountedLifecycle
        mountedLifecycle?.connect(
            feed: feed,
            inputs: [fullLifecycleRenderInput()],
            unit: "°C"
        )
        var mountLease: DashboardGraphChartMountLease? = mountRegistry.mount(
            ownerID: card.nativeID,
            lifecycle: try XCTUnwrap(mountedLifecycle)
        )
        coordinator.requestVisual(
            GraphChartVisualRequest(
                token: "off-main-held-render",
                inputs: [fullLifecycleRenderInput()],
                unit: "°C",
                size: CGSize(width: 400, height: 180),
                scale: 2,
                zoomScale: 1,
                panFraction: 0,
                engine: .coreGraphics
            ),
            completion: { _, _ in
                guard authority.acceptsWork else { return }
                renderCompletionCount.increment()
            }
        )
        try await renderGate.waitForEntry()

        let firstHistoryCommands = await transport.historyCommands()
        let cardHistoryID = try XCTUnwrap(firstHistoryCommands.first?["id"]?.dashboardTestInt)
        try await transport.pushHistory(
            id: cardHistoryID,
            states: [
                "sensor.off_main_lifetime": [
                    HACompactHistoryState(
                        state: "21.5",
                        lastUpdatedSeconds: 1_700_000_100
                    ),
                ],
            ]
        )
        try await waitForBootstrapCondition { await processingGate.waitingCount() == 1 }

        await transport.setHistoryAcknowledgementsHeld(true)
        model?.openDetails(entityID: "sensor.off_main_detail")
        model?.loadDetailHistory(entityID: "sensor.off_main_detail", hours: 1)
        try await waitForBootstrapCondition {
            let detailCommandReady = await transport.historyCommandCount() == 2
            let detailOwnerReady = await MainActor.run {
                model?.dashboardOwnerSnapshotForTesting().detailStartupCount == 1
            }
            return detailCommandReady && detailOwnerReady
        }
        let historyCommands = await transport.historyCommands()
        let detailHistoryID = try XCTUnwrap(historyCommands.last?["id"]?.dashboardTestInt)

        model?.states["switch.off_main_lifetime"] = HAState(
            entityId: "switch.off_main_lifetime",
            state: "off"
        )
        model?.installServiceCallerForTesting { _, _, _ in
            try await withTaskCancellationHandler(operation: {
                await serviceGate.wait()
                throw URLError(.timedOut)
            }, onCancel: {
                Task { await serviceGate.noteCancellation() }
            })
        }
        model?.setPower(entityID: "switch.off_main_lifetime", isOn: true)
        try await waitForBootstrapCondition {
            let serviceHeld = await serviceGate.isWaiting()
            let serviceOwned = await MainActor.run {
                model?.dashboardOwnerSnapshotForTesting().serviceTaskCount == 1
            }
            return serviceHeld && serviceOwned
        }

        // Queue reconnect in the same uninterrupted MainActor turn as final
        // release. It must be mirrored and synchronously cancelled before its
        // first suspension can mutate connection ownership.
        model?.reconnectRealtime()
        XCTAssertTrue(model?.dashboardOwnerSnapshotForTesting().reconnectTaskActive == true)
        XCTAssertEqual(feed.observerCount, 1)
        XCTAssertEqual(mountRegistry.liveMountCount(), 1)

        let holder = BootstrapOffMainModelHolder(try XCTUnwrap(model))
        model = nil
        let releaseCompleted = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            holder.release()
            releaseCompleted.signal()
        }

        // Deliberately block MainActor. The off-main last release and lifetime
        // revocation must finish synchronously even though owner cleanup cannot
        // yet run on MainActor.
        XCTAssertEqual(releaseCompleted.wait(timeout: .now() + 2), .success)
        XCTAssertNil(weakModel)
        XCTAssertFalse(authority.acceptsWork)
        XCTAssertFalse(mountedLifecycle?.isInvalidated == true)
        XCTAssertEqual(feed.observerCount, 1)
        XCTAssertEqual(mountRegistry.liveMountCount(), 1)
        XCTAssertEqual(renderCompletionCount.value, 0)
        XCTAssertTrue(entityCoordinator.debugSnapshot().hasStatusTask)

        let lateCallbacksQueued = DispatchSemaphore(value: 0)
        Task.detached {
            try? await transport.pushState(
                entityID: "sensor.off_main_late_entity",
                state: "must-not-publish"
            )
            try? await transport.resolveHistoryAcknowledgement(
                id: detailHistoryID,
                success: true
            )
            await processingGate.open()
            await serviceGate.release()
            renderGate.release()
            lateCallbacksQueued.signal()
        }
        XCTAssertEqual(lateCallbacksQueued.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(authority.acceptsWork)
        XCTAssertEqual(renderCompletionCount.value, 0)
        XCTAssertEqual(entityCoordinator.debugSnapshot().entityCount, 0)

        do {
            try await waitForBootstrapCondition {
                let socket = await connection.debugSnapshot()
                let metrics = await transport.metrics()
                let serviceCancelled = await serviceGate.cancellationCount() == 1
                let graphDrained = await MainActor.run {
                    mountedLifecycle?.isInvalidated == true &&
                        feed.observerCount == 0 &&
                        mountRegistry.liveMountCount() == 0 &&
                        coordinator.pendingWorkCount == 0
                }
                let entityDrained = await MainActor.run { () -> Bool in
                    let snapshot = entityCoordinator.debugSnapshot()
                    return !snapshot.hasSubscription &&
                        !snapshot.hasStatusTask &&
                        !snapshot.hasSubscriptionStartTask &&
                        snapshot.entityCount == 0
                }
                return serviceCancelled &&
                    graphDrained &&
                    entityDrained &&
                    socket.state == .disconnected &&
                    socket.pendingCommandCount == 0 &&
                    socket.subscriptionCount == 0 &&
                    socket.wireSubscriptionCount == 0 &&
                    socket.deliveryOwnerCount == 0 &&
                    socket.bufferedDeliveryCount == 0 &&
                    socket.activeDeliveryTaskCount == 0 &&
                    socket.activeTerminationTaskCount == 0 &&
                    socket.pendingTerminationCount == 0 &&
                    socket.receiveLoopCount == 0 &&
                    metrics.activeReceives == 0
            }
        } catch {
            let socket = await connection.debugSnapshot()
            let metrics = await transport.metrics()
            let serviceCancellationCount = await serviceGate.cancellationCount()
            let entity = entityCoordinator.debugSnapshot()
            print(
                "MODULE05_OFF_MAIN_TIMEOUT socket=\(socket) metrics=\(metrics) " +
                    "service_cancellations=\(serviceCancellationCount) " +
                    "entity=\(entity) invalidated=\(mountedLifecycle?.isInvalidated == true) " +
                    "feed_observers=\(feed.observerCount) mounts=\(mountRegistry.liveMountCount()) " +
                    "render_pending=\(coordinator.pendingWorkCount)"
            )
            throw error
        }

        XCTAssertEqual(renderCompletionCount.value, 0)
        XCTAssertEqual(coordinator.statistics.acceptedRevisionCount, 0)
        XCTAssertEqual(coordinator.pendingWorkCount, 0)
        XCTAssertFalse(authority.acceptsWork)
        mountLease = nil
        mountedLifecycle = nil
        for _ in 0..<100_000 where weakMountedLifecycle != nil { await Task.yield() }
        XCTAssertNil(weakMountedLifecycle)
        _ = mountLease
    }

    func testHundredFullDashboardReconnectRetryStopCyclesReturnEveryOwnerToZero() async throws {
        let historyCard: JSONValue = .object([
            "type": .string("history-graph"),
            "title": .string("Lifecycle history"),
            "entities": .array([.string("sensor.lifecycle")]),
        ])
        let transport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Lifecycle",
            dashboardCards: [historyCard]
        )
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "dashboard-full-lifecycle-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        var model: DashboardViewModel? = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )
        weak var weakModel = model
        let started = Date()

        for cycle in 1...100 {
            let entityBeforeBootstrap = await transport.entitySubscriptionCount()
            let historyBeforeBootstrap = await transport.historyCommandCount()
            let lovelaceBeforeBootstrap = await transport.lovelaceForces().count
            try await model?.bootstrapDashboard(using: client)
            try await waitForBootstrapCondition {
                await MainActor.run {
                    guard let model = model else { return false }
                    let snapshot = model.dashboardOwnerSnapshotForTesting()
                    return model.lifecycle.phase == .ready &&
                        snapshot.subscriptionKeys.count == 1 &&
                        snapshot.startupCount == 0
                }
            }
            let entityAfterBootstrap = await transport.entitySubscriptionCount()
            let historyAfterBootstrap = await transport.historyCommandCount()
            let lovelaceAfterBootstrap = await transport.lovelaceForces().count
            XCTAssertEqual(entityAfterBootstrap, entityBeforeBootstrap + 1)
            XCTAssertEqual(historyAfterBootstrap, historyBeforeBootstrap + 1)
            XCTAssertEqual(lovelaceAfterBootstrap, lovelaceBeforeBootstrap + 1)

            let card = try XCTUnwrap(model?.homeCards.first)
            let feed = try XCTUnwrap(model?.graphHistoryRevisionFeed(for: card))
            var mountedLifecycle: GraphChartMountedLifecycle? = GraphChartMountedLifecycle()
            weak var weakMountedLifecycle = mountedLifecycle
            mountedLifecycle?.connect(
                feed: feed,
                inputs: [fullLifecycleRenderInput()],
                unit: "°C"
            )
            var mountLease: DashboardGraphChartMountLease? = model?.graphChartMountRegistry.mount(
                ownerID: card.nativeID,
                lifecycle: try XCTUnwrap(mountedLifecycle)
            )
            mountedLifecycle?.coordinator.submitAcceptedRevision(
                inputs: [fullLifecycleRenderInput()],
                unit: "°C"
            )
            try await waitForBootstrapCondition {
                await MainActor.run {
                    mountedLifecycle?.coordinator.pendingWorkCount == 0
                }
            }
            XCTAssertEqual(feed.observerCount, 1)
            XCTAssertEqual(model?.dashboardOwnerSnapshotForTesting().mountedOwnerCount, 1)

            let entityBeforeReconnect = await transport.entitySubscriptionCount()
            let historyBeforeReconnect = await transport.historyCommandCount()
            let lovelaceBeforeReconnect = await transport.lovelaceForces().count
            model?.reconnectRealtime()
            try await waitForBootstrapCondition {
                let entityReady = await transport.entitySubscriptionCount() == entityBeforeReconnect + 1
                let historyReady = await transport.historyCommandCount() == historyBeforeReconnect + 1
                let lovelaceReady = await transport.lovelaceForces().count == lovelaceBeforeReconnect + 1
                let socketReady = await connection.debugSnapshot().state == .ready
                let modelReady = await MainActor.run { model?.lifecycle.phase == .ready }
                return entityReady && historyReady && lovelaceReady && socketReady && modelReady
            }
            XCTAssertFalse(mountedLifecycle?.isInvalidated == true)
            XCTAssertEqual(feed.observerCount, 1)

            let historyBeforeRetry = await transport.historyCommandCount()
            let lovelaceBeforeRetry = await transport.lovelaceForces().count
            model?.retryLovelace()
            try await waitForBootstrapCondition {
                let forces = await transport.lovelaceForces()
                return forces.count == lovelaceBeforeRetry + 1 && forces.last == true
            }

            model?.openDetails(entityID: "sensor.lifecycle")
            model?.loadDetailHistory(
                entityID: "sensor.lifecycle",
                hours: AppConfig.graphTimeRangePolicy.detailDefault.hours
            )
            try await waitForBootstrapCondition {
                let detailStarted = await transport.historyCommandCount() == historyBeforeRetry + 1
                let detailOwned = await MainActor.run { () -> Bool in
                    guard let snapshot = model?.dashboardOwnerSnapshotForTesting() else { return false }
                    return snapshot.desiredDetailHistoryKeys.count == 1 &&
                        snapshot.detailSubscriptionKeys.count == 1 &&
                        snapshot.detailStartupCount == 0
                }
                return detailStarted && detailOwned
            }
            let historyBeforeHealthyRetry = await transport.historyCommandCount()
            await model?.retryHistoriesForActiveViewForTesting()
            let historyAfterHealthyRetry = await transport.historyCommandCount()
            XCTAssertEqual(
                historyAfterHealthyRetry,
                historyBeforeHealthyRetry,
                "A scoped retry must retain healthy card and detail owners in cycle \(cycle)"
            )

            await model?.stop()
            XCTAssertEqual(model?.lifecycle.phase, .stopped)
            let owner = try XCTUnwrap(model?.dashboardOwnerSnapshotForTesting())
            XCTAssertTrue(owner.desiredHistoryKeys.isEmpty)
            XCTAssertTrue(owner.subscriptionKeys.isEmpty)
            XCTAssertTrue(owner.generationKeys.isEmpty)
            XCTAssertEqual(owner.startupCount, 0)
            XCTAssertTrue(owner.feedObserverCounts.isEmpty)
            XCTAssertTrue(owner.historyKeys.isEmpty)
            XCTAssertTrue(owner.statusKeys.isEmpty)
            XCTAssertEqual(owner.mountedOwnerCount, 0)
            XCTAssertTrue(owner.desiredDetailHistoryKeys.isEmpty)
            XCTAssertTrue(owner.detailSubscriptionKeys.isEmpty)
            XCTAssertTrue(owner.detailGenerationKeys.isEmpty)
            XCTAssertEqual(owner.detailStartupCount, 0)
            XCTAssertTrue(owner.detailHistoryKeys.isEmpty)
            XCTAssertTrue(owner.detailStatusKeys.isEmpty)
            XCTAssertFalse(owner.entityOwnerActive)
            XCTAssertFalse(owner.candidateEntityOwnerActive)
            XCTAssertFalse(owner.lovelaceSubscriptionActive)
            XCTAssertFalse(owner.bootstrapTaskActive)
            XCTAssertFalse(owner.connectionStatusTaskActive)
            XCTAssertFalse(owner.lovelaceFetchTaskActive)
            XCTAssertFalse(owner.dashboardOwnerTailActive)
            XCTAssertEqual(owner.serviceTaskCount, 0)
            XCTAssertFalse(owner.webSocketClientActive)
            XCTAssertFalse(owner.installedClientActive)
            XCTAssertTrue(mountedLifecycle?.isInvalidated == true)
            XCTAssertEqual(feed.observerCount, 0)
            XCTAssertEqual(mountedLifecycle?.coordinator.pendingWorkCount, 0)

            let socket = await connection.debugSnapshot()
            XCTAssertEqual(socket.state, .disconnected)
            XCTAssertEqual(socket.pendingCommandCount, 0)
            XCTAssertEqual(socket.subscriptionCount, 0)
            XCTAssertEqual(socket.wireSubscriptionCount, 0)
            XCTAssertEqual(socket.receiveLoopCount, 0)
            XCTAssertEqual(socket.deliveryOwnerCount, 0)
            XCTAssertEqual(socket.bufferedDeliveryCount, 0)
            XCTAssertEqual(socket.activeDeliveryTaskCount, 0)
            XCTAssertEqual(socket.activeTerminationTaskCount, 0)
            XCTAssertEqual(socket.pendingTerminationCount, 0)

            mountLease = nil
            mountedLifecycle = nil
            for _ in 0..<100_000 where weakMountedLifecycle != nil { await Task.yield() }
            XCTAssertNil(weakMountedLifecycle, "Graph lifecycle leaked after cycle \(cycle)")
            _ = mountLease
        }

        let elapsed = Date().timeIntervalSince(started)
        let finalTransport = await transport.metrics()
        let finalEntitySubscriptions = await transport.entitySubscriptionCount()
        let finalHistorySubscriptions = await transport.historyCommandCount()
        let finalLovelaceFetches = await transport.lovelaceForces().count
        XCTAssertEqual(finalTransport.activeReceives, 0)
        XCTAssertEqual(finalTransport.disconnectCalls, 200)
        XCTAssertEqual(finalEntitySubscriptions, 200)
        XCTAssertEqual(finalHistorySubscriptions, 300)
        XCTAssertEqual(finalLovelaceFetches, 300)
        XCTAssertLessThan(elapsed, 30)

        model = nil
        for _ in 0..<100_000 where weakModel != nil { await Task.yield() }
        XCTAssertNil(weakModel)
        print(
            "MODULE05_FULL_LIFECYCLE cycles=100 elapsed_seconds=\(String(format: "%.3f", elapsed)) " +
                "entity_subscriptions=200 history_subscriptions=300 lovelace_fetches=300 " +
                "final_socket_owners=0 final_card_owners=0 final_detail_owners=0 " +
                "final_feed_observers=0 final_mounts=0 final_render_work=0 model_released=true"
        )
    }

    private func assertBootstrapFailureDisconnects(
        mode: DashboardBootstrapTransport.Mode
    ) async throws {
        let transport = DashboardBootstrapTransport(mode: mode)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "dashboard-bootstrap-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        let model = DashboardViewModel()

        let bootstrapError: Error
        do {
            try await model.bootstrapDashboard(using: client)
            XCTFail("Expected dashboard bootstrap to fail in mode \(mode)")
            return
        } catch {
            bootstrapError = error
        }

        switch mode {
        case .malformedLovelace:
            XCTAssertTrue(
                bootstrapError is DecodingError || bootstrapError is LovelaceDecodeError,
                "Malformed Lovelace must fail through typed config decoding."
            )
        case .rejectStateSubscription:
            XCTAssertEqual(
                bootstrapError as? HomeAssistantWebSocketError,
                .commandFailed(
                    code: "injected_failure",
                    message: "state subscription rejected"
                )
            )
        case .rejectCurrentUser:
            XCTFail("Current-user rejection is expected to be nonfatal")
        case .holdCurrentUser:
            XCTFail("Held current-user mode is not a bootstrap failure fixture")
        case .holdFirstCurrentUser, .holdSecondAuthentication, .success:
            XCTFail("Successful bootstrap mode is not a failure fixture")
        }

        let snapshot = await connection.debugSnapshot()
        let metrics = await transport.metrics()
        XCTAssertEqual(snapshot.state, .disconnected)
        XCTAssertEqual(snapshot.receiveLoopCount, 0)
        XCTAssertEqual(snapshot.pendingCommandCount, 0)
        XCTAssertEqual(snapshot.subscriptionCount, 0)
        XCTAssertEqual(metrics.disconnectCalls, 1)
        XCTAssertEqual(metrics.activeReceives, 0)
    }
}

private func fullLifecycleRenderInput() -> GraphRenderSeriesInput {
    GraphRenderSeriesInput(
        entityID: "sensor.lifecycle",
        name: "Lifecycle",
        unit: "°C",
        color: GraphColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1),
        history: HAHistorySeries(
            entityID: "sensor.lifecycle",
            points: [
                HAHistoryPoint(
                    entityId: "sensor.lifecycle",
                    state: "21.5",
                    attributes: nil,
                    lastChangedSeconds: 1_700_000_000,
                    lastUpdatedSeconds: 1_700_000_000
                ),
            ]
        ),
        windowStart: 1_700_000_000,
        windowEnd: 1_700_003_600
    )
}

private enum BootstrapTestTimeout: Error {
    case conditionNotMet
}

private func waitForBootstrapCondition(
    _ condition: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<100_000 {
        if await condition() { return }
        await Task.yield()
    }
    throw BootstrapTestTimeout.conditionNotMet
}

private actor BootstrapCandidateGate {
    private var entryCount = 0
    private var heldEntries: [Int: CheckedContinuation<Void, Never>] = [:]

    func enterAndWait() async {
        entryCount += 1
        let entry = entryCount
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var updated = heldEntries
            updated[entry] = continuation
            heldEntries = updated
        }
    }

    func waitForEntryCount(_ expected: Int) async throws {
        for _ in 0..<100_000 {
            if entryCount >= expected { return }
            await Task.yield()
        }
        throw BootstrapTestTimeout.conditionNotMet
    }

    func release(entry: Int) {
        heldEntries.removeValue(forKey: entry)?.resume()
    }
}

private actor BootstrapServiceCallRecorder {
    private var calls: [(domain: String, service: String, data: [String: JSONValue])] = []

    func append(domain: String, service: String, data: [String: JSONValue]) {
        calls.append((domain, service, data))
    }

    func count() -> Int {
        calls.count
    }
}

private actor BootstrapServiceCallGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var cancellationObservations = 0

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func noteCancellation() {
        cancellationObservations += 1
    }

    func cancellationCount() -> Int {
        cancellationObservations
    }

    func isWaiting() -> Bool {
        continuation != nil
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor BootstrapHistoryProcessingGate {
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

private final class BootstrapOffMainModelHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var model: DashboardViewModel?

    init(_ model: DashboardViewModel) {
        self.model = model
    }

    func release() {
        lock.lock()
        model = nil
        lock.unlock()
    }
}

private final class BootstrapLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class DashboardEmergencyRenderGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var entered = false

    func enterAndWait() {
        lock.lock()
        entered = true
        lock.unlock()
        releaseSemaphore.wait()
    }

    func waitForEntry() async throws {
        for _ in 0..<100_000 {
            lock.lock()
            let current = entered
            lock.unlock()
            if current { return }
            await Task.yield()
        }
        throw BootstrapTestTimeout.conditionNotMet
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private actor DashboardBootstrapTransport: HomeAssistantWebSocketTransport {
    enum Mode {
        case malformedLovelace
        case rejectStateSubscription
        case rejectCurrentUser
        case holdCurrentUser
        case holdFirstCurrentUser
        case holdSecondAuthentication
        case success
    }

    private let mode: Mode
    private let dashboardTitle: String?
    private let successfulUserID: String
    private let dashboardCards: [JSONValue]
    private let registryEntities: [JSONValue]
    private var connected = false
    private var inbound: [Result<HAWebSocketFrame, Error>] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var sent: [[String: JSONValue]] = []
    private var activeReceives = 0
    private var disconnectCalls = 0
    private var stateSubscriptionID: Int?
    private var historyAcknowledgementsHeld: Bool

    init(
        mode: Mode,
        dashboardTitle: String? = nil,
        successfulUserID: String = "user-1",
        dashboardCards: [JSONValue] = [],
        registryEntities: [JSONValue] = [],
        holdHistoryAcknowledgements: Bool = false
    ) {
        self.mode = mode
        self.dashboardTitle = dashboardTitle
        self.successfulUserID = successfulUserID
        self.dashboardCards = dashboardCards
        self.registryEntities = registryEntities
        self.historyAcknowledgementsHeld = holdHistoryAcknowledgements
    }

    func connect() async throws {
        connected = true
        try deliver(["type": .string("auth_required")])
    }

    func send(_ frame: HAWebSocketFrame) async throws {
        guard connected else {
            throw HomeAssistantWebSocketError.disconnected
        }
        let message = try decode(frame)
        sent.append(message)
        if message["type"] == .string("auth") {
            if mode == .holdSecondAuthentication,
               authenticationCommandCount() == 2
            {
                return
            }
            try deliver([
                "type": .string("auth_ok"),
                "ha_version": .string("2025.7.0"),
            ])
            return
        }
        guard let id = message["id"]?.dashboardTestInt else {
            return
        }

        switch message["type"]?.dashboardTestString {
        case "lovelace/config":
            let result: JSONValue
            switch mode {
            case .malformedLovelace:
                result = .string("not-a-lovelace-config")
            case .rejectStateSubscription:
                result = .object(["views": .array([])])
            case .rejectCurrentUser:
                result = .object(["views": .array([
                    .object([
                        "title": .string("Public"),
                        "path": .string("default_view"),
                        "cards": .array([]),
                    ]),
                    .object([
                        "title": .string("Restricted"),
                        "path": .string("restricted"),
                        "visible": .array([.object(["user": .string("user-1")])]),
                        "cards": .array([]),
                    ]),
                ])])
            case .holdCurrentUser:
                result = .object(["views": .array([
                    .object([
                        "title": .string("Obsolete"),
                        "path": .string("default_view"),
                        "cards": .array([]),
                    ]),
                ])])
            case .holdFirstCurrentUser, .holdSecondAuthentication, .success:
                result = .object(["views": .array([
                    .object([
                        "title": .string(dashboardTitle ?? "Current"),
                        "path": .string("default_view"),
                        "cards": .array(dashboardCards),
                    ]),
                    .object([
                        "title": .string("Restricted Latest"),
                        "path": .string("restricted"),
                        "visible": .array([.object(["user": .string(successfulUserID)])]),
                        "cards": .array([]),
                    ]),
                ])])
            }
            try deliverSuccess(id: id, result: result)
        case "auth/current_user":
            if case .holdCurrentUser = mode {
                return
            } else if case .holdFirstCurrentUser = mode,
                      currentUserCommandCount() == 1
            {
                return
            } else if case .rejectCurrentUser = mode {
                try deliver([
                    "id": .int(id),
                    "type": .string("result"),
                    "success": .bool(false),
                    "error": .object([
                        "code": .string("injected_failure"),
                        "message": .string("current user unavailable"),
                    ]),
                ])
            } else {
                try deliverSuccess(id: id, result: .object(["id": .string(successfulUserID)]))
            }
        case "config/entity_registry/list_for_display":
            try deliverSuccess(id: id, result: .object(["entities": .array(registryEntities)]))
        case "frontend/get_user_data":
            try deliverSuccess(id: id, result: .object(["value": .null]))
        case "subscribe_entities":
            stateSubscriptionID = id
            if mode == .rejectStateSubscription {
                try deliver([
                    "id": .int(id),
                    "type": .string("result"),
                    "success": .bool(false),
                    "error": .object([
                        "code": .string("injected_failure"),
                        "message": .string("state subscription rejected"),
                    ]),
                ])
            } else {
                try deliverSuccess(id: id, result: .null)
                try deliver([
                    "id": .int(id),
                    "type": .string("event"),
                    "event": .object(["a": .object([:])]),
                ])
            }
        case "subscribe_events":
            try deliverSuccess(id: id, result: .null)
        case "history/stream":
            if !historyAcknowledgementsHeld {
                try deliverSuccess(id: id, result: .null)
            }
        case "unsubscribe_events":
            try deliverSuccess(id: id, result: .null)
        default:
            break
        }
    }

    func receive() async throws -> HAWebSocketFrame {
        guard connected else {
            throw HomeAssistantWebSocketError.disconnected
        }
        if !inbound.isEmpty {
            return try inbound.removeFirst().get()
        }
        activeReceives += 1
        return try await withCheckedThrowingContinuation { continuation in
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

    func metrics() -> (disconnectCalls: Int, activeReceives: Int) {
        (disconnectCalls, activeReceives)
    }

    func sentMessages() -> [[String: JSONValue]] {
        sent
    }

    func pushState(entityID: String, state: String) throws {
        guard let stateSubscriptionID = stateSubscriptionID else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        try deliver([
            "id": .int(stateSubscriptionID),
            "type": .string("event"),
            "event": .object([
                "a": .object([
                    entityID: .object([
                        "s": .string(state),
                        "a": .object([:]),
                        "c": .string("test-context"),
                        "lc": .double(1_700_000_000),
                    ]),
                ]),
            ]),
        ])
    }

    func pushMalformedEntityDelta() throws {
        guard let stateSubscriptionID = stateSubscriptionID else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        try deliver([
            "id": .int(stateSubscriptionID),
            "type": .string("event"),
            "event": .object([
                "c": .object([
                    "sensor.bad": .object([
                        "+": .object(["lc": .string("not-a-number")]),
                    ]),
                ]),
            ]),
        ])
    }

    func pushLovelaceUpdate() throws {
        guard let command = sent.last(where: {
            $0["type"] == .string("subscribe_events") &&
                $0["event_type"] == .string("lovelace_updated")
        }), let id = command["id"]?.dashboardTestInt
        else { throw HomeAssistantWebSocketError.invalidMessage }
        try deliver([
            "id": .int(id),
            "type": .string("event"),
            "event": .object([
                "event_type": .string("lovelace_updated"),
                "data": .object(["url_path": .null]),
            ]),
        ])
    }

    func lovelaceForces() -> [Bool] {
        sent.compactMap { command in
            guard command["type"] == .string("lovelace/config"),
                  case let .bool(force)? = command["force"]
            else { return nil }
            return force
        }
    }

    func currentUserCommandCount() -> Int {
        sent.filter { $0["type"] == .string("auth/current_user") }.count
    }

    func authenticationCommandCount() -> Int {
        sent.filter { $0["type"] == .string("auth") }.count
    }

    func entitySubscriptionCount() -> Int {
        sent.filter { $0["type"] == .string("subscribe_entities") }.count
    }

    func historyCommandCount() -> Int {
        sent.filter { $0["type"] == .string("history/stream") }.count
    }

    func historyCommands() -> [[String: JSONValue]] {
        sent.filter { $0["type"] == .string("history/stream") }
    }

    func setHistoryAcknowledgementsHeld(_ held: Bool) {
        historyAcknowledgementsHeld = held
    }

    func resolveHistoryAcknowledgement(id: Int, success: Bool) throws {
        var message: [String: JSONValue] = [
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(success),
            "result": .null,
        ]
        if !success {
            message["error"] = .object([
                "code": .string("injected_failure"),
                "message": .string("history subscription rejected"),
            ])
        }
        try deliver(message)
    }

    func pushHistory(id: Int, states: [String: [HACompactHistoryState]]) throws {
        let data = try JSONEncoder().encode(HAHistoryStreamMessage(states: states))
        let event = try JSONDecoder().decode(JSONValue.self, from: data)
        try deliver([
            "id": .int(id),
            "type": .string("event"),
            "event": event,
        ])
    }

    func resolveHeldCurrentUser(id userID: String) throws {
        guard let command = sent.last(where: { $0["type"] == .string("auth/current_user") }),
              let id = command["id"]?.dashboardTestInt
        else { throw HomeAssistantWebSocketError.invalidMessage }
        try deliverSuccess(id: id, result: .object(["id": .string(userID)]))
    }

    func resolveHeldCurrentUser(commandOrdinal: Int, id userID: String) throws {
        let commands = sent.filter { $0["type"] == .string("auth/current_user") }
        guard commands.indices.contains(commandOrdinal),
              let id = commands[commandOrdinal]["id"]?.dashboardTestInt
        else { throw HomeAssistantWebSocketError.invalidMessage }
        try deliverSuccess(id: id, result: .object(["id": .string(userID)]))
    }

    private func deliverSuccess(id: Int, result: JSONValue) throws {
        try deliver([
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": result,
        ])
    }

    private func deliver(_ object: [String: JSONValue]) throws {
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

private final class BootstrapMemoryNavigationPreferenceStore: LovelaceNavigationPreferenceStore {
    private var values: [String: Any] = [:]
    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}

private extension JSONValue {
    var dashboardTestInt: Int? {
        guard case let .int(value) = self else { return nil }
        return value
    }

    var dashboardTestString: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}
