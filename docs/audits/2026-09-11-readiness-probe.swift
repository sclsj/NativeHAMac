import Foundation
import CoreGraphics
import SwiftUI
import NativeHACore
@testable import NativeHAMac

// Standalone audit of production objects, without opening the app or contacting HA.
@main struct AuditProbe {
    @MainActor static func main() {
        // Keep audit probes from adding diagnostic rows to the user's app log.
        activeLoggingPolicy = LoggingPolicy(minimumSeverity: LogSeverityPolicy(
            webSocket: nil, network: nil, rendering: nil,
            interaction: nil, lifecycle: nil, general: nil
        ))
        let mode = CommandLine.arguments[1]
        if mode == "climate" {
            let state = HAState(entityId: "climate.audit", state: "unavailable", attributes: [:])
            _ = ClimateDetailContent(entityID: "climate.audit", state: state).body
            print("climate body completed")
        } else if mode == "infinite-axis" || mode == "large-finite-axis" {
            let values = mode == "infinite-axis" ? ["1", "inf"] : ["1e20", "1e20"]
            print(render(values: values, end: 100) == nil ? "nil render" : "render completed")
        } else if mode == "graph" {
            for end in [3600.0, 100.0] {
                let result = render(values: ["10", "20"], end: end)!
                let point = result.sample(atX: result.x(for: 60))!.values[0].point
                print("end=\(end) hover@60 value=\(point.y) sampleTime=\(point.t)")
                print("end=\(end) blue pixel near expected step midpoint=\(hasBlue(result, time: 50, value: 10))")
            }
            print("quiet viewport [25,75] render is nil=\(render(values: ["10", "20"], end: 100, zoom: 2, pan: 0.5) == nil)")
        } else {
            print("Usage: AuditProbe climate|infinite-axis|large-finite-axis|graph")
        }
    }

    static func render(values: [String], end: Double, zoom: CGFloat = 1, pan: Double = 1) -> GraphRenderResult? {
        let id = "sensor.audit"
        let points = values.enumerated().map { index, value in
            HAHistoryPoint(entityId: id, state: value, attributes: nil,
                lastChangedSeconds: Double(index * 100), lastUpdatedSeconds: Double(index * 100))
        }
        return GraphBitmapRenderer.render(inputs: [GraphRenderSeriesInput(
            entityID: id, name: id, unit: "°C",
            color: GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1),
            history: HAHistorySeries(entityID: id, points: points),
            windowStart: 0, windowEnd: end
        )], unit: "°C", size: CGSize(width: 254, height: 140), scale: 2,
            zoomScale: zoom, panFraction: pan, engine: .coreGraphics)
    }

    // Same two-orientation, radius-2 color oracle as the existing step test.
    static func hasBlue(_ result: GraphRenderResult, time: Double, value: Double) -> Bool {
        let image = result.image!
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { pointer in
            let context = CGContext(data: pointer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let x = Int(result.x(for: time) * result.scale)
        let expectedY = Int(result.y(for: value) * result.scale)
        for y in [expectedY, height - 1 - expectedY] {
            for row in max(y - 2, 0)...min(y + 2, height - 1) {
                for column in max(x - 2, 0)...min(x + 2, width - 1) {
                    let offset = (row * width + column) * 4
                    let red = Int(bytes[offset]), green = Int(bytes[offset + 1]), blue = Int(bytes[offset + 2])
                    if blue > red + 80 && blue > green + 45 { return true }
                }
            }
        }
        return false
    }
}
