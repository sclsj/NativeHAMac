import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class WeatherCardIntegrationTests: XCTestCase {
    func testWeatherMilestoneAddsNoForecastCommandTaskOwnerOrPersistenceSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let weatherFiles = [
            "Sources/NativeHAMac/WeatherPresentation.swift",
            "Sources/NativeHAMac/WeatherIconResolver.swift",
        ]
        for relativePath in weatherFiles {
            let source = try String(
                contentsOf: root.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertFalse(source.contains("weather/subscribe_forecast"), relativePath)
            XCTAssertFalse(source.contains("Task<"), relativePath)
            XCTAssertFalse(source.contains("Task {"), relativePath)
            XCTAssertFalse(source.contains("UserDefaults"), relativePath)
            XCTAssertFalse(source.contains("@AppStorage"), relativePath)
            XCTAssertFalse(source.contains("ForecastStore"), relativePath)
        }
    }

    func testAuthorizedReadOnlyLiveCurrentWeatherSmoke() async throws {
        guard ProcessInfo.processInfo.environment["NATIVEHA_RUN_LIVE_WEATHER_SMOKE"] == "1" else {
            throw XCTSkip("Set NATIVEHA_RUN_LIVE_WEATHER_SMOKE=1 for the authorized read-only weather smoke")
        }
        let token = try String(
            contentsOfFile: "/Users/jin/Documents/Computer/ha_apikey.txt",
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLs = [
            "http://joyj.me:8123", "http://172.20.200.123:8123", "http://192.168.71.18:8123",
        ].compactMap(URL.init(string:))
        var accepted: (HomeAssistantConfiguration, HAConfig, [HAState])?
        for baseURL in baseURLs {
            let configuration = HomeAssistantConfiguration(
                baseURL: baseURL,
                accessToken: token,
                timeout: 12
            )
            let rest = HomeAssistantRESTClient(configuration: configuration)
            if let config = try? await rest.fetchConfig(),
               let states = try? await rest.fetchStates()
            {
                accepted = (configuration, config, states)
                break
            }
        }
        let (configuration, serverConfig, states) = try XCTUnwrap(accepted)
        XCTAssertTrue(serverConfig.components.contains("weather"))
        let weatherStates = states.filter { $0.entityId.hasPrefix("weather.") }
        XCTAssertFalse(weatherStates.isEmpty)

        let client = HomeAssistantWebSocketClient(configuration: configuration)
        try await client.connect()
        let lovelace = try await client.fetchLovelaceConfig()
        await client.disconnect()
        let configAfter = try await HomeAssistantRESTClient(configuration: configuration).fetchConfig()
        XCTAssertEqual(configAfter, serverConfig)
        let weatherCards = LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: lovelace)
        ).views.flatMap(\.cards).filter { $0.type == "weather-forecast" }
        XCTAssertEqual(weatherCards.count, 3)
        XCTAssertEqual(Set(weatherCards.compactMap(\.entity)).count, 1)
        let stateMap = Dictionary(uniqueKeysWithValues: states.map { ($0.entityId, $0) })
        var summaries: [String] = []
        for card in weatherCards {
            let result = WeatherPresentationResolver.resolve(
                card: card,
                state: card.entity.flatMap { stateMap[$0] },
                serverUnitSystem: serverConfig.unitSystem,
                preferences: nil
            )
            XCTAssertFalse(result.condition.isEmpty)
            XCTAssertFalse(result.name.isEmpty)
            XCTAssertTrue(result.rendersCurrent)
            XCTAssertEqual(result.configuration.showForecast, false)
            XCTAssertNotNil(result.temperature)
            summaries.append("\(result.condition)|\(result.temperature ?? "missing")")
        }
        print("MODULE07_LIVE cards=\(weatherCards.count) entities=\(Set(weatherCards.compactMap(\.entity)).count) values=\(Set(summaries).sorted().joined(separator: ",")) config_unchanged=true commands=get_config|lovelace/config")
    }

    func testStateUpdateChangesOnlyTheMatchingWeatherCardPresentation() throws {
        let cards = try weatherCards([
            ("weather.inside", "Inside"),
            ("weather.outside", "Outside"),
        ])
        let model = DashboardViewModel(
            initialStates: [
                "weather.inside": state("weather.inside", "cloudy", 21),
                "weather.outside": state("weather.outside", "sunny", 27),
            ],
            initialViews: [LovelaceView(
                title: "Home", path: "default_view", cards: cards.map(\.source)
            )],
            homeAssistantConfig: HAConfig(
                components: ["weather"],
                unitSystem: HAUnitSystem(temperature: "°C", length: "km")
            )
        )
        let initial = model.homeCards.map { presentation($0, model: model) }

        model.states["weather.inside"] = state("weather.inside", "rainy", 19)
        let updated = model.homeCards.map { presentation($0, model: model) }

        XCTAssertNotEqual(initial[0], updated[0])
        XCTAssertEqual(initial[1], updated[1])
        XCTAssertEqual(updated[0].condition, "Rainy")
        XCTAssertEqual(updated[0].temperature, "19 °C")
        XCTAssertEqual(updated[1].condition, "Sunny")
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().startupCount, 0)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 0)
    }

    func testDuplicateCardsShareAcceptedStateButKeepDistinctModule04Identity() throws {
        let raw: JSONValue = .object([
            "type": .string("weather-forecast"),
            "entity": .string("weather.home"),
            "show_forecast": .bool(false),
        ])
        let config = try LovelaceConfig(rawValue: .object([
            "views": .array([.object([
                "title": .string("Home"),
                "path": .string("default_view"),
                "cards": .array([raw, raw]),
            ])]),
        ]))
        let model = DashboardViewModel(
            initialStates: ["weather.home": state("weather.home", "partlycloudy", 22.3)],
            initialViews: config.views,
            homeAssistantConfig: HAConfig(unitSystem: HAUnitSystem(temperature: "°C", length: "km"))
        )
        let cards = model.homeCards
        XCTAssertEqual(cards.count, 2)
        XCTAssertNotEqual(cards[0].identity, cards[1].identity)
        XCTAssertNotEqual(cards[0].nativeID, cards[1].nativeID)
        let left = presentation(cards[0], model: model)
        let right = presentation(cards[1], model: model)
        XCTAssertEqual(left.condition, right.condition)
        XCTAssertEqual(left.temperature, right.temperature)
        XCTAssertNotEqual(left.cardIdentity, right.cardIdentity)
    }

    func testRepeatedWeatherViewSwitchesCreateNoForecastOrRenderOwners() async throws {
        let source = LovelaceCard(type: "weather-forecast", entity: "weather.home", showForecast: false)
        let model = DashboardViewModel(
            initialStates: ["weather.home": state("weather.home", "cloudy", 20)],
            initialViews: [
                LovelaceView(title: "A", path: "a", cards: [source]),
                LovelaceView(title: "B", path: "b", cards: [source]),
            ]
        )
        let identities = model.presentationDashboard.views.map(\.resolved.identity)
        for index in 0..<40 {
            await model.selectViewForTesting(identities[index % identities.count])
            let snapshot = model.dashboardOwnerSnapshotForTesting()
            XCTAssertTrue(snapshot.subscriptionKeys.isEmpty)
            XCTAssertTrue(snapshot.generationKeys.isEmpty)
            XCTAssertEqual(snapshot.startupCount, 0)
            XCTAssertEqual(snapshot.mountedOwnerCount, 0)
            XCTAssertTrue(snapshot.desiredDetailHistoryKeys.isEmpty)
            XCTAssertEqual(snapshot.detailStartupCount, 0)
            XCTAssertEqual(snapshot.serviceTaskCount, 0)
            XCTAssertEqual(snapshot.dashboardOwnerNodeCount, 0)
            // Module 12's serialized owner tail may remain as a completed
            // bookkeeping task; weather adds no node/startup/subscription.
        }
    }

    func testPresenterAndModelReleaseWithoutWeatherRetention() throws {
        weak var weakModel: DashboardViewModel?
        autoreleasepool {
            var model: DashboardViewModel? = DashboardViewModel(
                initialStates: ["weather.home": state("weather.home", "sunny", 24)],
                initialViews: [LovelaceView(
                    title: "Home", path: "default_view",
                    cards: [LovelaceCard(type: "weather-forecast", entity: "weather.home")]
                )]
            )
            weakModel = model
            _ = presentation(model!.homeCards[0], model: model!)
            model = nil
        }
        XCTAssertNil(weakModel)
    }

    private func presentation(
        _ card: LovelacePresentationCard,
        model: DashboardViewModel
    ) -> WeatherCardPresentation {
        WeatherPresentationResolver.resolve(
            card: card,
            state: card.entity.flatMap { model.states[$0] },
            serverUnitSystem: model.homeAssistantConfig?.unitSystem,
            preferences: model.frontendLocalePreferences,
            symbolAvailability: { _ in true }
        )
    }

    private func state(_ entityID: String, _ condition: String, _ temperature: Double) -> HAState {
        HAState(
            entityId: entityID,
            state: condition,
            attributes: [
                "temperature": .double(temperature),
                "temperature_unit": .string("°C"),
                "humidity": .int(70),
            ]
        )
    }

    private func weatherCards(_ specifications: [(String, String)]) throws -> [LovelacePresentationCard] {
        let config = try LovelaceConfig(rawValue: .object([
            "views": .array([.object([
                "title": .string("Home"),
                "path": .string("default_view"),
                "cards": .array(specifications.map { entity, name in
                    .object([
                        "type": .string("weather-forecast"),
                        "entity": .string(entity),
                        "name": .string(name),
                    ])
                }),
            ])]),
        ]))
        return LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        ).views[0].cards
    }
}
