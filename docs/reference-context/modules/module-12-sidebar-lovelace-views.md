---
schema: nativeha-evidence/v1
module: "12"
title: Sidebar and Lovelace view navigation
plan: ../../rescue-plan/module-12-sidebar-lovelace-views.md
status: research-ready
contract_revision: 1
depends_on: ["01", "02", "04"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: dda63c1b69feed1de38e2f0657504bc9cd8c883c
graph_file: ../generated/module-12.dependencies.json
graph_fingerprint: 2029b45105e24649341ec59dc5f68a571a643059b6efd9c01a3b00c1b2eb0475
last_researched: 2026-08-25
---

# Module 12 evidence packet

## Gate and scope delta

This packet is the implementation authority for Module 12. Module 04 already
provides lossless views/cards and exact path-plus-canonical identities. Modules
01 and 02 already provide verified history ownership and a single multiplexed
WebSocket connection. Module 12 consumes those contracts; it does not redesign
them.

The user has intentionally skipped Module 03. NativeHA targets one fixed
personal Home Assistant deployment, keeps the current token/bootstrap path,
and has no profile switching or settings UI. Consequently Module 12 has no
profile namespace or transition state, and Module 05 must follow Module 12
rather than being treated as its prerequisite.

Relative to the rescue plan, research resolves these points:

- the hardcoded app/profile/sidebar rows are removed rather than preserved as
  nonfunctional destinations;
- `home_3h` and `home_12h` are excluded by exact path from primary navigation,
  while their source config and explicit route lookup remain intact;
- current-user visibility requires one optional typed `auth/current_user`
  bootstrap command; failure hides only user-list-gated primary items and does
  not fail dashboard bootstrap;
- selection persistence is a versioned fixed-deployment preference, not a
  profile-scoped preference;
- view selection, config reconciliation, refresh, history load, and graph-range
  changes share the existing serialized dashboard-owner operation tail; and
- global state and connection-status ownership survive a view switch. Only
  view/card/detail work is retired.

Still out of scope are full browser URL routing, Lovelace editing, a settings or
profile UI, server/token migration, full MDI rendering, Modules 05-11, a Metal
default, and the separate Module 09 stale-viewport fallback.

## Observable behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Required evidence |
|---|---|---|---|---|
| C12-01 | A valid resolved dashboard arrives | Produce primary navigation in raw view order. Exclude exact paths `home_3h` and `home_12h`, every `subview`, `visible: false`, and user-list views that do not contain the current user ID. Preserve every excluded view and its raw config for exact direct lookup. | Absence/`true` is visible. A user-list view is ineligible when user metadata is unavailable. Visibility is presentation, not authorization: an exact internal route may still resolve preserved hidden/subview source. Invalid view nodes never become navigation items. No title, icon, visibility, or exclusion decision mutates resolved identity. | Pure filtering matrix, live-shape fixture, raw preservation assertion. |
| C12-02 | Startup, restore, sidebar selection, or direct route | Runtime selection is the exact `LovelaceResolvedIdentity`. Sidebar actions carry that identity, so duplicate paths cannot select the wrong sibling. Path-based direct routing follows source order and selects the first exact path match, matching hass-frontend. | Startup order is: eligible unambiguous persisted primary locator; unique eligible `default_view`; first eligible raw-order view; controlled empty selection. A unique nonempty path is persisted; only a pathless view may persist its source index. Duplicate paths remain selectable by exact runtime identity but are not persisted. No UUID, hash, `contentRevision`, endpoint time, or semantic similarity selects ancestry/freshness. | Missing/duplicate/pathless/default/removed/hidden restore tests and exact-identity action tests. |
| C12-03 | A final primary selection commits, or a subview/back action occurs | Persist an unambiguous last committed eligible primary selection under versioned key `nativeha.navigation.selected-primary-view.v1`. A subview or other direct non-primary view is transient and does not overwrite that preference. Back resolves a valid internal `back_path`, otherwise returns to the last valid in-memory primary, otherwise applies startup fallback. | Inject `UserDefaults`/preference storage for tests. Selecting a duplicate-path primary clears the unsafe stored locator while retaining its exact in-memory identity. Missing legacy data requires no migration. Malformed, stale, ambiguous, excluded, or newly invisible values are removed; fallback is persisted only after final commit. Persistence failure is nonfatal and diagnostic. No profile/server key is introduced. | Fresh-install, v1 round-trip, malformed/stale/ambiguous fallback, subview/back, and write-after-final-commit tests. |
| C12-04 | Sidebar/top bar render the selected view | Replace hardcoded Overview/devices/history/settings/Joy rows with eligible Lovelace items. Show the active view title and optional supported icon; title fallback is `title`, then title-cased path, then source index. Keep one approved 1h/3h/6h/12h graph-range selector and Core Graphics. | `show_icon_and_title` semantics and icon-only/title-only inputs remain testable. Native may map supported MDI names to SF Symbols and uses one deterministic generic fallback for unsupported MDI names; raw icon is preserved. No settings/profile control or personal label appears. | Semantic view tests plus selected/unselected/focus/long-title/loading/empty wide/narrow GUI artifacts and manual keyboard/accessibility QA. |
| C12-05 | Selected view content renders or window size changes | Render cards from the selected presentation view. Apply the approved three-column/flattening exception only to actual `default_view`; render unrelated masonry views with their preserved card order and a bounded native container, and `panel` as one full-width first-card surface. Empty views render a controlled empty state. | Resize/layout recalculation does not change view/card identity, selection, subscription keys, or owners. Module 12 need not implement every sections/layout strategy; unsupported preserved content remains locally diagnostic. | Active-card/order/layout tests, 1792x1000 and 900x700 captures, repeated resize owner-count test. |
| C12-06 | Same-view no-op, config refresh, range change, or A -> B selection | Derive desired active-card owners from the final selected resolved view and effective range. Retain only the exact intersection of resolved card identity and full effective request. Same selection/no-op retains all; a distinct view normally shares none because Module 04 source paths include the view path. Range changes intentionally re-key history owners. | Every operation runs on the existing MainActor `dashboardOwnerOperationTail`. Synchronously advance navigation/config generation and desired ownership before suspension; detach obsolete startup, acknowledgement, delivery, and subscription ownership; await captured cancellations; recheck generation after every suspension; only the still-final candidate invalidates obsolete mounts/coordinators, removes obsolete visual stores, publishes selection, persists it, and starts missing owners. Never overlap old and replacement wire owners. | Deterministic held-startup/held-cancel tests for same view, range, refresh, A-B-C, A-B-A, exact owner intersection and cancel-before-install. |
| C12-07 | Old-view acknowledgement, history, status, feed, or render result arrives | No late view-owned result can mutate the new view. Close detail UI on navigation and retire its history generation/subscription before proceeding. Hidden/removed cards settle at zero history subscriptions, feed observers, mounted lifecycles, coordinator queued/in-flight work, and animations. | Each callback validates config generation, navigation generation, exact owner key, startup generation, and current desired membership as applicable. Feed is still published before `@Published` history. Mount invalidation is synchronous immediately before final publish; coordinator reset rejects old completion. Prepared cache entries may remain inert for normal bounded eviction but are scoped by exact card identity and cannot revive owners. | Gated late ack/history/status/feed/render/detail tests, weak-owner release, exact registry/queue counts, and hidden-view bounded-settlement assertions. |
| C12-08 | A -> B -> A occurs while B cancellation/startup is held | B never publishes after A becomes latest. The restored A installs exactly one fresh subscription/feed generation if its prior ownership was retired and reconnects retained mounted lifecycle without overlap. | Accepted visual state may remain while cancellation is awaited, as in Module 04 exact-revert behavior. Superseded cleanup is ownership-only. It cannot clear the currently published A visual/mount state or let the old A generation resume delivery. | Coalesced-caller and exact-revert tests proving one final wire owner, old observer zero, new observer one, and no intermediate presentation. |
| C12-09 | Global state or WebSocket status changes during navigation | Continue the one fixed-server global state subscription and global connection status across view switches. Current entity state remains available to newly mounted cards. Only view-owned history/status/feed/render work and detail ownership retire. | Do not reconnect the fixed server, refetch credentials, or treat global state/status callbacks as belonging to the old view. A config/bootstrap generation still rejects results from an obsolete whole-dashboard load. | Integration test with continuous global state/status plus switched view-owned histories; Module 02 connection-count tests remain green. |
| C12-10 | Current-user metadata is fetched | Issue typed `auth/current_user` through the existing Module 02 command path and retain only the decoded user ID needed by C12-01. Fetch it concurrently with bootstrap inputs and catch its failure independently. | Do not persist or log the response, token, credentials, MFA data, or user name. A timeout/error supplies `nil` user ID, a concise credential-free diagnostic, hides user-list-gated primary views, and continues bootstrap. Reconnect/bootstrap gets a fresh command generation; a late old response cannot revise current navigation. | Exact command/typed decode tests, failure/nonfatal bootstrap test, late bootstrap response test, and read-only live smoke. |
| C12-11 | Config refresh changes active or eligible views | Re-resolve the selected locator against the new candidate before owner diffing. Retain a changed view only by an unambiguous locator; its new exact resolved identity controls all card reconciliation. If no longer eligible, apply C12-02 fallback. | Raw index is only a locator for a pathless view, not proof of ancestry. A duplicate-path selection has exact runtime identity but no refresh/persistence ancestry claim. Card identity and owner reuse remain exact Module 04 equality. Config-refresh and selection requests are latest-wins on the same tail. | Removed/hidden/reordered/duplicate-path refresh matrix and raced refresh/selection tests. |
| C12-12 | Release candidate with large/live config | A deterministic 500-card fixture and repeated warmed selection/range/resize cycles remain bounded. Live Home appears once, maintenance duplicates do not appear, and selector ranges work without raw mutation. | Core Graphics, tooltip, WebSocket, history, graph-feed, render-coordinator, logging, and graph-range policies remain unchanged. No HA state-changing call is permitted. Any identity alias, old result publication, owner leak, migration ambiguity, introduced regression, or unresolved product choice is NO-GO. | Unit/integration/lifecycle/GUI/performance/full-suite/release/migration/read-only-live evidence listed below. |

Opaque UUID generations remain permitted for runtime lifetime isolation. They
are never persisted selection, model identity, owner ancestry, or freshness.

## Navigation model and state machines

### Pure model

Add a pure `LovelaceViewNavigation` layer with these distinct concepts:

- `LovelaceViewLocator`: `.path(String)` only for a unique nonempty source
  path, or `.sourceIndex(Int)` only when the source path is absent;
- `LovelaceNavigationItem`: exact resolved identity, locator, display title,
  raw icon, source index, and selected state;
- `selectedViewIdentity`: exact Module 04 resolved identity for the installed
  snapshot; and
- `lastPrimaryIdentity`: exact in-memory back destination, plus
  `lastPrimaryLocator`: the only persisted selection when unambiguous.

Locator equality makes a route findable; resolved identity decides SwiftUI and
owner lifetime. Never make those one type. Sidebar selection calls by exact
identity. The path API exists for internal links/back behavior and resolves the
first source-order exact match. Duplicate paths are retained and separately
selectable from a sidebar action when otherwise primary-eligible, but they have
no persisted locator; committing one clears an unsafe stored locator and keeps
only its exact in-memory identity.

### Eligibility and startup

For each valid raw-order view:

1. Exclude exact path membership in
   `AppConfig.lovelaceNavigationPolicy.excludedPrimaryPaths`.
2. Exclude `subview == true`.
3. Include absent/`true` visibility.
4. Exclude `false` visibility.
5. For a visibility array, include only if at least one `user` equals the
   optional current user ID; with no ID, exclude it.

This filter affects primary navigation, startup fallback, and persistence
restore. It does not delete raw/resolved views. A direct route may resolve a
preserved subview/hidden view because hass-frontend also routes an explicit
path without applying `_isVisible`; `visible` is not an access-control layer.

Startup waits for Lovelace config and the optional bounded current-user result,
then chooses:

1. a valid unambiguous persisted eligible primary;
2. the single eligible view whose path is exactly `default_view`;
3. the first eligible view in raw order; or
4. `nil`, producing a controlled empty-navigation/empty-dashboard state and no
   view owners.

After final install, persist an unambiguous primary locator. If an explicitly
routed subview/non-primary view is selected, retain the prior valid primary locator.
Back first resolves a supported internal `back_path` to an exact view path,
then that prior primary, then startup fallback. An external/unresolvable
`back_path` gets a diagnostic and fallback because full app/URL routing is out
of scope.

### Serialized view switch

Selection, config application, refresh, history load, and graph-range change
must enqueue on one `dashboardOwnerOperationTail`; a second tail is forbidden.
For final candidate `(config generation, navigation generation, view identity,
range)`:

1. Before an `await`, increment navigation generation, record desired selected
   identity/locator, close detail presentation, retire detail generation, and
   compute exact current/desired history-owner sets.
2. Detach obsolete desired keys, startup tasks, acknowledgement generations,
   subscription delivery generations, and detail ownership synchronously.
   Capture cancellations. Keep accepted visual snapshots and currently mounted
   UI intact while cancellation is suspended.
3. Await every captured startup/subscription/detail cancellation. No new owner
   with the same key may install until its predecessor cancellation completes.
4. Recheck config sequence, navigation sequence, desired selected identity,
   effective range, and desired keys after each suspension. A superseded
   candidate completes only its captured ownership cleanup and exits.
5. For the still-final candidate only, synchronously invalidate mounts and
   coordinator generations for obsolete owners, remove obsolete feeds/history/
   status stores, and publish the selected view immediately afterward.
6. Persist only a final committed eligible primary selection with an
   unambiguous locator; clear an unsafe duplicate-path locator.
7. Start missing desired owners. After every subscription acknowledgement,
   recheck all captured generations and desired membership before installing
   delivery ownership or publishing status/history.

The exact intersection is retained. A same-view no-op retains all current
owners. A config refresh may retain unchanged card owners in the selected view.
A distinct view normally retains none because card source identities contain
their view source path. Semantic duplicate cards in two views are not the same
owner. A range change changes the effective request and therefore replaces
history owners without changing raw card config.

Global `state_changed` and connection-status ownership are dashboard/server
lifetime, not selected-view lifetime. They stay connected. Current and future
view-scoped owners (history now; weather/template only after their modules)
must use the same active-card ownership seam, but Module 12 must not implement
Modules 07 or 08 speculatively.

## Persistence and migration policy

`LovelaceNavigationPolicy` is a typed `AppConfig` product policy with:

- `excludedPrimaryPaths = ["home_3h", "home_12h"]`; and
- `persistedPrimarySelectionKey =
  "nativeha.navigation.selected-primary-view.v1"`.

Implementation must add this approved typed surface to
`docs/configurability.md`. It does not imply a settings UI.

The stored v1 value is a small property-list-safe tagged locator (unique `path`
or a nonnegative `sourceIndex` for a pathless view), never canonical JSON, a
hash, a resolved identity, server URL, token, credential, or profile. There is
no pre-v1 route preference,
so fresh install is the complete migration. Invalid type/version/index, empty
path, ambiguous restore, excluded/hidden target, or removed view is discarded
and startup fallback applies. Failure to read/write preferences is nonfatal.

The fixed-server decision leaves the existing hardcoded/local token bootstrap
unchanged. Module 12 performs no credential migration and introduces no keychain
or profile persistence.

## Reference anchors

All frontend anchors are pinned to clean hass-frontend revision
`dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`. Exact hashes and the full closure
are in the generated graph.

| Behavior | Complete anchor and symbol/line hint | SHA-256 |
|---|---|---|
| Tab visibility, startup/path resolution, direct hidden routes, back, view cache/select | `src/panels/lovelace/hui-root.ts`: `render` 450, `_isVisible` 666, routing 775-847, `_goBack` 891, `_navigateToView` 1118, `_selectView` 1224 | `b0d88e019b04…` |
| View fields and fallback title/icon | `src/data/lovelace/config/view.ts`: `LovelaceBaseViewConfig` 55, `computeViewTitle` 97, `computeViewIcon` 102 | `97b0ae3abffd…` |
| Config ownership/update | `src/panels/lovelace/ha-panel-lovelace.ts`, `src/data/lovelace.ts` | `79c022d29059…`, `aa8d12f35f54…` |
| Current user collection/bootstrap | `src/data/ws-user.ts`: `userCollection` 5, `subscribeUser` 13; `src/state/auth-mixin.ts`: `hassConnected` 23; `src/types.ts`: `CurrentUser` 113 | `a37a7d50007c…`, `f3c18c5cc772…`, `52a272f9b19d…` |
| Runtime `auth/current_user` crossing | `home-assistant-js-websocket@9.6.0/dist/commands.js`: `getUser` 5; `dist/messages.js`: `user` 29 | `88685ebfab73…`, `5de87c3bf012…` |
| View creation/layout | `views/hui-view.ts`, `create-element/create-view-element.ts`, `views/get-view-type.ts`, `views/hui-masonry-view.ts`, `views/hui-panel-view.ts` | `7050ef76d095…`, `885726ed2a98…`, `df57793824e6…`, `28b681c4c9b2…`, `d1649c31dc04…` |
| View container/header | `views/hui-view-container.ts`, `views/hui-view-header.ts` | `9d6657c7f39e…`, `e96e02e6e096…` |
| Dialog-safe navigation/back | `src/common/navigate.ts`: `navigate` 59, `goBack` 97 | `6ca2c178560d…` |
| Card detach/history unsubscribe | `cards/hui-history-graph-card.ts`: `connectedCallback` 135, `disconnectedCallback` 142, `_subscribeHistory` 147, `_unsubscribeHistory` 236 | `f20a8c88f513…` |

The complete seeded files and behaviorally relevant dependencies were read.
The graph has 121 nodes, 901 edges, two recorded import cycles, zero unresolved
edges, and no truncation. Its max-depth/type-only/package boundaries are
candidate-discovery stops; explicit runtime seeds cover the injected
`home-assistant-js-websocket` current-user command. No other behaviorally
relevant npm runtime crossing was found.

## Native anchors and mapping

Native anchors are pinned to current `main` revision
`dda63c1b69feed1de38e2f0657504bc9cd8c883c`; that revision is housekeeping on
top of functional Module 04 baseline `933abd5`. Exact hashes/blobs are in the
graph and all production anchors are clean.

| Contract | Existing/planned Swift path | SHA-256 at research | Symbol/type and ownership |
|---|---|---|---|
| C12-01..03, C12-11 | New `Sources/NativeHAMac/LovelaceViewNavigation.swift` | N/A (planned) | Pure locator, item, eligibility, restore/fallback, direct route, and back resolution. No async owner or duplicated source models. |
| C12-01, C12-02 | `Sources/NativeHACore/LovelaceModels.swift` (`LovelaceView` 58, `LovelaceResolvedIdentity` 497, `LovelaceResolvedView` 544) | `02bed5b336729a496c7f2a48ecdcf17956af998624076ed0835164c188a9436e` | Consume existing raw visibility/subview/path/icon/title and exact resolved identity unchanged. |
| C12-04, C12-05 | `Sources/NativeHAMac/DashboardView.swift` (`DashboardView` 4, `SidebarView` 193) | `cccdbb341930b6310abc4170d5f5550c4446f4814dd79b08f6d7070c6d132b5d` | Render navigation items/selected presentation; remove hardcoded personal/app rows; preserve selector. |
| C12-05..09, C12-11 | `Sources/NativeHAMac/DashboardViewModel.swift` (`DashboardViewModel` 5, `dashboardOwnerOperationTail` 35, `reconcileLovelaceConfig` 723, `historyRequests` 1129) | `b471d586874816bfdaa4e74c8abcbe81cb8ebc1232a38a09921ba8f2a01d9280` | MainActor remains orchestration owner through Module 12. Add published navigation/selection and fold selection into the one existing owner tail. `historyRequests` derives only from final selected view. |
| C12-06..08 | `Sources/NativeHAMac/CardViews.swift`; `GraphRenderScheduling.swift` (`GraphHistoryRevisionFeed` 10, mount lifecycle 51, mount registry 101, coordinator 211) | `23fffc4f8411aacc8477efafc6b8bd3f80ed5c4f20cfddfba1c66931005f2832`; `6bca525704f55123d4f1007a86ed3289bac311a84fbbbadc7b8e6f704a57afb0` | Reuse exact owner IDs/feed generations/mount invalidation/coordinator reset; no second scheduler or hash ordering. |
| C12-07 | `Sources/NativeHAMac/GraphRendering.swift` (`GraphRenderSeriesInput` 36, `GraphBitmapRenderer` 302, private prepared cache 870) | `6fdeb14608f5a396a800fba83ce40df034e0cc93fde90b8ddaccfbaa1d22e373` | Keep Core Graphics and exact cache scope. Old hidden entries are inert and normally evicted; do not flush unrelated cache entries or accept late completions. |
| C12-10 | `Sources/NativeHACore/HomeAssistantWebSocketClient.swift` | `d0b5cc37bb151f54f178402b61429979cd067c1d2acf8a7f56662f468c62307d` | Add `fetchCurrentUser()` using `connection.call(["type": "auth/current_user"])`; reuse Module 02 timeout, request ID, cancellation, generation, and decoder behavior. |
| C12-10 | `Sources/NativeHACore/Models.swift` | `e25788d8b24b6fa1517fcfb104ffe4e3faa7f17dc24ea89564d981d782387a60` | Add minimal decoded `HACurrentUser { id }`; intentionally do not retain credentials, MFA modules, or name because navigation needs only ID. |
| C12-03, C12-04 | `Sources/NativeHAMac/AppConfig.swift` | `06ae89a0048416e79ecfc81e43a27076c23156a5c4fb0dd505ed2a9a78a23910` | Add `LovelaceNavigationPolicy` only. Preserve every current graph/transport/render/tooltip/logging/layout policy. |
| C12-05, C12-11 | `Sources/NativeHAMac/LovelacePresentation.swift` | `074c6d454d3f9b44135448b3f0444e3d19913eb59c63ca8a0029c603a44f9844` | Consume preserved per-view presentation; change only if active-view exposure lacks a narrow seam. |
| All | Focused tests listed in handoff | Exact test hashes are pinned in the graph. | Use fake preferences, WebSocket command gates, history subscriptions, feed/mount/coordinator gates, deterministic views, and weak lifetime probes. |

The current cache scope begins with resolved card native ID, and that ID's
source path includes the view path. History keys, feed ownership, SwiftUI IDs,
mount ownership, coordinator scope, and prepared-cache scope therefore already
isolate different views without a new identity scheme. With one fixed server,
no profile identity belongs in those keys or in persistence.

## Decisions and native deviations

| ID | Decision/deviation | Allowed reason | Preserved semantics | Test/status |
|---|---|---|---|---|
| D12-01 | Exclude only exact `home_3h`/`home_12h` paths from primary navigation. | User-approved fixed-dashboard policy. | Raw config and exact direct routes survive; selector provides graph range. | Path-exact fixture; resolved. |
| D12-02 | Persist last eligible primary in `UserDefaults`, not a browser URL or profile record. | Native-platform convention plus fixed-server decision. | Deterministic restore/fallback and transient subview behavior. | Migration/restore matrix; resolved. |
| D12-03 | On unavailable current user, fail closed only for user-list visibility and continue bootstrap. | Safe bounded error handling. | Public/boolean-visible dashboard remains usable; no restricted item is accidentally advertised. | Command failure test; resolved. |
| D12-04 | Use supported MDI-to-SF mappings plus a generic native icon fallback. | Native-platform limitation; full MDI asset system is absent. | Raw icon/title/accessibility survive and selection is unaffected. | Icon matrix/manual oracle; resolved scoped limitation. |
| D12-05 | Keep global state/status connected while retiring selected-view owners. | Existing native ownership boundary. | Same-server entity state remains current; hidden history/render work stops. | Gated integration; resolved. |
| D12-06 | Keep bounded prepared-cache entries inert rather than globally flushing on every switch. | Measured-performance architecture already verified by Modules 01/04/09. | Exact cache scope prevents cross-view reuse; coordinator generation prevents old publication. | Cache-scope/lifecycle test; resolved. |

## Required implementation order

1. Run the Module 12 checker and resolver. If green, use this packet and its
   named graph nodes rather than repeating broad research.
2. Add minimal `HACurrentUser` and `fetchCurrentUser()` with command/failure/
   cancellation tests. Do not touch authentication or token persistence.
3. Add pure navigation policy, locator, eligibility, display, restore, direct
   route, and back behavior with the complete unit matrix.
4. Add `LovelaceNavigationPolicy` to `AppConfig` and update
   `docs/configurability.md` in the same implementation commit.
5. Add active-view state to `DashboardViewModel`. Extend the existing
   serialized owner-operation boundary; do not introduce another tail.
6. Prove exact retain/cancel/install ordering with held startup/cancellation,
   A-B-C, A-B-A, config-refresh, range, late callback, detail, global-state,
   and weak-lifetime tests before changing the UI.
7. Replace the hardcoded sidebar/top title and render active presentation cards
   while retaining the selector and default-view-only layout exception.
8. Add GUI, performance, migration, release, full-suite, and read-only live
   evidence. Stop after Module 12; dispatch independent verification before
   Module 05.

Do not alter `LovelaceResolvedIdentity`, Module 02 connection architecture,
Module 01 history semantics, graph feed ordering, renderer/cache freshness,
tooltip/logging policy, or token bootstrap to make implementation easier.

## Required tests and evidence

### Unit and migration

Use a deterministic fixture with `default_view`, exact maintenance paths, one
genuine view, duplicate and pathless views, boolean/user-list visibility,
subview/back path, invalid view, empty view, panel, title/icon combinations,
and nested history cards. Prove C12-01 through C12-05 and C12-11, including raw
structural equality before/after navigation and range changes.

Preference tests use an isolated suite or injected in-memory store and clean up
only that exact suite. Cover no stored value, valid path/index, old/wrong
version, malformed payload, negative/out-of-range index, empty/duplicate path,
removed/excluded/newly hidden target, persist only after final commit, subview
not overwriting primary, write failure, and deterministic fallback. There is no
token/profile migration test because no such migration is allowed.

### Integration and lifecycle

Extend the existing fake WebSocket/history/render harness to prove:

- `auth/current_user` uses one normal typed command, decodes ID, and its
  rejection/timeout/late old response is nonfatal and credential-free;
- initial routing starts only selected-view history owners;
- exact same selection/config retains feeds, mounts, coordinators, histories,
  and one wire owner without churn;
- selection/range/config refresh serialize on one tail, with old desired and
  delivery generations retired before a held cancellation;
- A-B-C never publishes B, and A-B-A restarts exactly one fresh A owner/feed
  generation without overlap while keeping accepted A visual state during the
  hold;
- every old acknowledgement, history publication, owner status, feed event,
  and render completion is rejected;
- detail is dismissed and its owner canceled before final navigation publish;
- obsolete hidden owners settle at zero subscriptions, observers, mounts,
  queued/in-flight coordinator work, and animations; prepared cache entries
  cannot publish or cross exact scopes and return to normal bounded eviction;
- global state subscription and connection status continue once across view
  switches and are usable by the new view; and
- resize produces no selection/identity/subscription churn.

Re-run all applicable Module 02 connection tests, Module 01 history/feed/range/
detail tests, Module 04 identity/config-revert/mount tests, and Module 09 graph
coordinator/cache tests. Any regression is introduced until proven otherwise.

### GUI and manual

Use the existing macOS 12-compatible offscreen AppKit workflow at dark
appearance, scale 2, fixed locale/timezone, and bounded graph settlement.
Create current artifacts in `.build/render-artifacts/`:

- `sidebar-selected-home.png`, `sidebar-unselected-long-title.png`, and a
  deterministic focus/hover state;
- `dashboard-three-column.png` at 1792 x 1000 points;
- `dashboard-narrow.png` at 900 x 700 points;
- `dashboard-loading.png` and `dashboard-empty-view.png`; and
- selected genuine-view and panel-view captures.

Assert PNG signature, doubled pixel size, nonblank expected regions, selected
indicator/title/card presence, maintenance-label absence, and no unresolved
loading. Manually inspect keyboard activation/focus order, VoiceOver labels,
wide/narrow clipping/scrolling, long titles, rapid switching, subview/back,
range control, relaunch restore, and hidden graph settlement. Images do not
prove identity, ownership, accessibility, or cancellation.

### Performance

Generate a 10-view x 50-card fixture outside measured blocks. Measure cold
navigation preparation separately from warmed genuine-view/range switching and
wide/narrow resizing. Exercise 100 deterministic cycles using clock/CPU/memory
metrics supported by the toolchain, consume exact active-card/subscription/
observer/mount/queued-render counts, and use stored XCTest baselines rather
than brittle universal millisecond thresholds. After bounded settlement, only
the final view's exact owner set remains and memory/weak-owner counts do not
trend upward.

### Release and read-only live smoke

Before `complete`:

- run Module 12 context checker and resolver;
- run focused unit, migration, integration, lifecycle, GUI, and performance
  tests plus the green Module 02/01/04 and relevant Module 09 regressions;
- run the full test suite and release build;
- manually inspect required artifacts; and
- run authorized read-only config/current-user/history smoke without service
  calls or state mutation.

Research-time read-only live config smoke on 2026-08-25 found three valid raw
views in order: `default_view` (Home), `home_3h`, and `home_12h`. None supplied
icon, `show_icon_and_title`, visibility, subview, back path, or panel fields.
Counts remained 22 top-level and 31 recursive cards, consistent with the green
Module 04 packet. Exact path filtering yields one primary Home item; no
semantic/hash/timestamp duplicate inference is needed. Credentials were never
written to an artifact and no state-changing call was made.

## Resolved questions, risks, and stop rules

Resolved product questions:

- Module 03 is intentionally skipped, not complete; fixed server/token
  bootstrap remains.
- No profile/settings UI or credential/token migration is part of Module 12.
- Maintenance duplication is path-exact; graph selector remains global.
- Route persistence stores only final eligible primary selection, without a
  profile namespace.
- User-list visibility uses optional current user ID and fails closed only for
  those views.
- Global state/status remain connected; view/card/detail ownership retires.
- Module 05 follows independently verified Module 12 and omits profile work.

No material product or migration question remains unresolved. Technical risks
remain duplicate/pathless config churn, reentrant owner cancellation, native
icon limitations, user metadata failure, and layout cost; the contracts and
tests above bound each risk.

Stop implementation and return to research/user direction if:

- exact card/view identity is insufficient and a hash/timestamp/semantic
  ancestry heuristic appears necessary;
- a second owner-operation tail or overlapping old/new owner is proposed;
- current-user visibility would require storing/logging credentials or changing
  token bootstrap;
- persistence would need a profile/server namespace or a migration guarantee
  beyond the fresh v1 preference;
- unrelated views require changing the approved default-dashboard layout or
  graph-range product behavior;
- full URL/app routing, edit mode, settings/profile UI, or Modules 05-11 become
  necessary to make the bounded feature work; or
- any required lifecycle/release/live evidence cannot be made green.

## Exact implementation handoff

Dispatch one fresh sole Swift/test writer. Permitted production files:

- `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`;
- `Sources/NativeHACore/Models.swift`;
- new `Sources/NativeHAMac/LovelaceViewNavigation.swift`;
- `Sources/NativeHAMac/AppConfig.swift`;
- `Sources/NativeHAMac/DashboardViewModel.swift`;
- `Sources/NativeHAMac/DashboardView.swift`; and
- only a minimal edit to `LovelacePresentation.swift`, `CardViews.swift`,
  `GraphRenderScheduling.swift`, or `GraphRendering.swift` if a packet-named
  existing seam cannot be exercised without it. Such an edit must preserve the
  inherited contract and be justified in implementation evidence.

Permitted tests/artifacts:

- new `Tests/NativeHAMacTests/LovelaceViewNavigationTests.swift`;
- focused additions to `DashboardBootstrapLifecycleTests.swift`,
  `HistoryStreamIntegrationTests.swift`, and
  `GUIRenderingAndPerformanceTests.swift`;
- minimal core WebSocket client/connection tests for `auth/current_user`;
- a deterministic Module 12 fixture under `Tests/Fixtures/Lovelace/`;
- `.build/render-artifacts/` runtime outputs, which are not committed; and
- `docs/configurability.md` plus this Module 12 packet/index/generated graph if
  implementation changes their recorded anchors/status/evidence.

Do not edit Module 03, begin Module 05, add settings/profile/token migration,
or implement Modules 06-11. The exact next action is: run the green context
gate, implement C12-10 and the pure navigation model/tests first, then integrate
the single owner tail in the order above. After implementation evidence is
committed, launch a separate independent Module 12 verifier. Only a green
verification may mark Module 12 `complete` and dispatch Module 05 orchestration
decomposition under the fixed-server assumption.

## Research validation

- Pre-generation context check: expected `ENOENT` because no Module 12 graph
  existed.
- Generated graph: 121 nodes, 901 edges, zero unresolved, not truncated,
  fingerprint `2029b45105e24649341ec59dc5f68a571a643059b6efd9c01a3b00c1b2eb0475`.
- Post-generation context check: GREEN.
- Resolver self-test: PASS, 31 nodes, 61 edges, fingerprint
  `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`.
- Green prerequisite packets retained: Module 02 contract revision 2, Module
  01 revision 3, and independently verified Module 04 revision 1.
- Independent read-only configuration/ownership audit verdict: GO after adding
  current-user runtime tracing, fail-closed user-list eligibility, one-tail
  ordering, global-versus-view ownership, exact-revert, persistence, and cache
  rules now recorded above.

## Change log

- 2026-08-25, contract revision 1: initial bounded research-ready packet after
  fixed-server decision and independent navigation/ownership audit.
