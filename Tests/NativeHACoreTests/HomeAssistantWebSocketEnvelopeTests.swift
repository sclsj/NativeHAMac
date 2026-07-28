import Foundation
import XCTest
@testable import NativeHACore

final class HomeAssistantWebSocketEnvelopeTests: XCTestCase {
    func testScannerFindsNestedEventWithoutRetainingOrDecodingEnvelopePayload() throws {
        let source = #"{"id":42,"type":"event","event":{"text":"escaped } ] \" value","nested":[{"x":1}]}}"#
        let data = Data(source.utf8)
        let envelope = try XCTUnwrap(HAWebSocketEnvelopeScanner.scan(data).first)

        XCTAssertEqual(envelope.id, 42)
        XCTAssertEqual(envelope.type, "event")
        XCTAssertTrue(envelope.canRouteDirectly)
        let eventRange = try XCTUnwrap(envelope.eventRange)
        XCTAssertEqual(
            try JSONDecoder().decode(JSONValue.self, from: data.subdata(in: eventRange)),
            .object([
                "text": .string("escaped } ] \" value"),
                "nested": .array([.object(["x": .int(1)])]),
            ])
        )
    }

    func testScannerPreservesCoalescedObjectOrderAndRanges() throws {
        let source = #"[{"id":3,"type":"event","event":{"sequence":1}},{"id":7,"type":"result","success":true,"result":null},{"id":3,"type":"event","event":{"sequence":2}}]"#
        let data = Data(source.utf8)
        let envelopes = try HAWebSocketEnvelopeScanner.scan(data)

        XCTAssertEqual(envelopes.map(\.id), [3, 7, 3])
        XCTAssertEqual(envelopes.map(\.type), ["event", "result", "event"])
        XCTAssertEqual(
            envelopes.compactMap(\.eventRange).map {
                String(decoding: data.subdata(in: $0), as: UTF8.self)
            },
            [#"{"sequence":1}"#, #"{"sequence":2}"#]
        )
    }

    func testScannerRejectsMalformedEnvelopeBoundaries() {
        XCTAssertThrowsError(
            try HAWebSocketEnvelopeScanner.scan(Data(#"[{"id":1,"type":"event","event":{"x":1}]"#.utf8))
        )
        XCTAssertThrowsError(
            try HAWebSocketEnvelopeScanner.scan(Data(#"{"id":1,"type":"event","event":[1,2}}"#.utf8))
        )
        XCTAssertThrowsError(
            try HAWebSocketEnvelopeScanner.scan(Data(#"{"id":1,"type":"event","event":{"x":truX}}"#.utf8))
        )
        XCTAssertThrowsError(
            try HAWebSocketEnvelopeScanner.scan(Data(#"{"id":1,"type":"event","event":{"x" 1}}"#.utf8))
        )
    }

    func testScannerFallsBackForExtendedOrEscapedMetadata() throws {
        let extended = try XCTUnwrap(HAWebSocketEnvelopeScanner.scan(Data(
            #"{"id":1,"type":"event","event":{"x":1},"extension":true}"#.utf8
        )).first)
        XCTAssertFalse(extended.canRouteDirectly)

        let escaped = try XCTUnwrap(HAWebSocketEnvelopeScanner.scan(Data(
            #"{"id":1,"\u0074ype":"event","event":{"x":1}}"#.utf8
        )).first)
        XCTAssertFalse(escaped.canRouteDirectly)
    }
}
