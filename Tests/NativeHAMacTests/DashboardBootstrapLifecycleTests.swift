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

private actor DashboardBootstrapTransport: HomeAssistantWebSocketTransport {
    enum Mode {
        case malformedLovelace
        case rejectStateSubscription
    }

    private let mode: Mode
    private var connected = false
    private var inbound: [Result<HAWebSocketFrame, Error>] = []
    private var receiver: CheckedContinuation<HAWebSocketFrame, Error>?
    private var activeReceives = 0
    private var disconnectCalls = 0

    init(mode: Mode) {
        self.mode = mode
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
            let result: JSONValue = mode == .malformedLovelace
                ? .string("not-a-lovelace-config")
                : .object(["views": .array([])])
            try deliverSuccess(id: id, result: result)
        case "config/entity_registry/list_for_display":
            try deliverSuccess(id: id, result: .object(["entities": .array([])]))
        case "frontend/get_user_data":
            try deliverSuccess(id: id, result: .object(["value": .null]))
        case "subscribe_events":
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
            }
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
