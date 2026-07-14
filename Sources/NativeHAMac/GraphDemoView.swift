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
        
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/Users/jin/Documents/Computer/NativeHA/sps30_1day.json")),
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
        let allInputs = model.states.values.compactMap { state -> GraphRenderSeriesInput? in
            guard let history = model.histories[state.entityId] else { return nil }
            return GraphRenderSeriesInput(
                entityID: state.entityId,
                name: model.displayName(for: state.entityId),
                unit: model.unit(for: state.entityId) ?? "",
                color: GraphColor(red: 1, green: 0, blue: 0, alpha: 1),
                history: history.first!
            )
        }


        let converted = allInputs.compactMap { input -> GraphRenderedSeries? in
            let points = input.history.points.compactMap { point -> GraphRenderedPoint? in
                guard let t = parser.timestamp(from: point), let y = Double(point.state) else { return nil }
                return GraphRenderedPoint(t: t, y: y, display: point.state)
            }
            guard !points.isEmpty else { return nil }
            return GraphRenderedSeries(entityID: input.entityID, name: input.name, unit: input.unit, color: input.color, points: points)
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

struct DemoGraphView: View {
    let series: GraphRenderedSeries
    @Binding var visibleStart: Double
    @Binding var visibleEnd: Double
    let mode: AxisMode
    let lowPassFactor: Double
    let shrinkThreshold: Double

    @StateObject private var axisState = AxisStateModel()
    @State private var isInteracting = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = draw(size: geo.size, isInteracting: isInteracting) {
                    Image(decorative: image, scale: 2, orientation: .up)
                        .resizable()
                        .interpolation(.high)

                    // Animated Axis Overlay
                    DemoAxisOverlay(
                        axis: axisState.currentAxis ?? GraphAxis(min: 0, max: 1, ticks: []),
                        xTicks: linearTicks(min: visibleStart, max: visibleEnd, count: 5),
                        size: geo.size,
                        visibleStart: visibleStart,
                        visibleEnd: visibleEnd
                    )
                }

                DemoInteractionOverlay(
                    visibleStart: $visibleStart,
                    visibleEnd: $visibleEnd,
                    isInteracting: $isInteracting,
                    fullStart: series.points.first?.t ?? 0,
                    fullEnd: series.points.last?.t ?? 1
                )
            }
        }
    }

    private func draw(size: CGSize, isInteracting: Bool) -> CGImage? {
        let range = visibleRange(in: series.points, start: visibleStart, end: visibleEnd)
        let scale: CGFloat = 2.0
        let targetCount = Int(size.width * scale)
        let points = series.minMaxCache?.downsample(in: range, target: targetCount) ?? Array(series.points[range])

        let windowWidth = max(visibleEnd - visibleStart, 1)
        
        let baseMin = points.map(\.y).min() ?? 0
        let baseMax = points.map(\.y).max() ?? 1
        
        var targetMin = baseMin
        var targetMax = baseMax
        
        if mode == .interpolated || mode == .sticky {
            let padRange = visibleRange(in: series.points, start: visibleStart - windowWidth * 2, end: visibleEnd + windowWidth * 2)
            let paddedPoints = series.minMaxCache?.downsample(in: padRange, target: targetCount * 3) ?? Array(series.points[padRange])
            
            let decayScale = windowWidth * 0.5
            
            for p in paddedPoints {
                if p.t >= visibleStart && p.t <= visibleEnd { continue }
                
                let distance = p.t < visibleStart ? (visibleStart - p.t) : (p.t - visibleEnd)
                let weight = exp(-distance / decayScale)
                
                if p.y > baseMax {
                    let demandMax = baseMax + (p.y - baseMax) * weight
                    targetMax = max(targetMax, demandMax)
                }
                if p.y < baseMin {
                    let demandMin = baseMin - (baseMin - p.y) * weight
                    targetMin = min(targetMin, demandMin)
                }
            }
        }
        
        let rawTargetAxis = niceAxis(values: [targetMin, targetMax])
        
        RunLoop.main.perform(inModes: [.common]) {
            axisState.update(
                targetMin: rawTargetAxis.min,
                targetMax: rawTargetAxis.max,
                mode: mode,
                lowPassFactor: lowPassFactor,
                shrinkThreshold: shrinkThreshold,
                ticks: rawTargetAxis.ticks
            )
        }

        guard let currentAxis = axisState.currentAxis else { return nil }

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
                let yRange = max(currentAxis.max - currentAxis.min, 0.0001)
                let y = plotRect.maxY - plotRect.height * CGFloat((p.y - currentAxis.min) / yRange)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.addPath(path)
            context.strokePath()

            return context.makeImage()
        }
    }
}

class AxisStateModel: ObservableObject {
    @Published var currentAxis: GraphAxis?
    
    func update(targetMin: Double, targetMax: Double, mode: AxisMode, lowPassFactor: Double, shrinkThreshold: Double, ticks: [Double]) {
        guard let current = currentAxis else {
            currentAxis = GraphAxis(min: targetMin, max: targetMax, ticks: ticks)
            return
        }
        
        var newMin = current.min
        var newMax = current.max
        
        switch mode {
        case .instant:
            newMin = targetMin
            newMax = targetMax
        case .interpolated:
            newMin += (targetMin - current.min) * lowPassFactor
            newMax += (targetMax - current.max) * lowPassFactor
            // Snap if very close
            if abs(newMin - targetMin) < 0.01 { newMin = targetMin }
            if abs(newMax - targetMax) < 0.01 { newMax = targetMax }
        case .sticky:
            let currentRange = current.max - current.min
            if targetMax > current.max {
                newMax = targetMax + currentRange * 0.1
            } else if targetMax < current.max - currentRange * shrinkThreshold {
                newMax = targetMax + currentRange * 0.1
            }
            
            if targetMin < current.min {
                newMin = targetMin - currentRange * 0.1
            } else if targetMin > current.min + currentRange * shrinkThreshold {
                newMin = targetMin - currentRange * 0.1
            }
        }

        // Only publish if changed significantly to avoid infinite loops
        if abs(newMin - current.min) > 0.001 || abs(newMax - current.max) > 0.001 || current.ticks != ticks {
            let nextTicks = (mode == .instant) ? ticks : niceAxis(values: [newMin, newMax]).ticks
            currentAxis = GraphAxis(min: newMin, max: newMax, ticks: nextTicks)
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
    @Binding var isInteracting: Bool
    let fullStart: Double
    let fullEnd: Double

    func makeNSView(context: Context) -> DemoTrackingView {
        let view = DemoTrackingView()
        view.onInteractionChange = { interacting in
            if interacting != isInteracting {
                isInteracting = interacting
            }
        }
        view.onPan = { deltaX in
            let range = visibleEnd - visibleStart
            let shift = (deltaX / 400.0) * range
            visibleStart -= shift
            visibleEnd -= shift
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
        }
        return view
    }

    func updateNSView(_ nsView: DemoTrackingView, context: Context) {}
}

class DemoTrackingView: NSView {
    var onPan: ((Double) -> Void)?
    var onMagnify: ((Double) -> Void)?
    var onInteractionChange: ((Bool) -> Void)?

    private var interactionTimer: Timer?

    private func notifyInteraction() {
        if interactionTimer == nil {
            onInteractionChange?(true)
        }
        interactionTimer?.invalidate()
        interactionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.interactionTimer = nil
            self?.onInteractionChange?(false)
        }
        // Ensure timer fires even during scrolling runloop
        if let timer = interactionTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        notifyInteraction()
        
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            onMagnify?(Double(event.scrollingDeltaY / 360.0))
        } else {
            onPan?(Double(event.scrollingDeltaX))
        }
    }

    override func magnify(with event: NSEvent) {
        notifyInteraction()
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
