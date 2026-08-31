import NativeHACore

@MainActor
final class LovelaceDashboardStore {
    private(set) var raw: LovelaceConfig
    private(set) var resolved: LovelaceResolvedDashboard
    private(set) var presentation: LovelacePresentationDashboard
    private(set) var phase: DashboardComponentPhase

    init(config: LovelaceConfig = LovelaceConfig(views: [])) {
        raw = config
        resolved = LovelaceResolvedDashboard(source: config)
        presentation = LovelacePresentationDashboard(resolved: resolved)
        phase = .idle
    }

    func beginLoading(retainingInstalled: Bool) {
        phase = retainingInstalled ? .reconnecting : .loading
    }

    @discardableResult
    func prepare(_ config: LovelaceConfig) -> LovelacePresentationDashboard {
        LovelacePresentationDashboard(resolved: LovelaceResolvedDashboard(source: config))
    }

    func install(_ candidate: LovelacePresentationDashboard) {
        raw = candidate.resolved.source
        resolved = candidate.resolved
        presentation = candidate
        phase = .ready
    }

    func fail(_ message: String) { phase = .failed(message) }
    func stop() { phase = .stopped }
}
