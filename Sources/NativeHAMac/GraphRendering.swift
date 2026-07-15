import CoreGraphics
import Foundation
import Accelerate
import NativeHACore

struct GraphColor: Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let raw = UInt32(trimmed, radix: 16) else {
            return nil
        }

        self.red = CGFloat((raw >> 16) & 0xff) / 255
        self.green = CGFloat((raw >> 8) & 0xff) / 255
        self.blue = CGFloat(raw & 0xff) / 255
        self.alpha = 1
    }

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
    let minMaxCache: GraphMinMaxCache?
    let timelineSegments: [HAHistoryTimelineSegment]

    init(
        entityID: String,
        name: String,
        unit: String,
        color: GraphColor,
        points: [GraphRenderedPoint],
        minMaxCache: GraphMinMaxCache? = nil,
        timelineSegments: [HAHistoryTimelineSegment] = []
    ) {
        self.entityID = entityID
        self.name = name
        self.unit = unit
        self.color = color
        self.points = points
        self.minMaxCache = minMaxCache
        self.timelineSegments = timelineSegments
    }
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

struct GraphRenderResult {
    let image: CGImage
    let size: CGSize
    let scale: CGFloat
    let plotRect: CGRect
    let unit: String
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
        let isStateTimeline = unit.lowercased() == "state"

        if isStateTimeline {
            let values = series.compactMap { item -> GraphSampleValue? in
                guard let segment = timelineSegment(in: item.timelineSegments, at: targetTimestamp) else {
                    return nil
                }

                return GraphSampleValue(
                    series: item,
                    point: GraphRenderedPoint(t: targetTimestamp, y: 0, display: segment.display)
                )
            }

            guard !values.isEmpty else {
                return nil
            }

            return GraphSample(timestamp: targetTimestamp, x: clampedX, values: values)
        }

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

    private func timelineSegment(
        in segments: [HAHistoryTimelineSegment],
        at timestamp: Double
    ) -> HAHistoryTimelineSegment? {
        segments.first {
            timestamp >= $0.clippedStart && timestamp <= $0.clippedEnd
        }
    }
}

enum GraphBitmapRenderer {
    static func render(
        inputs: [GraphRenderSeriesInput],
        unit: String,
        size: CGSize,
        scale: CGFloat,
        zoomScale: CGFloat,
        panFraction: Double
    ) -> GraphRenderResult? {
        let pointSeries = inputs.compactMap {
            GraphPreparedSeriesCache.shared.series(for: $0, displayUnit: unit)
        }

        guard !pointSeries.isEmpty else {
            return nil
        }

        let isStateTimeline = unit.lowercased() == "state"
        let dataEnd = isStateTimeline ? Date().timeIntervalSince1970 : nil
        let fullBounds = timeBounds(pointSeries, overrideEnd: dataEnd)
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
            let points: [GraphRenderedPoint]
            let timelineSegments: [HAHistoryTimelineSegment]
            if isStateTimeline {
                timelineSegments = HAHistoryTimelineBuilder.segments(
                    from: item.points.map {
                        HAHistoryTimelinePoint(timestamp: $0.t, state: $0.display, display: $0.display)
                    },
                    visibleStart: visibleStart,
                    visibleEnd: visibleEnd,
                    endTime: fullBounds.end
                )
                points = timelineSegments.map {
                    GraphRenderedPoint(t: $0.clippedStart, y: 0, display: $0.display)
                }
            } else {
                timelineSegments = []
                let range = visibleRange(in: item.points, start: visibleStart, end: visibleEnd)
                let target = targetPointCount(
                    plotWidth: plotRect.width,
                    seriesCount: pointSeries.count
                )
                let cache = item.minMaxCache ?? GraphMinMaxCache(points: item.points)
                points = cache.downsample(in: range, target: target)
            }

            return GraphRenderedSeries(
                entityID: item.entityID,
                name: item.name,
                unit: item.unit,
                color: item.color,
                points: points,
                timelineSegments: timelineSegments
            )
        }
        .filter { isStateTimeline ? !$0.timelineSegments.isEmpty : !$0.points.isEmpty }

        guard !visibleSeries.isEmpty else {
            return nil
        }

        let values = visibleSeries.flatMap { $0.points.map(\.y) }
        let axis = isStateTimeline
            ? GraphAxis(min: -0.05, max: 1.05, ticks: [])
            : niceAxis(values: values)
        let xTicks = linearTicks(min: visibleStart, max: visibleEnd, count: 5)

        let image: CGImage?
        if isStateTimeline {
            image = drawTimelineBitmap(
                series: visibleSeries,
                size: size,
                scale: scale,
                plotRect: plotRect,
                visibleStart: visibleStart,
                visibleEnd: visibleEnd
            )
        } else {
            image = drawBitmap(
                series: visibleSeries,
                size: size,
                scale: scale,
                plotRect: plotRect,
                axis: axis,
                xTicks: xTicks,
                visibleStart: visibleStart,
                visibleEnd: visibleEnd
            )
        }

        guard let finalImage = image else {
            return nil
        }

        return GraphRenderResult(
            image: finalImage,
            size: size,
            scale: scale,
            plotRect: plotRect,
            unit: unit,
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

    private static func drawTimelineBitmap(
        series: [GraphRenderedSeries],
        size: CGSize,
        scale: CGFloat,
        plotRect: CGRect,
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
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(CGColor(red: 0.055, green: 0.06, blue: 0.06, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))

            let maxRowHeight: CGFloat = 24
            let rowHeight = min(plotRect.height / CGFloat(max(series.count, 1)), maxRowHeight)
            let totalHeight = rowHeight * CGFloat(series.count)
            let startY = plotRect.minY + (plotRect.height - totalHeight) / 2

            for (index, item) in series.enumerated() {
                let yOffset = startY + CGFloat(index) * rowHeight

                for segment in item.timelineSegments {
                    let startX = max(
                        plotRect.minX,
                        xPosition(segment.clippedStart, visibleStart: visibleStart, visibleEnd: visibleEnd, plotRect: plotRect)
                    )
                    let endX = min(
                        plotRect.maxX,
                        xPosition(segment.clippedEnd, visibleStart: visibleStart, visibleEnd: visibleEnd, plotRect: plotRect)
                    )
                    let blockWidth = endX - startX
                    if blockWidth <= 0 { continue }

                    let blockRect = CGRect(x: startX, y: yOffset + 2, width: blockWidth, height: max(rowHeight - 4, 1))
                    context.setFillColor(timelineColor(for: segment.state, entityID: item.entityID).cgColor)
                    context.fill(blockRect)
                }
            }

            return context.makeImage()
        }
    }

    private static func timelineColor(for state: String, entityID: String) -> GraphColor {
        let color = HAHistoryTimelineColorResolver.color(for: state, entityID: entityID)
        return GraphColor(hex: color.hex) ?? GraphColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)
    }

    private static func targetPointCount(
        plotWidth: CGFloat,
        seriesCount: Int
    ) -> Int {
        let count = max(seriesCount, 1)
        return max(Int(plotWidth * 2) / count, 80)
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

final class GraphDateParser {
    private let parser = HAHistoryTimestampParser()

    func timestamp(from point: HAHistoryPoint) -> Double? {
        parser.timestamp(from: point)
    }
}

private func numericValue(_ state: String) -> Double? {
    let lower = state.lowercased()
    if lower == "on" || lower == "running" || lower == "home" || lower == "active" || lower == "open" {
        return 1
    }
    if lower == "off" || lower == "idle" || lower == "not running" || lower == "not_home" || lower == "inactive" || lower == "closed" {
        return 0
    }
    return Double(state)
}

private func displayValue(_ state: String, unit: String) -> String {
    if unit.lowercased() == "state" {
        return state
    }

    if let value = Double(state) {
        if unit.isEmpty {
            return String(format: "%.2f", value)
        }
        if abs(value) >= 100 {
            return "\(String(format: "%.0f", value)) \(unit)"
        }
        return "\(String(format: "%.1f", value)) \(unit)"
    }

    return state
}

private func timeBounds(
    _ series: [GraphRenderedSeries],
    overrideEnd: Double? = nil
) -> (start: Double, end: Double) {
    let start = series.compactMap { $0.points.first?.t }.min() ?? 0
    let end = overrideEnd ?? series.compactMap { $0.points.last?.t }.max() ?? 1
    return (start, end)
}

private final class GraphPreparedSeriesCache {
    static let shared = GraphPreparedSeriesCache()

    private let lock = NSLock()
    private var storage: [String: GraphPreparedCacheEntry] = [:]
    private var insertionOrder: [String] = []
    private let limit = 96

    func series(for input: GraphRenderSeriesInput, displayUnit: String) -> GraphRenderedSeries? {
        let key = stableKey(for: input, displayUnit: displayUnit)
        let fingerprint = sourceFingerprint(for: input.history)

        lock.lock()
        if let cached = storage[key] {
            if cached.matches(fingerprint) {
                lock.unlock()
                return cached.series
            }
            lock.unlock()

            if let updated = incrementallyUpdate(
                cached,
                input: input,
                displayUnit: displayUnit,
                fingerprint: fingerprint
            ) {
                store(updated, key: key)
                return updated.series
            }
        } else {
            lock.unlock()
        }

        guard let prepared = prepareFull(input: input, displayUnit: displayUnit, fingerprint: fingerprint) else {
            return nil
        }

        store(prepared, key: key)
        return prepared.series
    }

    private func prepareFull(
        input: GraphRenderSeriesInput,
        displayUnit: String,
        fingerprint: GraphSourceFingerprint
    ) -> GraphPreparedCacheEntry? {
        let parser = GraphDateParser()
        let isStateTimeline = displayUnit.lowercased() == "state"
        let points = input.history.points.compactMap { point -> GraphRenderedPoint? in
            guard let timestamp = parser.timestamp(from: point) else {
                return nil
            }
            let value = numericValue(point.state)
            if value == nil && !isStateTimeline {
                return nil
            }

            return GraphRenderedPoint(
                t: timestamp,
                y: value ?? 0,
                display: displayValue(point.state, unit: displayUnit)
            )
        }
        .sorted { $0.t < $1.t }
        .removingRedundantStatePoints(enabled: isStateTimeline)

        guard !points.isEmpty else {
            return nil
        }

        return GraphPreparedCacheEntry(
            fingerprint: fingerprint,
            series: GraphRenderedSeries(
                entityID: input.entityID,
                name: input.name,
                unit: input.unit,
                color: input.color,
                points: points,
                minMaxCache: isStateTimeline ? nil : GraphMinMaxCache(points: points)
            )
        )
    }

    private func incrementallyUpdate(
        _ cached: GraphPreparedCacheEntry,
        input: GraphRenderSeriesInput,
        displayUnit: String,
        fingerprint: GraphSourceFingerprint
    ) -> GraphPreparedCacheEntry? {
        guard
            !input.history.points.isEmpty,
            !cached.series.points.isEmpty,
            let cachedLast = cached.fingerprint.lastTimestamp,
            let overlapIndex = input.history.points.lastIndex(where: { sourceTimestamp(from: $0) == cachedLast })
        else {
            return nil
        }

        let parser = GraphDateParser()
        let isStateTimeline = displayUnit.lowercased() == "state"

        if let firstInput = input.history.points.first,
           let firstInputT = parser.timestamp(from: firstInput),
           let cachedFirstT = cached.series.points.first?.t,
           firstInputT < cachedFirstT - 1.0 {
            return nil
        }

        var points: [GraphRenderedPoint]
        if
            let firstPoint = input.history.points.first,
            let firstSourceTimestamp = fingerprint.firstTimestamp,
            sourceTimestamp(from: firstPoint) == firstSourceTimestamp,
            let firstTimestamp = parser.timestamp(from: firstPoint)
        {
            let startIndex = lowerBound(in: cached.series.points, timestamp: firstTimestamp)
            points = Array(cached.series.points[startIndex...])
        } else {
            points = cached.series.points
        }

        let newSourceStart = input.history.points.index(after: overlapIndex)
        if newSourceStart < input.history.points.endIndex {
            points.reserveCapacity(points.count + input.history.points.distance(from: newSourceStart, to: input.history.points.endIndex))

            for point in input.history.points[newSourceStart...] {
                guard let timestamp = parser.timestamp(from: point) else {
                    continue
                }
                let value = numericValue(point.state)
                if value == nil && !isStateTimeline {
                    continue
                }

                let renderedPoint = GraphRenderedPoint(
                    t: timestamp,
                    y: value ?? 0,
                    display: displayValue(point.state, unit: displayUnit)
                )

                if let last = points.last, abs(last.t - renderedPoint.t) < 0.001 {
                    points[points.count - 1] = renderedPoint
                } else if isStateTimeline, points.last?.display == renderedPoint.display {
                    continue
                } else {
                    points.append(renderedPoint)
                }
            }
        }

        guard !points.isEmpty else {
            return nil
        }

        return GraphPreparedCacheEntry(
            fingerprint: fingerprint,
            series: GraphRenderedSeries(
                entityID: input.entityID,
                name: input.name,
                unit: input.unit,
                color: input.color,
                points: points,
                minMaxCache: isStateTimeline ? nil : GraphMinMaxCache(points: points)
            )
        )
    }

    private func store(_ entry: GraphPreparedCacheEntry, key: String) {
        lock.lock()
        let isNewKey = storage[key] == nil
        storage[key] = entry
        if isNewKey {
            insertionOrder.append(key)
        }
        while insertionOrder.count > limit {
            let oldKey = insertionOrder.removeFirst()
            storage.removeValue(forKey: oldKey)
        }
        lock.unlock()
    }

    private func stableKey(for input: GraphRenderSeriesInput, displayUnit: String) -> String {
        [
            input.entityID,
            input.name,
            input.unit,
            displayUnit,
            colorKey(input.color),
        ].joined(separator: "\u{1F}")
    }

    private func sourceFingerprint(for history: HAHistorySeries) -> GraphSourceFingerprint {
        GraphSourceFingerprint(
            count: history.points.count,
            firstTimestamp: history.points.first.flatMap(sourceTimestamp),
            lastTimestamp: history.points.last.flatMap(sourceTimestamp)
        )
    }
}

private struct GraphPreparedCacheEntry {
    let fingerprint: GraphSourceFingerprint
    let series: GraphRenderedSeries

    func matches(_ other: GraphSourceFingerprint) -> Bool {
        fingerprint == other
    }
}

private struct GraphSourceFingerprint: Equatable {
    let count: Int
    let firstTimestamp: String?
    let lastTimestamp: String?
}

private func sourceTimestamp(from point: HAHistoryPoint) -> String? {
    point.lastChanged ?? point.lastUpdated
}

private func colorKey(_ color: GraphColor) -> String {
    [
        Double(color.red),
        Double(color.green),
        Double(color.blue),
        Double(color.alpha),
    ]
    .map { String(format: "%.4f", $0) }
    .joined(separator: ",")
}

func visibleRange(
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

struct GraphMinMaxCache {
    let points: [GraphRenderedPoint]
    private let yValues: [Double]

    init(points: [GraphRenderedPoint]) {
        self.points = points
        self.yValues = points.map { $0.y }
    }

    func downsample(in range: Range<Int>, target: Int) -> [GraphRenderedPoint] {
        let clampedRange = max(range.lowerBound, 0)..<min(range.upperBound, points.count)
        let count = clampedRange.count
        guard count > 0 else {
            return []
        }
        guard count > target, target > 2 else {
            return Array(points[clampedRange])
        }

        let bucketCount = max(target / 2, 1)
        let bucketSize = Double(count) / Double(bucketCount)
        
        var output: [GraphRenderedPoint] = []
        output.reserveCapacity(target + 2)
        
        var minVal: Double = 0
        var minIdx: vDSP_Length = 0
        var maxVal: Double = 0
        var maxIdx: vDSP_Length = 0

        yValues.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            
            for bucket in 0..<bucketCount {
                let start = clampedRange.lowerBound + Int(Double(bucket) * bucketSize)
                let end = min(
                    clampedRange.lowerBound + Int(Double(bucket + 1) * bucketSize),
                    clampedRange.upperBound
                )
                let length = end - start
                guard length > 0 else { continue }
                
                vDSP_minviD(base + start, 1, &minVal, &minIdx, vDSP_Length(length))
                vDSP_maxviD(base + start, 1, &maxVal, &maxIdx, vDSP_Length(length))
                
                let minPoint = points[start + Int(minIdx)]
                let maxPoint = points[start + Int(maxIdx)]
                
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
        }

        let firstVisible = points[clampedRange.lowerBound]
        let lastVisible = points[clampedRange.upperBound - 1]
        if output.first != firstVisible {
            output.insert(firstVisible, at: 0)
        }
        if output.last != lastVisible {
            output.append(lastVisible)
        }
        return output.removingConsecutiveDuplicates()
    }
}

func niceAxis(values: [Double]) -> GraphAxis {
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

func linearTicks(min: Double, max: Double, count: Int) -> [Double] {
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

    func removingRedundantStatePoints(enabled: Bool) -> [GraphRenderedPoint] {
        guard enabled else {
            return self
        }

        var output: [GraphRenderedPoint] = []
        output.reserveCapacity(count)
        for item in self {
            if output.last?.display == item.display {
                continue
            }
            output.append(item)
        }
        return output
    }
}
