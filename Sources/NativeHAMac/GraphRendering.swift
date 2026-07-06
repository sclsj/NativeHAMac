import CoreGraphics
import Foundation
import NativeHACore

struct GraphColor: Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct GraphRenderSeriesInput {
    let entityID: String
    let name: String
    let unit: String
    let color: GraphColor
    let history: HAHistorySeries
}

struct GraphRenderedPoint: Equatable {
    let t: Double
    let y: Double
    let display: String
}

struct GraphRenderedSeries: Identifiable {
    var id: String { entityID }

    let entityID: String
    let name: String
    let unit: String
    let color: GraphColor
    let points: [GraphRenderedPoint]
}

struct GraphAxis {
    let min: Double
    let max: Double
    let ticks: [Double]
}

struct GraphSampleValue: Identifiable {
    var id: String { series.entityID }

    let series: GraphRenderedSeries
    let point: GraphRenderedPoint
}

struct GraphSample {
    let timestamp: Double
    let x: CGFloat
    let values: [GraphSampleValue]
}

enum GraphRenderQuality {
    case interactive
    case final
}

struct GraphRenderResult {
    let image: CGImage
    let size: CGSize
    let scale: CGFloat
    let plotRect: CGRect
    let unit: String
    let quality: GraphRenderQuality
    let series: [GraphRenderedSeries]
    let axis: GraphAxis
    let xTicks: [Double]
    let fullStart: Double
    let fullEnd: Double
    let visibleStart: Double
    let visibleEnd: Double
    let zoomScale: CGFloat
    let panFraction: Double

    func x(for timestamp: Double) -> CGFloat {
        let interval = max(visibleEnd - visibleStart, 1)
        let ratio = (timestamp - visibleStart) / interval
        return plotRect.minX + plotRect.width * CGFloat(ratio)
    }

    func y(for value: Double) -> CGFloat {
        let range = max(axis.max - axis.min, 0.0001)
        let ratio = (value - axis.min) / range
        return plotRect.maxY - plotRect.height * CGFloat(ratio)
    }

    func sample(atX xPosition: CGFloat) -> GraphSample? {
        let clampedX = min(max(xPosition, plotRect.minX), plotRect.maxX)
        let ratio = Double((clampedX - plotRect.minX) / plotRect.width)
        let targetTimestamp = visibleStart + (visibleEnd - visibleStart) * ratio

        let values = series.compactMap { item -> GraphSampleValue? in
            guard let point = nearestPoint(in: item.points, to: targetTimestamp) else {
                return nil
            }
            return GraphSampleValue(series: item, point: point)
        }

        guard !values.isEmpty else {
            return nil
        }

        let averageTimestamp = values.map(\.point.t).reduce(0, +) / Double(values.count)
        return GraphSample(timestamp: averageTimestamp, x: clampedX, values: values)
    }

    private func nearestPoint(in points: [GraphRenderedPoint], to timestamp: Double) -> GraphRenderedPoint? {
        guard !points.isEmpty else {
            return nil
        }

        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].t < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }

        if low == 0 {
            return points[0]
        }

        let before = points[low - 1]
        let after = points[low]
        return abs(before.t - timestamp) <= abs(after.t - timestamp) ? before : after
    }
}

enum GraphBitmapRenderer {
    static func render(
        inputs: [GraphRenderSeriesInput],
        unit: String,
        size: CGSize,
        scale: CGFloat,
        zoomScale: CGFloat,
        panFraction: Double,
        quality: GraphRenderQuality
    ) -> GraphRenderResult? {
        let pointSeries = inputs.compactMap {
            GraphPreparedSeriesCache.shared.series(for: $0, displayUnit: unit)
        }

        guard !pointSeries.isEmpty else {
            return nil
        }

        let fullBounds = timeBounds(pointSeries)
        let fullInterval = max(fullBounds.end - fullBounds.start, 1)
        let visibleInterval = fullInterval / max(Double(zoomScale), 1)
        let scrollableInterval = max(fullInterval - visibleInterval, 0)
        let pan = min(max(panFraction, 0), 1)
        let visibleStart = fullBounds.start + scrollableInterval * pan
        let visibleEnd = visibleStart + visibleInterval

        let plotRect = CGRect(
            x: 42,
            y: 18,
            width: max(size.width - 54, 1),
            height: max(size.height - 44, 1)
        )

        let visibleSeries = pointSeries.map { item -> GraphRenderedSeries in
            let range = visibleRange(in: item.points, start: visibleStart, end: visibleEnd)
            let target = targetPointCount(
                plotWidth: plotRect.width,
                seriesCount: pointSeries.count,
                quality: quality
            )
            let points: [GraphRenderedPoint]
            switch quality {
            case .interactive:
                points = strideDownsample(item.points, in: range, target: target)
            case .final:
                points = minMaxDownsample(item.points, in: range, target: target)
            }

            return GraphRenderedSeries(
                entityID: item.entityID,
                name: item.name,
                unit: item.unit,
                color: item.color,
                points: points
            )
        }
        .filter { !$0.points.isEmpty }

        guard !visibleSeries.isEmpty else {
            return nil
        }

        let values = visibleSeries.flatMap { $0.points.map(\.y) }
        let axis = unit.lowercased() == "state"
            ? GraphAxis(min: -0.05, max: 1.05, ticks: [0, 1])
            : niceAxis(values: values)
        let xTicks = linearTicks(min: visibleStart, max: visibleEnd, count: 5)

        guard let image = drawBitmap(
            series: visibleSeries,
            size: size,
            scale: scale,
            plotRect: plotRect,
            axis: axis,
            xTicks: xTicks,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd
        ) else {
            return nil
        }

        return GraphRenderResult(
            image: image,
            size: size,
            scale: scale,
            plotRect: plotRect,
            unit: unit,
            quality: quality,
            series: visibleSeries,
            axis: axis,
            xTicks: xTicks,
            fullStart: fullBounds.start,
            fullEnd: fullBounds.end,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
            zoomScale: zoomScale,
            panFraction: pan
        )
    }

    private static func drawBitmap(
        series: [GraphRenderedSeries],
        size: CGSize,
        scale: CGFloat,
        plotRect: CGRect,
        axis: GraphAxis,
        xTicks: [Double],
        visibleStart: Double,
        visibleEnd: Double
    ) -> CGImage? {
        let width = max(Int(size.width * scale), 1)
        let height = max(Int(size.height * scale), 1)
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        return data.withUnsafeMutableBytes { pointer in
            guard let context = CGContext(
                data: pointer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }

            context.scaleBy(x: scale, y: scale)
            // Bitmap contexts use a lower-left-style user space by default on macOS.
            // Flip into SwiftUI/AppKit's top-left layout convention so graph pixels
            // align with the overlay axes and hover geometry.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(CGColor(red: 0.055, green: 0.06, blue: 0.06, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))

            context.setStrokeColor(CGColor(gray: 1, alpha: 0.09))
            context.setLineWidth(1)
            for tick in axis.ticks {
                let y = yPosition(tick, axis: axis, plotRect: plotRect)
                context.move(to: CGPoint(x: plotRect.minX, y: y))
                context.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            }
            for tick in xTicks {
                let x = xPosition(tick, visibleStart: visibleStart, visibleEnd: visibleEnd, plotRect: plotRect)
                context.move(to: CGPoint(x: x, y: plotRect.minY))
                context.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            }
            context.strokePath()

            context.setLineJoin(.round)
            context.setLineCap(.round)
            for item in series {
                context.setStrokeColor(item.color.cgColor)
                context.setLineWidth(2)
                let path = CGMutablePath()
                for (index, point) in item.points.enumerated() {
                    let mapped = CGPoint(
                        x: xPosition(point.t, visibleStart: visibleStart, visibleEnd: visibleEnd, plotRect: plotRect),
                        y: yPosition(point.y, axis: axis, plotRect: plotRect)
                    )
                    if index == 0 {
                        path.move(to: mapped)
                    } else {
                        path.addLine(to: mapped)
                    }
                }
                context.addPath(path)
                context.strokePath()
            }

            return context.makeImage()
        }
    }

    private static func targetPointCount(
        plotWidth: CGFloat,
        seriesCount: Int,
        quality: GraphRenderQuality
    ) -> Int {
        let count = max(seriesCount, 1)
        switch quality {
        case .interactive:
            return max(Int(plotWidth) / count, 48)
        case .final:
            return max(Int(plotWidth * 2) / count, 80)
        }
    }

    private static func xPosition(
        _ timestamp: Double,
        visibleStart: Double,
        visibleEnd: Double,
        plotRect: CGRect
    ) -> CGFloat {
        let interval = max(visibleEnd - visibleStart, 1)
        return plotRect.minX + plotRect.width * CGFloat((timestamp - visibleStart) / interval)
    }

    private static func yPosition(_ value: Double, axis: GraphAxis, plotRect: CGRect) -> CGFloat {
        let range = max(axis.max - axis.min, 0.0001)
        return plotRect.maxY - plotRect.height * CGFloat((value - axis.min) / range)
    }
}

private enum DateParsing {
    private static let lock = NSLock()
    private static let normal = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func timestamp(from point: HAHistoryPoint) -> Double? {
        lock.lock()
        defer { lock.unlock() }

        if let value = point.lastUpdated, let date = parse(value) {
            return date.timeIntervalSince1970
        }
        if let value = point.lastChanged, let date = parse(value) {
            return date.timeIntervalSince1970
        }
        return nil
    }

    private static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? normal.date(from: value)
    }
}

private func numericValue(_ state: String) -> Double? {
    if state == "on" || state == "Running" || state == "running" {
        return 1
    }
    if state == "off" || state == "idle" || state == "Not running" {
        return 0
    }
    return Double(state)
}

private func displayValue(_ state: String, unit: String) -> String {
    if let value = Double(state) {
        if unit.isEmpty || unit.lowercased() == "state" {
            return String(format: "%.2f", value)
        }
        if abs(value) >= 100 {
            return "\(String(format: "%.0f", value)) \(unit)"
        }
        return "\(String(format: "%.1f", value)) \(unit)"
    }

    return state
}

private func timeBounds(_ series: [GraphRenderedSeries]) -> (start: Double, end: Double) {
    let start = series.compactMap { $0.points.first?.t }.min() ?? 0
    let end = series.compactMap { $0.points.last?.t }.max() ?? 1
    return (start, end)
}

private final class GraphPreparedSeriesCache {
    static let shared = GraphPreparedSeriesCache()

    private let lock = NSLock()
    private var storage: [String: GraphRenderedSeries] = [:]
    private var insertionOrder: [String] = []
    private let limit = 96

    func series(for input: GraphRenderSeriesInput, displayUnit: String) -> GraphRenderedSeries? {
        let key = cacheKey(for: input, displayUnit: displayUnit)
        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let points = input.history.points.compactMap { point -> GraphRenderedPoint? in
            guard
                let timestamp = DateParsing.timestamp(from: point),
                let value = numericValue(point.state)
            else {
                return nil
            }

            return GraphRenderedPoint(
                t: timestamp,
                y: value,
                display: displayValue(point.state, unit: displayUnit)
            )
        }
        .sorted { $0.t < $1.t }

        guard !points.isEmpty else {
            return nil
        }

        let prepared = GraphRenderedSeries(
            entityID: input.entityID,
            name: input.name,
            unit: input.unit,
            color: input.color,
            points: points
        )

        lock.lock()
        if let existing = storage[key] {
            lock.unlock()
            return existing
        }
        storage[key] = prepared
        insertionOrder.append(key)
        while insertionOrder.count > limit {
            let oldKey = insertionOrder.removeFirst()
            storage.removeValue(forKey: oldKey)
        }
        lock.unlock()

        return prepared
    }

    private func cacheKey(for input: GraphRenderSeriesInput, displayUnit: String) -> String {
        let first = input.history.points.first?.lastUpdated
            ?? input.history.points.first?.lastChanged
            ?? ""
        let last = input.history.points.last?.lastUpdated
            ?? input.history.points.last?.lastChanged
            ?? ""
        return [
            input.entityID,
            input.name,
            input.unit,
            displayUnit,
            "\(input.history.points.count)",
            first,
            last,
        ].joined(separator: "\u{1F}")
    }
}

private func visibleRange(
    in points: [GraphRenderedPoint],
    start: Double,
    end: Double
) -> Range<Int> {
    guard !points.isEmpty else {
        return 0..<0
    }

    let lower = lowerBound(in: points, timestamp: start)
    let upper = upperBound(in: points, timestamp: end)
    return min(lower, points.count)..<min(max(upper, lower), points.count)
}

private func lowerBound(in points: [GraphRenderedPoint], timestamp: Double) -> Int {
    var low = 0
    var high = points.count
    while low < high {
        let mid = (low + high) / 2
        if points[mid].t < timestamp {
            low = mid + 1
        } else {
            high = mid
        }
    }
    return low
}

private func upperBound(in points: [GraphRenderedPoint], timestamp: Double) -> Int {
    var low = 0
    var high = points.count
    while low < high {
        let mid = (low + high) / 2
        if points[mid].t <= timestamp {
            low = mid + 1
        } else {
            high = mid
        }
    }
    return low
}

private func strideDownsample(
    _ points: [GraphRenderedPoint],
    in range: Range<Int>,
    target: Int
) -> [GraphRenderedPoint] {
    let count = range.count
    guard count > 0 else {
        return []
    }
    guard count > target, target > 2 else {
        return Array(points[range])
    }

    let outputCount = min(target, count)
    let step = Double(count - 1) / Double(outputCount - 1)
    var output: [GraphRenderedPoint] = []
    output.reserveCapacity(outputCount)

    var lastIndex = -1
    for index in 0..<outputCount {
        let sourceIndex = range.lowerBound + Int((Double(index) * step).rounded())
        let clampedIndex = min(max(sourceIndex, range.lowerBound), range.upperBound - 1)
        if clampedIndex != lastIndex {
            output.append(points[clampedIndex])
            lastIndex = clampedIndex
        }
    }

    return output.removingConsecutiveDuplicates()
}

private func minMaxDownsample(
    _ points: [GraphRenderedPoint],
    in range: Range<Int>,
    target: Int
) -> [GraphRenderedPoint] {
    let count = range.count
    guard count > 0 else {
        return []
    }
    guard count > target, target > 2 else {
        return Array(points[range])
    }

    let bucketCount = max(target / 2, 1)
    let bucketSize = Double(count) / Double(bucketCount)
    var output: [GraphRenderedPoint] = []
    output.reserveCapacity(target + 2)

    for bucket in 0..<bucketCount {
        let start = range.lowerBound + Int(Double(bucket) * bucketSize)
        let end = min(range.lowerBound + Int(Double(bucket + 1) * bucketSize), range.upperBound)
        guard start < end else {
            continue
        }

        let slice = points[start..<end]
        guard
            let minPoint = slice.min(by: { $0.y < $1.y }),
            let maxPoint = slice.max(by: { $0.y < $1.y })
        else {
            continue
        }

        if minPoint.t <= maxPoint.t {
            output.append(minPoint)
            if minPoint != maxPoint {
                output.append(maxPoint)
            }
        } else {
            output.append(maxPoint)
            if minPoint != maxPoint {
                output.append(minPoint)
            }
        }
    }

    let firstVisible = points[range.lowerBound]
    let lastVisible = points[range.upperBound - 1]
    if output.first != firstVisible {
        output.insert(firstVisible, at: 0)
    }
    if output.last != lastVisible {
        output.append(lastVisible)
    }
    return output.removingConsecutiveDuplicates()
}

private func niceAxis(values: [Double]) -> GraphAxis {
    let minValue = values.min() ?? 0
    let maxValue = values.max() ?? 1
    let span = max(maxValue - minValue, 0.0001)
    let padding = max(span * 0.08, 0.01)
    let paddedMin = minValue - padding
    let paddedMax = maxValue + padding
    let roughStep = (paddedMax - paddedMin) / 4
    let step = niceNumber(roughStep)
    let axisMin = floor(paddedMin / step) * step
    let axisMax = ceil(paddedMax / step) * step

    var ticks: [Double] = []
    var value = axisMin
    while value <= axisMax + step * 0.5 {
        ticks.append(value)
        value += step
    }

    return GraphAxis(min: axisMin, max: axisMax, ticks: ticks)
}

private func niceNumber(_ value: Double) -> Double {
    guard value.isFinite, value > 0 else {
        return 1
    }

    let exponent = floor(log10(value))
    let fraction = value / pow(10, exponent)
    let niceFraction: Double
    if fraction <= 1 {
        niceFraction = 1
    } else if fraction <= 2 {
        niceFraction = 2
    } else if fraction <= 5 {
        niceFraction = 5
    } else {
        niceFraction = 10
    }
    return niceFraction * pow(10, exponent)
}

private func linearTicks(min: Double, max: Double, count: Int) -> [Double] {
    guard count > 1 else {
        return [min]
    }
    return (0..<count).map { min + (max - min) * Double($0) / Double(count - 1) }
}

private extension Array where Element == GraphRenderedPoint {
    func removingConsecutiveDuplicates() -> [GraphRenderedPoint] {
        var output: [GraphRenderedPoint] = []
        output.reserveCapacity(count)
        for item in self where output.last != item {
            output.append(item)
        }
        return output
    }
}
