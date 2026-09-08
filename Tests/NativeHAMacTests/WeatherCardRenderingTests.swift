import AppKit
import SwiftUI
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class WeatherCardRenderingTests: XCTestCase {
    func testRequiredCurrentConditionFixturesRenderAtWideAndNarrowTwoX() throws {
        let fixtures: [(String, String?, [String: JSONValue], HAUnitSystem)] = [
            ("sunny-c", "sunny", attributes(temperature: .double(22.3), unit: "°C", humidity: .int(78)), .init(temperature: "°C", length: "km")),
            ("cloudy", "cloudy", attributes(temperature: .int(20), unit: "°C", humidity: .int(80)), .init(temperature: "°C", length: "km")),
            ("rainy", "rainy", attributes(temperature: .double(18.4), unit: "°C", humidity: .int(92)), .init(temperature: "°C", length: "km")),
            ("clear-night", "clear-night", attributes(temperature: .double(16.8), unit: "°C", humidity: .int(84)), .init(temperature: "°C", length: "km")),
            ("missing", nil, [:], .init(temperature: "°C", length: "km")),
            ("unknown", "unknown", [:], .init(temperature: "°C", length: "km")),
            ("unavailable", "unavailable", [:], .init(temperature: "°C", length: "km")),
            ("missing-attributes", "fog", [:], .init(temperature: "°C", length: "km")),
            ("fahrenheit", "partlycloudy", attributes(temperature: .double(72.25), unit: "°F", humidity: .int(65)), .init(temperature: "°F", length: "mi")),
        ]

        for (name, condition, attributes, units) in fixtures {
            for (width, height) in [(496.0, 150.0), (320.0, 190.0)] {
                let (model, card) = try modelAndCard(
                    condition: condition,
                    attributes: attributes,
                    unitSystem: units
                )
                let size = CGSize(width: width, height: height)
                let rendered = try MacViewPNGRenderer.render(
                    WeatherCard(card: card)
                        .environmentObject(model)
                        .frame(width: width, height: height)
                        .background(Color(red: 0.055, green: 0.06, blue: 0.06)),
                    size: size,
                    displayScale: 2,
                    settleTime: 0.02
                )
                XCTAssertTrue(rendered.pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]), name)
                XCTAssertGreaterThan(rendered.pngData.count, 3_000, name)
                XCTAssertGreaterThan(rendered.nonBackgroundSampleCount, 80, name)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered.pngData))
                XCTAssertEqual(bitmap.pixelsWide, Int(width * 2), name)
                XCTAssertEqual(bitmap.pixelsHigh, Int(height * 2), name)

                let presentation = WeatherPresentationResolver.resolve(
                    card: card,
                    state: card.entity.flatMap { model.states[$0] },
                    serverUnitSystem: units,
                    preferences: model.frontendLocalePreferences,
                    symbolAvailability: { _ in true }
                )
                XCTAssertFalse(presentation.name.isEmpty, name)
                XCTAssertFalse(presentation.condition.isEmpty, name)
                XCTAssertFalse(presentation.icon.semanticLabel.isEmpty, name)
                XCTAssertLessThanOrEqual(presentation.secondary == nil ? 0 : 1, 1, name)
                if condition == "rainy" {
                    XCTAssertGreaterThan(rendered.blueSampleCount, 2, name)
                }

                let artifactName = "weather-\(name)-\(Int(width)).png"
                try persist(rendered.pngData, name: artifactName)
                try ApprovedVisualReference.compareIfPresent(actualPNG: rendered.pngData, name: artifactName)
            }
        }
    }

    func testNativeActionTargetAccessibilityAndSentinelParity() throws {
        for (condition, expectedTarget, shouldEnable) in [
            (Optional<String>.none, "", false),
            (Optional("unknown"), "weather.home", true),
            (Optional("unavailable"), "weather.home", true),
            (Optional("sunny"), "weather.home", true),
        ] {
            let (model, card) = try modelAndCard(
                condition: condition,
                attributes: attributes(temperature: .double(22.3), unit: "°C", humidity: .int(78)),
                unitSystem: .init(temperature: "°C", length: "km")
            )
            let controls = try hostedControls(card: card, model: model)
            if shouldEnable {
                let button = try XCTUnwrap(controls.first)
                XCTAssertTrue(button.isEnabled)
                XCTAssertEqual(button.accessibilityLabel(), "Home weather")
                XCTAssertTrue((button.accessibilityValue() as? String)?.contains(condition!.capitalized) == true)
                button.actionHandler?()
                XCTAssertEqual(model.selectedEntityID, expectedTarget)
            } else {
                XCTAssertTrue(controls.isEmpty)
                XCTAssertNil(model.selectedEntityID)
            }
        }
    }

    func testExplicitMoreInfoTargetAndNoneAreReflectedByNativeControl() throws {
        let override = try modelAndCard(
            condition: "sunny",
            attributes: attributes(temperature: .int(22), unit: "°C", humidity: .int(70)),
            unitSystem: .init(temperature: "°C", length: "km"),
            additions: ["tap_action": .object([
                "action": .string("more-info"),
                "entity": .string("weather.outside"),
            ])]
        )
        let overrideButton = try XCTUnwrap(hostedControls(card: override.1, model: override.0).first)
        overrideButton.actionHandler?()
        XCTAssertEqual(override.0.selectedEntityID, "weather.outside")

        let none = try modelAndCard(
            condition: "sunny",
            attributes: attributes(temperature: .int(22), unit: "°C", humidity: .int(70)),
            unitSystem: .init(temperature: "°C", length: "km"),
            additions: ["tap_action": .object(["action": .string("none")])]
        )
        XCTAssertTrue(try hostedControls(card: none.1, model: none.0).isEmpty)
    }

    private func hostedControls(
        card: LovelacePresentationCard,
        model: DashboardViewModel
    ) throws -> [EntityPrimaryActionNSButton] {
        let size = CGSize(width: 496, height: 150)
        let hosting = NSHostingView(
            rootView: WeatherCard(card: card)
                .environmentObject(model)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        for _ in 0..<3 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        var controls: [EntityPrimaryActionNSButton] = []
        func collect(_ view: NSView) {
            if let button = view as? EntityPrimaryActionNSButton { controls.append(button) }
            for subview in view.subviews { collect(subview) }
        }
        collect(hosting)
        window.orderOut(nil)
        window.close()
        return controls
    }

    private func modelAndCard(
        condition: String?,
        attributes: [String: JSONValue],
        unitSystem: HAUnitSystem,
        additions: [String: JSONValue] = [:]
    ) throws -> (DashboardViewModel, LovelacePresentationCard) {
        var rawCard: [String: JSONValue] = [
            "type": .string("weather-forecast"),
            "entity": .string("weather.home"),
            "name": .string("Home weather"),
            "show_forecast": .bool(false),
        ]
        additions.forEach { rawCard[$0.key] = $0.value }
        let config = try LovelaceConfig(rawValue: .object([
            "views": .array([.object([
                "title": .string("Home"),
                "path": .string("default_view"),
                "cards": .array([.object(rawCard)]),
            ])]),
        ]))
        let states: [String: HAState]
        if let condition = condition {
            states = ["weather.home": HAState(
                entityId: "weather.home",
                state: condition,
                attributes: attributes
            )]
        } else {
            states = [:]
        }
        let model = DashboardViewModel(
            initialStates: states,
            initialViews: config.views,
            homeAssistantConfig: HAConfig(
                components: ["weather"],
                unitSystem: unitSystem
            ),
            frontendLocalePreferences: HAFrontendLocalePreferences(
                language: "en", numberFormat: "comma_decimal", timeFormat: "24",
                dateFormat: "language", firstWeekday: "language", timeZone: "server"
            )
        )
        return (model, try XCTUnwrap(model.homeCards.first))
    }

    private static func attributes(
        temperature: JSONValue,
        unit: String,
        humidity: JSONValue
    ) -> [String: JSONValue] {
        [
            "temperature": temperature,
            "temperature_unit": .string(unit),
            "humidity": humidity,
        ]
    }

    private func attributes(
        temperature: JSONValue,
        unit: String,
        humidity: JSONValue
    ) -> [String: JSONValue] {
        Self.attributes(temperature: temperature, unit: unit, humidity: humidity)
    }

    private func persist(_ data: Data, name: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/render-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
