---
schema: nativeha-evidence/v1
module: "02"
title: WebSocket multiplexer and subscription architecture
plan: ../../rescue-plan/module-02-websocket-multiplexer.md
status: complete
contract_revision: 1
depends_on: []
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 04795558e076661287cabab524b19d3bb3337fa2
graph_file: ../generated/module-02.dependencies.json
graph_fingerprint: 6725be545f291f813a37e122f205aae56cd13af5fcba30a917ab0a020737a474
last_validated: 2026-07-28
---

# Module 02 evidence packet

## Scope delta

This packet confirms the rescue plan's single-receive-loop direction and adds
protocol details found inside `home-assistant-js-websocket@9.6.0`. It corrects
two assumptions in the plan:

- The current reference uniformly unwraps subscription wire messages from
  `message.event`; history and weather do not require different raw envelope
  normalization.
- Generic subscriptions auto-resubscribe by default. History deliberately opts
  out and rebuilds its request and accumulator on each `ready` event.

If NativeHA advertises Home Assistant's `coalesce_messages` supported feature,
it must accept an incoming JSON object or an ordered array of objects.

Implementation is complete in the uncommitted worktree based on NativeHA
`04795558e076661287cabab524b19d3bb3337fa2`. The independent verifier should
review that base plus the Module 02 diff; the frontmatter revision is not a
claim that the worktree implementation has already been committed.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| C02-01 | Connect/authenticate | Send token only after `auth_required`; accept `auth_ok`, reject `auth_invalid`. Optionally negotiate `coalesce_messages: 1` with command ID 1 on supported servers. | Do not start the steady receive loop until authentication succeeds. If coalescing is advertised, decode both object and ordered-array frames. | HF-01, NPM-02, NPM-03 | New connection actor and transport adapter | Scripted auth and coalesced-frame tests |
| C02-02 | Concurrent commands/subscriptions | Commands and subscriptions share one monotonically allocated ID space and exactly one steady socket receiver dispatches by ID. | Register pending state before send; out-of-order results resolve only their owner; unknown results are harmless. | NPM-01, SW-01 | Connection actor pending-command/subscription maps | Concurrent out-of-order/interleaving tests |
| C02-03 | Subscribe and receive event | Install subscription storage before sending. Successful ack retains it; `{type:"event", event:...}` delivers the unwrapped event payload. | Event-before-ack must be safe. Preserve order within a subscription; slow UI work must not block the socket or create unbounded unordered tasks. | HF-02, HF-03, NPM-01 | Typed subscription API plus serial delivery boundary | Early-event and slow-subscriber tests |
| C02-04 | Cancel subscription | Send `unsubscribe_events` with `subscription` equal to the original subscription command ID. | Cancellation is idempotent; remove local callback even after disconnect; late events do not deliver. | NPM-01, NPM-03 | Subscription handle | Exact-wire, repeated-cancel, and late-event tests |
| C02-05 | Failure/disconnect/reconnect | Reject ordinary in-flight commands with connection-lost, clear ownership, and surface lifecycle state. | Never resume a continuation twice. Implement generic automatic resubscription or keep the remaining parity gap explicit and the module non-complete; stale subscriptions must not silently survive. | NPM-01, HF-04 | Connection actor lifecycle/status events | Disconnect races, cleanup counts, reconnect cycles |
| C02-06 | Reconnect history stream | History disables generic resubscribe, listens for `ready`, rebuilds `start_time`, and creates a fresh accumulator. | Disposal removes listener and current subscription. Reconnect failures are contained for the owner to retry. | HF-02 | Module 01 owner using Module 02 status/subscription API | Module 01 fresh-stream test; Module 02 supports `resubscribe:false` or equivalent ownership |
| C02-07 | Command result/error | `success:true` resolves with result, including missing/null where allowed; `success:false` preserves server code/message. | Remove pending storage once; user-facing errors remain concise. Explicitly enabled debug tracing may persist complete wire payloads under the diagnostic policy. | NPM-01 | Command error model and continuation owner | Null result, server error, concise error, cancellation, and timeout tests |

## Source anchors

### hass-frontend at `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`

- **HF-01** — `src/entrypoints/core.ts::connProm`, Git blob
  `e8549e265db44300eddafb4ef3aaf8732655e719`, SHA-256
  `071b4ac3ecedd8adb13a8e677009f586ea05ed8acc28bd7375f0de0bc873e518`.
  Creates the shared package connection.
- **HF-02** — `src/data/history.ts::subscribeHistoryStream`, line hint 281,
  Git blob `5a3c3e8f8fa02c7a081a1ddb0fea875bd40147e2`, SHA-256
  `055be2c7ce23ba96de01948e8af51c1f3c699d0580f7d49c22ffc662eb19470c`.
- **HF-03** — `src/data/weather.ts::subscribeForecast`, line hint 698, Git
  blob `2e126b7f1c28dd9f77028d42abecece7e52c0f72`, SHA-256
  `386d4da61b41951bf15098c5b1d0ba8b301da27b7ed6602b96d4143bed1f514b`.
- **HF-04** — `src/state/connection-mixin.ts::connectionMixin`, especially
  `initializeHass` and `hassConnected` around line hints 54 and 231, Git blob
  `a6b0beefb0b308efd15b71dcf93649577b2af603`, SHA-256
  `ed4c83f57d1d308480daf560b91a13d8309f76a8745c035db35f501cc9a48a8a`.
- Lovelace command anchor — `src/data/lovelace/config/types.ts::fetchConfig`,
  line hint 31, Git blob `3735c8c58b016d1394d27ca53a3276ed0c4fc8c1`.

### npm runtime boundary

Package `home-assistant-js-websocket@9.6.0`, package.json SHA-256
`156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`,
Yarn locator `home-assistant-js-websocket@npm:9.6.0`, checksum
`10/0eded7864632b5e19e92289ffac0e24308b1e8f425e292ae87ed21450852f7705db521e202614b1d5bbdb7948633143dce2524ed548db0c38486b40ed1ffa474`.

- **NPM-01** — `dist/connection.js::Connection`, including `_handleMessage`,
  `_handleClose`, `sendMessagePromise`, and `subscribeMessage`; SHA-256
  `884929a38078cc51cb47b0d7d8a821ef99bc784bcd50792bf9b044f936db69e8`.
- **NPM-02** — `dist/socket.js::createSocket`; SHA-256
  `03211601a595e2bd99dd863cfbf382171e90d57097a317a50a9ea508c828307c`.
- **NPM-03** — `dist/messages.js::supportedFeatures` and
  `unsubscribeEvents`; SHA-256
  `5de87c3bf01207c73424e51a0676705afee7afc2efde7cb8707dfafe709a7b35`.

### NativeHA research baseline at `78a40f22dd278c74af9a81ae47a802fc4a94c1d1`

- **SW-01** — `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`, Git
  blob `2991447a91dd6d92185da8214e4d020a8a2845a2`, SHA-256
  `29530f8cab9c9d4ec7ba98ee082cf9671bc2978007be2a3f45baf87a9cf6132d`.
  `connect` begins around line 22, `receiveStateChanges` around 70,
  `sendCommand` around 88, and `receiveDictionary` around 144. Multiple owners
  directly receive from one socket and mutable IDs are unsynchronized.
- **SW-02** — `Sources/NativeHAMac/DashboardViewModel.swift::load`, line hint
  383, Git blob `37815aac34b736e645e929f586748c2e314d4deb`, SHA-256
  `f19f79bb937660d2128cdfc7dd083b43879d1d722eca9177c1e17ed32a416c16`.
  It fetches config, subscribes, and launches the direct state-change receiver.

## Dependency traces and boundaries

The generated graph is
[`module-02.dependencies.json`](../generated/module-02.dependencies.json),
fingerprint
`6725be545f291f813a37e122f205aae56cd13af5fcba30a917ab0a020737a474`.

- `src/entrypoints/core.ts::connProm` has a runtime package edge. TypeScript
  resolves declarations to `dist/index.d.ts`; package `exports.import` resolves
  actual runtime code to `dist/index.js`, which reaches `connection.js` and
  `socket.js`.
- History, weather, Lovelace config, and `util/websocket.ts` refer to
  `Connection` through type-only edges. That graph cannot identify the method
  implementation, so `connection.js`, `socket.js`, and `messages.js` are
  explicit reviewed seeds.
- Traversal enters only `home-assistant-js-websocket`; other npm packages and
  type-only declarations are recorded boundaries. The current graph has no
  unresolved edges and is not truncated.

## Native mapping

| Contract | Existing/planned Swift path | Symbol/type | Ownership/state | Notes |
|---|---|---|---|---|
| C02-01, C02-02, C02-05, C02-07 | `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift` | `HomeAssistantWebSocketConnection` actor | Socket, ID allocator, pending commands, receive task, lifecycle | Implemented with one steady receiver after auth |
| C02-01 | `Sources/NativeHACore/HomeAssistantWebSocketTransport.swift` | injectable protocol + URLSession adapter | Raw frame send/receive/cancel | Scripted transport suspends send/receive independently |
| C02-03, C02-04 | NativeHACore connection/subscription files | typed subscription handle and connection-wide callback coordinator | Bounded buffers, bounded active callback tasks, original ID, idempotent cancel | Preserve per-subscription order and expose work that ignores cancellation |
| Existing feature facade | `Sources/NativeHACore/HomeAssistantWebSocketClient.swift` | thin Lovelace/state wrappers | No raw receive ownership | Keep call sites small during migration |
| Subscription consumer | `Sources/NativeHAMac/DashboardViewModel.swift` | stored subscription token | Cancel on teardown/reconnect | Remove detached raw receive loop |

## Decisions and native deviations

| ID | Decision/deviation | Allowed reason | Preserved semantics | Test | Status |
|---|---|---|---|---|---|
| D02-01 | Use a Swift actor rather than JavaScript maps/event listeners. | Native concurrency convention | Serialized ID/storage ownership and one receiver | Race/interleaving suite | implemented |
| D02-02 | Add command timeout and cancellation cleanup absent or looser in the JS client. | Native lifecycle safety | Successful/error wire behavior remains identical | Timeout/cancel/disconnect races | implemented |
| D02-03 | Deliver callbacks outside connection-actor isolation through one connection-owned coordinator. It preserves per-owner serial order, bounds buffers, and globally caps active subscriber callbacks at the configured value (four in the app policy). Cancellation requests task cancellation and removes queued/callback ownership immediately; a callback that ignores cancellation remains explicitly owned and counted against the cap until it returns. Termination callbacks use a separate single-task bounded queue. | Performance, reentrancy, and native lifecycle safety | Per-subscription order; no cross-routing, receiver blocking, or monotonic callback-task creation during owner churn | Slow subscriber, gated termination, and eight-owner 2 MiB retention regressions | implemented |
| D02-04 | Keep a logical subscription record across reconnect while assigning it a fresh wire ID; cancellation uses the current wire ID and remains idempotent. | Native ownership convention | Generic subscriptions resubscribe; `resubscribe:false` owners rebuild on `ready` | Reconnect/opt-out/exact-wire tests | implemented |
| D02-05 | The URLSession adapter owns one pending receive continuation behind a lock and explicitly resumes it with `disconnected` during cancel/deinit. Late URLSession callbacks are ignored by receive identity. | Swift 5.6/macOS 12 lifecycle safety | Disconnect remains idempotent and every receive completes exactly once | Non-completing production-task adapter regression and live reconnect/disconnect smoke | implemented |
| D02-06 | Outbound frames synchronously enter a FIFO owned by one physical transport generation. Stopping a generation resolves active and queued tickets without requiring an indefinitely suspended native send to return. | Browser `WebSocket.send` is synchronous while macOS `URLSessionWebSocketTask.send` is completion-based; native lifecycle safety | Actual wire IDs remain monotonic; cancelled/expired work is suppressed; an old generation cannot block or retain its replacement | Suspended-send ordering, queued cancellation, reconnect isolation, and never-returning-send weak-retention regressions | implemented |

## Implementation result

### Actual diff scope

- `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift`: actor-owned
  authentication, IDs, command continuations, subscription records, one
  receiver, lifecycle stream, automatic reconnect/resubscribe, timeout and
  cancellation cleanup, coalesced-frame decoding, and bounded ordered delivery.
- `Sources/NativeHACore/HomeAssistantWebSocketTransport.swift`: injectable raw
  transport and a lock-protected URLSession adapter that owns and exactly-once
  completes its pending receive during disconnect/deinit.
- `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`: thin Lovelace and
  typed state-event facade; it no longer receives directly from the socket.
- `Sources/NativeHAMac/DashboardViewModel.swift`: stores the state subscription,
  observes connection lifecycle, and cancels the subscription/status task and
  connection at teardown.
- `Sources/NativeHAMac/AppConfig.swift` and `docs/configurability.md`: typed
  WebSocket policy for the 10-second command timeout, 256-event per-owner
  delivery capacity, and four active subscriber callbacks per connection.
- `Tests/NativeHACoreTests/HomeAssistantWebSocketConnectionTests.swift`,
  `HomeAssistantWebSocketMultiplexerStressTests.swift`,
  `HomeAssistantWebSocketPerformanceTests.swift`,
  `URLSessionHomeAssistantWebSocketTransportTests.swift`, and
  `ScriptedWebSocketTransport.swift`: deterministic protocol, production
  adapter, race, retention, stress, lifecycle, and split XCTMetric coverage.
- This packet and `docs/reference-context/README.md`: durable verifier handoff.

`docs/user-deviations.md` records the approved native scheduling and lifecycle
mechanisms needed to preserve the reference's observable WebSocket contract.

### Contract evidence

| Contract | Implementation evidence | Deterministic validation | Result |
|---|---|---|---|
| C02-01 | Auth reads directly only until `auth_ok`, then starts one receiver; version-gated feature ID 1 advertises coalescing and object/array frames share one decoder. Concurrent `connect()` calls share one attempt. | Auth required/ok/invalid, feature wire payload, coalesced frame, concurrent-connect receiver-count tests. | pass |
| C02-02 | One actor allocates command and subscription IDs and owns both lookup maps; pending ownership is installed before an asynchronous send. | Concurrent out-of-order calls, unknown ID, interleaved event/result, 250 command plus 250 subscription owner stress; separate 10,000-event warm-predecoded and decode-plus-dispatch XCTMetric fixtures with exact per-iteration count/checksum and constant-size output state. | pass |
| C02-03 | Subscription wire mapping exists before send; the connection-wide coordinator serializes each owner, caps buffered and active work, and receives unwrapped `event`. Overflow reports `deliveryOverflow` and removes only that owner; user termination callbacks never run on the receiver actor. | Event-before-ack, ordered delivery, stalled-owner isolation/overflow, gated non-returning termination, 9,750 exact event deliveries, two waves of eight 2 MiB callback owners proving four-task global retention bound and final zero, and ten subscribe/ack/cancel plus ten reconnect cycles per metric iteration. | pass |
| C02-04 | `HAWebSocketSubscription` keeps the original public ID and logical owner; actor cancellation removes local storage first and sends one unsubscribe for the current wire ID. | Exact unsubscribe wire, repeated cancel, late-event suppression, reconnect cancellation. | pass |
| C02-05 | Receive/send failure atomically fails ordinary pending work, drops wire ownership, emits lifecycle state, reconnects with bounded backoff, and resubscribes generic logical owners. The production adapter explicitly completes a pending receive during disconnect and rejects late callback completion. | Disconnect/send/malformed races, non-completing production-adapter cancel, generic reconnect, 100 reconnect cycles, one receiver per transport, final zero counts, and live URLSession reconnect/disconnect without continuation diagnostics. | pass |
| C02-06 | `resubscribe:false` removes the old owner on disconnect; `statusUpdates()` emits `ready` so Module 01 can rebuild `start_time` and its accumulator. | History opt-out is absent from replacement transport while generic state subscription is recreated. | pass for Module 02 primitive; Module 01 owns the fresh-stream consumer test |
| C02-07 | Result dispatch accepts missing/null success, retains server code/message on failure, and removes continuation ownership once on result/error/timeout/cancel/disconnect. | Null/missing result, concise server error, timeout, task cancellation, send failure, and disconnect cleanup. | pass |

### Independent verification result — 2026-07-17

Verdict: remain `verification-ready`. Deterministic routing is green, and the
read-only live server accepted the interleaved Lovelace, state, history, ping,
reconnect, and unsubscribe flow. Production lifecycle cleanup, non-returning
callback retention, and the required performance split do not yet meet the
packet's completion requirements.

| Contract | Independent evidence | Verdict |
|---|---|---|
| C02-01 | Swift 5.6.1/Xcode 13.4.1 auth, invalid-auth, feature-ID, coalesced-array, and single scripted receiver tests passed. The live connection authenticated and reached `ready` twice. | pass |
| C02-02 | Concurrent/out-of-order command and 10,000-message exact-owner tests passed; live Lovelace and ping commands completed while two subscription kinds shared the connection. The stress test enters through a serialized JSON array, and no separate predecoded warm-dispatch XCTMetric measurement or baseline exists. | routing pass; performance evidence incomplete |
| C02-03 | Early event, per-owner order, 9,750 exact event deliveries, checksum, and bounded-buffer isolation passed. An external read-only live probe then created and canceled eight history owners whose callbacks deliberately never returned: actor counts were `0/0/0`, but all eight captured 2 MiB payloads remained alive (16 MiB total). `HAWebSocketDeliveryQueue.finish()` clears only its buffer and does not own/cancel the unstructured drain task. Overflow and result-failure paths also await the user `onTermination` callback on the connection actor, so a non-returning termination handler can stop the sole receiver. | fail lifecycle/retention |
| C02-04 | Scripted exact-wire cancellation before and after wire-ID-changing reconnect passed; repeated cancellation sent one unsubscribe and late events were ignored. Live cancellation removed all reported owner/wire storage. | pass |
| C02-05 | Scripted disconnect/send/malformed races and 100 reconnect cycles passed with fake-transport counts at zero. The real URLSession live smoke emitted `SWIFT TASK CONTINUATION MISUSE: receive() leaked its continuation!` once at reconnect and once at final disconnect even though `debugSnapshot()` reported zero. The production adapter wraps `URLSessionWebSocketTask.receive` in a checked continuation, but `disconnect()` only cancels and nils the task; on this required macOS 12-era toolchain the pending callback did not resume. | fail production lifecycle cleanup |
| C02-06 | The scripted replacement transport recreated the generic state owner, omitted the `resubscribe:false` history owner, and emitted its second `ready`. The live smoke observed two `ready` states, one history termination, and recreated history with a fresh timestamp after reconnect; both history streams produced an event. | pass for Module 02 primitive |
| C02-07 | Null/missing success, server code/message, concise diagnostics, timeout, cancellation, disconnect, and send-failure tests passed. Live Lovelace and ping results also resolved with no pending command storage. | pass |

The separate predecoded measurement is necessary for completion, rather than
an optional baseline refinement: both the rescue plan and this packet require
warm predecoded dispatch to be measured independently from JSON decode plus
dispatch with `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. The
current stress test supplies correctness and end-to-end XCTest duration only
and contains no `measure(...)` call or stored performance baseline.

### Implementation correction result — 2026-07-17

The verifier's three blocking findings were corrected without reopening the
green frontend evidence graph:

- C02-05 now has a lock-protected production adapter owner for the pending
  receive. A deliberately non-completing raw URLSession-task double proves that
  repeated disconnect resumes the Swift continuation exactly once, cancels the
  raw task once, clears pending count, and ignores a late callback. The rebuilt
  real-server smoke repeated auth, concurrent commands/subscriptions,
  reconnect, resubscribe, cancellation, and final disconnect with no Swift task
  continuation-misuse diagnostic.
- C02-03 now uses one observable connection-owned callback coordinator instead
  of one unowned drain task per subscription. With the configured four-task
  limit, the first wave of eight non-returning callbacks retains exactly four
  2 MiB payloads after all owners/buffers are removed; a second eight-owner wave
  retains none and cannot grow the active count past four. Opening the gate
  returns active callback count and all weak payloads to zero. A separately
  gated termination callback remains active while a later command result is
  routed, proving user termination work does not execute on or stop the sole
  receiver.
- C02-02/C02-03 now have three independent three-iteration measurements using
  `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. The two routing
  fixtures each use 10,000 events across 250 owners; lifecycle performs ten
  reconnects plus cancel/disconnect and validates zero owned storage.

Baseline from the isolated
`swift test --filter HomeAssistantWebSocketPerformanceTests` run on Swift
5.6.1/Xcode 13.4.1:

| Fixture | Scale | Clock mean | CPU-time mean | Physical-memory delta mean | Peak-physical delta mean |
|---|---:|---:|---:|---:|---:|
| Warm predecoded dispatch | 10,000 events / 250 owners | 1.711 s | 1.767 s | 10.923 kB | 0 kB |
| Decode plus dispatch | one 10,000-event JSON array / 250 owners | 2.397 s | 2.482 s | 1,256.128 kB | 0 kB |
| Repeated lifecycle | 10 reconnects plus cancel/disconnect | 0.004 s | 0.007 s | 0 kB | 0 kB |

Memory-delta sampling is allocator-noisy and is recorded as a reproducible
baseline, not a hard pass threshold. Lifecycle correctness and monotonic-growth
prevention are asserted by deterministic ownership/weak-retention tests.

### Commands and results

Pre-edit gate:

```text
node tools/reference-context/check-context.mjs docs/reference-context/generated/module-02.dependencies.json
GREEN; only note was NativeHA HEAD moving from 78a40f2 to 0479555

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint 25f80cc423416c098c50eb9dde41b93ca8e31d18b2946fa6d404a7a915ad10ea
```

Post-implementation manifest/anchor maintenance:

```text
node tools/reference-context/trace-ts-deps.mjs --manifest docs/reference-context/manifests/module-02.inputs.json --out-json docs/reference-context/generated/module-02.dependencies.json --out-markdown docs/reference-context/generated/module-02.dependencies.md
28 nodes, 59 edges, fingerprint f7e34261f82f8d4a4e70d248c03087e99abec39a31b82130a9ff346a669f0abc

node tools/reference-context/check-context.mjs docs/reference-context/generated/module-02.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint f7e34261f82f8d4a4e70d248c03087e99abec39a31b82130a9ff346a669f0abc
```

Final deterministic validation:

```text
swift test --filter HomeAssistantWebSocket
12 tests, 0 failures; 0.652 seconds test execution

swift test
32 tests, 0 failures; 3.457 seconds test execution
```

The full suite retained its three existing expected-failure parity markers; no
unexpected failure remained. The 10,000-message fixture completed in about
0.606 seconds in the final debug run, delivered 9,750 ordered subscription
events plus 250 out-of-order command results with exact checksum, and ended
with zero actor-owned pending/subscription/wire/receiver storage. The
100-reconnect fixture completed in about 0.039 seconds and also ended at zero.

Independent verifier commands and results on Swift 5.6.1/Xcode 13.4.1:

```text
node tools/reference-context/check-context.mjs docs/reference-context/generated/module-02.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint f7e34261f82f8d4a4e70d248c03087e99abec39a31b82130a9ff346a669f0abc

/usr/bin/time -lp swift test --filter HomeAssistantWebSocket
12 tests, 0 failures; 0.654 seconds test execution
10,000-message fixture: 0.602 seconds; 100 reconnect cycles: 0.037 seconds
maximum resident set size: 82,247,680 bytes

/usr/bin/time -lp swift test
32 tests, 0 failures; 3.539 seconds test execution
three pre-existing expected-failure parity markers remained expected
10,000-message fixture: 0.606 seconds; 100 reconnect cycles: 0.038 seconds
maximum resident set size: 168,427,520 bytes

cd /tmp/nativeha-module02-smoke
swift run --skip-build NativeHAModule02Smoke http://joyj.me:8123
SWIFT TASK CONTINUATION MISUSE: receive() leaked its continuation!
SWIFT TASK CONTINUATION MISUSE: receive() leaked its continuation!
PASS: Lovelace present; state subscription acknowledged; history events 2;
ready events 2; history terminations 1; pre-disconnect counts 0/0/0/1;
final counts 0/0/0/0. No state-changing service call was made.

/usr/bin/time -lp swift run --skip-build NativeHAModule02Retention
RESULT: 8 canceled non-returning callbacks retained 8/8 captured payloads
(16 MiB) while actor pending/subscription/wire counts were 0/0/0.
peak memory footprint: 23,512,768 bytes
```

Correction-pass commands and results on the same required toolchain:

```text
node tools/reference-context/check-context.mjs docs/reference-context/generated/module-02.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint 6725be545f291f813a37e122f205aae56cd13af5fcba30a917ab0a020737a474

swift test --filter HomeAssistantWebSocketPerformanceTests
3 tests, 0 failures; separate warm-predecoded, decode-plus-dispatch, and lifecycle metrics recorded above

swift test --filter HomeAssistantWebSocket
17 tests, 0 failures; 18.753 seconds test execution

swift test
37 tests, 0 failures; 22.269 seconds test execution
three pre-existing expected-failure parity markers remained expected

cd /tmp/nativeha-module02-smoke
swift run NativeHAModule02Smoke http://joyj.me:8123
PASS: Lovelace present; history events 2; ready events 2; history terminations 1;
pre-disconnect counts 0/0/0/1; final counts 0/0/0/0.
No continuation-misuse diagnostic and no state-changing service call.
```

The two live probes were temporary Swift 5.6 packages under `/tmp` depending
on the local `NativeHACore`; they did not modify tracked source or tests. The
state event count remained zero because verification deliberately made no
state-changing service call. Subscription acknowledgement, concurrent routing,
automatic generic resubscription, fresh history ownership, and cancellation
were still exercised.

### Fresh independent re-verification after correction — 2026-07-17

Verdict: remain `verification-ready`. C02-01 and the routing part of C02-02
pass; the bounded delivery/lifecycle correction for C02-03 passes; and C02-04
through C02-07 pass. The three performance tests now enter genuinely distinct
predecoded-dispatch, decode-plus-dispatch, and reconnect-lifecycle paths, but
the warm/memory and repeated-subscription methodology is still insufficient
for C02-02/C02-03 completion.

| Contract | Fresh independent evidence | Verdict |
|---|---|---|
| C02-01 | Auth/invalid-auth, feature negotiation, coalesced arrays, concurrent connect, and exactly one scripted receiver passed on Swift 5.6.1 targeting macOS 12. The live connection authenticated and reached `ready` twice. | pass |
| C02-02 | Concurrent/out-of-order commands and the 10,000-message exact-owner/checksum fixture passed. The performance tests separately call `dispatchPredecodedMessages` and `decodeAndDispatchFrame`, so they are not merely two labels around one entry point. However, the first event dispatch in the claimed warm test occurs inside `measure`, without an unmeasured dispatch warm-up. Both routing fixtures also retain another 10,000 integers in the same `IntegerDeliveryLog` on every measured iteration, so the three-iteration `XCTMemoryMetric` is confounded by deliberately growing consumer storage. | routing pass; performance methodology fail |
| C02-03 | The two-wave test created eight 2 MiB callback owners per wave. With the four-task global cap, the first cancellation left exactly four observable active tasks and four retained payloads; the second wave started no additional callback and retained no additional payload. Owner/buffer counts were zero after cancellation, and active tasks plus weak payloads reached zero after gate release. A separately blocked termination callback stayed observable while the sole receiver routed a later command result. The remaining performance fixture performs ten reconnects but only one subscribe/cancel, rather than measuring repeated subscribe/cancel lifecycle work; its memory metric therefore does not close the packet's repeated-subscription requirement. | delivery/lifecycle pass; performance methodology fail |
| C02-04 | Exact-wire cancellation, idempotence, current post-reconnect wire ID, and late-event suppression passed. The live smoke removed all local owners before disconnect. | pass |
| C02-05 | The raw-task production-adapter regression passed: a non-completing receive was resumed once with `disconnected`, repeated disconnect canceled the raw task once, pending receive count reached zero, and late completion was ignored. The rebuilt live reconnect/disconnect smoke contained no checked-continuation leak, misuse, or double-resume diagnostic and ended at `0/0/0/0`. | pass |
| C02-06 | Generic subscription recreation, history `resubscribe:false` removal, lifecycle `ready`, and a fresh live history subscription after reconnect passed. | pass for the Module 02 primitive |
| C02-07 | Missing/null success, server code/message, timeout, task cancellation, send failure, malformed input, disconnect cleanup, and concise diagnostics passed. | pass |

Fresh commands and results:

```text
node tools/reference-context/check-context.mjs docs/reference-context/generated/module-02.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint 6725be545f291f813a37e122f205aae56cd13af5fcba30a917ab0a020737a474

swift test --filter URLSessionHomeAssistantWebSocketTransportTests.testDisconnectExactlyOnceResumesPendingProductionAdapterReceive
1 test, 0 failures; 0.002 seconds test execution

swift test --filter HomeAssistantWebSocketMultiplexerStressTests.testEightNonReturningOwnersRemainObservableAndGloballyBoundedAcrossCancellation
1 test, 0 failures; 0.046 seconds test execution

swift test --filter HomeAssistantWebSocketMultiplexerStressTests.testStalledSubscriberUsesBoundedOverflowWithoutBlockingOtherOwners
1 test, 0 failures; 0.005 seconds test execution

swift test --filter HomeAssistantWebSocketPerformanceTests
3 tests, 0 failures; 16.944 seconds test execution
warm predecoded: clock 1.822 s, CPU time 1.897 s, physical-memory delta 21.845 kB
decode plus dispatch: clock 2.142 s, CPU time 2.210 s, physical-memory delta 1,441.813 kB
repeated lifecycle: clock 0.004 s, CPU time 0.007 s, physical-memory delta 10.923 kB

/usr/bin/time -lp swift test --filter HomeAssistantWebSocket
17 tests, 0 failures; 17.800 seconds test execution
10,000-message fixture: 1.100 seconds; 100 reconnect cycles: 0.039 seconds
maximum resident set size: 72,941,568 bytes

/usr/bin/time -lp swift test
37 tests, 0 failures; 21.547 seconds test execution
three pre-existing expected-failure graph parity markers remained expected
10,000-message fixture: 1.156 seconds; 100 reconnect cycles: 0.039 seconds
maximum resident set size: 159,776,768 bytes

cd /tmp/nativeha-module02-smoke
swift run NativeHAModule02Smoke http://joyj.me:8123
PASS: Lovelace present; state events 2; history events 2; ready events 2;
history terminations 1; pre-disconnect counts 0/0/0/1; final counts 0/0/0/0.
No continuation-misuse diagnostic and no state-changing service call.
```

The first two metric tests do construct their 10,000-message/250-owner encoded
and predecoded fixtures outside `measure`, and all three use `XCTClockMetric`,
`XCTCPUMetric`, and `XCTMemoryMetric`. The failure is narrower: warm the event
dispatch path before `measure`, consume each iteration through resettable
count/checksum state rather than a monotonically growing value log, and add
repeated subscribe/cancel work to the lifecycle metric. Then rerun the three
metrics, targeted/full suites, and `git diff --check`; a further frontend audit
or another live smoke is unnecessary unless implementation changes touch the
wire or production transport lifecycle.

### Final performance-methodology correction — 2026-07-17

This bounded pass changed only
`Tests/NativeHACoreTests/HomeAssistantWebSocketPerformanceTests.swift` and this
packet. Production Swift, wire behavior, configuration, and the green reference
graph were unchanged.

The three fresh-verifier methodology blockers are corrected:

- The warm-predecoded test performs one complete 10,000-event dispatch through
  `dispatchPredecodedMessages` before `measure`. It waits for exact callback
  completion and idle delivery, resets the consumer, and therefore excludes
  warm-up output from every measured iteration.
- Both routing fixtures use a constant-size actor containing only `count` and
  `checksum`, rather than retaining arrays of delivered integers. The actor is
  reset before every measured iteration. Each iteration must deliver exactly
  10,000 callbacks with checksum `1,245,195,000` and reach zero buffered/active
  delivery work; an over-count, under-count, cross-iteration callback, or wrong
  value fails the test.
- Every lifecycle metric iteration creates a fresh connection and performs ten
  subscribe/ack/cancel cycles plus ten reconnect cycles. Ownership is asserted
  after every subscription acknowledgement, cancellation, and reconnect.
  Pending commands, subscriptions, wire subscriptions, buffers, active
  delivery/termination tasks, pending terminations, and dropped terminations
  must have their exact expected values; final disconnect additionally requires
  zero receive loops.

The warm and decode paths remain distinct at identical scale: warm-predecoded
dispatch consumes the already-built `[JSONValue]`, while decode-plus-dispatch
starts from one encoded 10,000-object WebSocket frame. Fixture construction is
outside `measure`. Each metric uses three measured iterations with
`XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric` on Swift 5.6.1/Xcode
13.4.1.

Corrected isolated baseline from
`swift test --filter HomeAssistantWebSocketPerformanceTests`:

| Fixture | Work per measured iteration | Clock mean (RSD) | CPU-time mean (RSD) | Physical-memory delta samples | Peak-physical delta |
|---|---|---:|---:|---:|---:|
| Warm predecoded | 10,000 events / 250 owners, after a separate 10,000-event warm-up | 2.033 s (4.056%) | 2.141 s (2.531%) | -65.536, 0, -81.920 kB | 0 kB |
| Decode plus dispatch | one encoded 10,000-event array / 250 owners | 2.378 s (4.817%) | 2.452 s (5.051%) | 2,113.536, 622.592, 671.744 kB | 0 kB |
| Repeated lifecycle | 10 subscribe/ack/cancel plus 10 reconnect cycles | 0.005 s (3.020%) | 0.007 s (3.090%) | 0, 0, 0 kB | 0 kB |

Physical-memory delta is an allocator page sample and may be zero or negative
when pages are returned; it is recorded verbatim rather than converted into an
absolute CI threshold. Reproducibility comes from fixed work, constant-size
consumer state, three iteration samples, exact count/checksum assertions, and
the deterministic lifecycle ownership checks.

Final commands and results:

```text
node tools/reference-context/check-context.mjs docs/reference-context/generated/module-02.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint 6725be545f291f813a37e122f205aae56cd13af5fcba30a917ab0a020737a474

swift test --filter HomeAssistantWebSocketPerformanceTests
3 tests, 0 failures; 20.759 seconds test execution
warm predecoded: clock 2.033 s, CPU time 2.141 s, memory samples -65.536/0/-81.920 kB
decode plus dispatch: clock 2.378 s, CPU time 2.452 s, memory samples 2113.536/622.592/671.744 kB
repeated lifecycle: clock 0.005 s, CPU time 0.007 s, memory samples 0/0/0 kB

swift test --filter HomeAssistantWebSocket
17 tests, 0 failures; 19.718 seconds test execution

swift test
37 tests, 0 failures; 24.909 seconds test execution
three pre-existing expected-failure graph parity markers remained expected
```

### Final fresh independent verification — 2026-07-17

Verdict: `complete`. A fresh verifier independently inspected the tracked and
untracked Module 02 diff, including the final performance-test methodology,
then reran every applicable context, performance, lifecycle, targeted, full,
and read-only live check on Swift 5.6.1/Xcode 13.4.1 targeting macOS 12.
C02-01 through C02-07 pass with no remaining Module 02 blocker.

| Contract | Final independent evidence | Verdict |
|---|---|---|
| C02-01 | Authentication ordering, invalid authentication, feature negotiation, coalesced arrays, concurrent connect, and one steady receiver passed. The live connection authenticated and reached `ready` twice. | pass |
| C02-02 | Concurrent/out-of-order routing and the 10,000-message stress fixture passed. The warm metric performs a completed unmeasured 10,000-event dispatch on the same `dispatchPredecodedMessages` path, resets its two-integer accumulator, and reaches idle before measurement. Every measured iteration resets that constant-size state and requires exactly 10,000 deliveries and checksum `1,245,195,000` before returning idle. | pass |
| C02-03 | Early event delivery, per-owner order, bounded overflow, blocked-termination isolation, the two-wave four-task retention bound, and final cleanup passed. Every lifecycle metric iteration used a fresh connection and performed ten acknowledged subscribe/cancel cycles plus ten reconnects with exact ownership checks after each phase and zero receive loops after final disconnect. | pass |
| C02-04 | Exact current-wire unsubscribe, idempotent cancellation, and late-event suppression passed; the live smoke removed all subscription ownership before disconnect. | pass |
| C02-05 | Disconnect/send/malformed races, 100 reconnect cycles, and the production-adapter exactly-once regression passed. The repeated live reconnect/disconnect smoke emitted no continuation leak, misuse, or double-resume diagnostic and ended at `0/0/0/0`. | pass |
| C02-06 | Generic resubscription, history `resubscribe:false` removal, lifecycle `ready`, and a freshly created live history owner after reconnect passed. | pass for the Module 02 primitive; Module 01 owns the consumer accumulator test |
| C02-07 | Missing/null success, server code/message, concise diagnostics, timeout, task cancellation, send failure, malformed input, and disconnect cleanup passed. Live Lovelace and ping commands also resolved with zero pending ownership. | pass |

The two routing measurements remain distinct at the same scale. Warm-predecoded
dispatch consumes the already-built 10,000-element `[JSONValue]`; decode plus
dispatch starts with a serialized 10,000-object WebSocket frame, runs
`JSONDecoder`, and then enters dispatch. Fixture construction remains outside
`measure`. All three fixtures use three iterations of `XCTClockMetric`,
`XCTCPUMetric`, and `XCTMemoryMetric`. Memory samples are recorded as allocator
observations and are not flaky absolute thresholds; deterministic count,
checksum, idle, and ownership assertions determine correctness.

Final isolated metric results:

| Fixture | Clock mean (RSD) | CPU-time mean (RSD) | Physical-memory delta samples | Peak-physical delta |
|---|---:|---:|---:|---:|
| Warm predecoded | 2.084 s (0.474%) | 2.169 s (0.567%) | -65.536, 0, -32.768 kB | 0 kB |
| Decode plus dispatch | 2.512 s (1.253%) | 2.587 s (0.980%) | 2,277.376, 1,736.768, 753.664 kB | 0 kB |
| Repeated lifecycle | 0.005 s (2.574%) | 0.007 s (1.249%) | 0, 0, 16.384 kB | 0 kB |

Final fresh commands and results:

```text
swift-driver version: 1.45.2 Apple Swift version 5.6.1
Target: arm64-apple-macosx12.0
Xcode 13.4.1 (13F100)

node tools/reference-context/check-context.mjs docs/reference-context/generated/module-02.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint 6725be545f291f813a37e122f205aae56cd13af5fcba30a917ab0a020737a474

swift test --filter URLSessionHomeAssistantWebSocketTransportTests.testDisconnectExactlyOnceResumesPendingProductionAdapterReceive
1 test, 0 failures; 0.003 seconds test execution

swift test --filter HomeAssistantWebSocketMultiplexerStressTests.testEightNonReturningOwnersRemainObservableAndGloballyBoundedAcrossCancellation
1 test, 0 failures; 0.051 seconds test execution

swift test --filter HomeAssistantWebSocketMultiplexerStressTests.testStalledSubscriberUsesBoundedOverflowWithoutBlockingOtherOwners
1 test, 0 failures; 0.004 seconds test execution

/usr/bin/time -lp swift test --filter HomeAssistantWebSocketPerformanceTests
3 tests, 0 failures; 20.524 seconds test execution
maximum resident set size: 83,083,264 bytes

/usr/bin/time -lp swift test --filter HomeAssistantWebSocket
17 tests, 0 failures; 20.485 seconds test execution
10,000-message routing stress: 1.213 seconds; 100 reconnect cycles: 0.038 seconds
maximum resident set size: 89,653,248 bytes

/usr/bin/time -lp swift test
37 tests, 0 failures; 23.135 seconds test execution
three pre-existing expected-failure graph parity markers remained expected
10,000-message routing stress: 1.096 seconds; 100 reconnect cycles: 0.038 seconds
maximum resident set size: 159,481,856 bytes

cd /tmp/nativeha-module02-smoke
swift run NativeHAModule02Smoke http://joyj.me:8123
PASS: Lovelace present; state events 0; history events 2; ready events 2;
history terminations 1; pre-disconnect counts 0/0/0/1; final counts 0/0/0/0.
No continuation diagnostic and no state-changing service call.

git diff --check
PASS (no output)
```

### Post-fix independent audit — 2026-07-27

Verdict: return to `verification-ready`. The focused Module 02 suite remains
green, but a deterministic transport test that suspends the first command send
after ID allocation reproduces non-increasing wire delivery. C02-02 therefore
does not currently prove the send-serialization guarantee that motivated
`e4eecb2`.

| Contract | Current evidence | Verdict |
|---|---|---|
| C02-01 | Existing authentication, feature negotiation, coalesced-frame, and single-receiver tests remain green. | pass |
| C02-02 | The tracked 64-command/64-subscription test passes because `ScriptedWebSocketTransport.send` has no suspension before it records a message. In an isolated clone, delaying ID 2 inside a conforming transport allowed ID 3 to arrive first; the strict transport recorded one non-increasing-ID violation and the new test failed. Allocation at `HomeAssistantWebSocketConnection.swift:659` and `:712` is actor-serialized, but the awaited sends at `:677` and `:735` are not connection-wide serialized across actor reentrancy. | fail send serialization |
| C02-03 through C02-07 | The tracked focused suite passed all delivery, retention, cancellation, reconnect, timeout, large-frame, and production receive-continuation regressions. | pass in focused suite |

Separately, later debug instrumentation logs complete text WebSocket frames.
With network logging enabled, large history payloads are copied into an
unbounded asynchronous SQLite queue and persisted in full. The observed
`~/Library/Caches/NativeHA_Logs.sqlite` was 1,586,012,160 bytes across 55 log
tables; the focused and full test runs also emitted repeated
`database is locked` diagnostics. This instrumentation is newer than the
original Module 02 implementation, but it now sits directly on the Module 02
receive path and can add disk growth, memory pressure, and background I/O
during long history streams.

Commands and results:

```text
swift test --filter HomeAssistantWebSocket
19 tests, 0 failures; 20.386 seconds test execution

# Isolated clone with a suspension-capable strict transport regression
swift test --filter HomeAssistantWebSocketConnectionTests.testSuspendingTransportCannotReorderAllocatedWireIDs
1 test, 1 failure; violationCount was 1 rather than 0

sqlite3 -readonly ~/Library/Caches/NativeHA_Logs.sqlite \
  "SELECT sum(pgsize) FROM dbstat;"
1586012160

swift test
96 tests, 3 skipped, 24 failures
```

The full-suite result is not Module 02 evidence: the pre-existing uncommitted
`AppConfig.graphRenderEngine = .coreGraphics` override changes graph behavior
and accounts for the failures observed outside the WebSocket suites. The
focused Module 02 suites were green before the added suspension reproduction.

Exact next actions:

1. Add one connection-owned outbound send serializer that preserves allocation
   order across commands, subscriptions, unsubscribe commands, feature
   negotiation, and resubscription even when a transport send suspends. Start
   timeouts when the serialized send is actually admitted, or explicitly test
   the chosen queued-time policy.
2. Keep the suspension-capable strict transport regression and rerun the
   concurrent mixed-ID, cancellation, disconnect, reconnect, and full focused
   Module 02 suites.
3. Replace full-frame debug logging with bounded metadata or a deliberately
   capped payload preview, and add SQLite retention/size and busy-handling
   policy so logging cannot grow without bound or flood diagnostics.

### Native send-order repair and superseded logging policy — 2026-07-28

Verdict: `complete`. An independent verifier reproduced the suspended-send
failure and added the first deterministic regression before production changes.
The repair adds a synchronous-enqueue FIFO per physical transport generation,
then revalidates command or subscription ownership immediately before the
queued item reaches `URLSessionWebSocketTask`. This preserves browser-observable
monotonic ID semantics without copying the browser's synchronous JavaScript
scheduling assumption.

The generation boundary is explicit: an indefinitely suspended send on an old
transport cannot block authentication or traffic on its replacement. Stopping
that generation resolves its active ticket and releases the serializer even if
the underlying transport never completes. A command cancelled while queued is
removed from pending ownership and skipped before it reaches the transport.
Existing receive-loop, timeout, callback coordinator, history opt-out, 32 MiB
receive policy, and production pending-receive cleanup paths were not replaced.

The logging half of the original repair was superseded by user direction.
Explicitly selected diagnostics must retain complete WebSocket frames and
other messages without a database ceiling, character truncation, or
queue-admission dropping. Resource use is controlled by per-subsystem severity
selection and lossless transaction batching rather than silently discarding
accepted diagnostics.

Validation:

```text
swift test --filter HomeAssistantWebSocketConnectionTests
14 tests, 0 failures

swift test --filter HomeAssistantWebSocket
23 tests, 0 failures; includes 10,000-message routing, 100 reconnect cycles,
bounded callback retention, split performance metrics, and URLSession adapter
cleanup

swift test --filter HomeAssistantHistoryStream
26 tests, 0 failures

swift test --filter HistoryStreamIntegrationTests
3 tests, 0 failures

NATIVEHA_RUN_LIVE_HISTORY_SMOKE=1 swift test \
  --filter HomeAssistantHistoryLiveSmokeTests.testReadOnlyOneHourTwelveHourTwentyFourHourAndReconnectSmoke
1 test, 0 failures; 1h/12h/24h history, reconnect, cancellation, and final
ownership cleanup passed against the live deployment
```

## Validation requirements

### Offline deterministic tests

Use a scripted fake transport. Cover auth success/invalid, single object and
coalesced arrays, concurrent out-of-order calls, interleaved results/events,
event-before-ack, null result, server error propagation, slow subscriber ordering,
idempotent unsubscribe, unknown IDs, late events, concise error diagnostics,
cancellation/timeout/send failure/malformed JSON/disconnect races, reconnect
policy, and final storage counts of zero. Include a high-volume
exact-count/checksum stress test.

### Read-only live smoke

Applicable after offline tests. Interleave Lovelace config fetch, state
subscription, and a history subscription on one authenticated connection;
observe clean cancellation and reconnect. Load connection details from the
locations named by the root instructions and keep protocol diagnostics concise.
This smoke is read-only and must not replace deterministic tests.

### Visual and animation oracle

N/A: this module owns transport and lifecycle, not pixels. A future reconnect
banner belongs to the dashboard-state module.

### Performance and lifecycle

Measure decode+dispatch separately from predecoded warm dispatch. Repeated
subscribe/cancel and reconnect cycles must return pending command, callback,
and receive-loop counts to zero without monotonic retained-memory growth.

## Open questions and risks

- Generic automatic resubscription, history opt-out, and array-frame support
  are implemented; these are no longer open design questions.
- The previous production pending-receive continuation leak is corrected and
  covered by both a production-adapter regression and a rebuilt live smoke.
- Swift cannot forcibly destroy arbitrary async callbacks that ignore task
  cancellation. Such work now remains visible and consumes one of four global
  delivery slots until it returns, preventing monotonic retained-task growth.
  Four permanently non-cooperative callbacks can therefore starve later event
  delivery; this is an explicit bounded-failure policy documented in
  `docs/configurability.md`, not hidden zero storage.
- Termination callbacks are receiver-independent and bounded to one active task
  plus the configured pending capacity. If a termination callback never
  returns, excess later termination notifications are counted and dropped
  rather than growing memory or blocking protocol routing.
- Split XCTMetric paths and corrected baselines are now recorded. The warm-up,
  constant-size resettable consumer, exact count/checksum, and repeated
  subscribe/cancel methodology gaps are closed. Allocator memory-delta samples
  remain observational rather than absolute thresholds, so regressions should
  continue to use the deterministic ownership assertions alongside them.
- Modern frontend state updates use `subscribe_entities`; generic transport must
  carry its compact event payload, but entity migration belongs to its module.

## Handoff

Module 02 is complete again. Preserve the per-generation outbound FIFO and its
pre-send ownership checks alongside the existing single receiver, callback
coordinator, reconnect primitive, production receive cleanup, history opt-out,
and large-frame policy. The native serializer is an intentional macOS transport
adaptation that preserves Home Assistant's observable protocol semantics.

## Change log

- 2026-07-16: initial read-only research packet and deterministic dependency
  graph created; status `research-ready`, contract revision 1.
- 2026-07-17: reconciled the packet with the merged product-intent, credential,
  configurability, and phase-routing guidance at NativeHA `78a40f2`.
- 2026-07-17: implemented C02-01 through C02-07 on base `0479555`, added the
  scripted fake-transport and stress/lifecycle matrix, passed focused and full
  tests, and advanced status to `verification-ready` for an independent agent.
- 2026-07-17: independent verification passed deterministic routing and the
  functional live protocol flow, but kept status `verification-ready` for the
  real-transport receive-continuation leak (C02-05), non-returning callback and
  termination-path retention (C02-03), and missing split XCTMetric performance
  evidence (C02-02/C02-03).
- 2026-07-17: corrected all three verifier findings, added production-adapter,
  two-wave eight-owner retention, gated-termination, and split XCTMetric
  regressions, passed 17 focused and 37 full tests, repeated the rebuilt live
  smoke without continuation diagnostics, and kept status
  `verification-ready` for a fresh independent verifier.
- 2026-07-17: fresh independent verification passed the production adapter,
  bounded callback ownership, termination isolation, targeted/full suites, and
  rebuilt read-only live smoke. It retained `verification-ready` for
  C02-02/C02-03 because the warm metric lacks an unmeasured event-dispatch
  warm-up, its consumer log grows by 10,000 values per measured iteration, and
  the lifecycle metric does not repeat subscribe/cancel work.
- 2026-07-17: corrected only the performance test methodology: added a complete
  unmeasured 10,000-event warm-up, constant-size resettable count/checksum state
  with exact per-iteration validation, and ten subscribe/ack/cancel cycles
  alongside ten reconnects per lifecycle iteration. Passed the corrected metric,
  focused WebSocket, and full suites and kept `verification-ready` for one final
  independent verifier.
- 2026-07-17: final fresh independent verification passed the corrected
  performance methodology, isolated critical lifecycle regressions, complete
  WebSocket and full suites, and a repeated read-only live reconnect/disconnect
  smoke with no continuation diagnostic and final zero ownership. C02-01 through
  C02-07 pass; status advanced to `complete`.
- 2026-07-27: a post-fix audit reproduced non-increasing wire IDs when a
  conforming transport suspends before completing an earlier send, so C02-02
  returned to failing and the packet returned to `verification-ready`. The
  audit also identified unbounded full-frame SQLite debug logging on the
  WebSocket path as a separate operational regression requiring bounded
  logging and retention.
- 2026-07-28: independently reproduced both findings, added a per-transport
  synchronous-enqueue FIFO with cancellation and generation guards, replaced
  full-frame logging with bounded metadata and bounded SQLite retention and
  queue policies, then added never-returning-send and locked-database
  regressions after a final independent lifecycle review. Focused, stress,
  lifecycle, history integration, and live 1h/12h/24h reconnect validation
  passed. Status returned to `complete`.
- 2026-07-28: user direction superseded the bounded diagnostic policy. Removed
  full-message truncation, database and pending-entry ceilings, and silent
  admission dropping while retaining the independently verified native
  send-order and lifecycle repairs.
