import Foundation
import NativeHACore

struct HAEntityStoreApplication: Equatable {
    let snapshot: [String: HAState]
    #if DEBUG
    let unknownChangedEntityIDs: [String]
    #endif
    let revision: UInt64
}

/// Pure ordered application of Home Assistant's compressed entity protocol.
/// Callers prepare a complete candidate and publish it once; no partially
/// decoded or partially applied payload can escape this value type.
struct HAEntityStore {
    private(set) var snapshot: [String: HAState] = [:]
    private(set) var revision: UInt64 = 0

    init(snapshot: [String: HAState] = [:], revision: UInt64 = 0) {
        self.snapshot = snapshot
        self.revision = revision
    }

    mutating func apply(
        _ payload: HAEntitySubscriptionPayload,
        authoritative: Bool
    ) -> HAEntityStoreApplication {
        var candidate = authoritative ? [:] : snapshot
        #if DEBUG
        var unknown: [String] = []
        #endif

        // Wire contract: additions/replacements, then removals, then changes.
        for (entityID, compressed) in payload.additions ?? [:] {
            candidate[entityID] = Self.state(entityID: entityID, compressed: compressed)
        }
        for entityID in payload.removals ?? [] {
            candidate.removeValue(forKey: entityID)
        }
        for (entityID, change) in payload.changes ?? [:] {
            guard let old = candidate[entityID] else {
                #if DEBUG
                unknown.append(entityID)
                #endif
                continue
            }
            candidate[entityID] = Self.patched(old, with: change)
        }

        revision &+= 1
        snapshot = candidate
        #if DEBUG
        return HAEntityStoreApplication(
            snapshot: candidate,
            unknownChangedEntityIDs: unknown.sorted(),
            revision: revision
        )
        #else
        return HAEntityStoreApplication(snapshot: candidate, revision: revision)
        #endif
    }

    private static func state(
        entityID: String,
        compressed: HACompressedEntityState
    ) -> HAState {
        let changed = HAEntityTimestampFormatter.string(compressed.lastChanged)
        let updated = compressed.lastUpdated.map(HAEntityTimestampFormatter.string) ?? changed
        return HAState(
            entityId: entityID,
            state: compressed.state,
            attributes: compressed.attributes,
            context: compressed.context.value,
            lastChanged: changed,
            lastUpdated: updated
        )
    }

    private static func patched(
        _ old: HAState,
        with change: HACompressedEntityChange
    ) -> HAState {
        var state = old.state
        var attributes = old.attributes
        var context = old.context
        var lastChanged = old.lastChanged
        var lastUpdated = old.lastUpdated

        if let additions = change.additions {
            if let value = additions.state { state = value }
            if let value = additions.context {
                switch value {
                case let .id(id):
                    context = HAContext(
                        id: id,
                        parentID: context?.parentID,
                        userID: context?.userID
                    )
                case let .object(patch):
                    context = HAContext(
                        id: patch.id.merging(over: context?.id),
                        parentID: patch.parentID.merging(over: context?.parentID),
                        userID: patch.userID.merging(over: context?.userID)
                    )
                }
            }
            if let seconds = additions.lastChanged, seconds != 0 {
                let value = HAEntityTimestampFormatter.string(seconds)
                lastChanged = value
                lastUpdated = value
            } else if let seconds = additions.lastUpdated, seconds != 0 {
                lastUpdated = HAEntityTimestampFormatter.string(seconds)
            }
            for (key, value) in additions.attributes ?? [:] {
                attributes[key] = value
            }
        }
        for key in change.removals?.attributes ?? [] {
            attributes.removeValue(forKey: key)
        }

        return HAState(
            entityId: old.entityId,
            state: state,
            attributes: attributes,
            context: context,
            lastChanged: lastChanged,
            lastUpdated: lastUpdated
        )
    }
}

private extension HAContextPatchField {
    func merging(over prior: String?) -> String? {
        switch self {
        case .absent: return prior
        case let .value(value): return value
        }
    }
}

private enum HAEntityTimestampFormatter {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    static func string(_ seconds: Double) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}
