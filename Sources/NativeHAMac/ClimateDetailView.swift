import AppKit
import NativeHACore
import SwiftUI

struct ClimateDetailContent: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let state: HAState
    @StateObject private var controller = ClimateServiceController()
    private var entity: ClimateEntity { ClimateEntity(state: state, unit: model.homeAssistantConfig?.unitSystem?.temperature) }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                if let value = entity.currentTemperature { reading("Current temperature", value: value, unit: entity.unit) }
                if let value = entity.currentHumidity { reading("Current humidity", value: value, unit: "%") }
            }
            ClimateControlDial(entity: entity, controller: controller)
                .frame(width: 320, height: 320)
                .disabled(!model.canInvokeClimate(entityID: entityID, service: controller.mainControl == .humidity ? "set_humidity" : "set_temperature"))
            if entity.features.contains(.targetHumidity) {
                Picker("Control", selection: Binding(get: { controller.mainControl }, set: { controller.selectMain($0) })) {
                    Text("Temperature").tag(ClimateMainControl.temperature)
                    Text("Humidity").tag(ClimateMainControl.humidity)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .disabled(entity.unavailable)
            }
            HStack(spacing: 10) {
                modeMenu("Mode", attribute: "hvac_mode", options: entity.hvacModes, current: state.state)
                if let options = entity.options("preset_mode") {
                    modeMenu("Preset", attribute: "preset_mode", options: options, current: entity.string("preset_mode"))
                }
            }
            if ["fan_mode", "swing_mode", "swing_horizontal_mode"].contains(where: { entity.options($0) != nil }) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                    ForEach(["fan_mode", "swing_mode", "swing_horizontal_mode"], id: \.self) { attribute in
                    if let options = entity.options(attribute) {
                        modeMenu(menuTitle(attribute), attribute: attribute, options: options, current: entity.string(attribute))
                    }
                    }
                }
            }
            if let error = controller.error {
                Text(error).foregroundColor(.red).font(.system(size: 12)).accessibilityLabel(Text("Climate control error: " + error))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            let detailGeneration = model.climateDetailGeneration
            controller.install(entity: entity) { [weak model] request, completion in
                guard let model = model, model.climateDetailGeneration == detailGeneration else { return false }
                return model.invokeClimate(request, entityID: entityID, completion: completion)
            }
        }
        .onChange(of: state) { _ in controller.replace(entity) }
        .onChange(of: model.climateEntityRevision) { _ in controller.replace(entity) }
        .onChange(of: model.climateDetailGeneration) { _ in controller.close() }
        .onDisappear { controller.close() }
    }

    private func reading(_ label: String, value: Double, unit: String) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.55))
            Text(ClimateNumberFormatting.format(value, digits: nil, unit: unit, preferences: model.frontendLocalePreferences)).font(.system(size: 20, weight: .semibold))
        }.frame(maxWidth: .infinity)
    }

    private func menuTitle(_ attribute: String) -> String {
        ["preset_mode": "Preset", "fan_mode": "Fan", "swing_mode": "Swing", "swing_horizontal_mode": "Horizontal swing"][attribute] ?? attribute
    }

    private func modeMenu(_ title: String, attribute: String, options: [String], current: String?) -> some View {
        ClimateModeMenu(title: title, symbol: ["hvac_mode": "power", "preset_mode": "figure.walk", "fan_mode": "fanblades", "swing_mode": "arrow.left.and.right", "swing_horizontal_mode": "arrow.left.and.right"][attribute] ?? "power", options: options, current: current, enabled: !options.isEmpty && model.canInvokeClimate(entityID: entityID, service: "set_" + attribute)) { controller.mode(attribute, value: $0) }
            .frame(width: attribute == "swing_horizontal_mode" ? 148 : 122, height: 56)
    }
}

struct ClimateControlDial: View {
    let entity: ClimateEntity
    @ObservedObject var controller: ClimateServiceController
    @State private var gestureTarget: ClimateTarget?
    @State private var gestureStarted = false
    @State private var isDragging = false
    @EnvironmentObject private var model: DashboardViewModel

    private var humidity: Bool { controller.mainControl == .humidity }
    private var target: ClimateTarget { humidity ? .humidity : entity.targetKind == .range ? controller.selectedTarget : .value }
    private var bounds: ClosedRange<Double>? { humidity ? entity.humidityBounds : entity.temperatureBounds }
    private var current: Double? { humidity ? entity.currentHumidity : entity.currentTemperature }
    private var isDual: Bool { !humidity && entity.targetKind == .range }
    private var unit: String { humidity ? "%" : entity.unit }
    private var step: Double { humidity ? entity.humidityStep : entity.step }

    var body: some View {
        GeometryReader { geometry in
            let metrics = ClimateDialGeometry(size: geometry.size)
            ZStack {
                ClimateControlDrawing(entity: entity, mainControl: controller.mainControl, values: controller.values)
                    .animation(isDragging || !entity.canAdjust(target) ? nil : climateTargetAnimation, value: visibleTargets)
                    .allowsHitTesting(false)
                ClimateDialInput(isEnabled: entity.canAdjust(target), value: displayed(target), bounds: bounds, onPointer: { point, phase in pointer(point, phase: phase, geometry: metrics) }, onKey: { key, released in keyboard(key, released: released) })
                    .accessibilityLabel(Text(humidity ? "Target humidity" : "Target temperature"))
                VStack(spacing: 4) {
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center).frame(width: 192).frame(minHeight: 24)
                    if isDual {
                        HStack(spacing: 16) { targetButton(.low); targetButton(.high) }
                    } else if let value = displayed(target), entity.targetKind != .readOnly || humidity {
                        ClimateLargeNumber(value: value, digits: humidity ? 0 : ClimateNumberFormatting.digits(step), unit: unit, preferences: model.frontendLocalePreferences)
                            .frame(minHeight: 64)
                    } else if !entity.unavailable {
                        Text(ClimateEntity.label(entity.state.state)).font(.system(size: 32))
                            .frame(minHeight: 64)
                    }
                    Text("").font(.system(size: 13, weight: .medium)).frame(width: 192).frame(minHeight: 24)
                }
                .frame(width: 230)
                .allowsHitTesting(isDual)
                if entity.canAdjust(target) {
                    VStack {
                        Spacer()
                        HStack(spacing: 24) {
                            adjustmentButton("minus", direction: -1)
                            adjustmentButton("plus", direction: 1)
                        }.padding(.bottom, 10)
                    }
                }
            }
        }
        .onChange(of: entity.canAdjust(target)) { adjustable in if !adjustable { resetGesture() } }
        .onChange(of: controller.mainControl) { _ in resetGesture() }
        .onDisappear { resetGesture() }
    }

    private var visibleTargets: [Double?] { humidity ? [displayed(.humidity)] : isDual ? [displayed(.low), displayed(.high)] : [displayed(.value)] }
    private var climateTargetAnimation: Animation {
        let policy = AppConfig.climateInteractionPolicy
        return .timingCurve(policy.animationCurve.x1, policy.animationCurve.y1, policy.animationCurve.x2, policy.animationCurve.y2, duration: policy.animationSeconds)
    }
    private func resetGesture() { gestureTarget = nil; gestureStarted = false; isDragging = false }

    private var label: String {
        if !humidity { return entity.actionLabel }
        if entity.unavailable { return "Unavailable" }
        return displayed(.humidity) == 0 || displayed(.humidity) == nil ? ClimateEntity.label(entity.state.state) : "Target humidity"
    }
    private func displayed(_ target: ClimateTarget) -> Double? { controller.value(target, fallback: entity) }
    private func formatted(_ value: Double) -> String { ClimateNumberFormatting.format(value, digits: humidity ? 0 : ClimateNumberFormatting.digits(step), unit: unit, preferences: model.frontendLocalePreferences) }
    private func targetButton(_ target: ClimateTarget) -> some View {
        Button {
            controller.selectTarget(target)
        } label: {
            ClimateLargeNumber(value: displayed(target) ?? 0, digits: ClimateNumberFormatting.digits(step), unit: unit, preferences: model.frontendLocalePreferences)
                .opacity(controller.selectedTarget == target ? 1 : 0.6)
        }.buttonStyle(.plain).accessibilityLabel(Text(target == .low ? "Low target" : "High target"))
    }
    private func adjustmentButton(_ symbol: String, direction: Double) -> some View {
        ClimateAdjustmentButton(symbol: symbol, label: direction < 0 ? "Decrease target" : "Increase target", color: isDual && entity.active ? ClimateControlDrawing.modeColor(target == .high ? "cool" : "heat") : Color.white.opacity(0.45)) { controller.button(direction, target: target) }.frame(width: 48, height: 48)
    }
    private func pointer(_ point: CGPoint, phase: ClimatePointerPhase, geometry: ClimateDialGeometry) {
        if phase == .cancel { resetGesture(); return }
        guard let bounds = bounds, entity.canAdjust(target) else { resetGesture(); return }
        if phase == .down {
            guard geometry.contains(point) else { return }
            gestureStarted = true
            isDragging = false
            gestureTarget = nil
            return
        }
        guard gestureStarted else { return }
        let raw = bounds.lowerBound + ClimateValueMapping.progress(at: point, size: geometry.size) * (bounds.upperBound - bounds.lowerBound)
        if gestureTarget == nil {
            if isDual, let low = displayed(.low), let high = displayed(.high) {
                gestureTarget = raw <= low ? .low : raw >= high ? .high : abs(raw - low) <= abs(raw - high) ? .low : .high
            } else { gestureTarget = target }
        }
        let selected = gestureTarget ?? target
        let direct = isDragging || phase == .move
        if phase == .move { isDragging = true }
        // A press alone is a click: its release animates. A recognized drag,
        // including its final release mapping, tracks the pointer directly.
        var transaction = Transaction(animation: direct ? nil : climateTargetAnimation)
        transaction.disablesAnimations = direct
        withTransaction(transaction) { controller.change(raw, target: selected) }
        if phase == .up {
            controller.commit(selected)
            resetGesture()
        }
    }
    private func keyboard(_ key: UInt16, released: Bool) {
        guard entity.canAdjust(target), let bounds = bounds, let value = displayed(target) else { return }
        if released { controller.commit(target); return }
        let next: Double
        switch key {
        case 123, 125: next = value - step
        case 124, 126: next = value + step
        case 116: next = value + max(step, (bounds.upperBound - bounds.lowerBound) / 10)
        case 121: next = value - max(step, (bounds.upperBound - bounds.lowerBound) / 10)
        case 115: next = bounds.lowerBound
        case 119: next = bounds.upperBound
        default: return
        }
        controller.change(next, target: target, snap: key == 116 || key == 121)
    }
}

enum ClimatePointerPhase { case down, move, up, cancel }

struct ClimateAdjustmentButton: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    let symbol: String
    let label: String
    let color: Color
    let action: () -> Void
    func makeNSView(context: Context) -> ClimateAdjustmentNSButton { ClimateAdjustmentNSButton() }
    func updateNSView(_ button: ClimateAdjustmentNSButton, context: Context) {
        button.isEnabled = enabled
        button.onPress = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
        button.contentTintColor = .white
        button.setAccessibilityLabel(label)
        button.layer?.borderColor = NSColor(color).cgColor
    }
}

final class ClimateAdjustmentNSButton: NSButton {
    var onPress: (() -> Void)?
    override var intrinsicContentSize: NSSize { NSSize(width: 48, height: 48) }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.borderWidth = 1
        target = self
        action = #selector(pressed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { onPress?() }
}

struct ClimateModeMenu: NSViewRepresentable {
    let title: String
    let symbol: String
    let options: [String]
    let current: String?
    let enabled: Bool
    let action: (String) -> Void
    func makeNSView(context: Context) -> ClimateModeNSButton { ClimateModeNSButton() }
    func updateNSView(_ button: ClimateModeNSButton, context: Context) {
        button.isEnabled = enabled
        button.options = options
        button.selected = current
        button.onSelection = action
        button.titleLabel = title
        button.valueLabel = current.flatMap { options.contains($0) ? ClimateEntity.label($0) : nil }
        button.symbol = symbol
        button.needsDisplay = true
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(current.map(ClimateEntity.label))
    }
}

final class ClimateModeNSButton: NSButton {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    var options: [String] = []
    var selected: String?
    var onSelection: ((String) -> Void)?
    var titleLabel = ""
    var valueLabel: String?
    var symbol = "power"
    override var intrinsicContentSize: NSSize { NSSize(width: 122, height: 56) }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        alignment = .left
        cell?.wraps = true
        cell?.lineBreakMode = .byTruncatingTail
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        layer?.cornerRadius = 8
        target = self
        action = #selector(showOptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let opacity: CGFloat = isEnabled ? 1 : 0.45
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 16, weight: .semibold).applying(.init(paletteColors: [.white])))
        image?.draw(in: CGRect(x: 10, y: (bounds.height - 20) / 2, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.58 * opacity)]
        let valueAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(opacity)]
        (titleLabel as NSString).draw(in: CGRect(x: 39, y: 13, width: bounds.width - 49, height: 14), withAttributes: titleAttributes)
        ((valueLabel ?? "Unavailable") as NSString).draw(in: CGRect(x: 39, y: 29, width: bounds.width - 49, height: 15), withAttributes: valueAttributes)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
    @objc private func showOptions() {
        let menu = NSMenu()
        for option in options {
            let item = NSMenuItem(title: ClimateEntity.label(option), action: #selector(selectOption(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = selected == option ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height), in: self)
    }
    @objc private func selectOption(_ item: NSMenuItem) { if let raw = item.representedObject as? String { onSelection?(raw) } }
}

struct ClimateLargeNumber: View {
    let value: Double
    let digits: Int
    let unit: String
    let preferences: HAFrontendLocalePreferences?
    var body: some View {
        let number = ClimateNumberFormatting.format(value, digits: digits, unit: "", preferences: preferences)
        let cut = digits > 0 ? number.index(number.endIndex, offsetBy: -(digits + 1), limitedBy: number.startIndex) ?? number.endIndex : number.endIndex
        HStack(alignment: .bottom, spacing: 0) {
            Text(String(number[..<cut])).font(.system(size: 57, weight: .medium))
            VStack(alignment: .leading, spacing: 0) {
                Text(unit).font(.system(size: 57 * 0.33, weight: .medium))
                Text(String(number[cut...])).font(.system(size: 57 * 0.42, weight: .medium)).frame(minHeight: 57 * 0.42 * 1.33, alignment: .bottom)
            }.padding(.vertical, 4)
        }.lineLimit(1).minimumScaleFactor(0.7)
    }
}

struct ClimateDialInput: NSViewRepresentable {
    @Environment(\.isEnabled) private var environmentEnabled
    let isEnabled: Bool
    let value: Double?
    let bounds: ClosedRange<Double>?
    let onPointer: (CGPoint, ClimatePointerPhase) -> Void
    let onKey: (UInt16, Bool) -> Void
    func makeNSView(context: Context) -> ClimateDialNSView { ClimateDialNSView() }
    func updateNSView(_ view: ClimateDialNSView, context: Context) {
        view.isEnabled = isEnabled && environmentEnabled
        view.onPointer = onPointer
        view.onKey = onKey
        view.setAccessibilityRole(.slider)
        view.setAccessibilityEnabled(view.isEnabled)
        view.setAccessibilityValue(value.map(NSNumber.init(value:)))
        view.setAccessibilityMinValue(bounds.map { NSNumber(value: $0.lowerBound) })
        view.setAccessibilityMaxValue(bounds.map { NSNumber(value: $0.upperBound) })
    }
}

final class ClimateDialNSView: NSView {
    var isEnabled = true
    var onPointer: ((CGPoint, ClimatePointerPhase) -> Void)?
    var onKey: ((UInt16, Bool) -> Void)?
    private var start: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func draw(_ dirtyRect: NSRect) {
        guard window?.firstResponder === self, isEnabled else { return }
        let geometry = ClimateDialGeometry(size: bounds.size)
        let path = NSBezierPath()
        for index in 0...100 {
            let point = geometry.point(Double(index) / 100)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.lineWidth = 28
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.45).setStroke()
        path.stroke()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { ClimateDialGeometry(size: bounds.size).contains(convert(point, from: superview)) ? super.hitTest(point) : nil }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        start = point
        onPointer?(point, .down)
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let start = start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - start.x, point.y - start.y) > AppConfig.climateInteractionPolicy.dragThreshold { onPointer?(point, .move) }
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        onPointer?(convert(event.locationInWindow, from: nil), isEnabled ? .up : .cancel)
    }
    override func cancelOperation(_ sender: Any?) { start = nil; onPointer?(.zero, .cancel) }
    override func keyDown(with event: NSEvent) {
        guard isEnabled, [123,124,125,126,115,119,116,121].contains(Int(event.keyCode)) else { super.keyDown(with: event); return }
        onKey?(event.keyCode, false)
    }
    override func keyUp(with event: NSEvent) {
        guard isEnabled, [123,124,125,126,115,119,116,121].contains(Int(event.keyCode)) else { super.keyUp(with: event); return }
        onKey?(event.keyCode, true)
    }
}

struct ClimateDialGeometry {
    let size: CGSize
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var radius: CGFloat { min(size.width, size.height) * 145 / 320 }
    func point(_ progress: Double) -> CGPoint {
        let angle: Double = (135 + 270 * min(max(progress, 0), 1)) * Double.pi / 180
        let x: Double = cos(angle)
        let y: Double = sin(angle)
        return CGPoint(x: center.x + CGFloat(x) * radius, y: center.y + CGFloat(y) * radius)
    }
    func contains(_ point: CGPoint) -> Bool {
        let width = min(size.width, size.height) * 24 / 320
        let distance = hypot(point.x - center.x, point.y - center.y)
        let phi = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        return abs(distance - radius) <= width && (phi >= 135 || phi <= 45)
    }
}

enum ClimateNumberFormatting {
    static func digits(_ step: Double) -> Int {
        guard step.isFinite, step > 0 else { return 0 }
        var value = step
        for digit in 0..<10 { if abs(value - value.rounded()) < 1e-8 { return digit }; value *= 10 }
        return 10
    }
    static func format(_ value: Double, digits: Int?, unit: String, preferences: HAFrontendLocalePreferences?) -> String {
        let metadata = GraphTooltipFormattingResolver.metadata(entityID: "", state: nil, registryDisplayPrecision: digits ?? 2, preferences: preferences, serverTimeZone: nil, policy: GraphTooltipFormattingPolicy())
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: metadata.numberLocaleIdentifier)
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = metadata.usesGroupingSeparator
        formatter.minimumFractionDigits = digits ?? 0
        formatter.maximumFractionDigits = digits ?? 2
        let number = formatter.string(from: NSNumber(value: value)) ?? String(value)
        let space = unit == "%" && !["cs","de","fi","fr","sk","sv"].contains(preferences?.language ?? "en") ? "" : " "
        return unit.isEmpty ? number : number + space + unit
    }
}
