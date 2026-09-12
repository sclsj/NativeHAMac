---
schema: nativeha-evidence/v1
module: "01"
title: History WebSocket stream and dashboard consumers
plan: ../../rescue-plan/module-01-history-ws-stream.md
status: complete
contract_revision: 3
depends_on: ["02"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 1c0bc6cc63e14036482dc34ffbf6cd2c0fc39acd
graph_file: ../generated/module-01.dependencies.json
graph_fingerprint: e3fe265a48a99eb4e1d7fb27f8cd43348d9cb5405a7d7753c50460a96d982b33
last_validated: 2026-09-12
---

# Module 01 evidence packet

2026-09-11 logging refresh: see the [logging review](../../audits/2026-09-11-logging.md) for failure diagnostics, writer repairs, tests, and validation limits. Native anchors are refreshed; protocol/product contract revisions are unchanged. Earlier verification entries retain their original revision-specific scope.


## Scope delta

The rescue plan's WebSocket direction is implemented. This packet preserves the following researched behavior and scope corrections:

- Module 02 already unwraps `{type: "event", event: ...}`. Module 01 consumes one decoded `HistoryStreamMessage`; it must not add a second raw-envelope compatibility path or another socket receiver.
- The reference accumulator concatenates samples and conditionally performs a stable timestamp sort. It does **not** deduplicate equal timestamps or chunk boundaries. Fresh reconnect ownership prevents stale pre-reconnect history from being merged, but sample deduplication is not a reference behavior.
- `start_time` and `end_time` in stream events describe server chunks. The frontend accumulator does not use them as a client cursor. The request's `start_time` is computed from the clock when each subscription is created.
- The reference card's `hours_to_show` behavior is overridden by the approved NativeHA product intent: the one Home dashboard uses one typed global range selector. Preserve raw decoded `hours_to_show`; do not rewrite it to carry selected UI state.
- Recorder-statistics merging remains outside this rescue module. The reference card fetches hourly statistics for windows of at least one hour and some sensor detail views prefer recorder statistics. This is a recorded parity gap, not a product deviation and not permission to remove future support.
- Module 01 must implement the foreground stream and current global/detail range policy now. On-demand expansion beyond the initial viewport, the shared byte-budgeted history/prepared cache, and idle 24-hour prefetch remain approved future work. The foreground design must not make them impossible.

Implementation changed NativeHA core/macOS sources, deterministic tests, a tracked benchmark, the canonical configuration note, the manifest/generated graph, and this packet/index. It did not change the reference checkout, rescue plan, canonical user deviations, server state, or Module 02 implementation.

Contract revision 2 is a bounded post-implementation refresh after Gemini commits `e4eecb2`, `f8f55f0`, and `3cd05d5`. It adds acceptance coverage for the production URLSession receive-size boundary and for visible progress during an active gesture. It does not reopen the frontend audit: the existing reference anchors are unchanged, while the affected Swift transport, parser, render scheduler, and tests are now explicit native anchors.

Contract revision 3 is the bounded 2026-08-23 current-anchor refresh after direct typed history delivery, tooltip metadata, and the off-main graph repair. The pinned hass-frontend/npm contracts remain unchanged. The refresh makes the accepted-publication/feed/render ordering explicit and records the bounded C01-06/C01-07 dashboard reconciliation correction. Status remains `complete` after a completely fresh verifier audited the correction and reran the required deterministic, visual, release, and live evidence.

The bounded post-Module 04 anchor maintenance keeps contract revision 3. It moves the history-owner identity anchor from the temporary reconstructed-card path into the exact resolved Lovelace/presentation identity, records the one serialized dashboard-owner operation boundary used by config, range, load, and refresh work, and pins synchronous mounted-chart retirement. These are integration and lifecycle strengthenings of C01-06 through C01-08; the Module 01 wire, accumulation, projection, publication, range, renderer, and REST boundaries do not change.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| C01-01 | A normalized `history/stream` event is delivered | Decode `states` by entity ID. Each compact state maps `s` to state, `a` to attributes, optional `lc` to last-changed seconds, and required `lu` to last-updated seconds. Preserve fractional seconds. Missing `a` is accepted as an empty object for server robustness; missing/malformed `s` or `lu` fails that message deliberately. Optional message `start_time`/`end_time` are retained as metadata. | Decode only the unwrapped event supplied by Module 02. Do not confuse compact WebSocket objects with REST `HAHistoryPoint` JSON. | HF-01, HF-T1 | New `HomeAssistantHistoryStream.swift` models/decoder | Hand-written decode fixtures for present/absent `lc`, present/empty/missing `a`, fractional values, optional chunk metadata, malformed required fields, and REST/stream shape separation. |
| C01-02 | Initial replay, empty completion event, or incremental chunk | Maintain combined history with the same entity-union and rolling-window behavior as `HistoryStream.processMessage`. The first non-empty history becomes the baseline; an empty `states` object leaves current history unchanged. Existing+incoming arrays concatenate; if the incoming first `lu` is older than the existing last `lu`, stable-sort by `lu`. Preserve equal-timestamp arrival order and exact duplicate samples. | On a later merge, trim against an injected `now - range`: retain all states at/after cutoff and prepend the last expired state at exactly the cutoff with `lc` cleared unless a state already exists at the cutoff. A newly introduced entity follows the reference's early-return branch and is first eligible for rolling trim on a later merge. Safely handle empty per-entity arrays rather than trapping. Chunk `start_time` is not a merge cursor. | HF-01, HF-T1, HF-T2 | Pure `HAHistoryStreamAccumulator` with injected clock | Fixed-clock tests for first/empty/multiple-entity messages, absent/new entities, in/out-of-order chunks, equal timestamps and duplicates, boundary-state rewrite, exact-cutoff no-duplicate behavior, and the new-entity trim timing. |
| C01-03 | A card/detail owner begins a foreground time-window subscription | Send `type: "history/stream"`, ordered `entity_ids`, ISO-8601 `start_time = now - effective range`, `minimal_response: true`, `significant_changes_only: true`, and computed `no_attributes`; omit `end_time` so the stream remains live. `no_attributes` is false if any requested entity is absent from current states or belongs to `climate`, `humidifier`, `input_datetime`, `water_heater`, `person`, or `device_tracker`; otherwise true. | Parameters are immutable for one wire owner. Range/entity changes cancel it and construct a new owner. The default booleans are server-side request semantics, not client filters. | HF-01 | Typed history method on `HomeAssistantWebSocketClient` plus request builder | Exact fake-transport wire assertions for ordered IDs, each boolean, ISO start, no end, explicit clock, all six attribute domains, mixed domains, and missing/current entity state. |
| C01-04 | Initial connection, disconnect/reconnect, or explicit disposal | Create exactly one initial stream using Module 02 `resubscribe: false`. After a disconnect, the next `ready` creates exactly one new request with a recomputed `start_time` and a fresh empty accumulator. Each callback publishes that accumulator's complete combined history. | Module 02's status stream yields its current state immediately, so the coordinator must not double-subscribe on the initial `ready`. Disposal cancels the current subscription and lifecycle listener. Late events and old-generation callbacks cannot publish. Initial subscribe rejection surfaces to the owner; reconnect subscribe failure is contained, exposed as owner error/status, and retried only on a later readiness or explicit refresh—not a busy loop. | HF-01, NPM-01, M02-C06 | History subscription coordinator built only on Module 02 connection/status APIs | Two-transport fake test proving one initial subscription, old history opt-out, a second fresh ISO start and accumulator after `ready`, no stale merge/duplicates, idempotent disposal, failed-resubscribe containment, and final Module 02 ownership counts of zero. |
| C01-05 | Combined compact history is projected for graph/timeline consumers | Centralize conversion instead of scattering seconds-to-ISO or compact-key logic through views. Preserve every non-empty timeline state including `unknown`, `unavailable`, and `none`; collapse consecutive equal states only in timeline preparation. Numeric line preparation skips values it cannot parse without removing them from stored history. Use `lc` when present, otherwise `lu`, except line data for `climate`, `humidifier`, and `water_heater` uses `lu`; retain the reference line attributes needed by those domains. Current/first attributes remain available for classification and names when minimal responses omit later attributes. | Preserve deterministic timestamp order and fractional precision. Keep compact numeric seconds authoritative through graph preparation; legacy string access/Codable may format lazily but must remain compatible. Do not mutate stored compact history merely to satisfy a renderer. | HF-01, HF-T2, SW-01, SW-05 | Centralized compact-to-graph adapter plus existing `HistoryGraphSupport`/render preparation | Timeline unknown/unavailable/none; numeric gaps; repeated state; climate/humidifier/water-heater `lu`; sparse attributes; current-state fallback; native numeric and legacy string/Codable timestamp compatibility. |
| C01-06 | Dashboard config loads, global range changes, a detail opens/closes, or visible history owners change | The intended Home dashboard owns foreground subscriptions for visible history cards only; each card publishes only to its own state. Effective range comes from a typed `AppConfig` policy with available selections, default, global scope, and detail default. Subscription/cache identity includes deterministic card identity, ordered entity IDs, and effective range; it must not depend on regenerated `UUID()` values. Preserve raw decoded `hoursToShow`. Detail history uses the configured detail range and cancels when its sheet disappears or identity changes. | Range changes cancel old owners before publishing a new generation. Overlapping entity sets remain isolated. Until Module 12 exists, do not subscribe the hidden maintenance views. Do not append `state_changed` events into an active history stream; state events continue to update current entity state only. | HF-02, HF-03, UD-01, CFG-01, SW-04, SW-05 | `AppConfig`, `DashboardViewModel`, `DashboardView`, `HistoryGraphCard`, `DetailHistoryGraph` | Two-card isolation, stable identity across recomputation, ordered-ID distinction, 1h/3h/12h global changes, raw-hours preservation, detail lifecycle, and no double append from state changes. Replace the obsolete per-card-hours expected failure with a passing approved-policy test. |
| C01-07 | Loading, replay, update, cancellation, server rejection, overflow, profile/connection change, owner disappearance, or an accepted large replay frame | Expose deterministic per-owner loading, ready-data, and error outcomes. One failed or slow history owner cannot erase/block another. A replay within the configured bounded receive policy, including a frame larger than URLSession's 1 MiB default, must not tear down the shared connection. Cancellation/profile teardown removes the owner promptly; an old callback cannot recreate UI state or prepared data. Explicit refresh renews the affected subscriptions. | Generation checks precede main-actor publication. UI publication is main-actor isolated, while decode/merge/preparation must not monopolize it. Delivery overflow and non-disconnect termination surface concise owner errors. Command acknowledgement timeout and maximum receive size are separate typed policies; extending the former is not a substitute for configuring the latter. | HF-02, HF-03, M02-C03, M02-C04, M02-C07 | History coordinator, production URLSession transport, and `DashboardViewModel` ownership | Fake rejection/overflow/late-event tests, strict mixed-command wire ordering, production-adapter receive above 1 MiB, cancellation during replay/merge, profile teardown, simultaneous owners with one blocked, weak-release/lifecycle probe, and exact final connection counts. |
| C01-08 | Replay or incremental content reaches a rendered card/detail, or the user continuously zooms/pans it | Loading settles to a graph/timeline; every accepted combined-history publication invalidates the relevant prepared/render state even when count and first/last timestamps happen to match prior data. Incremental history updates only the affected visual owner. Selected range defines the initial viewport. During a continuous gesture, publish bounded intermediate same-data frames and then settle on the newest viewport. | Render preparation stays asynchronous/cooperatively cancellable, foreground work outranks future cache/prefetch, and stale data generations cannot replace newer data. Viewport frames may be slightly behind the latest event when they share the current data generation; final settlement remains strict. No scheduler-driven animation is required by the stream itself. | HF-02, HF-03, SW-06 | Dashboard graph inputs, prepared-series invalidation/generation, and viewport render scheduler | Offscreen loading→replay→incremental states; same-count/same-endpoint content replacement regression; token-storm progressive publications with concurrency one and exact final token; active-gesture live captures before and after a failed 12h load; bounded settlement; replay/update PNG distinction; dismissal remains responsive during a gated slow merge/render. |
| C01-09 | Normal app history path versus command-line benchmark/probe path | `NativeHAMac` history cards and detail graphs use WebSocket `history/stream`, not REST `/api/history/period`. Keep `HomeAssistantRESTClient.fetchHistory` and REST-shaped models available for `GraphBench`, `GraphPyramidBench`, and `HAProbe` until separately migrated or retired. | No silent REST fallback in normal rendering: it would change streaming/error semantics and hide failures. Stream and REST decoders remain distinct. | SW-01, SW-02, SW-04 | App orchestration; existing REST client remains tool-owned | App integration spy proves zero REST history calls; existing REST tests and tool builds still pass; stream fixtures fail the REST decoder and vice versa. |

Contract-revision-2 clarification for C01-02/C01-04/C01-07/C01-08: the accumulator emits typed reset, unchanged, normal-overlap, or out-of-order-reset facts while merging. Publications carry monotonic owner generation; the first publication after initial subscribe, reconnect, or refresh is a reset. Pending reset dominates normal work, unchanged cannot overwrite pending work, and two undelivered normal publications compose only when accumulator-minted snapshot revisions prove a contiguous predecessor chain. Their reusable overlap is the exact intersection mapped from the last delivered snapshot to the newest one; a broken chain resets. Projection rejects older generations or untrusted lineage without mutation, and dashboard consumers check cancellation again after awaited projection. The existing raw callback remains compatible and takes the safe full-projection path.

Contract-revision-3 clarification for C01-05 through C01-08: each card owner publishes its accepted projected series to `GraphHistoryRevisionFeed` before assigning the same value to `@Published histories`. While a chart observer is mounted, the feed delivers accepted publications FIFO; before subscription it retains only the latest event for replay. Initial/reconnect/refresh and out-of-order publications reset prepared state, normal contiguous publications advance exact lineage, and unchanged publications do not publish. One per-chart `GraphChartRenderCoordinator` consumes accepted revisions serially and performs preparation/render work off-main; obsolete visuals may coalesce, accepted revision advancement may not. Feed/coordinator generation and exact projection lineage establish freshness. `contentRevision` hashes and endpoint timestamps never establish ordering. Tooltip precision/locale/timezone metadata is resolved from current state, the display registry, frontend language preferences, and server timezone and travels with graph input without mutating stored history or changing axis formatting.

## Source anchors

### hass-frontend at `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`

- **HF-01** — `src/data/history.ts`, especially `EntityHistoryState` (line hint 78), `HistoryStreamMessage` (89), `entityIdHistoryNeedsAttributes` (95), `HistoryStream.processMessage` (141/154), `subscribeHistoryStatesTimeWindow` (239), `subscribeHistoryStream` (281), and compact-data projection beginning near
  335. Git blob `5a3c3e8f8fa02c7a081a1ddb0fea875bd40147e2`, SHA-256
`055be2c7ce23ba96de01948e8af51c1f3c699d0580f7d49c22ffc662eb19470c`.
- **HF-02** — `src/panels/lovelace/cards/hui-history-graph-card.ts::HuiHistoryGraphCard`, line hints 81, 142, 147, 236, and 267. Git blob `9b6bb306ca29ecfc4e028cab468c5f826a0ed1a5`, SHA-256 `f20a8c88f513571917cb2471f034682c9bd09ff83570b44531664a75118ba7cd`. The literal reference default is 24 hours, but UD-01 overrides its per-card range choice for NativeHA.
- **HF-03** — `src/dialogs/more-info/ha-more-info-history.ts::MoreInfoHistory`, line hints 34, 161, 166, and 230. Git blob `2f75e720fd4be4a91a45adffa51fb70deaf7a90e`, SHA-256 `fc4e6bd1b2aa3967e56646a6d5ec56e16625d71429b585d536f6715f13b52a74`. It owns a 24-hour stream fallback but may prefer recorder statistics for eligible sensors; statistics are outside Module 01.
- **HF-T1** — `test/data/history.test.ts::HistoryStream.processMessage`, Git blob `76397a28de780dda5cd8d3c0eab4b5cd4ebaf04d`, SHA-256 `01d05009cae89da93e4b1aa4576c181d712e1ab3977829f5d56ad3b27f19b4f1`. Pins cutoff-boundary `lc` clearing and no-expiry behavior.
- **HF-T2** — `test/data/history-characterization.test.ts`, especially `HistoryStream characterization` near line 135, Git blob `0bcbfd3d480d01a62f5741a6e253470d332a029c`, SHA-256 `bc065e1a4726c2e3ec804fdc4de4ceca2ae91184c68e194753e2fc8ad4a9fcc1`. Pins multi-entity, absent/new-entity, out-of-order, compute/projection, and large mixed-payload behavior.
- **HF-B01** — `test/benchmarks/history-stream.bench.ts`, Git blob `f5b3cf5ff7af5221cdb918e32518a9fc05fb00da`, SHA-256 `c984b4b7c1d36336f15c7bda3d98e6cd115122572af0171fd7559f27e3e004d2`. Reference fixture: five entities, 25,000 initial states, then twenty incremental messages of ten states per entity with two warm-up iterations.

### npm runtime boundary reused from Module 02

- **NPM-01** — `home-assistant-js-websocket@9.6.0`, `dist/connection.js::Connection.subscribeMessage` around line hint 291, SHA-256 `884929a38078cc51cb47b0d7d8a821ef99bc784bcd50792bf9b044f936db69e8`. Package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`; Yarn locator `home-assistant-js-websocket@npm:9.6.0`, checksum `10/0eded7864632b5e19e92289ffac0e24308b1e8f425e292ae87ed21450852f7705db521e202614b1d5bbdb7948633143dce2524ed548db0c38486b40ed1ffa474`. This is a provenance anchor only; [Module 02](module-02-websocket-multiplexer.md) already verified its routing, unsubscribe, and `resubscribe:false` behavior.

The reference lockfile is `yarn.lock`, SHA-256 `ca345f66a74a1054b77bd2f47f20cb9e13e79b2c864f3375822cca9b14ff41b6`.

### NativeHA pre-implementation baseline at `92e9a2bf95f7dd2cfd649bba2bc0ac8dbbbccb19`

These anchors explain the implementation starting point. The current working tree is based on `0f6a324aa43c5c508a8304c1767483c0d2edc6f4`; its exact implementation and test hashes are pinned in the regenerated dependency graph rather than copied by hand here.

- **SW-01** — `Sources/NativeHACore/Models.swift::HAHistorySeries`, `HAHistoryPoint`, and `LovelaceCard`, line hints 69, 81, and 119. Git blob `69494d1d1b4f7b298cc294275269e04b8d24920b`, SHA-256 `5a9d62407b1f072cc8627a35b40fbbf6d82dbf61d1346cbf3b9aadb855bc5fc2`.
- **SW-02** — `Sources/NativeHACore/HomeAssistantRESTClient.swift::fetchHistory`, line hint 29. Git blob `f57d2d4e20eaa8271085dfda7985b292b9fc6332`, SHA-256 `954c494e8eef10a9c15b98342b72f20dc1d982c67bc378c36f6f33b2707380e8`.
- **SW-03** — `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`, Git blob `96434a2930fd14a3751872b9c567c3938cd32498`, SHA-256 `8aba0fb19193a7806801adc0480f2e92316c0594a82de4096fc3ffcb9d19c7fa`; and `HomeAssistantWebSocketConnection.swift::statusUpdates`, `subscribeRaw`, and `subscribeMessage`, line hints 257, 316, and 360, Git blob `a432522113ff1d044be8c497cc5f066e7504669b`, SHA-256 `62604bdd77b88b4fa7730c6620521daefd6211482fd0ca74cdb882ec70dd4ec6`.
- **SW-04** — `Sources/NativeHAMac/DashboardViewModel.swift`, especially `historyKey` (301), `load` (383), REST `loadHistories` (486), realtime history append (527), requests (767), and `cleanCards` (797). Git blob `0d0a6e96b6c3c143ce80db4e3626d2a87ae8b09f`, SHA-256 `86a442ecec0a61db8cf30b5c16579f16a7d78b48a3fc24fd44e9a6dabeb78edb`.
- **SW-05** — `Sources/NativeHAMac/AppConfig.swift`, line hints 13-20, Git blob `8e3b7f7abfa487125cb3593f97ef1e7d1aced981`, SHA-256 `ac0473f4ee44bfef7469aaaa85d93e7a39818845428ad3c62eb1f0c87c4edb6e`; and `Sources/NativeHAMac/CardViews.swift::HistoryGraphCard` (224), `UnitGraph` (302), and `DetailHistoryGraph` (1685), Git blob `c7424667fcf86ffb8f147faa7d75703077ed4961`, SHA-256 `a8861dc6f58730db7344aebc0dec80c9e9326c405dd157af3bc27c6939dd2f18`.
- **SW-06** — `Sources/NativeHAMac/GraphRendering.swift`, especially compact preparation/filtering near 602 and the 96-entry prepared cache/fingerprint near 550/745. Git blob `ad68bdc79988205ecbdb8d1118d6af5715577b1c`, SHA-256 `9ebca6835af2e08d7a86e228c72acd07bb3fa6e98b3501b5cf418d4267ac1efe`.
- **SW-T1** — `Tests/NativeHACoreTests/HistoryGraphSupportTests.swift`, Git blob `8e53e421fb762291ef42236154851bf567090e7f`, SHA-256 `a6c8e31d9186203f707d37af49cff1a7ed265b9d501fef91c58d2080f29cc8af`. It already preserves unknown/unavailable timeline segments.
- **SW-T2** — `Tests/NativeHAMacTests/GraphRenderingTests.swift`, Git blob `ba2a2145f7a7a1c08b366e66dbbde3629c01a0d5`, SHA-256 `57ca19e9d766040e89dcd838c36d58cf0ca1378c1ecaaa6a00a08eb164e6c9c0`. Its per-card-hours expected failure conflicts with UD-01 and must be replaced by the approved effective-range contract.

## Dependency traces and boundaries

The generated graph is [`module-01.dependencies.json`](../generated/module-01.dependencies.json), fingerprint `2711531db6e990ae4ce666c9075debbcbc60f9dd10a1138ee71a51c7b91d49f5`. It contains 21 nodes and 143 edges, one editor/card dynamic-import cycle, no unresolved edge, and no truncation.

- `src/data/history.ts` is the stream/request/accumulator entrypoint. Its only behavior-relevant runtime import for these selected symbols is `common/entity/compute_domain.ts`. Imports of `HomeAssistant`, `MessageBase`, and entity types are type-only boundaries.
- `HomeAssistant.connection` is dependency-injected through a TypeScript type, so static imports cannot discover the runtime subscription owner. `home-assistant-js-websocket/dist/connection.js::Connection` is an explicit seed. Traversal stops at the already-complete Module 02 contract rather than re-auditing the package.
- `HuiHistoryGraphCard` and `MoreInfoHistory` are explicit consumer seeds. Their direct edges to `data/history.ts` establish subscription and disposal ownership. Downstream chart, color, tooltip, editor, translation, and Lit internals are visual/framework boundaries for Modules 09/12, not stream semantics. Recorder/statistics edges are the explicit scope deferral above.
- The reviewed maximum depth is one because every behaviorally relevant cross-boundary owner is explicitly reseeded: `history.ts`, the two consumers, and the injected package connection. The 69 recorded max-depth edges all leave direct consumer support files for chart/editor/recorder/framework work; none determines the C01 stream protocol, merge, reconnect, or cancellation behavior. Six unallowlisted runtime package edges are Lit/date-fns UI support; only `home-assistant-js-websocket` is followed.

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
| C01-07 | `HomeAssistantWebSocketConnection.swift`, `HomeAssistantWebSocketTransport.swift`, `AppConfig.swift` | serialized command send and bounded production receive policy | one shared receiver; monotonically increasing wire sends; typed frame budget | A slow replay event is not a slow acknowledgement. Test the real adapter seam above 1 MiB and the exact live CO2/VOC card at 12h. |
| C01-06 | `Sources/NativeHAMac/AppConfig.swift` | typed graph time-range policy | available/default/global/detail values | Future expansion/cache fields may be represented, but their behavior is deferred below. |
| C01-06, C01-07, C01-09 | `Sources/NativeHAMac/DashboardViewModel.swift` | card/detail owner registry and published history | main-actor publication; async owner tasks | Remove app REST loads and realtime double-append path for active streams. |
| C01-06, C01-08 | `DashboardView.swift`, `CardViews.swift` | global selector, card/detail lifecycle | visible Home card/detail ownership | Preserve raw config and cancel on disappearance/key change. |
| C01-05, C01-08 | `HistoryGraphSupport.swift`, `GraphRendering.swift`, `GraphRenderScheduling.swift` | compact projection, prepared-series invalidation, and viewport coalescing | cancellable background preparation; predecessor-matched projection lineage before rendered-point reuse; one render in flight plus one latest pending request | Preserve same-shape/middle-correction invalidation and final-generation correctness while publishing visible progress during event tracking. |
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
| D01-04 | Serialize viewport rendering as one in-flight render plus one overwriteable latest pending request, publishing completed same-data frames during a gesture. | Swift-native scheduling required to preserve the reference's continuous visible redraw | Data-generation safety and exact final viewport remain strict; intermediate viewport frames may intentionally trail the newest input event. | C01-08, `f8f55f0` | Deterministic 8 ms token storm, fidelity oracle, live pre-gesture-end capture | implemented; independent post-12h GUI verification passed |
| D01-05 | Replace Foundation parsing in the hot history path only with a parser that exactly preserves accepted ISO-8601 timestamps and rejects malformed input. | Measured Swift performance | Timestamp meaning, fractional precision, timezone handling, and fallback behavior must not change. | C01-05, `3cd05d5` plus contract-revision-2 repair | UTC/fractional/offset/malformed matrix plus benchmark | implemented; canonical validation and noncanonical fallback pass |
| D01-06 | Retain compact `Double` timestamps in projected history points and format legacy strings only on demand. | Measured Swift performance | `lc`/`lu` selection, exact graph seconds, public string access, Codable keys/values, equality, content revisions, and legacy REST-shaped points remain compatible. | C01-05 and `Benchmarks/HistoryFetch/results.md` | Projection-domain matrix, native/legacy timestamp parser, Codable round trip, 102k-point release benchmark | implemented; projection mean reduced from 0.564 s to 0.060 s |
| HOLD-01 | Configure a typed, bounded URLSession WebSocket receive-size policy above the largest accepted dashboard replay; do not treat a longer command timeout as the fix. | Swift URLSession integration requirement | Home Assistant's valid history event is delivered unchanged and the shared connection remains ready. | C01-07, production measurements | Adapter frame above 1 MiB plus exact 1h/12h CO2/VOC live soak | implemented at 32 MiB; independent verifier passed |
| GAP-01 | Do not implement recorder statistics merge in this rescue module. | Explicit rescue-plan scope boundary, not an approved product deviation | State history streaming is preserved; future statistics parity remains visible. | HF-02/HF-03 | N/A for completion; retain documented gap | deferred parity work |

There is no unresolved product choice. The receive budget is a typed native policy constrained by measured payloads, and parser/scheduler correctness is evidence-driven. The implementation owner may revert or replace the unsafe parts of `e4eecb2`/`3cd05d5` in a new commit while preserving history; a 120-second acknowledgement timeout and an incompletely validated custom parser are not completion requirements.

## History decode/projection performance correction — 2026-07-28

The measured 12-hour delay was primarily local rather than a slow `history/stream` server response. Module 02 now routes the raw event slice directly to this module's typed decoder on its existing bounded ordered delivery worker. Module 01 projection then retains numeric `lc`/`lu` seconds instead of formatting every point to ISO text and parsing it back for graph preparation.

On the tracked 4,940,017-byte/102,418-point fixture, release direct typed decode was 0.387 seconds versus 3.633 seconds through the retained generic/re-encode comparison path. Numeric projection was 0.060 seconds versus 0.564 seconds before the change. Two read-only release live-smoke repetitions published the 12-hour CO2/VOC card in 1.397–1.485 seconds versus 4.735 seconds before, while the 1-hour/24-hour/reconnect/ownership/fractional-timestamp checks remained green. Detailed commands and caveats are in `Benchmarks/HistoryFetch/results.md`.

## Approved future work — not Module 01 completion gates

Module 01 must leave seams for these approved behaviors but must not silently claim them as implemented:

1. **On-demand range expansion:** zooming beyond the initial selected window requests/reuses older coverage asynchronously. It is cancellable, generation safe, globally configurable with optional per-graph override and maximum, and never blocks pan/dismissal. This likely coordinates with Module 09.
2. **Shared range-aware cache:** raw history and prepared series share the configurable 1 GiB upper budget, can satisfy a contained 1-hour request from 24-hour coverage, fetch only missing ranges when safe, expose stats/reset, and have deterministic eviction/byte accounting.
3. **Idle dashboard prefetch:** after dashboard config is available, fetch a configurable default 24-hour window for all referenced entities at lower priority than foreground input/live updates. Foreground and prefetch requests deduplicate by coverage; cancellation/profile changes discard stale work.

The foreground accumulator's rolling trim is subscription-local. It must not be reused as a future shared cache eviction policy or discard broader coverage.

## Validation requirements

### Offline deterministic tests

Use `ScriptedWebSocketTransport`, an injected clock, and small hand-written fixtures for semantics; generated fixtures cover scale. At minimum:

- C01-01: all compact field combinations, fractional seconds, chunk metadata, malformed required fields, and REST/stream decoder separation.
- C01-02: first/empty/multi-entity, absent/new entity, unordered/equal/duplicate timestamps, stable ordering, fixed cutoff, preserved boundary state with cleared `lc`, exact-cutoff behavior, and safe empty entity arrays.
- C01-03: exact command dictionary and every attribute-policy branch.
- C01-04/C01-07: event before/after acknowledgement as supported by Module 02, one initial owner, strict increasing wire-send IDs under mixed concurrent call/subscription registration, fresh reconnect request/accumulator, resubscribe failure, a production-adapter receive larger than 1 MiB under a typed bound, repeated cancel, late callbacks, profile teardown, owner-specific overflow, and zero final pending/subscription/wire/buffer/ receive ownership.
- C01-05: domain timestamp/attribute policy, unknown/unavailable/none timeline, numeric nonnumeric gaps without stored-data deletion, current-state fallback, and timestamp equivalence for UTC/fractional/offset inputs plus rejection or fallback for malformed hour/minute/second/trailing data.
- C01-06: two overlapping cards remain isolated; deterministic card identity; ordered IDs; global 1h/3h/12h changes; raw `hoursToShow` unchanged; detail open/close; state changes do not double append.
- C01-08: same count/first/last with changed state content invalidates prepared output; old generation cannot publish after a replacement; an 8 ms token storm publishes intermediate frames with concurrency one and settles on the final token.
- C01-09: app REST history call count remains zero while REST tests and all benchmark/probe targets compile.

### Read-only live smoke

Applicable after deterministic tests. Load the server/token from the root-named locations. On one authenticated Module 02 connection:

1. subscribe a small live-dashboard entity set for 1 hour;
2. decode the initial replay and completion/incremental chunks;
3. verify ordered entity ownership, compact fractional timestamps when present, and the actual `no_attributes` policy result;
4. cancel and confirm final ownership is zero;
5. force one read-only reconnect, observe a later `ready`, and verify one fresh start time/fresh accumulator with no old merge;
6. load the exact visible CO2/VOC owner at 1h and 12h; verify the measured 12h replay above 1 MiB settles without a shared reconnect and that returning to 1h recovers all owners;
7. verify SPS30 publishes distinct frames before a continuous gesture ends on a fresh 1h launch and again after the 12h transport exercise;
8. repeat a representative 24-hour read for performance/correctness evidence.

No service call or state mutation is needed. A live smoke validates integration, not accumulator edge cases.

### Visual and animation oracle

Module 01 has a visible integration result even though Module 09 owns drawing. Follow [visual testing](../../visual-testing.md): render fixed 496×260-point, 2× history cards for numeric and timeline data through loading, settled replay, and settled incremental update. Use fixed UTC source times and explicit Asia/Shanghai display timezone where the production formatter permits. Write inspectable artifacts, assert signature/dimensions/nonblank/settled regions, and require replay/update images to differ. Only manually reviewed comparable hass-frontend images may become tolerant baselines.

No stream-layer animation is required. If implementation adds data-transition animation, render progress 0/0.5/1 and reduced motion; the final frame must equal the nonanimated result. A gated slow merge/render must not block detail-sheet dismissal or unrelated controls.

### Performance, cache, and lifecycle

- Reproduce the reference scale (five entities, 25,000 states, twenty incremental chunks) and the rescue-plan 20,000-state/100×200-state fixtures. Measure decode separately from merge, cold replay separately from warm incremental work, plus adversarial out-of-order and rolling trim.
- Use constant-size count/checksum consumers and construct fixtures outside measured blocks. Use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`; record baselines rather than aggressive machine-specific limits.
- Exercise at least 100 card/detail subscribe/cancel cycles and reconnect cycles with final zero Module 02/storage counts and weak-release evidence.
- Compare live 1-hour and 24-hour correctness, time, CPU, and memory. If a Swift merge algorithm choice is genuinely unclear, benchmark sensible candidates under `Benchmarks/<topic>/` before selecting; preserve exact output.
- No shared history cache is implemented in Module 01, so cold/warm cache-hit acceptance is N/A now. Verify instead that subscription-local trimming does not mutate any separately retained broader fixture and that the existing prepared cache cannot return stale same-shape content.

## Open questions and risks

- **Stable card identity (resolved by Module 04):** the former `LovelaceCard.id` UUID and destructive `cleanCards` reconstruction are gone. Current history ownership uses the exact resolved raw source path plus canonical semantic config, then adds ordered entity IDs and the effective range in `HistoryRequest`. Preserve exact equality; hashes and endpoint timestamps are not ancestry or freshness order.
- **Immediate status yield:** `statusUpdates()` immediately yields `.ready` to a listener added after connection. A naive initial subscribe plus listener will create two initial history subscriptions.
- **No reference sample deduplication:** applying the current realtime merge's timestamp replacement rule to stream chunks would change frontend behavior. Request/coverage deduplication for future cache work is different from sample deduplication.
- **Timestamp policy:** blindly adapting compact states to an ISO model whose parser always prefers `last_changed` breaks the reference's `lu` rule for climate/humidifier/water-heater line data.
- **Timestamp fast-path correctness:** `3cd05d5` removed the dominant formatter cost, but its custom parser returns a value without fully validating hour/minute/second/trailing data and does not apply explicit numeric offsets. Tests cover only a normal UTC example. Revert or replace it unless an equivalence/malformed matrix proves the optimized path preserves semantics.
- **Production WebSocket frame limit (confirmed):** `URLSessionHomeAssistantWebSocketTransport` does not configure `URLSessionWebSocketTask.maximumMessageSize`. The current default is 1,048,576 bytes. The exact visible CO2/VOC `history/stream` replay measured about 406 KB at 1h and 4,912,600 bytes / 102,618 points at 12h. A clean `3cd05d5` app reproduces 12h `Loading history` plus repeated Live/Reconnecting while 1h succeeds. This is a Swift-native transport boundary, not different intended frontend behavior.
- **ID send order versus receive size:** `e4eecb2` moved command-ID allocation into actor-isolated registration/send, addressing a real `id_reuse` race introduced by unstructured Swift tasks. The reference JS connection assigns and sends in one synchronous turn. No deterministic mixed-command wire-order regression was added, and this fix cannot make a 4.9 MB frame fit a 1 MiB receive limit. The same commit's 120-second command timeout is not supported by this incident: the subscription acknowledgement measured about 7 ms and the oversized replay arrives afterward.
- **Gesture result versus current symptom:** `f8f55f0` has strong deterministic and live evidence for the original token-starvation mechanism, but the user again observed lag while the 12h card failed. Verify fresh 1h interaction before selecting 12h and repeat after the reconnect loop; transport/decode CPU pressure may mask a correct scheduler, but the current user-visible symptom remains a completion hold until reproduced cleanly.
- **Prepared-cache invalidation:** current fingerprints use count and first/last timestamps. Fresh replay content with the same shape can be stale unless the stream generation/content participates in invalidation.
- **Sparse attributes:** minimal responses make later attributes sparse. Keep current/first attributes available and calculate `no_attributes` correctly; otherwise climate/person/device-tracker classification or display regresses.
- **Scope coordination:** Module 12 later defines visible views; Module 09 later expands range/interaction; recorder statistics remains a visible parity gap. Module 01 should expose ownership seams, not implement those modules now.

None of these requires a new product choice, but HOLD-01 and the parser test gap are not yet addressed at `3cd05d5`. The approved future work remains explicitly deferred.

## Implementation result

The single Swift implementation owner completed the module on the working tree based at `0f6a324aa43c5c508a8304c1767483c0d2edc6f4`:

- `HomeAssistantHistoryStream.swift` now owns compact stream decoding, exact accumulation, projection, attribute policy, reconnect coordination, and cancellation. The WebSocket client exposes a typed `subscribeHistoryStatesTimeWindow` facade over Module 02 with `resubscribe: false`.
- `DashboardViewModel` now owns independent visible-card/detail stream subscriptions and generation-checked publication. The normal app history path no longer calls REST or appends `state_changed` samples. The REST client remains available to the benchmark/probe tools.
- `AppConfig` supplies the typed global 1/3/6/12-hour policy and 24-hour detail default. Deterministic traversal occurrence identity replaces regenerated UUID ownership while raw decoded `hoursToShow` remains unchanged.
- `HAHistorySeries` has a deterministic content revision, and graph preparation only reuses incremental work when content truly grows. Same-shape replacement therefore invalidates prepared/rendered output.
- Deterministic core, integration, rendering, lifecycle, performance, and opt-in live-smoke tests cover the contracts. `HistoryStreamBench` records the exact-output stable-merge choice under `Benchmarks/history-stream/`.

Actual implementation paths are pinned by the graph and comprise:

- `Package.swift`, `Sources/NativeHACore/HomeAssistantHistoryStream.swift`, `HomeAssistantWebSocketClient.swift`, and `Models.swift`;
- `Sources/NativeHAMac/AppConfig.swift`, `CardViews.swift`, `DashboardViewModel.swift`, and `GraphRendering.swift`;
- the new core history unit/performance/live-smoke tests, the macOS history integration tests, and focused graph/GUI regression additions;
- `Benchmarks/history-stream/`, `docs/configurability.md`, and the Module 01 manifest/generated graph/packet/index.

Post-checkpoint Gemini commits are preserved in history:

- `e4eecb2` serializes wire-ID allocation with actor-isolated registration/send and changes the app command timeout from 10 to 120 seconds. The ordering repair is plausible but lacks its required mixed-command wire-order test; the timeout change does not fix the confirmed oversized receive.
- `f8f55f0` adds `GraphViewportRenderScheduler`, cooperative rendering checks, deterministic scheduler/fidelity benchmarks, and live in-gesture capture evidence. It addresses the original strict-latest token starvation.
- `3cd05d5` hoists a formatter allocation from `maxGraphZoom` and adds a custom timestamp fast path. It targets a measured CPU hotspot, but the fast parser's timezone/malformed-input equivalence is not yet established.

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

- Initial and final staleness checks were green. The final resolver self-test passed with 28 nodes, 59 edges, and fingerprint `31bfe3e30a5d9e6098b57c3efbed65351a0a0cd4758edebac90bbe72078dde07`. After implementation, the regenerated Module 01 graph has 21 nodes, 143 edges, no unresolved/truncated dependency, and fingerprint `031ae9d2ee3c7471be95702c817114d393efd073b0685dc6679c78462983c51d`.
- Focused core history tests passed 10/10; focused macOS integration tests passed 2/2; focused graph tests passed 8/8. The final complete suite passed 58 tests with one intentional opt-in live-smoke skip and no failures in 33.301 seconds. Its two existing Module 09 hover/step markers remained expected.
- `NativeHAMac`, `GraphBench`, `GraphPyramidBench`, `ha-probe`, and `HistoryStreamBench` built. The release benchmark's final 40,000 samples had checksum `8026277772552279935`; the final run's stable merge averaged 87.218 ms versus 140.775 ms for full stable sort (1.61x) with exact array equality.
- XCTest metrics cover reference 25,000-state decode/cold replay/twenty warm chunks and rescue 20,000+100x200 out-of-order/trim fixtures using clock, CPU, and memory metrics. The latest debug out-of-order merge measured about 1.3–1.4 seconds after optimization; the tracked release benchmark above is the algorithm-selection evidence.
- Fixed 496x260-point at 2x loading/replay/update numeric and timeline PNGs are valid 992x520 nonblank artifacts; replay and update differ. The 20,000-point responsiveness/dismissal test passed in 0.203 seconds.
- The opt-in authenticated read-only smoke passed one-hour, forced reconnect, and 24-hour coverage with zero final ownership: 2,384 fractional one-hour points in 0.183 seconds, a fresh 2,384-point reconnect, and 55,859 fractional 24-hour points in 2.693 seconds. It made no state/service mutation.

The independent verifier must rerun the final full suite after inspecting the working-tree diff; implementer results are supporting evidence, not completion.

## Fresh independent verification — 2026-07-17

Verdict: remain `verification-ready`. The implementation and all executed offline/live suites are green, but the packet's required evidence is not yet complete for C01-04, C01-07, and C01-08. In particular, the visual test passed while producing incompletely settled replay/update artifacts, and the claimed gated responsiveness probe does not contain a gate or exercise a production history publication/render path. These are completion blockers even though no Swift test reported a failure.

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

No stream animation was introduced, so a stream animation oracle remains N/A. Diff inspection found only disabled range-expansion seams and the existing prepared-render cache invalidation fix; it did not implement shared history cache/prefetch, range expansion, recorder statistics, Module 09 interaction, or Module 12 view behavior. The read-only hass-frontend checkout remained clean. `Benchmarks/.DS_Store` is an accidental untracked artifact and must be removed by the implementation owner before commit.

Exact repair action:

1. For C01-04/C01-07, add deterministic fake-transport cases that reject the reconnect-created history subscription and gate a late callback/in-flight merge across cancellation or generation replacement. Assert concise owner-local error, no busy retry, no stale publication, another owner's continued delivery, a later readiness/explicit-refresh fresh start and accumulator, and exact zero pending/subscription/wire/delivery/buffer counts.
2. For C01-08, replace fixed visual settlement with a bounded readiness poll that requires the full header, range label, axes/ticks, and data region before capturing every replay/update PNG. Add a controllable gate inside the actual stream projection/publication or render-preparation path; prove the detail sheet and unrelated main-actor work complete before releasing it, then prove cancellation/generation prevents stale publication.
3. Rerun the focused/full suites, inspect all five regenerated PNGs, rerun the opt-in live smoke, remove `Benchmarks/.DS_Store`, and dispatch another fresh independent verification.

## Bounded repair implementation — 2026-07-17

The same single Swift implementation owner completed the verifier's bounded C01-04/C01-07/C01-08 repair action without broadening Module 01:

- The history coordinator now drains complete-history publications through one cancellable, serialized, latest-value worker. Cancellation/reconnect/refresh invalidates pending work immediately; a slow projection callback no longer blocks wire disposal, and a cancelled generation cannot publish `ready`.
- A deterministic two-owner `ScriptedWebSocketTransport` test rejects one reconnect-created `history/stream` subscription while the other owner keeps delivering. It proves the concise owner-local error, no busy retry, exact absence of abandoned ownership, explicit-refresh recovery with another fresh ISO start/accumulator, weak release, and zero pending/subscription/wire/ delivery/buffer/termination/receiver counts after disposal.
- `DashboardViewModel` has an internal default-no-op processing hook at the actual history projection/publication boundary. A 20,000-point production replay test holds that path, completes detail dismissal and unrelated main-actor work before release, cancels the card generation and wire owner before release, then proves the late callback cannot recreate history/status. The model weakly releases and all connection/transport counts finish at zero.
- `BitmapLineChart` reports when its production render result is installed. The visual renderer now combines that signal with a bounded three-second bitmap-readiness poll; it requires bright header/range text, populated graph ticks/data, and nonblank header/axis/data regions instead of sleeping 0.30 seconds. The obsolete unrelated detached-task responsiveness test was removed in favor of the production-path gated integration test.
- `Benchmarks/.DS_Store` was removed. No reference-checkout, Module 02, deferred cache/prefetch/range-expansion/statistics, Module 09, or Module 12 behavior changed.

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

The fixed 496x260-point at 2x visual test passed three consecutive repair runs under the bounded readiness poll. All five final PNGs are valid nonblank 992x520 images. Direct full-resolution inspection confirmed the loading shell, numeric replay/update, and timeline replay/update each contain their complete header and `1h` range label; settled graphs contain all five x-axis labels, ticks/grid, and data. Numeric and timeline replay/update pairs are visibly and bytewise distinct. Pixel inspection independently found bright header/range and bottom-axis components in every settled PNG.

The regenerated graph remains 21 nodes/143 edges with no unresolved or truncated dependency and now has fingerprint `749fb98463873b316b94bd8639167cf541dd0160bcb52d88c15a15a2b7813a00`. The final staleness check is green; the resolver self-test passes 28 nodes/59 edges with fingerprint `dd7691e06ec49684dfe6582befef9af042ab3a84872e1de17d684a619d4e21cd`. This repair evidence returns C01-04, C01-07, and C01-08 to a fresh verifier; it does not independently mark them complete.

## Fresh independent re-verification after bounded repair — 2026-07-17

Verdict: remain `verification-ready`. The bounded C01-04/C01-07 ownership and responsiveness repairs pass independently, as do C01-01 through C01-07 and C01-09 overall. C01-08 still fails the required visual-settlement oracle: the test's new readiness predicates return success for reproducibly incomplete replay images. A green XCTest result is therefore not completion evidence for the visual contract.

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

The three repeated visual runs produced identical hashes for each state, so the failure was not overwritten-file caching. Loading was complete. Numeric replay was `a9d487c7...` and lacked `1h`; numeric update was `888a90f2...` and was complete. Timeline replay was `3ec10f5e...` and lacked `1h` plus the x-axis labels; timeline update was `31971b88...` and was complete. Replay/update content itself remained distinct.

Compatibility and scope checks also passed: Swift 5.6.1/Xcode 13.4.1, Swift tools 5.6, and `arm64-apple-macosx12.0`; manifest/generated JSON parsing; local Markdown links; final green graph/resolver checks; clean hass-frontend checkout; and `git diff --check`. The untracked deliverable list contains only the three benchmark files and five intended Swift test/source files; the previously reported `Benchmarks/.DS_Store` is absent. Existing ignored `.DS_Store` files elsewhere in the repository were pre-existing and are outside the Module 01 diff. Inspection found only disabled expansion seams and prepared-cache invalidation: shared cache/prefetch/range expansion, recorder statistics, Module 09 interaction, and Module 12 view behavior remain deferred.

## Second bounded C01-08 visual-only repair — 2026-07-17

The same single Swift implementation owner repaired only the C01-08 test settlement/capture evidence. No file under `Sources/` changed during this repair, so history protocol, accumulator, reconnect, lifecycle, projection, rendering, and application behavior are byte-identical to the preceding bounded-repair verification. The prior five-product builds, exact-output release benchmark, and read-only live smoke therefore remain applicable.

The GUI oracle no longer counts bright samples in broad regions. After the production `BitmapLineChart.onRenderReady` result reports at least four x ticks and nonempty rendered data, it applies these layout-aware text conditions:

- The loading capture establishes a binary template from the exact range-label band. Before it can become a template, that band must contain exactly the two significant connected components expected for the fixture's `1h`: bounded `1`/`h` widths, 15-21 pixel glyph heights, a 2-7 pixel inter-glyph gap, and a 20-28 by 16-21 pixel union. Replay/update range masks must independently pass those constraints and match the loading template at intersection-over-union `>= 0.82`, allowing only a one-pixel composition translation.
- The title band must contain at least seven connected text glyph components with title-specific height and union geometry.
- Each of five nonoverlapping expected x-axis regions must contain at least five text-shaped connected components, at least 250 foreground glyph pixels, and a bounded 70-115 by 14-22 pixel group. The regions lie solely in the bottom label band, below plot borders, grid lines, and timeline/numeric data.
- Data still must be nonblank, but data/grid pixels cannot satisfy any label condition. Every accepted bitmap must pass all applicable conditions on two consecutive newly cached snapshots, each separated by a layout/display turn. A failure resets the consecutive count. There is no fixed sleep.

The named negative regression copies otherwise complete production-fixture bitmaps, erases only the range-label band from a populated numeric grid/data image, and erases only the five-label bottom band from populated timeline data. It proves the unaffected data/other-label condition remains present and that the settlement oracle rejects both exact incomplete shapes.

One test invocation now creates three complete repeated runs, each with five unique names. All 15 PNGs are nonblank 992x520 images. Numeric and timeline replay/update pairs are distinct; each state is deterministic across repeats:

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

All 15 uniquely named files were opened through the image viewer at original resolution. Exact original-PNG crop inspection and the production-test oracle establish that numeric replay contains `1h`, and timeline replay contains `1h` plus all five bottom-axis labels, in every repeat. ImageMagick pixel comparison reports zero differing pixels between loading and numeric-replay `1h` crops, zero between loading and timeline-replay `1h` crops, and zero between timeline replay/update bottom-label crops.

The in-app viewer can present two byte-identical PNG data URLs differently in one multi-image response (during this inspection, an equality check returned `same: true` while one preview omitted an overlay). A verifier must therefore inspect each original file and use its raw crop/component evidence rather than treating a transient preview thumbnail as different PNG content. This is a viewer-presentation caveat, not a waiver of the label conditions: the erased raw-PNG regressions fail the oracle deterministically.

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

The regenerated graph remains 21 nodes/143 edges with no unresolved/truncated dependency and fingerprint `a434215e524cdc48c7122fe266aa22a2e0ced1ff087ad4396ee0b435a4e2ab3b`. The graph check is green and resolver self-test remains green. C01-08 is returned to a fresh independent verifier; this repair does not mark it or the module complete. Module 01 manifest/generated JSON parsing, packet/index local Markdown links, and `git diff --check` pass; the read-only hass-frontend checkout remains clean. Exactly 15 uniquely named history artifacts remain in the artifact directory. No new `.DS_Store` is tracked or untracked; the ignored root/`Sources`/`Tests`/`docs`/`tools` files are pre-existing and outside this repair.

## Live GUI regression repair — updated 2026-07-19

Do not mark Module 01 complete before fresh independent verification. After the visual-only repair, the user reported and the final writer reproduced a live `CO2/VOC` history owner stuck loading with `Home Assistant WebSocket disconnected`; switching to 12h also cycled the shared app status between Live/Reconnecting. The production-matching replay was about 4,912,600 bytes / 102,618 points, exceeding URLSession's 1,048,576-byte default; 1h was about 406 KB and succeeded. The receive-size cause was a Swift-native transport boundary, while `e4eecb2`'s 120-second acknowledgement timeout did not address it.

The repair adds a typed 32 MiB receive policy and applies it to the concrete URLSession WebSocket task before `resume`. This is a finite per-message upper bound, not eager allocation; it covers the measured 26,490,281-byte 24-hour four-series SPS30 response. The app command timeout is restored to the evidence-backed 10 seconds. A production-adapter seam test delivers a frame one byte above the platform default without disconnecting, and a strict scripted transport now rejects any non-increasing actual wire-send ID.

The read-only release live smoke passed the exact `CO2/VOC` owner at 1h (8,530 points / 0.495s), 12h (102,565 points / four callbacks / 6.087s), and recovery to 1h (8,528 points / 0.470s). No reconnecting or other non-ready connection state occurred during the sequence, no owner reported an error, and ownership returned to zero after every window. A representative 24-hour stream also passed with 56,470 points in 2.716s. The scheduler mechanism below remains reopened only for the required fresh/post-12h live gesture captures by the independent verifier.

## Gesture rendering repair — 2026-07-18

The token-starvation cause is confirmed and repaired without changing graph fidelity. `BitmapLineChart` no longer cancels and replaces an uncancellable detached viewport render for every 8 ms scroll event. A dedicated scheduler keeps one render in flight, overwrites one pending slot with the newest viewport, publishes completed same-data frames through the main run loop's common modes, and immediately renders the newest pending request. Old history generations remain strictly rejected. Render preparation/downsampling/bitmap boundaries now include cooperative cancellation checks.

The tracked `Benchmarks/GraphRendering/` target contains methodology, live data metadata, results, production stage instrumentation, an exact scalar min/max oracle, and the scheduler/token-storm benchmark. Fresh live data contained 13,976 points across four SPS30 series for 1h and 335,776 for 24h. At 2×, production warm 1h render time was 3.555 ms median / 5.360 ms p95; 24h was 7.047 / 10.540 ms. Stroke/rasterization dominated warm work. Cold timestamp preparation remained a separate 0.613s/13.615s cost. 1×/2× retained identical points, axes, and bounds; the 100,000-point spike/noise fixture exactly matched the scalar min/max oracle. Stride and disabled antialiasing were rejected for fidelity risk, and alternate line/downsample implementations did not address the structural starvation mode.

In the deterministic 8 ms event/20 ms render test, the old strict-token model publishes zero in-gesture frames. The new scheduler publishes eight, starts ten renders for 24 events, replaces 14 pending requests, never exceeds one active render, and settles on the final token. The release app then passed a live 1h SPS30 scroll capture: 20 frames were captured before the 1.661-second event stream ended, with 15 distinct plot signatures and visible progressive x-window/line changes. Focused graph tests, the release deterministic benchmark, the opt-in live 1h/24h benchmark, the six-test GUI rendering suite, and the full 66-test suite pass (the normal full run skips the two opt-in live tests). This proves the token-starvation repair, not current end-to-end behavior under a reconnect loop. Module status remains `verification-ready` for the transport repair, before/after interaction check, parser correctness gap, and a fresh independent verifier.

## Contract revision 2 implementation — 2026-07-19

The sole Swift writer implemented the receive-bound, parser, strict-send-order, and configurable hover-capture work without reopening the frontend audit:

- `HomeAssistantWebSocketReceivePolicy` is threaded through the public client, connection, concrete transport, and app policy. The URLSession task receives the bound before resume. Normal library callers retain the platform default; the app deliberately selects 32 MiB.
- Concurrent command/subscription/unsubscribe work is exercised through a fake transport that enforces strictly increasing actual send order. Sixty-four commands plus sixty-four subscriptions and their cancellations pass with zero wire-order violations and zero final ownership.
- Canonical HA timestamps now validate every calendar, clock, fractional, timezone-offset, and trailing field before returning a value. Invalid canonical-looking strings cannot fall into Foundation's permissive normalization. A locked shared formatter pair preserves the compatibility fallback for noncanonical forms without constructing formatters during normal SwiftUI recomputation.
- `GraphInteractionPolicy` keeps the floating sample overlay enabled normally and permits `NATIVEHA_GRAPH_HOVER_OVERLAY=0` for unobscured live captures. Only overlay drawing is gated; the gesture view and zoom/pan callbacks remain present. Pure policy and rendered-PNG tests cover the seam.

Focused verification passed 19 WebSocket tests, 32 combined history/ integration/graph/GUI tests, the timestamp matrix/performance tests, the production configuration assertions, and the release deterministic scheduler benchmark. The five-iteration read-only live graph benchmark retained exact 1x/2x points/axes/bounds; cold preparation was 23.6/23.7 ms for 13,988 1h points and 747.5/571.6 ms for 335,700 24h points, replacing the provisional Foundation-dominated multi-second path. Exact transport live-smoke results are recorded above.

## Post-transport CPU repair and independent GUI verification — 2026-07-19

Once the 32 MiB receive policy made the exact 12h replay reliable, independent release-app verification exposed a second, distinct Swift-native bottleneck: settled 12h CPU remained about 117.7%. Sampling attributed the dominant work to six owner chains repeatedly performing full compact-history projection and `ISO8601DateFormatter.string`; an additional cluster came from full prepared- series rebuilds because a rolling window often retains the same point count. Socket receive and JSON decode were negligible in that settled profile.

The bounded repair adds one `HAHistoryProjectionStore` per history/detail owner. The final hardening makes overlap proof event-driven: the accumulator classifies reset, unchanged, normal append/rolling trim, and out-of-order reset while it already merges and trims. Normal publications carry retained old/new compact indices only when the retained existing indices form one contiguous suffix; an entity with a gapped retained slice projects fully. Rare out-of-order input resets every entity. The projection store uses those facts with O(1) bounds/endpoint validation and formats only the rolling boundary/prefix and new suffix, without a routine full-array equality scan. Raw/manual callers, context changes, resets, and middle corrections take full projection. The graph prepared-series cache may reuse a rolling overlap only when `HAHistoryProjectionStore` supplies its predecessor revision and exact old/new indices, and that predecessor matches the cached revision. It freshly prepares the prefix/boundary and suffix/tail and reuses only the indexed one-to-one sorted numeric slice; the graph layer does not repeat an O(n) source equality scan. Standalone/full series have no lineage. Typed publications carry monotonic owner generations: a newer generation clears and fully projects, while an older generation returns no result and cannot mutate lineage. Same-end middle replacement and middle correction plus a newer tail both remain full rebuilds. This changes no history publication cadence, accepted-sample set/order, cutoff, duplicate, merge, wire, or reconnect semantics.

Deterministic tests compare the 100,000-point incremental projection exactly to the full oracle and record one full plus one incremental build. Final release timing was 3.542 ms incremental versus 592.864 ms full; the full-suite debug run measured 19.218 versus 924.713 ms. Separate same-shape middle-correction tests prove full rebuild and exact corrected output in both projection and prepared-series caches. A bounded verifier regression combines a rolling middle correction with a newer tail and requires exact rendered values `[20, 99, 40, 50]` plus two full preparations and zero incremental preparations; the clean equal-count rolling fixture still requires one full and one incremental preparation. The common 99,999-point moved synthetic cutoff, unchanged overlap, and one new tail also matches a cold full oracle exactly, keeps the freshly projected boundary, and records one full plus one incremental preparation. A no-lineage rolling fixture, projection middle correction, and post-reset generation all record full preparation/no lineage.

The coordinator preserves relative overlap safety while coalescing: reset dominates an undelivered normal update and unchanged cannot erase pending work. The later settled-append repair below replaces the conservative two-normal reset with revision-checked overlap composition. Dashboard consumers check cancellation again after awaited projection. The existing raw `onHistory` API remains compatible; the typed publication overload is additive, and raw projection remains the safe full path.

The fresh independent release GUI verifier then passed the previously reopened C01-07/C01-08 path:

- fresh 1h rendered all owners and stayed `Live` for 20/20 status samples;
- exact CO2/VOC 12h rendered by the sixth capture and stayed `Live` for 80/80 samples over 36 seconds, with no reconnect/disconnect;
- settled 12h CPU samples averaged 26.43%, down 77.5% from the reproduced 117.7%, while observed app memory stayed 119–131 MB;
- with `NATIVEHA_GRAPH_HOVER_OVERLAY=0`, all 17 captured SPS30 plot frames during zoom/pan were unique and the final two settled frame hashes matched;
- return to 1h was fully rendered by the second capture and stayed `Live` for 60/60 samples over 25 seconds; the verifier terminated the PID and confirmed no app process remained.

The current-tree release live ownership harness independently passed exact CO2/VOC 1h (8,516 points / 0.437s), 12h (102,527 points / four callbacks / 4.852s), and recovery 1h (8,516 points / 0.429s), plus representative 24h (56,470 points / 2.688s). It observed no reconnect/non-ready state or owner error during the exact sequence and exact zero pending/subscription/wire/ delivery/buffer/task ownership after every cancellation and at final teardown.

Final deterministic validation after retained-suffix hardening passed 87 tests with two intentional live-gated skips and zero failures in 52.858 seconds. Focused `GraphRenderingTests` passed 17/17, `HomeAssistantHistoryStreamTests` passed 17/17, and `HomeAssistantHistoryStreamPerformanceTests` passed 6/6. All five products built before the proof-only follow-up; release `GraphRenderingBenchmarkTests` passed 2/2 with one-render concurrency, eight in-gesture publications, and exact final settlement; `git diff --check`, graph checker, and resolver self-test are green. The final graph has 21 nodes/143 edges with fingerprint `7fd7546a2f9b860af39694f3a1449d1d0d8e21bab8609e82b31f7c77dc395675`; the 28-node/59-edge resolver self-test fingerprint is `ab069e007ec7bfe3e9fb3019c9c58563ba9294af47b2ddb4fdc8bce4ef0a1f1a`. The independent verifier's GUI artifacts are retained at `/tmp/nativeha-final-verify-artifacts` for the current machine/session. GUI accessibility does not expose Module 02 ownership counts, so exact final ownership comes from the current-tree live harness above.

## Fresh independent bounded verification — 2026-07-19

Verdict: remain `verification-ready`. The verifier did not re-audit the frontend because the context graph was green. The transport, parser, configuration, projection, live ownership, release rendering, and retained GUI evidence all passed, but inspection found one C01-08 semantic counterexample in the prepared-series cache.

Validation run on the exact working-tree diff:

- graph staleness check: green; resolver self-test: 28 nodes/59 edges, fingerprint `07fbefb2ed438ebf93157065e91cb44a5af6bba999b609bd37e37079f5d69684`;
- targeted WebSocket/transport/multiplexer: 16/16; history/parser/integration: 30/30; graph/GUI/configuration: 22/22;
- full `swift test`: exit 0, 77 tests with two intentional opt-in live skips; release scheduler benchmark: 2/2; `swift build -c release` linked all five executable products;
- current-tree read-only live ownership harness: exact CO2/VOC 1h (8,508 points/0.438s), 12h (102,506 points/2 callbacks/4.660s), recovery 1h (8,506 points/0.403s), and representative 24h (56,465 points/2.602s). It reported zero owner error, reconnect/non-ready transition, and final internal owner;
- five-iteration release live graph benchmark: 13,952 1h points and 335,692 24h points; 24h cold preparation was 552.164/550.115 ms at 1x/2x, with identical points, axes, and bounds at both scales;
- retained GUI artifacts independently show CO2/VOC loading at 2s and rendered at 6s, rendered 1h recovery by 4s, 17/17 distinct in-gesture SPS30 hashes, and identical final settled hashes. The artifact directory contains no raw status/CPU log, so the recorded 80/80 Live and 26.43% mean CPU figures cannot be recomputed from files alone; the current-tree live harness independently supplies the zero-reconnect/non-ready/error and zero-ownership evidence.

Exact failed counterexample: begin with a prepared series whose compact source contains points `A B C D`. A later valid history publication contains `A B C' C D E`, where `C'` is an out-of-order correction/late sample before the prior last timestamp and `E` is a newer tail. `HAHistoryProjectionStore` correctly rejects incremental reuse because it cannot prove an exact compact overlap, performs a full projection, and includes `C'`. However, `GraphPreparedSeriesCache.incrementallyUpdate` currently requires only that the incoming last timestamp is newer and the old last timestamp `D` is present. It therefore reuses the cached prefix through `D` and appends only `E`, dropping `C'` from rendered output. The existing same-end correction test and clean equal-count rolling test pass separately and do not exercise this combined case.

The bounded repair must make prepared-series incremental reuse depend on proven exact source overlap/provenance (or exact-compare the reused source segment), then add a deterministic combined middle-correction/out-of-order-insertion plus new-tail oracle. That test must assert the incremental path is not used and the rendered output exactly equals full preparation. No sample, duplicate, order, cutoff, cadence, wire, or reconnect semantic may change.

## Superseded handoff — prepared-series counterexample

The transport, wire-order, timeout, parser, configurability, projection, live CO2/VOC, and gesture repairs are green. Do not mark the module complete or commit the repair as final until the prepared-series counterexample above is fixed and freshly reverified. The next verifier should first run:

```sh
node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-01.dependencies.json
node tools/reference-context/test-resolver.mjs
```

If green, inspect only the bounded cache repair and its combined correction plus new-tail oracle; do not re-audit the entire frontend or redo Module 02. Retain the already-green transport/live/GUI evidence unless a relevant functional path changes. Commit intentionally and mark complete only after no C01-01-through- C01-09 discrepancy remains. Future finite backfill/live-tail, prefetch/cache expansion, recorder statistics, Module 09, and Module 12 remain out of scope.

### Fresh moving-cutoff cache verification — 2026-07-19

Status remains `verification-ready`. The correction-plus-new-tail safeguard is correct and worth retaining, but the current exact-prefix proof rejects the normal Home Assistant rolling-window shape. A read-only 99,999-point harness used an old synthetic cutoff followed by unchanged history, then a moved synthetic cutoff, the unchanged retained history, and one new tail. The second render was exact against a cold full oracle, but cache statistics were two full preparations and zero incremental preparations. The compared incoming prefix includes the changed synthetic boundary, so it cannot equal the cached suffix.

An optimized 99,999-point `HAHistoryPoint` equality scan measured 5.634 ms per proof (mean of 100), while the debug harness's rejected second update spent 380.056 ms in full series preparation. The guard should not be removed: a real middle correction or out-of-order insertion is rare on an uninterrupted HA recorder stream, but the reference explicitly accepts out-of-order chunks, and reconnect/replay or delayed delivery can expose one. Silently omitting it would be a correctness failure. The bounded repair is to freshly prepare the one moving boundary, prove exact equality for the retained source overlap, reuse that overlap, and append the new tail. It must preserve both the common moving- cutoff oracle and the adversarial correction-plus-tail full-path oracle.

Staleness remained green and the resolver self-test passed 28 nodes / 59 edges with fingerprint `07fbefb2ed438ebf93157065e91cb44a5af6bba999b609bd37e37079f5d69684`. After the bounded repair, dispatch a fresh verifier for these two cache shapes; the frontend, transport, and retained live GUI evidence do not need re-audit.

### Bounded projection-lineage repair — 2026-07-19

Status remains `verification-ready` for the fresh bounded verifier. The sole Swift writer replaced the graph layer's duplicate O(n) `HAHistoryPoint` equality scan with transient provenance produced by the actor that already proved the compact overlap. `HAHistorySeriesCacheLineage` carries predecessor revision, old start, new start, and count; it is an additive public cross-target type but is deliberately excluded from `HAHistorySeries` Codable data and decodes as nil. The graph cache accepts it only when the predecessor revision matches and the prior prepared source was one-to-one, numeric, and strictly ordered. It freshly prepares prefix/suffix and reuses the indexed overlap.

Full projection, middle correction, standalone series, lineage absence, and owner-generation reset carry no lineage and take the full path. Dashboard history/detail owners reset their projection store on `.loading`, which occurs before initial, refresh, and reconnect replay, preventing cross-generation lineage. Codable, correction, absent-lineage, and reset tests pin these rules.

The production-shaped 99,999-point moved cutoff + unchanged overlap + one tail matches its cold full oracle exactly, includes the new boundary, and records full=1/incremental=1. Graph-only debug timing was 9.846 ms incremental versus 280.460 ms cold full; release was 0.861 ms versus 110.403 ms. The adversarial middle-correction + tail remains exact at full=2/incremental=0. Focused graph 16/16, history 14/14, and history-performance 6/6 pass. The full suite passes 83 tests with two intentional live-gated skips and zero failures in 52.775s.

### Event-driven lineage hardening — 2026-07-19

Status remains `verification-ready` for one fresh bounded verifier. The prior lineage design was correct but still performed a routine O(n) compact-array equality proof in `HAHistoryProjectionStore` on every normal tail. The sole Swift writer moved that classification to `HAHistoryStreamAccumulator`, where merge/trim already knows whether a publication is initial/reset, unchanged, normal append/rolling trim, or an out-of-order reset, and already knows the retained old/new indices. The projection and graph layers no longer contain `elementsEqual`, retained source-array search, or another full history scan on the normal tail path.

A fresh verifier found that retained indices are not necessarily contiguous when the existing array is already unsorted and the incoming first timestamp is not older than its last timestamp, because reference behavior deliberately does not sort that shape. For existing `[10:X, 30:A, 20:B, 40:C]`, cutoff 25, and incoming duplicate `[40:C]`, the exact result is `[25:B, 30:A, 40:C, 40:C]`. The accumulator now counts retained existing indices during the existing cutoff pass and emits overlap only when that count equals the suffix length from the first retained index. Otherwise it omits that entity's overlap, so projection and graph preparation both take their safe full paths. This adds no extra full-window scan.

The typed client overload is additive and the raw callback remains compatible. The coordinator attaches owner generation, makes reset dominate unsafe pending relative updates. At this hardening revision, two skipped normal snapshots still became a reset; the later settled-append repair safely composes them. The projection store clears/full-projects a newer generation and returns nil for an older generation without mutation. Dashboard history/detail callbacks check cancellation after the awaited store call and again inside the final MainActor hop. Deterministic tests pin every transition classification, reconnect reset/generation, coalescing safety, stale-generation rejection with no subsequent lineage seed, raw correction full fallback, and cancellation suppression.

Final focused results are history 17/17, graph 17/17, history performance 6/6, and integration 3/3. Full `swift test` passes 87 tests with two intentional live-gated skips and zero failures in 52.858s. The production-shaped 99,999- point graph oracle remains exact at full=1/incremental=1; final debug timing is 10.069 ms versus 274.580 ms cold, and release is 1.523 ms versus 115.503 ms. The 100,000-point history projection oracle remains exact at full=1/ incremental=1; final debug timing is 19.218 ms versus 924.713 ms full, and release is 3.542 ms versus 592.864 ms. `git diff --check` is green. The regenerated graph is green at 21 nodes / 143 edges with fingerprint `7fd7546a2f9b860af39694f3a1449d1d0d8e21bab8609e82b31f7c77dc395675`; the resolver self-test passes 28 nodes / 59 edges with fingerprint `ab069e007ec7bfe3e9fb3019c9c58563ba9294af47b2ddb4fdc8bce4ef0a1f1a`.

## Final fresh independent verification — 2026-07-19

Verdict: **complete**. A fresh Phase 3 verifier inspected the exact settled working-tree diff and found no C01-01-through-C01-09 discrepancy. The green dependency graph was reused without reopening the frontend audit, and the previous current-tree read-only live transport and final GUI evidence were retained because the last proof-only hardening did not alter wire or drawing behavior.

The bounded review specifically confirmed:

- the reference-valid unsorted cutoff-gap plus duplicate endpoint omits lineage and takes exact full projection and graph-preparation paths;
- normal publications use accumulator-produced contiguous-suffix provenance, with no routine `elementsEqual`, retained-source, or `sourcePoints` scan;
- reset/unchanged/normal/out-of-order transitions and publication coalescing reuse a skipped snapshot only through accumulator-minted revision continuity and exact overlap intersection;
- newer owner generations clear lineage, stale generations return without mutation, and dashboard callbacks check cancellation after projection and inside the final main-actor publication hop;
- the 100,000-point rolling projection and 99,999-point prepared-series paths exactly match cold full oracles while using one full plus one incremental build; middle corrections, missing lineage, reset generations, and gapped retained input take the full path;
- the configured URLSession receive bound is applied before resume and accepts a frame above the platform's 1 MiB default, while the hover environment seam changes overlay drawing without removing graph gesture input.

Fresh command evidence:

```text
check-context: GREEN
resolver: PASS, 28 nodes / 59 edges,
  ab069e007ec7bfe3e9fb3019c9c58563ba9294af47b2ddb4fdc8bce4ef0a1f1a

HomeAssistantWebSocket*: 19/19
HomeAssistantHistoryStreamTests: 17/17
HomeAssistantHistoryStreamPerformanceTests: 6/6
HistoryStreamIntegrationTests: 3/3
GraphRenderingTests: 17/17
swift test: exit 0; 87 tests, two intentional live-gated skips, zero failures

NativeHAMac, ha-probe, GraphBench, GraphPyramidBench, HistoryStreamBench: built
release GraphRenderingBenchmarkTests: 2/2
release 100,000-point projection: exact, 4.079 ms incremental / 537.212 ms full
release 99,999-point graph preparation: exact, 1.125 ms incremental / 108.199 ms full
release HistoryStreamBench: exact checksum 8026277772552279935;
  stable merge 89.480 ms / full stable sort 144.857 ms / 1.62x
git diff --check: pass
```

The two expected Module 09 hover/step parity markers remain out of this module's scope. `docs/debugging/sample.txt` remains untouched. Module 01 is complete and ready for the orchestrator's intentional commit; the next rescue workflow action is Module 04 research.

## Post-completion settled-append repair — 2026-07-19

Status remains **complete**. A bounded regression follow-up reproduced the remaining 12-hour lag in a production-shaped four-entity/100,000-point pipeline. At `bbe0768`, four undelivered normal append/trim publications were conservatively coalesced to reset. Across five deliveries this produced 24 full entity projections and 24 full prepared-series builds. The single captured release baseline was 3,912.705 ms end to end: 56.125 ms accumulator, 3,179.182 ms projection, and 677.397 ms prepared/min-max work.

The repair keeps the existing correction/reconnect safety boundaries while removing avoidable settled work:

- accumulator-minted predecessor/current revisions prove a consecutive snapshot chain; coalescing maps the exact intersection of consecutive entity overlaps back to the last delivered snapshot, and resets if the chain is broken;
- normal sorted append/rolling-prefix trim removes and mutates a uniquely owned array in place. Swift copy-on-write preserves an older publication when a callback still retains it. Unsorted/gapped filtering, correction, out-of-order input, reconnect, and untrusted/manual input remain full paths;
- projection no longer retains the entire previous compact array merely to validate its next overlap. Revision continuity supplies that proof, while cached first-attribute provenance keeps sparse/minimal-response context exact without another normal full-window scan;
- prepared numeric construction builds min/max scalar storage in the same pass instead of mapping a second complete y-value array, and per-card/detail cache scopes prevent overlapping owners from replacing each other's lineage;
- repeated `.ready`, unchanged-history, identical state, and identical global connection-status publications no longer trigger redundant broad `ObservableObject` invalidation. The dashboard body also computes cleaned card columns once per update instead of recomputing `homeCards` separately.

Three final release end-to-end runs had a 714.208 ms median total (24.700 ms accumulator, 566.287 ms projection, 120.439 ms prepared/min-max), 5.48× faster than the captured baseline. Every run proved zero coalesced resets, zero accumulator full fallbacks, 80 reusable entity paths, full=4/incremental=20 for both projection and prepared-series work, and exact points against a cold full oracle. Release `HistoryStreamBench` retained exact checksum `8026277772552279935` and improved from the prior 89.480 ms to 47.714 ms.

Deterministic validation passed 92 tests with two intentional live-gated skips and zero failures in 56.234 seconds. Focused history 20/20, graph 18/18, integration 3/3, history-performance 6/6, and release graph benchmark 3/3 passed; all five release products built. The existing two expected Module 09 parity markers remain unchanged.

Fresh authenticated read-only verification passed exact CO2/VOC 1h (8,537 points/0.443s), 12h (102,364 points/five callbacks/4.608s), recovery 1h (8,536 points/0.439s), and representative 24h (56,488 points/2.719s), plus the forced reconnect owner test. The live graph benchmark retained identical 1×/2× points, axes, and bounds for 13,964 1h and 335,708 24h points; cold 24h preparation was 572.115/546.582 ms.

A bounded release GUI launch selected 12h and, after ten seconds, Accessibility reported `Live`, complete CO2/VOC/SPS30 axes and series, and no `Loading history`; direct inspection of `/tmp/nativeha-array-reuse-12h.png` confirmed the rendered graphs. One process snapshot at 48 seconds was 10.1% CPU and 266,064 KiB RSS. The verifier terminated only its release PID and confirmed it was gone, leaving the user's pre-existing debug app process untouched. The launch did emit the existing SwiftUI warning that an `onChange(of: String)` action updated multiple times in one frame. Splitting the broad dashboard observation architecture and eliminating any remaining SwiftUI fan-out are intentionally deferred; they are not needed for the now-bounded settled append pipeline.

The regenerated graph remains 21 nodes/143 edges with fingerprint `7f40511c8dee7ca35452bc2bf345ffcccc1b5f66c34c34c1c3174ebdbceecf0d`; the resolver self-test passes 28 nodes/59 edges with fingerprint `5082aedcd141cbbdeb05d5809a1324449bc001dbd1059b71a0fd50f56616e1f5`.

## Bounded current-anchor refresh for typed history decoding — 2026-07-28

The changed NativeHA anchors were reviewed without reopening the reference audit. The refreshed graph is green at 21 nodes / 143 edges with fingerprint `2711531db6e990ae4ce666c9075debbcbc60f9dd10a1138ee71a51c7b91d49f5`. The pinned hass-frontend and npm sources are unchanged.

The current receive path has one avoidable large-history round trip:

1. `decodeFrame` decodes the complete wire object into `JSONValue`;
2. `dispatch` unwraps `message["event"]` and enqueues that generic value;
3. `subscribeMessage` encodes the generic event back to JSON and decodes `HAHistoryStreamMessage`;
4. the history coordinator accumulates the typed compact states.

The current-task production-shaped 4.94 MiB / 102,418-point benchmark measured 3.601 seconds for the generic decode/re-encode/typed-decode path and 0.386 seconds for one direct typed decode. This establishes a measured implementation need; it does not change any C01 protocol or history semantics.

A repair may route a lightweight raw envelope and deliver the exact `event` slice to the typed subscriber, but it must preserve these boundaries:

- exactly one socket receive loop and ordered object/coalesced-array dispatch;
- event-before-ack safety, per-owner serial delivery, bounded callback concurrency/capacity, and isolation of slow owners from the receiver;
- the native per-transport outbound FIFO and its pre-send ownership checks;
- `resubscribe: false` for history, fresh request time/accumulator/generation after `ready`, and cancellation/late-generation suppression;
- full original-frame diagnostic logging when WebSocket debug is explicitly enabled;
- `subscribeRaw`, command-result routing, null/error handling, and unknown-ID behavior for non-history consumers.

Large typed decoding should execute on the existing serial delivery side of the receive actor, not introduce a second receiver or an unbounded detached task. If raw slices are retained for queued callbacks, copy the bounded event slice rather than accidentally retaining an entire coalesced frame. A malformed typed event must remain a controlled owner-local condition and must not tear down the shared socket.

Numeric compact seconds remain authoritative after decode. A later measured optimization may project them directly into graph-native numeric timestamps, but must separately preserve C01-05's `lc`/`lu` domain rule, sparse attribute fallback, sentinel timeline states, fractional precision, accumulator-minted lineage, generation resets, and full fallback for corrections. Do not fold that projection change into transport routing without its exact cold-oracle and lineage tests.

## Bounded current-anchor refresh — 2026-08-23

The checker was run before regeneration and reported yellow only for 13 moved NativeHA source/test anchors between `562686a` and `342d35b`. The complete intervening changes relevant to this packet were reviewed. The hass-frontend revision, `history.ts`, card/detail consumers, npm connection runtime, and their content hashes are unchanged; no broad frontend audit was repeated.

The refreshed manifest adds the already-implemented raw envelope scanner, tooltip metadata path, accepted-revision feed/coordinator, and their focused tests as explicit anchors. The regenerated graph is green at 21 nodes / 143 edges, no unresolved edge or truncation, and fingerprint `544a42651b28edcfddc7093eac3d695a9d524f3760bf25839cf04171a14e3004`. The resolver self-test passes at 31 nodes / 61 edges, fingerprint `7148dbfcc04d8eae2868612b04e880e4bbed3e2b41247561291e775edb345071`. After the bounded correction, the pre-regeneration checker was yellow for exactly `DashboardViewModel.swift`, `HistoryStreamIntegrationTests.swift`, and `GraphRenderingTests.swift`; regeneration returned the graph to green.

### Contract change review

| Contract | Current-anchor result | Gate |
|---|---|---|
| C01-01 | Direct raw-slice delivery decodes `HAHistoryStreamMessage` on the existing bounded owner-local worker; malformed typed payloads remain owner-local and generic subscribers retain fallback. Compact seconds and fractional precision remain intact. | pass |
| C01-02 | Stable accumulation, cutoff boundary, equal timestamps, duplicates, and reset/normal/unchanged/out-of-order classification are unchanged. Accumulator revisions remain owner-local provenance, never digest/timestamp ordering. | pass |
| C01-03 | Ordered entity IDs, effective typed range, request booleans, fresh start time, and attribute policy are unchanged. | pass |
| C01-04 | Fresh reconnect request/accumulator/generation, history resubscribe opt-out, cancellation, and zero final ownership remain verified on the refreshed Module 02 transport. | pass |
| C01-05 | Numeric timestamps now remain native through projection. `contentRevision` invalidates same-shape changes; `cacheLineage` is accepted only for the exact immediate predecessor. Registry precision plus frontend locale/time preferences and server timezone affect hover labels without mutating history or axis formatting. | pass |
| C01-06 | Raw `hoursToShow`, typed global/detail range policy, deterministic traversal owner ID, card isolation, detail dismissal, and state-change non-append remain intact. Dashboard history reconciliation now owns an epoch and desired-key set, removes every obsolete artifact before awaits, rechecks after each cancellation/start await, and cancels a just-created obsolete owner. Rapid range changes retain only the current owner while a still-desired pending sibling survives unrelated removal. | pass; fresh verifier GO |
| C01-07 | Typed 32 MiB receive policy, direct large-event decode, bounded delivery, cancellation checks after projection, bootstrap cleanup, and owner-local transport failure remain intact. Explicit refresh snapshots key/subscription/generation ownership and guards both success and error after await; initial subscribe rejection retires pending feed/generation ownership while preserving the owner-local error for an explicit, non-busy-loop retry. | pass; fresh verifier GO |
| C01-08 | A per-card feed publishes before `@Published histories`; mounted observers receive FIFO and pre-subscription replay is latest-only. Initial/out-of-order reset flags and normal flags are correct. One per-chart coordinator consumes accepted revisions serially off-main, resets generations, coalesces only visuals, and rejects late completions. | pass |
| C01-09 | The app path remains WebSocket-only. REST history remains confined to `HomeAssistantRESTClient`, `GraphBench`, `GraphPyramidBench`, and `HAProbe`. | pass |

The C01-06 regression now gates history acknowledgements, drives `1h → 3h → 12h`, releases all three commands, and proves only the current `12h` key, feed, subscription, and status survive. A separate surviving-sibling test removes one card while another desired owner is pending and proves the desired owner is neither canceled nor restarted. The C01-07 regression suspends and rejects refresh while range/view reconciliation removes the old key and proves the late failure cannot recreate subscriptions, histories, feeds, statuses, or an app error. Initial owner rejection is also covered: pending ownership/feed is retired, the owner-local error remains visible, and only explicit refresh creates one fresh owner and recovers without a busy loop. The correction is confined to `DashboardViewModel` orchestration; transport, accumulator, projection, feed, and graph cache semantics are unchanged.

### Validation evidence

- `HomeAssistantHistoryStreamTests`: 20/20 pass, including compact decode, stable accumulation/cutoff/equal timestamps/duplicates, transition facts, projection lineage, reconnect, cancellation, and 100-cycle ownership.
- Implementer `HistoryStreamIntegrationTests`: 7/7 pass, including raw-hour preservation, effective range keys, overlapping-card isolation, feed reset flags before published histories, detail dismissal, late-publication suppression, rapid range reconciliation, refresh/removal rejection, surviving pending sibling, and initial rejection followed by explicit recovery.
- Typed transport/large-frame coverage: envelope 4/4, production adapter 2/2, and WebSocket connection 22/22 pass. The direct 100,000-sample typed event, coalesced FIFO, detached-decode generation guard, malformed owner-local decode, registry precision, and frontend-language commands are green.
- History/tooltip/graph coverage from the refresh remains history graph support 10/10 and tooltip formatting 7/7. The implementer reran `GraphRenderingTests` at 27/27: nearest-sample hover remains the sole expected failure, while `testHAReferenceNumericHistoryUsesStepEndSegments` is now an ordinary passing assertion after removal of its stale `XCTExpectFailure`.
- Fresh offscreen history visual coverage passed loading/replay/update settlement for numeric and timeline fixtures in three runs. All 15 PNGs were 992x520, manually inspected, populated, labelled, and visibly distinct where required. No new reference baseline was approved. The hover-hidden exact-PNG test passed this run, but remains a time-dependent fixture risk because its two renders use separate implicit `Date()` window ends. Exactly one pre-existing unrelated GUI fixture failure remains: `GUIRenderingAndPerformanceTests.testWarmGraphInteractionRenderCanBeMeasuredWithXCTMetrics` at line 184 uses fixed January data with no fixed August viewport, so the zoomed viewport has no points and the initial `XCTUnwrap(GraphRenderResult)` fails. Inspectable passing Module 01 artifacts are under `.build/render-artifacts/`, including `history-stream-run-03-loading.png`, `history-stream-run-03-numeric-replay.png`, `history-stream-run-03-numeric-update.png`, and `history-stream-run-03-timeline-replay.png`.
- Fresh authorized read-only release live smoke passed in 3.336 s with final zero ownership and no state-changing call. Representative 1h delivered 2,384 points in 0.064 s; reconnect produced a fresh owner with loading count 2. Visible CO2/VOC delivered 8,576 points at 1h in 0.173 s, 102,370 points at 12h in 1.490 s, and recovered 8,576 points at 1h in 0.170 s without a reconnect. Representative 24h delivered 57,066 points in 0.928 s. Registry bootstrap returned 276 entities / 74 display precisions, frontend language `en`, and all final pending/subscription/wire/receive/delivery counts were zero.
- Fresh `swift build -c release --product NativeHAMac` passed. The release executable is `.build/release/NativeHAMac`.
- Bounded correction writer results additionally pass history 20/20, WebSocket connection 22/22, envelope 4/4, dashboard bootstrap 2/2, and `git diff --check`.

### Fresh independent verification — 2026-08-23

Verdict: **GO; complete**. A completely fresh read-only verifier inspected the corrected diff and current anchors, reran deterministic/visual/release/live evidence, and returned GO for every contract:

| Contract | Fresh verifier evidence | Verdict |
|---|---|---|
| C01-01 | Compact typed direct-event decode, malformed owner-local handling, fractional timestamps, and REST/stream shape separation pass. | GO |
| C01-02 | Stable accumulation, cutoff boundary, equal timestamps, duplicates, unchanged/normal/reset/out-of-order facts, and exact projection lineage pass. | GO |
| C01-03 | Ordered IDs, typed range request, booleans, fresh start time, and attribute policy pass. | GO |
| C01-04 | Initial ownership, reconnect freshness, history resubscribe opt-out, cancellation, and zero final ownership pass. | GO |
| C01-05 | Domain timestamp/attribute rules, native numeric precision, sentinel timeline states, tooltip metadata, content revision, and strict cache lineage pass. | GO |
| C01-06 | Rapid `1h → 3h → 12h`, surviving pending sibling, raw hours, stable identity, range keys, detail lifecycle, and card isolation pass. | GO |
| C01-07 | Late rejected refresh after removal, initial rejection/explicit recovery, large frame, bounded owner-local delivery, bootstrap cleanup, and generation suppression pass. | GO |
| C01-08 | Feed-before-`@Published`, mounted FIFO, latest-only pre-mount replay, reset flags, off-main serial coordinator, stale completion rejection, and visual settlement pass. | GO |
| C01-09 | Normal app history remains WebSocket-only and REST remains tool/benchmark-owned. | GO |

Both Module 01 and Module 02 context checkers are green. The resolver self-test passes 31 nodes / 61 edges. Focused results are stream 20/20, integration 7/7, WebSocket connection 22/22, envelope 4/4, production adapter 2/2, history support 10/10, tooltip 7/7, graph 27/27, and bootstrap 2/2. The formerly flaky `testProductionHistoryProcessingGateAllowsDismissalAndCancellationSuppressesLatePublication` passed 20/20 isolated stress repetitions, followed by the complete integration class at 7/7. The step-end regression is an ordinary pass; nearest-sample hover is the sole intentional expected failure.

The post-patch full suite executed 139 tests with three intentional live/benchmark skips and exactly one failure: the unrelated fixed-time `GUIRenderingAndPerformanceTests.testWarmGraphInteractionRenderCanBeMeasuredWithXCTMetrics` fixture classified above. No Module 01 contract depends on that stale measurement fixture. The 15 required current PNGs, release build, authorized read-only live smoke, and exact final zero-ownership checks all passed.

## Bounded post-Module 04 anchor maintenance — 2026-08-23

The checker was run before regeneration and reported yellow for exactly eleven moved Module 01 anchors: `Models.swift`, `AppConfig.swift`, `CardViews.swift`, `DashboardViewModel.swift`, `GraphRenderScheduling.swift`, `GraphTooltipFormatting.swift`, the history live smoke, and the history integration, graph-rendering, tooltip, and GUI test files. The complete Module 04 changes to those anchors were inspected. The pinned hass-frontend history, history-card/detail, npm connection, and Module 02 transport contracts and content hashes are unchanged; no reference audit was repeated.

The manifest now anchors `JSONValue.canonicalSemanticValue`, the moved `LovelaceCard` and resolved identity/dashboard types in `LovelaceModels.swift`, the immutable presentation types, the mounted-chart lifecycle/registry, and their exact identity/presentation tests. The former `LovelaceCard` symbol was removed from the `Models.swift` entry. The regenerated graph is green at 21 nodes / 143 edges with zero unresolved edge or truncation and fingerprint `893b3e913aab46ad04b8e482962229275b5a9119354031202450a4f2d6706b91`. The resolver self-test passes at 31 nodes / 61 edges with fingerprint `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`.

### Contract classification

| Contract | Post-Module 04 result | Classification |
|---|---|---|
| C01-01 through C01-05 | Typed compact delivery, stable accumulation/cutoff/equal timestamps/duplicates, request fields, fresh reconnect ownership, numeric projection, `contentRevision`, and exact immediate-predecessor `cacheLineage` are unchanged. | contract preserved |
| C01-06 | Raw `hoursToShow` remains on the immutable source card while the selected AppConfig range remains the effective request policy. History owner identity now uses exact resolved source path plus canonical raw semantics, then ordered entity IDs and effective range. Identical decode retains the owner; insertion/removal/reorder/replacement re-key only according to the Module 04 path/semantic rules. There is no UUID, `hashValue`, digest ordering, or timestamp ordering. | integration strengthened; no contract revision change |
| C01-06/C01-07 | Config apply and external history load/range/refresh work now share one serialized MainActor dashboard-owner operation tail. Each awaited cancellation/startup/refresh boundary revalidates current config sequence, reconciliation epoch, desired key, and generation. Superseded cleanup retires only delivery ownership; the final candidate alone removes accepted stores or mounts. Exact revert and stale-middle cases restore one current owner without overlap or a late publication. | lifecycle strengthened; existing latest-owner/error-isolation contract preserved |
| C01-08 | `GraphHistoryRevisionFeed` still publishes before `@Published histories`, retains mounted FIFO/latest-only pre-mount replay, and drives one serial off-main coordinator. A dashboard-owned weak one-to-many mount registry now synchronously disconnects every obsolete unit chart immediately before final config install; identical and exact-revert owners keep a reconnectable mounted lifecycle. Coordinator reset/generation still rejects old render completion and exact projection/cache lineage remains strict. | lifecycle strengthened; accepted-publication/render contract preserved |
| C01-08 formatting | Module 04 adds an injected axis-formatting override only for deterministic GUI evidence. Production still uses the exact legacy `h:mm a` axis formatter. Tooltip locale/precision/timezone metadata, stored history, cache keys, and Core Graphics default are unchanged. | test seam; observable production behavior unchanged |
| C01-09 | Normal dashboard/detail history remains WebSocket `history/stream`; REST remains tool/benchmark-only. | contract preserved |

Invalid-only history cards now render a local diagnostic and create no request; a mixed valid/malformed row list retains the valid history owner and exposes the malformed row placeholder. This is Module 04 recovery integrated at the C01-06 owner-discovery boundary, not a change to stream accumulation or projection.

### Focused refresh evidence

- `HomeAssistantHistoryStreamTests` passed 20/20; `HistoryStreamIntegrationTests` passed 17/17, including both unified-tail entry orderings, config/startup and refresh/config interleavings, identical coalescing, insertion/removal/reorder, exact revert, stale retirement, and late-publication suppression.
- `GraphRenderingTests` passed 29/29 with only the recorded expected nearest- sample hover parity marker; `GraphTooltipFormattingTests` passed 7/7. The mounted hosted `BitmapLineChart` dashboard-replacement test passed 1/1.
- Exact identity/raw/presentation coverage passed 15/15 across `LovelaceModelTests` and `LovelacePresentationTests`, including the 500-card bounded traversal/lifetime fixture.
- The authorized read-only live history smoke passed 1/1 in 5.995 seconds. It retained three views, 22 top-level / 31 recursive cards and 66 rows; delivered 8,598 one-hour and 102,583 twelve-hour CO2/VOC points, then 8,600 recovery points and 57,090 representative 24-hour points; reconnect loading occurred twice; and final connection/history ownership was zero. No state-changing Home Assistant call was made.
- The fresh final Module 04 verifier independently ran the exact current tree's 168-test full suite (three authorized live skips, one unchanged fixed-time GUI fixture failure, zero introduced failures), release build, six manually inspected GUI artifacts, live dashboard/history smoke, and a separate lifecycle/identity/cache audit. Those results are recorded in the green Module 04 packet and remain applicable to the shared Module 01 anchors.

No C01 observable contract changed, so contract revision remains 3 and status remains `complete`.

### Preserved Module 09 boundary

The known stale visual request may still reach the coordinator after a newer accepted snapshot and cause repeated correctness-safe alignment/full-preparation fallback. Preparation is off-main, so this is not the removed synchronous-main bug. Keep it in the bounded Module 09 packet. Do not compare `contentRevision`, `firstTimestamp`, or `lastTimestamp` to infer freshness; the two attempted heuristics were rejected and reverted because they can return stale graph content.

## Bounded post-housekeeping anchor maintenance — 2026-08-25

The pre-refresh checker was yellow for exactly one anchored file, `Tests/NativeHAMacTests/GUIRenderingAndPerformanceTests.swift`, after NativeHA commit `dda63c1b69feed1de38e2f0657504bc9cd8c883c`. Exact inspection of `933abd5..dda63c1` confirmed that the relevant change only gives the synthetic January 2026 `performanceInput` an explicit matching `windowStart` and `windowEnd`. This repairs the previously classified fixed-time performance fixture, which had otherwise been clipped against the current date. It does not change production graph preparation/rendering, history publication, owner identity, range policy, or any C01 behavior.

The complete `GUIRenderingAndPerformanceTests` class passed 10/10 on the current tree, including the formerly failing warm interaction measurement and the Module 01 history/graph and Module 04 Lovelace/lifecycle artifacts that share the helper. Regeneration from the unchanged reviewed manifest is green at 21 nodes / 143 edges, zero unresolved edges, no truncation, and fingerprint `85ce90097513ac12bcf14d24c6b1b661f2d7a1754cc234982ee45eb842564398`. The resolver self-test remains green at 31 nodes / 61 edges with fingerprint `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`. No C01 observable contract changed, so status remains `complete` and contract revision remains 3.

## Bounded post-Module 12 anchor maintenance — 2026-08-25

The pre-refresh checker was yellow for exactly nine shared Module 12 anchors: `HomeAssistantWebSocketClient.swift`, `Models.swift`, `AppConfig.swift`, `DashboardView.swift`, `DashboardViewModel.swift`, `HomeAssistantHistoryLiveSmokeTests.swift`, `HomeAssistantWebSocketConnectionTests.swift`, `GUIRenderingAndPerformanceTests.swift`, and `HistoryStreamIntegrationTests.swift`. The complete final diff for all nine was inspected against C01 revision 3. Pinned frontend history/card/detail and npm connection sources are unchanged; no broad reference audit was repeated.

- The client/model additions are the independent minimal current-user command and `id` response needed by Module 12. They do not change typed history decode, accumulation, projection, subscription, or REST separation.
- The AppConfig change adds only the navigation exclusion/persistence policy. The approved global `[1, 3, 6, 12]` range, 24-hour detail default, 32 MiB receive bound, Core Graphics renderer, tooltip, graph-feed, coordinator, logging, and cache policies are unchanged; raw Lovelace `hoursToShow` remains source data.
- `DashboardView.swift` now renders the selected presentation view, retains the approved range selector, applies the three-column exception only to `default_view`, and gives unrelated/panel/empty views bounded native presentation. It does not alter history values, request construction, feed publication, prepared-series lineage, or renderer freshness.
- `DashboardViewModel.swift` generalizes the existing single MainActor owner tail from config/range/load/refresh to exact view selection. Desired history requests come only from the final selected resolved view and retain exact owner identity + ordered entity IDs + effective range. Same-view/exact intersection owners survive; hidden/removed/range-changed owners detach startup, acknowledgement, delivery, subscription, detail, feed, mount, and render ownership in the established cancel-before-final-install order. Every suspended boundary rechecks config/navigation/range/desired keys, and late acknowledgements/history/feed/render work cannot publish. Global state and connection status remain installed. No `contentRevision`, digest, endpoint timestamp, or first/last timestamp infers freshness or ancestry.
- The live-smoke and WebSocket tests add only current-user presence/typed command evidence. GUI additions exercise selected-view layout/accessibility and the warmed 500-card layout path. History integration additions directly prove view cancellation before install, late history/ack rejection, same-view retention, exact A -> B -> A restart, refresh/selection ordering, 100 selection/range cycles, final one-owner settlement, and zero teardown ownership. Existing C01 fixtures remain intact.

Module 12 therefore closes the former visible-view ownership handoff in C01-06/C01-07 without changing any C01 observable contract. Status remains `complete` and contract revision remains 3. The fresh Module 12 verifier passed all 23 inherited-plus-new `HistoryStreamIntegrationTests` in 1.700 seconds and the 100-cycle/500-card lifecycle gate in 0.268 seconds. The exact final full suite passed 196 tests with three authorized skips and zero failures; the release app built successfully. The authorized read-only live smoke passed in 5.085 seconds with representative one-hour 2,385 points, CO2/VOC one-hour 8,582 and 8,584 points, 12-hour 102,737 points, 24-hour 57,067 points, and final connection/history ownership zero. No state-changing call was made.

Regeneration from the unchanged reviewed manifest is green at 21 nodes / 143 edges, one cycle, zero unresolved edges, no truncation, and fingerprint `8080112b8a675b16476f214c5e5450e26321c93bc19081db0fa47a48fa5880cc`. The resolver self-test passes at 31 nodes / 61 edges with fingerprint `f9462562d7a09d8b37fea24ac7d8d9eebc7767fca7579bcedd489597a8a2ae18`. No Swift or test file was edited by this maintenance.

## Bounded post-Module 05 anchor maintenance — 2026-08-31

The pre-refresh checker was yellow for exactly ten shared Module 05 anchors: `HomeAssistantWebSocketClient.swift`, `HomeAssistantWebSocketConnection.swift`, `Models.swift`, `CardViews.swift`, `DashboardView.swift`, `DashboardViewModel.swift`, `HomeAssistantHistoryLiveSmokeTests.swift`, `HomeAssistantWebSocketConnectionTests.swift`, `GUIRenderingAndPerformanceTests.swift`, and `HistoryStreamIntegrationTests.swift`. The exact accepted Module 05 diff and final independent evidence were inspected against C01 revision 3. The pinned frontend history/card/detail and npm connection sources are unchanged; no broad reference audit was repeated.

Module 05 extracts history dictionaries, generations, startup tasks, subscriptions, desired keys, and graph revision feeds into the synchronous MainActor `DashboardHistoryCoordinator` façade. The sole `dashboardOwnerOperationTail`, request construction, startup/publication guards, feed-before-`@Published` boundary, and reconnect behavior remain in `DashboardViewModel` and Module 01 core. The manifest now pins that new storage owner in addition to the unchanged `DashboardViewModel`/`HistoryRequest` boundary. The remaining changed anchors add the typed entity owner, explicit shell/lifecycle presentation, stronger connection attempt isolation, and expanded stop/retry/race evidence; they do not alter history accumulation, projection lineage, exact active-view/range keys, detail isolation, mounted feed/render ownership, Core Graphics, or tooltip semantics. No hash, `contentRevision`, endpoint time, or first/last timestamp is used for freshness.

Regeneration is green at 21 nodes / 143 edges, one cycle, zero unresolved edges, no truncation, and fingerprint `75ba7d234b0d5af43ac039dbd4776508dcf55e0315594ff81e0f35fa94c8116d`. The resolver self-test passes at 31 nodes / 61 edges with fingerprint `da06a3bfa032082ad19743e076372c8a73181f37d75f4f468b60395000afa13d`. The fresh final Module 05 verifier passed 360/360 race processes, the 237-test full suite with three authorized skips and zero failures, release, GUI, and authorized read-only live smoke with no state-changing call. No C01 observable contract changed, so status remains `complete` and contract revision remains 3. The separate Module 09 stale-viewport fallback remains open. No Swift or test file was edited by this maintenance.

## Handoff

Module 01 is independently `complete` at contract revision 3 and its post-Module 07 graph is green. Preserve exact resolved active-view history identity, the unified dashboard-owner operation tail, post-await config/ navigation/range/generation guards, direct typed transport, exact projection lineage, feed-before-`@Published`, reconnectable mounted chart lifecycles, Core Graphics, tooltip metadata, and the separate Module 09 fallback. Never infer freshness from hashes or endpoint timestamps. Modules 05 and 06 are independently complete, and Module 07 current conditions are independently verified with forecast ownership deferred. The next staged action is Module 08 research only under the fixed-server/no-profile assumption.

## Change log

- 2026-07-17: created reviewed Module 01 manifest and compact dependency graph; completed bounded reference/Swift research; reconciled the rescue plan with verified Module 02 behavior and canonical global-range/future-cache intent; defined C01-01 through C01-09; status `research-ready` at contract revision 1.
- 2026-07-17: implemented C01-01 through C01-09 with one Swift writer; added deterministic core/macOS/visual/performance/live-smoke coverage and the tracked exact-output merge benchmark; regenerated the graph; recorded implementer validation; status `verification-ready` pending a fresh independent verifier.
- 2026-07-17: fresh independent verification passed C01-01, C01-02, C01-03, C01-05, C01-06, and C01-09, but retained `verification-ready`: C01-04/C01-07 lack required failure/generation evidence, and C01-08 produced visibly unsettled PNGs while its claimed gated dismissal probe had no gate or production-path contention.
- 2026-07-17: the single Swift owner completed the bounded C01-04/C01-07/C01-08 repair; added deterministic reconnect-failure/owner-isolation and real production-path cancellation evidence; replaced fixed visual timing with bounded render-state/bitmap readiness; regenerated and inspected settled artifacts; status remains `verification-ready` for a fresh verifier.
- 2026-07-17: a fresh independent re-verifier passed C01-04/C01-07 and all nonvisual checks, but retained `verification-ready`: three repeated visual tests falsely accepted the same incomplete numeric/timeline replay images. C01-08 requires one more bounded visual-readiness repair.
- 2026-07-17: the single Swift owner completed a visual-only C01-08 repair; replaced coarse readiness with consecutive `1h` template and five-region axis glyph-component checks, added exact erased-label-band regressions, generated and inspected 15 unique artifacts, and documented the in-app viewer's inconsistent presentation of identical data URLs. Production source remained unchanged; status stays `verification-ready` for a fresh verifier.
- 2026-07-18: repaired the SPS30 gesture token-starvation regression with one serialized render plus a coalesced latest request; added reusable live 1h/24h stage and scheduler benchmarks, cancellation checkpoints, fidelity oracles, deterministic regression coverage, and live in-gesture frame evidence. Status remains `verification-ready` for the separate loading/reconnect hold and a fresh verifier.
- 2026-07-19: bounded contract-revision-2 refresh confirmed the 12h failure as URLSession's unconfigured 1 MiB receive limit (4,912,600-byte production replay), recorded the scope and test gaps of `e4eecb2`, `f8f55f0`, and `3cd05d5`, and reopened end-to-end gesture verification before/after 12h.
- 2026-07-19: configured the typed 32 MiB receive policy, restored the evidence-backed 10-second command timeout, validated strict actual-wire ID ordering and canonical timestamp semantics, and added plot-only capture configurability. After the repaired 12h path exposed a separate settled CPU bottleneck, added exact-overlap projection/prepared-series reuse with full fallback for corrections. The fresh independent release GUI verifier passed 1h/12h/recovery health, resource, gesture-progress, and settlement checks; the current-tree full suite, five products, release benchmarks, and live ownership harness passed. Status remains `verification-ready` for the final orchestrator's bounded review/commit decision.
- 2026-07-19: bounded review found that the prepared-series rolling fast path located the old tail but did not prove the source values before it were unchanged. The same sole writer retained the prior source array and now requires exact old-suffix/new-prefix equality before reusing rendered points. Added a middle-correction-plus-new-tail full-path oracle while retaining the clean rolling incremental oracle; focused and 78-test full suites pass.
- 2026-07-19: a fresh bounded verifier passed all transport, parser, projection, live ownership, release benchmark, and retained GUI gates, but found that a middle correction/out-of-order insertion combined with a newer tail can bypass exact-overlap proof in `GraphPreparedSeriesCache` and omit the corrected sample. Status remains `verification-ready` for one bounded cache repair and fresh verification of that counterexample.
- 2026-07-19: the next read-only verifier confirmed the correction safeguard but found the exact proof also rejects HA's normal moved-cutoff plus retained- overlap plus new-tail shape. A 99,999-point oracle remained exact only through a second full preparation; optimized equality proof cost was 5.634 ms. Status remains `verification-ready` for a boundary-aware exact-overlap repair.
- 2026-07-19: replaced the duplicate graph-layer equality proof with transient predecessor/index lineage emitted by `HAHistoryProjectionStore`; reset lineage on owner loading/reconnect/refresh, kept transient provenance out of Codable output, and added exact moving-boundary, absent-lineage, correction, and generation-reset tests. The 99,999-point release graph update measured 0.861 ms versus 110.403 ms cold full; focused and 83-test full suites pass.
- 2026-07-19: final fresh independent verification passed C01-01 through C01-09. Exact unsorted-gap/full-fallback, generation/cancellation, coalescing, 100k fast-path, receive-bound, hover-policy, focused/full-suite, five-product-build, and release-benchmark gates are green; status `complete`.
- 2026-07-19: post-completion settled-append repair composed consecutive normal snapshot lineage instead of resetting, reused rolling accumulator storage, removed retained compact-window and duplicate min/max passes, scoped prepared caches per owner, and suppressed redundant dashboard publications. The exact four-entity/100k end-to-end release median improved 5.48× with zero avoidable resets/full fallbacks; deterministic, live 1h/12h/recovery/24h, live graph, and bounded release-GUI checks pass; status remains `complete`.
- 2026-07-28: refreshed current Module 01/02 Swift anchors after a measured large-history decode benchmark. Recorded the generic `JSONValue`→re-encode→typed-decode bottleneck and the exact receive/delivery/reconnect/projection contracts a direct typed path must preserve. Regenerated a green 21-node/143-edge graph; status remains `complete`.
- 2026-07-28: added Home Assistant-default graph crosshair formatting using effective entity-registry display precision, frontend locale/time preferences, and the retained server timezone, with typed global/per-entity digit and time-precision overrides. Numeric formatting remains lazy at hover time so the native-timestamp history preparation path is unchanged; native and legacy timestamp hover samples are equivalent, and the 84,000-point debug preparation benchmark averaged 389 ms versus the recorded 405 ms baseline. The axis formatter and history transport semantics are unchanged; status remains `complete`.
- 2026-08-23: bounded current-anchor refresh verified direct typed delivery, compact projection, feed-before-published ordering, FIFO mounted preparation, latest-only pre-mount replay, reset flags, tooltip metadata, off-main chart ownership, Core Graphics default, release/live behavior, and the strict projection/cache oracles. A fresh orchestration audit found two bounded dashboard races: rapid range changes can retain an obsolete owner and late explicit-refresh failure can recreate status for a removed key. Recorded deterministic gated regressions and an epoch/generation-safe repair handoff; status returns to `verification-ready` at contract revision 3.
- 2026-08-23: the bounded correction added desired-key/epoch reconciliation, post-await owner checks, obsolete-owner cancellation, guarded refresh completion/error, and cleanup that preserves initial rejection status while allowing explicit recovery. Four gated integration tests cover rapid range changes, late rejected refresh after removal, a surviving pending sibling, and initial rejection followed by explicit refresh. The writer's focused suites and diff check pass; status remains `verification-ready` for a completely fresh verifier, with prior release/live evidence not promoted to post-correction evidence.
- 2026-08-23: a completely fresh verifier returned GO for C01-01 through C01-09. Both module checkers, resolver, all focused suites, 20/20 detail-gate stress, 15 manually inspected GUI artifacts, release build, and authorized read-only 1h/reconnect/12h/recovery/24h live smoke passed with final zero ownership. The 139-test full suite retained exactly one classified unrelated fixed-time performance-fixture failure and three intentional skips. Status is `complete`; next action is bounded Module 04 research.
- 2026-08-23: regenerated the graph after Module 04 replaced temporary card identity/reconstruction, unified config/range/load/refresh owner operations, and added synchronous mounted-chart lifetime retirement across eleven shared anchors. Exact diff inspection, 73/73 stream/integration/graph/tooltip tests, 15/15 identity/presentation tests, the hosted mounted-chart test, and fresh read-only 1h/reconnect/12h/recovery/24h live smoke all passed. C01 contracts are preserved, contract revision remains 3, and the graph is green.
- 2026-08-31: pinned the extracted `DashboardHistoryCoordinator` storage owner, inspected all ten shared Module 05 anchors, and regenerated a green 21-node / 143-edge graph without changing C01 revision 3 or the open Module 09 stale-viewport boundary. Status remains `complete`.
- 2026-09-01: inspected the six shared Module 06 anchors and regenerated a green 21-node / 143-edge graph with fingerprint `ee28b70f56a8bd2fccfe661db121866379622e4ce185aa5643f3c861a4c79140`. C01 revision 3 remains complete; Core Graphics and the separate Module 09 stale-viewport fallback are unchanged.
- 2026-09-08: inspected the Module 07 changes to shared Lovelace/current-state anchors and regenerated a green 21-node / 143-edge graph with fingerprint `9731b5099e3a7f4cb6cca4279981e34124c33ced4ec62caedfcec9c7f5252651`. C01 revision 3 remains complete; Core Graphics and the separate Module 09 stale-viewport fallback are unchanged. Module 08 research only is next.
