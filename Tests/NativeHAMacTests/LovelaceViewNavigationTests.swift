import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class LovelaceViewNavigationTests: XCTestCase {
    func testPrimaryFilteringPreservesRawViewsAndUsesExactResolvedIdentities() throws {
        let config = try fixture()
        let rawBefore = config.rawValue
        let navigation = makeNavigation(config, currentUserID: "user-1")

        XCTAssertEqual(
            navigation.primaryViews.map(\.source.path),
            ["default_view", "allowed-user", "duplicate", "duplicate", nil, "long_unlabeled-view"]
        )
        XCTAssertEqual(config.rawValue, rawBefore)
        XCTAssertEqual(navigation.dashboard.source.views.count, 12)
        XCTAssertNotNil(navigation.directRoute(path: "home_3h"))
        XCTAssertNotNil(navigation.directRoute(path: "home_12h"))
        XCTAssertNotNil(navigation.directRoute(path: "hidden"))
        XCTAssertNotNil(navigation.directRoute(path: "child"))
        XCTAssertEqual(
            navigation.primaryViews.filter { $0.source.path == "duplicate" }.map(\.identity),
            [navigation.dashboard.views[7].identity, navigation.dashboard.views[8].identity]
        )
        XCTAssertFalse(navigation.primaryViews.contains { $0.source.sourceIndex == 11 })
    }

    func testVisibilityMatrixFailsClosedOnlyForUserListsAndMalformedValues() throws {
        let config = try fixture()
        XCTAssertFalse(makeNavigation(config, currentUserID: nil).primaryViews.contains {
            $0.source.path == "allowed-user"
        })
        XCTAssertTrue(makeNavigation(config, currentUserID: "user-1").primaryViews.contains {
            $0.source.path == "allowed-user"
        })
        XCTAssertFalse(makeNavigation(config, currentUserID: "user-1").primaryViews.contains {
            $0.source.path == "other-user"
        })

        let malformed = try LovelaceConfig(rawValue: .object([
            "views": .array([
                .object(["title": .string("Public"), "visible": .bool(true), "cards": .array([])]),
                .object(["title": .string("Malformed"), "visible": .string("yes"), "cards": .array([])]),
            ]),
        ]))
        XCTAssertEqual(makeNavigation(malformed, currentUserID: nil).primaryViews.map(\.source.title), ["Public"])
    }

    func testZeroAndAllIneligibleViewsProduceFinalEmptySelection() throws {
        let empty = LovelaceConfig(views: [])
        let emptyNavigation = makeNavigation(empty, currentUserID: nil)
        XCTAssertTrue(emptyNavigation.primaryViews.isEmpty)
        XCTAssertNil(emptyNavigation.startupSelection(persisted: nil))

        let allIneligible = try LovelaceConfig(rawValue: .object([
            "views": .array([
                .object([
                    "title": .string("Maintenance"),
                    "path": .string("home_3h"),
                    "cards": .array([]),
                ]),
                .object([
                    "title": .string("Hidden"),
                    "path": .string("hidden"),
                    "visible": .bool(false),
                    "cards": .array([]),
                ]),
                .object([
                    "title": .string("Child"),
                    "path": .string("child"),
                    "subview": .bool(true),
                    "cards": .array([]),
                ]),
            ]),
        ]))
        let ineligibleNavigation = makeNavigation(allIneligible, currentUserID: nil)
        XCTAssertTrue(ineligibleNavigation.primaryViews.isEmpty)
        XCTAssertNil(ineligibleNavigation.startupSelection(persisted: .path("hidden")))
        XCTAssertEqual(ineligibleNavigation.dashboard.source.rawValue, allIneligible.rawValue)
    }

    func testStartupRestoreFallbackAndDuplicatePathRules() throws {
        let navigation = makeNavigation(try fixture(), currentUserID: "user-1")
        XCTAssertEqual(
            navigation.startupSelection(persisted: .path("allowed-user"))?.source.path,
            "allowed-user"
        )
        XCTAssertEqual(
            navigation.startupSelection(persisted: .path("removed"))?.source.path,
            "default_view"
        )
        XCTAssertEqual(
            navigation.startupSelection(persisted: .path("home_3h"))?.source.path,
            "default_view"
        )
        XCTAssertNil(navigation.view(for: .path("duplicate"), primaryOnly: true))
        XCTAssertNil(navigation.locator(for: navigation.dashboard.views[7]))
        XCTAssertNil(navigation.locator(for: navigation.dashboard.views[8]))
        XCTAssertEqual(navigation.locator(for: navigation.dashboard.views[9]), .sourceIndex(9))
        XCTAssertEqual(
            navigation.startupSelection(persisted: .sourceIndex(9))?.identity,
            navigation.dashboard.views[9].identity
        )
        XCTAssertEqual(
            navigation.directRoute(path: "duplicate")?.identity,
            navigation.dashboard.views[7].identity,
            "Path routes follow raw source order; sidebar actions use exact identity."
        )
    }

    func testSubviewBackUsesBackPathThenPrimaryThenStartupFallback() throws {
        let navigation = makeNavigation(try fixture(), currentUserID: "user-1")
        let home = navigation.dashboard.views[0]
        let child = try XCTUnwrap(navigation.directRoute(path: "child"))
        XCTAssertEqual(
            navigation.backSelection(
                from: child.identity,
                lastPrimaryIdentity: navigation.dashboard.views[4].identity,
                persistedPrimaryLocator: .path("allowed-user")
            )?.identity,
            home.identity
        )

        let hidden = try XCTUnwrap(navigation.directRoute(path: "hidden"))
        XCTAssertEqual(
            navigation.backSelection(
                from: hidden.identity,
                lastPrimaryIdentity: navigation.dashboard.views[4].identity,
                persistedPrimaryLocator: .path("default_view")
            )?.identity,
            navigation.dashboard.views[4].identity
        )
        XCTAssertEqual(
            navigation.backSelection(
                from: hidden.identity,
                lastPrimaryIdentity: nil,
                persistedPrimaryLocator: .path("allowed-user")
            )?.identity,
            navigation.dashboard.views[4].identity
        )
    }

    func testDisplayTitleIconModesAndSelectedItemIdentity() throws {
        let navigation = makeNavigation(try fixture(), currentUserID: "user-1")
        let selected = navigation.dashboard.views[10].identity
        let items = navigation.items(selectedIdentity: selected)
        let home = try XCTUnwrap(items.first { $0.identity == navigation.dashboard.views[0].identity })
        XCTAssertEqual(home.title, "Home")
        XCTAssertEqual(home.rawIcon, "mdi:home")
        XCTAssertEqual(home.displayMode, .iconAndTitle)

        let unlabeled = try XCTUnwrap(items.first { $0.identity == selected })
        XCTAssertEqual(unlabeled.title, "Long Unlabeled View")
        XCTAssertEqual(unlabeled.displayMode, .icon)
        XCTAssertTrue(unlabeled.isSelected)

        let pathless = try XCTUnwrap(items.first { $0.sourceIndex == 9 })
        XCTAssertEqual(pathless.title, "View 10")
        XCTAssertEqual(pathless.displayMode, .title)
    }

    func testVersionedPreferenceRoundTripAndMalformedCleanup() throws {
        let key = "isolated.module12.selection"
        let store = MemoryNavigationPreferenceStore()
        let persistence = LovelaceNavigationSelectionPersistence(key: key, store: store)

        XCTAssertNil(try persistence.load())
        try persistence.save(.path("default_view"))
        XCTAssertEqual(try persistence.load(), .path("default_view"))
        try persistence.save(.sourceIndex(4))
        XCTAssertEqual(try persistence.load(), .sourceIndex(4))

        let malformedValues: [Any] = [
            ["version": 0, "kind": "path", "path": "default_view"],
            ["version": true, "kind": "path", "path": "default_view"],
            ["version": 1, "kind": "path", "path": ""],
            ["version": 1, "kind": "path", "path": "default_view", "hash": "forbidden"],
            ["version": 1, "kind": "sourceIndex", "sourceIndex": -1],
            ["version": 1, "kind": "sourceIndex", "sourceIndex": 2.5],
            ["version": 1, "kind": "sourceIndex", "sourceIndex": true],
            "not a property-list locator",
        ]
        for malformed in malformedValues {
            store.values[key] = malformed
            XCTAssertNil(try persistence.load())
            XCTAssertNil(store.values[key])
        }

        try persistence.save(nil)
        XCTAssertNil(store.values[key])
    }

    func testPreferenceReadWriteFailureIsPropagatedForNonfatalOwnerDiagnostics() {
        let persistence = LovelaceNavigationSelectionPersistence(
            key: "failure",
            store: FailingNavigationPreferenceStore()
        )
        XCTAssertThrowsError(try persistence.load())
        XCTAssertThrowsError(try persistence.save(.path("default_view")))
        XCTAssertThrowsError(try persistence.save(nil))
    }

    @MainActor
    func testViewModelPersistsOnlyFinalUnambiguousPrimaryAndTransientRouteDoesNotOverwrite() async throws {
        let config = try fixture()
        let store = MemoryNavigationPreferenceStore()
        let persistence = LovelaceNavigationSelectionPersistence(
            key: AppConfig.lovelaceNavigationPolicy.persistedPrimarySelectionKey,
            store: store
        )
        let model = DashboardViewModel(
            initialViews: config.views,
            currentUserID: "user-1",
            navigationPreferenceStore: store
        )

        XCTAssertEqual(model.homeView?.path, "default_view")
        XCTAssertNil(try persistence.load(), "Initializer selection is not a committed async install")
        let allowed = try XCTUnwrap(model.presentationDashboard.views.first {
            $0.resolved.source.path == "allowed-user"
        })
        await model.selectViewForTesting(allowed.id)
        XCTAssertEqual(model.homeView?.path, "allowed-user")
        XCTAssertEqual(try persistence.load(), .path("allowed-user"))

        await model.navigateToViewForTesting(path: "hidden")
        XCTAssertEqual(model.homeView?.path, "hidden")
        XCTAssertEqual(try persistence.load(), .path("allowed-user"))

        let duplicate = try XCTUnwrap(model.navigationItems.first {
            $0.title == "Duplicate A"
        })
        await model.selectViewForTesting(duplicate.identity)
        XCTAssertEqual(model.homeView?.title, "Duplicate A")
        XCTAssertNil(try persistence.load(), "Ambiguous duplicate primary clears unsafe persistence")
    }

    @MainActor
    func testConfigRefreshReResolvesUniqueLocatorAndFallsBackWhenRemoved() async throws {
        let config = try fixture()
        let store = MemoryNavigationPreferenceStore()
        let model = DashboardViewModel(
            initialViews: config.views,
            currentUserID: "user-1",
            navigationPreferenceStore: store
        )
        let allowed = try XCTUnwrap(model.presentationDashboard.views.first {
            $0.resolved.source.path == "allowed-user"
        })
        await model.selectViewForTesting(allowed.id)

        let reorderedRaw: JSONValue
        guard case let .object(root) = config.rawValue,
              case let .array(rawViews)? = root["views"]
        else { return XCTFail("Fixture must contain raw views") }
        var reordered = rawViews
        let allowedRaw = reordered.remove(at: 4)
        reordered.insert(allowedRaw, at: 1)
        var reorderedRoot = root
        reorderedRoot["views"] = .array(reordered)
        reorderedRaw = .object(reorderedRoot)
        await model.applyLovelaceConfigForTesting(try LovelaceConfig(rawValue: reorderedRaw))
        XCTAssertEqual(model.homeView?.path, "allowed-user")
        XCTAssertEqual(model.homeView?.sourceIndex, 1)

        var removed = reordered
        removed.removeAll {
            guard case let .object(object) = $0 else { return false }
            return object["path"] == .string("allowed-user")
        }
        var removedRoot = root
        removedRoot["views"] = .array(removed)
        await model.applyLovelaceConfigForTesting(
            try LovelaceConfig(rawValue: .object(removedRoot))
        )
        XCTAssertEqual(model.homeView?.path, "default_view")
    }

    @MainActor
    func testViewModelDistinguishesNeverLoadedFromLoadedWithoutSelectableView() async throws {
        let model = DashboardViewModel(
            navigationPreferenceStore: MemoryNavigationPreferenceStore()
        )
        XCTAssertFalse(model.hasLoadedDashboard)
        XCTAssertNil(model.selectedViewIdentity)

        await model.applyLovelaceConfigForTesting(LovelaceConfig(views: []))
        XCTAssertTrue(model.hasLoadedDashboard)
        XCTAssertTrue(model.views.isEmpty)
        XCTAssertTrue(model.navigationItems.isEmpty)
        XCTAssertNil(model.selectedViewIdentity)

        let allIneligible = try LovelaceConfig(rawValue: .object([
            "views": .array([
                .object([
                    "title": .string("Maintenance"),
                    "path": .string("home_12h"),
                    "cards": .array([]),
                ]),
                .object([
                    "title": .string("Restricted"),
                    "path": .string("restricted"),
                    "visible": .array([.object(["user": .string("different-user")])]),
                    "cards": .array([]),
                ]),
            ]),
        ]))
        await model.applyLovelaceConfigForTesting(allIneligible)
        XCTAssertTrue(model.hasLoadedDashboard)
        XCTAssertEqual(model.views.count, 2, "Raw ineligible views remain preserved")
        XCTAssertTrue(model.navigationItems.isEmpty)
        XCTAssertNil(model.selectedViewIdentity)
        XCTAssertTrue(model.activeCards.isEmpty)
    }

    private func fixture() throws -> LovelaceConfig {
        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Lovelace/module-12-navigation.json")
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        return try LovelaceConfig(rawValue: raw)
    }

    private func makeNavigation(
        _ config: LovelaceConfig,
        currentUserID: String?
    ) -> LovelaceViewNavigation {
        LovelaceViewNavigation(
            dashboard: LovelaceResolvedDashboard(source: config),
            currentUserID: currentUserID,
            policy: AppConfig.lovelaceNavigationPolicy
        )
    }
}

private final class MemoryNavigationPreferenceStore: LovelaceNavigationPreferenceStore {
    var values: [String: Any] = [:]

    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}

private enum NavigationPreferenceFailure: Error {
    case injected
}

private final class FailingNavigationPreferenceStore: LovelaceNavigationPreferenceStore {
    func object(forKey key: String) throws -> Any? { throw NavigationPreferenceFailure.injected }
    func set(_ value: Any, forKey key: String) throws { throw NavigationPreferenceFailure.injected }
    func removeObject(forKey key: String) throws { throw NavigationPreferenceFailure.injected }
}
