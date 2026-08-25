import Foundation
import NativeHACore

enum LovelaceViewLocator: Equatable {
    case path(String)
    case sourceIndex(Int)

    fileprivate var propertyListValue: [String: Any] {
        switch self {
        case let .path(path):
            return ["version": 1, "kind": "path", "path": path]
        case let .sourceIndex(index):
            return ["version": 1, "kind": "sourceIndex", "sourceIndex": index]
        }
    }

    fileprivate static func decodePropertyList(_ value: Any) -> LovelaceViewLocator? {
        guard
            let object = value as? [String: Any],
            !(object["version"] is Bool),
            let version = object["version"] as? NSNumber,
            version.intValue == 1,
            let kind = object["kind"] as? String
        else { return nil }

        switch kind {
        case "path":
            guard
                object.keys.sorted() == ["kind", "path", "version"],
                let path = object["path"] as? String,
                !path.isEmpty
            else { return nil }
            return .path(path)
        case "sourceIndex":
            guard
                object.keys.sorted() == ["kind", "sourceIndex", "version"],
                !(object["sourceIndex"] is Bool),
                let number = object["sourceIndex"] as? NSNumber,
                number.intValue >= 0,
                Double(number.intValue) == number.doubleValue
            else { return nil }
            return .sourceIndex(number.intValue)
        default:
            return nil
        }
    }
}

enum LovelaceNavigationItemDisplayMode: Equatable {
    case title
    case icon
    case iconAndTitle
}

struct LovelaceNavigationItem: Equatable, Identifiable {
    var id: LovelaceResolvedIdentity { identity }
    let identity: LovelaceResolvedIdentity
    let locator: LovelaceViewLocator?
    let title: String
    let rawIcon: String?
    let displayMode: LovelaceNavigationItemDisplayMode
    let sourceIndex: Int
    let isSelected: Bool
}

/// Pure navigation policy over a lossless Module 04 resolved dashboard.
/// Locators answer route/persistence questions; exact resolved identities
/// answer runtime selection and owner-lifetime questions.
struct LovelaceViewNavigation {
    let dashboard: LovelaceResolvedDashboard
    let currentUserID: String?
    let policy: LovelaceNavigationPolicy

    private var validViews: [LovelaceResolvedView] {
        dashboard.views.filter { $0.source.diagnostic == nil }
    }

    private var nonemptyPathCounts: [String: Int] {
        validViews.reduce(into: [:]) { counts, view in
            guard let path = view.source.path, !path.isEmpty else { return }
            counts[path, default: 0] += 1
        }
    }

    var primaryViews: [LovelaceResolvedView] {
        validViews.filter(isEligiblePrimary)
    }

    func items(selectedIdentity: LovelaceResolvedIdentity?) -> [LovelaceNavigationItem] {
        primaryViews.map { view in
            LovelaceNavigationItem(
                identity: view.identity,
                locator: locator(for: view),
                title: displayTitle(for: view.source),
                rawIcon: normalizedIcon(view.source.icon),
                displayMode: displayMode(for: view.source),
                sourceIndex: view.source.sourceIndex,
                isSelected: view.identity == selectedIdentity
            )
        }
    }

    func view(identity: LovelaceResolvedIdentity?) -> LovelaceResolvedView? {
        guard let identity = identity else { return nil }
        return dashboard.views.first { $0.identity == identity }
    }

    func primaryView(identity: LovelaceResolvedIdentity?) -> LovelaceResolvedView? {
        guard let identity = identity else { return nil }
        return primaryViews.first { $0.identity == identity }
    }

    func locator(for view: LovelaceResolvedView) -> LovelaceViewLocator? {
        switch view.source.path {
        case nil:
            return .sourceIndex(view.source.sourceIndex)
        case let path? where !path.isEmpty && nonemptyPathCounts[path] == 1:
            return .path(path)
        default:
            return nil
        }
    }

    func persistedPrimaryLocator(for identity: LovelaceResolvedIdentity?) -> LovelaceViewLocator? {
        guard let primary = primaryView(identity: identity) else { return nil }
        return locator(for: primary)
    }

    func view(for locator: LovelaceViewLocator, primaryOnly: Bool) -> LovelaceResolvedView? {
        let candidates = primaryOnly ? primaryViews : validViews
        switch locator {
        case let .path(path):
            guard !path.isEmpty, nonemptyPathCounts[path] == 1 else { return nil }
            return candidates.first { $0.source.path == path }
        case let .sourceIndex(index):
            return candidates.first {
                $0.source.sourceIndex == index && $0.source.path == nil
            }
        }
    }

    func directRoute(path: String) -> LovelaceResolvedView? {
        guard !path.isEmpty else { return nil }
        return validViews.first { $0.source.path == path }
    }

    func startupSelection(persisted locator: LovelaceViewLocator?) -> LovelaceResolvedView? {
        if let locator = locator, let restored = view(for: locator, primaryOnly: true) {
            return restored
        }
        let defaults = primaryViews.filter { $0.source.path == "default_view" }
        if defaults.count == 1 {
            return defaults[0]
        }
        return primaryViews.first
    }

    func backSelection(
        from identity: LovelaceResolvedIdentity?,
        lastPrimaryIdentity: LovelaceResolvedIdentity?,
        persistedPrimaryLocator: LovelaceViewLocator?
    ) -> LovelaceResolvedView? {
        if
            let source = view(identity: identity)?.source,
            let backPath = source.backPath,
            let routed = directRoute(path: backPath)
        {
            return routed
        }
        if let primary = primaryView(identity: lastPrimaryIdentity) {
            return primary
        }
        return startupSelection(persisted: persistedPrimaryLocator)
    }

    func displayTitle(for view: LovelaceView) -> String {
        if
            case let .object(object) = view.rawValue,
            case let .string(title)? = object["title"],
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        if let path = view.path, !path.isEmpty {
            return path
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return "View \(view.sourceIndex + 1)"
    }

    private func isEligiblePrimary(_ view: LovelaceResolvedView) -> Bool {
        if let path = view.source.path, policy.excludedPrimaryPaths.contains(path) {
            return false
        }
        if view.source.subview == true { return false }
        switch view.source.visible {
        case nil:
            return true
        case let .bool(isVisible)?:
            return isVisible
        case let .array(entries)?:
            guard let currentUserID = currentUserID else { return false }
            return entries.contains { entry in
                guard
                    case let .object(object) = entry,
                    case let .string(userID)? = object["user"]
                else { return false }
                return userID == currentUserID
            }
        default:
            return false
        }
    }

    private func displayMode(for view: LovelaceView) -> LovelaceNavigationItemDisplayMode {
        let hasIcon = normalizedIcon(view.icon) != nil
        if view.showIconAndTitle == true, hasIcon {
            return .iconAndTitle
        }
        return hasIcon ? .icon : .title
    }

    private func normalizedIcon(_ icon: String?) -> String? {
        guard let icon = icon?.trimmingCharacters(in: .whitespacesAndNewlines), !icon.isEmpty else {
            return nil
        }
        return icon
    }
}

protocol LovelaceNavigationPreferenceStore: AnyObject {
    func object(forKey key: String) throws -> Any?
    func set(_ value: Any, forKey key: String) throws
    func removeObject(forKey key: String) throws
}

final class UserDefaultsLovelaceNavigationPreferenceStore: LovelaceNavigationPreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func object(forKey key: String) throws -> Any? {
        defaults.object(forKey: key)
    }

    func set(_ value: Any, forKey key: String) throws {
        defaults.set(value, forKey: key)
    }

    func removeObject(forKey key: String) throws {
        defaults.removeObject(forKey: key)
    }
}

struct LovelaceNavigationSelectionPersistence {
    let key: String
    let store: LovelaceNavigationPreferenceStore

    func load() throws -> LovelaceViewLocator? {
        guard let value = try store.object(forKey: key) else { return nil }
        guard let locator = LovelaceViewLocator.decodePropertyList(value) else {
            try store.removeObject(forKey: key)
            return nil
        }
        return locator
    }

    func save(_ locator: LovelaceViewLocator?) throws {
        if let locator = locator {
            try store.set(locator.propertyListValue, forKey: key)
        } else {
            try store.removeObject(forKey: key)
        }
    }
}
