import Foundation
import XCTest
@testable import NativeHACore

final class HomeAssistantHistoryLiveSmokeTests: XCTestCase {
    func testReadOnlyOneHourTwentyFourHourAndReconnectSmoke() async throws {
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
            commandTimeout: 15,
            subscriptionDeliveryCapacity: 256,
            maximumConcurrentCallbackTasks: 4
        )
        try await client.connect()
        defer { Task { await client.disconnect() } }

        let lovelace = try await client.fetchLovelaceConfig()
        let requested = representativeHistoryEntityIDs(
            config: lovelace,
            currentStates: currentStates
        )
        XCTAssertFalse(requested.isEmpty)
        let stateMap = Dictionary(uniqueKeysWithValues: currentStates.map { ($0.entityId, $0) })

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
        await reconnectOwner.cancel()
        try await requireZeroHistoryOwnership(client.connection)

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
        print("LIVE_HISTORY no_attributes=\(HAHistoryAttributePolicy.noAttributes(entityIDs: requested, currentStates: stateMap))")
        print("LIVE_HISTORY 1h callbacks=\(oneHourSnapshot.callbackCount) points=\(oneHourSnapshot.pointCount) attributes=\(oneHourSnapshot.attributePointCount) fractional=\(oneHourSnapshot.fractionalTimestampCount) elapsed=\(String(format: "%.3f", oneHourElapsed))s")
        print("LIVE_HISTORY reconnect callbacks=\(reconnectSnapshot.callbackCount) loading=\(reconnectSnapshot.loadingCount) points=\(reconnectSnapshot.pointCount)")
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

private actor LiveHistoryLog {
    private var histories: [[String: [HACompactHistoryState]]] = []
    private var statuses: [HAHistoryStreamOwnerStatus] = []

    var callbackCount: Int { histories.count }
    var loadingCount: Int { statuses.filter { $0 == .loading }.count }

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
    let pointCount: Int
    let attributePointCount: Int
    let fractionalTimestampCount: Int
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
