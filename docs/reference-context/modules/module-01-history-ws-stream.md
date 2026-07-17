---
schema: nativeha-evidence/v1
module: "01"
title: History WebSocket stream and dashboard consumers
plan: ../../rescue-plan/module-01-history-ws-stream.md
status: research-ready
contract_revision: 1
depends_on: ["02"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 92e9a2bf95f7dd2cfd649bba2bc0ac8dbbbccb19
graph_file: ../generated/module-01.dependencies.json
graph_fingerprint: df8a12499ec172d728bca112c393796fa19f054dc14e340bf573bf762db01da5
last_validated: 2026-07-17
---

# Module 01 evidence packet

## Scope delta

The rescue plan's WebSocket direction is confirmed. This packet makes the
following behavior and scope corrections before implementation:

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

Research changed only the manifest, generated graph, and this packet. No Swift,
test, rescue-plan, canonical product/configuration, tool, or reference-checkout
file changed.

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

### NativeHA at `92e9a2bf95f7dd2cfd649bba2bc0ac8dbbbccb19`

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
`df8a12499ec172d728bca112c393796fa19f054dc14e340bf573bf762db01da5`.
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
| D01-01 | Use Swift value types/actors and an injected clock rather than mutable JavaScript objects/listeners. | Native platform convention and determinism | Same wire fields, rolling window, ordering, and fresh reconnect outcomes. | C01-01 through C01-04 | Fake clock/transport suite | proposed implementation technique; allowed |
| D01-02 | Safely accept missing `a` and empty per-entity arrays instead of crashing on malformed/sparse server data. | Native robustness | Valid server history behavior and attributes remain unchanged. | C01-01/C01-02 | Sparse/malformed fixtures | proposed implementation technique; allowed |
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
deterministic acceptance test, so the packet is `research-ready`.

## Handoff

Keep the parent task as orchestrator and dispatch exactly one implementation
subagent as the only Swift writer.

The implementation agent must first run:

```sh
node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-01.dependencies.json
node tools/reference-context/test-resolver.mjs
```

If the graph is green, read this packet, the Module 01 rescue plan, the complete
current Swift owners named above, and only HF-01/HF-02/HF-03 plus the focused
tests/benchmark as needed. Do not re-audit the full frontend or Module 02.

Implement C01-01 through C01-09 in dependency order. Expected scope is a new
`Sources/NativeHACore/HomeAssistantHistoryStream.swift`, small typed additions
to the WebSocket facade, `AppConfig` and its canonical configuration note,
dashboard/card/detail ownership, narrowly necessary prepared-output
invalidation, deterministic core/macOS tests, and this packet/index. Preserve
the REST tool path and do not implement the deferred shared cache, idle
prefetch, arbitrary range expansion, recorder statistics, Module 04 decoding,
Module 09 rendering redesign, or Module 12 navigation.

Run targeted history/WebSocket tests, performance/lifecycle tests, the full
suite, app/tool builds, applicable offscreen visual checks, and a read-only live
1h/24h/reconnect smoke. Record exact results and actual diff scope here, then
set status to `verification-ready` with an exact fresh-verifier handoff. Do not
mark `complete` without independent verification.

## Change log

- 2026-07-17: created reviewed Module 01 manifest and compact dependency graph;
  completed bounded reference/Swift research; reconciled the rescue plan with
  verified Module 02 behavior and canonical global-range/future-cache intent;
  defined C01-01 through C01-09; status `research-ready` at contract revision 1.
