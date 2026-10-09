import Foundation
import NativeHACore

/// One detail's presentation owner. Child slider drag/key geometry is separate:
/// slider-moved invalidates completion authority but does not change sliderValue.
/// Bind the child only when this owner's value changes, not on every revision.
@MainActor
final class FanServiceController: ObservableObject {
    typealias Sender = (FanServiceRequest, @escaping (String?) -> Void) -> Bool
    @Published private(set) var entity: FanEntity?
    @Published private(set) var sliderValue: Double?
    @Published private(set) var speedValue: FanSpeed = .off
    @Published private(set) var error: String?
    private(set) var presetDedupValue: String?
    private(set) var revision: UInt64 = 0
    private(set) var interactionRevision: UInt64 = 0
    private var lifetime: UInt64 = 0
    private var sender: Sender?

    func install(entity: FanEntity?, sender: @escaping Sender) {
        lifetime &+= 1
        self.sender = sender
        replace(entity)
    }

    /// Called for every accepted replacement, including equal-content objects.
    func replace(_ entity: FanEntity?) {
        revision &+= 1
        interactionRevision &+= 1
        self.entity = entity
        sliderValue = entity?.sliderValue
        speedValue = entity?.selectedSpeed ?? .off
        presetDedupValue = entity?.presetMode
        error = nil
    }

    /// Pointer/key activity can supersede an old failure before its next commit.
    func inputBegan() {
        guard let entity = entity, !entity.unavailable, sender != nil else { return }
        interactionRevision &+= 1
        error = nil
    }

    func percentage(_ value: Double) {
        guard let entity = entity, let request = FanServiceBuilder.percentage(value, entity: entity) else { return }
        sliderValue = value
        send(request)
    }

    func speed(_ value: FanSpeed) {
        guard let entity = entity, let request = FanServiceBuilder.speed(value, entity: entity) else { return }
        speedValue = value
        send(request)
    }

    func preset(_ value: String) {
        guard let entity = entity, value != presetDedupValue,
              let request = FanServiceBuilder.preset(value, entity: entity) else { return }
        presetDedupValue = value
        send(request)
    }

    func direction(_ value: FanDirection) {
        guard let entity = entity, let request = FanServiceBuilder.direction(value, entity: entity) else { return }
        send(request)
    }

    func oscillation(_ value: Bool) {
        guard let entity = entity, let request = FanServiceBuilder.oscillation(value, entity: entity) else { return }
        send(request)
    }

    func power(on: Bool) {
        guard let entity = entity, let request = FanServiceBuilder.power(on: on, entity: entity) else { return }
        send(request)
    }

    func togglePower() {
        guard let entity = entity, let request = FanServiceBuilder.togglePower(entity: entity) else { return }
        send(request)
    }

    private func send(_ request: FanServiceRequest) {
        interactionRevision &+= 1
        let interaction = interactionRevision, lifetime = self.lifetime
        error = nil
        let completion: (String?) -> Void = { [weak self] failure in
            guard let self = self, self.lifetime == lifetime,
                  self.interactionRevision == interaction else { return }
            // Neither success nor failure rolls back fan drafts/dedup.
            self.error = failure
        }
        if sender?(request, completion) != true { completion("Fan control is no longer available.") }
    }

    func close() {
        lifetime &+= 1
        sender = nil
        replace(nil)
    }
}
