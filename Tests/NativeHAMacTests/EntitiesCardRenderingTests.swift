import AppKit
import SwiftUI
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class EntitiesCardRenderingTests: XCTestCase {
    func testMixedEntityStatesRenderNonblankAtWideAndNarrowTwoX() throws {
        let model = renderingModel()
        let card = try renderingCard()

        for width in [496.0, 320.0] {
            let size = CGSize(width: width, height: 520)
            let rendered = try MacViewPNGRenderer.render(
                EntitiesCard(card: card)
                    .environmentObject(model)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(Color(red: 0.055, green: 0.06, blue: 0.06)),
                size: size,
                displayScale: 2
            )

            XCTAssertTrue(rendered.pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
            XCTAssertGreaterThan(rendered.pngData.count, 8_000)
            XCTAssertGreaterThan(rendered.nonBackgroundSampleCount, 100)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: rendered.pngData))
            XCTAssertEqual(rep.pixelsWide, Int(width * 2))
            XCTAssertEqual(rep.pixelsHigh, 1_040)
            try persist(rendered.pngData, name: "module-06-entities-\(Int(width)).png")
        }
    }

    func testPresentationAccessibilityValuesCoverMissingSecondaryWarningsAndPower() throws {
        let model = renderingModel()
        let card = try renderingCard()
        let rows = try XCTUnwrap(card.rows)
        let presentations = rows.map {
            model.entityRowPresentation($0, cardStateColor: card.source.stateColor)
        }

        XCTAssertEqual(presentations.map(\.name), [
            "Long temperature name intended to truncate without changing identity",
            "Unknown sensor",
            "Unavailable switch",
            "Available switch",
            "Missing entity",
            "Duplicate one",
            "Duplicate two",
            "Unsupported icon",
        ])
        XCTAssertEqual(presentations[0].secondary?.accessibilityLabel, "Entity ID")
        XCTAssertEqual(presentations[0].secondary?.accessibilityValue, "sensor.temperature")
        XCTAssertEqual(presentations[1].stateText, "Unknown")
        XCTAssertEqual(presentations[2].stateText, "Unavailable")
        XCTAssertTrue(presentations[3].showsPowerControl)
        XCTAssertEqual(presentations[4].stateText, "Missing entity")
        XCTAssertEqual(presentations[4].primaryAction, .none)
        XCTAssertEqual(presentations[5].entityID, presentations[6].entityID)
        XCTAssertNotEqual(rows[5].identity, rows[6].identity)
        XCTAssertTrue(presentations[7].warningText?.contains("mdi:not-in-bounded-table") == true)
        XCTAssertFalse(presentations[7].icon.semanticLabel.isEmpty)
    }

    func testHeaderAndRowControlsAreSiblingNativeAccessibilityElements() throws {
        let model = renderingModel()
        model.installServiceCallerForTesting { _, _, _ in }
        let card = try renderingCard()
        let size = CGSize(width: 496, height: 520)
        let hosting = NSHostingView(
            rootView: EntitiesCard(card: card)
                .environmentObject(model)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        let previousActivationPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
        defer {
            window.orderOut(nil)
            window.close()
            NSApplication.shared.setActivationPolicy(previousActivationPolicy)
        }
        for _ in 0..<3 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }

        let switches = nativeControls(in: hosting, as: EntityPowerNSSwitch.self)
        let primaryTargets = nativeControls(in: hosting, as: EntityPrimaryActionNSButton.self)
        XCTAssertEqual(
            Set(switches.compactMap { $0.accessibilityLabel() }),
            ["Entities power", "Unavailable switch power", "Available switch power"]
        )
        XCTAssertFalse(try XCTUnwrap(
            switches.first { $0.accessibilityLabel() == "Unavailable switch power" }
        ).isEnabled)
        XCTAssertTrue(try XCTUnwrap(
            switches.first { $0.accessibilityLabel() == "Entities power" }
        ).isEnabled)
        XCTAssertTrue(try XCTUnwrap(
            switches.first { $0.accessibilityLabel() == "Available switch power" }
        ).isEnabled)
        XCTAssertTrue(primaryTargets.contains { $0.accessibilityLabel() == "Unknown sensor" })
        XCTAssertTrue(primaryTargets.contains { $0.accessibilityLabel() == "Unavailable switch" })
        XCTAssertFalse(primaryTargets.contains { $0.accessibilityLabel() == "Missing entity" })
        XCTAssertFalse(primaryTargets.contains { $0.accessibilityLabel() == "Unsupported icon" })
        XCTAssertGreaterThanOrEqual(primaryTargets.filter(\.isEnabled).count, 4)
        XCTAssertTrue(switches.allSatisfy { $0.superview != nil })
        XCTAssertTrue(primaryTargets.allSatisfy { $0.superview != nil })
        XCTAssertTrue(primaryTargets.allSatisfy { $0.bounds.width > 20 && $0.bounds.height > 10 })

        let availablePrimary = try XCTUnwrap(
            primaryTargets.first { $0.accessibilityLabel() == "Available switch" }
        )
        let headerSwitch = try XCTUnwrap(
            switches.first { $0.accessibilityLabel() == "Entities power" }
        )
        let availableSwitch = try XCTUnwrap(
            switches.first { $0.accessibilityLabel() == "Available switch power" }
        )
        window.recalculateKeyViewLoop()
        nativeControls(in: hosting, as: EntityFocusOrderNSView.self).forEach {
            $0.configureKeyViewOrder()
        }
        XCTAssertEqual(
            headerSwitch.nextKeyView?.accessibilityLabel(),
            "Long temperature name intended to truncate without changing identity"
        )
        XCTAssertTrue(window.makeFirstResponder(availablePrimary))
        XCTAssertTrue(window.firstResponder === availablePrimary)
        XCTAssertTrue(
            availablePrimary.nextKeyView === availableSwitch,
            "The row primary target must precede its sibling power control in keyboard order"
        )
        availablePrimary.keyDown(with: try keyEvent(character: "\r", keyCode: 36, window: window))
        XCTAssertEqual(model.selectedEntityID, "switch.available")
        model.closeDetails()

        XCTAssertTrue(window.makeFirstResponder(availableSwitch))
        XCTAssertTrue(window.firstResponder === availableSwitch)
        availableSwitch.keyDown(with: try keyEvent(character: " ", keyCode: 49, window: window))
        XCTAssertEqual(model.states["switch.available"]?.state, "on")
    }

    private func renderingModel() -> DashboardViewModel {
        DashboardViewModel(
            initialStates: [
                "sensor.temperature": HAState(
                    entityId: "sensor.temperature",
                    state: "22.40",
                    attributes: [
                        "friendly_name": .string("Temperature"),
                        "device_class": .string("temperature"),
                        "unit_of_measurement": .string("°C"),
                    ]
                ),
                "sensor.unknown": HAState(
                    entityId: "sensor.unknown",
                    state: "unknown",
                    attributes: ["friendly_name": .string("Unknown sensor")]
                ),
                "switch.unavailable": HAState(
                    entityId: "switch.unavailable",
                    state: "unavailable",
                    attributes: ["friendly_name": .string("Unavailable switch")]
                ),
                "switch.available": HAState(
                    entityId: "switch.available",
                    state: "off",
                    attributes: ["friendly_name": .string("Available switch")]
                ),
                "sensor.duplicate": HAState(entityId: "sensor.duplicate", state: "7"),
                "sensor.icon": HAState(
                    entityId: "sensor.icon",
                    state: "55",
                    attributes: ["friendly_name": .string("Unsupported icon")]
                ),
            ],
            homeAssistantConfig: HAConfig(timeZone: "Asia/Shanghai"),
            frontendLocalePreferences: HAFrontendLocalePreferences(
                language: "en_US_POSIX",
                numberFormat: "none",
                timeFormat: "24",
                dateFormat: "system",
                firstWeekday: "monday",
                timeZone: "server"
            ),
            entityDisplayPrecisions: ["sensor.temperature": 2]
        )
    }

    private func renderingCard() throws -> LovelacePresentationCard {
        let config = try LovelaceConfig(rawValue: .object([
            "views": .array([.object([
                "title": .string("Home"),
                "path": .string("default_view"),
                "cards": .array([.object([
                    "type": .string("entities"),
                    "title": .string("Mixed entities"),
                    "show_header_toggle": .bool(true),
                    "state_color": .bool(true),
                    "entities": .array([
                        .object([
                            "entity": .string("sensor.temperature"),
                            "name": .string("Long temperature name intended to truncate without changing identity"),
                            "secondary_info": .string("entity-id"),
                        ]),
                        .string("sensor.unknown"),
                        .string("switch.unavailable"),
                        .string("switch.available"),
                        .object(["entity": .string("sensor.missing"), "name": .string("Missing entity")]),
                        .object(["entity": .string("sensor.duplicate"), "name": .string("Duplicate one")]),
                        .object(["entity": .string("sensor.duplicate"), "name": .string("Duplicate two")]),
                        .object([
                            "entity": .string("sensor.icon"),
                            "icon": .string("mdi:not-in-bounded-table"),
                            "tap_action": .object(["action": .string("none")]),
                        ]),
                    ]),
                ])]),
            ])]),
        ]))
        return LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        ).views[0].cards[0]
    }

    private func persist(_ data: Data, name: String) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NativeHA-Module06", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MODULE06_GUI artifact=\(url.path) bytes=\(data.count)")
    }

    private func nativeControls<Control: NSView>(
        in root: NSView,
        as type: Control.Type
    ) -> [Control] {
        var result: [Control] = []
        func collect(_ view: NSView) {
            if let control = view as? Control { result.append(control) }
            for subview in view.subviews { collect(subview) }
        }
        collect(root)
        return result
    }

    private func keyEvent(character: String, keyCode: UInt16, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
