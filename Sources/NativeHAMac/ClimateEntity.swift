import Foundation
import NativeHACore

struct ClimateEntityFeature: OptionSet {
    let rawValue: Int
    static let targetTemperature = Self(rawValue: 1)
    static let targetRange = Self(rawValue: 2)
    static let targetHumidity = Self(rawValue: 4)
    static let fanMode = Self(rawValue: 8)
    static let presetMode = Self(rawValue: 16)
    static let swingMode = Self(rawValue: 32)
    static let auxiliaryHeat = Self(rawValue: 64)
    static let turnOff = Self(rawValue: 128)
    static let turnOn = Self(rawValue: 256)
    static let horizontalSwingMode = Self(rawValue: 512)
}

enum ClimateTarget: String { case value, low, high, humidity }
enum ClimateMainControl: String { case temperature, humidity }
enum ClimateTargetKind { case single, range, readOnly }

struct ClimateEntity {
    let state: HAState
    let unit: String
    var entityID: String { state.entityId }
    var unavailable: Bool { state.state == "unavailable" }
    var active: Bool { !["off", "unknown", "unavailable"].contains(state.state) }
    var features: ClimateEntityFeature {
        guard let value = number("supported_features"), value >= 0, value < Double(Int.max), value.rounded(.towardZero) == value else { return [] }
        return ClimateEntityFeature(rawValue: Int(value))
    }
    var currentTemperature: Double? { number("current_temperature") }
    var currentHumidity: Double? { number("current_humidity") }
    var step: Double {
        let supplied = number("target_temp_step") ?? 0
        return supplied > 0 ? supplied : (unit == "°F" ? 1 : 0.5)
    }
    var humidityStep: Double { max(number("target_humidity_step") ?? 1, 0) }
    var temperatureBounds: ClosedRange<Double>? { bounds(number("min_temp"), number("max_temp")) }
    var humidityBounds: ClosedRange<Double>? { bounds(number("min_humidity") ?? 0, number("max_humidity") ?? 100) }
    var targetKind: ClimateTargetKind {
        if features.contains(.targetTemperature), value(.value) != nil { return .single }
        if features.contains(.targetRange), value(.low) != nil, value(.high) != nil { return .range }
        return .readOnly
    }
    var hvacModes: [String] {
        let order = ["auto", "heat_cool", "heat", "cool", "dry", "fan_only", "off"]
        return (strings("hvac_modes") ?? []).enumerated().sorted {
            guard let lhs = order.firstIndex(of: $0.element), let rhs = order.firstIndex(of: $1.element) else { return $0.offset < $1.offset }
            return lhs < rhs
        }.map(\.element)
    }
    var actionLabel: String {
        if unavailable { return "Unavailable" }
        if let action = string("hvac_action"), action != "off", !action.isEmpty { return Self.label(action) }
        return targetKind == .readOnly ? "" : Self.label(state.state)
    }

    init(state: HAState, unit: String?) { self.state = state; self.unit = unit ?? "" }

    func number(_ name: String) -> Double? {
        let value: Double
        switch state.attributes[name] {
        case let .double(item)?: value = item
        case let .int(item)?: value = Double(item)
        default: return nil
        }
        return value.isFinite ? value : nil
    }
    func string(_ name: String) -> String? {
        guard case let .string(value)? = state.attributes[name] else { return nil }
        return value
    }
    func strings(_ name: String) -> [String]? {
        guard case let .array(values)? = state.attributes[name] else { return nil }
        return values.compactMap { if case let .string(value) = $0 { return value }; return nil }
    }
    func value(_ target: ClimateTarget) -> Double? { number(Self.attribute(target)) }
    func canAdjust(_ target: ClimateTarget) -> Bool {
        guard !unavailable else { return false }
        switch target {
        case .value: return targetKind == .single && temperatureBounds != nil
        case .low, .high: return targetKind == .range && temperatureBounds != nil && (value(.low) ?? 0) <= (value(.high) ?? 0)
        case .humidity: return features.contains(.targetHumidity) && value(.humidity) != nil && humidityBounds != nil && humidityStep > 0
        }
    }
    func options(_ attribute: String) -> [String]? {
        let feature: ClimateEntityFeature
        switch attribute {
        case "preset_mode": feature = .presetMode
        case "fan_mode": feature = .fanMode
        case "swing_mode": feature = .swingMode
        case "swing_horizontal_mode": feature = .horizontalSwingMode
        default: return nil
        }
        return features.contains(feature) ? strings(attribute + "s") : nil
    }
    static func attribute(_ target: ClimateTarget) -> String {
        switch target { case .value: return "temperature"; case .low: return "target_temp_low"; case .high: return "target_temp_high"; case .humidity: return "humidity" }
    }
    static func label(_ raw: String) -> String {
        let known = ["auto": "Auto", "heat_cool": "Heat/Cool", "heat": "Heat", "cool": "Cool", "dry": "Dry", "fan_only": "Fan only", "off": "Off", "unknown": "Unknown", "unavailable": "Unavailable", "idle": "Idle", "cooling": "Cooling", "heating": "Heating", "preheating": "Preheating", "defrosting": "Defrosting", "drying": "Drying", "fan": "Fan", "none": "None", "sleep": "Sleep", "activity": "Activity", "on": "On"]
        return known[raw] ?? raw
    }
    private func bounds(_ minimum: Double?, _ maximum: Double?) -> ClosedRange<Double>? {
        guard let minimum = minimum, let maximum = maximum, minimum < maximum else { return nil }
        return minimum...maximum
    }
}

struct ClimateServiceRequest: Equatable {
    let service: String
    let data: [String: JSONValue]
}

enum ClimateServiceBuilder {
    static func isSupported(_ request: ClimateServiceRequest, entity: ClimateEntity) -> Bool {
        guard request.data["entity_id"] == .string(entity.entityID), !entity.unavailable else { return false }
        let targets: [ClimateTarget]
        switch request.service {
        case "set_temperature": targets = request.data["temperature"] == nil ? [.low, .high] : [.value]
        case "set_humidity": targets = [.humidity]
        case "turn_on", "turn_off": return power(on: request.service == "turn_on", entity: entity) == request
        default:
            let attribute = String(request.service.dropFirst(4))
            guard case let .string(value)? = request.data[attribute] else { return false }
            return mode(attribute, value: value, entity: entity) == request
        }
        guard Set(request.data.keys) == Set(["entity_id"] + targets.map(ClimateEntity.attribute)) else { return false }
        if targets == [.low, .high], case let .double(low)? = request.data["target_temp_low"], case let .double(high)? = request.data["target_temp_high"], low > high + entity.step / 2 + 1e-10 { return false }
        return targets.allSatisfy { target in
            guard entity.canAdjust(target), case let .double(value)? = request.data[ClimateEntity.attribute(target)] else { return false }
            // Pointer rounding follows HA, including a half-step past an off-grid
            // bound or neighbor. Reject arbitrary external values beyond that envelope.
            guard value.isFinite, let bounds = target == .humidity ? entity.humidityBounds : entity.temperatureBounds else { return false }
            let step = target == .humidity ? entity.humidityStep : entity.step
            return value >= bounds.lowerBound - step / 2 && value <= bounds.upperBound + step / 2
        }
    }
    static func target(_ target: ClimateTarget, values: [ClimateTarget: Double], entity: ClimateEntity) -> ClimateServiceRequest? {
        guard entity.canAdjust(target) else { return nil }
        let targets: [ClimateTarget] = target == .low || target == .high ? [.low, .high] : [target]
        var data: [String: JSONValue] = ["entity_id": .string(entity.entityID)]
        for item in targets {
            guard let value = values[item], value.isFinite else { return nil }
            data[ClimateEntity.attribute(item)] = .double(value)
        }
        let request = ClimateServiceRequest(service: target == .humidity ? "set_humidity" : "set_temperature", data: data)
        return isSupported(request, entity: entity) ? request : nil
    }
    static func mode(_ attribute: String, value: String, entity: ClimateEntity) -> ClimateServiceRequest? {
        guard !entity.unavailable else { return nil }
        let options = attribute == "hvac_mode" ? entity.hvacModes : entity.options(attribute)
        let old = attribute == "hvac_mode" ? entity.state.state : entity.string(attribute)
        guard options?.contains(value) == true, old != value, attribute != "preset_mode" || !value.isEmpty else { return nil }
        return ClimateServiceRequest(service: "set_" + attribute, data: ["entity_id": .string(entity.entityID), attribute: .string(value)])
    }
    static func power(on: Bool, entity: ClimateEntity) -> ClimateServiceRequest? {
        guard !entity.unavailable, entity.features.contains(on ? .turnOn : .turnOff) else { return nil }
        return ClimateServiceRequest(service: on ? "turn_on" : "turn_off", data: ["entity_id": .string(entity.entityID)])
    }
}

enum ClimateValueMapping {
    static func clamp(_ value: Double, _ bounds: ClosedRange<Double>) -> Double { min(max(value, bounds.lowerBound), bounds.upperBound) }
    static func stepped(_ value: Double, step: Double) -> Double { floor(value / step + 0.5) * step }
    static func progress(at point: CGPoint, size: CGSize) -> Double {
        let phi = atan2((point.y - size.height / 2) / size.height, (point.x - size.width / 2) / size.width) * 180 / .pi
        let angle = (phi - 90 + 360).truncatingRemainder(dividingBy: 360) - 45
        return min(max(angle / 270, 0), 1)
    }
    static func adjusted(_ value: Double, target: ClimateTarget, values: [ClimateTarget: Double], entity: ClimateEntity, snap: Bool) -> Double? {
        guard value.isFinite, entity.canAdjust(target), let bounds = target == .humidity ? entity.humidityBounds : entity.temperatureBounds else { return nil }
        var result = clamp(value, bounds)
        if target == .low, let high = values[.high] { result = min(result, high) }
        if target == .high, let low = values[.low] { result = max(result, low) }
        return snap ? stepped(result, step: target == .humidity ? entity.humidityStep : entity.step) : result
    }
}
