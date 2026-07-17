---
schema: nativeha-evidence/v1
module: "02"
title: WebSocket multiplexer and subscription architecture
plan: ../../rescue-plan/module-02-websocket-multiplexer.md
status: research-ready
contract_revision: 1
depends_on: []
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 78a40f22dd278c74af9a81ae47a802fc4a94c1d1
graph_file: ../generated/module-02.dependencies.json
graph_fingerprint: 25f80cc423416c098c50eb9dde41b93ca8e31d18b2946fa6d404a7a915ad10ea
last_validated: 2026-07-17
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

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| C02-01 | Connect/authenticate | Send token only after `auth_required`; accept `auth_ok`, reject `auth_invalid`. Optionally negotiate `coalesce_messages: 1` with command ID 1 on supported servers. | Do not start the steady receive loop until authentication succeeds. If coalescing is advertised, decode both object and ordered-array frames. | HF-01, NPM-02, NPM-03 | New connection actor and transport adapter | Scripted auth and coalesced-frame tests |
| C02-02 | Concurrent commands/subscriptions | Commands and subscriptions share one monotonically allocated ID space and exactly one steady socket receiver dispatches by ID. | Register pending state before send; out-of-order results resolve only their owner; unknown results are harmless. | NPM-01, SW-01 | Connection actor pending-command/subscription maps | Concurrent out-of-order/interleaving tests |
| C02-03 | Subscribe and receive event | Install subscription storage before sending. Successful ack retains it; `{type:"event", event:...}` delivers the unwrapped event payload. | Event-before-ack must be safe. Preserve order within a subscription; slow UI work must not block the socket or create unbounded unordered tasks. | HF-02, HF-03, NPM-01 | Typed subscription API plus serial delivery boundary | Early-event and slow-subscriber tests |
| C02-04 | Cancel subscription | Send `unsubscribe_events` with `subscription` equal to the original subscription command ID. | Cancellation is idempotent; remove local callback even after disconnect; late events do not deliver. | NPM-01, NPM-03 | Subscription handle | Exact-wire, repeated-cancel, and late-event tests |
| C02-05 | Failure/disconnect/reconnect | Reject ordinary in-flight commands with connection-lost, clear ownership, and surface lifecycle state. | Never resume a continuation twice. Implement generic automatic resubscription or keep the remaining parity gap explicit and the module non-complete; stale subscriptions must not silently survive. | NPM-01, HF-04 | Connection actor lifecycle/status events | Disconnect races, cleanup counts, reconnect cycles |
| C02-06 | Reconnect history stream | History disables generic resubscribe, listens for `ready`, rebuilds `start_time`, and creates a fresh accumulator. | Disposal removes listener and current subscription. Reconnect failures are contained for the owner to retry. | HF-02 | Module 01 owner using Module 02 status/subscription API | Module 01 fresh-stream test; Module 02 supports `resubscribe:false` or equivalent ownership |
| C02-07 | Command result/error | `success:true` resolves with result, including missing/null where allowed; `success:false` preserves server code/message. | Remove pending storage once; diagnostics remain concise and do not require full request-payload dumps. | NPM-01 | Command error model and continuation owner | Null result, server error, concise-diagnostics, cancellation, and timeout tests |

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

### NativeHA at `78a40f22dd278c74af9a81ae47a802fc4a94c1d1`

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
`25f80cc423416c098c50eb9dde41b93ca8e31d18b2946fa6d404a7a915ad10ea`.

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
| C02-01, C02-02, C02-05, C02-07 | `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift` (new) | actor-backed connection | Socket, ID allocator, pending commands, receive task, lifecycle | One steady receiver after auth |
| C02-01 | `Sources/NativeHACore/…Transport.swift` (new or internal) | injectable transport + URLSession adapter | Raw frame send/receive/cancel | Fake transport must suspend send/receive independently |
| C02-03, C02-04 | NativeHACore connection/subscription files | typed subscription handle | Callback queue, original ID, idempotent cancel | Preserve per-subscription order |
| Existing feature facade | `Sources/NativeHACore/HomeAssistantWebSocketClient.swift` | thin Lovelace/state wrappers | No raw receive ownership | Keep call sites small during migration |
| Subscription consumer | `Sources/NativeHAMac/DashboardViewModel.swift` | stored subscription token | Cancel on teardown/reconnect | Remove detached raw receive loop |

## Decisions and native deviations

| ID | Decision/deviation | Allowed reason | Preserved semantics | Test | Status |
|---|---|---|---|---|---|
| D02-01 | Use a Swift actor rather than JavaScript maps/event listeners. | Native concurrency convention | Serialized ID/storage ownership and one receiver | Race/interleaving suite | proposed |
| D02-02 | Add command timeout and cancellation cleanup absent or looser in the JS client. | Native lifecycle safety | Successful/error wire behavior remains identical | Timeout/cancel/disconnect races | proposed |
| D02-03 | Deliver callbacks outside actor isolation through a bounded serial mechanism. | Performance and reentrancy safety | Per-subscription order; no cross-routing | Slow subscriber and cleanup stress | proposed |

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

- Choose whether contract revision 1 implements generic automatic
  resubscription directly or first exposes the lifecycle API Module 01 needs
  for a fresh history stream. If generic parity is deferred, record it as an
  outstanding gap and do not mark Module 02 complete.
- Advertising `coalesce_messages` without array-frame support is invalid. It is
  acceptable to defer advertisement and object-array support together, but the
  choice must be explicit.
- Unbounded child tasks would hide callback blocking at the cost of order and
  memory; tests must enforce the selected bounded serial delivery policy.
- Modern frontend state updates use `subscribe_entities`; generic transport must
  carry its compact event payload, but entity migration belongs to its module.

## Handoff

Next action: implement Module 02 contracts C02-01 through C02-07. First run:

```sh
node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-02.dependencies.json
node tools/reference-context/test-resolver.mjs
```

Expected Swift ownership is the new actor/transport/subscription types,
`HomeAssistantWebSocketClient.swift`, `DashboardViewModel.swift`, and new
NativeHACore tests. Do not broadly reread hass-frontend while the checker is
green. After implementation, record decisions/tests here and change status to
`verification-ready` before dispatching the independent verifier.

## Change log

- 2026-07-16: initial read-only research packet and deterministic dependency
  graph created; status `research-ready`, contract revision 1.
- 2026-07-17: reconciled the packet with the merged product-intent, credential,
  configurability, and phase-routing guidance at NativeHA `78a40f2`.
