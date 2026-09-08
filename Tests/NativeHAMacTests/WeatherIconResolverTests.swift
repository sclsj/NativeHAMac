import XCTest
@testable import NativeHAMac

final class WeatherIconResolverTests: XCTestCase {
    func testEveryStandardConditionHasAnIsolatedSymbolAndSemanticLabel() {
        let expected: [(String, String, String)] = [
            ("clear-night", "moon.stars.fill", "Clear night"),
            ("cloudy", "cloud.fill", "Cloudy"),
            ("fog", "cloud.fog.fill", "Fog"),
            ("hail", "cloud.hail.fill", "Hail"),
            ("lightning", "cloud.bolt.fill", "Lightning"),
            ("lightning-rainy", "cloud.bolt.rain.fill", "Lightning rainy"),
            ("partlycloudy", "cloud.sun.fill", "Partly cloudy"),
            ("pouring", "cloud.heavyrain.fill", "Pouring"),
            ("rainy", "cloud.rain.fill", "Rainy"),
            ("snowy", "cloud.snow.fill", "Snowy"),
            ("snowy-rainy", "cloud.sleet.fill", "Snowy rainy"),
            ("sunny", "sun.max.fill", "Sunny"),
            ("windy", "wind", "Windy"),
            ("windy-variant", "wind.circle.fill", "Windy variant"),
            ("exceptional", "exclamationmark.triangle.fill", "Exceptional"),
        ]

        for (condition, symbol, label) in expected {
            let result = WeatherIconResolver.resolve(condition: condition, symbolAvailability: { _ in true })
            XCTAssertEqual(result.symbolName, symbol, condition)
            XCTAssertEqual(result.semanticLabel, label, condition)
            XCTAssertNil(result.fallbackText, condition)
        }
    }

    func testUnknownConditionAndUnavailableSymbolsNeverFallBackToSunny() {
        let unknown = WeatherIconResolver.resolve(condition: "dust-storm", symbolAvailability: { $0 == "cloud.fill" })
        XCTAssertEqual(unknown.symbolName, "cloud.fill")
        XCTAssertEqual(unknown.semanticLabel, "Unknown weather condition")
        XCTAssertNotEqual(unknown.symbolName, "sun.max.fill")

        let noSymbols = WeatherIconResolver.resolve(condition: "sunny", symbolAvailability: { _ in false })
        XCTAssertNil(noSymbols.symbolName)
        XCTAssertEqual(noSymbols.fallbackText, "?")
        XCTAssertEqual(noSymbols.colorRole, .cloud)
    }

    func testMissingUnknownAndUnavailableUseIntentionalSentinelPresentations() {
        let available: (String) -> Bool = { _ in true }
        XCTAssertEqual(WeatherIconResolver.missing(symbolAvailability: available).semanticLabel, "Missing weather entity")
        XCTAssertEqual(WeatherIconResolver.unknown(symbolAvailability: available).symbolName, "questionmark.circle")
        XCTAssertEqual(
            WeatherIconResolver.unavailable(symbolAvailability: available).symbolName,
            "exclamationmark.triangle.fill"
        )
    }

    func testPreferredSymbolsResolveOnSupportedMacOS12Runtime() {
        let conditions = [
            "clear-night", "cloudy", "fog", "hail", "lightning", "lightning-rainy",
            "partlycloudy", "pouring", "rainy", "snowy", "snowy-rainy", "sunny",
            "windy", "windy-variant", "exceptional",
        ]
        for condition in conditions {
            let resolved = WeatherIconResolver.resolve(condition: condition)
            XCTAssertNotNil(resolved.symbolName, condition)
            XCTAssertNil(resolved.fallbackText, condition)
            if condition == "sunny" {
                XCTAssertEqual(resolved.symbolName, "sun.max.fill")
            }
        }
        XCTAssertNotNil(WeatherIconResolver.missing().symbolName)
        XCTAssertNotNil(WeatherIconResolver.unknown().symbolName)
        XCTAssertNotNil(WeatherIconResolver.unavailable().symbolName)
    }
}
