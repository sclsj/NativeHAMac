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

    init(debounceNanoseconds: UInt64 = AppConfig.climateInteractionPolicy.buttonDebounceNanoseconds, menuResyncNanoseconds: UInt64 = AppConfig.climateInteractionPolicy.menuResyncNanoseconds, sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }) {
        self.debounceNanoseconds = debounceNanoseconds
        self.menuResyncNanoseconds = menuResyncNanoseconds
        self.sleep = sleep
    }

    func install(entity: ClimateEntity, sender: @escaping Sender) {
        self.sender = sender
        replace(entity)
    }

    func replace(_ entity: ClimateEntity) {
        entityVersion &+= 1
        cancelResyncs()
        self.entity = entity
        values = Dictionary(uniqueKeysWithValues: [ClimateTarget.value, .low, .high, .humidity].compactMap { target in entity.value(target).map { (target, $0) } })
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
        values[target] = adjusted
        selectedTarget = target
        requestGeneration &+= 1
        error = nil
    }

    func button(_ direction: Double, target: ClimateTarget) {
        guard let entity = entity, entity.canAdjust(target), let current = values[target] else { return }
        change(current + direction * (target == .humidity ? entity.humidityStep : entity.step), target: target, snap: false)
        cancelDebounce()
        let generation = debounceGeneration
        let sleep = self.sleep
        let delay = debounceNanoseconds
        debounceTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self = self, self.debounceGeneration == generation else { return }
            self.debounceTask = nil
            self.commit(target)
        }
    }

    func commit(_ target: ClimateTarget) {
        guard let entity = entity, let request = ClimateServiceBuilder.target(target, values: values, entity: entity) else { return }
        send(request)
    }

    func mode(_ attribute: String, value: String) {
        guard let entity = entity, let request = ClimateServiceBuilder.mode(attribute, value: value, entity: entity) else { return }
        send(request, resyncOnSuccess: true)
    }

    private func send(_ request: ClimateServiceRequest, resyncOnSuccess: Bool = false) {
        requestGeneration &+= 1
        let generation = requestGeneration
        let lifetime = self.lifetime
        let entityVersion = self.entityVersion
        error = nil
        _ = sender?(request) { [weak self] failure in
            guard let self = self, self.lifetime == lifetime else { return }
            if failure == nil, resyncOnSuccess, self.entityVersion == entityVersion {
                self.scheduleResync(entityVersion: entityVersion, lifetime: lifetime)
            }
            guard self.requestGeneration == generation else { return }
            // Reference keeps the local draft on error until an entity replacement.
            self.error = failure
        }
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
            self.cancelDebounce()
            self.resetControlDraft()
        }
    }

    private func resetControlDraft() {
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
        sender = nil
        entity = nil
        values = [:]
        mainControl = .temperature
        selectedTarget = .low
        error = nil
    }

    deinit { debounceTask?.cancel(); resyncTasks.values.forEach { $0.cancel() } }
}
