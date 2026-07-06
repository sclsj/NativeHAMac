import CoreGraphics
import Foundation
import NativeHACore

@main
enum GraphBench {
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

        let definitions = [
            DatasetDefinition(
                name: "TempHumidity",
                entityIDs: [
                    "sensor.qtpy_sensors_bme688_humidity",
                    "sensor.qtpy_sensors_bme688_temperature",
                ]
            ),
            DatasetDefinition(
                name: "AirQuality",
                entityIDs: [
                    "sensor.qtpy_air_quality_bme688_iaq",
                    "sensor.qtpy_air_quality_scd41_co2",
                    "sensor.sps30_pm4_0",
                    "sensor.sps30_pm10",
                    "sensor.sps30_pm2_5",
                    "sensor.sps30_pm1_0",
                    "sensor.joy_iphone_ble_distance",
                ]
            ),
            DatasetDefinition(
                name: "HeaterState",
                entityIDs: ["binary_sensor.heater_active"]
            ),
        ]

        let hours = 12
        print("Fetching \(hours)h of real Home Assistant history...")
        let datasets = try await definitions.asyncMap { definition -> BenchDataset in
            let start = now()
            let history = try await client.fetchHistory(entityIDs: definition.entityIDs, hoursToShow: hours)
            let series = history.compactMap(BenchSeries.init(history:))
            let elapsed = now() - start
            let points = series.map(\.points.count).reduce(0, +)
            print("- \(definition.name): \(series.count) series, \(points) points fetched/decoded in \(format(elapsed)) ms")
            return BenchDataset(name: definition.name, series: series)
        }

        let groups = datasets.flatMap { dataset in
            dataset.unitGroups().map { group in
                BenchGroup(name: "\(dataset.name) [\(group.unit)]", unit: group.unit, series: group.series)
            }
        }.filter { !$0.series.isEmpty }

        print("")
        print("Dataset groups:")
        for group in groups {
            let points = group.series.map(\.points.count).reduce(0, +)
            print("- \(group.name): \(group.series.count) series, \(points) points")
        }

        runDownsampleBenchmarks(groups: groups)
        runAxisBenchmarks(groups: groups)
        runHoverBenchmarks(groups: groups)
        runRenderBenchmarks(groups: groups)
        runPipelineBenchmarks(groups: groups)
    }
}

private struct DatasetDefinition {
    let name: String
    let entityIDs: [String]
}

private struct BenchDataset {
    let name: String
    let series: [BenchSeries]

    func unitGroups() -> [(unit: String, series: [BenchSeries])] {
        Dictionary(grouping: series) { $0.unit }
            .map { (unit: $0.key, series: $0.value) }
            .sorted { $0.unit < $1.unit }
    }
}

private struct BenchGroup {
    let name: String
    let unit: String
    let series: [BenchSeries]
}

private struct BenchSeries {
    let entityID: String
    let unit: String
    let points: [BenchPoint]

    init?(history: HAHistorySeries) {
        let formatter = DateParser()
        var unit = ""
        let points = history.points.compactMap { point -> BenchPoint? in
            if unit.isEmpty, let attributes = point.attributes {
                unit = unitFromAttributes(attributes) ?? ""
            }
            guard
                let timestamp = formatter.timestamp(from: point),
                let value = numericValue(point.state)
            else {
                return nil
            }
            return BenchPoint(t: timestamp, y: value)
        }

        guard !points.isEmpty else {
            return nil
        }

        if unit.isEmpty && history.entityID.contains("binary_sensor") {
            unit = "state"
        }

        self.entityID = history.entityID
        self.unit = unit.isEmpty ? "value" : unit
        self.points = points.sorted { $0.t < $1.t }
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
        if let value = point.lastChanged, let date = parse(value) {
            return date.timeIntervalSince1970
        }
        if let value = point.lastUpdated, let date = parse(value) {
            return date.timeIntervalSince1970
        }
        return nil
    }

    private func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? normal.date(from: value)
    }
}

private struct Axis {
    let min: Double
    let max: Double
    let ticks: [Double]
}

private enum DownsampleAlgorithm: String, CaseIterable {
    case none
    case stride
    case minMax
    case firstLastMinMax
    case lttb
}

private enum AxisAlgorithm: String, CaseIterable {
    case paddedMinMax
    case niceTicks
    case robustPercentile
    case fixedBinary
}

private enum RenderAlgorithm: String, CaseIterable {
    case cgPath
    case immediateLines
    case cachedBitmapBlit
}

private func runDownsampleBenchmarks(groups: [BenchGroup]) {
    print("")
    print("Downsampling benchmark, median ms per group over 80 runs:")
    print("| group | input pts | target | none | stride | minMax | firstLastMinMax | lttb |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")

    for group in groups {
        let target = targetPoints(width: 496, seriesCount: group.series.count)
        let inputCount = group.series.map(\.points.count).reduce(0, +)
        var values: [String: Double] = [:]
        for algorithm in DownsampleAlgorithm.allCases {
            let result = benchmark(iterations: 80) {
                _ = group.series.map { downsample($0.points, target: target, algorithm: algorithm) }
            }
            values[algorithm.rawValue] = result.medianMS
        }

        print("| \(group.name) | \(inputCount) | \(target) | \(format(values["none"] ?? 0)) | \(format(values["stride"] ?? 0)) | \(format(values["minMax"] ?? 0)) | \(format(values["firstLastMinMax"] ?? 0)) | \(format(values["lttb"] ?? 0)) |")
    }
}

private func runAxisBenchmarks(groups: [BenchGroup]) {
    print("")
    print("Axis benchmark after minMax downsampling, median ms over 200 runs:")
    print("| group | pts | paddedMinMax | niceTicks | robustPercentile | fixedBinary |")
    print("|---|---:|---:|---:|---:|---:|")

    for group in groups {
        let target = targetPoints(width: 496, seriesCount: group.series.count)
        let points = group.series.flatMap { downsample($0.points, target: target, algorithm: .minMax) }
        var values: [String: Double] = [:]
        for algorithm in AxisAlgorithm.allCases {
            let result = benchmark(iterations: 200) {
                _ = axis(for: points, algorithm: algorithm)
            }
            values[algorithm.rawValue] = result.medianMS
        }

        print("| \(group.name) | \(points.count) | \(format(values["paddedMinMax"] ?? 0)) | \(format(values["niceTicks"] ?? 0)) | \(format(values["robustPercentile"] ?? 0)) | \(format(values["fixedBinary"] ?? 0)) |")
    }
}

private func runHoverBenchmarks(groups: [BenchGroup]) {
    print("")
    print("Hover lookup benchmark, 1,000 sample x positions, median ms over 80 runs:")
    print("| group | pts | linear | binary | pixelIndex |")
    print("|---|---:|---:|---:|---:|")

    for group in groups {
        let target = targetPoints(width: 496, seriesCount: group.series.count)
        let series = group.series.map {
            BenchSeries(entityID: $0.entityID, unit: $0.unit, points: downsample($0.points, target: target, algorithm: .minMax))
        }
        let points = series.map(\.points.count).reduce(0, +)
        let bounds = timeBounds(series: series)
        let queries = (0..<1000).map { index in
            bounds.min + (bounds.max - bounds.min) * Double(index) / 999
        }
        let index = PixelIndex(series: series, width: 496, tMin: bounds.min, tMax: bounds.max)

        let linear = benchmark(iterations: 80) {
            for query in queries {
                _ = series.map { nearestLinear($0.points, query) }
            }
        }
        let binary = benchmark(iterations: 80) {
            for query in queries {
                _ = series.map { nearestBinary($0.points, query) }
            }
        }
        let pixel = benchmark(iterations: 80) {
            for query in queries {
                _ = index.nearest(t: query)
            }
        }

        print("| \(group.name) | \(points) | \(format(linear.medianMS)) | \(format(binary.medianMS)) | \(format(pixel.medianMS)) |")
    }
}

private func runRenderBenchmarks(groups: [BenchGroup]) {
    print("")
    print("Bitmap render benchmark, 496x220 px, minMax downsample + nice axis, median ms over 60 runs:")
    print("| group | pts drawn | cgPath | immediateLines | cachedBitmapBlit |")
    print("|---|---:|---:|---:|---:|")

    for group in groups {
        let prepared = prepare(group: group, downsample: .minMax, axisAlgorithm: .niceTicks)
        let count = prepared.series.map(\.points.count).reduce(0, +)
        var values: [String: Double] = [:]
        for algorithm in RenderAlgorithm.allCases {
            let iterations = algorithm == .cachedBitmapBlit ? 300 : 60
            let result = benchmark(iterations: iterations) {
                _ = render(prepared, algorithm: algorithm)
            }
            values[algorithm.rawValue] = result.medianMS
        }

        print("| \(group.name) | \(count) | \(format(values["cgPath"] ?? 0)) | \(format(values["immediateLines"] ?? 0)) | \(format(values["cachedBitmapBlit"] ?? 0)) |")
    }
}

private func runPipelineBenchmarks(groups: [BenchGroup]) {
    print("")
    print("Full pipeline benchmark, downsample + axis + render, median ms over 40 runs:")
    print("| group | stride+nice+cgPath | minMax+nice+cgPath | lttb+nice+cgPath | minMax+robust+cgPath | minMax+nice+blit |")
    print("|---|---:|---:|---:|---:|---:|")

    for group in groups {
        let cases: [(String, DownsampleAlgorithm, AxisAlgorithm, RenderAlgorithm)] = [
            ("stride+nice+cgPath", .stride, .niceTicks, .cgPath),
            ("minMax+nice+cgPath", .minMax, .niceTicks, .cgPath),
            ("lttb+nice+cgPath", .lttb, .niceTicks, .cgPath),
            ("minMax+robust+cgPath", .minMax, .robustPercentile, .cgPath),
            ("minMax+nice+blit", .minMax, .niceTicks, .cachedBitmapBlit),
        ]
        var results: [String: Double] = [:]
        for item in cases {
            let result = benchmark(iterations: 40) {
                let prepared = prepare(group: group, downsample: item.1, axisAlgorithm: item.2)
                _ = render(prepared, algorithm: item.3)
            }
            results[item.0] = result.medianMS
        }

        print("| \(group.name) | \(format(results["stride+nice+cgPath"] ?? 0)) | \(format(results["minMax+nice+cgPath"] ?? 0)) | \(format(results["lttb+nice+cgPath"] ?? 0)) | \(format(results["minMax+robust+cgPath"] ?? 0)) | \(format(results["minMax+nice+blit"] ?? 0)) |")
    }
}

private struct PreparedChart {
    let width: Int
    let height: Int
    let plot: CGRect
    let axis: Axis
    let tMin: Double
    let tMax: Double
    let series: [BenchSeries]
}

private func prepare(
    group: BenchGroup,
    downsample algorithm: DownsampleAlgorithm,
    axisAlgorithm: AxisAlgorithm
) -> PreparedChart {
    let width = 496
    let height = 220
    let target = targetPoints(width: width, seriesCount: group.series.count)
    let series = group.series.map {
        BenchSeries(entityID: $0.entityID, unit: $0.unit, points: downsample($0.points, target: target, algorithm: algorithm))
    }
    let all = series.flatMap(\.points)
    let bounds = timeBounds(series: series)
    let chartAxis = axis(for: all, algorithm: axisAlgorithm)
    return PreparedChart(
        width: width,
        height: height,
        plot: CGRect(x: 42, y: 16, width: 440, height: 174),
        axis: chartAxis,
        tMin: bounds.min,
        tMax: bounds.max,
        series: series
    )
}

private func render(_ chart: PreparedChart, algorithm: RenderAlgorithm) -> CGImage? {
    if algorithm == .cachedBitmapBlit {
        guard let source = render(chart, algorithm: .cgPath) else {
            return nil
        }
        return bitmapContext(width: chart.width, height: chart.height) { context in
            context.draw(source, in: CGRect(x: 0, y: 0, width: chart.width, height: chart.height))
        }
    }

    return bitmapContext(width: chart.width, height: chart.height) { context in
        context.setFillColor(CGColor(red: 0.07, green: 0.075, blue: 0.075, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: chart.width, height: chart.height))

        context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
        context.setLineWidth(1)
        for tick in chart.axis.ticks {
            let y = yPosition(tick, axis: chart.axis, plot: chart.plot)
            context.move(to: CGPoint(x: chart.plot.minX, y: y))
            context.addLine(to: CGPoint(x: chart.plot.maxX, y: y))
        }
        context.strokePath()

        for (index, series) in chart.series.enumerated() {
            context.setStrokeColor(color(index: index))
            context.setLineWidth(2)
            switch algorithm {
            case .cgPath, .cachedBitmapBlit:
                let path = CGMutablePath()
                add(series: series, to: path, chart: chart)
                context.addPath(path)
                context.strokePath()
            case .immediateLines:
                add(series: series, to: context, chart: chart)
                context.strokePath()
            }
        }
    }
}

private func bitmapContext(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
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
        draw(context)
        return context.makeImage()
    }
}

private func add(series: BenchSeries, to path: CGMutablePath, chart: PreparedChart) {
    for (index, point) in series.points.enumerated() {
        let mapped = map(point, chart: chart)
        if index == 0 {
            path.move(to: mapped)
        } else {
            path.addLine(to: mapped)
        }
    }
}

private func add(series: BenchSeries, to context: CGContext, chart: PreparedChart) {
    for (index, point) in series.points.enumerated() {
        let mapped = map(point, chart: chart)
        if index == 0 {
            context.move(to: mapped)
        } else {
            context.addLine(to: mapped)
        }
    }
}

private func map(_ point: BenchPoint, chart: PreparedChart) -> CGPoint {
    let xRange = max(chart.tMax - chart.tMin, 1)
    let yRange = max(chart.axis.max - chart.axis.min, 0.0001)
    let x = chart.plot.minX + chart.plot.width * CGFloat((point.t - chart.tMin) / xRange)
    let y = chart.plot.maxY - chart.plot.height * CGFloat((point.y - chart.axis.min) / yRange)
    return CGPoint(x: x, y: y)
}

private func yPosition(_ value: Double, axis: Axis, plot: CGRect) -> CGFloat {
    let yRange = max(axis.max - axis.min, 0.0001)
    return plot.maxY - plot.height * CGFloat((value - axis.min) / yRange)
}

private func color(index: Int) -> CGColor {
    let colors: [(CGFloat, CGFloat, CGFloat)] = [
        (0.26, 0.47, 0.95),
        (0.93, 0.66, 0.22),
        (0.40, 0.86, 0.82),
        (0.95, 0.32, 0.50),
        (0.66, 0.42, 0.92),
        (0.45, 0.76, 0.32),
    ]
    let value = colors[index % colors.count]
    return CGColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
}

private func downsample(
    _ points: [BenchPoint],
    target: Int,
    algorithm: DownsampleAlgorithm
) -> [BenchPoint] {
    guard points.count > target, target > 2 else {
        return points
    }

    switch algorithm {
    case .none:
        return points
    case .stride:
        return strideDownsample(points, target: target)
    case .minMax:
        return minMaxDownsample(points, target: target)
    case .firstLastMinMax:
        return firstLastMinMaxDownsample(points, target: target)
    case .lttb:
        return lttb(points, target: target)
    }
}

private func strideDownsample(_ points: [BenchPoint], target: Int) -> [BenchPoint] {
    let stride = max(points.count / target, 1)
    var output = points.enumerated().compactMap { index, point in
        index % stride == 0 ? point : nil
    }
    if output.last != points.last, let last = points.last {
        output.append(last)
    }
    return output
}

private func minMaxDownsample(_ points: [BenchPoint], target: Int) -> [BenchPoint] {
    let bucketSize = Double(points.count) / Double(max(target / 2, 1))
    var output: [BenchPoint] = []
    output.reserveCapacity(target + 2)

    var bucket = 0
    while true {
        let start = Int(Double(bucket) * bucketSize)
        if start >= points.count {
            break
        }
        let end = min(Int(Double(bucket + 1) * bucketSize), points.count)
        if start >= end {
            break
        }

        let slice = points[start..<end]
        if let minPoint = slice.min(by: { $0.y < $1.y }), let maxPoint = slice.max(by: { $0.y < $1.y }) {
            if minPoint.t < maxPoint.t {
                output.append(minPoint)
                if minPoint != maxPoint { output.append(maxPoint) }
            } else {
                output.append(maxPoint)
                if minPoint != maxPoint { output.append(minPoint) }
            }
        }
        bucket += 1
    }

    return output
}

private func firstLastMinMaxDownsample(_ points: [BenchPoint], target: Int) -> [BenchPoint] {
    let bucketSize = Double(points.count) / Double(max(target / 4, 1))
    var output: [BenchPoint] = []
    output.reserveCapacity(target + 4)

    var bucket = 0
    while true {
        let start = Int(Double(bucket) * bucketSize)
        if start >= points.count {
            break
        }
        let end = min(Int(Double(bucket + 1) * bucketSize), points.count)
        if start >= end {
            break
        }

        let slice = Array(points[start..<end])
        var candidates: [BenchPoint] = []
        if let first = slice.first { candidates.append(first) }
        if let minPoint = slice.min(by: { $0.y < $1.y }) { candidates.append(minPoint) }
        if let maxPoint = slice.max(by: { $0.y < $1.y }) { candidates.append(maxPoint) }
        if let last = slice.last { candidates.append(last) }
        output.append(contentsOf: candidates.removingConsecutiveDuplicates().sorted { $0.t < $1.t })
        bucket += 1
    }

    return output.removingConsecutiveDuplicates()
}

private func lttb(_ points: [BenchPoint], target: Int) -> [BenchPoint] {
    guard target < points.count, target > 2 else {
        return points
    }

    let bucketSize = Double(points.count - 2) / Double(target - 2)
    var sampled = [BenchPoint]()
    sampled.reserveCapacity(target)
    sampled.append(points[0])

    var a = 0
    for i in 0..<(target - 2) {
        let rangeStart = Int(floor(Double(i + 1) * bucketSize)) + 1
        let rangeEnd = min(Int(floor(Double(i + 2) * bucketSize)) + 1, points.count)
        let avgRange = points[rangeStart..<rangeEnd]
        let avgX = avgRange.map(\.t).reduce(0, +) / Double(max(avgRange.count, 1))
        let avgY = avgRange.map(\.y).reduce(0, +) / Double(max(avgRange.count, 1))

        let bucketStart = Int(floor(Double(i) * bucketSize)) + 1
        let bucketEnd = min(Int(floor(Double(i + 1) * bucketSize)) + 1, points.count - 1)

        var maxArea = -Double.greatestFiniteMagnitude
        var nextA = bucketStart
        let pointA = points[a]

        for index in bucketStart..<bucketEnd {
            let point = points[index]
            let area = abs(
                (pointA.t - avgX) * (point.y - pointA.y) -
                (pointA.t - point.t) * (avgY - pointA.y)
            ) * 0.5
            if area > maxArea {
                maxArea = area
                nextA = index
            }
        }

        sampled.append(points[nextA])
        a = nextA
    }

    sampled.append(points[points.count - 1])
    return sampled
}

private func axis(for points: [BenchPoint], algorithm: AxisAlgorithm) -> Axis {
    guard !points.isEmpty else {
        return Axis(min: 0, max: 1, ticks: [0, 0.25, 0.5, 0.75, 1])
    }

    switch algorithm {
    case .fixedBinary:
        return Axis(min: -0.05, max: 1.05, ticks: [0, 1])
    case .paddedMinMax:
        let minValue = points.map(\.y).min() ?? 0
        let maxValue = points.map(\.y).max() ?? 1
        let padding = max((maxValue - minValue) * 0.08, 0.01)
        let minAxis = minValue - padding
        let maxAxis = maxValue + padding
        return Axis(min: minAxis, max: maxAxis, ticks: linearTicks(min: minAxis, max: maxAxis, count: 5))
    case .niceTicks:
        let minValue = points.map(\.y).min() ?? 0
        let maxValue = points.map(\.y).max() ?? 1
        return niceAxis(min: minValue, max: maxValue, tickCount: 5)
    case .robustPercentile:
        let sorted = points.map(\.y).sorted()
        let low = percentile(sorted, 0.01)
        let high = percentile(sorted, 0.99)
        return niceAxis(min: low, max: high, tickCount: 5)
    }
}

private func linearTicks(min: Double, max: Double, count: Int) -> [Double] {
    guard count > 1 else {
        return [min]
    }
    return (0..<count).map { min + (max - min) * Double($0) / Double(count - 1) }
}

private func niceAxis(min: Double, max: Double, tickCount: Int) -> Axis {
    let span = max - min
    let safeSpan = span == 0 ? Swift.max(abs(max), 1) : span
    let roughStep = safeSpan / Double(Swift.max(tickCount - 1, 1))
    let step = niceNumber(roughStep)
    let niceMin = floor(min / step) * step
    let niceMax = ceil(max / step) * step
    var ticks: [Double] = []
    var value = niceMin
    while value <= niceMax + step * 0.5 {
        ticks.append(value)
        value += step
    }
    return Axis(min: niceMin, max: niceMax, ticks: ticks)
}

private func niceNumber(_ value: Double) -> Double {
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

private func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else {
        return 0
    }
    let index = min(max(Int(Double(sorted.count - 1) * p), 0), sorted.count - 1)
    return sorted[index]
}

private struct PixelIndex {
    let buckets: [[BenchPoint]]
    let tMin: Double
    let tMax: Double

    init(series: [BenchSeries], width: Int, tMin: Double, tMax: Double) {
        self.tMin = tMin
        self.tMax = tMax
        var buckets = Array(repeating: [BenchPoint](), count: width)
        let range = max(tMax - tMin, 1)
        for point in series.flatMap(\.points) {
            let index = min(max(Int((point.t - tMin) / range * Double(width - 1)), 0), width - 1)
            buckets[index].append(point)
        }
        self.buckets = buckets
    }

    func nearest(t: Double) -> BenchPoint? {
        let range = max(tMax - tMin, 1)
        let index = min(max(Int((t - tMin) / range * Double(buckets.count - 1)), 0), buckets.count - 1)
        for offset in 0..<buckets.count {
            let left = index - offset
            let right = index + offset
            if left >= 0, let point = buckets[left].min(by: { abs($0.t - t) < abs($1.t - t) }) {
                return point
            }
            if right < buckets.count, let point = buckets[right].min(by: { abs($0.t - t) < abs($1.t - t) }) {
                return point
            }
        }
        return nil
    }
}

private func nearestLinear(_ points: [BenchPoint], _ t: Double) -> BenchPoint? {
    points.min { abs($0.t - t) < abs($1.t - t) }
}

private func nearestBinary(_ points: [BenchPoint], _ t: Double) -> BenchPoint? {
    guard !points.isEmpty else {
        return nil
    }
    var low = 0
    var high = points.count - 1
    while low < high {
        let mid = (low + high) / 2
        if points[mid].t < t {
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
    return abs(before.t - t) < abs(after.t - t) ? before : after
}

private func timeBounds(series: [BenchSeries]) -> (min: Double, max: Double) {
    let points = series.flatMap(\.points)
    return (points.map(\.t).min() ?? 0, points.map(\.t).max() ?? 1)
}

private func targetPoints(width: Int, seriesCount: Int) -> Int {
    max(width * 2 / max(seriesCount, 1), 80)
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

private func unitFromAttributes(_ attributes: [String: JSONValue]) -> String? {
    guard case let .string(unit)? = attributes["unit_of_measurement"] else {
        return nil
    }
    return unit
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

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for item in self {
            values.append(try await transform(item))
        }
        return values
    }
}

private extension BenchSeries {
    init(entityID: String, unit: String, points: [BenchPoint]) {
        self.entityID = entityID
        self.unit = unit
        self.points = points
    }
}
