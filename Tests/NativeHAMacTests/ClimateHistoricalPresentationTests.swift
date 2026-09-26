import AppKit
import NativeHACore
import SwiftUI
import XCTest
@testable import NativeHAMac

/// Presentation-only extraction from 3f8d15f:CardViews.swift. Callbacks are inert:
/// no historical entity fallbacks, predictions, or service ownership are used.
@MainActor
final class ClimateHistoricalPresentationTests: XCTestCase {
    func testHistoricalInterruptedTargetTransition() throws {
        _ = NSApplication.shared
        let source = HistoricalMotionSource()
        let host = NSHostingView(rootView: HistoricalMotionHost(source: source).background(Color(red: 0.09, green: 0.095, blue: 0.1)))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-recovery-baseline")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func capture(_ name: String, after delay: Double) throws {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: delay))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]))
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        try capture("motion-00-initial", after: 0.1)
        source.target = 0.9
        try capture("motion-01-settled", after: 0.4)
        source.target = 0.1
        try capture("motion-02-outbound", after: 0.1)
        source.target = 0.8
        try capture("motion-03-reverse-start", after: 0.01)
        try capture("motion-04-reverse-middle", after: 0.1)
        try capture("motion-05-reverse-final", after: 0.3)
    }

    func testHistoricalWholeDetailAndTransitionFixtures() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-recovery-baseline")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, state) in try ClimateFixtures.states() {
            let entity = ClimateEntity(state: state, unit: "°C")
            guard entity.targetKind == .single, let target = entity.value(.value), let current = entity.currentTemperature, let bounds = entity.temperatureBounds else { continue }
            let model = DashboardViewModel(initialStates: [entity.entityID: state])
            for width in [520, 360] {
                let content = VStack(spacing: 18) {
                    VStack(spacing: 5) {
                        Text("Current temperature").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.55))
                        Text(formatTemperature(current, unit: entity.unit)).font(.system(size: 20, weight: .semibold))
                    }
                    HistoricalClimateTemperatureDial(target: target, current: current, minimum: bounds.lowerBound, maximum: bounds.upperBound, step: entity.step, unit: entity.unit, hvacMode: state.state, actionLabel: entity.actionLabel, onSetTarget: { _ in })
                        .frame(width: 320, height: 320)
                    HStack(spacing: 10) {
                        menuControl(title: "Mode", value: ClimateEntity.label(state.state), systemName: "power", options: entity.hvacModes) { _ in }
                        if let options = entity.options("preset_mode") {
                            menuControl(title: "Preset", value: ClimateEntity.label(entity.string("preset_mode") ?? ""), systemName: "figure.walk", options: options) { _ in }
                        }
                    }
                }.frame(maxWidth: .infinity)
                let view: AnyView
                if width == 520 {
                    view = AnyView(VStack(alignment: .leading, spacing: 0) {
                        EntityPanelHeader(entityID: entity.entityID)
                        Divider().background(Color.white.opacity(0.08))
                        ScrollView { content.padding(22) }
                    }.frame(width: 520, height: 620))
                } else {
                    view = AnyView(ScrollView { content.padding(20) })
                }
                let image = try MacViewPNGRenderer.render(view.environmentObject(model).foregroundColor(.white).background(Color(red: 0.09, green: 0.095, blue: 0.1)), size: CGSize(width: width, height: 620), displayScale: 2, settleTime: 0.03)
                try image.pngData.write(to: directory.appendingPathComponent("\(name)-\(width)x620.png"))
            }
        }
        for progress in [0.0, 0.5, 1.0] {
            let image = try MacViewPNGRenderer.render(HistoricalClimateDialDrawing(targetProgress: progress, currentProgress: 0.7, isCooling: true, hasTemperatureDifference: true), size: CGSize(width: 320, height: 320), displayScale: 2)
            try image.pngData.write(to: directory.appendingPathComponent("target-\(progress).png"))
        }
    }
}

private final class HistoricalMotionSource: ObservableObject {
    @Published var target = 1.0 / 9
}

private struct HistoricalMotionHost: View {
    @ObservedObject var source: HistoricalMotionSource
    var body: some View {
        HistoricalClimateDialDrawing(targetProgress: source.target, currentProgress: 0.5222, isCooling: true, hasTemperatureDifference: true)
            .animation(haSliderAnimation, value: source.target)
    }
}

private struct HistoricalClimateTemperatureDial: View {
    let target: Double
    let current: Double
    let minimum: Double
    let maximum: Double
    let step: Double
    let unit: String
    let hvacMode: String
    let actionLabel: String
    let onSetTarget: (Double) -> Void
    @State private var draftTarget: Double?
    @State private var dragStart: CGPoint?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let metrics = DialMetrics(size: geometry.size)
            let targetValue = displayedTarget
            let targetProgress = progress(for: targetValue)
            let currentProgress = progress(for: current)

            ZStack {
                HistoricalClimateDialDrawing(
                    targetProgress: targetProgress,
                    currentProgress: currentProgress,
                    isCooling: hvacMode == "cool",
                    hasTemperatureDifference: abs(current - targetValue) > 0.05
                )
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard metrics.containsSliderPoint(value.location) else {
                                    return
                                }

                                if dragStart == nil {
                                    dragStart = value.startLocation
                                }

                                if dragDistance(from: dragStart ?? value.startLocation, to: value.location) > 4 {
                                    isDragging = true
                                    var transaction = Transaction()
                                    transaction.animation = nil
                                    withTransaction(transaction) {
                                        draftTarget = temperature(at: value.location, metrics: metrics)
                                    }
                                }
                            }
                            .onEnded { value in
                                guard metrics.containsSliderPoint(value.location) else {
                                    dragStart = nil
                                    isDragging = false
                                    return
                                }

                                let newTarget = temperature(at: value.location, metrics: metrics)
                                if isDragging {
                                    var transaction = Transaction()
                                    transaction.animation = nil
                                    withTransaction(transaction) {
                                        draftTarget = newTarget
                                    }
                                } else {
                                    withAnimation(haSliderAnimation) {
                                        draftTarget = newTarget
                                    }
                                }
                                dragStart = nil
                                isDragging = false
                                onSetTarget(newTarget)
                            }
                    )

                VStack(spacing: 4) {
                    Text(actionLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(width: metrics.infoWidth)
                        .frame(minHeight: 24)
                    HistoricalBigTemperatureText(
                        value: targetValue,
                        unit: unit,
                        fractionDigits: fractionDigits(for: step)
                    )
                    .frame(minHeight: 64)
                    Text("")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: metrics.infoWidth)
                        .frame(minHeight: 24)
                }
                .position(metrics.center)

                VStack {
                    Spacer()
                    HStack(spacing: 24) {
                        roundActionButton(systemName: "minus") {
                            setTargetFromButton(displayedTarget - step)
                        }
                        roundActionButton(systemName: "plus") {
                            setTargetFromButton(displayedTarget + step)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(isDragging ? nil : haSliderAnimation, value: displayedTarget)
        .onChange(of: target) { newValue in
            if let draftTarget = draftTarget, abs(draftTarget - newValue) <= max(step, 0.1) * 0.55 {
                self.draftTarget = nil
            }
        }
    }

    private var displayedTarget: Double {
        draftTarget ?? target
    }

    private func progress(for value: Double) -> Double {
        guard maximum > minimum else {
            return 0
        }
        return Swift.min(Swift.max((value - minimum) / (maximum - minimum), 0), 1)
    }

    private func temperature(at location: CGPoint, metrics: DialMetrics) -> Double {
        let progress = metrics.progress(at: location)
        let snap = max(step, 0.1)
        let raw = minimum + progress * (maximum - minimum)
        let snapped = (raw / snap).rounded() * snap
        return Swift.min(Swift.max(snapped, minimum), maximum)
    }

    private func setTargetFromButton(_ value: Double) {
        let clamped = Swift.min(Swift.max(value, minimum), maximum)
        let snap = max(step, 0.1)
        let snapped = (clamped / snap).rounded() * snap
        withAnimation(haSliderAnimation) {
            draftTarget = snapped
        }
        onSetTarget(snapped)
    }

    private func dragDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }
}

private struct HistoricalBigTemperatureText: View {
    let value: Double
    let unit: String
    let fractionDigits: Int

    var body: some View {
        let parts = splitTemperature(value, fractionDigits: fractionDigits)

        HStack(alignment: .bottom, spacing: 0) {
            Text(parts.integer)
                .font(.system(size: 57, weight: .medium))
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 0) {
                Text(unit)
                    .font(.system(size: 57 * 0.33, weight: .medium))
                    .lineLimit(1)
                Text(parts.decimal)
                    .font(.system(size: 57 * 0.42, weight: .medium))
                    .frame(minHeight: 57 * 0.42 * 1.33, alignment: .bottom)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct HistoricalClimateDialDrawing: View, Animatable {
    var targetProgress: Double
    let currentProgress: Double
    let isCooling: Bool
    let hasTemperatureDifference: Bool

    var animatableData: Double {
        get { targetProgress }
        set { targetProgress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let metrics = DialMetrics(size: size)
            let style = StrokeStyle(lineWidth: metrics.trackStrokeWidth, lineCap: .round, lineJoin: .round)
            let highlightStart = Swift.min(targetProgress, currentProgress)
            let highlightEnd = Swift.max(targetProgress, currentProgress)

            context.stroke(
                dialArcPath(metrics: metrics, from: 0, to: 1),
                with: .color(Color.white.opacity(0.10)),
                style: style
            )

            if isCooling, hasTemperatureDifference {
                context.stroke(
                    dialArcPath(metrics: metrics, from: highlightStart, to: highlightEnd),
                    with: .color(Color(red: 0.10, green: 0.48, blue: 0.95)),
                    style: style
                )
            }

            context.fill(
                circlePath(center: metrics.point(progress: currentProgress), diameter: 7),
                with: .color(Color.white.opacity(0.9))
            )

            let targetPoint = metrics.point(progress: targetProgress)
            context.addFilter(.shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1))
            context.fill(
                circlePath(center: targetPoint, diameter: 24),
                with: .color(targetOuterColor)
            )
            context.fill(
                circlePath(center: targetPoint, diameter: 18),
                with: .color(.white)
            )
        }
    }

    private var targetOuterColor: Color {
        isCooling ? Color(red: 0.10, green: 0.48, blue: 0.95) : Color.white.opacity(0.25)
    }
}

private struct DialMetrics {
    static let startAngle = 135.0
    static let sweepAngle = 270.0

    private let scale: CGFloat
    let center: CGPoint
    let radius: CGFloat
    let trackStrokeWidth: CGFloat
    let infoWidth: CGFloat

    init(size: CGSize) {
        self.scale = Swift.min(size.width, size.height) / 320
        self.center = CGPoint(x: size.width / 2, y: size.height / 2)
        self.radius = 145 * scale
        self.trackStrokeWidth = 24 * scale
        self.infoWidth = 192 * scale
    }

    func point(progress: Double) -> CGPoint {
        let clamped = Swift.min(Swift.max(progress, 0), 1)
        let angle = CGFloat((Self.startAngle + Self.sweepAngle * clamped) * .pi / 180)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    func progress(at point: CGPoint) -> Double {
        var angle = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if angle < 0 {
            angle += 360
        }

        let endAngle = Self.startAngle + Self.sweepAngle
        let wrappedEndAngle = endAngle - 360
        if angle < Self.startAngle {
            if angle <= wrappedEndAngle {
                angle += 360
            } else {
                let distanceToStart = Self.startAngle - angle
                let distanceToEnd = angle - wrappedEndAngle
                angle = distanceToStart <= distanceToEnd ? Self.startAngle : endAngle
            }
        }

        let clamped = Swift.min(Swift.max(angle, Self.startAngle), endAngle)
        return (clamped - Self.startAngle) / Self.sweepAngle
    }

    func containsSliderPoint(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let hitWidth = max(trackStrokeWidth * 1.45, 34)
        guard distance >= radius - hitWidth, distance <= radius + hitWidth else {
            return false
        }

        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 {
            angle += 360
        }

        let endAngle = Self.startAngle + Self.sweepAngle
        let wrappedEndAngle = endAngle - 360
        return angle >= Self.startAngle || angle <= wrappedEndAngle
    }
}

private func dialArcPath(metrics: DialMetrics, from: Double, to: Double) -> Path {
    let start = Swift.min(Swift.max(from, 0), 1)
    let end = Swift.min(Swift.max(to, 0), 1)
    let lower = Swift.min(start, end)
    let upper = Swift.max(start, end)
    let steps = max(Int((upper - lower) * 120), 2)
    var path = Path()

    for index in 0...steps {
        let progress = lower + (upper - lower) * Double(index) / Double(steps)
        let point = metrics.point(progress: progress)
        if index == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }

    return path
}

private func circlePath(center: CGPoint, diameter: CGFloat) -> Path {
    Path(ellipseIn: CGRect(
        x: center.x - diameter / 2,
        y: center.y - diameter / 2,
        width: diameter,
        height: diameter
    ))
}

private func roundActionButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .medium))
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .background(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
    }
    .buttonStyle(.plain)
}

private let haSliderAnimation = Animation.timingCurve(0.42, 0, 0.58, 1, duration: 0.30)

private func menuControl(
    title: String,
    value: String,
    systemName: String,
    options: [String],
    action: @escaping (String) -> Void
) -> some View {
    Menu {
        ForEach(options, id: \.self) { option in
            Button(prettyMode(option)) {
                action(option)
            }
        }
    } label: {
        HStack(spacing: 9) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                Text(value.isEmpty ? "Unavailable" : value)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .frame(minWidth: 102, minHeight: 40)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
        .cornerRadius(8)
    }
    .buttonStyle(.plain)
    .menuStyle(BorderlessButtonMenuStyle())
    .disabled(options.isEmpty)
}

private func prettyMode(_ value: String) -> String {
    if value == "none" {
        return "None"
    }
    if value == "fan_only" {
        return "Fan only"
    }
    return value
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
}

private func formatTemperature(_ value: Double, unit: String) -> String {
    "\(formatTemperatureValue(value)) \(unit)"
}

private func formatTemperatureValue(_ value: Double) -> String {
    abs(value.rounded() - value) < 0.05
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
}

private func fractionDigits(for step: Double) -> Int {
    let positiveStep = abs(step)
    guard positiveStep > 0 else {
        return 0
    }

    var digits = 0
    var scaled = positiveStep
    while digits < 3, abs(scaled.rounded() - scaled) > 0.000001 {
        scaled *= 10
        digits += 1
    }

    return max(digits, positiveStep < 1 ? 1 : 0)
}

private func splitTemperature(_ value: Double, fractionDigits: Int) -> (integer: String, decimal: String) {
    let formatted = String(format: "%.\(fractionDigits)f", value)
    guard fractionDigits > 0 else {
        return (formatted, "")
    }

    let parts = formatted.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let integer = parts.first.map(String.init) ?? formatted
    let decimalValue = parts.count > 1 ? String(parts[1]) : String(repeating: "0", count: fractionDigits)
    return (integer, ".\(decimalValue)")
}
