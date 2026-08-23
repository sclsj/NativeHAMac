import Foundation
import XCTest
@testable import NativeHACore

final class LovelaceModelTests: XCTestCase {
    func testRepresentativeFixturePreservesRawAndTypedSurface() throws {
        let data = try fixture("representative-dashboard")
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        let config = try JSONDecoder().decode(LovelaceConfig.self, from: data)
        XCTAssertEqual(config.rawValue, raw)
        XCTAssertEqual(config.views.map(\.path), ["default_view", "home_3h", "home_12h"])
        XCTAssertEqual(config.views[0].icon, "mdi:home")
        XCTAssertEqual(config.views[0].showIconAndTitle, false)
        XCTAssertEqual(config.views[0].subview, false)
        XCTAssertEqual(config.views[0].backPath, "/lovelace")
        XCTAssertEqual(config.views[0].panel, false)
        XCTAssertEqual(config.views[0].type, "masonry")
        XCTAssertNotNil(config.views[0].visible)
        XCTAssertNotNil(config.views[0].theme)
        XCTAssertNotNil(config.views[0].background)
        XCTAssertNotNil(config.views[0].sections)
        XCTAssertNotNil(config.views[0].header)
        XCTAssertNotNil(config.views[0].footer)

        let cards = config.views[0].cards
        XCTAssertEqual(cards.count, 5)
        XCTAssertEqual(cards[0].showHeaderToggle, false)
        XCTAssertEqual(cards[0].icon, "mdi:format-list-bulleted")
        XCTAssertEqual(cards[0].stateColor, true)
        XCTAssertEqual(cards[0].disabled, false)
        XCTAssertNotNil(cards[0].gridOptions)
        XCTAssertNotNil(cards[0].visibility)
        XCTAssertNotNil(cards[0].header)
        XCTAssertNotNil(cards[0].footer)
        XCTAssertNotNil(cards[0].tapAction)
        XCTAssertNotNil(cards[0].holdAction)
        XCTAssertNotNil(cards[0].doubleTapAction)
        XCTAssertEqual(cards[0].entities?.map(\.entity), ["sensor.string_row", "sensor.object_row", nil])
        XCTAssertEqual(cards[0].entities?[1].stateColor, false)
        XCTAssertEqual(cards[0].entities?[1].color, "red")
        XCTAssertEqual(cards[0].entities?[1].icon, "mdi:gauge")
        XCTAssertEqual(cards[0].entities?[1].secondaryInfo, "last-changed")
        XCTAssertEqual(cards[0].entities?[1].showName, true)
        XCTAssertEqual(cards[0].entities?[1].showIcon, false)
        XCTAssertNotNil(cards[0].entities?[1].tapAction)
        XCTAssertNotNil(cards[0].entities?[1].holdAction)
        XCTAssertNotNil(cards[0].entities?[1].doubleTapAction)
        XCTAssertEqual(cards[0].entities?[1].name, "Object")
        XCTAssertEqual(cards[0].entities?[2].type, "divider")
        XCTAssertEqual(cards[1].hoursToShow, 12)
        XCTAssertEqual(cards[1].entities?.first?.color, "#00aaff")
        XCTAssertNil(cards[1].diagnostic)
        XCTAssertNotNil(cards[1].entities?[1].diagnostic)
        XCTAssertEqual(cards[1].showNames, false)
        XCTAssertEqual(cards[1].logarithmicScale, true)
        XCTAssertEqual(cards[1].minYAxis, 0)
        XCTAssertEqual(cards[1].maxYAxis, 100.5)
        XCTAssertEqual(cards[1].fitYData, true)
        XCTAssertEqual(cards[1].splitDeviceClasses, false)
        XCTAssertEqual(cards[1].expandLegend, true)
        XCTAssertEqual(cards[2].showForecast, false)
        XCTAssertEqual(cards[2].showCurrent, true)
        XCTAssertEqual(cards[2].forecastType, "daily")
        XCTAssertEqual(cards[2].forecastSlots, 5)
        XCTAssertEqual(cards[2].secondaryInfoAttribute, "humidity")
        XCTAssertEqual(cards[2].roundTemperature, true)
        XCTAssertEqual(cards[2].name, "Home weather")
        XCTAssertEqual(cards[3].textOnly, false)
        XCTAssertEqual(cards[3].cardSize, 3)
        XCTAssertEqual(cards[3].entityIDs, ["sensor.a"])
        XCTAssertEqual(cards[3].entityID, "sensor.b")
        XCTAssertEqual(cards[3].showEmpty, false)
        XCTAssertNotNil(cards[3].tapAction)
        XCTAssertEqual(cards[4].cards?[1].columns, 2)
        XCTAssertEqual(cards[4].cards?[1].square, false)
        XCTAssertNotNil(cards[4].cards?[2].conditionalCard)
        XCTAssertNotNil(cards[4].cards?[2].conditions)
    }

    func testUnknownFieldsAndAllJSONTypesSurviveDecode() throws {
        let data = try fixture("unknown-fields")
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        let config = try JSONDecoder().decode(LovelaceConfig.self, from: data)
        XCTAssertEqual(config.rawValue, raw)
        XCTAssertEqual(LovelaceResolvedDashboard(source: config).source.rawValue, raw)
        XCTAssertTrue(config.rawValue.canonicalSemanticValue.contains("unknown_top"))
    }

    func testInvalidRootsThrowAndMalformedChildrenRecoverInOrder() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(LovelaceConfig.self, from: Data("[]".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LovelaceConfig.self, from: Data("{}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LovelaceConfig.self, from: Data("{\"views\":null}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LovelaceConfig.self, from: Data("{\"views\":[".utf8)))

        let config = try JSONDecoder().decode(LovelaceConfig.self, from: fixture("malformed-configurations"))
        XCTAssertEqual(config.views.count, 3)
        XCTAssertNotNil(config.views[0].diagnostic)
        XCTAssertEqual(config.views[1].cards.count, 12)
        XCTAssertEqual(config.views[1].cards.first?.content, "valid before")
        XCTAssertEqual(config.views[1].cards.last?.content, "valid after")
        XCTAssertNotNil(config.views[1].cards[1].diagnostic)
        XCTAssertNotNil(config.views[1].cards[2].diagnostic)
        XCTAssertNotNil(config.views[1].cards[3].diagnostic)
        XCTAssertEqual(config.views[1].cards[4].entities?.count, 4)
        XCTAssertNotNil(config.views[1].cards[4].entities?[1].diagnostic)
        XCTAssertNotNil(config.views[1].cards[5].diagnostic)
        for index in 6...10 {
            XCTAssertNotNil(config.views[1].cards[index].diagnostic, "supported invalid card \(index) must recover locally")
        }
        XCTAssertEqual(config.views[1].cards[7].entities?.count, 1)
        XCTAssertNotNil(config.views[1].cards[7].entities?.first?.diagnostic)
        XCTAssertNotNil(config.views[2].diagnostic)
        XCTAssertTrue(config.views[2].diagnostic?.message.contains("icon must be a string") == true)
        XCTAssertTrue(config.views[2].diagnostic?.message.contains("panel must be a boolean") == true)
    }

    func testCanonicalSemanticValueAndResolvedIdentityAreExactAndDeterministic() throws {
        let left: JSONValue = .object(["b": .double(1), "a": .int(1)])
        let reordered: JSONValue = .object(["a": .int(1), "b": .double(1)])
        XCTAssertEqual(left.canonicalSemanticValue, reordered.canonicalSemanticValue)
        XCTAssertNotEqual(JSONValue.int(1).canonicalSemanticValue, JSONValue.double(1).canonicalSemanticValue)
        XCTAssertNotEqual(JSONValue.string("ab").canonicalSemanticValue, JSONValue.string("a") .canonicalSemanticValue)
        XCTAssertEqual(JSONValue.double(-0.0).canonicalSemanticValue, JSONValue.double(0.0).canonicalSemanticValue)

        let config = try JSONDecoder().decode(LovelaceConfig.self, from: fixture("representative-dashboard"))
        let first = LovelaceResolvedDashboard(source: config)
        let second = LovelaceResolvedDashboard(source: config)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.views[0].cards[0].identity, second.views[0].cards[0].identity)
        XCTAssertNotEqual(first.views[0].cards[0].identity, first.views[0].cards[1].identity)
    }

    func testIdentityMatrixUsesRawPathAndExactSemantics() throws {
        func resolved(_ cards: [LovelaceCard]) -> [LovelaceResolvedCard] {
            LovelaceResolvedDashboard(source: LovelaceConfig(views: [
                LovelaceView(title: "Home", path: "default_view", cards: cards),
            ])).views[0].cards
        }
        let a = LovelaceCard(type: "markdown", title: "A", content: "a")
        let b = LovelaceCard(type: "markdown", title: "B", content: "b")
        let same = resolved([a, b])
        XCTAssertEqual(same, resolved([a, b]))
        let inserted = resolved([LovelaceCard(type: "markdown", content: "x"), a, b])
        XCTAssertNotEqual(same[0].identity, inserted[1].identity)
        let reordered = resolved([b, a])
        XCTAssertNotEqual(same[0].identity, reordered[1].identity)
        let duplicates = resolved([a, a])
        XCTAssertNotEqual(duplicates[0].identity, duplicates[1].identity)
        let replacement = resolved([LovelaceCard(type: "markdown", title: "A", content: "changed"), b])
        XCTAssertNotEqual(same[0].identity, replacement[0].identity)
        XCTAssertEqual(same[1].identity, replacement[1].identity)
    }

    func testDeterministicFiveHundredCardDecodeResolveAndTraversal() throws {
        func leaf(view: Int, index: Int) -> JSONValue {
            switch index % 4 {
            case 0:
                return .object([
                    "type": .string("entities"),
                    "title": .string("Rows \(index)"),
                    "entities": .array([
                        .string("sensor.\(view)_\(index)_string"),
                        .object(["entity": .string("sensor.\(view)_\(index)_object")]),
                        .object(["type": .string("divider")]),
                    ]),
                ])
            case 1:
                return .object([
                    "type": .string("history-graph"),
                    "entities": .array([.string("sensor.\(view)_\(index)_history")]),
                ])
            case 2:
                return .object(["type": .string("weather-forecast"), "entity": .string("weather.\(view)_\(index)")])
            default:
                return .object(["type": .string("markdown"), "content": .string("Value \(view)-\(index)")])
            }
        }
        let rawViews: [JSONValue] = (0..<10).map { view in
            .object([
                "title": .string("View \(view)"),
                "path": .string(view == 0 ? "default_view" : "view_\(view)"),
                "cards": .array((0..<5).map { stack in
                    .object([
                        "type": .string("vertical-stack"),
                        "cards": .array((0..<9).map { leaf(view: view, index: stack * 9 + $0) }),
                    ])
                }),
            ])
        }
        let data = try JSONEncoder().encode(JSONValue.object(["views": .array(rawViews)]))
        let first = try JSONDecoder().decode(LovelaceConfig.self, from: data)
        let firstResolved = LovelaceResolvedDashboard(source: first)
        let secondResolved = LovelaceResolvedDashboard(
            source: try JSONDecoder().decode(LovelaceConfig.self, from: data)
        )
        XCTAssertEqual(firstResolved, secondResolved)
        func allCards(_ cards: [LovelaceResolvedCard]) -> [LovelaceResolvedCard] {
            cards.flatMap { [$0] + allCards($0.cards ?? []) }
        }
        let firstCards = firstResolved.views.flatMap { allCards($0.cards) }
        let secondCards = secondResolved.views.flatMap { allCards($0.cards) }
        XCTAssertEqual(firstCards.count, 500)
        func checksum(_ cards: [LovelaceResolvedCard]) -> UInt64 {
            cards.flatMap { $0.identity.ownerKey.utf8 }.reduce(14_695_981_039_346_656_037) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
        }
        XCTAssertEqual(checksum(firstCards), checksum(secondCards))
        XCTAssertNotEqual(checksum(firstCards), 0)
    }

    private func fixture(_ name: String) throws -> Data {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: testsDirectory
            .appendingPathComponent("Fixtures/Lovelace/\(name).json"))
    }
}
