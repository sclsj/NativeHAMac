import AppKit
import SwiftUI
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class WeatherDetailRenderingTests: XCTestCase {
    func testRequiredWeatherDetailFixturesRenderAtProductionAndNarrowSizes() throws {
        let fixtures: [(name: String, state: HAState, selected: HAWeatherForecastType?)] = [
            ("daily", state(condition: "partlycloudy", features: 3, forecast: dailyForecast(6)), nil),
            ("hourly", state(condition: "rainy", features: 3, forecast: hourlyForecast(48)), .hourly),
            ("loading", state(condition: "cloudy", features: 3, forecast: nil), nil),
            ("terminal-loading", state(condition: "fog", features: 1, forecast: .array([])), nil),
            ("sparse", state(condition: "sunny", features: 1, forecast: dailyForecast(6), sparse: true), nil),
            ("unknown", state(condition: "unknown", features: 1, forecast: dailyForecast(6)), nil),
            ("unavailable", state(condition: "unavailable", features: 1, forecast: dailyForecast(6)), nil),
        ]

        for fixture in fixtures {
            let model = model(for: fixture.state)
            model.openDetails(entityID: fixture.state.entityId)
            if let selected = fixture.selected {
                model.selectWeatherForecastType(selected)
            }
            let presentation = try XCTUnwrap(model.weatherDetailPresentation(
                now: ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
            ))
            XCTAssertFalse(presentation.condition.isEmpty, fixture.name)
            XCTAssertTrue(presentation.timestampHelp.contains("Last updated"), fixture.name)
            if fixture.name == "hourly" {
                XCTAssertEqual(presentation.forecast?.itemCount, 48)
            } else if fixture.name == "loading" || fixture.name == "terminal-loading" {
                XCTAssertTrue(presentation.forecast?.isLoading == true)
            } else {
                XCTAssertEqual(presentation.forecast?.itemCount, 6)
            }

            let full = try MacViewPNGRenderer.render(
                EntityDetailSheet(entityID: fixture.state.entityId)
                    .environmentObject(model),
                size: CGSize(width: 520, height: 620),
                displayScale: 2,
                settleTime: 0.04
            )
            try assertPNG(full, width: 520, height: 620, name: fixture.name)
            try persist(full.pngData, name: "weather-detail-\(fixture.name)-520x620.png")

            let narrow = try MacViewPNGRenderer.render(
                ScrollView {
                    WeatherDetailView(
                        state: fixture.state,
                        coordinator: model.weatherDetailCoordinator,
                        now: { ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")! },
                        cadenceNanoseconds: 60_000_000_000
                    )
                    .environmentObject(model)
                    .padding(18)
                }
                .frame(width: 360, height: 620)
                .background(Color(red: 0.09, green: 0.095, blue: 0.1)),
                size: CGSize(width: 360, height: 620),
                displayScale: 2,
                settleTime: 0.04
            )
            try assertPNG(narrow, width: 360, height: 620, name: "\(fixture.name)-narrow")
            try persist(narrow.pngData, name: "weather-detail-\(fixture.name)-360x620.png")
        }
    }

    func testForecastTabSelectionUsesTheNativeModelRoute() throws {
        let fixture = state(condition: "partlycloudy", features: 3, forecast: dailyForecast(6))
        let model = model(for: fixture)
        model.openDetails(entityID: fixture.entityId)
        XCTAssertEqual(model.weatherDetailCoordinator.supportedTypes, [.daily, .hourly])
        XCTAssertEqual(model.weatherDetailCoordinator.selectedType, .daily)

        model.selectWeatherForecastType(.hourly)
        XCTAssertEqual(model.weatherDetailCoordinator.selectedType, .hourly)
    }

    func testRelativeTimeCadenceRunsOnlyWhileDetailBodyIsVisible() {
        let fixture = state(condition: "partlycloudy", features: 3, forecast: dailyForecast(6))
        let model = model(for: fixture)
        model.openDetails(entityID: fixture.entityId)
        let counter = WeatherDetailNowCounter()
        var window: NSWindow? = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window?.isReleasedWhenClosed = false
        do {
            let hosting = NSHostingView(
                rootView: WeatherDetailView(
                    state: fixture,
                    coordinator: model.weatherDetailCoordinator,
                    now: {
                        counter.increment()
                        return ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
                    },
                    cadenceNanoseconds: 5_000_000
                )
                .environmentObject(model)
                .frame(width: 480, height: 540)
            )
            window?.contentView = hosting
            window?.orderBack(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
            XCTAssertGreaterThanOrEqual(counter.value, 3)
            window?.contentView = nil
        }
        window?.close()
        window = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        let afterDisappearance = counter.value
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        XCTAssertEqual(counter.value, afterDisappearance)
    }

    private func model(for state: HAState) -> DashboardViewModel {
        DashboardViewModel(
            initialStates: [state.entityId: state],
            homeAssistantConfig: .init(
                timeZone: "Asia/Shanghai",
                unitSystem: .init(temperature: "°C", length: "km")
            ),
            frontendLocalePreferences: .init(
                language: "en_US_POSIX",
                numberFormat: "comma_decimal",
                timeFormat: "24",
                dateFormat: "language",
                firstWeekday: "monday",
                timeZone: "Asia/Shanghai"
            )
        )
    }

    private func state(
        condition: String,
        features: Int,
        forecast: JSONValue?,
        sparse: Bool = false
    ) -> HAState {
        var attributes: [String: JSONValue] = [
            "supported_features": .int(features),
            "temperature": .double(22.3),
            "temperature_unit": .string("°C"),
            "attribution": .string("Weather data supplied by a deliberately long local Home Assistant attribution that must wrap without clipping."),
        ]
        if !sparse {
            attributes.merge([
                "pressure": .double(1010.5),
                "pressure_unit": .string("hPa"),
                "humidity": .int(78),
                "wind_speed": .double(10.8),
                "wind_speed_unit": .string("km/h"),
                "wind_bearing": .double(2.8),
                "visibility": .double(10),
                "visibility_unit": .string("km"),
            ]) { _, new in new }
        }
        if let forecast = forecast { attributes["forecast"] = forecast }
        return HAState(
            entityId: "weather.home",
            state: condition,
            attributes: attributes,
            lastChanged: "2026-09-09T11:55:00Z",
            lastUpdated: "2026-09-09T11:57:00Z"
        )
    }

    private func dailyForecast(_ count: Int) -> JSONValue {
        forecast(count: count, interval: 86_400)
    }

    private func hourlyForecast(_ count: Int) -> JSONValue {
        forecast(count: count, interval: 3_600)
    }

    private func forecast(count: Int, interval: TimeInterval) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-09-09T00:00:00Z")!
        var values: [JSONValue] = []
        for index in 0..<count {
            let date = formatter.string(from: start.addingTimeInterval(Double(index) * interval))
            let temperature = Double(24 + (index % 5))
            let low = Double(17 + (index % 4))
            let condition = index.isMultiple(of: 2) ? "partlycloudy" : "rainy"
            values.append(.object([
                "datetime": .string(date),
                "temperature": .double(temperature),
                "templow": .double(low),
                "condition": .string(condition),
                "is_daytime": .bool(!index.isMultiple(of: 2)),
                "precipitation": .double(Double(index) / 10),
            ]))
        }
        return .array(values)
    }

    private func assertPNG(
        _ rendered: RenderedPNG,
        width: Int,
        height: Int,
        name: String
    ) throws {
        XCTAssertTrue(rendered.pngData.starts(with: [0x89, 0x50, 0x4e, 0x47]), name)
        XCTAssertGreaterThan(rendered.pngData.count, 8_000, name)
        XCTAssertGreaterThan(rendered.nonBackgroundSampleCount, 200, name)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered.pngData))
        XCTAssertEqual(bitmap.pixelsWide, width * 2, name)
        XCTAssertEqual(bitmap.pixelsHigh, height * 2, name)
    }

    private func persist(_ data: Data, name: String) throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/render-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        print("MODULE07_DETAIL_GUI artifact=\(url.path)")
    }

}

private final class WeatherDetailNowCounter {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
