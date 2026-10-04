import XCTest
import AppKit
import SwiftUI
import NativeHACore
@testable import NativeHAMac

@MainActor
final class ClimatePendingFeedbackTests: XCTestCase {
    func testButtonDraftSurvivesModeEchoBeforeDebounce() async throws {
        for policy in [ClimateModeFeedback.immediate, .authoritative] {
            let clock = ClimatePendingClock()
            let controller = ClimateServiceController(debounceNanoseconds: 1, modeFeedback: policy, confirmationNanoseconds: 10, sleep: { await clock.wait($0) })
            let initial = try ClimateFixtures.entity(overrides: ["temperature": .double(22)], mode: "off")
            var calls: [ClimateServiceRequest] = []
            controller.install(entity: initial) { request, _ in calls.append(request); return true }
            defer { controller.close() }
            controller.button(1, target: .value)
            controller.mode("hvac_mode", value: "cool")
            controller.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(22)], mode: "cool"))
            XCTAssertEqual(controller.values[.value]!, 22.1, accuracy: 0.00001)
            for _ in 0..<100 { await Task.yield() }
            await clock.release(1)
            for _ in 0..<1000 where calls.count < 2 { await Task.yield() }
            XCTAssertEqual(calls.last?.data["temperature"], .double(22.1))
            controller.close()
            await clock.releaseAll()
        }
    }

    func testEarlierButtonEchoDoesNotEraseNewerIntentAndExternalTargetWins() throws {
        let controller = ClimateServiceController()
        var calls: [ClimateServiceRequest] = []
        var completions: [(String?) -> Void] = []
        controller.install(entity: try ClimateFixtures.entity(overrides: ["temperature": .double(22)])) {
            calls.append($0); completions.append($1); return true
        }
        defer { controller.close() }
        controller.button(1, target: .value)
        controller.commit(.value)
        controller.button(1, target: .value)
        controller.commit(.value)
        controller.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(22.1)]))
        XCTAssertEqual(controller.values[.value]!, 22.2, accuracy: 1e-8)
        completions[0]("Superseded request failed")
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.values[.value]!, 22.2, accuracy: 1e-8)
        controller.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(22.2)]))
        completions[1]("Late failure after confirmation")
        XCTAssertNil(controller.error)
        controller.button(1, target: .value)
        controller.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(25)]))
        XCTAssertEqual(controller.values[.value], 25)
        XCTAssertEqual(calls.count, 2)
    }

    func testRoundedEarlierEchoAndDifferentEntityCannotReusePendingIntent() async throws {
        let clock = ClimatePendingClock()
        let controller = ClimateServiceController(debounceNanoseconds: 1, sleep: { await clock.wait($0) })
        var calls: [ClimateServiceRequest] = []
        let initial = try ClimateFixtures.entity(overrides: ["temperature": .double(22.1)], mode: "off")
        controller.install(entity: initial) { request, _ in calls.append(request); return true }
        controller.button(1, target: .value)
        controller.button(1, target: .value)
        controller.commit(.value)
        controller.button(1, target: .value)
        controller.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(22.3)], mode: "off"))
        XCTAssertEqual(controller.values[.value]!, 22.4, accuracy: 1e-8)
        controller.mode("hvac_mode", value: "cool")
        let different = ClimateEntity(state: HAState(entityId: "climate.other", state: "off", attributes: initial.state.attributes, lastChanged: initial.state.lastChanged, lastUpdated: initial.state.lastUpdated), unit: initial.unit)
        controller.replace(different)
        XCTAssertNil(controller.pendingMode)
        XCTAssertEqual(controller.values[.value], 22.1)
        for _ in 0..<100 { await Task.yield() }
        await clock.releaseAll()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.last?.data["entity_id"], .string(initial.entityID))
        controller.close()
    }

    func testImmediateReversalRetainsLatestModeThroughBaselineAndOlderEcho() throws {
        let controller = ClimateServiceController()
        let off = try ClimateFixtures.entity("off")
        var calls: [ClimateServiceRequest] = []
        var completions: [(String?) -> Void] = []
        controller.install(entity: off) { calls.append($0); completions.append($1); return true }
        defer { controller.close() }
        controller.mode("hvac_mode", value: "cool")
        XCTAssertEqual(controller.presentation(off).displayedMode, "cool")
        XCTAssertEqual(controller.entity?.state.state, "off")
        controller.mode("hvac_mode", value: "off")
        XCTAssertEqual(calls.map { $0.data["hvac_mode"] }, [.string("cool"), .string("off")])
        XCTAssertTrue(ClimateServiceBuilder.isSupported(calls[1], entity: off))
        controller.replace(off)
        XCTAssertEqual(controller.pendingMode, "off", "An unrelated unchanged baseline is not confirmation of the reversal")
        controller.replace(try ClimateFixtures.entity(mode: "cool"))
        XCTAssertEqual(controller.pendingMode, "off")
        completions[0]("Old failure")
        XCTAssertEqual(controller.pendingMode, "off")
        XCTAssertNil(controller.error)
        completions[1](nil)
        XCTAssertEqual(controller.pendingMode, "off", "A service acknowledgement alone is not state confirmation")
        controller.replace(off)
        XCTAssertNil(controller.pendingMode)
    }

    func testNewestFailureRejectionAndUnavailableDiscardPendingPresentation() throws {
        let controller = ClimateServiceController()
        let off = try ClimateFixtures.entity("off")
        var completion: ((String?) -> Void)?
        controller.install(entity: off) { _, callback in completion = callback; return true }
        controller.mode("hvac_mode", value: "cool")
        completion?("Failure")
        XCTAssertNil(controller.pendingMode)
        XCTAssertEqual(controller.error, "Failure")
        controller.button(1, target: .value)
        controller.commit(.value)
        completion?("Target failure")
        XCTAssertEqual(controller.values[.value], off.value(.value))
        controller.mode("hvac_mode", value: "cool")
        controller.button(1, target: .value)
        controller.replace(try ClimateFixtures.entity("unavailable"))
        XCTAssertNil(controller.pendingMode)
        controller.close()
        completion?("Dismissed failure")
        XCTAssertNil(controller.error)
        controller.install(entity: off) { _, _ in false }
        controller.mode("hvac_mode", value: "cool")
        XCTAssertNil(controller.pendingMode)
        XCTAssertNotNil(controller.error)
        controller.close()
    }

    func testModeAndTargetTimeoutsUseLatestServerAndCannotSurviveDismissal() async throws {
        let clock = ClimatePendingClock()
        let controller = ClimateServiceController(confirmationNanoseconds: 10, sleep: { await clock.wait($0) })
        let off = try ClimateFixtures.entity("off")
        controller.install(entity: off) { _, _ in true }
        controller.mode("hvac_mode", value: "cool")
        controller.button(1, target: .value)
        controller.commit(.value)
        for _ in 0..<100 { await Task.yield() }
        await clock.release(10)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(controller.pendingMode)
        XCTAssertEqual(controller.values[.value], off.value(.value))
        XCTAssertNotNil(controller.error)
        controller.mode("hvac_mode", value: "cool")
        controller.button(1, target: .value)
        controller.commit(.value)
        for _ in 0..<100 { await Task.yield() }
        controller.close()
        controller.install(entity: off) { _, _ in true }
        await clock.releaseAll()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(controller.error)
        XCTAssertNil(controller.pendingMode)
        controller.close()
    }

    func testCapabilityChangeCancelsButtonIntentBeforeSend() async throws {
        for overrides: [String: JSONValue] in [["max_temp": .double(22)], ["supported_features": .int(0)], ["temperature": .null]] {
            let clock = ClimatePendingClock()
            let controller = ClimateServiceController(debounceNanoseconds: 1, sleep: { await clock.wait($0) })
            let initial = try ClimateFixtures.entity(overrides: ["temperature": .double(22)])
            var calls = 0
            controller.install(entity: initial) { _, _ in calls += 1; return true }
            controller.button(1, target: .value)
            controller.replace(try ClimateFixtures.entity(overrides: overrides))
            for _ in 0..<100 { await Task.yield() }
            await clock.releaseAll()
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(calls, 0)
            controller.close()
        }
    }

    func testMountedModeStartsFadingBeforeServiceCompletionAndButtonDraftSurvivesEcho() async throws {
        let clock = ClimatePendingClock()
        let controller = ClimateServiceController(debounceNanoseconds: 1, confirmationNanoseconds: 10, sleep: { await clock.wait($0) })
        let initial = try ClimateFixtures.entity(overrides: ["temperature": .double(20), "target_temp_step": .double(1)], mode: "off")
        let fixture = ClimatePendingHost(entity: initial, controller: controller)
        defer { fixture.close() }
        let mode = try XCTUnwrap(fixture.descendants.compactMap { $0 as? ClimateModeNSButton }.first { $0.titleLabel == "Mode" })
        // Exercise focused button activation; the window otherwise chooses
        // the dial as its initial keyboard responder and paints its focus ring.
        fixture.window.makeFirstResponder(mode)
        mode.performClick(nil)
        XCTAssertEqual(controller.pendingMode, "cool")
        XCTAssertEqual(fixture.model.states[initial.entityID]?.state, "off")
        let early = try fixture.capture("mode-activation-early", after: 0.015)
        let middle = try fixture.capture("mode-activation-middle", after: 0.065)
        let final = try fixture.capture("mode-activation-final", after: 0.25)
        XCTAssertLessThan(try tailChroma(early) + 0.03, try tailChroma(middle))
        XCTAssertLessThan(try tailChroma(middle) + 0.03, try tailChroma(final))
        XCTAssertEqual(mode.selected, "cool")
        XCTAssertEqual(controller.entity?.state.state, "off")
        XCTAssertEqual(controller.presentation(initial).actionLabel, "Cool", "Pending mode must not invent a cooling/idle action")
        let plus = try XCTUnwrap(fixture.descendants.compactMap { $0 as? ClimateAdjustmentNSButton }.first { $0.accessibilityLabel() == "Increase target" })
        plus.performClick(nil)
        plus.performClick(nil)
        mode.performClick(nil)
        XCTAssertEqual(controller.values[.value], 22)
        XCTAssertEqual(controller.pendingMode, "off")
        let targetEarly = try fixture.capture("button-mode-early", after: 0.02)
        let echo = try ClimateFixtures.entity(overrides: ["temperature": .double(20), "target_temp_step": .double(1)], mode: "cool")
        fixture.replace(echo)
        let targetMiddle = try fixture.capture("button-mode-older-echo", after: 0.10)
        XCTAssertEqual(controller.values[.value], 22)
        XCTAssertEqual(controller.pendingMode, "off")
        let targetFinal = try fixture.capture("button-mode-final", after: 0.3)
        XCTAssertLessThan(try knobProgress(targetEarly), try knobProgress(targetMiddle) - 0.02)
        XCTAssertLessThan(try knobProgress(targetMiddle), try knobProgress(targetFinal) - 0.02)
        XCTAssertEqual(try knobProgress(targetFinal), 3.0 / 9, accuracy: 0.004)
        XCTAssertEqual(try tailChroma(targetFinal), 0, accuracy: 0.02)
        for _ in 0..<100 { await Task.yield() }
        await clock.release(1)
        for _ in 0..<100 { await Task.yield() }
        let calls = await fixture.services.calls
        XCTAssertEqual(calls.map(\.service), ["set_hvac_mode", "set_hvac_mode", "set_temperature"])
        XCTAssertEqual(calls.last?.data["temperature"], .double(22))
        XCTAssertEqual(fixture.model.states[initial.entityID]?.attributes["temperature"], .double(20))
        fixture.replace(try ClimateFixtures.entity(overrides: ["temperature": .double(22), "target_temp_step": .double(1)], mode: "off"))
        let confirmed = try fixture.capture("confirmed-final", after: 0.1)
        XCTAssertEqual(try knobProgress(confirmed), 3.0 / 9, accuracy: 0.004)
        XCTAssertNil(controller.pendingMode)
        await fixture.services.releaseAll()
        fixture.close()
        await clock.releaseAll()
        print("Mounted climate: mode fade and target motion measured while all service completions were gated; three exact requests, no shared optimistic state.")
    }

    func testMountedSecondActivationUsesLatestModeBeforeAppKitRefresh() async throws {
        let controller = ClimateServiceController()
        let initial = try ClimateFixtures.entity("off")
        let fixture = ClimatePendingHost(entity: initial, controller: controller)
        defer { fixture.close() }
        let mode = try XCTUnwrap(fixture.descendants.compactMap { $0 as? ClimateModeNSButton }.first { $0.titleLabel == "Mode" })
        mode.performClick(nil)
        XCTAssertEqual(controller.pendingMode, "cool")
        // The accepted callback arrives before SwiftUI redraws the button;
        // its installed action still captures the previous Off presentation.
        controller.replace(try ClimateFixtures.entity(mode: "cool"))
        XCTAssertNil(controller.pendingMode)
        mode.performClick(nil)
        XCTAssertEqual(controller.pendingMode, "off")
        for _ in 0..<100 { await Task.yield() }
        let calls = await fixture.services.calls
        XCTAssertEqual(calls.map { $0.data["hvac_mode"] }, [.string("cool"), .string("off")])
        fixture.close()
        await fixture.services.releaseAll()
    }

    private func tailChroma(_ image: CGImage) throws -> CGFloat {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let point = ClimateDialGeometry(size: CGSize(width: 320, height: 320)).point(0.9)
        let scale = CGFloat(image.width) / 320
        let color = try XCTUnwrap(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return color.blueComponent - color.redComponent
    }

    private func knobProgress(_ image: CGImage) throws -> Double {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(image.width) / 320
        var sum = CGPoint.zero
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                guard abs(hypot(point.x - 160, point.y - 160) - 145) < 20,
                      let color = bitmap.colorAt(x: x, y: y), min(color.redComponent, color.greenComponent, color.blueComponent) > 0.975 else { continue }
                sum.x += point.x; sum.y += point.y; count += 1
            }
        }
        XCTAssertGreaterThan(count, 100)
        return ClimateValueMapping.progress(at: CGPoint(x: sum.x / CGFloat(max(count, 1)), y: sum.y / CGFloat(max(count, 1))), size: CGSize(width: 320, height: 320))
    }
}

@MainActor
private final class ClimatePendingSource: ObservableObject {
    @Published var entity: ClimateEntity
    init(_ entity: ClimateEntity) { self.entity = entity }
}

private struct ClimatePendingContent: View {
    @ObservedObject var source: ClimatePendingSource
    let controller: ClimateServiceController
    var body: some View { ClimateDetailContent(entityID: source.entity.entityID, state: source.entity.state, controller: controller) }
}

@MainActor
private final class ClimatePendingHost {
    let source: ClimatePendingSource
    let controller: ClimateServiceController
    let model: DashboardViewModel
    let services = ClimatePendingServices()
    let host: NSHostingView<AnyView>
    let window: NSWindow
    private var closed = false
    init(entity: ClimateEntity, controller: ClimateServiceController) {
        self.controller = controller
        source = ClimatePendingSource(entity)
        model = DashboardViewModel(initialStates: [entity.entityID: entity.state], homeAssistantConfig: HAConfig(unitSystem: HAUnitSystem(temperature: "°C")))
        let services = self.services
        model.installServiceCallerForTesting { _, service, data in await services.call(ClimateServiceRequest(service: service, data: data)) }
        model.openDetails(entityID: entity.entityID)
        host = NSHostingView(rootView: AnyView(ClimatePendingContent(source: source, controller: controller).environmentObject(model).background(Color(white: 28 / 255))))
        _ = NSApplication.shared
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 380, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        settle(0.1)
    }
    var descendants: [NSView] {
        func visit(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { visit($0) } }
        return visit(host)
    }
    func replace(_ entity: ClimateEntity) {
        source.entity = entity
        model.states[entity.entityID] = entity.state
        model.acceptClimateReplacement(entityIDs: [entity.entityID])
    }
    func close() {
        guard !closed else { return }
        closed = true
        controller.close(); model.closeDetails(); window.orderOut(nil); window.close()
    }
    func capture(_ name: String, after delay: Double) throws -> CGImage {
        settle(delay)
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-pending-feedback")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + "-panel.png"))
        let input = try XCTUnwrap(descendants.compactMap { $0 as? ClimateDialNSView }.first)
        let scale = CGFloat(image.width) / host.bounds.width
        var rect = input.convert(input.bounds, to: host)
        if !host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
        let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)))
        try XCTUnwrap(NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
        return cropped
    }
    private func settle(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
}

private actor ClimatePendingServices {
    private(set) var calls: [ClimateServiceRequest] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func call(_ request: ClimateServiceRequest) async {
        calls.append(request)
        await withCheckedContinuation { waiters.append($0) }
    }
    func releaseAll() { let ready = waiters; waiters = []; ready.forEach { $0.resume() } }
}

actor ClimatePendingClock {
    private var waiters: [(UInt64, CheckedContinuation<Void, Never>)] = []
    func wait(_ duration: UInt64) async { await withCheckedContinuation { waiters.append((duration, $0)) } }
    func release(_ duration: UInt64) {
        let ready = waiters.filter { $0.0 == duration }
        waiters.removeAll { $0.0 == duration }
        ready.forEach { $0.1.resume() }
    }
    func releaseAll() { let ready = waiters; waiters = []; ready.forEach { $0.1.resume() } }
}
