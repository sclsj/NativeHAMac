import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class HAEntityStoreTests: XCTestCase {
    func testTenThousandEntityTypedDecodeMetric() throws {
        let data = try tenThousandEntityData()
        var decodedCount = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let payload = try! JSONDecoder().decode(HAEntitySubscriptionPayload.self, from: data)
            decodedCount = payload.additions?.count ?? 0
        }
        XCTAssertEqual(decodedCount, 10_000)
    }

    func testTenThousandEntityPreparationMetric() throws {
        let data = try tenThousandEntityData()
        let payload = try JSONDecoder().decode(HAEntitySubscriptionPayload.self, from: data)
        var preparedCount = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            var store = HAEntityStore()
            preparedCount = store.apply(payload, authoritative: true).snapshot.count
        }
        XCTAssertEqual(preparedCount, 10_000)
    }

    private func tenThousandEntityData() throws -> Data {
        let additions = Dictionary(uniqueKeysWithValues: (0..<10_000).map { index in
            ("sensor.\(index)", JSONValue.object([
                "s": .string("\(index)"),
                "a": .object(["value": .int(index)]),
                "c": .string("context-\(index)"),
                "lc": .double(Double(1_700_000_000 + index)),
            ]))
        })
        return try JSONEncoder().encode(JSONValue.object(["a": .object(additions)]))
    }

    func testAuthoritativeSnapshotAndOrderedAddRemoveChange() throws {
        var store = HAEntityStore(snapshot: [
            "sensor.obsolete": HAState(entityId: "sensor.obsolete", state: "old"),
        ])
        let context = HACompressedContext.object(
            HAContext(id: "ctx-1", parentID: "parent", userID: "user")
        )
        let full = HAEntitySubscriptionPayload(additions: [
            "sensor.one": HACompressedEntityState(
                state: "1",
                attributes: ["keep": .int(1), "remove": .bool(true)],
                context: context,
                lastChanged: 1_700_000_000,
                lastUpdated: 1_700_000_001
            ),
        ])

        let first = store.apply(full, authoritative: true)
        XCTAssertNil(first.snapshot["sensor.obsolete"])
        XCTAssertEqual(first.snapshot["sensor.one"]?.context, context.value)
        XCTAssertEqual(first.snapshot["sensor.one"]?.lastChanged, "2023-11-14T22:13:20.000Z")
        XCTAssertEqual(first.snapshot["sensor.one"]?.lastUpdated, "2023-11-14T22:13:21.000Z")

        let replacement = HACompressedEntityState(
            state: "replacement",
            attributes: [:],
            context: .id("replacement-context"),
            lastChanged: 1_700_000_002
        )
        let delta = HAEntitySubscriptionPayload(
            additions: ["sensor.ordered": replacement],
            removals: ["sensor.ordered"],
            changes: [
                "sensor.one": HACompressedEntityChange(
                    additions: HACompressedEntityPatch(
                        state: "2",
                        attributes: ["added": .string("yes")],
                        context: .id("ctx-2"),
                        lastChanged: 1_700_000_003
                    ),
                    removals: HACompressedEntityPatchRemoval(attributes: ["remove"])
                ),
                "sensor.ordered": HACompressedEntityChange(
                    additions: HACompressedEntityPatch(state: "must-not-exist")
                ),
            ]
        )
        let second = store.apply(delta, authoritative: false)
        XCTAssertNil(second.snapshot["sensor.ordered"], "add then remove then change must ignore the final unknown patch")
        XCTAssertEqual(second.unknownChangedEntityIDs, ["sensor.ordered"])
        XCTAssertEqual(second.snapshot["sensor.one"]?.state, "2")
        XCTAssertEqual(second.snapshot["sensor.one"]?.attributes["keep"], .int(1))
        XCTAssertEqual(second.snapshot["sensor.one"]?.attributes["added"], .string("yes"))
        XCTAssertNil(second.snapshot["sensor.one"]?.attributes["remove"])
        XCTAssertEqual(second.snapshot["sensor.one"]?.context, HAContext(id: "ctx-2", parentID: "parent", userID: "user"))
        XCTAssertEqual(second.snapshot["sensor.one"]?.lastChanged, "2023-11-14T22:13:23.000Z")
        XCTAssertEqual(second.snapshot["sensor.one"]?.lastUpdated, "2023-11-14T22:13:23.000Z")
    }

    func testLastUpdatedOnlyDoesNotChangeLastChanged() {
        var store = HAEntityStore()
        _ = store.apply(
            HAEntitySubscriptionPayload(additions: [
                "sensor.time": HACompressedEntityState(
                    state: "one",
                    attributes: [:],
                    context: .id("context"),
                    lastChanged: 1_700_000_000
                ),
            ]),
            authoritative: true
        )
        let result = store.apply(
            HAEntitySubscriptionPayload(changes: [
                "sensor.time": HACompressedEntityChange(
                    additions: HACompressedEntityPatch(lastUpdated: 1_700_000_100)
                ),
            ]),
            authoritative: false
        )
        XCTAssertEqual(result.snapshot["sensor.time"]?.lastChanged, "2023-11-14T22:13:20.000Z")
        XCTAssertEqual(result.snapshot["sensor.time"]?.lastUpdated, "2023-11-14T22:15:00.000Z")
    }

    func testPartialContextObjectPatchMergesPresentFieldsAndPreservesOrClearsOthers() throws {
        var store = HAEntityStore()
        _ = store.apply(
            HAEntitySubscriptionPayload(additions: [
                "sensor.context": HACompressedEntityState(
                    state: "one",
                    attributes: [:],
                    context: .object(HAContext(id: "old-id", parentID: "old-parent", userID: "old-user")),
                    lastChanged: 1_700_000_000
                ),
            ]),
            authoritative: true
        )

        let partialData = Data(#"{"c":{"sensor.context":{"+":{"c":{"parent_id":"new-parent"}}}}}"#.utf8)
        let partial = try JSONDecoder().decode(HAEntitySubscriptionPayload.self, from: partialData)
        let merged = store.apply(partial, authoritative: false)
        XCTAssertEqual(
            merged.snapshot["sensor.context"]?.context,
            HAContext(id: "old-id", parentID: "new-parent", userID: "old-user")
        )

        let clearingData = Data(#"{"c":{"sensor.context":{"+":{"c":{"user_id":null}}}}}"#.utf8)
        let clearing = try JSONDecoder().decode(HAEntitySubscriptionPayload.self, from: clearingData)
        let cleared = store.apply(clearing, authoritative: false)
        XCTAssertEqual(
            cleared.snapshot["sensor.context"]?.context,
            HAContext(id: "old-id", parentID: "new-parent", userID: nil)
        )
    }

    func testMalformedPayloadDecodeCannotPartiallyMutateStore() throws {
        let store = HAEntityStore(snapshot: [
            "sensor.stable": HAState(entityId: "sensor.stable", state: "stable"),
        ])
        let before = store
        let malformed = Data(#"{"a":{"sensor.bad":{"s":"bad","a":{},"c":"ctx"}}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HAEntitySubscriptionPayload.self, from: malformed))
        XCTAssertEqual(store.snapshot, before.snapshot)
        XCTAssertEqual(store.revision, before.revision)
    }

    func testTenThousandFullAndOrderedThousandDeltaBurst() {
        let additions = Dictionary(uniqueKeysWithValues: (0..<10_000).map { index in
            ("sensor.\(index)", HACompressedEntityState(
                state: "\(index)",
                attributes: ["value": .int(index)],
                context: .id("c\(index)"),
                lastChanged: Double(1_700_000_000 + index)
            ))
        })
        var store = HAEntityStore()
        let full = store.apply(
            HAEntitySubscriptionPayload(additions: additions),
            authoritative: true
        )
        XCTAssertEqual(full.snapshot.count, 10_000)

        for burst in 0..<10 {
            let changes = Dictionary(uniqueKeysWithValues: (0..<1_000).map { index in
                ("sensor.\(index)", HACompressedEntityChange(
                    additions: HACompressedEntityPatch(state: "b\(burst)-\(index)")
                ))
            })
            _ = store.apply(HAEntitySubscriptionPayload(changes: changes), authoritative: false)
        }
        XCTAssertEqual(store.snapshot.count, 10_000)
        XCTAssertEqual(store.snapshot["sensor.999"]?.state, "b9-999")
        XCTAssertEqual(store.snapshot["sensor.9999"]?.state, "9999")
    }
}
