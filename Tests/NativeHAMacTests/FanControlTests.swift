import AppKit
import SwiftUI
import XCTest
import NativeHACore
@testable import NativeHAMac

@MainActor
final class FanControlTests: XCTestCase {
    func testMountedSliderPanPhasesEqualBindingReplacementAndOneCommit() throws {
        let fan = try FanFixtures.complete()
        let model = DashboardViewModel(initialStates: [fan.entityID: fan.state])
        model.installServiceCallerForTesting { _, _, _ in }
        model.openDetails(entityID: fan.entityID)
        let controller = try XCTUnwrap(model.fanDetailController)
        let mounted = FanMountedView(FanDetailControls(controller: controller, timestamp: "Fixed time"), size: CGSize(width: 360, height: 620))
        defer { mounted.close(); model.closeDetails() }
        let input: FanControlNSView = try XCTUnwrap(mounted.find())
        XCTAssertEqual(input.presentation.value, 50)
        mouse(input, .leftMouseDown, x: 65, y: 200)
        mouse(input, .leftMouseDragged, x: 65, y: 189)
        XCTAssertTrue(input.dragging)
        XCTAssertEqual(input.presentation.value, 50, "panstart does not move")
        XCTAssertNotNil(input.presentation.tooltip)
        for index in 0..<1_000 { mouse(input, .leftMouseDragged, x: 65, y: 180 - CGFloat(index) / 10) }
        let draft = input.presentation.value
        XCTAssertEqual(controller.sliderValue, 50)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 0)
        model.acceptFanReplacement(entityIDs: [fan.entityID]); mounted.settle()
        XCTAssertEqual(input.presentation.value, draft, "Equal owner binding must not overwrite the child drag")
        mouse(input, .leftMouseUp, x: 65, y: 0)
        XCTAssertEqual(controller.sliderValue, 100)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 1)
        XCTAssertFalse(input.dragging); XCTAssertNil(input.presentation.tooltip)
        XCTAssertEqual(model.states[fan.entityID], fan.state)
        XCTAssertEqual(controller.entity?.header, .percentage(50))
    }

    func testMountedChangedBindingCancelAndUnavailableKeyboard() throws {
        let fan = try FanFixtures.complete()
        let controller = FanServiceController()
        var calls: [FanServiceRequest] = []
        controller.install(entity: fan) { request, _ in calls.append(request); return true }
        let mounted = FanMountedView(FanDetailControls(controller: controller, timestamp: ""), size: CGSize(width: 360, height: 620))
        defer { mounted.close(); controller.close() }
        let input: FanControlNSView = try XCTUnwrap(mounted.find())
        mouse(input, .leftMouseDown, x: 65, y: 200)
        mouse(input, .leftMouseDragged, x: 65, y: 180)
        mouse(input, .leftMouseDragged, x: 65, y: 100)
        var attrs = fan.state.attributes; attrs["percentage"] = 75
        controller.replace(FanFixtures.entity(attrs, id: fan.entityID)); mounted.settle()
        XCTAssertEqual(input.presentation.value, 75, "Current replacement payload reaches mounted input")
        input.cancelOperation(nil)
        XCTAssertEqual(input.presentation.value, 50, "Cancel restores panstart value, sends nothing")
        XCTAssertTrue(calls.isEmpty)
        controller.replace(FanFixtures.entity(attrs, state: "unavailable", id: fan.entityID)); mounted.settle()
        key(input, 119, released: false); key(input, 119, released: true)
        XCTAssertFalse(input.enabled); XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(input.accessibilityPerformIncrement())
    }

    func testSliderClickIncidentalMovementKeyboardRepeatEndpointAndTooltipLifetime() throws {
        let entity = FanFixtures.entity(["supported_features": 1, "percentage_step": 16, "percentage": 32])
        let controller = FanServiceController(); var calls: [FanServiceRequest] = []
        controller.install(entity: entity) { request, _ in calls.append(request); return true }
        let mounted = FanMountedView(FanDetailControls(controller: controller, timestamp: ""), size: CGSize(width: 360, height: 620))
        let input: FanControlNSView = try XCTUnwrap(mounted.find())
        mouse(input, .leftMouseDown, x: 65, y: 1)
        mouse(input, .leftMouseDragged, x: 65, y: 0)
        XCTAssertFalse(input.dragging); XCTAssertEqual(input.presentation.value, 32)
        mouse(input, .leftMouseUp, x: 65, y: 0)
        XCTAssertEqual(calls.last?.data["percentage"], .double(96))
        mounted.settle()
        key(input, 119, released: false); key(input, 119, released: true)
        XCTAssertEqual(calls.last?.data["percentage"], .double(100))
        key(input, 125, released: false); key(input, 125, released: false); key(input, 125, released: false)
        XCTAssertEqual(calls.count, 2)
        key(input, 125, released: true)
        XCTAssertEqual(calls.count, 3); XCTAssertEqual(calls.last?.data["percentage"], .double(52))
        XCTAssertTrue(input.ownsTooltipTimer)
        mounted.settle(0.55)
        XCTAssertNil(input.presentation.tooltip); XCTAssertFalse(input.ownsTooltipTimer)
        key(input, 126, released: false); key(input, 126, released: true)
        XCTAssertTrue(input.ownsTooltipTimer)
        mounted.close(); controller.close()
        XCTAssertFalse(input.ownsTooltipTimer)
        XCTAssertNil(input.presentation.tooltip)
    }

    func testDiscreteFocusOnlyArrowsRepeatedSelectionAndToggleLocalCheck() throws {
        let controller = FanServiceController(); var calls: [FanServiceRequest] = []
        controller.install(entity: FanFixtures.entity(["supported_features": 1, "percentage_step": 33, "percentage": 0])) { request, _ in calls.append(request); return true }
        let mounted = FanMountedView(FanDetailControls(controller: controller, timestamp: ""), size: CGSize(width: 360, height: 620))
        defer { mounted.close(); controller.close() }
        let input: FanControlNSView = try XCTUnwrap(mounted.find())
        mounted.window.makeFirstResponder(input)
        XCTAssertEqual(input.presentation.focusedIndex, 3)
        key(input, 125, released: false)
        XCTAssertEqual(input.presentation.focusedIndex, 0); XCTAssertTrue(calls.isEmpty)
        key(input, 49, released: false); key(input, 49, released: false)
        XCTAssertEqual(calls.map { $0.data["percentage"] }, [.double(99), .double(99)])
        controller.replace(FanFixtures.entity(state: "off")); mounted.settle()
        key(input, 126, released: false)
        XCTAssertTrue(input.presentation.checked)
        XCTAssertEqual(controller.entity?.state.state, "off")
        key(input, 126, released: false)
        XCTAssertEqual(calls.count, 3, "Arrow toward current local check is a no-op")
        key(input, 49, released: false)
        XCTAssertFalse(input.presentation.checked); XCTAssertEqual(calls.last?.service, "turn_off")
    }

    func testMountedMenusKeepAuthoritativeRawSelectionAndRejectRetiredActions() throws {
        let fan = try FanFixtures.complete()
        let controller = FanServiceController(); var calls: [FanServiceRequest] = []
        controller.install(entity: fan) { request, _ in calls.append(request); return true }
        let mounted = FanMountedView(FanDetailControls(controller: controller, timestamp: ""), size: CGSize(width: 360, height: 620))
        defer { mounted.close(); controller.close() }
        let buttons: [FanMenuButton] = mounted.findAll()
        XCTAssertEqual(buttons.count, 3)
        let preset = try XCTUnwrap(buttons.first { $0.kind == .preset })
        let menu = preset.makeMenu()
        XCTAssertEqual(menu.items.map(\.title), ["auto", "quiet_mode", "Custom Night"])
        XCTAssertEqual(menu.items.map(\.state), [.on, .off, .off])
        preset.selectItem(menu.items[2]); preset.selectItem(menu.items[2]); mounted.settle()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(preset.makeMenu().items.map(\.state), [.on, .off, .off])
        controller.replace(fan); mounted.settle(); preset.selectItem(menu.items[2])
        XCTAssertEqual(calls.count, 2)
        controller.close(); preset.selectItem(menu.items[1])
        XCTAssertEqual(calls.count, 2)
    }

    func testMountedChoiceGeometryAccessibilityAndShapeReplacement() throws {
        let controller = FanServiceController(); var calls: [FanServiceRequest] = []
        controller.install(entity: FanFixtures.entity(["supported_features": 1, "percentage_step": 33, "percentage": 0])) { request, _ in calls.append(request); return true }
        let mounted = FanMountedView(FanDetailControls(controller: controller, timestamp: ""), size: CGSize(width: 360, height: 620))
        defer { mounted.close(); controller.close() }
        let input: FanControlNSView = try XCTUnwrap(mounted.find())
        mounted.window.makeFirstResponder(input)
        XCTAssertEqual(input.presentation.focusedIndex, 3)
        let children = try XCTUnwrap(input.accessibilityChildren() as? [FanChoiceAccessibilityElement])
        XCTAssertEqual(children.map { $0.accessibilityLabel() }, ["High", "Medium", "Low", "Off"])
        XCTAssertTrue(children[0].accessibilityPerformPress())
        let gap = FanControlGeometry.optionRect(index: 0, count: 4, bounds: input.bounds, padding: 4).maxY + 2
        mouse(input, .leftMouseDown, x: 65, y: gap); mouse(input, .leftMouseUp, x: 65, y: gap)
        XCTAssertEqual(calls.count, 1)
        controller.replace(FanFixtures.entity(["supported_features": 1, "percentage_step": 100, "percentage": 100])); mounted.settle()
        XCTAssertNil(input.presentation.focusedIndex)
        input.presentation.focusedIndex = 99
        XCTAssertFalse(input.accessibilityPerformPress())
        key(input, 49, released: false)
        XCTAssertEqual(calls.last?.data["percentage"], .double(100))
        controller.replace(FanFixtures.entity(state: "unknown")); mounted.settle()
        XCTAssertFalse(children[0].accessibilityPerformPress(), "Retained AX child cannot become a different control")
        let power = try XCTUnwrap(input.accessibilityChildren() as? [FanChoiceAccessibilityElement])
        XCTAssertEqual(power.map { $0.accessibilityLabel() }, ["On", "Off"])
        XCTAssertTrue(power[0].accessibilityPerformPress()); XCTAssertTrue(power[1].accessibilityPerformPress())
        XCTAssertEqual(calls.suffix(2).map(\.service), ["turn_on", "turn_off"])
        let count = calls.count
        mouse(input, .leftMouseDown, x: 65, y: 40); mouse(input, .leftMouseUp, x: 65, y: 240)
        XCTAssertEqual(calls.count, count)
        controller.replace(FanFixtures.entity(state: "unavailable")); mounted.settle()
        XCTAssertFalse(power[0].accessibilityPerformPress())
        input.retire()
        XCTAssertFalse(children[0].accessibilityPerformPress()); XCTAssertFalse(power[1].accessibilityPerformPress())
        XCTAssertEqual(calls.count, count)
        XCTAssertNotNil(NSImage(systemSymbolName: "fanblades", accessibilityDescription: nil))
    }

    func testSyntheticControlAndFullSheetPNGCaptures() throws {
        let full = try FanFixtures.complete()
        let variants = try JSONDecoder().decode([String: [String: JSONValue]].self, from: Data(contentsOf: FanFixtures.root.appendingPathComponent("render-variants.json")))
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/render-artifacts/fan")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in variants.keys.sorted() {
            let variant = variants[name]!
            var attributes = full.state.attributes
            if case let .object(overrides)? = variant["attributes"] { attributes.merge(overrides) { _, new in new } }
            let state: String
            if case let .string(value)? = variant["state"] { state = value } else { state = full.state.state }
            let entity = FanFixtures.entity(attributes, state: state, id: full.entityID)
            let controller = FanServiceController(); controller.install(entity: entity) { _, _ in XCTFail("Capture must not send a command"); return false }
            let view = FanDetailControls(controller: controller, timestamp: "Oct 8, 2026 at 12:00:00 PM")
                .padding(24).frame(width: 360, height: 620, alignment: .top).background(Color(white: 28 / 255))
            let png = try MacViewPNGRenderer.render(view, size: CGSize(width: 360, height: 620), displayScale: 2, settleTime: 0.05)
            XCTAssertGreaterThan(png.nonBackgroundSampleCount, 100)
            try png.pngData.write(to: output.appendingPathComponent(name + ".png"))
            controller.close()
        }
        let model = DashboardViewModel(initialStates: [full.entityID: full.state])
        model.openDetails(entityID: full.entityID)
        let png = try MacViewPNGRenderer.render(EntityDetailSheet(entityID: full.entityID).environmentObject(model), size: CGSize(width: 520, height: 620), displayScale: 2, settleTime: 0.05)
        try png.pngData.write(to: output.appendingPathComponent("full-sheet.png"))
        model.closeDetails()
    }

    func testMountedSliderCompositorMarkerMotionAndDirectDrag() throws {
        let controller = FanServiceController(); var calls = 0
        controller.install(entity: FanFixtures.entity(["supported_features": 1, "percentage_step": 1, "percentage": 25])) { _, _ in calls += 1; return true }
        let view = FanControlSurface(controller: controller).frame(width: 130, height: 279)
            .frame(width: 360, height: 320).background(Color(white: 28 / 255))
        let mounted = FanMountedView(view, size: CGSize(width: 360, height: 320))
        defer { mounted.close(); controller.close() }
        let input: FanControlNSView = try XCTUnwrap(mounted.find())
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/fan-motion")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(delay: Double) throws -> CGImage {
            mounted.settle(delay)
            return try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(mounted.window.windowNumber), [.boundsIgnoreFraming, .bestResolution]))
        }
        func marker(_ name: String, image: CGImage) throws -> Double {
            let bitmap = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
            let scale = Double(bitmap.pixelsWide) / 360
            var rows: [Double] = []
            for y in 0..<bitmap.pixelsHigh {
                var white = 0
                for x in Int(160 * scale)..<Int(200 * scale) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.9, color.greenComponent > 0.9, color.blueComponent > 0.9 { white += 1 }
                }
                if white > Int(25 * scale) { rows.append(Double(y) / scale) }
            }
            XCTAssertFalse(rows.isEmpty, "Visible horizontal marker, independent of text")
            return rows.reduce(0, +) / Double(max(1, rows.count))
        }
        let initial = try capture(delay: 0.25)
        mouse(input, .leftMouseDown, x: 65, y: 70); mouse(input, .leftMouseUp, x: 65, y: 70)
        var frames: [CGImage] = []
        for _ in 0..<12 { frames.append(try capture(delay: 0.015)) }
        let final = try capture(delay: 0.2)
        let start = try marker("start", image: initial)
        let samples = try frames.enumerated().map { try marker("frame-\($0.offset)", image: $0.element) }
        let end = try marker("end", image: final)
        XCTAssertGreaterThan(start - end, 130)
        XCTAssertTrue(samples.contains { $0 < start - 5 && $0 > end + 5 }, "180ms transition has an intermediate marker position: \(start), \(samples), \(end)")
        XCTAssertEqual(calls, 1)
        mouse(input, .leftMouseDown, x: 65, y: 70); mouse(input, .leftMouseDragged, x: 65, y: 90)
        mouse(input, .leftMouseDragged, x: 65, y: 140)
        XCTAssertFalse(input.presentation.animatesValue)
        XCTAssertEqual(input.presentation.value, 100 * (1 - 140.0 / 279), accuracy: 0.01)
        let direct = try marker("direct-drag", image: capture(delay: 0.06))
        XCTAssertFalse(input.presentation.animatesValue)
        XCTAssertEqual(direct - end, 70, accuracy: 3)
        XCTAssertEqual(calls, 1)
        input.cancelOperation(nil)
        mounted.settle(0.1)
        func assertTransition(_ name: String, change: () -> Void) throws {
            let before = try capture(delay: 0.2)
            change()
            var frames: [CGImage] = []
            for _ in 0..<12 { frames.append(try capture(delay: 0.015)) }
            let after = try capture(delay: 0.2)
            let first = try marker(name + "-start", image: before)
            let last = try marker(name + "-end", image: after)
            let points = try frames.enumerated().map { try marker(name + "-\($0.offset)", image: $0.element) }
            XCTAssertGreaterThan(abs(last - first), 30)
            XCTAssertTrue(points.contains { $0 > min(first, last) + 3 && $0 < max(first, last) - 3 }, name + " has visible intermediate geometry")
        }
        try assertTransition("keyboard") { key(input, 119, released: false) }
        XCTAssertEqual(calls, 1, "Keydown changes only child geometry")
        key(input, 119, released: true)
        XCTAssertEqual(calls, 2)
        try assertTransition("owner") { controller.replace(FanFixtures.entity(["supported_features": 1, "percentage_step": 1, "percentage": 40])) }
        XCTAssertEqual(calls, 2, "Owner echo has no outbound command")
    }

    func testToggleSwipeUsesDominantAxisVelocity() throws {
        let controller = FanServiceController(); var calls: [FanServiceRequest] = []
        controller.install(entity: FanFixtures.entity()) { request, _ in calls.append(request); return true }
        let mounted = FanMountedView(FanDetailControls(controller: controller, timestamp: ""), size: CGSize(width: 360, height: 620))
        defer { mounted.close(); controller.close() }
        let input: FanControlNSView = try XCTUnwrap(mounted.find())
        mouse(input, .leftMouseDown, x: 30, y: 80, timestamp: 1)
        mouse(input, .leftMouseUp, x: 90, y: 160, timestamp: 1.3)
        XCTAssertTrue(calls.isEmpty, "80/0.30 is below 300 despite Euclidean 100/0.30 exceeding it")
        XCTAssertTrue(input.presentation.checked)
        mouse(input, .leftMouseDown, x: 30, y: 80, timestamp: 2)
        mouse(input, .leftMouseUp, x: 90, y: 160, timestamp: 2.2)
        XCTAssertEqual(calls.map(\.service), ["turn_off"])
        XCTAssertFalse(input.presentation.checked)
        mouse(input, .leftMouseDown, x: 65, y: 200, timestamp: 3)
        mouse(input, .leftMouseUp, x: 65, y: 100, timestamp: 3.2)
        XCTAssertEqual(calls.map(\.service), ["turn_off", "turn_on"])
        XCTAssertTrue(input.presentation.checked)
    }

    private func mouse(_ view: NSView, _ type: NSEvent.EventType, x: CGFloat, y: CGFloat, timestamp: TimeInterval? = nil) {
        let location = view.convert(CGPoint(x: x, y: y), to: nil)
        let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: timestamp ?? (type == .leftMouseDown ? 1 : 1.1), windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type { case .leftMouseDown: view.mouseDown(with: event); case .leftMouseDragged: view.mouseDragged(with: event); default: view.mouseUp(with: event) }
    }
    private func key(_ view: NSView, _ code: UInt16, released: Bool) {
        let event = NSEvent.keyEvent(with: released ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        if released { view.keyUp(with: event) } else { view.keyDown(with: event) }
    }
}

@MainActor
private final class FanMountedView {
    let window: NSWindow
    let host: NSView
    init<V: View>(_ view: V, size: CGSize) {
        _ = NSApplication.shared
        host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 50, y: 50), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua); window.orderBack(nil)
        settle()
    }
    func settle(_ duration: Double = 0.02) { RunLoop.main.run(until: Date(timeIntervalSinceNow: duration)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }
    func find<T: NSView>() -> T? { findAll().first }
    func findAll<T: NSView>() -> [T] {
        func scan(_ view: NSView) -> [T] {
            if let result = view as? T { return [result] }
            var results: [T] = []
            for child in view.subviews { results += scan(child) }
            return results
        }
        return scan(host)
    }
    func close() { window.contentView = nil; window.orderOut(nil); window.close() }
}
