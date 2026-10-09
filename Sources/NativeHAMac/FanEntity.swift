import Foundation
import NativeHACore

struct FanEntityFeature: OptionSet {
    let rawValue: Int
    static let setSpeed = Self(rawValue: 1)
    static let oscillate = Self(rawValue: 2)
    static let direction = Self(rawValue: 4)
    static let presetMode = Self(rawValue: 8)
    static let turnOff = Self(rawValue: 16)
    static let turnOn = Self(rawValue: 32)
}

enum FanSpeed: String { case off, low, medium, high, on }
enum FanDirection: String, CaseIterable { case forward, reverse }
enum FanMainControl: Equatable {
    case toggle, explicitPower, discrete([FanSpeed]), slider, invalidSpeed
}

/// Formatting belongs to the presentation layer; the raw state is never
/// replaced by the local speed draft, or by the control's zero fallback.
enum FanHeaderValue: Equatable {
    case state(String)
    case percentage(Double)
}

struct FanEntity {
    let state: HAState
    var entityID: String { state.entityId }
    var unavailable: Bool { state.state == "unavailable" }
    var active: Bool { !["off", "unknown", "unavailable"].contains(state.state) }
    var isFan: Bool { entityID.hasPrefix("fan.") && entityID.count > 4 }
    var features: FanEntityFeature {
        guard let value = number("supported_features"), value >= 0,
              value < Double(Int.max), value.rounded(.towardZero) == value else { return [] }
        return FanEntityFeature(rawValue: Int(value))
    }
    var percentage: Double? { number("percentage") }
    /// Only missing/null defaults to one. A malformed supplied step stays invalid.
    var step: Double? {
        if isAbsent("percentage_step") { return 1 }
        guard let value = number("percentage_step"), value > 0 else { return nil }
        return value
    }
    var speedCount: Int? { step.flatMap(FanValueMapping.speedCount) }
    var speeds: [FanSpeed]? { speedCount.flatMap(FanValueMapping.speeds) }
    var mainControl: FanMainControl {
        guard features.contains(.setSpeed) else {
            return state.state == "unknown" || assumedState ? .explicitPower : .toggle
        }
        guard let count = speedCount else { return .invalidSpeed }
        if let options = FanValueMapping.speeds(count: count) { return .discrete(options) }
        return count > 4 ? .slider : .invalidSpeed
    }
    var showsSliderPower: Bool { mainControl == .slider }
    var assumedState: Bool { boolean("assumed_state") ?? false }
    var presetMode: String? { string("preset_mode") }
    var presetModes: [String]? {
        guard features.contains(.presetMode), case let .array(values)? = state.attributes["preset_modes"] else { return nil }
        var strings: [String] = []
        for value in values {
            guard case let .string(string) = value else { return nil }
            strings.append(string)
        }
        return strings
    }
    var direction: String? { string("direction") }
    var directionOptions: [FanDirection]? { features.contains(.direction) ? FanDirection.allCases : nil }
    var oscillating: Bool? { boolean("oscillating") }
    var oscillationOptions: [Bool]? { features.contains(.oscillate) ? [true, false] : nil }
    var selectedOscillation: Bool { oscillating ?? false }
    var header: FanHeaderValue {
        guard active, let value = percentage, value != 0 else { return .state(state.state) }
        return .percentage(FanValueMapping.round(value))
    }
    /// nil distinguishes malformed active data from normal optional zero.
    var controlPercentage: Double? {
        guard active else { return 0 }
        return isAbsent("percentage") ? 0 : percentage
    }
    var sliderValue: Double? { controlPercentage.map { max(FanValueMapping.round($0), 0) } }
    var selectedSpeed: FanSpeed {
        guard let percentage = controlPercentage, let step = step else { return .off }
        return FanValueMapping.speed(percentage: percentage, step: step)
    }
    private func isAbsent(_ key: String) -> Bool {
        state.attributes[key] == nil || state.attributes[key] == .null
    }
    private func number(_ key: String) -> Double? {
        let value: Double
        switch state.attributes[key] {
        case let .int(item)?: value = Double(item)
        case let .double(item)?: value = item
        default: return nil
        }
        return value.isFinite ? value : nil
    }
    private func string(_ key: String) -> String? {
        guard case let .string(value)? = state.attributes[key] else { return nil }
        return value
    }
    private func boolean(_ key: String) -> Bool? {
        guard case let .bool(value)? = state.attributes[key] else { return nil }
        return value
    }
}

enum FanSliderKey: String, CaseIterable {
    case up = "ArrowUp", right = "ArrowRight", down = "ArrowDown", left = "ArrowLeft"
    case pageUp = "PageUp", pageDown = "PageDown", home = "Home", end = "End"
}

enum FanValueMapping {
    /// JavaScript Math.round ties toward positive infinity, unlike Swift's default.
    static func round(_ value: Double) -> Double {
        let lower = floor(value)
        return value - lower < 0.5 ? lower : ceil(value)
    }
    static func speedCount(step: Double) -> Int? {
        guard step.isFinite, step > 0 else { return nil }
        let count = round(100 / step) + 1
        guard count.isFinite, count >= 2, count < Double(Int.max) else { return nil }
        return Int(count)
    }
    static func speeds(count: Int) -> [FanSpeed]? {
        switch count {
        case 2: return [.off, .on]
        case 3: return [.off, .low, .high]
        case 4: return [.off, .low, .medium, .high]
        default: return nil
        }
    }
    static func speed(percentage: Double, step: Double) -> FanSpeed {
        guard percentage.isFinite, let count = speedCount(step: step), let options = speeds(count: count) else { return .off }
        let index = round(percentage / step)
        guard index.isFinite, index >= 0, index < Double(options.count) else { return .off }
        return options[Int(index)]
    }
    /// Invalid/unavailable choices are not manufactured into an Off service.
    static func percentage(speed: FanSpeed, step: Double) -> Double? {
        guard let count = speedCount(step: step), let options = speeds(count: count),
              let index = options.firstIndex(of: speed) else { return nil }
        return floor(Double(index) * step)
    }
    static func bounded(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }
    static func stepped(_ value: Double, step: Double) -> Double? {
        guard value.isFinite, speedCount(step: step) != nil else { return nil }
        let result = round(value / step) * step
        return result.isFinite ? result : nil
    }
    /// Top-origin coordinates, as in the reference DOM. Drag geometry is unsnapped.
    static func pointerValue(y: Double, top: Double, height: Double) -> Double? {
        guard y.isFinite, top.isFinite, height.isFinite, height > 0 else { return nil }
        let progress = 1 - (y - top) / height
        guard progress.isFinite else { return nil }
        return min(max(progress, 0), 1) * 100
    }
    static func pointerCommit(y: Double, top: Double, height: Double, step: Double) -> Double? {
        pointerValue(y: y, top: top, height: height).flatMap { stepped($0, step: step) }
    }
    /// Returns the keydown draft only; a mounted owner commits on keyup.
    static func keyboard(_ key: FanSliderKey, value: Double?, step: Double, rtl: Bool = false) -> Double? {
        guard speedCount(step: step) != nil, (value ?? 0).isFinite else { return nil }
        switch key {
        case .home: return 0
        case .end: return 100
        case .pageUp, .pageDown:
            let delta = max(step, 10) * (key == .pageUp ? 1 : -1)
            return bounded((value ?? 0) + delta).flatMap { stepped($0, step: step) }
        default:
            let increases = key == .up || (key == .right && !rtl) || (key == .left && rtl)
            return bounded((value ?? 0) + step * (increases ? 1 : -1))
        }
    }
}

struct FanServiceRequest: Equatable {
    let domain: String
    let service: String
    let data: [String: JSONValue]
}

/// No transport, drafts, busy flag, or shared-state mutation. Preset duplicate
/// suppression belongs to FanServiceController, not this builder.
enum FanServiceBuilder {
    /// Revalidate untrusted/raw requests at dispatch against the latest entity.
    /// Numeric JSON representations may differ; never normalize their payload.
    static func isSupported(_ request: FanServiceRequest, entity: FanEntity) -> Bool {
        guard request.domain == "fan", request.data["entity_id"] == .string(entity.entityID) else { return false }
        let expected: FanServiceRequest?
        switch request.service {
        case "turn_on", "turn_off": expected = power(on: request.service == "turn_on", entity: entity)
        case "set_percentage":
            let value: Double
            switch request.data["percentage"] {
            case let .int(number)?: value = Double(number)
            case let .double(number)?: value = number
            default: return false
            }
            guard percentage(value, entity: entity) != nil else { return false }
            return Set(request.data.keys) == ["entity_id", "percentage"]
        case "set_preset_mode":
            guard case let .string(value)? = request.data["preset_mode"] else { return false }
            expected = preset(value, entity: entity)
        case "set_direction":
            guard case let .string(value)? = request.data["direction"], let direction = FanDirection(rawValue: value) else { return false }
            expected = self.direction(direction, entity: entity)
        case "oscillate":
            guard case let .bool(value)? = request.data["oscillating"] else { return false }
            expected = oscillation(value, entity: entity)
        default: return false
        }
        return expected == request
    }

    static func percentage(_ value: Double, entity: FanEntity) -> FanServiceRequest? {
        guard entity.features.contains(.setSpeed), entity.speedCount != nil,
              value.isFinite, (0...100).contains(value) else { return nil }
        return request("set_percentage", data: ["percentage": .double(value)], entity: entity)
    }
    static func speed(_ speed: FanSpeed, entity: FanEntity) -> FanServiceRequest? {
        guard let step = entity.step, let value = FanValueMapping.percentage(speed: speed, step: step) else { return nil }
        return percentage(value, entity: entity)
    }
    static func power(on: Bool, entity: FanEntity) -> FanServiceRequest? {
        request(on ? "turn_on" : "turn_off", data: [:], entity: entity)
    }
    static func togglePower(entity: FanEntity) -> FanServiceRequest? {
        power(on: entity.state.state != "on", entity: entity)
    }
    static func preset(_ value: String, entity: FanEntity) -> FanServiceRequest? {
        guard !value.isEmpty, entity.presetModes?.contains(value) == true else { return nil }
        return request("set_preset_mode", data: ["preset_mode": .string(value)], entity: entity)
    }
    static func direction(_ value: FanDirection, entity: FanEntity) -> FanServiceRequest? {
        guard entity.features.contains(.direction), entity.direction != value.rawValue else { return nil }
        return request("set_direction", data: ["direction": .string(value.rawValue)], entity: entity)
    }
    static func oscillation(_ value: Bool, entity: FanEntity) -> FanServiceRequest? {
        guard entity.features.contains(.oscillate), entity.oscillating != value else { return nil }
        return request("oscillate", data: ["oscillating": .bool(value)], entity: entity)
    }
    private static func request(_ service: String, data: [String: JSONValue], entity: FanEntity) -> FanServiceRequest? {
        guard entity.isFan, !entity.unavailable else { return nil }
        var payload = data
        payload["entity_id"] = .string(entity.entityID)
        return FanServiceRequest(domain: "fan", service: service, data: payload)
    }
}
