import Foundation
import NativeHACore
import XCTest
@testable import NativeHAMac

enum FanFixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Fan")
    static func complete() throws -> FanEntity {
        FanEntity(state: try JSONDecoder().decode(HAState.self, from: Data(contentsOf: root.appendingPathComponent("complete.json"))))
    }
    static func entity(_ attributes: [String: JSONValue] = [:], state: String = "on", id: String = "fan.fixture_pure") -> FanEntity {
        FanEntity(state: HAState(entityId: id, state: state, attributes: attributes, lastChanged: "2026-10-08T12:00:00+00:00", lastUpdated: "2026-10-08T12:00:00+00:00"))
    }
}

final class FanEntityTests: XCTestCase {
    func testFeaturesShapesAndIndependentMenus() throws {
        let full = try FanFixtures.complete()
        XCTAssertEqual(full.mainControl, .slider)
        XCTAssertTrue(full.showsSliderPower)
        XCTAssertEqual(full.presetModes, ["auto", "quiet_mode", "Custom Night"])
        XCTAssertEqual(full.directionOptions, [.forward, .reverse])
        XCTAssertEqual(full.oscillationOptions, [true, false])
        for mask in 0...63 {
            let fan = FanFixtures.entity(["supported_features": .int(mask), "preset_modes": .array([])])
            XCTAssertEqual(fan.features.rawValue, mask)
            XCTAssertEqual(fan.mainControl, mask & 1 == 1 ? .slider : .toggle)
            XCTAssertEqual(fan.presetModes != nil, mask & 8 == 8)
            XCTAssertEqual(fan.directionOptions != nil, mask & 4 == 4)
            XCTAssertEqual(fan.oscillationOptions != nil, mask & 2 == 2)
        }
        XCTAssertNil(FanFixtures.entity(["supported_features": 8]).presetModes)
        XCTAssertEqual(FanFixtures.entity().mainControl, .toggle)
        XCTAssertEqual(FanFixtures.entity(state: "unknown").mainControl, .explicitPower)
        XCTAssertEqual(FanFixtures.entity(["assumed_state": true]).mainControl, .explicitPower)
        for (step, speeds): (Double, [FanSpeed]) in [(100, [.off, .on]), (50, [.off, .low, .high]), (100 / 3, [.off, .low, .medium, .high])] {
            let fan = FanFixtures.entity(["supported_features": 1, "percentage_step": .double(step)])
            XCTAssertEqual(fan.mainControl, .discrete(speeds))
            XCTAssertFalse(fan.showsSliderPower)
        }
    }

    func testHeaderAndControlKeepDifferentOptionalDefaults() {
        for value: JSONValue? in [nil, .null, .int(0)] {
            var attrs: [String: JSONValue] = ["supported_features": 1]
            attrs["percentage"] = value
            let fan = FanFixtures.entity(attrs)
            XCTAssertEqual(fan.header, .state("on"))
            XCTAssertEqual(fan.sliderValue, 0)
            XCTAssertEqual(fan.selectedSpeed, .off)
            XCTAssertEqual(fan.step, 1)
        }
        for value in [0.4, 1, 25, 33, 50, 66, 100, 150] {
            let fan = FanFixtures.entity(["percentage": .double(value)])
            XCTAssertEqual(fan.header, .percentage(FanValueMapping.round(value)))
            XCTAssertEqual(fan.sliderValue, FanValueMapping.round(value))
        }
        for state in ["off", "unknown", "unavailable"] {
            let fan = FanFixtures.entity(["supported_features": 1, "percentage": 75], state: state)
            XCTAssertEqual(fan.header, .state(state))
            XCTAssertEqual(fan.sliderValue, 0)
            XCTAssertEqual(fan.mainControl, .slider)
            XCTAssertEqual(FanServiceBuilder.percentage(25, entity: fan) != nil, state != "unavailable")
        }
        XCTAssertEqual(FanFixtures.entity(["percentage": .double(-0.5)]).sliderValue, 0)
        XCTAssertEqual(FanValueMapping.round(0.5), 1)
        XCTAssertEqual(FanValueMapping.round(-1.5), -1)
        XCTAssertEqual(FanValueMapping.round(0.49999999999999994), 0)
    }

    func testExactServicesRepeatedSpeedAndRawMenuValues() throws {
        let fan = try FanFixtures.complete()
        let original = fan.state
        for value in [0.0, 33.25, 100] {
            let expected = FanServiceRequest(domain: "fan", service: "set_percentage", data: ["entity_id": .string(fan.entityID), "percentage": .double(value)])
            XCTAssertEqual(FanServiceBuilder.percentage(value, entity: fan), expected)
            XCTAssertEqual(FanServiceBuilder.percentage(value, entity: fan), expected)
        }
        for on in [true, false] {
            XCTAssertEqual(FanServiceBuilder.power(on: on, entity: fan), FanServiceRequest(domain: "fan", service: on ? "turn_on" : "turn_off", data: ["entity_id": .string(fan.entityID)]))
            XCTAssertNotNil(FanServiceBuilder.power(on: on, entity: FanFixtures.entity()))
        }
        XCTAssertEqual(FanServiceBuilder.togglePower(entity: fan)?.service, "turn_off")
        XCTAssertEqual(FanServiceBuilder.togglePower(entity: FanFixtures.entity(state: "unknown"))?.service, "turn_on")
        for raw in ["auto", "quiet_mode", "Custom Night"] {
            XCTAssertEqual(FanServiceBuilder.preset(raw, entity: fan), FanServiceRequest(domain: "fan", service: "set_preset_mode", data: ["entity_id": .string(fan.entityID), "preset_mode": .string(raw)]))
        }
        XCTAssertNil(FanServiceBuilder.preset("", entity: fan))
        XCTAssertNil(FanServiceBuilder.preset("Quiet Mode", entity: fan))
        XCTAssertEqual(FanServiceBuilder.direction(.reverse, entity: fan), FanServiceRequest(domain: "fan", service: "set_direction", data: ["entity_id": .string(fan.entityID), "direction": "reverse"]))
        XCTAssertNil(FanServiceBuilder.direction(.forward, entity: fan))
        XCTAssertEqual(FanServiceBuilder.oscillation(true, entity: fan), FanServiceRequest(domain: "fan", service: "oscillate", data: ["entity_id": .string(fan.entityID), "oscillating": true]))
        XCTAssertNil(FanServiceBuilder.oscillation(false, entity: fan))
        let missing = FanFixtures.entity(["supported_features": 6], state: "off")
        XCTAssertFalse(missing.selectedOscillation)
        for _ in 0..<2 {
            XCTAssertEqual(FanServiceBuilder.oscillation(false, entity: missing)?.data["oscillating"], .bool(false))
            XCTAssertNotNil(FanServiceBuilder.direction(.forward, entity: missing))
        }
        XCTAssertEqual(fan.state, original)
    }

    func testMalformedDataFailsClosedWithoutDefaultingOrCrashing() {
        for bad in [JSONValue.string("25"), .bool(true), .array([]), .object([:]), .double(.infinity), .double(.nan)] {
            let fan = FanFixtures.entity(["supported_features": 1, "percentage_step": bad, "percentage": bad])
            XCTAssertNil(fan.step)
            XCTAssertNil(fan.sliderValue)
            XCTAssertEqual(fan.mainControl, .invalidSpeed)
            XCTAssertNil(FanServiceBuilder.percentage(50, entity: fan))
        }
        for step in [0, -1, 201, Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude] {
            let fan = FanFixtures.entity(["supported_features": 1, "percentage_step": .double(step)])
            XCTAssertNil(fan.speedCount)
            XCTAssertEqual(fan.mainControl, .invalidSpeed)
            XCTAssertNil(FanServiceBuilder.speed(.high, entity: fan))
        }
        XCTAssertEqual(FanFixtures.entity(["percentage_step": .null]).step, 1)
        for mask in [JSONValue.string("63"), .bool(true), .double(-1), .double(1.5), .double(.infinity), .double(Double(Int.max))] {
            XCTAssertTrue(FanFixtures.entity(["supported_features": mask]).features.isEmpty)
        }
        XCTAssertNil(FanFixtures.entity(["supported_features": 8, "preset_modes": .array(["auto", 2])]).presetModes)
        let fan = FanFixtures.entity(["supported_features": 63])
        for value in [Double.nan, .infinity, -.infinity, -0.1, 100.1] {
            XCTAssertNil(FanServiceBuilder.percentage(value, entity: fan))
        }
        XCTAssertNil(FanServiceBuilder.power(on: true, entity: FanFixtures.entity(id: "climate.fixture")))
        XCTAssertNil(FanServiceBuilder.power(on: true, entity: FanFixtures.entity(id: "fan.")))
        XCTAssertNil(FanServiceBuilder.percentage(20, entity: FanFixtures.entity()))
        XCTAssertNil(FanServiceBuilder.preset("auto", entity: FanFixtures.entity()))
        XCTAssertNil(FanServiceBuilder.direction(.forward, entity: FanFixtures.entity()))
        XCTAssertNil(FanServiceBuilder.oscillation(true, entity: FanFixtures.entity()))
        let unavailable = FanFixtures.entity(["supported_features": 63, "preset_modes": .array(["auto"])], state: "unavailable")
        XCTAssertNil(FanServiceBuilder.power(on: true, entity: unavailable))
        XCTAssertNil(FanServiceBuilder.preset("auto", entity: unavailable))
        XCTAssertNil(FanServiceBuilder.direction(.forward, entity: unavailable))
        XCTAssertNil(FanServiceBuilder.oscillation(true, entity: unavailable))
    }

    func testPointerKeyboardAndServiceBoundaryStayDistinct() throws {
        let step16 = FanFixtures.entity(["supported_features": 1, "percentage_step": 16])
        XCTAssertEqual(FanValueMapping.pointerCommit(y: 10, top: 10, height: 320, step: 16), 96)
        XCTAssertEqual(FanValueMapping.keyboard(.end, value: 37, step: 16), 100)
        XCTAssertEqual(FanValueMapping.keyboard(.up, value: 37, step: 16), 53)
        XCTAssertEqual(FanServiceBuilder.percentage(53, entity: step16)?.data["percentage"], .double(53))
        XCTAssertEqual(FanValueMapping.keyboard(.up, value: 96, step: 16), 100)
        XCTAssertEqual(FanValueMapping.keyboard(.pageUp, value: 96, step: 16), 96)
        XCTAssertEqual(FanValueMapping.keyboard(.home, value: nil, step: 16), 0)
        let overflow = try XCTUnwrap(FanValueMapping.pointerCommit(y: 0, top: 0, height: 320, step: 22))
        XCTAssertEqual(overflow, 110)
        XCTAssertNil(FanServiceBuilder.percentage(overflow, entity: FanFixtures.entity(["supported_features": 1, "percentage_step": 22])))
        XCTAssertEqual(FanValueMapping.percentage(speed: .high, step: 40), 120)
        XCTAssertNil(FanServiceBuilder.speed(.high, entity: FanFixtures.entity(["supported_features": 1, "percentage_step": 40])))
        XCTAssertEqual(FanServiceBuilder.speed(.off, entity: FanFixtures.entity(["supported_features": 1, "percentage_step": 33]))?.service, "set_percentage")
        XCTAssertEqual(FanServiceBuilder.speed(.high, entity: FanFixtures.entity(["supported_features": 1, "percentage_step": 33]))?.data["percentage"], .double(99))
        XCTAssertNil(FanValueMapping.pointerValue(y: 0, top: 0, height: 0))
        XCTAssertNil(FanValueMapping.pointerValue(y: .nan, top: 0, height: 320))
        XCTAssertNil(FanValueMapping.keyboard(.end, value: .infinity, step: 1))
        XCTAssertNil(FanValueMapping.stepped(50, step: 0))
    }

    func testMappingsAgainstExtractedReferenceSourceOracle() throws {
        struct Selection: Decodable { let percentage: Double; let speed: String }
        struct Count: Decodable {
            let id: String; let attributes: [String: JSONValue]; let count: JSONValue
            let speeds: [Selection]; let selections: [Selection]
        }
        struct Pointer: Decodable { let step: Double; let y: Double; let raw: Double; let stepped: JSONValue }
        struct Key: Decodable { let step: Double; let initial: Double; let direction: String; let code: String; let value: Double }
        struct Oracle: Decodable {
            let featureBits: [String: Int]; let discreteThreshold: Int
            let countCases: [Count]; let pointerCases: [Pointer]; let keyboardCases: [Key]
        }
        let oracle = try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: FanFixtures.root.appendingPathComponent("expected-semantics.json")))
        XCTAssertEqual(oracle.featureBits, ["SET_SPEED": FanEntityFeature.setSpeed.rawValue, "OSCILLATE": FanEntityFeature.oscillate.rawValue, "DIRECTION": FanEntityFeature.direction.rawValue, "PRESET_MODE": FanEntityFeature.presetMode.rawValue, "TURN_OFF": FanEntityFeature.turnOff.rawValue, "TURN_ON": FanEntityFeature.turnOn.rawValue])
        XCTAssertEqual(oracle.discreteThreshold, 4)
        for fixture in oracle.countCases {
            let fan = FanFixtures.entity(fixture.attributes)
            guard case let .int(count) = fixture.count, count >= 2 else {
                XCTAssertNil(fan.speedCount, fixture.id)
                continue
            }
            XCTAssertEqual(fan.speedCount, count, fixture.id)
            let step = try XCTUnwrap(fan.step)
            for selection in fixture.selections {
                XCTAssertEqual(FanValueMapping.speed(percentage: selection.percentage, step: step).rawValue, selection.speed, fixture.id)
            }
            for speed in fixture.speeds {
                XCTAssertEqual(FanValueMapping.percentage(speed: try XCTUnwrap(FanSpeed(rawValue: speed.speed)), step: step), speed.percentage, fixture.id)
            }
        }
        for fixture in oracle.pointerCases {
            XCTAssertEqual(FanValueMapping.pointerValue(y: fixture.y, top: 0, height: 320), fixture.raw)
            let native = FanValueMapping.pointerCommit(y: fixture.y, top: 0, height: 320, step: fixture.step)
            switch fixture.stepped {
            case let .int(value): XCTAssertEqual(native, Double(value))
            case let .double(value): XCTAssertEqual(try XCTUnwrap(native), value, accuracy: 1e-10)
            case .object: XCTAssertNil(native, "Native rejects reference's nonfinite malformed-step result")
            default: XCTFail("Unexpected oracle numeric encoding")
            }
        }
        for fixture in oracle.keyboardCases {
            XCTAssertEqual(FanValueMapping.keyboard(try XCTUnwrap(FanSliderKey(rawValue: fixture.code)), value: fixture.initial, step: fixture.step, rtl: fixture.direction == "rtl"), fixture.value)
        }
    }

    func testTenThousandPurePreparationsAndMappingsPerformance() throws {
        let complete = try FanFixtures.complete().state
        let states = [complete, FanFixtures.entity().state,
                      FanFixtures.entity(["supported_features": 1, "percentage_step": 33, "percentage": 66]).state,
                      FanFixtures.entity(["supported_features": 63], state: "unavailable").state]
        var consumed = 0.0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for index in 0..<10_000 {
                let fan = FanEntity(state: states[index % states.count])
                _ = fan.mainControl
                _ = fan.header
                consumed += fan.sliderValue ?? 0
                consumed += FanValueMapping.keyboard(.up, value: fan.sliderValue, step: fan.step ?? 1) ?? 0
            }
        }
        XCTAssertGreaterThan(consumed, 0)
    }
}
