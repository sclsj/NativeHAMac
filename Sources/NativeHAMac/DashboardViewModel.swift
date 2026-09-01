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
    @Published private var historyPublicationRevision: UInt64 = 0
    @Published private(set) var lifecycle = DashboardLifecycle()
    @Published var activeBaseURL: URL?
    @Published var showEntityIDs = AppConfig.showEntityIDsByDefault
    @Published var selectedEntityID: String?
    private(set) var homeAssistantConfig: HAConfig?
    private(set) var frontendLocalePreferences: HAFrontendLocalePreferences?
    private(set) var entityDisplayPrecisions: [String: Int] = [:]
    private(set) var entityRegistryIcons: [String: String] = [:]

    private nonisolated let lifetimeAuthority: DashboardLifetimeAuthority
    private let emergencyOwnershipBag: DashboardEmergencyOwnershipBag
    private var restClient: HomeAssistantRESTClient?
    private var webSocketClient: HomeAssistantWebSocketClient? {
        didSet { emergencyOwnershipBag.setWebSocketClient(webSocketClient) }
    }
    private var entityCoordinator: HAEntitySubscriptionCoordinator? {
        didSet { emergencyOwnershipBag.setEntityCoordinator(entityCoordinator) }
    }
    private var lovelaceUpdateSubscription: HAWebSocketSubscription? {
        didSet { emergencyOwnershipBag.setLovelaceSubscription(lovelaceUpdateSubscription) }
    }
    private var lovelaceFetchTask: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(lovelaceFetchTask, for: .lovelaceFetch) }
    }
    private var latestLovelaceFetchGeneration: UInt64 = 0
    private var connectionStatusTask: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(connectionStatusTask, for: .connectionStatus) }
    }
    private var connectionWasNonReady = false
    private var bootstrapTask: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(bootstrapTask, for: .bootstrap) }
    }
    private var lifecycleTransitionTail: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(lifecycleTransitionTail, for: .lifecycleTail) }
    }
    private var startTransitionTask: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(startTransitionTask, for: .startTransition) }
    }
    private var retryTransitionTask: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(retryTransitionTask, for: .retryTransition) }
    }
    private var reconnectTask: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(reconnectTask, for: .reconnect) }
    }
    private var latestLifecycleTransitionSequence: UInt64 = 0
    private var trackedStartTransitionSequence: UInt64?
    private var trackedRetryTransitionSequence: UInt64?
    private let historyCoordinator = DashboardHistoryCoordinator()
    private var latestConfigRequestSequence: UInt64 = 0
    private var latestNavigationRequestSequence: UInt64 = 0
    private var latestBootstrapSequence: UInt64 = 0
    private var latestBootstrapClient: HomeAssistantWebSocketClient? {
        didSet { emergencyOwnershipBag.setLatestBootstrapClient(latestBootstrapClient) }
    }
    private var latestBootstrapEntityCoordinator: HAEntitySubscriptionCoordinator? {
        didSet { emergencyOwnershipBag.setCandidateEntityCoordinator(latestBootstrapEntityCoordinator) }
    }
    private var installedBootstrapSequence: UInt64?
    private var installedBootstrapClient: HomeAssistantWebSocketClient? {
        didSet { emergencyOwnershipBag.setInstalledBootstrapClient(installedBootstrapClient) }
    }
    private var latestDashboardOwnerOperationSequence: UInt64 = 0
    private var dashboardOwnerOperationTail: Task<Void, Never>? {
        didSet { emergencyOwnershipBag.setTask(dashboardOwnerOperationTail, for: .dashboardOwnerTail) }
    }
    private let dashboardOwnerOperationRegistry: DashboardOwnerOperationRegistry
    private var latestQueuedDashboardCandidate: DashboardOwnerCandidate?
    private var desiredSelectedViewIdentity: LovelaceResolvedIdentity?
    private var selectedViewLocator: LovelaceViewLocator?
    private var selectedViewIsPrimary = false
    private var lastPrimaryIdentity: LovelaceResolvedIdentity?
    private var lastPrimaryLocator: LovelaceViewLocator?
    private var currentUserID: String?
    private let navigationSelectionPersistence: LovelaceNavigationSelectionPersistence
    private(set) var presentationDashboard: LovelacePresentationDashboard
    private let lovelaceStore: LovelaceDashboardStore
    private let serviceController: DashboardServiceController
    let graphChartMountRegistry = DashboardGraphChartMountRegistry()
    private let historyNow: @Sendable () -> Date
    let graphAxisTimeFormattingOverride: GraphTooltipFormattingMetadata?
    private let historyProcessingHook: @Sendable () async -> Void
    private let dashboardOwnerCandidateHook: @Sendable () async -> Void
    private let lifecycleBootstrapClientOverride: HomeAssistantWebSocketClient?
    private var emergencyDetachAction: (() -> DashboardEmergencyDeinitCleanup)?
    private var hasStarted = false
    private var appGeneration: UInt64 = 0
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
        entityRegistryIcons: [String: String] = [:],
        currentUserID: String? = nil,
        navigationPreferenceStore: LovelaceNavigationPreferenceStore = UserDefaultsLovelaceNavigationPreferenceStore(),
        historyNow: @escaping @Sendable () -> Date = { Date() },
        graphAxisTimeFormattingOverride: GraphTooltipFormattingMetadata? = nil,
        historyProcessingHook: @escaping @Sendable () async -> Void = {},
        dashboardOwnerCandidateHook: @escaping @Sendable () async -> Void = {},
        lifecycleBootstrapClientOverride: HomeAssistantWebSocketClient? = nil
    ) {
        let lifetimeAuthority = DashboardLifetimeAuthority()
        let dashboardOwnerOperationRegistry = DashboardOwnerOperationRegistry()
        self.lifetimeAuthority = lifetimeAuthority
        self.dashboardOwnerOperationRegistry = dashboardOwnerOperationRegistry
        self.emergencyOwnershipBag = DashboardEmergencyOwnershipBag(
            lifetimeAuthority: lifetimeAuthority,
            dashboardOwnerOperationRegistry: dashboardOwnerOperationRegistry
        )
        self.serviceController = DashboardServiceController(
            lifetimeAuthority: lifetimeAuthority
        )
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
        self.lovelaceStore = LovelaceDashboardStore(config: initialConfig)
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
        self.entityRegistryIcons = entityRegistryIcons
        self.historyNow = historyNow
        self.graphAxisTimeFormattingOverride = graphAxisTimeFormattingOverride
        self.historyProcessingHook = historyProcessingHook
        self.dashboardOwnerCandidateHook = dashboardOwnerCandidateHook
        self.lifecycleBootstrapClientOverride = lifecycleBootstrapClientOverride
        self.emergencyDetachAction = nil
        let emergencyBag = emergencyOwnershipBag
        let emergencyHistory = historyCoordinator
        let emergencyService = serviceController
        let emergencyMounts = graphChartMountRegistry
        emergencyService.setTaskObserver { tasks in
            emergencyBag.setServiceTasks(tasks)
        }
        // Property observers do not run for assignments performed by init.
        // Seed the emergency mirror explicitly for directly injected clients.
        emergencyBag.setWebSocketClient(webSocketClient)
        self.emergencyDetachAction = {
            DashboardEmergencyDeinitCleanup(
                ownership: emergencyBag.detachSynchronously(),
                historyCoordinator: emergencyHistory,
                serviceController: emergencyService,
                mountRegistry: emergencyMounts
            )
        }
    }

    var status: String { lifecycle.compatibilityStatus }

    nonisolated func acceptsLifetimeWork() -> Bool {
        lifetimeAuthority.acceptsWork
    }

    nonisolated var lifetimeAuthorityForTesting: DashboardLifetimeAuthority {
        lifetimeAuthority
    }

    var errorMessage: String? { lifecycle.primaryErrorMessage }

    var componentFailures: [(DashboardComponent, String)] {
        lifecycle.componentFailures
    }

    var histories: [String: [HAHistorySeries]] {
        get { historyCoordinator.histories }
        set { historyCoordinator.histories = newValue; historyPublicationRevision &+= 1 }
    }

    var detailHistories: [String: HAHistorySeries] {
        get { historyCoordinator.detailHistories }
        set { historyCoordinator.detailHistories = newValue; historyPublicationRevision &+= 1 }
    }

    var historyStatuses: [String: HAHistoryStreamOwnerStatus] {
        get { historyCoordinator.statuses }
        set { historyCoordinator.statuses = newValue; historyPublicationRevision &+= 1 }
    }

    var detailHistoryStatuses: [String: HAHistoryStreamOwnerStatus] {
        get { historyCoordinator.detailStatuses }
        set { historyCoordinator.detailStatuses = newValue; historyPublicationRevision &+= 1 }
    }

    private var historySubscriptions: [String: HAHistoryStreamSubscription] {
        get { historyCoordinator.subscriptions }
        set {
            historyCoordinator.subscriptions = newValue
            emergencyOwnershipBag.setHistorySubscriptions(Array(newValue.values))
        }
    }
    private var historyStartupTasks: [UUID: HistoryStartupTask] {
        get { historyCoordinator.startupTasks }
        set {
            historyCoordinator.startupTasks = newValue
            emergencyOwnershipBag.setHistoryStartupTasks(newValue.values.map(\.task))
        }
    }
    private var detailHistorySubscriptions: [String: HAHistoryStreamSubscription] {
        get { historyCoordinator.detailSubscriptions }
        set {
            historyCoordinator.detailSubscriptions = newValue
            emergencyOwnershipBag.setDetailHistorySubscriptions(Array(newValue.values))
        }
    }
    private var detailHistoryStartupTasks: [UUID: DetailHistoryStartupTask] {
        get { historyCoordinator.detailStartupTasks }
        set {
            historyCoordinator.detailStartupTasks = newValue
            emergencyOwnershipBag.setDetailHistoryStartupTasks(newValue.values.map(\.task))
        }
    }
    private var historyGenerations: [String: UUID] {
        get { historyCoordinator.generations }
        set { historyCoordinator.generations = newValue }
    }
    private var detailHistoryGenerations: [String: UUID] {
        get { historyCoordinator.detailGenerations }
        set { historyCoordinator.detailGenerations = newValue }
    }
    private var graphHistoryRevisionFeeds: [String: GraphHistoryRevisionFeed] {
        get { historyCoordinator.graphRevisionFeeds }
        set { historyCoordinator.graphRevisionFeeds = newValue }
    }
    private var desiredHistoryKeys: Set<String> {
        get { historyCoordinator.desiredKeys }
        set { historyCoordinator.desiredKeys = newValue }
    }
    private var desiredDetailHistoryKeys: Set<String> {
        get { historyCoordinator.desiredDetailKeys }
        set { historyCoordinator.desiredDetailKeys = newValue }
    }
    private var historyReconciliationEpoch: UInt64 {
        get { historyCoordinator.reconciliationEpoch }
        set { historyCoordinator.reconciliationEpoch = newValue }
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
        _ = enqueueLifecycleTransition(.start)
    }

    func viewDidAppear() {
        _ = enqueueLifecycleTransition(.start)
    }

    func viewDidDisappear() {
        // SwiftUI lifecycle intent must enter the serialized tail before this
        // MainActor turn ends. Wrapping `stop()` in another Task allows a
        // same-turn reappearance to enqueue first and then be overwritten by
        // the delayed disappearance.
        _ = enqueueLifecycleTransition(.stop)
    }

    func retryBootstrap() {
        _ = enqueueLifecycleTransition(.retry)
    }

    @discardableResult
    private func enqueueLifecycleTransition(
        _ transition: DashboardAppLifecycleTransition
    ) -> Task<Void, Never> {
        latestLifecycleTransitionSequence &+= 1
        let sequence = latestLifecycleTransitionSequence
        let previousTail = lifecycleTransitionTail

        // A newer app-lifecycle intent makes any queued start obsolete. An
        // already-running retry is allowed to finish its internal stop, but
        // cancellation prevents it from installing its now-obsolete restart.
        startTransitionTask?.cancel()
        retryTransitionTask?.cancel()

        let weakModel = WeakDashboardViewModelBox(self)
        let task = Task { @MainActor [weakModel] in
            await previousTail?.value
            guard transition == .stop || !Task.isCancelled else {
                weakModel.value?.finishLifecycleTransition(transition, sequence: sequence)
                return
            }
            switch transition {
            case .start:
                weakModel.value?.startImmediatelyIfCurrent(transitionSequence: sequence)
            case .stop:
                guard let detached = weakModel.value?.detachAppOwnershipSynchronously() else {
                    return
                }
                await Self.finishExplicitAppOwnership(detached)
                weakModel.value?.finishStopIfCurrent(transitionSequence: sequence)
            case .retry:
                guard let detached = weakModel.value?.detachAppOwnershipSynchronously() else {
                    return
                }
                await Self.finishExplicitAppOwnership(detached)
                guard !Task.isCancelled,
                      weakModel.value?.latestLifecycleTransitionSequence == sequence
                else {
                    weakModel.value?.finishLifecycleTransition(transition, sequence: sequence)
                    return
                }
                weakModel.value?.finishStopIfCurrent(transitionSequence: sequence)
                weakModel.value?.startImmediatelyIfCurrent(transitionSequence: sequence)
            }
            weakModel.value?.finishLifecycleTransition(transition, sequence: sequence)
        }
        lifecycleTransitionTail = task
        switch transition {
        case .start:
            startTransitionTask = task
            trackedStartTransitionSequence = sequence
        case .retry:
            retryTransitionTask = task
            trackedRetryTransitionSequence = sequence
        case .stop:
            break
        }
        return task
    }

    private func finishLifecycleTransition(
        _ transition: DashboardAppLifecycleTransition,
        sequence: UInt64
    ) {
        switch transition {
        case .start where trackedStartTransitionSequence == sequence:
            startTransitionTask = nil
            trackedStartTransitionSequence = nil
        case .retry where trackedRetryTransitionSequence == sequence:
            retryTransitionTask = nil
            trackedRetryTransitionSequence = nil
        default:
            break
        }
    }

    private func startImmediatelyIfCurrent(transitionSequence: UInt64) {
        guard latestLifecycleTransitionSequence == transitionSequence,
              !hasStarted
        else { return }

        hasStarted = true
        appGeneration &+= 1
        lifecycle.begin()
        let generation = appGeneration
        let bootstrapClientOverride = lifecycleBootstrapClientOverride
        let weakModel = WeakDashboardViewModelBox(self)
        bootstrapTask = Task { @MainActor [weakModel, bootstrapClientOverride] in
            if let bootstrapClientOverride = bootstrapClientOverride {
                try? await Self.runOwnedBootstrap(using: bootstrapClientOverride, model: weakModel)
            } else {
                await Self.runOwnedLoad(model: weakModel)
            }
            guard weakModel.value?.appGeneration == generation else { return }
            weakModel.value?.bootstrapTask = nil
        }
    }

    func retryLovelace() {
        fetchLovelace(force: true)
    }

    func retryHistoriesForActiveView() {
        let weakModel = WeakDashboardViewModelBox(self)
        Task { @MainActor [weakModel] in
            let task = weakModel.value?.enqueueFailedActiveHistoryRetry()
            await task?.value
        }
    }

    func reconnectRealtime() {
        guard lifetimeAuthority.acceptsWork, let client = webSocketClient else { return }
        let capturedGeneration = appGeneration
        reconnectTask?.cancel()
        let weakModel = WeakDashboardViewModelBox(self)
        let authority = lifetimeAuthority
        let task = Task { [client, weakModel, authority] in
            guard authority.acceptsWork, !Task.isCancelled else { return }
            await Self.runExplicitReconnect(using: client, lifetimeAuthority: authority)
            await MainActor.run {
                guard authority.acceptsWork,
                      weakModel.value?.appGeneration == capturedGeneration,
                      weakModel.value?.webSocketClient === client
                else { return }
                weakModel.value?.reconnectTask = nil
            }
        }
        reconnectTask = task
    }

    private static func runExplicitReconnect(
        using client: HomeAssistantWebSocketClient,
        lifetimeAuthority: DashboardLifetimeAuthority
    ) async {
        guard lifetimeAuthority.acceptsWork, !Task.isCancelled else { return }
        await client.connection.reconnect()
        guard lifetimeAuthority.acceptsWork, !Task.isCancelled else { return }

        // `reconnect()` initiates the connection-owned retry loop and returns.
        // Keep the app owner task alive until that loop reaches a terminal
        // authentication outcome so stop/retry/deinit can inventory and cancel
        // the complete explicit-reconnect lifetime.
        let updates = await client.connection.statusUpdates()
        for await state in updates {
            guard lifetimeAuthority.acceptsWork, !Task.isCancelled else { return }
            switch state {
            case .ready, .authenticationFailed:
                return
            case .disconnected, .reconnecting, .connecting:
                continue
            }
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
        EntityRowPresentationResolver.displayName(
            entityID: entityID,
            state: states[entityID]
        )
    }

    func displayState(for entityID: String) -> String {
        EntityStateFormatter.display(
            state: states[entityID],
            entityID: entityID,
            registryDisplayPrecision: entityDisplayPrecisions[entityID],
            preferences: frontendLocalePreferences,
            serverTimeZone: homeAssistantConfig?.timeZone,
            now: historyNow()
        ).text
    }

    func entityRowPresentation(
        _ row: LovelacePresentationRow,
        cardStateColor: Bool?
    ) -> EntityRowPresentation {
        EntityRowPresentationResolver.resolve(
            row: row,
            cardStateColor: cardStateColor,
            states: states,
            registryDisplayPrecisions: entityDisplayPrecisions,
            registryIcons: entityRegistryIcons,
            preferences: frontendLocalePreferences,
            serverTimeZone: homeAssistantConfig?.timeZone,
            now: historyNow()
        )
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
        EntityRowPresentationResolver.rowPowerDomains.contains(domain(for: entityID))
    }

    func canControlPower(entityID: String) -> Bool {
        canSetRowPower(entityID: entityID, isOn: !isOn(entityID: entityID))
    }

    func canSetRowPower(entityID: String, isOn: Bool) -> Bool {
        guard let route = EntityRowPresentationResolver.rowPowerRoute(
            entityID: entityID,
            isOn: isOn
        ) else { return false }
        return canInvokePower(entityID: entityID, requestedRoute: route)
    }

    func canSetHeaderPower(entityIDs: [String], isOn: Bool) -> Bool {
        let route = EntityRowPresentationResolver.headerPowerRoute(isOn: isOn)
        return EntityRowPresentationResolver.headerTransitionTargets(
            candidates: entityIDs,
            states: states,
            isOn: isOn
        ).contains { entityID in
            canInvokePower(entityID: entityID, requestedRoute: route)
        }
    }

    func canInvokeService(entityID: String, domain: String, service: String) -> Bool {
        serviceController.canInvoke(
            entityID: entityID,
            state: states[entityID],
            domain: domain,
            service: service
        )
    }

    func canSetFanPercentage(entityID: String, percentage: Int) -> Bool {
        if percentage <= 0 {
            return canSetRowPower(entityID: entityID, isOn: false)
        }
        return canInvokeService(
            entityID: entityID,
            domain: "fan",
            service: "set_percentage"
        )
    }

    func setPower(entityID: String, isOn: Bool) {
        guard let route = EntityRowPresentationResolver.rowPowerRoute(
            entityID: entityID,
            isOn: isOn
        ),
              canInvokePower(entityID: entityID, requestedRoute: route)
        else {
            return
        }

        performPowerCall(entityID: entityID, isOn: isOn, route: route)
    }

    func setPower(entityIDs: [String], isOn: Bool) {
        let route = EntityRowPresentationResolver.headerPowerRoute(isOn: isOn)
        let targets = EntityRowPresentationResolver.headerTransitionTargets(
            candidates: entityIDs,
            states: states,
            isOn: isOn
        )
        for entityID in targets where canInvokePower(entityID: entityID, requestedRoute: route) {
            performPowerCall(entityID: entityID, isOn: isOn, route: route)
        }
    }

    func setFanPercentage(entityID: String, percentage: Int) {
        if percentage <= 0 {
            guard canSetRowPower(entityID: entityID, isOn: false) else { return }
            performPowerCall(entityID: entityID, isOn: false)
            applyOptimisticAttributes(
                entityID: entityID,
                state: "off",
                attributes: ["percentage": .int(0)]
            )
            return
        }
        let service = "set_percentage"
        guard serviceController.canInvoke(
            entityID: entityID,
            state: states[entityID],
            domain: "fan",
            service: service
        ) else { return }

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
        guard serviceController.canInvoke(
            entityID: entityID,
            state: states[entityID],
            domain: "climate",
            service: "set_temperature"
        ) else { return }
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
        guard states[entityID]?.state != mode,
              serviceController.canInvoke(
                entityID: entityID,
                state: states[entityID],
                domain: "climate",
                service: "set_hvac_mode"
              )
        else {
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
        guard serviceController.canInvoke(
            entityID: entityID,
            state: states[entityID],
            domain: "climate",
            service: "set_preset_mode"
        ) else { return }
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
        guard states[entityID]?.attributes["fan_mode"]?.asString != mode,
              serviceController.canInvoke(
                entityID: entityID,
                state: states[entityID],
                domain: "climate",
                service: "set_fan_mode"
              )
        else {
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
        guard states[entityID]?.attributes["swing_mode"]?.asString != mode,
              serviceController.canInvoke(
                entityID: entityID,
                state: states[entityID],
                domain: "climate",
                service: "set_swing_mode"
              )
        else {
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
        _ = enqueueActiveHistoryRefresh()
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
            mountedOwnerCount: graphChartMountRegistry.liveMountCount(),
            desiredDetailHistoryKeys: desiredDetailHistoryKeys,
            detailSubscriptionKeys: Set(detailHistorySubscriptions.keys),
            detailGenerationKeys: Set(detailHistoryGenerations.keys),
            detailStartupCount: detailHistoryStartupTasks.count,
            detailHistoryKeys: Set(detailHistories.keys),
            detailStatusKeys: Set(detailHistoryStatuses.keys),
            entityOwnerActive: entityCoordinator != nil,
            candidateEntityOwnerActive: latestBootstrapEntityCoordinator != nil,
            lovelaceSubscriptionActive: lovelaceUpdateSubscription != nil,
            bootstrapTaskActive: bootstrapTask != nil,
            connectionStatusTaskActive: connectionStatusTask != nil,
            lovelaceFetchTaskActive: lovelaceFetchTask != nil,
            reconnectTaskActive: reconnectTask != nil,
            dashboardOwnerTailActive: dashboardOwnerOperationTail != nil,
            dashboardOwnerNodeCount: dashboardOwnerOperationRegistry.count,
            serviceTaskCount: serviceController.inFlightCount,
            webSocketClientActive: webSocketClient != nil,
            installedClientActive: installedBootstrapClient != nil
        )
    }

    func retryHistoriesForActiveViewForTesting() async {
        let startingSequence = latestDashboardOwnerOperationSequence
        let task = enqueueFailedActiveHistoryRetry()
        await task.value
        await awaitStableDashboardOwnerOperationTail(startingAt: startingSequence)
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
        guard lifetimeAuthority.acceptsWork else { return }
        let effectiveHours = AppConfig.graphTimeRangePolicy.detailDefault.hours
        let key = detailHistoryKey(entityID: entityID, hours: effectiveHours)
        desiredDetailHistoryKeys.insert(key)
        guard detailHistorySubscriptions[key] == nil,
              detailHistoryGenerations[key] == nil,
              let client = webSocketClient
        else { return }
        let startupID = UUID()
        let generation = UUID()
        let stateSnapshot = states
        let processingHook = historyProcessingHook
        let now = historyNow
        let authority = lifetimeAuthority
        let weakModel = WeakDashboardViewModelBox(self)
        detailHistoryGenerations[key] = generation
        detailHistoryStatuses[key] = .loading
        let task = Task { @MainActor [weakModel] in
            await Self.runDetailHistoryStartup(
                entityID: entityID,
                hours: effectiveHours,
                key: key,
                generation: generation,
                client: client,
                stateSnapshot: stateSnapshot,
                processingHook: processingHook,
                now: now,
                lifetimeAuthority: authority,
                model: weakModel
            )
            weakModel.value?.detailHistoryStartupTasks.removeValue(forKey: startupID)
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

    private static func runOwnedLoad(model weakModel: WeakDashboardViewModelBox) async {
        do {
            weakModel.value?.lifecycle.set(.bootstrap, phase: .loading)
            guard let token = try weakModel.value?.loadToken() else { return }
            weakModel.value?.lifecycle.begin()
            let connection = try await Self.firstWorkingConnection(token: token)
            guard let webSocket = weakModel.value?.installOwnedLoadConnection(connection) else { return }
            try await runOwnedBootstrap(using: webSocket, model: weakModel)
        } catch {
            guard weakModel.value?.lifecycle.phase != .stopped else { return }
            weakModel.value?.lifecycle.failBootstrap(error.localizedDescription)
        }
    }

    private static func runOwnedBootstrap(
        using webSocket: HomeAssistantWebSocketClient,
        model weakModel: WeakDashboardViewModelBox
    ) async throws {
        guard let start = weakModel.value?.beginOwnedBootstrap(using: webSocket) else {
            await webSocket.disconnect()
            return
        }
        await start.obsoleteCandidate?.stop()
        guard weakModel.value?.isCurrentBootstrap(start.sequence, client: webSocket) == true else {
            await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
            return
        }

        do {
            try await webSocket.connect()
            guard weakModel.value?.isCurrentBootstrap(start.sequence, client: webSocket) == true else {
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }

            async let registryResponse = try? await webSocket.fetchEntityRegistryDisplay()
            async let localeResponse = try? await webSocket.fetchFrontendLocalePreferences()
            async let currentUserResponse = fetchCurrentUserResult(using: webSocket)
            let config = try await webSocket.fetchLovelaceConfig()
            let (registry, locale, currentUserResult) = await (
                registryResponse,
                localeResponse,
                currentUserResponse
            )
            let registryMetadata = entityRegistryPresentationMetadata(registry ?? nil)
            guard let candidate = weakModel.value?.prepareOwnedBootstrapCandidate(
                sequence: start.sequence,
                client: webSocket,
                locale: locale ?? nil,
                currentUserResult: currentUserResult,
                weakModel: weakModel
            ) else {
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }

            _ = try await candidate.start(using: webSocket)
            guard weakModel.value?.isCurrentBootstrap(start.sequence, client: webSocket) == true else {
                await candidate.stop()
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }

            await applyLovelaceConfig(
                config,
                startHistoryOwners: false,
                bootstrapSequence: start.sequence,
                model: weakModel
            )
            guard weakModel.value?.isCurrentBootstrap(start.sequence, client: webSocket) == true else {
                await candidate.stop()
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }

            let updateSubscription = try await webSocket.subscribeLovelaceUpdates {
                await MainActor.run {
                    guard weakModel.value?.isCurrentInstalledBootstrap(
                        start.sequence,
                        client: webSocket
                    ) == true else { return }
                    weakModel.value?.fetchLovelace(force: false)
                }
            }
            guard weakModel.value?.isCurrentBootstrap(start.sequence, client: webSocket) == true else {
                await updateSubscription.cancel()
                await candidate.stop()
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }

            guard let retirement = weakModel.value?.beginOwnedBootstrapInstallation(
                sequence: start.sequence,
                client: webSocket
            ) else {
                await updateSubscription.cancel()
                await candidate.stop()
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }
            await retirement.entity?.stop()
            await retirement.lovelace?.cancel()
            await retirement.statusTask?.value
            if let oldClient = retirement.client, oldClient !== webSocket {
                await disconnectOwnedClientIfNeeded(oldClient, model: weakModel)
            }
            guard weakModel.value?.isCurrentBootstrap(start.sequence, client: webSocket) == true else {
                await updateSubscription.cancel()
                await candidate.stop()
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }

            let proof = try candidate.proveLiveGenerationForInstallation()
            guard weakModel.value?.finishOwnedBootstrapInstallation(
                sequence: start.sequence,
                client: webSocket,
                entityCoordinator: candidate,
                lovelaceUpdateSubscription: updateSubscription,
                entityProof: proof,
                registryDisplayPrecisions: registryMetadata.precisions,
                registryIcons: registryMetadata.icons
            ) == true else {
                await updateSubscription.cancel()
                await candidate.stop()
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                return
            }
            weakModel.value?.enqueueCurrentDashboardOwnerCandidate(
                startHistoryOwners: true,
                runsCandidateHook: false
            )
        } catch {
            guard let failure = weakModel.value?.beginOwnedBootstrapFailure(
                sequence: start.sequence,
                client: webSocket,
                error: error
            ) else {
                await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
                throw error
            }
            for task in failure.serviceTasks { await task.value }
            await failure.entity?.stop()
            if failure.candidate !== failure.entity { await failure.candidate?.stop() }
            await failure.lovelace?.cancel()
            await failure.statusTask?.value
            if let oldClient = failure.installedClient, oldClient !== webSocket {
                await disconnectOwnedClientIfNeeded(oldClient, model: weakModel)
            }
            await disconnectOwnedClientIfNeeded(webSocket, model: weakModel)
            throw error
        }
    }

    private static func disconnectOwnedClientIfNeeded(
        _ client: HomeAssistantWebSocketClient,
        model weakModel: WeakDashboardViewModelBox
    ) async {
        guard weakModel.value?.clientIsCurrentlyOwned(client) != true else { return }
        await client.disconnect()
    }

    private func beginOwnedBootstrap(using client: HomeAssistantWebSocketClient) -> OwnedBootstrapStart {
        latestBootstrapSequence &+= 1
        let sequence = latestBootstrapSequence
        let obsolete = latestBootstrapEntityCoordinator
        latestBootstrapEntityCoordinator = nil
        latestBootstrapClient = client
        lifecycle.begin()
        return OwnedBootstrapStart(sequence: sequence, obsoleteCandidate: obsolete)
    }

    private func installOwnedLoadConnection(_ connection: Connection) -> HomeAssistantWebSocketClient {
        activeBaseURL = connection.baseURL
        restClient = connection.restClient
        homeAssistantConfig = connection.homeAssistantConfig
        lifecycle.loading()
        return HomeAssistantWebSocketClient(
            configuration: connection.configuration,
            commandTimeout: AppConfig.webSocketPolicy.commandTimeout,
            receivePolicy: AppConfig.webSocketPolicy.receivePolicy,
            subscriptionDeliveryCapacity: AppConfig.webSocketPolicy.subscriptionDeliveryCapacity,
            maximumConcurrentCallbackTasks: AppConfig.webSocketPolicy.maximumConcurrentCallbackTasks
        )
    }

    private func prepareOwnedBootstrapCandidate(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient,
        locale: HAFrontendLocalePreferences?,
        currentUserResult: Result<HACurrentUser, Error>,
        weakModel: WeakDashboardViewModelBox
    ) -> HAEntitySubscriptionCoordinator? {
        guard isCurrentBootstrap(sequence, client: client) else { return nil }
        frontendLocalePreferences = locale
        switch currentUserResult {
        case let .success(user): currentUserID = user.id
        case .failure:
            currentUserID = nil
            AppLog(
                "Current user metadata unavailable; user-restricted navigation is hidden",
                severity: .warning,
                category: .lifecycle
            )
        }
        let weakEntityOwner = WeakInstalledEntityCoordinatorBox()
        let entityTaskOwnerID = UUID()
        let emergencyBag = emergencyOwnershipBag
        let candidate = HAEntitySubscriptionCoordinator(
            initialStates: states,
            lifetimeAuthority: lifetimeAuthority,
            taskObserver: { tasks in
                emergencyBag.setEntityCoordinatorTasks(tasks, ownerID: entityTaskOwnerID)
            },
            onSnapshot: { snapshot in
                guard let owner = weakEntityOwner.value,
                      weakModel.value?.entityCoordinator === owner
                else { return }
                weakModel.value?.states = snapshot
            },
            onPhase: { phase in
                guard let owner = weakEntityOwner.value,
                      weakModel.value?.entityCoordinator === owner
                else { return }
                weakModel.value?.lifecycle.set(.entities, phase: phase)
            }
        )
        weakEntityOwner.value = candidate
        latestBootstrapEntityCoordinator = candidate
        return candidate
    }

    private func beginOwnedBootstrapInstallation(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) -> OwnedBootstrapRetirement? {
        guard isCurrentBootstrap(sequence, client: client) else { return nil }
        let retirement = OwnedBootstrapRetirement(
            entity: entityCoordinator,
            lovelace: lovelaceUpdateSubscription,
            statusTask: connectionStatusTask,
            client: installedBootstrapClient
        )
        entityCoordinator = nil
        lovelaceUpdateSubscription = nil
        connectionStatusTask = nil
        webSocketClient = nil
        installedBootstrapClient = nil
        installedBootstrapSequence = nil
        entityDisplayPrecisions = [:]
        entityRegistryIcons = [:]
        retirement.statusTask?.cancel()
        return retirement
    }

    private func finishOwnedBootstrapInstallation(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient,
        entityCoordinator candidate: HAEntitySubscriptionCoordinator,
        lovelaceUpdateSubscription: HAWebSocketSubscription,
        entityProof: HAEntitySubscriptionInstallationProof,
        registryDisplayPrecisions: [String: Int],
        registryIcons: [String: String]
    ) -> Bool {
        guard isCurrentBootstrap(sequence, client: client) else { return false }
        entityCoordinator = candidate
        latestBootstrapEntityCoordinator = nil
        self.lovelaceUpdateSubscription = lovelaceUpdateSubscription
        states = entityProof.snapshot
        entityDisplayPrecisions = registryDisplayPrecisions
        entityRegistryIcons = registryIcons
        webSocketClient = client
        installedBootstrapClient = client
        installedBootstrapSequence = sequence
        lifecycle.installed()
        serviceController.install { [weak restClient] domain, service, data in
            guard let restClient = restClient else { throw URLError(.cancelled) }
            _ = try await restClient.callService(domain: domain, service: service, data: data)
        }
        connectionStatusTask = makeConnectionStatusTask(sequence: sequence, client: client)
        return true
    }

    private func beginOwnedBootstrapFailure(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient,
        error: Error
    ) -> OwnedBootstrapFailure? {
        guard isCurrentBootstrap(sequence, client: client) else { return nil }
        let failure = OwnedBootstrapFailure(
            serviceTasks: serviceController.stopSynchronously(),
            entity: entityCoordinator,
            candidate: latestBootstrapEntityCoordinator,
            lovelace: lovelaceUpdateSubscription,
            statusTask: connectionStatusTask,
            installedClient: installedBootstrapClient
        )
        restClient = nil
        entityCoordinator = nil
        latestBootstrapEntityCoordinator = nil
        lovelaceUpdateSubscription = nil
        connectionStatusTask = nil
        webSocketClient = nil
        installedBootstrapClient = nil
        installedBootstrapSequence = nil
        latestBootstrapClient = nil
        entityDisplayPrecisions = [:]
        entityRegistryIcons = [:]
        failure.statusTask?.cancel()
        lifecycle.failBootstrap(error.localizedDescription)
        return failure
    }

    private func clientIsCurrentlyOwned(_ client: HomeAssistantWebSocketClient) -> Bool {
        latestBootstrapClient === client || installedBootstrapClient === client || webSocketClient === client
    }

    private func load() async {
        do {
            lifecycle.set(.bootstrap, phase: .loading)
            let token = try loadToken()

            lifecycle.begin()
            let connection = try await Self.firstWorkingConnection(token: token)
            activeBaseURL = connection.baseURL
            restClient = connection.restClient
            homeAssistantConfig = connection.homeAssistantConfig

            lifecycle.loading()
            let webSocket = HomeAssistantWebSocketClient(
                configuration: connection.configuration,
                commandTimeout: AppConfig.webSocketPolicy.commandTimeout,
                receivePolicy: AppConfig.webSocketPolicy.receivePolicy,
                subscriptionDeliveryCapacity: AppConfig.webSocketPolicy.subscriptionDeliveryCapacity,
                maximumConcurrentCallbackTasks: AppConfig.webSocketPolicy.maximumConcurrentCallbackTasks
            )
            try await bootstrapDashboard(using: webSocket)
        } catch {
            guard lifecycle.phase != .stopped else { return }
            lifecycle.failBootstrap(error.localizedDescription)
        }
    }

    func bootstrapDashboard(using webSocket: HomeAssistantWebSocketClient) async throws {
        latestBootstrapSequence &+= 1
        let bootstrapSequence = latestBootstrapSequence
        let obsoleteCandidateEntityCoordinator = latestBootstrapEntityCoordinator
        latestBootstrapEntityCoordinator = nil
        latestBootstrapClient = webSocket
        lifecycle.begin()
        await obsoleteCandidateEntityCoordinator?.stop()
        guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
            await disconnectIfUnownedByCurrentBootstrap(webSocket)
            return
        }

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
            let registryMetadata = Self.entityRegistryPresentationMetadata(registry ?? nil)
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

            let weakModel = WeakDashboardViewModelBox(self)
            let weakEntityOwner = WeakInstalledEntityCoordinatorBox()
            let entityTaskOwnerID = UUID()
            let emergencyBag = emergencyOwnershipBag
            let candidateEntityCoordinator = HAEntitySubscriptionCoordinator(
                initialStates: states,
                lifetimeAuthority: lifetimeAuthority,
                taskObserver: { tasks in
                    emergencyBag.setEntityCoordinatorTasks(tasks, ownerID: entityTaskOwnerID)
                },
                onSnapshot: { snapshot in
                    guard let owner = weakEntityOwner.value,
                          weakModel.value?.entityCoordinator === owner
                    else { return }
                    weakModel.value?.states = snapshot
                },
                onPhase: { phase in
                    guard let owner = weakEntityOwner.value,
                          weakModel.value?.entityCoordinator === owner
                    else { return }
                    weakModel.value?.lifecycle.set(.entities, phase: phase)
                }
            )
            weakEntityOwner.value = candidateEntityCoordinator
            latestBootstrapEntityCoordinator = candidateEntityCoordinator
            _ = try await candidateEntityCoordinator.start(using: webSocket)
            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await candidateEntityCoordinator.stop()
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }
            await applyLovelaceConfig(
                config,
                startHistoryOwners: false,
                bootstrapSequence: bootstrapSequence
            )

            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await candidateEntityCoordinator.stop()
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }

            let candidateLovelaceSubscription = try await webSocket.subscribeLovelaceUpdates {
                await MainActor.run {
                    guard weakModel.value?.isCurrentInstalledBootstrap(
                        bootstrapSequence,
                        client: webSocket
                    ) == true else { return }
                    weakModel.value?.fetchLovelace(force: false)
                }
            }
            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await candidateLovelaceSubscription.cancel()
                await candidateEntityCoordinator.stop()
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }

            let installed = try await installBootstrapOwnership(
                sequence: bootstrapSequence,
                client: webSocket,
                entityCoordinator: candidateEntityCoordinator,
                lovelaceUpdateSubscription: candidateLovelaceSubscription,
                registryDisplayPrecisions: registryMetadata.precisions,
                registryIcons: registryMetadata.icons
            )
            guard installed else { return }

            enqueueCurrentDashboardOwnerCandidate(
                startHistoryOwners: true,
                runsCandidateHook: false
            )
        } catch {
            guard isCurrentBootstrap(bootstrapSequence, client: webSocket) else {
                await disconnectIfUnownedByCurrentBootstrap(webSocket)
                return
            }
            // A fatal replacement invalidates every installed app-generation
            // authority before publishing failure or awaiting transport
            // teardown. In particular, retained cards must not keep using the
            // previous REST caller while the old and failed socket owners are
            // being retired.
            let serviceTasks = serviceController.stopSynchronously()
            restClient = nil
            lifecycle.failBootstrap(error.localizedDescription)
            await failCurrentBootstrap(
                sequence: bootstrapSequence,
                client: webSocket,
                serviceTasks: serviceTasks
            )
            throw error
        }
    }

    private func isCurrentBootstrap(
        _ sequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) -> Bool {
        lifetimeAuthority.acceptsWork &&
            latestBootstrapSequence == sequence &&
            latestBootstrapClient === client
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
        client: HomeAssistantWebSocketClient,
        serviceTasks: [Task<Void, Never>]
    ) async {
        guard isCurrentBootstrap(sequence, client: client) else {
            for task in serviceTasks { await task.value }
            await disconnectIfUnownedByCurrentBootstrap(client)
            return
        }

        let installedClient = installedBootstrapClient
        let candidateEntityCoordinator = latestBootstrapEntityCoordinator
        let entityCoordinator = entityCoordinator
        let lovelaceSubscription = lovelaceUpdateSubscription
        let statusTask = connectionStatusTask
        self.entityCoordinator = nil
        latestBootstrapEntityCoordinator = nil
        lovelaceUpdateSubscription = nil
        connectionStatusTask = nil
        webSocketClient = nil
        installedBootstrapClient = nil
        installedBootstrapSequence = nil
        entityDisplayPrecisions = [:]
        entityRegistryIcons = [:]
        statusTask?.cancel()
        // stopSynchronously already advanced the action generation, removed
        // the caller/task registry, and cancelled these captured tasks before
        // lifecycle failure was published. Settle them before either the old
        // or failed transport completes its disconnect boundary.
        for task in serviceTasks { await task.value }
        await entityCoordinator?.stop()
        if candidateEntityCoordinator !== entityCoordinator {
            await candidateEntityCoordinator?.stop()
        }
        await lovelaceSubscription?.cancel()
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
        entityCoordinator candidateEntityCoordinator: HAEntitySubscriptionCoordinator,
        lovelaceUpdateSubscription candidateLovelaceSubscription: HAWebSocketSubscription,
        registryDisplayPrecisions: [String: Int],
        registryIcons: [String: String]
    ) async throws -> Bool {
        guard isCurrentBootstrap(sequence, client: client) else {
            await candidateEntityCoordinator.stop()
            await candidateLovelaceSubscription.cancel()
            await disconnectIfUnownedByCurrentBootstrap(client)
            return false
        }

        let oldEntityCoordinator = entityCoordinator
        let oldLovelaceSubscription = lovelaceUpdateSubscription
        let oldStatusTask = connectionStatusTask
        let oldClient = installedBootstrapClient
        entityCoordinator = nil
        lovelaceUpdateSubscription = nil
        connectionStatusTask = nil
        webSocketClient = nil
        installedBootstrapClient = nil
        installedBootstrapSequence = nil
        entityDisplayPrecisions = [:]
        entityRegistryIcons = [:]
        oldStatusTask?.cancel()
        await oldEntityCoordinator?.stop()
        await oldLovelaceSubscription?.cancel()

        if let oldClient = oldClient, oldClient !== client {
            await disconnectIfUnownedByCurrentBootstrap(oldClient)
        }

        guard isCurrentBootstrap(sequence, client: client) else {
            await candidateEntityCoordinator.stop()
            await candidateLovelaceSubscription.cancel()
            await disconnectIfUnownedByCurrentBootstrap(client)
            return false
        }

        // This is the final candidate check. No suspension may occur between
        // proving the accepted live entity generation, copying its retained
        // store, assigning publication authority, and publishing lifecycle
        // readiness. A candidate invalidated while bootstrap work was held can
        // therefore never be installed from its stale retained snapshot.
        let entityProof: HAEntitySubscriptionInstallationProof
        do {
            entityProof = try candidateEntityCoordinator.proveLiveGenerationForInstallation()
        } catch {
            await candidateLovelaceSubscription.cancel()
            throw error
        }
        entityCoordinator = candidateEntityCoordinator
        latestBootstrapEntityCoordinator = nil
        lovelaceUpdateSubscription = candidateLovelaceSubscription
        states = entityProof.snapshot
        entityDisplayPrecisions = registryDisplayPrecisions
        entityRegistryIcons = registryIcons
        webSocketClient = client
        installedBootstrapClient = client
        installedBootstrapSequence = sequence
        lifecycle.installed()
        serviceController.install { [weak restClient] domain, service, data in
            guard let restClient = restClient else { throw URLError(.cancelled) }
            _ = try await restClient.callService(domain: domain, service: service, data: data)
        }
        AppLog("Dashboard successfully connected and became Live", category: .lifecycle)
        connectionStatusTask = makeConnectionStatusTask(sequence: sequence, client: client)
        return true
    }

    private func makeConnectionStatusTask(
        sequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) -> Task<Void, Never> {
        let authority = lifetimeAuthority
        return Task { [weak self, client, authority] in
            for await connectionState in await client.connection.statusUpdates() {
                guard authority.acceptsWork, !Task.isCancelled else { return }
                await MainActor.run {
                    guard authority.acceptsWork,
                          self?.isCurrentInstalledBootstrap(sequence, client: client) == true
                    else {
                        return
                    }
                    let nextStatus: String
                    switch connectionState {
                    case .ready:
                        nextStatus = "Live"
                        self?.lifecycle.connectionChanged(.ready)
                        if self?.connectionWasNonReady == true {
                            self?.connectionWasNonReady = false
                            self?.refreshLovelaceAfterReconnect(
                                bootstrapSequence: sequence,
                                client: client
                            )
                        }
                    case .disconnected:
                        nextStatus = "Disconnected"
                        self?.connectionWasNonReady = true
                        self?.lifecycle.connectionChanged(.disconnected)
                    case .reconnecting:
                        nextStatus = "Reconnecting"
                        self?.connectionWasNonReady = true
                        self?.lifecycle.connectionChanged(.reconnecting)
                    case let .authenticationFailed(message):
                        nextStatus = "Error"
                        self?.lifecycle.set(
                            .realtime,
                            phase: .failed("WebSocket authentication failed: \(message)")
                        )
                    case .connecting:
                        nextStatus = "Connecting"
                        self?.connectionWasNonReady = true
                        self?.lifecycle.set(.realtime, phase: .loading)
                    }
                    _ = nextStatus
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

    private func fetchLovelace(force: Bool) {
        guard lifetimeAuthority.acceptsWork,
              let client = webSocketClient,
              let sequence = installedBootstrapSequence,
              isCurrentInstalledBootstrap(sequence, client: client)
        else { return }
        latestLovelaceFetchGeneration &+= 1
        let fetchGeneration = latestLovelaceFetchGeneration
        let capturedAppGeneration = appGeneration
        let authority = lifetimeAuthority
        lovelaceFetchTask?.cancel()
        lovelaceStore.beginLoading(retainingInstalled: hasLoadedDashboard)
        lifecycle.set(.lovelace, phase: hasLoadedDashboard ? .reconnecting : .loading)
        lovelaceFetchTask = Task { @MainActor [weak self, authority] in
            guard authority.acceptsWork, !Task.isCancelled else { return }
            do {
                let config = try await client.fetchLovelaceConfig(force: force)
                guard authority.acceptsWork,
                      !Task.isCancelled,
                      self?.appGeneration == capturedAppGeneration,
                      self?.latestLovelaceFetchGeneration == fetchGeneration,
                      self?.isCurrentInstalledBootstrap(sequence, client: client) == true
                else { return }
                guard let weakModel = self.map(WeakDashboardViewModelBox.init) else { return }
                await Self.applyLovelaceConfig(
                    config,
                    startHistoryOwners: true,
                    bootstrapSequence: nil,
                    model: weakModel
                )
                guard authority.acceptsWork,
                      weakModel.value?.appGeneration == capturedAppGeneration,
                      weakModel.value?.latestLovelaceFetchGeneration == fetchGeneration,
                      weakModel.value?.isCurrentInstalledBootstrap(sequence, client: client) == true
                else { return }
                weakModel.value?.lifecycle.set(.lovelace, phase: .ready)
                weakModel.value?.lovelaceFetchTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard authority.acceptsWork,
                      self?.appGeneration == capturedAppGeneration,
                      self?.latestLovelaceFetchGeneration == fetchGeneration,
                      self?.isCurrentInstalledBootstrap(sequence, client: client) == true
                else { return }
                self?.lovelaceStore.fail(error.localizedDescription)
                self?.lifecycle.set(.lovelace, phase: .failed(error.localizedDescription))
                self?.lovelaceFetchTask = nil
            }
        }
    }

    private func refreshLovelaceAfterReconnect(
        bootstrapSequence: UInt64,
        client: HomeAssistantWebSocketClient
    ) {
        guard isCurrentInstalledBootstrap(bootstrapSequence, client: client) else { return }
        fetchLovelace(force: false)
    }

    private func enqueueFailedActiveHistoryRetry() -> Task<Void, Never> {
        let capturedConfigSequence = latestConfigRequestSequence
        latestDashboardOwnerOperationSequence &+= 1
        let operationSequence = latestDashboardOwnerOperationSequence
        let previousTail = dashboardOwnerOperationTail
        let weakModel = WeakDashboardViewModelBox(self)
        let operationRegistry = dashboardOwnerOperationRegistry
        let task = Task { @MainActor [weakModel, operationRegistry] in
            defer { operationRegistry.finish(sequence: operationSequence) }
            await previousTail?.value
            guard !Task.isCancelled,
                  let detached = weakModel.value?.detachFailedActiveHistoryOwnership(
                    configRequestSequence: capturedConfigSequence
                  )
            else { return }
            operationRegistry.setDetachedOwnership(
                DetachedDashboardOwnership(
                    startups: detached.cardStartups,
                    subscriptions: detached.cardSubscriptions,
                    detailStartups: detached.detailStartups,
                    detailSubscriptions: [detached.detailSubscription].compactMap { $0 }
                ),
                sequence: operationSequence
            )

            for startup in detached.cardStartups { await startup.value }
            for subscription in detached.cardSubscriptions { await subscription.cancel() }
            for startup in detached.detailStartups { await startup.value }
            await detached.detailSubscription?.cancel()

            guard !Task.isCancelled,
                  weakModel.value?.latestConfigRequestSequence == capturedConfigSequence
            else { return }
            let startups = weakModel.value?.beginMissingActiveHistoryStartups(
                configRequestSequence: capturedConfigSequence
            ) ?? []
            if let detail = detached.detailRetry,
               weakModel.value?.selectedEntityID == detail.entityID,
               weakModel.value?.desiredDetailHistoryKeys.contains(detail.key) == true {
                weakModel.value?.loadDetailHistory(
                    entityID: detail.entityID,
                    hours: detail.hours
                )
            }
            for startup in startups { await startup.value }
        }
        operationRegistry.register(
            DashboardOwnerOperationNode(task: task, detachedOwnership: nil),
            sequence: operationSequence
        )
        dashboardOwnerOperationTail = task
        return task
    }

    private func enqueueActiveHistoryRefresh() -> Task<Void, Never> {
        let capturedConfigSequence = latestConfigRequestSequence
        latestDashboardOwnerOperationSequence &+= 1
        let operationSequence = latestDashboardOwnerOperationSequence
        let previousTail = dashboardOwnerOperationTail
        let weakModel = WeakDashboardViewModelBox(self)
        let operationRegistry = dashboardOwnerOperationRegistry
        let task = Task { @MainActor [weakModel, operationRegistry] in
            defer { operationRegistry.finish(sequence: operationSequence) }
            await previousTail?.value
            guard !Task.isCancelled,
                  let ownership = weakModel.value?.prepareActiveHistoryRefresh(
                    configRequestSequence: capturedConfigSequence
                  )
            else { return }

            for startup in ownership.startups { await startup.value }
            for owner in ownership.refreshes {
                guard !Task.isCancelled,
                      weakModel.value?.isCurrentHistoryRefreshOwner(
                        owner,
                        configRequestSequence: capturedConfigSequence
                      ) == true
                else { return }
                do {
                    try await owner.subscription.refresh()
                } catch {
                    weakModel.value?.failHistoryRefresh(
                        owner,
                        configRequestSequence: capturedConfigSequence,
                        error: error
                    )
                }
            }
        }
        operationRegistry.register(
            DashboardOwnerOperationNode(task: task, detachedOwnership: nil),
            sequence: operationSequence
        )
        dashboardOwnerOperationTail = task
        return task
    }

    private func prepareActiveHistoryRefresh(
        configRequestSequence: UInt64
    ) -> HistoryRefreshOwnership? {
        guard latestConfigRequestSequence == configRequestSequence else { return nil }
        let startups = beginMissingActiveHistoryStartups(
            configRequestSequence: configRequestSequence
        )
        let reconciliationEpoch = historyReconciliationEpoch
        let refreshes: [HistoryRefreshOwner] = historySubscriptions.compactMap { key, subscription in
            guard desiredHistoryKeys.contains(key),
                  let generation = historyGenerations[key]
            else { return nil }
            historyStatuses[key] = .loading
            return HistoryRefreshOwner(
                key: key,
                generation: generation,
                reconciliationEpoch: reconciliationEpoch,
                subscription: subscription
            )
        }
        return HistoryRefreshOwnership(startups: startups, refreshes: refreshes)
    }

    private func isCurrentHistoryRefreshOwner(
        _ owner: HistoryRefreshOwner,
        configRequestSequence: UInt64
    ) -> Bool {
        latestConfigRequestSequence == configRequestSequence &&
            historyReconciliationEpoch == owner.reconciliationEpoch &&
            desiredHistoryKeys.contains(owner.key) &&
            historyGenerations[owner.key] == owner.generation &&
            historySubscriptions[owner.key] === owner.subscription
    }

    private func failHistoryRefresh(
        _ owner: HistoryRefreshOwner,
        configRequestSequence: UInt64,
        error: Error
    ) {
        guard isCurrentHistoryRefreshOwner(
            owner,
            configRequestSequence: configRequestSequence
        ) else { return }
        historyStatuses[owner.key] = .error(error.localizedDescription)
    }

    private func detachFailedActiveHistoryOwnership(
        configRequestSequence: UInt64
    ) -> FailedHistoryRetryOwnership? {
        guard latestConfigRequestSequence == configRequestSequence else { return nil }
        let activeKeys = Set(historyRequests().map(\.key))
        let failedKeys = activeKeys.filter { key in
                guard let status = historyStatuses[key] else { return true }
                if case .error = status { return true }
                return historySubscriptions[key] == nil
        }
        let startupIDs = historyStartupTasks.compactMap { id, startup in
            failedKeys.contains(startup.key) ? id : nil
        }
        let cardStartups = startupIDs.compactMap {
            historyStartupTasks.removeValue(forKey: $0)?.task
        }
        cardStartups.forEach { $0.cancel() }
        var cardSubscriptions: [HAHistoryStreamSubscription] = []
        for key in failedKeys {
            if let subscription = historySubscriptions.removeValue(forKey: key) {
                cardSubscriptions.append(subscription)
            }
            historyGenerations.removeValue(forKey: key)
            graphHistoryRevisionFeeds.removeValue(forKey: key)
            historyStatuses.removeValue(forKey: key)
            histories.removeValue(forKey: key)
        }

        let detail = detachCurrentFailedDetailForRetry()
        return FailedHistoryRetryOwnership(
            cardStartups: cardStartups,
            cardSubscriptions: cardSubscriptions,
            detailStartups: detail?.startups ?? [],
            detailSubscription: detail?.subscription,
            detailRetry: detail.map {
                FailedDetailHistoryRetry(entityID: $0.entityID, key: $0.key, hours: $0.hours)
            }
        )
    }

    private func beginMissingActiveHistoryStartups(
        configRequestSequence: UInt64
    ) -> [Task<Void, Never>] {
        guard latestConfigRequestSequence == configRequestSequence,
              let client = webSocketClient
        else { return [] }
        let reconciliationEpoch = historyReconciliationEpoch
        return historyRequests().compactMap { request in
            beginHistoryStartup(
                request,
                webSocketClient: client,
                reconciliationEpoch: reconciliationEpoch,
                configRequestSequence: configRequestSequence
            )
        }
    }

    private func detachCurrentFailedDetailForRetry() -> (
        entityID: String,
        key: String,
        hours: Int,
        startups: [Task<Void, Never>],
        subscription: HAHistoryStreamSubscription?
    )? {
        let hours = AppConfig.graphTimeRangePolicy.detailDefault.hours
        guard let entityID = selectedEntityID else { return nil }
        let key = detailHistoryKey(entityID: entityID, hours: hours)
        guard desiredDetailHistoryKeys.contains(key) else { return nil }
        let shouldRetry: Bool
        if case .error = detailHistoryStatuses[key] {
            shouldRetry = true
        } else {
            shouldRetry = detailHistorySubscriptions[key] == nil
        }
        guard shouldRetry else { return nil }

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
        detailHistories.removeValue(forKey: key)
        return (entityID, key, hours, startups, subscription)
    }

    func stop() async {
        let transition = enqueueLifecycleTransition(.stop)
        await transition.value
    }

    private func finishStopIfCurrent(transitionSequence: UInt64) {
        guard latestLifecycleTransitionSequence == transitionSequence else { return }
        lovelaceStore.stop()
        lifecycle.stop()
    }

    private func detachAppOwnershipSynchronously() -> DetachedDashboardAppOwnership {
        // All callback authority and owner registries are invalidated before
        // the first await. Captured handles are the only objects retired below.
        appGeneration &+= 1
        latestBootstrapSequence &+= 1
        latestConfigRequestSequence &+= 1
        latestNavigationRequestSequence &+= 1
        latestLovelaceFetchGeneration &+= 1
        latestDashboardOwnerOperationSequence &+= 1
        hasStarted = false
        connectionWasNonReady = false
        desiredSelectedViewIdentity = nil
        latestQueuedDashboardCandidate = nil

        let bootstrapTask = self.bootstrapTask
        let statusTask = connectionStatusTask
        let configTask = lovelaceFetchTask
        let reconnectTask = self.reconnectTask
        let ownerTail = dashboardOwnerOperationTail
        let ownerOperations = dashboardOwnerOperationRegistry.detachSynchronously()
        let entityOwner = entityCoordinator
        let candidateEntityOwner = latestBootstrapEntityCoordinator
        let lovelaceSubscription = lovelaceUpdateSubscription
        var clients: [HomeAssistantWebSocketClient] = []
        for client in [installedBootstrapClient, latestBootstrapClient, webSocketClient].compactMap({ $0 })
            where !clients.contains(where: { $0 === client })
        {
            clients.append(client)
        }
        var detachedEntityOwnerships: [HAEntitySubscriptionDetachedOwnership] = []
        if let entityOwner = entityOwner {
            detachedEntityOwnerships.append(entityOwner.detachOwnershipSynchronously())
        }
        if let candidateEntityOwner = candidateEntityOwner,
           candidateEntityOwner !== entityOwner
        {
            detachedEntityOwnerships.append(candidateEntityOwner.detachOwnershipSynchronously())
        }
        let detachedHistory = detachOwnershipSynchronously(notIn: [])
        // Explicit app stop is stronger than ordinary view/config
        // reconciliation. A card startup may be suspended awaiting its wire
        // acknowledgement; cancelling the captured task propagates into the
        // Module 02 registration cancellation handler before we await it or
        // disconnect the socket. Ordinary reconciliation deliberately keeps
        // its acknowledgement-before-cancel ordering unchanged.
        detachedHistory.startups.forEach { $0.cancel() }
        for operation in ownerOperations {
            operation.task.cancel()
            operation.detachedOwnership?.startups.forEach { $0.cancel() }
            operation.detachedOwnership?.detailStartups.forEach { $0.cancel() }
        }
        graphChartMountRegistry.invalidateOwners(notIn: [])
        graphHistoryRevisionFeeds.removeAll()
        historyStatuses.removeAll()
        histories.removeAll()
        let serviceTasks = serviceController.stopSynchronously()

        self.bootstrapTask = nil
        connectionStatusTask = nil
        lovelaceFetchTask = nil
        self.reconnectTask = nil
        dashboardOwnerOperationTail = nil
        entityCoordinator = nil
        latestBootstrapEntityCoordinator = nil
        lovelaceUpdateSubscription = nil
        webSocketClient = nil
        installedBootstrapClient = nil
        installedBootstrapSequence = nil
        latestBootstrapClient = nil
        restClient = nil
        entityDisplayPrecisions = [:]
        entityRegistryIcons = [:]

        bootstrapTask?.cancel()
        statusTask?.cancel()
        configTask?.cancel()
        reconnectTask?.cancel()
        ownerTail?.cancel()
        serviceTasks.forEach { $0.cancel() }
        return DetachedDashboardAppOwnership(
            bootstrapTask: bootstrapTask,
            statusTask: statusTask,
            configTask: configTask,
            reconnectTask: reconnectTask,
            ownerTail: ownerTail,
            ownerOperations: ownerOperations,
            serviceTasks: serviceTasks,
            entityOwnerships: detachedEntityOwnerships,
            lovelaceSubscription: lovelaceSubscription,
            historyOwnership: detachedHistory,
            clients: clients
        )
    }

    private static func finishExplicitAppOwnership(
        _ detached: DetachedDashboardAppOwnership
    ) async {
        for ownership in detached.entityOwnerships {
            await ownership.finish()
        }
        await detached.lovelaceSubscription?.cancel()
        await finishDetachedOwnership(detached.historyOwnership)
        for operation in detached.ownerOperations {
            if let ownership = operation.detachedOwnership {
                await finishDetachedOwnership(ownership)
            }
        }
        await detached.bootstrapTask?.value
        await detached.statusTask?.value
        await detached.configTask?.value
        await detached.reconnectTask?.value
        for operation in detached.ownerOperations { await operation.task.value }
        await detached.ownerTail?.value
        for task in detached.serviceTasks { await task.value }
        for client in detached.clients { await client.disconnect() }
    }

    func setLifecyclePhaseForTesting(_ phase: DashboardLifecyclePhase) {
        switch phase {
        case .ready:
            lifecycle.installed()
        case .reconnecting, .disconnected:
            lifecycle.connectionChanged(phase)
        case .failed:
            lifecycle.failBootstrap("Injected test failure")
        case .stopped:
            lifecycle.stop()
        case .connecting:
            lifecycle.begin()
        case .loading:
            lifecycle.begin(); lifecycle.loading()
        case .idle:
            lifecycle = DashboardLifecycle()
        }
    }

    func setComponentPhaseForTesting(
        _ component: DashboardComponent,
        phase: DashboardComponentPhase
    ) {
        lifecycle.set(component, phase: phase)
    }

    func bootstrapCandidateEntityCoordinatorForTesting() -> HAEntitySubscriptionCoordinator? {
        latestBootstrapEntityCoordinator
    }

    func installedEntityCoordinatorForTesting() -> HAEntitySubscriptionCoordinator? {
        entityCoordinator
    }

    func installBootstrapCandidateEntityCoordinatorForTesting(
        _ coordinator: HAEntitySubscriptionCoordinator
    ) {
        latestBootstrapEntityCoordinator = coordinator
    }

    func installDashboardOwnerTailForTesting(_ task: Task<Void, Never>) {
        latestDashboardOwnerOperationSequence &+= 1
        dashboardOwnerOperationTail = task
    }

    func awaitLifecycleTransitionsForTesting() async {
        var observedSequence = latestLifecycleTransitionSequence
        while true {
            await lifecycleTransitionTail?.value
            let latestSequence = latestLifecycleTransitionSequence
            if latestSequence == observedSequence { return }
            observedSequence = latestSequence
        }
    }

    func installServiceCallerForTesting(_ caller: @escaping DashboardServiceController.Caller) {
        serviceController.install(caller: caller)
    }

    private func parseDate(_ value: String) -> Date? {
        fractionalISOFormatter.date(from: value) ?? isoFormatter.date(from: value)
    }

    func synchronizeHistorySubscriptionsForTesting() async {
        let startingSequence = latestDashboardOwnerOperationSequence
        enqueueCurrentDashboardOwnerCandidate(
            startHistoryOwners: webSocketClient != nil,
            runsCandidateHook: false
        )
        await awaitStableDashboardOwnerOperationTail(startingAt: startingSequence)
    }

    func applyLovelaceConfigForTesting(_ config: LovelaceConfig) async {
        await applyLovelaceConfig(config, startHistoryOwners: webSocketClient != nil)
    }

    private func applyLovelaceConfig(
        _ config: LovelaceConfig,
        startHistoryOwners: Bool,
        bootstrapSequence: UInt64? = nil
    ) async {
        let weakModel = WeakDashboardViewModelBox(self)
        await Self.applyLovelaceConfig(
            config,
            startHistoryOwners: startHistoryOwners,
            bootstrapSequence: bootstrapSequence,
            model: weakModel
        )
    }

    private static func applyLovelaceConfig(
        _ config: LovelaceConfig,
        startHistoryOwners: Bool,
        bootstrapSequence: UInt64?,
        model weakModel: WeakDashboardViewModelBox
    ) async {
        var tail = weakModel.value?.enqueueLovelaceConfig(
            config,
            startHistoryOwners: startHistoryOwners,
            bootstrapSequence: bootstrapSequence
        )
        var observedSequence = weakModel.value?.latestDashboardOwnerOperationSequence ?? 0
        while true {
            await tail?.value
            guard let latestSequence = weakModel.value?.latestDashboardOwnerOperationSequence else {
                return
            }
            if latestSequence == observedSequence { return }
            observedSequence = latestSequence
            tail = weakModel.value?.dashboardOwnerOperationTail
        }
    }

    private func enqueueLovelaceConfig(
        _ config: LovelaceConfig,
        startHistoryOwners: Bool,
        bootstrapSequence: UInt64?
    ) -> Task<Void, Never>? {
        guard bootstrapSequence.map({ latestBootstrapSequence == $0 }) ?? true else { return nil }
        if latestQueuedConfigRawValue == config.rawValue,
           dashboardOwnerOperationTail != nil,
           latestQueuedDashboardCandidate?.bootstrapSequence == bootstrapSequence
        {
            return dashboardOwnerOperationTail
        }
        if bootstrapSequence == nil,
           hasLoadedDashboard,
           latestQueuedConfigRawValue == nil,
           presentationDashboard.resolved.source.rawValue == config.rawValue
        {
            return dashboardOwnerOperationTail
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
        _ = enqueueDashboardOwnerCandidate(
            dashboard: dashboard,
            selectedView: selected,
            startHistoryOwners: startHistoryOwners,
            configRequestSequence: requestSequence,
            bootstrapSequence: bootstrapSequence
        )
        return dashboardOwnerOperationTail
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

    @discardableResult
    private func enqueueDashboardOwnerCandidate(
        dashboard: LovelacePresentationDashboard,
        selectedView: LovelaceResolvedView?,
        startHistoryOwners: Bool,
        configRequestSequence: UInt64,
        bootstrapSequence: UInt64? = nil,
        runsCandidateHook: Bool = true
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
        let weakModel = WeakDashboardViewModelBox(self)
        let candidateHook = dashboardOwnerCandidateHook
        let operationRegistry = dashboardOwnerOperationRegistry
        let task = Task { @MainActor [weakModel, candidateHook, operationRegistry] in
            defer { operationRegistry.finish(sequence: operationSequence) }
            await previousTail?.value
            guard !Task.isCancelled else { return }
            if runsCandidateHook {
                await candidateHook()
            }
            await Self.finishDetachedOwnership(detached)
            guard weakModel.value?.isCurrent(candidate) == true else {
                if weakModel.value?.latestQueuedDashboardCandidate?.navigationRequestSequence ==
                    candidate.navigationRequestSequence
                {
                    weakModel.value?.latestQueuedDashboardCandidate = nil
                }
                return
            }
            let shouldStartHistories = weakModel.value?.installDashboardOwnerCandidateSynchronously(candidate) == true
            if shouldStartHistories {
                await Self.startCandidateHistories(candidate, model: weakModel)
            }
            if weakModel.value?.latestQueuedDashboardCandidate?.navigationRequestSequence ==
                candidate.navigationRequestSequence
            {
                weakModel.value?.latestQueuedDashboardCandidate = nil
            }
        }
        operationRegistry.register(
            DashboardOwnerOperationNode(task: task, detachedOwnership: detached),
            sequence: operationSequence
        )
        dashboardOwnerOperationTail = task
        return operationSequence
    }

    private func enqueueCurrentDashboardOwnerCandidate(
        startHistoryOwners: Bool,
        runsCandidateHook: Bool = true
    ) {
        let dashboard = latestQueuedDashboardCandidate?.dashboard ?? presentationDashboard
        let navigation = self.navigation(for: dashboard)
        let selected = navigation.view(identity: desiredSelectedViewIdentity)
            ?? navigation.startupSelection(persisted: lastPrimaryLocator)
        _ = enqueueDashboardOwnerCandidate(
            dashboard: dashboard,
            selectedView: selected,
            startHistoryOwners: startHistoryOwners,
            configRequestSequence: latestConfigRequestSequence,
            runsCandidateHook: runsCandidateHook
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

    private static func finishDetachedOwnership(_ detached: DetachedDashboardOwnership) async {
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
        lifetimeAuthority.acceptsWork &&
            latestConfigRequestSequence == candidate.configRequestSequence &&
            (candidate.bootstrapSequence.map { latestBootstrapSequence == $0 } ?? true) &&
            latestNavigationRequestSequence == candidate.navigationRequestSequence &&
            desiredSelectedViewIdentity == candidate.selectedViewIdentity &&
            selectedGraphHours == candidate.graphHours &&
            desiredHistoryKeys == Set(candidate.desiredRequests.map(\.key))
    }

    private func installDashboardOwnerCandidateSynchronously(
        _ candidate: DashboardOwnerCandidate
    ) -> Bool {
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
        lovelaceStore.install(candidate.dashboard)
        lifecycle.set(.lovelace, phase: .ready)
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

        return candidate.startHistoryOwners && isCurrent(candidate)
    }

    private static func startCandidateHistories(
        _ candidate: DashboardOwnerCandidate,
        model weakModel: WeakDashboardViewModelBox
    ) async {
        for request in candidate.desiredRequests {
            guard !Task.isCancelled,
                  weakModel.value?.isCurrent(candidate) == true
            else { break }
            guard let startup = weakModel.value?.beginHistoryStartup(
                request,
                reconciliationEpoch: weakModel.value?.historyReconciliationEpoch ?? 0,
                configRequestSequence: candidate.configRequestSequence
            ) else { continue }
            await startup.value
        }

        guard weakModel.value?.isCurrent(candidate) != true,
              let detached = weakModel.value?.detachOwnershipSynchronously(
                notIn: weakModel.value?.latestQueuedHistoryKeys ?? []
              )
        else { return }
        detached.startups.forEach { $0.cancel() }
        await finishDetachedOwnership(detached)
    }

    private func beginHistoryStartup(
        _ request: HistoryRequest,
        webSocketClient explicitClient: HomeAssistantWebSocketClient? = nil,
        reconciliationEpoch: UInt64,
        configRequestSequence: UInt64?
    ) -> Task<Void, Never>? {
        let key = request.key
        guard lifetimeAuthority.acceptsWork,
              historyReconciliationEpoch == reconciliationEpoch,
              desiredHistoryKeys.contains(key),
              historySubscriptions[key] == nil,
              historyGenerations[key] == nil,
              let client = explicitClient ?? webSocketClient
        else { return nil }

        let generation = UUID()
        let startupID = UUID()
        let stateSnapshot = states
        let graphRevisionFeed = GraphHistoryRevisionFeed()
        let processingHook = historyProcessingHook
        let now = historyNow
        let authority = lifetimeAuthority
        let weakModel = WeakDashboardViewModelBox(self)
        historyGenerations[key] = generation
        graphHistoryRevisionFeeds[key] = graphRevisionFeed
        historyStatuses[key] = .loading

        let task = Task { @MainActor [weakModel] in
            await Self.runHistoryStartup(
                request,
                client: client,
                reconciliationEpoch: reconciliationEpoch,
                configRequestSequence: configRequestSequence,
                generation: generation,
                stateSnapshot: stateSnapshot,
                graphRevisionFeed: graphRevisionFeed,
                processingHook: processingHook,
                now: now,
                lifetimeAuthority: authority,
                model: weakModel
            )
            weakModel.value?.historyStartupTasks.removeValue(forKey: startupID)
        }
        historyStartupTasks[startupID] = HistoryStartupTask(key: key, task: task)
        return task
    }

    private static func runHistoryStartup(
        _ request: HistoryRequest,
        client: HomeAssistantWebSocketClient,
        reconciliationEpoch: UInt64,
        configRequestSequence: UInt64?,
        generation: UUID,
        stateSnapshot: [String: HAState],
        graphRevisionFeed: GraphHistoryRevisionFeed,
        processingHook: @escaping @Sendable () async -> Void,
        now: @escaping @Sendable () -> Date,
        lifetimeAuthority: DashboardLifetimeAuthority,
        model weakModel: WeakDashboardViewModelBox
    ) async {
        let key = request.key
        let projectionStore = HAHistoryProjectionStore(
            orderedEntityIDs: request.entityIDs,
            currentStates: stateSnapshot
        )
        do {
            guard lifetimeAuthority.acceptsWork, !Task.isCancelled else { return }
            let subscription = try await client.subscribeHistoryStatesTimeWindow(
                entityIDs: request.entityIDs,
                hoursToShow: request.hoursToShow,
                currentStates: stateSnapshot,
                now: now,
                onStatus: { status in
                    await MainActor.run {
                        guard lifetimeAuthority.acceptsWork,
                              weakModel.value?.historyGenerations[key] == generation,
                              weakModel.value?.desiredHistoryKeys.contains(key) == true,
                              weakModel.value?.historyStatuses[key] != status
                        else { return }
                        weakModel.value?.historyStatuses[key] = status
                    }
                },
                onPublication: { publication in
                    if case .unchanged = publication.transition { return }
                    let resetPreparedState: Bool
                    switch publication.transition {
                    case .reset, .outOfOrderReset: resetPreparedState = true
                    case .normal, .unchanged: resetPreparedState = false
                    }
                    await processingHook()
                    guard lifetimeAuthority.acceptsWork,
                          !Task.isCancelled,
                          let projected = await projectionStore.series(from: publication),
                          !Task.isCancelled
                    else { return }
                    await MainActor.run {
                        guard lifetimeAuthority.acceptsWork,
                              !Task.isCancelled,
                              weakModel.value?.historyGenerations[key] == generation,
                              weakModel.value?.desiredHistoryKeys.contains(key) == true
                        else { return }
                        graphRevisionFeed.publish(projected, resetPreparedState: resetPreparedState)
                        weakModel.value?.histories[key] = projected
                    }
                }
            )
            guard lifetimeAuthority.acceptsWork,
                  weakModel.value?.acceptHistoryStartup(
                key: key,
                generation: generation,
                reconciliationEpoch: reconciliationEpoch,
                configRequestSequence: configRequestSequence,
                subscription: subscription
            ) == true else {
                await subscription.cancel()
                return
            }
        } catch {
            weakModel.value?.failHistoryStartup(key: key, generation: generation, error: error)
        }
    }

    private func acceptHistoryStartup(
        key: String,
        generation: UUID,
        reconciliationEpoch _: UInt64,
        configRequestSequence: UInt64?,
        subscription: HAHistoryStreamSubscription
    ) -> Bool {
        guard lifetimeAuthority.acceptsWork,
              !Task.isCancelled,
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
            return false
        }
        historySubscriptions[key] = subscription
        return true
    }

    private func failHistoryStartup(key: String, generation: UUID, error: Error) {
        guard lifetimeAuthority.acceptsWork,
              desiredHistoryKeys.contains(key),
              historyGenerations[key] == generation
        else { return }
        historyGenerations.removeValue(forKey: key)
        graphHistoryRevisionFeeds.removeValue(forKey: key)
        historyStatuses[key] = .error(error.localizedDescription)
    }

    private static func runDetailHistoryStartup(
        entityID: String,
        hours: Int,
        key: String,
        generation: UUID,
        client: HomeAssistantWebSocketClient,
        stateSnapshot: [String: HAState],
        processingHook: @escaping @Sendable () async -> Void,
        now: @escaping @Sendable () -> Date,
        lifetimeAuthority: DashboardLifetimeAuthority,
        model weakModel: WeakDashboardViewModelBox
    ) async {
        let projectionStore = HAHistoryProjectionStore(
            orderedEntityIDs: [entityID],
            currentStates: stateSnapshot
        )
        do {
            guard lifetimeAuthority.acceptsWork, !Task.isCancelled else { return }
            let subscription = try await client.subscribeHistoryStatesTimeWindow(
                entityIDs: [entityID],
                hoursToShow: hours,
                currentStates: stateSnapshot,
                now: now,
                onStatus: { status in
                    await MainActor.run {
                        guard lifetimeAuthority.acceptsWork,
                              weakModel.value?.detailHistoryGenerations[key] == generation,
                              weakModel.value?.detailHistoryStatuses[key] != status
                        else { return }
                        weakModel.value?.detailHistoryStatuses[key] = status
                    }
                },
                onPublication: { publication in
                    if case .unchanged = publication.transition { return }
                    await processingHook()
                    guard lifetimeAuthority.acceptsWork,
                          !Task.isCancelled,
                          let projection = await projectionStore.series(from: publication)?.first,
                          !Task.isCancelled
                    else { return }
                    await MainActor.run {
                        guard lifetimeAuthority.acceptsWork,
                              !Task.isCancelled,
                              weakModel.value?.detailHistoryGenerations[key] == generation
                        else { return }
                        weakModel.value?.detailHistories[key] = projection
                    }
                }
            )
            guard lifetimeAuthority.acceptsWork,
                  weakModel.value?.acceptDetailHistoryStartup(
                key: key,
                generation: generation,
                subscription: subscription
            ) == true else {
                await subscription.cancel()
                return
            }
        } catch {
            weakModel.value?.failDetailHistoryStartup(key: key, generation: generation, error: error)
        }
    }

    private func acceptDetailHistoryStartup(
        key: String,
        generation: UUID,
        subscription: HAHistoryStreamSubscription
    ) -> Bool {
        guard lifetimeAuthority.acceptsWork,
              !Task.isCancelled,
              desiredDetailHistoryKeys.contains(key),
              detailHistoryGenerations[key] == generation
        else { return false }
        detailHistorySubscriptions[key] = subscription
        return true
    }

    private func failDetailHistoryStartup(key: String, generation: UUID, error: Error) {
        guard lifetimeAuthority.acceptsWork,
              detailHistoryGenerations[key] == generation
        else { return }
        detailHistoryGenerations.removeValue(forKey: key)
        detailHistoryStatuses[key] = .error(error.localizedDescription)
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


    private static func firstWorkingConnection(token: String) async throws -> Connection {
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

    private static func entityRegistryPresentationMetadata(
        _ registry: HAEntityRegistryDisplayResponse?
    ) -> (precisions: [String: Int], icons: [String: String]) {
        let entries = registry?.entities ?? []
        return (
            Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
                entry.displayPrecision.map { (entry.entityID, $0) }
            }),
            Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
                entry.icon.map { (entry.entityID, $0) }
            })
        )
    }

    private func performPowerCall(
        entityID: String,
        isOn: Bool,
        route: EntityPowerRoute? = nil
    ) {
        guard let route = route ?? EntityRowPresentationResolver.rowPowerRoute(
            entityID: entityID,
            isOn: isOn
        ) else { return }
        guard canInvokePower(entityID: entityID, requestedRoute: route) else { return }
        applyOptimisticState(entityID: entityID, state: isOn ? "on" : "off")
        callService(
            domain: route.domain,
            service: route.service,
            data: ["entity_id": .string(entityID)],
            errorContext: "Service call failed for \(entityID)"
        )
    }

    private func canInvokePower(
        entityID: String,
        requestedRoute: EntityPowerRoute
    ) -> Bool {
        let routes = EntityRowPresentationResolver.equivalentPowerRoutes(entityID: entityID)
        guard routes.contains(requestedRoute) else { return false }
        return routes.allSatisfy { route in
            serviceController.canInvoke(
                entityID: entityID,
                state: states[entityID],
                domain: route.domain,
                service: route.service
            )
        }
    }

    private func callService(
        domain: String,
        service: String,
        data: [String: JSONValue],
        errorContext: String
    ) {
        guard case let .string(entityID)? = data["entity_id"] else { return }
        lifecycle.set(.service, phase: .loading)
        let invoked = serviceController.invoke(
            entityID: entityID,
            domain: domain,
            service: service,
            data: data,
            errorContext: errorContext
        ) { [weak self] failure in
            self?.lifecycle.set(
                .service,
                phase: failure.map(DashboardComponentPhase.failed) ?? .ready
            )
        }
        if !invoked, serviceController.errorMessage == nil {
            lifecycle.set(.service, phase: .idle)
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
            context: old.context,
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
        guard let cleanup = emergencyDetachAction?() else { return }
        Task { @MainActor in
            cleanup.mountRegistry.invalidateOwners(notIn: [])
            cleanup.historyCoordinator.reconciliationEpoch &+= 1
            cleanup.historyCoordinator.desiredKeys.removeAll()
            cleanup.historyCoordinator.desiredDetailKeys.removeAll()
            cleanup.historyCoordinator.generations.removeAll()
            cleanup.historyCoordinator.detailGenerations.removeAll()
            cleanup.historyCoordinator.startupTasks.removeAll()
            cleanup.historyCoordinator.detailStartupTasks.removeAll()
            cleanup.historyCoordinator.subscriptions.removeAll()
            cleanup.historyCoordinator.detailSubscriptions.removeAll()
            cleanup.historyCoordinator.graphRevisionFeeds.removeAll()
            cleanup.historyCoordinator.statuses.removeAll()
            cleanup.historyCoordinator.detailStatuses.removeAll()
            cleanup.historyCoordinator.histories.removeAll()
            cleanup.historyCoordinator.detailHistories.removeAll()
            let serviceTasks = cleanup.serviceController.stopSynchronously()

            var entityOwnerships: [HAEntitySubscriptionDetachedOwnership] = []
            if let entity = cleanup.ownership.entityCoordinator {
                entityOwnerships.append(entity.detachOwnershipSynchronously())
            }
            if let candidate = cleanup.ownership.candidateEntityCoordinator,
               candidate !== cleanup.ownership.entityCoordinator
            {
                entityOwnerships.append(candidate.detachOwnershipSynchronously())
            }
            for ownership in entityOwnerships { await ownership.finish() }
            await cleanup.ownership.lovelaceSubscription?.cancel()
            for subscription in cleanup.ownership.historySubscriptions {
                await subscription.cancel()
            }
            for subscription in cleanup.ownership.detailHistorySubscriptions {
                await subscription.cancel()
            }
            for client in cleanup.ownership.clients { await client.disconnect() }
            for task in cleanup.ownership.tasks { await task.value }
            for task in serviceTasks { await task.value }
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

private final class WeakInstalledEntityCoordinatorBox: @unchecked Sendable {
    weak var value: HAEntitySubscriptionCoordinator?
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
    let desiredDetailHistoryKeys: Set<String>
    let detailSubscriptionKeys: Set<String>
    let detailGenerationKeys: Set<String>
    let detailStartupCount: Int
    let detailHistoryKeys: Set<String>
    let detailStatusKeys: Set<String>
    let entityOwnerActive: Bool
    let candidateEntityOwnerActive: Bool
    let lovelaceSubscriptionActive: Bool
    let bootstrapTaskActive: Bool
    let connectionStatusTaskActive: Bool
    let lovelaceFetchTaskActive: Bool
    let reconnectTaskActive: Bool
    let dashboardOwnerTailActive: Bool
    let dashboardOwnerNodeCount: Int
    let serviceTaskCount: Int
    let webSocketClientActive: Bool
    let installedClientActive: Bool
}

private struct DetachedDashboardOwnership {
    let startups: [Task<Void, Never>]
    let subscriptions: [HAHistoryStreamSubscription]
    let detailStartups: [Task<Void, Never>]
    let detailSubscriptions: [HAHistoryStreamSubscription]
}

private struct DashboardOwnerOperationNode {
    let task: Task<Void, Never>
    var detachedOwnership: DetachedDashboardOwnership?
}

/// Every node in the one dashboard-owner chain remains visible here until its
/// task and task-local retirement finish. Stop and nonisolated deinit can thus
/// cancel hidden predecessors without changing ordinary reconciliation order.
private final class DashboardOwnerOperationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nodes: [UInt64: DashboardOwnerOperationNode] = [:]
    private var isPermanentlyRevoked = false

    func register(_ node: DashboardOwnerOperationNode, sequence: UInt64) {
        lock.lock()
        let reject = isPermanentlyRevoked
        if !reject { nodes[sequence] = node }
        lock.unlock()
        if reject { cancel(node) }
    }

    func setDetachedOwnership(
        _ ownership: DetachedDashboardOwnership,
        sequence: UInt64
    ) {
        lock.lock()
        let reject = isPermanentlyRevoked || nodes[sequence] == nil
        if !reject { nodes[sequence]?.detachedOwnership = ownership }
        lock.unlock()
        if reject { cancel(ownership) }
    }

    func finish(sequence: UInt64) {
        lock.lock()
        nodes.removeValue(forKey: sequence)
        lock.unlock()
    }

    func detachSynchronously(revokingPermanently: Bool = false) -> [DashboardOwnerOperationNode] {
        lock.lock()
        if revokingPermanently { isPermanentlyRevoked = true }
        let detached = Array(nodes.values)
        nodes.removeAll()
        lock.unlock()
        detached.forEach(cancel)
        return detached
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return nodes.count
    }

    private func cancel(_ node: DashboardOwnerOperationNode) {
        node.task.cancel()
        if let ownership = node.detachedOwnership { cancel(ownership) }
    }

    private func cancel(_ ownership: DetachedDashboardOwnership) {
        ownership.startups.forEach { $0.cancel() }
        ownership.detailStartups.forEach { $0.cancel() }
        Task {
            for subscription in ownership.subscriptions { await subscription.cancel() }
            for subscription in ownership.detailSubscriptions { await subscription.cancel() }
        }
    }
}

private struct FailedHistoryRetryOwnership {
    let cardStartups: [Task<Void, Never>]
    let cardSubscriptions: [HAHistoryStreamSubscription]
    let detailStartups: [Task<Void, Never>]
    let detailSubscription: HAHistoryStreamSubscription?
    let detailRetry: FailedDetailHistoryRetry?
}

private struct FailedDetailHistoryRetry {
    let entityID: String
    let key: String
    let hours: Int
}

private struct HistoryRefreshOwnership {
    let startups: [Task<Void, Never>]
    let refreshes: [HistoryRefreshOwner]
}

private struct HistoryRefreshOwner {
    let key: String
    let generation: UUID
    let reconciliationEpoch: UInt64
    let subscription: HAHistoryStreamSubscription
}

private struct DetachedDashboardAppOwnership {
    let bootstrapTask: Task<Void, Never>?
    let statusTask: Task<Void, Never>?
    let configTask: Task<Void, Never>?
    let reconnectTask: Task<Void, Never>?
    let ownerTail: Task<Void, Never>?
    let ownerOperations: [DashboardOwnerOperationNode]
    let serviceTasks: [Task<Void, Never>]
    let entityOwnerships: [HAEntitySubscriptionDetachedOwnership]
    let lovelaceSubscription: HAWebSocketSubscription?
    let historyOwnership: DetachedDashboardOwnership
    let clients: [HomeAssistantWebSocketClient]
}

private struct DashboardEmergencyDeinitCleanup {
    let ownership: DashboardEmergencyBagOwnership
    let historyCoordinator: DashboardHistoryCoordinator
    let serviceController: DashboardServiceController
    let mountRegistry: DashboardGraphChartMountRegistry
}

private enum DashboardEmergencyTaskKey: Hashable {
    case bootstrap
    case connectionStatus
    case lovelaceFetch
    case lifecycleTail
    case startTransition
    case retryTransition
    case reconnect
    case dashboardOwnerTail
}

private struct DashboardEmergencyBagOwnership {
    let tasks: [Task<Void, Never>]
    let entityCoordinator: HAEntitySubscriptionCoordinator?
    let candidateEntityCoordinator: HAEntitySubscriptionCoordinator?
    let lovelaceSubscription: HAWebSocketSubscription?
    let historySubscriptions: [HAHistoryStreamSubscription]
    let detailHistorySubscriptions: [HAHistoryStreamSubscription]
    let clients: [HomeAssistantWebSocketClient]
}

/// Thread-safe, non-self-retaining emergency inventory. The model writes this
/// mirror only from MainActor, while nonisolated `deinit` may atomically revoke
/// acceptance and cancel Task handles from any executor. MainActor-only owner
/// registries and graph lifecycles are cleared by the follow-up cleanup task,
/// which captures this detached inventory and fixed collaborators, never the
/// deinitializing model.
private final class DashboardEmergencyOwnershipBag: @unchecked Sendable {
    private let lock = NSLock()
    private let lifetimeAuthority: DashboardLifetimeAuthority
    private let dashboardOwnerOperationRegistry: DashboardOwnerOperationRegistry
    private var isDetached = false
    private var tasks: [DashboardEmergencyTaskKey: Task<Void, Never>] = [:]
    private var serviceTasks: [Task<Void, Never>] = []
    private var entityCoordinatorTasks: [UUID: [Task<Void, Never>]] = [:]
    private var historyStartupTasks: [Task<Void, Never>] = []
    private var detailHistoryStartupTasks: [Task<Void, Never>] = []
    private var entityCoordinator: HAEntitySubscriptionCoordinator?
    private var candidateEntityCoordinator: HAEntitySubscriptionCoordinator?
    private var lovelaceSubscription: HAWebSocketSubscription?
    private var historySubscriptions: [HAHistoryStreamSubscription] = []
    private var detailHistorySubscriptions: [HAHistoryStreamSubscription] = []
    private var webSocketClient: HomeAssistantWebSocketClient?
    private var latestBootstrapClient: HomeAssistantWebSocketClient?
    private var installedBootstrapClient: HomeAssistantWebSocketClient?

    init(
        lifetimeAuthority: DashboardLifetimeAuthority,
        dashboardOwnerOperationRegistry: DashboardOwnerOperationRegistry
    ) {
        self.lifetimeAuthority = lifetimeAuthority
        self.dashboardOwnerOperationRegistry = dashboardOwnerOperationRegistry
    }

    func setTask(_ task: Task<Void, Never>?, for key: DashboardEmergencyTaskKey) {
        lock.lock()
        guard !isDetached else {
            lock.unlock()
            task?.cancel()
            return
        }
        tasks[key] = task
        lock.unlock()
    }

    func setServiceTasks(_ value: [Task<Void, Never>]) {
        lock.lock()
        guard !isDetached else {
            lock.unlock()
            value.forEach { $0.cancel() }
            return
        }
        serviceTasks = value
        lock.unlock()
    }

    func setEntityCoordinatorTasks(
        _ value: [Task<Void, Never>],
        ownerID: UUID
    ) {
        lock.lock()
        guard !isDetached else {
            lock.unlock()
            value.forEach { $0.cancel() }
            return
        }
        if value.isEmpty {
            entityCoordinatorTasks.removeValue(forKey: ownerID)
        } else {
            entityCoordinatorTasks[ownerID] = value
        }
        lock.unlock()
    }

    func setHistoryStartupTasks(_ value: [Task<Void, Never>]) {
        lock.lock()
        guard !isDetached else {
            lock.unlock()
            value.forEach { $0.cancel() }
            return
        }
        historyStartupTasks = value
        lock.unlock()
    }

    func setDetailHistoryStartupTasks(_ value: [Task<Void, Never>]) {
        lock.lock()
        guard !isDetached else {
            lock.unlock()
            value.forEach { $0.cancel() }
            return
        }
        detailHistoryStartupTasks = value
        lock.unlock()
    }

    func setEntityCoordinator(_ value: HAEntitySubscriptionCoordinator?) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { entityCoordinator = value }
    }

    func setCandidateEntityCoordinator(_ value: HAEntitySubscriptionCoordinator?) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { candidateEntityCoordinator = value }
    }

    func setLovelaceSubscription(_ value: HAWebSocketSubscription?) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { lovelaceSubscription = value }
    }

    func setHistorySubscriptions(_ value: [HAHistoryStreamSubscription]) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { historySubscriptions = value }
    }

    func setDetailHistorySubscriptions(_ value: [HAHistoryStreamSubscription]) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { detailHistorySubscriptions = value }
    }

    func setWebSocketClient(_ value: HomeAssistantWebSocketClient?) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { webSocketClient = value }
    }

    func setLatestBootstrapClient(_ value: HomeAssistantWebSocketClient?) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { latestBootstrapClient = value }
    }

    func setInstalledBootstrapClient(_ value: HomeAssistantWebSocketClient?) {
        lock.lock(); defer { lock.unlock() }
        if !isDetached { installedBootstrapClient = value }
    }

    func detachSynchronously() -> DashboardEmergencyBagOwnership {
        // This is intentionally the first deinit operation: all background
        // callbacks consult the same lock-protected authority, so they become
        // inert even when MainActor cleanup is deliberately delayed.
        lifetimeAuthority.revoke()
        let ownerOperations = dashboardOwnerOperationRegistry.detachSynchronously(
            revokingPermanently: true
        )
        lock.lock()
        isDetached = true
        var detachedTasks = Array(tasks.values)
        detachedTasks.append(contentsOf: serviceTasks)
        detachedTasks.append(contentsOf: entityCoordinatorTasks.values.flatMap { $0 })
        detachedTasks.append(contentsOf: ownerOperations.map(\.task))
        detachedTasks.append(contentsOf: historyStartupTasks)
        detachedTasks.append(contentsOf: detailHistoryStartupTasks)
        for operation in ownerOperations {
            detachedTasks.append(contentsOf: operation.detachedOwnership?.startups ?? [])
            detachedTasks.append(contentsOf: operation.detachedOwnership?.detailStartups ?? [])
        }
        let detachedEntity = entityCoordinator
        let detachedCandidate = candidateEntityCoordinator
        let detachedLovelace = lovelaceSubscription
        var detachedHistory = historySubscriptions
        var detachedDetail = detailHistorySubscriptions
        for operation in ownerOperations {
            detachedHistory.append(contentsOf: operation.detachedOwnership?.subscriptions ?? [])
            detachedDetail.append(contentsOf: operation.detachedOwnership?.detailSubscriptions ?? [])
        }
        var clients: [HomeAssistantWebSocketClient] = []
        for client in [webSocketClient, latestBootstrapClient, installedBootstrapClient].compactMap({ $0 })
            where !clients.contains(where: { $0 === client })
        {
            clients.append(client)
        }
        tasks.removeAll()
        serviceTasks.removeAll()
        entityCoordinatorTasks.removeAll()
        historyStartupTasks.removeAll()
        detailHistoryStartupTasks.removeAll()
        entityCoordinator = nil
        candidateEntityCoordinator = nil
        lovelaceSubscription = nil
        historySubscriptions.removeAll()
        detailHistorySubscriptions.removeAll()
        webSocketClient = nil
        latestBootstrapClient = nil
        installedBootstrapClient = nil
        lock.unlock()

        detachedTasks.forEach { $0.cancel() }
        return DashboardEmergencyBagOwnership(
            tasks: detachedTasks,
            entityCoordinator: detachedEntity,
            candidateEntityCoordinator: detachedCandidate,
            lovelaceSubscription: detachedLovelace,
            historySubscriptions: detachedHistory,
            detailHistorySubscriptions: detachedDetail,
            clients: clients
        )
    }
}

private struct OwnedBootstrapStart {
    let sequence: UInt64
    let obsoleteCandidate: HAEntitySubscriptionCoordinator?
}

private struct OwnedBootstrapRetirement {
    let entity: HAEntitySubscriptionCoordinator?
    let lovelace: HAWebSocketSubscription?
    let statusTask: Task<Void, Never>?
    let client: HomeAssistantWebSocketClient?
}

private struct OwnedBootstrapFailure {
    let serviceTasks: [Task<Void, Never>]
    let entity: HAEntitySubscriptionCoordinator?
    let candidate: HAEntitySubscriptionCoordinator?
    let lovelace: HAWebSocketSubscription?
    let statusTask: Task<Void, Never>?
    let installedClient: HomeAssistantWebSocketClient?
}

private enum DashboardAppLifecycleTransition: Equatable {
    case start
    case stop
    case retry
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
