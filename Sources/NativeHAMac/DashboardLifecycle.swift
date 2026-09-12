import Foundation
import NativeHACore

/// Process-local acceptance authority for work owned by one DashboardViewModel
/// lifetime. Explicit stop/restart continues to use the MainActor app/config
/// generations; this independent token exists so a nonisolated deinit can
/// synchronously make every detached callback inert before MainActor cleanup
/// is able to run.
final class DashboardLifetimeAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var accepting = true

    func revoke() {
        lock.lock()
        accepting = false
        lock.unlock()
    }

    var acceptsWork: Bool {
        lock.lock()
        defer { lock.unlock() }
        return accepting
    }
}

enum DashboardLifecyclePhase: String, CaseIterable, Equatable {
    case idle
    case connecting
    case loading
    case ready
    case reconnecting
    case disconnected
    case failed
    case stopped
}

enum DashboardComponent: String, CaseIterable, Hashable {
    case bootstrap
    case entities
    case lovelace
    case realtime
    case service
}

enum DashboardComponentPhase: Equatable {
    case idle
    case loading
    case ready
    case reconnecting
    case disconnected
    case failed(String)
    case stopped

    var errorMessage: String? {
        guard case let .failed(message) = self else { return nil }
        return message
    }
}

struct DashboardLifecycle: Equatable {
    private(set) var phase: DashboardLifecyclePhase = .idle
    private(set) var components: [DashboardComponent: DashboardComponentPhase] =
        Dictionary(uniqueKeysWithValues: DashboardComponent.allCases.map { ($0, .idle) })

    mutating func begin() {
        phase = .connecting
        components[.bootstrap] = .loading
        components[.entities] = .loading
        components[.lovelace] = .loading
        components[.realtime] = .loading
        components[.service] = .idle
    }

    mutating func loading() { phase = .loading }

    mutating func installed() {
        components[.bootstrap] = .ready
        components[.entities] = .ready
        components[.lovelace] = .ready
        components[.realtime] = .ready
        phase = .ready
    }

    mutating func connectionChanged(_ next: DashboardLifecyclePhase) {
        guard next == .ready || next == .reconnecting || next == .disconnected else { return }
        phase = next
        switch next {
        case .ready:
            components[.realtime] = .ready
            phase = requiredReconnectComponentsSettled ? .ready : .reconnecting
        case .reconnecting:
            components[.realtime] = .reconnecting
            components[.entities] = .reconnecting
            components[.lovelace] = .reconnecting
        case .disconnected:
            components[.realtime] = .disconnected
            components[.entities] = .disconnected
        default:
            break
        }
    }

    mutating func set(_ component: DashboardComponent, phase: DashboardComponentPhase) {
        #if DEBUG
        if case let .failed(message) = phase, components[component] != phase {
            AppLog("Dashboard \(component.rawValue) failed: \(message)", severity: .error, category: .lifecycle)
        }
        #endif
        components[component] = phase
        if self.phase == .reconnecting,
           components[.realtime] == .ready,
           requiredReconnectComponentsSettled
        {
            self.phase = .ready
        }
    }

    mutating func failBootstrap(_ message: String) {
        set(.bootstrap, phase: .failed(message))
        phase = .failed
    }

    mutating func stop() {
        phase = .stopped
        for component in DashboardComponent.allCases {
            components[component] = .stopped
        }
    }

    var compatibilityStatus: String {
        switch phase {
        case .idle: return "Starting"
        case .connecting: return "Connecting"
        case .loading: return "Loading dashboard"
        case .ready: return "Live"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Disconnected"
        case .failed: return "Error"
        case .stopped: return "Stopped"
        }
    }

    var primaryErrorMessage: String? {
        let priority: [DashboardComponent] = [.bootstrap, .entities, .lovelace, .realtime, .service]
        return priority.compactMap { component in
            components[component]?.errorMessage.map { "\(component.rawValue.capitalized): \($0)" }
        }.first
    }

    var componentFailures: [(DashboardComponent, String)] {
        DashboardComponent.allCases.compactMap { component in
            components[component]?.errorMessage.map { (component, $0) }
        }
    }

    private var requiredReconnectComponentsSettled: Bool {
        [DashboardComponent.entities, .lovelace].allSatisfy { component in
            guard let phase = components[component] else { return false }
            switch phase {
            case .ready, .failed:
                return true
            default:
                return false
            }
        }
    }
}
