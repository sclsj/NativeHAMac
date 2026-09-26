import AppKit
import NativeHACore
import SwiftUI
import XCTest
@testable import NativeHAMac

enum ClimateFixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Climate")
    static func states() throws -> [(String, HAState)] {
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("render-states.json"))) as! [String: Any]
        let base = document["base"] as! [String: Any]
        return try (document["variants"] as! [[String: Any]]).map { variant in
            var result = base
            var attributes = variant["replaceAttributes"] as? Bool == true ? [:] : base["attributes"] as! [String: Any]
            attributes.merge(variant["attributes"] as! [String: Any]) { _, new in new }
            result["attributes"] = attributes
            result["state"] = variant["state"]
            result["last_changed"] = document["timestamp"]
            result["last_updated"] = document["timestamp"]
            return (variant["name"] as! String, try JSONDecoder().decode(HAState.self, from: JSONSerialization.data(withJSONObject: result)))
        }
    }
    static func entity(_ name: String = "cooling", overrides: [String: JSONValue] = [:], mode: String? = nil, unit: String = "°C") throws -> ClimateEntity {
        let state = try states().first { $0.0 == name }!.1
        var attributes = state.attributes
        attributes.merge(overrides) { _, new in new }
        return ClimateEntity(state: HAState(entityId: state.entityId, state: mode ?? state.state, attributes: attributes, lastChanged: state.lastChanged, lastUpdated: state.lastUpdated), unit: unit)
    }
}

final class ClimateEntityTests: XCTestCase {
    func testSparseMalformedAndIndependentReadings() throws {
        let sparse = try ClimateFixtures.entity("sparse")
        XCTAssertNil(sparse.currentTemperature)
        XCTAssertNil(sparse.value(.value))
        XCTAssertNil(sparse.temperatureBounds)
        XCTAssertEqual(sparse.hvacModes, [])
        XCTAssertEqual(sparse.targetKind, .readOnly)
        for malformed in [JSONValue.string("23"), .null, .bool(true), .double(.infinity), .double(.nan)] {
            let entity = try ClimateFixtures.entity(overrides: ["temperature": malformed, "current_temperature": malformed])
            XCTAssertNil(entity.currentTemperature)
            XCTAssertNil(entity.value(.value))
        }
        for mask in [JSONValue.double(1e100), .double(-1), .double(.infinity), .double(1.5)] {
            XCTAssertTrue(try ClimateFixtures.entity(overrides: ["supported_features": mask]).features.isEmpty)
        }
        XCTAssertEqual(try ClimateFixtures.entity(overrides: ["current_temperature": .int(0)]).currentTemperature, 0)
    }

    func testFeaturesPrecedenceAndOptionalMenus() throws {
        for mask in [1,2,4,8,16,32,64,128,256,512] {
            XCTAssertEqual(try ClimateFixtures.entity(overrides: ["supported_features": .int(mask)]).features.rawValue, mask)
        }
        let full = try ClimateFixtures.entity("complete")
        XCTAssertEqual(full.targetKind, .range)
        XCTAssertEqual(full.options("swing_horizontal_mode"), ["off", "horizontal"])
        XCTAssertEqual(try ClimateFixtures.entity("complete", overrides: ["supported_features": .int(1023), "temperature": .double(22)]).targetKind, .single)
        XCTAssertEqual(try ClimateFixtures.entity("complete", overrides: ["target_temp_high": .null]).targetKind, .readOnly)
        XCTAssertNil(try ClimateFixtures.entity("complete", overrides: ["supported_features": .int(0)]).options("fan_mode"))
        XCTAssertTrue(try ClimateFixtures.entity("unknown").canAdjust(.value))
        XCTAssertTrue(try ClimateFixtures.entity("off").canAdjust(.value))
        XCTAssertFalse(try ClimateFixtures.entity("unavailable").canAdjust(.value))
        XCTAssertEqual(full.hvacModes, ["heat_cool", "heat", "cool", "off"])
    }

    func testUnitsActionsAndSteps() throws {
        XCTAssertEqual(try ClimateFixtures.entity(overrides: ["temperature_unit": .string("wrong"), "target_temp_step": .null], unit: "°F").step, 1)
        XCTAssertEqual(try ClimateFixtures.entity(overrides: ["target_temp_step": .int(0)]).step, 0.5)
        XCTAssertEqual(try ClimateFixtures.entity("off").actionLabel, "Off")
        XCTAssertEqual(try ClimateFixtures.entity("idle").actionLabel, "Idle")
        XCTAssertEqual(ClimateEntity.label("my_custom_mode"), "my_custom_mode")
        XCTAssertEqual(ClimateNumberFormatting.format(22.25, digits: 2, unit: "°C", preferences: nil), "22.25 °C")
        XCTAssertEqual(ClimateNumberFormatting.format(22.25, digits: 1, unit: "°C", preferences: nil), "22.3 °C")
        XCTAssertEqual(ClimateNumberFormatting.format(-22.25, digits: 1, unit: "°C", preferences: nil), "-22.3 °C")
    }

    func testPointerAndButtonAsymmetryMatchesSourceOracle() throws {
        let entity = try ClimateFixtures.entity(overrides: ["target_temp_step": .double(0.5)])
        XCTAssertEqual(ClimateValueMapping.adjusted(22.75, target: .value, values: [:], entity: entity, snap: false), 22.75)
        XCTAssertEqual(ClimateValueMapping.adjusted(22.75, target: .value, values: [:], entity: entity, snap: true), 23)
        XCTAssertEqual(ClimateValueMapping.stepped(-1.25, step: 0.5), -1)
        let offGrid = try ClimateFixtures.entity(overrides: ["min_temp": .double(19.2), "target_temp_step": .double(0.5)])
        XCTAssertEqual(ClimateValueMapping.adjusted(18, target: .value, values: [:], entity: offGrid, snap: true), 19)
        let geometry = ClimateDialGeometry(size: CGSize(width: 320, height: 320))
        for progress in [0.0, 0.5, 1.0] { XCTAssertEqual(ClimateValueMapping.progress(at: geometry.point(progress), size: geometry.size), progress, accuracy: 1e-9) }
        XCTAssertEqual(ClimateValueMapping.progress(at: CGPoint(x: 160, y: 320), size: geometry.size), 0)
        XCTAssertEqual(ClimateValueMapping.progress(at: CGPoint(x: 160.001, y: 320), size: geometry.size), 1)
        XCTAssertFalse(geometry.contains(geometry.center))
        XCTAssertTrue(geometry.contains(geometry.point(0.5)))
    }

    func testExactPayloadsAndRevalidation() throws {
        let entity = try ClimateFixtures.entity("complete")
        for (attribute, value) in [("hvac_mode", "heat"), ("preset_mode", "sleep"), ("fan_mode", "high"), ("swing_mode", "vertical"), ("swing_horizontal_mode", "horizontal")] {
            let request = try XCTUnwrap(ClimateServiceBuilder.mode(attribute, value: value, entity: entity))
            XCTAssertEqual(request.service, "set_" + attribute)
            XCTAssertEqual(request.data, ["entity_id": .string(entity.entityID), attribute: .string(value)])
            XCTAssertTrue(ClimateServiceBuilder.isSupported(request, entity: entity))
        }
        XCTAssertNil(ClimateServiceBuilder.mode("fan_mode", value: "invented", entity: entity))
        XCTAssertNil(ClimateServiceBuilder.mode("preset_mode", value: "none", entity: entity))
        let range = try XCTUnwrap(ClimateServiceBuilder.target(.low, values: [.low: 22, .high: 25], entity: entity))
        XCTAssertEqual(range.data, ["entity_id": .string(entity.entityID), "target_temp_low": .double(22), "target_temp_high": .double(25)])
        XCTAssertEqual(ClimateServiceBuilder.target(.humidity, values: [.humidity: 55], entity: entity)?.service, "set_humidity")
        XCTAssertEqual(ClimateServiceBuilder.power(on: true, entity: entity)?.service, "turn_on")
        XCTAssertEqual(ClimateServiceBuilder.power(on: false, entity: entity)?.service, "turn_off")
        XCTAssertFalse(ClimateServiceBuilder.isSupported(range, entity: try ClimateFixtures.entity("unavailable")))
    }

    func testColdTenThousandClimatePreparationsPerformance() throws {
        let states = try ClimateFixtures.states().map(\.1)
        var consumed = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for index in 0..<10_000 { let entity = ClimateEntity(state: states[index % states.count], unit: "°C"); consumed += entity.hvacModes.count + entity.features.rawValue; _ = entity.targetKind }
        }
        XCTAssertGreaterThan(consumed, 0)
    }

    func testWarmTenThousandMappingsPerformance() {
        let geometry = ClimateDialGeometry(size: CGSize(width: 320, height: 320))
        let points = (0..<10_000).map { geometry.point(Double($0) / 9999) }
        var result = 0.0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) { for point in points { result += ClimateValueMapping.progress(at: point, size: geometry.size) } }
        XCTAssertGreaterThan(result, 0)
    }
}

@MainActor
final class ClimateDetailInteractionTests: XCTestCase {
    func testHitTestingAtNonzeroFrameAndModeSelectionAction() throws {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let input = ClimateDialNSView(frame: CGRect(x: 50, y: 70, width: 320, height: 320))
        parent.addSubview(input)
        let geometry = ClimateDialGeometry(size: input.bounds.size)
        XCTAssertTrue(input.hitTest(input.convert(geometry.point(0.5), to: parent)) === input)
        XCTAssertNil(input.hitTest(input.convert(geometry.center, to: parent)))
        let entity = try ClimateFixtures.entity("complete")
        let controller = ClimateServiceController()
        var request: ClimateServiceRequest?
        controller.install(entity: entity) { call, _ in request = call; return true }
        let button = ClimateModeNSButton()
        button.onSelection = { controller.mode("swing_horizontal_mode", value: $0) }
        let item = NSMenuItem()
        item.representedObject = "horizontal"
        button.perform(NSSelectorFromString("selectOption:"), with: item)
        XCTAssertEqual(request?.data["swing_horizontal_mode"], .string("horizontal"))
        controller.close()
    }
    func testHostedProductionPointerKeyboardAndButtons() async throws {
        let entity = try ClimateFixtures.entity(overrides: ["temperature": .double(22.25), "target_temp_step": .double(0.5)])
        let controller = ClimateServiceController(debounceNanoseconds: 0)
        var requests: [ClimateServiceRequest] = []
        controller.install(entity: entity) { request, _ in requests.append(request); return true }
        let model = DashboardViewModel(initialStates: [entity.entityID: entity.state])
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: ClimateControlDial(entity: entity, controller: controller).environmentObject(model))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close(); controller.close() }
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        func descendants(_ view: NSView) -> [NSView] {
            var result = [view]
            for child in view.subviews { result.append(contentsOf: descendants(child)) }
            return result
        }
        let input = try XCTUnwrap(descendants(hosting).compactMap { $0 as? ClimateDialNSView }.first)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: input.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let geometry = ClimateDialGeometry(size: CGSize(width: 320, height: 320))
        input.mouseDown(with: try mouse(.leftMouseDown, geometry.point(0.2)))
        for index in 0..<1000 { input.mouseDragged(with: try mouse(.leftMouseDragged, geometry.point(Double(index) / 999))) }
        XCTAssertEqual(requests.count, 0)
        input.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 160, y: -100)))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.last?.data["temperature"], .double(23.5))
        input.mouseDown(with: try mouse(.leftMouseDown, geometry.point(0.5)))
        input.mouseDragged(with: try mouse(.leftMouseDragged, geometry.point(0.9)))
        input.cancelOperation(nil)
        input.mouseUp(with: try mouse(.leftMouseUp, geometry.point(0.9)))
        XCTAssertEqual(requests.count, 1)
        controller.replace(entity)
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 126))
        let up = try XCTUnwrap(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 126))
        input.keyDown(with: down)
        XCTAssertEqual(requests.count, 1)
        input.keyUp(with: up)
        XCTAssertEqual(requests.last?.data["temperature"], .double(22.75))
        let plus = try XCTUnwrap(descendants(hosting).compactMap { $0 as? ClimateAdjustmentNSButton }.first { $0.accessibilityLabel() == "Increase target" })
        XCTAssertEqual(plus.bounds.width, 48, accuracy: 0.5)
        XCTAssertEqual(plus.bounds.height, 48, accuracy: 0.5)
        plus.performClick(nil)
        for _ in 0..<1000 where requests.count < 3 { await Task.yield() }
        XCTAssertEqual(requests.last?.data["temperature"], .double(23.25))
        XCTAssertEqual(requests.count, 3)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
        window.makeFirstResponder(nil)
        input.needsDisplay = true
        hosting.displayIfNeeded()
        func bitmap() throws -> Data {
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        let unfocused = try bitmap()
        window.makeFirstResponder(input)
        hosting.displayIfNeeded()
        let focused = try bitmap()
        XCTAssertNotEqual(unfocused, focused)
        try FileManager.default.createDirectory(atPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts", withIntermediateDirectories: true)
        try focused.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-dial-focused.png"))
    }

    func testHeldModelCompletionsCannotPublishOlderOrDismissedError() async throws {
        let entity = try ClimateFixtures.entity()
        let model = DashboardViewModel(initialStates: [entity.entityID: entity.state], homeAssistantConfig: HAConfig(unitSystem: HAUnitSystem(temperature: "°C")))
        let gate = ClimateHeldCaller()
        model.installServiceCallerForTesting { _, _, data in try await gate.call(data) }
        model.openDetails(entityID: entity.entityID)
        for value in [23.0, 24.0] {
            let request = try XCTUnwrap(ClimateServiceBuilder.target(.value, values: [.value: value], entity: entity))
            XCTAssertTrue(model.invokeClimate(request, entityID: entity.entityID, completion: { _ in }))
        }
        for _ in 0..<1000 { if await gate.count == 2 { break }; await Task.yield() }
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 2)
        await gate.finish(24, failure: false)
        for _ in 0..<1000 where model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 2 { await Task.yield() }
        await gate.finish(23, failure: true)
        for _ in 0..<1000 where model.dashboardOwnerSnapshotForTesting().serviceTaskCount != 0 { await Task.yield() }
        XCTAssertFalse(model.componentFailures.contains { $0.0 == .service })
        let request = try XCTUnwrap(ClimateServiceBuilder.target(.value, values: [.value: 25], entity: entity))
        XCTAssertTrue(model.invokeClimate(request, entityID: entity.entityID, completion: { _ in }))
        for _ in 0..<1000 { if await gate.count == 1 { break }; await Task.yield() }
        model.closeDetails()
        model.openDetails(entityID: entity.entityID)
        await gate.finish(25, failure: true)
        for _ in 0..<1000 where model.dashboardOwnerSnapshotForTesting().serviceTaskCount != 0 { await Task.yield() }
        XCTAssertFalse(model.componentFailures.contains { $0.0 == .service })
        XCTAssertEqual(model.states[entity.entityID], entity.state)
        await model.stop()
    }

    func testMenuSuccessResyncAndControlRemountResetAuthoritativeDrafts() async throws {
        let gate = ClimateSleepGate()
        let entity = try ClimateFixtures.entity("complete")
        let controller = ClimateServiceController(sleep: { _ in await gate.wait() })
        var completions: [(String?) -> Void] = []
        controller.install(entity: entity) { _, completion in completions.append(completion); return true }
        controller.change(24, target: .low)
        controller.mode("hvac_mode", value: "heat")
        completions.removeFirst()(nil)
        controller.change(24.5, target: .low)
        for _ in 0..<100 { await Task.yield() }
        await gate.release()
        for _ in 0..<1000 where controller.values[.low] != 21 { await Task.yield() }
        XCTAssertEqual(controller.values[.low], 21)
        controller.change(23, target: .low)
        controller.selectTarget(.high)
        controller.selectMain(.humidity)
        controller.change(65, target: .humidity)
        controller.selectMain(.temperature)
        XCTAssertEqual(controller.values[.low], 21)
        XCTAssertEqual(controller.values[.humidity], 50)
        XCTAssertEqual(controller.selectedTarget, .low)
        controller.mode("hvac_mode", value: "heat")
        completions.removeFirst()(nil)
        controller.replace(try ClimateFixtures.entity("complete", overrides: ["target_temp_low": .double(20)]))
        controller.change(22, target: .low)
        for _ in 0..<100 { await Task.yield() }
        await gate.release()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(controller.values[.low], 22)
        controller.close()
    }
    func testDraftAuthoritativeReplacementAndFailureOrdering() throws {
        let entity = try ClimateFixtures.entity()
        let controller = ClimateServiceController()
        var requests: [ClimateServiceRequest] = []
        var completions: [(String?) -> Void] = []
        controller.install(entity: entity) { request, completion in requests.append(request); completions.append(completion); return true }
        for index in 0..<1000 { controller.change(19 + Double(index) / 999 * 9, target: .value) }
        XCTAssertEqual(requests.count, 0)
        controller.commit(.value)
        XCTAssertEqual(requests.count, 1)
        controller.change(25, target: .value)
        controller.commit(.value)
        completions[0]("Old failure")
        XCTAssertNil(controller.error)
        completions[1]("Current failure")
        XCTAssertEqual(controller.error, "Current failure")
        XCTAssertEqual(controller.values[.value], 25)
        controller.replace(entity)
        XCTAssertEqual(controller.values[.value], 22.8)
        XCTAssertNil(controller.error)
        controller.close()
        completions[1]("Late failure")
        XCTAssertNil(controller.error)
    }

    func testButtonDebounceUsesFinalDraftAndDismissalCancels() async throws {
        let gate = ClimateSleepGate()
        let controller = ClimateServiceController(sleep: { _ in await gate.wait() })
        let entity = try ClimateFixtures.entity(overrides: ["temperature": .double(22.25), "target_temp_step": .double(0.5)])
        var requests: [ClimateServiceRequest] = []
        controller.install(entity: entity) { request, _ in requests.append(request); return true }
        controller.button(1, target: .value)
        controller.button(1, target: .value)
        XCTAssertEqual(controller.values[.value], 23.25)
        XCTAssertTrue(requests.isEmpty)
        for _ in 0..<100 { await Task.yield() }
        await gate.release()
        for _ in 0..<1000 where requests.isEmpty { await Task.yield() }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.data["temperature"], .double(23.25))
        controller.button(-1, target: .value)
        controller.close()
        await gate.release()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(requests.count, 1)
    }

    func testHumiditySelectionRangeAndUnavailability() throws {
        let entity = try ClimateFixtures.entity("complete")
        let controller = ClimateServiceController()
        var calls: [ClimateServiceRequest] = []
        controller.install(entity: entity) { request, _ in calls.append(request); return true }
        controller.selectMain(.humidity)
        XCTAssertEqual(controller.mainControl, .humidity)
        controller.change(55, target: .humidity)
        controller.commit(.humidity)
        XCTAssertEqual(calls.last?.data["humidity"], .double(55))
        controller.replace(try ClimateFixtures.entity("complete", overrides: ["supported_features": .int(1018)]))
        XCTAssertEqual(controller.mainControl, .temperature)
        XCTAssertEqual(controller.selectedTarget, .low)
        XCTAssertTrue(controller.entity!.canAdjust(controller.selectedTarget))
        controller.change(30, target: .low, snap: false)
        XCTAssertEqual(controller.values[.low], 25)
        controller.commit(.low)
        XCTAssertEqual(calls.last?.data["target_temp_high"], .double(25))
        controller.replace(try ClimateFixtures.entity("unavailable"))
        XCTAssertEqual(controller.mainControl, .temperature)
        controller.change(26, target: .value)
        controller.commit(.value)
        XCTAssertEqual(calls.count, 2)
    }

    func testDashboardConcurrentCommitsRemainOwnedWithoutOptimisticState() async throws {
        let entity = try ClimateFixtures.entity("unknown")
        let model = DashboardViewModel(initialStates: [entity.entityID: entity.state], homeAssistantConfig: HAConfig(unitSystem: HAUnitSystem(temperature: "°C")))
        let recorder = ClimateRecorder()
        model.installServiceCallerForTesting { _, service, data in await recorder.record(service, data: data) }
        for value in [23.0, 24.0] {
            let request = try XCTUnwrap(ClimateServiceBuilder.target(.value, values: [.value: value], entity: entity))
            XCTAssertTrue(model.invokeClimate(request, entityID: entity.entityID, completion: { _ in }))
        }
        XCTAssertEqual(model.states[entity.entityID], entity.state)
        for _ in 0..<1000 { if await recorder.count == 2 { break }; await Task.yield() }
        let count = await recorder.count
        XCTAssertEqual(count, 2)
        await model.stop()
        XCTAssertFalse(model.canInvokeClimate(entityID: entity.entityID, service: "set_temperature"))
    }

    func testReplacementProvenanceAndHundredDetailLifetimes() async throws {
        let entity = try ClimateFixtures.entity()
        var model: DashboardViewModel? = DashboardViewModel(initialStates: [entity.entityID: entity.state])
        weak var weakModel = model
        for _ in 0..<100 {
            model?.openDetails(entityID: entity.entityID)
            let revision = model!.climateEntityRevision
            model?.acceptClimateReplacement(entityIDs: ["sensor.unrelated"])
            XCTAssertEqual(model?.climateEntityRevision, revision)
            model?.acceptClimateReplacement(entityIDs: [entity.entityID])
            XCTAssertEqual(model?.climateEntityRevision, revision + 1)
            var controller: ClimateServiceController? = ClimateServiceController()
            weak var weakController = controller
            controller?.install(entity: entity) { _, _ in true }
            controller?.button(1, target: .value)
            controller?.close()
            controller = nil
            XCTAssertNil(weakController)
            model?.closeDetails()
            XCTAssertEqual(model?.dashboardOwnerSnapshotForTesting().detailStartupCount, 0)
            XCTAssertTrue(model!.dashboardOwnerSnapshotForTesting().desiredDetailHistoryKeys.isEmpty)
        }
        await model?.stop()
        model = nil
        for _ in 0..<1000 where weakModel != nil { await Task.yield() }
        XCTAssertNil(weakModel)
    }

    func testWarmThousandDraftUpdatesAndReconciliationsPerformance() throws {
        let entity = try ClimateFixtures.entity()
        let controller = ClimateServiceController()
        var calls = 0
        controller.install(entity: entity) { _, _ in calls += 1; return true }
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for index in 0..<1000 { controller.change(19 + Double(index) / 1000 * 9, target: .value); controller.replace(entity) }
        }
        XCTAssertEqual(calls, 0)
        controller.commit(.value)
        XCTAssertEqual(calls, 1)
    }
}

actor ClimateSleepGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { await withCheckedContinuation { waiters.append($0) } }
    func release() { let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}
actor ClimateRecorder {
    private(set) var count = 0
    func record(_ service: String, data: [String: JSONValue]) { count += 1 }
}

actor ClimateHeldCaller {
    private var pending: [Double: CheckedContinuation<Void, Error>] = [:]
    var count: Int { pending.count }
    func call(_ data: [String: JSONValue]) async throws {
        guard case let .double(value)? = data["temperature"] else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in install(continuation, value: value) }
    }
    private func install(_ continuation: CheckedContinuation<Void, Error>, value: Double) { pending[value] = continuation }
    func finish(_ value: Double, failure: Bool) {
        let continuation = pending.removeValue(forKey: value)
        if failure { continuation?.resume(throwing: URLError(.badServerResponse)) } else { continuation?.resume() }
    }
}

@MainActor
final class ClimateDetailRenderingTests: XCTestCase {
    func testCompleteAndNarrowClimateFixtures() throws {
        try FileManager.default.createDirectory(atPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts", withIntermediateDirectories: true)
        for (name, state) in try ClimateFixtures.states() {
            let model = DashboardViewModel(initialStates: [state.entityId: state], homeAssistantConfig: HAConfig(unitSystem: HAUnitSystem(temperature: "°C")))
            model.installServiceCallerForTesting { _, _, _ in }
            for width in [520, 360] {
                let view = width == 520 ? AnyView(EntityDetailSheet(entityID: state.entityId)) : AnyView(ScrollView { ClimateDetailContent(entityID: state.entityId, state: state).padding(20) })
                let rendered = try MacViewPNGRenderer.render(view.environmentObject(model).background(Color(red: 0.09, green: 0.095, blue: 0.1)), size: CGSize(width: width, height: 620), displayScale: 2, settleTime: 0.03)
                let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/render-artifacts/climate-detail-\(name)-\(width)x620.png")
                try rendered.pngData.write(to: url)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered.pngData))
                XCTAssertEqual(bitmap.pixelsWide, width * 2)
                XCTAssertEqual(bitmap.pixelsHigh, 1240)
                XCTAssertGreaterThan(rendered.nonBackgroundSampleCount, 100)
                XCTAssertEqual(Array(rendered.pngData.prefix(8)), [137,80,78,71,13,10,26,10])
            }
        }
    }

    func testDialKeyframesAndColdRenderPerformance() throws {
        try FileManager.default.createDirectory(atPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts", withIntermediateDirectories: true)
        let entity = try ClimateFixtures.entity()
        var images: [Data] = []
        for progress in [0.0, 0.5, 1.0] {
            let value = 19 + progress * 9
            let png = try MacViewPNGRenderer.render(ClimateControlDrawing(entity: entity, mainControl: .temperature, values: [.value: value]), size: CGSize(width: 320, height: 320), displayScale: 2)
            images.append(png.pngData)
            try png.pngData.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/render-artifacts/climate-dial-progress-\(progress).png"))
        }
        XCTAssertNotEqual(images[0], images[1]); XCTAssertNotEqual(images[1], images[2])
        let final = try MacViewPNGRenderer.render(ClimateControlDrawing(entity: entity, mainControl: .temperature, values: [.value: 28]), size: CGSize(width: 320, height: 320), displayScale: 2)
        XCTAssertEqual(images[2], final.pngData)
        let full = try ClimateFixtures.entity("complete")
        let controller = ClimateServiceController()
        controller.install(entity: full) { _, _ in true }
        controller.selectMain(.humidity)
        let humidityModel = DashboardViewModel(initialStates: [full.entityID: full.state])
        let humidity = try MacViewPNGRenderer.render(ClimateControlDial(entity: full, controller: controller).environmentObject(humidityModel), size: CGSize(width: 320, height: 320), displayScale: 2)
        try humidity.pngData.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/render-artifacts/climate-detail-complete-humidity-320x320.png"))
        controller.close()
        var consumed = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let model = DashboardViewModel(initialStates: [entity.entityID: entity.state], homeAssistantConfig: HAConfig(unitSystem: HAUnitSystem(temperature: "°C")))
            let image = try? MacViewPNGRenderer.render(EntityDetailSheet(entityID: entity.entityID).environmentObject(model), size: CGSize(width: 520, height: 620), displayScale: 2)
            consumed += image?.pngData.count ?? 0
        }
        XCTAssertGreaterThan(consumed, 0)
    }

    func testAnimationVectorInterpolatesOnlyTargetsWithoutInventingMissingValues() throws {
        let startEntity = try ClimateFixtures.entity(overrides: ["current_temperature": .double(20)])
        let endEntity = try ClimateFixtures.entity(overrides: ["current_temperature": .double(26)])
        let start = ClimateCapabilityDrawing(entity: startEntity, mainControl: .temperature, values: [.value: 20])
        var midpoint = ClimateCapabilityDrawing(entity: endEntity, mainControl: .temperature, values: [.value: 26])
        var vector = midpoint.animatableData - start.animatableData
        vector.scale(by: 0.5)
        midpoint.animatableData = start.animatableData + vector
        XCTAssertEqual(midpoint.values[.value], 23)
        let directMidpoint = ClimateCapabilityDrawing(entity: endEntity, mainControl: .temperature, values: [.value: 23])
        XCTAssertEqual(try MacViewPNGRenderer.render(midpoint, size: CGSize(width: 320, height: 320), displayScale: 2).pngData,
                       try MacViewPNGRenderer.render(directMidpoint, size: CGSize(width: 320, height: 320), displayScale: 2).pngData)
        XCTAssertNil(midpoint.values[.humidity])
        var single = ClimateDialDrawing(targetProgress: 0.8, currentProgress: 0.7, isCooling: true, hasTemperatureDifference: true)
        single.animatableData = 0.5
        XCTAssertEqual(single.currentProgress, 0.7)
        let expected = ClimateDialDrawing(targetProgress: 0.5, currentProgress: 0.7, isCooling: true, hasTemperatureDifference: true)
        XCTAssertEqual(try MacViewPNGRenderer.render(single, size: CGSize(width: 320, height: 320), displayScale: 2).pngData,
                       try MacViewPNGRenderer.render(expected, size: CGSize(width: 320, height: 320), displayScale: 2).pngData)
    }
}
