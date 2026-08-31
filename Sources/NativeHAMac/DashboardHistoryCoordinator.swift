import Foundation
import NativeHACore

/// MainActor storage façade for dashboard/detail history ownership. It owns no
/// serialization task: every desired-owner mutation remains driven by
/// DashboardViewModel's single `dashboardOwnerOperationTail`, while Module 01
/// alone owns wire reconnect behavior.
final class DashboardHistoryCoordinator {
    var histories: [String: [HAHistorySeries]] = [:]
    var detailHistories: [String: HAHistorySeries] = [:]
    var statuses: [String: HAHistoryStreamOwnerStatus] = [:]
    var detailStatuses: [String: HAHistoryStreamOwnerStatus] = [:]
    var subscriptions: [String: HAHistoryStreamSubscription] = [:]
    var startupTasks: [UUID: HistoryStartupTask] = [:]
    var detailSubscriptions: [String: HAHistoryStreamSubscription] = [:]
    var detailStartupTasks: [UUID: DetailHistoryStartupTask] = [:]
    var generations: [String: UUID] = [:]
    var detailGenerations: [String: UUID] = [:]
    var graphRevisionFeeds: [String: GraphHistoryRevisionFeed] = [:]
    var desiredKeys: Set<String> = []
    var desiredDetailKeys: Set<String> = []
    var reconciliationEpoch: UInt64 = 0

    @MainActor var hasNoLiveOwnership: Bool {
        subscriptions.isEmpty && startupTasks.isEmpty &&
            detailSubscriptions.isEmpty && detailStartupTasks.isEmpty &&
            generations.isEmpty && detailGenerations.isEmpty &&
            graphRevisionFeeds.values.allSatisfy { $0.observerCount == 0 }
    }
}

struct HistoryStartupTask {
    let key: String
    let task: Task<Void, Never>
}

struct DetailHistoryStartupTask {
    let key: String
    let task: Task<Void, Never>
}
