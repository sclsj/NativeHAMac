import Foundation
import NativeHACore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedGraphHours = AppConfig.defaultGraphHours
    @Published private(set) var views: [LovelaceView] = []
    @Published private(set) var navigationItems: [LovelaceNavigationItem] = []
    @Published private(set) var selectedViewIdentity: LovelaceResolvedIdentity?
    @Published private(set) var hasLoadedDashboard: Bool
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
    private var detailHistoryStartupTasks: [UUID: DetailHistoryStartupTask] = [:]
    private var historyGenerations: [String: UUID] = [:]
    private var graphHistoryRevisionFeeds: [String: GraphHistoryRevisionFeed] = [:]
    private var desiredHistoryKeys: Set<String> = []
    private var historyReconciliationEpoch: UInt64 = 0
    private var latestConfigRequestSequence: UInt64 = 0
    private var latestNavigationRequestSequence: UInt64 = 0
    private var latestBootstrapSequence: UInt64 = 0
    private var latestBootstrapClient: HomeAssistantWebSocketClient?
    private var installedBootstrapSequence: UInt64?
    private var installedBootstrapClient: HomeAssistantWebSocketClient?
    private var latestDashboardOwnerOperationSequence: UInt64 = 0
    private var dashboardOwnerOperationTail: Task<Void, Never>?
    private var latestQueuedDashboardCandidate: DashboardOwnerCandidate?
    private var desiredSelectedViewIdentity: LovelaceResolvedIdentity?
    private var selectedViewLocator: LovelaceViewLocator?
    private var selectedViewIsPrimary = false
    private var lastPrimaryIdentity: LovelaceResolvedIdentity?
    private var lastPrimaryLocator: LovelaceViewLocator?
    private var currentUserID: String?
    private let navigationSelectionPersistence: LovelaceNavigationSelectionPersistence
    private(set) var presentationDashboard: LovelacePresentationDashboard
    let graphChartMountRegistry = DashboardGraphChartMountRegistry()
    private var detailHistoryGenerations: [String: UUID] = [:]
    private var desiredDetailHistoryKeys: Set<String> = []
    private let historyNow: @Sendable () -> Date
    let graphAxisTimeFormattingOverride: GraphTooltipFormattingMetadata?
    private let historyProcessingHook: @Sendable () async -> Void
    private let dashboardOwnerCandidateHook: @Sendable () async -> Void
    private var hasStarted = false
    private var pendingStates: [String: HAState] = [:]
    private var stateFlushGeneration: UInt64?
    private let isoFormatter = ISO8601DateFormatter()
    private let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var latestQueuedConfigRawValue: JSONValue? {
        latestQueuedDashboardCandidate?.dashboard.resolved.source.rawValue
    }

    private var latestQueuedHistoryKeys: Set<String> {
        desiredHistoryKeys
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
        currentUserID: String? = nil,
        navigationPreferenceStore: LovelaceNavigationPreferenceStore = UserDefaultsLovelaceNavigationPreferenceStore(),
        historyNow: @escaping @Sendable () -> Date = { Date() },
        graphAxisTimeFormattingOverride: GraphTooltipFormattingMetadata? = nil,
        historyProcessingHook: @escaping @Sendable () async -> Void = {},
        dashboardOwnerCandidateHook: @escaping @Sendable () async -> Void = {}
    ) {
        let initialConfig = LovelaceConfig(views: initialViews)
        let initialResolved = LovelaceResolvedDashboard(source: initialConfig)
        let initialPresentation = LovelacePresentationDashboard(resolved: initialResolved)
        let persistence = LovelaceNavigationSelectionPersistence(
            key: AppConfig.lovelaceNavigationPolicy.persistedPrimarySelectionKey,
            store: navigationPreferenceStore
        )
        let initialNavigation = LovelaceViewNavigation(
            dashboard: initialResolved,
            currentUserID: currentUserID,
            policy: AppConfig.lovelaceNavigationPolicy
        )
        let persistedLocator: LovelaceViewLocator?
        do {
            persistedLocator = try persistence.load()
        } catch {
            persistedLocator = nil
            AppLog(
                "Lovelace navigation preference could not be read",
                severity: .warning,
                category: .lifecycle
            )
        }
        let initialSelection = initialNavigation.startupSelection(persisted: persistedLocator)
        self.presentationDashboard = initialPresentation
        self.navigationSelectionPersistence = persistence
        self.currentUserID = currentUserID
        self.hasLoadedDashboard = !initialViews.isEmpty
        self.selectedViewIdentity = initialSelection?.identity
        self.desiredSelectedViewIdentity = initialSelection?.identity
        self.selectedViewLocator = initialSelection.flatMap(initialNavigation.locator)
        self.selectedViewIsPrimary = initialSelection.map {
            initialNavigation.primaryView(identity: $0.identity) != nil
        } ?? false
        if selectedViewIsPrimary {
            self.lastPrimaryIdentity = initialSelection?.identity
            self.lastPrimaryLocator = initialSelection.flatMap(initialNavigation.locator)
        }
        self.navigationItems = initialNavigation.items(selectedIdentity: initialSelection?.identity)
        self.webSocketClient = webSocketClient
        self.states = initialStates
        self.views = initialViews
        self.homeAssistantConfig = homeAssistantConfig
        self.frontendLocalePreferences = frontendLocalePreferences
        self.entityDisplayPrecisions = entityDisplayPrecisions
        self.historyNow = historyNow
        self.graphAxisTimeFormattingOverride = graphAxisTimeFormattingOverride
        self.historyProcessingHook = historyProcessingHook
        self.dashboardOwnerCandidateHook = dashboardOwnerCandidateHook
    }

    var homeView: LovelaceView? {
        activePresentationView?.resolved.source
    }

    var graphWindowNow: Date { historyNow() }

    var homeCards: [LovelacePresentationCard] {
        activeCards
    }

    var activePresentationView: LovelacePresentationView? {
        guard let selectedViewIdentity = selectedViewIdentity else { return nil }
        return presentationDashboard.views.first { $0.id == selectedViewIdentity }
    }

    var activeCards: [LovelacePresentationCard] {
        activePresentationView?.cards ?? []
    }

    var dashboardColumns: [[LovelacePresentationCard]] {
        guard let activeView = activePresentationView else { return [] }
        if activeView.resolved.source.panel == true || activeView.resolved.source.type == "panel" {
            return activeView.cards.first.map { [[$0]] } ?? []
        }
        guard activeView.resolved.source.path == "default_view" else {
            return activeView.cards.isEmpty ? [] : [activeView.cards]
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
        enqueueCurrentDashboardOwnerCandidate(startHistoryOwners: webSocketClient != nil)
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

    func selectView(_ identity: LovelaceResolvedIdentity) {
        guard identity != desiredSelectedViewIdentity else { return }
        let sourceDashboard = presentationDashboard
        let sourceNavigation = navigation(for: sourceDashboard)
        let targetNavigation: LovelaceViewNavigation
        let targetDashboard: LovelacePresentationDashboard
        if let queued = latestQueuedDashboardCandidate {
            targetDashboard = queued.dashboard
            targetNavigation = navigation(for: queued.dashboard)
        } else {
            targetDashboard = presentationDashboard
            targetNavigation = sourceNavigation
        }

        let selected: LovelaceResolvedView?
        if let exact = targetNavigation.view(identity: identity) {
            selected = exact
        } else if
            let source = sourceNavigation.view(identity: identity),
            let locator = sourceNavigation.locator(for: source)
        {
            selected = targetNavigation.view(
                for: locator,
                primaryOnly: sourceNavigation.primaryView(identity: identity) != nil
            )
        } else {
            selected = nil
        }
        guard let selected = selected else { return }
        enqueueDashboardOwnerCandidate(
            dashboard: targetDashboard,
            selectedView: selected,
            startHistoryOwners: webSocketClient != nil,
            configRequestSequence: latestConfigRequestSequence
        )
    }

    func navigateToView(path: String) {
        let dashboard = latestQueuedDashboardCandidate?.dashboard ?? presentationDashboard
        let navigation = navigation(for: dashboard)
        guard let selected = navigation.directRoute(path: path) else {
            AppLog("Lovelace route could not be resolved", severity: .warning, category: .interaction)
            return
        }
        enqueueDashboardOwnerCandidate(
            dashboard: dashboard,
            selectedView: selected,
            startHistoryOwners: webSocketClient != nil,
            configRequestSequence: latestConfigRequestSequence
        )
    }

    func navigateBack() {
        let dashboard = latestQueuedDashboardCandidate?.dashboard ?? presentationDashboard
        let navigation = navigation(for: dashboard)
        guard let selected = navigation.backSelection(
            from: desiredSelectedViewIdentity,
            lastPrimaryIdentity: lastPrimaryIdentity,
            persistedPrimaryLocator: lastPrimaryLocator
        ) else {
            enqueueDashboardOwnerCandidate(
                dashboard: dashboard,
                selectedView: nil,
                startHistoryOwners: webSocketClient != nil,
                configRequestSequence: latestConfigRequestSequence
            )
            return
        }
        enqueueDashboardOwnerCandidate(
            dashboard: dashboard,
            selectedView: selected,
            startHistoryOwners: webSocketClient != nil,
            configRequestSequence: latestConfigRequestSequence
        )
    }

    func selectViewForTesting(_ identity: LovelaceResolvedIdentity) async {
        selectView(identity)
        await awaitStableDashboardOwnerOperationTail(
            startingAt: latestDashboardOwnerOperationSequence
        )
    }

    func navigateToViewForTesting(path: String) async {
        navigateToView(path: path)
        await awaitStableDashboardOwnerOperationTail(
            startingAt: latestDashboardOwnerOperationSequence
        )
    }

    func setGraphHoursForTesting(_ hours: Int) async {
        setGraphHours(hours)
        await awaitStableDashboardOwnerOperationTail(
            startingAt: latestDashboardOwnerOperationSequence
        )
    }

    func dashboardOwnerSnapshotForTesting() -> DashboardOwnerDebugSnapshot {
        DashboardOwnerDebugSnapshot(
            activeCardOwnerIDs: activeCardOwnerIDs(
                from: presentationDashboard,
                selectedViewIdentity: selectedViewIdentity
            ),
            desiredHistoryKeys: desiredHistoryKeys,
            subscriptionKeys: Set(historySubscriptions.keys),
            generationKeys: Set(historyGenerations.keys),
            startupCount: historyStartupTasks.count,
            feedObserverCounts: graphHistoryRevisionFeeds.mapValues(\.observerCount),
            historyKeys: Set(histories.keys),
            statusKeys: Set(historyStatuses.keys),
            mountedOwnerCount: graphChartMountRegistry.liveMountCount()
        )
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
        let startupID = UUID()
        let task = Task { @MainActor [weak self] in
            await self?.startDetailHistory(entityID: entityID, hours: effectiveHours, key: key)
            self?.detailHistoryStartupTasks.removeValue(forKey: startupID)
        }
        detailHistoryStartupTasks[startupID] = DetailHistoryStartupTask(key: key, task: task)
    }

    func unloadDetailHistory(entityID: String, hours: Int) {
        let key = detailHistoryKey(entityID: entityID, hours: hours)
        desiredDetailHistoryKeys.remove(key)
        let startupIDs = detailHistoryStartupTasks.compactMap { id, startup in
            startup.key == key ? id : nil
        }
        let startups = startupIDs.compactMap {
            detailHistoryStartupTasks.removeValue(forKey: $0)?.task
        }
        startups.forEach { $0.cancel() }
        let subscription = detailHistorySubscriptions.removeValue(forKey: key)
        detailHistoryGenerations.removeValue(forKey: key)
        detailHistoryStatuses.removeValue(forKey: key)
        Task {
            for startup in startups { await startup.value }
            await subscription?.cancel()
        }
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
        latestBootstrapSequence &+= 1
        let bootstrapSequence = latestBootstrapSequence
        latestBootstrapClient = webSocket
        pendingStates.removeAll()
        stateFlushGeneration = nil

        do {
            try await webSocket.connect()
            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }

            async let registryResponse = try? await webSocket.fetchEntityRegistryDisplay()
            async let localeResponse = try? await webSocket.fetchFrontendLocalePreferences()
            async let currentUserResponse = Self.fetchCurrentUserResult(using: webSocket)
            let config = try await webSocket.fetchLovelaceConfig()
            let (registry, locale, currentUserResult) = await (
                registryResponse,
                localeResponse,
                currentUserResponse
            )
            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }
            entityDisplayPrecisions = Dictionary(uniqueKeysWithValues:
                (registry?.entities ?? []).compactMap { entry in
                    entry.displayPrecision.map { (entry.entityID, $0) }
                }
            )
            frontendLocalePreferences = locale ?? nil
            switch currentUserResult {
            case let .success(user):
                currentUserID = user.id
            case .failure:
                currentUserID = nil
                AppLog(
                    "Current user metadata unavailable; user-restricted navigation is hidden",
                    severity: .warning,
                    category: .lifecycle
                )
            }
            await applyLovelaceConfig(
                config,
                startHistoryOwners: false,
                bootstrapSequence: bootstrapSequence
            )

            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }

            let weakModel = WeakDashboardViewModelBox(self)
            let candidateStateSubscription = try await webSocket.subscribeToStateChanges { state in
                await MainActor.run {
                    weakModel.value?.queueStateUpdate(
                        state,
                        bootstrapSequence: bootstrapSequence,
                        client: webSocket
                    )
                }
            }
            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await candidateStateSubscription.cancel()
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }

            let installed = await installBootstrapOwnership(
                sequence: bootstrapSequence,
                client: webSocket,
                stateSubscription: candidateStateSubscription
            )
            guard installed else { return }

            Task { [weak self] in
                await self?.loadHistories()
            }
        } catch {
            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }
            await failCurrentBootstrap(sequence: bootstrapSequence, client: webSocket)
            throw error
        }
    }

    private func isCurrentBootstrap(
        _ sequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) -> Bool {
        latestBootstrapSequence == sequence && latestBootstrapClient === client
    }

    private func isCurrentInstalledBootstrap(
        _ sequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) -> Bool {
        isCurrentBootstrap(sequence, client: client) &&
            installedBootstrapSequence == sequence &&
            installedBootstrapClient === client &&
            webSocketClient === client
    }

    private func disconnectIfUnownedByCurrentBootstrap(
        _ client: HomeAssistantWebSocketClient
    ) async {
        guard latestBootstrapClient !== client, installedBootstrapClient !== client else {
            return
        }
        await client.disconnect()
    }

    private func failCurrentBootstrap(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) async {
        guard isCurrentBootstrap(sequence, client: client) else {
            await disconnectIfUnownedByCurrentBootstrap(client)
            return
        }

        let installedClient = installedBootstrapClient
        let subscription = stateSubscription
        let statusTask = connectionStatusTask
        stateSubscription = nil
        connectionStatusTask = nil
        webSocketClient = nil
        installedBootstrapClient = nil
        installedBootstrapSequence = nil
        statusTask?.cancel()
        await subscription?.cancel()
        if let installedClient = installedClient, installedClient !== client {
            await disconnectIfUnownedByCurrentBootstrap(installedClient)
        }
        if isCurrentBootstrap(sequence, client: client) {
            latestBootstrapClient = nil
            await client.disconnect()
        } else {
            await disconnectIfUnownedByCurrentBootstrap(client)
        }
    }

    private func installBootstrapOwnership(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient,
        stateSubscription candidateStateSubscription: HAWebSocketSubscription
    ) async -> Bool {
        guard isCurrentBootstrap(sequence, client: client) else {
            await candidateStateSubscription.cancel()
            await disconnectIfUnownedByCurrentBootstrap(client)
            return false
        }

        let oldSubscription = stateSubscription
        let oldStatusTask = connectionStatusTask
        let oldClient = installedBootstrapClient
        stateSubscription = nil
        connectionStatusTask = nil
        webSocketClient = nil
        installedBootstrapClient = nil
        installedBootstrapSequence = nil
        oldStatusTask?.cancel()
        await oldSubscription?.cancel()

        if let oldClient = oldClient, oldClient !== client {
            await disconnectIfUnownedByCurrentBootstrap(oldClient)
        }

        guard isCurrentBootstrap(sequence, client: client) else {
            await candidateStateSubscription.cancel()
            await disconnectIfUnownedByCurrentBootstrap(client)
            return false
        }

        stateSubscription = candidateStateSubscription
        webSocketClient = client
        installedBootstrapClient = client
        installedBootstrapSequence = sequence
        status = "Live"
        AppLog("Dashboard successfully connected and became Live", category: .lifecycle)
        connectionStatusTask = makeConnectionStatusTask(sequence: sequence, client: client)
        return true
    }

    private func makeConnectionStatusTask(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) -> Task<Void, Never> {
        Task { [weak self, client] in
            for await connectionState in await client.connection.statusUpdates() {
                await MainActor.run {
                    guard self?.isCurrentInstalledBootstrap(sequence, client: client) == true else {
                        return
                    }
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
    }

    private nonisolated static func fetchCurrentUserResult(
        using webSocket: HomeAssistantWebSocketClient
    ) async -> Result<HACurrentUser, Error> {
        do {
            return .success(try await webSocket.fetchCurrentUser())
        } catch {
            return .failure(error)
        }
    }

    private func parseDate(_ value: String) -> Date? {
        fractionalISOFormatter.date(from: value) ?? isoFormatter.date(from: value)
    }

    private func queueStateUpdate(
        _ state: HAState,
        bootstrapSequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) {
        guard isCurrentInstalledBootstrap(bootstrapSequence, client: client) else {
            return
        }
        pendingStates[state.entityId] = state

        guard stateFlushGeneration != bootstrapSequence else {
            return
        }

        stateFlushGeneration = bootstrapSequence
        Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: AppConfig.graphRenderSchedulingPolicy.realtimeStateCoalesceNanoseconds
            )
            self?.flushPendingStates(
                bootstrapSequence: bootstrapSequence,
                client: client
            )
        }
    }

    private func flushPendingStates(
        bootstrapSequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) {
        guard stateFlushGeneration == bootstrapSequence else { return }
        stateFlushGeneration = nil
        guard isCurrentInstalledBootstrap(bootstrapSequence, client: client) else {
            pendingStates.removeAll()
            return
        }
        guard !pendingStates.isEmpty else {
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
    }

    func synchronizeHistorySubscriptionsForTesting() async {
        await loadHistories()
    }

    func applyLovelaceConfigForTesting(_ config: LovelaceConfig) async {
        await applyLovelaceConfig(config, startHistoryOwners: webSocketClient != nil)
    }

    private func applyLovelaceConfig(
        _ config: LovelaceConfig,
        startHistoryOwners: Bool,
        bootstrapSequence: UInt64? = nil
    ) async {
        guard bootstrapSequence.map({ latestBootstrapSequence == $0 }) ?? true else { return }
        if latestQueuedConfigRawValue == config.rawValue,
           dashboardOwnerOperationTail != nil,
           latestQueuedDashboardCandidate?.bootstrapSequence == bootstrapSequence
        {
            await awaitStableDashboardOwnerOperationTail(
                startingAt: latestDashboardOwnerOperationSequence
            )
            guard bootstrapSequence.map({ latestBootstrapSequence == $0 }) ?? true else { return }
            return
        }
        if bootstrapSequence == nil,
           hasLoadedDashboard,
           latestQueuedConfigRawValue == nil,
           presentationDashboard.resolved.source.rawValue == config.rawValue
        {
            await awaitStableDashboardOwnerOperationTail(
                startingAt: latestDashboardOwnerOperationSequence
            )
            guard bootstrapSequence.map({ latestBootstrapSequence == $0 }) ?? true else { return }
            return
        }

        let dashboard = LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        )
        let navigation = self.navigation(for: dashboard)
        let previousLocator = latestQueuedDashboardCandidate?.selectedLocator ?? selectedViewLocator
        let previousWasPrimary = latestQueuedDashboardCandidate?.selectionIsPrimary ?? selectedViewIsPrimary
        var selected = previousLocator.flatMap {
            navigation.view(for: $0, primaryOnly: previousWasPrimary)
        }
        if selected == nil {
            let persistedLocator: LovelaceViewLocator?
            do {
                persistedLocator = try navigationSelectionPersistence.load()
            } catch {
                persistedLocator = lastPrimaryLocator
                AppLog(
                    "Lovelace navigation preference could not be read",
                    severity: .warning,
                    category: .lifecycle
                )
            }
            if let persistedLocator = persistedLocator,
               navigation.view(for: persistedLocator, primaryOnly: true) == nil
            {
                clearPersistedNavigationSelection()
            }
            selected = navigation.startupSelection(
                persisted: persistedLocator ?? lastPrimaryLocator
            )
        }
        latestConfigRequestSequence &+= 1
        let requestSequence = latestConfigRequestSequence
        let operationSequence = enqueueDashboardOwnerCandidate(
            dashboard: dashboard,
            selectedView: selected,
            startHistoryOwners: startHistoryOwners,
            configRequestSequence: requestSequence,
            bootstrapSequence: bootstrapSequence
        )
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

    @discardableResult
    private func enqueueDashboardOwnerCandidate(
        dashboard: LovelacePresentationDashboard,
        selectedView: LovelaceResolvedView?,
        startHistoryOwners: Bool,
        configRequestSequence: UInt64,
        bootstrapSequence: UInt64? = nil
    ) -> UInt64 {
        latestNavigationRequestSequence &+= 1
        let navigationSequence = latestNavigationRequestSequence
        let navigation = self.navigation(for: dashboard)
        let selectedIdentity = selectedView?.identity
        let selectedLocator = selectedView.flatMap(navigation.locator)
        let selectionIsPrimary = selectedIdentity.map {
            navigation.primaryView(identity: $0) != nil
        } ?? false
        let desiredRequests = historyRequests(
            from: dashboard,
            selectedViewIdentity: selectedIdentity,
            hours: selectedGraphHours
        )
        let desiredKeys = Set(desiredRequests.map(\.key))
        let candidate = DashboardOwnerCandidate(
            dashboard: dashboard,
            selectedViewIdentity: selectedIdentity,
            selectedLocator: selectedLocator,
            selectionIsPrimary: selectionIsPrimary,
            graphHours: selectedGraphHours,
            startHistoryOwners: startHistoryOwners,
            configRequestSequence: configRequestSequence,
            bootstrapSequence: bootstrapSequence,
            navigationRequestSequence: navigationSequence,
            desiredRequests: desiredRequests,
            desiredGraphOwnerIDs: activeCardOwnerIDs(
                from: dashboard,
                selectedViewIdentity: selectedIdentity
            )
        )

        desiredSelectedViewIdentity = selectedIdentity
        let detached = detachOwnershipSynchronously(notIn: desiredKeys)
        latestQueuedDashboardCandidate = candidate
        latestDashboardOwnerOperationSequence &+= 1
        let operationSequence = latestDashboardOwnerOperationSequence
        let previousTail = dashboardOwnerOperationTail
        let task = Task { @MainActor [weak self] in
            await previousTail?.value
            guard let self = self else { return }
            await self.dashboardOwnerCandidateHook()
            await self.finishDetachedOwnership(detached)
            guard self.isCurrent(candidate) else {
                if self.latestQueuedDashboardCandidate?.navigationRequestSequence ==
                    candidate.navigationRequestSequence
                {
                    self.latestQueuedDashboardCandidate = nil
                }
                return
            }
            await self.installDashboardOwnerCandidate(candidate)
            if self.latestQueuedDashboardCandidate?.navigationRequestSequence ==
                candidate.navigationRequestSequence
            {
                self.latestQueuedDashboardCandidate = nil
            }
        }
        dashboardOwnerOperationTail = task
        return operationSequence
    }

    private func enqueueCurrentDashboardOwnerCandidate(startHistoryOwners: Bool) {
        let dashboard = latestQueuedDashboardCandidate?.dashboard ?? presentationDashboard
        let navigation = self.navigation(for: dashboard)
        let selected = navigation.view(identity: desiredSelectedViewIdentity)
            ?? navigation.startupSelection(persisted: lastPrimaryLocator)
        _ = enqueueDashboardOwnerCandidate(
            dashboard: dashboard,
            selectedView: selected,
            startHistoryOwners: startHistoryOwners,
            configRequestSequence: latestConfigRequestSequence
        )
    }

    private func detachOwnershipSynchronously(notIn desiredKeys: Set<String>) -> DetachedDashboardOwnership {
        if desiredHistoryKeys != desiredKeys {
            historyReconciliationEpoch &+= 1
        }
        desiredHistoryKeys = desiredKeys

        let obsoleteOwnershipKeys = Set(historySubscriptions.keys)
            .union(historyGenerations.keys)
            .union(historyStartupTasks.values.map(\.key))
            .subtracting(desiredKeys)
        let startupIDs = historyStartupTasks.compactMap { id, startup in
            obsoleteOwnershipKeys.contains(startup.key) ? id : nil
        }
        let startups = startupIDs.compactMap {
            historyStartupTasks.removeValue(forKey: $0)?.task
        }
        var subscriptions: [HAHistoryStreamSubscription] = []
        for key in obsoleteOwnershipKeys {
            if let subscription = historySubscriptions.removeValue(forKey: key) {
                subscriptions.append(subscription)
            }
            historyGenerations.removeValue(forKey: key)
        }

        let detailStartups = detailHistoryStartupTasks.values.map(\.task)
        detailStartups.forEach { $0.cancel() }
        detailHistoryStartupTasks.removeAll()
        let detailSubscriptions = Array(detailHistorySubscriptions.values)
        detailHistorySubscriptions.removeAll()
        detailHistoryGenerations.removeAll()
        desiredDetailHistoryKeys.removeAll()
        detailHistoryStatuses.removeAll()
        detailHistories.removeAll()
        selectedEntityID = nil
        return DetachedDashboardOwnership(
            startups: startups,
            subscriptions: subscriptions,
            detailStartups: detailStartups,
            detailSubscriptions: detailSubscriptions
        )
    }

    private func finishDetachedOwnership(_ detached: DetachedDashboardOwnership) async {
        for startup in detached.startups {
            await startup.value
        }
        for subscription in detached.subscriptions {
            await subscription.cancel()
        }
        for startup in detached.detailStartups {
            await startup.value
        }
        for subscription in detached.detailSubscriptions {
            await subscription.cancel()
        }
    }

    private func isCurrent(_ candidate: DashboardOwnerCandidate) -> Bool {
        latestConfigRequestSequence == candidate.configRequestSequence &&
            (candidate.bootstrapSequence.map { latestBootstrapSequence == $0 } ?? true) &&
            latestNavigationRequestSequence == candidate.navigationRequestSequence &&
            desiredSelectedViewIdentity == candidate.selectedViewIdentity &&
            selectedGraphHours == candidate.graphHours &&
            desiredHistoryKeys == Set(candidate.desiredRequests.map(\.key))
    }

    private func installDashboardOwnerCandidate(_ candidate: DashboardOwnerCandidate) async {
        let desiredKeys = Set(candidate.desiredRequests.map(\.key))
        let obsoleteVisualKeys = Set(graphHistoryRevisionFeeds.keys)
            .union(historyStatuses.keys)
            .union(histories.keys)
            .subtracting(desiredKeys)
        for key in obsoleteVisualKeys {
            graphHistoryRevisionFeeds.removeValue(forKey: key)
            historyStatuses.removeValue(forKey: key)
            histories.removeValue(forKey: key)
        }

        // This is the synchronous cancel-before-publish boundary for mounted
        // chart feeds and coordinator/render generations.
        graphChartMountRegistry.invalidateOwners(notIn: candidate.desiredGraphOwnerIDs)
        presentationDashboard = candidate.dashboard
        views = candidate.dashboard.resolved.source.views
        hasLoadedDashboard = true
        selectedViewIdentity = candidate.selectedViewIdentity
        selectedViewLocator = candidate.selectedLocator
        selectedViewIsPrimary = candidate.selectionIsPrimary
        let navigation = self.navigation(for: candidate.dashboard)
        navigationItems = navigation.items(selectedIdentity: candidate.selectedViewIdentity)

        if candidate.selectionIsPrimary {
            lastPrimaryIdentity = candidate.selectedViewIdentity
            lastPrimaryLocator = candidate.selectedLocator
            do {
                try navigationSelectionPersistence.save(candidate.selectedLocator)
            } catch {
                AppLog(
                    "Lovelace navigation preference could not be written",
                    severity: .warning,
                    category: .lifecycle
                )
            }
        } else if candidate.selectedViewIdentity == nil {
            lastPrimaryIdentity = nil
            lastPrimaryLocator = nil
            clearPersistedNavigationSelection()
        }

        guard candidate.startHistoryOwners, isCurrent(candidate) else { return }
        await loadHistoriesInline(configRequestSequence: candidate.configRequestSequence)
        guard isCurrent(candidate) else {
            await retireCardHistoryOwnership(notIn: latestQueuedHistoryKeys)
            return
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
            !Task.isCancelled,
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
                !Task.isCancelled,
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
        historyRequests(
            from: presentationDashboard,
            selectedViewIdentity: selectedViewIdentity,
            hours: selectedGraphHours
        )
    }

    private func historyRequests(
        from dashboard: LovelacePresentationDashboard,
        selectedViewIdentity: LovelaceResolvedIdentity?,
        hours: Int
    ) -> [HistoryRequest] {
        var requests: [HistoryRequest] = []
        let cards = dashboard.views.first { $0.id == selectedViewIdentity }?.cards ?? []
        collectHistoryRequests(from: cards, hours: hours, into: &requests)
        return requests.removingDuplicates()
    }

    private func collectHistoryRequests(
        from cards: [LovelacePresentationCard],
        hours: Int,
        into requests: inout [HistoryRequest]
    ) {
        for card in cards {
            if card.type == "history-graph", card.source.diagnostic == nil {
                let entities = historyEntityIDs(for: card)
                if !entities.isEmpty {
                    requests.append(HistoryRequest(
                        ownerID: card.nativeID,
                        entityIDs: entities,
                        hoursToShow: hours
                    ))
                }
            }

            if let nestedCards = card.cards {
                collectHistoryRequests(from: nestedCards, hours: hours, into: &requests)
            }
        }
    }

    private func activeCardOwnerIDs(
        from dashboard: LovelacePresentationDashboard,
        selectedViewIdentity: LovelaceResolvedIdentity?
    ) -> Set<String> {
        guard let cards = dashboard.views.first(where: { $0.id == selectedViewIdentity })?.cards else {
            return []
        }
        var owners = Set<String>()
        collectActiveCardOwnerIDs(from: cards, into: &owners)
        return owners
    }

    private func collectActiveCardOwnerIDs(
        from cards: [LovelacePresentationCard],
        into owners: inout Set<String>
    ) {
        for card in cards {
            owners.insert(card.nativeID)
            if let nested = card.cards {
                collectActiveCardOwnerIDs(from: nested, into: &owners)
            }
        }
    }

    private func navigation(
        for dashboard: LovelacePresentationDashboard
    ) -> LovelaceViewNavigation {
        LovelaceViewNavigation(
            dashboard: dashboard.resolved,
            currentUserID: currentUserID,
            policy: AppConfig.lovelaceNavigationPolicy
        )
    }

    private func clearPersistedNavigationSelection() {
        do {
            try navigationSelectionPersistence.save(nil)
        } catch {
            AppLog(
                "Lovelace navigation preference could not be cleared",
                severity: .warning,
                category: .lifecycle
            )
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

struct DashboardOwnerDebugSnapshot: Equatable {
    let activeCardOwnerIDs: Set<String>
    let desiredHistoryKeys: Set<String>
    let subscriptionKeys: Set<String>
    let generationKeys: Set<String>
    let startupCount: Int
    let feedObserverCounts: [String: Int]
    let historyKeys: Set<String>
    let statusKeys: Set<String>
    let mountedOwnerCount: Int
}

private struct HistoryStartupTask {
    let key: String
    let task: Task<Void, Never>
}

private struct DetachedDashboardOwnership {
    let startups: [Task<Void, Never>]
    let subscriptions: [HAHistoryStreamSubscription]
    let detailStartups: [Task<Void, Never>]
    let detailSubscriptions: [HAHistoryStreamSubscription]
}

private struct DetailHistoryStartupTask {
    let key: String
    let task: Task<Void, Never>
}

private struct DashboardOwnerCandidate {
    let dashboard: LovelacePresentationDashboard
    let selectedViewIdentity: LovelaceResolvedIdentity?
    let selectedLocator: LovelaceViewLocator?
    let selectionIsPrimary: Bool
    let graphHours: Int
    let startHistoryOwners: Bool
    let configRequestSequence: UInt64
    let bootstrapSequence: UInt64?
    let navigationRequestSequence: UInt64
    let desiredRequests: [HistoryRequest]
    let desiredGraphOwnerIDs: Set<String>
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
