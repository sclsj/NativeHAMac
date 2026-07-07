import CoreGraphics
import Foundation
import NativeHACore

@main
enum GraphPyramidBench {
    static func main() async throws {
        let token = try String(
            contentsOfFile: "/Users/jin/Documents/Computer/ha_apikey.txt",
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let client = HomeAssistantRESTClient(
            configuration: HomeAssistantConfiguration(
                baseURL: URL(string: "http://joyj.me:8123")!,
                accessToken: token,
                timeout: 30
            )
        )

        let entityIDs = [
            "sensor.sps30_pm4_0",
            "sensor.sps30_pm10",
            "sensor.sps30_pm2_5",
            "sensor.sps30_pm1_0",
        ]

        print("Fetching 12h SPS30 history...")
        let fetchStart = now()
        let history = try await client.fetchHistory(entityIDs: entityIDs, hoursToShow: 12)
        let series = history.compactMap(BenchSeries.init(history:))
        let fetchElapsed = now() - fetchStart
        let totalPoints = series.map(\.points.count).reduce(0, +)
        print("- \(series.count) series, \(totalPoints) points fetched/decoded in \(format(fetchElapsed)) ms")

        guard !series.isEmpty else {
            print("No numeric SPS30 series found.")
            return
        }

        let target = targetPoints(plotWidth: 442, seriesCount: series.count)
        let bounds = timeBounds(series: series)
        let span = max(bounds.max - bounds.min, 1)
        let scenarios = [
            Scenario(name: "full 12h", start: bounds.min, end: bounds.max),
            Scenario(name: "first 3h", start: bounds.min, end: bounds.min + span * 0.25),
            Scenario(name: "middle 3h", start: bounds.min + span * 0.375, end: bounds.min + span * 0.625),
            Scenario(name: "last 3h", start: bounds.max - span * 0.25, end: bounds.max),
            Scenario(name: "last 1h", start: bounds.max - span / 12, end: bounds.max),
            Scenario(name: "last 20m", start: bounds.max - span / 36, end: bounds.max),
        ]

        let build = benchmark(iterations: 20) {
            _ = series.map { BenchMinMaxCache(points: $0.points) }
        }
        let caches = series.map { BenchMinMaxCache(points: $0.points) }
        print("- cache build median: \(format(build.medianMS)) ms")
        print("- target points per rendered series: \(target)")

        print("")
        print("Pixel equivalence against full-scan min/max:")
        print("| window | raw pts | drawn pts | points equal | pixels equal |")
        print("|---|---:|---:|---:|---:|")

        for scenario in scenarios {
            let baseline = prepareChart(
                series: series,
                caches: caches,
                scenario: scenario,
                target: target,
                method: .fullScan
            )
            let optimized = prepareChart(
                series: series,
                caches: caches,
                scenario: scenario,
                target: target,
                method: .cache
            )

            let pointsEqual = zip(baseline.series, optimized.series).allSatisfy { $0.points == $1.points }
            let pixelsEqual = renderPixels(baseline) == renderPixels(optimized)
            let rawCount = visiblePointCount(series: series, scenario: scenario)
            let drawnCount = optimized.series.map(\.points.count).reduce(0, +)
            print("| \(scenario.name) | \(rawCount) | \(drawnCount) | \(pointsEqual ? "yes" : "no") | \(pixelsEqual ? "yes" : "no") |")
        }

        print("")
        print("Downsample only, median ms:")
        print("| window | full scan | cached min/max | speedup |")
        print("|---|---:|---:|---:|")

        for scenario in scenarios {
            let baseline = benchmark(iterations: 80) {
                _ = downsampleAll(
                    series: series,
                    caches: caches,
                    scenario: scenario,
                    target: target,
                    method: .fullScan
                )
            }
            let optimized = benchmark(iterations: 240) {
                _ = downsampleAll(
                    series: series,
                    caches: caches,
                    scenario: scenario,
                    target: target,
                    method: .cache
                )
            }
            let speedup = baseline.medianMS / max(optimized.medianMS, 0.0001)
            print("| \(scenario.name) | \(format(baseline.medianMS)) | \(format(optimized.medianMS)) | \(format(speedup))x |")
        }

        print("")
        print("Full bitmap pipeline, median ms:")
        print("| window | full scan | cached min/max | speedup |")
        print("|---|---:|---:|---:|")

        for scenario in scenarios {
            let baseline = benchmark(iterations: 30) {
                let chart = prepareChart(
                    series: series,
                    caches: caches,
                    scenario: scenario,
                    target: target,
                    method: .fullScan
                )
                _ = renderPixels(chart)
            }
            let optimized = benchmark(iterations: 120) {
                let chart = prepareChart(
                    series: series,
                    caches: caches,
                    scenario: scenario,
                    target: target,
                    method: .cache
                )
                _ = renderPixels(chart)
            }
            let speedup = baseline.medianMS / max(optimized.medianMS, 0.0001)
            print("| \(scenario.name) | \(format(baseline.medianMS)) | \(format(optimized.medianMS)) | \(format(speedup))x |")
        }
    }
}

private enum DownsampleMethod {
    case fullScan
    case cache
}

private struct Scenario {
    let name: String
    let start: Double
    let end: Double
}

private struct BenchSeries {
    let entityID: String
    let points: [BenchPoint]

    init?(history: HAHistorySeries) {
        let parser = DateParser()
        let points = history.points.compactMap { point -> BenchPoint? in
            guard
                let timestamp = parser.timestamp(from: point),
                let value = numericValue(point.state)
            else {
                return nil
            }
            return BenchPoint(t: timestamp, y: value)
        }
        .sorted { $0.t < $1.t }

        guard !points.isEmpty else {
            return nil
        }

        self.entityID = history.entityID
        self.points = points
    }

    init(entityID: String, points: [BenchPoint]) {
        self.entityID = entityID
        self.points = points
    }
}

private struct BenchPoint: Equatable {
    let t: Double
    let y: Double
}

private final class DateParser {
    private let normal = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func timestamp(from point: HAHistoryPoint) -> Double? {
        if let value = point.lastUpdated, let date = parse(value) {
            return date.timeIntervalSince1970
        }
        if let value = point.lastChanged, let date = parse(value) {
            return date.timeIntervalSince1970
        }
        return nil
    }

    private func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? normal.date(from: value)
    }
}

private struct BenchMinMaxCache {
    private static let blockSize = 32

    let points: [BenchPoint]
    private let levels: [[BenchBucket]]

    init(points: [BenchPoint]) {
        self.points = points

        var base: [BenchBucket] = []
        base.reserveCapacity((points.count + Self.blockSize - 1) / Self.blockSize)
        var blockStart = 0
        while blockStart < points.count {
            let blockEnd = min(blockStart + Self.blockSize, points.count)
            if let bucket = Self.scannedBucket(points: points, in: blockStart..<blockEnd) {
                base.append(bucket)
            }
            blockStart += Self.blockSize
        }

        var levels: [[BenchBucket]] = base.isEmpty ? [] : [base]
        var span = 2
        while span <= base.count {
            let halfSpan = span / 2
            var current: [BenchBucket] = []
            current.reserveCapacity(base.count - span + 1)

            let previous = levels[levels.count - 1]
            for index in 0...(base.count - span) {
                current.append(
                    BenchBucket.combining(
                        previous[index],
                        previous[index + halfSpan],
                        points: points
                    )
                )
            }

            levels.append(current)
            span *= 2
        }

        self.levels = levels
    }

    func downsample(in range: Range<Int>, target: Int) -> [BenchPoint] {
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
        if bucketSize <= Double(Self.blockSize * 2) {
            return minMaxDownsample(points, in: clampedRange, target: target)
        }

        var output: [BenchPoint] = []
        output.reserveCapacity(target + 2)

        for bucket in 0..<bucketCount {
            let start = clampedRange.lowerBound + Int(Double(bucket) * bucketSize)
            let end = min(
                clampedRange.lowerBound + Int(Double(bucket + 1) * bucketSize),
                clampedRange.upperBound
            )
            guard start < end, let minMax = minMaxIndices(in: start..<end) else {
                continue
            }

            let minPoint = points[minMax.minIndex]
            let maxPoint = points[minMax.maxIndex]
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

    private func minMaxIndices(in range: Range<Int>) -> BenchBucket? {
        let lower = max(range.lowerBound, 0)
        let upper = min(range.upperBound, points.count)
        guard lower < upper else {
            return nil
        }

        var result: BenchBucket?

        func include(_ bucket: BenchBucket?) {
            guard let bucket = bucket else {
                return
            }
            if let current = result {
                result = BenchBucket.combining(current, bucket, points: points)
            } else {
                result = bucket
            }
        }

        let fullStart = min(roundUpToBlock(lower), upper)
        include(Self.scannedBucket(points: points, in: lower..<fullStart))

        guard fullStart < upper else {
            return result
        }

        let fullBlockStart = fullStart / Self.blockSize
        let fullBlockEnd = upper / Self.blockSize
        var cursor = fullStart
        if fullBlockStart < fullBlockEnd {
            include(blockMinMax(in: fullBlockStart..<fullBlockEnd))
            cursor = fullBlockEnd * Self.blockSize
        }

        include(Self.scannedBucket(points: points, in: cursor..<upper))
        return result
    }

    private func blockMinMax(in blocks: Range<Int>) -> BenchBucket? {
        let count = blocks.count
        guard count > 0, !levels.isEmpty else {
            return nil
        }

        let level = Self.floorLog2(count)
        let span = 1 << level
        let left = levels[level][blocks.lowerBound]
        let right = levels[level][blocks.upperBound - span]
        return BenchBucket.combining(left, right, points: points)
    }

    private func roundUpToBlock(_ index: Int) -> Int {
        ((index + Self.blockSize - 1) / Self.blockSize) * Self.blockSize
    }

    private static func floorLog2(_ value: Int) -> Int {
        var value = value
        var result = 0
        while value > 1 {
            value >>= 1
            result += 1
        }
        return result
    }

    private static func scannedBucket(points: [BenchPoint], in range: Range<Int>) -> BenchBucket? {
        guard let first = range.first else {
            return nil
        }

        var minIndex = first
        var maxIndex = first
        for index in range.dropFirst() {
            if points[index].y < points[minIndex].y {
                minIndex = index
            }
            if points[index].y > points[maxIndex].y {
                maxIndex = index
            }
        }

        return BenchBucket(minIndex: minIndex, maxIndex: maxIndex)
    }
}

private struct BenchBucket {
    let minIndex: Int
    let maxIndex: Int

    static func combining(_ first: BenchBucket, _ second: BenchBucket, points: [BenchPoint]) -> BenchBucket {
        var minIndex = first.minIndex
        var maxIndex = first.maxIndex

        if points[second.minIndex].y < points[minIndex].y {
            minIndex = second.minIndex
        }
        if points[second.maxIndex].y > points[maxIndex].y {
            maxIndex = second.maxIndex
        }

        return BenchBucket(minIndex: minIndex, maxIndex: maxIndex)
    }
}

private struct Chart {
    let width: Int
    let height: Int
    let plot: CGRect
    let axis: Axis
    let visibleStart: Double
    let visibleEnd: Double
    let series: [BenchSeries]
}

private struct Axis {
    let min: Double
    let max: Double
    let ticks: [Double]
}

private func prepareChart(
    series: [BenchSeries],
    caches: [BenchMinMaxCache],
    scenario: Scenario,
    target: Int,
    method: DownsampleMethod
) -> Chart {
    let renderedSeries = zip(series, caches).map { item, cache -> BenchSeries in
        let range = visibleRange(in: item.points, start: scenario.start, end: scenario.end)
        let points: [BenchPoint]
        switch method {
        case .fullScan:
            points = minMaxDownsample(item.points, in: range, target: target)
        case .cache:
            points = cache.downsample(in: range, target: target)
        }
        return BenchSeries(entityID: item.entityID, points: points)
    }
    .filter { !$0.points.isEmpty }

    let axis = niceAxis(values: renderedSeries.flatMap { $0.points.map(\.y) })
    return Chart(
        width: 496,
        height: 220,
        plot: CGRect(x: 42, y: 18, width: 442, height: 176),
        axis: axis,
        visibleStart: scenario.start,
        visibleEnd: scenario.end,
        series: renderedSeries
    )
}

private func downsampleAll(
    series: [BenchSeries],
    caches: [BenchMinMaxCache],
    scenario: Scenario,
    target: Int,
    method: DownsampleMethod
) -> [BenchSeries] {
    zip(series, caches).map { item, cache -> BenchSeries in
        let range = visibleRange(in: item.points, start: scenario.start, end: scenario.end)
        let points: [BenchPoint]
        switch method {
        case .fullScan:
            points = minMaxDownsample(item.points, in: range, target: target)
        case .cache:
            points = cache.downsample(in: range, target: target)
        }
        return BenchSeries(entityID: item.entityID, points: points)
    }
}

private func minMaxDownsample(
    _ points: [BenchPoint],
    in range: Range<Int>,
    target: Int
) -> [BenchPoint] {
    let count = range.count
    guard count > 0 else {
        return []
    }
    guard count > target, target > 2 else {
        return Array(points[range])
    }

    let bucketCount = max(target / 2, 1)
    let bucketSize = Double(count) / Double(bucketCount)
    var output: [BenchPoint] = []
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

private func renderPixels(_ chart: Chart) -> [UInt8] {
    let bytesPerRow = chart.width * 4
    var data = [UInt8](repeating: 0, count: bytesPerRow * chart.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    data.withUnsafeMutableBytes { pointer in
        guard let context = CGContext(
            data: pointer.baseAddress,
            width: chart.width,
            height: chart.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }

        context.setShouldAntialias(false)
        context.setFillColor(CGColor(red: 0.055, green: 0.06, blue: 0.06, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: chart.width, height: chart.height))

        context.setStrokeColor(CGColor(gray: 1, alpha: 0.09))
        context.setLineWidth(1)
        for tick in chart.axis.ticks {
            let y = yPosition(tick, axis: chart.axis, plot: chart.plot)
            context.move(to: CGPoint(x: chart.plot.minX, y: y))
            context.addLine(to: CGPoint(x: chart.plot.maxX, y: y))
        }
        for index in 0..<5 {
            let t = chart.visibleStart + (chart.visibleEnd - chart.visibleStart) * Double(index) / 4
            let x = xPosition(t, visibleStart: chart.visibleStart, visibleEnd: chart.visibleEnd, plot: chart.plot)
            context.move(to: CGPoint(x: x, y: chart.plot.minY))
            context.addLine(to: CGPoint(x: x, y: chart.plot.maxY))
        }
        context.strokePath()

        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineWidth(2)
        for (index, item) in chart.series.enumerated() {
            context.setStrokeColor(color(index: index))
            let path = CGMutablePath()
            for (pointIndex, point) in item.points.enumerated() {
                let mapped = CGPoint(
                    x: xPosition(point.t, visibleStart: chart.visibleStart, visibleEnd: chart.visibleEnd, plot: chart.plot),
                    y: yPosition(point.y, axis: chart.axis, plot: chart.plot)
                )
                if pointIndex == 0 {
                    path.move(to: mapped)
                } else {
                    path.addLine(to: mapped)
                }
            }
            context.addPath(path)
            context.strokePath()
        }
    }

    return data
}

private func visibleRange(in points: [BenchPoint], start: Double, end: Double) -> Range<Int> {
    guard !points.isEmpty else {
        return 0..<0
    }

    let lower = lowerBound(in: points, timestamp: start)
    let upper = upperBound(in: points, timestamp: end)
    return min(lower, points.count)..<min(max(upper, lower), points.count)
}

private func lowerBound(in points: [BenchPoint], timestamp: Double) -> Int {
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

private func upperBound(in points: [BenchPoint], timestamp: Double) -> Int {
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

private func niceAxis(values: [Double]) -> Axis {
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

    return Axis(min: axisMin, max: axisMax, ticks: ticks)
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

private func xPosition(
    _ timestamp: Double,
    visibleStart: Double,
    visibleEnd: Double,
    plot: CGRect
) -> CGFloat {
    let interval = max(visibleEnd - visibleStart, 1)
    return plot.minX + plot.width * CGFloat((timestamp - visibleStart) / interval)
}

private func yPosition(_ value: Double, axis: Axis, plot: CGRect) -> CGFloat {
    let range = max(axis.max - axis.min, 0.0001)
    return plot.maxY - plot.height * CGFloat((value - axis.min) / range)
}

private func color(index: Int) -> CGColor {
    let colors: [(CGFloat, CGFloat, CGFloat)] = [
        (0.26, 0.47, 0.95),
        (0.93, 0.66, 0.22),
        (0.40, 0.86, 0.82),
        (0.95, 0.32, 0.50),
    ]
    let value = colors[index % colors.count]
    return CGColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
}

private func visiblePointCount(series: [BenchSeries], scenario: Scenario) -> Int {
    series
        .map { visibleRange(in: $0.points, start: scenario.start, end: scenario.end).count }
        .reduce(0, +)
}

private func targetPoints(plotWidth: Int, seriesCount: Int) -> Int {
    max(plotWidth * 2 / max(seriesCount, 1), 80)
}

private func timeBounds(series: [BenchSeries]) -> (min: Double, max: Double) {
    let points = series.flatMap(\.points)
    return (points.map(\.t).min() ?? 0, points.map(\.t).max() ?? 1)
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

private struct BenchmarkResult {
    let medianMS: Double
}

private func benchmark(iterations: Int, body: () -> Void) -> BenchmarkResult {
    for _ in 0..<max(iterations / 10, 1) {
        body()
    }

    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let start = now()
        body()
        samples.append(now() - start)
    }

    samples.sort()
    return BenchmarkResult(medianMS: samples[samples.count / 2])
}

private func now() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000.0
}

private func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}

private extension Array where Element == BenchPoint {
    func removingConsecutiveDuplicates() -> [BenchPoint] {
        var output: [BenchPoint] = []
        output.reserveCapacity(count)
        for item in self where output.last != item {
            output.append(item)
        }
        return output
    }
}
