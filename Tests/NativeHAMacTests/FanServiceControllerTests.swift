import XCTest
import NativeHACore
@testable import NativeHAMac

@MainActor
final class FanServiceControllerTests: XCTestCase {
    func testLocalSpeedAndPresetAreIndependentOfAuthoritativeHeaderAndMenus() throws {
        let entity = try FanFixtures.complete()
        let controller = FanServiceController()
        var requests: [FanServiceRequest] = []
        var completions: [(String?) -> Void] = []
        controller.install(entity: entity) { request, completion in
            requests.append(request); completions.append(completion); return true
        }
        controller.percentage(0)
        controller.percentage(75)
        XCTAssertEqual(controller.sliderValue, 75)
        XCTAssertEqual(controller.entity?.header, .percentage(50))
        XCTAssertEqual(controller.entity?.state, entity.state)
        XCTAssertEqual(requests.map { $0.data["percentage"] }, [.double(0), .double(75)])
        completions[0]("obsolete failure")
        XCTAssertNil(controller.error)
        completions[1]("current failure")
        XCTAssertEqual(controller.error, "current failure")
        XCTAssertEqual(controller.sliderValue, 75)
        controller.preset("Custom Night")
        controller.preset("Custom Night")
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(controller.entity?.presetMode, "auto")
        completions[2]("preset failure")
        controller.preset("Custom Night")
        XCTAssertEqual(requests.count, 3, "Failure must not reset duplicate suppression")
        controller.replace(entity)
        controller.preset("Custom Night")
        XCTAssertEqual(requests.count, 4, "Equal replacement resets preset dedup")
        controller.direction(.reverse); controller.direction(.reverse)
        controller.oscillation(true); controller.oscillation(true)
        controller.togglePower(); controller.togglePower()
        XCTAssertEqual(requests.suffix(6).map(\.service), ["set_direction", "set_direction", "oscillate", "oscillate", "turn_off", "turn_off"])
        XCTAssertEqual(controller.entity?.direction, "forward")
        XCTAssertEqual(controller.entity?.oscillating, false)
    }

    func testReplacementInputAndCloseRevokeFailuresWithoutResettingEqualChildBinding() throws {
        let entity = try FanFixtures.complete()
        let controller = FanServiceController()
        var completions: [(String?) -> Void] = []
        controller.install(entity: entity) { _, completion in completions.append(completion); return true }
        controller.percentage(75)
        controller.inputBegan()
        completions[0]("before drag")
        XCTAssertNil(controller.error)
        // A future child owns 63.2 while the owner binding remains 75.
        // An equal authoritative replacement recomputes owner=50, but another
        // equal replacement must not pretend the binding changed a second time.
        controller.replace(entity)
        let oldBinding = controller.sliderValue
        let revision = controller.revision
        controller.inputBegan()
        controller.replace(entity)
        XCTAssertEqual(controller.sliderValue, oldBinding)
        XCTAssertGreaterThan(controller.revision, revision)
        controller.percentage(25)
        controller.replace(entity)
        completions[1]("before replacement")
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.sliderValue, 50)
        controller.percentage(25)
        controller.close()
        controller.install(entity: entity) { _, _ in true }
        completions[2]("before remount")
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.sliderValue, 50)
        controller.close()
        controller.percentage(100)
        XCTAssertNil(controller.entity)
        XCTAssertNil(controller.sliderValue)
    }

    func testDiscreteRepeatsMissingOscillationAndUnavailableCapabilityChanges() {
        let controller = FanServiceController()
        var requests: [FanServiceRequest] = []
        let discrete = FanFixtures.entity(["supported_features": 3, "percentage_step": 33], state: "unknown")
        controller.install(entity: discrete) { request, _ in requests.append(request); return true }
        controller.speed(.off); controller.speed(.high); controller.speed(.high)
        controller.oscillation(false); controller.oscillation(false)
        XCTAssertEqual(requests.prefix(3).map { $0.data["percentage"] }, [.double(0), .double(99), .double(99)])
        XCTAssertEqual(requests.suffix(2).map { $0.data["oscillating"] }, [.bool(false), .bool(false)])
        controller.replace(FanFixtures.entity(state: "unknown"))
        controller.percentage(50); controller.speed(.high); controller.oscillation(true)
        XCTAssertEqual(requests.count, 5)
        controller.power(on: true)
        XCTAssertEqual(requests.count, 6, "Power bits are not required")
        controller.replace(FanFixtures.entity(["supported_features": 63], state: "unavailable"))
        controller.power(on: true); controller.percentage(50); controller.direction(.reverse)
        XCTAssertEqual(requests.count, 6)
        controller.replace(nil)
        controller.togglePower()
        XCTAssertEqual(requests.count, 6)
    }

    func testRawRequestValidationRejectsTypeDomainIdentityExtraKeysAndLostFeatures() throws {
        let fan = try FanFixtures.complete()
        let valid = try XCTUnwrap(FanServiceBuilder.percentage(100, entity: fan))
        XCTAssertTrue(FanServiceBuilder.isSupported(valid, entity: fan))
        var data = valid.data
        for value: JSONValue in [.string("50"), .bool(true), .null, .double(.nan), .double(.infinity), .int(-1), .int(101)] {
            data["percentage"] = value
            XCTAssertFalse(FanServiceBuilder.isSupported(.init(domain: "fan", service: "set_percentage", data: data), entity: fan))
        }
        data = valid.data; data["extra"] = true
        XCTAssertFalse(FanServiceBuilder.isSupported(.init(domain: "fan", service: valid.service, data: data), entity: fan))
        data = valid.data; data["entity_id"] = "fan.other"
        XCTAssertFalse(FanServiceBuilder.isSupported(.init(domain: "fan", service: valid.service, data: data), entity: fan))
        XCTAssertFalse(FanServiceBuilder.isSupported(.init(domain: "climate", service: valid.service, data: valid.data), entity: fan))
        XCTAssertFalse(FanServiceBuilder.isSupported(.init(domain: "fan", service: "toggle", data: valid.data), entity: fan))
        XCTAssertFalse(FanServiceBuilder.isSupported(valid, entity: FanFixtures.entity(id: fan.entityID)))
        for request in [FanServiceBuilder.preset("Custom Night", entity: fan), FanServiceBuilder.direction(.reverse, entity: fan), FanServiceBuilder.oscillation(true, entity: fan), FanServiceBuilder.power(on: true, entity: fan)].compactMap({ $0 }) {
            XCTAssertTrue(FanServiceBuilder.isSupported(request, entity: fan))
        }
        XCTAssertFalse(FanServiceBuilder.isSupported(.init(domain: "fan", service: "oscillate", data: ["entity_id": .string(fan.entityID), "oscillating": "true"]), entity: fan))
    }

    func testModelBridgeKeepsAllCommitsAndStateAuthoritativeWithHeldOutOfOrderResults() async throws {
        let fan = try FanFixtures.complete()
        let model = DashboardViewModel(initialStates: [fan.entityID: fan.state])
        let wire = HeldFanServices()
        model.installServiceCallerForTesting { try await wire.call($0, $1, $2) }
        model.openDetails(entityID: fan.entityID)
        let controller = try XCTUnwrap(model.fanDetailController)
        controller.percentage(0); controller.percentage(25); controller.percentage(100)
        try await waitForFan { await wire.count == 3 }
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 3)
        let calls = await wire.requests
        XCTAssertTrue(calls.allSatisfy { $0.domain == "fan" && $0.service == "set_percentage" })
        XCTAssertEqual(Set(calls.compactMap { $0.data["percentage"]?.doubleValue }), [0, 25, 100])
        XCTAssertEqual(model.states[fan.entityID], fan.state)
        await wire.release(percentage: 100, failure: true)
        try await waitForFan { controller.error != nil }
        let latestError = controller.error
        await wire.release(percentage: 0, failure: true)
        await wire.release(percentage: 25, failure: false)
        try await waitForFan { model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0 }
        XCTAssertEqual(controller.error, latestError)
        XCTAssertEqual(model.lifecycle.components[.service], latestError.map(DashboardComponentPhase.failed))
        XCTAssertEqual(controller.sliderValue, 100)
        XCTAssertEqual(model.states[fan.entityID], fan.state)
        XCTAssertTrue(model.dashboardOwnerSnapshotForTesting().desiredDetailHistoryKeys.isEmpty)
        await model.stop()
    }

    func testModelReplacementInputDismissReopenAndStopSuppressOldCallbacks() async throws {
        let fan = try FanFixtures.complete()
        let model = DashboardViewModel(initialStates: [fan.entityID: fan.state])
        let wire = HeldFanServices()
        model.installServiceCallerForTesting { try await wire.call($0, $1, $2) }
        model.openDetails(entityID: fan.entityID)
        var controller = try XCTUnwrap(model.fanDetailController)
        controller.percentage(10)
        try await waitForFan { await wire.count == 1 }
        controller.inputBegan()
        await wire.release(percentage: 10, failure: true)
        try await waitForFan { model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0 }
        XCTAssertNil(controller.error); XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lifecycle.components[.service], .idle)
        controller.percentage(20)
        try await waitForFan { await wire.count == 2 }
        let revision = model.fanEntityRevision
        model.acceptFanReplacement(entityIDs: [fan.entityID])
        XCTAssertEqual(model.fanEntityRevision, revision + 1)
        XCTAssertEqual(controller.sliderValue, 50)
        await wire.release(percentage: 20, failure: true)
        try await waitForFan { model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0 }
        XCTAssertNil(controller.error); XCTAssertNil(model.errorMessage)
        controller.percentage(30)
        try await waitForFan { await wire.count == 3 }
        let old = controller
        model.closeDetails(); model.openDetails(entityID: fan.entityID)
        controller = try XCTUnwrap(model.fanDetailController)
        XCTAssertFalse(old === controller); XCTAssertNil(old.entity)
        await wire.release(percentage: 30, failure: true)
        try await waitForFan { model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0 }
        XCTAssertNil(controller.error); XCTAssertNil(model.errorMessage)
        controller.percentage(40)
        try await waitForFan { await wire.count == 4 }
        let stopping = Task { await model.stop() }
        try await waitForFan { model.fanDetailController == nil }
        await wire.release(percentage: 40, failure: true)
        await stopping.value
        XCTAssertNil(controller.entity); XCTAssertNil(controller.error)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 0)
        XCTAssertFalse(model.canSetFanPercentage(entityID: fan.entityID, percentage: 50))
    }

    func testModelLegacyZeroUnknownRawValidationAndCurrentCapabilities() async throws {
        let fan = FanFixtures.entity(["supported_features": 1], state: "unknown")
        let model = DashboardViewModel(initialStates: [fan.entityID: fan.state])
        let wire = HeldFanServices()
        model.installServiceCallerForTesting { try await wire.call($0, $1, $2) }
        XCTAssertTrue(model.canSetFanPercentage(entityID: fan.entityID, percentage: 0))
        XCTAssertFalse(model.canSetRowPower(entityID: fan.entityID, isOn: true), "Unknown detail policy must not alter row power")
        model.setFanPercentage(entityID: fan.entityID, percentage: 0)
        model.setFanPercentage(entityID: fan.entityID, percentage: 0)
        try await waitForFan { await wire.count == 2 }
        XCTAssertEqual(model.states[fan.entityID], fan.state)
        model.openDetails(entityID: fan.entityID)
        let controller = try XCTUnwrap(model.fanDetailController)
        let request = try XCTUnwrap(FanServiceBuilder.percentage(25, entity: fan))
        model.states[fan.entityID] = FanFixtures.entity(id: fan.entityID).state
        XCTAssertFalse(model.invokeFan(request, entityID: fan.entityID, completion: { _ in XCTFail() }))
        controller.percentage(25)
        XCTAssertEqual(model.dashboardOwnerSnapshotForTesting().serviceTaskCount, 2)
        model.states.removeValue(forKey: fan.entityID)
        XCTAssertNil(controller.entity)
        XCTAssertFalse(model.canSetFanPercentage(entityID: fan.entityID, percentage: 0))
        await wire.releaseAll()
        await model.stop()
    }

    func testHundredDetailCyclesRetireControllersWithoutHistoryOwnersOrLateFailures() async throws {
        let first = try FanFixtures.complete()
        let second = FanFixtures.entity(["supported_features": 1], id: "fan.fixture_second")
        let model = DashboardViewModel(initialStates: [first.entityID: first.state, second.entityID: second.state])
        let wire = HeldFanServices()
        model.installServiceCallerForTesting { try await wire.call($0, $1, $2) }
        for index in 0..<100 {
            model.openDetails(entityID: index % 2 == 0 ? first.entityID : second.entityID)
            weak var retired = model.fanDetailController
            retired?.percentage(Double(index))
            try await waitForFan { await wire.count == index + 1 }
            model.closeDetails()
            XCTAssertNil(retired, "Service completions must not retain a detail controller")
        }
        model.openDetails(entityID: second.entityID)
        let newest = try XCTUnwrap(model.fanDetailController)
        for index in 0..<100 { await wire.release(percentage: Double(index), failure: true) }
        try await waitForFan { model.dashboardOwnerSnapshotForTesting().serviceTaskCount == 0 }
        XCTAssertNil(newest.error); XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lifecycle.components[.service], .idle)
        let owners = model.dashboardOwnerSnapshotForTesting()
        XCTAssertTrue(owners.desiredDetailHistoryKeys.isEmpty)
        XCTAssertTrue(owners.detailSubscriptionKeys.isEmpty)
        XCTAssertTrue(owners.detailGenerationKeys.isEmpty)
        XCTAssertEqual(owners.detailStartupCount, 0)
        await model.stop()
    }

    func testSharedServiceOwnerRetiresRejectedCompletionWithoutPublishingError() async throws {
        let service = DashboardServiceController()
        let wire = HeldFanServices()
        service.install { try await wire.call($0, $1, $2) }
        var accepts = true
        var callbackCount = 0
        XCTAssertTrue(service.invoke(entityID: "fan.fixture_service", domain: "fan", service: "set_percentage",
            data: ["percentage": 1], errorContext: "obsolete", admission: .fanDetail,
            completionAuthority: .init(accepts: { accepts })) { _ in callbackCount += 1 })
        try await waitForFan { await wire.count == 1 }
        accepts = false
        await wire.release(percentage: 1, failure: true)
        try await waitForFan { service.inFlightCount == 0 }
        XCTAssertNil(service.errorMessage)
        XCTAssertEqual(callbackCount, 0)
    }
}

private actor HeldFanServices {
    private(set) var requests: [FanServiceRequest] = []
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    var count: Int { requests.count }
    func call(_ domain: String, _ service: String, _ data: [String: JSONValue]) async throws {
        let id = requests.count
        requests.append(.init(domain: domain, service: service, data: data))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store(continuation, id: id)
        }
    }
    private func store(_ continuation: CheckedContinuation<Void, Error>, id: Int) { continuations[id] = continuation }
    func release(percentage: Double, failure: Bool) {
        guard let id = requests.indices.first(where: { requests[$0].data["percentage"]?.doubleValue == percentage && continuations[$0] != nil }), let continuation = continuations.removeValue(forKey: id) else { return }
        if failure { continuation.resume(throwing: URLError(.timedOut)) }
        else { continuation.resume() }
    }
    func releaseAll() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private extension JSONValue {
    var doubleValue: Double? {
        switch self {
        case let .int(value): return Double(value)
        case let .double(value): return value
        default: return nil
        }
    }
}

@MainActor
private func waitForFan(_ condition: @escaping @MainActor () async -> Bool) async throws {
    for _ in 0..<100_000 {
        if await condition() { return }
        await Task.yield()
    }
    throw URLError(.timedOut)
}
