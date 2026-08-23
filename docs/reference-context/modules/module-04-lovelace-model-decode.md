---
module: "04"
title: Lossless Lovelace decode and stable resolved identity
plan: ../../rescue-plan/module-04-lovelace-model-decode.md
status: complete
contract_revision: 1
depends_on: ["01", "02"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: f58345bde090444777eb3cbf610822c466ee2300
graph_file: ../generated/module-04.dependencies.json
graph_fingerprint: 0295bb6ce08fba5412d8d81e01816f668c5ad9860317781e2f0c7dd706f9fa8e
last_researched: 2026-08-23
last_implemented: 2026-08-23
last_verified: 2026-08-23
---

# Module 04 evidence packet

## Gate and scope

This packet is the implementation authority for the bounded Module 04
Lovelace-model stage. It starts from independently complete Module 02 transport
and Module 01 history/feed/render ownership. The implementation agent should
not repeat the broad frontend audit when the graph remains green.

In scope:

- preserve the complete semantic JSON tree for the fetched Lovelace config;
- expose typed fields needed by the currently supported native entities,
  history, weather, markdown, stack/grid/container, and view-routing surfaces;
- recover malformed or unsupported children locally after a valid root;
- replace random/ad-hoc model identity with deterministic resolved traversal
  identity;
- apply NativeHA presentation policy through immutable wrappers rather than
  rebuilding decoded cards; and
- reconcile history, feed, SwiftUI, render-coordinator, and cache ownership
  when config identity changes.

Out of scope:

- new renderer parity for conditional, grid, card-detail, or Modules 06-11;
- Module 03 profile persistence or a settings UI;
- Module 12 navigation UI or active-view subscription reconciliation;
- Module 05 orchestration decomposition;
- Lovelace edit/save support; and
- the separate Module 09 stale-viewport fallback repair.

## Observable behavior contracts

| ID | Trigger | Required observable behavior | Failure and lifecycle rule |
|---|---|---|---|
| C04-01 | Decode a valid Lovelace root | Preserve the complete top-level, view, card, nested-card, and entity-row semantic JSON values with the existing `JSONValue`; expose typed accessors without mutating raw values. Explicit `false`, `null`, arrays, objects, strings, booleans, integers, and doubles remain distinguishable after `JSONValue` decoding. | Object member order and original numeric lexical spelling are not available and are not contractual. Structural `JSONValue` equality is contractual. |
| C04-02 | Decode invalid root framing or a malformed child | Invalid JSON, a non-object root, or a missing/non-array `views` container fails the Lovelace bootstrap. Once a valid `views` array exists, each view, card, nested card, and row is decoded independently; malformed/unsupported children remain in order as raw diagnostic nodes/placeholders and valid siblings survive. | A required field with the wrong type on a supported renderer cannot silently take the absent-field default. Diagnostics identify the local raw path. No child failure discards a valid sibling list. |
| C04-03 | Read a supported current card/view/row | Typed accessors cover the fields in **Typed native surface** while preserving every unknown key recursively. String rows and object rows both remain representable; object rows without an entity are preserved as unsupported rows. | Missing optional values use the documented renderer/reference default. Present-but-invalid values produce a local invalid node or diagnostic state, not silent coercion. |
| C04-04 | Resolve the same or changed source config | Resolve view/card/row identity before presentation. Identity contains the exact raw source traversal path, including container labels and indices, plus a deterministic canonical semantic representation of the raw node. Identical same-path semantic input produces equal identity across processes and decodes. | No UUID, `hashValue`, process-random seed, history digest, or endpoint timestamp participates in model/traversal identity or ordering. A compact digest may be diagnostic only; exact canonical equality controls reuse. |
| C04-05 | Insert, remove, reorder, replace, or duplicate siblings | Source paths disambiguate identical siblings. A same-path semantic replacement changes identity. Insert/remove/reorder intentionally re-keys every affected path while unaffected paths retain identity. Two identical siblings have distinct path identities; swapping byte-identical siblings is semantically indistinguishable and does not invent ancestry. | The old affected owner must be invalidated and canceled before a replacement owner can install. Identity must never alias a different same-position config. |
| C04-06 | Apply hidden/injected entities, flattening, or column placement | Keep decoded models immutable. A resolved/presentation wrapper carries source node, source path/identity, effective rows, visibility, flattening, and placement. Filtering never reconstructs the source card or renumbers later source identities. | Apply the approved vertical-stack flattening/three-column layout only to the actual `default_view`. Preserve the `home_3h`/`home_12h` maintenance views raw; Module 12 owns hiding them from intended navigation. Synthetic injected rows use deterministic parent/policy/index identity. |
| C04-07 | Apply identical or changed config to a running dashboard | Reuse a history/feed/chart owner only when resolved card identity and the effective request contract are exactly equal. Identical refresh keeps the same subscription key, feed instance/generation, SwiftUI chart lifetime, coordinator, and cache scope without wire churn. | Compute the new tree first. Retire obsolete generation/startup/subscription delivery ownership before awaiting cancellation so old and replacement ownership cannot overlap, but preserve the published dashboard's accepted feeds/histories/statuses and mounted lifecycles while awaits are pending. Complete captured ownership cancellation, then recheck latest-wins immediately before any destructive visual or presentation action; only the candidate that remains final may remove visual stores or invalidate mounts immediately before publish. Superseded cleanup is ownership-only and cannot destructively apply an intermediate snapshot. |
| C04-08 | A history or render completion races config replacement | The resolved owner identity flows through `HistoryRequest`, subscription keys, `GraphHistoryRevisionFeed`, SwiftUI IDs, coordinator generation, and prepared-cache scope. Late old history projection, feed delivery, or render completion cannot mutate the new/visible owner. | Preserve Module 01 feed-before-`@Published`, mounted FIFO, pre-mount latest-only replay, reset flags, off-main serial preparation, and exact immediate-predecessor cache lineage. A same-identity owner returning after stale cleanup keeps its mounted lifecycle reconnectable while the retired feed observer is released. Never infer freshness from hashes or first/last timestamps. |
| C04-09 | Read graph/weather/layout policy from decoded config | Raw `hours_to_show` remains on the source node while `AppConfig.graphTimeRangePolicy` supplies the effective selected history range. `show_forecast: false` differs from absence. Core Graphics remains the primary renderer; current tooltip, WebSocket, logging, and layout policies remain intact. | Module 04 does not make Metal default, remove the graph selector, generalize the default-dashboard layout deviation, or convert app history to REST. |
| C04-10 | Decode/render a large or live dashboard | A deterministic 500-card fixture decodes, resolves, transforms, refreshes, and discards with bounded ownership and no random-ID accumulation. The current live dashboard decodes read-only without dropping supported cards/rows. Required offscreen artifacts expose local fallbacks and nested layout without treating pixels as evidence of raw preservation or lifecycle correctness. | Release/full tests, GUI inspection, and authorized read-only live smoke must pass before `complete`. Any introduced failure, missing required visual evidence, owner leak, or unresolved behavior choice is NO-GO. |

Opaque UUIDs may remain for non-orderable runtime generation provenance, such
as history generations, feed generations, or coordinator lifetime isolation.
They are not decoded model identity, traversal identity, config ancestry, or a
freshness comparison.

## Decode and recovery policy

| Boundary | Input | Result |
|---|---|---|
| Root bytes | Invalid JSON | Throw; dashboard bootstrap exposes its existing controlled error and disconnect cleanup. |
| Root value | Non-object | Throw. |
| `views` | Missing, `null`, or non-array | Throw; no usable Lovelace dashboard exists. |
| View element | Object with valid/optional fields | Preserve raw object, typed fields, cards, and source index. |
| View element | Non-object or invalid required routing field | Preserve an invalid view node at its source index with local diagnostic; other views remain available. |
| `cards`/nested `cards` | Absent | Empty/absent according to the source field; not an error. |
| `cards`/nested `cards` | Present but non-array | Mark that containing node invalid for supported rendering while preserving its raw value and siblings. |
| Card element | Unknown but valid string `type` | Preserve and render the existing unsupported-card placeholder. |
| Card element | Non-object, missing/non-string `type`, or invalid required supported field | Preserve an invalid card node/placeholder at the original path. |
| Entity row | String | Preserve raw string and expose its entity ID. |
| Entity row | Object | Preserve the complete object and expose common typed fields when valid. |
| Entity row | Unknown object or object without `entity` | Preserve and render a local unsupported-row placeholder. |
| Entity row | Other scalar/array or malformed supported field | Preserve an invalid-row diagnostic at the original index. |

Recovery is deliberately stricter at the root and local beneath a valid views
array. This follows hass-frontend's open config model and local error-element
behavior without copying its JavaScript/Lit architecture.

## Identity and owner reconciliation

### Resolved identity

A resolved source path is a typed sequence, not a presentation index string.
Examples are `views[0]`, `views[0].cards[2]`,
`views[0].cards[2].cards[1]`, and `views[0].cards[4].entities[3]`.
Container labels prevent unrelated arrays from sharing an occurrence.

The semantic component is a deterministic canonical serialization of the
node's raw `JSONValue`: object keys sorted, JSON types marked, arrays ordered,
and strings escaped deterministically. Equality compares this exact canonical
value, not only a digest. This yields the following rules:

| Change | Identity/owner result |
|---|---|
| Decode identical bytes twice | All view/card/row identities equal; existing owners reusable when effective request also matches. |
| Change an unknown raw key at the same path | Identity changes; old owner cannot alias the replacement. |
| Change type/title/entity/entity order/nested content | Identity changes. |
| Insert/remove before a sibling | Shifted raw paths change and affected owners re-key; unaffected earlier paths remain. |
| Reorder distinct siblings | Changed paths re-key; no timestamp/hash ancestry inference. |
| Two identical siblings | Canonical values match but paths differ, so IDs do not collide. |
| Swap two byte-identical siblings | Result is semantically indistinguishable; no artificial UUID claims which duplicate moved. |
| Hide one source card/row in presentation | Other source paths/IDs do not renumber. |

### Atomic config application

The implementation must provide one dashboard-owner reconciliation boundary:

1. Decode and resolve a complete candidate tree without mutating the published
   source tree.
2. Transform it to presentation nodes and compute desired history/render
   owners.
3. Compare exact resolved identity plus effective request contract.
4. Increment the reconciliation epoch; detach obsolete desired keys,
   generations, startups, and subscription/delivery ownership so callbacks are
   suppressed before any await, while leaving the published dashboard's
   accepted feeds, histories, statuses, observers, mounts, and render scope
   intact.
5. Complete every captured startup/subscription cancellation before any
   replacement owner may overlap or start.
6. After captured ownership cancellation completes, recheck latest-wins
   identity immediately before any destructive visual or presentation action;
   superseded ownership-only cleanup may finish its captured cancellations.
7. If superseded, exit after ownership-only cleanup; preserve accepted visual
   stores and mounted lifecycles for the still-published dashboard so a later
   same-identity owner remains reconnectable.
8. Only a candidate that is still final may remove obsolete visual stores and
   invalidate obsolete mounts/coordinator work, immediately before publish.
9. Publish/install that final candidate and start only its still-desired
   owners.

An identical refresh must not churn. A replacement at the same raw path must
not retain a feed merely because its entity list/range happens to match. Tests
must gate subscription acknowledgements, projection, and render completion to
prove cancel-before-install and late-result rejection.

## Typed native surface

The source models retain raw values and expose at least these typed fields.
Accessors should read from the preserved raw tree where practical so typed and
raw state cannot diverge.

### Top-level and view

- top level: `views` plus every unknown key;
- view: `title`, `path`, `icon`, `show_icon_and_title`, `visible`, `subview`,
  `back_path`, `panel`, `type`, `theme`, `background`, `cards`, `sections`,
  `header`, and `footer`;
- `visible`, background, sections, header, and footer may remain raw typed
  values when their complete renderer schema is outside Module 04.

### Common/card/container

- common: `type`, `title`, `entity`, `entities`, `cards`, `content`,
  `grid_options`, `visibility`, `disabled`, and unknown keys;
- vertical/horizontal stack: ordered `cards`;
- grid: ordered `cards`, `columns`, and `square`;
- conditional: raw `card` and `conditions`, preserved for future rendering;
- action objects remain raw at every supported card/row location.

### Entities and rows

- entities card: `show_header_toggle`, `icon`, `state_color`, `header`, and
  `footer`;
- rows: string/object shape plus `type`, `entity`, `name`, `icon`,
  `secondary_info`, `state_color`, `show_name`, `show_icon`, `tap_action`,
  `hold_action`, and `double_tap_action`;
- unsupported divider/section/custom/conditional rows remain present even when
  NativeHA cannot render their full semantics yet.

### History, weather, and markdown

- history: `hours_to_show`, `show_names`, `logarithmic_scale`, `min_y_axis`,
  `max_y_axis`, `fit_y_data`, `split_device_classes`, `expand_legend`; history
  entity objects preserve `entity`, `name`, `color`, and unknown keys;
- weather: `name`, `show_current`, `show_forecast`, `forecast_type`,
  `forecast_slots`, `secondary_info_attribute`, and `round_temperature`;
- markdown: `content`, `text_only`, `card_size`, `entity_ids`, `entity_id`,
  `show_empty`, and action fields.

## Reference anchors

All reference anchors are pinned to hass-frontend
`dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`. Exact SHA-256 values and the
resolved dependency closure are stored in the generated graph.

| Behavior | Complete source anchors | SHA-256 |
|---|---|---|
| Open card/view/root config | `src/data/lovelace/config/card.ts`, `view.ts`, `types.ts` | `ae51b8e1…`, `97b0ae3a…`, `49abacb3…` |
| Supported card and row shapes | `src/panels/lovelace/cards/types.ts`, `entity-rows/types.ts`, `common/process-config-entities.ts` | `673793f3…`, `4a6479d6…`, pinned in graph |
| Local element/card/row recovery | `create-element/create-element-base.ts`, `create-card-element.ts`, `create-row-element.ts`, `cards/hui-card.ts` | `9b4f30ba…`, `4a9cf4b8…`, `9029d7b8…`, `13e2df04…` |
| View and stack runtime traversal | `views/hui-view.ts`, `views/hui-masonry-view.ts`, `cards/hui-stack-card.ts`, `hui-root.ts` | `7050ef76…`, `28b681c4…`, `09f9c24a…`, `b0d88e01…` |
| Current supported runtime defaults | `hui-entities-card.ts`, `hui-history-graph-card.ts`, `hui-weather-forecast-card.ts`, `hui-markdown-card.ts` | `ae43e83a…`, `f20a8c88…`, `a176b520…`, `f50a78a5…` |

The complete seeded files were read, including their local creation/error and
container runtime paths. The graph uses depth one as a safety boundary but
explicitly reseeds every behaviorally relevant runtime crossing found by the
audit. Its 206 nodes / 2,724 edges have zero unresolved edges and no truncation.
The 1,635 max-depth boundaries and 832 type-only boundaries are candidate
discovery stops, not unreviewed behavior claims; no behaviorally relevant npm
runtime crossing was found. If implementation introduces a new renderer or
dependency, update/research the manifest rather than assuming this closure.

## Native anchors and mapping

Native anchors are pinned to
`a06d55fff9a7b76913015564276d7c218f834513`; exact SHA-256 values are in the
generated graph.

| Current anchor | Current role and Module 04 handoff |
|---|---|
| `Sources/NativeHACore/JSONValue.swift` (`feae6ef6…`) | Reuse for recursive raw semantic values and canonical serialization; do not add an incompatible raw JSON enum. |
| `Sources/NativeHACore/LovelaceModels.swift` | Raw-preserving source values, local diagnostics, complete typed accessors, exact canonical serialization inputs, typed source paths, resolved identities, and immutable resolved trees. The former narrow structs and UUID identities were removed from `Models.swift`. |
| `Sources/NativeHACore/HomeAssistantWebSocketClient.swift` (`d0b5cc37…`) | Keep typed `lovelace/config` command on the verified Module 02 connection. |
| `Sources/NativeHAMac/AppConfig.swift` (`218b86ab…`) | Preserve current graph, layout, hidden/injected entity, renderer, and transport policies. No new configuration surface is required unless implementation changes policy. |
| `Sources/NativeHAMac/LovelacePresentation.swift` | Separate immutable presentation wrappers carry resolved identity, effective rows, visibility, default-view flattening, and synthetic-row policy without rebuilding decoded source. |
| `Sources/NativeHAMac/DashboardViewModel.swift` (`9f231c34…`) | Replace `flatten`/`cleanCards` reconstruction with resolved source and presentation nodes; add atomic config/owner reconciliation while preserving Module 01 desired-key/epoch behavior. |
| `Sources/NativeHAMac/DashboardView.swift` (`cccdbb34…`) | Iterate presentation nodes by resolved identity and apply default-view-only layout policy. Do not implement Module 12 navigation. |
| `Sources/NativeHAMac/CardViews.swift` (`ae9b4078…`) | Render resolved nodes/rows, local invalid placeholders, typed fields, and stable IDs; pass resolved owner identity to graph requests/cache. |
| `Sources/NativeHAMac/GraphRenderScheduling.swift` (`9812a7a1…`) | Preserve feed/coordinator generation semantics and reject old completion on owner replacement. Do not weaken cache correctness. |

## Required implementation order

1. Run the Module 04 checker. If green, use this packet rather than reopening
   broad frontend research.
2. Add raw-preserving source models and deterministic canonical serialization;
   keep the source tree immutable and macOS 12/Swift-compatible.
3. Add resolved view/card/row path identities and local invalid/unsupported
   nodes; remove UUID/process-random model identity.
4. Add typed accessors and representative/unknown/malformed fixtures with unit
   tests before changing presentation.
5. Introduce a separate resolved presentation layer for default-view
   flattening, hidden/injected rows, and column placement. Delete destructive
   reconstruction only after integration tests prove raw/source identity.
6. Route `DashboardView`, `CardRenderer`, rows, history keys, feeds, SwiftUI
   identity, coordinator, and cache scopes through resolved nodes.
7. Add atomic config application and gated lifecycle tests for identical,
   replacement, insertion, removal, and reorder refreshes.
8. Add performance, GUI, live, release, and regression evidence. Do not broaden
   into later modules.

Likely implementation files are `Models.swift` or one new core
`LovelaceModels.swift`, `DashboardViewModel.swift`, `DashboardView.swift`,
`CardViews.swift`, focused tests/fixtures, and only minimal supporting test
hooks. Preserve macOS 12 and current Swift package compatibility.

## Required tests and evidence

### Deterministic fixtures and unit tests

Create checked-in Lovelace fixtures with fixed synthetic values:

- `representative-dashboard.json`: `default_view`, `home_3h`, and `home_12h`;
  string/object rows; history entity name/color; weather explicit false;
  markdown; vertical/horizontal/grid nesting; conditional preservation;
- `unknown-fields.json`: unknown top/view/card/action/row/nested keys containing
  all JSON types, including explicit null and false;
- `malformed-configurations.json` or bounded case fixtures: invalid root/views,
  malformed view/card/row siblings, missing/unknown type, wrong typed fields,
  empty arrays, unsupported rows, truncated JSON, and bounded deep nesting.

Tests must prove:

- exact raw structural equality after decode and after presentation;
- every typed field and snake-case mapping in this packet;
- explicit false versus absent, and raw hours versus effective selected range;
- identical decode stable identity across fresh decoders/process-independent
  canonical construction;
- same-path unknown/type/entity/nesting changes re-key;
- insert/remove/reorder/identical-duplicate identity matrix;
- hidden/default flattening does not renumber source identities;
- supported siblings and ordered local placeholders survive malformed input;
- source models remain unchanged after transformation.

### Integration and lifecycle

Pass fixtures through decode -> resolve -> presentation -> `CardRenderer` and
assert supported card/row counts/order, placeholder paths, raw preservation,
default-view-only flattening, maintenance-view retention, and effective graph
requests.

Use deterministic gates to prove:

- identical refresh keeps the same wire subscription count, key, feed object
  and generation, SwiftUI chart/coordinator lifetime, and cache scope;
- replacement at the same path invalidates old state before install even when
  entity list/range match;
- insertion/removal/reorder cancel/re-key affected owners only;
- late acknowledgement, projection, feed delivery, and render completion from
  an old config cannot publish;
- weak old feeds/nodes/coordinators release and final subscription/delivery/
  observer/queued-work counts are exact;
- Module 01 range change, detail dismissal, publication ordering, and Module 02
  connection/large-frame tests remain green.

### Performance

Use a deterministic 10-view x 50-card fixture with nested stacks and mixed row
shapes. Generate outside measured blocks. Separately measure cold JSON/raw
decode, warm resolve/presentation, and repeated identical/replacement refresh
using clock/CPU/memory metrics available on the supported toolchain. Consume a
deterministic traversal count/canonical checksum. Repeated discard/replacement
must not retain unbounded decoded nodes, feeds, coordinators, subscriptions, or
random identity entries. Record XCTest baselines rather than brittle universal
millisecond limits.

### GUI and manual evidence

Use the existing offscreen AppKit capture workflow at scale 2, fixed dark
appearance, locale/timezone, sizes, and bounded settlement. Produce and inspect:

- `lovelace-unknown-card.png` at 496 x 150 points;
- `lovelace-unsupported-row.png` at 496 x 210 points;
- `lovelace-nested-496.png` at 496 x 640 points;
- `lovelace-nested-360.png` at 360 x 640 points; and
- two identical-refresh renders plus semantic lifetime assertions.

Assert PNG signature, exact doubled pixels, nonblank regions, expected labels,
and absence of unresolved loading. Manually compare matching reference/live
state. Do not approve a new baseline mechanically; screenshots do not prove raw
preservation, identity, lifecycle, accessibility, or performance.

### Release, full suite, and live smoke

Before `complete`:

- run the Module 04 checker and resolver;
- run new unit/integration/lifecycle/performance/GUI tests and all applicable
  Module 01/02 history/graph/WebSocket tests;
- run the full suite and classify introduced versus pre-existing failures;
- run a release build;
- run authorized read-only live Lovelace decode/render smoke; and
- verify the current Core Graphics dashboard and histories still function.

Research-time live smoke on 2026-08-23 used only read-only config commands. It
found three raw views (`default_view`, `home_3h`, `home_12h`), 31 cards across
entities/history/weather/markdown/vertical-stack, 66 rows, maximum nesting
depth one, and no malformed node. Observed unmodeled live keys include
`refresh_interval` and `logarithmic_scale`; both must survive raw decode. Do not
emit or mutate Home Assistant state during implementation verification.

## Implementation evidence

One fresh sole Swift/test writer implemented C04-01 through C04-10 without a
commit. The bounded production diff is:

- `JSONValue.swift`: exact tagged canonical semantic serialization; no digest
  or ordering comparison;
- new `LovelaceModels.swift`: raw root/view/card/row preservation, strict root
  failure, local invalid nodes, complete typed surface, typed raw paths, and
  exact path-plus-canonical resolved identity;
- new `LovelacePresentation.swift`: immutable source/resolved/presentation
  layers, default-view-only flattening and three-column inputs, raw maintenance
  views, and deterministic synthetic rows;
- `DashboardViewModel.swift`, `CardViews.swift`, and the `CardColumnRule`
  adapter: exact identity flows through history keys, feeds, SwiftUI IDs,
  coordinator/cache scopes, and atomic config-epoch reconciliation; the old
  destructive `cleanCards`/`flatten` reconstruction and model UUID fallback are
  gone; and
- focused deterministic fixtures/tests plus live-shape and GUI evidence.

Contract evidence before independent verification:

| Contracts | Implementation evidence |
|---|---|
| C04-01..03 | `LovelaceModelTests` passes six cases covering structural raw equality, all JSON types, representative typed fields, string/object rows, unknown keys, strict root errors, and ordered local malformed siblings. |
| C04-04..06 | Exact canonical identity tests cover identical decode, same-path semantic replacement, insertion/removal/reorder, duplicates, nested raw paths, source immutability, hidden/injected row identity, default-only flattening, and raw maintenance views. Source models no longer conform to `Identifiable`; only resolved/presentation nodes own traversal IDs. |
| C04-07..08 | Gated integration proves identical config retains one wire command, exact history key, feed object/generation, and cache scope. Replacement releases the old feed, keeps one owner, rejects its late event, and accepts the new event. Insert/remove/reorder retains unaffected A and re-keys only affected raw paths with exact owner counts. A gated coordinator/cache test records two full preparations and one exact same-owner hit, then suppresses the old render completion after replacement reset. |
| C04-09 | Tests distinguish raw 12-hour config from the effective one-hour AppConfig selection and explicit `show_forecast: false` from absence. Core Graphics, tooltip, transport, range selector, logging, and Module 09 cache-lineage behavior were not changed. |
| C04-10 | Deterministic nested 500-card decode/resolve/presentation tests pass with vertical stacks, mixed supported cards, and mixed string/object/unsupported rows. Twenty repeated semantic replacements retain exactly the current 500 source/resolved nodes and discard to zero. Cold decode measured about 0.049 seconds and resolve/presentation about 0.011 seconds in the focused three-iteration run, with clock/CPU/memory metrics recorded by XCTest and no brittle threshold. |

The first independent verifier/auditor returned bounded NO-GO findings. The
same sole writer resolved them before re-verification: supported native card
types now validate their required semantic fields and render local invalid
placeholders; all typed view/common/action/row/weather/markdown surfaces are
fixture-asserted; markdown `entity_ids` accepts the HA string and string-array
forms; signed zero is normalized in canonical identity; default-dashboard
filtering/layout applies only to an actual `default_view`; and dashboard config
application now invalidates every weakly registered mounted bitmap-chart lease
for obsolete owners before publishing the replacement tree.

The mount registry is one-to-many per history-card owner, so different unit
groups cannot overwrite each other. A gated two-chart test records exactly two
live mounts and two feed observers, retains both on identical config, then
records zero mounts, observers, and queued work before replacement install;
the gated old completion cannot publish and both weak lifecycle references are
released. A separate hosted SwiftUI/`BitmapLineChart` test repeats the actual
config-application seam with two mounted charts and reaches the same zero
counts.

A subsequent concurrency audit found a distinct-config reentrancy gap while
subscription cancellation or startup acknowledgement was awaited. Config
applications are coalesced by exact pending raw value, and every history
startup, including startup launched by an external range/bootstrap load, is
tracked. Gated
tests prove: a middle candidate cannot install/start while old cancellation is
held; a config cannot pass an external held subscribe then held unsubscribe;
concurrent identical configs issue one command and reuse one owner; and a
superseded two-card startup retains the unchanged same-key owner while
cancelling only the replaced owner before the latest starts.

A final exact-revert audit exercised visible A -> held-cancellation B -> A,
including a coalesced B caller. Obsolete subscription/generation ownership is
retired before the awaited cancellation, while its accepted visual state and
mounted chart stay available until the cancellation resolves. The restored A
candidate detects the ownership gap, creates one fresh subscription/feed
generation, and reconnects the retained chart lifecycle. The coalesced caller
waits through the stable latest tail rather than returning at its superseded
middle candidate. The gated test finishes with exactly one subscription and
one wire owner; the old feed has zero observers and the new feed has one.

The final lifecycle audits found both orderings of the remaining gap: an
external range/load/refresh could enter while config reconciliation was
suspended, and a later config could bypass an external operation suspended in
unsubscribe/startup. Config apply, external card-history load/range
reconciliation, and refresh now occupy one atomic MainActor owner-operation
tail. External operations capture their config sequence when enqueued and
revalidate after awaited boundaries; sequence-qualified loading performed by
the config operation itself executes inline to avoid self-deadlock. Queued
candidate ownership keys derive from the candidate using the selected range at
execution, and rapid queued range work likewise uses the latest selected range
rather than installing an intermediate owner. A startup entered before a
config may still be adopted only when its exact key remains current.

Deterministic tests cover both cancellation orderings. Config-first keeps
Initial data, status, feed observer, and mount intact while its unsubscribe is
held; a queued three-hour range load issues no second Initial command, then
ends with only Latest at three hours and exactly one subscription, wire owner,
and delivery owner, with late Initial delivery suppressed. Range-first removes
Initial ownership and holds its unsubscribe before Latest is queued; Latest
remains unpublished and issues no history command until release, then becomes
the sole owner at the selected range. Existing gated tests also cover
refresh-first -> config and held-startup -> config on the same operation tail.

A third C04-07/C04-08 lifecycle audit found a stale-cleanup hazard inside that
tail: a published candidate superseded during startup could begin cleanup using
an intermediate candidate's excluded-owner snapshot, then permanently
invalidate a still-mounted same-identity chart while cancellation was held and
a later exact owner returned. Superseded cleanup now retires only generation,
startup, subscription, and delivery ownership required to prevent overlap. It
does not invalidate mounts or remove accepted history/status/feed stores; the
final queued candidate rederives desired ownership after the await and alone
owns those destructive presentation decisions.

The gated B -> C -> D test publishes B with one accepted mounted owner and one
held startup, queues excluding C, then holds the stale cleanup unsubscribe for
B's accepted owner while D queues the same stable card identity. C never
publishes. B's accepted data, status, feed observer, and mounted lifecycle
remain intact while held. D restarts that owner exactly once; the lifecycle is
still reconnectable, reconnect releases the old feed observer, final
subscription/wire/delivery ownership is exactly one, and a late callback from
the retired subscription cannot alter accepted history.

History semantic validation now requires at least one usable non-diagnostic,
nonempty entity. Invalid-only history renders a local invalid card and starts
no request; mixed valid/malformed history plots the valid sibling and renders
the malformed resolved-path row placeholder in source order. Entities cards
use the same usability predicate for rendering and toggle ownership.

Validation performed by the implementation writer:

- Module 04 context checker: green after manifest/graph refresh, 206 nodes / 2,724
  edges, zero unresolved, no truncation, fingerprint
  `0295bb6ce08fba5412d8d81e01816f668c5ad9860317781e2f0c7dd706f9fa8e`;
- resolver self-test: pass, 31 nodes / 61 edges, fingerprint
  `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`;
- post-repair Module 04 focused suites: 42/42, comprising model 6/6,
  presentation/performance/lifetime 9/9, history integration 17/17, tooltip
  formatting 7/7, GUI 2/2, and mounted owner graph 1/1;
- the implementation writer's final affected regression command passed 27/27:
  all 17 history integration tests, all seven tooltip tests, both legacy graph
  label/oracle GUI tests, and the Module 04 GUI artifact test;
- the independent pre-final-repair full suite ran 164 tests with three
  authorized live benchmark skips and four failures. Two were introduced axis
  label/oracle regressions and are now fixed: the production default again uses
  the exact legacy `h:mm a` formatter, while only the deterministic Module 04
  artifact model injects fixed UTC/24-hour metadata; both exact failed tests
  pass in the final affected command. The other two are classified
  pre-existing: the fixed January/current-August warm-render viewport fixture,
  and the known flaky hover-overlay byte-exact comparison that passed on
  immediate reruns. They remain visible and require the fresh post-repair
  verifier's full-suite gate;
- release build: pass at `.build/release/NativeHAMac`;
- read-only live smoke: pass, three views, 22 top-level / 31 recursive cards,
  66 rows with exact raw-to-typed counts, no malformed view, 102,426 points for
  the 12-hour CO2/VOC replay, 57,077 points for 24 hours, and final ownership
  zero; no state-changing command was sent; and
- GUI: exact 2x PNG dimensions/signatures/nonblank checks pass for unknown card,
  unsupported row, 496/360 nested widths, and byte-identical refresh renders.
  The nested artifacts now originate from JSON decode through resolve,
  non-default presentation, and renderer, with settled entities, history,
  weather, markdown, horizontal-stack fallback, and grid fallback content.
  Required nested images are exactly 496x640 and 360x640 points
  (992x1280 and 720x1280 pixels at 2x), use a fixed timestamp, en_US_POSIX
  24-hour labels, and explicitly injected UTC graph metadata without changing
  the production default axis formatter;
  The writer manually inspected all distinct images; the unsupported row label
  and exact raw path are visible and valid siblings remain rendered. No visual
  baseline was approved mechanically.

### Final independent verification

A completely fresh verifier returned GO for C04-01 through C04-10 after all
lifecycle-audit findings and packet-language discrepancies were resolved. A
different fresh concurrency/lifecycle/identity/cache auditor independently
returned source GO. Final evidence was:

- 46/46 focused contract tests passed, including all 17 history/config
  lifecycle tests, both unified-tail entry orderings, exact revert/coalescing,
  and the B -> C -> D stale-retirement reconnect gate;
- the full suite ran 168 tests with three authorized live skips and one
  unchanged pre-existing failure,
  `testWarmGraphInteractionRenderCanBeMeasuredWithXCTMetrics`, whose fixed
  January data remains outside the current August viewport; there were zero
  introduced failures;
- the release build passed as an arm64 executable at
  `.build/release/NativeHAMac`, SHA-256
  `9ff284180a46711fa55429209e7398148c03533338ce7644763c4d29c83bf94a`;
- the authorized read-only live smoke passed with three views, 22 top-level / 31
  recursive cards, 66 rows, exact raw-to-typed counts, 102,562 12-hour CO2/VOC
  points, 57,086 24-hour points, and zero final connection/history ownership;
- all six required GUI artifacts were regenerated and manually inspected at
  their exact 2x dimensions; supported content was settled and unclipped,
  local fallback paths remained visible, and the two identical-refresh images
  were byte-identical with SHA-256
  `3c3cbd3b34221e53a5a6661a6dd1bffa417791e0a96992687a9289135f9b5aa3`;
  and
- final static review found no random decoded-model identity, hash/digest or
  timestamp ancestry ordering, destructive source reconstruction, owner
  overlap, stale mounted-lifecycle invalidation, or cache-lineage weakening.

Implementation verdict: **complete / independently verified**.

## Remaining risks and stop rules

- Canonical semantic serialization must be deterministic and exact; a digest
  collision may not reuse a different config.
- Local recovery must expose invalid supported fields rather than silently
  changing behavior.
- Presentation and source paths can be confused during flattening/filtering;
  tests must assert both.
- Atomic config application may expose a same-key lifecycle hole; stop if old
  ownership can overlap replacement installation.
- The 500-card test can accidentally include fixture generation or bitmap work;
  keep phases separate.
- Stop rather than adding Module 03/05/12 or card-detail behavior.
- Stop if visual/manual evidence cannot be inspected, if the daily-use default
  dashboard loses supported cards/rows, or if a proposed repair orders history
  by hashes or timestamps.

The known stale visual request/full-preparation fallback remains a Module 09
issue. Module 04 may change ownership inputs but must retain strict cache
correctness and may not compare `contentRevision`, `firstTimestamp`, or
`lastTimestamp` to infer ancestry.

## Research validation and handoff

- Graph: green, 206 nodes / 2,724 edges, three cycles, zero unresolved edges,
  no truncation, implementation fingerprint
  `0295bb6ce08fba5412d8d81e01816f668c5ad9860317781e2f0c7dd706f9fa8e`.
- Resolver self-test: pass, 31 nodes / 61 edges, fingerprint
  `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`.
- A fresh researcher reviewed the complete relevant current Swift and
  hass-frontend config/model/runtime sources and performed the read-only live
  shape smoke.
- A separate read-only identity/lifecycle/destructive-transformation auditor
  returned GO with no material product question unresolved and supplied the
  exact C04-04 through C04-08 rules above.

Verdict: **complete / independently verified**. Preserve these contracts in
Module 03 and later work; do not reopen Module 04 or fold the separate Module
09 stale-viewport repair into this handoff.
