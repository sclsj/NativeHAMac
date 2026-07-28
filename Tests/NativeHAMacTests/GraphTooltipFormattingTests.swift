import CoreGraphics
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class GraphTooltipFormattingTests: XCTestCase {
    func testDigitPrecedenceAndClamping() {
        let state = HAState(
            entityId: "sensor.test",
            state: "12",
            attributes: ["step": .int(1)]
        )
        let preferences = localePreferences()

        let perEntity = metadata(
            state: state,
            registry: 4,
            preferences: preferences,
            policy: GraphTooltipFormattingPolicy(
                numericDigits: 3,
                entityNumericDigits: ["sensor.test": 99]
            )
        )
        XCTAssertEqual(perEntity.minimumFractionDigits, 15)
        XCTAssertEqual(perEntity.maximumFractionDigits, 15)

        let global = metadata(
            state: state,
            registry: 4,
            preferences: preferences,
            policy: GraphTooltipFormattingPolicy(numericDigits: -4)
        )
        XCTAssertEqual(global.maximumFractionDigits, 0)

        let registry = metadata(
            state: state,
            registry: 4,
            preferences: preferences
        )
        XCTAssertEqual(registry.minimumFractionDigits, 4)
        XCTAssertEqual(registry.maximumFractionDigits, 4)
        XCTAssertEqual(registry.formatNumber(12.3, unit: "ppm"), "12.3000 ppm")

        let integerStep = metadata(state: state, preferences: preferences)
        XCTAssertEqual(integerStep.maximumFractionDigits, 0)
        XCTAssertEqual(integerStep.formatNumber(12, unit: "ppm"), "12 ppm")
    }

    func testHAFallbackUsesCanonicalParsedDigitsInsteadOfRawTrailingZeros() {
        let result = metadata(
            state: HAState(entityId: "sensor.test", state: "12.3000"),
            preferences: localePreferences()
        )

        XCTAssertTrue(result.usesCanonicalValueDigits)
        XCTAssertEqual(result.formatNumber(12.3, unit: "ppm"), "12.3 ppm")
        XCTAssertEqual(result.formatNumber(12.345, unit: "ppm"), "12.345 ppm")
    }

    func testNumberLocalePreferencesControlSeparators() {
        let decimalComma = metadata(
            preferences: localePreferences(numberFormat: "decimal_comma")
        )
        let noGrouping = metadata(
            preferences: localePreferences(numberFormat: "none"),
            policy: GraphTooltipFormattingPolicy(numericDigits: 2)
        )

        XCTAssertEqual(decimalComma.formatNumber(1_234.5, unit: ""), "1.234,5")
        XCTAssertEqual(noGrouping.formatNumber(1_234.5, unit: ""), "1234.50")
        XCTAssertTrue(decimalComma.numberLocaleIdentifier.hasPrefix("de"))
        XCTAssertTrue(decimalComma.timeLocaleIdentifier.hasPrefix("en"))
    }

    func testTimeModesUseFullLocalizedDateAndRequestedPrecision() {
        let timestamp = 1_767_225_600.456
        let base = metadata(
            preferences: localePreferences(timeFormat: "24", timeZone: "server"),
            serverTimeZone: "UTC"
        )
        let minute = replacingTimePrecision(base, with: .minute)
        let fractional = replacingTimePrecision(base, with: .fractionalSeconds(3))

        let secondsText = base.formatTime(timestamp)
        let minuteText = minute.formatTime(timestamp)
        let fractionalText = fractional.formatTime(timestamp)
        XCTAssertTrue(secondsText.contains("2026"))
        XCTAssertTrue(secondsText.contains("00:00:00"))
        XCTAssertTrue(minuteText.contains("00:00"))
        XCTAssertFalse(minuteText.contains("00:00:00"))
        XCTAssertTrue(fractionalText.contains("00:00:00.456"))
    }

    func testFormattingOnlyInvalidatesPreparedDisplayWithoutChangingGeometry() throws {
        let twoDigits = fixedMetadata(digits: 2)
        let threeDigits = fixedMetadata(digits: 3)
        let legacy = input(nativeTimestamps: false, formatting: twoDigits)
        let reformatted = input(nativeTimestamps: false, formatting: threeDigits)
        GraphBitmapRenderer.resetPreparedSeriesCache()

        let first = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(legacy, displayUnit: "ppm")
        )
        let second = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(reformatted, displayUnit: "ppm")
        )

        XCTAssertEqual(first.points.map(\.t), second.points.map(\.t))
        XCTAssertEqual(first.points.map(\.y), second.points.map(\.y))
        XCTAssertEqual(first.points.map(\.display), second.points.map(\.display))
        XCTAssertEqual(
            first.tooltipFormatting.formatNumber(first.points[0].y, unit: first.unit),
            "12.30 ppm"
        )
        XCTAssertEqual(
            second.tooltipFormatting.formatNumber(second.points[0].y, unit: second.unit),
            "12.300 ppm"
        )
        XCTAssertEqual(
            GraphBitmapRenderer.preparedSeriesCacheStatistics().fullPreparationCount,
            2
        )
    }

    func testNativeNumericAndLegacyStringHistoryProduceEquivalentHoverSamples() throws {
        let formatting = fixedMetadata(digits: 2)
        let legacyResult = try render(input(nativeTimestamps: false, formatting: formatting))
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let nativeResult = try render(input(nativeTimestamps: true, formatting: formatting))
        let legacySample = try XCTUnwrap(legacyResult.sample(atX: legacyResult.plotRect.midX))
        let nativeSample = try XCTUnwrap(nativeResult.sample(atX: nativeResult.plotRect.midX))

        XCTAssertEqual(nativeSample.timestamp, legacySample.timestamp, accuracy: 0.001)
        XCTAssertEqual(nativeSample.values.map(\.point.y), legacySample.values.map(\.point.y))
        XCTAssertEqual(nativeSample.values.map(\.point.display), legacySample.values.map(\.point.display))
    }

    func testProductionTooltipFormattingDefaultsToHomeAssistant() {
        let policy = AppConfig.graphTooltipFormattingPolicy
        XCTAssertEqual(policy.timePrecision, .homeAssistant)
        XCTAssertNil(policy.numericDigits)
        XCTAssertTrue(policy.entityNumericDigits.isEmpty)
    }

    private func metadata(
        state: HAState? = HAState(entityId: "sensor.test", state: "1234.5"),
        registry: Int? = nil,
        preferences: HAFrontendLocalePreferences? = nil,
        serverTimeZone: String? = nil,
        policy: GraphTooltipFormattingPolicy = GraphTooltipFormattingPolicy()
    ) -> GraphTooltipFormattingMetadata {
        GraphTooltipFormattingResolver.metadata(
            entityID: "sensor.test",
            state: state,
            registryDisplayPrecision: registry,
            preferences: preferences,
            serverTimeZone: serverTimeZone,
            policy: policy
        )
    }

    private func localePreferences(
        numberFormat: String = "comma_decimal",
        timeFormat: String = "24",
        timeZone: String = "local"
    ) -> HAFrontendLocalePreferences {
        HAFrontendLocalePreferences(
            language: "en",
            numberFormat: numberFormat,
            timeFormat: timeFormat,
            dateFormat: "system",
            firstWeekday: "monday",
            timeZone: timeZone
        )
    }

    private func fixedMetadata(digits: Int) -> GraphTooltipFormattingMetadata {
        metadata(
            preferences: localePreferences(),
            serverTimeZone: "UTC",
            policy: GraphTooltipFormattingPolicy(numericDigits: digits)
        )
    }

    private func replacingTimePrecision(
        _ source: GraphTooltipFormattingMetadata,
        with precision: GraphTooltipTimePrecision
    ) -> GraphTooltipFormattingMetadata {
        GraphTooltipFormattingMetadata(
            minimumFractionDigits: source.minimumFractionDigits,
            maximumFractionDigits: source.maximumFractionDigits,
            usesCanonicalValueDigits: source.usesCanonicalValueDigits,
            numberLocaleIdentifier: source.numberLocaleIdentifier,
            timeLocaleIdentifier: source.timeLocaleIdentifier,
            usesGroupingSeparator: source.usesGroupingSeparator,
            timePrecision: precision,
            timeFormatPreference: source.timeFormatPreference,
            timeZoneIdentifier: source.timeZoneIdentifier
        )
    }

    private func input(
        nativeTimestamps: Bool,
        formatting: GraphTooltipFormattingMetadata
    ) -> GraphRenderSeriesInput {
        let timestamps = [1_767_225_600.0, 1_767_225_660.0, 1_767_225_720.0]
        let values = ["12.3", "13.4", "14.5"]
        let points = zip(timestamps, values).map { pair -> HAHistoryPoint in
            let (timestamp, value) = pair
            if nativeTimestamps {
                return HAHistoryPoint(
                    entityId: "sensor.test",
                    state: value,
                    attributes: nil,
                    lastChangedSeconds: timestamp,
                    lastUpdatedSeconds: timestamp
                )
            }
            return HAHistoryPoint(
                entityId: "sensor.test",
                state: value,
                attributes: nil,
                lastChanged: ISO8601DateFormatter().string(
                    from: Date(timeIntervalSince1970: timestamp)
                ),
                lastUpdated: nil
            )
        }
        return GraphRenderSeriesInput(
            cacheScope: "tooltip-formatting-test",
            entityID: "sensor.test",
            name: "Test",
            unit: "ppm",
            color: GraphColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
            history: HAHistorySeries(entityID: "sensor.test", points: points),
            windowStart: timestamps.first,
            windowEnd: timestamps.last,
            tooltipFormatting: formatting
        )
    }

    private func render(_ input: GraphRenderSeriesInput) throws -> GraphRenderResult {
        try XCTUnwrap(GraphBitmapRenderer.prepareViewportData(
            inputs: [input],
            unit: "ppm",
            size: CGSize(width: 496, height: 178),
            scale: 2,
            zoomScale: 1,
            panFraction: 1
        )?.result)
    }
}
