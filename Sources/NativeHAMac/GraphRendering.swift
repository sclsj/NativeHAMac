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
    let cacheScope: String
    let entityID: String
    let name: String
    let unit: String
    let color: GraphColor
    let history: HAHistorySeries
    /// Requested window start (Unix seconds). Used by the timeline renderer to anchor
    /// the left edge to the actual query window rather than the first event timestamp.
    let windowStart: Double?
    /// Requested window end (Unix seconds). Defaults to now when nil.
    let windowEnd: Double?

    init(
        cacheScope: String = "",
        entityID: String,
        name: String,
        unit: String,
        color: GraphColor,
        history: HAHistorySeries,
        windowStart: Double? = nil,
        windowEnd: Double? = nil
    ) {
        self.cacheScope = cacheScope
        self.entityID = entityID
        self.name = name
        self.unit = unit
        self.color = color
        self.history = history
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
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
    let image: CGImage?
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

struct GraphRenderMetrics: Equatable {
    let inputPointCount: Int
    let preparedPointCount: Int
    let renderedPointCount: Int
    let bitmapByteCount: Int
    let seriesPreparationNanoseconds: UInt64
    let viewportPreparationNanoseconds: UInt64
    let bitmapAllocationNanoseconds: UInt64
    let contextSetupNanoseconds: UInt64
    let backgroundFillNanoseconds: UInt64
    let pathConstructionNanoseconds: UInt64
    let pathStrokeNanoseconds: UInt64
    let imageSnapshotNanoseconds: UInt64
    let totalNanoseconds: UInt64
}

struct GraphPreparedSeriesCacheStatistics: Equatable {
    let fullPreparationCount: Int
    let incrementalPreparationCount: Int
    let cacheHitCount: Int
}

private struct GraphBitmapDrawMetrics {
    let bitmapByteCount: Int
    let allocationNanoseconds: UInt64
    let contextSetupNanoseconds: UInt64
    let backgroundFillNanoseconds: UInt64
    let pathConstructionNanoseconds: UInt64
    let pathStrokeNanoseconds: UInt64
    let imageSnapshotNanoseconds: UInt64
}

private struct GraphBitmapDrawResult {
    let image: CGImage?
    let metrics: GraphBitmapDrawMetrics
}

enum GraphBitmapRenderer {
    static func prepareViewportData(
        inputs: [GraphRenderSeriesInput],
        unit: String,
        size: CGSize,
        scale: CGFloat,
        zoomScale: CGFloat,
        panFraction: Double
    ) -> (result: GraphRenderResult, preparedPointCount: Int, seriesPreparationNanoseconds: UInt64, viewportPreparationNanoseconds: UInt64)? {
        let seriesPreparationStart = graphRenderClock()
        let pointSeries = inputs.compactMap {
            GraphPreparedSeriesCache.shared.series(for: $0, displayUnit: unit)
        }
        let seriesPreparationNanoseconds = graphRenderElapsed(since: seriesPreparationStart)

        guard !pointSeries.isEmpty, !graphRenderIsCancelled() else {
            return nil
        }

        let viewportPreparationStart = graphRenderClock()
        let isStateTimeline = unit.lowercased() == "state"
        let dataEnd = inputs.compactMap(\.windowEnd).max() ?? Date().timeIntervalSince1970
        let dataStart = inputs.compactMap(\.windowStart).min()
        let fullBounds = timeBounds(pointSeries, overrideStart: dataStart, overrideEnd: dataEnd)
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
        let viewportPreparationNanoseconds = graphRenderElapsed(since: viewportPreparationStart)

        let result = GraphRenderResult(
            image: nil,
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
        
        return (result, pointSeries.reduce(0) { $0 + $1.points.count }, seriesPreparationNanoseconds, viewportPreparationNanoseconds)
    }

    static func render(
        inputs: [GraphRenderSeriesInput],
        unit: String,
        size: CGSize,
        scale: CGFloat,
        zoomScale: CGFloat,
        panFraction: Double,
        engine: GraphRenderEngine = AppConfig.graphRenderEngine,
        metrics: ((GraphRenderMetrics) -> Void)? = nil
    ) -> GraphRenderResult? {
        let totalStart = graphRenderClock()
        
        guard let prepared = prepareViewportData(
            inputs: inputs,
            unit: unit,
            size: size,
            scale: scale,
            zoomScale: zoomScale,
            panFraction: panFraction
        ) else {
            return nil
        }
        
        var result = prepared.result
        
        var bitmapByteCount = 0
        var bitmapAllocationNanoseconds: UInt64 = 0
        var contextSetupNanoseconds: UInt64 = 0
        var backgroundFillNanoseconds: UInt64 = 0
        var pathConstructionNanoseconds: UInt64 = 0
        var pathStrokeNanoseconds: UInt64 = 0
        var imageSnapshotNanoseconds: UInt64 = 0

        switch engine {
        case .coreGraphics:
            guard let renderedBitmap = renderPreparedCoreGraphics(result) else {
                return nil
            }
            result = renderedBitmap.result
            let bitmap = renderedBitmap.bitmap

            bitmapByteCount = bitmap.metrics.bitmapByteCount
            bitmapAllocationNanoseconds = bitmap.metrics.allocationNanoseconds
            contextSetupNanoseconds = bitmap.metrics.contextSetupNanoseconds
            backgroundFillNanoseconds = bitmap.metrics.backgroundFillNanoseconds
            pathConstructionNanoseconds = bitmap.metrics.pathConstructionNanoseconds
            pathStrokeNanoseconds = bitmap.metrics.pathStrokeNanoseconds
            imageSnapshotNanoseconds = bitmap.metrics.imageSnapshotNanoseconds
        case .canvas, .metal:
            break
        }

        metrics?(GraphRenderMetrics(
            inputPointCount: inputs.reduce(0) { $0 + $1.history.points.count },
            preparedPointCount: prepared.preparedPointCount,
            renderedPointCount: result.series.reduce(0) {
                $0 + $1.points.count + $1.timelineSegments.count
            },
            bitmapByteCount: bitmapByteCount,
            seriesPreparationNanoseconds: prepared.seriesPreparationNanoseconds,
            viewportPreparationNanoseconds: prepared.viewportPreparationNanoseconds,
            bitmapAllocationNanoseconds: bitmapAllocationNanoseconds,
            contextSetupNanoseconds: contextSetupNanoseconds,
            backgroundFillNanoseconds: backgroundFillNanoseconds,
            pathConstructionNanoseconds: pathConstructionNanoseconds,
            pathStrokeNanoseconds: pathStrokeNanoseconds,
            imageSnapshotNanoseconds: imageSnapshotNanoseconds,
            totalNanoseconds: graphRenderElapsed(since: totalStart)
        ))
        
        return result
    }

    static func resetPreparedSeriesCache() {
        GraphPreparedSeriesCache.shared.reset()
    }

    static func preparedSeriesCacheStatistics() -> GraphPreparedSeriesCacheStatistics {
        GraphPreparedSeriesCache.shared.statistics()
    }

    static func preparedSeriesForTesting(
        _ input: GraphRenderSeriesInput,
        displayUnit: String
    ) -> GraphRenderedSeries? {
        GraphPreparedSeriesCache.shared.series(for: input, displayUnit: displayUnit)
    }

    /// Renderer-only seam used by the engine benchmark after common viewport
    /// preparation has completed. Completion means the CGImage snapshot exists.
    static func renderPreparedCoreGraphicsForBenchmark(
        _ prepared: GraphRenderResult
    ) -> GraphRenderResult? {
        renderPreparedCoreGraphics(prepared)?.result
    }

    private static func renderPreparedCoreGraphics(
        _ prepared: GraphRenderResult
    ) -> (result: GraphRenderResult, bitmap: GraphBitmapDrawResult)? {
        let bitmap: GraphBitmapDrawResult?
        if prepared.unit.lowercased() == "state" {
            bitmap = drawTimelineBitmap(
                series: prepared.series,
                size: prepared.size,
                scale: prepared.scale,
                plotRect: prepared.plotRect,
                visibleStart: prepared.visibleStart,
                visibleEnd: prepared.visibleEnd
            )
        } else {
            bitmap = drawBitmap(
                series: prepared.series,
                size: prepared.size,
                scale: prepared.scale,
                plotRect: prepared.plotRect,
                axis: prepared.axis,
                xTicks: prepared.xTicks,
                visibleStart: prepared.visibleStart,
                visibleEnd: prepared.visibleEnd
            )
        }
        guard let bitmap = bitmap else {
            return nil
        }

        return (
            GraphRenderResult(
                image: bitmap.image,
                size: prepared.size,
                scale: prepared.scale,
                plotRect: prepared.plotRect,
                unit: prepared.unit,
                series: prepared.series,
                axis: prepared.axis,
                xTicks: prepared.xTicks,
                fullStart: prepared.fullStart,
                fullEnd: prepared.fullEnd,
                visibleStart: prepared.visibleStart,
                visibleEnd: prepared.visibleEnd,
                zoomScale: prepared.zoomScale,
                panFraction: prepared.panFraction
            ),
            bitmap
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
    ) -> GraphBitmapDrawResult? {
        let width = max(Int(size.width * scale), 1)
        let height = max(Int(size.height * scale), 1)
        let bytesPerRow = width * 4
        let allocationStart = graphRenderClock()
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let allocationNanoseconds = graphRenderElapsed(since: allocationStart)

        return data.withUnsafeMutableBytes { pointer in
            guard !graphRenderIsCancelled() else {
                return nil
            }

            let contextSetupStart = graphRenderClock()
            let colorSpace = CGColorSpaceCreateDeviceRGB()
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
            context.setLineJoin(.round)
            context.setLineCap(.round)
            let contextSetupNanoseconds = graphRenderElapsed(since: contextSetupStart)

            let backgroundFillStart = graphRenderClock()
            context.setFillColor(CGColor(red: 0.055, green: 0.06, blue: 0.06, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let backgroundFillNanoseconds = graphRenderElapsed(since: backgroundFillStart)

            var pathConstructionNanoseconds: UInt64 = 0
            var pathStrokeNanoseconds: UInt64 = 0
            for item in series {
                guard !graphRenderIsCancelled() else {
                    return nil
                }

                let pathConstructionStart = graphRenderClock()
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
                pathConstructionNanoseconds += graphRenderElapsed(since: pathConstructionStart)

                let pathStrokeStart = graphRenderClock()
                context.setStrokeColor(item.color.cgColor)
                context.setLineWidth(2)
                context.addPath(path)
                context.strokePath()
                pathStrokeNanoseconds += graphRenderElapsed(since: pathStrokeStart)
            }

            guard !graphRenderIsCancelled() else {
                return nil
            }
            let imageSnapshotStart = graphRenderClock()
            guard let image = context.makeImage() else {
                return nil
            }
            let imageSnapshotNanoseconds = graphRenderElapsed(since: imageSnapshotStart)
            return GraphBitmapDrawResult(
                image: image,
                metrics: GraphBitmapDrawMetrics(
                    bitmapByteCount: bytesPerRow * height,
                    allocationNanoseconds: allocationNanoseconds,
                    contextSetupNanoseconds: contextSetupNanoseconds,
                    backgroundFillNanoseconds: backgroundFillNanoseconds,
                    pathConstructionNanoseconds: pathConstructionNanoseconds,
                    pathStrokeNanoseconds: pathStrokeNanoseconds,
                    imageSnapshotNanoseconds: imageSnapshotNanoseconds
                )
            )
        }
    }

    private static func drawTimelineBitmap(
        series: [GraphRenderedSeries],
        size: CGSize,
        scale: CGFloat,
        plotRect: CGRect,
        visibleStart: Double,
        visibleEnd: Double
    ) -> GraphBitmapDrawResult? {
        let width = max(Int(size.width * scale), 1)
        let height = max(Int(size.height * scale), 1)
        let bytesPerRow = width * 4
        let allocationStart = graphRenderClock()
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let allocationNanoseconds = graphRenderElapsed(since: allocationStart)

        return data.withUnsafeMutableBytes { pointer in
            guard !graphRenderIsCancelled() else {
                return nil
            }

            let contextSetupStart = graphRenderClock()
            let colorSpace = CGColorSpaceCreateDeviceRGB()
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
            let contextSetupNanoseconds = graphRenderElapsed(since: contextSetupStart)

            let backgroundFillStart = graphRenderClock()
            context.setFillColor(CGColor(red: 0.055, green: 0.06, blue: 0.06, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let backgroundFillNanoseconds = graphRenderElapsed(since: backgroundFillStart)

            let maxRowHeight: CGFloat = 24
            let rowHeight = min(plotRect.height / CGFloat(max(series.count, 1)), maxRowHeight)
            let totalHeight = rowHeight * CGFloat(series.count)
            let startY = plotRect.minY + (plotRect.height - totalHeight) / 2

            var pathConstructionNanoseconds: UInt64 = 0
            var pathStrokeNanoseconds: UInt64 = 0
            for (index, item) in series.enumerated() {
                guard !graphRenderIsCancelled() else {
                    return nil
                }
                let yOffset = startY + CGFloat(index) * rowHeight

                for segment in item.timelineSegments {
                    let pathConstructionStart = graphRenderClock()
                    let startX = max(
                        plotRect.minX,
                        xPosition(segment.clippedStart, visibleStart: visibleStart, visibleEnd: visibleEnd, plotRect: plotRect)
                    )
                    let endX = min(
                        plotRect.maxX,
                        xPosition(segment.clippedEnd, visibleStart: visibleStart, visibleEnd: visibleEnd, plotRect: plotRect)
                    )
                    let blockWidth = endX - startX
                    pathConstructionNanoseconds += graphRenderElapsed(since: pathConstructionStart)
                    if blockWidth <= 0 { continue }

                    let pathStrokeStart = graphRenderClock()
                    let blockRect = CGRect(x: startX, y: yOffset + 2, width: blockWidth, height: max(rowHeight - 4, 1))
                    context.setFillColor(timelineColor(for: segment.state, entityID: item.entityID).cgColor)
                    context.fill(blockRect)
                    pathStrokeNanoseconds += graphRenderElapsed(since: pathStrokeStart)
                }
            }

            guard !graphRenderIsCancelled() else {
                return nil
            }
            let imageSnapshotStart = graphRenderClock()
            guard let image = context.makeImage() else {
                return nil
            }
            let imageSnapshotNanoseconds = graphRenderElapsed(since: imageSnapshotStart)
            return GraphBitmapDrawResult(
                image: image,
                metrics: GraphBitmapDrawMetrics(
                    bitmapByteCount: bytesPerRow * height,
                    allocationNanoseconds: allocationNanoseconds,
                    contextSetupNanoseconds: contextSetupNanoseconds,
                    backgroundFillNanoseconds: backgroundFillNanoseconds,
                    pathConstructionNanoseconds: pathConstructionNanoseconds,
                    pathStrokeNanoseconds: pathStrokeNanoseconds,
                    imageSnapshotNanoseconds: imageSnapshotNanoseconds
                )
            )
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
    overrideStart: Double? = nil,
    overrideEnd: Double? = nil
) -> (start: Double, end: Double) {
    let start = overrideStart ?? series.compactMap { $0.points.first?.t }.min() ?? 0
    let end   = overrideEnd   ?? series.compactMap { $0.points.last?.t }.max()  ?? 1
    return (start, end)
}

private final class GraphPreparedSeriesCache {
    static let shared = GraphPreparedSeriesCache()

    private let lock = NSLock()
    private var storage: [String: GraphPreparedCacheEntry] = [:]
    private var insertionOrder: [String] = []
    private let limit = 96
    private var fullPreparationCount = 0
    private var incrementalPreparationCount = 0
    private var cacheHitCount = 0

    func reset() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
        fullPreparationCount = 0
        incrementalPreparationCount = 0
        cacheHitCount = 0
        lock.unlock()
    }

    func statistics() -> GraphPreparedSeriesCacheStatistics {
        lock.lock()
        defer { lock.unlock() }
        return GraphPreparedSeriesCacheStatistics(
            fullPreparationCount: fullPreparationCount,
            incrementalPreparationCount: incrementalPreparationCount,
            cacheHitCount: cacheHitCount
        )
    }

    func series(for input: GraphRenderSeriesInput, displayUnit: String) -> GraphRenderedSeries? {
        let key = stableKey(for: input, displayUnit: displayUnit)
        let fingerprint = sourceFingerprint(for: input.history)

        let isMainThread = Thread.isMainThread
        let requestStart = graphRenderClock()
        
        lock.lock()
        let lockWaitNanoseconds = graphRenderElapsed(since: requestStart)
        if lockWaitNanoseconds > 5_000_000 {
            print("[LAG-DEBUG] [\(isMainThread ? "MAIN" : "BG")] lock.lock() waited \(Double(lockWaitNanoseconds) / 1_000_000)ms for \(input.entityID)")
        }

        if let cached = storage[key] {
            if cached.matches(fingerprint) {
                cacheHitCount += 1
                lock.unlock()
                return cached.series
            }
            lock.unlock()

            let incStart = graphRenderClock()
            if let updated = incrementallyUpdate(
                cached,
                input: input,
                displayUnit: displayUnit,
                fingerprint: fingerprint
            ) {
                let incElapsed = graphRenderElapsed(since: incStart)
                if incElapsed > 5_000_000 {
                    print("[LAG-DEBUG] [\(isMainThread ? "MAIN" : "BG")] incrementallyUpdate took \(Double(incElapsed) / 1_000_000)ms for \(input.entityID)")
                }
                lock.lock()
                incrementalPreparationCount += 1
                lock.unlock()
                store(updated, key: key)
                return updated.series
            } else {
                print("[LAG-DEBUG] [\(isMainThread ? "MAIN" : "BG")] incrementallyUpdate FAILED for \(input.entityID) (points: \(input.history.points.count))")
            }
        } else {
            lock.unlock()
        }

        let fullStart = graphRenderClock()
        guard let prepared = prepareFull(input: input, displayUnit: displayUnit, fingerprint: fingerprint) else {
            return nil
        }
        let fullElapsed = graphRenderElapsed(since: fullStart)
        print("[LAG-DEBUG] [\(isMainThread ? "MAIN" : "BG")] prepareFull took \(Double(fullElapsed) / 1_000_000)ms for \(input.entityID)")

        lock.lock()
        fullPreparationCount += 1
        lock.unlock()
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
        var points: [GraphRenderedPoint] = []
        points.reserveCapacity(input.history.points.count)
        var yValues: [Double] = []
        if !isStateTimeline {
            yValues.reserveCapacity(input.history.points.count)
        }
        var isTimestampSorted = true
        var isOneToOneStrictlyIncreasingNumericSource = !isStateTimeline
        var previousTimestamp: Double?

        for (index, point) in input.history.points.enumerated() {
            if index % 1_024 == 0, graphRenderIsCancelled() {
                return nil
            }
            guard let timestamp = parser.timestamp(from: point) else {
                isOneToOneStrictlyIncreasingNumericSource = false
                continue
            }
            let value = numericValue(point.state)
            if value == nil && !isStateTimeline {
                isOneToOneStrictlyIncreasingNumericSource = false
                continue
            }

            if let previousTimestamp = previousTimestamp, timestamp < previousTimestamp {
                isTimestampSorted = false
            }
            if let previousTimestamp = previousTimestamp, timestamp < previousTimestamp {
                isOneToOneStrictlyIncreasingNumericSource = false
            }
            previousTimestamp = timestamp
            points.append(GraphRenderedPoint(
                t: timestamp,
                y: value ?? 0,
                display: displayValue(point.state, unit: displayUnit)
            ))
            if !isStateTimeline {
                yValues.append(value ?? 0)
            }
        }

        if !isTimestampSorted {
            points.sort { $0.t < $1.t }
            if !isStateTimeline {
                yValues = points.map(\.y)
            }
        }
        points = points.removingRedundantStatePoints(enabled: isStateTimeline)

        guard !points.isEmpty else {
            return nil
        }

        return GraphPreparedCacheEntry(
            fingerprint: fingerprint,
            isOneToOneStrictlyIncreasingNumericSource:
                isOneToOneStrictlyIncreasingNumericSource && points.count == input.history.points.count,
            series: GraphRenderedSeries(
                entityID: input.entityID,
                name: input.name,
                unit: input.unit,
                color: input.color,
                points: points,
                minMaxCache: isStateTimeline ? nil : GraphMinMaxCache(
                    points: points,
                    yValues: yValues
                )
            )
        )
    }

    private func incrementallyUpdate(
        _ cached: GraphPreparedCacheEntry,
        input: GraphRenderSeriesInput,
        displayUnit: String,
        fingerprint: GraphSourceFingerprint
    ) -> GraphPreparedCacheEntry? {
        let isStateTimeline = displayUnit.lowercased() == "state"
        guard !isStateTimeline else {
            print("[LAG-DEBUG] incrementallyUpdate failed: isStateTimeline")
            return nil
        }
        guard fingerprint.count > 0 else {
            print("[LAG-DEBUG] incrementallyUpdate failed: fingerprint.count == 0")
            return nil
        }
        guard !input.history.points.isEmpty else {
            print("[LAG-DEBUG] incrementallyUpdate failed: input points empty")
            return nil
        }
        guard !cached.series.points.isEmpty else {
            print("[LAG-DEBUG] incrementallyUpdate failed: cached series empty")
            return nil
        }

        let parser = GraphDateParser()
        var points: [GraphRenderedPoint] = []
        points.reserveCapacity(input.history.points.count)
        var yValues: [Double] = []
        yValues.reserveCapacity(input.history.points.count)

        func appendFreshSource(_ range: Range<Int>) -> Bool {
            for (offset, sourceIndex) in range.enumerated() {
                if offset % 1_024 == 0, graphRenderIsCancelled() {
                    return false
                }
                let source = input.history.points[sourceIndex]
                let timestampOpt = parser.timestamp(from: source)
                guard let timestamp = timestampOpt else {
                    print("[LAG-DEBUG] incrementallyUpdate appendFreshSource failed: timestamp nil")
                    return false
                }
                guard let value = numericValue(source.state) else {
                    print("[LAG-DEBUG] incrementallyUpdate appendFreshSource failed: value nil")
                    return false
                }
                guard points.last.map({ timestamp >= $0.t }) ?? true else {
                    print("[LAG-DEBUG] incrementallyUpdate appendFreshSource failed: timestamp \(timestamp) < last \(points.last!.t)")
                    return false
                }
                points.append(GraphRenderedPoint(
                    t: timestamp,
                    y: value,
                    display: displayValue(source.state, unit: displayUnit)
                ))
                yValues.append(value)
            }
            return true
        }

        // Use timestamp bounds to find the overlapping region, ignoring strict lineage indices
        // to gracefully handle skipped revisions from SwiftUI coalescing.
        var overlapStartTime: Double? = nil
        var firstValidNewIndex = 0
        for i in 0..<input.history.points.count {
            let pt = input.history.points[i]
            if let ts = parser.timestamp(from: pt), numericValue(pt.state) != nil {
                overlapStartTime = ts
                firstValidNewIndex = i
                break
            }
        }
        
        guard let startTime = overlapStartTime else { return nil }
        
        // Find the last timestamp in the cache
        let lastCachedPoint = cached.series.points.last!
        
        // If the new raw data starts AFTER the cache ends, there is absolutely no overlap.
        // We cannot use the cache at all, so we must fall back to prepareFull.
        guard startTime <= lastCachedPoint.t else {
            print("[LAG-DEBUG] incrementallyUpdate failed: no overlap (startTime \(startTime) > cache.last \(lastCachedPoint.t))")
            return nil
        }
        
        let cacheStartIndex = lowerBound(in: cached.series.points, timestamp: startTime)
        
        // Find where the new suffix begins in the raw input
        var suffixStartRawIndex = input.history.points.count
        for i in (0..<input.history.points.count).reversed() {
            let pt = input.history.points[i]
            if let ts = parser.timestamp(from: pt), numericValue(pt.state) != nil {
                if ts <= lastCachedPoint.t {
                    suffixStartRawIndex = i + 1
                    break
                }
            }
        }
        
        // Parse the fresh prefix (if any)
        guard appendFreshSource(0..<firstValidNewIndex) else {
            return nil
        }
        
        // Append the overlapping cache slice
        let cachedOverlap = cached.series.points[cacheStartIndex...]
        if let prefixLast = points.last, let overlapFirst = cachedOverlap.first,
           overlapFirst.t < prefixLast.t {
            print("[LAG-DEBUG] incrementallyUpdate failed: overlap \(overlapFirst.t) < prefix \(prefixLast.t)")
            return nil
        }
        points.append(contentsOf: cachedOverlap)
        
        if let cachedYValues = cached.series.minMaxCache?.yValues, cacheStartIndex < cachedYValues.count {
            yValues.append(contentsOf: cachedYValues[cacheStartIndex...])
        }
        
        // Parse the fresh suffix (if any)
        guard !graphRenderIsCancelled() else {
            print("[LAG-DEBUG] incrementallyUpdate failed: cancelled")
            return nil
        }
        guard appendFreshSource(suffixStartRawIndex..<input.history.points.count) else {
            print("[LAG-DEBUG] incrementallyUpdate failed: appendFreshSource suffix failed")
            return nil
        }
        guard yValues.count == points.count else {
            print("[LAG-DEBUG] incrementallyUpdate failed: yValues count mismatch")
            return nil
        }
        guard !points.isEmpty else {
            print("[LAG-DEBUG] incrementallyUpdate failed: points empty")
            return nil
        }

        return GraphPreparedCacheEntry(
            fingerprint: fingerprint,
            isOneToOneStrictlyIncreasingNumericSource: true,
            series: GraphRenderedSeries(
                entityID: input.entityID,
                name: input.name,
                unit: input.unit,
                color: input.color,
                points: points,
                minMaxCache: GraphMinMaxCache(points: points, yValues: yValues)
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
            input.cacheScope,
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
            lastTimestamp: history.points.last.flatMap(sourceTimestamp),
            contentRevision: history.contentRevision
        )
    }
}

private func graphRenderClock() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

private func graphRenderElapsed(since start: UInt64) -> UInt64 {
    DispatchTime.now().uptimeNanoseconds - start
}

private func graphRenderIsCancelled() -> Bool {
    withUnsafeCurrentTask { $0?.isCancelled ?? false }
}

private struct GraphPreparedCacheEntry {
    let fingerprint: GraphSourceFingerprint
    /// Full preparation records this once so the numeric rolling fast path can
    /// consume trusted projection lineage by source index without reparsing the
    /// cached source.
    let isOneToOneStrictlyIncreasingNumericSource: Bool
    let series: GraphRenderedSeries

    func matches(_ other: GraphSourceFingerprint) -> Bool {
        fingerprint == other
    }
}

private struct GraphSourceFingerprint: Equatable {
    let count: Int
    let firstTimestamp: String?
    let lastTimestamp: String?
    let contentRevision: UInt64
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
    fileprivate let yValues: [Double]

    init(points: [GraphRenderedPoint]) {
        self.points = points
        self.yValues = points.map { $0.y }
    }

    fileprivate init(points: [GraphRenderedPoint], yValues: [Double]) {
        precondition(points.count == yValues.count)
        self.points = points
        self.yValues = yValues
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
