# Module 02: WebSocket Client Multiplexer And Subscription Architecture

> **Status: complete within the verified packet scope.** The
> [Module 02 evidence packet](../reference-context/modules/module-02-websocket-multiplexer.md)
> records implemented contracts, validation, and deferred work. The original
> findings, architecture sketches, task lists, and acceptance checklist below
> are historical planning, not a fresh code audit or remaining-work checklist.
> Preserve the packet contracts; verify current code before reopening work.

Original Claude module: `2. WebSocket Client: Multiplexer / Subscription Architecture`.

Original priority: critical. This must land before module 01 and before any weather forecast or markdown template subscription work.

## Goal

Replace the original single-purpose WebSocket client with a safe connection layer that has exactly one receive loop per socket, dispatches command responses by message ID, dispatches subscription payloads by subscription ID, supports unsubscribe, and cleans up pending continuations on disconnect/cancel.

## Historical Findings Before Rescue

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:11` is a simple `final class` with mutable `task` and `nextID`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:22` connects and authenticates by reading directly from `receiveDictionary()`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:58` fetches Lovelace with `sendCommand`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:63` subscribes to `state_changed` by calling `sendCommand`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:70` then enters `receiveStateChanges`, which directly loops on `receiveDictionary()`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:88` implements `sendCommand` by sending a command and then directly reading from the WebSocket until it sees the matching ID.
- There is no pending command map, no subscription callback map, no unsubscribe method, no command timeout, no reconnect strategy, and no continuation cleanup.

Historical failure mode, repaired by Module 02: if `receiveStateChanges` is running while another command is sent, both are reading from the same `URLSessionWebSocketTask`. Either consumer can steal the other's message. This breaks concurrent command/subscription use and will break module 01.

## Reference Findings

- hass-frontend calls a shared connection abstraction, not raw per-feature receives. Examples:
  - `hass.callWS(...)` in `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/types.ts:31`
  - `hass.connection.subscribeMessage(...)` in `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:292`
  - `connection.subscribeMessage(...)` in `/Users/jin/Documents/HA/hass-frontend/src/data/weather.ts:704`
- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:281` wraps subscription reconnect behavior around the shared connection and returns an unsubscribe function.
- Home Assistant WebSocket commands are ID-based. Subscription commands also use IDs; later event payloads are correlated with the subscription ID.

## Target Architecture

Use an actor-backed connection core so all mutable WebSocket state is serialized:

```swift
public actor HomeAssistantWebSocketConnection {
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextID = 1
    private var pendingCommands: [Int: PendingCommand] = [:]
    private var subscriptions: [Int: Subscription] = [:]
}
```

Expose a small public API from `NativeHACore`:

- `connect() async throws`
- `disconnect() async`
- `call<T: Decodable>(_ message: [String: JSONValue], as: T.Type) async throws -> T`
- `callRaw(_ message: [String: JSONValue]) async throws -> JSONValue`
- `subscribeMessage<T: Decodable>(_ message: [String: JSONValue], onMessage: @escaping @Sendable (T) async -> Void) async throws -> HAWebSocketSubscription`
- `subscribeEvents(eventType:onEvent:)` as a convenience wrapper over `subscribeMessage`

`HAWebSocketSubscription` should have:

- `id`: original subscription command ID
- `cancel() async`: sends an unsubscribe command once and removes callback locally
- automatic cleanup if the socket disconnects

Message handling:

- Authentication can read directly until `auth_ok`, before starting the steady-state receive loop.
- After auth succeeds, start exactly one receive loop.
- The receive loop decodes each JSON message and hands it to the actor for dispatch.
- `type == "result"` with `id` resolves the pending command if present.
- Subscription messages with `id` dispatch to the matching subscription callback. Normalize payloads so feature code does not need to know whether Home Assistant wrapped data in `event`.
- Unknown IDs should be ignored or logged without crashing.
- Any socket error should fail all pending commands, notify or cancel all subscriptions, and mark the connection disconnected.

## Detailed Implementation Tasks

1. Define JSON message models.
   - Prefer `Codable` structs using `JSONValue` payloads over `[String: Any]`.
   - Add `HomeAssistantWebSocketMessage` with fields `id`, `type`, `success`, `result`, `error`, `event`, and a raw object fallback.
   - Add `HAWebSocketCommandError` with Home Assistant error code/message when available.

2. Centralize ID allocation.
   - Allocate IDs only inside the actor.
   - Ensure command and subscription IDs share the same monotonically increasing counter.
   - Never increment `nextID` outside actor isolation.

3. Implement send serialization.
   - Use `JSONEncoder` or `JSONSerialization` consistently from `JSONValue`.
   - Include `id` and `type` in every command after auth.
   - Follow `LoggingPolicy`: subsystem/severity filtering controls selection; persist every selected diagnostic in full, including frames when WebSocket debug logging is enabled.

4. Implement `callRaw`.
   - Register a pending continuation before sending.
   - Send the command.
   - Await matching `result`.
   - Accept `success: true` with absent/null result for subscription acks.
   - On `success: false`, throw with server error message/code.
   - On task cancellation, remove the pending command and do not resume twice.
   - Add a reasonable timeout using `configuration.timeout` or an explicit command timeout.

5. Implement `subscribeMessage`.
   - Register the subscription callback before or immediately after successful subscribe ack, depending on message ordering observed in tests.
   - Return a cancellation handle that sends `type: "unsubscribe_events"` with `subscription: <original subscription id>` unless Home Assistant requires a different unsubscribe type for the subscription command. Keep the unsubscribe mapping centralized for future non-event subscription commands.
   - Remove the subscription locally even if server unsubscribe fails after disconnect.
   - Preserve the implemented bounded per-subscription queues and connection-wide callback limit. Unbounded child tasks are not an acceptable replacement.

6. Port existing app calls.
   - `fetchLovelaceConfig()` becomes a thin `call` wrapper for `type: "lovelace/config"`.
   - The original state-change API was superseded; current Module 05 app state uses the typed `subscribe_entities` owner. Preserve that path rather than restoring the old event subscription.
   - DashboardViewModel should keep the returned subscription token and cancel on teardown/reconnect.

7. Add reconnect boundaries.
   - Preserve verified reconnect/status/resubscription behavior, including Module 01 fresh history accumulators; the old disconnect-only minimum is superseded.
   - Do not silently reuse stale subscriptions after reconnect unless the subscription owner rebuilds its request.

8. Add lifecycle cleanup.
   - `disconnect()` cancels receive task, cancels WebSocket task, fails pending commands, removes subscriptions, and marks state disconnected.
   - `deinit` should call a non-async cleanup path or require explicit disconnect by owner.

## File Ownership And Scope

Likely files to edit in future implementation:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift`
- Optional new `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketConnection.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/JSONValue.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- Tests under `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHACoreTests/`

Out of scope:

- OAuth/native-app registration.
- Service-call migration from REST to WebSocket.
- Module 01 history stream feature logic beyond adding the generic subscription primitive.

## Tests And Verification

Follow the shared test-method guidance in [`../visual-testing.md`](../visual-testing.md), especially its macOS 12/Xcode 13.4.1 performance limits. This module is a transport primitive with no direct visual output, so card snapshots, visual references, and animation keyframes are deliberately unnecessary. Its correctness must be proved at the routing and lifecycle boundaries instead.

### Unit tests

Add `Tests/NativeHACoreTests/HomeAssistantWebSocketConnectionTests.swift`. Put a small send/receive protocol in front of `URLSessionWebSocketTask` and drive it with a scripted fake transport; the default suite must not contact a server or use credentials. Keep complete sent-message and callback-delivery logs in the fake so tests can assert ordering without relying on real-time sleeps.

Cover at least:

- Authentication accepts the `auth_required` -> auth send -> `auth_ok` sequence, rejects `auth_invalid`, and does not start more than one steady-state receive loop.
- `callRaw` allocates unique, monotonically increasing IDs; concurrent calls resolve correctly when results arrive in or out of order; `success: true` with null/absent `result` is accepted where the command contract permits it.
- Command failures retain the Home Assistant error code/message without requiring full request-payload dumps.
- Subscription acknowledgement and early-event ordering are both safe. An event can arrive while a command is in flight, but command responses never reach callbacks and subscription events are never swallowed by command waits.
- Subscription payload variants used by `subscribe_events`, `history/stream`, and `weather/subscribe_forecast` normalize according to their tested envelopes rather than assuming every payload is under `event`.
- `cancel()` is idempotent, emits the centralized unsubscribe command exactly once, removes callback storage even if the socket is already gone, and ignores a late event.
- Command-task cancellation removes and resumes its continuation exactly once; timeout, send failure, malformed JSON, unknown ID, unsupported frame type, and disconnect each take a controlled path.
- Disconnect fails every pending command once, terminates subscriptions, drops callback storage, and leaves a late response harmless. A reconnect uses a fresh receive loop and IDs/subscriptions according to the documented reconnect policy; it must not silently replay stale history subscriptions.

### Integration and stress tests

Add `Tests/NativeHACoreTests/HomeAssistantWebSocketMultiplexerStressTests.swift` using deterministic prebuilt message scripts:

- Route 10,000 interleaved results/events across at least 250 concurrent command and subscription IDs, then assert per-ID ordering, exact delivery counts, and a checksum of consumed payloads.
- Stall one subscriber behind a bounded continuation while other subscribers and command responses continue. Assert that the slow subscriber cannot block the socket receive loop, corrupt order within another subscriber, or cause cross-ID delivery. The chosen overflow/back-pressure behavior for the slow subscriber must itself be asserted.
- Exercise unsubscribe racing with an in-flight callback, task cancellation racing with a result, socket failure during send, and 100 disconnect/reconnect cycles. Use bounded expectations or polling, not long arbitrary sleeps.

After module 05 owns visible connection state, a single `@MainActor` downstream smoke test may be added under `NativeHAMacTests` (likely `DashboardWebSocketLifecycleTests.swift`) to prove that a fake reconnect reaches `DashboardViewModel` and creates only one replacement state/history subscription. It should assert model state and fake-transport counts; a dashboard PNG is not needed to test low-level dispatch.

### GUI rendering and animation

None. The multiplexer owns no pixels or animation, so its tests should not produce PNGs or visual baselines. Do not use screenshots as evidence of routing, ordering, cancellation, or duplicate prevention. If a later reconnect banner requires visual coverage, that belongs to the dashboard-state module and must use the offscreen AppKit method in `../visual-testing.md`.

### Performance and lifecycle

Add XCTest measurements to `HomeAssistantWebSocketMultiplexerStressTests.swift` with fixture construction outside the measured block and a checksum/count consumed inside it so the optimizer cannot remove the work:

- Measure warm dispatch of the predecoded 10,000-message/250-subscription script separately from JSON decoding and cold connection/authentication setup.
- Measure end-to-end decode plus dispatch for a serialized 10,000-message script, callback allocation behavior, and incremental batches while subscriptions already exist.
- Measure 100 reconnect cycles and repeated subscribe/cancel cycles separately; after draining tasks, assert pending-continuation, receive-loop, and callback-storage counts return to zero and retained memory does not grow monotonically.
- Use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, warm the dispatch path before warm measurements, and prefer stored XCTest baselines. Any hard-coded safety ceiling must be deliberately loose and documented.

Xcode 13.4.1 does not expose `XCTHitchMetric`; event-to-frame hitch testing is neither useful nor required for this nonvisual module. Signpost metrics should be added only if dispatch is instrumented with a meaningful interval.

### Manual QA

- Start the app and verify Lovelace config loads while state changes and history subscriptions are active.
- Trigger another WebSocket command and a reconnect while state changes flow; verify there is no stalled UI, cross-delivery, or duplicate state/history update.
- Close the app and verify no receive task prevents process exit. Manual observation supplements, but does not replace, fake-transport counts and lifecycle assertions.

## Risks

- Callback reentrancy can deadlock if callbacks call back into the same actor synchronously. Keep callbacks outside actor isolation.
- Resuming continuations more than once will crash. Pending command removal must be atomic inside the actor.
- Treating all subscription messages as `event` may break `history/stream` or `weather/subscribe_forecast` if their payloads differ. Normalize at the connection layer with tests.
- A reconnect layer that auto-replays stale history subscriptions will conflict with hass-frontend's explicit fresh-stream behavior.
- An overly synchronous fake can hide receive/cancel races. The scripted transport must support independently suspended send, receive, and callback delivery, with bounded deterministic release points.
- Unbounded child tasks can make a slow subscriber look isolated while creating memory growth or reordering. Stress tests must assert the selected queue/back-pressure contract and cleanup.
- Tight wall-clock assertions will be machine-dependent. Store XCTest baselines and use deterministic delivery counts as the primary correctness signal.

## Acceptance Criteria

- There is exactly one steady-state receive loop per WebSocket task.
- Multiple concurrent `call` operations work reliably.
- State-change subscription and arbitrary commands can run concurrently.
- Subscription owners receive an unsubscribe handle and can clean up.
- Pending commands and subscriptions are cleaned up on disconnect or cancellation.
- Module 01 can be implemented without introducing a second raw receiver.
- The fake-transport suite proves routing, per-subscriber ordering, early-event handling, unsubscribe, cancellation, reconnect, timeout, and controlled malformed-message behavior without network access or credentials.
- The 10,000-message/250-subscription stress fixture has no missing, duplicate, or cross-routed deliveries, including while one subscriber is stalled.
- Wall-clock, CPU, and memory baselines exist for decode/dispatch, warm dispatch, and repeated reconnect/subscription lifecycle work; receive-loop and callback storage return to zero after cleanup.
- No direct GUI snapshot is required for this nonvisual module; any downstream reconnect smoke test asserts exactly one replacement subscription rather than treating a screenshot as lifecycle proof.
