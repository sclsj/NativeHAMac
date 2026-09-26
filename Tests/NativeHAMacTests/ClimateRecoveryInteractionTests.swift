import AppKit
import NativeHACore
import SwiftUI
import XCTest
@testable import NativeHAMac

@MainActor
final class ClimateRecoveryInteractionTests: XCTestCase {
    func testMountedTransitionsAndDirectDragRelease() throws {
        let entity = try ClimateFixtures.entity(overrides: ["temperature": .double(20)])
        let controller = ClimateServiceController()
        var calls: [ClimateServiceRequest] = []
        controller.install(entity: entity) { request, _ in calls.append(request); return true }
        let source = ClimateRecoverySource(entity: entity)
        let model = DashboardViewModel(initialStates: [entity.entityID: entity.state])
        let host = NSHostingView(rootView: ClimateRecoveryDialHost(source: source, controller: controller).environmentObject(model).foregroundColor(.white).background(Color(red: 0.09, green: 0.095, blue: 0.1)))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { controller.close(); window.orderOut(nil); window.close() }
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        settle(0.05)
        let input = try XCTUnwrap(descendants(host).compactMap { $0 as? ClimateDialNSView }.first)
        let geometry = ClimateDialGeometry(size: input.bounds.size)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-recovery-motion")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var frames: [String: Data] = [:]
        func capture(_ name: String, after delay: Double) throws -> Data {
            settle(delay)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            // Canvas is composited by WindowServer. NSView.cacheDisplay on
            // macOS 12 can retain its initial layer while capturing fresh text.
            let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]))
            let rep = NSBitmapImageRep(cgImage: image)
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            frames[name] = data
            return data
        }
        func event(_ type: NSEvent.EventType, _ progress: Double) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: input.convert(geometry.point(progress), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        func tap(_ progress: Double) throws {
            let point = input.convert(geometry.point(progress), to: host.superview)
            XCTAssertTrue(host.hitTest(point) === input, "The mounted drawing must not intercept the native dial")
            input.mouseDown(with: try event(.leftMouseDown, progress))
            input.mouseUp(with: try event(.leftMouseUp, progress))
            window.makeFirstResponder(nil)
        }
        _ = try capture("00-initial", after: 0.01)
        try tap(0.9)
        let tapStart = try capture("01-tap-start", after: 0.01)
        let tapMiddle = try capture("02-tap-middle", after: 0.11)
        let tapFinal = try capture("03-tap-final", after: 0.3)
        XCTAssertNotEqual(tapStart, tapMiddle)
        XCTAssertNotEqual(tapMiddle, tapFinal)
        XCTAssertEqual(calls.count, 1)

        try tap(0.1)
        _ = try capture("04-reverse-outbound", after: 0.1)
        try tap(0.8)
        let reversalStart = try capture("05-reverse-start", after: 0.01)
        let reversalMiddle = try capture("06-reverse-middle", after: 0.1)
        let reversalFinal = try capture("07-reverse-final", after: 0.3)
        XCTAssertNotEqual(reversalStart, reversalMiddle)
        XCTAssertNotEqual(reversalMiddle, reversalFinal)

        input.mouseDown(with: try event(.leftMouseDown, 0.8))
        input.mouseDragged(with: try event(.leftMouseDragged, 0.4))
        window.makeFirstResponder(nil)
        let drag = try capture("08-drag-direct", after: 0.02)
        XCTAssertEqual(drag, try capture("09-drag-held", after: 0.35))
        XCTAssertEqual(calls.count, 3)
        input.mouseUp(with: try event(.leftMouseUp, 0.6))
        let release = try capture("10-drag-release-direct", after: 0.02)
        XCTAssertEqual(release, try capture("11-drag-release-held", after: 0.35))
        XCTAssertEqual(calls.count, 4)

        let plus = try XCTUnwrap(descendants(host).compactMap { $0 as? ClimateAdjustmentNSButton }.first { $0.accessibilityLabel() == "Increase target" })
        XCTAssertTrue(host.hitTest(plus.convert(CGPoint(x: 24, y: 24), to: host.superview)) === plus)
        plus.performClick(nil)
        _ = try capture("12-button-first", after: 0.05)
        plus.performClick(nil)
        _ = try capture("13-button-repeat", after: 0.08)
        _ = try capture("14-button-final", after: 0.35)
        XCTAssertEqual(calls.count, 4, "Buttons remain debounced")
        controller.cancelDebounce()

        controller.mode("preset_mode", value: "sleep")
        XCTAssertEqual(calls.last?.data["preset_mode"], .string("sleep"))
        let authoritative = try ClimateFixtures.entity(overrides: ["temperature": .double(21), "preset_mode": .string("sleep")])
        source.entity = authoritative
        controller.replace(authoritative)
        let presetStart = try capture("15-preset-authoritative-start", after: 0.01)
        let presetMid = try capture("16-preset-authoritative-middle", after: 0.1)
        XCTAssertNotEqual(presetStart, presetMid)
        controller.replace(authoritative)
        _ = try capture("17-equal-replacement", after: 0.01)
        let settled = try capture("18-preset-final", after: 0.3)
        controller.replace(authoritative)
        XCTAssertEqual(settled, try capture("19-equal-settled", after: 0.05))
        let currentOnly = try ClimateFixtures.entity(overrides: ["temperature": .double(21), "current_temperature": .double(27), "preset_mode": .string("sleep")])
        source.entity = currentOnly
        controller.replace(currentOnly)
        // Allow the new SwiftUI transaction to reach WindowServer; this is
        // shorter than the 300ms target transition, not a no-latency claim.
        let currentImmediate = try capture("20-current-only-immediate", after: 0.08)
        XCTAssertNotEqual(settled, currentImmediate)
        XCTAssertEqual(currentImmediate, try capture("21-current-only-held", after: 0.35))

        input.mouseDown(with: try event(.leftMouseDown, 0.5))
        input.mouseDragged(with: try event(.leftMouseDragged, 0.7))
        input.cancelOperation(nil)
        input.mouseUp(with: try event(.leftMouseUp, 0.7))
        XCTAssertEqual(calls.count, 5)
        controller.button(1, target: .value)
        source.showsDial = false
        controller.close()
        _ = try capture("22-dismissed", after: 0.35)
        XCTAssertFalse(descendants(host).contains { $0 is ClimateDialNSView })
        XCTAssertEqual(calls.count, 5)

        // Inspect only white knob pixels on the dial annulus. Text changes or
        // a stale Canvas cache cannot satisfy these temporal geometry checks.
        func progress(_ name: String) throws -> Double { try knobProgress(XCTUnwrap(frames[name])) }
        let initial = try progress("00-initial")
        let start = try progress("01-tap-start")
        let middle = try progress("02-tap-middle")
        let final = try progress("03-tap-final")
        XCTAssertEqual(initial, 1 / 9, accuracy: 0.003)
        XCTAssertEqual(start, initial, accuracy: 0.06)
        XCTAssertGreaterThan(middle, start + 0.05)
        XCTAssertLessThan(middle, final - 0.05)
        XCTAssertEqual(final, 0.9, accuracy: 0.003)
        let reverseStart = try progress("05-reverse-start")
        let reverseMiddle = try progress("06-reverse-middle")
        let reverseFinal = try progress("07-reverse-final")
        XCTAssertGreaterThan(abs(reverseStart - reverseFinal), 0.01)
        // Historical SwiftUI timing curves blend interrupted movement: the
        // knob may continue outbound before returning to the latest target.
        XCTAssertGreaterThan(abs(reverseMiddle - reverseStart), 0.01)
        XCTAssertEqual(reverseFinal, 0.8, accuracy: 0.003)
        for name in ["08-drag-direct", "09-drag-held"] { XCTAssertEqual(try progress(name), 0.4, accuracy: 0.003) }
        for name in ["10-drag-release-direct", "11-drag-release-held"] { XCTAssertEqual(try progress(name), 0.6, accuracy: 0.003) }
        XCTAssertGreaterThan(try progress("14-button-final"), try progress("12-button-first"))
        XCTAssertEqual(try progress("14-button-final"), (24.6 - 19) / 9, accuracy: 0.003)
        XCTAssertGreaterThan(try progress("15-preset-authoritative-start"), try progress("16-preset-authoritative-middle"))
        XCTAssertGreaterThan(try progress("16-preset-authoritative-middle"), try progress("18-preset-final"))
        for name in ["18-preset-final", "19-equal-settled", "20-current-only-immediate", "21-current-only-held"] {
            XCTAssertEqual(try progress(name), 2 / 9, accuracy: 0.003)
        }
    }

    private func knobProgress(_ data: Data) throws -> Double {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let scale = Double(bitmap.pixelsWide) / 320
        let geometry = ClimateDialGeometry(size: CGSize(width: 320, height: 320))
        var count = 0
        var sum = CGPoint.zero
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let point = CGPoint(x: (Double(x) + 0.5) / scale, y: (Double(y) + 0.5) / scale)
                guard geometry.contains(point),
                      let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      min(color.redComponent, color.greenComponent, color.blueComponent) > 0.97 else { continue }
                count += 1
                sum.x += point.x
                sum.y += point.y
            }
        }
        XCTAssertGreaterThan(count, Int(100 * scale * scale), "The 18-point white target knob must be visible")
        return ClimateValueMapping.progress(at: CGPoint(x: sum.x / CGFloat(max(count, 1)), y: sum.y / CGFloat(max(count, 1))), size: geometry.size)
    }

    private func settle(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
}

@MainActor
private final class ClimateRecoverySource: ObservableObject {
    @Published var entity: ClimateEntity
    @Published var showsDial = true
    init(entity: ClimateEntity) { self.entity = entity }
}

private struct ClimateRecoveryDialHost: View {
    @ObservedObject var source: ClimateRecoverySource
    let controller: ClimateServiceController
    var body: some View {
        Group {
            if source.showsDial { ClimateControlDial(entity: source.entity, controller: controller) }
            else { Color.clear }
        }
    }
}
