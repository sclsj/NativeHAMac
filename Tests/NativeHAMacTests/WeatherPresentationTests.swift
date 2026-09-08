import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class WeatherPresentationTests: XCTestCase {
    private let english = HAFrontendLocalePreferences(
        language: "en", numberFormat: "comma_decimal", timeFormat: "24",
        dateFormat: "language", firstWeekday: "language", timeZone: "server"
    )

    func testCurrentConditionNameTemperatureAndImplicitHumidity() throws {
        let card = try weatherCard(["name": .string("Kitchen weather")])
        let state = HAState(
            entityId: "weather.home",
            state: "partlycloudy",
            attributes: [
                "friendly_name": .string("Ignored friendly name"),
                "temperature": .string("22.356"),
                "temperature_unit": .string("°C"),
                "humidity": .int(78),
            ]
        )
        let result = resolve(card, state: state)

        XCTAssertEqual(result.stateKind, .current)
        XCTAssertEqual(result.name, "Kitchen weather")
        XCTAssertEqual(result.condition, "Partly cloudy")
        XCTAssertEqual(result.icon.symbolName, "cloud.sun.fill")
        XCTAssertEqual(result.temperature, "22.36 °C")
        XCTAssertEqual(result.secondary, WeatherSecondaryPresentation(
            attribute: "humidity", label: "Humidity", value: "78%"
        ))
        XCTAssertEqual(result.primaryAction, .details(entityID: "weather.home"))
        XCTAssertTrue(result.rendersCurrent)
    }

    func testIntegerDoubleNumericStringAndMalformedTemperatureAreRecoverable() throws {
        let card = try weatherCard()
        let values: [(JSONValue, String?)] = [
            (.int(21), "21 °C"),
            (.double(21.5), "21.5 °C"),
            (.string("21.25"), "21.25 °C"),
            (.string("not-a-number"), "not-a-number °C"),
            (.null, nil),
            (.array([.int(21)]), nil),
            (.object(["value": .int(21)]), nil),
        ]
        for (value, expected) in values {
            let state = HAState(
                entityId: "weather.home", state: "sunny",
                attributes: ["temperature": value, "temperature_unit": .string("°C")]
            )
            XCTAssertEqual(resolve(card, state: state).temperature, expected, "\(value)")
        }
    }

    func testTemperatureUnitPrecedenceRoundingAndLocalePolicy() throws {
        let entityUnit = HAState(
            entityId: "weather.home", state: "sunny",
            attributes: ["temperature": .double(22.65), "temperature_unit": .string("K")]
        )
        XCTAssertEqual(
            resolve(try weatherCard(), state: entityUnit, units: HAUnitSystem(temperature: "°F", length: "mi")).temperature,
            "22.65 K"
        )
        XCTAssertEqual(
            resolve(
                try weatherCard(["round_temperature": .bool(true)]),
                state: entityUnit,
                units: HAUnitSystem(temperature: "°F", length: "mi")
            ).temperature,
            "23 K"
        )

        let serverUnit = HAState(
            entityId: "weather.home", state: "sunny",
            attributes: ["temperature": .double(72.125)]
        )
        XCTAssertEqual(
            resolve(try weatherCard(), state: serverUnit, units: HAUnitSystem(temperature: "°F", length: "mi")).temperature,
            "72.12 °F"
        )

        let french = HAFrontendLocalePreferences(
            language: "fr", numberFormat: "decimal_comma", timeFormat: "24",
            dateFormat: "language", firstWeekday: "language", timeZone: "server"
        )
        let humidity = try weatherCard(["secondary_info_attribute": .string("humidity")])
        let localized = WeatherPresentationResolver.resolve(
            card: humidity,
            state: HAState(entityId: "weather.home", state: "cloudy", attributes: ["humidity": .double(78.5)]),
            serverUnitSystem: HAUnitSystem(temperature: "°C", length: "km"),
            preferences: french,
            symbolAvailability: { _ in true }
        )
        XCTAssertEqual(localized.secondary?.value, "78,5 %")
    }

    func testExplicitSecondaryAttributeFormatsWeatherUnitsAndFallbacks() throws {
        let units = HAUnitSystem(temperature: "°C", length: "km")
        let state = HAState(
            entityId: "weather.home", state: "rainy",
            attributes: [
                "humidity": .double(70.4),
                "pressure": .double(1010.55),
                "visibility": .int(12),
                "precipitation": .double(1.25),
                "wind_speed": .double(10.8),
                "wind_bearing": .double(2.8),
                "apparent_temperature": .double(20.7),
                "custom_text": .string("moderate"),
            ]
        )
        let expected: [(String, String)] = [
            ("humidity", "70.4%"),
            ("pressure", "1,010.55 hPa"),
            ("visibility", "12 km"),
            ("precipitation", "1.25 mm"),
            ("wind_speed", "10.8 km/h (N)"),
            ("apparent_temperature", "20.7 °C"),
            ("custom_text", "moderate"),
        ]
        for (attribute, value) in expected {
            let result = resolve(
                try weatherCard(["secondary_info_attribute": .string(attribute)]),
                state: state,
                units: units
            )
            XCTAssertEqual(result.secondary?.value, value, attribute)
        }

        for value in [JSONValue.null, .object(["bad": .bool(true)]), .array([])] {
            let malformed = HAState(
                entityId: "weather.home", state: "rainy",
                attributes: ["pressure": value]
            )
            XCTAssertEqual(
                resolve(
                    try weatherCard(["secondary_info_attribute": .string("pressure")]),
                    state: malformed,
                    units: units
                ).secondary?.value,
                "Unknown"
            )
        }
        XCTAssertEqual(
            resolve(
                try weatherCard(["secondary_info_attribute": .string("pressure")]),
                state: HAState(entityId: "weather.home", state: "rainy"),
                units: units
            ).secondary?.value,
            "Unknown"
        )
        XCTAssertEqual(
            resolve(
                try weatherCard(["secondary_info_attribute": .string("wind_speed")]),
                state: HAState(entityId: "weather.home", state: "windy"),
                units: units
            ).secondary?.value,
            "-"
        )
    }

    func testWindDistinguishesMissingNullMalformedAndIndependentBearing() throws {
        let card = try weatherCard(["secondary_info_attribute": .string("wind_speed")])
        let metric = HAUnitSystem(temperature: "°C", length: "km")

        for attributes in [
            ["wind_bearing": JSONValue.int(2)],
            ["wind_speed": JSONValue.null, "wind_bearing": .string("2.8")],
        ] {
            let result = resolve(
                card,
                state: HAState(entityId: "weather.home", state: "windy", attributes: attributes),
                units: metric
            )
            XCTAssertEqual(result.secondary?.value, "- (N)")
        }

        for (bearing, expected) in [(nil, "gusty"), (JSONValue.int(2), "gusty (N)")] {
            var attributes = ["wind_speed": JSONValue.string("gusty")]
            attributes["wind_bearing"] = bearing
            let malformedString = resolve(
                card,
                state: HAState(
                    entityId: "weather.home", state: "windy",
                    attributes: attributes
                ),
                units: metric
            )
            XCTAssertEqual(malformedString.secondary?.value, expected)
        }

        for malformed in [
            JSONValue.object(["value": .int(10)]),
            .array([.int(10)]),
            .double(.infinity),
        ] {
            let result = resolve(
                card,
                state: HAState(
                    entityId: "weather.home", state: "windy",
                    attributes: ["wind_speed": malformed]
                ),
                units: metric
            )
            XCTAssertEqual(result.secondary?.value, "Unknown")
        }
    }

    func testWindMissingOrEmptyServerLengthRetainsExactSlashHUnit() throws {
        let card = try weatherCard(["secondary_info_attribute": .string("wind_speed")])
        let state = HAState(
            entityId: "weather.home", state: "windy",
            attributes: ["wind_speed": .int(10)]
        )
        for units in [
            HAUnitSystem(temperature: "°C", length: nil),
            HAUnitSystem(temperature: "°C", length: ""),
        ] {
            XCTAssertEqual(resolve(card, state: state, units: units).secondary?.value, "10 /h")
        }
    }

    func testAllShowFlagCombinationsRenderCurrentAndPreserveForecastFieldsInertly() throws {
        for showCurrent in [false, true] {
            for showForecast in [false, true] {
                let card = try weatherCard([
                    "show_current": .bool(showCurrent),
                    "show_forecast": .bool(showForecast),
                    "forecast_type": .string("hourly"),
                    "forecast_slots": .int(-3),
                ])
                let result = resolve(
                    card,
                    state: HAState(entityId: "weather.home", state: "cloudy")
                )
                XCTAssertTrue(result.rendersCurrent)
                XCTAssertEqual(result.configuration.showCurrent, showCurrent)
                XCTAssertEqual(result.configuration.showForecast, showForecast)
                XCTAssertEqual(result.configuration.forecastType, "hourly")
                XCTAssertEqual(result.configuration.forecastSlots, -3)
            }
        }
        XCTAssertTrue(resolve(
            try weatherCard(),
            state: HAState(entityId: "weather.home", state: "sunny")
        ).rendersCurrent)
    }

    func testMissingUnknownAndUnavailableUseExactActionMatrix() throws {
        let card = try weatherCard()
        let missing = resolve(card, state: nil)
        XCTAssertEqual(missing.stateKind, .missing)
        XCTAssertEqual(missing.condition, "Missing entity: weather.home")
        XCTAssertEqual(missing.primaryAction, .none)
        XCTAssertFalse(missing.isActionable)

        for sentinel in ["unknown", "unavailable"] {
            let result = resolve(
                card,
                state: HAState(entityId: "weather.home", state: sentinel)
            )
            XCTAssertEqual(result.condition, sentinel == "unknown" ? "Unknown" : "Unavailable")
            XCTAssertEqual(result.primaryAction, .details(entityID: "weather.home"))
            XCTAssertTrue(result.isActionable)
            XCTAssertNotEqual(result.icon.symbolName, "sun.max.fill")
        }
    }

    func testDetailsOverrideNoneAndMalformedUnsupportedActionsNeverFallThrough() throws {
        let state = HAState(entityId: "weather.home", state: "sunny")
        XCTAssertEqual(resolve(try weatherCard(), state: state).primaryAction, .details(entityID: "weather.home"))
        XCTAssertEqual(
            resolve(try weatherCard(["tap_action": .object([
                "action": .string("more-info"), "entity": .string("weather.outside"),
            ])]), state: state).primaryAction,
            .details(entityID: "weather.outside")
        )
        XCTAssertEqual(
            resolve(try weatherCard(["tap_action": .object(["action": .string("none")])]), state: state).primaryAction,
            .none
        )
        let unsupportedActions: [JSONValue] = [
            .string("more-info"),
            .object([:]),
            .object(["action": .string("navigate")]),
            .object(["action": .string("more-info"), "entity": .int(7)]),
            .object(["action": .string("more-info"), "confirmation": .object([:])]),
        ]
        for action in unsupportedActions {
            let result = resolve(try weatherCard(["tap_action": action]), state: state)
            XCTAssertEqual(result.primaryAction, .unsupported, "\(action)")
            XCTAssertFalse(result.isActionable)
            XCTAssertTrue(result.warningText?.contains("tap_action") == true)
        }
    }

    func testStructuredNameUsesExistingFallbackAndKeepsRawIdentityAndDiagnostic() throws {
        let structured: JSONValue = .object(["type": .string("entity")])
        let card = try weatherCard(["name": structured])
        let result = resolve(
            card,
            state: HAState(
                entityId: "weather.home", state: "clear-night",
                attributes: ["friendly_name": .string("Home forecast")]
            )
        )
        XCTAssertEqual(result.name, "Home forecast")
        XCTAssertEqual(result.configuration.rawName, structured)
        XCTAssertEqual(result.cardIdentity, card.identity)
        XCTAssertTrue(result.warningText?.contains("unsupported structured weather name") == true)
        XCTAssertNil(card.source.diagnostic)
    }

    func testConditionLabelsAreFiniteAndUnknownFallbackIsCleaned() throws {
        let conditions = [
            "clear-night", "cloudy", "fog", "hail", "lightning", "lightning-rainy",
            "partlycloudy", "pouring", "rainy", "snowy", "snowy-rainy", "sunny",
            "windy", "windy-variant", "exceptional",
        ]
        XCTAssertEqual(conditions.map(WeatherPresentationResolver.conditionLabel), [
            "Clear night", "Cloudy", "Fog", "Hail", "Lightning", "Lightning rainy",
            "Partly cloudy", "Pouring", "Rainy", "Snowy", "Snowy rainy", "Sunny",
            "Windy", "Windy variant", "Exceptional",
        ])
        XCTAssertEqual(WeatherPresentationResolver.conditionLabel("dust_storm"), "Dust storm")
    }

    private func resolve(
        _ card: LovelacePresentationCard,
        state: HAState?,
        units: HAUnitSystem = HAUnitSystem(temperature: "°C", length: "km")
    ) -> WeatherCardPresentation {
        WeatherPresentationResolver.resolve(
            card: card,
            state: state,
            serverUnitSystem: units,
            preferences: english,
            symbolAvailability: { _ in true }
        )
    }

    private func weatherCard(_ additions: [String: JSONValue] = [:]) throws -> LovelacePresentationCard {
        var rawCard: [String: JSONValue] = [
            "type": .string("weather-forecast"),
            "entity": .string("weather.home"),
        ]
        additions.forEach { rawCard[$0.key] = $0.value }
        let root: JSONValue = .object([
            "views": .array([.object([
                "title": .string("Weather"),
                "path": .string("default_view"),
                "cards": .array([.object(rawCard)]),
            ])]),
        ])
        let config = try JSONDecoder().decode(
            LovelaceConfig.self,
            from: JSONEncoder().encode(root)
        )
        return LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        ).views[0].cards[0]
    }
}
