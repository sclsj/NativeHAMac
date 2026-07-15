import Foundation
import NativeHACore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedGraphHours = AppConfig.defaultGraphHours
    @Published var views: [LovelaceView] = []
    @Published var states: [String: HAState] = [:]
    @Published var histories: [String: [HAHistorySeries]] = [:]
    @Published var detailHistories: [String: HAHistorySeries] = [:]
    @Published var status = "Starting"
    @Published var errorMessage: String?
    @Published var activeBaseURL: URL?
    @Published var showEntityIDs = AppConfig.showEntityIDsByDefault
    @Published var selectedEntityID: String?

    private var restClient: HomeAssistantRESTClient?
    private var webSocketClient: HomeAssistantWebSocketClient?
    private var hasStarted = false
    private var pendingStates: [String: HAState] = [:]
    private var pendingHistoryStates: [HAState] = []
    private var isStateFlushScheduled = false
    private let isoFormatter = ISO8601DateFormatter()
    private let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var homeView: LovelaceView? {
        views.first(where: { $0.path == "default_view" }) ?? views.first
    }

    var homeCards: [LovelaceCard] {
        guard let cards = homeView?.cards else {
            return []
        }

        return cleanCards(flatten(cards))
    }

    var dashboardColumns: [[LovelaceCard]] {
        var columns = Array(repeating: [LovelaceCard](), count: AppConfig.dashboardColumnCount)
        var unplaced: [LovelaceCard] = []

        for card in homeCards {
            if let rule = AppConfig.cardColumnRules.first(where: { $0.matches(card) }) {
                let index = min(max(rule.column, 0), columns.count - 1)
                columns[index].append(card)
            } else {
                unplaced.append(card)
            }
        }

        for card in unplaced {
            let index = columns.enumerated().min(by: { $0.element.count < $1.element.count })?.offset ?? 0
            columns[index].append(card)
        }

        return columns
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        Task {
            await load()
        }
    }

    func setGraphHours(_ hours: Int) {
        guard selectedGraphHours != hours else {
            return
        }

        selectedGraphHours = hours
        Task {
            await loadHistories()
        }
    }

    func displayName(for entityID: String) -> String {
        if
            let nameValue = states[entityID]?.attributes["friendly_name"],
            case let .string(name) = nameValue
        {
            return name
        }

        return entityID
            .split(separator: ".")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ").capitalized }
            ?? entityID
    }

    func displayState(for entityID: String) -> String {
        guard let state = states[entityID] else {
            return "Unavailable"
        }

        var value = state.state
        if let numeric = Double(value) {
            value = formatNumber(numeric)
        }

        if let unit = unit(for: entityID), !unit.isEmpty {
            return "\(value) \(unit)"
        }

        return value.replacingOccurrences(of: "_", with: " ")
    }

    func unit(for entityID: String) -> String? {
        guard
            let unitValue = states[entityID]?.attributes["unit_of_measurement"],
            case let .string(unit) = unitValue
        else {
            return nil
        }

        return unit
    }

    func isOn(entityID: String) -> Bool {
        states[entityID]?.state == "on"
    }

    func canToggle(entityID: String) -> Bool {
        switch domain(for: entityID) {
        case "switch", "fan", "input_boolean", "automation":
            return true
        default:
            return false
        }
    }

    func setPower(entityID: String, isOn: Bool) {
        guard canToggle(entityID: entityID) else {
            return
        }

        performPowerCall(entityID: entityID, isOn: isOn)
    }

    func setPower(entityIDs: [String], isOn: Bool) {
        for entityID in entityIDs where canToggle(entityID: entityID) {
            performPowerCall(entityID: entityID, isOn: isOn)
        }
    }

    func setFanPercentage(entityID: String, percentage: Int) {
        if percentage <= 0 {
            performPowerCall(entityID: entityID, isOn: false)
            applyOptimisticAttributes(
                entityID: entityID,
                state: "off",
                attributes: ["percentage": .int(0)]
            )
            return
        }

        applyOptimisticAttributes(
            entityID: entityID,
            state: "on",
            attributes: ["percentage": .int(percentage)]
        )
        callService(
            domain: "fan",
            service: "set_percentage",
            data: [
                "entity_id": .string(entityID),
                "percentage": .int(percentage),
            ],
            errorContext: "Fan speed failed for \(entityID)"
        )
    }

    func setClimateTemperature(entityID: String, temperature: Double) {
        applyOptimisticAttributes(entityID: entityID, attributes: ["temperature": .double(temperature)])
        callService(
            domain: "climate",
            service: "set_temperature",
            data: [
                "entity_id": .string(entityID),
                "temperature": .double(temperature),
            ],
            errorContext: "Temperature change failed for \(entityID)"
        )
    }

    func setClimateHVACMode(entityID: String, mode: String) {
        guard states[entityID]?.state != mode else {
            return
        }

        applyOptimisticAttributes(entityID: entityID, state: mode, attributes: [:])
        callService(
            domain: "climate",
            service: "set_hvac_mode",
            data: [
                "entity_id": .string(entityID),
                "hvac_mode": .string(mode),
            ],
            errorContext: "Mode change failed for \(entityID)"
        )
    }

    func setClimatePresetMode(entityID: String, mode: String, predictedTemperature: Double? = nil) {
        guard states[entityID]?.attributes["preset_mode"]?.asString != mode else {
            if let predictedTemperature = predictedTemperature {
                applyOptimisticAttributes(
                    entityID: entityID,
                    attributes: ["temperature": .double(predictedTemperature)]
                )
            }
            return
        }

        var updates: [String: JSONValue] = ["preset_mode": .string(mode)]
        if let predictedTemperature = predictedTemperature {
            updates["temperature"] = .double(predictedTemperature)
        }

        applyOptimisticAttributes(entityID: entityID, attributes: updates)
        callService(
            domain: "climate",
            service: "set_preset_mode",
            data: [
                "entity_id": .string(entityID),
                "preset_mode": .string(mode),
            ],
            errorContext: "Preset change failed for \(entityID)"
        )
    }

    func setClimateFanMode(entityID: String, mode: String) {
        guard states[entityID]?.attributes["fan_mode"]?.asString != mode else {
            return
        }

        applyOptimisticAttributes(entityID: entityID, attributes: ["fan_mode": .string(mode)])
        callService(
            domain: "climate",
            service: "set_fan_mode",
            data: [
                "entity_id": .string(entityID),
                "fan_mode": .string(mode),
            ],
            errorContext: "Fan mode change failed for \(entityID)"
        )
    }

    func setClimateSwingMode(entityID: String, mode: String) {
        guard states[entityID]?.attributes["swing_mode"]?.asString != mode else {
            return
        }

        applyOptimisticAttributes(entityID: entityID, attributes: ["swing_mode": .string(mode)])
        callService(
            domain: "climate",
            service: "set_swing_mode",
            data: [
                "entity_id": .string(entityID),
                "swing_mode": .string(mode),
            ],
            errorContext: "Swing mode change failed for \(entityID)"
        )
    }

    func allOn(entityIDs: [String]) -> Bool {
        let toggleable = entityIDs.filter { canToggle(entityID: $0) }
        guard !toggleable.isEmpty else {
            return false
        }
        return toggleable.allSatisfy { isOn(entityID: $0) }
    }

    func refreshHistories() {
        Task {
            await loadHistories()
        }
    }

    func historyKey(for card: LovelaceCard) -> String {
        let entities = historyEntityIDs(for: card)
        return "\(selectedGraphHours):\(entities.joined(separator: ","))"
    }

    func historySeries(for card: LovelaceCard) -> [HAHistorySeries]? {
        histories[historyKey(for: card)]
    }

    func detailHistory(entityID: String, hours: Int) -> HAHistorySeries? {
        detailHistories[detailHistoryKey(entityID: entityID, hours: hours)]
    }

    func loadDetailHistory(entityID: String, hours: Int) {
        let key = detailHistoryKey(entityID: entityID, hours: hours)
        guard detailHistories[key] == nil else {
            return
        }

        Task {
            await loadDetailHistory(entityID: entityID, hours: hours, key: key)
        }
    }

    func historyEntityIDs(for card: LovelaceCard) -> [String] {
        (card.entities?.compactMap(\.entity) ?? [])
            .filter { !AppConfig.hiddenEntityIDs.contains($0) }
    }

    func openDetails(entityID: String) {
        selectedEntityID = entityID
    }

    func closeDetails() {
        selectedEntityID = nil
    }

    func domain(for entityID: String) -> String {
        String(entityID.split(separator: ".").first ?? "")
    }

    func date(from point: HAHistoryPoint) -> Date? {
        historyDate(from: point)
    }

    func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    func detailTime(_ value: String?) -> String {
        guard let value = value, let date = parseDate(value) else {
            return "Unknown"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    func weatherSummary(_ state: String) -> String {
        switch state {
        case "partlycloudy":
            return "Partly cloudy"
        default:
            return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    func stringValue(_ value: JSONValue) -> String {
        switch value {
        case let .string(value):
            return value
        case let .int(value):
            return "\(value)"
        case let .double(value):
            return formatNumber(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .object:
            return "{...}"
        case .array:
            return "[...]"
        case .null:
            return "null"
        }
    }

    private func load() async {
        do {
            status = "Reading token"
            let token = try loadToken()

            status = "Connecting"
            let connection = try await firstWorkingConnection(token: token)
            activeBaseURL = connection.baseURL
            restClient = connection.restClient

            status = "Loading states"
            let stateList = try await connection.restClient.fetchStates()
            states = Dictionary(uniqueKeysWithValues: stateList.map { ($0.entityId, $0) })

            status = "Loading dashboard"
            let webSocket = HomeAssistantWebSocketClient(configuration: connection.configuration)
            try await webSocket.connect()
            let config = try await webSocket.fetchLovelaceConfig()
            views = config.views
            webSocketClient = webSocket

            status = "Live"
            try await webSocket.subscribeToStateChanges()

            Task { [weak self] in
                await self?.loadHistories()
            }

            Task { [weak self, webSocket] in
                do {
                    try await webSocket.receiveStateChanges { [weak self] state in
                        self?.queueStateUpdate(state)
                    }
                } catch {
                    await MainActor.run {
                        self?.status = "Disconnected"
                        self?.errorMessage = "WebSocket disconnected: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            status = "Error"
            errorMessage = error.localizedDescription
        }
    }

    private func parseDate(_ value: String) -> Date? {
        fractionalISOFormatter.date(from: value) ?? isoFormatter.date(from: value)
    }

    private func queueStateUpdate(_ state: HAState) {
        pendingStates[state.entityId] = state
        pendingHistoryStates.append(state)

        guard !isStateFlushScheduled else {
            return
        }

        isStateFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: AppConfig.realtimeUpdateCoalesceNanoseconds)
            self?.flushPendingStates()
        }
    }

    private func flushPendingStates() {
        guard !pendingStates.isEmpty else {
            isStateFlushScheduled = false
            return
        }

        let historyStates = pendingHistoryStates

        for (entityID, state) in pendingStates {
            states[entityID] = state
        }
        pendingStates.removeAll()
        pendingHistoryStates.removeAll()
        isStateFlushScheduled = false

        appendRealtimeHistoryStates(historyStates)
    }

    private func loadHistories() async {
            guard let restClient = restClient else {
                return
            }

            do {
                let requests = historyRequests()
                var nextHistories: [String: [HAHistorySeries]] = histories

                for request in requests {
                    nextHistories[request.key] = try await restClient.fetchHistory(
                        entityIDs: request.entityIDs,
                        hoursToShow: request.hoursToShow
                    )
                }

                histories = nextHistories
            } catch {
                errorMessage = "History refresh failed: \(error.localizedDescription)"
            }
        }


    private func loadDetailHistory(entityID: String, hours: Int, key: String) async {
        guard let restClient = restClient else {
            return
        }

        do {
            let series = try await restClient.fetchHistory(entityIDs: [entityID], hoursToShow: hours)
            if let first = series.first {
                detailHistories[key] = first
            }
        } catch {
            errorMessage = "Detail history failed for \(entityID): \(error.localizedDescription)"
        }
    }

    private func detailHistoryKey(entityID: String, hours: Int) -> String {
        "\(hours):\(entityID)"
    }

    private func appendRealtimeHistoryStates(_ states: [HAState]) {
        let pointsByEntity = Dictionary(grouping: states.compactMap { realtimeHistoryPoint(from: $0) }) { item in
            item.point.entityId ?? item.entityID
        }

        guard !pointsByEntity.isEmpty else {
            return
        }

        var nextHistories = histories
        var historiesChanged = false
        for key in Array(nextHistories.keys) {
            guard
                let hours = hoursToShow(fromHistoryKey: key),
                let requestedEntityIDs = entityIDs(fromHistoryKey: key),
                let series = nextHistories[key]
            else {
                continue
            }

            let relevantPoints = pointsByEntity.filter { requestedEntityIDs.contains($0.key) }
            guard !relevantPoints.isEmpty else {
                continue
            }

            let cutoff = Date().addingTimeInterval(TimeInterval(-max(hours, 1) * 60 * 60))
            let merged = append(pointsByEntity: relevantPoints, to: series, cutoff: cutoff)
            if merged != series {
                nextHistories[key] = merged
                historiesChanged = true
            }
        }

        if historiesChanged {
            histories = nextHistories
        }

        var nextDetailHistories = detailHistories
        var detailChanged = false
        for (key, series) in Array(nextDetailHistories) {
            guard
                let request = detailHistoryRequest(fromKey: key),
                let updates = pointsByEntity[series.entityID] ?? pointsByEntity[request.entityID]
            else {
                continue
            }

            let cutoff = Date().addingTimeInterval(TimeInterval(-max(request.hours, 1) * 60 * 60))
            let mergedPoints = merge(points: series.points, with: updates.map { $0.point }, cutoff: cutoff)
            if mergedPoints != series.points {
                nextDetailHistories[key] = HAHistorySeries(entityID: series.entityID, points: mergedPoints)
                detailChanged = true
            }
        }

        if detailChanged {
            detailHistories = nextDetailHistories
        }
    }

    private func append(
        pointsByEntity: [String: [RealtimeHistoryPoint]],
        to seriesList: [HAHistorySeries],
        cutoff: Date
    ) -> [HAHistorySeries] {
        var output = seriesList
        var existingEntityIDs = Set(seriesList.map(\.entityID))

        for index in output.indices {
            let entityID = output[index].entityID
            guard let updates = pointsByEntity[entityID] else {
                continue
            }

            let mergedPoints = merge(points: output[index].points, with: updates.map { $0.point }, cutoff: cutoff)
            output[index] = HAHistorySeries(entityID: entityID, points: mergedPoints)
        }

        for (entityID, updates) in pointsByEntity where !existingEntityIDs.contains(entityID) {
            let mergedPoints = merge(points: [], with: updates.map { $0.point }, cutoff: cutoff)
            guard !mergedPoints.isEmpty else {
                continue
            }
            output.append(HAHistorySeries(entityID: entityID, points: mergedPoints))
            existingEntityIDs.insert(entityID)
        }

        return output
    }

    private func merge(
        points: [HAHistoryPoint],
        with updates: [HAHistoryPoint],
        cutoff: Date
    ) -> [HAHistoryPoint] {
        let sortedUpdates = updates
            .filter { historyDate(from: $0) != nil }
            .sorted {
                (historyDate(from: $0) ?? .distantPast) < (historyDate(from: $1) ?? .distantPast)
            }

        guard !sortedUpdates.isEmpty else {
            return points
        }

        var merged = points
        merged.reserveCapacity(points.count + sortedUpdates.count)

        for point in sortedUpdates {
            guard let timestamp = historyDate(from: point) else {
                continue
            }

            if let last = merged.last, let lastTimestamp = historyDate(from: last) {
                let delta = timestamp.timeIntervalSince(lastTimestamp)
                if abs(delta) < 0.001 {
                    merged[merged.count - 1] = point
                } else if delta > 0 {
                    merged.append(point)
                } else {
                    let insertionIndex = upperBound(in: merged, timestamp: timestamp)
                    if insertionIndex > 0,
                       let previousTimestamp = historyDate(from: merged[insertionIndex - 1]),
                       abs(timestamp.timeIntervalSince(previousTimestamp)) < 0.001
                    {
                        merged[insertionIndex - 1] = point
                    } else {
                        merged.insert(point, at: insertionIndex)
                    }
                }
            } else {
                merged.append(point)
            }
        }

        let cutoffIndex = lowerBound(in: merged, timestamp: cutoff)
        if cutoffIndex > 0 {
            merged.removeFirst(cutoffIndex)
        }
        return merged
    }

    private func realtimeHistoryPoint(from state: HAState) -> RealtimeHistoryPoint? {
        guard isHistoryRenderableState(state.state) else {
            return nil
        }

        let point = HAHistoryPoint(
            entityId: state.entityId,
            state: state.state,
            attributes: state.attributes,
            lastChanged: state.lastChanged,
            lastUpdated: state.lastUpdated
        )

        guard historyDate(from: point) != nil else {
            return nil
        }

        return RealtimeHistoryPoint(entityID: state.entityId, point: point)
    }

    private func historyDate(from point: HAHistoryPoint) -> Date? {
        if let lastChanged = point.lastChanged, let date = parseDate(lastChanged) {
            return date
        }

        if let lastUpdated = point.lastUpdated, let date = parseDate(lastUpdated) {
            return date
        }

        return nil
    }

    private func isHistoryRenderableState(_ value: String) -> Bool {
        !value.isEmpty
    }

    private func lowerBound(in points: [HAHistoryPoint], timestamp: Date) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            guard let date = historyDate(from: points[mid]) else {
                low = mid + 1
                continue
            }

            if date < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func upperBound(in points: [HAHistoryPoint], timestamp: Date) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            guard let date = historyDate(from: points[mid]) else {
                low = mid + 1
                continue
            }

            if date <= timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func hoursToShow(fromHistoryKey key: String) -> Int? {
        guard let rawHours = key.split(separator: ":", maxSplits: 1).first else {
            return nil
        }
        return Int(rawHours)
    }

    private func entityIDs(fromHistoryKey key: String) -> Set<String>? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return nil
        }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    private func detailHistoryRequest(fromKey key: String) -> (hours: Int, entityID: String)? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let hours = Int(parts[0]) else {
            return nil
        }
        return (hours, parts[1])
    }


    private func historyRequests() -> [HistoryRequest] {
        var requests: [HistoryRequest] = []
        collectHistoryRequests(from: homeCards, into: &requests)
        return requests.removingDuplicates()
    }

    private func collectHistoryRequests(from cards: [LovelaceCard], into requests: inout [HistoryRequest]) {
        for card in cards {
            if card.type == "history-graph" {
                let entities = historyEntityIDs(for: card)
                if !entities.isEmpty {
                    requests.append(HistoryRequest(entityIDs: entities, hoursToShow: selectedGraphHours))
                }
            }

            if let nestedCards = card.cards {
                collectHistoryRequests(from: nestedCards, into: &requests)
            }
        }
    }

    private func flatten(_ cards: [LovelaceCard]) -> [LovelaceCard] {
        cards.flatMap { card -> [LovelaceCard] in
            if card.type == "vertical-stack", let nestedCards = card.cards {
                return flatten(nestedCards)
            }
            return [card]
        }
    }

    private func cleanCards(_ cards: [LovelaceCard]) -> [LovelaceCard] {
        cards.compactMap { card in
            let configuredEntities = card.entities ?? []
            let extraEntities = card.title.flatMap { AppConfig.extraEntitiesByCardTitle[$0] } ?? []
            let mergedEntities = (extraEntities + configuredEntities).removingDuplicateEntities()
            let cleanedEntities = (card.entities == nil && extraEntities.isEmpty ? nil : mergedEntities).map { entities in
                entities.filter { entityRef in
                    guard let entity = entityRef.entity else {
                        return true
                    }
                    return !AppConfig.hiddenEntityIDs.contains(entity)
                }
            }

            let cleanedNestedCards = card.cards.map { cleanCards($0) }

            if card.entities != nil, cleanedEntities?.isEmpty == true {
                return nil
            }

            if card.type == "history-graph", cleanedEntities?.isEmpty == true {
                return nil
            }

            return LovelaceCard(
                type: card.type,
                title: card.title,
                entity: card.entity,
                entities: cleanedEntities,
                cards: cleanedNestedCards,
                hoursToShow: selectedGraphHours,
                showForecast: card.showForecast,
                content: card.content
            )
        }
    }

    private func firstWorkingConnection(token: String) async throws -> Connection {
        var lastError: Error?

        for baseURL in AppConfig.baseURLs {
            let configuration = HomeAssistantConfiguration(baseURL: baseURL, accessToken: token)
            let client = HomeAssistantRESTClient(configuration: configuration)

            do {
                _ = try await client.fetchConfig()
                return Connection(
                    baseURL: baseURL,
                    configuration: configuration,
                    restClient: client
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func loadToken() throws -> String {
        try String(contentsOfFile: AppConfig.tokenFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performPowerCall(entityID: String, isOn: Bool) {
        let service = isOn ? "turn_on" : "turn_off"
        let domain = domain(for: entityID)
        applyOptimisticState(entityID: entityID, state: isOn ? "on" : "off")
        callService(
            domain: domain,
            service: service,
            data: ["entity_id": .string(entityID)],
            errorContext: "Service call failed for \(entityID)"
        )
    }

    private func callService(
        domain: String,
        service: String,
        data: [String: JSONValue],
        errorContext: String
    ) {
        guard let restClient = restClient else {
            return
        }

        Task {
            do {
                _ = try await restClient.callService(domain: domain, service: service, data: data)
            } catch {
                self.errorMessage = "\(errorContext): \(error.localizedDescription)"
            }
        }
    }

    private func applyOptimisticState(entityID: String, state: String) {
        applyOptimisticAttributes(entityID: entityID, state: state, attributes: [:])
    }

    private func applyOptimisticAttributes(
        entityID: String,
        state: String? = nil,
        attributes updates: [String: JSONValue]
    ) {
        guard let old = states[entityID] else {
            return
        }

        var attributes = old.attributes
        for (key, value) in updates {
            attributes[key] = value
        }

        states[entityID] = HAState(
            entityId: old.entityId,
            state: state ?? old.state,
            attributes: attributes,
            lastChanged: old.lastChanged,
            lastUpdated: old.lastUpdated
        )
    }

    private func formatNumber(_ value: Double) -> String {
        if abs(value) >= 100 {
            return String(format: "%.0f", value)
        }

        if abs(value) >= 10 {
            return String(format: "%.1f", value)
        }

        return String(format: "%.2f", value)
    }
}

private struct Connection {
    let baseURL: URL
    let configuration: HomeAssistantConfiguration
    let restClient: HomeAssistantRESTClient
}

private struct RealtimeHistoryPoint {
    let entityID: String
    let point: HAHistoryPoint
}

struct HistoryRequest: Hashable {
    let entityIDs: [String]
    let hoursToShow: Int

    var key: String {
        "\(hoursToShow):\(entityIDs.joined(separator: ","))"
    }
}

private extension Array where Element == HistoryRequest {
    func removingDuplicates() -> [HistoryRequest] {
        var seen = Set<String>()
        return filter { request in
            seen.insert(request.key).inserted
        }
    }
}

private extension Array where Element == LovelaceEntityRef {
    func removingDuplicateEntities() -> [LovelaceEntityRef] {
        var seen = Set<String>()
        return filter { item in
            guard let entity = item.entity else {
                return true
            }
            return seen.insert(entity).inserted
        }
    }
}

private extension JSONValue {
    var asString: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }
}
