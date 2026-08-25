import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class GUIRenderingAndPerformanceTests: XCTestCase {
    func testEntitiesCardCanRenderToPNG() throws {
        let model = DashboardViewModel()
        model.states = [
            "sensor.room_temperature": HAState(
                entityId: "sensor.room_temperature",
                state: "22.4",
                attributes: [
                    "friendly_name": .string("Room temperature"),
                    "unit_of_measurement": .string("°C"),
                ]
            ),
            "switch.desk_lamp": HAState(
                entityId: "switch.desk_lamp",
                state: "on",
                attributes: ["friendly_name": .string("Desk lamp")]
            ),
        ]
        let card = LovelaceCard(
            type: "entities",
            title: "Office",
            entities: [
                LovelaceEntityRef(entity: "sensor.room_temperature"),
                LovelaceEntityRef(entity: "switch.desk_lamp"),
            ]
        )

        let rendered = try MacViewPNGRenderer.render(
            EntitiesCard(card: card)
                .environmentObject(model)
                .frame(width: 496, height: 210, alignment: .top)
                .background(Color(red: 0.055, green: 0.06, blue: 0.06)),
            size: CGSize(width: 496, height: 210),
            displayScale: 2
        )

        try assertUsablePNG(rendered, minimumBytes: 8_000, minimumChangedSamples: 100)
        try persistAndAttach(rendered.pngData, name: "entities-card.png")
        try ApprovedVisualReference.compareIfPresent(
            actualPNG: rendered.pngData,
            name: "entities-card.png"
        )
    }

    func testHistoryGraphViewCanRenderToPNG() throws {
        let input = performanceInput(pointCount: 720, entityID: "sensor.visual_graph")
        let rendered = try MacViewPNGRenderer.render(
            BitmapLineChart(
                unit: "µg/m³",
                inputs: [input],
                zoomScale: 1,
                panFraction: 1,
                hoverLocation: .constant(nil),
                onMagnify: { _, _, _ in },
                onPan: { _ in }
            )
            .frame(width: 496, height: 178),
            size: CGSize(width: 496, height: 178),
            displayScale: 2,
            settleTime: 0.25
        )

        try assertUsablePNG(rendered, minimumBytes: 8_000, minimumChangedSamples: 100)
        XCTAssertGreaterThan(
            rendered.blueSampleCount,
            20,
            "The settled view snapshot should contain the rendered blue data line, not only its loading state."
        )
        try persistAndAttach(rendered.pngData, name: "history-graph.png")
        try ApprovedVisualReference.compareIfPresent(
            actualPNG: rendered.pngData,
            name: "history-graph.png"
        )
    }

    func testGraphHoverOverlayCanBeHiddenWithoutChangingTheUnderlyingPlot() throws {
        let input = performanceInput(pointCount: 720, entityID: "sensor.hover_overlay")
        let size = CGSize(width: 496, height: 178)

        func render(hover: CGPoint?, showsHoverOverlay: Bool) throws -> RenderedPNG {
            try MacViewPNGRenderer.render(
                BitmapLineChart(
                    unit: "µg/m³",
                    inputs: [input],
                    zoomScale: 1,
                    panFraction: 1,
                    showsHoverOverlay: showsHoverOverlay,
                    hoverLocation: .constant(hover),
                    onMagnify: { _, _, _ in },
                    onPan: { _ in }
                )
                .frame(width: size.width, height: size.height),
                size: size,
                displayScale: 2,
                settleTime: 0.25
            )
        }

        let plotOnly = try render(hover: nil, showsHoverOverlay: false)
        let hiddenHover = try render(hover: CGPoint(x: 250, y: 80), showsHoverOverlay: false)
        let visibleHover = try render(hover: CGPoint(x: 250, y: 80), showsHoverOverlay: true)

        XCTAssertEqual(hiddenHover.pngData, plotOnly.pngData)
        XCTAssertNotEqual(visibleHover.pngData, plotOnly.pngData)
        XCTAssertGreaterThan(hiddenHover.blueSampleCount, 20)
    }

    func testGraphHoverOverlayRendersForNativeNumericHistory() throws {
        let input = numericPerformanceInput(
            pointCount: 720,
            entityID: "sensor.numeric_hover_overlay"
        )
        let size = CGSize(width: 496, height: 178)

        func render(hover: CGPoint?) throws -> RenderedPNG {
            try MacViewPNGRenderer.render(
                BitmapLineChart(
                    unit: "µg/m³",
                    inputs: [input],
                    zoomScale: 1,
                    panFraction: 1,
                    showsHoverOverlay: true,
                    hoverLocation: .constant(hover),
                    onMagnify: { _, _, _ in },
                    onPan: { _ in }
                )
                .frame(width: size.width, height: size.height),
                size: size,
                displayScale: 2,
                settleTime: 0.25
            )
        }

        let plotOnly = try render(hover: nil)
        let visibleHover = try render(hover: CGPoint(x: 250, y: 80))

        XCTAssertNotEqual(visibleHover.pngData, plotOnly.pngData)
        XCTAssertGreaterThan(visibleHover.blueSampleCount, 20)
    }

    func testClimateDialAnimationKeyframesRenderDistinctImages() throws {
        var frameData: [Data] = []

        for (index, progress) in [0.15, 0.50, 0.85].enumerated() {
            let rendered = try MacViewPNGRenderer.render(
                ClimateDialDrawing(
                    targetProgress: progress,
                    currentProgress: 0.35,
                    isCooling: true,
                    hasTemperatureDifference: true
                )
                .frame(width: 320, height: 320)
                .background(Color(red: 0.055, green: 0.06, blue: 0.06)),
                size: CGSize(width: 320, height: 320),
                displayScale: 2
            )

            try assertUsablePNG(rendered, minimumBytes: 5_000, minimumChangedSamples: 100)
            XCTAssertGreaterThan(rendered.blueSampleCount, 20)
            frameData.append(rendered.pngData)

            let name = "climate-dial-frame-\(index).png"
            try persistAndAttach(rendered.pngData, name: name)
            try ApprovedVisualReference.compareIfPresent(actualPNG: rendered.pngData, name: name)
        }

        XCTAssertNotEqual(frameData[0], frameData[1])
        XCTAssertNotEqual(frameData[1], frameData[2])
        XCTAssertNotEqual(frameData[0], frameData[2])
    }

    func testWarmGraphInteractionRenderCanBeMeasuredWithXCTMetrics() throws {
        let input = performanceInput(pointCount: 20_000, entityID: "sensor.performance_graph")
        let size = CGSize(width: 496, height: 178)

        _ = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [input],
            unit: "µg/m³",
            size: size,
            scale: 2,
            zoomScale: 4,
            panFraction: 0.6
        ))

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            _ = GraphBitmapRenderer.render(
                inputs: [input],
                unit: "µg/m³",
                size: size,
                scale: 2,
                zoomScale: 4,
                panFraction: 0.6
            )
        }
    }

    func testHistoryStreamNumericAndTimelineLoadingReplayIncrementalArtifacts() throws {
        let size = CGSize(width: 496, height: 260)
        for run in 1...3 {
            let (loading, oracle) = try historyLoadingVisual(size: size)
            let prefix = String(format: "history-stream-run-%02d", run)
            try persistAndAttach(loading.pngData, name: "\(prefix)-loading.png")

            let numericReplay = try historyStreamVisual(
                input: historyStreamNumericInput(middleState: "20"),
                unit: "°C",
                size: size,
                oracle: oracle
            )
            let numericUpdate = try historyStreamVisual(
                input: historyStreamNumericInput(middleState: "28"),
                unit: "°C",
                size: size,
                oracle: oracle
            )
            try persistAndAttach(numericReplay.pngData, name: "\(prefix)-numeric-replay.png")
            try persistAndAttach(numericUpdate.pngData, name: "\(prefix)-numeric-update.png")
            XCTAssertNotEqual(numericReplay.pngData, numericUpdate.pngData)

            let timelineReplay = try historyStreamVisual(
                input: historyStreamTimelineInput(lastState: "unknown"),
                unit: HAHistoryGraphClassifier.stateUnit,
                size: size,
                oracle: oracle
            )
            let timelineUpdate = try historyStreamVisual(
                input: historyStreamTimelineInput(lastState: "off"),
                unit: HAHistoryGraphClassifier.stateUnit,
                size: size,
                oracle: oracle
            )
            try persistAndAttach(timelineReplay.pngData, name: "\(prefix)-timeline-replay.png")
            try persistAndAttach(timelineUpdate.pngData, name: "\(prefix)-timeline-update.png")
            XCTAssertNotEqual(timelineReplay.pngData, timelineUpdate.pngData)
        }
    }

    func testHistoryVisualLabelOracleRejectsPopulatedGraphsWithBlankLabelBands() throws {
        let size = CGSize(width: 496, height: 260)
        let (_, oracle) = try historyLoadingVisual(size: size)
        let numeric = try historyStreamVisual(
            input: historyStreamNumericInput(middleState: "20"),
            unit: "°C",
            size: size,
            oracle: oracle
        )
        let timeline = try historyStreamVisual(
            input: historyStreamTimelineInput(lastState: "unknown"),
            unit: HAHistoryGraphClassifier.stateUnit,
            size: size,
            oracle: oracle
        )

        let numericBitmap = try XCTUnwrap(NSBitmapImageRep(data: numeric.pngData))
        let blankRange = try oracle.erasingRangeLabel(in: numericBitmap)
        XCTAssertGreaterThan(changedSamples(in: blankRange, x: 80..<960, y: 100..<420), 100)
        XCTAssertTrue(oracle.hasFiveAxisLabels(in: blankRange))
        XCTAssertFalse(
            oracle.isSettled(blankRange, requiresAxesAndData: true),
            "A populated grid/data bitmap with a blank 1h band must not settle."
        )

        let timelineBitmap = try XCTUnwrap(NSBitmapImageRep(data: timeline.pngData))
        let blankAxis = try oracle.erasingAxisLabels(in: timelineBitmap)
        XCTAssertGreaterThan(changedSamples(in: blankAxis, x: 80..<960, y: 100..<420), 100)
        XCTAssertTrue(oracle.hasOneHourRangeLabel(in: blankAxis))
        XCTAssertFalse(
            oracle.isSettled(blankAxis, requiresAxesAndData: true),
            "Populated timeline data with a blank five-label bottom band must not settle."
        )
    }

    func testLovelaceFallbackAndNestedLayoutArtifacts() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtureData = try Data(contentsOf: testsDirectory
            .appendingPathComponent("Fixtures/Lovelace/representative-dashboard.json"))
        let config = try JSONDecoder().decode(LovelaceConfig.self, from: fixtureData)
        let fixedNow = Date(timeIntervalSince1970: 1_787_486_400)
        let fixedPreferences = HAFrontendLocalePreferences(
            language: "en_US_POSIX",
            numberFormat: "none",
            timeFormat: "24",
            dateFormat: "language",
            firstWeekday: "monday",
            timeZone: "server"
        )
        let fixedAxisFormatting = GraphTooltipFormattingResolver.metadata(
            entityID: "sensor.history",
            state: nil,
            registryDisplayPrecision: nil,
            preferences: fixedPreferences,
            serverTimeZone: "UTC",
            policy: AppConfig.graphTooltipFormattingPolicy
        )
        let model = DashboardViewModel(
            initialViews: config.views,
            homeAssistantConfig: HAConfig(timeZone: "UTC"),
            frontendLocalePreferences: fixedPreferences,
            historyNow: { fixedNow },
            graphAxisTimeFormattingOverride: fixedAxisFormatting
        )
        model.states = [
            "sensor.string_row": HAState(entityId: "sensor.string_row", state: "21.0", attributes: [:]),
            "sensor.object_row": HAState(entityId: "sensor.object_row", state: "42", attributes: [:]),
            "sensor.history": HAState(entityId: "sensor.history", state: "22.0", attributes: [
                "unit_of_measurement": .string("°C"),
            ]),
            "weather.home": HAState(entityId: "weather.home", state: "sunny", attributes: [
                "temperature": .double(23),
                "temperature_unit": .string("°C"),
                "humidity": .double(45),
            ]),
        ]
        let unknown = LovelacePresentationCard.standalone(LovelaceCard(
            type: "custom:unknown-fixture",
            title: "Unknown fixture"
        ))
        let unsupportedRow = LovelacePresentationCard.standalone(LovelaceCard(
            type: "entities",
            title: "Rows",
            entities: [
                LovelaceEntityRef(entity: "sensor.valid", name: "Valid row"),
                LovelaceEntityRef(entity: nil, type: "divider"),
            ]
        ))
        let nestedView = try XCTUnwrap(model.presentationDashboard.views.first {
            $0.resolved.source.path == "home_3h"
        })
        let nested = try XCTUnwrap(nestedView.cards.first)
        let history = try XCTUnwrap(nested.cards?.first { $0.type == "history-graph" })
        let now = fixedNow.timeIntervalSince1970
        model.histories[model.historyKey(for: history)] = [HAHistorySeries(
            entityID: "sensor.history",
            points: (0..<24).map { index in
                HAHistoryPoint(
                    entityId: "sensor.history",
                    state: String(20 + Double(index) / 10),
                    attributes: nil,
                    lastChangedSeconds: now - Double(23 - index) * 300,
                    lastUpdatedSeconds: now - Double(23 - index) * 300
                )
            },
            contentRevision: 1
        )]

        try renderLovelaceArtifact(
            CardRenderer(card: unknown).environmentObject(model),
            size: CGSize(width: 496, height: 150),
            name: "lovelace-unknown-card.png"
        )
        try renderLovelaceArtifact(
            CardRenderer(card: unsupportedRow).environmentObject(model),
            size: CGSize(width: 496, height: 210),
            name: "lovelace-unsupported-row.png"
        )
        try renderLovelaceArtifact(
            CardRenderer(card: nested)
                .environmentObject(model)
                .frame(width: 496 / 0.72, alignment: .top)
                .scaleEffect(0.72, anchor: .topLeading)
                .frame(width: 496, height: 640, alignment: .topLeading)
                .clipped(),
            size: CGSize(width: 496, height: 640),
            settleTime: 0.3,
            name: "lovelace-nested-496.png"
        )
        try renderLovelaceArtifact(
            CardRenderer(card: nested)
                .environmentObject(model)
                .frame(width: 360 / 0.72, alignment: .top)
                .scaleEffect(0.72, anchor: .topLeading)
                .frame(width: 360, height: 640, alignment: .topLeading)
                .clipped(),
            size: CGSize(width: 360, height: 640),
            settleTime: 0.3,
            name: "lovelace-nested-360.png"
        )

        let first = try MacViewPNGRenderer.render(
            CardRenderer(card: unknown).environmentObject(model).frame(width: 496, height: 150),
            size: CGSize(width: 496, height: 150),
            displayScale: 2
        )
        let second = try MacViewPNGRenderer.render(
            CardRenderer(card: unknown).environmentObject(model).frame(width: 496, height: 150),
            size: CGSize(width: 496, height: 150),
            displayScale: 2
        )
        XCTAssertEqual(first.pngData, second.pngData)
        try persistAndAttach(first.pngData, name: "lovelace-identical-refresh-1.png")
        try persistAndAttach(second.pngData, name: "lovelace-identical-refresh-2.png")
    }

    func testMountedBitmapChartsAreInvalidatedDuringDashboardReplacement() throws {
        func config(title: String) -> LovelaceConfig {
            LovelaceConfig(views: [
                LovelaceView(title: "Home", path: "default_view", cards: [
                    LovelaceCard(
                        type: "history-graph",
                        title: title,
                        entities: [LovelaceEntityRef(entity: "sensor.mounted")]
                    ),
                ]),
            ])
        }

        let initial = config(title: "Mounted")
        let model = DashboardViewModel(initialViews: initial.views)
        let ownerID = try XCTUnwrap(model.homeCards.first?.nativeID)
        let firstLifecycle = GraphChartMountedLifecycle()
        let secondLifecycle = GraphChartMountedLifecycle()
        let input = performanceInput(pointCount: 48, entityID: "sensor.mounted")
        var scheduledReplacement = false
        var replacementApplied = false

        _ = try MacViewPNGRenderer.render(
            VStack {
                BitmapLineChart(
                    unit: "°C",
                    inputs: [input],
                    mountOwnerID: ownerID,
                    mountRegistry: model.graphChartMountRegistry,
                    mountedLifecycle: firstLifecycle,
                    zoomScale: 1,
                    panFraction: 1,
                    hoverLocation: .constant(nil),
                    onMagnify: { _, _, _ in },
                    onPan: { _ in }
                )
                BitmapLineChart(
                    unit: "%",
                    inputs: [input],
                    mountOwnerID: ownerID,
                    mountRegistry: model.graphChartMountRegistry,
                    mountedLifecycle: secondLifecycle,
                    zoomScale: 1,
                    panFraction: 1,
                    hoverLocation: .constant(nil),
                    onMagnify: { _, _, _ in },
                    onPan: { _ in }
                )
            },
            size: CGSize(width: 496, height: 356),
            displayScale: 2,
            readiness: {
                if model.graphChartMountRegistry.liveMountCount(ownerID: ownerID) == 2,
                   !scheduledReplacement
                {
                    scheduledReplacement = true
                    Task { @MainActor in
                        await model.applyLovelaceConfigForTesting(config(title: "Replacement"))
                        replacementApplied = true
                    }
                }
                return replacementApplied && model.graphChartMountRegistry.liveMountCount() == 0
            }
        )

        XCTAssertTrue(replacementApplied)
        XCTAssertTrue(firstLifecycle.isInvalidated)
        XCTAssertTrue(secondLifecycle.isInvalidated)
        XCTAssertEqual(model.graphChartMountRegistry.liveMountCount(), 0)
        XCTAssertEqual(firstLifecycle.coordinator.pendingWorkCount, 0)
        XCTAssertEqual(secondLifecycle.coordinator.pendingWorkCount, 0)
    }

    func testModule12SidebarAndActiveViewArtifacts() async throws {
        let config = try module12VisualConfig()
        let model = DashboardViewModel(
            initialStates: [
                "sensor.home": HAState(
                    entityId: "sensor.home",
                    state: "21.5",
                    attributes: ["friendly_name": .string("Home temperature"), "unit_of_measurement": .string("°C")]
                ),
                "sensor.genuine": HAState(
                    entityId: "sensor.genuine",
                    state: "42",
                    attributes: ["friendly_name": .string("Genuine view sensor")]
                ),
                "sensor.panel": HAState(
                    entityId: "sensor.panel",
                    state: "on",
                    attributes: ["friendly_name": .string("Panel sensor")]
                ),
            ],
            initialViews: config.views,
            navigationPreferenceStore: GUIMemoryNavigationPreferenceStore()
        )
        model.status = "Live"

        XCTAssertEqual(model.navigationItems.map(\.title), [
            "Home",
            "A Deliberately Long Genuine Lovelace View Title",
            "Panel View",
            "Empty View",
        ])
        XCTAssertFalse(model.navigationItems.contains { ["3h maintenance", "12h maintenance"].contains($0.title) })

        let sidebar = try MacViewPNGRenderer.render(
            SidebarView()
                .environmentObject(model)
                .frame(width: AppConfig.sidebarWidth, height: 700)
                .background(Color(red: 0.105, green: 0.11, blue: 0.108)),
            size: CGSize(width: AppConfig.sidebarWidth, height: 700),
            displayScale: 2
        )
        try assertUsablePNG(sidebar, minimumBytes: 7_000, minimumChangedSamples: 80)
        try assertDimensions(
            sidebar.pngData,
            width: Int(AppConfig.sidebarWidth * 2),
            height: 1_400
        )
        try persistAndAttach(sidebar.pngData, name: "sidebar-selected-home.png")
        try persistAndAttach(sidebar.pngData, name: "sidebar-unselected-long-title.png")

        let longView = try XCTUnwrap(model.presentationDashboard.views.first {
            $0.resolved.source.path == "genuine"
        })
        let focusedSidebar = try MacViewPNGRenderer.render(
            SidebarView(focusedIdentityForRendering: longView.id)
                .environmentObject(model)
                .frame(width: AppConfig.sidebarWidth, height: 700)
                .background(Color(red: 0.105, green: 0.11, blue: 0.108)),
            size: CGSize(width: AppConfig.sidebarWidth, height: 700),
            displayScale: 2
        )
        try assertUsablePNG(focusedSidebar, minimumBytes: 7_000, minimumChangedSamples: 80)
        XCTAssertNotEqual(sidebar.pngData, focusedSidebar.pngData)
        try persistAndAttach(focusedSidebar.pngData, name: "sidebar-focus.png")

        await model.selectViewForTesting(longView.id)

        let genuine = try renderModule12Dashboard(model, size: CGSize(width: 1_792, height: 1_000))
        try persistAndAttach(genuine.pngData, name: "dashboard-genuine-view.png")
        let narrow = try renderModule12Dashboard(model, size: CGSize(width: 900, height: 700))
        try persistAndAttach(narrow.pngData, name: "dashboard-narrow.png")

        let home = try XCTUnwrap(model.presentationDashboard.views.first {
            $0.resolved.source.path == "default_view"
        })
        await model.selectViewForTesting(home.id)
        let wide = try renderModule12Dashboard(model, size: CGSize(width: 1_792, height: 1_000))
        try persistAndAttach(wide.pngData, name: "dashboard-three-column.png")

        let panel = try XCTUnwrap(model.presentationDashboard.views.first {
            $0.resolved.source.path == "panel"
        })
        await model.selectViewForTesting(panel.id)
        let panelImage = try renderModule12Dashboard(model, size: CGSize(width: 1_792, height: 1_000))
        try persistAndAttach(panelImage.pngData, name: "dashboard-panel-view.png")

        let empty = try XCTUnwrap(model.presentationDashboard.views.first {
            $0.resolved.source.path == "empty"
        })
        await model.selectViewForTesting(empty.id)
        let emptyImage = try renderModule12Dashboard(model, size: CGSize(width: 900, height: 700))
        try persistAndAttach(emptyImage.pngData, name: "dashboard-empty-view.png")

        let loadingModel = DashboardViewModel(
            navigationPreferenceStore: GUIMemoryNavigationPreferenceStore()
        )
        loadingModel.status = "Loading dashboard"
        let loading = try renderModule12Dashboard(loadingModel, size: CGSize(width: 900, height: 700))
        try persistAndAttach(loading.pngData, name: "dashboard-loading.png")

        let noViewsModel = DashboardViewModel(
            navigationPreferenceStore: GUIMemoryNavigationPreferenceStore()
        )
        await noViewsModel.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        noViewsModel.status = "Live"
        let noViews = try renderModule12Dashboard(noViewsModel, size: CGSize(width: 900, height: 700))
        try persistAndAttach(noViews.pngData, name: "dashboard-no-views.png")

        let allIneligible = try LovelaceConfig(rawValue: .object([
            "views": .array([
                .object([
                    "title": .string("Maintenance"),
                    "path": .string("home_3h"),
                    "cards": .array([]),
                ]),
                .object([
                    "title": .string("Hidden"),
                    "path": .string("hidden"),
                    "visible": .bool(false),
                    "cards": .array([]),
                ]),
            ]),
        ]))
        let ineligibleModel = DashboardViewModel(
            navigationPreferenceStore: GUIMemoryNavigationPreferenceStore()
        )
        await ineligibleModel.applyLovelaceConfigForTesting(allIneligible)
        ineligibleModel.status = "Live"
        let ineligible = try renderModule12Dashboard(ineligibleModel, size: CGSize(width: 900, height: 700))
        try persistAndAttach(ineligible.pngData, name: "dashboard-all-ineligible.png")

        XCTAssertNotEqual(genuine.pngData, wide.pngData)
        XCTAssertNotEqual(panelImage.pngData, wide.pngData)
        XCTAssertNotEqual(emptyImage.pngData, loading.pngData)
        XCTAssertNotEqual(noViews.pngData, loading.pngData)
        XCTAssertEqual(
            noViews.pngData,
            ineligible.pngData,
            "Zero raw views and all-ineligible views share the same controlled loaded-empty presentation"
        )
    }

    func testModule12SidebarHostedWindowAccessibilityAndKeyboardTraversal() async throws {
        let model = DashboardViewModel(
            initialViews: try module12VisualConfig().views,
            navigationPreferenceStore: GUIMemoryNavigationPreferenceStore()
        )
        let secondNavigationIdentity = try XCTUnwrap(model.navigationItems.dropFirst().first?.identity)
        var focused: [LovelaceResolvedIdentity] = []
        let hostingView = NSHostingView(
            rootView: SidebarView(focusObserver: { identity in
                if let identity = identity { focused.append(identity) }
            })
            .environmentObject(model)
            .frame(width: AppConfig.sidebarWidth, height: 700)
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: AppConfig.sidebarWidth, height: 700)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
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

        for _ in 0..<4 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }
        XCTAssertTrue(window.isVisible)
        XCTAssertNotEqual(window.windowNumber, 0)
        window.recalculateKeyViewLoop()
        let buttons = sidebarAccessibilityButtons(in: hostingView)
        XCTAssertEqual(buttons.count, 4, "Every primary row must expose one concrete AppKit accessibility button")
        XCTAssertEqual(buttons.compactMap { $0.accessibilityLabel() }, [
            "Home",
            "A Deliberately Long Genuine Lovelace View Title",
            "Panel View",
            "Empty View",
        ])
        XCTAssertTrue(buttons.allSatisfy { $0.isAccessibilityElement() })
        XCTAssertTrue(buttons.allSatisfy { $0.accessibilityRole() == .button })
        XCTAssertTrue(buttons.allSatisfy { NSAccessibility.unignoredAncestor(of: $0) != nil })
        XCTAssertTrue(buttons.allSatisfy { $0.bounds.width > 200 && $0.bounds.height >= 38 })
        XCTAssertEqual(buttons.map { $0.isAccessibilitySelected() }, [true, false, false, false])

        XCTAssertTrue(window.makeFirstResponder(buttons[0]))
        let tab = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))
        buttons[0].keyDown(with: tab)
        XCTAssertTrue(window.firstResponder === buttons[1])

        let space = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        buttons[1].keyDown(with: space)
        try await waitForGUICondition {
            await MainActor.run {
                model.navigationItems.first(where: \.isSelected)?.title ==
                    "A Deliberately Long Genuine Lovelace View Title"
            }
        }
        for _ in 0..<2 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            hostingView.layoutSubtreeIfNeeded()
        }
        let updatedButtons = sidebarAccessibilityButtons(in: hostingView)
        XCTAssertEqual(updatedButtons.map { $0.isAccessibilitySelected() }, [false, true, false, false])
        XCTAssertEqual(
            focused.filter { $0 == secondNavigationIdentity }.count,
            1,
            "Tab traversal must move native focus to the second exact view identity"
        )
        print(
            "MODULE12_AX buttons=\(updatedButtons.count) labels=\(updatedButtons.compactMap { $0.accessibilityLabel() }.joined(separator: "|")) selected=\(updatedButtons.map { $0.isAccessibilitySelected() }) tab_focus=second activation=second"
        )
    }

    func testModule12FiveHundredCardNavigationPreparationPerformance() throws {
        let cards = (0..<50).map { index in
            LovelaceCard(
                type: "entities",
                title: "Card \(index)",
                entities: [LovelaceEntityRef(entity: "sensor.fixture_\(index)")]
            )
        }
        let config = LovelaceConfig(views: (0..<10).map { index in
            LovelaceView(
                title: index == 0 ? "Home" : "View \(index)",
                path: index == 0 ? "default_view" : "view_\(index)",
                cards: cards,
                sourceIndex: index
            )
        })
        let resolved = LovelaceResolvedDashboard(source: config)
        let models = try config.views.enumerated().map { index, view -> DashboardViewModel in
            let store = GUIMemoryNavigationPreferenceStore()
            let persistence = LovelaceNavigationSelectionPersistence(
                key: AppConfig.lovelaceNavigationPolicy.persistedPrimarySelectionKey,
                store: store
            )
            try persistence.save(.path(try XCTUnwrap(view.path)))
            let model = DashboardViewModel(
                initialViews: config.views,
                navigationPreferenceStore: store
            )
            XCTAssertEqual(model.homeView?.path, view.path, "Prepared model \(index) must select its genuine locator")
            XCTAssertEqual(model.activeCards.count, 50)
            return model
        }
        let initialSize = CGSize(width: 1_792, height: 1_000)
        let hostingView = NSHostingView(
            rootView: AnyView(
                DashboardView(model: models[0], startsOnAppear: false)
                    .frame(width: initialSize.width, height: initialSize.height)
            )
        )
        hostingView.frame = CGRect(origin: .zero, size: initialSize)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderBack(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let ranges = AppConfig.graphHourOptions

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            for cycle in 0..<100 {
                let model = models[cycle % models.count]
                model.selectedGraphHours = ranges[cycle % ranges.count]
                let size = cycle.isMultiple(of: 2)
                    ? CGSize(width: 1_792, height: 1_000)
                    : CGSize(width: 900, height: 700)
                hostingView.rootView = AnyView(
                    DashboardView(model: model, startsOnAppear: false)
                        .frame(width: size.width, height: size.height)
                )
                hostingView.frame = CGRect(origin: .zero, size: size)
                hostingView.layoutSubtreeIfNeeded()
                hostingView.displayIfNeeded()
                XCTAssertEqual(model.activeCards.count, 50)
                XCTAssertEqual(model.navigationItems.filter(\.isSelected).count, 1)
                XCTAssertFalse(model.dashboardColumns.isEmpty)
                XCTAssertEqual(resolved.views.reduce(0) { $0 + $1.cards.count }, 500)
            }
        }
        print("MODULE12_LAYOUT_METRIC cycles=100 views=10 cards=500 widths=1792|900 ranges=\(ranges)")
    }

    private func module12VisualConfig() throws -> LovelaceConfig {
        func entitiesCard(_ title: String, _ entityID: String) -> JSONValue {
            .object([
                "type": .string("entities"),
                "title": .string(title),
                "entities": .array([.string(entityID)]),
            ])
        }
        return try LovelaceConfig(rawValue: .object([
            "views": .array([
                .object([
                    "title": .string("Home"),
                    "path": .string("default_view"),
                    "cards": .array([entitiesCard("Home card", "sensor.home")]),
                ]),
                .object([
                    "title": .string("3h maintenance"),
                    "path": .string("home_3h"),
                    "cards": .array([]),
                ]),
                .object([
                    "title": .string("12h maintenance"),
                    "path": .string("home_12h"),
                    "cards": .array([]),
                ]),
                .object([
                    "title": .string("A Deliberately Long Genuine Lovelace View Title"),
                    "path": .string("genuine"),
                    "icon": .string("mdi:weather-cloudy"),
                    "show_icon_and_title": .bool(true),
                    "cards": .array([entitiesCard("Genuine card", "sensor.genuine")]),
                ]),
                .object([
                    "title": .string("Panel View"),
                    "path": .string("panel"),
                    "panel": .bool(true),
                    "cards": .array([entitiesCard("Panel card", "sensor.panel")]),
                ]),
                .object([
                    "title": .string("Empty View"),
                    "path": .string("empty"),
                    "cards": .array([]),
                ]),
            ]),
        ]))
    }

    private func renderModule12Dashboard(
        _ model: DashboardViewModel,
        size: CGSize
    ) throws -> RenderedPNG {
        let rendered = try MacViewPNGRenderer.render(
            DashboardView(model: model, startsOnAppear: false)
                .frame(width: size.width, height: size.height),
            size: size,
            displayScale: 2,
            settleTime: 0.1
        )
        try assertUsablePNG(rendered, minimumBytes: 10_000, minimumChangedSamples: 100)
        try assertDimensions(
            rendered.pngData,
            width: Int(size.width * 2),
            height: Int(size.height * 2)
        )
        return rendered
    }

    private func renderLovelaceArtifact<Content: View>(
        _ content: Content,
        size: CGSize,
        settleTime: TimeInterval = 0,
        name: String
    ) throws {
        let rendered = try MacViewPNGRenderer.render(
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(red: 0.055, green: 0.06, blue: 0.06)),
            size: size,
            displayScale: 2,
            settleTime: settleTime
        )
        try assertUsablePNG(rendered, minimumBytes: 3_000, minimumChangedSamples: 30)
        try assertDimensions(
            rendered.pngData,
            width: Int(size.width * 2),
            height: Int(size.height * 2)
        )
        try persistAndAttach(rendered.pngData, name: name)
    }

    private func historyLoadingVisual(
        size: CGSize
    ) throws -> (rendered: RenderedPNG, oracle: HistoryVisualLabelOracle) {
        let loadingProbe = HistoryVisualSettlementProbe()
        var discoveredOracle: HistoryVisualLabelOracle?
        let loading = try MacViewPNGRenderer.render(
            HistoryStreamLoadingFixture(onReady: { loadingProbe.markLoadingReady() }),
            size: size,
            displayScale: 2,
            readiness: { loadingProbe.isReady },
            bitmapReadiness: { bitmap in
                guard let oracle = HistoryVisualLabelOracle.discover(in: bitmap) else {
                    return false
                }
                discoveredOracle = oracle
                return oracle.isSettled(bitmap, requiresAxesAndData: false)
            },
            requiredConsecutiveBitmapReadinessPasses: 2
        )
        let oracle = try XCTUnwrap(discoveredOracle)
        try assertUsablePNG(loading, minimumBytes: 3_000, minimumChangedSamples: 20)
        try assertDimensions(loading.pngData, width: 992, height: 520)
        try assertSettledHistorySurface(
            loading.pngData,
            requiresAxesAndData: false,
            oracle: oracle
        )
        return (loading, oracle)
    }

    private func historyStreamVisual(
        input: GraphRenderSeriesInput,
        unit: String,
        size: CGSize,
        oracle: HistoryVisualLabelOracle
    ) throws -> RenderedPNG {
        let probe = HistoryVisualSettlementProbe()
        let rendered = try MacViewPNGRenderer.render(
            HistoryStreamVisualFixture(
                unit: unit,
                input: input,
                onRenderReady: { probe.record($0) }
            ),
            size: size,
            displayScale: 2,
            readiness: { probe.isReady },
            bitmapReadiness: { oracle.isSettled($0, requiresAxesAndData: true) },
            requiredConsecutiveBitmapReadinessPasses: 2
        )
        XCTAssertGreaterThanOrEqual(probe.xTickCount, 4)
        XCTAssertGreaterThan(probe.renderedDatumCount, 0)
        try assertUsablePNG(rendered, minimumBytes: 8_000, minimumChangedSamples: 100)
        try assertDimensions(rendered.pngData, width: 992, height: 520)
        try assertSettledHistorySurface(
            rendered.pngData,
            requiresAxesAndData: true,
            oracle: oracle
        )
        return rendered
    }

    private func assertSettledHistorySurface(
        _ data: Data,
        requiresAxesAndData: Bool,
        oracle: HistoryVisualLabelOracle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data), file: file, line: line)
        XCTAssertTrue(oracle.hasHeaderLabel(in: bitmap), "Header glyphs were not settled", file: file, line: line)
        XCTAssertTrue(
            oracle.hasOneHourRangeLabel(in: bitmap),
            "The composited 1h glyph template was not present in its range-label band",
            file: file,
            line: line
        )

        guard requiresAxesAndData else { return }
        let dataInk = changedSamples(in: bitmap, x: 80..<960, y: 100..<420)
        XCTAssertTrue(
            oracle.hasFiveAxisLabels(in: bitmap),
            "Five separated bottom-axis glyph groups were not settled",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(dataInk, 100, "Rendered data region was not settled", file: file, line: line)
    }

    private func changedSamples(
        in bitmap: NSBitmapImageRep,
        x: Range<Int>,
        y: Range<Int>
    ) -> Int {
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
            return 0
        }
        var count = 0
        for row in stride(from: y.lowerBound, to: min(y.upperBound, bitmap.pixelsHigh), by: 2) {
            for column in stride(from: x.lowerBound, to: min(x.upperBound, bitmap.pixelsWide), by: 2) {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let difference = abs(color.redComponent - background.redComponent) +
                    abs(color.greenComponent - background.greenComponent) +
                    abs(color.blueComponent - background.blueComponent) +
                    abs(color.alphaComponent - background.alphaComponent)
                if difference > 0.06 { count += 1 }
            }
        }
        return count
    }

    private func assertDimensions(_ data: Data, width: Int, height: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, width)
        XCTAssertEqual(bitmap.pixelsHigh, height)
    }

    private func assertUsablePNG(
        _ rendered: RenderedPNG,
        minimumBytes: Int,
        minimumChangedSamples: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            Array(rendered.pngData.prefix(8)),
            [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
            file: file,
            line: line
        )
        XCTAssertGreaterThan(rendered.pngData.count, minimumBytes, file: file, line: line)
        XCTAssertGreaterThan(
            rendered.nonBackgroundSampleCount,
            minimumChangedSamples,
            file: file,
            line: line
        )
    }

    private func persistAndAttach(_ data: Data, name: String) throws {
        let url = try writeRenderArtifact(data, name: name)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("Rendered GUI artifact: \(url.path)")
    }
}

private struct HistoryStreamLoadingFixture: View {
    let onReady: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("History")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("1h")
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity)
            Text("Loading history")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(18)
        .frame(width: 496, height: 260)
        .background(Color(red: 0.09, green: 0.095, blue: 0.095))
        .onAppear(perform: onReady)
    }
}

private struct HistoryStreamVisualFixture: View {
    let unit: String
    let input: GraphRenderSeriesInput
    let onRenderReady: (GraphRenderResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(unit == HAHistoryGraphClassifier.stateUnit ? "Timeline history" : "Numeric history")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("1h")
                    .font(.system(size: 12, weight: .medium))
            }
            BitmapLineChart(
                unit: unit,
                inputs: [input],
                zoomScale: 1,
                panFraction: 1,
                hoverLocation: .constant(nil),
                onMagnify: { _, _, _ in },
                onPan: { _ in },
                onRenderReady: onRenderReady
            )
        }
        .padding(18)
        .frame(width: 496, height: 260)
        .background(Color(red: 0.09, green: 0.095, blue: 0.095))
    }
}

private final class HistoryVisualSettlementProbe {
    private(set) var isReady = false
    private(set) var xTickCount = 0
    private(set) var renderedDatumCount = 0

    func markLoadingReady() {
        isReady = true
    }

    func record(_ result: GraphRenderResult) {
        xTickCount = result.xTicks.count
        renderedDatumCount = result.series.reduce(0) { count, series in
            count + series.points.count + series.timelineSegments.count
        }
        isReady = xTickCount >= 4 && renderedDatumCount > 0
    }
}

private struct HistoryVisualLabelOracle {
    private let shellAtLowEdge: Bool
    private let oneHourTemplate: HistoryBinaryMask

    static func discover(in bitmap: NSBitmapImageRep) -> HistoryVisualLabelOracle? {
        for shellAtLowEdge in [true, false] {
            let mask = HistoryBinaryMask(
                bitmap: bitmap,
                rect: rangeRect(in: bitmap, shellAtLowEdge: shellAtLowEdge)
            )
            guard mask.looksLikeOneHourGlyphs else { continue }
            let oracle = HistoryVisualLabelOracle(
                shellAtLowEdge: shellAtLowEdge,
                oneHourTemplate: mask
            )
            if oracle.hasHeaderLabel(in: bitmap) {
                return oracle
            }
        }
        return nil
    }

    func isSettled(_ bitmap: NSBitmapImageRep, requiresAxesAndData: Bool) -> Bool {
        guard hasHeaderLabel(in: bitmap), hasOneHourRangeLabel(in: bitmap) else {
            return false
        }
        guard requiresAxesAndData else { return true }
        return hasFiveAxisLabels(in: bitmap) && dataRegionIsPopulated(in: bitmap)
    }

    func hasHeaderLabel(in bitmap: NSBitmapImageRep) -> Bool {
        let mask = HistoryBinaryMask(
            bitmap: bitmap,
            rect: Self.orientedRect(
                x: 20..<700,
                topY: 20..<78,
                in: bitmap,
                shellAtLowEdge: shellAtLowEdge
            )
        )
        let glyphs = mask.components.filter {
            $0.pixelCount >= 40 && $0.height >= 15 && $0.height <= 25
        }
        guard glyphs.count >= 7, let bounds = HistoryGlyphComponent.union(glyphs) else {
            return false
        }
        return bounds.width >= 70 && bounds.height >= 17 && bounds.height <= 30
    }

    func hasOneHourRangeLabel(in bitmap: NSBitmapImageRep) -> Bool {
        let candidate = HistoryBinaryMask(
            bitmap: bitmap,
            rect: Self.rangeRect(in: bitmap, shellAtLowEdge: shellAtLowEdge)
        )
        guard candidate.looksLikeOneHourGlyphs else { return false }
        return oneHourTemplate.maximumIntersectionOverUnion(with: candidate, translationRadius: 1) >= 0.82
    }

    func hasFiveAxisLabels(in bitmap: NSBitmapImageRep) -> Bool {
        let horizontalBands = [
            60..<185,
            255..<390,
            455..<595,
            660..<800,
            860..<985,
        ]
        return horizontalBands.allSatisfy { xBand in
            let mask = HistoryBinaryMask(
                bitmap: bitmap,
                rect: Self.orientedRect(
                    x: xBand,
                    topY: 440..<480,
                    in: bitmap,
                    shellAtLowEdge: shellAtLowEdge
                )
            )
            let glyphs = mask.components.filter {
                $0.pixelCount >= 30 && $0.height >= 12 && $0.height <= 21
            }
            guard glyphs.count >= 5, let bounds = HistoryGlyphComponent.union(glyphs) else {
                return false
            }
            return mask.foregroundCount >= 250 &&
                bounds.width >= 70 && bounds.width <= 115 &&
                bounds.height >= 14 && bounds.height <= 22
        }
    }

    func erasingRangeLabel(in bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
        let rect = Self.rangeRect(in: bitmap, shellAtLowEdge: shellAtLowEdge)
        return try bitmapByErasing(rect: rect, in: bitmap)
    }

    func erasingAxisLabels(in bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
        let rect = Self.orientedRect(
            x: 50..<985,
            topY: 435..<485,
            in: bitmap,
            shellAtLowEdge: shellAtLowEdge
        )
        return try bitmapByErasing(rect: rect, in: bitmap)
    }

    private func dataRegionIsPopulated(in bitmap: NSBitmapImageRep) -> Bool {
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
            return false
        }
        var count = 0
        for y in stride(from: 100, to: min(420, bitmap.pixelsHigh), by: 2) {
            for x in stride(from: 80, to: min(960, bitmap.pixelsWide), by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let difference = abs(color.redComponent - background.redComponent) +
                    abs(color.greenComponent - background.greenComponent) +
                    abs(color.blueComponent - background.blueComponent) +
                    abs(color.alphaComponent - background.alphaComponent)
                if difference > 0.06 {
                    count += 1
                    if count > 100 { return true }
                }
            }
        }
        return false
    }

    private func bitmapByErasing(
        rect: HistoryPixelRect,
        in bitmap: NSBitmapImageRep
    ) throws -> NSBitmapImageRep {
        guard
            let data = bitmap.representation(using: .png, properties: [:]),
            let copy = NSBitmapImageRep(data: data),
            let fill = copy.colorAt(x: rect.x.lowerBound, y: rect.y.lowerBound)
        else {
            throw MacViewPNGRendererError.bitmapCreationFailed
        }
        for y in rect.y {
            for x in rect.x {
                copy.setColor(fill, atX: x, y: y)
            }
        }
        return copy
    }

    private static func rangeRect(
        in bitmap: NSBitmapImageRep,
        shellAtLowEdge: Bool
    ) -> HistoryPixelRect {
        orientedRect(
            x: 900..<975,
            topY: 30..<75,
            in: bitmap,
            shellAtLowEdge: shellAtLowEdge
        )
    }

    private static func orientedRect(
        x: Range<Int>,
        topY: Range<Int>,
        in bitmap: NSBitmapImageRep,
        shellAtLowEdge: Bool
    ) -> HistoryPixelRect {
        let y: Range<Int>
        if shellAtLowEdge {
            y = topY
        } else {
            y = (bitmap.pixelsHigh - topY.upperBound)..<(bitmap.pixelsHigh - topY.lowerBound)
        }
        return HistoryPixelRect(
            x: max(0, x.lowerBound)..<min(bitmap.pixelsWide, x.upperBound),
            y: max(0, y.lowerBound)..<min(bitmap.pixelsHigh, y.upperBound)
        )
    }
}

private struct HistoryPixelRect {
    let x: Range<Int>
    let y: Range<Int>
}

private struct HistoryGlyphComponent {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int
    let pixelCount: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }

    static func union(_ components: [HistoryGlyphComponent]) -> HistoryGlyphComponent? {
        guard let first = components.first else { return nil }
        return components.dropFirst().reduce(first) { result, component in
            HistoryGlyphComponent(
                minX: min(result.minX, component.minX),
                maxX: max(result.maxX, component.maxX),
                minY: min(result.minY, component.minY),
                maxY: max(result.maxY, component.maxY),
                pixelCount: result.pixelCount + component.pixelCount
            )
        }
    }
}

private struct HistoryBinaryMask {
    let width: Int
    let height: Int
    let pixels: [Bool]

    init(bitmap: NSBitmapImageRep, rect: HistoryPixelRect) {
        width = rect.x.count
        height = rect.y.count
        var values = Array(repeating: false, count: width * height)
        for (localY, y) in rect.y.enumerated() {
            for (localX, x) in rect.x.enumerated() {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let brightness = max(
                    color.redComponent,
                    max(color.greenComponent, color.blueComponent)
                )
                values[localY * width + localX] = brightness > 0.45 && color.alphaComponent > 0.5
            }
        }
        pixels = values
    }

    var foregroundCount: Int {
        pixels.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    var looksLikeOneHourGlyphs: Bool {
        let glyphs = components
            .filter { $0.pixelCount >= 40 && $0.height >= 15 && $0.height <= 21 }
            .sorted { $0.minX < $1.minX }
        guard glyphs.count == 2, let bounds = HistoryGlyphComponent.union(glyphs) else {
            return false
        }
        return foregroundCount >= 150 && foregroundCount <= 260 &&
            glyphs[0].width >= 6 && glyphs[0].width <= 10 &&
            glyphs[1].width >= 10 && glyphs[1].width <= 14 &&
            glyphs[1].minX - glyphs[0].maxX >= 2 &&
            glyphs[1].minX - glyphs[0].maxX <= 7 &&
            bounds.width >= 20 && bounds.width <= 28 &&
            bounds.height >= 16 && bounds.height <= 21
    }

    var components: [HistoryGlyphComponent] {
        guard width > 0, height > 0 else { return [] }
        var visited = Array(repeating: false, count: pixels.count)
        var result: [HistoryGlyphComponent] = []
        for start in pixels.indices where pixels[start] && !visited[start] {
            visited[start] = true
            var stack = [start]
            var cursor = 0
            var minX = start % width
            var maxX = minX
            var minY = start / width
            var maxY = minY
            var count = 0
            while cursor < stack.count {
                let index = stack[cursor]
                cursor += 1
                count += 1
                let x = index % width
                let y = index / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                for adjacentY in max(0, y - 1)...min(height - 1, y + 1) {
                    for adjacentX in max(0, x - 1)...min(width - 1, x + 1) {
                        let adjacent = adjacentY * width + adjacentX
                        if pixels[adjacent] && !visited[adjacent] {
                            visited[adjacent] = true
                            stack.append(adjacent)
                        }
                    }
                }
            }
            result.append(
                HistoryGlyphComponent(
                    minX: minX,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY,
                    pixelCount: count
                )
            )
        }
        return result
    }

    func maximumIntersectionOverUnion(
        with candidate: HistoryBinaryMask,
        translationRadius: Int
    ) -> Double {
        guard width == candidate.width, height == candidate.height else { return 0 }
        let templateCount = foregroundCount
        let candidateCount = candidate.foregroundCount
        guard templateCount > 0, candidateCount > 0 else { return 0 }
        var maximum = 0.0
        for offsetY in -translationRadius...translationRadius {
            for offsetX in -translationRadius...translationRadius {
                var intersection = 0
                for y in 0..<height {
                    let candidateY = y + offsetY
                    guard candidateY >= 0, candidateY < height else { continue }
                    for x in 0..<width where pixels[y * width + x] {
                        let candidateX = x + offsetX
                        guard candidateX >= 0, candidateX < width else { continue }
                        if candidate.pixels[candidateY * width + candidateX] {
                            intersection += 1
                        }
                    }
                }
                let union = templateCount + candidateCount - intersection
                if union > 0 {
                    maximum = max(maximum, Double(intersection) / Double(union))
                }
            }
        }
        return maximum
    }
}

struct RenderedPNG {
    let pngData: Data
    let nonBackgroundSampleCount: Int
    let blueSampleCount: Int
}

enum MacViewPNGRendererError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
    case settlementTimedOut
}

enum MacViewPNGRenderer {
    @MainActor
    static func render<V: View>(
        _ view: V,
        size: CGSize,
        displayScale: CGFloat,
        settleTime: TimeInterval = 0,
        readiness: (() -> Bool)? = nil,
        bitmapReadiness: ((NSBitmapImageRep) -> Bool)? = nil,
        requiredConsecutiveBitmapReadinessPasses: Int = 1,
        readinessTimeout: TimeInterval = 3
    ) throws -> RenderedPNG {
        _ = NSApplication.shared

        let hostingView = NSHostingView(
            rootView: view
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.displayScale, displayScale)
        )
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.orderBack(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        if let readiness = readiness {
            let deadline = Date(timeIntervalSinceNow: readinessTimeout)
            while !readiness(), Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                hostingView.layoutSubtreeIfNeeded()
                hostingView.displayIfNeeded()
            }
            guard readiness() else {
                throw MacViewPNGRendererError.settlementTimedOut
            }
            // Readiness is emitted when production render state is installed.
            // Complete two deterministic layout/display turns so its SwiftUI
            // overlays (header, range, axes, and tick labels) are composited.
            for _ in 0..<2 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                hostingView.layoutSubtreeIfNeeded()
                hostingView.displayIfNeeded()
            }
        } else if settleTime > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: settleTime))
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }

        let makeBitmap: () throws -> NSBitmapImageRep = {
            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
                throw MacViewPNGRendererError.bitmapCreationFailed
            }
            bitmap.size = size
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            return bitmap
        }

        let bitmap: NSBitmapImageRep
        if let bitmapReadiness = bitmapReadiness {
            let deadline = Date(timeIntervalSinceNow: readinessTimeout)
            var settled: NSBitmapImageRep?
            var consecutivePasses = 0
            let requiredPasses = max(1, requiredConsecutiveBitmapReadinessPasses)
            repeat {
                let candidate = try makeBitmap()
                if bitmapReadiness(candidate) {
                    consecutivePasses += 1
                    if consecutivePasses >= requiredPasses {
                        settled = candidate
                        break
                    }
                } else {
                    consecutivePasses = 0
                }
                // Every pass is evaluated against a newly cached bitmap after
                // another display turn; a single transient label composition
                // can therefore never be accepted as the final artifact.
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                hostingView.layoutSubtreeIfNeeded()
                hostingView.displayIfNeeded()
            } while Date() < deadline
            guard let settled = settled else {
                throw MacViewPNGRendererError.settlementTimedOut
            }
            bitmap = settled
        } else {
            bitmap = try makeBitmap()
        }

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw MacViewPNGRendererError.pngEncodingFailed
        }

        return RenderedPNG(
            pngData: pngData,
            nonBackgroundSampleCount: changedSampleCount(in: bitmap),
            blueSampleCount: blueSampleCount(in: bitmap)
        )
    }

    private static func changedSampleCount(in bitmap: NSBitmapImageRep) -> Int {
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
            return 0
        }
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let difference = abs(color.redComponent - background.redComponent) +
                    abs(color.greenComponent - background.greenComponent) +
                    abs(color.blueComponent - background.blueComponent) +
                    abs(color.alphaComponent - background.alphaComponent)
                if difference > 0.06 {
                    count += 1
                }
            }
        }
        return count
    }

    private static func blueSampleCount(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.blueComponent > color.redComponent + 0.18 &&
                    color.blueComponent > color.greenComponent + 0.08 &&
                    color.alphaComponent > 0.5 {
                    count += 1
                }
            }
        }
        return count
    }
}

enum ApprovedVisualReference {
    static func compareIfPresent(
        actualPNG: Data,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let referenceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ReferenceImages", isDirectory: true)
            .appendingPathComponent(name)
        let requiresReferences = ProcessInfo.processInfo.environment["NATIVEHA_REQUIRE_VISUAL_REFERENCES"] == "1"

        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            if requiresReferences {
                XCTFail("Missing approved visual reference at \(referenceURL.path)", file: file, line: line)
            }
            return
        }

        let expectedData = try Data(contentsOf: referenceURL)
        let expected = try XCTUnwrap(NSBitmapImageRep(data: expectedData), file: file, line: line)
        let actual = try XCTUnwrap(NSBitmapImageRep(data: actualPNG), file: file, line: line)
        XCTAssertEqual(actual.pixelsWide, expected.pixelsWide, file: file, line: line)
        XCTAssertEqual(actual.pixelsHigh, expected.pixelsHigh, file: file, line: line)
        guard actual.pixelsWide == expected.pixelsWide, actual.pixelsHigh == expected.pixelsHigh else {
            return
        }

        var changed = 0
        var total = 0
        var channelDelta = 0.0
        for y in stride(from: 0, to: actual.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: actual.pixelsWide, by: 2) {
                guard
                    let lhs = actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    let rhs = expected.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else {
                    continue
                }
                let deltas = [
                    abs(lhs.redComponent - rhs.redComponent),
                    abs(lhs.greenComponent - rhs.greenComponent),
                    abs(lhs.blueComponent - rhs.blueComponent),
                    abs(lhs.alphaComponent - rhs.alphaComponent),
                ]
                if deltas.max() ?? 0 > 0.08 {
                    changed += 1
                }
                channelDelta += deltas.reduce(0, +) / Double(deltas.count)
                total += 1
            }
        }

        let changedRatio = total == 0 ? 1 : Double(changed) / Double(total)
        let meanChannelDelta = total == 0 ? 1 : channelDelta / Double(total)
        XCTAssertLessThanOrEqual(
            changedRatio,
            0.02,
            "\(name) changed \(String(format: "%.2f", changedRatio * 100))% of sampled pixels.",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            meanChannelDelta,
            0.015,
            "\(name) mean channel delta was \(String(format: "%.4f", meanChannelDelta)).",
            file: file,
            line: line
        )
    }
}

private final class GUIMemoryNavigationPreferenceStore: LovelaceNavigationPreferenceStore {
    private var values: [String: Any] = [:]
    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}

private func performanceInput(pointCount: Int, entityID: String) -> GraphRenderSeriesInput {
    let points = (0..<pointCount).map { index -> HAHistoryPoint in
        let offset = index
        let hour = offset / 3_600
        let minute = (offset % 3_600) / 60
        let second = offset % 60
        let timestamp = String(
            format: "2026-01-01T%02d:%02d:%02dZ",
            hour,
            minute,
            second
        )
        let value = 18 + sin(Double(index) / 19) * 8 + cos(Double(index) / 61) * 3
        return HAHistoryPoint(
            entityId: entityID,
            state: String(format: "%.3f", value),
            attributes: nil,
            lastChanged: timestamp,
            lastUpdated: timestamp
        )
    }
    return GraphRenderSeriesInput(
        entityID: entityID,
        name: "Performance fixture",
        unit: "µg/m³",
        color: GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1),
        history: HAHistorySeries(entityID: entityID, points: points),
        windowStart: 1767225600.0,
        windowEnd: 1767225600.0 + Double(pointCount)
    )
}

private func numericPerformanceInput(pointCount: Int, entityID: String) -> GraphRenderSeriesInput {
    let points = (0..<pointCount).map { index -> HAHistoryPoint in
        let value = 18 + sin(Double(index) / 19) * 8 + cos(Double(index) / 61) * 3
        let timestamp = historyVisualBase + Double(index)
        return HAHistoryPoint(
            entityId: entityID,
            state: String(format: "%.3f", value),
            attributes: nil,
            lastChangedSeconds: timestamp,
            lastUpdatedSeconds: timestamp
        )
    }
    return GraphRenderSeriesInput(
        entityID: entityID,
        name: "Numeric performance fixture",
        unit: "µg/m³",
        color: GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1),
        history: HAHistorySeries(entityID: entityID, points: points),
        windowStart: historyVisualBase,
        windowEnd: historyVisualBase + Double(max(pointCount - 1, 0))
    )
}

private let historyVisualBase = 1_767_225_600.0

private func historyStreamNumericInput(middleState: String) -> GraphRenderSeriesInput {
    GraphRenderSeriesInput(
        entityID: "sensor.history_visual",
        name: "History visual",
        unit: "°C",
        color: GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1),
        history: HAHistorySeries(
            entityID: "sensor.history_visual",
            points: [
                historyVisualPoint(entityID: "sensor.history_visual", state: "18", offset: 0),
                historyVisualPoint(entityID: "sensor.history_visual", state: middleState, offset: 1_800),
                historyVisualPoint(entityID: "sensor.history_visual", state: "22", offset: 3_600),
            ]
        ),
        windowStart: historyVisualBase,
        windowEnd: historyVisualBase + 3_600
    )
}

private func historyStreamTimelineInput(lastState: String) -> GraphRenderSeriesInput {
    GraphRenderSeriesInput(
        entityID: "switch.history_visual",
        name: "History visual",
        unit: HAHistoryGraphClassifier.stateUnit,
        color: GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1),
        history: HAHistorySeries(
            entityID: "switch.history_visual",
            points: [
                historyVisualPoint(entityID: "switch.history_visual", state: "off", offset: 0),
                historyVisualPoint(entityID: "switch.history_visual", state: "on", offset: 1_200),
                historyVisualPoint(entityID: "switch.history_visual", state: lastState, offset: 2_400),
            ]
        ),
        windowStart: historyVisualBase,
        windowEnd: historyVisualBase + 3_600
    )
}

private func historyVisualPoint(entityID: String, state: String, offset: Int) -> HAHistoryPoint {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: Date(timeIntervalSince1970: historyVisualBase + Double(offset)))
    return HAHistoryPoint(
        entityId: entityID,
        state: state,
        attributes: nil,
        lastChanged: timestamp,
        lastUpdated: timestamp
    )
}

private func writeRenderArtifact(_ data: Data, name: String) throws -> URL {
    let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/render-artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )
    let outputURL = outputDirectory.appendingPathComponent(name)
    try data.write(to: outputURL, options: .atomic)
    return outputURL
}

private enum GUIConditionTimeout: Error {
    case conditionNotMet
}

private func waitForGUICondition(
    _ condition: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<100_000 {
        if await condition() { return }
        await Task.yield()
    }
    throw GUIConditionTimeout.conditionNotMet
}

@MainActor
private func sidebarAccessibilityButtons(in root: NSView) -> [SidebarAccessibilityNSButton] {
    func collect(_ view: NSView, into result: inout [SidebarAccessibilityNSButton]) {
        if let button = view as? SidebarAccessibilityNSButton {
            result.append(button)
        }
        for subview in view.subviews {
            collect(subview, into: &result)
        }
    }

    var buttons: [SidebarAccessibilityNSButton] = []
    collect(root, into: &buttons)
    return buttons.sorted { lhs, rhs in
        let lhsY = lhs.window.map {
            $0.convertToScreen(lhs.convert(lhs.bounds, to: nil)).midY
        } ?? lhs.frame.midY
        let rhsY = rhs.window.map {
            $0.convertToScreen(rhs.convert(rhs.bounds, to: nil)).midY
        } ?? rhs.frame.midY
        return lhsY > rhsY
    }
}
