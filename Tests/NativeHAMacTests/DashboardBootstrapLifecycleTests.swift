import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class DashboardBootstrapLifecycleTests: XCTestCase {
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
        XCTAssertEqual(beforeSwitch.subscriptionCount, 1)
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
        XCTAssertEqual(afterSwitch.subscriptionCount, 1)
        XCTAssertEqual(afterSwitch.wireSubscriptionCount, 1)

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
        XCTAssertEqual(liveSnapshot.subscriptionCount, 1)
        XCTAssertEqual(liveSnapshot.wireSubscriptionCount, 1)

        try await transport.resolveHeldCurrentUser(commandOrdinal: 0, id: "obsolete-user")
        try await obsolete.value
        let metrics = await transport.metrics()
        XCTAssertEqual(metrics.disconnectCalls, 0, "Obsolete same-client bootstrap must not disconnect latest ownership")
        let finalSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(finalSnapshot.state, .ready)
        XCTAssertEqual(finalSnapshot.subscriptionCount, 1)
        XCTAssertEqual(finalSnapshot.wireSubscriptionCount, 1)

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
        XCTAssertEqual(latestSnapshot.subscriptionCount, 1)
        XCTAssertEqual(latestSnapshot.wireSubscriptionCount, 1)

        try await latestTransport.pushState(entityID: "sensor.latest", state: "current")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["sensor.latest"]?.state == "current" }
        }
        XCTAssertEqual(model.status, "Live")
        XCTAssertEqual(model.homeView?.title, "Latest Apply")

        await latestClient.disconnect()
    }

    func testLatestBootstrapFailureRetiresPreviouslyInstalledDistinctClientWithoutLeak() async throws {
        let installedTransport = DashboardBootstrapTransport(
            mode: .success,
            dashboardTitle: "Installed"
        )
        let failingTransport = DashboardBootstrapTransport(mode: .malformedLovelace)
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
        let installedClient = HomeAssistantWebSocketClient(connection: installedConnection)
        let failingClient = HomeAssistantWebSocketClient(connection: failingConnection)
        let model = DashboardViewModel(
            navigationPreferenceStore: BootstrapMemoryNavigationPreferenceStore()
        )

        try await model.bootstrapDashboard(using: installedClient)
        let initiallyInstalledSnapshot = await installedConnection.debugSnapshot()
        XCTAssertEqual(initiallyInstalledSnapshot.subscriptionCount, 1)
        do {
            try await model.bootstrapDashboard(using: failingClient)
            XCTFail("Malformed latest bootstrap must fail")
        } catch {
            XCTAssertTrue(error is DecodingError || error is LovelaceDecodeError)
        }

        let installedSnapshot = await installedConnection.debugSnapshot()
        let failingSnapshot = await failingConnection.debugSnapshot()
        XCTAssertEqual(installedSnapshot.state, .disconnected)
        XCTAssertEqual(installedSnapshot.subscriptionCount, 0)
        XCTAssertEqual(installedSnapshot.wireSubscriptionCount, 0)
        XCTAssertEqual(failingSnapshot.state, .disconnected)
        XCTAssertEqual(failingSnapshot.subscriptionCount, 0)
        let installedMetrics = await installedTransport.metrics()
        let failingMetrics = await failingTransport.metrics()
        XCTAssertEqual(installedMetrics.disconnectCalls, 1)
        XCTAssertEqual(failingMetrics.disconnectCalls, 1)
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
        XCTAssertEqual(snapshot.subscriptionCount, 1)
        XCTAssertEqual(snapshot.wireSubscriptionCount, 1)
        XCTAssertEqual(metrics.disconnectCalls, 0)

        try await transport.pushState(entityID: "sensor.shared", state: "latest")
        try await waitForBootstrapCondition {
            await MainActor.run { model.states["sensor.shared"]?.state == "latest" }
        }
        await client.disconnect()
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
        case .holdFirstCurrentUser, .success:
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

private actor DashboardBootstrapTransport: HomeAssistantWebSocketTransport {
    enum Mode {
        case malformedLovelace
        case rejectStateSubscription
        case rejectCurrentUser
        case holdCurrentUser
        case holdFirstCurrentUser
        case success
    }

    private let mode: Mode
    private let dashboardTitle: String?
    private let successfulUserID: String
    private var connected = false
    private var inbound: [Result<HAWebSocketFrame, Error>] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var sent: [[String: JSONValue]] = []
    private var activeReceives = 0
    private var disconnectCalls = 0
    private var stateSubscriptionID: Int?

    init(
        mode: Mode,
        dashboardTitle: String? = nil,
        successfulUserID: String = "user-1"
    ) {
        self.mode = mode
        self.dashboardTitle = dashboardTitle
        self.successfulUserID = successfulUserID
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
            case .holdFirstCurrentUser, .success:
                result = .object(["views": .array([
                    .object([
                        "title": .string(dashboardTitle ?? "Current"),
                        "path": .string("default_view"),
                        "cards": .array([]),
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
            try deliverSuccess(id: id, result: .object(["entities": .array([])]))
        case "frontend/get_user_data":
            try deliverSuccess(id: id, result: .object(["value": .null]))
        case "subscribe_events":
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
                "event_type": .string("state_changed"),
                "data": .object([
                    "new_state": .object([
                        "entity_id": .string(entityID),
                        "state": .string(state),
                        "attributes": .object([:]),
                    ]),
                ]),
            ]),
        ])
    }

    func currentUserCommandCount() -> Int {
        sent.filter { $0["type"] == .string("auth/current_user") }.count
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
