import Foundation
import NativeHACore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedGraphHours = AppConfig.defaultGraphHours
    @Published private(set) var views: [LovelaceView] = []
    @Published var states: [String: HAState] = [:]
    @Published var histories: [String: [HAHistorySeries]] = [:]
    @Published var detailHistories: [String: HAHistorySeries] = [:]
    @Published var historyStatuses: [String: HAHistoryStreamOwnerStatus] = [:]
    @Published var detailHistoryStatuses: [String: HAHistoryStreamOwnerStatus] = [:]
    @Published var status = "Starting"
    @Published var errorMessage: String?
    @Published var activeBaseURL: URL?
    @Published var showEntityIDs = AppConfig.showEntityIDsByDefault
    @Published var selectedEntityID: String?
    private(set) var homeAssistantConfig: HAConfig?
    private(set) var frontendLocalePreferences: HAFrontendLocalePreferences?
    private(set) var entityDisplayPrecisions: [String: Int] = [:]

    private var restClient: HomeAssistantRESTClient?
    private var webSocketClient: HomeAssistantWebSocketClient?
    private var stateSubscription: HAWebSocketSubscription?
    private var connectionStatusTask: Task<Void, Never>?
    private var historySubscriptions: [String: HAHistoryStreamSubscription] = [:]
    private var historyStartupTasks: [UUID: HistoryStartupTask] = [:]
    private var detailHistorySubscriptions: [String: HAHistoryStreamSubscription] = [:]
    private var historyGenerations: [String: UUID] = [:]
    private var graphHistoryRevisionFeeds: [String: GraphHistoryRevisionFeed] = [:]
    private var desiredHistoryKeys: Set<String> = []
    private var historyReconciliationEpoch: UInt64 = 0
    private var latestConfigRequestSequence: UInt64 = 0
    private var latestDashboardOwnerOperationSequence: UInt64 = 0
    private var dashboardOwnerOperationTail: Task<Void, Never>?
    private var latestQueuedConfigCandidate: LovelacePresentationDashboard?
    private(set) var presentationDashboard: LovelacePresentationDashboard
    let graphChartMountRegistry = DashboardGraphChartMountRegistry()
    private var detailHistoryGenerations: [String: UUID] = [:]
    private var desiredDetailHistoryKeys: Set<String> = []
    private let historyNow: @Sendable () -> Date
    let graphAxisTimeFormattingOverride: GraphTooltipFormattingMetadata?
    private let historyProcessingHook: @Sendable () async -> Void
    private var hasStarted = false
    private var pendingStates: [String: HAState] = [:]
    private var isStateFlushScheduled = false
    private let isoFormatter = ISO8601DateFormatter()
    private let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var latestQueuedConfigRawValue: JSONValue? {
        latestQueuedConfigCandidate?.resolved.source.rawValue
    }

    private var latestQueuedHistoryKeys: Set<String> {
        guard let latestQueuedConfigCandidate = latestQueuedConfigCandidate else { return [] }
        return Set(historyRequests(from: latestQueuedConfigCandidate).map(\.key))
    }

    private let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    private let detailTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    init(
        webSocketClient: HomeAssistantWebSocketClient? = nil,
        initialStates: [String: HAState] = [:],
        initialViews: [LovelaceView] = [],
        homeAssistantConfig: HAConfig? = nil,
        frontendLocalePreferences: HAFrontendLocalePreferences? = nil,
        entityDisplayPrecisions: [String: Int] = [:],
        historyNow: @escaping @Sendable () -> Date = { Date() },
        graphAxisTimeFormattingOverride: GraphTooltipFormattingMetadata? = nil,
        historyProcessingHook: @escaping @Sendable () async -> Void = {}
    ) {
        let initialConfig = LovelaceConfig(views: initialViews)
        let initialResolved = LovelaceResolvedDashboard(source: initialConfig)
        self.presentationDashboard = LovelacePresentationDashboard(resolved: initialResolved)
        self.webSocketClient = webSocketClient
        self.states = initialStates
        self.views = initialViews
        self.homeAssistantConfig = homeAssistantConfig
        self.frontendLocalePreferences = frontendLocalePreferences
        self.entityDisplayPrecisions = entityDisplayPrecisions
        self.historyNow = historyNow
        self.graphAxisTimeFormattingOverride = graphAxisTimeFormattingOverride
        self.historyProcessingHook = historyProcessingHook
    }

    var homeView: LovelaceView? {
        views.first(where: { $0.path == "default_view" }) ?? views.first
    }

    var graphWindowNow: Date { historyNow() }

    var homeCards: [LovelacePresentationCard] {
        presentationDashboard.views.first(where: { $0.resolved.source.path == "default_view" })?.cards
            ?? presentationDashboard.views.first?.cards
            ?? []
    }

    var dashboardColumns: [[LovelacePresentationCard]] {
        guard presentationDashboard.views.contains(where: {
            $0.resolved.source.path == "default_view"
        }) else {
            return homeCards.isEmpty ? [] : [homeCards]
        }
        var columns = Array(repeating: [LovelacePresentationCard](), count: AppConfig.dashboardColumnCount)
        var unplaced: [LovelacePresentationCard] = []

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
        guard
            AppConfig.graphTimeRangePolicy.selection(hours: hours) != nil,
            selectedGraphHours != hours
        else {
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

    func graphTooltipFormatting(for entityID: String) -> GraphTooltipFormattingMetadata {
        GraphTooltipFormattingResolver.metadata(
            entityID: entityID,
            state: states[entityID],
            registryDisplayPrecision: entityDisplayPrecisions[entityID],
            preferences: frontendLocalePreferences,
            serverTimeZone: homeAssistantConfig?.timeZone,
            policy: AppConfig.graphTooltipFormattingPolicy
        )
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
            await refreshHistorySubscriptions()
        }
    }

    func historyKey(for card: LovelacePresentationCard) -> String {
        let entities = historyEntityIDs(for: card)
        return HistoryRequest(
            ownerID: card.nativeID,
            entityIDs: entities,
            hoursToShow: selectedGraphHours
        ).key
    }

    func historyKey(for card: LovelaceCard) -> String {
        let identity = LovelaceResolvedIdentity(
            sourcePath: LovelaceSourcePath().appending("cards", index: 0),
            rawValue: card.rawValue
        )
        return HistoryRequest(
            ownerID: identity.ownerKey,
            entityIDs: historyEntityIDs(for: card),
            hoursToShow: selectedGraphHours
        ).key
    }

    func historySeries(for card: LovelacePresentationCard) -> [HAHistorySeries]? {
        histories[historyKey(for: card)]
    }

    func historyStatus(for card: LovelacePresentationCard) -> HAHistoryStreamOwnerStatus? {
        historyStatuses[historyKey(for: card)]
    }

    func graphHistoryRevisionFeed(for card: LovelacePresentationCard) -> GraphHistoryRevisionFeed? {
        graphHistoryRevisionFeeds[historyKey(for: card)]
    }

    func detailHistory(entityID: String, hours: Int) -> HAHistorySeries? {
        detailHistories[detailHistoryKey(entityID: entityID, hours: hours)]
    }

    func detailHistoryStatus(entityID: String, hours: Int) -> HAHistoryStreamOwnerStatus? {
        detailHistoryStatuses[detailHistoryKey(entityID: entityID, hours: hours)]
    }

    func loadDetailHistory(entityID: String, hours: Int) {
        let effectiveHours = AppConfig.graphTimeRangePolicy.detailDefault.hours
        let key = detailHistoryKey(entityID: entityID, hours: effectiveHours)
        desiredDetailHistoryKeys.insert(key)
        Task {
            await startDetailHistory(entityID: entityID, hours: effectiveHours, key: key)
        }
    }

    func unloadDetailHistory(entityID: String, hours: Int) {
        let key = detailHistoryKey(entityID: entityID, hours: hours)
        desiredDetailHistoryKeys.remove(key)
        let subscription = detailHistorySubscriptions.removeValue(forKey: key)
        detailHistoryGenerations.removeValue(forKey: key)
        detailHistoryStatuses.removeValue(forKey: key)
        Task { await subscription?.cancel() }
    }

    func historyEntityIDs(for card: LovelacePresentationCard) -> [String] {
        guard card.source.diagnostic == nil else { return [] }
        return (card.rows ?? []).compactMap { row in
            guard row.source.diagnostic == nil,
                  let entityID = row.source.entity,
                  !entityID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return entityID
        }
    }

    func historyEntityIDs(for card: LovelaceCard) -> [String] {
        (card.entities?.compactMap(\.entity) ?? [])
            .filter { !AppConfig.hiddenEntityIDs.contains($0) }
    }

    func openDetails(entityID: String) {
        if let previous = selectedEntityID, previous != entityID {
            unloadDetailHistory(
                entityID: previous,
                hours: AppConfig.graphTimeRangePolicy.detailDefault.hours
            )
        }
        selectedEntityID = entityID
    }

    func closeDetails() {
        if let selectedEntityID = selectedEntityID {
            unloadDetailHistory(
                entityID: selectedEntityID,
                hours: AppConfig.graphTimeRangePolicy.detailDefault.hours
            )
        }
        selectedEntityID = nil
    }

    func domain(for entityID: String) -> String {
        String(entityID.split(separator: ".").first ?? "")
    }

    func date(from point: HAHistoryPoint) -> Date? {
        historyDate(from: point)
    }

    func shortTime(_ date: Date) -> String {
        shortTimeFormatter.string(from: date)
    }

    func detailTime(_ value: String?) -> String {
        guard let value = value, let date = parseDate(value) else {
            return "Unknown"
        }
        return detailTimeFormatter.string(from: date)
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
            homeAssistantConfig = connection.homeAssistantConfig

            status = "Loading states"
            let stateList = try await connection.restClient.fetchStates()
            states = Dictionary(uniqueKeysWithValues: stateList.map { ($0.entityId, $0) })

            status = "Loading dashboard"
            let webSocket = HomeAssistantWebSocketClient(
                configuration: connection.configuration,
                commandTimeout: AppConfig.webSocketPolicy.commandTimeout,
                receivePolicy: AppConfig.webSocketPolicy.receivePolicy,
                subscriptionDeliveryCapacity: AppConfig.webSocketPolicy.subscriptionDeliveryCapacity,
                maximumConcurrentCallbackTasks: AppConfig.webSocketPolicy.maximumConcurrentCallbackTasks
            )
            try await bootstrapDashboard(using: webSocket)
        } catch {
            status = "Error"
            errorMessage = error.localizedDescription
        }
    }

    func bootstrapDashboard(using webSocket: HomeAssistantWebSocketClient) async throws {
        try await webSocket.connect()
        do {
            async let registryResponse = try? await webSocket.fetchEntityRegistryDisplay()
            async let localeResponse = try? await webSocket.fetchFrontendLocalePreferences()
            let config = try await webSocket.fetchLovelaceConfig()
            let (registry, locale) = await (registryResponse, localeResponse)
            entityDisplayPrecisions = Dictionary(uniqueKeysWithValues:
                (registry?.entities ?? []).compactMap { entry in
                    entry.displayPrecision.map { (entry.entityID, $0) }
                }
            )
            frontendLocalePreferences = locale ?? nil
            await applyLovelaceConfig(config, startHistoryOwners: false)

            status = "Live"
            AppLog("Dashboard successfully connected and became Live", category: .lifecycle)
            let weakModel = WeakDashboardViewModelBox(self)
            stateSubscription = try await webSocket.subscribeToStateChanges { state in
                await MainActor.run {
                    weakModel.value?.queueStateUpdate(state)
                }
            }
            webSocketClient = webSocket

            Task { [weak self] in
                await self?.loadHistories()
            }

            connectionStatusTask = Task { [weak self, webSocket] in
                for await connectionState in await webSocket.connection.statusUpdates() {
                    await MainActor.run {
                        let nextStatus: String
                        switch connectionState {
                        case .ready:
                            nextStatus = "Live"
                        case .disconnected:
                            nextStatus = "Disconnected"
                        case .reconnecting:
                            nextStatus = "Reconnecting"
                        case let .authenticationFailed(message):
                            nextStatus = "Error"
                            self?.errorMessage = "WebSocket authentication failed: \(message)"
                        case .connecting:
                            nextStatus = "Connecting"
                        }
                        if self?.status != nextStatus {
                            self?.status = nextStatus
                        }
                    }
                }
            }
        } catch {
            await webSocket.disconnect()
            throw error
        }
    }

    private func parseDate(_ value: String) -> Date? {
        fractionalISOFormatter.date(from: value) ?? isoFormatter.date(from: value)
    }

    private func queueStateUpdate(_ state: HAState) {
        pendingStates[state.entityId] = state

        guard !isStateFlushScheduled else {
            return
        }

        isStateFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: AppConfig.graphRenderSchedulingPolicy.realtimeStateCoalesceNanoseconds
            )
            self?.flushPendingStates()
        }
    }

    private func flushPendingStates() {
        guard !pendingStates.isEmpty else {
            isStateFlushScheduled = false
            return
        }

        if pendingStates.contains(where: { states[$0.key] != $0.value }) {
            var updatedStates = states
            for (entityID, state) in pendingStates {
                updatedStates[entityID] = state
            }
            states = updatedStates
        }
        pendingStates.removeAll()
        isStateFlushScheduled = false
    }

    func synchronizeHistorySubscriptionsForTesting() async {
        await loadHistories()
    }

    func applyLovelaceConfigForTesting(_ config: LovelaceConfig) async {
        await applyLovelaceConfig(config, startHistoryOwners: webSocketClient != nil)
    }

    private func applyLovelaceConfig(
        _ config: LovelaceConfig,
        startHistoryOwners: Bool
    ) async {
        if latestQueuedConfigRawValue == config.rawValue,
           dashboardOwnerOperationTail != nil
        {
            await awaitStableDashboardOwnerOperationTail(
                startingAt: latestDashboardOwnerOperationSequence
            )
            return
        }
        if latestQueuedConfigRawValue == nil,
           presentationDashboard.resolved.source.rawValue == config.rawValue
        {
            await awaitStableDashboardOwnerOperationTail(
                startingAt: latestDashboardOwnerOperationSequence
            )
            return
        }

        let candidate = LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        )
        latestConfigRequestSequence &+= 1
        let requestSequence = latestConfigRequestSequence
        latestQueuedConfigCandidate = candidate
        latestDashboardOwnerOperationSequence &+= 1
        let operationSequence = latestDashboardOwnerOperationSequence
        let previousTail = dashboardOwnerOperationTail
        let task = Task { @MainActor [weak self] in
            await previousTail?.value
            guard let self = self else { return }
            await self.reconcileLovelaceConfig(
                candidate,
                startHistoryOwners: startHistoryOwners,
                requestSequence: requestSequence
            )
            if self.latestConfigRequestSequence == requestSequence {
                self.latestQueuedConfigCandidate = nil
            }
        }
        dashboardOwnerOperationTail = task
        await awaitStableDashboardOwnerOperationTail(startingAt: operationSequence)
    }

    @discardableResult
    private func awaitStableDashboardOwnerOperationTail(startingAt sequence: UInt64) async -> UInt64 {
        var observedSequence = sequence
        while true {
            await dashboardOwnerOperationTail?.value
            let latestSequence = latestDashboardOwnerOperationSequence
            if latestSequence == observedSequence { return latestSequence }
            observedSequence = latestSequence
        }
    }

    private func enqueueDashboardOwnerOperation(
        _ operation: @escaping @MainActor (DashboardViewModel) async -> Void
    ) async {
        latestDashboardOwnerOperationSequence &+= 1
        let previousTail = dashboardOwnerOperationTail
        let task = Task { @MainActor [weak self] in
            await previousTail?.value
            guard let self = self else { return }
            await operation(self)
        }
        dashboardOwnerOperationTail = task
        await task.value
    }

    private func reconcileLovelaceConfig(
        _ candidate: LovelacePresentationDashboard,
        startHistoryOwners: Bool,
        requestSequence: UInt64
    ) async {
        guard latestConfigRequestSequence == requestSequence else { return }

        let desiredRequests = historyRequests(from: candidate)
        let desiredKeys = Set(desiredRequests.map(\.key))
        let desiredGraphOwnerIDs = Set(desiredRequests.map(\.ownerID))
        let errorKeys = Set(historyStatuses.compactMap { key, status -> String? in
            if case .error = status { return key }
            return nil
        })
        let trackedKeys = Set(historySubscriptions.keys)
            .union(historyGenerations.keys)
            .union(historyStartupTasks.values.map(\.key))
            .union(errorKeys)
        let ownershipIsConsistent = desiredHistoryKeys == desiredKeys && trackedKeys == desiredKeys
        guard candidate != presentationDashboard || !ownershipIsConsistent else { return }
        historyReconciliationEpoch &+= 1
        desiredHistoryKeys = desiredKeys

        let obsoleteKeys = Set(historySubscriptions.keys)
            .union(historyGenerations.keys)
            .union(graphHistoryRevisionFeeds.keys)
            .union(historyStatuses.keys)
            .union(histories.keys)
            .subtracting(desiredKeys)
        var obsoleteSubscriptions: [HAHistoryStreamSubscription] = []
        let obsoleteStartupIDs = historyStartupTasks.compactMap { id, startup in
            obsoleteKeys.contains(startup.key) ? id : nil
        }
        let obsoleteStartups = obsoleteStartupIDs.compactMap { id in
            historyStartupTasks.removeValue(forKey: id)?.task
        }
        for key in obsoleteKeys {
            if let subscription = historySubscriptions.removeValue(forKey: key) {
                obsoleteSubscriptions.append(subscription)
            }
            historyGenerations.removeValue(forKey: key)
        }
        for startup in obsoleteStartups {
            await startup.value
        }
        for subscription in obsoleteSubscriptions {
            await subscription.cancel()
        }
        guard latestConfigRequestSequence == requestSequence else { return }

        // Keep the still-visible dashboard's last accepted data/feed/status
        // intact while cancellation is pending. Only a candidate that remains
        // latest may retire those visual stores immediately before install.
        for key in obsoleteKeys {
            graphHistoryRevisionFeeds.removeValue(forKey: key)
            historyStatuses.removeValue(forKey: key)
            histories.removeValue(forKey: key)
        }
        // Cancellation is complete and the candidate is still current. End
        // obsolete mounted render lifetimes immediately before publishing;
        // a superseded candidate never freezes mounts belonging to the still
        // visible dashboard.
        graphChartMountRegistry.invalidateOwners(notIn: desiredGraphOwnerIDs)
        presentationDashboard = candidate
        views = candidate.resolved.source.views
        if startHistoryOwners {
            await loadHistories(configRequestSequence: requestSequence)
            guard latestConfigRequestSequence == requestSequence else {
                await retireCardHistoryOwnership(notIn: latestQueuedHistoryKeys)
                return
            }
        }
    }

    private func loadHistories(configRequestSequence: UInt64? = nil) async {
        if let configRequestSequence = configRequestSequence {
            await loadHistoriesInline(configRequestSequence: configRequestSequence)
            return
        }

        let capturedConfigSequence = latestConfigRequestSequence
        await enqueueDashboardOwnerOperation { model in
            await model.loadHistoriesInline(configRequestSequence: capturedConfigSequence)
        }
    }

    private func loadHistoriesInline(configRequestSequence: UInt64) async {
        guard latestConfigRequestSequence == configRequestSequence else { return }
        guard let webSocketClient = webSocketClient else { return }

        let requests = historyRequests()
        let desiredKeys = Set(requests.map(\.key))
        if desiredKeys != desiredHistoryKeys {
            desiredHistoryKeys = desiredKeys
            historyReconciliationEpoch &+= 1
        }
        let reconciliationEpoch = historyReconciliationEpoch
        let obsoleteKeys = Set(historySubscriptions.keys)
            .union(historyGenerations.keys)
            .union(graphHistoryRevisionFeeds.keys)
            .union(historyStatuses.keys)
            .union(histories.keys)
            .subtracting(desiredKeys)
        var obsoleteSubscriptions: [HAHistoryStreamSubscription] = []
        for key in obsoleteKeys {
            if let subscription = historySubscriptions.removeValue(forKey: key) {
                obsoleteSubscriptions.append(subscription)
            }
            historyGenerations.removeValue(forKey: key)
            graphHistoryRevisionFeeds.removeValue(forKey: key)
            historyStatuses.removeValue(forKey: key)
            histories.removeValue(forKey: key)
        }
        for subscription in obsoleteSubscriptions {
            await subscription.cancel()
        }

        guard
            latestConfigRequestSequence == configRequestSequence,
            historyReconciliationEpoch == reconciliationEpoch
        else { return }
        for request in requests {
            guard latestConfigRequestSequence == configRequestSequence else { return }
            guard historyReconciliationEpoch == reconciliationEpoch else { return }
            guard
                desiredHistoryKeys.contains(request.key),
                historySubscriptions[request.key] == nil,
                historyGenerations[request.key] == nil
            else { continue }
            await startHistoryTracked(
                request,
                webSocketClient: webSocketClient,
                reconciliationEpoch: reconciliationEpoch,
                configRequestSequence: configRequestSequence
            )
        }
    }

    private func startHistoryTracked(
        _ request: HistoryRequest,
        webSocketClient: HomeAssistantWebSocketClient,
        reconciliationEpoch: UInt64,
        configRequestSequence: UInt64?
    ) async {
        let startupID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.startHistory(
                request,
                webSocketClient: webSocketClient,
                reconciliationEpoch: reconciliationEpoch,
                configRequestSequence: configRequestSequence
            )
        }
        historyStartupTasks[startupID] = HistoryStartupTask(key: request.key, task: task)
        await task.value
        historyStartupTasks.removeValue(forKey: startupID)
    }

    private func startHistory(
        _ request: HistoryRequest,
        webSocketClient: HomeAssistantWebSocketClient,
        reconciliationEpoch: UInt64,
        configRequestSequence: UInt64? = nil
    ) async {
        let key = request.key
        guard
            historyReconciliationEpoch == reconciliationEpoch,
            desiredHistoryKeys.contains(key),
            historySubscriptions[key] == nil,
            historyGenerations[key] == nil
        else { return }
        let generation = UUID()
        let stateSnapshot = states
        historyGenerations[key] = generation
        let graphRevisionFeed = GraphHistoryRevisionFeed()
        graphHistoryRevisionFeeds[key] = graphRevisionFeed
        historyStatuses[key] = .loading
        let weakModel = WeakDashboardViewModelBox(self)
        let processingHook = historyProcessingHook
        let projectionStore = HAHistoryProjectionStore(
            orderedEntityIDs: request.entityIDs,
            currentStates: stateSnapshot
        )

        do {
            let subscription = try await webSocketClient.subscribeHistoryStatesTimeWindow(
                entityIDs: request.entityIDs,
                hoursToShow: request.hoursToShow,
                currentStates: stateSnapshot,
                now: historyNow,
                onStatus: { status in
                    await MainActor.run {
                        guard weakModel.value?.historyGenerations[key] == generation else { return }
                        guard weakModel.value?.desiredHistoryKeys.contains(key) == true else { return }
                        guard weakModel.value?.historyStatuses[key] != status else { return }
                        weakModel.value?.historyStatuses[key] = status
                    }
                },
                onPublication: { publication in
                    if case .unchanged = publication.transition { return }
                    let resetsPreparedGraphState: Bool
                    switch publication.transition {
                    case .reset, .outOfOrderReset:
                        resetsPreparedGraphState = true
                    case .normal, .unchanged:
                        resetsPreparedGraphState = false
                    }
                    await processingHook()
                    guard !Task.isCancelled else { return }
                    guard let projected = await projectionStore.series(from: publication) else { return }
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        guard weakModel.value?.historyGenerations[key] == generation else { return }
                        guard weakModel.value?.desiredHistoryKeys.contains(key) == true else { return }
                        graphRevisionFeed.publish(
                            projected,
                            resetPreparedState: resetsPreparedGraphState
                        )
                        weakModel.value?.histories[key] = projected
                    }
                }
            )
            guard
                configRequestSequence.map({
                    latestConfigRequestSequence == $0 ||
                        latestQueuedHistoryKeys.contains(key) ||
                        (latestQueuedConfigRawValue == nil && desiredHistoryKeys.contains(key))
                }) ?? true,
                desiredHistoryKeys.contains(key),
                historyGenerations[key] == generation
            else {
                if historyGenerations[key] == generation {
                    historyGenerations.removeValue(forKey: key)
                    graphHistoryRevisionFeeds.removeValue(forKey: key)
                    historyStatuses.removeValue(forKey: key)
                    histories.removeValue(forKey: key)
                }
                await subscription.cancel()
                return
            }
            historySubscriptions[key] = subscription
        } catch {
            guard
                desiredHistoryKeys.contains(key),
                historyGenerations[key] == generation
            else { return }
            historyGenerations.removeValue(forKey: key)
            graphHistoryRevisionFeeds.removeValue(forKey: key)
            historyStatuses[key] = .error(error.localizedDescription)
            errorMessage = "History stream failed: \(error.localizedDescription)"
        }
    }

    private func retireCardHistoryOwnership(notIn retainedKeys: Set<String>) async {
        historyReconciliationEpoch &+= 1
        desiredHistoryKeys.formIntersection(retainedKeys)
        // This reconciliation has already been superseded. Retire only live
        // delivery ownership so the final queued candidate cannot overlap it.
        // Accepted visual stores and mounted lifecycles still belong to the
        // published dashboard; only the final candidate may retire those.
        let obsoleteOwnershipKeys = Set(historySubscriptions.keys)
            .union(historyGenerations.keys)
            .union(historyStartupTasks.values.map(\.key))
            .subtracting(retainedKeys)
        let startupIDs = historyStartupTasks.compactMap { id, startup in
            obsoleteOwnershipKeys.contains(startup.key) ? id : nil
        }
        let startups = startupIDs.compactMap { historyStartupTasks.removeValue(forKey: $0)?.task }
        var subscriptions: [HAHistoryStreamSubscription] = []
        for key in obsoleteOwnershipKeys {
            if let subscription = historySubscriptions.removeValue(forKey: key) {
                subscriptions.append(subscription)
            }
            historyGenerations.removeValue(forKey: key)
        }
        for startup in startups {
            await startup.value
        }
        for subscription in subscriptions {
            await subscription.cancel()
        }
    }

    private func refreshHistorySubscriptions() async {
        let capturedConfigSequence = latestConfigRequestSequence
        await enqueueDashboardOwnerOperation { model in
            await model.refreshHistorySubscriptionsInline(
                configRequestSequence: capturedConfigSequence
            )
        }
    }

    private func refreshHistorySubscriptionsInline(configRequestSequence: UInt64) async {
        guard latestConfigRequestSequence == configRequestSequence else { return }
        let currentDesiredKeys = Set(historyRequests().map(\.key))
        if historySubscriptions.isEmpty || currentDesiredKeys != desiredHistoryKeys {
            await loadHistoriesInline(configRequestSequence: configRequestSequence)
            return
        }
        let reconciliationEpoch = historyReconciliationEpoch
        let subscriptions = historySubscriptions.compactMap { key, subscription in
            historyGenerations[key].map { (key, subscription, $0) }
        }
        for (key, subscription, generation) in subscriptions {
            guard
                latestConfigRequestSequence == configRequestSequence,
                historyReconciliationEpoch == reconciliationEpoch,
                desiredHistoryKeys.contains(key),
                historyGenerations[key] == generation,
                historySubscriptions[key] === subscription
            else { continue }
            historyStatuses[key] = .loading
            do {
                try await subscription.refresh()
            } catch {
                guard
                    latestConfigRequestSequence == configRequestSequence,
                    desiredHistoryKeys.contains(key),
                    historyGenerations[key] == generation,
                    historySubscriptions[key] === subscription
                else { continue }
                historyStatuses[key] = .error(error.localizedDescription)
            }
        }
    }

    private func startDetailHistory(entityID: String, hours: Int, key: String) async {
        guard
            desiredDetailHistoryKeys.contains(key),
            detailHistorySubscriptions[key] == nil,
            let webSocketClient = webSocketClient
        else { return }

        let generation = UUID()
        let stateSnapshot = states
        detailHistoryGenerations[key] = generation
        detailHistoryStatuses[key] = .loading
        let weakModel = WeakDashboardViewModelBox(self)
        let processingHook = historyProcessingHook
        let projectionStore = HAHistoryProjectionStore(
            orderedEntityIDs: [entityID],
            currentStates: stateSnapshot
        )
        do {
            let subscription = try await webSocketClient.subscribeHistoryStatesTimeWindow(
                entityIDs: [entityID],
                hoursToShow: hours,
                currentStates: stateSnapshot,
                now: historyNow,
                onStatus: { status in
                    await MainActor.run {
                        guard weakModel.value?.detailHistoryGenerations[key] == generation else { return }
                        guard weakModel.value?.detailHistoryStatuses[key] != status else { return }
                        weakModel.value?.detailHistoryStatuses[key] = status
                    }
                },
                onPublication: { publication in
                    if case .unchanged = publication.transition { return }
                    await processingHook()
                    guard !Task.isCancelled else { return }
                    guard let projection = await projectionStore.series(from: publication)?.first else { return }
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        guard weakModel.value?.detailHistoryGenerations[key] == generation else { return }
                        weakModel.value?.detailHistories[key] = projection
                    }
                }
            )
            guard
                desiredDetailHistoryKeys.contains(key),
                detailHistoryGenerations[key] == generation
            else {
                await subscription.cancel()
                return
            }
            detailHistorySubscriptions[key] = subscription
        } catch {
            guard detailHistoryGenerations[key] == generation else { return }
            detailHistoryStatuses[key] = .error(error.localizedDescription)
            errorMessage = "Detail history failed for \(entityID): \(error.localizedDescription)"
        }
    }

    private func detailHistoryKey(entityID: String, hours: Int) -> String {
        "\(hours):\(entityID)"
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

    private func historyRequests() -> [HistoryRequest] {
        historyRequests(from: presentationDashboard)
    }

    private func historyRequests(from dashboard: LovelacePresentationDashboard) -> [HistoryRequest] {
        var requests: [HistoryRequest] = []
        let cards = dashboard.views.first(where: { $0.resolved.source.path == "default_view" })?.cards
            ?? dashboard.views.first?.cards
            ?? []
        collectHistoryRequests(from: cards, into: &requests)
        return requests.removingDuplicates()
    }

    private func collectHistoryRequests(
        from cards: [LovelacePresentationCard],
        into requests: inout [HistoryRequest]
    ) {
        for card in cards {
            if card.type == "history-graph", card.source.diagnostic == nil {
                let entities = historyEntityIDs(for: card)
                if !entities.isEmpty {
                    requests.append(HistoryRequest(
                        ownerID: card.nativeID,
                        entityIDs: entities,
                        hoursToShow: selectedGraphHours
                    ))
                }
            }

            if let nestedCards = card.cards {
                collectHistoryRequests(from: nestedCards, into: &requests)
            }
        }
    }


    private func firstWorkingConnection(token: String) async throws -> Connection {
        var lastError: Error?

        for baseURL in AppConfig.baseURLs {
            let configuration = HomeAssistantConfiguration(baseURL: baseURL, accessToken: token)
            let client = HomeAssistantRESTClient(configuration: configuration)

            do {
                let homeAssistantConfig = try await client.fetchConfig()
                return Connection(
                    baseURL: baseURL,
                    configuration: configuration,
                    restClient: client,
                    homeAssistantConfig: homeAssistantConfig
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

    deinit {
        connectionStatusTask?.cancel()
        let stateSubscription = stateSubscription
        let historySubscriptions = Array(historySubscriptions.values)
        let detailHistorySubscriptions = Array(detailHistorySubscriptions.values)
        let client = webSocketClient
        Task {
            await stateSubscription?.cancel()
            for subscription in historySubscriptions {
                await subscription.cancel()
            }
            for subscription in detailHistorySubscriptions {
                await subscription.cancel()
            }
            await client?.disconnect()
        }
    }
}

private struct Connection {
    let baseURL: URL
    let configuration: HomeAssistantConfiguration
    let restClient: HomeAssistantRESTClient
    let homeAssistantConfig: HAConfig
}

private final class WeakDashboardViewModelBox: @unchecked Sendable {
    weak var value: DashboardViewModel?

    init(_ value: DashboardViewModel) {
        self.value = value
    }
}

struct HistoryRequest: Hashable {
    let ownerID: String
    let entityIDs: [String]
    let hoursToShow: Int

    var key: String {
        [ownerID, "\(hoursToShow)", entityIDs.joined(separator: ",")]
            .joined(separator: "\u{1F}")
    }
}

private struct HistoryStartupTask {
    let key: String
    let task: Task<Void, Never>
}

private extension Array where Element == HistoryRequest {
    func removingDuplicates() -> [HistoryRequest] {
        var seen = Set<String>()
        return filter { request in
            seen.insert(request.key).inserted
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
