import Foundation
import XCTest
@testable import NativeHACore

final class HomeAssistantHistoryLiveSmokeTests: XCTestCase {
    func testReadOnlyOneHourTwelveHourTwentyFourHourAndReconnectSmoke() async throws {
        guard ProcessInfo.processInfo.environment["NATIVEHA_RUN_LIVE_HISTORY_SMOKE"] == "1" else {
            throw XCTSkip("Set NATIVEHA_RUN_LIVE_HISTORY_SMOKE=1 for the authorized read-only live smoke")
        }

        let token = try String(
            contentsOfFile: "/Users/jin/Documents/Computer/ha_apikey.txt",
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLs = [
            "http://joyj.me:8123",
            "http://172.20.200.123:8123",
            "http://192.168.71.18:8123",
        ].compactMap(URL.init(string:))
        let (configuration, currentStates) = try await firstLiveConfiguration(
            baseURLs: baseURLs,
            token: token
        )
        let client = HomeAssistantWebSocketClient(
            configuration: configuration,
            commandTimeout: 10,
            receivePolicy: HomeAssistantWebSocketReceivePolicy(
                maximumMessageBytes: 32 * 1_024 * 1_024
            ),
            subscriptionDeliveryCapacity: 256,
            maximumConcurrentCallbackTasks: 4
        )
        try await client.connect()
        defer { Task { await client.disconnect() } }

        let registryDisplay = try await client.fetchEntityRegistryDisplay()
        let frontendLocale = try await client.fetchFrontendLocalePreferences()
        let currentUser = try await client.fetchCurrentUser()
        XCTAssertFalse(registryDisplay.entities.isEmpty)
        XCTAssertFalse(frontendLocale?.language.isEmpty ?? true)
        XCTAssertFalse(currentUser.id.isEmpty)

        let lovelace = try await client.fetchLovelaceConfig()
        guard case let .object(lovelaceRoot) = lovelace.rawValue,
              case let .array(rawViews)? = lovelaceRoot["views"]
        else {
            return XCTFail("Live Lovelace raw root/views were not preserved")
        }
        XCTAssertEqual(rawViews.count, lovelace.views.count)
        XCTAssertFalse(lovelace.views.contains { $0.diagnostic != nil })
        let liveResolved = LovelaceResolvedDashboard(source: lovelace)
        XCTAssertEqual(liveResolved.views.count, lovelace.views.count)
        XCTAssertEqual(
            liveResolved.views.flatMap(\.cards).count,
            lovelace.views.flatMap(\.cards).count,
            "Resolving must not drop live top-level cards"
        )
        let rawShape = rawLovelaceShape(lovelace.rawValue)
        let parsedShape = parsedLovelaceShape(lovelace)
        XCTAssertEqual(parsedShape.cards, rawShape.cards, "Typed decode must retain every live nested card")
        XCTAssertEqual(parsedShape.rows, rawShape.rows, "Typed decode must retain every live entity row")
        let requested = representativeHistoryEntityIDs(
            config: lovelace,
            currentStates: currentStates
        )
        XCTAssertFalse(requested.isEmpty)
        let stateMap = Dictionary(uniqueKeysWithValues: currentStates.map { ($0.entityId, $0) })
        let co2VOCEntities = try XCTUnwrap(
            historyEntityIDs(in: lovelace, cardTitle: "CO2/VOC"),
            "The live dashboard must retain the exact card that reproduced the oversized replay"
        )
        XCTAssertFalse(co2VOCEntities.isEmpty)

        let initialEntityLog = LiveEntityPayloadLog()
        let initialEntityOwner = try await client.subscribeEntities { payload in
            await initialEntityLog.append(payload)
        }
        try await liveWait { await initialEntityLog.count > 0 }
        let initialEntityValue = await initialEntityLog.first
        let initialEntityPayload = try XCTUnwrap(initialEntityValue)
        XCTAssertFalse(initialEntityPayload.additions?.isEmpty ?? true)
        await initialEntityOwner.cancel()
        try await requireZeroHistoryOwnership(client.connection)

        let oneHour = LiveHistoryLog()
        let oneHourStart = ProcessInfo.processInfo.systemUptime
        let oneHourOwner = try await client.subscribeHistoryStatesTimeWindow(
            entityIDs: requested,
            hoursToShow: 1,
            currentStates: stateMap,
            onStatus: { await oneHour.append(status: $0) },
            onHistory: { await oneHour.append(history: $0) }
        )
        try await liveWait { await oneHour.callbackCount > 0 }
        let oneHourSnapshot = await oneHour.snapshot()
        let oneHourElapsed = ProcessInfo.processInfo.systemUptime - oneHourStart
        XCTAssertTrue(Set(oneHourSnapshot.history.keys).isSubset(of: Set(requested)))
        await oneHourOwner.cancel()
        try await requireZeroHistoryOwnership(client.connection)

        let reconnect = LiveHistoryLog()
        let reconnectOwner = try await client.subscribeHistoryStatesTimeWindow(
            entityIDs: requested,
            hoursToShow: 1,
            currentStates: stateMap,
            onStatus: { await reconnect.append(status: $0) },
            onHistory: { await reconnect.append(history: $0) }
        )
        try await liveWait { await reconnect.callbackCount > 0 }
        let callbacksBeforeReconnect = await reconnect.callbackCount
        await client.connection.reconnect()
        try await liveWait(timeout: 30) {
            let loadingCount = await reconnect.loadingCount
            let callbackCount = await reconnect.callbackCount
            return loadingCount >= 2 && callbackCount > callbacksBeforeReconnect
        }
        let reconnectSnapshot = await reconnect.snapshot()
        XCTAssertGreaterThanOrEqual(reconnectSnapshot.loadingCount, 2)
        XCTAssertTrue(Set(reconnectSnapshot.history.keys).isSubset(of: Set(requested)))
        let reconnectEntityLog = LiveEntityPayloadLog()
        let reconnectEntityOwner = try await client.subscribeEntities { payload in
            await reconnectEntityLog.append(payload)
        }
        try await liveWait { await reconnectEntityLog.count > 0 }
        let reconnectEntityValue = await reconnectEntityLog.first
        let reconnectEntityPayload = try XCTUnwrap(reconnectEntityValue)
        XCTAssertFalse(reconnectEntityPayload.additions?.isEmpty ?? true)
        await reconnectEntityOwner.cancel()
        await reconnectOwner.cancel()
        try await requireZeroHistoryOwnership(client.connection)

        let connectionLog = LiveConnectionLog()
        let connectionStates = await client.connection.statusUpdates()
        let connectionLogTask = Task {
            for await state in connectionStates {
                await connectionLog.append(state)
            }
        }
        defer { connectionLogTask.cancel() }

        var exactWindowSnapshots: [(hours: Int, snapshot: LiveHistorySnapshot, elapsed: TimeInterval)] = []
        for hours in [1, 12, 1] {
            let log = LiveHistoryLog()
            let start = ProcessInfo.processInfo.systemUptime
            let owner = try await client.subscribeHistoryStatesTimeWindow(
                entityIDs: co2VOCEntities,
                hoursToShow: hours,
                currentStates: stateMap,
                onStatus: { await log.append(status: $0) },
                onHistory: { await log.append(history: $0) }
            )
            try await liveWait(timeout: hours == 12 ? 60 : 20) { await log.callbackCount > 0 }
            let snapshot = await log.snapshot()
            exactWindowSnapshots.append((
                hours: hours,
                snapshot: snapshot,
                elapsed: ProcessInfo.processInfo.systemUptime - start
            ))
            XCTAssertGreaterThan(snapshot.pointCount, 0, "CO2/VOC \(hours)h replay was empty")
            XCTAssertEqual(snapshot.errorCount, 0, "CO2/VOC \(hours)h owner reported an error")
            await owner.cancel()
            try await requireZeroHistoryOwnership(client.connection)
        }
        let reconnectingCount = await connectionLog.reconnectingCount
        let nonReadyCount = await connectionLog.nonReadyCount
        XCTAssertEqual(reconnectingCount, 0)
        XCTAssertEqual(nonReadyCount, 0)

        let twentyFourHour = LiveHistoryLog()
        let twentyFourStart = ProcessInfo.processInfo.systemUptime
        let twentyFourOwner = try await client.subscribeHistoryStatesTimeWindow(
            entityIDs: requested,
            hoursToShow: 24,
            currentStates: stateMap,
            onStatus: { await twentyFourHour.append(status: $0) },
            onHistory: { await twentyFourHour.append(history: $0) }
        )
        try await liveWait(timeout: 30) { await twentyFourHour.callbackCount > 0 }
        let twentyFourSnapshot = await twentyFourHour.snapshot()
        let twentyFourElapsed = ProcessInfo.processInfo.systemUptime - twentyFourStart
        XCTAssertTrue(Set(twentyFourSnapshot.history.keys).isSubset(of: Set(requested)))
        await twentyFourOwner.cancel()
        try await requireZeroHistoryOwnership(client.connection)

        print("LIVE_HISTORY entities=\(requested.joined(separator: ","))")
        print(
            "LIVE_LOVELACE views=\(lovelace.views.count) " +
            "top_cards=\(lovelace.views.flatMap(\.cards).count) " +
            "cards=\(parsedShape.cards) rows=\(parsedShape.rows) " +
            "resolved_top=\(liveResolved.views.flatMap(\.cards).count)"
        )
        print(
            "LIVE_FORMATTING registry_entities=\(registryDisplay.entities.count) " +
            "precisions=\(registryDisplay.entities.compactMap(\.displayPrecision).count) " +
            "language=\(frontendLocale?.language ?? "system")"
        )
        print("LIVE_CURRENT_USER id_present=\(!currentUser.id.isEmpty)")
        print(
            "LIVE_ENTITIES initial=\(initialEntityPayload.additions?.count ?? 0) " +
            "reconnect=\(reconnectEntityPayload.additions?.count ?? 0) resubscribe=false"
        )
        print("LIVE_HISTORY no_attributes=\(HAHistoryAttributePolicy.noAttributes(entityIDs: requested, currentStates: stateMap))")
        print("LIVE_HISTORY 1h callbacks=\(oneHourSnapshot.callbackCount) points=\(oneHourSnapshot.pointCount) attributes=\(oneHourSnapshot.attributePointCount) fractional=\(oneHourSnapshot.fractionalTimestampCount) elapsed=\(String(format: "%.3f", oneHourElapsed))s")
        print("LIVE_HISTORY reconnect callbacks=\(reconnectSnapshot.callbackCount) loading=\(reconnectSnapshot.loadingCount) points=\(reconnectSnapshot.pointCount)")
        for result in exactWindowSnapshots {
            print("LIVE_HISTORY CO2_VOC \(result.hours)h callbacks=\(result.snapshot.callbackCount) points=\(result.snapshot.pointCount) elapsed=\(String(format: "%.3f", result.elapsed))s")
        }
        print("LIVE_HISTORY 24h callbacks=\(twentyFourSnapshot.callbackCount) points=\(twentyFourSnapshot.pointCount) attributes=\(twentyFourSnapshot.attributePointCount) fractional=\(twentyFourSnapshot.fractionalTimestampCount) elapsed=\(String(format: "%.3f", twentyFourElapsed))s")

        await client.disconnect()
        let final = await client.connection.debugSnapshot()
        XCTAssertEqual(final.pendingCommandCount, 0)
        XCTAssertEqual(final.subscriptionCount, 0)
        XCTAssertEqual(final.wireSubscriptionCount, 0)
        XCTAssertEqual(final.receiveLoopCount, 0)
        XCTAssertEqual(final.deliveryOwnerCount, 0)
        XCTAssertEqual(final.bufferedDeliveryCount, 0)
    }

    private func firstLiveConfiguration(
        baseURLs: [URL],
        token: String
    ) async throws -> (HomeAssistantConfiguration, [HAState]) {
        var lastError: Error?
        for baseURL in baseURLs {
            let configuration = HomeAssistantConfiguration(baseURL: baseURL, accessToken: token, timeout: 15)
            let rest = HomeAssistantRESTClient(configuration: configuration)
            do {
                _ = try await rest.fetchConfig()
                return (configuration, try await rest.fetchStates())
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func parsedLovelaceShape(_ config: LovelaceConfig) -> (cards: Int, rows: Int) {
        func collect(_ cards: [LovelaceCard]) -> (cards: Int, rows: Int) {
            cards.reduce(into: (cards: 0, rows: 0)) { result, card in
                result.cards += 1
                result.rows += card.entities?.count ?? 0
                let nested = collect(card.cards ?? [])
                result.cards += nested.cards
                result.rows += nested.rows
            }
        }
        return collect(config.views.flatMap(\.cards))
    }

    private func rawLovelaceShape(_ raw: JSONValue) -> (cards: Int, rows: Int) {
        func collectCards(_ value: JSONValue?) -> (cards: Int, rows: Int) {
            guard case let .array(cards)? = value else { return (0, 0) }
            return cards.reduce(into: (cards: 0, rows: 0)) { result, card in
                result.cards += 1
                guard case let .object(object) = card else { return }
                if case let .array(rows)? = object["entities"] {
                    result.rows += rows.count
                }
                let nested = collectCards(object["cards"])
                result.cards += nested.cards
                result.rows += nested.rows
            }
        }
        guard case let .object(root) = raw, case let .array(views)? = root["views"] else {
            return (0, 0)
        }
        return views.reduce(into: (cards: 0, rows: 0)) { result, view in
            guard case let .object(object) = view else { return }
            let shape = collectCards(object["cards"])
            result.cards += shape.cards
            result.rows += shape.rows
        }
    }

    private func representativeHistoryEntityIDs(
        config: LovelaceConfig,
        currentStates: [HAState]
    ) -> [String] {
        var historyEntities: [String] = []
        func collect(_ cards: [LovelaceCard]) {
            for card in cards {
                if card.type == "history-graph" {
                    historyEntities.append(contentsOf: card.entities?.compactMap(\.entity) ?? [])
                }
                collect(card.cards ?? [])
            }
        }
        for view in config.views where view.path == "default_view" || historyEntities.isEmpty {
            collect(view.cards)
            if !historyEntities.isEmpty { break }
        }
        if historyEntities.isEmpty {
            historyEntities = currentStates
                .map(\.entityId)
                .filter { $0.hasPrefix("sensor.") || $0.hasPrefix("binary_sensor.") }
        }
        var seen = Set<String>()
        return historyEntities.filter { seen.insert($0).inserted }.prefix(3).map { $0 }
    }

    private func historyEntityIDs(
        in config: LovelaceConfig,
        cardTitle: String
    ) -> [String]? {
        func find(in cards: [LovelaceCard]) -> [String]? {
            for card in cards {
                if card.type == "history-graph", card.title == cardTitle {
                    return card.entities?.compactMap(\.entity) ?? []
                }
                if let nested = card.cards, let result = find(in: nested) {
                    return result
                }
            }
            return nil
        }

        for view in config.views {
            if let result = find(in: view.cards) {
                return result
            }
        }
        return nil
    }

    private func requireZeroHistoryOwnership(
        _ connection: HomeAssistantWebSocketConnection
    ) async throws {
        try await liveWait {
            let snapshot = await connection.debugSnapshot()
            return snapshot.pendingCommandCount == 0 &&
                snapshot.subscriptionCount == 0 &&
                snapshot.wireSubscriptionCount == 0 &&
                snapshot.deliveryOwnerCount == 0 &&
                snapshot.bufferedDeliveryCount == 0 &&
                snapshot.activeDeliveryTaskCount == 0
        }
    }
}

private actor LiveEntityPayloadLog {
    private var payloads: [HAEntitySubscriptionPayload] = []
    var count: Int { payloads.count }
    var first: HAEntitySubscriptionPayload? { payloads.first }
    func append(_ payload: HAEntitySubscriptionPayload) { payloads.append(payload) }
}

private actor LiveHistoryLog {
    private var histories: [[String: [HACompactHistoryState]]] = []
    private var statuses: [HAHistoryStreamOwnerStatus] = []

    var callbackCount: Int { histories.count }
    var loadingCount: Int { statuses.filter { $0 == .loading }.count }
    var errorCount: Int {
        statuses.filter {
            if case .error = $0 { return true }
            return false
        }.count
    }

    func append(history: [String: [HACompactHistoryState]]) {
        histories.append(history)
    }

    func append(status: HAHistoryStreamOwnerStatus) {
        statuses.append(status)
    }

    func snapshot() -> LiveHistorySnapshot {
        let history = histories.last ?? [:]
        let points = history.values.flatMap { $0 }
        return LiveHistorySnapshot(
            history: history,
            callbackCount: histories.count,
            loadingCount: loadingCount,
            errorCount: errorCount,
            pointCount: points.count,
            attributePointCount: points.filter { !$0.attributes.isEmpty }.count,
            fractionalTimestampCount: points.filter {
                $0.lastUpdatedSeconds.rounded(.towardZero) != $0.lastUpdatedSeconds
            }.count
        )
    }
}

private struct LiveHistorySnapshot {
    let history: [String: [HACompactHistoryState]]
    let callbackCount: Int
    let loadingCount: Int
    let errorCount: Int
    let pointCount: Int
    let attributePointCount: Int
    let fractionalTimestampCount: Int
}

private actor LiveConnectionLog {
    private var states: [HAWebSocketConnectionState] = []

    var reconnectingCount: Int {
        states.filter {
            if case .reconnecting = $0 { return true }
            return false
        }.count
    }

    var nonReadyCount: Int {
        states.filter { $0 != .ready }.count
    }

    func append(_ state: HAWebSocketConnectionState) {
        states.append(state)
    }
}

private enum LiveHistoryWaitError: Error { case timedOut }

private func liveWait(
    timeout: TimeInterval = 20,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw LiveHistoryWaitError.timedOut
}
