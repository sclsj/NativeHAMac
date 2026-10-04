import SwiftUI

/// All target capabilities share the reference's directional arc semantics.
struct ClimateControlDrawing: View {
    let entity: ClimateEntity
    let mainControl: ClimateMainControl
    let values: [ClimateTarget: Double]
    var targetAnimation: Animation? = nil
    // Presentation history only: fade the last drawn mode to neutral when
    // HA reports Off, without replacing or predicting the entity's state.
    @State private var lastActiveMode: String?

    var body: some View {
        ClimateModeFadeDrawing(entity: entity, mainControl: mainControl, values: values, targetAnimation: targetAnimation, fadingMode: entity.active ? entity.state.state : lastActiveMode, activeFraction: entity.active ? 1 : 0)
            .animation(.easeInOut(duration: AppConfig.climateInteractionPolicy.modeFadeSeconds), value: entity.active)
            .onAppear { if entity.active { lastActiveMode = entity.state.state } }
            .onChange(of: entity.state.state) { mode in
                if !["off", "unknown", "unavailable"].contains(mode) { lastActiveMode = mode }
            }
    }

    static func modeColor(_ mode: String) -> Color { ClimateCapabilityDrawing.modeColor(mode) }
}

/// Separate animation owners preserve the target's 300ms motion when a
/// server update changes both target and active state in the same turn.
private struct ClimateModeFadeDrawing: View, Animatable {
    let entity: ClimateEntity
    let mainControl: ClimateMainControl
    let values: [ClimateTarget: Double]
    let targetAnimation: Animation?
    let fadingMode: String?
    var activeFraction: Double
    var animatableData: Double {
        get { activeFraction }
        set { activeFraction = newValue }
    }
    var body: some View {
        ClimateCapabilityDrawing(entity: entity, mainControl: mainControl, values: values, activeFraction: activeFraction, fadingMode: fadingMode)
            .animation(targetAnimation, value: visibleTargets)
    }
    private var visibleTargets: [Double?] {
        let targets: [ClimateTarget] = mainControl == .humidity ? [.humidity] : entity.targetKind == .range ? [.low, .high] : [.value]
        return targets.map { values[$0] ?? entity.value($0) }
    }
}

struct ClimateCapabilityDrawing: View, Animatable {
    let entity: ClimateEntity
    let mainControl: ClimateMainControl
    var values: [ClimateTarget: Double]
    private var currentTemperature: Double?
    private var currentHumidity: Double?
    private let activeFraction: Double
    private let fadingMode: String?
    init(entity: ClimateEntity, mainControl: ClimateMainControl, values: [ClimateTarget: Double], activeFraction: Double? = nil, fadingMode: String? = nil) {
        self.entity = entity
        self.mainControl = mainControl
        self.values = values
        currentTemperature = entity.currentTemperature
        currentHumidity = entity.currentHumidity
        self.activeFraction = activeFraction ?? (entity.active ? 1 : 0)
        self.fadingMode = fadingMode
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
        let rgb = modeComponents(mode)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
    private static func modeComponents(_ mode: String) -> (Double, Double, Double) {
        switch mode {
        case "heat": return (1, 111 / 255, 34 / 255)
        case "cool": return (33 / 255, 150 / 255, 243 / 255)
        case "dry": return (1, 152 / 255, 0)
        case "fan_only": return (0, 188 / 255, 212 / 255)
        case "auto": return (76 / 255, 175 / 255, 80 / 255)
        default: return (1, 193 / 255, 7 / 255)
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
            let clearBackground = Color(white: 17 / 255)
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
            context.stroke(path(0, 1), with: .color(Color(white: 70 / 255).opacity(0.3)), style: stroke)
            guard validBounds != nil else {
                if !humidity, entity.targetKind == .readOnly { context.stroke(path(0, 1), with: .color(Self.modeColor(fadingMode ?? entity.state.state).opacity(0.5 * activeFraction)), style: stroke) }
                return
            }
            if let current = current { dot(current, diameter: 8, color: Color(white: 225 / 255).opacity(0.5)) }
            guard !entity.unavailable else { return }
            let targets: [ClimateTarget] = humidity ? [.humidity] : entity.targetKind == .range ? [.low, .high] : entity.targetKind == .single ? [.value] : []
            if targets.isEmpty, !humidity, activeFraction > 0 {
                context.opacity = activeFraction
                context.stroke(path(0, 1), with: .color(Self.modeColor(fadingMode ?? entity.state.state).opacity(0.5)), style: stroke)
                if let current = current, bounds.contains(current) { dot(current, diameter: 8, color: Color(red: 0.09, green: 0.095, blue: 0.1)) }
                context.opacity = 1
            }
            for target in targets {
                guard let value = values[target] ?? entity.value(target) else { continue }
                let mode: String
                if target == .low { mode = "heat" }
                else if target == .high { mode = "cool" }
                else if humidity { mode = "heat" }
                else {
                    let modes = entity.hvacModes.filter { ["heat", "cool", "heat_cool"].contains($0) }
                    let displayedMode = fadingMode ?? entity.state.state
                    mode = modes.count == 1 && ["off", "auto"].contains(displayedMode) ? modes[0] : displayedMode
                }
                let color: Color = Self.modeColor(humidity ? "cool" : mode)
                let fraction = progress(value)
                if activeFraction > 0 {
                    context.opacity = activeFraction
                    let start = mode == "cool" ? fraction : 0
                    let end = mode == "heat" ? fraction : 1
                    // HA's arc-clear layer prevents the neutral track from
                    // brightening the translucent mode arc underneath it.
                    context.stroke(path(start, end), with: .color(clearBackground), style: stroke)
                    context.stroke(path(start, end), with: .color(color.opacity(0.5)), style: stroke)
                    let currentValue = current ?? (mode == "cool" ? bounds.upperBound : bounds.lowerBound)
                    if mode == "cool", value <= currentValue {
                        context.stroke(path(fraction, progress(currentValue)), with: .color(color), style: stroke)
                    } else if mode == "heat", currentValue <= value {
                        context.stroke(path(progress(currentValue), fraction), with: .color(color), style: stroke)
                    }
                    if let current = current, bounds.contains(current), mode == "cool" && value <= current || mode == "heat" && current <= value || !["heat", "cool"].contains(mode) {
                        dot(current, diameter: 8, color: clearBackground.opacity(0.5))
                    }
                    context.opacity = 1
                }
                let rgb = Self.modeComponents(humidity ? "cool" : mode)
                let outline = Color(red: 0.62 + (rgb.0 - 0.62) * activeFraction, green: 0.62 + (rgb.1 - 0.62) * activeFraction, blue: 0.62 + (rgb.2 - 0.62) * activeFraction)
                dot(value, diameter: 24, color: outline)
                dot(value, diameter: 18, color: .white)
            }
        }
    }
}
