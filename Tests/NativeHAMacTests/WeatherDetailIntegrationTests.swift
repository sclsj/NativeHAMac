import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class WeatherDetailIntegrationTests: XCTestCase {
    func testAuthorizedReadOnlyLiveWeatherDetailSmoke() async throws {
        guard ProcessInfo.processInfo.environment["NATIVEHA_RUN_LIVE_WEATHER_DETAIL_SMOKE"] == "1" else {
            throw XCTSkip(
                "Set NATIVEHA_RUN_LIVE_WEATHER_DETAIL_SMOKE=1 for the authorized read-only detail smoke"
            )
        }
        let token = try String(
            contentsOfFile: AppConfig.tokenFilePath,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        var accepted: (HomeAssistantConfiguration, HAConfig, [HAState])?
        for baseURL in AppConfig.baseURLs {
            let configuration = HomeAssistantConfiguration(
                baseURL: baseURL,
                accessToken: token,
                timeout: 12
            )
            let rest = HomeAssistantRESTClient(configuration: configuration)
            if let config = try? await rest.fetchConfig(),
               let states = try? await rest.fetchStates()
            {
                accepted = (configuration, config, states)
                break
            }
        }
        let (configuration, serverConfig, states) = try XCTUnwrap(accepted)
        let weatherStates = states.filter {
            $0.entityId.hasPrefix("weather.") &&
                !HAWeatherForecastFeatures.supportedTypes(in: $0.attributes).isEmpty
        }
        let state = try XCTUnwrap(
            weatherStates.first { $0.entityId == "weather.forecast_wo_de_jia" }
                ?? weatherStates.first
        )
        let client = HomeAssistantWebSocketClient(configuration: configuration)
        try await client.connect()
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state],
            homeAssistantConfig: serverConfig
        )

        model.openDetails(entityID: state.entityId)
        let defaultType = try XCTUnwrap(model.weatherDetailCoordinator.selectedType)
        try await waitUntilLive {
            model.weatherDetailCoordinator.modernEvent?.forecast?.count ?? 0 > 2
        }
        let firstCount = try XCTUnwrap(model.weatherDetailCoordinator.modernEvent?.forecast?.count)
        XCTAssertEqual(model.weatherDetailCoordinator.modernEvent?.type, defaultType)
        XCTAssertEqual(model.weatherDetailPresentation()?.forecast?.itemCount, firstCount)

        var switchedType: HAWeatherForecastType?
        var switchedCount: Int?
        if let alternate = model.weatherDetailCoordinator.supportedTypes.first(where: { $0 != defaultType }) {
            model.selectWeatherForecastType(alternate)
            try await waitUntilLive {
                model.weatherDetailCoordinator.modernEvent?.type == alternate &&
                    (model.weatherDetailCoordinator.modernEvent?.forecast?.count ?? 0) > 2
            }
            switchedType = alternate
            switchedCount = model.weatherDetailCoordinator.modernEvent?.forecast?.count
            XCTAssertEqual(model.weatherDetailPresentation()?.forecast?.itemCount, switchedCount)
        }

        model.closeDetails()
        await model.awaitDashboardOwnerOperationsForTesting()
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().weatherDetail.ownerCount, 0)
        let closedSocket = await client.connection.debugSnapshot()
        XCTAssertEqual(closedSocket.subscriptionCount, 0)
        await client.disconnect()
        let configAfter = try await HomeAssistantRESTClient(configuration: configuration).fetchConfig()
        XCTAssertEqual(configAfter, serverConfig)
        print(
            "MODULE07_DETAIL_LIVE entity=\(state.entityId) default=\(defaultType.rawValue):\(firstCount) " +
                "switched=\(switchedType?.rawValue ?? "none"):\(switchedCount.map(String.init) ?? "none") " +
                "owners=0 config_unchanged=true commands=weather/subscribe_forecast|unsubscribe_events"
        )
    }

    func testOpenDailySwitchHourlyRejectsLateDailyAndCloseReturnsOwnershipToZero() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 3)
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state],
            homeAssistantConfig: .init(timeZone: "Asia/Shanghai", unitSystem: .init(temperature: "°C", length: "km"))
        )

        model.openDetails(entityID: state.entityId)
        try await waitUntil { await transport.forecastCommands().count == 1 }
        try await waitUntil { model.weatherDetailCoordinator.hasSubscription }
        let initialCommands = await transport.forecastCommands()
        let daily = try XCTUnwrap(initialCommands.first)
        XCTAssertEqual(daily["forecast_type"], .string("daily"))
        let dailyID = try XCTUnwrap(daily["id"]?.integer)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().weatherDetail.ownerCount, 1)

        try await transport.pushForecast(id: dailyID, type: .daily, temperatures: [20, 21, 22, 23, 24, 25])
        try await waitUntil { model.weatherDetailCoordinator.modernEvent?.forecast?.count == 6 }

        model.selectWeatherForecastType(.hourly)
        XCTAssertNil(model.weatherDetailCoordinator.modernEvent, "Type invalidation clears old publication synchronously")
        XCTAssertEqual(model.weatherDetailCoordinator.selectedType, .hourly)
        try await waitUntil { await transport.forecastCommands().count == 2 }
        try await waitUntil { model.weatherDetailCoordinator.hasSubscription }
        let commands = await transport.forecastCommands()
        let hourly = commands[1]
        XCTAssertEqual(hourly["forecast_type"], .string("hourly"))
        let hourlyID = try XCTUnwrap(hourly["id"]?.integer)

        try await transport.pushForecast(id: dailyID, type: .daily, temperatures: [90, 91, 92])
        await Task.yield()
        XCTAssertNil(model.weatherDetailCoordinator.modernEvent, "Retired wire event cannot mutate the new tab")

        try await transport.pushForecast(id: hourlyID, type: .hourly, temperatures: Array(0..<48).map(Double.init))
        try await waitUntil { model.weatherDetailCoordinator.modernEvent?.forecast?.count == 48 }
        XCTAssertEqual(model.weatherDetailPresentation()?.forecast?.itemCount, 48)

        model.closeDetails()
        XCTAssertNil(model.selectedEntityID)
        XCTAssertFalse(model.weatherDetailCoordinator.debugSnapshot().desired)
        await model.awaitDashboardOwnerOperationsForTesting()
        let final = model.dashboardOwnerSnapshotForTesting().weatherDetail
        XCTAssertFalse(final.startupActive)
        XCTAssertFalse(final.subscriptionActive)
        XCTAssertNil(final.selectedEntityID)
        let socket = await client.connection.debugSnapshot()
        XCTAssertEqual(socket.subscriptionCount, 0)
        await client.disconnect()
    }

    func testHeldAcknowledgementTrueABATabChurnAndSameKeyReopenNeverOverlap() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: false)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 3)
        let model = DashboardViewModel(webSocketClient: client, initialStates: [state.entityId: state])

        model.openDetails(entityID: state.entityId)
        try await waitUntil { await transport.forecastCommands().count == 1 }
        let firstGeneration = model.weatherDetailCoordinator.debugSnapshot().presentationGeneration
        XCTAssertTrue(model.weatherDetailCoordinator.hasStartup)

        model.selectWeatherForecastType(.hourly)
        XCTAssertFalse(model.weatherDetailCoordinator.hasStartup, "Old held startup is detached synchronously")
        try await waitUntil { await transport.forecastCommands().count == 2 }
        let secondGeneration = model.weatherDetailCoordinator.debugSnapshot().presentationGeneration
        XCTAssertNotEqual(firstGeneration, secondGeneration)
        XCTAssertLessThanOrEqual(model.weatherDetailCoordinator.ownerCount, 1)

        model.selectWeatherForecastType(.daily)
        try await waitUntil { await transport.forecastCommands().count == 3 }
        let thirdGeneration = model.weatherDetailCoordinator.debugSnapshot().presentationGeneration
        XCTAssertNotEqual(secondGeneration, thirdGeneration, "A-B-A must establish fresh presentation authority")

        model.openDetails(entityID: state.entityId)
        try await waitUntil { await transport.forecastCommands().count == 4 }
        let fourthGeneration = model.weatherDetailCoordinator.debugSnapshot().presentationGeneration
        XCTAssertNotEqual(thirdGeneration, fourthGeneration, "Same-key reopen must not reuse the held attempt")
        XCTAssertLessThanOrEqual(model.weatherDetailCoordinator.ownerCount, 1)

        let commands = await transport.forecastCommands()
        for stale in commands.prefix(3) {
            try await transport.acknowledge(id: try XCTUnwrap(stale["id"]?.integer))
        }
        await Task.yield()
        XCTAssertFalse(model.weatherDetailCoordinator.hasSubscription)
        let beforeCurrentAck = await client.connection.debugSnapshot()
        XCTAssertEqual(
            beforeCurrentAck.subscriptionCount,
            1,
            "Only the fourth, current pre-ack logical owner remains after late stale acknowledgements"
        )

        try await transport.acknowledge(id: try XCTUnwrap(commands[3]["id"]?.integer))
        try await waitUntil { model.weatherDetailCoordinator.hasSubscription }
        let active = await client.connection.debugSnapshot()
        XCTAssertEqual(active.subscriptionCount, 1)
        model.closeDetails()
        await model.awaitDashboardOwnerOperationsForTesting()
        XCTAssertEqual(model.weatherDetailCoordinator.ownerCount, 0)
        let closed = await client.connection.debugSnapshot()
        XCTAssertEqual(closed.subscriptionCount, 0)
        XCTAssertEqual(closed.deliveryOwnerCount, 0)
        await client.disconnect()
    }

    func testUnsupportedThenFeatureGainStartsOnceAndOrdinaryFeatureLossDoesNotChurnOwner() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let client = try await connectedClient(transport)
        let unsupported = weatherState(features: 0)
        let model = DashboardViewModel(webSocketClient: client, initialStates: [unsupported.entityId: unsupported])
        model.openDetails(entityID: unsupported.entityId)
        await Task.yield()
        let unsupportedCommands = await transport.forecastCommands()
        XCTAssertTrue(unsupportedCommands.isEmpty)
        XCTAssertEqual(model.weatherDetailCoordinator.phase, .omitted)

        let supported = weatherState(features: 3)
        model.states[supported.entityId] = supported
        try await waitUntil { await transport.forecastCommands().count == 1 }
        try await waitUntil { model.weatherDetailCoordinator.hasSubscription }
        XCTAssertEqual(model.weatherDetailCoordinator.selectedType, .daily)

        model.states[supported.entityId] = weatherState(features: 2)
        await Task.yield()
        XCTAssertEqual(model.weatherDetailCoordinator.selectedType, .daily)
        let retainedCommands = await transport.forecastCommands()
        XCTAssertEqual(retainedCommands.count, 1)
        XCTAssertTrue(model.weatherDetailCoordinator.hasSubscription)
        model.closeDetails()
        await model.awaitDashboardOwnerOperationsForTesting()
        await client.disconnect()
    }

    func testDashboardReplacementSynchronouslyClosesWeatherAndNoCardStartsForecastOwner() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 3)
        let original = LovelaceConfig(views: [
            LovelaceView(title: "Home", path: "default_view", cards: [
                LovelaceCard(rawValue: .object([
                    "type": .string("weather-forecast"),
                    "entity": .string(state.entityId),
                    "show_forecast": .bool(false),
                ]), diagnosticPath: "views[0].cards[0]"),
            ]),
        ])
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state],
            initialViews: original.views
        )
        await model.synchronizeHistorySubscriptionsForTesting()
        let cardOnlyCommands = await transport.forecastCommands()
        XCTAssertTrue(cardOnlyCommands.isEmpty, "Mounted forecast-off card has zero detail owner")

        model.openDetails(entityID: state.entityId)
        try await waitUntil { model.weatherDetailCoordinator.hasSubscription }
        let replacement = LovelaceConfig(views: [
            LovelaceView(title: "Other", path: "other", cards: []),
        ])
        let apply = Task { @MainActor in await model.applyLovelaceConfigForTesting(replacement) }
        await Task.yield()
        XCTAssertNil(model.selectedEntityID, "Config invalidation dismisses detail synchronously")
        XCTAssertFalse(model.weatherDetailCoordinator.debugSnapshot().desired)
        await apply.value
        XCTAssertEqual(model.weatherDetailCoordinator.ownerCount, 0)
        let socket = await client.connection.debugSnapshot()
        XCTAssertEqual(socket.subscriptionCount, 0)
        XCTAssertEqual(socket.deliveryOwnerCount, 0)
        await client.disconnect()
    }

    func testViewSwitchDrainsHeldStartupAndActiveSubscription() async throws {
        let state = weatherState(features: 1)
        let views = navigationViews()

        let heldTransport = WeatherDetailTestTransport(acknowledgesForecast: false)
        let heldClient = try await connectedClient(heldTransport)
        let heldModel = DashboardViewModel(
            webSocketClient: heldClient,
            initialStates: [state.entityId: state],
            initialViews: views
        )
        heldModel.openDetails(entityID: state.entityId)
        try await waitUntil { await heldTransport.forecastCommands().count == 1 }
        XCTAssertTrue(heldModel.weatherDetailCoordinator.hasStartup)
        let heldTarget = try XCTUnwrap(heldModel.navigationItems.last?.identity)
        await heldModel.selectViewForTesting(heldTarget)
        XCTAssertEqual(heldModel.weatherDetailCoordinator.ownerCount, 0)
        let heldSocket = await heldClient.connection.debugSnapshot()
        XCTAssertEqual(heldSocket.subscriptionCount, 0)
        XCTAssertEqual(heldSocket.deliveryOwnerCount, 0)
        await heldClient.disconnect()

        let activeTransport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let activeClient = try await connectedClient(activeTransport)
        let activeModel = DashboardViewModel(
            webSocketClient: activeClient,
            initialStates: [state.entityId: state],
            initialViews: views
        )
        activeModel.openDetails(entityID: state.entityId)
        try await waitUntil { activeModel.weatherDetailCoordinator.hasSubscription }
        let activeTarget = try XCTUnwrap(activeModel.navigationItems.last?.identity)
        await activeModel.selectViewForTesting(activeTarget)
        XCTAssertEqual(activeModel.weatherDetailCoordinator.ownerCount, 0)
        let activeSocket = await activeClient.connection.debugSnapshot()
        XCTAssertEqual(activeSocket.subscriptionCount, 0)
        XCTAssertEqual(activeSocket.deliveryOwnerCount, 0)
        await activeClient.disconnect()
    }

    func testConfigReplacementDrainsHeldWeatherStartup() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: false)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 1)
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state],
            initialViews: navigationViews()
        )
        model.openDetails(entityID: state.entityId)
        try await waitUntil { await transport.forecastCommands().count == 1 }
        XCTAssertTrue(model.weatherDetailCoordinator.hasStartup)

        await model.applyLovelaceConfigForTesting(
            LovelaceConfig(views: [LovelaceView(title: "Replacement", path: "replacement", cards: [])])
        )
        XCTAssertEqual(model.weatherDetailCoordinator.ownerCount, 0)
        let socket = await client.connection.debugSnapshot()
        XCTAssertEqual(socket.subscriptionCount, 0)
        XCTAssertEqual(socket.deliveryOwnerCount, 0)
        await client.disconnect()
    }

    func testStopDrainsHeldStartupAndActiveSubscription() async throws {
        let state = weatherState(features: 1)

        let heldTransport = WeatherDetailTestTransport(acknowledgesForecast: false)
        let heldClient = try await connectedClient(heldTransport)
        let heldModel = DashboardViewModel(
            webSocketClient: heldClient,
            initialStates: [state.entityId: state]
        )
        heldModel.openDetails(entityID: state.entityId)
        try await waitUntil { await heldTransport.forecastCommands().count == 1 }
        await heldModel.stop()
        XCTAssertEqual(heldModel.weatherDetailCoordinator.ownerCount, 0)
        let heldSocket = await heldClient.connection.debugSnapshot()
        XCTAssertEqual(heldSocket.subscriptionCount, 0)
        XCTAssertEqual(heldSocket.deliveryOwnerCount, 0)

        let activeTransport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let activeClient = try await connectedClient(activeTransport)
        let activeModel = DashboardViewModel(
            webSocketClient: activeClient,
            initialStates: [state.entityId: state]
        )
        activeModel.openDetails(entityID: state.entityId)
        try await waitUntil { activeModel.weatherDetailCoordinator.hasSubscription }
        await activeModel.stop()
        XCTAssertEqual(activeModel.weatherDetailCoordinator.ownerCount, 0)
        let activeSocket = await activeClient.connection.debugSnapshot()
        XCTAssertEqual(activeSocket.subscriptionCount, 0)
        XCTAssertEqual(activeSocket.deliveryOwnerCount, 0)
    }

    func testPreAcknowledgementReconnectStartsOneFreshAttemptButPostAcknowledgementUsesModule02Owner() async throws {
        let preAckTransport = WeatherDetailTestTransport(acknowledgesForecast: false)
        let preAckClient = try await connectedClient(preAckTransport)
        let state = weatherState(features: 1)
        let preAckModel = DashboardViewModel(
            webSocketClient: preAckClient,
            initialStates: [state.entityId: state]
        )
        preAckModel.openDetails(entityID: state.entityId)
        try await waitUntil { await preAckTransport.forecastCommands().count == 1 }
        try await preAckTransport.failReceive()
        try await waitUntil { (await preAckClient.connection.debugSnapshot()).state == .ready }
        try await waitUntil { !preAckModel.weatherDetailCoordinator.hasStartup }
        XCTAssertEqual(preAckModel.weatherDetailCoordinator.phase, .reconnecting)
        preAckModel.reconcileWeatherDetailReadyForTesting()
        try await waitUntil { await preAckTransport.forecastCommands().count == 2 }
        let retry = await preAckTransport.forecastCommands()[1]
        try await preAckTransport.acknowledge(id: try XCTUnwrap(retry["id"]?.integer))
        try await waitUntil { preAckModel.weatherDetailCoordinator.hasSubscription }
        let preAckSocket = await preAckClient.connection.debugSnapshot()
        XCTAssertEqual(preAckSocket.subscriptionCount, 1)
        preAckModel.closeDetails()
        await preAckModel.awaitDashboardOwnerOperationsForTesting()
        await preAckClient.disconnect()

        let postAckTransport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let postAckClient = try await connectedClient(postAckTransport)
        let postAckModel = DashboardViewModel(
            webSocketClient: postAckClient,
            initialStates: [state.entityId: state]
        )
        postAckModel.openDetails(entityID: state.entityId)
        try await waitUntil { postAckModel.weatherDetailCoordinator.hasSubscription }
        let postAckInitialCommands = await postAckTransport.forecastCommands()
        let first = try XCTUnwrap(postAckInitialCommands.first)
        try await postAckTransport.pushForecast(
            id: try XCTUnwrap(first["id"]?.integer),
            type: .daily,
            temperatures: [20, 21, 22, 23, 24, 25]
        )
        try await waitUntil { postAckModel.weatherDetailCoordinator.modernEvent != nil }
        try await postAckTransport.failReceive()
        try await waitUntil { await postAckTransport.forecastCommands().count == 2 }
        try await waitUntil { (await postAckClient.connection.debugSnapshot()).state == .ready }
        postAckModel.reconcileWeatherDetailReadyForTesting()
        await postAckModel.awaitDashboardOwnerOperationsForTesting()
        let postAckCommands = await postAckTransport.forecastCommands()
        XCTAssertEqual(postAckCommands.count, 2, "View model must not duplicate Module 02 resubscription")
        XCTAssertNotNil(postAckModel.weatherDetailCoordinator.modernEvent, "Accepted content is retained while reconnecting")
        let postAckSocket = await postAckClient.connection.debugSnapshot()
        XCTAssertEqual(postAckSocket.subscriptionCount, 1)
        postAckModel.closeDetails()
        await postAckModel.awaitDashboardOwnerOperationsForTesting()
        await postAckClient.disconnect()
    }

    func testMalformedCurrentEventTerminatesWithoutBusyRetryAndTabChangeRecovers() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 3)
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state]
        )
        model.openDetails(entityID: state.entityId)
        try await waitUntil { model.weatherDetailCoordinator.hasSubscription }
        let initialCommands = await transport.forecastCommands()
        let first = try XCTUnwrap(initialCommands.first)
        let cancellationBoundary = WeatherDetailSuspensionGate()
        let heldTail = Task { await cancellationBoundary.suspend() }
        model.installDashboardOwnerTailForTesting(heldTail)
        await cancellationBoundary.waitUntilEntered()

        try await transport.pushMalformedForecast(id: try XCTUnwrap(first["id"]?.integer))
        try await waitUntil { model.weatherDetailCoordinator.phase == .terminalFailure }
        XCTAssertFalse(model.weatherDetailCoordinator.hasSubscription)
        XCTAssertTrue(model.weatherDetailCoordinator.debugSnapshot().currentAttemptFailed)
        XCTAssertTrue(model.weatherDetailPresentation()?.forecast?.isLoading == true)
        let commandsAfterFailure = await transport.forecastCommands()
        XCTAssertEqual(commandsAfterFailure.count, 1)
        try await waitUntil {
            let snapshot = await client.connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0
        }
        let promptlyRetiredSocket = await client.connection.debugSnapshot()
        XCTAssertEqual(promptlyRetiredSocket.subscriptionCount, 0)
        XCTAssertEqual(promptlyRetiredSocket.wireSubscriptionCount, 0)
        XCTAssertEqual(promptlyRetiredSocket.deliveryOwnerCount, 0)

        try await transport.pushForecast(
            id: try XCTUnwrap(first["id"]?.integer),
            type: .daily,
            temperatures: [90, 91, 92]
        )
        await Task.yield()
        XCTAssertNil(model.weatherDetailCoordinator.modernEvent, "Invalidated callback authority rejects later old events")

        model.reconcileWeatherDetailReadyForTesting()
        model.selectWeatherForecastType(.hourly)
        await Task.yield()
        let commandsWhilePredecessorHeld = await transport.forecastCommands()
        XCTAssertEqual(
            commandsWhilePredecessorHeld.count,
            1,
            "Prompt retirement bypasses the predecessor, but replacement remains serialized behind it"
        )
        let retiredWhilePredecessorHeld = await client.connection.debugSnapshot()
        XCTAssertEqual(retiredWhilePredecessorHeld.subscriptionCount, 0)
        XCTAssertEqual(retiredWhilePredecessorHeld.wireSubscriptionCount, 0)
        XCTAssertEqual(retiredWhilePredecessorHeld.deliveryOwnerCount, 0)

        await cancellationBoundary.release()
        try await waitUntil { await transport.forecastCommands().count == 2 }
        try await waitUntil { model.weatherDetailCoordinator.hasSubscription }
        await model.awaitDashboardOwnerOperationsForTesting()
        XCTAssertFalse(model.weatherDetailCoordinator.debugSnapshot().currentAttemptFailed)
        let recoveredSocket = await client.connection.debugSnapshot()
        XCTAssertEqual(recoveredSocket.subscriptionCount, 1, "Tab recovery installs exactly one new owner")
        XCTAssertEqual(recoveredSocket.wireSubscriptionCount, 1)
        XCTAssertEqual(recoveredSocket.deliveryOwnerCount, 1)
        model.closeDetails()
        await model.awaitDashboardOwnerOperationsForTesting()
        XCTAssertEqual(model.weatherDetailCoordinator.ownerCount, 0)
        let closedSocket = await client.connection.debugSnapshot()
        XCTAssertEqual(closedSocket.subscriptionCount, 0)
        XCTAssertEqual(closedSocket.wireSubscriptionCount, 0)
        XCTAssertEqual(closedSocket.deliveryOwnerCount, 0)
        await client.disconnect()
    }

    func testMalformedEventAtHeldPostInstallBoundaryPromptlyCancelsAtomicOwner() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let client = try await connectedClient(transport)
        let installBoundary = WeatherDetailSuspensionGate()
        let state = weatherState(features: 1)
        let model = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state],
            weatherDetailSubscriptionInstallHook: {
                await installBoundary.suspend()
            }
        )

        model.openDetails(entityID: state.entityId)
        await installBoundary.waitUntilEntered()
        let commands = await transport.forecastCommands()
        let command = try XCTUnwrap(commands.first)
        let wireID = try XCTUnwrap(command["id"]?.integer)
        XCTAssertFalse(model.weatherDetailCoordinator.hasStartup)
        XCTAssertTrue(model.weatherDetailCoordinator.hasSubscription)
        let heldInstallSocket = await client.connection.debugSnapshot()
        XCTAssertEqual(heldInstallSocket.subscriptionCount, 1)
        XCTAssertEqual(heldInstallSocket.wireSubscriptionCount, 1)
        XCTAssertEqual(heldInstallSocket.deliveryOwnerCount, 1)

        try await transport.pushMalformedForecast(id: wireID)
        try await waitUntil { model.weatherDetailCoordinator.phase == .terminalFailure }
        XCTAssertEqual(model.weatherDetailCoordinator.ownerCount, 0, "Termination detaches the atomically installed owner")
        XCTAssertTrue(model.weatherDetailCoordinator.debugSnapshot().currentAttemptFailed)

        try await waitUntil {
            let snapshot = await client.connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0
        }

        try await transport.pushForecast(id: wireID, type: .daily, temperatures: [70, 71, 72])
        await Task.yield()
        XCTAssertNil(model.weatherDetailCoordinator.modernEvent)
        let invalidatedSocket = await client.connection.debugSnapshot()
        XCTAssertEqual(invalidatedSocket.subscriptionCount, 0)
        XCTAssertEqual(invalidatedSocket.wireSubscriptionCount, 0)
        XCTAssertEqual(invalidatedSocket.deliveryOwnerCount, 0)

        await installBoundary.release()
        await model.awaitDashboardOwnerOperationsForTesting()
        let retired = await client.connection.debugSnapshot()
        XCTAssertEqual(retired.subscriptionCount, 0)
        XCTAssertEqual(retired.deliveryOwnerCount, 0)
        XCTAssertEqual(model.weatherDetailCoordinator.ownerCount, 0)
        model.closeDetails()
        await model.awaitDashboardOwnerOperationsForTesting()
        await client.disconnect()
    }

    func testNonWeatherTargetHasNoOwnerAndWeatherModelDeinitDrainsInstalledOwner() async throws {
        let sensor = HAState(entityId: "sensor.temperature", state: "21", attributes: [:])
        let nonWeather = DashboardViewModel(initialStates: [sensor.entityId: sensor])
        nonWeather.openDetails(entityID: sensor.entityId)
        XCTAssertEqual(nonWeather.weatherDetailCoordinator.ownerCount, 0)
        XCTAssertNil(nonWeather.weatherDetailCoordinator.selectedEntityID)

        let transport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 1)
        var model: DashboardViewModel? = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state]
        )
        weak var weakModel = model
        model?.openDetails(entityID: state.entityId)
        try await waitUntil { model?.weatherDetailCoordinator.hasSubscription == true }
        model = nil
        try await waitUntil { weakModel == nil }
        try await waitUntil { (await client.connection.debugSnapshot()).subscriptionCount == 0 }
        let socket = await client.connection.debugSnapshot()
        XCTAssertEqual(socket.deliveryOwnerCount, 0)
        await client.disconnect()
    }

    func testWeatherModelDeinitDrainsHeldStartup() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: false)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 1)
        var model: DashboardViewModel? = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state]
        )
        weak var weakModel = model
        model?.openDetails(entityID: state.entityId)
        try await waitUntil { await transport.forecastCommands().count == 1 }
        XCTAssertTrue(model?.weatherDetailCoordinator.hasStartup == true)
        model = nil
        try await waitUntil { weakModel == nil }
        try await waitUntil {
            let snapshot = await client.connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 && snapshot.deliveryOwnerCount == 0
        }
        await client.disconnect()
    }

    func testMalformedCallbackRetirementDoesNotRetainModelAcrossHeldTail() async throws {
        let transport = WeatherDetailTestTransport(acknowledgesForecast: true)
        let client = try await connectedClient(transport)
        let state = weatherState(features: 1)
        var model: DashboardViewModel? = DashboardViewModel(
            webSocketClient: client,
            initialStates: [state.entityId: state]
        )
        weak var weakModel = model
        model?.openDetails(entityID: state.entityId)
        try await waitUntil { model?.weatherDetailCoordinator.hasSubscription == true }
        let commands = await transport.forecastCommands()
        let command = try XCTUnwrap(commands.first)
        let cancellationBoundary = WeatherDetailSuspensionGate()
        let heldTail = Task { await cancellationBoundary.suspend() }
        model?.installDashboardOwnerTailForTesting(heldTail)
        await cancellationBoundary.waitUntilEntered()

        try await transport.pushMalformedForecast(id: try XCTUnwrap(command["id"]?.integer))
        try await waitUntil { model?.weatherDetailCoordinator.phase == .terminalFailure }
        model = nil
        try await waitUntil { weakModel == nil }
        let heldSocket = await client.connection.debugSnapshot()
        XCTAssertEqual(
            heldSocket.subscriptionCount,
            0,
            "Emergency deinit retirement must not be blocked by the ordinary owner tail"
        )

        await cancellationBoundary.release()
        try await waitUntil {
            let snapshot = await client.connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 && snapshot.deliveryOwnerCount == 0
        }
        await client.disconnect()
    }

    private func connectedClient(_ transport: WeatherDetailTestTransport) async throws -> HomeAssistantWebSocketClient {
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "weather-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        try await client.connect()
        return client
    }

    private func weatherState(features: Int) -> HAState {
        HAState(
            entityId: "weather.home",
            state: "partlycloudy",
            attributes: [
                "supported_features": .int(features),
                "temperature": .double(22.3),
                "temperature_unit": .string("°C"),
                "humidity": .int(78),
            ],
            lastChanged: "2026-09-09T00:00:00Z",
            lastUpdated: "2026-09-09T00:01:00Z"
        )
    }

    private func navigationViews() -> [LovelaceView] {
        [
            LovelaceView(title: "Home", path: "home", cards: []),
            LovelaceView(title: "Other", path: "other", cards: []),
        ]
    }

    private func waitUntil(
        iterations: Int = 50_000,
        _ predicate: @escaping () async -> Bool
    ) async throws {
        for _ in 0..<iterations {
            if await predicate() { return }
            await Task.yield()
        }
        throw WeatherDetailTestError.timeout
    }

    private func waitUntilLive(
        iterations: Int = 750,
        _ predicate: @escaping () -> Bool
    ) async throws {
        for _ in 0..<iterations {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw WeatherDetailTestError.timeout
    }
}

private enum WeatherDetailTestError: Error { case timeout }

private actor WeatherDetailSuspensionGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        entered = true
        let currentEntryWaiters = entryWaiters
        entryWaiters.removeAll()
        currentEntryWaiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let currentReleaseWaiters = releaseWaiters
        releaseWaiters.removeAll()
        currentReleaseWaiters.forEach { $0.resume() }
    }
}

private actor WeatherDetailTestTransport: HomeAssistantWebSocketTransport {
    private var inbound: [HAWebSocketFrame] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var sent: [[String: JSONValue]] = []
    private var connected = false
    private let acknowledgesForecast: Bool

    init(acknowledgesForecast: Bool) {
        self.acknowledgesForecast = acknowledgesForecast
    }

    func connect() async throws {
        connected = true
        try deliver(["type": .string("auth_required")])
    }

    func send(_ frame: HAWebSocketFrame) async throws {
        guard connected else { throw HomeAssistantWebSocketError.disconnected }
        let object = try decode(frame)
        sent.append(object)
        switch object["type"] {
        case .string("auth"):
            try deliver(["type": .string("auth_ok"), "ha_version": .string("2026.5.4")])
        case .string("weather/subscribe_forecast") where acknowledgesForecast:
            if let id = object["id"]?.integer { try acknowledge(id: id) }
        case .string("unsubscribe_events"):
            if let id = object["id"]?.integer { try acknowledge(id: id) }
        default:
            break
        }
    }

    func receive() async throws -> HAWebSocketFrame {
        guard connected else { throw HomeAssistantWebSocketError.disconnected }
        if !inbound.isEmpty { return inbound.removeFirst() }
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }

    func disconnect() async {
        connected = false
        let current = receiver
        receiver = nil
        current?.resume(throwing: HomeAssistantWebSocketError.disconnected)
    }

    func failReceive() throws {
        guard let receiver = receiver else { throw WeatherDetailTestError.timeout }
        self.receiver = nil
        receiver.resume(throwing: HomeAssistantWebSocketError.disconnected)
    }

    func forecastCommands() -> [[String: JSONValue]] {
        sent.filter { $0["type"] == .string("weather/subscribe_forecast") }
    }

    func acknowledge(id: Int) throws {
        try deliver([
            "id": .int(id),
            "type": .string("result"),
            "success": .bool(true),
            "result": .null,
        ])
    }

    func pushForecast(id: Int, type: HAWeatherForecastType, temperatures: [Double]) throws {
        let formatter = ISO8601DateFormatter()
        let base = formatter.date(from: "2026-09-09T00:00:00Z")!
        let interval: TimeInterval = type == .hourly ? 3_600 : (type == .twiceDaily ? 43_200 : 86_400)
        try deliver([
            "id": .int(id),
            "type": .string("event"),
            "event": .object([
                "type": .string(type.rawValue),
                "forecast": .array(temperatures.enumerated().map { index, temperature in
                    .object([
                        "datetime": .string(formatter.string(from: base.addingTimeInterval(Double(index) * interval))),
                        "temperature": .double(temperature),
                        "condition": .string("partlycloudy"),
                    ])
                }),
            ]),
        ])
    }

    func pushMalformedForecast(id: Int) throws {
        try deliver([
            "id": .int(id),
            "type": .string("event"),
            "event": .object([
                "type": .string("daily"),
                "forecast": .array([
                    .object([
                        "datetime": .string("2026-09-09T00:00:00Z"),
                        "temperature": .bool(true),
                    ]),
                ]),
            ]),
        ])
    }

    private func deliver(_ object: [String: JSONValue]) throws {
        let data = try JSONEncoder().encode(JSONValue.object(object))
        let frame = HAWebSocketFrame.string(String(decoding: data, as: UTF8.self))
        if let receiver = receiver {
            self.receiver = nil
            receiver.resume(returning: frame)
        } else {
            inbound.append(frame)
        }
    }

    private func decode(_ frame: HAWebSocketFrame) throws -> [String: JSONValue] {
        let data: Data
        switch frame {
        case let .string(value): data = Data(value.utf8)
        case let .data(value): data = value
        }
        guard case let .object(object) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        return object
    }
}

private extension JSONValue {
    var integer: Int? {
        if case let .int(value) = self { return value }
        return nil
    }
}
