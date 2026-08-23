import AppKit
import NativeHACore
import SwiftUI

struct CardRenderer: View {
    let card: LovelaceCard

    var body: some View {
        switch card.type {
        case "vertical-stack":
            VStack(spacing: AppConfig.dashboardColumnSpacing) {
                ForEach(card.cards ?? [], id: \.nativeID) { nestedCard in
                    CardRenderer(card: nestedCard)
                }
            }
        case "entities":
            EntitiesCard(card: card)
        case "history-graph":
            HistoryGraphCard(card: card)
        case "weather-forecast":
            WeatherCard(card: card)
        case "markdown":
            MarkdownCard(card: card)
        default:
            UnsupportedCard(card: card)
        }
    }
}

extension LovelaceCard {
    var nativeID: String {
        if let nativeOwnerID = nativeOwnerID {
            return nativeOwnerID
        }
        let entityList = entities?.compactMap(\.entity).joined(separator: ",") ?? ""
        let nestedCards = cards?.map(\.nativeID).joined(separator: "|") ?? ""
        let rawHours = hoursToShow.map { String($0) } ?? ""
        let components: [String] = [type, title ?? "", entity ?? "", entityList, nestedCards, rawHours]
        return components.joined(separator: "::")
    }
}

struct EntitiesCard: View {
    @EnvironmentObject private var model: DashboardViewModel
    let card: LovelaceCard

    private var entityIDs: [String] {
        card.entities?.compactMap(\.entity) ?? []
    }

    private var toggleableEntityIDs: [String] {
        entityIDs.filter { model.canToggle(entityID: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let title = card.title {
                    CardTitle(title)
                }
                Spacer()
                if toggleableEntityIDs.count > 1 {
                    Toggle("", isOn: Binding(
                        get: { model.allOn(entityIDs: toggleableEntityIDs) },
                        set: { model.setPower(entityIDs: toggleableEntityIDs, isOn: $0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            .padding(.bottom, 14)

            ForEach(card.entities ?? []) { entityRef in
                if let entityID = entityRef.entity {
                    EntityRow(
                        entityID: entityID,
                        name: entityRef.name ?? model.displayName(for: entityID)
                    )

                    if entityRef.id != (card.entities ?? []).last?.id {
                        Divider()
                            .background(Color.white.opacity(0.08))
                    }
                }
            }
        }
        .cardStyle()
    }
}

struct EntityRow: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let name: String

    var body: some View {
        Button(action: {
            model.openDetails(entityID: entityID)
        }) {
            HStack(spacing: 16) {
                DomainIcon(entityID: entityID)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(1)
                    if model.showEntityIDs {
                        Text(entityID)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if model.canToggle(entityID: entityID) {
                    Toggle("", isOn: Binding(
                        get: { model.isOn(entityID: entityID) },
                        set: { model.setPower(entityID: entityID, isOn: $0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onTapGesture {}
                } else {
                    Text(model.displayState(for: entityID))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}

struct WeatherCard: View {
    @EnvironmentObject private var model: DashboardViewModel
    let card: LovelaceCard

    var body: some View {
        Button(action: {
            if let entityID = card.entity {
                model.openDetails(entityID: entityID)
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.yellow)
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 4) {
                    if let entityID = card.entity, let state = model.states[entityID] {
                        Text(model.weatherSummary(state.state))
                            .font(.system(size: 22, weight: .semibold))
                        Text(model.displayName(for: entityID))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text("Weather unavailable")
                            .font(.system(size: 15, weight: .medium))
                    }
                }

                Spacer()

                if let entityID = card.entity, let state = model.states[entityID] {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(weatherTemperature(from: state))
                            .font(.system(size: 28, weight: .medium))
                        if let humidity = humidity(from: state) {
                            Text(humidity)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private func weatherTemperature(from state: HAState) -> String {
        guard
            let temperature = state.attributes["temperature"],
            case let .double(value) = temperature
        else {
            return model.displayState(for: state.entityId)
        }

        let unit: String
        if
            let unitValue = state.attributes["temperature_unit"],
            case let .string(rawUnit) = unitValue
        {
            unit = rawUnit
        } else {
            unit = ""
        }

        return "\(String(format: "%.1f", value)) \(unit)"
    }

    private func humidity(from state: HAState) -> String? {
        guard
            let humidity = state.attributes["humidity"],
            case let .double(value) = humidity
        else {
            return nil
        }

        return "\(String(format: "%.0f", value))%"
    }
}

struct HistoryGraphCard: View {
    @EnvironmentObject private var model: DashboardViewModel
    let card: LovelaceCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if let title = card.title {
                    CardTitle(title)
                }
                Spacer()
                Text("\(model.selectedGraphHours)h")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }

            if let series = model.historySeries(for: card), !series.isEmpty {
                let groups = groupedSeries(series)
                ForEach(groups, id: \.unit) { group in
                    UnitGraph(
                        cacheScope: "card:\(card.nativeID):\(model.selectedGraphHours)h:\(group.unit)",
                        unit: group.unit,
                        series: group.series,
                        revisionFeed: model.graphHistoryRevisionFeed(for: card)
                    )

                    if group.unit != groups.last?.unit {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.vertical, 6)
                    }
                }
            } else if case let .error(message)? = model.historyStatus(for: card) {
                historyError(message)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading history")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, minHeight: 170)
            }
        }
        .cardStyle()
    }

    private func historyError(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.yellow)
            Text("History unavailable")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private func groupedSeries(_ series: [HAHistorySeries]) -> [SeriesGroup] {
        let groups = Dictionary(grouping: series) { item -> String in
            HAHistoryGraphClassifier.displayUnit(
                entityID: item.entityID,
                currentUnit: model.unit(for: item.entityID),
                currentAttributes: model.states[item.entityID]?.attributes,
                history: item
            )
        }

        return groups
            .map { SeriesGroup(unit: $0.key, series: $0.value) }
            .sorted { left, right in
                groupSortKey(left.unit) < groupSortKey(right.unit)
            }
    }

    private func groupSortKey(_ unit: String) -> String {
        switch unit {
        case "%":
            return "0-%"
        case "°C":
            return "1-c"
        case "IAQ":
            return "2-iaq"
        case "ppm":
            return "3-ppm"
        case "µg/m³", "μg/m³":
            return "4-ug"
        default:
            return "9-\(unit)"
        }
    }
}

private struct SeriesGroup {
    let unit: String
    let series: [HAHistorySeries]
}

struct UnitGraph: View {
    @EnvironmentObject private var model: DashboardViewModel
    let cacheScope: String
    let unit: String
    let series: [HAHistorySeries]
    let revisionFeed: GraphHistoryRevisionFeed?
    @State private var hoverLocation: CGPoint?
    @State private var zoomScale: CGFloat = 1
    @State private var panFraction: Double = 1
    /// Stable time anchor for the X-axis coordinate space. Only updated when
    /// the underlying data changes (new points arrive), NOT on every body
    /// evaluation. This prevents the coordinate space from sliding forward
    /// during gesture-driven re-renders.
    @State private var windowAnchor: Double = Date().timeIntervalSince1970

    /// Token derived from series content to detect actual data changes.
    private var seriesContentToken: String {
        series.map { "\($0.entityID):\($0.points.count):\($0.contentRevision)" }
            .joined(separator: "|")
    }

    private var graphInputs: [GraphRenderSeriesInput] {
        let windowEnd   = windowAnchor
        let windowStart = windowEnd - Double(model.selectedGraphHours) * 3600
        return series.enumerated().map { index, item in
            GraphRenderSeriesInput(
                cacheScope: cacheScope,
                entityID: item.entityID,
                name: model.displayName(for: item.entityID),
                unit: unit,
                color: graphColor(at: index),
                history: item,
                windowStart: windowStart,
                windowEnd: windowEnd,
                tooltipFormatting: model.graphTooltipFormatting(for: item.entityID)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BitmapLineChart(
                unit: unit,
                inputs: graphInputs,
                revisionFeed: revisionFeed,
                zoomScale: zoomScale,
                panFraction: panFraction,
                hoverLocation: $hoverLocation
            ) { delta, anchorFraction, maxZoom in
                let currentZoom = zoomScale
                let nextZoom = min(max(currentZoom * CGFloat(1 + delta), 1), maxZoom)
                zoomScale = nextZoom
                panFraction = anchoredPanFraction(
                    oldZoom: currentZoom,
                    newZoom: nextZoom,
                    oldPanFraction: panFraction,
                    anchorFraction: anchorFraction
                )
                AppLog("onMagnify: delta=\(delta) newZoom=\(zoomScale) newPan=\(panFraction)", severity: .debug, category: .interaction)
            } onPan: { delta in
                guard zoomScale > 1.01 else {
                    return
                }
                let old = panFraction
                panFraction = min(max(panFraction - panDelta(for: delta, zoomScale: zoomScale), 0), 1)
                AppLog("onPan: scrollDelta=\(delta) oldPan=\(old) newPan=\(panFraction)", severity: .debug, category: .interaction)
            }
            .frame(height: chartHeight)

            HStack(spacing: 12) {
                ForEach(graphInputs, id: \.entityID) { item in
                    Button(action: {
                        model.openDetails(entityID: item.entityID)
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color.swiftUIColor)
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .lineLimit(1)
                            Text(model.displayState(for: item.entityID))
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if zoomScale > 1.05 {
                    Text("\(String(format: "%.1f", zoomScale))x")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.48))
                }
            }
        }
        .onChange(of: seriesContentToken) { _ in
            let oldAnchor = windowAnchor
            if zoomScale <= 1.01 && panFraction >= 0.995 {
                windowAnchor = Date().timeIntervalSince1970
            }
            AppLog("onChange(seriesContentToken): zoom=\(zoomScale) pan=\(panFraction) oldAnchor=\(oldAnchor) newAnchor=\(windowAnchor)", severity: .debug, category: .interaction)
        }
        .onChange(of: zoomScale) { newValue in
            let oldAnchor = windowAnchor
            if zoomScale <= 1.01 && panFraction >= 0.995 {
                windowAnchor = Date().timeIntervalSince1970
            }
            AppLog("onChange(zoomScale): zoom=\(newValue) pan=\(panFraction) oldAnchor=\(oldAnchor) newAnchor=\(windowAnchor)", severity: .debug, category: .interaction)
        }
        .onChange(of: panFraction) { newValue in
            let oldAnchor = windowAnchor
            if zoomScale <= 1.01 && panFraction >= 0.995 {
                windowAnchor = Date().timeIntervalSince1970
            }
            AppLog("onChange(panFraction): zoom=\(zoomScale) pan=\(newValue) oldAnchor=\(oldAnchor) newAnchor=\(windowAnchor)", severity: .debug, category: .interaction)
        }
    }

    private var chartHeight: CGFloat {
        unit == HAHistoryGraphClassifier.stateUnit ? 96 : 178
    }

}

enum GraphCanvasGeometry {
    static func numericPath(
        for item: GraphRenderedSeries,
        rendered: GraphRenderResult
    ) -> Path {
        var path = Path()
        for (index, point) in item.points.enumerated() {
            let mapped = CGPoint(
                x: rendered.x(for: point.t),
                y: rendered.y(for: point.y)
            )
            if index == 0 {
                path.move(to: mapped)
            } else {
                path.addLine(to: mapped)
            }
        }
        return path
    }
}

/// The production Canvas plot extracted so the benchmark can force the same
/// drawing closure through an offscreen AppKit display pass.
struct GraphCanvasPlot: View {
    let rendered: GraphRenderResult

    var body: some View {
        Canvas { context, _ in
            if rendered.unit.lowercased() == "state" {
                drawTimeline(context: &context)
            } else {
                for item in rendered.series {
                    context.stroke(
                        GraphCanvasGeometry.numericPath(for: item, rendered: rendered),
                        with: .color(item.color.swiftUIColor),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }

    private func drawTimeline(context: inout GraphicsContext) {
        let maxRowHeight: CGFloat = 24
        let rowHeight = min(
            rendered.plotRect.height / CGFloat(max(rendered.series.count, 1)),
            maxRowHeight
        )
        let totalHeight = rowHeight * CGFloat(rendered.series.count)
        let startY = rendered.plotRect.minY + (rendered.plotRect.height - totalHeight) / 2

        for (index, item) in rendered.series.enumerated() {
            let yOffset = startY + CGFloat(index) * rowHeight
            for segment in item.timelineSegments {
                let startX = max(rendered.plotRect.minX, rendered.x(for: segment.clippedStart))
                let endX = min(rendered.plotRect.maxX, rendered.x(for: segment.clippedEnd))
                let blockWidth = endX - startX
                if blockWidth <= 0 { continue }
                let blockRect = CGRect(
                    x: startX,
                    y: yOffset + 2,
                    width: blockWidth,
                    height: max(rowHeight - 4, 1)
                )
                let hex = HAHistoryTimelineColorResolver.color(
                    for: segment.state,
                    entityID: item.entityID
                ).hex
                let color = GraphColor(hex: hex)?.swiftUIColor ??
                    Color(red: 0.62, green: 0.62, blue: 0.62)
                context.fill(Path(blockRect), with: .color(color))
            }
        }
    }
}

struct BitmapLineChart: View {
    let unit: String
    let inputs: [GraphRenderSeriesInput]
    let revisionFeed: GraphHistoryRevisionFeed?
    let zoomScale: CGFloat
    let panFraction: Double
    let showsHoverOverlay: Bool
    @Binding var hoverLocation: CGPoint?
    let onMagnify: (CGFloat, Double, CGFloat) -> Void
    let onPan: (CGFloat) -> Void
    let onRenderReady: (GraphRenderResult) -> Void
    @State private var rendered: GraphRenderResult?
    @State private var renderedToken = ""
    @StateObject private var renderCoordinator = GraphChartRenderCoordinator()
    @State private var subscribedFeed: GraphHistoryRevisionFeed?
    @State private var feedSubscription: UUID?
    @State private var renderAttempted = false

    init(
        unit: String,
        inputs: [GraphRenderSeriesInput],
        revisionFeed: GraphHistoryRevisionFeed? = nil,
        zoomScale: CGFloat,
        panFraction: Double,
        showsHoverOverlay: Bool = AppConfig.graphInteractionPolicy.hoverOverlayEnabled(),
        hoverLocation: Binding<CGPoint?>,
        onMagnify: @escaping (CGFloat, Double, CGFloat) -> Void,
        onPan: @escaping (CGFloat) -> Void,
        onRenderReady: @escaping (GraphRenderResult) -> Void = { _ in }
    ) {
        self.unit = unit
        self.inputs = inputs
        self.revisionFeed = revisionFeed
        self.zoomScale = zoomScale
        self.panFraction = panFraction
        self.showsHoverOverlay = showsHoverOverlay
        _hoverLocation = hoverLocation
        self.onMagnify = onMagnify
        self.onPan = onPan
        self.onRenderReady = onRenderReady
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let viewportToken = renderViewportToken(size: size)
            let dataToken = renderDataToken()
            let maxZoom = maxGraphZoom(for: inputs, size: size)
            let screenScale = NSScreen.main?.backingScaleFactor ?? 2
            let engine = AppConfig.graphRenderEngine
            let renderToken = [
                combinedRenderToken(viewportToken: viewportToken, dataToken: dataToken),
                String(describing: screenScale),
                String(describing: engine),
            ].joined(separator: "::")
            // Feed ownership participates in the installed-image identity.
            // A range/reconnect generation change must reset/re-key first and
            // then request a visual even when the source payload is identical.
            let token = graphChartLifecycleToken(
                renderToken: renderToken,
                feedGeneration: revisionFeed?.generation
            )
            let displayRender = rendered

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.19))

                if let renderedResult = displayRender {
                    switch engine {
                    case .coreGraphics, .metal:
                        if let image = renderedResult.image {
                            Image(decorative: image, scale: renderedResult.scale, orientation: .up)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                        }
                    case .canvas:
                        GraphCanvasPlot(rendered: renderedResult)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    }

                    axisOverlay(rendered: renderedResult)

                    if showsHoverOverlay,
                       let hoverLocation = hoverLocation,
                       let sample = renderedResult.sample(atX: hoverLocation.x)
                    {
                        hoverOverlay(sample: sample, rendered: renderedResult, size: size)
                    }
                } else if !renderAttempted {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Preparing graph")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("No numeric history")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.52))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                GraphInteractionOverlay(
                    onHover: { point in
                        hoverLocation = point
                    },
                    onMagnify: { delta, point in
                        onMagnify(delta, anchorFraction(for: point, size: size), maxZoom)
                    },
                    onPan: { delta in
                        onPan(delta)
                    }
                )
            }
            .onAppear {
                connectRevisionFeed()
                requestRender(
                    token: token,
                    size: size,
                    scale: screenScale,
                    engine: engine
                )
            }
            .onChange(of: token) { _ in
                connectRevisionFeed()
                requestRender(
                    token: token,
                    size: size,
                    scale: screenScale,
                    engine: engine
                )
            }
            .onDisappear {
                disconnectRevisionFeed()
            }
        }
    }

    private func requestRender(
        token: String,
        size: CGSize,
        scale: CGFloat,
        engine: GraphRenderEngine
    ) {
        guard size.width > 1, size.height > 1, renderedToken != token else { return }
        renderCoordinator.requestVisual(GraphChartVisualRequest(
            token: token,
            inputs: inputs,
            unit: unit,
            size: size,
            scale: scale,
            zoomScale: zoomScale,
            panFraction: panFraction,
            engine: engine
        )) { completedToken, result in
            guard completedToken == token else { return }
            rendered = result
            renderedToken = completedToken
            renderAttempted = true
            if let result = result {
                onRenderReady(result)
            }
        }
    }

    private func connectRevisionFeed() {
        guard subscribedFeed?.generation != revisionFeed?.generation else { return }
        subscribedFeed?.unsubscribe(feedSubscription)
        renderCoordinator.reset()
        subscribedFeed = revisionFeed
        let templates = inputs
        let displayUnit = unit
        feedSubscription = revisionFeed?.subscribe { event in
            if event.resetPreparedState {
                // Reconnect/correction publications must not reuse or seed the
                // preceding prepared-cache ownership generation.
                renderCoordinator.reset()
            }
            let byEntity = Dictionary(uniqueKeysWithValues: event.series.map { ($0.entityID, $0) })
            let acceptedInputs = templates.compactMap { template -> GraphRenderSeriesInput? in
                guard let history = byEntity[template.entityID] else { return nil }
                return template.replacingHistory(history)
            }
            guard !acceptedInputs.isEmpty else { return }
            renderCoordinator.submitAcceptedRevision(inputs: acceptedInputs, unit: displayUnit)
        }
    }

    private func disconnectRevisionFeed() {
        subscribedFeed?.unsubscribe(feedSubscription)
        subscribedFeed = nil
        feedSubscription = nil
        renderCoordinator.reset()
    }

    private func anchorFraction(for point: CGPoint, size: CGSize) -> Double {
        let plotMinX: CGFloat = 42
        let plotWidth = max(size.width - 54, 1)
        return min(max(Double((point.x - plotMinX) / plotWidth), 0), 1)
    }

    private func combinedRenderToken(viewportToken: String, dataToken: String) -> String {
        "\(viewportToken)::\(dataToken)"
    }

    private func renderViewportToken(size: CGSize) -> String {
        [
            unit,
            "\(Int(size.width))x\(Int(size.height))",
            String(format: "%.6f", Double(zoomScale)),
            String(format: "%.6f", panFraction),
        ].joined(separator: "::")
    }

    private func renderDataToken() -> String {
        let seriesToken = inputs.map { input in
            let first = input.history.points.first?.lastChanged ?? input.history.points.first?.lastUpdated ?? ""
            let last = input.history.points.last?.lastChanged ?? input.history.points.last?.lastUpdated ?? ""
            let color = [
                input.color.red,
                input.color.green,
                input.color.blue,
                input.color.alpha,
            ].map { String(describing: $0) }.joined(separator: ",")
            return [
                input.cacheScope,
                input.entityID,
                input.name,
                input.unit,
                color,
                input.windowStart.map(String.init(describing:)) ?? "nil",
                input.windowEnd.map(String.init(describing:)) ?? "nil",
                input.tooltipFormatting.cacheKey,
                String(input.history.points.count),
                first,
                last,
                String(input.history.contentRevision),
            ].joined(separator: ":")
        }.joined(separator: "|")

        return seriesToken
    }

    private func axisOverlay(rendered: GraphRenderResult) -> some View {
        ZStack(alignment: .topLeading) {
            if rendered.unit.lowercased() != "state" {
                Text(rendered.unit.isEmpty ? "value" : rendered.unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .position(x: 18, y: 11)

                ForEach(rendered.axis.ticks, id: \.self) { tick in
                    let y = rendered.y(for: tick)
                    
                    Path { path in
                        path.move(to: CGPoint(x: rendered.plotRect.minX, y: y))
                        path.addLine(to: CGPoint(x: rendered.plotRect.maxX, y: y))
                    }
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)

                    Text(formatAxisValue(tick))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .position(x: 21, y: y)
                }
            }

            ForEach(rendered.xTicks, id: \.self) { tick in
                let x = rendered.x(for: tick)
                
                Path { path in
                    path.move(to: CGPoint(x: x, y: rendered.plotRect.minY))
                    path.addLine(to: CGPoint(x: x, y: rendered.plotRect.maxY))
                }
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                
                Text(formatTime(tick))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
                    .position(x: x, y: rendered.size.height - 11)
            }
        }
        .animation(.easeOut(duration: 0.2), value: rendered.axis.ticks)
        .animation(.easeOut(duration: 0.2), value: rendered.xTicks)
    }

    private func hoverOverlay(sample: GraphSample, rendered: GraphRenderResult, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: sample.x, y: rendered.plotRect.minY))
                path.addLine(to: CGPoint(x: sample.x, y: rendered.plotRect.maxY))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)

            if rendered.unit.lowercased() != "state" {
                ForEach(sample.values) { value in
                    Circle()
                        .fill(value.series.color.swiftUIColor)
                        .frame(width: 8, height: 8)
                        .position(x: sample.x, y: rendered.y(for: value.point.y))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(formatTooltipTime(sample))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)

                ForEach(sample.values) { value in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(value.series.color.swiftUIColor)
                            .frame(width: 7, height: 7)
                        Text(value.series.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(tooltipDisplay(value, unit: rendered.unit))
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.82))
                }
            }
            .padding(9)
            .frame(width: 230)
            .background(Color(red: 0.06, green: 0.065, blue: 0.07).opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(7)
            .position(
                x: min(max(sample.x + 118, 118), size.width - 118),
                y: rendered.plotRect.minY + 58
            )
        }
    }

    func formatAxisValue(_ value: Double) -> String {
        if abs(value) >= 1000 {
            let divided = value / 1000
            let isInteger = floor(divided) == divided
            return isInteger ? String(format: "%.0fk", divided) : String(format: "%.1fk", divided)
        }
        let isInteger = floor(value) == value
        return isInteger ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    func formatTime(_ timestamp: Double) -> String {
        BitmapLineChart.timeFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    func formatTooltipTime(_ sample: GraphSample) -> String {
        let formatting = sample.values.first?.series.tooltipFormatting ?? .platformDefault
        return formatting.formatTime(sample.timestamp)
    }

    func tooltipDisplay(_ value: GraphSampleValue, unit: String) -> String {
        guard unit.lowercased() != "state" else {
            return value.point.display
        }
        return value.series.tooltipFormatting.formatNumber(
            value.point.y,
            unit: value.series.unit
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

func anchoredPanFraction(
    oldZoom: CGFloat,
    newZoom: CGFloat,
    oldPanFraction: Double,
    anchorFraction: Double
) -> Double {
    let newZoomValue = max(Double(newZoom), 1)
    guard newZoomValue > 1.01 else {
        return 1
    }

    let oldZoomValue = max(Double(oldZoom), 1)
    let anchor = min(max(anchorFraction, 0), 1)
    let oldVisibleFraction = 1 / oldZoomValue
    let oldScrollableFraction = max(1 - oldVisibleFraction, 0)
    let oldStartFraction = min(max(oldPanFraction, 0), 1) * oldScrollableFraction
    let anchoredFullFraction = oldStartFraction + anchor * oldVisibleFraction

    let newVisibleFraction = 1 / newZoomValue
    let newScrollableFraction = max(1 - newVisibleFraction, 0.000001)
    let nextPan = (anchoredFullFraction - anchor * newVisibleFraction) / newScrollableFraction
    return min(max(nextPan, 0), 1)
}

func panDelta(for scrollDelta: CGFloat, zoomScale: CGFloat) -> Double {
    let zoom = max(Double(zoomScale), 1.000001)
    return Double(scrollDelta / 900) / max(zoom - 1, 0.000001)
}

private func maxGraphZoom(for inputs: [GraphRenderSeriesInput], size: CGSize) -> CGFloat {
    let plotWidth = max(size.width - 54, 1)
    let minVisibleSamples = max(plotWidth * AppConfig.graphMaxZoomVisibleSamplePercentage, 1)
    let densestSeriesCount = inputs
        .map { $0.history.points.count }
        .max() ?? 0

    var maxZoom = max(CGFloat(densestSeriesCount) / minVisibleSamples, 1)

    let minTimeRange: Double = 30 * 60 // 30 minutes viewable

    let fullEnd = inputs.compactMap(\.windowEnd).max() ?? Date().timeIntervalSince1970
    let fullStart = inputs.compactMap(\.windowStart).min() ?? fullEnd - 3600

    if fullStart < fullEnd {
        let fullInterval = fullEnd - fullStart
        let timeBasedMaxZoom = CGFloat(fullInterval / minTimeRange)
        maxZoom = max(maxZoom, timeBasedMaxZoom)
    }

    return maxZoom
}

struct GraphInteractionOverlay: NSViewRepresentable {
    let onHover: (CGPoint?) -> Void
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onPan: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onHover: onHover, onMagnify: onMagnify, onPan: onPan)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHover = onHover
        nsView.onMagnify = onMagnify
        nsView.onPan = onPan
    }

    class TrackingView: NSView {
        var onHover: (CGPoint?) -> Void
        var onMagnify: (CGFloat, CGPoint) -> Void
        var onPan: (CGFloat) -> Void

        enum GestureAxis { case pan, zoom }
        private var currentAxis: GestureAxis? = nil

        init(onHover: @escaping (CGPoint?) -> Void, onMagnify: @escaping (CGFloat, CGPoint) -> Void, onPan: @escaping (CGFloat) -> Void) {
            self.onHover = onHover
            self.onMagnify = onMagnify
            self.onPan = onPan
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseMoved(with event: NSEvent) {
            onHover(convert(event.locationInWindow, from: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            onHover(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onHover(nil)
        }

        override func magnify(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onHover(point)
            
            if event.phase == .began {
                AppLog("Magnification gesture began at \(point)", category: .interaction)
            } else if event.phase == .ended || event.phase == .cancelled {
                AppLog("Magnification gesture ended", category: .interaction)
            }
            
            onMagnify(event.magnification, point)
        }

        override func scrollWheel(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onHover(point)
            
            let hasPhase = !event.phase.isEmpty || !event.momentumPhase.isEmpty
            
            if hasPhase, currentAxis == nil {
                if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
                    currentAxis = .zoom
                } else {
                    currentAxis = .pan
                }
            }
            
            let axis = currentAxis ?? (abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? .zoom : .pan)
            
            if axis == .zoom {
                onMagnify(event.scrollingDeltaY / 360, point)
            } else {
                onPan(event.scrollingDeltaX)
            }
            
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                currentAxis = nil
                AppLog("Scroll/pan gesture ended", severity: .debug, category: .interaction)
            }
        }
    }
}

struct UnsupportedCard: View {
    let card: LovelaceCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(card.title ?? "Unsupported Card")
            Text(card.type)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text("Native renderer not implemented yet.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
        .cardStyle()
    }
}

struct MarkdownCard: View {
    let card: LovelaceCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = card.title {
                CardTitle(title)
            }

            Text(card.content ?? "")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .cardStyle()
    }
}

struct EntityDetailSheet: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EntityPanelHeader(entityID: entityID)

            Divider()
                .background(Color.white.opacity(0.08))

            if let state = model.states[entityID] {
                ScrollView {
                    detailContent(state: state)
                        .padding(22)
                }
            } else {
                Text("Entity is unavailable")
                    .foregroundColor(.white.opacity(0.62))
                    .padding(22)
            }
        }
        .frame(width: 520, height: 620)
        .background(Color(red: 0.09, green: 0.095, blue: 0.1))
        .foregroundColor(.white)
    }

    @ViewBuilder
    private func detailContent(state: HAState) -> some View {
        switch model.domain(for: entityID) {
        case "climate":
            ClimateDetailContent(entityID: entityID, state: state)
        case "fan":
            FanDetailContent(entityID: entityID, state: state)
        case "sensor":
            SensorDetailContent(entityID: entityID, state: state)
        case "switch", "input_boolean", "automation":
            SwitchDetailContent(entityID: entityID, state: state)
        default:
            DefaultEntityDetailContent(entityID: entityID, state: state)
        }
    }
}

struct EntityPanelHeader: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String

    var body: some View {
        HStack(spacing: 14) {
            Button(action: {
                model.closeDetails()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName(for: entityID))
                    .font(.system(size: 20, weight: .semibold))
                Text(entityID)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.48))
                    .textSelection(.enabled)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "chart.bar")
            }
            .buttonStyle(.borderless)
            Button(action: {}) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            Button(action: {}) {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

struct ClimateDetailContent: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let state: HAState
    @State private var localTarget: Double?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text("Current temperature")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                Text(formatTemperature(currentTemperature, unit: temperatureUnit))
                    .font(.system(size: 20, weight: .semibold))
            }

            ClimateTemperatureDial(
                target: visibleTargetTemperature,
                current: currentTemperature,
                minimum: minTemperature,
                maximum: maxTemperature,
                step: step,
                unit: temperatureUnit,
                hvacMode: state.state,
                actionLabel: actionLabel,
                onSetTarget: setTarget
            )
            .frame(width: 320, height: 320)

            HStack(spacing: 10) {
                menuControl(
                    title: "Mode",
                    value: prettyMode(state.state),
                    systemName: "power",
                    options: hvacModes
                ) { mode in
                    model.setClimateHVACMode(entityID: entityID, mode: mode)
                }

                menuControl(
                    title: "Preset",
                    value: prettyMode(presetMode),
                    systemName: "figure.walk",
                    options: presetModes
                ) { mode in
                    setPresetMode(mode)
                }

                if !fanModes.isEmpty {
                    menuControl(
                        title: "Fan",
                        value: prettyMode(fanMode),
                        systemName: "fanblades",
                        options: fanModes
                    ) { mode in
                        model.setClimateFanMode(entityID: entityID, mode: mode)
                    }
                }

                if !swingModes.isEmpty {
                    menuControl(
                        title: "Swing",
                        value: prettyMode(swingMode),
                        systemName: "arrow.left.and.right",
                        options: swingModes
                    ) { mode in
                        model.setClimateSwingMode(entityID: entityID, mode: mode)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: targetTemperature) { newValue in
            if let localTarget = localTarget, abs(localTarget - newValue) <= max(step, 0.1) * 0.55 {
                self.localTarget = nil
            }
        }
    }

    private var currentTemperature: Double {
        state.attributes["current_temperature"]?.asDouble ?? targetTemperature
    }

    private var targetTemperature: Double {
        state.attributes["temperature"]?.asDouble ?? currentTemperature
    }

    private var visibleTargetTemperature: Double {
        localTarget ?? targetTemperature
    }

    private var minTemperature: Double {
        state.attributes["min_temp"]?.asDouble ?? 16
    }

    private var maxTemperature: Double {
        state.attributes["max_temp"]?.asDouble ?? 30
    }

    private var step: Double {
        state.attributes["target_temp_step"]?.asDouble ?? 0.5
    }

    private var temperatureUnit: String {
        state.attributes["temperature_unit"]?.asString ?? "°C"
    }

    private var hvacModes: [String] {
        state.attributes["hvac_modes"]?.asStringArray ?? ["off", "cool"]
    }

    private var presetModes: [String] {
        state.attributes["preset_modes"]?.asStringArray ?? []
    }

    private var presetMode: String {
        state.attributes["preset_mode"]?.asString ?? "none"
    }

    private var fanModes: [String] {
        state.attributes["fan_modes"]?.asStringArray ?? []
    }

    private var fanMode: String {
        state.attributes["fan_mode"]?.asString ?? ""
    }

    private var swingModes: [String] {
        state.attributes["swing_modes"]?.asStringArray ?? []
    }

    private var swingMode: String {
        state.attributes["swing_mode"]?.asString ?? ""
    }

    private var actionLabel: String {
        if let action = state.attributes["hvac_action"]?.asString {
            switch action {
            case "cooling":
                return "Cooling"
            case "heating":
                return "Heating"
            case "idle", "off":
                return "Idle"
            default:
                return prettyMode(action)
            }
        }

        if model.isOn(entityID: "fan.ac_unit_controller_ac_fan") {
            return "Cooling"
        }
        return "Idle"
    }

    private func setTarget(_ value: Double) {
        let clamped = min(max(value, minTemperature), maxTemperature)
        let rounded = (clamped / step).rounded() * step
        withAnimation(haSliderAnimation) {
            localTarget = rounded
        }
        model.setClimateTemperature(entityID: entityID, temperature: rounded)
    }

    private func setPresetMode(_ mode: String) {
        let predictedTarget = AppConfig.climatePresetTargetTemperatures[entityID]?[mode]
        if let predictedTarget = predictedTarget {
            let clamped = min(max(predictedTarget, minTemperature), maxTemperature)
            let rounded = (clamped / step).rounded() * step
            withAnimation(haSliderAnimation) {
                localTarget = rounded
            }
            model.setClimatePresetMode(entityID: entityID, mode: mode, predictedTemperature: rounded)
        } else {
            model.setClimatePresetMode(entityID: entityID, mode: mode)
        }
    }
}

struct ClimateTemperatureDial: View {
    let target: Double
    let current: Double
    let minimum: Double
    let maximum: Double
    let step: Double
    let unit: String
    let hvacMode: String
    let actionLabel: String
    let onSetTarget: (Double) -> Void
    @State private var draftTarget: Double?
    @State private var dragStart: CGPoint?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let metrics = DialMetrics(size: geometry.size)
            let targetValue = displayedTarget
            let targetProgress = progress(for: targetValue)
            let currentProgress = progress(for: current)

            ZStack {
                ClimateDialDrawing(
                    targetProgress: targetProgress,
                    currentProgress: currentProgress,
                    isCooling: hvacMode == "cool",
                    hasTemperatureDifference: abs(current - targetValue) > 0.05
                )
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard metrics.containsSliderPoint(value.location) else {
                                    return
                                }

                                if dragStart == nil {
                                    dragStart = value.startLocation
                                }

                                if dragDistance(from: dragStart ?? value.startLocation, to: value.location) > 4 {
                                    isDragging = true
                                    var transaction = Transaction()
                                    transaction.animation = nil
                                    withTransaction(transaction) {
                                        draftTarget = temperature(at: value.location, metrics: metrics)
                                    }
                                }
                            }
                            .onEnded { value in
                                guard metrics.containsSliderPoint(value.location) else {
                                    dragStart = nil
                                    isDragging = false
                                    return
                                }

                                let newTarget = temperature(at: value.location, metrics: metrics)
                                if isDragging {
                                    var transaction = Transaction()
                                    transaction.animation = nil
                                    withTransaction(transaction) {
                                        draftTarget = newTarget
                                    }
                                } else {
                                    withAnimation(haSliderAnimation) {
                                        draftTarget = newTarget
                                    }
                                }
                                dragStart = nil
                                isDragging = false
                                onSetTarget(newTarget)
                            }
                    )

                VStack(spacing: 4) {
                    Text(actionLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(width: metrics.infoWidth)
                        .frame(minHeight: 24)
                    BigTemperatureText(
                        value: targetValue,
                        unit: unit,
                        fractionDigits: fractionDigits(for: step)
                    )
                    .frame(minHeight: 64)
                    Text("")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: metrics.infoWidth)
                        .frame(minHeight: 24)
                }
                .position(metrics.center)

                VStack {
                    Spacer()
                    HStack(spacing: 24) {
                        roundActionButton(systemName: "minus") {
                            setTargetFromButton(displayedTarget - step)
                        }
                        roundActionButton(systemName: "plus") {
                            setTargetFromButton(displayedTarget + step)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(isDragging ? nil : haSliderAnimation, value: displayedTarget)
        .onChange(of: target) { newValue in
            if let draftTarget = draftTarget, abs(draftTarget - newValue) <= max(step, 0.1) * 0.55 {
                self.draftTarget = nil
            }
        }
    }

    private var displayedTarget: Double {
        draftTarget ?? target
    }

    private func progress(for value: Double) -> Double {
        guard maximum > minimum else {
            return 0
        }
        return Swift.min(Swift.max((value - minimum) / (maximum - minimum), 0), 1)
    }

    private func temperature(at location: CGPoint, metrics: DialMetrics) -> Double {
        let progress = metrics.progress(at: location)
        let snap = max(step, 0.1)
        let raw = minimum + progress * (maximum - minimum)
        let snapped = (raw / snap).rounded() * snap
        return Swift.min(Swift.max(snapped, minimum), maximum)
    }

    private func setTargetFromButton(_ value: Double) {
        let clamped = Swift.min(Swift.max(value, minimum), maximum)
        let snap = max(step, 0.1)
        let snapped = (clamped / snap).rounded() * snap
        withAnimation(haSliderAnimation) {
            draftTarget = snapped
        }
        onSetTarget(snapped)
    }

    private func dragDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }
}

struct BigTemperatureText: View {
    let value: Double
    let unit: String
    let fractionDigits: Int

    var body: some View {
        let parts = splitTemperature(value, fractionDigits: fractionDigits)

        HStack(alignment: .bottom, spacing: 0) {
            Text(parts.integer)
                .font(.system(size: 57, weight: .medium))
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 0) {
                Text(unit)
                    .font(.system(size: 57 * 0.33, weight: .medium))
                    .lineLimit(1)
                Text(parts.decimal)
                    .font(.system(size: 57 * 0.42, weight: .medium))
                    .frame(minHeight: 57 * 0.42 * 1.33, alignment: .bottom)
            }
            .padding(.vertical, 4)
        }
    }
}

struct ClimateDialDrawing: View, Animatable {
    var targetProgress: Double
    let currentProgress: Double
    let isCooling: Bool
    let hasTemperatureDifference: Bool

    var animatableData: Double {
        get { targetProgress }
        set { targetProgress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let metrics = DialMetrics(size: size)
            let style = StrokeStyle(lineWidth: metrics.trackStrokeWidth, lineCap: .round, lineJoin: .round)
            let highlightStart = Swift.min(targetProgress, currentProgress)
            let highlightEnd = Swift.max(targetProgress, currentProgress)

            context.stroke(
                dialArcPath(metrics: metrics, from: 0, to: 1),
                with: .color(Color.white.opacity(0.10)),
                style: style
            )

            if isCooling, hasTemperatureDifference {
                context.stroke(
                    dialArcPath(metrics: metrics, from: highlightStart, to: highlightEnd),
                    with: .color(Color(red: 0.10, green: 0.48, blue: 0.95)),
                    style: style
                )
            }

            context.fill(
                circlePath(center: metrics.point(progress: currentProgress), diameter: 7),
                with: .color(Color.white.opacity(0.9))
            )

            let targetPoint = metrics.point(progress: targetProgress)
            context.addFilter(.shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1))
            context.fill(
                circlePath(center: targetPoint, diameter: 24),
                with: .color(targetOuterColor)
            )
            context.fill(
                circlePath(center: targetPoint, diameter: 18),
                with: .color(.white)
            )
        }
    }

    private var targetOuterColor: Color {
        isCooling ? Color(red: 0.10, green: 0.48, blue: 0.95) : Color.white.opacity(0.25)
    }
}

private struct DialMetrics {
    static let startAngle = 135.0
    static let sweepAngle = 270.0

    private let scale: CGFloat
    let center: CGPoint
    let radius: CGFloat
    let trackStrokeWidth: CGFloat
    let infoWidth: CGFloat

    init(size: CGSize) {
        self.scale = Swift.min(size.width, size.height) / 320
        self.center = CGPoint(x: size.width / 2, y: size.height / 2)
        self.radius = 145 * scale
        self.trackStrokeWidth = 24 * scale
        self.infoWidth = 192 * scale
    }

    func point(progress: Double) -> CGPoint {
        let clamped = Swift.min(Swift.max(progress, 0), 1)
        let angle = CGFloat((Self.startAngle + Self.sweepAngle * clamped) * .pi / 180)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    func progress(at point: CGPoint) -> Double {
        var angle = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if angle < 0 {
            angle += 360
        }

        let endAngle = Self.startAngle + Self.sweepAngle
        let wrappedEndAngle = endAngle - 360
        if angle < Self.startAngle {
            if angle <= wrappedEndAngle {
                angle += 360
            } else {
                let distanceToStart = Self.startAngle - angle
                let distanceToEnd = angle - wrappedEndAngle
                angle = distanceToStart <= distanceToEnd ? Self.startAngle : endAngle
            }
        }

        let clamped = Swift.min(Swift.max(angle, Self.startAngle), endAngle)
        return (clamped - Self.startAngle) / Self.sweepAngle
    }

    func containsSliderPoint(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let hitWidth = max(trackStrokeWidth * 1.45, 34)
        guard distance >= radius - hitWidth, distance <= radius + hitWidth else {
            return false
        }

        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 {
            angle += 360
        }

        let endAngle = Self.startAngle + Self.sweepAngle
        let wrappedEndAngle = endAngle - 360
        return angle >= Self.startAngle || angle <= wrappedEndAngle
    }
}

private func dialArcPath(metrics: DialMetrics, from: Double, to: Double) -> Path {
    let start = Swift.min(Swift.max(from, 0), 1)
    let end = Swift.min(Swift.max(to, 0), 1)
    let lower = Swift.min(start, end)
    let upper = Swift.max(start, end)
    let steps = max(Int((upper - lower) * 120), 2)
    var path = Path()

    for index in 0...steps {
        let progress = lower + (upper - lower) * Double(index) / Double(steps)
        let point = metrics.point(progress: progress)
        if index == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }

    return path
}

private func circlePath(center: CGPoint, diameter: CGFloat) -> Path {
    Path(ellipseIn: CGRect(
        x: center.x - diameter / 2,
        y: center.y - diameter / 2,
        width: diameter,
        height: diameter
    ))
}

struct FanDetailContent: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let state: HAState

    private let speeds: [(label: String, percentage: Int)] = [
        ("Off", 0),
        ("Low", 33),
        ("Medium", 66),
        ("High", 100),
    ]

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 5) {
                Text("\(currentPercentage)%")
                    .font(.system(size: 38, weight: .medium))
                Text(model.detailTime(state.lastChanged))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }

            VStack(spacing: 0) {
                ForEach(speeds, id: \.label) { speed in
                    Button(action: {
                        model.setFanPercentage(entityID: entityID, percentage: speed.percentage)
                    }) {
                        VStack(spacing: 5) {
                            Image(systemName: speed.percentage == 0 ? "fan.slash" : "fanblades")
                                .font(.system(size: 18, weight: .semibold))
                            Text(speed.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(width: 104, height: 66)
                        .background(selected(speed.percentage) ? Color.cyan : Color(red: 0.08, green: 0.28, blue: 0.31))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))

            DetailHistoryGraph(entityID: entityID, title: "History", hours: 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var currentPercentage: Int {
        if state.state == "off" {
            return 0
        }
        return Int((state.attributes["percentage"]?.asDouble ?? 0).rounded())
    }

    private func selected(_ percentage: Int) -> Bool {
        if percentage == 0 {
            return currentPercentage == 0
        }
        return abs(currentPercentage - percentage) <= 17
    }
}

struct SensorDetailContent: View {
    let entityID: String
    let state: HAState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailStateRow(entityID: entityID, state: state)
            DetailHistoryGraph(entityID: entityID, title: "History", hours: 24)
            AttributesSection(entityID: entityID, state: state)
        }
    }
}

struct SwitchDetailContent: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let state: HAState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Power")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.detailTime(state.lastChanged))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.52))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.isOn(entityID: entityID) },
                    set: { model.setPower(entityID: entityID, isOn: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            DetailHistoryGraph(entityID: entityID, title: "History", hours: 24)
            AttributesSection(entityID: entityID, state: state)
        }
    }
}

struct DefaultEntityDetailContent: View {
    let entityID: String
    let state: HAState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailStateRow(entityID: entityID, state: state)
            AttributesSection(entityID: entityID, state: state)
        }
    }
}

struct DetailStateRow: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let state: HAState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DomainIcon(entityID: entityID)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName(for: entityID))
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.detailTime(state.lastChanged))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.52))
                }
                Spacer()
                Text(model.displayState(for: entityID))
                    .font(.system(size: 15, weight: .semibold))
            }
        }
    }
}

struct DetailHistoryGraph: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let title: String
    let hours: Int
    @State private var hoverLocation: CGPoint?
    @State private var zoomScale: CGFloat = 1
    @State private var panFraction: Double = 1
    @State private var windowAnchor: Double = Date().timeIntervalSince1970

    var body: some View {
        let effectiveHours = AppConfig.graphTimeRangePolicy.detailDefault.hours
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(effectiveHours)h")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.8))
            }

            if let history = model.detailHistory(entityID: entityID, hours: effectiveHours) {
                let displayUnit = HAHistoryGraphClassifier.displayUnit(
                    entityID: entityID,
                    currentUnit: model.unit(for: entityID),
                    currentAttributes: model.states[entityID]?.attributes,
                    history: history
                )
                let windowEnd = windowAnchor
                let windowStart = windowEnd - Double(effectiveHours) * 3600
                BitmapLineChart(
                    unit: displayUnit,
                    inputs: [
                        GraphRenderSeriesInput(
                            cacheScope: "detail:\(entityID):\(effectiveHours)h",
                            entityID: entityID,
                            name: model.displayName(for: entityID),
                            unit: displayUnit,
                            color: graphColor(for: entityID),
                            history: history,
                            windowStart: windowStart,
                            windowEnd: windowEnd,
                            tooltipFormatting: model.graphTooltipFormatting(for: entityID)
                        ),
                    ],
                    zoomScale: zoomScale,
                    panFraction: panFraction,
                    hoverLocation: $hoverLocation
                ) { delta, anchorFraction, maxZoom in
                    let currentZoom = zoomScale
                    let nextZoom = min(max(currentZoom * CGFloat(1 + delta), 1), maxZoom)
                    zoomScale = nextZoom
                    panFraction = anchoredPanFraction(
                        oldZoom: currentZoom,
                        newZoom: nextZoom,
                        oldPanFraction: panFraction,
                        anchorFraction: anchorFraction
                    )
                    AppLog("onMagnify: delta=\(delta) newZoom=\(zoomScale) newPan=\(panFraction)", severity: .debug, category: .interaction)
                } onPan: { delta in
                    guard zoomScale > 1.01 else {
                        return
                    }
                    let old = panFraction
                    panFraction = min(max(panFraction - panDelta(for: delta, zoomScale: zoomScale), 0), 1)
                    AppLog("onPan: scrollDelta=\(delta) oldPan=\(old) newPan=\(panFraction)", severity: .debug, category: .interaction)
                }
                .frame(height: 230)
                .onChange(of: "\(history.points.count):\(history.contentRevision)") { _ in
                    if zoomScale <= 1.01 && panFraction >= 0.995 {
                        windowAnchor = Date().timeIntervalSince1970
                    }
                }
                .onChange(of: zoomScale) { _ in
                    if zoomScale <= 1.01 && panFraction >= 0.995 {
                        windowAnchor = Date().timeIntervalSince1970
                    }
                }
                .onChange(of: panFraction) { _ in
                    if zoomScale <= 1.01 && panFraction >= 0.995 {
                        windowAnchor = Date().timeIntervalSince1970
                    }
                }
            } else if case let .error(message)? = model.detailHistoryStatus(
                entityID: entityID,
                hours: effectiveHours
            ) {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.yellow)
                    Text("History unavailable")
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 230)
                .background(Color.black.opacity(0.18))
                .cornerRadius(4)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading history")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, minHeight: 230)
                .background(Color.black.opacity(0.18))
                .cornerRadius(4)
            }
        }
        .onAppear {
            model.loadDetailHistory(entityID: entityID, hours: effectiveHours)
        }
        .onDisappear {
            model.unloadDetailHistory(entityID: entityID, hours: effectiveHours)
        }
    }
}

struct AttributesSection: View {
    @EnvironmentObject private var model: DashboardViewModel
    let entityID: String
    let state: HAState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 8) {
                detailRow("Last changed", model.detailTime(state.lastChanged))
                detailRow("Last updated", model.detailTime(state.lastUpdated))
            }

            Text("Attributes")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 4)

            ForEach(state.attributes.keys.sorted(), id: \.self) { key in
                if let value = state.attributes[key] {
                    detailRow(key, model.stringValue(value))
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.52))
            Spacer(minLength: 24)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}

private func roundActionButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .medium))
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .background(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
    }
    .buttonStyle(.plain)
}

private let haSliderAnimation = Animation.timingCurve(0.42, 0, 0.58, 1, duration: 0.30)

private func menuControl(
    title: String,
    value: String,
    systemName: String,
    options: [String],
    action: @escaping (String) -> Void
) -> some View {
    Menu {
        ForEach(options, id: \.self) { option in
            Button(prettyMode(option)) {
                action(option)
            }
        }
    } label: {
        HStack(spacing: 9) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                Text(value.isEmpty ? "Unavailable" : value)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .frame(minWidth: 102, minHeight: 40)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
        .cornerRadius(8)
    }
    .buttonStyle(.plain)
    .menuStyle(BorderlessButtonMenuStyle())
    .disabled(options.isEmpty)
}

private func prettyMode(_ value: String) -> String {
    if value == "none" {
        return "None"
    }
    if value == "fan_only" {
        return "Fan only"
    }
    return value
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
}

private func formatTemperature(_ value: Double, unit: String) -> String {
    "\(formatTemperatureValue(value)) \(unit)"
}

private func formatTemperatureValue(_ value: Double) -> String {
    abs(value.rounded() - value) < 0.05
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
}

private func fractionDigits(for step: Double) -> Int {
    let positiveStep = abs(step)
    guard positiveStep > 0 else {
        return 0
    }

    var digits = 0
    var scaled = positiveStep
    while digits < 3, abs(scaled.rounded() - scaled) > 0.000001 {
        scaled *= 10
        digits += 1
    }

    return max(digits, positiveStep < 1 ? 1 : 0)
}

private func splitTemperature(_ value: Double, fractionDigits: Int) -> (integer: String, decimal: String) {
    let formatted = String(format: "%.\(fractionDigits)f", value)
    guard fractionDigits > 0 else {
        return (formatted, "")
    }

    let parts = formatted.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let integer = parts.first.map(String.init) ?? formatted
    let decimalValue = parts.count > 1 ? String(parts[1]) : String(repeating: "0", count: fractionDigits)
    return (integer, ".\(decimalValue)")
}

private extension JSONValue {
    var asString: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var asDouble: Double? {
        switch self {
        case let .double(value):
            return value
        case let .int(value):
            return Double(value)
        case let .string(value):
            return Double(value)
        default:
            return nil
        }
    }

    var asStringArray: [String]? {
        if case let .array(values) = self {
            return values.compactMap(\.asString)
        }
        return nil
    }
}

struct CardTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 21, weight: .medium))
            .lineLimit(1)
            .foregroundColor(.white.opacity(0.86))
    }
}

struct DomainIcon: View {
    let entityID: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(0.13))
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private var domain: String {
        String(entityID.split(separator: ".").first ?? "")
    }

    private var symbol: String {
        switch domain {
        case "sensor":
            if entityID.contains("temperature") {
                return "thermometer"
            }
            if entityID.contains("humidity") {
                return "drop.fill"
            }
            return "waveform.path.ecg"
        case "binary_sensor":
            return "circle"
        case "switch", "input_boolean":
            return "power"
        case "fan":
            return "fanblades"
        case "person", "device_tracker":
            return "person.fill"
        case "weather":
            return "cloud.sun.fill"
        case "climate":
            return "thermometer.medium"
        default:
            return "smallcircle.filled.circle"
        }
    }

    private var color: Color {
        switch domain {
        case "sensor":
            return Color(red: 0.2, green: 0.58, blue: 0.86)
        case "binary_sensor":
            return Color(red: 0.2, green: 0.58, blue: 0.86)
        case "switch", "input_boolean":
            return Color(red: 0.2, green: 0.72, blue: 0.38)
        case "fan":
            return Color(red: 0.2, green: 0.58, blue: 0.86)
        case "person", "device_tracker":
            return Color(red: 0.2, green: 0.58, blue: 0.86)
        case "weather":
            return Color.yellow
        case "climate":
            return Color.orange
        default:
            return Color.white.opacity(0.75)
        }
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color(red: 0.095, green: 0.1, blue: 0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(8)
    }
}

func graphChartLifecycleToken(renderToken: String, feedGeneration: UUID?) -> String {
    "\(renderToken)::feed:\(feedGeneration?.uuidString ?? "none")"
}

extension GraphColor {
    var swiftUIColor: Color {
        Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}

func graphColor(for entityID: String) -> GraphColor {
    let hash = abs(entityID.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
    return graphColor(at: hash % graphPaletteCount)
}

private let graphPaletteCount = 6

func graphColor(at index: Int) -> GraphColor {
    switch abs(index) % graphPaletteCount {
    case 0:
        return GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1)
    case 1:
        return GraphColor(red: 0.93, green: 0.66, blue: 0.22, alpha: 1)
    case 2:
        return GraphColor(red: 0.4, green: 0.86, blue: 0.82, alpha: 1)
    case 3:
        return GraphColor(red: 0.95, green: 0.32, blue: 0.5, alpha: 1)
    case 4:
        return GraphColor(red: 0.66, green: 0.42, blue: 0.92, alpha: 1)
    default:
        return GraphColor(red: 0.45, green: 0.76, blue: 0.32, alpha: 1)
    }
}

func color(for entityID: String) -> Color {
    graphColor(for: entityID).swiftUIColor
}
