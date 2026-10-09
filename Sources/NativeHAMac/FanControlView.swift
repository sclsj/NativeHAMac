import AppKit
import NativeHACore
import SwiftUI

@MainActor
final class FanControlPresentation: ObservableObject {
    var inputOwner: ObjectIdentifier?
    @Published var shape: FanMainControl = .invalidSpeed
    @Published var value: Double = 0
    @Published var animatesValue = false
    @Published var checked = false
    @Published var speed: FanSpeed = .off
    @Published var rawActive = false
    @Published var rawOff = false
    @Published var unavailable = false
    @Published var focusedIndex: Int?
    @Published var keyboardFocus = false
    @Published var tooltip: String?
    var color: Color { unavailable ? Color(white: 111 / 255) : rawActive ? Color(red: 0, green: 188 / 255, blue: 212 / 255) : Color(white: 158 / 255) }
}

struct FanControlSurface: View {
    @ObservedObject var controller: FanServiceController
    var preferences: HAFrontendLocalePreferences?
    // Keep drawing in the enclosing SwiftUI tree, separate from native input.
    // State retains this reference; only the drawing subscribes to its changes.
    @State private var presentation = FanControlPresentation()
    var body: some View {
        ZStack {
            FanControlDrawing(presentation: presentation)
            FanControlInput(controller: controller, presentation: presentation, preferences: preferences)
        }
    }
}

private struct FanControlInput: NSViewRepresentable {
    @ObservedObject var controller: FanServiceController
    let presentation: FanControlPresentation
    var preferences: HAFrontendLocalePreferences?
    func makeNSView(context: Context) -> FanControlNSView { FanControlNSView(presentation: presentation) }
    func updateNSView(_ view: FanControlNSView, context: Context) { view.configure(controller: controller, preferences: preferences) }
    static func dismantleNSView(_ view: FanControlNSView, coordinator: ()) { view.retire(deferPresentation: true) }
}

final class FanControlNSView: NSView {
    let presentation: FanControlPresentation
    private weak var controller: FanServiceController?
    private var preferences: HAFrontendLocalePreferences?
    private var lastSliderBinding: Double?
    private var lastCheckedBinding: Bool?
    private var installedShape: FanMainControl?
    private var choiceGeneration = 0
    private var downPoint: CGPoint?
    private var downTime: TimeInterval = 0
    private var maxMovement: CGFloat = 0
    private var savedValue: Double = 0
    private(set) var dragging = false
    private var pressedKeys: Set<UInt16> = []
    private var tooltipTimer: Timer?
    private let policy = AppConfig.fanPolicy
    private var options: [FanSpeed] { if case let .discrete(values) = presentation.shape { return values.reversed() }; return [] }
    var enabled: Bool { controller?.entity.map { !$0.unavailable && $0.mainControl != .invalidSpeed && $0.mainControl == presentation.shape } ?? false }
    var ownsTooltipTimer: Bool { tooltipTimer != nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { enabled }
    init(presentation: FanControlPresentation) {
        self.presentation = presentation
        super.init(frame: .zero)
        setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); updateAccessibility() }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func becomeFirstResponder() -> Bool {
        presentation.keyboardFocus = true
        if !options.isEmpty { presentation.focusedIndex = options.firstIndex(of: presentation.speed) ?? 0 }
        return true
    }
    override func resignFirstResponder() -> Bool { presentation.keyboardFocus = false; presentation.focusedIndex = nil; cancelInput(); return true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { cancelInput() } }

    func configure(controller: FanServiceController, preferences: HAFrontendLocalePreferences?) {
        presentation.inputOwner = ObjectIdentifier(self)
        let newOwner = self.controller !== controller
        self.controller = controller; self.preferences = preferences
        let entity = controller.entity
        let shape = entity?.mainControl ?? .invalidSpeed
        let changedShape = installedShape != shape
        if newOwner || changedShape || entity?.unavailable != false { cancelInput() }
        if newOwner || changedShape { presentation.focusedIndex = nil; choiceGeneration += 1 }
        var transaction = Transaction(animation: newOwner || changedShape ? nil : .easeInOut(duration: policy.geometrySeconds))
        transaction.disablesAnimations = newOwner || changedShape || dragging
        withTransaction(transaction) {
            presentation.animatesValue = !newOwner && !changedShape && !dragging
            presentation.shape = shape
            presentation.rawActive = entity?.active ?? false
            presentation.rawOff = entity?.state.state == "off"
            presentation.unavailable = entity?.unavailable ?? true
            // Lit compares owner binding values, not state-object identity.
            // An equal replacement during drag leaves the child's own value.
            if newOwner || changedShape || lastSliderBinding != controller.sliderValue {
                presentation.value = controller.sliderValue ?? 0
                lastSliderBinding = controller.sliderValue
            }
            let checked = entity?.state.state == "on"
            if newOwner || changedShape || lastCheckedBinding != checked {
                presentation.checked = checked; lastCheckedBinding = checked
            }
            presentation.speed = controller.speedValue
        }
        installedShape = shape
        updateAccessibility()
    }

    func retire(deferPresentation: Bool = false) {
        controller = nil; installedShape = nil
        tooltipTimer?.invalidate(); tooltipTimer = nil
        if deferPresentation {
            downPoint = nil; dragging = false; pressedKeys.removeAll()
            let identity = ObjectIdentifier(self)
            DispatchQueue.main.async { [weak presentation] in
                guard let presentation = presentation, presentation.inputOwner == identity else { return }
                presentation.tooltip = nil; presentation.keyboardFocus = false
                presentation.inputOwner = nil
            }
        } else { cancelInput(); presentation.keyboardFocus = false }
    }
    private func cancelInput() {
        if dragging { setValue(savedValue, animated: false) }
        downPoint = nil; dragging = false; pressedKeys.removeAll()
        tooltipTimer?.invalidate(); tooltipTimer = nil; presentation.tooltip = nil
    }
    override func cancelOperation(_ sender: Any?) { cancelInput() }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        window?.makeFirstResponder(self); presentation.keyboardFocus = false
        controller?.inputBegan()
        tooltipTimer?.invalidate(); tooltipTimer = nil
        downPoint = convert(event.locationInWindow, from: nil); downTime = event.timestamp
        maxMovement = 0; dragging = false
        if !options.isEmpty || presentation.shape == .explicitPower, let point = downPoint { presentation.focusedIndex = optionIndex(point) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, let start = downPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        maxMovement = max(maxMovement, hypot(point.x - start.x, point.y - start.y))
        guard presentation.shape == .slider else { return }
        if dragging {
            if let value = FanValueMapping.pointerValue(y: Double(point.y), top: 0, height: Double(bounds.height)) { setValue(value, animated: false); showTooltip() }
        } else if maxMovement > policy.dragThreshold {
            dragging = true; savedValue = presentation.value; showTooltip()
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard enabled, let start = downPoint else { cancelInput(); return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - start.x, point.y - start.y)
        maxMovement = max(maxMovement, distance)
        let duration = max(event.timestamp - downTime, 0)
        let tapOrPress = maxMovement < policy.tapMovementLimit && (duration < policy.tapSeconds || duration > policy.pressSeconds)
        downPoint = nil
        switch presentation.shape {
        case .slider:
            guard dragging || distance > policy.dragThreshold || tapOrPress,
                  let step = controller?.entity?.step,
                  let value = FanValueMapping.pointerCommit(y: Double(point.y), top: 0, height: Double(bounds.height), step: step) else { dragging = false; return }
            let direct = dragging
            dragging = false; presentation.tooltip = nil
            setValue(value, animated: !direct); controller?.percentage(value)
        case .toggle:
            // Hammer's overall velocity is the dominant axis, not path distance.
            let verticalDistance = abs(point.y - start.y)
            let verticalSwipe = verticalDistance > abs(point.x - start.x) && distance > policy.dragThreshold && Double(verticalDistance) / max(duration, 0.001) > policy.swipePointsPerSecond
            if verticalSwipe { setChecked(point.y < start.y) }
            else if tapOrPress { setChecked(!presentation.checked) }
        case .explicitPower:
            if let index = optionIndex(point), optionIndex(start) == index { controller?.power(on: index == 0) }
        case .discrete:
            if let index = optionIndex(point), index == presentation.focusedIndex { controller?.speed(options[index]) }
        case .invalidSpeed: break
        }
        updateAccessibility()
    }
    private func optionIndex(_ point: CGPoint) -> Int? {
        let count = presentation.shape == .explicitPower ? 2 : options.count
        let padding = presentation.shape == .explicitPower ? policy.switchPadding : policy.selectionPadding
        return (0..<count).first { index in
            let rect = FanControlGeometry.optionRect(index: index, count: count, bounds: bounds, padding: padding)
            return NSBezierPath(roundedRect: rect, xRadius: policy.cornerRadius - padding, yRadius: policy.cornerRadius - padding).contains(point)
        }
    }
    override func keyDown(with event: NSEvent) {
        guard enabled else { return }
        let code = event.keyCode
        if code == 53 { cancelInput(); return }
        if [36, 49, 123, 124, 125, 126, 115, 119, 116, 121].contains(code) { controller?.inputBegan() }
        presentation.keyboardFocus = true
        switch presentation.shape {
        case .slider:
            guard let key = Self.sliderKey(code), let step = controller?.entity?.step,
                  let value = FanValueMapping.keyboard(key, value: presentation.value, step: step, rtl: userInterfaceLayoutDirection == .rightToLeft) else { super.keyDown(with: event); return }
            pressedKeys.insert(code)
            setValue(value, animated: true); showTooltip()
        case .discrete:
            guard !options.isEmpty else { return }
            let candidate = presentation.focusedIndex ?? options.firstIndex(of: presentation.speed) ?? 0
            let index = options.indices.contains(candidate) ? candidate : 0
            switch code {
            case 123, 126: presentation.focusedIndex = (index + options.count - 1) % options.count
            case 124, 125: presentation.focusedIndex = (index + 1) % options.count
            case 36, 49: controller?.speed(options[index])
            default: super.keyDown(with: event)
            }
        case .toggle:
            if code == 36 || code == 49 { setChecked(!presentation.checked) }
            else if code == 126, !presentation.checked { setChecked(true) }
            else if code == 125, presentation.checked { setChecked(false) }
            else { super.keyDown(with: event) }
        case .explicitPower:
            if code == 126 || code == 125 { presentation.focusedIndex = code == 126 ? 0 : 1 }
            else if code == 36 || code == 49 { controller?.power(on: (presentation.focusedIndex ?? 0) == 0) }
            else { super.keyDown(with: event) }
        case .invalidSpeed: break
        }
        updateAccessibility()
    }
    override func keyUp(with event: NSEvent) {
        guard enabled, presentation.shape == .slider, pressedKeys.remove(event.keyCode) != nil else { return }
        controller?.percentage(presentation.value)
        tooltipTimer?.invalidate()
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: policy.tooltipSeconds, repeats: false) { [weak self] _ in
            self?.presentation.tooltip = nil; self?.tooltipTimer = nil
        }
    }
    private func setChecked(_ checked: Bool) {
        withAnimation(.easeInOut(duration: policy.geometrySeconds)) { presentation.checked = checked }
        controller?.power(on: checked)
    }
    private func setValue(_ value: Double, animated: Bool) {
        presentation.animatesValue = animated
        var transaction = Transaction(animation: animated ? .easeInOut(duration: policy.geometrySeconds) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) { presentation.value = value }
        updateAccessibility()
    }
    private func showTooltip() {
        tooltipTimer?.invalidate(); tooltipTimer = nil
        let value = controller?.entity?.step.flatMap { FanValueMapping.stepped(presentation.value, step: $0) } ?? presentation.value
        presentation.tooltip = ClimateNumberFormatting.format(value, digits: nil, unit: "%", preferences: preferences)
    }
    static func sliderKey(_ code: UInt16) -> FanSliderKey? {
        [123: .left, 124: .right, 125: .down, 126: .up, 115: .home, 119: .end, 116: .pageUp, 121: .pageDown][code]
    }
    private func updateAccessibility() {
        setAccessibilityEnabled(enabled)
        setAccessibilityLabel(presentation.shape == .slider ? "Fan speed" : "Fan power and speed")
        if presentation.shape == .slider {
            setAccessibilityChildren(nil)
            setAccessibilityRole(.slider); setAccessibilityMinValue(0); setAccessibilityMaxValue(100)
            setAccessibilityValue(presentation.value)
        } else if !options.isEmpty || presentation.shape == .explicitPower {
            setAccessibilityRole(options.isEmpty ? .group : .radioGroup)
            let labels = options.isEmpty ? ["On", "Off"] : options.map { $0.rawValue.capitalized }
            let children = labels.enumerated().map { index, label -> FanChoiceAccessibilityElement in
                let child = FanChoiceAccessibilityElement()
                child.owner = self; child.index = index; child.generation = choiceGeneration
                child.setAccessibilityRole(options.isEmpty ? .button : .radioButton)
                child.setAccessibilityLabel(label); child.setAccessibilityParent(self)
                child.setAccessibilityEnabled(enabled)
                child.setAccessibilityValue(options.isEmpty ? (index == 0 ? presentation.rawActive : presentation.rawOff) : presentation.speed == options[index])
                let rect = FanControlGeometry.optionRect(index: index, count: labels.count, bounds: bounds, padding: options.isEmpty ? policy.switchPadding : policy.selectionPadding)
                child.setAccessibilityFrame(window?.convertToScreen(convert(rect, to: nil)) ?? .zero)
                return child
            }
            setAccessibilityChildren(children)
        } else {
            setAccessibilityChildren(nil); setAccessibilityRole(.checkBox)
            setAccessibilityValue(options.isEmpty ? (presentation.checked ? "On" : "Off") : presentation.speed.rawValue.capitalized)
        }
    }
    func activateChoice(_ index: Int, generation: Int? = nil) -> Bool {
        guard enabled, generation == nil || generation == choiceGeneration else { return false }
        controller?.inputBegan()
        if !options.isEmpty, options.indices.contains(index) { controller?.speed(options[index]); return true }
        if presentation.shape == .explicitPower, (0...1).contains(index) { controller?.power(on: index == 0); return true }
        return false
    }
    override func accessibilityPerformIncrement() -> Bool { accessibilityStep(.up) }
    override func accessibilityPerformDecrement() -> Bool { accessibilityStep(.down) }
    private func accessibilityStep(_ key: FanSliderKey) -> Bool {
        guard enabled, presentation.shape == .slider, let step = controller?.entity?.step,
              let value = FanValueMapping.keyboard(key, value: presentation.value, step: step) else { return false }
        setValue(value, animated: true); controller?.percentage(value); return true
    }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        if presentation.shape == .toggle { setChecked(!presentation.checked); return true }
        if !options.isEmpty { return activateChoice(presentation.focusedIndex ?? options.firstIndex(of: presentation.speed) ?? 0) }
        if presentation.shape == .explicitPower { controller?.power(on: (presentation.focusedIndex ?? 0) == 0); return true }
        return false
    }
    deinit { tooltipTimer?.invalidate() }
}

enum FanControlGeometry {
    static func optionRect(index: Int, count: Int, bounds: CGRect, padding: CGFloat) -> CGRect {
        guard count > 0 else { return .zero }
        let height = max(0, (bounds.height - padding * CGFloat(count + 1)) / CGFloat(count))
        return CGRect(x: padding, y: padding + CGFloat(index) * (height + padding), width: max(0, bounds.width - 2 * padding), height: height)
    }
}

final class FanChoiceAccessibilityElement: NSAccessibilityElement {
    weak var owner: FanControlNSView?
    var index = 0
    var generation = 0
    override func accessibilityPerformPress() -> Bool { owner?.activateChoice(index, generation: generation) ?? false }
}

struct FanControlDrawing: View {
    @ObservedObject var presentation: FanControlPresentation
    @State private var hoveredOption: String?
    @State private var hoveredSwitch = false
    private let policy = AppConfig.fanPolicy
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if presentation.shape != .explicitPower {
                    RoundedRectangle(cornerRadius: policy.cornerRadius).fill((presentation.shape == .toggle ? switchColor : presentation.color).opacity(presentation.shape == .toggle && (hoveredSwitch || presentation.keyboardFocus) ? 0.4 : 0.2))
                }
                switch presentation.shape {
                case .slider:
                    FanSliderFill(value: FanValueMapping.bounded(presentation.value) ?? 0, color: presentation.color, size: size)
                        .animation(presentation.animatesValue ? .easeInOut(duration: policy.geometrySeconds) : nil, value: presentation.value)
                        .transaction { if !presentation.animatesValue { $0.animation = nil; $0.disablesAnimations = true } }
                        .clipShape(RoundedRectangle(cornerRadius: policy.cornerRadius))
                case let .discrete(speeds):
                    VStack(spacing: policy.selectionPadding) {
                        ForEach(Array(speeds.reversed().enumerated()), id: \.offset) { index, speed in
                            option(speed.rawValue.capitalized, on: speed != .off, selected: presentation.speed == speed, focused: presentation.focusedIndex == index)
                        }
                    }.padding(policy.selectionPadding)
                case .toggle:
                    let height = (size.height - 2 * policy.switchPadding) / 2
                    RoundedRectangle(cornerRadius: policy.cornerRadius - policy.switchPadding)
                        .fill(switchColor)
                        .overlay(FanGlyph(on: presentation.checked, size: 24).foregroundColor(.white))
                        .frame(width: size.width - 2 * policy.switchPadding, height: height)
                        .offset(y: presentation.checked ? -height / 2 : height / 2)
                        .animation(.easeInOut(duration: policy.geometrySeconds), value: presentation.checked)
                case .explicitPower:
                    VStack(spacing: policy.switchPadding) {
                        option("On", on: true, selected: presentation.rawActive, focused: presentation.focusedIndex == 0, explicit: true)
                        option("Off", on: false, selected: controllerOff, focused: presentation.focusedIndex == 1, explicit: true)
                    }.padding(policy.switchPadding)
                case .invalidSpeed: Text("Speed unavailable").font(.system(size: 13)).multilineTextAlignment(.center).padding()
                }
                if presentation.keyboardFocus, presentation.shape == .slider || presentation.shape == .toggle {
                    RoundedRectangle(cornerRadius: policy.cornerRadius).stroke(Color.accentColor, lineWidth: 2).padding(1)
                }
                Text(presentation.tooltip ?? " ").font(.system(size: 20)).padding(.vertical, 4).padding(.horizontal, 8).background(Color(white: 17 / 255)).cornerRadius(12)
                        .opacity(presentation.tooltip == nil ? 0 : 1)
                        .animation(.easeInOut(duration: policy.geometrySeconds), value: presentation.tooltip != nil)
                        .fixedSize().frame(width: 0, alignment: .trailing).offset(x: -4)
                        .position(x: 0, y: size.height - min(max(size.height * CGFloat((FanValueMapping.bounded(presentation.value) ?? 0) / 100) - (size.width / 4 + 4) / 2, 0), size.height))
                        .transaction { $0.animation = nil }
                        .allowsHitTesting(false)
            }.opacity(presentation.unavailable && presentation.shape == .toggle ? 0.5 : 1)
                .onHover { hoveredSwitch = $0 && !presentation.unavailable }
        }
    }
    private var controllerOff: Bool { presentation.rawOff }
    private var switchColor: Color { presentation.checked ? Color(red: 0, green: 188 / 255, blue: 212 / 255) : Color(white: 158 / 255) }
    private func option(_ label: String, on: Bool, selected: Bool, focused: Bool, explicit: Bool = false) -> some View {
        ZStack {
            if explicit { RoundedRectangle(cornerRadius: policy.cornerRadius).fill(Color(white: 70 / 255).opacity(0.2)) }
            RoundedRectangle(cornerRadius: explicit ? policy.cornerRadius : policy.cornerRadius - policy.selectionPadding)
                .fill(presentation.unavailable ? Color(white: 70 / 255) : presentation.color).opacity(selected ? 1 : hoveredOption == label ? 0.2 : 0)
                .animation(.easeInOut(duration: policy.selectionSeconds), value: selected)
            VStack(spacing: 4) {
                FanGlyph(on: on, size: explicit ? 24 : 20)
                if !explicit { Text(label).font(.system(size: 14, weight: .medium)) }
            }.foregroundColor(selected ? .white : Color(white: presentation.unavailable ? 70 / 255 : 225 / 255))
            if focused && presentation.keyboardFocus {
                RoundedRectangle(cornerRadius: policy.cornerRadius - policy.selectionPadding).stroke(Color.accentColor, lineWidth: 2)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).onHover { hovering in hoveredOption = hovering && !presentation.unavailable ? label : nil }
    }
}

struct FanGlyph: View {
    var on: Bool
    var size: CGFloat
    var body: some View {
        Image(systemName: "fanblades").font(.system(size: size)).overlay {
            if !on { Rectangle().frame(width: size * 1.25, height: 2).rotationEffect(.degrees(45)) }
        }
    }
}

private struct FanSliderFill: View, Animatable {
    var value: Double
    var color: Color
    var size: CGSize
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8).fill(color)
            RoundedRectangle(cornerRadius: 4).fill(Color.white).frame(width: size.width / 2, height: 4).offset(y: size.width / 8)
        }.frame(width: size.width, height: size.height).offset(y: size.height * CGFloat(1 - value / 100))
    }
}
