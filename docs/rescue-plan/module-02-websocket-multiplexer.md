# Module 02: WebSocket Client Multiplexer And Subscription Architecture

Original Claude module: `2. WebSocket Client: Multiplexer / Subscription Architecture`.

Priority: critical. This must land before module 01 and before any weather forecast or markdown template subscription work.

## Goal

Replace the current single-purpose WebSocket client with a safe connection layer that has exactly one receive loop per socket, dispatches command responses by message ID, dispatches subscription payloads by subscription ID, supports unsubscribe, and cleans up pending continuations on disconnect/cancel.

## Confirmed Current-Code Findings

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:11` is a simple `final class` with mutable `task` and `nextID`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:22` connects and authenticates by reading directly from `receiveDictionary()`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:58` fetches Lovelace with `sendCommand`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:63` subscribes to `state_changed` by calling `sendCommand`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:70` then enters `receiveStateChanges`, which directly loops on `receiveDictionary()`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift:88` implements `sendCommand` by sending a command and then directly reading from the WebSocket until it sees the matching ID.
- There is no pending command map, no subscription callback map, no unsubscribe method, no command timeout, no reconnect strategy, and no continuation cleanup.

Confirmed failure mode: if `receiveStateChanges` is running while another command is sent, both are reading from the same `URLSessionWebSocketTask`. Either consumer can steal the other's message. This breaks concurrent command/subscription use and will break module 01.

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
   - Avoid printing tokens or full payloads that may contain secrets.

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
   - Ensure callback delivery does not block the receive loop. Dispatch callbacks in child `Task`s or through a controlled async queue.

6. Port existing app calls.
   - `fetchLovelaceConfig()` becomes a thin `call` wrapper for `type: "lovelace/config"`.
   - `subscribeToStateChanges()` and `receiveStateChanges(...)` collapse into one `subscribeEvents(eventType: "state_changed", onEvent:)`.
   - DashboardViewModel should keep the returned subscription token and cancel on teardown/reconnect.

7. Add reconnect boundaries.
   - Minimum acceptable: fail pending commands and surface `Disconnected` without message stealing.
   - Preferred: expose connection status events and allow higher-level managers to reconnect and resubscribe. Module 01 requires fresh history accumulators after reconnect.
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

Unit tests with a fake WebSocket transport are strongly recommended. If `URLSessionWebSocketTask` is hard to fake, introduce a small protocol around send/receive.

Test cases:

- Auth handshake succeeds only after `auth_required`, auth send, and `auth_ok`.
- `callRaw` sends unique IDs and resolves responses out of order.
- Two concurrent commands both receive the correct results.
- A subscription receives events while a command is in flight.
- A command response is not delivered to a subscription callback.
- A subscription event is not swallowed by a pending command wait.
- Unsubscribe sends the expected command and removes callback.
- Disconnect fails all pending commands exactly once.
- Cancellation of a command removes its continuation and later response is ignored.
- Invalid JSON or unsupported WebSocket message type produces a controlled error.

Manual QA:

- Start app, verify Lovelace config loads.
- State changes continue to update rows while history subscriptions are active.
- Trigger a refresh or another WebSocket command while state changes are flowing; no disconnection or stalled UI.
- Close the app and ensure no hanging receive task prevents process exit.

## Risks

- Callback reentrancy can deadlock if callbacks call back into the same actor synchronously. Keep callbacks outside actor isolation.
- Resuming continuations more than once will crash. Pending command removal must be atomic inside the actor.
- Treating all subscription messages as `event` may break `history/stream` or `weather/subscribe_forecast` if their payloads differ. Normalize at the connection layer with tests.
- A reconnect layer that auto-replays stale history subscriptions will conflict with hass-frontend's explicit fresh-stream behavior.

## Acceptance Criteria

- There is exactly one steady-state receive loop per WebSocket task.
- Multiple concurrent `call` operations work reliably.
- State-change subscription and arbitrary commands can run concurrently.
- Subscription owners receive an unsubscribe handle and can clean up.
- Pending commands and subscriptions are cleaned up on disconnect or cancellation.
- Module 01 can be implemented without introducing a second raw receiver.

