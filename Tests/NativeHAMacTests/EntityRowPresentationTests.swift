import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class EntityRowPresentationTests: XCTestCase {
    func testNameMatrixPreservesEmptyAndResolvesStructuredItemsWithoutInvalidatingRow() {
        let state = HAState(
            entityId: "sensor.room_temperature",
            state: "21",
            attributes: ["friendly_name": .string("Room Temperature")]
        )
        let exactEmpty = presentation(
            raw: .object(["entity": .string(state.entityId), "name": .string("")]),
            states: [state.entityId: state]
        )
        XCTAssertEqual(exactEmpty.name, "")

        let structuredRaw: JSONValue = .object([
            "entity": .string(state.entityId),
            "name": .array([
                .object(["type": .string("text"), "text": .string("Inside")]),
                .object(["type": .string("entity")]),
                .object(["type": .string("area")]),
                .int(4),
            ]),
        ])
        let structured = presentation(raw: structuredRaw, states: [state.entityId: state])
        XCTAssertEqual(structured.name, "Inside Room Temperature")
        XCTAssertTrue(structured.isSupported)
        XCTAssertTrue(structured.warningText?.contains("area") == true)
        XCTAssertEqual(row(raw: structuredRaw).source.rawValue, structuredRaw)

        let nullFriendly = HAState(
            entityId: "sensor.raw_name",
            state: "ok",
            attributes: ["friendly_name": .null]
        )
        XCTAssertEqual(
            presentation(raw: .string(nullFriendly.entityId), states: [nullFriendly.entityId: nullFriendly]).name,
            ""
        )
        XCTAssertEqual(
            presentation(raw: .string("sensor.object_name"), states: [:]).name,
            "object name"
        )
    }

    func testMissingUnknownUnavailableAndRawStateRemainDistinct() {
        let missing = presentation(raw: .string("sensor.missing"), states: [:])
        XCTAssertEqual(missing.stateText, "Missing entity")
        XCTAssertEqual(missing.stateKind, .missing)
        XCTAssertEqual(missing.primaryAction, .none)

        let unknown = state("sensor.status", "unknown")
        let unavailable = state("sensor.status", "unavailable")
        let raw = state("sensor.status", "partly_cloudy")
        XCTAssertEqual(presentation(for: unknown).stateText, "Unknown")
        XCTAssertEqual(presentation(for: unavailable).stateText, "Unavailable")
        XCTAssertEqual(presentation(for: raw).stateText, "partly_cloudy")
    }

    func testNumericPrecisionLocaleAndUnitSpacingMatrix() {
        let precise = state(
            "sensor.precise", "12.3",
            ["unit_of_measurement": .string("ppm")]
        )
        XCTAssertEqual(
            presentation(for: precise, precisions: [precise.entityId: 4]).stateText,
            "12.3000 ppm"
        )

        let integer = state(
            "sensor.integer", "12",
            ["step": .int(1), "unit_of_measurement": .string("°")]
        )
        XCTAssertEqual(presentation(for: integer).stateText, "12°")

        let trailing = state(
            "sensor.trailing", "12.3000",
            ["unit_of_measurement": .string("′")]
        )
        XCTAssertEqual(presentation(for: trailing).stateText, "12.3000 ′")

        let percent = state(
            "sensor.percent", "50",
            ["unit_of_measurement": .string("%")]
        )
        XCTAssertEqual(presentation(for: percent, preferences: preferences(language: "en")).stateText, "50%")
        for language in ["cs", "de", "fi", "fr", "sk", "sv"] {
            XCTAssertEqual(
                presentation(for: percent, preferences: preferences(language: language)).stateText,
                "50 %",
                language
            )
        }

        let noGrouping = state(
            "sensor.large", "1234.50",
            ["unit_of_measurement": .string("W")]
        )
        XCTAssertEqual(
            presentation(for: noGrouping, preferences: preferences(numberFormat: "none")).stateText,
            "1234.50 W"
        )
    }

    func testDurationMonetaryDateTimeAndTimestampFormattingPaths() {
        let duration = state(
            "sensor.duration", "1.5",
            ["device_class": .string("duration"), "unit_of_measurement": .string("h")]
        )
        let durationText = presentation(for: duration).stateText
        XCTAssertTrue(durationText.contains("1"))
        XCTAssertTrue(durationText.contains("30"))

        let money = state(
            "sensor.cost", "12.50",
            ["device_class": .string("monetary"), "unit_of_measurement": .string("USD")]
        )
        let monetary = presentation(for: money, preferences: preferences(numberFormat: "none")).stateText
        XCTAssertTrue(monetary.contains("12.50"))
        XCTAssertTrue(monetary.contains("$") || monetary.contains("USD"))

        let date = state("date.trip", "2026-09-03")
        XCTAssertTrue(
            presentation(for: date, preferences: preferences(), rowType: "simple-entity")
                .stateText.contains("2026")
        )
        let time = state("time.alarm", "14:05:06")
        XCTAssertTrue(
            presentation(for: time, preferences: preferences(), rowType: "simple-entity")
                .stateText.contains("14:05")
        )

        let timestamp = state(
            "sensor.updated", "2026-09-01T00:00:00Z",
            ["device_class": .string("timestamp")]
        )
        let timestampText = presentation(
            for: timestamp,
            preferences: preferences(timeZone: "server"),
            serverTimeZone: "Asia/Shanghai"
        ).stateText
        XCTAssertTrue(timestampText.contains("2026"))
        XCTAssertTrue(timestampText.contains("08:00"))

        let invalid = state(
            "sensor.invalid_time", "not-a-date",
            ["device_class": .string("timestamp")]
        )
        XCTAssertEqual(presentation(for: invalid).stateText, "not-a-date")
    }

    func testIconPrecedenceMappingsAndDeterministicFallbacks() {
        let entity = state(
            "sensor.room", "42",
            ["device_class": .string("humidity"), "icon": .string("mdi:battery")]
        )
        let rowOverride = presentation(
            raw: .object(["entity": .string(entity.entityId), "icon": .string("mdi:thermometer")]),
            states: [entity.entityId: entity],
            registryIcons: [entity.entityId: "mdi:home"]
        )
        XCTAssertEqual(rowOverride.icon.symbolName, "thermometer")
        XCTAssertEqual(rowOverride.icon.requestedIdentifier, "mdi:thermometer")
        XCTAssertNil(rowOverride.icon.warning)

        let registry = presentation(
            raw: .string(entity.entityId),
            states: [entity.entityId: entity],
            registryIcons: [entity.entityId: "mdi:home"]
        )
        XCTAssertEqual(registry.icon.symbolName, "house")

        let unsupported = presentation(
            raw: .object(["entity": .string(entity.entityId), "icon": .string("mdi:custom-thing")]),
            states: [entity.entityId: entity]
        )
        XCTAssertEqual(unsupported.icon.symbolName, "drop")
        XCTAssertEqual(unsupported.icon.requestedIdentifier, "mdi:custom-thing")
        XCTAssertNotNil(unsupported.icon.warning)

        let symbolFallback = presentation(
            for: entity,
            availability: { $0 == "circle.grid.2x2" }
        )
        XCTAssertEqual(symbolFallback.icon.symbolName, "circle.grid.2x2")
        let textFallback = presentation(for: entity, availability: { _ in false })
        XCTAssertNil(textFallback.icon.symbolName)
        XCTAssertEqual(textFallback.icon.fallbackText, "?")
        XCTAssertFalse(textFallback.icon.semanticLabel.isEmpty)
    }

    func testEveryBoundedSemanticAndDirectIconMapping() {
        let semanticCases: [(HAState?, String, String)] = [
            (nil, "sensor.missing", "questionmark.square"),
            (state("sensor.unavailable", "unavailable"), "sensor.unavailable", "exclamationmark.triangle"),
            (state("sensor.unknown", "unknown"), "sensor.unknown", "questionmark.circle"),
            (state("sensor.temperature", "20", ["device_class": .string("temperature")]), "sensor.temperature", "thermometer"),
            (state("sensor.humidity", "40", ["device_class": .string("humidity")]), "sensor.humidity", "drop"),
            (state("sensor.battery_high", "70", ["device_class": .string("battery")]), "sensor.battery_high", "battery.100"),
            (state("sensor.battery_medium", "30", ["device_class": .string("battery")]), "sensor.battery_medium", "battery.50"),
            (state("sensor.battery_low", "29", ["device_class": .string("battery")]), "sensor.battery_low", "battery.25"),
            (state("device_tracker.phone", "home"), "device_tracker.phone", "house"),
            (state("person.jin", "away"), "person.jin", "location"),
            (state("sensor.generic", "1"), "sensor.generic", "gauge"),
            (state("binary_sensor.door", "off"), "binary_sensor.door", "sensor"),
            (state("switch.plug", "on"), "switch.plug", "switch.2"),
            (state("automation.rule", "on"), "automation.rule", "gearshape.2"),
            (state("weather.home", "sunny"), "weather.home", "cloud.sun"),
            (state("climate.room", "heat"), "climate.room", "thermometer"),
            (state("fan.room", "on"), "fan.room", "fanblades"),
            (state("button.run", "2026-09-01T00:00:00Z"), "button.run", "circle"),
            (state("zone.home", "0"), "zone.home", "mappin.and.ellipse"),
            (state("number.level", "2"), "number.level", "number.square"),
            (state("script.run", "off"), "script.run", "scroll"),
            (state("select.mode", "auto"), "select.mode", "list.bullet.rectangle"),
            (state("update.system", "on"), "update.system", "arrow.triangle.2.circlepath"),
            (state("calendar.work", "off"), "calendar.work", "circle.grid.2x2"),
        ]
        for (state, entityID, expected) in semanticCases {
            let result = presentation(
                raw: .object([
                    "entity": .string(entityID),
                    "type": .string("simple-entity"),
                ]),
                states: state.map { [entityID: $0] } ?? [:]
            )
            XCTAssertEqual(result.icon.symbolName, expected, entityID)
        }

        let direct: [String: String] = [
            "mdi:thermometer": "thermometer",
            "mdi:water-percent": "drop",
            "mdi:humidity": "drop",
            "mdi:battery": "battery.100",
            "mdi:home": "house",
            "mdi:map-marker": "location",
            "mdi:toggle-switch": "switch.2",
            "mdi:cog": "gearshape.2",
            "mdi:update": "arrow.triangle.2.circlepath",
        ]
        for (identifier, expected) in direct {
            let entity = state("sensor.direct", "1")
            let result = presentation(
                raw: .object(["entity": .string(entity.entityId), "icon": .string(identifier)]),
                states: [entity.entityId: entity]
            )
            XCTAssertEqual(result.icon.symbolName, expected, identifier)
            XCTAssertEqual(result.icon.requestedIdentifier, identifier)
        }
    }

    func testStateColorMatrixAndCardPropagation() {
        let battery = state(
            "sensor.battery", "29",
            ["device_class": .string("battery"), "unit_of_measurement": .string("%")]
        )
        XCTAssertEqual(presentation(for: battery, rowStateColor: true).colorRole, .batteryLow)
        XCTAssertEqual(presentation(for: state("light.lamp", "on")).colorRole, .active)
        XCTAssertEqual(presentation(for: state("switch.outlet", "off"), cardStateColor: true).colorRole, .inactive)
        XCTAssertEqual(presentation(for: state("switch.outlet", "unavailable"), rowStateColor: false).colorRole, .normal)
        XCTAssertEqual(presentation(for: state("camera.door", "streaming"), rowStateColor: true).colorRole, .active)
        XCTAssertEqual(
            presentation(
                for: state("group.room", "open"),
                rowStateColor: true,
                rowType: "simple-entity"
            ).colorRole,
            .active
        )
    }

    func testActionClassificationNeverFallsThroughAndSecondaryMatrixIsExact() {
        let entity = HAState(
            entityId: "switch.desk",
            state: "off",
            attributes: [
                "current_position": .int(0),
                "current_tilt_position": .int(0),
                "brightness": .int(128),
            ],
            lastChanged: "2026-09-01T00:00:00Z",
            lastUpdated: "2026-09-01T00:01:00Z"
        )
        let absent = presentation(for: entity)
        XCTAssertEqual(absent.primaryAction, .details(entityID: entity.entityId))
        XCTAssertTrue(absent.showsPowerControl)

        let moreInfo = presentation(
            raw: .object([
                "entity": .string(entity.entityId),
                "tap_action": .object(["action": .string("more-info"), "entity": .string("light.other")]),
            ]),
            states: [entity.entityId: entity]
        )
        XCTAssertEqual(moreInfo.primaryAction, .details(entityID: "light.other"))

        let none = presentation(
            raw: .object([
                "entity": .string(entity.entityId),
                "tap_action": .object(["action": .string("none")]),
            ]),
            states: [entity.entityId: entity]
        )
        XCTAssertEqual(none.primaryAction, .none)

        let unsupported = presentation(
            raw: .object([
                "entity": .string(entity.entityId),
                "tap_action": .object(["action": .string("navigate")]),
                "hold_action": .object(["action": .string("toggle")]),
                "double_tap_action": .object(["action": .string("none")]),
            ]),
            states: [entity.entityId: entity]
        )
        XCTAssertEqual(unsupported.primaryAction, .unsupported)
        XCTAssertEqual(unsupported.warningText, "Unsupported action: tap_action, hold_action")

        XCTAssertEqual(secondary("position", entity).visibleText, "Position: 0")
        XCTAssertEqual(secondary("tilt-position", entity).visibleText, "Tilt position: 0")
        XCTAssertEqual(secondary("brightness", entity).visibleText, "50 %")
        let never = secondary("last-triggered", entity)
        XCTAssertEqual(never.visibleText, "Never triggered")
        XCTAssertEqual(never.accessibilityLabel, "Last triggered")
        XCTAssertEqual(never.accessibilityValue, "Never triggered")

        let zeroBrightness = state("light.zero", "on", ["brightness": .int(0)])
        XCTAssertNil(presentation(for: zeroBrightness, secondaryInfo: "brightness").secondary)
    }

    func testRowSelectionAndPowerRoutingMatrix() {
        XCTAssertEqual(presentation(for: state("climate.room", "heat")).kind, .deferredSpecialized)
        XCTAssertEqual(presentation(for: state("weather.home", "sunny")).kind, .deferredSpecialized)
        XCTAssertEqual(presentation(for: state("climate.room", "heat")).primaryAction, .none)
        XCTAssertTrue(presentation(for: state("binary_sensor.door", "on")).isSupported)

        let unsupported = presentation(
            raw: .object(["type": .string("divider")]),
            states: [:]
        )
        XCTAssertFalse(unsupported.isSupported)
        let malformedOptional = presentation(
            raw: .object(["entity": .string("sensor.bad_icon"), "icon": .int(4)]),
            states: ["sensor.bad_icon": state("sensor.bad_icon", "1")]
        )
        XCTAssertFalse(malformedOptional.isSupported)

        XCTAssertEqual(
            EntityRowPresentationResolver.rowPowerRoute(entityID: "cover.blind", isOn: true),
            EntityPowerRoute(domain: "cover", service: "open_cover")
        )
        XCTAssertEqual(
            EntityRowPresentationResolver.rowPowerRoute(entityID: "lock.door", isOn: false),
            EntityPowerRoute(domain: "lock", service: "lock")
        )
        XCTAssertEqual(
            EntityRowPresentationResolver.rowPowerRoute(entityID: "group.room", isOn: true),
            EntityPowerRoute(domain: "homeassistant", service: "turn_on")
        )
        XCTAssertEqual(
            EntityRowPresentationResolver.headerPowerRoute(isOn: false),
            EntityPowerRoute(domain: "homeassistant", service: "turn_off")
        )
    }

    func testImplicitRowFactoryMatrixRejectsEveryReferenceSpecializedDomain() {
        let toggleDomains = [
            "alert", "automation", "fan", "input_boolean", "light",
            "remote", "siren", "switch", "vacuum",
        ]
        XCTAssertEqual(EntityRowPresentationResolver.implicitToggleDomains, Set(toggleDomains))
        for domain in toggleDomains {
            let result = presentation(for: state("\(domain).example", "off"))
            XCTAssertEqual(result.kind, .generic, domain)
            XCTAssertTrue(result.showsPowerControl, domain)
        }

        XCTAssertEqual(presentation(for: state("sensor.example", "1")).kind, .generic)
        for domain in ["binary_sensor", "device_tracker", "future_domain"] {
            XCTAssertEqual(presentation(for: state("\(domain).example", "off")).kind, .generic, domain)
        }

        for domain in ["climate", "weather"] {
            let result = presentation(for: state("\(domain).example", "off"))
            XCTAssertEqual(result.kind, .deferredSpecialized, domain)
            XCTAssertEqual(result.primaryAction, .none, domain)
        }

        let specializedDomains = [
            "button", "cover", "date", "datetime", "event", "group", "humidifier",
            "input_button", "input_datetime", "input_number", "input_select", "input_text",
            "lock", "media_player", "number", "scene", "script", "select", "text", "time",
            "timer", "update", "valve", "water_heater",
        ]
        XCTAssertEqual(
            EntityRowPresentationResolver.implicitSpecializedDomains,
            Set(specializedDomains)
        )
        for domain in specializedDomains {
            let result = presentation(for: state("\(domain).example", "off"))
            XCTAssertFalse(result.isSupported, domain)
            XCTAssertEqual(result.primaryAction, .none, domain)
            XCTAssertFalse(result.showsPowerControl, domain)
            XCTAssertTrue(result.warningText?.contains(domain) == true, domain)
        }
    }

    private func presentation(
        for state: HAState,
        precisions: [String: Int] = [:],
        preferences: HAFrontendLocalePreferences? = nil,
        serverTimeZone: String? = nil,
        rowStateColor: Bool? = nil,
        cardStateColor: Bool? = nil,
        secondaryInfo: String? = nil,
        rowType: String? = nil,
        availability: @escaping EntityRowPresentationResolver.SymbolAvailability = { _ in true }
    ) -> EntityRowPresentation {
        var object: [String: JSONValue] = ["entity": .string(state.entityId)]
        if let rowStateColor = rowStateColor { object["state_color"] = .bool(rowStateColor) }
        if let secondaryInfo = secondaryInfo { object["secondary_info"] = .string(secondaryInfo) }
        if let rowType = rowType { object["type"] = .string(rowType) }
        return presentation(
            raw: .object(object), states: [state.entityId: state], precisions: precisions,
            preferences: preferences, serverTimeZone: serverTimeZone,
            cardStateColor: cardStateColor, availability: availability
        )
    }

    private func presentation(
        raw: JSONValue,
        states: [String: HAState],
        precisions: [String: Int] = [:],
        registryIcons: [String: String] = [:],
        preferences: HAFrontendLocalePreferences? = nil,
        serverTimeZone: String? = nil,
        cardStateColor: Bool? = nil,
        availability: @escaping EntityRowPresentationResolver.SymbolAvailability = { _ in true }
    ) -> EntityRowPresentation {
        EntityRowPresentationResolver.resolve(
            row: row(raw: raw),
            cardStateColor: cardStateColor,
            states: states,
            registryDisplayPrecisions: precisions,
            registryIcons: registryIcons,
            preferences: preferences,
            serverTimeZone: serverTimeZone,
            now: Date(timeIntervalSince1970: 1_788_225_600),
            symbolAvailability: availability
        )
    }

    private func row(raw: JSONValue) -> LovelacePresentationRow {
        let source = LovelaceEntityRef(rawValue: raw, diagnosticPath: "row")
        return LovelacePresentationRow(
            source: source,
            identity: LovelaceResolvedIdentity(sourcePath: LovelaceSourcePath(), rawValue: raw),
            isSynthetic: false
        )
    }

    private func state(
        _ entityID: String,
        _ value: String,
        _ attributes: [String: JSONValue] = [:]
    ) -> HAState {
        HAState(entityId: entityID, state: value, attributes: attributes)
    }

    private func secondary(_ kind: String, _ state: HAState) -> EntitySecondaryPresentation {
        presentation(for: state, secondaryInfo: kind).secondary!
    }

    private func preferences(
        language: String = "en_US_POSIX",
        numberFormat: String = "none",
        timeZone: String = "server"
    ) -> HAFrontendLocalePreferences {
        HAFrontendLocalePreferences(
            language: language,
            numberFormat: numberFormat,
            timeFormat: "24",
            dateFormat: "system",
            firstWeekday: "monday",
            timeZone: timeZone
        )
    }
}
