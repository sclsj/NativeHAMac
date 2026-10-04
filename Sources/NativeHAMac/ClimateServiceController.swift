import Foundation
import NativeHACore

/// Mounted climate presentation only. HA's shared entity dictionary is never optimistic.
@MainActor
final class ClimateServiceController: ObservableObject {
    typealias Sender = (ClimateServiceRequest, @escaping (String?) -> Void) -> Bool
    typealias Sleeper = @Sendable (UInt64) async throws -> Void
    @Published private(set) var values: [ClimateTarget: Double] = [:]
    @Published private(set) var mainControl: ClimateMainControl = .temperature
    @Published private(set) var selectedTarget: ClimateTarget = .low
    @Published private(set) var error: String?
    @Published private(set) var pendingMode: String?
    private(set) var entity: ClimateEntity?
    private var sender: Sender?
    private var debounceTask: Task<Void, Never>?
    private var debounceGeneration: UInt64 = 0
    private var requestGeneration: UInt64 = 0
    private var lifetime: UInt64 = 0
    private var entityVersion: UInt64 = 0
    private var resyncTasks: [UUID: Task<Void, Never>] = [:]
    private let sleep: Sleeper
    private let debounceNanoseconds: UInt64
    private let menuResyncNanoseconds: UInt64
    private let modeFeedback: ClimateModeFeedback
    private let confirmationNanoseconds: UInt64
    private var modeID: UUID?
    private var modeBaseline: String?
    private var modeAlternatives: Set<String> = []
    private var modeCanConfirm = false
    private var modeTimeout: Task<Void, Never>?
    private struct ButtonIntent {
        let id: UUID
        let target: ClimateTarget
        let values: [ClimateTarget: Double]
        var earlier: [ClimateTarget: Set<Double>]
    }
    private var buttonIntent: ButtonIntent?
    private var targetTimeout: Task<Void, Never>?

    init(debounceNanoseconds: UInt64 = AppConfig.climateInteractionPolicy.buttonDebounceNanoseconds, menuResyncNanoseconds: UInt64 = AppConfig.climateInteractionPolicy.menuResyncNanoseconds, modeFeedback: ClimateModeFeedback = AppConfig.climateModeFeedback, confirmationNanoseconds: UInt64 = AppConfig.climatePendingConfirmationNanoseconds, sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }) {
        self.debounceNanoseconds = debounceNanoseconds
        self.menuResyncNanoseconds = menuResyncNanoseconds
        self.sleep = sleep
        self.modeFeedback = modeFeedback
        self.confirmationNanoseconds = confirmationNanoseconds
    }

    func install(entity: ClimateEntity, sender: @escaping Sender) {
        self.sender = sender
        replace(entity)
    }

    func replace(_ entity: ClimateEntity) {
        if let previous = self.entity, previous.entityID != entity.entityID {
            lifetime &+= 1
            clearMode(); clearButtonIntent(); cancelDebounce()
        }
        entityVersion &+= 1
        cancelResyncs()
        self.entity = entity
        values = Dictionary(uniqueKeysWithValues: [ClimateTarget.value, .low, .high, .humidity].compactMap { target in entity.value(target).map { (target, $0) } })
        if let intent = buttonIntent {
            // Mode/current-reading echoes can repeat the old target while a
            // button edit is debouncing or in flight. Only those field values
            // and earlier local targets are retained, within the timeout.
            let supported = ClimateServiceBuilder.target(intent.target, values: intent.values, entity: entity) != nil
            let confirmed = intent.values.allSatisfy { target, desired in entity.value(target).map { abs($0 - desired) < 1e-8 } == true }
            let unchangedOrEarlier = intent.values.allSatisfy { target, desired in
                guard let actual = entity.value(target) else { return false }
                return abs(actual - desired) < 1e-8 || intent.earlier[target]?.contains(where: { abs($0 - actual) < 1e-8 }) == true
            }
            if supported && !confirmed && unchangedOrEarlier {
                values.merge(intent.values) { _, pending in pending }
            } else {
                clearButtonIntent()
                cancelDebounce()
            }
        }
        if let mode = pendingMode {
            // Off → Cool → Off may receive an unchanged Off snapshot before
            // Cool arrives. It cannot yet confirm the latest reversal.
            if entity.state.state != modeBaseline { modeCanConfirm = true }
            if entity.unavailable || !entity.hvacModes.contains(mode) ||
                (entity.state.state == mode && modeCanConfirm) ||
                (entity.state.state != mode && !modeAlternatives.contains(entity.state.state)) {
                clearMode()
            }
        }
        if !entity.features.contains(.targetHumidity), mainControl == .humidity { mainControl = .temperature; selectedTarget = .low }
        // Acknowledgements/failures from the older presentation cannot overwrite this state.
        requestGeneration &+= 1
        error = nil
    }

    func selectMain(_ selection: ClimateMainControl) {
        guard let entity = entity, !entity.unavailable, selection == .temperature || entity.features.contains(.targetHumidity) else { return }
        guard mainControl != selection else { return }
        cancelDebounce()
        mainControl = selection
        resetControlDraft()
    }

    func selectTarget(_ target: ClimateTarget) { selectedTarget = target }

    func value(_ target: ClimateTarget, fallback: ClimateEntity) -> Double? { values[target] ?? fallback.value(target) }

    func change(_ value: Double, target: ClimateTarget, snap: Bool = true) {
        guard let entity = entity, let adjusted = ClimateValueMapping.adjusted(value, target: target, values: values, entity: entity, snap: snap) else { return }
        clearButtonIntent()
        cancelDebounce()
        values[target] = adjusted
        selectedTarget = target
        requestGeneration &+= 1
        error = nil
    }

    func button(_ direction: Double, target: ClimateTarget) {
        guard let entity = entity, entity.canAdjust(target), let current = values[target] else { return }
        let previous = buttonIntent
        change(current + direction * (target == .humidity ? entity.humidityStep : entity.step), target: target, snap: false)
        let targets: [ClimateTarget] = target == .low || target == .high ? [.low, .high] : [target]
        let desired = values.filter { targets.contains($0.key) }
        var earlier = previous?.earlier ?? [:]
        for item in targets {
            if let baseline = entity.value(item) { earlier[item, default: []].insert(baseline) }
            if let old = previous?.values[item] { earlier[item, default: []].insert(old) }
        }
        let intent = ButtonIntent(id: UUID(), target: target, values: desired, earlier: earlier)
        buttonIntent = intent
        cancelDebounce()
        let generation = debounceGeneration
        let sleep = self.sleep
        let delay = debounceNanoseconds
        debounceTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self = self, self.debounceGeneration == generation else { return }
            self.debounceTask = nil
            guard self.buttonIntent?.id == intent.id else { return }
            self.commit(target)
        }
    }

    func commit(_ target: ClimateTarget) {
        // Button payloads come from captured intent, never an intervening echo.
        guard let entity = entity, let request = ClimateServiceBuilder.target(target, values: buttonIntent?.values ?? values, entity: entity) else { return }
        if let intent = buttonIntent {
            cancelDebounce()
            scheduleTargetTimeout(intent.id)
            send(request, pendingCompletion: { [weak self] failure in
                guard let self = self, self.buttonIntent?.id == intent.id, let failure = failure else { return }
                self.rollbackButtonIntent()
                self.error = failure
            })
        } else { send(request) }
    }

    func mode(_ attribute: String, value: String) {
        guard let entity = entity else { return }
        if attribute == "hvac_mode", modeFeedback == .immediate {
            guard value != (pendingMode ?? entity.state.state),
                  let request = ClimateServiceBuilder.mode(attribute, value: value, entity: entity, allowCurrentValue: pendingMode != nil) else { return }
            if let pendingMode = pendingMode { modeAlternatives.insert(pendingMode) }
            modeAlternatives.insert(entity.state.state)
            let id = UUID()
            modeID = id
            modeBaseline = entity.state.state
            modeCanConfirm = value != entity.state.state
            pendingMode = value
            scheduleModeTimeout(id)
            send(request, pendingCompletion: { [weak self] failure in
                guard let self = self, self.modeID == id, let failure = failure else { return }
                self.clearMode()
                self.error = failure
            })
            return
        }
        guard let request = ClimateServiceBuilder.mode(attribute, value: value, entity: entity) else { return }
        send(request, resyncOnSuccess: true)
    }

    func presentation(_ authoritative: ClimateEntity) -> ClimateEntity {
        var result = authoritative
        result.presentationMode = pendingMode
        return result
    }

    private func send(_ request: ClimateServiceRequest, resyncOnSuccess: Bool = false, pendingCompletion: ((String?) -> Void)? = nil) {
        requestGeneration &+= 1
        let generation = requestGeneration
        let lifetime = self.lifetime
        let entityVersion = self.entityVersion
        error = nil
        let completion: (String?) -> Void = { [weak self] failure in
            guard let self = self, self.lifetime == lifetime else { return }
            pendingCompletion?(failure)
            if failure == nil, resyncOnSuccess, self.entityVersion == entityVersion {
                self.scheduleResync(entityVersion: entityVersion, lifetime: lifetime)
            }
            guard self.requestGeneration == generation else { return }
            // Reference keeps the local draft on error until an entity replacement.
            self.error = failure
        }
        if sender?(request, completion) != true { completion("Climate control is no longer available.") }
    }

    private func scheduleResync(entityVersion: UInt64, lifetime: UInt64) {
        let id = UUID()
        let sleep = self.sleep
        let delay = menuResyncNanoseconds
        resyncTasks[id] = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self = self else { return }
            self.resyncTasks.removeValue(forKey: id)
            guard self.entityVersion == entityVersion, self.lifetime == lifetime else { return }
            if self.buttonIntent == nil {
                self.cancelDebounce()
                self.resetControlDraft()
            }
        }
    }

    private func resetControlDraft() {
        clearButtonIntent()
        guard let entity = entity else { return }
        values = Dictionary(uniqueKeysWithValues: [ClimateTarget.value, .low, .high, .humidity].compactMap { target in entity.value(target).map { (target, $0) } })
        selectedTarget = .low
    }

    private func cancelResyncs() {
        resyncTasks.values.forEach { $0.cancel() }
        resyncTasks.removeAll()
    }

    func cancelDebounce() {
        debounceGeneration &+= 1
        debounceTask?.cancel()
        debounceTask = nil
    }

    func close() {
        lifetime &+= 1
        cancelDebounce()
        cancelResyncs()
        clearButtonIntent()
        clearMode()
        sender = nil
        entity = nil
        values = [:]
        mainControl = .temperature
        selectedTarget = .low
        error = nil
    }

    private func clearMode() {
        modeTimeout?.cancel(); modeTimeout = nil
        modeID = nil; pendingMode = nil; modeBaseline = nil
        modeAlternatives = []; modeCanConfirm = false
    }

    private func clearButtonIntent() {
        targetTimeout?.cancel(); targetTimeout = nil
        buttonIntent = nil
    }

    private func rollbackButtonIntent() {
        if let intent = buttonIntent, let entity = entity {
            for target in intent.values.keys { values[target] = entity.value(target) }
        }
        cancelDebounce()
        clearButtonIntent()
    }

    private func scheduleModeTimeout(_ id: UUID) {
        modeTimeout?.cancel()
        let sleep = self.sleep, delay = confirmationNanoseconds
        modeTimeout = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self = self, self.modeID == id else { return }
            let alreadyMatches = self.entity?.state.state == self.pendingMode
            self.clearMode()
            if !alreadyMatches { self.error = "Home Assistant has not confirmed the requested mode." }
        }
    }

    private func scheduleTargetTimeout(_ id: UUID) {
        targetTimeout?.cancel()
        let sleep = self.sleep, delay = confirmationNanoseconds
        targetTimeout = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self = self, self.buttonIntent?.id == id else { return }
            self.rollbackButtonIntent()
            self.error = "Home Assistant has not confirmed the requested target."
        }
    }

    deinit { debounceTask?.cancel(); modeTimeout?.cancel(); targetTimeout?.cancel(); resyncTasks.values.forEach { $0.cancel() } }
}
