---
module: "04"
title: Lossless Lovelace decode and stable resolved identity
plan: ../../rescue-plan/module-04-lovelace-model-decode.md
status: research-ready
contract_revision: 1
depends_on: ["01", "02"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: a06d55fff9a7b76913015564276d7c218f834513
graph_file: ../generated/module-04.dependencies.json
graph_fingerprint: 54340880dda33a339e54ea41222d2e91fff9d8d5c8791c1c4a05dfcfe3bb6379
last_researched: 2026-08-23
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
| C04-07 | Apply identical or changed config to a running dashboard | Reuse a history/feed/chart owner only when resolved card identity and the effective request contract are exactly equal. Identical refresh keeps the same subscription key, feed instance/generation, SwiftUI chart lifetime, coordinator, and cache scope without wire churn. | For replacement/removal/reorder, compute the new tree first; synchronously invalidate old desired keys, generations, feeds, histories, statuses, and config epoch; cancel old subscription/coordinator work; epoch-check; then publish/install replacements. Old and replacement ownership cannot overlap. |
| C04-08 | A history or render completion races config replacement | The resolved owner identity flows through `HistoryRequest`, subscription keys, `GraphHistoryRevisionFeed`, SwiftUI IDs, coordinator generation, and prepared-cache scope. Late old history projection, feed delivery, or render completion cannot mutate the new/visible owner. | Preserve Module 01 feed-before-`@Published`, mounted FIFO, pre-mount latest-only replay, reset flags, off-main serial preparation, and exact immediate-predecessor cache lineage. Never infer freshness from hashes or first/last timestamps. |
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
4. Increment a config-reconciliation epoch and synchronously remove every
   obsolete/replaced desired key, history generation, feed, history/status
   value, observer binding, and coordinator/cache scope from current ownership.
5. Cancel captured subscriptions and queued/in-flight render work.
6. Recheck epoch and identity after every await.
7. Publish/install the candidate tree and start only still-desired owners.

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
| `Sources/NativeHACore/Models.swift` (`e5f00bf9…`) | Replace UUID model/row fallback and narrow all-or-nothing Lovelace structs with raw-preserving source values and typed accessors. |
| `Sources/NativeHACore/HomeAssistantWebSocketClient.swift` (`d0b5cc37…`) | Keep typed `lovelace/config` command on the verified Module 02 connection. |
| `Sources/NativeHAMac/AppConfig.swift` (`218b86ab…`) | Preserve current graph, layout, hidden/injected entity, renderer, and transport policies. No new configuration surface is required unless implementation changes policy. |
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
  no truncation, fingerprint
  `54340880dda33a339e54ea41222d2e91fff9d8d5c8791c1c4a05dfcfe3bb6379`.
- Resolver self-test: pass, 31 nodes / 61 edges, fingerprint
  `7148dbfcc04d8eae2868612b04e880e4bbed3e2b41247561291e775edb345071`.
- A fresh researcher reviewed the complete relevant current Swift and
  hass-frontend config/model/runtime sources and performed the read-only live
  shape smoke.
- A separate read-only identity/lifecycle/destructive-transformation auditor
  returned GO with no material product question unresolved and supplied the
  exact C04-04 through C04-08 rules above.

Verdict: **research-ready / GO for one fresh Module 04 implementation writer**.
The writer must run the checker first, implement C04-01 through C04-10 in the
recorded order, report exact files/tests/artifacts, and not commit. A different
fresh verifier and separate lifecycle audit must review the completed change.
