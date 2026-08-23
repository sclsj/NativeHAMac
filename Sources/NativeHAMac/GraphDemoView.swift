import Foundation
import NativeHACore
import SwiftUI

struct GraphDemoView: View {
    @EnvironmentObject private var model: DashboardViewModel
    @Environment(\.presentationMode) var presentationMode

    @State private var lowPassFactor: Double = 0.15
    @State private var shrinkThreshold: Double = 0.5

    @State private var visibleStart: Double = 0
    @State private var visibleEnd: Double = 1
    @State private var isInitialized = false
    @State private var targetSeries: GraphRenderedSeries?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Graph Scaling Algorithm Demo")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()
            .background(Color.black.opacity(0.2))

            if let targetSeries = targetSeries {
                HStack(spacing: 16) {
                    demoCard(title: "1. Instant Rescale (Current)", series: targetSeries, mode: .instant)
                        .frame(maxWidth: .infinity)
                    demoCard(title: "2. Interpolated (Smooth)", series: targetSeries, mode: .interpolated)
                        .frame(maxWidth: .infinity)
                    demoCard(title: "3. Sticky (Hysteresis)", series: targetSeries, mode: .sticky)
                        .frame(maxWidth: .infinity)
                }
                .padding()

                controlPanel
            } else {
                Text("Waiting for sps30 or suitable sensor data...")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .frame(minWidth: 1000, minHeight: 400)
        .onAppear {
            if !isInitialized {
                DispatchQueue.global(qos: .userInitiated).async {
                    let series = findTargetSeries()
                    DispatchQueue.main.async {
                        self.targetSeries = series
                        if let start = series?.points.first?.t, let end = series?.points.last?.t {
                            self.visibleStart = start
                            self.visibleEnd = end
                        }
                        self.isInitialized = true
                    }
                }
            }
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Low-pass Factor (Interpolated): \(String(format: "%.2f", lowPassFactor))")
                Slider(value: $lowPassFactor, in: 0.01...1.0)
            }
            HStack {
                Text("Shrink Threshold (Sticky): \(String(format: "%.2f", shrinkThreshold))")
                Slider(value: $shrinkThreshold, in: 0.1...1.0)
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }

    private func findTargetSeries() -> GraphRenderedSeries? {
        let parser = GraphDateParser()
        
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/Users/jin/Documents/Computer/NativeHA/Tests/Fixtures/History/sps30_1day.json")),
           let histories = try? JSONDecoder().decode([HAHistorySeries].self, from: data),
           let history = histories.first {
            
            let points = history.points.compactMap { point -> GraphRenderedPoint? in
                guard let t = parser.timestamp(from: point), let y = Double(point.state) else { return nil }
                return GraphRenderedPoint(t: t, y: y, display: point.state)
            }
            if !points.isEmpty {
                let cache = GraphMinMaxCache(points: points)
                return GraphRenderedSeries(entityID: history.entityID, name: "SPS30 Demo Data", unit: "µg/m³", color: GraphColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1), points: points, minMaxCache: cache)
            }
        }
        let allInputs = model.histories.values.flatMap { $0 }.map { history in
            return GraphRenderSeriesInput(
                entityID: history.entityID,
                name: model.displayName(for: history.entityID),
                unit: model.unit(for: history.entityID) ?? "",
                color: GraphColor(red: 1, green: 0, blue: 0, alpha: 1),
                history: history
            )
        }


        let converted = allInputs.compactMap { input -> GraphRenderedSeries? in
            let points = input.history.points.compactMap { point -> GraphRenderedPoint? in
                guard let t = parser.timestamp(from: point), let y = Double(point.state) else { return nil }
                return GraphRenderedPoint(t: t, y: y, display: point.state)
            }
            guard !points.isEmpty else { return nil }
            return GraphRenderedSeries(
                entityID: input.entityID,
                name: input.name,
                unit: input.unit,
                color: input.color,
                points: points,
                minMaxCache: GraphMinMaxCache(points: points)
            )
        }

        return converted.first { $0.entityID.contains("sps30") }
            ?? converted.first { $0.entityID.contains("temperature") }
            ?? converted.first
    }

    private func demoCard(title: String, series: GraphRenderedSeries, mode: AxisMode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).bold()
            DemoGraphView(
                series: series,
                visibleStart: $visibleStart,
                visibleEnd: $visibleEnd,
                mode: mode,
                lowPassFactor: lowPassFactor,
                shrinkThreshold: shrinkThreshold
            )
            .frame(height: 200)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
        }
    }
}

enum AxisMode {
    case instant, interpolated, sticky
}

private final class DemoRenderState {
    var axis: GraphAxis?
}

struct DemoGraphView: View {
    let series: GraphRenderedSeries
    @Binding var visibleStart: Double
    @Binding var visibleEnd: Double
    let mode: AxisMode
    let lowPassFactor: Double
    let shrinkThreshold: Double

    @State private var renderState = DemoRenderState()
    @State private var settleTick = 0
    @State private var settleTimer: Timer?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let frame = renderFrame(size: size, tick: settleTick)
            let needsSettling = frame?.needsSettling ?? false

            ZStack {
                if let frame = frame {
                    Image(decorative: frame.image, scale: frame.scale, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .clipped()

                    DemoAxisOverlay(
                        axis: frame.axis,
                        xTicks: frame.xTicks,
                        size: size,
                        visibleStart: frame.visibleStart,
                        visibleEnd: frame.visibleEnd
                    )
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                DemoInteractionOverlay(
                    visibleStart: $visibleStart,
                    visibleEnd: $visibleEnd,
                    fullStart: series.points.first?.t ?? 0,
                    fullEnd: series.points.last?.t ?? 1
                )
            }
            .onAppear {
                updateSettleTimer(needsSettling: needsSettling)
            }
            .onChange(of: needsSettling) { newValue in
                updateSettleTimer(needsSettling: newValue)
            }
            .onDisappear {
                stopSettleTimer()
            }
        }
    }

    private func renderFrame(size: CGSize, tick: Int) -> DemoRenderedFrame? {
        _ = tick
        guard size.width > 1, size.height > 1 else {
            return nil
        }

        let frame = DemoGraphRenderer.render(
            series: series,
            size: size,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
            mode: mode,
            lowPassFactor: lowPassFactor,
            shrinkThreshold: shrinkThreshold,
            currentAxis: renderState.axis
        )

        if let axis = frame?.axis {
            renderState.axis = axis
        }
        return frame
    }

    private func updateSettleTimer(needsSettling: Bool) {
        if needsSettling {
            startSettleTimer()
        } else {
            stopSettleTimer()
        }
    }

    private func startSettleTimer() {
        guard settleTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            settleTick = settleTick &+ 1
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func stopSettleTimer() {
        settleTimer?.invalidate()
        settleTimer = nil
    }
}

private struct DemoRenderedFrame {
    let image: CGImage
    let scale: CGFloat
    let axis: GraphAxis
    let xTicks: [Double]
    let visibleStart: Double
    let visibleEnd: Double
    let needsSettling: Bool
}

private enum DemoGraphRenderer {
    static func render(
        series: GraphRenderedSeries,
        size: CGSize,
        visibleStart: Double,
        visibleEnd: Double,
        mode: AxisMode,
        lowPassFactor: Double,
        shrinkThreshold: Double,
        currentAxis: GraphAxis?
    ) -> DemoRenderedFrame? {
        let scale: CGFloat = 2.0
        let targetCount = max(Int(size.width * scale), 1)
        let range = visibleRange(in: series.points, start: visibleStart, end: visibleEnd)
        let points = series.minMaxCache?.downsample(in: range, target: targetCount) ?? Array(series.points[range])

        guard !points.isEmpty else {
            return nil
        }

        let targetAxis = axisTarget(
            series: series,
            visiblePoints: points,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
            targetCount: targetCount,
            mode: mode
        )
        let axis = adjustedAxis(
            current: currentAxis,
            target: targetAxis,
            mode: mode,
            lowPassFactor: lowPassFactor,
            shrinkThreshold: shrinkThreshold
        )
        let needsSettling = mode == .interpolated && !axisApproximatelyMatches(axis, targetAxis)

        guard let image = drawImage(
            points: points,
            size: size,
            scale: scale,
            axis: axis,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd
        ) else {
            return nil
        }

        return DemoRenderedFrame(
            image: image,
            scale: scale,
            axis: axis,
            xTicks: linearTicks(min: visibleStart, max: visibleEnd, count: 5),
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
            needsSettling: needsSettling
        )
    }

    private static func axisTarget(
        series: GraphRenderedSeries,
        visiblePoints: [GraphRenderedPoint],
        visibleStart: Double,
        visibleEnd: Double,
        targetCount: Int,
        mode: AxisMode
    ) -> GraphAxis {
        let windowWidth = max(visibleEnd - visibleStart, 1)
        let baseMin = visiblePoints.map(\.y).min() ?? 0
        let baseMax = visiblePoints.map(\.y).max() ?? 1

        var targetMin = baseMin
        var targetMax = baseMax

        if mode == .interpolated || mode == .sticky {
            let padRange = visibleRange(
                in: series.points,
                start: visibleStart - windowWidth * 2,
                end: visibleEnd + windowWidth * 2
            )
            let paddedPoints = series.minMaxCache?.downsample(in: padRange, target: targetCount * 3)
                ?? Array(series.points[padRange])
            let decayScale = windowWidth * 0.5

            for point in paddedPoints {
                if point.t >= visibleStart && point.t <= visibleEnd {
                    continue
                }

                let distance = point.t < visibleStart ? (visibleStart - point.t) : (point.t - visibleEnd)
                let weight = exp(-distance / decayScale)

                if point.y > baseMax {
                    targetMax = max(targetMax, baseMax + (point.y - baseMax) * weight)
                }
                if point.y < baseMin {
                    targetMin = min(targetMin, baseMin - (baseMin - point.y) * weight)
                }
            }
        }

        return niceAxis(values: [targetMin, targetMax])
    }

    private static func adjustedAxis(
        current: GraphAxis?,
        target: GraphAxis,
        mode: AxisMode,
        lowPassFactor: Double,
        shrinkThreshold: Double
    ) -> GraphAxis {
        guard let current = current else {
            return target
        }

        var newMin = current.min
        var newMax = current.max

        switch mode {
        case .instant:
            newMin = target.min
            newMax = target.max
        case .interpolated:
            newMin += (target.min - current.min) * lowPassFactor
            newMax += (target.max - current.max) * lowPassFactor
            if abs(newMin - target.min) < 0.01 { newMin = target.min }
            if abs(newMax - target.max) < 0.01 { newMax = target.max }
        case .sticky:
            let currentRange = current.max - current.min
            if target.max > current.max {
                newMax = target.max + currentRange * 0.1
            } else if target.max < current.max - currentRange * shrinkThreshold {
                newMax = target.max + currentRange * 0.1
            }

            if target.min < current.min {
                newMin = target.min - currentRange * 0.1
            } else if target.min > current.min + currentRange * shrinkThreshold {
                newMin = target.min - currentRange * 0.1
            }
        }

        let ticks = mode == .instant ? target.ticks : niceAxis(values: [newMin, newMax]).ticks
        return GraphAxis(min: newMin, max: newMax, ticks: ticks)
    }

    private static func axisApproximatelyMatches(_ lhs: GraphAxis, _ rhs: GraphAxis) -> Bool {
        abs(lhs.min - rhs.min) < 0.01 && abs(lhs.max - rhs.max) < 0.01
    }

    private static func drawImage(
        points: [GraphRenderedPoint],
        size: CGSize,
        scale: CGFloat,
        axis: GraphAxis,
        visibleStart: Double,
        visibleEnd: Double
    ) -> CGImage? {
        let plotRect = CGRect(x: 40, y: 10, width: size.width - 50, height: size.height - 20)
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        var data = [UInt8](repeating: 0, count: width * height * 4)

        return data.withUnsafeMutableBytes { pointer -> CGImage? in
            guard let context = CGContext(data: pointer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)

            context.setStrokeColor(CGColor(red: 0.2, green: 0.6, blue: 0.86, alpha: 1))
            context.setLineWidth(2)
            let path = CGMutablePath()
            for (i, p) in points.enumerated() {
                let x = plotRect.minX + plotRect.width * CGFloat((p.t - visibleStart) / max(visibleEnd - visibleStart, 1))
                let yRange = max(axis.max - axis.min, 0.0001)
                let y = plotRect.maxY - plotRect.height * CGFloat((p.y - axis.min) / yRange)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.addPath(path)
            context.strokePath()

            return context.makeImage()
        }
    }
}

struct DemoAxisOverlay: View {
    let axis: GraphAxis
    let xTicks: [Double]
    let size: CGSize
    let visibleStart: Double
    let visibleEnd: Double

    private func yPosition(for tick: Double, in plotRect: CGRect) -> CGFloat {
        let yRange = max(axis.max - axis.min, 0.0001)
        return plotRect.maxY - plotRect.height * CGFloat((tick - axis.min) / yRange)
    }

    private func xPosition(for tick: Double, in plotRect: CGRect) -> CGFloat {
        plotRect.minX + plotRect.width * CGFloat((tick - visibleStart) / max(visibleEnd - visibleStart, 1))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let plotRect = CGRect(x: 40, y: 10, width: size.width - 50, height: size.height - 20)

            ForEach(axis.ticks, id: \.self) { tick in
                let y = yPosition(for: tick, in: plotRect)
                
                Path { path in
                    path.move(to: CGPoint(x: plotRect.minX, y: y))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                }
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                
                Text(formatAxis(tick))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
                    .position(x: 20, y: y)
            }
            
            ForEach(xTicks, id: \.self) { tick in
                let x = xPosition(for: tick, in: plotRect)
                
                Path { path in
                    path.move(to: CGPoint(x: x, y: plotRect.minY))
                    path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                }
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                
                Text(formatTimeLabel(tick))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
                    .position(x: x, y: plotRect.maxY + 10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: axis.ticks)
        .animation(.easeOut(duration: 0.2), value: xTicks)
    }
}

struct DemoInteractionOverlay: NSViewRepresentable {
    @Binding var visibleStart: Double
    @Binding var visibleEnd: Double
    let fullStart: Double
    let fullEnd: Double

    func makeNSView(context: Context) -> DemoTrackingView {
        let view = DemoTrackingView()
        view.onPan = { deltaX in
            let range = visibleEnd - visibleStart
            let shift = (deltaX / 400.0) * range
            visibleStart -= shift
            visibleEnd -= shift
            clampVisibleWindow()
        }
        view.onMagnify = { magDelta in
            let zoom = 1.0 + magDelta
            guard zoom > 0.1 else { return }

            let range = visibleEnd - visibleStart
            let newRange = range / zoom
            let diff = range - newRange
            visibleStart += diff / 2
            visibleEnd -= diff / 2

            // Allow zooming in VERY far (10 samples might be just a few seconds depending on sensor, let's limit to 30 seconds min)
            if visibleEnd - visibleStart < 30 {
                let center = (visibleStart + visibleEnd) / 2
                visibleStart = center - 15
                visibleEnd = center + 15
            }
            clampVisibleWindow()
        }
        return view
    }

    func updateNSView(_ nsView: DemoTrackingView, context: Context) {}

    private func clampVisibleWindow() {
        let fullRange = max(fullEnd - fullStart, 1)
        var range = visibleEnd - visibleStart
        range = min(max(range, 30), fullRange)

        let center = (visibleStart + visibleEnd) / 2
        visibleStart = center - range / 2
        visibleEnd = center + range / 2

        if visibleStart < fullStart {
            visibleStart = fullStart
            visibleEnd = fullStart + range
        }
        if visibleEnd > fullEnd {
            visibleEnd = fullEnd
            visibleStart = fullEnd - range
        }
    }
}

class DemoTrackingView: NSView {
    var onPan: ((Double) -> Void)?
    var onMagnify: ((Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            onMagnify?(Double(event.scrollingDeltaY / 360.0))
        } else {
            onPan?(Double(event.scrollingDeltaX))
        }
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(Double(event.magnification))
    }
}

private func formatAxis(_ value: Double) -> String {
    let isInteger = floor(value) == value
    return isInteger ? String(format: "%.0f", value) : String(format: "%.1f", value)
}

private func formatTimeLabel(_ timestamp: Double) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}
