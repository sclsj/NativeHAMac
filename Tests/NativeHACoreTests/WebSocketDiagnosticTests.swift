import XCTest
@testable import NativeHACore

final class WebSocketDiagnosticTests: XCTestCase {
    private var savedPolicy: LoggingPolicy!

    override func setUp() {
        super.setUp()
        savedPolicy = activeLoggingPolicy
        activeLoggingPolicy.minimumSeverity.webSocket = .warning
    }

    override func tearDown() {
        activeLoggingPolicy = savedPolicy
        super.tearDown()
    }

    func testRejectedCommandPersistsIdentityAndServerReasonAtWarningThreshold() async throws {
        let marker = "rejection-\(UUID())"
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let connection = makeConnection(transport)
        try await connection.connect()
        let call = Task { try await connection.callRaw(["type": .string(marker)]) }
        try await waitUntil { await transport.sentObjects().contains { $0["type"] == .string(marker) } }
        let sent = await transport.sentObjects()
        let id = try XCTUnwrap(sent.first { $0["type"] == .string(marker) }?["id"]?.testInt)
        try await transport.push([
            "id": .int(id), "type": "result", "success": false,
            "error": .object(["code": "invalid_format", "message": "complete server reason"]),
        ])
        do {
            _ = try await call.value
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .commandFailed(code: "invalid_format", message: "complete server reason"))
        }
        let rows = try persistedDiagnosticMessages(containing: marker)
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertTrue(row.contains("command id=\(id)"))
        XCTAssertTrue(row.contains("connection="))
        XCTAssertTrue(row.contains("generation="))
        XCTAssertTrue(row.contains("complete server reason"))
        await connection.disconnect()
    }

    func testTimeoutIsRecordedButNormalCancellationIsNot() async throws {
        let timeoutMarker = "timeout-\(UUID())"
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let connection = makeConnection(transport, timeout: 5_000_000)
        try await connection.connect()
        do {
            _ = try await connection.callRaw(["type": .string(timeoutMarker)])
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? HomeAssistantWebSocketError, .timedOut)
        }
        XCTAssertEqual(try persistedDiagnosticMessages(containing: timeoutMarker).count, 1)
        await connection.disconnect()

        let cancelMarker = "cancel-\(UUID())"
        let cancelTransport = ScriptedWebSocketTransport(automaticAuthentication: true)
        let cancelConnection = makeConnection(cancelTransport)
        try await cancelConnection.connect()
        let task = Task { try await cancelConnection.callRaw(["type": .string(cancelMarker)]) }
        try await waitUntil { await cancelTransport.sentObjects().contains { $0["type"] == .string(cancelMarker) } }
        task.cancel()
        _ = try? await task.value
        XCTAssertTrue(try persistedDiagnosticMessages(containing: cancelMarker).isEmpty)
        await cancelConnection.disconnect()
    }

    func testTypedPayloadFailureRetainsCodingPathAndFullPayload() async throws {
        let marker = "typed-decode-\(UUID())"
        let transport = ScriptedWebSocketTransport(automaticAuthentication: true, automaticSubscriptionAcknowledgement: true)
        let connection = makeConnection(transport)
        try await connection.connect()
        let errors = WebSocketErrorLog()
        let subscription = try await connection.subscribeMessage(
            ["type": "subscribe_events", "event_type": .string(marker)],
            as: DiagnosticPayload.self,
            onTermination: { await errors.append($0) }
        ) { _ in XCTFail("Malformed event must not be delivered") }
        try await transport.push([
            "id": .int(subscription.id), "type": "event",
            "event": .object(["sequence": "not an integer", "complete_payload": .string(marker)]),
        ])
        try await waitUntil { await errors.snapshot().count == 1 }
        let rows = try persistedDiagnosticMessages(containing: marker)
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertTrue(row.contains("typeMismatch"))
        XCTAssertTrue(row.contains("sequence"))
        XCTAssertTrue(row.contains("complete_payload"))
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.state, .ready)
        await subscription.cancel()
        await connection.disconnect()
    }

    private func makeConnection(_ transport: ScriptedWebSocketTransport, timeout: UInt64 = 5_000_000_000) -> HomeAssistantWebSocketConnection {
        HomeAssistantWebSocketConnection(accessToken: "test", commandTimeoutNanoseconds: timeout, transportFactory: { transport })
    }
}

private struct DiagnosticPayload: Decodable { let sequence: Int }
