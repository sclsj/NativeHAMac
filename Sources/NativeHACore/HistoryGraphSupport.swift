import Foundation

public struct HAHistoryTimelinePoint: Equatable {
    public let timestamp: Double
    public let state: String
    public let display: String

    public init(timestamp: Double, state: String, display: String? = nil) {
        self.timestamp = timestamp
        self.state = state
        self.display = display ?? state
    }
}

public struct HAHistoryTimelineSegment: Equatable {
    public let state: String
    public let display: String
    public let start: Double
    public let end: Double
    public let clippedStart: Double
    public let clippedEnd: Double

    public init(
        state: String,
        display: String,
        start: Double,
        end: Double,
        clippedStart: Double,
        clippedEnd: Double
    ) {
        self.state = state
        self.display = display
        self.start = start
        self.end = end
        self.clippedStart = clippedStart
        self.clippedEnd = clippedEnd
    }
}

public enum HAHistoryTimelineBuilder {
    public static func segments(
        from points: [HAHistoryTimelinePoint],
        visibleStart: Double,
        visibleEnd: Double,
        endTime: Double? = nil
    ) -> [HAHistoryTimelineSegment] {
        guard visibleEnd > visibleStart else {
            return []
        }

        let timelineEnd = endTime ?? visibleEnd
        let states = deduplicated(points: points)
            .filter { $0.timestamp <= timelineEnd }

        guard !states.isEmpty else {
            return []
        }

        var output: [HAHistoryTimelineSegment] = []
        output.reserveCapacity(states.count)

        for index in states.indices {
            let point = states[index]
            let nextStart = states.index(after: index) < states.endIndex
                ? states[states.index(after: index)].timestamp
                : timelineEnd
            let end = min(nextStart, timelineEnd)

            guard end > visibleStart, point.timestamp < visibleEnd else {
                continue
            }

            let clippedStart = min(max(point.timestamp, visibleStart), visibleEnd)
            let clippedEnd = min(max(end, visibleStart), visibleEnd)
            guard clippedEnd > clippedStart else {
                continue
            }

            output.append(HAHistoryTimelineSegment(
                state: point.state,
                display: point.display,
                start: point.timestamp,
                end: end,
                clippedStart: clippedStart,
                clippedEnd: clippedEnd
            ))
        }

        return output
    }

    public static func deduplicated(points: [HAHistoryTimelinePoint]) -> [HAHistoryTimelinePoint] {
        let sorted = points.enumerated().sorted {
            if $0.element.timestamp == $1.element.timestamp {
                return $0.offset < $1.offset
            }
            return $0.element.timestamp < $1.element.timestamp
        }

        var output: [HAHistoryTimelinePoint] = []
        output.reserveCapacity(sorted.count)
        for item in sorted {
            let point = item.element
            if output.last?.state == point.state {
                continue
            }
            output.append(point)
        }
        return output
    }
}

public struct HAHistoryTimelineColor: Equatable {
    public let name: String
    public let hex: String

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}

public enum HAHistoryTimelineColorResolver {
    public static let unavailable = HAHistoryTimelineColor(name: "state-unavailable", hex: "#bdbdbd")
    public static let unknown = HAHistoryTimelineColor(name: "state-unknown", hex: "#9e9e9e")
    public static let inactive = HAHistoryTimelineColor(name: "state-inactive", hex: "#44739e")
    public static let active = HAHistoryTimelineColor(name: "state-active", hex: "#fdd663")
    public static let activeBlue = HAHistoryTimelineColor(name: "state-active-blue", hex: "#039be5")
    public static let activeGreen = HAHistoryTimelineColor(name: "state-active-green", hex: "#43a047")
    public static let activeOrange = HAHistoryTimelineColor(name: "state-active-orange", hex: "#ff9800")
    public static let activeRed = HAHistoryTimelineColor(name: "state-active-red", hex: "#db4437")

    private static let categoricalPalette = [
        "#039be5",
        "#e91e63",
        "#43a047",
        "#ff9800",
        "#8e24aa",
        "#00acc1",
        "#7cb342",
        "#f4511e",
    ]

    public static func color(for state: String, entityID: String) -> HAHistoryTimelineColor {
        let normalized = state.lowercased()
        let domain = HAHistoryGraphClassifier.domain(from: entityID)

        switch normalized {
        case "unavailable":
            return unavailable
        case "unknown":
            return unknown
        case "off", "not_home", "closed", "inactive", "idle", "not running", "locked", "standby":
            return inactive
        case "on", "home", "open", "active", "running", "streaming":
            return activeColor(for: domain, state: normalized)
        default:
            if isInactiveDomainState(domain: domain, state: normalized) {
                return inactive
            }
            if isActiveDomainState(domain: domain, state: normalized) {
                return activeColor(for: domain, state: normalized)
            }
            let hex = categoricalPalette[stableIndex(for: "\(entityID)|\(normalized)", count: categoricalPalette.count)]
            return HAHistoryTimelineColor(name: "state-categorical", hex: hex)
        }
    }

    private static func activeColor(for domain: String, state: String) -> HAHistoryTimelineColor {
        switch domain {
        case "person", "device_tracker":
            return activeBlue
        case "binary_sensor":
            return state == "running" ? activeGreen : active
        case "fan", "switch", "input_boolean", "automation", "light":
            return active
        case "cover", "valve":
            return activeBlue
        case "alert", "plant", "update":
            return activeRed
        case "climate":
            return ["cool", "cooling"].contains(state) ? activeBlue : activeOrange
        default:
            return active
        }
    }

    private static func isInactiveDomainState(domain: String, state: String) -> Bool {
        switch domain {
        case "alarm_control_panel":
            return state == "disarmed"
        case "alert":
            return state == "idle"
        case "cover", "valve":
            return state == "closed"
        case "lock":
            return state == "locked"
        case "vacuum", "lawn_mower":
            return ["idle", "docked", "paused"].contains(state)
        case "media_player":
            return state == "standby"
        default:
            return false
        }
    }

    private static func isActiveDomainState(domain: String, state: String) -> Bool {
        switch domain {
        case "alarm_control_panel":
            return state != "disarmed"
        case "climate":
            return ["cool", "cooling", "heat", "heating"].contains(state)
        case "group":
            return ["on", "home", "open", "locked", "problem"].contains(state)
        case "timer":
            return state == "active"
        case "camera":
            return state == "streaming"
        default:
            return false
        }
    }

    private static func stableIndex(for value: String, count: Int) -> Int {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(max(count, 1)))
    }
}

public enum HAHistoryGraphClassifier {
    public static let stateUnit = "State"
    public static let blankUnit = ""

    private static let numericDomains: Set<String> = [
        "counter",
        "input_number",
        "number",
    ]

    private static let numericSensorDeviceClasses: Set<String> = [
        "absolute_humidity",
        "apparent_power",
        "aqi",
        "area",
        "atmospheric_pressure",
        "battery",
        "blood_glucose_concentration",
        "carbon_dioxide",
        "carbon_monoxide",
        "conductivity",
        "current",
        "data_rate",
        "data_size",
        "distance",
        "duration",
        "energy",
        "energy_distance",
        "energy_storage",
        "frequency",
        "gas",
        "humidity",
        "illuminance",
        "irradiance",
        "moisture",
        "monetary",
        "nitrogen_dioxide",
        "nitrogen_monoxide",
        "nitrous_oxide",
        "ozone",
        "ph",
        "pm1",
        "pm10",
        "pm25",
        "pm4",
        "power",
        "power_factor",
        "precipitation",
        "precipitation_intensity",
        "pressure",
        "radon",
        "reactive_energy",
        "reactive_power",
        "signal_strength",
        "sound_pressure",
        "speed",
        "sulphur_dioxide",
        "temperature",
        "temperature_delta",
        "volatile_organic_compounds",
        "volatile_organic_compounds_parts",
        "voltage",
        "volume",
        "volume_flow_rate",
        "volume_storage",
        "water",
        "weight",
        "wind_direction",
        "wind_speed",
    ]

    public static func displayUnit(
        entityID: String,
        currentUnit: String?,
        currentAttributes: [String: JSONValue]?,
        history: HAHistorySeries
    ) -> String {
        if isTimeline(
            entityID: entityID,
            currentAttributes: currentAttributes,
            history: history
        ) {
            return stateUnit
        }

        return currentUnit
            ?? unit(from: currentAttributes)
            ?? unitFromHistory(history)
            ?? blankUnit
    }

    public static func isTimeline(
        entityID: String,
        currentAttributes: [String: JSONValue]?,
        history: HAHistorySeries
    ) -> Bool {
        !isNumeric(
            entityID: entityID,
            currentAttributes: currentAttributes,
            history: history
        )
    }

    public static func isNumeric(
        entityID: String,
        currentAttributes: [String: JSONValue]?,
        history: HAHistorySeries
    ) -> Bool {
        let domain = domain(from: entityID)
        if numericDomains.contains(domain) {
            return true
        }

        if let attributes = currentAttributes {
            if isNumericFromAttributes(attributes) {
                return true
            }
            if domain == "sensor",
               let deviceClass = attributes.stringValue(for: "device_class"),
               numericSensorDeviceClasses.contains(deviceClass) {
                return true
            }
            return false
        }

        return history.points.contains { point in
            guard let attributes = point.attributes else {
                return false
            }
            if isNumericFromAttributes(attributes) {
                return true
            }
            if domain == "sensor",
               let deviceClass = attributes.stringValue(for: "device_class"),
               numericSensorDeviceClasses.contains(deviceClass) {
                return true
            }
            return false
        }
    }

    public static func domain(from entityID: String) -> String {
        String(entityID.split(separator: ".", maxSplits: 1).first ?? "")
    }

    private static func isNumericFromAttributes(_ attributes: [String: JSONValue]) -> Bool {
        attributes["unit_of_measurement"] != nil || attributes["state_class"] != nil
    }

    private static func unitFromHistory(_ history: HAHistorySeries) -> String? {
        for point in history.points {
            if let unit = unit(from: point.attributes) {
                return unit
            }
        }
        return nil
    }

    private static func unit(from attributes: [String: JSONValue]?) -> String? {
        attributes?.stringValue(for: "unit_of_measurement")
    }
}

public struct HAHistoryTimestampParser {
    public init() {}

    public func timestamp(from point: HAHistoryPoint) -> Double? {
        if let value = point.lastChanged, let timestamp = parse(value) {
            return timestamp
        }
        if let value = point.lastUpdated, let timestamp = parse(value) {
            return timestamp
        }
        return nil
    }

    private func parse(_ value: String) -> Double? {
        if let timestamp = parseFast(value) {
            return timestamp
        }
        // Home Assistant's canonical timestamp shape must not fall through to
        // Foundation, whose formatter normalizes invalid calendar and offset
        // fields. Alternate ISO-8601 forms retain the compatibility fallback.
        guard !Self.hasCanonicalPrefix(value) else { return nil }
        return HAISO8601Fallback.shared.timestamp(from: value)
    }

    private func parseFast(_ value: String) -> Double? {
        value.utf8.withContiguousStorageIfAvailable { bytes in
            Self.parseCanonicalISO8601(bytes)
        } ?? nil
    }

    private static func parseCanonicalISO8601(
        _ bytes: UnsafeBufferPointer<UInt8>
    ) -> Double? {
        guard bytes.count >= 20 else { return nil }

        @inline(__always)
        func digit(_ index: Int) -> Int? {
            let byte = bytes[index]
            guard byte >= 48, byte <= 57 else { return nil }
            return Int(byte - 48)
        }

        @inline(__always)
        func twoDigits(_ index: Int) -> Int? {
            guard let first = digit(index), let second = digit(index + 1) else { return nil }
            return first * 10 + second
        }

        guard
            bytes[4] == 45,
            bytes[7] == 45,
            bytes[10] == 84,
            bytes[13] == 58,
            bytes[16] == 58,
            let yearThousands = digit(0),
            let yearHundreds = digit(1),
            let yearTens = digit(2),
            let yearOnes = digit(3),
            let month = twoDigits(5),
            let day = twoDigits(8),
            let hour = twoDigits(11),
            let minute = twoDigits(14),
            let second = twoDigits(17)
        else { return nil }

        let year = yearThousands * 1_000 + yearHundreds * 100 + yearTens * 10 + yearOnes
        guard year >= 1970, hour < 24, minute < 60, second < 60 else { return nil }

        let isLeap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let monthDays = [0, 31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard month >= 1, month <= 12, day >= 1, day <= monthDays[month] else { return nil }

        var index = 19
        var fractionalSeconds = 0.0
        if bytes[index] == 46 {
            index += 1
            let fractionalStart = index
            var place = 0.1
            while index < bytes.count, let value = digit(index) {
                fractionalSeconds += Double(value) * place
                place *= 0.1
                index += 1
            }
            guard index > fractionalStart else { return nil }
        }

        var offsetSeconds = 0
        if index < bytes.count, bytes[index] == 90 {
            index += 1
        } else {
            guard
                index + 6 == bytes.count,
                bytes[index] == 43 || bytes[index] == 45,
                bytes[index + 3] == 58,
                let offsetHour = twoDigits(index + 1),
                let offsetMinute = twoDigits(index + 4),
                offsetHour < 24,
                offsetMinute < 60
            else { return nil }
            let magnitude = offsetHour * 3_600 + offsetMinute * 60
            offsetSeconds = bytes[index] == 43 ? magnitude : -magnitude
            index += 6
        }
        guard index == bytes.count else { return nil }

        var days = day - 1
        for precedingMonth in 1..<month {
            days += monthDays[precedingMonth]
        }
        let priorYear = year - 1
        let leapDays = (priorYear / 4 - priorYear / 100 + priorYear / 400) -
            (1969 / 4 - 1969 / 100 + 1969 / 400)
        days += (year - 1970) * 365 + leapDays

        return Double(days * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds) +
            fractionalSeconds
    }

    private static func hasCanonicalPrefix(_ value: String) -> Bool {
        value.utf8.withContiguousStorageIfAvailable { bytes in
            guard bytes.count >= 19 else { return false }
            let digitIndices = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
            guard digitIndices.allSatisfy({ bytes[$0] >= 48 && bytes[$0] <= 57 }) else {
                return false
            }
            return bytes[4] == 45 && bytes[7] == 45 && bytes[10] == 84 &&
                bytes[13] == 58 && bytes[16] == 58
        } ?? false
    }
}

private final class HAISO8601Fallback: @unchecked Sendable {
    static let shared = HAISO8601Fallback()

    private let lock = NSLock()
    private let normal = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func timestamp(from value: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return (fractional.date(from: value) ?? normal.date(from: value))?.timeIntervalSince1970
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(for key: String) -> String? {
        guard case let .string(value) = self[key] else {
            return nil
        }
        return value
    }
}
