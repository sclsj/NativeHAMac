import AppKit
import NativeHACore
import SwiftUI
import XCTest
@testable import NativeHAMac

@MainActor
final class ClimateFollowupTests: XCTestCase {
    func testTwoModeToggleUsesAuthoritativeSelectionAndSafeMenuFallback() throws {
        let entity = try ClimateFixtures.entity("off")
        let controller = ClimateServiceController()
        var calls: [ClimateServiceRequest] = []
        controller.install(entity: entity) { request, _ in calls.append(request); return true }
        defer { controller.close() }
        let button = ClimateModeNSButton()
        button.options = ["cool", "off"]
        button.selected = "off"
        button.togglesTwoOptions = true
        button.onSelection = { controller.mode("hvac_mode", value: $0) }
        button.performClick(nil)
        XCTAssertEqual(calls.last?.data["hvac_mode"], .string("cool"))
        XCTAssertEqual(button.selected, "off")
        XCTAssertEqual(controller.entity?.state.state, "off", "Sending a request must not predict HA state")
        controller.replace(try ClimateFixtures.entity(mode: "cool"))
        button.selected = "cool"
        button.performClick(nil)
        XCTAssertEqual(calls.last?.data["hvac_mode"], .string("off"))
        XCTAssertEqual(calls.count, 2)
        button.selected = "unknown"
        XCTAssertNil(button.toggleDestination)
        button.selected = "cool"
        button.options = ["cool", "heat", "off"]
        XCTAssertNil(button.toggleDestination)
        button.options = ["cool", "cool"]
        XCTAssertNil(button.toggleDestination)
        button.options = ["cool", "off"]
        button.togglesTwoOptions = false
        XCTAssertNil(button.toggleDestination, "Preset and other controls retain menus even with two choices")
    }

    func testMountedRoundedEndpointClicksCommitExtremeValues() throws {
        let fixture = try ClimateFollowupHost(value: 22)
        defer { fixture.close() }
        let input = try fixture.input()
        let geometry = ClimateDialGeometry(size: input.bounds.size)
        for (progress, offset) in [(0.0, CGFloat(8)), (1.0, CGFloat(-8))] {
            let endpoint = geometry.point(progress)
            // Inside the visible round cap, beyond the angular centerline.
            let point = CGPoint(x: endpoint.x + offset, y: endpoint.y + 8)
            XCTAssertTrue(geometry.contains(point), "The visible rounded endpoint must accept clicks")
            XCTAssertTrue(fixture.host.hitTest(input.convert(point, to: fixture.host.superview)) === input)
            try fixture.click(point)
            XCTAssertEqual(fixture.controller.values[.value], progress == 0 ? 19 : 28)
        }
        XCTAssertEqual(fixture.calls.count, 2)
        XCTAssertFalse(geometry.contains(CGPoint(x: 160, y: 305)))
        XCTAssertFalse(geometry.contains(geometry.center))
    }

    func testMountedAuthoritativeOffCoolFade() throws {
        let fixture = try ClimateFollowupHost(value: 21.4, mode: "off")
        defer { fixture.close() }
        for (index, mode) in ["cool", "off"].enumerated() {
            fixture.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(21.4)], mode: mode))
            let early = try fixture.capture("fade-\(index)-early", after: 0.015)
            let middle = try fixture.capture("fade-\(index)-middle", after: 0.065)
            let final = try fixture.capture("fade-\(index)-final", after: 0.25)
            let differences = try [early, middle, final].map { try tailChroma($0) }
            if mode == "cool" {
                XCTAssertLessThan(differences[0] + 0.03, differences[1])
                XCTAssertLessThan(differences[1] + 0.03, differences[2])
            } else {
                XCTAssertGreaterThan(differences[0], differences[1] + 0.03)
                XCTAssertGreaterThan(differences[1], differences[2] + 0.03)
            }
        }
        XCTAssertTrue(fixture.calls.isEmpty)
    }

    func testMultiModeFadeOutDoesNotFlashAnotherColorOrArc() throws {
        let fixture = try ClimateFollowupHost(value: 24.6)
        defer { fixture.close() }
        let modes: JSONValue = .array([.string("heat"), .string("cool"), .string("off")])
        fixture.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(24.6), "hvac_modes": modes], mode: "cool"))
        fixture.settle(0.3)
        fixture.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(24.6), "hvac_modes": modes], mode: "off"))
        let early = try fixture.capture("multimode-off-early", after: 0.04)
        XCTAssertGreaterThan(try tailChroma(early), 0.08)
        let bitmap = NSBitmapImageRep(cgImage: early)
        let point = ClimateDialGeometry(size: CGSize(width: 320, height: 320)).point(0.2)
        let scale = CGFloat(early.width) / 320
        let color = try XCTUnwrap(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        XCTAssertEqual(color.redComponent, color.blueComponent, accuracy: 0.02, "Inactive transition must not flash a full yellow track")
        _ = try fixture.capture("multimode-off-final", after: 0.25)
    }

    func testActualButtonTrackingDoesNotLoseRapidActions() throws {
        let fixture = try ClimateFollowupHost(value: 21.9)
        defer { fixture.close() }
        let plus = try XCTUnwrap(fixture.descendants(fixture.host).compactMap { $0 as? ClimateAdjustmentNSButton }.first { $0.accessibilityLabel() == "Increase target" })
        var frames: [CGImage] = []
        for index in 0..<4 {
            let point = plus.convert(CGPoint(x: 24, y: 24), to: nil)
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: index, clickCount: 1, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.08, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: index, clickCount: 1, pressure: 0))
            let capture = Timer(timeInterval: 0.025, repeats: true) { _ in
                if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(fixture.window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) { frames.append(image) }
            }
            let release = Timer(timeInterval: 0.08, repeats: false) { _ in NSApplication.shared.postEvent(up, atStart: true) }
            RunLoop.main.add(capture, forMode: .eventTracking)
            RunLoop.main.add(release, forMode: .eventTracking)
            plus.mouseDown(with: down)
            capture.invalidate(); release.invalidate()
            fixture.settle(0.025)
            XCTAssertEqual(try XCTUnwrap(fixture.controller.values[.value]), 22 + Double(index) * 0.1, accuracy: 0.00001)
        }
        XCTAssertGreaterThanOrEqual(frames.count, 4)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-followups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, frame) in frames.enumerated() {
            try XCTUnwrap(NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("tracking-\(index).png"))
        }
        let final = try fixture.capture("tracking-final", after: 0.35)
        let positions = try frames.map { try knobProgress($0) }
        XCTAssertGreaterThan(positions.last ?? 0, (positions.first ?? 0) + 0.01, "An existing dial animation must advance during later native button tracking loops")
        for index in 1..<positions.count { XCTAssertGreaterThanOrEqual(positions[index], positions[index - 1] - 0.001) }
        XCTAssertEqual(try knobProgress(final), (22.3 - 19) / 9, accuracy: 0.003)
        fixture.controller.cancelDebounce()
        print("Climate button tracking: \(frames.count) actual compositor samples during four 80ms native tracking loops; positions \(positions); final local target \(fixture.controller.values[.value] ?? 0)")
    }

    func testModeFadeAndTargetMotionHaveIndependentDurationsAndReverse() throws {
        let fixture = try ClimateFollowupHost(value: 20, mode: "off")
        defer { fixture.close() }
        fixture.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(26.2)], mode: "cool"))
        let early = try fixture.capture("simultaneous-early", after: 0.02)
        let modeFinished = try fixture.capture("simultaneous-mode-finished", after: 0.19)
        let final = try fixture.capture("simultaneous-final", after: 0.2)
        XCTAssertLessThan(try knobProgress(early), try knobProgress(modeFinished) - 0.03)
        XCTAssertLessThan(try knobProgress(modeFinished), try knobProgress(final) - 0.01, "Mode color must not shorten the established target animation")
        XCTAssertEqual(try tailChroma(modeFinished), try tailChroma(final), accuracy: 0.02)
        XCTAssertEqual(try knobProgress(final), 0.8, accuracy: 0.003)
        fixture.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(26.2)], mode: "off"))
        let outbound = try fixture.capture("fade-reversal-outbound", after: 0.07)
        fixture.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(26.2)], mode: "cool"))
        let reverseEarly = try fixture.capture("fade-reversal-early", after: 0.025)
        let reverseFinal = try fixture.capture("fade-reversal-final", after: 0.25)
        XCTAssertGreaterThan(try tailChroma(outbound), 0.03)
        XCTAssertLessThan(try tailChroma(reverseEarly), try tailChroma(reverseFinal) - 0.03)
        XCTAssertEqual(try tailChroma(reverseFinal), try tailChroma(final), accuracy: 0.02)
        XCTAssertTrue(fixture.calls.isEmpty)
    }

    func testTabularNumberOptionKeepsIntegerPositionAcrossFractionWidths() throws {
        var integerCrops: [Data] = []
        for value in [22.1, 22.9] {
            let view = ClimateLargeNumber(value: value, digits: 1, unit: "°C", preferences: nil, layout: .tabularDigits).foregroundColor(.white).frame(width: 230, height: 100).background(Color.black)
            let rendered = try MacViewPNGRenderer.render(view, size: CGSize(width: 230, height: 100), displayScale: 2)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered.pngData))
            let image = try XCTUnwrap(bitmap.cgImage)
            // The integer occupies the left part of the centered number;
            // the decimal/unit stack starts to its right (x≈133 points).
            let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: 260, height: 200)))
            integerCrops.append(try XCTUnwrap(NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])))
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-followups")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try rendered.pngData.write(to: directory.appendingPathComponent("tabular-\(value).png"))
        }
        XCTAssertEqual(integerCrops[0], integerCrops[1])
    }

    private func knobProgress(_ image: CGImage) throws -> Double {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(image.width) / 320
        var count = 0
        var sum = CGPoint.zero
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                guard abs(hypot(point.x - 160, point.y - 160) - 145) < 20,
                      let color = bitmap.colorAt(x: x, y: y), min(color.redComponent, color.greenComponent, color.blueComponent) > 0.975 else { continue }
                count += 1; sum.x += point.x; sum.y += point.y
            }
        }
        XCTAssertGreaterThan(count, 100)
        return ClimateValueMapping.progress(at: CGPoint(x: sum.x / CGFloat(max(count, 1)), y: sum.y / CGFloat(max(count, 1))), size: CGSize(width: 320, height: 320))
    }

    func testMountedPointerNumberChangesWithoutAnimatedClipping() throws {
        let fixture = try ClimateFollowupHost(value: 21.9)
        defer { fixture.close() }
        for value in [22.1, 21.9, 22.1] {
            let input = try fixture.input()
            try fixture.click(ClimateDialGeometry(size: input.bounds.size).point((value - 19) / 9))
            let early = try fixture.capture("number-\(value)-early", after: 0.04)
            let middle = try fixture.capture("number-\(value)-middle", after: 0.07)
            let final = try fixture.capture("number-\(value)-final", after: 0.3)
            XCTAssertEqual(try numberPixels(early), try numberPixels(final), "New glyphs must fit immediately, without inheriting dial layout interpolation")
            XCTAssertEqual(try numberPixels(middle), try numberPixels(final))
        }
    }

    private func tailChroma(_ image: CGImage) throws -> CGFloat {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let point = ClimateDialGeometry(size: CGSize(width: 320, height: 320)).point(0.9)
        let scale = CGFloat(image.width) / 320
        let color = try XCTUnwrap(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.deviceRGB))
        return color.blueComponent - color.redComponent
    }

    private func numberPixels(_ image: CGImage) throws -> Data {
        let scale = CGFloat(image.width) / 320
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 85 * scale, y: 125 * scale, width: 150 * scale, height: 70 * scale)))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class ClimateFollowupSource: ObservableObject {
    @Published var entity: ClimateEntity
    init(_ entity: ClimateEntity) { self.entity = entity }
}

private struct ClimateFollowupDial: View {
    @ObservedObject var source: ClimateFollowupSource
    let controller: ClimateServiceController
    var body: some View { ClimateControlDial(entity: source.entity, controller: controller) }
}

@MainActor
private final class ClimateFollowupHost {
    let source: ClimateFollowupSource
    let controller = ClimateServiceController()
    let model: DashboardViewModel
    let host: NSHostingView<AnyView>
    let window: NSWindow
    var calls: [ClimateServiceRequest] = []

    init(value: Double, mode: String = "cool") throws {
        let entity = try ClimateFixtures.entity(overrides: ["temperature": .double(value)], mode: mode)
        source = ClimateFollowupSource(entity)
        model = DashboardViewModel(initialStates: [entity.entityID: entity.state])
        host = NSHostingView(rootView: AnyView(ClimateFollowupDial(source: source, controller: controller).environmentObject(model).foregroundColor(.white).background(Color(white: 28 / 255))))
        _ = NSApplication.shared
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        controller.install(entity: entity) { [weak self] request, _ in self?.calls.append(request); return true }
        window.orderBack(nil)
        settle(0.1)
    }
    func close() { controller.close(); window.orderOut(nil); window.close() }
    func replace(_ entity: ClimateEntity) { source.entity = entity; controller.replace(entity) }
    func input() throws -> ClimateDialNSView { try XCTUnwrap(descendants(host).compactMap { $0 as? ClimateDialNSView }.first) }
    func click(_ point: CGPoint) throws {
        let input = try self.input()
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: input.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { input.mouseDown(with: event) } else { input.mouseUp(with: event) }
        }
    }
    func capture(_ name: String, after delay: Double) throws -> CGImage {
        settle(delay)
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-followups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
        return image
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    func settle(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
}
