import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class LovelacePresentationTests: XCTestCase {
    func testDefaultPresentationIsSeparateAndPreservesRawMaintenanceViews() throws {
        let config = try fixtureConfig("representative-dashboard")
        let originalRaw = config.rawValue
        let resolved = LovelaceResolvedDashboard(source: config)
        let presentation = LovelacePresentationDashboard(resolved: resolved)

        XCTAssertEqual(config.rawValue, originalRaw)
        XCTAssertEqual(presentation.resolved.source.rawValue, originalRaw)
        XCTAssertEqual(presentation.views.map { $0.resolved.source.path }, ["default_view", "home_3h", "home_12h"])
        XCTAssertEqual(config.views[0].cards.count, 5, "Source vertical stack must remain present")
        XCTAssertEqual(presentation.views[0].cards.count, 7, "Only default_view flattens the vertical stack")
        XCTAssertEqual(
            presentation.views[0].cards.suffix(3).map { $0.identity.sourcePath.description },
            [
                "views[0].cards[4].cards[0]",
                "views[0].cards[4].cards[1]",
                "views[0].cards[4].cards[2]",
            ]
        )
        XCTAssertEqual(presentation.views[1].resolved.source.rawValue, config.views[1].rawValue)
        XCTAssertEqual(presentation.views[2].resolved.source.rawValue, config.views[2].rawValue)
    }

    func testHiddenAndSyntheticRowsDoNotMutateOrRenumberSourceRows() {
        let source = LovelaceCard(
            type: "entities",
            title: "AC Unit Controller",
            entities: [
                LovelaceEntityRef(entity: "sensor.humidity_temp_humidity"),
                LovelaceEntityRef(entity: "sensor.kept"),
            ]
        )
        let config = LovelaceConfig(views: [
            LovelaceView(title: "Home", path: "default_view", cards: [source]),
        ])
        let presentation = LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        )
        let card = presentation.views[0].cards[0]
        XCTAssertEqual(config.views[0].cards[0].entities?.map(\.entity), [
            "sensor.humidity_temp_humidity", "sensor.kept",
        ])
        XCTAssertEqual(card.rows?.map { $0.source.entity }, ["climate.room_ac", "sensor.kept"])
        XCTAssertEqual(card.rows?.last?.identity.sourcePath.description, "views[0].cards[0].entities[1]")
        XCTAssertEqual(card.rows?.first?.identity.sourcePath.description, "views[0].cards[0].synthetic_entities[0]")
    }

    func testDashboardWithoutActualDefaultViewUsesOneUnfilteredSourceColumn() throws {
        let source = LovelaceCard(
            type: "entities",
            title: "AC Unit Controller",
            entities: [
                LovelaceEntityRef(entity: "sensor.humidity_temp_humidity"),
                LovelaceEntityRef(entity: "sensor.kept"),
            ]
        )
        let history = LovelaceCard(
            type: "history-graph",
            entities: [LovelaceEntityRef(entity: "sensor.humidity_temp_humidity")]
        )
        let model = DashboardViewModel(initialViews: [
            LovelaceView(title: "Unrelated", path: "unrelated", cards: [source, history]),
        ])

        XCTAssertEqual(model.dashboardColumns.count, 1)
        XCTAssertEqual(model.dashboardColumns[0].count, 2)
        XCTAssertEqual(model.homeCards[0].rows?.map { $0.source.entity }, [
            "sensor.humidity_temp_humidity", "sensor.kept",
        ])
        XCTAssertEqual(
            model.historyEntityIDs(for: model.homeCards[1]),
            ["sensor.humidity_temp_humidity"]
        )
    }

    func testRawHoursAndWeatherFalseRemainDistinctFromEffectivePolicyAndAbsence() throws {
        let config = try fixtureConfig("representative-dashboard")
        let model = DashboardViewModel(initialViews: config.views)
        let history = try XCTUnwrap(model.homeCards.first { $0.type == "history-graph" })
        let weather = try XCTUnwrap(model.homeCards.first { $0.type == "weather-forecast" })
        XCTAssertEqual(history.hoursToShow, 12)
        XCTAssertEqual(model.historyEntityIDs(for: history), ["sensor.history"])
        XCTAssertEqual(history.rows?.filter { $0.source.diagnostic != nil }.count, 1)
        XCTAssertEqual(model.selectedGraphHours, AppConfig.graphTimeRangePolicy.defaultSelection.hours)
        XCTAssertEqual(weather.showForecast, false)
        XCTAssertNil(LovelaceCard(type: "weather-forecast").showForecast)
    }

    func testMalformedPresentationKeepsLocalPlaceholdersAndValidSiblings() throws {
        let config = try fixtureConfig("malformed-configurations")
        let presentation = LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        )
        let cards = presentation.views[1].cards
        XCTAssertEqual(cards.count, 12)
        XCTAssertEqual(cards.first?.content, "valid before")
        XCTAssertEqual(cards.last?.content, "valid after")
        XCTAssertEqual(cards.filter { $0.source.diagnostic != nil }.count, 9)
        XCTAssertEqual(cards[4].rows?.count, 4)
        XCTAssertEqual(cards[4].rows?.filter { $0.source.diagnostic != nil }.count, 2)
    }

    func testIdenticalPresentationKeepsExactCardIdentity() throws {
        let config = try fixtureConfig("representative-dashboard")
        let left = LovelacePresentationDashboard(resolved: LovelaceResolvedDashboard(source: config))
        let right = LovelacePresentationDashboard(resolved: LovelaceResolvedDashboard(source: config))
        XCTAssertEqual(left, right)
        XCTAssertEqual(left.views[0].cards.map(\.identity), right.views[0].cards.map(\.identity))
    }

    func testRepeatedFiveHundredCardReplacementAndDiscardKeepsOnlyCurrentTree() async {
        let model = DashboardViewModel()
        for revision in 0..<20 {
            let config = try! JSONDecoder().decode(
                LovelaceConfig.self,
                from: largeFixtureData(revision: revision)
            )
            await model.applyLovelaceConfigForTesting(config)
            XCTAssertEqual(recursiveResolvedCardCount(model.presentationDashboard.resolved), 500)
            XCTAssertTrue(model.histories.isEmpty)
            XCTAssertTrue(model.historyStatuses.isEmpty)
            XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 0)
        }
        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        XCTAssertTrue(model.views.isEmpty)
        XCTAssertTrue(model.presentationDashboard.views.isEmpty)
        XCTAssertTrue(model.histories.isEmpty)
        XCTAssertTrue(model.historyStatuses.isEmpty)
    }

    func testFiveHundredCardColdDecodePerformanceCanBeMeasured() throws {
        let data = try largeFixtureData()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let config = try! JSONDecoder().decode(LovelaceConfig.self, from: data)
            XCTAssertEqual(recursiveSourceCardCount(config), 500)
        }
    }

    func testFiveHundredCardResolveAndPresentationPerformanceCanBeMeasured() throws {
        let config = try JSONDecoder().decode(LovelaceConfig.self, from: largeFixtureData())
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let presentation = LovelacePresentationDashboard(
                resolved: LovelaceResolvedDashboard(source: config)
            )
            XCTAssertEqual(recursiveResolvedCardCount(presentation.resolved), 500)
        }
    }

    private func fixtureConfig(_ name: String) throws -> LovelaceConfig {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: testsDirectory
            .appendingPathComponent("Fixtures/Lovelace/\(name).json"))
        return try JSONDecoder().decode(LovelaceConfig.self, from: data)
    }

    private func largeFixtureData(revision: Int = 0) throws -> Data {
        func leaf(view: Int, index: Int) -> JSONValue {
            switch index % 4 {
            case 0:
                return .object([
                    "type": .string("entities"),
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
                    "title": .string("Revision \(revision)"),
                ])
            case 2:
                return .object([
                    "type": .string("weather-forecast"),
                    "entity": .string("weather.\(view)_\(index)"),
                ])
            default:
                return .object([
                    "type": .string("markdown"),
                    "content": .string("Revision \(revision) value \(view)-\(index)"),
                ])
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
        return try JSONEncoder().encode(JSONValue.object(["views": .array(rawViews)]))
    }

    private func recursiveSourceCardCount(_ config: LovelaceConfig) -> Int {
        func count(_ cards: [LovelaceCard]) -> Int {
            cards.reduce(0) { $0 + 1 + count($1.cards ?? []) }
        }
        return config.views.reduce(0) { $0 + count($1.cards) }
    }

    private func recursiveResolvedCardCount(_ dashboard: LovelaceResolvedDashboard) -> Int {
        func count(_ cards: [LovelaceResolvedCard]) -> Int {
            cards.reduce(0) { $0 + 1 + count($1.cards ?? []) }
        }
        return dashboard.views.reduce(0) { $0 + count($1.cards) }
    }
}
