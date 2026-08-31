import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class DashboardOrchestrationTests: XCTestCase {
    func testTenThousandEntityMainActorPublicationMetric() {
        let snapshot = Dictionary(uniqueKeysWithValues: (0..<10_000).map { index in
            ("sensor.\(index)", HAState(entityId: "sensor.\(index)", state: "\(index)"))
        })
        let model = DashboardViewModel()
        var consumed = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            model.states = snapshot
            consumed = model.states.count
        }
        XCTAssertEqual(consumed, 10_000)
    }

    func testHundredEntityOwnerStartStopCyclesLeaveNoTasksOrSubscriptions() async throws {
        let transport = EntityCoordinatorTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "entity-cycle-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        try await client.connect()
        var coordinator: HAEntitySubscriptionCoordinator? = HAEntitySubscriptionCoordinator(
            onSnapshot: { _ in },
            onPhase: { _ in }
        )
        weak var weakCoordinator = coordinator
        for _ in 0..<100 {
            _ = try await coordinator?.start(using: client)
            await coordinator?.stop()
            let snapshot = await connection.debugSnapshot()
            XCTAssertEqual(snapshot.subscriptionCount, 0)
            XCTAssertEqual(snapshot.deliveryOwnerCount, 0)
        }
        let subscriptionStarts = await transport.entitySubscriptionCount()
        XCTAssertEqual(subscriptionStarts, 100)
        coordinator = nil
        for _ in 0..<100 where weakCoordinator != nil { await Task.yield() }
        XCTAssertNil(weakCoordinator)
        await client.disconnect()
    }

    func testEntityCoordinatorUsesFreshAuthoritativeOwnerAcrossReconnect() async throws {
        let transport = EntityCoordinatorTransport()
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "entity-coordinator-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        try await client.connect()
        var published: [String: HAState] = [
            "sensor.retained": HAState(entityId: "sensor.retained", state: "retained"),
        ]
        var phases: [DashboardComponentPhase] = []
        let coordinator = HAEntitySubscriptionCoordinator(
            initialStates: published,
            onSnapshot: { published = $0 },
            onPhase: { phases.append($0) }
        )

        let first = try await coordinator.start(using: client)
        XCTAssertEqual(Set(first.keys), ["sensor.initial"])
        XCTAssertNil(published["sensor.retained"])
        try await transport.pushDelta(entityID: "sensor.initial", state: "delta")
        try await waitForOrchestrationCondition { published["sensor.initial"]?.state == "delta" }

        await connection.reconnect()
        try await waitForOrchestrationCondition {
            await transport.entitySubscriptionCount() == 2
        }
        try await waitForOrchestrationCondition { Set(published.keys) == ["sensor.reconnected"] }
        XCTAssertNil(published["sensor.initial"], "Reconnect full snapshot must atomically replace retained entities")
        XCTAssertTrue(phases.contains(.reconnecting) || phases.contains(.disconnected))
        let reconnectSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(reconnectSnapshot.subscriptionCount, 1)

        await coordinator.stop()
        let owner = coordinator.debugSnapshot()
        XCTAssertFalse(owner.hasSubscription)
        XCTAssertFalse(owner.hasStatusTask)
        let stoppedSnapshot = await connection.debugSnapshot()
        XCTAssertEqual(stoppedSnapshot.subscriptionCount, 0)
        await client.disconnect()
    }

    func testEntityCoordinatorRejectsMalformedOrNonFullInitialEventsAndResumesWaiter() async throws {
        for initialEvent in [
            EntityCoordinatorTransport.InitialEvent.malformed,
            .emptyWithoutAdditions,
            .changeOnly,
        ] {
            let transport = EntityCoordinatorTransport(initialEvent: initialEvent)
            let connection = HomeAssistantWebSocketConnection(
                accessToken: "entity-invalid-first-test-token",
                commandTimeoutNanoseconds: 5_000_000_000,
                reconnectDelayNanoseconds: { _ in 0 },
                transportFactory: { transport }
            )
            let client = HomeAssistantWebSocketClient(connection: connection)
            try await client.connect()
            var phases: [DashboardComponentPhase] = []
            let coordinator = HAEntitySubscriptionCoordinator(
                onSnapshot: { _ in XCTFail("An invalid first event must not publish") },
                onPhase: { phases.append($0) }
            )

            do {
                _ = try await coordinator.start(using: client)
                XCTFail("An invalid first event must terminate its initial waiter")
            } catch {
                // Expected: the precise error type is transport- versus
                // coordinator-owned, but the generation must settle failed.
            }
            XCTAssertTrue(phases.contains { if case .failed = $0 { return true }; return false })
            let owner = coordinator.debugSnapshot()
            XCTAssertFalse(owner.acceptedFirstSnapshot)
            XCTAssertFalse(owner.hasSubscription)
            try await waitForOrchestrationCondition {
                let snapshot = await connection.debugSnapshot()
                return snapshot.subscriptionCount == 0 && snapshot.deliveryOwnerCount == 0
            }
            let socket = await connection.debugSnapshot()
            XCTAssertEqual(socket.subscriptionCount, 0)
            XCTAssertEqual(socket.deliveryOwnerCount, 0)
            await coordinator.stop()
            await client.disconnect()
        }
    }

    func testEntityCoordinatorAcceptsExplicitEmptyFullAndMalformedDeltaFailsGeneration() async throws {
        let transport = EntityCoordinatorTransport(initialEvent: .explicitEmptyFull)
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "entity-empty-full-test-token",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 0 },
            transportFactory: { transport }
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        try await client.connect()
        var published: [String: HAState] = [
            "sensor.retained": HAState(entityId: "sensor.retained", state: "retained"),
        ]
        var phases: [DashboardComponentPhase] = []
        let coordinator = HAEntitySubscriptionCoordinator(
            initialStates: published,
            onSnapshot: { published = $0 },
            onPhase: { phases.append($0) }
        )

        let initial = try await coordinator.start(using: client)
        XCTAssertTrue(initial.isEmpty)
        XCTAssertTrue(published.isEmpty)
        XCTAssertTrue(coordinator.debugSnapshot().acceptedFirstSnapshot)

        try await transport.pushMalformedDelta()
        try await waitForOrchestrationCondition {
            phases.contains { if case .failed = $0 { return true }; return false }
        }
        let failedOwner = coordinator.debugSnapshot()
        XCTAssertFalse(failedOwner.acceptedFirstSnapshot)
        XCTAssertFalse(failedOwner.hasSubscription)
        try await waitForOrchestrationCondition {
            let snapshot = await connection.debugSnapshot()
            return snapshot.subscriptionCount == 0 && snapshot.deliveryOwnerCount == 0
        }
        let failedSocket = await connection.debugSnapshot()
        XCTAssertEqual(failedSocket.subscriptionCount, 0)
        XCTAssertEqual(failedSocket.deliveryOwnerCount, 0)
        await coordinator.stop()
        await client.disconnect()
    }

    func testExplicitStopIsIdempotentAndLeavesDashboardOwnersEmpty() async {
        let model = DashboardViewModel(
            initialStates: ["sensor.one": HAState(entityId: "sensor.one", state: "1")],
            initialViews: [],
            navigationPreferenceStore: OrchestrationMemoryPreferenceStore()
        )
        await model.stop()
        await model.stop()
        XCTAssertEqual(model.lifecycle.phase, .stopped)
        let snapshot = model.dashboardOwnerSnapshotForTesting()
        XCTAssertTrue(snapshot.desiredHistoryKeys.isEmpty)
        XCTAssertTrue(snapshot.subscriptionKeys.isEmpty)
        XCTAssertTrue(snapshot.generationKeys.isEmpty)
        XCTAssertEqual(snapshot.startupCount, 0)
        XCTAssertEqual(snapshot.mountedOwnerCount, 0)
    }
}

private actor EntityCoordinatorTransport: HomeAssistantWebSocketTransport {
    enum InitialEvent {
        case full
        case explicitEmptyFull
        case emptyWithoutAdditions
        case changeOnly
        case malformed
    }

    private let initialEvent: InitialEvent
    private var connected = false
    private var inbound: [HAWebSocketFrame] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var subscribeCount = 0
    private var subscriptionID: Int?

    init(initialEvent: InitialEvent = .full) {
        self.initialEvent = initialEvent
    }

    func connect() async throws {
        connected = true
        try deliver(["type": .string("auth_required")])
    }

    func send(_ frame: HAWebSocketFrame) async throws {
        let object = try decode(frame)
        if object["type"] == .string("auth") {
            try deliver(["type": .string("auth_ok"), "ha_version": .string("2025.7.0")])
            return
        }
        guard let id = object["id"]?.orchestrationInt else { return }
        switch object["type"] {
        case .string("subscribe_entities"):
            subscribeCount += 1
            subscriptionID = id
            try result(id: id)
            if subscribeCount > 1 {
                try deliverEntityEvent(id: id, additions: ["sensor.reconnected": "full-\(subscribeCount)"])
            } else {
                switch initialEvent {
                case .full:
                    try deliverEntityEvent(id: id, additions: ["sensor.initial": "full-1"])
                case .explicitEmptyFull:
                    try deliverEntityEvent(id: id, additions: [:])
                case .emptyWithoutAdditions:
                    try deliver(["id": .int(id), "type": .string("event"), "event": .object([:])])
                case .changeOnly:
                    try deliver([
                        "id": .int(id), "type": .string("event"),
                        "event": .object([
                            "c": .object([
                                "sensor.unknown": .object(["+": .object(["s": .string("bad")])]),
                            ]),
                        ]),
                    ])
                case .malformed:
                    try deliver([
                        "id": .int(id), "type": .string("event"),
                        "event": .object([
                            "a": .object([
                                "sensor.bad": .object([
                                    "s": .string("bad"), "a": .object([:]), "c": .string("context"),
                                ]),
                            ]),
                        ]),
                    ])
                }
            }
        case .string("unsubscribe_events"):
            try result(id: id)
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
        if let receiver = receiver {
            self.receiver = nil
            receiver.resume(throwing: HomeAssistantWebSocketError.disconnected)
        }
    }

    func pushDelta(entityID: String, state: String) throws {
        guard let id = subscriptionID else { throw HomeAssistantWebSocketError.invalidMessage }
        try deliver([
            "id": .int(id), "type": .string("event"),
            "event": .object([
                "c": .object([
                    entityID: .object(["+": .object(["s": .string(state)])]),
                ]),
            ]),
        ])
    }

    func pushMalformedDelta() throws {
        guard let id = subscriptionID else { throw HomeAssistantWebSocketError.invalidMessage }
        try deliver([
            "id": .int(id), "type": .string("event"),
            "event": .object([
                "c": .object([
                    "sensor.bad": .object(["+": .object(["lc": .string("not-a-number")])]),
                ]),
            ]),
        ])
    }

    func entitySubscriptionCount() -> Int { subscribeCount }

    private func result(id: Int) throws {
        try deliver(["id": .int(id), "type": .string("result"), "success": .bool(true), "result": .null])
    }

    private func deliverEntityEvent(id: Int, additions: [String: String]) throws {
        let states = additions.mapValues { value in
            JSONValue.object([
                "s": .string(value), "a": .object([:]), "c": .string("context"),
                "lc": .double(1_700_000_000),
            ])
        }
        try deliver([
            "id": .int(id), "type": .string("event"),
            "event": .object(["a": .object(states)]),
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
        switch frame { case let .string(value): data = Data(value.utf8); case let .data(value): data = value }
        guard case let .object(object) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        return object
    }
}

private final class OrchestrationMemoryPreferenceStore: LovelaceNavigationPreferenceStore {
    func object(forKey key: String) throws -> Any? { nil }
    func set(_ value: Any, forKey key: String) throws {}
    func removeObject(forKey key: String) throws {}
}

private extension JSONValue {
    var orchestrationInt: Int? { guard case let .int(value) = self else { return nil }; return value }
}

private func waitForOrchestrationCondition(
    _ condition: @escaping () async -> Bool
) async throws {
    for _ in 0..<100_000 {
        if await condition() { return }
        await Task.yield()
    }
    throw URLError(.timedOut)
}
