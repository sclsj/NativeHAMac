---
schema: nativeha-evidence/v1
module: "02"
title: WebSocket multiplexer and subscription architecture
plan: ../../rescue-plan/module-02-websocket-multiplexer.md
status: complete
contract_revision: 2
depends_on: []
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 9291da336d2f068c39c4924fed3add4c52c27f85
graph_file: ../generated/module-02.dependencies.json
graph_fingerprint: 0d5d18dbc77d36c1f5ee5a16023c0a658788fa96c9394ecc188217280864d4c1
last_validated: 2026-09-11
---

# Module 02 evidence packet

2026-09-11 anchor refresh: the shared dashboard bootstrap and its tests changed; see [Module 05 consolidation](module-05-dashboard-viewmodel-state.md#2026-09-11-bootstrap-consolidation) for validation and limits. This module's contract revision is unchanged; older verification entries below retain their original revision-specific evidence.

## Scope delta

This packet confirms the rescue plan's single-receive-loop direction and adds protocol details found inside `home-assistant-js-websocket@9.6.0`. It corrects two assumptions in the plan:

- The current reference uniformly unwraps subscription wire messages from `message.event`; history and weather do not require different raw envelope normalization.
- Generic subscriptions auto-resubscribe by default. History deliberately opts out and rebuilds its request and accumulator on each `ready` event.

If NativeHA advertises Home Assistant's `coalesce_messages` supported feature, it must accept an incoming JSON object or an ordered array of objects.

The current diagnostic follow-up is based on NativeHA `e347408455e01b774d93800c881850b6f88997d2`, which contains the explicit lossy-limit revert. The frontmatter revision identifies that committed base; the packet's later validation sections record subsequent implementation work.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| C02-01 | Connect/authenticate | Send token only after `auth_required`; accept `auth_ok`, reject `auth_invalid`. Optionally negotiate `coalesce_messages: 1` with command ID 1 on supported servers. | Do not start the steady receive loop until authentication succeeds. If coalescing is advertised, decode both object and ordered-array frames. | HF-01, NPM-02, NPM-03 | New connection actor and transport adapter | Scripted auth and coalesced-frame tests |
| C02-02 | Concurrent commands/subscriptions | Commands and subscriptions share one monotonically allocated ID space and exactly one steady socket receiver dispatches by ID. | Register pending state before send; out-of-order results resolve only their owner; unknown results are harmless. | NPM-01, SW-01 | Connection actor pending-command/subscription maps | Concurrent out-of-order/interleaving tests |
| C02-03 | Subscribe and receive event | Install subscription storage before sending. Successful ack retains it; `{type:"event", event:...}` delivers the unwrapped event payload. Standard typed events may decode directly from a validated copied event slice while raw/extended envelopes retain generic decoding. | Event-before-ack must be safe. Preserve order within a subscription; slow or large typed decoding must not block the socket actor or create unbounded unordered tasks. Cancellation suppresses late callbacks, and a typed decode failure is owner-local rather than connection-fatal. | HF-02, HF-03, NPM-01 | Typed subscription API, envelope scanner, and bounded serial delivery boundary | Early-event, large typed event, malformed typed owner, cancellation, coalesced order, raw fallback, and slow-subscriber tests |
| C02-04 | Cancel subscription | Send `unsubscribe_events` with `subscription` equal to the original subscription command ID. | Cancellation is idempotent; remove local callback even after disconnect; late events do not deliver. | NPM-01, NPM-03 | Subscription handle | Exact-wire, repeated-cancel, and late-event tests |
| C02-05 | Failure/disconnect/reconnect | Reject ordinary in-flight commands with connection-lost, clear ownership, and surface lifecycle state. | Never resume a continuation twice. Implement generic automatic resubscription; stale subscriptions and frames decoded after a generation change must not publish into the replacement generation. | NPM-01, HF-04 | Connection actor lifecycle/status events and generation-gated envelope dispatch | Disconnect races, cleanup counts, detached-decode cancellation, and reconnect cycles |
| C02-06 | Reconnect history stream | History disables generic resubscribe, listens for `ready`, rebuilds `start_time`, and creates a fresh accumulator. | Disposal removes listener and current subscription. Reconnect failures are contained for the owner to retry. | HF-02 | Module 01 owner using Module 02 status/subscription API | Module 01 fresh-stream test; Module 02 supports `resubscribe:false` or equivalent ownership |
| C02-07 | Command result/error | `success:true` resolves with result, including missing/null where allowed; `success:false` preserves server code/message. | Remove pending storage once; user-facing errors remain concise. Explicitly enabled debug tracing may persist complete wire payloads under the diagnostic policy. | NPM-01 | Command error model and continuation owner | Null result, server error, concise error, cancellation, and timeout tests |
| C02-08 | Dashboard formatting bootstrap commands | Fetch compressed entity-registry display metadata with `config/entity_registry/list_for_display` and frontend locale preferences with `frontend/get_user_data` key `language` through the same typed command path. Decode effective `dp` precision and the complete locale policy; a null preference value remains an allowed fallback. | These commands may run concurrently with Lovelace fetch and must retain C02-02 routing/order. Optional metadata failure stays local and must not prevent dashboard config loading. Any required bootstrap or state-subscription failure after connect must disconnect the newly owned client exactly once. | HF-05, HF-06, HF-07, NPM-01 | `HomeAssistantWebSocketClient`, typed response models, and `DashboardViewModel.runOwnedBootstrap` | Exact command/decode, bootstrap-failure cleanup, and read-only live formatting/bootstrap tests |

## Source anchors

### hass-frontend at `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`

- **HF-01** — `src/entrypoints/core.ts::connProm`, Git blob `e8549e265db44300eddafb4ef3aaf8732655e719`, SHA-256 `071b4ac3ecedd8adb13a8e677009f586ea05ed8acc28bd7375f0de0bc873e518`. Creates the shared package connection.
- **HF-02** — `src/data/history.ts::subscribeHistoryStream`, line hint 281, Git blob `5a3c3e8f8fa02c7a081a1ddb0fea875bd40147e2`, SHA-256 `055be2c7ce23ba96de01948e8af51c1f3c699d0580f7d49c22ffc662eb19470c`.
- **HF-03** — `src/data/weather.ts::subscribeForecast`, line hint 698, Git blob `2e126b7f1c28dd9f77028d42abecece7e52c0f72`, SHA-256 `386d4da61b41951bf15098c5b1d0ba8b301da27b7ed6602b96d4143bed1f514b`.
- **HF-04** — `src/state/connection-mixin.ts::connectionMixin`, especially `initializeHass` and `hassConnected` around line hints 54 and 231, Git blob `a6b0beefb0b308efd15b71dcf93649577b2af603`, SHA-256 `ed4c83f57d1d308480daf560b91a13d8309f76a8745c035db35f501cc9a48a8a`.
- Lovelace command anchor — `src/data/lovelace/config/types.ts::fetchConfig`, line hint 31, Git blob `3735c8c58b016d1394d27ca53a3276ed0c4fc8c1`.
- **HF-05** — `src/data/entity/entity_registry.ts::EntityRegistryDisplayEntryResponse` and `fetchEntityRegistryDisplay`, line hints 31 and 301, Git blob `8510cae926a61cf71b9bf8097f200f3009187907`, SHA-256 `8ca09217f83a34fc78662e858393f90d269666ba9c3019be969817a77e73c6a2`. The display response uses compressed `ei` and effective `dp` fields.
- **HF-06** — `src/data/frontend.ts::fetchFrontendUserData`, line hint 52, Git blob `697fc39cf6b745dcc5c49dc09f7d74ad19d78fc6`, SHA-256 `b6490f26521aae4c9d873f2d317c9f84cd14541943483d295f99dccbcff63834`. It sends `frontend/get_user_data` with a typed key and returns nullable `value`.
- **HF-07** — `src/data/translation.ts::FrontendLocaleData`, line hint 45, Git blob `9e159dd0d125b90ba2d595695decb66c63a79d50`, SHA-256 `df1b54754227498aa473376f7038e6ffa0bd13deb37a47cec5d8e2317177a53d`. It defines language, number/time/date formats, first weekday, and timezone.

### npm runtime boundary

Package `home-assistant-js-websocket@9.6.0`, package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`, Yarn locator `home-assistant-js-websocket@npm:9.6.0`, checksum `10/0eded7864632b5e19e92289ffac0e24308b1e8f425e292ae87ed21450852f7705db521e202614b1d5bbdb7948633143dce2524ed548db0c38486b40ed1ffa474`.

- **NPM-01** — `dist/connection.js::Connection`, including `_handleMessage`, `_handleClose`, `sendMessagePromise`, and `subscribeMessage`; SHA-256 `884929a38078cc51cb47b0d7d8a821ef99bc784bcd50792bf9b044f936db69e8`.
- **NPM-02** — `dist/socket.js::createSocket`; SHA-256 `03211601a595e2bd99dd863cfbf382171e90d57097a317a50a9ea508c828307c`.
- **NPM-03** — `dist/messages.js::supportedFeatures` and `unsubscribeEvents`; SHA-256 `5de87c3bf01207c73424e51a0676705afee7afc2efde7cb8707dfafe709a7b35`.

### NativeHA research baseline at `78a40f22dd278c74af9a81ae47a802fc4a94c1d1`

- **SW-01** — `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`, Git blob `2991447a91dd6d92185da8214e4d020a8a2845a2`, SHA-256 `29530f8cab9c9d4ec7ba98ee082cf9671bc2978007be2a3f45baf87a9cf6132d`. `connect` begins around line 22, `receiveStateChanges` around 70, `sendCommand` around 88, and `receiveDictionary` around 144. Multiple owners directly receive from one socket and mutable IDs are unsynchronized.
- **SW-02** — `Sources/NativeHAMac/DashboardViewModel.swift::load`, line hint 383, Git blob `37815aac34b736e645e929f586748c2e314d4deb`, SHA-256 `f19f79bb937660d2128cdfc7dd083b43879d1d722eca9177c1e17ed32a416c16`. It fetches config, subscribes, and launches the direct state-change receiver.

### Current anchors at `f58345bde090444777eb3cbf610822c466ee2300` plus the reviewed Module 04 worktree

- **SW-03** — `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift`, Git blob `c245df11ab38f7a294a16ce5bf45212c3fe7b96a`, SHA-256 `0482c187bb5256145c0bd48f3ca8f7fad85f916856bd7d99875e2a11aa4ef53c`. Owns the single receiver, shared ID space, outbound generation FIFO, pending/subscription maps, bounded callback coordinator, direct typed-event route, cleanup, and reconnect generation checks.
- **SW-04** — `Sources/NativeHACore/HomeAssistantWebSocketEnvelope.swift`, Git blob `893c91f417584126e7a4ab81767ca8c8a965dea3`, SHA-256 `a426613a8784bbf48d2fd156a24ed5d81de3a3c1f15feac954b73b2cb2140436`. Validates object/coalesced-array boundaries and extracts exact copied event slices while forcing extended/escaped metadata through generic decoding.
- **SW-05** — `Sources/NativeHACore/HomeAssistantWebSocketTransport.swift`, Git blob `dea3b1bc4d8e0e0a50051f8f769c1d01f3e25ab5`, SHA-256 `8b9f71a671e2ea28eda63e672e752e4427c92300b9b2f1abaa3d744dc0fc98e3`. Applies the finite receive limit before resume and exactly-once completes a pending production receive during disconnect.
- **SW-06** — `Sources/NativeHACore/HomeAssistantHistoryStream.swift`, Git blob `8cac19f68aea0fca6b17af7619c03bdfa528880c`, SHA-256 `fbaf6d5bad0a7e7284c1716b1182c4167f229fb221c089374fed8e6ec1ed1728`. The coordinator uses typed `subscribeMessage`, explicitly passes `resubscribe:false`, and rebuilds generation, start time, and accumulator on `ready`.
- **SW-07** — `Sources/NativeHACore/HomeAssistantWebSocketClient.swift` and `Sources/NativeHACore/Models.swift`, Git blobs `41139d06b468cafc9a631dabaa789c3fab1c7eb1` and Module 04 worktree blob `b43c25f217bbef8053468728a569da1c25b234d0`, SHA-256 `d0b5cc37bb151f54f178402b61429979cd067c1d2acf8a7f56662f468c62307d` and `e25788d8b24b6fa1517fcfb104ffe4e3faa7f17dc24ea89564d981d782387a60`. These provide the thin client facade and compressed display/nullable locale typed command models without adding a second receiver. Module 04 moved only the unrelated Lovelace model declarations out of `Models.swift`; the four C02-08 typed response models are unchanged.
- **SW-08** — `Sources/NativeHAMac/AppConfig.swift` and `Sources/NativeHAMac/DashboardViewModel.swift`, Module 04 worktree blobs `a93044b070318f2f6fe431920380087ff6b68c1a` and `b6e22b2a2af82a015396dbbfc60a6d9b6b363953`, SHA-256 `06ae89a0048416e79ecfc81e43a27076c23156a5c4fb0dd505ed2a9a78a23910` and `b471d586874816bfdaa4e74c8abcbe81cb8ebc1232a38a09921ba8f2a01d9280`. The WebSocket policy remains 10 seconds / 32 MiB / 256 buffered events / four active callback tasks. Dashboard bootstrap passes the complete policy, runs display/locale/Lovelace typed calls on the verified connection, stores the successful state subscription, and observes status. Its extracted `bootstrapDashboard(using:)` disconnects the authenticated client if required config decode or state-subscription setup fails before ownership transfer.
- **SW-09** — `Tests/NativeHACoreTests/HomeAssistantWebSocketConnectionTests.swift`, Git blob `acbae66947dd8ccb7ef907fb20a474380f1d7948`, SHA-256 `9cc0ef20158ed38f42b974aa6871898d7da7af43e69dc855e4ffcdaa22a4c5cd`. `testCancelledQueuedTypedSliceReleasesLargeCoalescedFrameBacking` observes release of an 8 MiB custom-deallocated coalesced frame after cancellation; `testDetachedScanAndDecodeGuardsDropStaleGenerationEvents` deterministically gates both envelope-scan and payload-decode boundaries across reconnect.
- **SW-10** — `Tests/NativeHAMacTests/DashboardBootstrapLifecycleTests.swift`, Module 04 worktree blob `8f52b825c02c6f09927beaa5570ceaa46be06ee2`, SHA-256 `e9df5964d211fe692119a64bc21d70ad7afc56b939ffec7d65208d67a2c1b897`. Two deterministic production-model tests prove exactly one disconnect and zero receive/pending/subscription ownership after malformed Lovelace (under either the standard decoder or Module 04's strict root decoder) and a rejected state subscription.

## Dependency traces and boundaries

The generated graph is [`module-02.dependencies.json`](../generated/module-02.dependencies.json), fingerprint `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`.

- `src/entrypoints/core.ts::connProm` has a runtime package edge. TypeScript resolves declarations to `dist/index.d.ts`; package `exports.import` resolves actual runtime code to `dist/index.js`, which reaches `connection.js` and `socket.js`.
- History, weather, Lovelace config, and `util/websocket.ts` refer to `Connection` through type-only edges. That graph cannot identify the method implementation, so `connection.js`, `socket.js`, and `messages.js` are explicit reviewed seeds.
- Traversal enters only `home-assistant-js-websocket`; other npm packages and type-only declarations are recorded boundaries. The current graph has no unresolved edges and is not truncated.

## Native mapping

| Contract | Existing/planned Swift path | Symbol/type | Ownership/state | Notes |
|---|---|---|---|---|
| C02-01, C02-02, C02-05, C02-07 | `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift` | `HomeAssistantWebSocketConnection` actor | Socket, ID allocator, pending commands, receive task, lifecycle | Implemented with one steady receiver after auth |
| C02-01 | `Sources/NativeHACore/HomeAssistantWebSocketTransport.swift` | injectable protocol + URLSession adapter | Raw frame send/receive/cancel | Scripted transport suspends send/receive independently |
| C02-03, C02-04 | NativeHACore connection/subscription files | typed subscription handle and connection-wide callback coordinator | Bounded buffers, bounded active callback tasks, original ID, idempotent cancel | Preserve per-subscription order and expose work that ignores cancellation |
| Existing feature facade | `Sources/NativeHACore/HomeAssistantWebSocketClient.swift` | thin Lovelace/state plus typed display/locale command wrappers | No raw receive ownership | Keep call sites small during migration |
| Subscription consumer | `Sources/NativeHAMac/DashboardViewModel.swift` | stored subscription token | Cancel on teardown/reconnect | Remove detached raw receive loop |
| C02-08 | `Sources/NativeHACore/Models.swift`, `HomeAssistantWebSocketClient.swift`, and `Sources/NativeHAMac/DashboardViewModel.swift` | compressed display/locale response models and bootstrap calls | Concurrent typed command owners on the shared connection; optional metadata fallback is dashboard-local | Preserve exact command types and nullable preference behavior |

## Decisions and native deviations

| ID | Decision/deviation | Allowed reason | Preserved semantics | Test | Status |
|---|---|---|---|---|---|
| D02-01 | Use a Swift actor rather than JavaScript maps/event listeners. | Native concurrency convention | Serialized ID/storage ownership and one receiver | Race/interleaving suite | implemented |
| D02-02 | Add command timeout and cancellation cleanup absent or looser in the JS client. | Native lifecycle safety | Successful/error wire behavior remains identical | Timeout/cancel/disconnect races | implemented |
| D02-03 | Deliver callbacks outside connection-actor isolation through one connection-owned coordinator. It preserves per-owner serial order, bounds buffers, and globally caps active subscriber callbacks at the configured value (four in the app policy). Cancellation requests task cancellation and removes queued/callback ownership immediately; a callback that ignores cancellation remains explicitly owned and counted against the cap until it returns. Termination callbacks use a separate single-task bounded queue. | Performance, reentrancy, and native lifecycle safety | Per-subscription order; no cross-routing, receiver blocking, or monotonic callback-task creation during owner churn | Slow subscriber, gated termination, and eight-owner 2 MiB retention regressions | implemented |
| D02-04 | Keep a logical subscription record across reconnect while assigning it a fresh wire ID; cancellation uses the current wire ID and remains idempotent. | Native ownership convention | Generic subscriptions resubscribe; `resubscribe:false` owners rebuild on `ready` | Reconnect/opt-out/exact-wire tests | implemented |
| D02-05 | The URLSession adapter owns one pending receive continuation behind a lock and explicitly resumes it with `disconnected` during cancel/deinit. Late URLSession callbacks are ignored by receive identity. | Swift 5.6/macOS 12 lifecycle safety | Disconnect remains idempotent and every receive completes exactly once | Non-completing production-task adapter regression and live reconnect/disconnect smoke | implemented |
| D02-06 | Outbound frames synchronously enter a FIFO owned by one physical transport generation. Stopping a generation resolves active and queued tickets without requiring an indefinitely suspended native send to return. | Browser `WebSocket.send` is synchronous while macOS `URLSessionWebSocketTask.send` is completion-based; native lifecycle safety | Actual wire IDs remain monotonic; cancelled/expired work is suppressed; an old generation cannot block or retain its replacement | Suspended-send ordering, queued cancellation, reconnect isolation, and never-returning-send weak-retention regressions | implemented |
| D02-07 | Scan the lightweight top-level envelope and pass a copied raw `event` slice to typed subscribers; retain generic `JSONValue` decoding for raw subscriptions, commands, extended envelopes, and mixed coalesced objects. Typed decode runs inside the existing bounded per-owner serial delivery tasks. | Measured Swift performance without changing the browser/macOS transport boundary | Full frame logging, one native receiver, outbound FIFO, event-before-ack, per-owner order/capacity, four-task global bound, cancellation, reconnect generation checks, malformed-frame reconnect, and raw fallback remain intact. | 100k typed fixture, coalesced ordering, blocked decode responsiveness/cancellation, malformed typed owner isolation, raw fallback, existing reconnect/stress/URLSession suites, and live smoke | implemented; 12-hour live publication reduced from 4.735 s to 1.397–1.485 s |

## Implementation result

The 2026-07-28 performance correction adds `HomeAssistantWebSocketEnvelope.swift`. It validates JSON structure while extracting only top-level `id`, `type`, and the `event` byte range for the standard three-field Home Assistant event envelope. Unknown/escaped metadata uses the complete generic decoder. The selected event range is copied before queuing so a small queued event cannot retain a larger coalesced frame. `JSONDecoder` for typed payloads runs in the coordinator's already-bounded detached task, not on the connection actor or in unbounded work. Complete text or base64 frame diagnostics are still emitted before scanning, so explicitly enabled debug logging remains lossless.

### Actual diff scope

- `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift`: actor-owned authentication, IDs, command continuations, subscription records, one receiver, lifecycle stream, automatic reconnect/resubscribe, timeout and cancellation cleanup, coalesced-frame decoding, and bounded ordered delivery.
- `Sources/NativeHACore/HomeAssistantWebSocketTransport.swift`: injectable raw transport and a lock-protected URLSession adapter that owns and exactly-once completes its pending receive during disconnect/deinit.
- `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`: thin Lovelace and typed state-event facade; it no longer receives directly from the socket.
- `Sources/NativeHAMac/DashboardViewModel.swift`: stores the state subscription, observes connection lifecycle, and cancels the subscription/status task and connection at teardown.
- `Sources/NativeHAMac/AppConfig.swift` and `docs/configurability.md`: typed WebSocket policy for the 10-second command timeout, 256-event per-owner delivery capacity, and four active subscriber callbacks per connection.
- `Tests/NativeHACoreTests/HomeAssistantWebSocketConnectionTests.swift`, `HomeAssistantWebSocketMultiplexerStressTests.swift`, `HomeAssistantWebSocketPerformanceTests.swift`, `URLSessionHomeAssistantWebSocketTransportTests.swift`, and `ScriptedWebSocketTransport.swift`: deterministic protocol, production adapter, race, retention, stress, lifecycle, and split XCTMetric coverage.
- This packet and `docs/reference-context/README.md`: durable verifier handoff.

`docs/user-deviations.md` records the approved native scheduling and lifecycle mechanisms needed to preserve the reference's observable WebSocket contract.

### Contract evidence

| Contract | Implementation evidence | Deterministic validation | Result |
|---|---|---|---|
| C02-01 | Auth reads directly only until `auth_ok`, then starts one receiver; version-gated feature ID 1 advertises coalescing and object/array frames share one decoder. Concurrent `connect()` calls share one attempt. | Auth required/ok/invalid, feature wire payload, coalesced frame, concurrent-connect receiver-count tests. | pass |
| C02-02 | One actor allocates command and subscription IDs and owns both lookup maps; pending ownership is installed before an asynchronous send. | Concurrent out-of-order calls, unknown ID, interleaved event/result, 250 command plus 250 subscription owner stress; separate 10,000-event warm-predecoded and decode-plus-dispatch XCTMetric fixtures with exact per-iteration count/checksum and constant-size output state. | pass |
| C02-03 | Subscription wire mapping exists before send; the connection-wide coordinator serializes each owner, caps buffered and active work, and receives unwrapped `event`. Standard typed events use copied `Data.subdata` event slices; raw/extended envelopes retain generic decoding. | Existing event-before-ack, ordering, overflow, bounded callback, 100,000-state typed decode, owner-local malformed decode, and raw fallback tests pass. The new custom-deallocator regression queues a small typed slice from an 8 MiB coalesced frame, cancels its blocked owner, and observes release of the original frame backing before the blocked callback returns. | pass |
| C02-04 | `HAWebSocketSubscription` keeps the original public ID and logical owner; actor cancellation removes local storage first and sends one unsubscribe for the current wire ID. | Exact unsubscribe wire, repeated cancel, late-event suppression, reconnect cancellation. | pass |
| C02-05 | Receive/send failure atomically fails ordinary pending work, drops wire ownership, emits lifecycle state, reconnects with bounded backoff, and resubscribes generic logical owners. The production adapter explicitly completes a pending receive during disconnect and rejects late callback completion. Detached frame scan/decode paths recheck connection generation before dispatch. | Existing failure/reconnect/production-adapter tests pass. A test-only injected boundary hook now gates both the completed envelope scan and completed generic payload decode; reconnect occurs while old work is suspended, release produces no stale delivery, and a replacement-generation event then delivers normally. | pass |
| C02-06 | `resubscribe:false` removes the old owner on disconnect; `statusUpdates()` emits `ready` so Module 01 can rebuild `start_time` and its accumulator. | History opt-out is absent from replacement transport while generic state subscription is recreated. | pass for Module 02 primitive; Module 01 owns the fresh-stream consumer test |
| C02-07 | Result dispatch accepts missing/null success, retains server code/message on failure, and removes continuation ownership once on result/error/timeout/cancel/disconnect. | Null/missing result, concise server error, timeout, task cancellation, send failure, and disconnect cleanup. | pass |
| C02-08 | The client sends the exact display-registry and language preference commands through `call`, decodes compressed `ei`/`dp` plus nullable locale `value`, and Dashboard bootstrap treats these metadata fetches as optional alongside Lovelace. | Existing typed command tests pass. `bootstrapDashboard(using:)` now transfers the client to stored ownership only after config decode and state-subscription success; its catch disconnects first. Two NativeHAMac tests inject malformed Lovelace and rejected state subscription and assert one disconnect, zero active receives, and zero connection-owned pending/subscription/receiver storage. | pass |

### Independent verification result — 2026-07-17

Verdict: remain `verification-ready`. Deterministic routing is green, and the read-only live server accepted the interleaved Lovelace, state, history, ping, reconnect, and unsubscribe flow. Production lifecycle cleanup, non-returning callback retention, and the required performance split do not yet meet the packet's completion requirements.

| Contract | Independent evidence | Verdict |
|---|---|---|
| C02-01 | Swift 5.6.1/Xcode 13.4.1 auth, invalid-auth, feature-ID, coalesced-array, and single scripted receiver tests passed. The live connection authenticated and reached `ready` twice. | pass |
| C02-02 | Concurrent/out-of-order command and 10,000-message exact-owner tests passed; live Lovelace and ping commands completed while two subscription kinds shared the connection. The stress test enters through a serialized JSON array, and no separate predecoded warm-dispatch XCTMetric measurement or baseline exists. | routing pass; performance evidence incomplete |
| C02-03 | Early event, per-owner order, 9,750 exact event deliveries, checksum, and bounded-buffer isolation passed. An external read-only live probe then created and canceled eight history owners whose callbacks deliberately never returned: actor counts were `0/0/0`, but all eight captured 2 MiB payloads remained alive (16 MiB total). `HAWebSocketDeliveryQueue.finish()` clears only its buffer and does not own/cancel the unstructured drain task. Overflow and result-failure paths also await the user `onTermination` callback on the connection actor, so a non-returning termination handler can stop the sole receiver. | fail lifecycle/retention |
| C02-04 | Scripted exact-wire cancellation before and after wire-ID-changing reconnect passed; repeated cancellation sent one unsubscribe and late events were ignored. Live cancellation removed all reported owner/wire storage. | pass |
| C02-05 | Scripted disconnect/send/malformed races and 100 reconnect cycles passed with fake-transport counts at zero. The real URLSession live smoke emitted `SWIFT TASK CONTINUATION MISUSE: receive() leaked its continuation!` once at reconnect and once at final disconnect even though `debugSnapshot()` reported zero. The production adapter wraps `URLSessionWebSocketTask.receive` in a checked continuation, but `disconnect()` only cancels and nils the task; on this required macOS 12-era toolchain the pending callback did not resume. | fail production lifecycle cleanup |
| C02-06 | The scripted replacement transport recreated the generic state owner, omitted the `resubscribe:false` history owner, and emitted its second `ready`. The live smoke observed two `ready` states, one history termination, and recreated history with a fresh timestamp after reconnect; both history streams produced an event. | pass for Module 02 primitive |
| C02-07 | Null/missing success, server code/message, concise diagnostics, timeout, cancellation, disconnect, and send-failure tests passed. Live Lovelace and ping results also resolved with no pending command storage. | pass |

The separate predecoded measurement is necessary for completion, rather than an optional baseline refinement: both the rescue plan and this packet require warm predecoded dispatch to be measured independently from JSON decode plus dispatch with `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. The current stress test supplies correctness and end-to-end XCTest duration only and contains no `measure(...)` call or stored performance baseline.

### Implementation correction result — 2026-07-17

The verifier's three blocking findings were corrected without reopening the green frontend evidence graph:

- C02-05 now has a lock-protected production adapter owner for the pending receive. A deliberately non-completing raw URLSession-task double proves that repeated disconnect resumes the Swift continuation exactly once, cancels the raw task once, clears pending count, and ignores a late callback. The rebuilt real-server smoke repeated auth, concurrent commands/subscriptions, reconnect, resubscribe, cancellation, and final disconnect with no Swift task continuation-misuse diagnostic.
- C02-03 now uses one observable connection-owned callback coordinator instead of one unowned drain task per subscription. With the configured four-task limit, the first wave of eight non-returning callbacks retains exactly four 2 MiB payloads after all owners/buffers are removed; a second eight-owner wave retains none and cannot grow the active count past four. Opening the gate returns active callback count and all weak payloads to zero. A separately gated termination callback remains active while a later command result is routed, proving user termination work does not execute on or stop the sole receiver.
- C02-02/C02-03 now have three independent three-iteration measurements using `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. The two routing fixtures each use 10,000 events across 250 owners; lifecycle performs ten reconnects plus cancel/disconnect and validates zero owned storage.

Baseline from the isolated `swift test --filter HomeAssistantWebSocketPerformanceTests` run on Swift 5.6.1/Xcode 13.4.1:

| Fixture | Scale | Clock mean | CPU-time mean | Physical-memory delta mean | Peak-physical delta mean |
|---|---:|---:|---:|---:|---:|
| Warm predecoded dispatch | 10,000 events / 250 owners | 1.711 s | 1.767 s | 10.923 kB | 0 kB |
| Decode plus dispatch | one 10,000-event JSON array / 250 owners | 2.397 s | 2.482 s | 1,256.128 kB | 0 kB |
| Repeated lifecycle | 10 reconnects plus cancel/disconnect | 0.004 s | 0.007 s | 0 kB | 0 kB |

Memory-delta sampling is allocator-noisy and is recorded as a reproducible baseline, not a hard pass threshold. Lifecycle correctness and monotonic-growth prevention are asserted by deterministic ownership/weak-retention tests.

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

The full suite retained its three existing expected-failure parity markers; no unexpected failure remained. The 10,000-message fixture completed in about 0.606 seconds in the final debug run, delivered 9,750 ordered subscription events plus 250 out-of-order command results with exact checksum, and ended with zero actor-owned pending/subscription/wire/receiver storage. The 100-reconnect fixture completed in about 0.039 seconds and also ended at zero.

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

The two live probes were temporary Swift 5.6 packages under `/tmp` depending on the local `NativeHACore`; they did not modify tracked source or tests. The state event count remained zero because verification deliberately made no state-changing service call. Subscription acknowledgement, concurrent routing, automatic generic resubscription, fresh history ownership, and cancellation were still exercised.

### Fresh independent re-verification after correction — 2026-07-17

Verdict: remain `verification-ready`. C02-01 and the routing part of C02-02 pass; the bounded delivery/lifecycle correction for C02-03 passes; and C02-04 through C02-07 pass. The three performance tests now enter genuinely distinct predecoded-dispatch, decode-plus-dispatch, and reconnect-lifecycle paths, but the warm/memory and repeated-subscription methodology is still insufficient for C02-02/C02-03 completion.

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

The first two metric tests do construct their 10,000-message/250-owner encoded and predecoded fixtures outside `measure`, and all three use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. The failure is narrower: warm the event dispatch path before `measure`, consume each iteration through resettable count/checksum state rather than a monotonically growing value log, and add repeated subscribe/cancel work to the lifecycle metric. Then rerun the three metrics, targeted/full suites, and `git diff --check`; a further frontend audit or another live smoke is unnecessary unless implementation changes touch the wire or production transport lifecycle.

### Final performance-methodology correction — 2026-07-17

This bounded pass changed only `Tests/NativeHACoreTests/HomeAssistantWebSocketPerformanceTests.swift` and this packet. Production Swift, wire behavior, configuration, and the green reference graph were unchanged.

The three fresh-verifier methodology blockers are corrected:

- The warm-predecoded test performs one complete 10,000-event dispatch through `dispatchPredecodedMessages` before `measure`. It waits for exact callback completion and idle delivery, resets the consumer, and therefore excludes warm-up output from every measured iteration.
- Both routing fixtures use a constant-size actor containing only `count` and `checksum`, rather than retaining arrays of delivered integers. The actor is reset before every measured iteration. Each iteration must deliver exactly 10,000 callbacks with checksum `1,245,195,000` and reach zero buffered/active delivery work; an over-count, under-count, cross-iteration callback, or wrong value fails the test.
- Every lifecycle metric iteration creates a fresh connection and performs ten subscribe/ack/cancel cycles plus ten reconnect cycles. Ownership is asserted after every subscription acknowledgement, cancellation, and reconnect. Pending commands, subscriptions, wire subscriptions, buffers, active delivery/termination tasks, pending terminations, and dropped terminations must have their exact expected values; final disconnect additionally requires zero receive loops.

The warm and decode paths remain distinct at identical scale: warm-predecoded dispatch consumes the already-built `[JSONValue]`, while decode-plus-dispatch starts from one encoded 10,000-object WebSocket frame. Fixture construction is outside `measure`. Each metric uses three measured iterations with `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric` on Swift 5.6.1/Xcode 13.4.1.

Corrected isolated baseline from `swift test --filter HomeAssistantWebSocketPerformanceTests`:

| Fixture | Work per measured iteration | Clock mean (RSD) | CPU-time mean (RSD) | Physical-memory delta samples | Peak-physical delta |
|---|---|---:|---:|---:|---:|
| Warm predecoded | 10,000 events / 250 owners, after a separate 10,000-event warm-up | 2.033 s (4.056%) | 2.141 s (2.531%) | -65.536, 0, -81.920 kB | 0 kB |
| Decode plus dispatch | one encoded 10,000-event array / 250 owners | 2.378 s (4.817%) | 2.452 s (5.051%) | 2,113.536, 622.592, 671.744 kB | 0 kB |
| Repeated lifecycle | 10 subscribe/ack/cancel plus 10 reconnect cycles | 0.005 s (3.020%) | 0.007 s (3.090%) | 0, 0, 0 kB | 0 kB |

Physical-memory delta is an allocator page sample and may be zero or negative when pages are returned; it is recorded verbatim rather than converted into an absolute CI threshold. Reproducibility comes from fixed work, constant-size consumer state, three iteration samples, exact count/checksum assertions, and the deterministic lifecycle ownership checks.

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

Verdict: `complete`. A fresh verifier independently inspected the tracked and untracked Module 02 diff, including the final performance-test methodology, then reran every applicable context, performance, lifecycle, targeted, full, and read-only live check on Swift 5.6.1/Xcode 13.4.1 targeting macOS 12. C02-01 through C02-07 pass with no remaining Module 02 blocker.

| Contract | Final independent evidence | Verdict |
|---|---|---|
| C02-01 | Authentication ordering, invalid authentication, feature negotiation, coalesced arrays, concurrent connect, and one steady receiver passed. The live connection authenticated and reached `ready` twice. | pass |
| C02-02 | Concurrent/out-of-order routing and the 10,000-message stress fixture passed. The warm metric performs a completed unmeasured 10,000-event dispatch on the same `dispatchPredecodedMessages` path, resets its two-integer accumulator, and reaches idle before measurement. Every measured iteration resets that constant-size state and requires exactly 10,000 deliveries and checksum `1,245,195,000` before returning idle. | pass |
| C02-03 | Early event delivery, per-owner order, bounded overflow, blocked-termination isolation, the two-wave four-task retention bound, and final cleanup passed. Every lifecycle metric iteration used a fresh connection and performed ten acknowledged subscribe/cancel cycles plus ten reconnects with exact ownership checks after each phase and zero receive loops after final disconnect. | pass |
| C02-04 | Exact current-wire unsubscribe, idempotent cancellation, and late-event suppression passed; the live smoke removed all subscription ownership before disconnect. | pass |
| C02-05 | Disconnect/send/malformed races, 100 reconnect cycles, and the production-adapter exactly-once regression passed. The repeated live reconnect/disconnect smoke emitted no continuation leak, misuse, or double-resume diagnostic and ended at `0/0/0/0`. | pass |
| C02-06 | Generic resubscription, history `resubscribe:false` removal, lifecycle `ready`, and a freshly created live history owner after reconnect passed. | pass for the Module 02 primitive; Module 01 owns the consumer accumulator test |
| C02-07 | Missing/null success, server code/message, concise diagnostics, timeout, task cancellation, send failure, malformed input, and disconnect cleanup passed. Live Lovelace and ping commands also resolved with zero pending ownership. | pass |

The two routing measurements remain distinct at the same scale. Warm-predecoded dispatch consumes the already-built 10,000-element `[JSONValue]`; decode plus dispatch starts with a serialized 10,000-object WebSocket frame, runs `JSONDecoder`, and then enters dispatch. Fixture construction remains outside `measure`. All three fixtures use three iterations of `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. Memory samples are recorded as allocator observations and are not flaky absolute thresholds; deterministic count, checksum, idle, and ownership assertions determine correctness.

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

Verdict: return to `verification-ready`. The focused Module 02 suite remains green, but a deterministic transport test that suspends the first command send after ID allocation reproduces non-increasing wire delivery. C02-02 therefore does not currently prove the send-serialization guarantee that motivated `e4eecb2`.

| Contract | Current evidence | Verdict |
|---|---|---|
| C02-01 | Existing authentication, feature negotiation, coalesced-frame, and single-receiver tests remain green. | pass |
| C02-02 | The tracked 64-command/64-subscription test passes because `ScriptedWebSocketTransport.send` has no suspension before it records a message. In an isolated clone, delaying ID 2 inside a conforming transport allowed ID 3 to arrive first; the strict transport recorded one non-increasing-ID violation and the new test failed. Allocation at `HomeAssistantWebSocketConnection.swift:659` and `:712` is actor-serialized, but the awaited sends at `:677` and `:735` are not connection-wide serialized across actor reentrancy. | fail send serialization |
| C02-03 through C02-07 | The tracked focused suite passed all delivery, retention, cancellation, reconnect, timeout, large-frame, and production receive-continuation regressions. | pass in focused suite |

Separately, later debug instrumentation logs complete text WebSocket frames. With network logging enabled, large history payloads are copied into an unbounded asynchronous SQLite queue and persisted in full. The observed `~/Library/Caches/NativeHA_Logs.sqlite` was 1,586,012,160 bytes across 55 log tables; the focused and full test runs also emitted repeated `database is locked` diagnostics. This instrumentation is newer than the original Module 02 implementation, but it now sits directly on the Module 02 receive path and can add disk growth, memory pressure, and background I/O during long history streams.

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

The full-suite result is not Module 02 evidence: the pre-existing uncommitted `AppConfig.graphRenderEngine = .coreGraphics` override changes graph behavior and accounts for the failures observed outside the WebSocket suites. The focused Module 02 suites were green before the added suspension reproduction.

Exact next actions:

1. Add one connection-owned outbound send serializer that preserves allocation order across commands, subscriptions, unsubscribe commands, feature negotiation, and resubscription even when a transport send suspends. Start timeouts when the serialized send is actually admitted, or explicitly test the chosen queued-time policy.
2. Keep the suspension-capable strict transport regression and rerun the concurrent mixed-ID, cancellation, disconnect, reconnect, and full focused Module 02 suites.
3. Replace full-frame debug logging with bounded metadata or a deliberately capped payload preview, and add SQLite retention/size and busy-handling policy so logging cannot grow without bound or flood diagnostics.

### Native send-order repair and superseded logging policy — 2026-07-28

Verdict: `complete`. An independent verifier reproduced the suspended-send failure and added the first deterministic regression before production changes. The repair adds a synchronous-enqueue FIFO per physical transport generation, then revalidates command or subscription ownership immediately before the queued item reaches `URLSessionWebSocketTask`. This preserves browser-observable monotonic ID semantics without copying the browser's synchronous JavaScript scheduling assumption.

The generation boundary is explicit: an indefinitely suspended send on an old transport cannot block authentication or traffic on its replacement. Stopping that generation resolves its active ticket and releases the serializer even if the underlying transport never completes. A command cancelled while queued is removed from pending ownership and skipped before it reaches the transport. Existing receive-loop, timeout, callback coordinator, history opt-out, 32 MiB receive policy, and production pending-receive cleanup paths were not replaced.

The logging half of the original repair was superseded by user direction. Explicitly selected diagnostics retain complete WebSocket frames and other messages without a database ceiling, character truncation, or queue-admission dropping. WebSocket has its own minimum-severity setting, independent of other network diagnostics. The app selects `warning` now that Module 02 is complete; selecting `debug` records full text frames and base64 binary frames.

Accepted entries enter an uncapped in-memory buffer and SQLite work remains off the caller. The logger commits one explicit WAL transaction every second or after 256 entries, retries complete batches after writer contention, and forces a final flush during normal app termination. This reduces transaction and synchronization overhead without silently dropping accepted entries. A sudden crash may lose the current one-second memory-resident batch; a minute-long interval was rejected as the default because it would enlarge that diagnostic blind spot.

Validation:

```text
swift test --filter HomeAssistantWebSocketConnectionTests
14 tests, 0 failures

swift test --filter HomeAssistantWebSocket
23 tests, 0 failures; includes 10,000-message routing, 100 reconnect cycles,
bounded callback retention, split performance metrics, and URLSession adapter
cleanup

swift test --filter SQLiteLoggerTests
4 tests, 0 failures; independent subsystem thresholds, complete large payload,
single-transaction batching, threshold flush, and lock-contention retry

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges

node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-02.dependencies.json
YELLOW only for known changed NativeHA implementation anchors; pinned
hass-frontend and npm evidence remains unchanged

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

Use a scripted fake transport. Cover auth success/invalid, single object and coalesced arrays, concurrent out-of-order calls, interleaved results/events, event-before-ack, null result, server error propagation, slow subscriber ordering, idempotent unsubscribe, unknown IDs, late events, concise error diagnostics, cancellation/timeout/send failure/malformed JSON/disconnect races, reconnect policy, and final storage counts of zero. Include a high-volume exact-count/checksum stress test.

### Read-only live smoke

Applicable after offline tests. Interleave Lovelace config fetch, state subscription, and a history subscription on one authenticated connection; observe clean cancellation and reconnect. Load connection details from the locations named by the root instructions and keep protocol diagnostics concise. This smoke is read-only and must not replace deterministic tests.

### Visual and animation oracle

N/A: this module owns transport and lifecycle, not pixels. A future reconnect banner belongs to the dashboard-state module.

### Performance and lifecycle

Measure decode+dispatch separately from predecoded warm dispatch. Repeated subscribe/cancel and reconnect cycles must return pending command, callback, and receive-loop counts to zero without monotonic retained-memory growth.

## Open questions and risks

- Generic automatic resubscription, history opt-out, and array-frame support are implemented; these are no longer open design questions.
- The previous production pending-receive continuation leak is corrected and covered by both a production-adapter regression and a rebuilt live smoke.
- Swift cannot forcibly destroy arbitrary async callbacks that ignore task cancellation. Such work now remains visible and consumes one of four global delivery slots until it returns, preventing monotonic retained-task growth. Four permanently non-cooperative callbacks can therefore starve later event delivery; this is an explicit bounded-failure policy documented in `docs/configurability.md`, not hidden zero storage.
- Termination callbacks are receiver-independent and bounded to one active task plus the configured pending capacity. If a termination callback never returns, excess later termination notifications are counted and dropped rather than growing memory or blocking protocol routing.
- Split XCTMetric paths and corrected baselines are now recorded. The warm-up, constant-size resettable consumer, exact count/checksum, and repeated subscribe/cancel methodology gaps are closed. Allocator memory-delta samples remain observational rather than absolute thresholds, so regressions should continue to use the deterministic ownership assertions alongside them.
- Modern frontend state updates use `subscribe_entities`; generic transport must carry its compact event payload, but entity migration belongs to its module.

## Bounded current-anchor refresh for typed subscription delivery — 2026-07-28

The refreshed graph is green at 28 nodes / 59 edges with fingerprint `7caa26b38988ea4eb9ebf235476ed32cd7bef1516667a135ca672c9bfce24a3d`. Reference and npm hashes are unchanged. The reviewed current Swift anchors add the per-generation outbound FIFO, lossless subsystem logging policy, and the following inbound typed-subscription cost:

- `decodeFrame` materializes every object and coalesced array element as `JSONValue` on the connection actor;
- `dispatch` unwraps `event` and the callback coordinator queues `JSONValue`;
- `subscribeMessage` re-encodes that payload and invokes a second `JSONDecoder` for the requested type.

Removing that round trip is compatible with C02 only if the replacement keeps wire-envelope routing separate from feature decoding. A bounded raw-envelope representation may retain `id`, `type`, acknowledgement/error fields, and an exact event payload slice. Typed payload decoding should occur in the existing per-owner serial delivery task so a multi-megabyte history event does not monopolize the connection actor. Raw subscriptions and command results may keep their generic representation until separately measured.

The implementation must not disturb:

- one steady receiver, object plus ordered coalesced-array support, and harmless unknown IDs;
- subscription storage before send and safe event-before-ack delivery;
- bounded callback buffers, the global active-callback cap, per-owner ordering, overflow behavior, termination isolation, and exact cleanup counts;
- logical/wire subscription ownership, idempotent unsubscribe, generic resubscription, history opt-out, and late-event suppression;
- the synchronous-enqueue outbound FIFO, monotonic wire IDs, queued-work ownership revalidation, and physical-generation isolation;
- complete original-frame debug diagnostics when that subsystem is enabled.

Raw payload storage needs an explicit retention test: a queued slice must not retain a much larger coalesced frame after cancellation. Typed decode failure must be tested as a controlled owner-local outcome rather than a shared socket failure. Performance verification should compare current generic round-trip against direct typed decode on the same captured payload and consume equal typed output/checksums.

## Bounded post-fix evidence refresh — 2026-08-23

The pre-refresh checker was yellow only for changed NativeHA anchors in `HomeAssistantWebSocketClient.swift`, `AppConfig.swift`, and `DashboardViewModel.swift`; every pinned hass-frontend/npm anchor remained valid. The complete relevant native diff from the packet's pinned `562686a5649e6d858b191b267f21f206454ad91a` through current `9392bc99c67c4ba3fdae622bf1ef521182e42e69` was reviewed. Reference behavior did not move, so no broad frontend audit was repeated.

Contract changes and strengthened implementation:

- **C02-03 changed:** typed standard event envelopes now bypass the generic `JSONValue` materialize/re-encode round trip. A detached scanner validates object/coalesced-array framing; the connection actor rechecks generation; an exact copied event slice enters the existing bounded owner-serial callback coordinator. Extended/escaped envelopes and raw subscribers retain generic decoding. Malformed typed payloads drop only that delivery and later valid payloads for the same owner still arrive.
- **C02-05 strengthened in code:** frames scanned or decoded off-actor are discarded if the physical connection generation changed or disconnect was requested before actor dispatch. Existing send-generation isolation remains unchanged.
- **C02-08 added:** dashboard bootstrap now issues typed `config/entity_registry/list_for_display` and `frontend/get_user_data` key `language` calls through the shared multiplexer. Native models decode effective `dp`, the frontend locale fields, and nullable `value`.

Unchanged contracts:

- **C02-01/C02-02:** authentication still precedes exactly one steady receiver; command and subscription IDs still share one actor-owned sequence and one physical-generation outbound FIFO with pre-send cancellation checks.
- **C02-04/C02-07:** subscription cancellation remains idempotent and uses the current wire ID; command result, error, timeout, cancellation, and disconnect ownership still complete exactly once.
- **C02-05/C02-06:** generic logical owners still resubscribe with a fresh wire ID. History still opts out, observes `ready`, and replaces its generation, start time, accumulator, and wire subscription; stale history-owner callbacks cannot publish.
- The production URLSession adapter still completes its one pending receive on disconnect and applies the receive ceiling before task resume. AppConfig's WebSocket policy is unchanged at a 10-second timeout, 32 MiB per message, 256 buffered events per owner, and four active callback tasks. The Core Graphics and tooltip additions in the same config file do not alter transport policy.
- `DashboardViewModel.load` still constructs one client with the complete typed policy, stores the successful state subscription, consumes connection status, and tears down established owners. Its newer graph revision-feed publication changes downstream history rendering ownership, not connection routing.

The reviewed manifest now explicitly pins the envelope scanner, history opt-out consumer, typed response models, and exact frontend display/locale command sources. The rebuilt graph has 31 nodes, 61 edges, no cycles, no unresolved edges, and no truncation.

Refresh validation:

```text
node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-02.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 31 nodes, 61 edges, fingerprint
6f86bc91977eecb6fd6cde76d4fda80dd8c9896e8d0c06be5f6d9aa219c3723a
```

### Bounded correction result

The sole correction writer closed all three supervisor findings without changing the protocol contracts:

1. **C02-08 bootstrap cleanup corrected.** `DashboardViewModel.load` delegates connected setup to `bootstrapDashboard(using:)`. That method stores the client only after Lovelace decode and state-subscription acknowledgement; any intervening error disconnects before rethrow. The new macOS lifecycle suite injects malformed Lovelace and rejected state subscription and proves exactly one disconnect plus zero active receives, pending commands, subscriptions, and receive loops.
2. **C02-03 backing retention proven.** A new connection regression allocates an 8 MiB custom-deallocated coalesced binary frame, queues its small typed event behind a blocked owner, cancels the subscription, and observes the large frame deallocator before the unrelated blocked callback returns.
3. **C02-05 detached-decode generation race proven.** A test-only optional hook observes the post-scan and post-generic-decode boundaries. The regression separately suspends old-generation work at both boundaries, reconnects, releases it, proves no stale event arrives, then proves the replacement generation still delivers. Production initialization leaves the hook nil.

The implementer and supervisor reported the following actual passing results:

```text
DashboardBootstrapLifecycleTests
2 tests, 0 failures

HomeAssistantWebSocketConnectionTests
22 tests, 0 failures

HomeAssistantWebSocketEnvelopeTests
4 tests, 0 failures

HomeAssistantWebSocketMultiplexerStressTests
4 tests, 0 failures

URLSessionHomeAssistantWebSocketTransportTests
2 tests, 0 failures

HomeAssistantWebSocketPerformanceTests
3 tests, 0 failures

HomeAssistantHistoryStreamTests
20 tests, 0 failures

HistoryStreamIntegrationTests
3 tests, 0 failures

git diff --check
PASS (no output)
```

This read-only artifact refresh made no further Swift or test edits. The three findings are corrected in the current worktree, but status remains `verification-ready` until a fresh independent verifier reruns the contract-ID audit, applicable tests, and authorized read-only live smoke. No new live-smoke result is claimed here.

### Fresh independent verification after bounded correction — 2026-08-23

Verdict: **GO**. The fresh verifier inspected the corrected source, test, packet, and graph anchors; independently reran the applicable deterministic suites and authorized read-only live smoke; and found no introduced or unexpected failure.

| Contract | Fresh independent evidence | Verdict |
|---|---|---|
| C02-01 | Authentication ordering, feature negotiation, object/coalesced framing, and exactly one steady receiver passed. | PASS |
| C02-02 | Shared command/subscription ID allocation, strict physical-generation send FIFO, interleaved/out-of-order routing, cancellation before send, and stress counts passed. | PASS |
| C02-03 | Direct typed delivery, per-owner ordering, owner-local malformed decode, raw fallback, bounded callback concurrency/overflow, 100,000-state delivery, and the 8 MiB coalesced backing-release regression passed. | PASS |
| C02-04 | Current-wire-ID unsubscribe, idempotent cancellation, local callback removal, and late-event suppression passed. | PASS |
| C02-05 | Exactly-once pending receive/command cleanup, send and receive generation isolation, both deterministic detached scan/decode reconnect races, 100 reconnect cycles, and final zero storage passed. | PASS |
| C02-06 | Generic resubscription and history opt-out remained separate; history rebuilt its request, accumulator, and owner generation after a fresh reconnect and cleaned up fully. | PASS |
| C02-07 | Success/null results, server code/message, timeout, cancellation, send failure, malformed input, disconnect, and exactly-once pending ownership passed. | PASS |
| C02-08 | Exact entity-registry/language commands and typed decoding passed. Malformed Lovelace and rejected state-subscription bootstrap failures each disconnected exactly once with zero remaining receive/command/subscription ownership. | PASS |

Fresh focused validation totaled 60 passing tests:

```text
HomeAssistantWebSocketConnectionTests             22 / 22
HomeAssistantWebSocketEnvelopeTests                4 / 4
HomeAssistantWebSocketMultiplexerStressTests       4 / 4
URLSessionHomeAssistantWebSocketTransportTests     2 / 2
HomeAssistantWebSocketPerformanceTests             3 / 3
HomeAssistantHistoryStreamTests                    20 / 20
HistoryStreamIntegrationTests                       3 / 3
DashboardBootstrapLifecycleTests                    2 / 2
Total                                              60 / 60
```

The authorized read-only live smoke passed 1/1 in 7.339 seconds. It decoded 276 entity-registry display entries, including 74 effective display precisions, and frontend language `en`. Typed history delivery passed for 1h, 12h, and 24h windows; the 12h live card publication contained 102,306 points. A fresh disconnect/reconnect cycle recreated the appropriate owners, final connection and subscription ownership was zero, and no continuation diagnostic appeared. The verifier made no state-changing Home Assistant service call.

Visual/animation verification is N/A because Module 02 owns transport and lifecycle rather than pixels. The only non-failing diagnostics were the known SwiftPM collections-file deprecation warning and allocator-noisy observational performance samples; neither represents a contract failure.

The supervisor gate then reran the same 60-test matrix from the final worktree: 60/60 passed in 25.103 seconds. A separate authorized read-only live rerun passed 1/1 in 10.378 seconds with 276 registry entries, 74 display precisions, language `en`, 1h/12h/24h typed history delivery, 102,311 points in the 12h publication, a fresh reconnect cycle, and final zero connection/subscription ownership. It made no state-changing call. The checker and resolver remained green at the packet fingerprint, and `git diff --check` passed.

### Bounded Module 01 prerequisite-anchor maintenance — 2026-08-23

After Module 02 completed, the bounded Module 01 reconciliation repair changed the shared `DashboardViewModel.swift` file and made the Module 02 checker yellow only for that native anchor. The complete worktree diff was inspected. It adds `desiredHistoryKeys` and a reconciliation epoch, then changes only `loadHistories`, `startHistory`, and `refreshHistorySubscriptions` plus their history status/publication guards below the connection bootstrap boundary.

There is no Module 02 contract change. `load()` still constructs one client with the complete AppConfig WebSocket policy and delegates to `bootstrapDashboard(using:)`. That bootstrap still connects once, runs the typed registry/language/Lovelace commands through the verified shared client, stores client ownership only after the state subscription succeeds, disconnects on any intervening failure, and installs the same connection-status observer. AppConfig's 10-second / 32 MiB / 256-event / four-callback policy is unchanged. C02-08 and C02-01 through C02-07 therefore retain the fresh GO evidence above.

The manifest did not change. Regeneration updated only current repository and native-anchor metadata; the graph remains bounded at 31 nodes / 61 edges with fingerprint `7148dbfcc04d8eae2868612b04e880e4bbed3e2b41247561291e775edb345071`. Contract revision remains 2. This maintenance did not repeat the broad audit, rerun implementation/live tests, or claim new live evidence.

### Bounded post-Module 04 anchor maintenance — 2026-08-23

Module 04 moved four shared native anchors and made this graph yellow. The complete diffs of those anchors were inspected without reopening the reference frontend audit:

- `Models.swift` lost only the old Lovelace declarations, now owned by `LovelaceModels.swift`. The compressed entity-registry response and nullable frontend-language response types named by C02-08 are byte-for-byte unchanged.
- `AppConfig.swift` changed only Lovelace presentation-card matching helpers. `AppConfig.webSocketPolicy` remains 10 seconds / 32 MiB / 256 buffered events / four concurrent callback tasks.
- `DashboardViewModel.swift` now sends a successfully decoded Lovelace config through deterministic presentation/history-owner reconciliation before the state subscription. It still connects once; issues the registry, language, and Lovelace typed calls on the same client; treats the two formatting calls as owner-local optional metadata; subscribes to states through the verified connection API; transfers client ownership only after that subscription succeeds; observes connection status; and disconnects exactly once on any intervening failure. Module 04 adds serialized dashboard/history ownership below that boundary but no second socket receive path or transport owner.
- `DashboardBootstrapLifecycleTests.swift` now accepts Module 04's explicit `LovelaceDecodeError` for a malformed root in addition to `DecodingError`. Its observable assertions remain exactly one disconnect and zero receive, pending-command, and subscription ownership. Both tests passed in the refreshed worktree.

No C02-01 through C02-08 behavior changed, so contract revision remains 2 and the earlier 60-test/read-only-live GO evidence remains applicable. The focused bootstrap lifecycle rerun passed 2/2. The unchanged manifest regenerated a green 31-node / 61-edge graph with fingerprint `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`; the resolver self-test passed at the same fingerprint. No Swift or test file was edited by this maintenance.

## Bounded post-Module 12 anchor maintenance — 2026-08-25

The pre-refresh checker was yellow for exactly six shared Module 12 anchors: `HomeAssistantWebSocketClient.swift`, `Models.swift`, `AppConfig.swift`, `DashboardViewModel.swift`, `HomeAssistantWebSocketConnectionTests.swift`, and `DashboardBootstrapLifecycleTests.swift`. The complete final Module 12 diff for each anchor was inspected against C02 revision 2. The pinned hass-frontend/npm transport sources and all other Module 02 anchors remain unchanged; no broad reference audit was repeated.

- `HomeAssistantWebSocketClient.swift` adds only the typed `auth/current_user` command facade, routed through the same verified connection `call` path. It adds no receiver, ID allocator, subscription map, send queue, or reconnect owner.
- `Models.swift` adds the minimal independent `HACurrentUser.id` response shape. The compressed entity-registry and nullable frontend-locale types for C02-08 are unchanged.
- `AppConfig.swift` adds only the Module 12 primary-view exclusion and selection-persistence policy. The WebSocket policy remains 10 seconds / 32 MiB / 256 buffered events / four active callback tasks; graph range, renderer, tooltip, logging, and render-coordinator policies are unchanged.
- `DashboardViewModel.swift` adds a concurrent optional current-user bootstrap command and exact bootstrap-generation/client guards. Lovelace, registry, locale, and current-user commands still share the one verified connection; current-user failure is owner-local. Required config/state-subscription failure still disconnects owned clients, while overlapping same-client and distinct-client bootstraps cannot let obsolete state/status/config callbacks publish or disconnect current ownership. State batching is now scoped to the installed bootstrap generation. This strengthens C02-05/C02-08 cleanup and late-callback isolation without changing C02 wire semantics.
- `HomeAssistantWebSocketConnectionTests.swift` adds only the exact typed current-user command/decode regression; all existing multiplexer tests are unchanged. `DashboardBootstrapLifecycleTests.swift` expands the production bootstrap harness for optional metadata failure, overlapping candidates, exact installed ownership, and obsolete callback rejection while retaining the existing malformed-config and rejected-state-subscription cleanup gates.

No C02-01 through C02-08 observable contract changed, so status remains `complete` and contract revision remains 2. The fresh Module 12 verifier ran the exact final worktree's 196-test full suite with three authorized skips and zero failures. Its focused bootstrap lifecycle suite passed 9/9; the typed current-user command passed in the full suite. The authorized read-only live smoke passed in 5.085 seconds with current-user ID present, 276 registry entries / 74 display precisions, one-hour/12-hour/24-hour typed history, reconnect coverage, and final command/subscription/wire/delivery/receive ownership zero. No state-changing call was made. Release `NativeHAMac` also built successfully.

Regeneration from the unchanged reviewed manifest is green at 31 nodes / 61 edges, zero unresolved edges, no truncation, and fingerprint `f9462562d7a09d8b37fea24ac7d8d9eebc7767fca7579bcedd489597a8a2ae18`. The resolver self-test passes at the same 31-node / 61-edge fingerprint. No Swift or test file was edited by this maintenance.

## Bounded post-Module 05 anchor maintenance — 2026-08-31

The pre-refresh checker was yellow for exactly six shared Module 05 anchors: `HomeAssistantWebSocketClient.swift`, `HomeAssistantWebSocketConnection.swift`, `Models.swift`, `DashboardViewModel.swift`, `HomeAssistantWebSocketConnectionTests.swift`, and `DashboardBootstrapLifecycleTests.swift`. The exact accepted Module 05 diff and its final independent verification evidence were inspected against C02 revision 2. The pinned frontend/npm transport sources and every other Module 02 anchor are unchanged; no broad reference audit was repeated.

Module 05 adds the typed entity-stream consumer and explicit dashboard lifecycle around the existing connection, while the eighth bounded correction strengthens the connection itself with stable attempt tokens, synchronous old- generation revocation before suspended disconnect cleanup, and authentication- boundary validation. Those changes preserve the one receiver, monotonic wire ID/FIFO send owner, bounded callback dispatcher, direct typed delivery, owner-local cancellation, and exact required-bootstrap cleanup established by C02. The client/model additions introduce no second receive path. Dashboard bootstrap still installs only the exact winning generation/client and retires failed or obsolete candidates. The two changed test classes add deterministic cancellation-insensitive connection races and stronger bootstrap/lifecycle ownership oracles without weakening earlier assertions.

No manifest path moved for Module 02. Regeneration from the unchanged reviewed manifest is green at 31 nodes / 61 edges, zero unresolved edges, no truncation, and fingerprint `da06a3bfa032082ad19743e076372c8a73181f37d75f4f468b60395000afa13d`. The resolver self-test passes at the same 31-node / 61-edge fingerprint. The fresh final Module 05 verifier passed 360/360 race processes, the 237-test full suite with three authorized skips and zero failures, release, GUI, and authorized read-only live smoke with no state-changing call. No C02 observable contract changed, so status remains `complete` and contract revision remains 2. No Swift or test file was edited by this maintenance.

## Handoff

Module 02 is complete and its post-Module 07 evidence graph is green. Preserve the per-generation outbound FIFO, single receiver, bounded callback coordinator, direct typed owner-local decode, production receive cleanup, history opt-out, exact bootstrap generation/client guards, required-bootstrap failure cleanup, and 32 MiB large-frame policy in later modules. Modules 05 and 06 are independently complete, and Module 07 current conditions are independently verified with forecast ownership deferred. The next staged action is Module 08 research only under the approved fixed-server/no-profile assumption, not further Module 02 redesign.

## Change log

- 2026-07-16: initial read-only research packet and deterministic dependency graph created; status `research-ready`, contract revision 1.
- 2026-07-17: reconciled the packet with the merged product-intent, credential, configurability, and phase-routing guidance at NativeHA `78a40f2`.
- 2026-07-17: implemented C02-01 through C02-07 on base `0479555`, added the scripted fake-transport and stress/lifecycle matrix, passed focused and full tests, and advanced status to `verification-ready` for an independent agent.
- 2026-07-17: independent verification passed deterministic routing and the functional live protocol flow, but kept status `verification-ready` for the real-transport receive-continuation leak (C02-05), non-returning callback and termination-path retention (C02-03), and missing split XCTMetric performance evidence (C02-02/C02-03).
- 2026-07-17: corrected all three verifier findings, added production-adapter, two-wave eight-owner retention, gated-termination, and split XCTMetric regressions, passed 17 focused and 37 full tests, repeated the rebuilt live smoke without continuation diagnostics, and kept status `verification-ready` for a fresh independent verifier.
- 2026-07-17: fresh independent verification passed the production adapter, bounded callback ownership, termination isolation, targeted/full suites, and rebuilt read-only live smoke. It retained `verification-ready` for C02-02/C02-03 because the warm metric lacks an unmeasured event-dispatch warm-up, its consumer log grows by 10,000 values per measured iteration, and the lifecycle metric does not repeat subscribe/cancel work.
- 2026-07-17: corrected only the performance test methodology: added a complete unmeasured 10,000-event warm-up, constant-size resettable count/checksum state with exact per-iteration validation, and ten subscribe/ack/cancel cycles alongside ten reconnects per lifecycle iteration. Passed the corrected metric, focused WebSocket, and full suites and kept `verification-ready` for one final independent verifier.
- 2026-07-17: final fresh independent verification passed the corrected performance methodology, isolated critical lifecycle regressions, complete WebSocket and full suites, and a repeated read-only live reconnect/disconnect smoke with no continuation diagnostic and final zero ownership. C02-01 through C02-07 pass; status advanced to `complete`.
- 2026-07-27: a post-fix audit reproduced non-increasing wire IDs when a conforming transport suspends before completing an earlier send, so C02-02 returned to failing and the packet returned to `verification-ready`. The audit also identified unbounded full-frame SQLite debug logging on the WebSocket path as a separate operational regression requiring bounded logging and retention.
- 2026-07-28: independently reproduced both findings, added a per-transport synchronous-enqueue FIFO with cancellation and generation guards, replaced full-frame logging with bounded metadata and bounded SQLite retention and queue policies, then added never-returning-send and locked-database regressions after a final independent lifecycle review. Focused, stress, lifecycle, history integration, and live 1h/12h/24h reconnect validation passed. Status returned to `complete`.
- 2026-07-28: user direction superseded the bounded diagnostic policy. Removed full-message truncation, database and pending-entry ceilings, and silent admission dropping while retaining the independently verified native send-order and lifecycle repairs.
- 2026-07-28: added independent minimum severities for WebSocket and the other diagnostic subsystems. Replaced per-row autocommit with background one-second/256-entry WAL transactions, full-batch contention retry, and a normal-termination flush. WebSocket now defaults to `warning`; `debug` preserves complete frames.
- 2026-07-28: refreshed current typed-subscription, dispatch, send-serializer, reconnect, and cancellation anchors for the measured history-decode follow-up. Recorded the generic payload round trip and the invariants required for raw-envelope/direct-typed delivery. Regenerated a green 28-node/59-edge graph; status remains `complete`.
- 2026-08-23: reviewed every relevant native change since the pinned revision, added exact display-registry/frontend-locale plus typed-envelope/history-opt-out anchors, bumped the packet to contract revision 2 with C02-08, and regenerated a green 31-node/61-edge graph. Focused suites passed, but a supervisor audit found failed Dashboard bootstrap cleanup plus missing coalesced backing-retention and detached-decode generation-race regressions. Status returned to `verification-ready` pending bounded implementation correction and fresh independent verification.
- 2026-08-23: the bounded correction extracted exactly-once Dashboard bootstrap failure cleanup and added deterministic large-coalesced-frame retention plus post-scan/post-decode reconnect-generation regressions. Refreshed exact source and test worktree anchors and regenerated a green 31-node/61-edge graph with fingerprint `6f86bc91977eecb6fd6cde76d4fda80dd8c9896e8d0c06be5f6d9aa219c3723a`. Reported focused, performance, history, and macOS integration suites pass; status remains `verification-ready` for a fresh independent verifier and no new live-smoke result is claimed.
- 2026-08-23: fresh independent verification passed C02-01 through C02-08, all 60 focused tests, and the authorized read-only live formatting, 1h/12h/24h typed-history, reconnect, and final-zero-ownership smoke. No continuation diagnostic or state-changing service call occurred. Status advanced to `complete`; Module 01 bounded evidence refresh is the next gate.
- 2026-08-23: regenerated the Module 02 graph after the bounded Module 01 reconciliation repair moved the shared DashboardViewModel anchor. Complete diff inspection confirmed no change to C02-08 bootstrap, client policy, ownership transfer, failure cleanup, or connection-status behavior. The graph returned green at 31 nodes / 61 edges without a contract revision bump; the fresh Module 01 verifier subsequently returned GO, so bounded Module 04 research is the next gate.
- 2026-08-23: regenerated the graph after Module 04 moved Lovelace declarations, presentation matching, dashboard config/history ownership, and the malformed bootstrap error type across four shared anchors. Exact diff inspection and a 2/2 bootstrap lifecycle rerun confirmed all C02 contracts and the WebSocket policy unchanged. The graph is green at 31 nodes / 61 edges and contract revision remains 2.
- 2026-08-31: inspected the six shared Module 05 anchor changes, preserved all C02 revision-2 transport/bootstrap contracts, and regenerated a green 31-node / 61-edge graph. Status remains `complete`.
- 2026-09-01: inspected the three shared Module 06 anchors, including accepted-generation registry metadata install/reset, and regenerated a green 31-node / 61-edge graph with fingerprint `10d915249a1671df8fa185f4972b614324ec544331f54fcc5c2d20623b8ba506`. C02 revision 2 and transport/bootstrap ownership remain unchanged.
- 2026-09-08: inspected the Module 07 shared config/state model anchors and regenerated a green 31-node / 61-edge graph with fingerprint `26a89dfc1a88704dcb44a2fc97d2c5c41f20bacf0eb79f5816f20ecfb26e9372`. C02 revision 2 transport/bootstrap ownership remains unchanged; Module 08 research only is next.
