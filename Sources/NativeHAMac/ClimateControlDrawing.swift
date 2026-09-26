import SwiftUI

/// The established single-target renderer is shared with its geometry regressions.
/// Extra capabilities retain their existing rendering without changing that surface.
struct ClimateControlDrawing: View {
    let entity: ClimateEntity
    let mainControl: ClimateMainControl
    let values: [ClimateTarget: Double]

    var body: some View {
        if mainControl == .temperature, entity.targetKind == .single,
           !entity.unavailable, let bounds = entity.temperatureBounds,
           let target = values[.value] ?? entity.value(.value) {
            ClimateDialDrawing(
                targetProgress: progress(target, bounds: bounds),
                currentProgress: entity.currentTemperature.map { progress($0, bounds: bounds) },
                isCooling: entity.state.state == "cool",
                hasTemperatureDifference: entity.currentTemperature.map { abs($0 - target) > 0.05 } ?? false
            )
        } else {
            ClimateCapabilityDrawing(entity: entity, mainControl: mainControl, values: values)
        }
    }

    private func progress(_ value: Double, bounds: ClosedRange<Double>) -> Double {
        ClimateValueMapping.clamp((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound), 0...1)
    }

    static func modeColor(_ mode: String) -> Color { ClimateCapabilityDrawing.modeColor(mode) }
}

struct ClimateCapabilityDrawing: View, Animatable {
    let entity: ClimateEntity
    let mainControl: ClimateMainControl
    var values: [ClimateTarget: Double]
    private var currentTemperature: Double?
    private var currentHumidity: Double?
    init(entity: ClimateEntity, mainControl: ClimateMainControl, values: [ClimateTarget: Double]) {
        self.entity = entity
        self.mainControl = mainControl
        self.values = values
        currentTemperature = entity.currentTemperature
        currentHumidity = entity.currentHumidity
    }
    typealias TargetVector = AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>
    var animatableData: TargetVector {
        get { TargetVector(AnimatablePair(values[.value] ?? entity.value(.value) ?? 0, values[.low] ?? entity.value(.low) ?? 0), AnimatablePair(values[.high] ?? entity.value(.high) ?? 0, values[.humidity] ?? entity.value(.humidity) ?? 0)) }
        set {
            if values[.value] != nil || entity.value(.value) != nil { values[.value] = newValue.first.first }
            if values[.low] != nil || entity.value(.low) != nil { values[.low] = newValue.first.second }
            if values[.high] != nil || entity.value(.high) != nil { values[.high] = newValue.second.first }
            if values[.humidity] != nil || entity.value(.humidity) != nil { values[.humidity] = newValue.second.second }
        }
    }

    static func modeColor(_ mode: String) -> Color {
        switch mode {
        case "heat": return Color(red: 1, green: 111 / 255, blue: 34 / 255)
        case "cool": return Color(red: 33 / 255, green: 150 / 255, blue: 243 / 255)
        case "dry": return Color(red: 1, green: 152 / 255, blue: 0)
        case "fan_only": return Color(red: 0, green: 188 / 255, blue: 212 / 255)
        case "auto": return Color(red: 76 / 255, green: 175 / 255, blue: 80 / 255)
        default: return Color(red: 1, green: 193 / 255, blue: 7 / 255)
        }
    }
    static func actionColor(_ entity: ClimateEntity) -> Color? {
        guard entity.active, let action = entity.string("hvac_action"), let mode = ["cooling": "cool", "heating": "heat", "preheating": "heat", "defrosting": "heat", "drying": "dry", "fan": "fan_only"][action] else { return nil }
        return modeColor(mode)
    }

    var body: some View {
        Canvas { context, size in
            let geometry = ClimateDialGeometry(size: size)
            let humidity = mainControl == .humidity
            let validBounds = humidity ? entity.humidityBounds : entity.temperatureBounds
            let bounds = validBounds ?? 0...1
            let current = humidity ? currentHumidity : currentTemperature
            let stroke = StrokeStyle(lineWidth: min(size.width, size.height) * 24 / 320, lineCap: .round)
            func progress(_ value: Double) -> Double { ClimateValueMapping.clamp((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound), 0...1) }
            func path(_ from: Double, _ to: Double) -> Path {
                var path = Path()
                path.addArc(center: geometry.center, radius: geometry.radius, startAngle: .degrees(135 + 270 * from), endAngle: .degrees(135 + 270 * to), clockwise: false)
                return path
            }
            func dot(_ value: Double, diameter: CGFloat, color: Color) {
                let point = geometry.point(progress(value))
                context.fill(Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)), with: .color(color))
            }
            context.stroke(path(0, 1), with: .color(.white.opacity(0.10)), style: stroke)
            guard validBounds != nil else {
                if !humidity, entity.targetKind == .readOnly, entity.active { context.stroke(path(0, 1), with: .color(Self.modeColor(entity.state.state).opacity(0.5)), style: stroke) }
                return
            }
            if let current = current { dot(current, diameter: 8, color: .white.opacity(0.5)) }
            guard !entity.unavailable else { return }
            let targets: [ClimateTarget] = humidity ? [.humidity] : entity.targetKind == .range ? [.low, .high] : entity.targetKind == .single ? [.value] : []
            if targets.isEmpty, !humidity, entity.active {
                context.stroke(path(0, 1), with: .color(Self.modeColor(entity.state.state).opacity(0.5)), style: stroke)
                if let current = current, bounds.contains(current) { dot(current, diameter: 8, color: Color(red: 0.09, green: 0.095, blue: 0.1)) }
            }
            for target in targets {
                guard let value = values[target] ?? entity.value(target) else { continue }
                let mode: String
                if target == .low { mode = "heat" }
                else if target == .high { mode = "cool" }
                else if humidity { mode = "heat" }
                else {
                    let modes = entity.hvacModes.filter { ["heat", "cool", "heat_cool"].contains($0) }
                    mode = modes.count == 1 && ["off", "auto"].contains(entity.state.state) ? modes[0] : entity.state.state
                }
                let color: Color = Self.modeColor(humidity ? "cool" : mode)
                let fraction = progress(value)
                if entity.active {
                    let start = mode == "cool" ? fraction : 0
                    let end = mode == "heat" ? fraction : 1
                    context.stroke(path(start, end), with: .color(color.opacity(0.5)), style: stroke)
                    let currentValue = current ?? (mode == "cool" ? bounds.upperBound : bounds.lowerBound)
                    if mode == "cool", value <= currentValue {
                        context.stroke(path(fraction, progress(currentValue)), with: .color(color), style: stroke)
                    } else if mode == "heat", currentValue <= value {
                        context.stroke(path(progress(currentValue), fraction), with: .color(color), style: stroke)
                    }
                    if let current = current, bounds.contains(current), mode == "cool" && value <= current || mode == "heat" && current <= value || !["heat", "cool"].contains(mode) {
                        dot(current, diameter: 8, color: Color(red: 0.09, green: 0.095, blue: 0.1))
                    }
                }
                dot(value, diameter: 24, color: entity.active ? color : .white)
                dot(value, diameter: 18, color: .white)
            }
        }
    }
}
