import XCTest
@testable import NativeHACore
@testable import NativeHAMac

@MainActor
final class DashboardServiceControllerTests: XCTestCase {
    func testOptimisticServiceStateReconstructionPreservesAcceptedContext() {
        let context = HAContext(
            id: "context-id",
            parentID: "parent-id",
            userID: "user-id"
        )
        let original = HAState(
            entityId: "switch.context",
            state: "off",
            attributes: ["friendly_name": .string("Context switch")],
            context: context,
            lastChanged: "2026-08-26T12:00:00.000Z",
            lastUpdated: "2026-08-26T12:00:01.000Z"
        )
        let model = DashboardViewModel(initialStates: [original.entityId: original])
        model.installServiceCallerForTesting { _, _, _ in }

        model.setPower(entityID: original.entityId, isOn: true)

        let optimistic = model.states[original.entityId]
        XCTAssertEqual(optimistic?.state, "on")
        XCTAssertEqual(optimistic?.attributes, original.attributes)
        XCTAssertEqual(optimistic?.context, context)
        XCTAssertEqual(optimistic?.lastChanged, original.lastChanged)
        XCTAssertEqual(optimistic?.lastUpdated, original.lastUpdated)
    }

    func testCanInvokeRequiresInstalledCallerAndStopRejectsRetainedStateAction() async {
        let recorder = ServiceCallRecorder()
        let controller = DashboardServiceController()
        let retained = HAState(entityId: "switch.retained", state: "off")

        XCTAssertFalse(controller.canInvoke(
            entityID: retained.entityId,
            state: retained,
            domain: "switch",
            service: "turn_on"
        ))
        XCTAssertFalse(controller.invoke(
            entityID: retained.entityId,
            domain: "switch",
            service: "turn_on",
            data: ["entity_id": .string(retained.entityId)],
            errorContext: "must not emit without caller"
        ))

        controller.install { domain, service, data in
            await recorder.append(domain: domain, service: service, data: data)
        }
        XCTAssertTrue(controller.canInvoke(
            entityID: retained.entityId,
            state: retained,
            domain: "switch",
            service: "turn_on"
        ))

        let detached = controller.stopSynchronously()
        XCTAssertFalse(controller.canInvoke(
            entityID: retained.entityId,
            state: retained,
            domain: "switch",
            service: "turn_on"
        ))
        XCTAssertFalse(controller.invoke(
            entityID: retained.entityId,
            domain: "switch",
            service: "turn_on",
            data: ["entity_id": .string(retained.entityId)],
            errorContext: "must not emit after stop"
        ))
        for task in detached { await task.value }
        XCTAssertEqual(controller.inFlightCount, 0)
        let calls = await recorder.snapshot()
        XCTAssertTrue(calls.isEmpty)
    }

    func testMissingUnavailableAndDuplicateActionAreDisabled() async throws {
        let recorder = ServiceCallRecorder()
        let gate = ServiceCallGate()
        let controller = DashboardServiceController()
        controller.install { domain, service, data in
            await recorder.append(domain: domain, service: service, data: data)
            await gate.wait()
        }
        let available = HAState(entityId: "switch.one", state: "off")
        XCTAssertFalse(controller.canInvoke(
            entityID: "switch.one", state: nil, domain: "switch", service: "turn_on"
        ))
        XCTAssertFalse(controller.canInvoke(
            entityID: "switch.one",
            state: HAState(entityId: "switch.one", state: "unavailable"),
            domain: "switch",
            service: "turn_on"
        ))
        XCTAssertTrue(controller.canInvoke(
            entityID: "switch.one", state: available, domain: "switch", service: "turn_on"
        ))

        XCTAssertTrue(controller.invoke(
            entityID: "switch.one",
            domain: "switch",
            service: "turn_on",
            data: ["entity_id": .string("switch.one")],
            errorContext: "failed"
        ))
        XCTAssertFalse(controller.invoke(
            entityID: "switch.one",
            domain: "switch",
            service: "turn_on",
            data: ["entity_id": .string("switch.one")],
            errorContext: "failed"
        ))
        XCTAssertFalse(controller.canInvoke(
            entityID: "switch.one", state: available, domain: "switch", service: "turn_off"
        ))
        XCTAssertFalse(controller.invoke(
            entityID: "switch.one",
            domain: "switch",
            service: "turn_off",
            data: ["entity_id": .string("switch.one")],
            errorContext: "opposite failed"
        ), "Opposite power actions for one entity are incompatible and must not overlap")
        XCTAssertEqual(controller.inFlightCount, 1)
        await gate.release()
        try await waitForServiceCondition { controller.inFlightCount == 0 }
        let calls = await recorder.snapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "switch")
        XCTAssertEqual(calls.first?.1, "turn_on")
        XCTAssertEqual(calls.first?.2, ["entity_id": .string("switch.one")])
        XCTAssertTrue(controller.canInvoke(
            entityID: "switch.one", state: available, domain: "switch", service: "turn_off"
        ))
    }

    func testFailureIsOwnedAndStopRejectsLateCompletionWithoutRetry() async throws {
        let recorder = ServiceCallRecorder()
        let failureController = DashboardServiceController()
        failureController.install { domain, service, data in
            await recorder.append(domain: domain, service: service, data: data)
            throw URLError(.timedOut)
        }
        XCTAssertTrue(failureController.invoke(
            entityID: "fan.one",
            domain: "fan",
            service: "set_percentage",
            data: ["entity_id": .string("fan.one"), "percentage": .int(50)],
            errorContext: "Fan speed failed"
        ))
        try await waitForServiceCondition { failureController.inFlightCount == 0 }
        XCTAssertTrue(failureController.errorMessage?.contains("Fan speed failed") == true)
        let failedCalls = await recorder.snapshot()
        XCTAssertEqual(failedCalls.count, 1, "A failure must never schedule an automatic retry")

        let gate = ServiceCallGate()
        let stoppedController = DashboardServiceController()
        var completionCount = 0
        stoppedController.install { _, _, _ in await gate.wait() }
        XCTAssertTrue(stoppedController.invoke(
            entityID: "switch.late",
            domain: "switch",
            service: "turn_off",
            data: ["entity_id": .string("switch.late")],
            errorContext: "late"
        ) { _ in completionCount += 1 })
        let detached = stoppedController.stopSynchronously()
        XCTAssertEqual(stoppedController.inFlightCount, 0)
        await gate.release()
        for task in detached { await task.value }
        XCTAssertEqual(completionCount, 0)
    }
}

private actor ServiceCallRecorder {
    private var calls: [(String, String, [String: JSONValue])] = []
    func append(domain: String, service: String, data: [String: JSONValue]) {
        calls.append((domain, service, data))
    }
    func snapshot() -> [(String, String, [String: JSONValue])] { calls }
}

private actor ServiceCallGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func waitForServiceCondition(
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<100_000 {
        if condition() { return }
        await Task.yield()
    }
    throw URLError(.timedOut)
}
