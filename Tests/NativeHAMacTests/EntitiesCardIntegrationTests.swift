import Foundation
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class EntitiesCardIntegrationTests: XCTestCase {
    func testSourceDuplicatesRemainVisibleAndSyntheticOnlySkipsRepresentedEntity() {
        let duplicateA = LovelaceEntityRef(entity: "sensor.same", name: "First")
        let duplicateB = LovelaceEntityRef(entity: "sensor.same", name: "Second")
        let source = LovelaceCard(
            type: "entities",
            title: "AC Unit Controller",
            entities: [duplicateA, duplicateB]
        )
        let dashboard = LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: LovelaceConfig(views: [
                LovelaceView(title: "Home", path: "default_view", cards: [source]),
            ]))
        )
        let rows = dashboard.views[0].cards[0].rows ?? []

        XCTAssertEqual(rows.map { $0.source.name }, ["Room AC", "First", "Second"])
        XCTAssertEqual(rows.map { $0.source.entity }, ["climate.room_ac", "sensor.same", "sensor.same"])
        XCTAssertNotEqual(rows[1].identity, rows[2].identity)
        XCTAssertEqual(rows[1].identity.sourcePath.description, "views[0].cards[0].entities[0]")
        XCTAssertEqual(rows[2].identity.sourcePath.description, "views[0].cards[0].entities[1]")
    }

    func testHeaderIntentCandidatesCheckedAndTransitionStagesRemainSeparate() throws {
        let rows: [JSONValue] = [
            .string("switch.one"),
            .object(["entity": .string("switch.one"), "name": .string("Duplicate")]),
            .string("light.two"),
            .string("sensor.read_only"),
        ]
        let implicit = try card(raw: .object([
            "type": .string("entities"),
            "title": .string(""),
            "entities": .array(rows),
        ]))
        let states = [
            "switch.one": HAState(entityId: "switch.one", state: "off"),
            "light.two": HAState(entityId: "light.two", state: "on"),
            "sensor.read_only": HAState(entityId: "sensor.read_only", state: "3"),
        ]

        XCTAssertTrue(EntityRowPresentationResolver.headerConfiguredIntent(card: implicit))
        let candidates = EntityRowPresentationResolver.headerCandidates(card: implicit, states: states)
        XCTAssertEqual(candidates, ["switch.one", "light.two"])
        XCTAssertTrue(EntityRowPresentationResolver.headerChecked(candidates: candidates, states: states))
        XCTAssertEqual(
            EntityRowPresentationResolver.headerTransitionTargets(
                candidates: candidates, states: states, isOn: true
            ),
            ["switch.one"]
        )
        XCTAssertEqual(
            EntityRowPresentationResolver.headerTransitionTargets(
                candidates: candidates, states: states, isOn: false
            ),
            ["light.two"]
        )

        let missingTitle = try card(raw: .object([
            "type": .string("entities"),
            "entities": .array(rows),
        ]))
        XCTAssertFalse(EntityRowPresentationResolver.headerConfiguredIntent(card: missingTitle))
        let explicitFalse = try card(raw: .object([
            "type": .string("entities"),
            "title": .string("Power"),
            "show_header_toggle": .bool(false),
            "entities": .array(rows),
        ]))
        XCTAssertFalse(EntityRowPresentationResolver.headerConfiguredIntent(card: explicitFalse))
        let explicitTrue = try card(raw: .object([
            "type": .string("entities"),
            "show_header_toggle": .bool(true),
            "entities": .array([.string("switch.missing")]),
        ]))
        XCTAssertTrue(EntityRowPresentationResolver.headerConfiguredIntent(card: explicitTrue))
        XCTAssertTrue(EntityRowPresentationResolver.headerCandidates(card: explicitTrue, states: states).isEmpty)
    }

    func testRowAndHeaderDispatchUseExactRoutesAndPreserveOptimisticMetadata() async {
        let original = HAState(
            entityId: "cover.blind",
            state: "off",
            attributes: ["friendly_name": .string("Blind"), "position": .int(7)],
            context: HAContext(id: "context", parentID: "parent", userID: "user"),
            lastChanged: "2026-09-01T00:00:00Z",
            lastUpdated: "2026-09-01T00:01:00Z"
        )
        let headerSwitch = HAState(entityId: "switch.header", state: "off")
        let recorder = ServiceRecorder()
        let model = DashboardViewModel(initialStates: [
            original.entityId: original,
            headerSwitch.entityId: headerSwitch,
        ])
        model.installServiceCallerForTesting { domain, service, data in
            await recorder.record(domain: domain, service: service, data: data)
        }

        XCTAssertTrue(model.canSetRowPower(entityID: original.entityId, isOn: true))
        model.setPower(entityID: original.entityId, isOn: true)
        XCTAssertEqual(model.states[original.entityId]?.state, "on")
        XCTAssertEqual(model.states[original.entityId]?.attributes, original.attributes)
        XCTAssertEqual(model.states[original.entityId]?.context, original.context)
        XCTAssertEqual(model.states[original.entityId]?.lastChanged, original.lastChanged)
        XCTAssertEqual(model.states[original.entityId]?.lastUpdated, original.lastUpdated)

        await waitUntil { await recorder.count == 1 }
        let rowCall = await recorder.calls[0]
        XCTAssertEqual(rowCall.domain, "cover")
        XCTAssertEqual(rowCall.service, "open_cover")
        XCTAssertEqual(rowCall.data["entity_id"], .string(original.entityId))

        model.setPower(entityIDs: [headerSwitch.entityId], isOn: true)
        await waitUntil { await recorder.count == 2 }
        let headerCall = await recorder.calls[1]
        XCTAssertEqual(headerCall.domain, "homeassistant")
        XCTAssertEqual(headerCall.service, "turn_on")
        XCTAssertEqual(model.states[headerSwitch.entityId]?.state, "on")
    }

    func testMissingUnknownUnavailableAndNoCallerNeverDispatch() async {
        let recorder = ServiceRecorder()
        let model = DashboardViewModel(initialStates: [
            "switch.unknown": HAState(entityId: "switch.unknown", state: "unknown"),
            "switch.unavailable": HAState(entityId: "switch.unavailable", state: "unavailable"),
            "switch.available": HAState(entityId: "switch.available", state: "off"),
        ])
        model.installServiceCallerForTesting { domain, service, data in
            await recorder.record(domain: domain, service: service, data: data)
        }

        model.setPower(entityID: "switch.unknown", isOn: true)
        model.setPower(entityID: "switch.unavailable", isOn: true)
        model.setPower(entityID: "switch.missing", isOn: true)
        await Task.yield()
        let countBeforeStop = await recorder.count
        XCTAssertEqual(countBeforeStop, 0)

        await model.stop()
        model.setPower(entityID: "switch.available", isOn: true)
        await Task.yield()
        let countAfterStop = await recorder.count
        XCTAssertEqual(countAfterStop, 0)
        XCTAssertEqual(model.states["switch.available"]?.state, "off")
    }

    func testRowAndHeaderPowerFamiliesCannotOverlapForOneEntity() async {
        let rowFirst = "switch.row_first"
        let headerFirst = "switch.header_first"
        let unrelated = "switch.unrelated"
        let recorder = HoldingServiceRecorder()
        let model = DashboardViewModel(initialStates: [
            rowFirst: HAState(entityId: rowFirst, state: "off"),
            headerFirst: HAState(entityId: headerFirst, state: "off"),
            unrelated: HAState(entityId: unrelated, state: "off"),
        ])
        model.installServiceCallerForTesting { domain, service, data in
            await recorder.recordAndWait(domain: domain, service: service, data: data)
        }

        model.setPower(entityID: rowFirst, isOn: true)
        await waitUntil { await recorder.count == 1 }
        XCTAssertFalse(model.canSetRowPower(entityID: rowFirst, isOn: false))
        XCTAssertFalse(model.canSetHeaderPower(entityIDs: [rowFirst], isOn: false))
        model.setPower(entityID: rowFirst, isOn: false)
        model.setPower(entityIDs: [rowFirst], isOn: false)
        await Task.yield()
        let rowFirstCount = await recorder.count
        XCTAssertEqual(rowFirstCount, 1)

        model.setPower(entityIDs: [headerFirst], isOn: true)
        await waitUntil { await recorder.count == 2 }
        XCTAssertFalse(model.canSetRowPower(entityID: headerFirst, isOn: false))
        XCTAssertFalse(model.canSetHeaderPower(entityIDs: [headerFirst], isOn: false))
        model.setPower(entityID: headerFirst, isOn: false)
        model.setPower(entityIDs: [headerFirst], isOn: false)
        await Task.yield()
        let headerFirstCount = await recorder.count
        XCTAssertEqual(headerFirstCount, 2)

        XCTAssertTrue(model.canSetRowPower(entityID: unrelated, isOn: true))
        model.setPower(entityID: unrelated, isOn: true)
        await waitUntil { await recorder.count == 3 }
        let calls = await recorder.calls
        XCTAssertEqual(calls.filter { $0.entityID == rowFirst }.map(\.route), ["switch.turn_on"])
        XCTAssertEqual(
            calls.filter { $0.entityID == headerFirst }.map(\.route),
            ["homeassistant.turn_on"]
        )
        XCTAssertEqual(calls.filter { $0.entityID == unrelated }.map(\.route), ["switch.turn_on"])

        await recorder.releaseAll()
        await waitUntil { model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0 }
    }

    func testStateBurstRecomputesSynchronouslyWithoutChangingRawRowIdentity() throws {
        let raw: JSONValue = .object([
            "entity": .string("sensor.burst"),
            "name": .array([
                .object(["type": .string("text"), "text": .string("Burst")]),
                .object(["type": .string("entity")]),
            ]),
        ])
        let source = LovelaceEntityRef(rawValue: raw, diagnosticPath: "row")
        let identity = LovelaceResolvedIdentity(
            sourcePath: LovelaceSourcePath().appending("entities", index: 0),
            rawValue: raw
        )
        let row = LovelacePresentationRow(source: source, identity: identity, isSynthetic: false)
        let model = DashboardViewModel(initialStates: [
            "sensor.burst": HAState(entityId: "sensor.burst", state: "0"),
        ])

        for revision in 1...100 {
            model.states["sensor.burst"] = HAState(
                entityId: "sensor.burst",
                state: String(revision),
                attributes: ["friendly_name": .string("Revision \(revision)")]
            )
        }
        let result = model.entityRowPresentation(row, cardStateColor: nil)
        XCTAssertEqual(result.name, "Burst Revision 100")
        XCTAssertEqual(result.stateText, "100")
        XCTAssertEqual(row.identity, identity)
        XCTAssertEqual(row.source.rawValue, raw)
        let owners = model.dashboardOwnerSnapshotForTesting()
        XCTAssertFalse(owners.dashboardOwnerTailActive)
        XCTAssertEqual(owners.dashboardOwnerNodeCount, 0)
        XCTAssertEqual(owners.startupCount, 0)
        XCTAssertEqual(owners.serviceTaskCount, 0)
    }

    private func card(raw: JSONValue) throws -> LovelacePresentationCard {
        let config = try LovelaceConfig(rawValue: .object([
            "views": .array([.object([
                "title": .string("Home"),
                "path": .string("default_view"),
                "cards": .array([raw]),
            ])]),
        ]))
        return LovelacePresentationDashboard(
            resolved: LovelaceResolvedDashboard(source: config)
        ).views[0].cards[0]
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await predicate()), Date() < deadline {
            await Task.yield()
        }
        let satisfied = await predicate()
        XCTAssertTrue(satisfied)
    }
}

private actor ServiceRecorder {
    struct Call {
        let domain: String
        let service: String
        let data: [String: JSONValue]
    }

    private(set) var calls: [Call] = []
    var count: Int { calls.count }

    func record(domain: String, service: String, data: [String: JSONValue]) {
        calls.append(Call(domain: domain, service: service, data: data))
    }
}

private actor HoldingServiceRecorder {
    struct Call {
        let domain: String
        let service: String
        let entityID: String
        var route: String { "\(domain).\(service)" }
    }

    private(set) var calls: [Call] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false
    var count: Int { calls.count }

    func recordAndWait(domain: String, service: String, data: [String: JSONValue]) async {
        guard case let .string(entityID)? = data["entity_id"] else { return }
        calls.append(Call(domain: domain, service: service, entityID: entityID))
        guard !released else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func releaseAll() {
        released = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}
