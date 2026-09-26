import AppKit
import NativeHACore
import SwiftUI
import XCTest
@testable import NativeHAMac

@MainActor
final class ClimateDashboardEntryTests: XCTestCase {
    func testNormalAndInjectedHomeRowsMountProductionClimatePanel() async throws {
        for injected in [false, true] {
            let fixture = try ClimateFixtures.entity()
            let state = HAState(entityId: "climate.room_ac", state: fixture.state.state, attributes: fixture.state.attributes)
            let card = LovelaceCard(type: "entities", title: injected ? "AC Unit Controller" : "Climate", entities: injected ? [LovelaceEntityRef(entity: "fan.ac_unit_controller")] : [LovelaceEntityRef(entity: state.entityId, name: "Room AC")])
            let model = DashboardViewModel(initialStates: [state.entityId: state], initialViews: [LovelaceView(title: "Home", path: "default_view", cards: [card])], homeAssistantConfig: HAConfig(unitSystem: HAUnitSystem(temperature: "°C")))
            let recorder = ClimateRecorder()
            model.installServiceCallerForTesting { _, service, data in await recorder.record(service, data: data) }
            _ = NSApplication.shared
            let host = NSHostingView(rootView: DashboardView(model: model, startsOnAppear: false))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1900, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            defer { model.closeDetails(); window.orderOut(nil); window.close() }
            host.frame = CGRect(x: 0, y: 0, width: 1900, height: 800)
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                return self.descendants(host).contains { ($0 as? EntityPrimaryActionNSButton)?.accessibilityLabel() == "Room AC" }
            }
            let row = try XCTUnwrap(descendants(host).compactMap { $0 as? EntityPrimaryActionNSButton }.first { $0.accessibilityLabel() == "Room AC" })
            XCTAssertTrue(row.isEnabled)
            XCTAssertTrue(host.hitTest(row.convert(CGPoint(x: row.bounds.midX, y: row.bounds.midY), to: host.superview)) === row)
            row.performClick(nil)
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                return self.descendants(host).contains { $0 is ClimateDialNSView }
            }
            XCTAssertEqual(model.selectedEntityID, state.entityId)
            XCTAssertEqual(descendants(host).filter { $0 is ClimateDialNSView }.count, 1)
            let menus = descendants(host).compactMap { $0 as? ClimateModeNSButton }
            XCTAssertEqual(Set(menus.map(\.titleLabel)), ["Mode", "Preset"])
            for menu in menus {
                XCTAssertTrue(host.hitTest(menu.convert(CGPoint(x: menu.bounds.midX, y: menu.bounds.midY), to: host.superview)) === menu)
            }
            let count = await recorder.count
            XCTAssertEqual(count, 0, "Opening alone must not call climate services")
            let preset = try XCTUnwrap(menus.first { $0.titleLabel == "Preset" })
            let item = NSMenuItem()
            item.representedObject = "sleep"
            preset.perform(NSSelectorFromString("selectOption:"), with: item)
            for _ in 0..<1000 { if await recorder.count == 1 { break }; await Task.yield() }
            let selectionCount = await recorder.count
            XCTAssertEqual(selectionCount, 1)
            XCTAssertEqual(preset.selected, "none", "Menus keep the authoritative selection")
            model.closeDetails()
            try await waitUntil { !self.descendants(host).contains { $0 is ClimateDialNSView } }
            XCTAssertFalse(descendants(host).contains { $0 is ClimateDialNSView })
            await model.stop()
        }
    }

    private func waitUntil(_ ready: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !ready(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(ready(), "Mounted UI did not reach the expected state within two seconds")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
}
