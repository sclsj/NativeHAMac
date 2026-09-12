import Foundation
import XCTest
import Combine
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class MarkdownLifecycleTests: XCTestCase {
    func testExactWireMarkerFreeDuplicatesAndEventIsolation() async throws {
        let transport = MarkdownTestTransport()
        let client = try await connected(transport)
        let source = try markdownCard(content: "hello", additions: ["entity_id": .array([.string("sensor.a")]), "unknown": .int(4)])
        let views = [LovelaceView(title: "Home", path: "home", cards: [source, source])]
        let model = DashboardViewModel(webSocketClient: client, initialViews: views, currentUserName: "Actual Name")
        await model.synchronizeHistorySubscriptionsForTesting()
        try await until { await transport.commands().count == 2 }
        let commands = await transport.commands()
        XCTAssertEqual(commands[0]["strict"], .bool(true)); XCTAssertEqual(commands[0]["report_errors"], .bool(false))
        XCTAssertEqual(commands[0]["variables"], .object(["config": source.rawValue, "user": .string("Actual Name")]))
        XCTAssertEqual(commands[0]["entity_ids"], .array([.string("sensor.a")]))
        let cards = model.activeCards
        let first = try XCTUnwrap(model.markdownState(for: cards[0]))
        let second = try XCTUnwrap(model.markdownState(for: cards[1]))
        XCTAssertFalse(first === second)
        // Dictionary startup order is intentionally unspecified.
        for command in commands { try await transport.event(id: try id(command), result: "**settled**") }
        try await until { first.document.source == "**settled**" && second.document.source == "**settled**" }
        let firstID = try id(commands[0])
        try await transport.streamError(id: firstID, message: "Warning", level: "WARNING")
        try await transport.streamError(id: firstID, message: "Error", level: "ERROR")
        try await transport.streamError(id: firstID, message: "Later warning", level: "WARNING")
        try await transport.event(id: firstID, result: "recovered")
        try await until { first.document.source == "recovered" || second.document.source == "recovered" }
        let updated = first.document.source == "recovered" ? first : second
        XCTAssertEqual(updated.alert, "Error"); XCTAssertEqual(updated.alertLevel, .error)
        XCTAssertEqual((updated === first ? second : first).document.source, "**settled**")
        await model.stop()
        XCTAssertEqual(model.markdownCoordinator.ownerCount, 0)
        let snapshot = await client.connection.debugSnapshot()
        XCTAssertEqual(snapshot.subscriptionCount, 0)
    }

    func testViewReturnRetainsResultButConfigReplacementCreatesNewState() async throws {
        let transport = MarkdownTestTransport(); let client = try await connected(transport)
        let card = try markdownCard(content: "hello")
        let views = [LovelaceView(title: "Home", path: "home", cards: [card]), LovelaceView(title: "Other", path: "other", cards: [])]
        let model = DashboardViewModel(webSocketClient: client, initialViews: views, currentUserName: "Name")
        await model.synchronizeHistorySubscriptionsForTesting()
        try await until { await transport.commands().count == 1 }
        let captured = await transport.commands()
        let command = try XCTUnwrap(captured.first)
        try await transport.event(id: try id(command), result: "retained")
        let state = try XCTUnwrap(model.markdownState(for: model.activeCards[0]))
        try await until { state.document.source == "retained" }
        await model.navigateToViewForTesting(path: "other")
        XCTAssertEqual(model.markdownCoordinator.ownerCount, 0)
        await model.navigateToViewForTesting(path: "home")
        XCTAssertTrue(model.markdownState(for: model.activeCards[0]) === state)
        XCTAssertEqual(state.document.source, "retained")
        try await until { await transport.commands().count == 2 }
        await model.setGraphHoursForTesting(3)
        let count1 = await transport.commands().count
        XCTAssertEqual(count1, 2)
        let replacement = LovelaceConfig(views: [views[0], LovelaceView(title: "Changed elsewhere", path: "other", cards: [])])
        await model.applyLovelaceConfigForTesting(replacement)
        XCTAssertFalse(model.markdownState(for: model.activeCards[0]) === state)
        try await until { await transport.commands().count == 3 }
        await model.stop()
    }

    func testEmptyWrapperCancelsAndCachedViewReturnStaysHidden() async throws {
        let transport = MarkdownTestTransport(); let client = try await connected(transport)
        let card = try markdownCard(content: "hello", additions: ["show_empty": .bool(false)])
        let views = [LovelaceView(title: "Home", path: "home", cards: [card]), LovelaceView(title: "Other", path: "other", cards: [])]
        let model = DashboardViewModel(webSocketClient: client, initialViews: views, currentUserName: "Name")
        await model.synchronizeHistorySubscriptionsForTesting()
        try await until { await transport.commands().count == 1 }
        let captured = await transport.commands()
        let command = try XCTUnwrap(captured.first)
        try await transport.event(id: try id(command), result: "")
        try await until { model.markdownCoordinator.ownerCount == 0 && model.dashboardColumns.flatMap { $0 }.isEmpty }
        await model.navigateToViewForTesting(path: "other")
        await model.navigateToViewForTesting(path: "home")
        XCTAssertTrue(model.dashboardColumns.flatMap { $0 }.isEmpty)
        let count2 = await transport.commands().count
        XCTAssertEqual(count2, 1)
        await model.stop()
    }

    func testHeldAcknowledgementRemovalAndDeinitCancelOwnership() async throws {
        let transport = MarkdownTestTransport(acknowledges: false); let client = try await connected(transport)
        let card = try markdownCard(content: "held")
        var model: DashboardViewModel? = DashboardViewModel(webSocketClient: client,
            initialViews: [LovelaceView(title: "Home", path: "home", cards: [card])], currentUserName: "Name")
        await model?.synchronizeHistorySubscriptionsForTesting()
        try await until { await transport.commands().count == 1 }
        weak var weakModel = model
        model = nil
        try await until { weakModel == nil }
        try await until { let state = await client.connection.debugSnapshot(); return state.subscriptionCount == 0 && state.deliveryOwnerCount == 0 }
        await client.disconnect()
    }

    func testMissingNameDoesNotSubscribeAndRejectionFallsBack() async throws {
        let transport = MarkdownTestTransport(rejects: true); let client = try await connected(transport)
        let card = try markdownCard(content: "source **fallback**")
        let dashboard = LovelacePresentationDashboard(resolved: LovelaceResolvedDashboard(source: LovelaceConfig(views: [LovelaceView(title: "Home", cards: [card])])))
        let coordinator = DashboardMarkdownCoordinator(authority: DashboardLifetimeAuthority())
        let selected = dashboard.views[0].id
        _ = coordinator.reconcile(dashboard: dashboard, selected: selected)
        coordinator.activate(using: client, userName: nil)
        XCTAssertEqual(coordinator.state(for: dashboard.views[0].cards[0], view: selected)?.phase, .metadataUnavailable)
        let count3 = await transport.commands().count
        XCTAssertEqual(count3, 0)
        await coordinator.close().finish()
        _ = coordinator.reconcile(dashboard: dashboard, selected: selected)
        coordinator.activate(using: client, userName: "")
        try await until { coordinator.state(for: dashboard.views[0].cards[0], view: selected)?.document.source == card.content }
        XCTAssertNil(coordinator.state(for: dashboard.views[0].cards[0], view: selected)?.alert)
        let count4 = await transport.commands().count
        XCTAssertEqual(count4, 1)
        await coordinator.close().finish(); await client.disconnect()
    }

    func testUnsupportedContainersAndExtraPanelCardsHaveNoDemand() throws {
        let md = try markdownCard(content: "hello")
        let source = LovelaceConfig(views: [LovelaceView(title: "Home", cards: [LovelaceCard(type: "horizontal-stack", cards: [md]), LovelaceCard(type: "vertical-stack", cards: [md])])])
        let dashboard = LovelacePresentationDashboard(resolved: LovelaceResolvedDashboard(source: source))
        XCTAssertEqual(DashboardMarkdownCoordinator.renderedMarkdownCards(dashboard.views[0]).count, 1)
        let panel = try LovelaceConfig(rawValue: .object(["views": .array([.object(["panel": .bool(true), "cards": .array([.object(["type": .string("entities"), "entities": .array([.string("sensor.a")])]), md.rawValue])])])]))
        let panelDashboard = LovelacePresentationDashboard(resolved: LovelaceResolvedDashboard(source: panel))
        XCTAssertTrue(DashboardMarkdownCoordinator.renderedMarkdownCards(panelDashboard.views[0]).isEmpty)
    }

    func testCacheIndependentExpiryAndRetainedViewBeyondOneSecond() async throws {
        let transport = MarkdownTestTransport(); let client = try await connected(transport)
        var instant = Date(timeIntervalSince1970: 100)
        let coordinator = DashboardMarkdownCoordinator(authority: DashboardLifetimeAuthority(), now: { instant })
        coordinator.retire = { ownership in Task { await ownership.finish() } }
        let card = try markdownCard(content: "cache")
        func dashboard(_ title: String) -> LovelacePresentationDashboard {
            LovelacePresentationDashboard(resolved: LovelaceResolvedDashboard(source: LovelaceConfig(views: [LovelaceView(title: title, path: "home", cards: [card])])))
        }
        let first = dashboard("First")
        _ = coordinator.reconcile(dashboard: first, selected: first.views[0].id)
        coordinator.activate(using: client, userName: "Name")
        try await until { await transport.commands().count == 1 }
        let commands = await transport.commands()
        try await transport.event(id: try id(commands[0]), result: "cached A")
        let state = try XCTUnwrap(coordinator.state(for: first.views[0].cards[0], view: first.views[0].id))
        try await until { state.result?.result == "cached A" }
        await coordinator.reconcile(dashboard: first, selected: nil).finish()
        XCTAssertEqual(coordinator.cachedResultCount, 1)
        instant = Date(timeIntervalSince1970: 100.5)
        _ = coordinator.reconcile(dashboard: first, selected: first.views[0].id)
        coordinator.activate(using: client, userName: "Name")
        try await until { await transport.commands().count == 2 }
        let secondCommands = await transport.commands()
        try await transport.event(id: try id(secondCommands[1]), result: "cached B")
        try await until { state.result?.result == "cached B" }
        await coordinator.reconcile(dashboard: first, selected: nil).finish()
        instant = Date(timeIntervalSince1970: 100.75)
        let second = dashboard("Second")
        await coordinator.reconcile(dashboard: second, selected: second.views[0].id).finish()
        XCTAssertEqual(coordinator.state(for: second.views[0].cards[0], view: second.views[0].id)?.result?.result, "cached B")
        instant = Date(timeIntervalSince1970: 101.1)
        let third = dashboard("Third")
        await coordinator.reconcile(dashboard: third, selected: third.views[0].id).finish()
        XCTAssertNil(coordinator.state(for: third.views[0].cards[0], view: third.views[0].id)?.result)
        // Accepted result on an existing wrapper is independent of short cache TTL.
        coordinator.activate(using: client, userName: "Name")
        try await until { await transport.commands().count == 3 }
        let thirdCommands = await transport.commands()
        try await transport.event(id: try id(thirdCommands[2]), result: "retained beyond TTL")
        let retained = try XCTUnwrap(coordinator.state(for: third.views[0].cards[0], view: third.views[0].id))
        try await until { retained.result != nil }
        await coordinator.reconcile(dashboard: third, selected: nil).finish()
        instant = Date(timeIntervalSince1970: 120)
        _ = coordinator.reconcile(dashboard: third, selected: third.views[0].id)
        coordinator.activate(using: client, userName: "Name")
        try await until { retained.document.source == "retained beyond TTL" }
        XCTAssertTrue(coordinator.state(for: third.views[0].cards[0], view: third.views[0].id) === retained)
        await coordinator.close().finish(); await client.disconnect()
    }

    func testNewCachedEmptyWrapperRetiresBeforeAcknowledgementAndIgnoresLateRejection() async throws {
        let transport = MarkdownTestTransport(); let client = try await connected(transport)
        let card = try markdownCard(content: "empty", additions: ["show_empty": .bool(false)])
        let views = [LovelaceView(title: "Home", path: "home", cards: [card])]
        let model = DashboardViewModel(webSocketClient: client, initialViews: views, currentUserName: "Name")
        await model.synchronizeHistorySubscriptionsForTesting()
        try await until { await transport.commands().count == 1 }
        let commands = await transport.commands()
        try await transport.event(id: try id(commands[0]), result: "")
        try await until { model.markdownCoordinator.ownerCount == 0 }
        await transport.holdAcknowledgements()
        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: [views[0], LovelaceView(title: "Added", path: "added", cards: [])]))
        let state = try XCTUnwrap(model.markdownState(for: model.activeCards[0]))
        XCTAssertTrue(state.hidden)
        XCTAssertEqual(model.markdownCoordinator.ownerCount, 0)
        let later = await transport.commands()
        for command in later { try await transport.reject(id: try id(command)) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(state.hidden); XCTAssertEqual(state.result?.result, "")
        XCTAssertNil(state.alert)
        await model.stop()
        let snapshot = await client.connection.debugSnapshot()
        XCTAssertEqual(snapshot.subscriptionCount, 0)
    }

    func testPhysicalReconnectReusesOriginalRequestAndRetainsAlert() async throws {
        let transport = MarkdownTestTransport(); let client = try await connected(transport)
        let card = try markdownCard(content: "reconnect", additions: ["entity_id": .string("sensor.a")])
        let model = DashboardViewModel(webSocketClient: client, initialViews: [LovelaceView(title: "Home", path: "home", cards: [card])], currentUserName: "Name")
        await model.synchronizeHistorySubscriptionsForTesting()
        try await until { await transport.commands().count == 1 }
        let before = await transport.commands()
        let state = try XCTUnwrap(model.markdownState(for: model.activeCards[0]))
        try await transport.event(id: try id(before[0]), result: "retained")
        try await transport.streamError(id: try id(before[0]), message: "warning stays", level: "WARNING")
        try await until { state.alert != nil && model.markdownCoordinator.startupCount == 0 }
        try await transport.failReceive()
        try await until { await transport.commands().count == 2 }
        let after = await transport.commands()
        var first = before[0], second = after[1]; first.removeValue(forKey: "id"); second.removeValue(forKey: "id")
        XCTAssertEqual(first, second)
        XCTAssertEqual(state.result?.result, "retained"); XCTAssertEqual(state.alert, "warning stays")
        try await transport.event(id: try id(after[1]), result: "reconnected")
        try await until { state.document.source == "reconnected" }
        await model.stop()
    }

    func testOneHundredCardUpdatesStayIsolatedAndChurnReturnsOwnersToZero() async throws {
        let transport = MarkdownTestTransport(); let client = try await connected(transport)
        let cards = try (0..<100).map { try markdownCard(content: "source \($0)") }
        let model = DashboardViewModel(webSocketClient: client, initialViews: [LovelaceView(title: "Home", path: "home", cards: cards)], currentUserName: "Name")
        await model.synchronizeHistorySubscriptionsForTesting()
        try await until { await transport.commands().count == 100 && model.markdownCoordinator.startupCount == 0 }
        let commands = await transport.commands()
        let command = try XCTUnwrap(commands.first { $0["template"] == .string("source 0") })
        let selected = try XCTUnwrap(model.markdownState(for: model.activeCards[0]))
        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        let start = Date()
        for index in 0..<100 { try await transport.event(id: try id(command), result: "update \(index)") }
        try await until { selected.document.source == "update 99" }
        print("Markdown 100-card / 100-update settled: \(Date().timeIntervalSince(start))s")
        XCTAssertEqual(publications, 0)
        XCTAssertTrue(model.activeCards.dropFirst().allSatisfy { model.markdownState(for: $0)?.result == nil })
        observation.cancel()
        await model.stop()
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().markdownOwnerCount, 0)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().markdownPreparationCount, 0)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().markdownRetainedCardCount, 0)
    }

    private func connected(_ transport: MarkdownTestTransport) async throws -> HomeAssistantWebSocketClient {
        let connection = HomeAssistantWebSocketConnection(accessToken: "fixture-token", commandTimeoutNanoseconds: 5_000_000_000, reconnectDelayNanoseconds: { _ in 0 }, transportFactory: { transport })
        let client = HomeAssistantWebSocketClient(connection: connection)
        try await client.connect(); return client
    }
    private func id(_ object: [String: JSONValue]) throws -> Int { guard case let .int(id)? = object["id"] else { throw MarkdownTestError.timeout }; return id }
    private func until(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<25_000 { if await predicate() { return }; await Task.yield() }
        throw MarkdownTestError.timeout
    }
}

enum MarkdownTestError: Error { case timeout }
actor MarkdownTestTransport: HomeAssistantWebSocketTransport {
    private var inbound: [HAWebSocketFrame] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var sent: [[String: JSONValue]] = []
    private var online = false
    var acknowledges: Bool
    let rejects: Bool
    init(acknowledges: Bool = true, rejects: Bool = false) { self.acknowledges = acknowledges; self.rejects = rejects }
    func connect() async throws { online = true; try deliver(["type": .string("auth_required")]) }
    func send(_ frame: HAWebSocketFrame) async throws {
        guard online else { throw HomeAssistantWebSocketError.disconnected }
        let data: Data
        switch frame { case let .string(text): data = Data(text.utf8); case let .data(value): data = value }
        let object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        sent.append(object)
        if object["type"] == .string("auth") { try deliver(["type": .string("auth_ok"), "ha_version": .string("2026.5.4")]); return }
        guard let id = object["id"] else { return }
        if object["type"] == .string("unsubscribe_events") || object["type"] == .string("render_template") && acknowledges {
            let rejected = rejects && object["type"] == .string("render_template")
            try deliver(["id": id, "type": .string("result"), "success": .bool(!rejected), "result": .null,
                         "error": .object(["code": .string("invalid_template"), "message": .string("Fixture rejection")])])
        }
    }
    func receive() async throws -> HAWebSocketFrame {
        guard online else { throw HomeAssistantWebSocketError.disconnected }
        if !inbound.isEmpty { return inbound.removeFirst() }
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }
    func disconnect() async { online = false; let pending = receiver; receiver = nil; pending?.resume(throwing: HomeAssistantWebSocketError.disconnected) }
    func failReceive() throws { guard let receiver = receiver else { throw MarkdownTestError.timeout }; self.receiver = nil; receiver.resume(throwing: HomeAssistantWebSocketError.disconnected) }
    func holdAcknowledgements() { acknowledges = false }
    func reject(id: Int) throws { try deliver(["id": .int(id), "type": .string("result"), "success": .bool(false), "error": .object(["code": .string("invalid_template"), "message": .string("Late rejection")])]) }
    func commands() -> [[String: JSONValue]] { sent.filter { $0["type"] == .string("render_template") } }
    func event(id: Int, result: String) throws {
        try deliver(["id": .int(id), "type": .string("event"), "event": .object(["result": .string(result), "listeners": .object(["all": .bool(false), "domains": .array([]), "entities": .array([]), "time": .bool(false)])])])
    }
    func streamError(id: Int, message: String, level: String) throws { try deliver(["id": .int(id), "type": .string("event"), "event": .object(["error": .string(message), "level": .string(level)])]) }
    private func deliver(_ object: [String: JSONValue]) throws {
        let frame = HAWebSocketFrame.string(String(decoding: try JSONEncoder().encode(object), as: UTF8.self))
        if let receiver = receiver { self.receiver = nil; receiver.resume(returning: frame) } else { inbound.append(frame) }
    }
}
