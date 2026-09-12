import Foundation
import NativeHACore

struct MarkdownOwnerKey: Hashable {
    let view: LovelaceResolvedIdentity
    let card: LovelaceResolvedIdentity
}

enum MarkdownTemplatePhase: Equatable {
    case pending, subscribed, disconnected, rejected, metadataUnavailable, hidden
}

@MainActor
final class MarkdownCardState: ObservableObject {
    @Published var document = MarkdownDocument.blank
    @Published var phase = MarkdownTemplatePhase.pending
    @Published var alert: String?
    @Published var alertLevel: HATemplateErrorLevel?
    @Published var hidden = false
    private(set) var result: HATemplateResult?
    let card: LovelacePresentationCard
    init(card: LovelacePresentationCard) { self.card = card }
    func store(_ result: HATemplateResult) { self.result = result }
}

struct MarkdownDetachedOwnership {
    var tasks: [Task<Void, Never>] = []
    var subscriptions: [HAWebSocketSubscription] = []
    func cancelTasks() { tasks.forEach { $0.cancel() } }
    func finish() async {
        cancelTasks()
        // Cancel wire handles before joining parse/startup work.
        for subscription in subscriptions { await subscription.cancel() }
        for task in tasks { await task.value }
    }
}

@MainActor
final class DashboardMarkdownCoordinator {
    @MainActor private final class Entry {
        let state: MarkdownCardState
        var attempt = UUID()
        var startup: Task<Void, Never>?
        var subscription: HAWebSocketSubscription?
        var preparation: Task<Void, Never>?
        var revision = UUID()
        var active = false
        var reconnectPending = false
        var connectsCachedEmpty = false
        init(card: LovelacePresentationCard) { state = MarkdownCardState(card: card) }
    }
    private struct CachedResult {
        let result: HATemplateResult
        let deadline: Date
    }
    private var entries: [MarkdownOwnerKey: Entry] = [:]
    private var cacheIncarnation = UUID()
    private var cache: [String: CachedResult] = [:]
    private let now: () -> Date
    private let authority: DashboardLifetimeAuthority
    private var installedConfig: JSONValue?
    private var selectedView: LovelaceResolvedIdentity?
    private var client: HomeAssistantWebSocketClient?
    private var userName: String?
    private var readyTask: Task<Void, Never>?
    var retire: ((MarkdownDetachedOwnership) -> Void)?
    var visibilityChanged: (() -> Void)?
    var ownershipChanged: ((MarkdownDetachedOwnership) -> Void)?

    init(authority: DashboardLifetimeAuthority, now: @escaping () -> Date = Date.init) {
        self.authority = authority; self.now = now
    }

    func state(for card: LovelacePresentationCard, view: LovelaceResolvedIdentity?) -> MarkdownCardState? {
        guard let view = view else { return nil }
        return entries[MarkdownOwnerKey(view: view, card: card.identity)]?.state
    }

    /// Called before dashboard publication. Equal views retain cached wrapper
    /// state; changed view raw configuration creates new concrete cards.
    func reconcile(dashboard: LovelacePresentationDashboard, selected: LovelaceResolvedIdentity?) -> MarkdownDetachedOwnership {
        var detached = MarkdownDetachedOwnership()
        if let installedConfig = installedConfig, installedConfig != dashboard.resolved.source.rawValue {
            for entry in entries.values { append(detach(entry), to: &detached) }
            entries.removeAll()
        }
        installedConfig = dashboard.resolved.source.rawValue
        let survivingViews = Set(dashboard.views.map(\.id))
        for (key, entry) in entries where !survivingViews.contains(key.view) || key.view != selected {
            if entry.active || entry.startup != nil || entry.subscription != nil || entry.preparation != nil { append(detach(entry), to: &detached) }
            if !survivingViews.contains(key.view) { entries.removeValue(forKey: key) }
        }
        selectedView = selected
        guard let view = dashboard.views.first(where: { $0.id == selected }) else {
            inventory(); return detached
        }
        let cards = Self.renderedMarkdownCards(view)
        for card in cards {
            let key = MarkdownOwnerKey(view: view.id, card: card.identity)
            if entries[key] == nil {
                let entry = Entry(card: card)
                entries[key] = entry
                if let cached = cachedResult(for: card.source) {
                    entry.state.store(cached)
                    if card.source.showEmpty == false && cached.result.isEmpty {
                        entry.state.hidden = true; entry.state.phase = .hidden; entry.connectsCachedEmpty = true
                    }
                    prepare(cached.result, key: key, entry: entry)
                }
            }
        }
        inventory()
        return detached
    }

    func activate(using client: HomeAssistantWebSocketClient, userName: String?) {
        self.client = client; self.userName = userName
        for (key, entry) in entries where key.view == selectedView && (!entry.state.hidden || entry.connectsCachedEmpty) {
            guard !entry.active else { continue }
            entry.active = true
            if let result = entry.state.result, entry.state.document.source != result.result {
                prepare(result.result, key: key, entry: entry)
            }
            guard let userName = userName else {
                entry.state.phase = .metadataUnavailable
                continue
            }
            start(key: key, entry: entry, client: client, userName: userName)
        }
        inventory()
    }

    func connectionReady() {
        readyTask?.cancel()
        let startups = entries.values.compactMap(\.startup)
        readyTask = Task { @MainActor [weak self] in
            for startup in startups { await startup.value }
            guard !Task.isCancelled, let self = self, let client = self.client, let userName = self.userName else { return }
            for (key, entry) in self.entries where entry.active && entry.reconnectPending && entry.startup == nil && entry.subscription == nil {
                entry.reconnectPending = false
                self.start(key: key, entry: entry, client: client, userName: userName)
            }
            self.readyTask = nil
            self.inventory()
        }
        inventory()
    }

    func close() -> MarkdownDetachedOwnership {
        var ownership = MarkdownDetachedOwnership(tasks: [readyTask].compactMap { $0 })
        readyTask?.cancel(); readyTask = nil
        for entry in entries.values { append(detach(entry), to: &ownership) }
        entries.removeAll(); cache.removeAll(); cacheIncarnation = UUID(); installedConfig = nil; selectedView = nil; client = nil; userName = nil
        inventory()
        return ownership
    }

    private func start(key: MarkdownOwnerKey, entry: Entry, client: HomeAssistantWebSocketClient, userName: String) {
        guard authority.acceptsWork, entry.startup == nil, entry.subscription == nil else { return }
        let attempt = UUID(); entry.attempt = attempt
        entry.state.alert = nil; entry.state.alertLevel = nil
        entry.state.phase = .pending
        let card = entry.state.card.source
        entry.startup = Task { @MainActor [weak self] in
            do {
                let handle = try await client.subscribeRenderTemplate(card: card, userName: userName,
                    onTermination: { [weak self] error in
                        await self?.terminated(error, key: key, attempt: attempt)
                    }, onEvent: { [weak self] event in
                        await self?.receive(event, key: key, attempt: attempt)
                    })
                guard let self = self, let current = self.current(key, attempt: attempt), !Task.isCancelled else {
                    await handle.cancel(); return
                }
                current.startup = nil; current.subscription = handle
                if current.connectsCachedEmpty {
                    current.connectsCachedEmpty = false
                    current.state.phase = .hidden
                    let ownership = self.detach(current)
                    self.retire?(ownership)
                } else { current.state.phase = .subscribed }
                self.inventory()
            } catch {
                guard let self = self, let current = self.current(key, attempt: attempt) else { return }
                current.startup = nil
                if Task.isCancelled { return }
                if case HomeAssistantWebSocketError.disconnected = error {
                    current.reconnectPending = true; current.state.phase = .disconnected
                } else {
                    current.state.phase = .rejected
                    current.state.store(HATemplateResult(result: card.content ?? ""))
                    self.prepare(card.content ?? "", key: key, entry: current)
                }
                self.inventory()
            }
        }
        if entry.connectsCachedEmpty {
            // hui-card removes a cached empty child immediately after its
            // connect attempt. Native cancellation revokes pending demand too.
            entry.connectsCachedEmpty = false
            let ownership = detach(entry)
            entry.state.phase = .hidden
            retire?(ownership)
        }
        inventory()
    }

    private func current(_ key: MarkdownOwnerKey, attempt: UUID) -> Entry? {
        guard authority.acceptsWork, let entry = entries[key], entry.active,
              entry.attempt == attempt, (!entry.state.hidden || entry.connectsCachedEmpty) else { return nil }
        return entry
    }

    private func receive(_ event: HATemplateEvent, key: MarkdownOwnerKey, attempt: UUID) {
        guard let entry = current(key, attempt: attempt) else { return }
        guard !entry.connectsCachedEmpty else { return }
        switch event {
        case let .error(message, level):
            AppLog("Markdown template \(level.rawValue); card=\(key.card.sourcePath): \(message)", severity: level == .error ? .error : .warning, category: .webSocket)
            if level == .error || entry.state.alertLevel != .error {
                entry.state.alert = message; entry.state.alertLevel = level
            }
        case let .result(result):
            entry.state.store(result)
            if entry.state.card.source.showEmpty == false && result.result.isEmpty {
                entry.state.hidden = true; entry.state.phase = .hidden
                let ownership = detach(entry)
                retire?(ownership)
                visibilityChanged?()
            } else {
                prepare(result.result, key: key, entry: entry)
            }
        }
    }

    private func terminated(_ error: Error, key: MarkdownOwnerKey, attempt: UUID) {
        guard let entry = current(key, attempt: attempt) else { return }
        let ownership = detach(entry)
        entry.state.phase = .rejected
        entry.state.alert = "Template stream unavailable: \(error.localizedDescription)"
        entry.state.alertLevel = .error
        retire?(ownership)
    }

    private func prepare(_ source: String, key: MarkdownOwnerKey, entry: Entry) {
        entry.preparation?.cancel()
        let revision = UUID(); entry.revision = revision
        entry.preparation = Task { @MainActor [weak self] in
            let document: MarkdownDocument
            do { document = try await MarkdownPreparationCache.shared.prepare(source) }
            catch is CancellationError { return }
            catch {
                AppLog("Markdown preparation failed; card=\(key.card.sourcePath): \(error)", severity: .error, category: .rendering)
                document = MarkdownDocument(source: source, blocks: [], fallbackNotice: "Markdown could not be parsed. Showing the complete source.")
            }
            guard !Task.isCancelled, let self = self, self.authority.acceptsWork,
                  let current = self.entries[key], current.revision == revision else { return }
            current.state.document = document
            current.preparation = nil
            self.inventory()
        }
        inventory()
    }

    private func detach(_ entry: Entry) -> MarkdownDetachedOwnership {
        let wasConnected = entry.active || entry.startup != nil || entry.subscription != nil
        entry.active = false; entry.reconnectPending = false
        entry.attempt = UUID(); entry.revision = UUID()
        if entry.startup != nil || entry.subscription != nil {
            entry.state.alert = nil; entry.state.alertLevel = nil
        }
        if wasConnected, let result = entry.state.result {
            let key = entry.state.card.source.rawValue.canonicalSemanticValue
            if let cached = cache[key], cached.deadline <= now() { cache.removeValue(forKey: key) }
            let incarnation = cacheIncarnation
            let deadline = min(cache[key]?.deadline ?? now().addingTimeInterval(1), now().addingTimeInterval(1))
            cache[key] = CachedResult(result: result, deadline: deadline)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard self?.cacheIncarnation == incarnation else { return }
                self?.cache.removeValue(forKey: key)
            }
        }
        let ownership = MarkdownDetachedOwnership(tasks: [entry.startup, entry.preparation].compactMap { $0 },
                                                  subscriptions: [entry.subscription].compactMap { $0 })
        ownership.cancelTasks()
        entry.startup = nil; entry.subscription = nil; entry.preparation = nil
        inventory()
        return ownership
    }

    private func cachedResult(for card: LovelaceCard) -> HATemplateResult? {
        let instant = now()
        cache = cache.filter { $0.value.deadline > instant }
        return cache[card.rawValue.canonicalSemanticValue]?.result
    }
    private func inventory() {
        ownershipChanged?(MarkdownDetachedOwnership(
            tasks: entries.values.flatMap { [$0.startup, $0.preparation].compactMap { $0 } } + [readyTask].compactMap { $0 },
            subscriptions: entries.values.compactMap(\.subscription)))
    }
    private func append(_ value: MarkdownDetachedOwnership, to target: inout MarkdownDetachedOwnership) {
        target.tasks += value.tasks; target.subscriptions += value.subscriptions
    }
    var ownerCount: Int { entries.values.reduce(0) { $0 + ($1.startup == nil ? 0 : 1) + ($1.subscription == nil ? 0 : 1) } }
    var retainedCardCount: Int { entries.count }
    var startupCount: Int { entries.values.filter { $0.startup != nil }.count }
    var preparationCount: Int { entries.values.filter { $0.preparation != nil }.count }
    var cachedResultCount: Int { cache.filter { $0.value.deadline > now() }.count }

    static func renderedMarkdownCards(_ view: LovelacePresentationView) -> [LovelacePresentationCard] {
        func collect(_ card: LovelacePresentationCard) -> [LovelacePresentationCard] {
            guard card.source.diagnostic == nil, card.isVisible else { return [] }
            if card.type == "markdown" { return [card] }
            if card.type == "vertical-stack" { return (card.cards ?? []).flatMap { collect($0) } }
            return []
        }
        let cards = view.resolved.source.panel == true || view.resolved.source.type == "panel" ? Array(view.cards.prefix(1)) : view.cards
        return cards.flatMap { collect($0) }
    }
}
