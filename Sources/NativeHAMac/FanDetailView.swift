import AppKit
import NativeHACore
import SwiftUI

struct FanDetailContent: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let state: HAState
    var body: some View {
        VStack(spacing: AppConfig.fanPolicy.controlSpacing) {
            if let controller = model.fanDetailController {
                FanDetailControls(controller: controller, timestamp: model.detailTime(state.lastChanged), preferences: model.frontendLocalePreferences)
                    .id(ObjectIdentifier(controller))
            }
            DetailHistoryGraph(entityID: entityID, title: "History", hours: 24)
        }.frame(maxWidth: .infinity)
    }
}

struct FanDetailControls: View {
    @ObservedObject var controller: FanServiceController
    let timestamp: String
    var preferences: HAFrontendLocalePreferences?
    var viewportHeight: CGFloat = 620
    private let policy = AppConfig.fanPolicy
    var body: some View {
        VStack(spacing: policy.controlSpacing) {
            if let entity = controller.entity {
                VStack(spacing: 5) {
                    Text(header(entity)).font(.system(size: 36, weight: .regular))
                        .accessibilityIdentifier("fan-state-header")
                    Text(timestamp).font(.system(size: 12)).foregroundColor(Color(white: 155 / 255))
                }
                FanControlSurface(controller: controller, preferences: preferences)
                    .frame(width: policy.controlWidth, height: policy.controlHeight(viewportHeight: viewportHeight))
                if entity.showsSliderPower {
                    Button { controller.togglePower() } label: {
                        Image(systemName: "power").font(.system(size: 24))
                            .foregroundColor(Color(white: 155 / 255))
                            .frame(width: policy.powerDiameter, height: policy.powerDiameter)
                            .background(Circle().stroke(Color(white: 155 / 255), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(entity.unavailable).accessibilityLabel("Power")
                }
                menus(entity)
                if let error = controller.error {
                    Text(error).font(.system(size: 12)).foregroundColor(.red)
                        .accessibilityLabel("Fan control error: " + error)
                }
            }
        }.foregroundColor(Color(white: 225 / 255)).frame(maxWidth: .infinity)
    }
    private func header(_ entity: FanEntity) -> String {
        switch entity.header {
        case let .percentage(value): return ClimateNumberFormatting.format(value, digits: 0, unit: "%", preferences: preferences)
        case let .state(value): return ["on": "On", "off": "Off", "unknown": "Unknown", "unavailable": "Unavailable"][value] ?? value
        }
    }
    private func menus(_ entity: FanEntity) -> some View {
        let items = FanMenuKind.allCases.filter { $0.options(entity) != nil }
        let maximum = items.count == 3 ? policy.threeMenuMaximumWidth : policy.menuMaximumWidth
        return FanMenuRows(controller: controller, items: items, maximumWidth: maximum)
    }
}

private struct FanMenuRows: View {
    @ObservedObject var controller: FanServiceController
    let items: [FanMenuKind]
    let maximumWidth: CGFloat
    @State private var availableWidth: CGFloat = 0
    private let policy = AppConfig.fanPolicy
    private var columns: Int { max(1, min(items.count, Int((availableWidth + policy.menuSpacing) / (policy.menuMinimumWidth + policy.menuSpacing)))) }
    private var rows: Int { (items.count + columns - 1) / columns }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: policy.menuSpacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: policy.menuSpacing) {
                        ForEach(Array(items.dropFirst(row * columns).prefix(columns)), id: \.self) { kind in
                            FanMenuControl(controller: controller, kind: kind)
                                .frame(width: min(maximumWidth, max(policy.menuMinimumWidth, (geometry.size.width - CGFloat(columns - 1) * policy.menuSpacing) / CGFloat(columns))), height: policy.menuHeight)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
            .onAppear { availableWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { availableWidth = $0 }
        }.frame(height: CGFloat(rows) * policy.menuHeight + CGFloat(max(rows - 1, 0)) * policy.menuSpacing)
    }
}

enum FanMenuKind: CaseIterable {
    case preset, direction, oscillation
    var title: String { switch self { case .preset: return "Preset mode"; case .direction: return "Direction"; case .oscillation: return "Oscillating" } }
    var symbol: String { switch self { case .preset: return "slider.horizontal.3"; case .direction: return "arrow.left.and.right"; case .oscillation: return "arrow.triangle.swap" } }
    func options(_ entity: FanEntity) -> [String]? {
        switch self {
        case .preset: return entity.presetModes
        case .direction: return entity.directionOptions?.map(\.rawValue)
        case .oscillation: return entity.oscillationOptions?.map { $0 ? "true" : "false" }
        }
    }
    func selected(_ entity: FanEntity) -> String? {
        switch self { case .preset: return entity.presetMode; case .direction: return entity.direction; case .oscillation: return entity.selectedOscillation ? "true" : "false" }
    }
    func label(_ raw: String) -> String {
        switch self {
        case .preset: return raw
        case .direction: return raw == "forward" ? "Forward" : raw == "reverse" ? "Reverse" : raw
        case .oscillation: return raw == "true" ? "On" : "Off"
        }
    }
    @MainActor func select(_ raw: String, controller: FanServiceController) {
        switch self {
        case .preset: controller.preset(raw)
        case .direction: if let value = FanDirection(rawValue: raw) { controller.direction(value) }
        case .oscillation: if raw == "true" || raw == "false" { controller.oscillation(raw == "true") }
        }
    }
}

struct FanMenuControl: NSViewRepresentable {
    @ObservedObject var controller: FanServiceController
    let kind: FanMenuKind
    func makeNSView(context: Context) -> FanMenuButton { FanMenuButton() }
    func updateNSView(_ button: FanMenuButton, context: Context) { button.configure(controller: controller, kind: kind) }
    static func dismantleNSView(_ button: FanMenuButton, coordinator: ()) { button.retire() }
}

final class FanMenuButton: NSButton {
    private weak var controller: FanServiceController?
    private(set) var kind = FanMenuKind.preset
    private var openMenu: NSMenu?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 48) }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""; isBordered = false; target = self; action = #selector(showOptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(controller: FanServiceController, kind: FanMenuKind) {
        self.controller = controller; self.kind = kind
        isEnabled = controller.entity.map { !$0.unavailable && kind.options($0) != nil } ?? false
        setAccessibilityLabel(kind.title)
        setAccessibilityValue(controller.entity.flatMap(kind.selected).map(kind.label))
        needsDisplay = true
        if !isEnabled { openMenu?.cancelTracking() }
    }
    func retire() { openMenu?.cancelTracking(); openMenu = nil; controller = nil }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 70 / 255, alpha: isHighlighted ? 0.4 : 0.2).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let color = NSColor(white: isEnabled ? 225 / 255 : 70 / 255, alpha: 1)
        let symbol = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular).applying(.init(paletteColors: [color])))
        symbol?.draw(in: CGRect(x: 10, y: 14, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let value = controller?.entity.flatMap { entity in kind.selected(entity).flatMap { kind.options(entity)?.contains($0) == true ? kind.label($0) : nil } }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (kind.title as NSString).draw(in: CGRect(x: 40, y: value == nil ? 15 : 6, width: bounds.width - 50, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: value == nil ? 14 : 12), .foregroundColor: color, .paragraphStyle: paragraph])
        if let value = value { (value as NSString).draw(in: CGRect(x: 40, y: 24, width: bounds.width - 50, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: color, .paragraphStyle: paragraph]) }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12); ring.lineWidth = 2; ring.stroke()
        }
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        guard let entity = controller?.entity else { return menu }
        for raw in kind.options(entity) ?? [] {
            let item = NSMenuItem(title: kind.label(raw), action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = raw; item.state = kind.selected(entity) == raw ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
    @objc private func showOptions() {
        guard isEnabled else { return }
        let menu = makeMenu(); openMenu = menu
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height), in: self)
        openMenu = nil
    }
    @objc func selectItem(_ item: NSMenuItem) {
        guard let controller = controller, let entity = controller.entity, !entity.unavailable,
              let raw = item.representedObject as? String, kind.options(entity)?.contains(raw) == true else { return }
        kind.select(raw, controller: controller)
    }
}
