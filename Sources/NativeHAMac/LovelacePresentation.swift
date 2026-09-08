import Foundation
import NativeHACore

struct LovelacePresentationRow: Equatable, Identifiable {
    var id: LovelaceResolvedIdentity { identity }
    let source: LovelaceEntityRef
    let identity: LovelaceResolvedIdentity
    let isSynthetic: Bool
}

struct LovelacePresentationCard: Equatable, Identifiable {
    var id: LovelaceResolvedIdentity { identity }
    let source: LovelaceCard
    let identity: LovelaceResolvedIdentity
    let rows: [LovelacePresentationRow]?
    let cards: [LovelacePresentationCard]?
    let isVisible: Bool

    var nativeID: String { identity.ownerKey }
    var type: String { source.type }
    var title: String? { source.title }
    var entity: String? { source.entity }
    var hoursToShow: Int? { source.hoursToShow }
    var showCurrent: Bool? { source.showCurrent }
    var showForecast: Bool? { source.showForecast }
    var forecastType: String? { source.forecastType }
    var forecastSlots: Int? { source.forecastSlots }
    var secondaryInfoAttribute: String? { source.secondaryInfoAttribute }
    var roundTemperature: Bool? { source.roundTemperature }
    var name: String? { source.name }
    var nameValue: JSONValue? { source.nameValue }
    var tapAction: JSONValue? { source.tapAction }
    var holdAction: JSONValue? { source.holdAction }
    var doubleTapAction: JSONValue? { source.doubleTapAction }
    var content: String? { source.content }
    var entities: [LovelaceEntityRef]? { rows?.map(\.source) }

    static func standalone(_ source: LovelaceCard) -> LovelacePresentationCard {
        let resolved = LovelaceResolvedDashboard(source: LovelaceConfig(views: [
            LovelaceView(title: "Standalone", cards: [source]),
        ])).views[0].cards[0]
        return LovelacePresentationTransformer.card(
            resolved,
            appliesDefaultDashboardPolicy: false
        )
    }
}

struct LovelacePresentationView: Equatable, Identifiable {
    var id: LovelaceResolvedIdentity { resolved.identity }
    let resolved: LovelaceResolvedView
    let cards: [LovelacePresentationCard]
}

struct LovelacePresentationDashboard: Equatable {
    let resolved: LovelaceResolvedDashboard
    let views: [LovelacePresentationView]

    init(resolved: LovelaceResolvedDashboard) {
        self.resolved = resolved
        views = resolved.views.map { view in
            let isDefaultView = view.source.path == "default_view"
            let cards = LovelacePresentationTransformer.cards(
                view.cards,
                appliesDefaultDashboardPolicy: isDefaultView
            )
            return LovelacePresentationView(resolved: view, cards: cards)
        }
    }
}

enum LovelacePresentationTransformer {
    static func cards(
        _ resolvedCards: [LovelaceResolvedCard],
        appliesDefaultDashboardPolicy: Bool
    ) -> [LovelacePresentationCard] {
        let transformed = resolvedCards.map {
            card($0, appliesDefaultDashboardPolicy: appliesDefaultDashboardPolicy)
        }
        guard appliesDefaultDashboardPolicy else { return transformed }
        return transformed.flatMap(flattenDefaultVerticalStack)
    }

    static func card(
        _ resolved: LovelaceResolvedCard,
        appliesDefaultDashboardPolicy: Bool
    ) -> LovelacePresentationCard {
        let sourceRows = resolved.rows?.map {
            LovelacePresentationRow(source: $0.source, identity: $0.identity, isSynthetic: false)
        }
        let extraRows: [LovelacePresentationRow]
        if
            appliesDefaultDashboardPolicy,
            let title = resolved.source.title,
            let extras = AppConfig.extraEntitiesByCardTitle[title]
        {
            extraRows = extras.enumerated().map { index, source in
                let path = resolved.identity.sourcePath.appending("synthetic_entities", index: index)
                return LovelacePresentationRow(
                    source: source,
                    identity: LovelaceResolvedIdentity(sourcePath: path, rawValue: source.rawValue),
                    isSynthetic: true
                )
            }
        } else {
            extraRows = []
        }

        let effectiveRows: [LovelacePresentationRow]?
        if sourceRows == nil, extraRows.isEmpty {
            effectiveRows = nil
        } else {
            let keptSourceRows = (sourceRows ?? []).filter { row in
                guard appliesDefaultDashboardPolicy,
                      let entityID = row.source.entity
                else { return true }
                return !AppConfig.hiddenEntityIDs.contains(entityID)
            }
            var representedEntities = Set(keptSourceRows.compactMap { $0.source.entity })
            let keptExtraRows = extraRows.filter { row in
                guard let entityID = row.source.entity else { return true }
                if appliesDefaultDashboardPolicy,
                   AppConfig.hiddenEntityIDs.contains(entityID)
                {
                    return false
                }
                return representedEntities.insert(entityID).inserted
            }
            effectiveRows = keptExtraRows + keptSourceRows
        }

        let nested = resolved.cards.map {
            $0.map { card($0, appliesDefaultDashboardPolicy: appliesDefaultDashboardPolicy) }
        }
        let hidesEmptyEntityCard = resolved.source.diagnostic == nil &&
            resolved.source.entities != nil && effectiveRows?.isEmpty == true
        let hidesEmptyHistory = resolved.source.diagnostic == nil &&
            resolved.source.type == "history-graph" && effectiveRows?.isEmpty == true
        return LovelacePresentationCard(
            source: resolved.source,
            identity: resolved.identity,
            rows: effectiveRows,
            cards: nested,
            isVisible: !hidesEmptyEntityCard && !hidesEmptyHistory
        )
    }

    private static func flattenDefaultVerticalStack(
        _ card: LovelacePresentationCard
    ) -> [LovelacePresentationCard] {
        guard
            card.source.diagnostic == nil,
            card.type == "vertical-stack",
            let nested = card.cards
        else {
            return card.isVisible ? [card] : []
        }
        return nested.flatMap(flattenDefaultVerticalStack)
    }
}
