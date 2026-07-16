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

struct RenderedPNG {
    let pngData: Data
    let nonBackgroundSampleCount: Int
    let blueSampleCount: Int
}

enum MacViewPNGRendererError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
}

enum MacViewPNGRenderer {
    @MainActor
    static func render<V: View>(
        _ view: V,
        size: CGSize,
        displayScale: CGFloat,
        settleTime: TimeInterval = 0
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
        if settleTime > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: settleTime))
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw MacViewPNGRendererError.bitmapCreationFailed
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

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
        history: HAHistorySeries(entityID: entityID, points: points)
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
