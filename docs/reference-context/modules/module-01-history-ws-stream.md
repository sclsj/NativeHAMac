---
schema: nativeha-evidence/v1
module: "01"
title: History WebSocket stream and dashboard consumers
plan: ../../rescue-plan/module-01-history-ws-stream.md
status: verification-ready
contract_revision: 1
depends_on: ["02"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 0f6a324aa43c5c508a8304c1767483c0d2edc6f4
graph_file: ../generated/module-01.dependencies.json
graph_fingerprint: 7db0d643160dc350a5646250e83baa6a432911fca03e02465246870a06b75602
last_validated: 2026-07-17
---

# Module 01 evidence packet

## Scope delta

The rescue plan's WebSocket direction is implemented. This packet preserves
the following researched behavior and scope corrections:

- Module 02 already unwraps `{type: "event", event: ...}`. Module 01 consumes
  one decoded `HistoryStreamMessage`; it must not add a second raw-envelope
  compatibility path or another socket receiver.
- The reference accumulator concatenates samples and conditionally performs a
  stable timestamp sort. It does **not** deduplicate equal timestamps or chunk
  boundaries. Fresh reconnect ownership prevents stale pre-reconnect history
  from being merged, but sample deduplication is not a reference behavior.
- `start_time` and `end_time` in stream events describe server chunks. The
  frontend accumulator does not use them as a client cursor. The request's
  `start_time` is computed from the clock when each subscription is created.
- The reference card's `hours_to_show` behavior is overridden by the approved
  NativeHA product intent: the one Home dashboard uses one typed global range
  selector. Preserve raw decoded `hours_to_show`; do not rewrite it to carry
  selected UI state.
- Recorder-statistics merging remains outside this rescue module. The reference
  card fetches hourly statistics for windows of at least one hour and some
  sensor detail views prefer recorder statistics. This is a recorded parity
  gap, not a product deviation and not permission to remove future support.
- Module 01 must implement the foreground stream and current global/detail
  range policy now. On-demand expansion beyond the initial viewport, the
  shared byte-budgeted history/prepared cache, and idle 24-hour prefetch remain
  approved future work. The foreground design must not make them impossible.

Implementation changed NativeHA core/macOS sources, deterministic tests, a
tracked benchmark, the canonical configuration note, the manifest/generated
graph, and this packet/index. It did not change the reference checkout, rescue
plan, canonical user deviations, server state, or Module 02 implementation.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| C01-01 | A normalized `history/stream` event is delivered | Decode `states` by entity ID. Each compact state maps `s` to state, `a` to attributes, optional `lc` to last-changed seconds, and required `lu` to last-updated seconds. Preserve fractional seconds. Missing `a` is accepted as an empty object for server robustness; missing/malformed `s` or `lu` fails that message deliberately. Optional message `start_time`/`end_time` are retained as metadata. | Decode only the unwrapped event supplied by Module 02. Do not confuse compact WebSocket objects with REST `HAHistoryPoint` JSON. | HF-01, HF-T1 | New `HomeAssistantHistoryStream.swift` models/decoder | Hand-written decode fixtures for present/absent `lc`, present/empty/missing `a`, fractional values, optional chunk metadata, malformed required fields, and REST/stream shape separation. |
| C01-02 | Initial replay, empty completion event, or incremental chunk | Maintain combined history with the same entity-union and rolling-window behavior as `HistoryStream.processMessage`. The first non-empty history becomes the baseline; an empty `states` object leaves current history unchanged. Existing+incoming arrays concatenate; if the incoming first `lu` is older than the existing last `lu`, stable-sort by `lu`. Preserve equal-timestamp arrival order and exact duplicate samples. | On a later merge, trim against an injected `now - range`: retain all states at/after cutoff and prepend the last expired state at exactly the cutoff with `lc` cleared unless a state already exists at the cutoff. A newly introduced entity follows the reference's early-return branch and is first eligible for rolling trim on a later merge. Safely handle empty per-entity arrays rather than trapping. Chunk `start_time` is not a merge cursor. | HF-01, HF-T1, HF-T2 | Pure `HAHistoryStreamAccumulator` with injected clock | Fixed-clock tests for first/empty/multiple-entity messages, absent/new entities, in/out-of-order chunks, equal timestamps and duplicates, boundary-state rewrite, exact-cutoff no-duplicate behavior, and the new-entity trim timing. |
| C01-03 | A card/detail owner begins a foreground time-window subscription | Send `type: "history/stream"`, ordered `entity_ids`, ISO-8601 `start_time = now - effective range`, `minimal_response: true`, `significant_changes_only: true`, and computed `no_attributes`; omit `end_time` so the stream remains live. `no_attributes` is false if any requested entity is absent from current states or belongs to `climate`, `humidifier`, `input_datetime`, `water_heater`, `person`, or `device_tracker`; otherwise true. | Parameters are immutable for one wire owner. Range/entity changes cancel it and construct a new owner. The default booleans are server-side request semantics, not client filters. | HF-01 | Typed history method on `HomeAssistantWebSocketClient` plus request builder | Exact fake-transport wire assertions for ordered IDs, each boolean, ISO start, no end, explicit clock, all six attribute domains, mixed domains, and missing/current entity state. |
| C01-04 | Initial connection, disconnect/reconnect, or explicit disposal | Create exactly one initial stream using Module 02 `resubscribe: false`. After a disconnect, the next `ready` creates exactly one new request with a recomputed `start_time` and a fresh empty accumulator. Each callback publishes that accumulator's complete combined history. | Module 02's status stream yields its current state immediately, so the coordinator must not double-subscribe on the initial `ready`. Disposal cancels the current subscription and lifecycle listener. Late events and old-generation callbacks cannot publish. Initial subscribe rejection surfaces to the owner; reconnect subscribe failure is contained, exposed as owner error/status, and retried only on a later readiness or explicit refresh—not a busy loop. | HF-01, NPM-01, M02-C06 | History subscription coordinator built only on Module 02 connection/status APIs | Two-transport fake test proving one initial subscription, old history opt-out, a second fresh ISO start and accumulator after `ready`, no stale merge/duplicates, idempotent disposal, failed-resubscribe containment, and final Module 02 ownership counts of zero. |
| C01-05 | Combined compact history is projected for graph/timeline consumers | Centralize conversion instead of scattering seconds-to-ISO or compact-key logic through views. Preserve every non-empty timeline state including `unknown`, `unavailable`, and `none`; collapse consecutive equal states only in timeline preparation. Numeric line preparation skips values it cannot parse without removing them from stored history. Use `lc` when present, otherwise `lu`, except line data for `climate`, `humidifier`, and `water_heater` uses `lu`; retain the reference line attributes needed by those domains. Current/first attributes remain available for classification and names when minimal responses omit later attributes. | Preserve deterministic timestamp order and fractional precision. Do not mutate the stored compact history merely to satisfy a renderer. | HF-01, HF-T2, SW-01, SW-05 | New centralized compact-to-graph adapter plus existing `HistoryGraphSupport`/render preparation | Timeline unknown/unavailable/none; numeric gaps; repeated state; climate/humidifier/water-heater `lu`; sparse attributes; current-state fallback; compact-to-existing-series precision tests. |
| C01-06 | Dashboard config loads, global range changes, a detail opens/closes, or visible history owners change | The intended Home dashboard owns foreground subscriptions for visible history cards only; each card publishes only to its own state. Effective range comes from a typed `AppConfig` policy with available selections, default, global scope, and detail default. Subscription/cache identity includes deterministic card identity, ordered entity IDs, and effective range; it must not depend on regenerated `UUID()` values. Preserve raw decoded `hoursToShow`. Detail history uses the configured detail range and cancels when its sheet disappears or identity changes. | Range changes cancel old owners before publishing a new generation. Overlapping entity sets remain isolated. Until Module 12 exists, do not subscribe the hidden maintenance views. Do not append `state_changed` events into an active history stream; state events continue to update current entity state only. | HF-02, HF-03, UD-01, CFG-01, SW-04, SW-05 | `AppConfig`, `DashboardViewModel`, `DashboardView`, `HistoryGraphCard`, `DetailHistoryGraph` | Two-card isolation, stable identity across recomputation, ordered-ID distinction, 1h/3h/12h global changes, raw-hours preservation, detail lifecycle, and no double append from state changes. Replace the obsolete per-card-hours expected failure with a passing approved-policy test. |
| C01-07 | Loading, replay, update, cancellation, server rejection, overflow, profile/connection change, or owner disappearance | Expose deterministic per-owner loading, ready-data, and error outcomes. One failed or slow history owner cannot erase/block another. Cancellation/profile teardown removes the owner promptly; an old callback cannot recreate UI state or prepared data. Explicit refresh renews the affected subscriptions. | Generation checks precede main-actor publication. UI publication is main-actor isolated, while decode/merge/preparation must not monopolize it. Delivery overflow and non-disconnect termination surface concise owner errors. | HF-02, HF-03, M02-C03, M02-C04, M02-C07 | History coordinator and `DashboardViewModel` ownership | Fake rejection/overflow/late-event tests, cancellation during replay/merge, profile teardown, simultaneous owners with one blocked, weak-release/lifecycle probe, and exact final connection counts. |
| C01-08 | Replay or incremental content reaches a rendered card/detail | Loading settles to a graph/timeline; every accepted combined-history publication invalidates the relevant prepared/render state even when count and first/last timestamps happen to match prior data. Incremental history updates only the affected visual owner. Selected range defines the initial viewport. | Render preparation stays asynchronous/cancellable, foreground work outranks future cache/prefetch, and stale render generations cannot replace newer data. No scheduler-driven animation is required by the stream itself. | HF-02, HF-03, SW-06 | Dashboard graph inputs and prepared-series invalidation/generation | Offscreen loading→replay→incremental states; same-count/same-endpoint content replacement regression; bounded settlement; replay/update PNG distinction; dismissal remains responsive during a gated slow merge/render. |
| C01-09 | Normal app history path versus command-line benchmark/probe path | `NativeHAMac` history cards and detail graphs use WebSocket `history/stream`, not REST `/api/history/period`. Keep `HomeAssistantRESTClient.fetchHistory` and REST-shaped models available for `GraphBench`, `GraphPyramidBench`, and `HAProbe` until separately migrated or retired. | No silent REST fallback in normal rendering: it would change streaming/error semantics and hide failures. Stream and REST decoders remain distinct. | SW-01, SW-02, SW-04 | App orchestration; existing REST client remains tool-owned | App integration spy proves zero REST history calls; existing REST tests and tool builds still pass; stream fixtures fail the REST decoder and vice versa. |

## Source anchors

### hass-frontend at `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`

- **HF-01** — `src/data/history.ts`, especially
  `EntityHistoryState` (line hint 78), `HistoryStreamMessage` (89),
  `entityIdHistoryNeedsAttributes` (95), `HistoryStream.processMessage`
  (141/154), `subscribeHistoryStatesTimeWindow` (239),
  `subscribeHistoryStream` (281), and compact-data projection beginning near
  335. Git blob `5a3c3e8f8fa02c7a081a1ddb0fea875bd40147e2`, SHA-256
  `055be2c7ce23ba96de01948e8af51c1f3c699d0580f7d49c22ffc662eb19470c`.
- **HF-02** —
  `src/panels/lovelace/cards/hui-history-graph-card.ts::HuiHistoryGraphCard`,
  line hints 81, 142, 147, 236, and 267. Git blob
  `9b6bb306ca29ecfc4e028cab468c5f826a0ed1a5`, SHA-256
  `f20a8c88f513571917cb2471f034682c9bd09ff83570b44531664a75118ba7cd`.
  The literal reference default is 24 hours, but UD-01 overrides its per-card
  range choice for NativeHA.
- **HF-03** —
  `src/dialogs/more-info/ha-more-info-history.ts::MoreInfoHistory`, line hints
  34, 161, 166, and 230. Git blob
  `2f75e720fd4be4a91a45adffa51fb70deaf7a90e`, SHA-256
  `fc4e6bd1b2aa3967e56646a6d5ec56e16625d71429b585d536f6715f13b52a74`.
  It owns a 24-hour stream fallback but may prefer recorder statistics for
  eligible sensors; statistics are outside Module 01.
- **HF-T1** — `test/data/history.test.ts::HistoryStream.processMessage`, Git
  blob `76397a28de780dda5cd8d3c0eab4b5cd4ebaf04d`, SHA-256
  `01d05009cae89da93e4b1aa4576c181d712e1ab3977829f5d56ad3b27f19b4f1`.
  Pins cutoff-boundary `lc` clearing and no-expiry behavior.
- **HF-T2** — `test/data/history-characterization.test.ts`, especially
  `HistoryStream characterization` near line 135, Git blob
  `0bcbfd3d480d01a62f5741a6e253470d332a029c`, SHA-256
  `bc065e1a4726c2e3ec804fdc4de4ceca2ae91184c68e194753e2fc8ad4a9fcc1`.
  Pins multi-entity, absent/new-entity, out-of-order, compute/projection, and
  large mixed-payload behavior.
- **HF-B01** — `test/benchmarks/history-stream.bench.ts`, Git blob
  `f5b3cf5ff7af5221cdb918e32518a9fc05fb00da`, SHA-256
  `c984b4b7c1d36336f15c7bda3d98e6cd115122572af0171fd7559f27e3e004d2`.
  Reference fixture: five entities, 25,000 initial states, then twenty
  incremental messages of ten states per entity with two warm-up iterations.

### npm runtime boundary reused from Module 02

- **NPM-01** — `home-assistant-js-websocket@9.6.0`,
  `dist/connection.js::Connection.subscribeMessage` around line hint 291,
  SHA-256
  `884929a38078cc51cb47b0d7d8a821ef99bc784bcd50792bf9b044f936db69e8`.
  Package.json SHA-256
  `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`;
  Yarn locator `home-assistant-js-websocket@npm:9.6.0`, checksum
  `10/0eded7864632b5e19e92289ffac0e24308b1e8f425e292ae87ed21450852f7705db521e202614b1d5bbdb7948633143dce2524ed548db0c38486b40ed1ffa474`.
  This is a provenance anchor only; [Module 02](module-02-websocket-multiplexer.md)
  already verified its routing, unsubscribe, and `resubscribe:false` behavior.

The reference lockfile is `yarn.lock`, SHA-256
`ca345f66a74a1054b77bd2f47f20cb9e13e79b2c864f3375822cca9b14ff41b6`.

### NativeHA pre-implementation baseline at `92e9a2bf95f7dd2cfd649bba2bc0ac8dbbbccb19`

These anchors explain the implementation starting point. The current working
tree is based on `0f6a324aa43c5c508a8304c1767483c0d2edc6f4`; its exact implementation and
test hashes are pinned in the regenerated dependency graph rather than copied
by hand here.

- **SW-01** — `Sources/NativeHACore/Models.swift::HAHistorySeries`,
  `HAHistoryPoint`, and `LovelaceCard`, line hints 69, 81, and 119. Git blob
  `69494d1d1b4f7b298cc294275269e04b8d24920b`, SHA-256
  `5a9d62407b1f072cc8627a35b40fbbf6d82dbf61d1346cbf3b9aadb855bc5fc2`.
- **SW-02** —
  `Sources/NativeHACore/HomeAssistantRESTClient.swift::fetchHistory`, line
  hint 29. Git blob `f57d2d4e20eaa8271085dfda7985b292b9fc6332`, SHA-256
  `954c494e8eef10a9c15b98342b72f20dc1d982c67bc378c36f6f33b2707380e8`.
- **SW-03** — `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`, Git
  blob `96434a2930fd14a3751872b9c567c3938cd32498`, SHA-256
  `8aba0fb19193a7806801adc0480f2e92316c0594a82de4096fc3ffcb9d19c7fa`;
  and `HomeAssistantWebSocketConnection.swift::statusUpdates`,
  `subscribeRaw`, and `subscribeMessage`, line hints 257, 316, and 360, Git
  blob `a432522113ff1d044be8c497cc5f066e7504669b`, SHA-256
  `62604bdd77b88b4fa7730c6620521daefd6211482fd0ca74cdb882ec70dd4ec6`.
- **SW-04** — `Sources/NativeHAMac/DashboardViewModel.swift`, especially
  `historyKey` (301), `load` (383), REST `loadHistories` (486), realtime
  history append (527), requests (767), and `cleanCards` (797). Git blob
  `0d0a6e96b6c3c143ce80db4e3626d2a87ae8b09f`, SHA-256
  `86a442ecec0a61db8cf30b5c16579f16a7d78b48a3fc24fd44e9a6dabeb78edb`.
- **SW-05** — `Sources/NativeHAMac/AppConfig.swift`, line hints 13-20, Git
  blob `8e3b7f7abfa487125cb3593f97ef1e7d1aced981`, SHA-256
  `ac0473f4ee44bfef7469aaaa85d93e7a39818845428ad3c62eb1f0c87c4edb6e`;
  and `Sources/NativeHAMac/CardViews.swift::HistoryGraphCard` (224),
  `UnitGraph` (302), and `DetailHistoryGraph` (1685), Git blob
  `c7424667fcf86ffb8f147faa7d75703077ed4961`, SHA-256
  `a8861dc6f58730db7344aebc0dec80c9e9326c405dd157af3bc27c6939dd2f18`.
- **SW-06** — `Sources/NativeHAMac/GraphRendering.swift`, especially compact
  preparation/filtering near 602 and the 96-entry prepared cache/fingerprint
  near 550/745. Git blob `ad68bdc79988205ecbdb8d1118d6af5715577b1c`,
  SHA-256
  `9ebca6835af2e08d7a86e228c72acd07bb3fa6e98b3501b5cf418d4267ac1efe`.
- **SW-T1** — `Tests/NativeHACoreTests/HistoryGraphSupportTests.swift`, Git
  blob `8e53e421fb762291ef42236154851bf567090e7f`, SHA-256
  `a6c8e31d9186203f707d37af49cff1a7ed265b9d501fef91c58d2080f29cc8af`.
  It already preserves unknown/unavailable timeline segments.
- **SW-T2** — `Tests/NativeHAMacTests/GraphRenderingTests.swift`, Git blob
  `ba2a2145f7a7a1c08b366e66dbbde3629c01a0d5`, SHA-256
  `57ca19e9d766040e89dcd838c36d58cf0ca1378c1ecaaa6a00a08eb164e6c9c0`.
  Its per-card-hours expected failure conflicts with UD-01 and must be replaced
  by the approved effective-range contract.

## Dependency traces and boundaries

The generated graph is
[`module-01.dependencies.json`](../generated/module-01.dependencies.json),
fingerprint
`7db0d643160dc350a5646250e83baa6a432911fca03e02465246870a06b75602`.
It contains 21 nodes and 143 edges, one editor/card dynamic-import cycle, no
unresolved edge, and no truncation.

- `src/data/history.ts` is the stream/request/accumulator entrypoint. Its only
  behavior-relevant runtime import for these selected symbols is
  `common/entity/compute_domain.ts`. Imports of `HomeAssistant`, `MessageBase`,
  and entity types are type-only boundaries.
- `HomeAssistant.connection` is dependency-injected through a TypeScript type,
  so static imports cannot discover the runtime subscription owner.
  `home-assistant-js-websocket/dist/connection.js::Connection` is an explicit
  seed. Traversal stops at the already-complete Module 02 contract rather than
  re-auditing the package.
- `HuiHistoryGraphCard` and `MoreInfoHistory` are explicit consumer seeds.
  Their direct edges to `data/history.ts` establish subscription and disposal
  ownership. Downstream chart, color, tooltip, editor, translation, and Lit
  internals are visual/framework boundaries for Modules 09/12, not stream
  semantics. Recorder/statistics edges are the explicit scope deferral above.
- The reviewed maximum depth is one because every behaviorally relevant
  cross-boundary owner is explicitly reseeded: `history.ts`, the two consumers,
  and the injected package connection. The 69 recorded max-depth edges all
  leave direct consumer support files for chart/editor/recorder/framework work;
  none determines the C01 stream protocol, merge, reconnect, or cancellation
  behavior. Six unallowlisted runtime package edges are Lit/date-fns UI support;
  only `home-assistant-js-websocket` is followed.

## Module 02 prerequisite mapping

| Module 01 need | Verified Module 02 contract | Required use |
|---|---|---|
| One receiver and ID routing | C02-02/C02-03 | Use `subscribeMessage`; never receive raw frames in history code. |
| Unwrapped event payload | C02-03 | Decode `HistoryStreamMessage` directly, not `{event: ...}`. |
| Exact/idempotent unsubscribe and late-event suppression | C02-04 | Store/cancel the returned subscription handle and add owner generation checks. |
| Fresh history on reconnect | C02-05/C02-06 | Pass `resubscribe: false`; observe `ready`; make a new request and accumulator once. |
| Bounded delivery/errors | C02-03/C02-07 | Keep merge work off the receiver path and surface owner-specific termination. |

## Native mapping

| Contract | Existing/planned Swift path | Symbol/type | Ownership/state | Notes |
|---|---|---|---|---|
| C01-01, C01-02, C01-05 | New `Sources/NativeHACore/HomeAssistantHistoryStream.swift` | compact models, accumulator, projection | Pure/sendable values with injected clock | Keep compact seconds authoritative; centralize any legacy-series adapter. |
| C01-03, C01-04, C01-07 | `HomeAssistantWebSocketClient.swift` plus the new history file | typed subscription/coordinator | Current wire handle, lifecycle task, generation, fresh accumulator | Built only on Module 02; exactly one initial subscription despite immediate status yield. |
| C01-06 | `Sources/NativeHAMac/AppConfig.swift` | typed graph time-range policy | available/default/global/detail values | Future expansion/cache fields may be represented, but their behavior is deferred below. |
| C01-06, C01-07, C01-09 | `Sources/NativeHAMac/DashboardViewModel.swift` | card/detail owner registry and published history | main-actor publication; async owner tasks | Remove app REST loads and realtime double-append path for active streams. |
| C01-06, C01-08 | `DashboardView.swift`, `CardViews.swift` | global selector, card/detail lifecycle | visible Home card/detail ownership | Preserve raw config and cancel on disappearance/key change. |
| C01-05, C01-08 | `HistoryGraphSupport.swift`, `GraphRendering.swift` | compact projection and prepared-series invalidation | cancellable background preparation with generation | Fix same-shape replacement invalidation without turning Module 01 into a graph-render rewrite. |
| C01-09 | `HomeAssistantRESTClient.swift`, benchmark/probe targets | existing REST client | tool-only until later migration | Do not delete or silently use as app fallback. |

## Decisions and native deviations

| ID | Decision/deviation | Allowed reason | Preserved semantics | Evidence | Test | Status |
|---|---|---|---|---|---|---|
| UD-01 | One typed global graph-range selector on the intended Home dashboard overrides the reference card's independent `hours_to_show`; raw values remain decoded. | User-approved product intent | Requested/displayed visible graphs share the selected effective range; raw Lovelace remains available. | [User deviations](../../user-deviations.md#dashboard-graph-time-range), CFG-01 | Range/key/request/raw-model matrix | approved; Module 01 current scope |
| UD-02 | Selected range is an initial viewport, not the eventual zoom-out maximum. | User-approved future intent | Current selected-window stream remains reference-correct; later expansion fetches/reuses older coverage. | [User deviations](../../user-deviations.md#expand-graph-history-beyond-the-initial-range) | Current range tests now; expansion tests later | approved; behavior deferred |
| UD-03 | Idle 24-hour prefetch and range-aware shared cache are lower-priority, cancellable, deduplicated, and budgeted. | User-approved future intent/performance | Foreground stream correctness and responsiveness remain primary. | [User deviations](../../user-deviations.md#idle-history-prefetch-and-range-reuse), CFG-05 | Cache coverage/priority/cancellation benchmarks later | approved; behavior deferred |
| D01-01 | Use Swift value types/actors and an injected clock rather than mutable JavaScript objects/listeners. | Native platform convention and determinism | Same wire fields, rolling window, ordering, and fresh reconnect outcomes. | C01-01 through C01-04 | Fake clock/transport suite | implemented |
| D01-02 | Safely accept missing `a` and empty per-entity arrays instead of crashing on malformed/sparse server data. | Native robustness | Valid server history behavior and attributes remain unchanged. | C01-01/C01-02 | Sparse/malformed fixtures | implemented |
| D01-03 | Use an exact stable two-way merge when existing and incoming arrays are each ordered, with a full stable-sort fallback for unsorted input. | Swift performance optimization proven against the reference output | Equal-timestamp arrival order, duplicates, cutoff behavior, and all projected values remain byte-for-byte equivalent in the tracked fixture. | C01-02, HF-01 | Unit fixtures plus `HistoryStreamBench` | implemented; benchmarked |
| GAP-01 | Do not implement recorder statistics merge in this rescue module. | Explicit rescue-plan scope boundary, not an approved product deviation | State history streaming is preserved; future statistics parity remains visible. | HF-02/HF-03 | N/A for completion; retain documented gap | deferred parity work |

There is no unresolved product choice. Implementation mechanics such as a
dedicated coordinator actor versus actor-isolated client state are left to the
single Swift writer as long as the contracts and Module 02 ownership hold.

## Approved future work — not Module 01 completion gates

Module 01 must leave seams for these approved behaviors but must not silently
claim them as implemented:

1. **On-demand range expansion:** zooming beyond the initial selected window
   requests/reuses older coverage asynchronously. It is cancellable, generation
   safe, globally configurable with optional per-graph override and maximum,
   and never blocks pan/dismissal. This likely coordinates with Module 09.
2. **Shared range-aware cache:** raw history and prepared series share the
   configurable 1 GiB upper budget, can satisfy a contained 1-hour request from
   24-hour coverage, fetch only missing ranges when safe, expose stats/reset,
   and have deterministic eviction/byte accounting.
3. **Idle dashboard prefetch:** after dashboard config is available, fetch a
   configurable default 24-hour window for all referenced entities at lower
   priority than foreground input/live updates. Foreground and prefetch requests
   deduplicate by coverage; cancellation/profile changes discard stale work.

The foreground accumulator's rolling trim is subscription-local. It must not
be reused as a future shared cache eviction policy or discard broader coverage.

## Validation requirements

### Offline deterministic tests

Use `ScriptedWebSocketTransport`, an injected clock, and small hand-written
fixtures for semantics; generated fixtures cover scale. At minimum:

- C01-01: all compact field combinations, fractional seconds, chunk metadata,
  malformed required fields, and REST/stream decoder separation.
- C01-02: first/empty/multi-entity, absent/new entity, unordered/equal/duplicate
  timestamps, stable ordering, fixed cutoff, preserved boundary state with
  cleared `lc`, exact-cutoff behavior, and safe empty entity arrays.
- C01-03: exact command dictionary and every attribute-policy branch.
- C01-04/C01-07: event before/after acknowledgement as supported by Module 02,
  one initial owner, fresh reconnect request/accumulator, resubscribe failure,
  repeated cancel, late callbacks, profile teardown, owner-specific overflow,
  and zero final pending/subscription/wire/buffer/receive ownership.
- C01-05: domain timestamp/attribute policy, unknown/unavailable/none timeline,
  numeric nonnumeric gaps without stored-data deletion, and current-state
  fallback.
- C01-06: two overlapping cards remain isolated; deterministic card identity;
  ordered IDs; global 1h/3h/12h changes; raw `hoursToShow` unchanged; detail
  open/close; state changes do not double append.
- C01-08: same count/first/last with changed state content invalidates prepared
  output; old generation cannot publish after a replacement.
- C01-09: app REST history call count remains zero while REST tests and all
  benchmark/probe targets compile.

### Read-only live smoke

Applicable after deterministic tests. Load the server/token from the root-named
locations. On one authenticated Module 02 connection:

1. subscribe a small live-dashboard entity set for 1 hour;
2. decode the initial replay and completion/incremental chunks;
3. verify ordered entity ownership, compact fractional timestamps when present,
   and the actual `no_attributes` policy result;
4. cancel and confirm final ownership is zero;
5. force one read-only reconnect, observe a later `ready`, and verify one fresh
   start time/fresh accumulator with no old merge;
6. repeat a representative 24-hour read for performance/correctness evidence.

No service call or state mutation is needed. A live smoke validates integration,
not accumulator edge cases.

### Visual and animation oracle

Module 01 has a visible integration result even though Module 09 owns drawing.
Follow [visual testing](../../visual-testing.md): render fixed 496×260-point,
2× history cards for numeric and timeline data through loading, settled replay,
and settled incremental update. Use fixed UTC source times and explicit
Asia/Shanghai display timezone where the production formatter permits. Write
inspectable artifacts, assert signature/dimensions/nonblank/settled regions,
and require replay/update images to differ. Only manually reviewed comparable
hass-frontend images may become tolerant baselines.

No stream-layer animation is required. If implementation adds data-transition
animation, render progress 0/0.5/1 and reduced motion; the final frame must equal
the nonanimated result. A gated slow merge/render must not block detail-sheet
dismissal or unrelated controls.

### Performance, cache, and lifecycle

- Reproduce the reference scale (five entities, 25,000 states, twenty
  incremental chunks) and the rescue-plan 20,000-state/100×200-state fixtures.
  Measure decode separately from merge, cold replay separately from warm
  incremental work, plus adversarial out-of-order and rolling trim.
- Use constant-size count/checksum consumers and construct fixtures outside
  measured blocks. Use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`;
  record baselines rather than aggressive machine-specific limits.
- Exercise at least 100 card/detail subscribe/cancel cycles and reconnect cycles
  with final zero Module 02/storage counts and weak-release evidence.
- Compare live 1-hour and 24-hour correctness, time, CPU, and memory. If a Swift
  merge algorithm choice is genuinely unclear, benchmark sensible candidates
  under `Benchmarks/<topic>/` before selecting; preserve exact output.
- No shared history cache is implemented in Module 01, so cold/warm cache-hit
  acceptance is N/A now. Verify instead that subscription-local trimming does
  not mutate any separately retained broader fixture and that the existing
  prepared cache cannot return stale same-shape content.

## Open questions and risks

- **Stable card identity:** `LovelaceCard.id` is a random UUID and `cleanCards`
  rebuilds cards. Do not use it for long-lived stream ownership. Derive a
  deterministic traversal/config occurrence identity without waiting for
  Module 04, and keep it replaceable when decoding is expanded.
- **Immediate status yield:** `statusUpdates()` immediately yields `.ready` to
  a listener added after connection. A naive initial subscribe plus listener
  will create two initial history subscriptions.
- **No reference sample deduplication:** applying the current realtime merge's
  timestamp replacement rule to stream chunks would change frontend behavior.
  Request/coverage deduplication for future cache work is different from sample
  deduplication.
- **Timestamp policy:** blindly adapting compact states to an ISO model whose
  parser always prefers `last_changed` breaks the reference's `lu` rule for
  climate/humidifier/water-heater line data.
- **Prepared-cache invalidation:** current fingerprints use count and first/last
  timestamps. Fresh replay content with the same shape can be stale unless the
  stream generation/content participates in invalidation.
- **Sparse attributes:** minimal responses make later attributes sparse. Keep
  current/first attributes available and calculate `no_attributes` correctly;
  otherwise climate/person/device-tracker classification or display regresses.
- **Scope coordination:** Module 12 later defines visible views; Module 09 later
  expands range/interaction; recorder statistics remains a visible parity gap.
  Module 01 should expose ownership seams, not implement those modules now.

None of these is a material behavior question: each has a contract and
deterministic acceptance test. The implementation owner addressed the current
Module 01 risks; the approved future work remains explicitly deferred.

## Implementation result

The single Swift implementation owner completed the module on the working tree
based at `0f6a324aa43c5c508a8304c1767483c0d2edc6f4`:

- `HomeAssistantHistoryStream.swift` now owns compact stream decoding, exact
  accumulation, projection, attribute policy, reconnect coordination, and
  cancellation. The WebSocket client exposes a typed
  `subscribeHistoryStatesTimeWindow` facade over Module 02 with
  `resubscribe: false`.
- `DashboardViewModel` now owns independent visible-card/detail stream
  subscriptions and generation-checked publication. The normal app history
  path no longer calls REST or appends `state_changed` samples. The REST client
  remains available to the benchmark/probe tools.
- `AppConfig` supplies the typed global 1/3/6/12-hour policy and 24-hour detail
  default. Deterministic traversal occurrence identity replaces regenerated
  UUID ownership while raw decoded `hoursToShow` remains unchanged.
- `HAHistorySeries` has a deterministic content revision, and graph preparation
  only reuses incremental work when content truly grows. Same-shape replacement
  therefore invalidates prepared/rendered output.
- Deterministic core, integration, rendering, lifecycle, performance, and
  opt-in live-smoke tests cover the contracts. `HistoryStreamBench` records the
  exact-output stable-merge choice under `Benchmarks/history-stream/`.

Actual implementation paths are pinned by the graph and comprise:

- `Package.swift`, `Sources/NativeHACore/HomeAssistantHistoryStream.swift`,
  `HomeAssistantWebSocketClient.swift`, and `Models.swift`;
- `Sources/NativeHAMac/AppConfig.swift`, `CardViews.swift`,
  `DashboardViewModel.swift`, and `GraphRendering.swift`;
- the new core history unit/performance/live-smoke tests, the macOS history
  integration tests, and focused graph/GUI regression additions;
- `Benchmarks/history-stream/`, `docs/configurability.md`, and the Module 01
  manifest/generated graph/packet/index.

## Implementer verification

| Contract | Implementer evidence | Result before independent verification |
|---|---|---|
| C01-01 | Compact fixtures cover optional/missing fields, fractional seconds, metadata, malformed requirements, and REST-shape separation. | pass |
| C01-02 | Fixed-clock union/order/duplicate/cutoff/new-entity tests plus exact benchmark comparison cover accumulation. | pass |
| C01-03 | Fake transport asserts ordered IDs, ISO start, omitted end, booleans, six attribute domains, mixed/missing states. | pass |
| C01-04 | Initial-ready, rejection, reconnect freshness, 100 reconnects, cancel/idempotence, stale generation, and zero ownership are deterministic. | pass |
| C01-05 | Projection tests cover timeline sentinel states, numeric gaps, timestamp/domain rules, sparse attributes, and precision. | pass |
| C01-06 | Two-card isolation, deterministic occurrence/ordered identity, global range replacement, raw hours, detail lifecycle/race, and no state double-append pass. | pass |
| C01-07 | Owner-specific loading/error UI, rejection, cancellation, late generation suppression, weak release, and 100-cycle zero ownership pass. | pass |
| C01-08 | Same-shape invalidation, replay/update PNG distinction, async 20k preparation, and prompt detail dismissal pass. | pass |
| C01-09 | App orchestration uses only the WebSocket stream; REST remains separate and all app/tool products build. | pass |

Recorded implementer runs on 2026-07-17:

- Initial and final staleness checks were green. The final resolver self-test
  passed with 28 nodes, 59 edges, and fingerprint
  `31bfe3e30a5d9e6098b57c3efbed65351a0a0cd4758edebac90bbe72078dde07`.
  After implementation, the regenerated Module 01 graph has 21 nodes, 143
  edges, no unresolved/truncated dependency, and fingerprint
  `031ae9d2ee3c7471be95702c817114d393efd073b0685dc6679c78462983c51d`.
- Focused core history tests passed 10/10; focused macOS integration tests
  passed 2/2; focused graph tests passed 8/8. The final complete suite passed
  58 tests with one intentional opt-in live-smoke skip and no failures in
  33.301 seconds. Its two existing Module 09 hover/step markers remained
  expected.
- `NativeHAMac`, `GraphBench`, `GraphPyramidBench`, `ha-probe`, and
  `HistoryStreamBench` built. The release benchmark's final 40,000 samples had
  checksum `8026277772552279935`; the final run's stable merge averaged 87.218
  ms versus 140.775 ms for full stable sort (1.61x) with exact array equality.
- XCTest metrics cover reference 25,000-state decode/cold replay/twenty warm
  chunks and rescue 20,000+100x200 out-of-order/trim fixtures using clock, CPU,
  and memory metrics. The latest debug out-of-order merge measured about
  1.3–1.4 seconds after optimization; the tracked release benchmark above is
  the algorithm-selection evidence.
- Fixed 496x260-point at 2x loading/replay/update numeric and timeline PNGs are
  valid 992x520 nonblank artifacts; replay and update differ. The 20,000-point
  responsiveness/dismissal test passed in 0.203 seconds.
- The opt-in authenticated read-only smoke passed one-hour, forced reconnect,
  and 24-hour coverage with zero final ownership: 2,384 fractional one-hour
  points in 0.183 seconds, a fresh 2,384-point reconnect, and 55,859 fractional
  24-hour points in 2.693 seconds. It made no state/service mutation.

The independent verifier must rerun the final full suite after inspecting the
working-tree diff; implementer results are supporting evidence, not completion.

## Fresh independent verification — 2026-07-17

Verdict: remain `verification-ready`. The implementation and all executed
offline/live suites are green, but the packet's required evidence is not yet
complete for C01-04, C01-07, and C01-08. In particular, the visual test passed
while producing incompletely settled replay/update artifacts, and the claimed
gated responsiveness probe does not contain a gate or exercise a production
history publication/render path. These are completion blockers even though no
Swift test reported a failure.

| Contract | Independent evidence | Verdict |
|---|---|---|
| C01-01 | The compact decoder and REST/stream separation were inspected and the focused fixtures passed, including fractional seconds, optional/missing fields, metadata, malformed required fields, and empty entity arrays. | pass |
| C01-02 | Stable equal-timestamp/duplicate order, out-of-order merging, cutoff boundary rewrite, exact-cutoff behavior, and new-entity trim timing passed. The release benchmark also required exact equality between both candidate arrays. | pass |
| C01-03 | The exact `history/stream` wire dictionary, ordered IDs, recomputed fractional ISO start, omitted end, both booleans, all six attribute domains, mixed domains, and missing/current state policy passed inspection and deterministic tests. The live ordinary-domain request reported `no_attributes=true` and returned zero attribute-bearing points, as expected. | pass |
| C01-04 | One initial owner despite immediate `ready`, `resubscribe:false`, 100 fresh-start reconnects, fresh accumulator data, weak release, idempotent cancellation, and final zero ownership passed. However, no Module 01 test rejects the reconnect-created subscription and proves owner error, no busy loop, zero abandoned ownership, and a later readiness/refresh retry with another fresh accumulator, although the packet explicitly requires that case. | required failed-resubscribe evidence missing |
| C01-05 | Timeline sentinel states, numeric stored-data preservation, sparse attributes, deterministic ordering, centralized fractional timestamp conversion, and the `lu` production branch shared by climate/humidifier/water-heater passed tests plus code inspection. | pass |
| C01-06 | Two overlapping card owners remained isolated; deterministic occurrence identity, ordered entity identity, raw `hoursToShow`, global effective-range replacement, 24-hour detail ownership, prompt detail cancellation, and removal of `state_changed` history appends passed. | pass |
| C01-07 | Initial rejection/status propagation, repeated cancellation, 100-cycle weak release, and exact final Module 02 ownership passed. The implementer table nevertheless claims late-generation suppression and broader error isolation that the Module 01 tests do not exercise: there is no gated late callback during cancellation/replacement, reconnect-subscribe rejection, history-owner overflow/error isolation with another live owner, or cancellation while merge/preparation is in flight. | required cancellation/error/generation evidence incomplete |
| C01-08 | Same-shape content revision invalidation and semantic owner isolation passed. The fixed visual test passed and wrote five valid nonblank 992x520 PNGs with different replay/update hashes, but direct inspection found incompletely settled captures on repeated runs (one timeline replay lacked its range/x-axis labels; after the full suite the numeric update lacked its header and the timeline update lacked its header/x-axis labels). The helper waits a fixed 0.30 seconds rather than polling readiness. The 20,000-point dismissal test passed in 0.195-0.330 seconds, but merely starts an unrelated `Task.detached`, immediately opens/closes a model, and awaits projection; it has no controllable gate, no production stream publication/render path, and no before-gate responsiveness assertion. | fail |
| C01-09 | Search and diff inspection found no app-facing `fetchHistory` call or realtime history append. REST remains only in the REST client/tool path, the stream/REST decoder separation passed, and all app/tool products built. | pass |

Independent commands and observations:

```text
node tools/reference-context/check-context.mjs docs/reference-context/generated/module-01.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint 31bfe3e30a5d9e6098b57c3efbed65351a0a0cd4758edebac90bbe72078dde07

/usr/bin/time -lp swift test --filter HomeAssistantHistoryStreamTests
10 tests, 0 failures; 100 reconnect and 100 subscribe/cancel cycles passed;
maximum resident set size 81,559,552 bytes

/usr/bin/time -lp swift test --filter HomeAssistantWebSocket
17 tests, 0 failures; maximum resident set size 76,398,592 bytes

/usr/bin/time -lp swift test --filter HistoryStreamIntegrationTests
2 tests, 0 failures

/usr/bin/time -lp swift test --filter GraphRenderingTests
8 tests, 0 failures; the two pre-existing Module 09 markers remained expected

/usr/bin/time -lp swift test --filter HomeAssistantHistoryStreamPerformanceTests
5 tests, 0 failures; decode, cold replay, warm 20-chunk merge, 20,000+100x200
out-of-order merge, and rolling trim remained separate clock/CPU/memory metrics;
out-of-order clock mean 1.309 seconds; maximum resident set size 125,796,352 bytes

swift test --skip-build
58 tests, 1 intentional opt-in live skip, 0 failures; 31.227 seconds

swift build --product NativeHAMac
swift build --product GraphBench
swift build --product GraphPyramidBench
swift build --product ha-probe
swift build --product HistoryStreamBench
all passed

/usr/bin/time -lp swift run -c release HistoryStreamBench
exact arrays matched; final 40,000; checksum 8026277772552279935;
stable merge 95.983 ms average; full stable sort 161.985 ms average;
maximum resident set size 122,650,624 bytes; no speed threshold enforced

NATIVEHA_RUN_LIVE_HISTORY_SMOKE=1 swift test --filter \
  HomeAssistantHistoryLiveSmokeTests.testReadOnlyOneHourTwentyFourHourAndReconnectSmoke
1 test, 0 failures; entities sensor.qtpy_sensors_bme688_humidity,
sensor.qtpy_sensors_bme688_temperature, switch.cmpower_w1_7ac38d_33_fen_kong_kai_guan;
no_attributes=true; 1h 2,381 points/2,381 fractional/0 attributes in 0.167s;
reconnect callbacks 2/loading 2/fresh final 2,381 points; 24h 55,863
points/55,863 fractional/0 attributes in 3.400s; final ownership zero;
maximum resident set size 100,253,696 bytes; no service/state mutation

Swift 5.6.1; target arm64-apple-macosx12.0; Xcode 13.4.1; Swift tools 5.6;
Module 01 manifest/generated JSON parse PASS; git diff --check PASS
```

No stream animation was introduced, so a stream animation oracle remains N/A.
Diff inspection found only disabled range-expansion seams and the existing
prepared-render cache invalidation fix; it did not implement shared history
cache/prefetch, range expansion, recorder statistics, Module 09 interaction,
or Module 12 view behavior. The read-only hass-frontend checkout remained
clean. `Benchmarks/.DS_Store` is an accidental untracked artifact and must be
removed by the implementation owner before commit.

Exact repair action:

1. For C01-04/C01-07, add deterministic fake-transport cases that reject the
   reconnect-created history subscription and gate a late callback/in-flight
   merge across cancellation or generation replacement. Assert concise
   owner-local error, no busy retry, no stale publication, another owner's
   continued delivery, a later readiness/explicit-refresh fresh start and
   accumulator, and exact zero pending/subscription/wire/delivery/buffer counts.
2. For C01-08, replace fixed visual settlement with a bounded readiness poll
   that requires the full header, range label, axes/ticks, and data region
   before capturing every replay/update PNG. Add a controllable gate inside the
   actual stream projection/publication or render-preparation path; prove the
   detail sheet and unrelated main-actor work complete before releasing it,
   then prove cancellation/generation prevents stale publication.
3. Rerun the focused/full suites, inspect all five regenerated PNGs, rerun the
   opt-in live smoke, remove `Benchmarks/.DS_Store`, and dispatch another fresh
   independent verification.

## Bounded repair implementation — 2026-07-17

The same single Swift implementation owner completed the verifier's bounded
C01-04/C01-07/C01-08 repair action without broadening Module 01:

- The history coordinator now drains complete-history publications through one
  cancellable, serialized, latest-value worker. Cancellation/reconnect/refresh
  invalidates pending work immediately; a slow projection callback no longer
  blocks wire disposal, and a cancelled generation cannot publish `ready`.
- A deterministic two-owner `ScriptedWebSocketTransport` test rejects one
  reconnect-created `history/stream` subscription while the other owner keeps
  delivering. It proves the concise owner-local error, no busy retry, exact
  absence of abandoned ownership, explicit-refresh recovery with another fresh
  ISO start/accumulator, weak release, and zero pending/subscription/wire/
  delivery/buffer/termination/receiver counts after disposal.
- `DashboardViewModel` has an internal default-no-op processing hook at the
  actual history projection/publication boundary. A 20,000-point production
  replay test holds that path, completes detail dismissal and unrelated
  main-actor work before release, cancels the card generation and wire owner
  before release, then proves the late callback cannot recreate history/status.
  The model weakly releases and all connection/transport counts finish at zero.
- `BitmapLineChart` reports when its production render result is installed.
  The visual renderer now combines that signal with a bounded three-second
  bitmap-readiness poll; it requires bright header/range text, populated graph
  ticks/data, and nonblank header/axis/data regions instead of sleeping 0.30
  seconds. The obsolete unrelated detached-task responsiveness test was
  removed in favor of the production-path gated integration test.
- `Benchmarks/.DS_Store` was removed. No reference-checkout, Module 02,
  deferred cache/prefetch/range-expansion/statistics, Module 09, or Module 12
  behavior changed.

Repair validation on the final working tree:

```text
HomeAssistantHistoryStreamTests: 11 passed
HomeAssistantWebSocket*: 17 passed
HistoryStreamIntegrationTests: 3 passed
GraphRenderingTests: 8 passed; two existing Module 09 markers expected
GUIRenderingAndPerformanceTests: 5 passed
HomeAssistantHistoryStreamPerformanceTests: 5 passed; out-of-order mean 1.297s

swift test: 59 tests, 1 intentional opt-in live skip, 0 failures; 35.375s
NativeHAMac, GraphBench, GraphPyramidBench, ha-probe, HistoryStreamBench: built

release HistoryStreamBench: exact final 40,000 samples;
checksum 8026277772552279935; merge 91.902ms, sort 143.339ms, 1.56x

read-only live smoke: 1 test passed in 3.641s; no_attributes=true;
1h 2,378 points/2 callbacks/0 attributes/2,378 fractional in 0.177s;
reconnect fresh 2,376 points/2 callbacks/2 loading states;
24h 56,166 points/2 callbacks/0 attributes/56,166 fractional in 2.650s;
zero final ownership, no service/state mutation, max RSS 95,502,336 bytes
```

The fixed 496x260-point at 2x visual test passed three consecutive repair runs
under the bounded readiness poll. All five final PNGs are valid nonblank
992x520 images. Direct full-resolution inspection confirmed the loading shell,
numeric replay/update, and timeline replay/update each contain their complete
header and `1h` range label; settled graphs contain all five x-axis labels,
ticks/grid, and data. Numeric and timeline replay/update pairs are visibly and
bytewise distinct. Pixel inspection independently found bright header/range
and bottom-axis components in every settled PNG.

The regenerated graph remains 21 nodes/143 edges with no unresolved or
truncated dependency and now has fingerprint
`749fb98463873b316b94bd8639167cf541dd0160bcb52d88c15a15a2b7813a00`.
The final staleness check is green; the resolver self-test passes 28 nodes/59
edges with fingerprint
`dd7691e06ec49684dfe6582befef9af042ab3a84872e1de17d684a619d4e21cd`.
This repair evidence returns C01-04, C01-07, and C01-08 to a fresh verifier; it
does not independently mark them complete.

## Fresh independent re-verification after bounded repair — 2026-07-17

Verdict: remain `verification-ready`. The bounded C01-04/C01-07 ownership and
responsiveness repairs pass independently, as do C01-01 through C01-07 and
C01-09 overall. C01-08 still fails the required visual-settlement oracle: the
test's new readiness predicates return success for reproducibly incomplete
replay images. A green XCTest result is therefore not completion evidence for
the visual contract.

| Contract | Fresh independent evidence | Verdict |
|---|---|---|
| C01-01 | Focused compact fixtures passed for optional/missing fields, fractional seconds, metadata, malformed required fields, empty entity arrays, and REST/stream decoder separation. | pass |
| C01-02 | Stable equal-timestamp/duplicate ordering, out-of-order merging, cutoff rewrite, exact-cutoff behavior, new-entity timing, and unchanged broader coverage passed. The release benchmark required exact array equality. | pass |
| C01-03 | Inspection and deterministic tests passed for ordered IDs, recomputed fractional ISO start, omitted end, both request booleans, all six attribute domains, and missing/current-state policy. The live ordinary-domain request reported `no_attributes=true` with zero attribute-bearing points. | pass |
| C01-04 | The exact two-owner reconnect-rejection case passed. One reconnect-created owner received the concise local `history_unavailable` error, issued no busy-loop retry, left the other owner delivering, then explicitly refreshed with a later ISO start and a fresh-only accumulator. The 100 reconnect cycle also produced 101 distinct starts. Final pending/subscription/wire/delivery/buffer/task/termination/receiver ownership was exactly zero and both owners weakly released. | pass |
| C01-05 | Timeline sentinel-state preservation, nonnumeric stored-data preservation, sparse attributes, domain timestamp rules, fractional conversion, deterministic ordering, and same-shape content revision passed. | pass |
| C01-06 | Two overlapping owners stayed isolated; deterministic occurrence and ordered-entity identity, global effective range, raw `hoursToShow`, 24-hour detail ownership, prompt detail cancellation, and no `state_changed` history append passed. | pass |
| C01-07 | Initial/reconnect rejection is owner-local; the unaffected owner remains live. A separate production-path 20,000-point gate held actual projection/publication while detail-state dismissal and unrelated main-actor work completed. Cancellation removed the generation and wire owner before release; the gated callback then recreated neither history nor status. The model weakly released and all connection/transport counts reached zero. | pass |
| C01-08 | Same-shape invalidation and the production-path cancellation gate pass. The fixed 496x260-point at 2x visual XCTest also passed three consecutive runs, and all five PNGs were nonblank 992x520 images with distinct replay/update hashes. Direct original-resolution inspection nevertheless found the numeric replay missing its `1h` range label and the timeline replay missing both `1h` and all five x-axis labels. The same incomplete images and hashes recurred in all three uniquely copied runs, proving that the coarse bright-pixel readiness regions admit plot/grid false positives. | fail visual settlement |
| C01-09 | Search/diff inspection found no normal macOS app `fetchHistory` call, REST fallback, or realtime double append. REST remains in `HomeAssistantRESTClient`, `GraphBench`, `GraphPyramidBench`, and `HAProbe`; all five products build. | pass |

Fresh commands and results:

```text
node tools/reference-context/check-context.mjs docs/reference-context/generated/module-01.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint dd7691e06ec49684dfe6582befef9af042ab3a84872e1de17d684a619d4e21cd

swift test --filter HomeAssistantHistoryStreamTests
11 tests, 0 failures; 100 reconnect and 100 subscribe/cancel cycles passed

swift test --filter HomeAssistantWebSocket
17 tests, 0 failures

swift test --filter HistoryStreamIntegrationTests
3 tests, 0 failures; production-path gate passed

swift test --filter GraphRenderingTests
8 tests, 0 failures; two existing Module 09 expected markers remained expected

swift test --filter HomeAssistantHistoryStreamPerformanceTests
5 tests, 0 failures; out-of-order clock mean 1.281 seconds

swift test --filter GUIRenderingAndPerformanceTests
5 tests, 0 failures; visual assertion false positive documented above

swift test
59 tests, 1 intentional opt-in live skip, 0 failures; 34.707 seconds

swift build --product NativeHAMac
swift build --product GraphBench
swift build --product GraphPyramidBench
swift build --product ha-probe
swift build --product HistoryStreamBench
all passed

swift run -c release HistoryStreamBench
exact arrays matched; final 40,000; checksum 8026277772552279935;
stable merge 93.030ms average; full stable sort 149.806ms average;
no speed threshold enforced

NATIVEHA_RUN_LIVE_HISTORY_SMOKE=1 swift test --filter \
  HomeAssistantHistoryLiveSmokeTests.testReadOnlyOneHourTwentyFourHourAndReconnectSmoke
1 test passed; entities sensor.qtpy_sensors_bme688_humidity,
sensor.qtpy_sensors_bme688_temperature,
switch.cmpower_w1_7ac38d_33_fen_kong_kai_guan; no_attributes=true;
1h 2,374 points/1 callback/0 attributes/2,374 fractional in 0.174s;
reconnect 2 callbacks/2 loading states/fresh final 2,374 points;
24h 56,597 points/1 callback/0 attributes/56,597 fractional in 3.259s;
zero-ownership assertions passed; no service/state mutation
```

The three repeated visual runs produced identical hashes for each state, so the
failure was not overwritten-file caching. Loading was complete. Numeric replay
was `a9d487c7...` and lacked `1h`; numeric update was `888a90f2...` and was
complete. Timeline replay was `3ec10f5e...` and lacked `1h` plus the x-axis
labels; timeline update was `31971b88...` and was complete. Replay/update
content itself remained distinct.

Compatibility and scope checks also passed: Swift 5.6.1/Xcode 13.4.1, Swift
tools 5.6, and `arm64-apple-macosx12.0`; manifest/generated JSON parsing; local
Markdown links; final green graph/resolver checks; clean hass-frontend checkout;
and `git diff --check`. The untracked deliverable list contains only the three
benchmark files and five intended Swift test/source files; the previously
reported `Benchmarks/.DS_Store` is absent. Existing ignored `.DS_Store` files
elsewhere in the repository were pre-existing and are outside the Module 01
diff. Inspection found only disabled expansion seams and prepared-cache
invalidation: shared cache/prefetch/range expansion, recorder statistics,
Module 09 interaction, and Module 12 view behavior remain deferred.

## Second bounded C01-08 visual-only repair — 2026-07-17

The same single Swift implementation owner repaired only the C01-08 test
settlement/capture evidence. No file under `Sources/` changed during this
repair, so history protocol, accumulator, reconnect, lifecycle, projection,
rendering, and application behavior are byte-identical to the preceding
bounded-repair verification. The prior five-product builds, exact-output
release benchmark, and read-only live smoke therefore remain applicable.

The GUI oracle no longer counts bright samples in broad regions. After the
production `BitmapLineChart.onRenderReady` result reports at least four x ticks
and nonempty rendered data, it applies these layout-aware text conditions:

- The loading capture establishes a binary template from the exact range-label
  band. Before it can become a template, that band must contain exactly the two
  significant connected components expected for the fixture's `1h`: bounded
  `1`/`h` widths, 15-21 pixel glyph heights, a 2-7 pixel inter-glyph gap, and a
  20-28 by 16-21 pixel union. Replay/update range masks must independently pass
  those constraints and match the loading template at intersection-over-union
  `>= 0.82`, allowing only a one-pixel composition translation.
- The title band must contain at least seven connected text glyph components
  with title-specific height and union geometry.
- Each of five nonoverlapping expected x-axis regions must contain at least
  five text-shaped connected components, at least 250 foreground glyph pixels,
  and a bounded 70-115 by 14-22 pixel group. The regions lie solely in the
  bottom label band, below plot borders, grid lines, and timeline/numeric data.
- Data still must be nonblank, but data/grid pixels cannot satisfy any label
  condition. Every accepted bitmap must pass all applicable conditions on two
  consecutive newly cached snapshots, each separated by a layout/display
  turn. A failure resets the consecutive count. There is no fixed sleep.

The named negative regression copies otherwise complete production-fixture
bitmaps, erases only the range-label band from a populated numeric grid/data
image, and erases only the five-label bottom band from populated timeline data.
It proves the unaffected data/other-label condition remains present and that
the settlement oracle rejects both exact incomplete shapes.

One test invocation now creates three complete repeated runs, each with five
unique names. All 15 PNGs are nonblank 992x520 images. Numeric and timeline
replay/update pairs are distinct; each state is deterministic across repeats:

```text
history-stream-run-{01,02,03}-loading.png
  694df21b101244fb3c68fd3686beacd3c7089c1821d9bfcb3d85f36dcb5108d4
history-stream-run-{01,02,03}-numeric-replay.png
  a9d487c71931decf9f26bc3a138b7894a62f200b8a361489bfdb9b11ada265d0
history-stream-run-{01,02,03}-numeric-update.png
  888a90f2a11cd5d226bd908defc9012d077f500687e6e5cb0e01fafa96740c9f
history-stream-run-{01,02,03}-timeline-replay.png
  3ec10f5eff5087e57c67cedba7b8b65ed5bf2d29ac4bce4ee02bc1a0330f8982
history-stream-run-{01,02,03}-timeline-update.png
  31971b88140cbcf2ca495e0014337faa062f08f3a3ea5bf34877fd3b58b01778
```

All 15 uniquely named files were opened through the image viewer at original
resolution. Exact original-PNG crop inspection and the production-test oracle
establish that numeric replay contains `1h`, and timeline replay contains `1h`
plus all five bottom-axis labels, in every repeat. ImageMagick pixel comparison
reports zero differing pixels between loading and numeric-replay `1h` crops,
zero between loading and timeline-replay `1h` crops, and zero between timeline
replay/update bottom-label crops.

The in-app viewer can present two byte-identical PNG data URLs differently in
one multi-image response (during this inspection, an equality check returned
`same: true` while one preview omitted an overlay). A verifier must therefore
inspect each original file and use its raw crop/component evidence rather than
treating a transient preview thumbnail as different PNG content. This is a
viewer-presentation caveat, not a waiver of the label conditions: the erased
raw-PNG regressions fail the oracle deterministically.

Final repair validation:

```text
node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-01.dependencies.json
GREEN

node tools/reference-context/test-resolver.mjs
PASS: 28 nodes, 59 edges, fingerprint
dd7691e06ec49684dfe6582befef9af042ab3a84872e1de17d684a619d4e21cd

swift test --filter \
  GUIRenderingAndPerformanceTests.testHistoryVisualLabelOracleRejectsPopulatedGraphsWithBlankLabelBands
1 test, 0 failures; exact blank-range/blank-axis regressions passed; 3.092s

swift test --filter \
  GUIRenderingAndPerformanceTests.testHistoryStreamNumericAndTimelineLoadingReplayIncrementalArtifacts
1 test, 0 failures; all 15 unique artifacts produced; 17.227s

swift test --filter GUIRenderingAndPerformanceTests
6 tests, 0 failures; 18.469s

swift test --filter GraphRenderingTests  # repeated twice
8 tests, 0 failures each run; two pre-existing Module 09 markers expected

swift test --filter HistoryStreamIntegrationTests  # repeated twice
3 tests, 0 failures each run

/usr/bin/time -lp swift test
60 tests, 1 intentional opt-in live skip, 0 failures; 47.720s;
maximum resident set size 1,878,949,888 bytes
```

The regenerated graph remains 21 nodes/143 edges with no unresolved/truncated
dependency and fingerprint
`7db0d643160dc350a5646250e83baa6a432911fca03e02465246870a06b75602`.
The graph check is green and resolver self-test remains green. C01-08 is
returned to a fresh independent verifier; this repair does not mark it or the
module complete. Module 01 manifest/generated JSON parsing, packet/index local
Markdown links, and `git diff --check` pass; the read-only hass-frontend
checkout remains clean. Exactly 15 uniquely named history artifacts remain in
the artifact directory. No new `.DS_Store` is tracked or untracked; the ignored
root/`Sources`/`Tests`/`docs`/`tools` files are pre-existing and outside this
repair.

## Live GUI regression hold — 2026-07-17

Do not mark Module 01 complete. After the visual-only repair, the user reported
and the final writer reproduced a live `CO2/VOC` history owner stuck loading
with `Home Assistant WebSocket disconnected`; switching to 12h also cycles the
shared app status between Live/Reconnecting. The user also reports SPS30
scroll/zoom/pan redraw only after the gesture ends. The time-boxed pass made no
application changes because neither root cause was proven enough for a safe
fix. The self-contained reproduction, likely transport/render causes, exact
stress evidence, current scope, and next commands are in [`todo.md`](../../../todo.md).

## Handoff

First repair and live-verify both GUI regressions in [`todo.md`](../../../todo.md).
Then dispatch a fresh independent verifier. It must first run:

```sh
node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-01.dependencies.json
node tools/reference-context/test-resolver.mjs
```

If green, inspect the actual diff and graph-pinned implementation paths, then
verify C01-01 through C01-09 against this packet without re-auditing the entire
frontend or redoing Module 02. Rerun focused history/integration/render tests,
the full suite, all five products, the release benchmark, PNG checks, lifecycle
ownership checks, and the opt-in read-only live one-hour/reconnect/24-hour smoke
when the configured server is reachable. Confirm normal app history has zero
REST fallback/double append and that approved future cache/prefetch/expansion,
recorder statistics, Module 09, and Module 12 work did not leak into scope.

Independently re-verify C01-08's consecutive label-specific settlement and
blank-band regressions plus the bounded C01-04/C01-07 repair above. Inspect the
15 uniquely named original-resolution PNGs and raw label crops; account for the
documented in-app preview inconsistency by comparing source bytes/components if
two identical data URLs appear different. Explicitly confirm numeric replay has
`1h` and timeline replay has `1h` plus five separated bottom-axis labels. The
verifier remains read-only with respect to Swift unless the orchestrator starts
a separate repair task. Mark the module complete only after every replay and
update capture contains the complete header/range/axis/data surface and all C01
contracts pass independently.

## Change log

- 2026-07-17: created reviewed Module 01 manifest and compact dependency graph;
  completed bounded reference/Swift research; reconciled the rescue plan with
  verified Module 02 behavior and canonical global-range/future-cache intent;
  defined C01-01 through C01-09; status `research-ready` at contract revision 1.
- 2026-07-17: implemented C01-01 through C01-09 with one Swift writer; added
  deterministic core/macOS/visual/performance/live-smoke coverage and the
  tracked exact-output merge benchmark; regenerated the graph; recorded
  implementer validation; status `verification-ready` pending a fresh
  independent verifier.
- 2026-07-17: fresh independent verification passed C01-01, C01-02, C01-03,
  C01-05, C01-06, and C01-09, but retained `verification-ready`: C01-04/C01-07
  lack required failure/generation evidence, and C01-08 produced visibly
  unsettled PNGs while its claimed gated dismissal probe had no gate or
  production-path contention.
- 2026-07-17: the single Swift owner completed the bounded C01-04/C01-07/C01-08
  repair; added deterministic reconnect-failure/owner-isolation and real
  production-path cancellation evidence; replaced fixed visual timing with
  bounded render-state/bitmap readiness; regenerated and inspected settled
  artifacts; status remains `verification-ready` for a fresh verifier.
- 2026-07-17: a fresh independent re-verifier passed C01-04/C01-07 and all
  nonvisual checks, but retained `verification-ready`: three repeated visual
  tests falsely accepted the same incomplete numeric/timeline replay images.
  C01-08 requires one more bounded visual-readiness repair.
- 2026-07-17: the single Swift owner completed a visual-only C01-08 repair;
  replaced coarse readiness with consecutive `1h` template and five-region
  axis glyph-component checks, added exact erased-label-band regressions,
  generated and inspected 15 unique artifacts, and documented the in-app
  viewer's inconsistent presentation of identical data URLs. Production source
  remained unchanged; status stays `verification-ready` for a fresh verifier.
