import Foundation
import NativeHACore

struct DashboardServiceAction: Hashable {
    let entityID: String
    let domain: String
    let service: String
}

@MainActor
final class DashboardServiceController {
    typealias Caller = @Sendable (String, String, [String: JSONValue]) async throws -> Void

    private var generation: UInt64 = 0
    private var tasks: [DashboardServiceAction: (UUID, Task<Void, Never>)] = [:]
    private(set) var errorMessage: String?
    private var caller: Caller?
    private var taskObserver: (([Task<Void, Never>]) -> Void)?
    private let lifetimeAuthority: DashboardLifetimeAuthority

    init(lifetimeAuthority: DashboardLifetimeAuthority = DashboardLifetimeAuthority()) {
        self.lifetimeAuthority = lifetimeAuthority
    }

    func setTaskObserver(_ observer: @escaping ([Task<Void, Never>]) -> Void) {
        taskObserver = observer
        observer(tasks.values.map(\.1))
    }

    func install(caller: @escaping Caller) {
        guard lifetimeAuthority.acceptsWork else { return }
        self.caller = caller
        errorMessage = nil
    }

    func canInvoke(entityID: String, state: HAState?, domain: String, service: String) -> Bool {
        guard lifetimeAuthority.acceptsWork,
              caller != nil,
              let state = state,
              state.state != "unavailable",
              state.state != "unknown"
        else {
            return false
        }
        return tasks[actionKey(entityID: entityID, domain: domain, service: service)] == nil
    }

    @discardableResult
    func invoke(
        entityID: String,
        domain: String,
        service: String,
        data: [String: JSONValue],
        errorContext: String,
        onCompletion: @escaping @MainActor (String?) -> Void = { _ in }
    ) -> Bool {
        let action = actionKey(entityID: entityID, domain: domain, service: service)
        guard lifetimeAuthority.acceptsWork,
              tasks[action] == nil,
              let caller = caller
        else { return false }
        let token = UUID()
        let capturedGeneration = generation
        let authority = lifetimeAuthority
        let task = Task { [weak self, authority] in
            guard authority.acceptsWork, !Task.isCancelled else { return }
            let failure: String?
            do {
                try await caller(domain, service, data)
                failure = nil
            } catch is CancellationError {
                return
            } catch {
                failure = "\(errorContext): \(error.localizedDescription)"
            }
            guard authority.acceptsWork, !Task.isCancelled else { return }
            await MainActor.run {
                guard authority.acceptsWork,
                      let self = self,
                      self.generation == capturedGeneration,
                      self.tasks[action]?.0 == token
                else { return }
                self.tasks.removeValue(forKey: action)
                self.taskObserver?(self.tasks.values.map(\.1))
                self.errorMessage = failure
                onCompletion(failure)
            }
        }
        tasks[action] = (token, task)
        taskObserver?(tasks.values.map(\.1))
        return true
    }

    func stopSynchronously() -> [Task<Void, Never>] {
        generation &+= 1
        let detached = tasks.values.map(\.1)
        tasks.removeAll()
        taskObserver?([])
        caller = nil
        detached.forEach { $0.cancel() }
        return detached
    }

    var inFlightCount: Int { tasks.count }

    private func actionKey(entityID: String, domain: String, service: String) -> DashboardServiceAction {
        let incompatibleFamily = service == "turn_on" || service == "turn_off" ? "power" : service
        return DashboardServiceAction(
            entityID: entityID,
            domain: domain,
            service: incompatibleFamily
        )
    }
}
