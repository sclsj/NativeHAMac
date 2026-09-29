---
schema: nativeha-evidence/v1
module: "12"
title: Sidebar and Lovelace view navigation
plan: ../../rescue-plan/module-12-sidebar-lovelace-views.md
status: complete
contract_revision: 1
depends_on: ["01", "02", "04"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 9291da336d2f068c39c4924fed3add4c52c27f85
graph_file: ../generated/module-12.dependencies.json
graph_fingerprint: "ae11f6f5cb77abf047a2b6987dc48114a627580c030c6fe48dbd96868e4ca16a"
last_researched: 2026-08-25
last_verified: 2026-08-25
last_validated: 2026-09-11
---

# Module 12 evidence packet

2026-09-11 anchor refresh: the shared dashboard bootstrap and its tests changed; see [Module 05 consolidation](module-05-dashboard-viewmodel-state.md#2026-09-11-bootstrap-consolidation) for validation and limits. This module's contract revision is unchanged; older verification entries below retain their original revision-specific evidence.

## Gate and scope delta

This packet is the implementation authority for Module 12. Module 04 already provides lossless views/cards and exact path-plus-canonical identities. Modules 01 and 02 already provide verified history ownership and a single multiplexed WebSocket connection. Module 12 consumes those contracts; it does not redesign them.

The user has intentionally skipped Module 03. NativeHA targets one fixed personal Home Assistant deployment, keeps the current token/bootstrap path, and has no profile switching or settings UI. Consequently Module 12 has no profile namespace or transition state, and Module 05 must follow Module 12 rather than being treated as its prerequisite.

Relative to the rescue plan, research resolves these points:

- the hardcoded app/profile/sidebar rows are removed rather than preserved as nonfunctional destinations;
- `home_3h` and `home_12h` are excluded by exact path from primary navigation, while their source config and explicit route lookup remain intact;
- current-user visibility requires one optional typed `auth/current_user` bootstrap command; failure hides only user-list-gated primary items and does not fail dashboard bootstrap;
- selection persistence is a versioned fixed-deployment preference, not a profile-scoped preference;
- view selection, config reconciliation, refresh, history load, and graph-range changes share the existing serialized dashboard-owner operation tail; and
- global state and connection-status ownership survive a view switch. Only view/card/detail work is retired.

Still out of scope are full browser URL routing, Lovelace editing, a settings or profile UI, server/token migration, full MDI rendering, Modules 05-11, a Metal default, and the separate Module 09 stale-viewport fallback.

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

Opaque UUID generations remain permitted for runtime lifetime isolation. They are never persisted selection, model identity, owner ancestry, or freshness.

## Navigation model and state machines

### Pure model

Add a pure `LovelaceViewNavigation` layer with these distinct concepts:

- `LovelaceViewLocator`: `.path(String)` only for a unique nonempty source path, or `.sourceIndex(Int)` only when the source path is absent;
- `LovelaceNavigationItem`: exact resolved identity, locator, display title, raw icon, source index, and selected state;
- `selectedViewIdentity`: exact Module 04 resolved identity for the installed snapshot; and
- `lastPrimaryIdentity`: exact in-memory back destination, plus `lastPrimaryLocator`: the only persisted selection when unambiguous.

Locator equality makes a route findable; resolved identity decides SwiftUI and owner lifetime. Never make those one type. Sidebar selection calls by exact identity. The path API exists for internal links/back behavior and resolves the first source-order exact match. Duplicate paths are retained and separately selectable from a sidebar action when otherwise primary-eligible, but they have no persisted locator; committing one clears an unsafe stored locator and keeps only its exact in-memory identity.

### Eligibility and startup

For each valid raw-order view:

1. Exclude exact path membership in `AppConfig.lovelaceNavigationPolicy.excludedPrimaryPaths`.
2. Exclude `subview == true`.
3. Include absent/`true` visibility.
4. Exclude `false` visibility.
5. For a visibility array, include only if at least one `user` equals the optional current user ID; with no ID, exclude it.

This filter affects primary navigation, startup fallback, and persistence restore. It does not delete raw/resolved views. A direct route may resolve a preserved subview/hidden view because hass-frontend also routes an explicit path without applying `_isVisible`; `visible` is not an access-control layer.

Startup waits for Lovelace config and the optional bounded current-user result, then chooses:

1. a valid unambiguous persisted eligible primary;
2. the single eligible view whose path is exactly `default_view`;
3. the first eligible view in raw order; or
4. `nil`, producing a controlled empty-navigation/empty-dashboard state and no view owners.

After final install, persist an unambiguous primary locator. If an explicitly routed subview/non-primary view is selected, retain the prior valid primary locator. Back first resolves a supported internal `back_path` to an exact view path, then that prior primary, then startup fallback. An external/unresolvable `back_path` gets a diagnostic and fallback because full app/URL routing is out of scope.

### Serialized view switch

Selection, config application, refresh, history load, and graph-range change must enqueue on one `dashboardOwnerOperationTail`; a second tail is forbidden. For final candidate `(config generation, navigation generation, view identity, range)`:

1. Before an `await`, increment navigation generation, record desired selected identity/locator, close detail presentation, retire detail generation, and compute exact current/desired history-owner sets.
2. Detach obsolete desired keys, startup tasks, acknowledgement generations, subscription delivery generations, and detail ownership synchronously. Capture cancellations. Keep accepted visual snapshots and currently mounted UI intact while cancellation is suspended.
3. Await every captured startup/subscription/detail cancellation. No new owner with the same key may install until its predecessor cancellation completes.
4. Recheck config sequence, navigation sequence, desired selected identity, effective range, and desired keys after each suspension. A superseded candidate completes only its captured ownership cleanup and exits.
5. For the still-final candidate only, synchronously invalidate mounts and coordinator generations for obsolete owners, remove obsolete feeds/history/ status stores, and publish the selected view immediately afterward.
6. Persist only a final committed eligible primary selection with an unambiguous locator; clear an unsafe duplicate-path locator.
7. Start missing desired owners. After every subscription acknowledgement, recheck all captured generations and desired membership before installing delivery ownership or publishing status/history.

The exact intersection is retained. A same-view no-op retains all current owners. A config refresh may retain unchanged card owners in the selected view. A distinct view normally retains none because card source identities contain their view source path. Semantic duplicate cards in two views are not the same owner. A range change changes the effective request and therefore replaces history owners without changing raw card config.

Global `state_changed` and connection-status ownership are dashboard/server lifetime, not selected-view lifetime. They stay connected. Current and future view-scoped owners (history now; weather/template only after their modules) must use the same active-card ownership seam, but Module 12 must not implement Modules 07 or 08 speculatively.

## Persistence and migration policy

`LovelaceNavigationPolicy` is a typed `AppConfig` product policy with:

- `excludedPrimaryPaths = ["home_3h", "home_12h"]`; and
- `persistedPrimarySelectionKey = "nativeha.navigation.selected-primary-view.v1"`.

Implementation must add this approved typed surface to `docs/configurability.md`. It does not imply a settings UI.

The stored v1 value is a small property-list-safe tagged locator (unique `path` or a nonnegative `sourceIndex` for a pathless view), never canonical JSON, a hash, a resolved identity, server URL, token, credential, or profile. There is no pre-v1 route preference, so fresh install is the complete migration. Invalid type/version/index, empty path, ambiguous restore, excluded/hidden target, or removed view is discarded and startup fallback applies. Failure to read/write preferences is nonfatal.

The fixed-server decision leaves the existing hardcoded/local token bootstrap unchanged. Module 12 performs no credential migration and introduces no keychain or profile persistence.

## Reference anchors

All frontend anchors are pinned to clean hass-frontend revision `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`. Exact hashes and the full closure are in the generated graph.

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

The complete seeded files and behaviorally relevant dependencies were read. The graph has 121 nodes, 901 edges, two recorded import cycles, zero unresolved edges, and no truncation. Its max-depth/type-only/package boundaries are candidate-discovery stops; explicit runtime seeds cover the injected `home-assistant-js-websocket` current-user command. No other behaviorally relevant npm runtime crossing was found.

## Native anchors and mapping

Research anchors were pinned to current `main` revision `a4dcd1c8d8fe171a9753b109ae9b241aa6f44cef`, the Module 12 research commit on top of functional Module 04 baseline `933abd5`. The regenerated graph records the implementation worktree anchor hashes for independent verification.

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

The current cache scope begins with resolved card native ID, and that ID's source path includes the view path. History keys, feed ownership, SwiftUI IDs, mount ownership, coordinator scope, and prepared-cache scope therefore already isolate different views without a new identity scheme. With one fixed server, no profile identity belongs in those keys or in persistence.

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

1. Run the Module 12 checker and resolver. If green, use this packet and its named graph nodes rather than repeating broad research.
2. Add minimal `HACurrentUser` and `fetchCurrentUser()` with command/failure/ cancellation tests. Do not touch authentication or token persistence.
3. Add pure navigation policy, locator, eligibility, display, restore, direct route, and back behavior with the complete unit matrix.
4. Add `LovelaceNavigationPolicy` to `AppConfig` and update `docs/configurability.md` in the same implementation commit.
5. Add active-view state to `DashboardViewModel`. Extend the existing serialized owner-operation boundary; do not introduce another tail.
6. Prove exact retain/cancel/install ordering with held startup/cancellation, A-B-C, A-B-A, config-refresh, range, late callback, detail, global-state, and weak-lifetime tests before changing the UI.
7. Replace the hardcoded sidebar/top title and render active presentation cards while retaining the selector and default-view-only layout exception.
8. Add GUI, performance, migration, release, full-suite, and read-only live evidence. Stop after Module 12; dispatch independent verification before Module 05.

Do not alter `LovelaceResolvedIdentity`, Module 02 connection architecture, Module 01 history semantics, graph feed ordering, renderer/cache freshness, tooltip/logging policy, or token bootstrap to make implementation easier.

## Required tests and evidence

### Unit and migration

Use a deterministic fixture with `default_view`, exact maintenance paths, one genuine view, duplicate and pathless views, boolean/user-list visibility, subview/back path, invalid view, empty view, panel, title/icon combinations, and nested history cards. Prove C12-01 through C12-05 and C12-11, including raw structural equality before/after navigation and range changes.

Preference tests use an isolated suite or injected in-memory store and clean up only that exact suite. Cover no stored value, valid path/index, old/wrong version, malformed payload, negative/out-of-range index, empty/duplicate path, removed/excluded/newly hidden target, persist only after final commit, subview not overwriting primary, write failure, and deterministic fallback. There is no token/profile migration test because no such migration is allowed.

### Integration and lifecycle

Extend the existing fake WebSocket/history/render harness to prove:

- `auth/current_user` uses one normal typed command, decodes ID, and its rejection/timeout/late old response is nonfatal and credential-free;
- initial routing starts only selected-view history owners;
- exact same selection/config retains feeds, mounts, coordinators, histories, and one wire owner without churn;
- selection/range/config refresh serialize on one tail, with old desired and delivery generations retired before a held cancellation;
- A-B-C never publishes B, and A-B-A restarts exactly one fresh A owner/feed generation without overlap while keeping accepted A visual state during the hold;
- every old acknowledgement, history publication, owner status, feed event, and render completion is rejected;
- detail is dismissed and its owner canceled before final navigation publish;
- obsolete hidden owners settle at zero subscriptions, observers, mounts, queued/in-flight coordinator work, and animations; prepared cache entries cannot publish or cross exact scopes and return to normal bounded eviction;
- global state subscription and connection status continue once across view switches and are usable by the new view; and
- resize produces no selection/identity/subscription churn.

Re-run all applicable Module 02 connection tests, Module 01 history/feed/range/ detail tests, Module 04 identity/config-revert/mount tests, and Module 09 graph coordinator/cache tests. Any regression is introduced until proven otherwise.

### GUI and manual

Use the existing macOS 12-compatible offscreen AppKit workflow at dark appearance, scale 2, fixed locale/timezone, and bounded graph settlement. Create current artifacts in `.build/render-artifacts/`:

- `sidebar-selected-home.png`, `sidebar-unselected-long-title.png`, and a deterministic focus/hover state;
- `dashboard-three-column.png` at 1792 x 1000 points;
- `dashboard-narrow.png` at 900 x 700 points;
- `dashboard-loading.png` and `dashboard-empty-view.png`; and
- selected genuine-view and panel-view captures.

Assert PNG signature, doubled pixel size, nonblank expected regions, selected indicator/title/card presence, maintenance-label absence, and no unresolved loading. Manually inspect keyboard activation/focus order, VoiceOver labels, wide/narrow clipping/scrolling, long titles, rapid switching, subview/back, range control, relaunch restore, and hidden graph settlement. Images do not prove identity, ownership, accessibility, or cancellation.

### Performance

Generate a 10-view x 50-card fixture outside measured blocks. Measure cold navigation preparation separately from warmed genuine-view/range switching and wide/narrow resizing. Exercise 100 deterministic cycles using clock/CPU/memory metrics supported by the toolchain, consume exact active-card/subscription/ observer/mount/queued-render counts, and use stored XCTest baselines rather than brittle universal millisecond thresholds. After bounded settlement, only the final view's exact owner set remains and memory/weak-owner counts do not trend upward.

### Release and read-only live smoke

Before `complete`:

- run Module 12 context checker and resolver;
- run focused unit, migration, integration, lifecycle, GUI, and performance tests plus the green Module 02/01/04 and relevant Module 09 regressions;
- run the full test suite and release build;
- manually inspect required artifacts; and
- run authorized read-only config/current-user/history smoke without service calls or state mutation.

Research-time read-only live config smoke on 2026-08-25 found three valid raw views in order: `default_view` (Home), `home_3h`, and `home_12h`. None supplied icon, `show_icon_and_title`, visibility, subview, back path, or panel fields. Counts remained 22 top-level and 31 recursive cards, consistent with the green Module 04 packet. Exact path filtering yields one primary Home item; no semantic/hash/timestamp duplicate inference is needed. Credentials were never written to an artifact and no state-changing call was made.

## Implementation evidence

One fresh sole Swift/test writer implemented C12-01 through C12-12 without a commit. The bounded production diff is:

- a minimal decoded `HACurrentUser { id }` and typed `fetchCurrentUser()` on the existing Module 02 command path;
- the approved `LovelaceNavigationPolicy` with exact maintenance exclusions and one versioned fixed-deployment preference key;
- new pure `LovelaceViewNavigation` locator, eligibility, display, restore, direct-route, back, and persistence behavior;
- active exact view/card state in `DashboardViewModel`, with selection, config, refresh, and range operations sharing the pre-existing `dashboardOwnerOperationTail`; and
- a native dynamic sidebar/top title and selected-view content in `DashboardView`, retaining the approved range selector and Core Graphics.

No profile/settings UI, server/token migration, second owner-operation tail, hash/timestamp freshness rule, full URL router, or Module 05-11 behavior was added. `LovelaceResolvedIdentity`, Module 02 connection ownership, the global state/status lifetime, graph feed-before-publication ordering, render coordinator/cache freshness, tooltip, logging, and graph-range policies remain intact.

Contract evidence before independent verification:

| Contracts | Implementation evidence |
|---|---|
| C12-01..05, C12-11 | Nine pure/navigation-view-model tests cover exact maintenance/subview/boolean/user filtering with raw preservation; unavailable-user fail-closed behavior; duplicate/pathless locator rules; default/first/empty fallback; direct hidden routes and back; title/icon modes; strict v1 persistence cleanup/failure; transient routes; and reorder/removal config reconciliation. The deterministic fixture includes duplicate, pathless, hidden, user-list, subview, panel, empty, default, maintenance, and invalid inputs. |
| C12-06..09 | Twenty-two `HistoryStreamIntegrationTests` pass, including inherited unified-tail/exact-revert gates plus view cancel-before-install, late history/detail/feed/render/status rejection, global state/status continuity, exact A-B-A restart with no B publication, same-view no churn, late old acknowledgement rejection, and selection raced with config refresh. Obsolete desired generations are detached synchronously before suspension; only the final candidate removes visuals, invalidates mounts/coordinators, publishes, persists, and starts missing owners. |
| C12-10 | The typed command test proves the exact `auth/current_user` request and minimal ID decode. Five bootstrap lifecycle tests prove rejection and timeout are nonfatal, user-list items alone fail closed, global state ownership continues, and a late old bootstrap user cannot revise the current navigation. Live output reports only whether an ID was present. |
| C12-04, C12-05, C12-12 | Nine dark 2x GUI artifacts pass signature, dimension, nonblank-region, active title/card/indicator, maintenance-label absence, long-title, loading, empty, wide/narrow, genuine-view, and panel checks. The writer manually inspected the contact sheet: selected state, clipping/scrolling, default-only three columns, native one-column unrelated view, full-width panel, loading, and empty states are coherent. Native rows are `Button`s with explicit labels and selected traits; keyboard traversal and VoiceOver remain an explicit independent manual gate because PNGs cannot prove them. |
| C12-12 | The deterministic 10-view x 50-card test completes 100 navigation preparation cycles with XCTest clock/CPU/memory metrics and no failure; fixture construction is outside the measured block. The final full suite passes 188 tests with three authorized skips and zero failures in 79.871 seconds. The production release build passes. |

During implementation, directly cancelling a held card-history startup caused an inherited Module 04 acknowledgement-before-cancel lifecycle test to fail. The writer classified it as introduced and removed that premature task cancellation: desired/startup generations still reject the old result, while the existing command acknowledgement is allowed to yield its cancellable subscription before orderly teardown. The focused history suite and full suite then returned green. No remaining failure was classified or waived.

Implementation-time read-only live smoke passed in 6.379 seconds. It decoded three views, 22 top-level / 31 recursive cards, and 66 rows; obtained a current user ID without logging it; decoded a representative one-hour history with 2,382 points, one-hour CO2/VOC with 8,658 points, 12-hour CO2/VOC with 102,723 points, and 24-hour history with 57,075 points. It made no service call or state mutation.

Implementation validation:

- Module 12 graph: GREEN, 121 nodes / 901 edges, two cycles, zero unresolved, no truncation, fingerprint `9b1d9ef6299ea75638bb1d7771ac3c6226f04b42a806780e5638f3579f3eb2ef`;
- resolver self-test: PASS, 31 nodes / 61 edges, fingerprint `bebafb88c82d7a3e6acd08f7577e2dbca3a2c82c1b2ccc28533c09c2e760a711`;
- focused navigation 9/9, bootstrap 5/5, history integration 22/22, current-user command, GUI-artifact, performance, and read-only-live tests: PASS;
- full suite: 188 tests executed, three authorized skips, zero failures;
- release build: PASS; and
- inherited Module 02/01/04 and relevant Module 09 regressions: PASS through the full suite.

Implementation verdict: **GO to independent verification**. Status is `verification-ready`, not `complete`. The verifier must review the exact diff, rerun graph/resolver/focused/full/release/live gates, regenerate and inspect the nine artifacts, manually exercise keyboard activation/focus order and VoiceOver labels, and specifically audit the one-tail cancellation ordering, global-versus-view ownership, direct hidden routes, duplicate/pathless persistence, exact cache/coordinator scope, and the inherited startup acknowledgement behavior. Any old-view publication, owner overlap/leak, hash/timestamp ancestry, bootstrap/token change, or accessibility failure is NO-GO.

## Independent verification

The fresh independent verifier's 2026-08-25 verdict is **NO-GO**. Module 12 remains `verification-ready`; it is not complete and does not unlock Module 05. The implementation is broadly functional and every executed automated suite is green, but three contract defects and one required manual-evidence gap remain:

- **C12-10 fails bootstrap-generation isolation.** In `DashboardViewModel.bootstrapDashboard(using:)`, an obsolete invocation unconditionally disconnects the client passed to it at both sequence guards. If a newer bootstrap uses the same client, the obsolete invocation can disconnect the current owner. There is also an actor-reentrant interval between the first sequence guard and the second guard: the old invocation assigns `currentUserID` and awaits config application, so a newer bootstrap can begin while an old config candidate is still able to publish. The existing late-current-user test uses two distinct clients and holds the old result before the first guard; it does not cover either unsafe interleaving.
- **C12-02 does not present its controlled empty-dashboard state for a valid dashboard with zero views.** `LovelaceViewNavigation.startupSelection` correctly returns `nil`, but `DashboardView.content` treats `activePresentationView == nil && views.isEmpty` as loading. After an empty config reaches `Live`, the UI therefore continues to show a spinner and `Live`, rather than `No dashboard view is available`. The existing empty artifact covers a selected view with zero cards, not zero eligible/zero raw views.
- **C12-12 lacks the specified warmed performance/lifecycle evidence.** The 500-card test runs 100 pure `LovelaceViewNavigation` preparations. It never performs warmed view selection, graph-range replacement, or wide/narrow resize cycles and does not consume final subscription/feed-observer/mount/ queued-render/weak-owner counts. Its individual run passed at 0.015 seconds average clock time, but it cannot establish the bounded end-to-end contract.
- **C12-04 keyboard and VoiceOver evidence remains unresolved.** Static review confirms native `Button` rows, explicit labels, selected traits, focus state, and a visually distinct focus outline. The regenerated focus artifact is distinct. The strongest safe local offscreen AppKit accessibility probe exposed no SwiftUI button nodes (`BUTTON_COUNT=0`), and directly launched package executables exposed no scriptable window to System Events. Thus the verifier could not honestly claim keyboard traversal/activation or VoiceOver label/selected-trait behavior. PNGs do not satisfy that gate.

Bounded correction request:

1. Make bootstrap ownership explicit so an obsolete invocation can neither mutate current bootstrap state nor disconnect a client still owned by the latest invocation. Add deterministic same-client and post-first-guard held- apply tests, plus distinct-client coverage, proving the latest navigation, state subscription, connection status, and client survive.
2. Distinguish not-yet-loaded from loaded-with-no-selectable-view and add pure/ view-model/GUI tests for zero raw views and all-ineligible views.
3. Replace or extend the Module 12 performance test with 100 warmed selection, range, and resize cycles over the 10-view/500-card fixture. Assert exact final active cards and zero obsolete subscription, feed-observer, mount, queued/in-flight render, animation, and weak-owner counts after settlement.
4. Run one real app-window keyboard/VoiceOver pass, or add a reliable macOS-12-compatible accessibility harness that proves row order, Tab focus, activation, labels, and the selected trait. Regenerate the affected packet evidence, then dispatch a fresh independent verifier.

Fresh independent validation that did pass:

- Module 12 context checker: GREEN, 121 nodes / 901 edges, two cycles, zero unresolved, fingerprint `9b1d9ef6299ea75638bb1d7771ac3c6226f04b42a806780e5638f3579f3eb2ef`;
- resolver self-test: PASS, 31 nodes / 61 edges, fingerprint `bebafb88c82d7a3e6acd08f7577e2dbca3a2c82c1b2ccc28533c09c2e760a711`;
- navigation 9/9 in 0.026 seconds, bootstrap 5/5 in 0.240 seconds, history integration 22/22 in 1.402 seconds, typed current-user command 1/1 in 0.005 seconds, Module 12 GUI generation 1/1 in 10.473 seconds, and the current 500-card preparation metric 1/1 in 0.433 seconds;
- full suite: 188 tests, three authorized skips, zero failures in 77.977 seconds. This includes the Module 02 transport, Module 01 history, Module 04 model/presentation/identity, and relevant Module 09 coordinator/cache regressions; Core Graphics, range, tooltip, logging, WebSocket, history, feed, coordinator, and cache policies remained green;
- production build: PASS in 6.46 seconds;
- read-only live smoke: PASS in 6.562 seconds with three views, 22 top-level / 31 recursive cards, 66 rows, current-user ID present, registry 276 entries / 74 precisions, representative 1h 2,380 points, CO2/VOC 1h 8,663 and 8,660 points, CO2/VOC 12h 102,740 points, and 24h 57,071 points. Final ownership was zero and no service/state-changing call was made; and
- all nine required Module 12 PNGs regenerated with correct PNG signatures and 2x dimensions (sidebar 476x1400; narrow/loading/empty 1800x1400; wide/ genuine/panel 3584x2000). Contact-sheet inspection found maintenance labels absent, selected and focus styling distinct, long-title truncation coherent, narrow/wide content unclipped, panel full-width, and loading/empty-selected- view states distinct. `git diff --check` passed.

The prerequisite module packets remain complete at Module 02 contract revision 2, Module 01 revision 3, and Module 04 revision 1. Their focused regressions are green in the full suite. Their old generated context graphs report expected yellow source-anchor changes against the uncommitted Module 12 implementation; that is not a prerequisite contract failure and those graphs were not modified by the verifier.

## Bounded correction after independent NO-GO

The sole implementation writer addressed exactly the verifier's four findings without a commit. Status remains `verification-ready`; this is correction evidence for a fresh verifier, not self-approval.

### C12-10 bootstrap generation and client ownership

Every `bootstrapDashboard(using:)` invocation now owns an exact monotonically increasing bootstrap generation and client reference. The generation is carried through the existing dashboard-owner candidate and is part of every `isCurrent` check before config/navigation publication. Bootstrap config coalescing requires the same optional bootstrap generation, so two overlapping invocations with byte-identical config cannot accidentally share an obsolete candidate. A same-raw successful rebootstrap also reapplies navigation because current-user visibility may differ.

Current-user, registry, locale, config, state-subscription acknowledgement, installed client, state callback, coalesced state flush, connection-status callback, error, cancellation, and disconnect paths all validate the exact generation/client owner. An obsolete invocation disconnects only a client not owned by the current invocation or installed owner. Replacement atomically detaches the old global subscription/status task, awaits cancellation, then rechecks the generation before installing the new subscription/client/status. A failing latest replacement also retires and disconnects a previously installed distinct client, so no ignored global owner leaks.

Nine deterministic bootstrap tests pass in 0.413 seconds. They include:

- held first-current-user overlap on the same client: the latest invocation remains ready with exactly one state subscription/wire owner and zero disconnects before explicit teardown; the obsolete late result cannot alter navigation, status, client, or state ownership;
- two same-client, identical-config invocations held after the first guard in the owner tail: candidate one never publishes, candidate two alone installs, final subscription/wire ownership is one, and disconnect count is zero;
- distinct-client, two-stage held apply: the first candidate never publishes while the second is held, the obsolete client disconnects exactly once, and latest navigation, `Live` status, state callback, client, and one global subscription survive;
- the original distinct-client late-current-user gate; and
- latest bootstrap failure after an installed client: both old installed and failed replacement clients disconnect exactly once and settle with zero subscriptions.

### C12-02 final loaded-empty state

`DashboardViewModel.hasLoadedDashboard` now distinguishes never-loaded from a final installed dashboard snapshot. The byte-identical empty-config shortcut is disabled until the first real config installation. `DashboardView` keeps the spinner only while not loaded; zero raw views and preserved all-ineligible raw views render `No dashboard view is available`, while a selected empty view still renders `This view has no cards`.

The pure/navigation/view-model suite passes 11/11 in 0.019 seconds, including zero raw views and maintenance/hidden/subview/user-ineligible matrices with raw preservation. The GUI gate regenerates the original nine artifacts plus `dashboard-no-views.png` and `dashboard-all-ineligible.png`; the two final loaded-empty images are byte-identical to each other and distinct from `dashboard-loading.png`. The affected GUI test passes in 12.231 seconds, and manual inspection confirms the controlled message and `Live` status rather than a perpetual spinner.

### C12-12 warmed performance and lifecycle

The 10-view x 50-card fixture remains built outside measured blocks. A new actual async lifecycle test performs 100 exact genuine-view selections and 100 graph-range replacements through the production owner tail. Each selected view has 50 active cards and one exact history owner; every cycle mounts a feed, requests coordinator visual work at alternating wide/narrow dimensions, then proves the retired lifecycle invalidated before proceeding. The focused run completed in 0.304 seconds.

Before teardown, the final active set is exactly 50 card identities with one desired/subscription/generation/feed/wire/delivery history owner, one current feed observer, one current mount, zero startups, and zero coordinator pending work. After the final empty-config settlement there are zero active owners, subscriptions, wire/delivery owners, feed observers, mounts, coordinator queued/in-flight render work, retained obsolete visuals, and weak lifecycle owners.

The XCTest clock/CPU/memory metric now performs 100 warmed hosted SwiftUI layout/display preparations across ten genuinely selected models, all 500 cards, all approved ranges, and alternating 1792 x 1000 / 900 x 700 sizes. The three-iteration focused result averaged 0.745 seconds monotonic clock and 0.745 seconds CPU per 100-cycle block, with about 399 KB average physical-memory delta and no threshold failure. It consumes exact selected-item, active-card, column, and 500-card counts; the async lifecycle gate supplies the exact owner settlement evidence rather than faking async work with sleeps.

All 23 inherited-plus-corrected `HistoryStreamIntegrationTests` pass in 1.728 seconds, including every prior Module 01/04 held-startup/cancellation/revert contract.

### C12-04 concrete accessibility and keyboard harness

SwiftUI sidebar visuals now overlay one transparent concrete AppKit `NSButton` per navigation row. Each button is an unignored accessibility element with role `button`, explicit full title label, stable source-index identifier, selected property/value, full-row hit bounds, and native first-responder focus callback. The button handles Tab/Shift-Tab by visual raw order and Space/Return activation; the existing deterministic focus outline is driven by the same native focus callback.

The macOS XCTest process would not become the application key window even after safe `.regular` activation, so the allowed reliable-harness branch was used. A visible titled `NSWindow` hosts the actual sidebar and concrete AppKit nodes. The test finds exactly four unignored button nodes in order `Home`, the long Genuine title, `Panel View`, `Empty View`; initial selected properties are `[true, false, false, false]`. A real Tab key event (key code 48) moves the window first responder from row one to row two, and a real Space key event (key code 49) activates row two's exact identity. The live AX properties update to `[false, true, false, false]`. The harness passes in 0.260 seconds and prints a credential-free `MODULE12_AX` oracle. This proves the in-process AX tree, order, focus traversal, activation, labels, and selected state; the fresh verifier may additionally listen with VoiceOver but need not infer semantics from PNGs or static source.

### Correction release evidence and verdict

- Full suite: 196 tests executed, three authorized skips, zero failures in 84.894 seconds.
- Release build: PASS in 20.00 seconds; Core Graphics remains primary.
- Read-only live smoke: PASS in 5.365 seconds with three views, 22 top-level / 31 recursive cards, 66 rows, current-user ID present, registry 276 / 74 precision entries, representative one-hour 2,380 points, CO2/VOC one-hour 8,591 and 8,589 points, CO2/VOC 12-hour 102,736 points, and 24-hour 57,068 points. No state-changing call was made.
- GUI: all original nine plus both loaded-empty artifacts regenerated with valid 2x dimensions/signatures; focused and full-suite checks pass and manual inspection finds the sidebar, long title, focus, wide/narrow, panel, selected-empty, loaded-empty, and loading states coherent.
- Context checker: GREEN, 121 nodes / 901 edges, two cycles, zero unresolved, no truncation, fingerprint `520448b227d6950243f102ec6ed5a3bbee6b0e1e542d84b01b5b93ecaa1100a6`.
- Resolver self-test: PASS, 31 nodes / 61 edges, fingerprint `f9462562d7a09d8b37fea24ac7d8d9eebc7767fca7579bcedd489597a8a2ae18`.

Correction verdict: **GO to fresh independent re-verification**. The original NO-GO remains recorded above as history. Remaining verification risk is bounded to independently auditing the new generation/client guards and the concrete AppKit overlay/first-responder integration in the real app. There is no unresolved product, migration, token, renderer, identity, or performance decision, and Module 05 remains locked until the fresh verifier returns GO.

## Fresh independent re-verification

The fresh correction verifier's 2026-08-25 verdict is **GO**. Module 12 is complete at contract revision 1 and unlocks fresh Module 05 research under the fixed-server/no-profile assumption. The verifier inspected the complete Swift, test, fixture, configuration, manifest, generated-graph, and documentation diff from `a4dcd1c`, reran every previously failed gate, and found no material defect, evidence gap, migration question, or unauthorized scope expansion.

| Contract | Fresh independent result |
|---|---|
| C12-01 | GO: exact maintenance/subview/boolean/user filtering, raw preservation, unavailable-user fail-closed behavior, and live three-view shape are covered without identity mutation. |
| C12-02 | GO: exact resolved selection, source-order direct routes, duplicate/pathless/default fallback, and distinct never-loaded/zero-raw/all-ineligible/selected-empty states pass. Production config application sets the final loaded state for both zero-view cases. |
| C12-03 | GO: strict v1 property-list persistence, malformed/stale/ambiguous cleanup, final-primary-only writes, transient subview behavior, and no profile/server namespace pass. |
| C12-04 | GO: dynamic rows, title/icon modes, long-title/focus rendering, full-row hit targets, native AX nodes, keyboard traversal/activation, selected state, and the unchanged range selector pass. No settings/profile/personal rows remain. |
| C12-05 | GO: actual-default three columns, unrelated one-column native layout, panel first-card full width, empty state, raw card order, and wide/narrow resize rendering pass without identity churn. |
| C12-06 | GO: one owner tail, same-view retention, exact range re-keying, config/selection races, cancel-before-install, and exact final owner intersections pass. |
| C12-07 | GO: late acknowledgement/history/status/feed/render/detail results are generation- and exact-owner-rejected; hidden/removed owners settle with zero subscriptions, observers, mounts, coordinator work, and weak lifecycles. |
| C12-08 | GO: held A-B-A and A-B-C/latest-wins paths never publish the intermediate candidate and finish with one fresh exact owner without overlap. |
| C12-09 | GO: global state and connection status survive view navigation while view/detail histories retire; the fixed client is not reconnected for view selection. |
| C12-10 | GO: minimal `auth/current_user` decoding and nonfatal failure pass. Every bootstrap candidate, installed client/subscription/status task, state callback/flush, failure, cancellation, and disconnect path checks exact generation/client ownership. Same-client and distinct-client overlaps, byte-identical post-first-guard candidates, and installed-client replacement failure finish with the exact expected owner/disconnect counts; obsolete metadata/config/state/status cannot publish. |
| C12-11 | GO: refresh resolves only an unambiguous locator into a new exact identity, falls back when removed/ineligible, and never uses a hash, `contentRevision`, timestamp, or semantic ancestry. |
| C12-12 | GO: the genuine 10-view/500-card lifecycle and hosted-layout gates, full regressions, release build, artifacts, context graph, resolver, and authorized read-only live smoke are green. Core Graphics and the approved WebSocket/history/feed/coordinator/cache/range/tooltip/logging policies remain intact. |

Fresh exact validation:

- navigation/loaded-state tests: 11/11 in 0.021 seconds; bootstrap lifecycle: 9/9 in 0.414 seconds; history/navigation integration: 23/23 in 1.700 seconds; typed current-user command passed in the full suite;
- the production-tail lifecycle gate completed 100 exact view selections and 100 range replacements over 10 genuine views and 500 distinct resolved cards in 0.268 seconds. Before teardown it had exactly 50 active cards, one desired/ generation/subscription/feed/wire/delivery owner, one observer and mount, and zero startups or coordinator work. Final empty-config settlement had zero subscription, wire, delivery, feed-observer, mount, queued/in-flight render, retained visual, and weak-lifecycle ownership;
- the three-iteration hosted SwiftUI metric completed 100 warmed alternating 1792x1000/900x700 layout/display cycles per block across all ten selected models, 500 cards, and all `[1, 3, 6, 12]` ranges. Average monotonic clock and CPU time were both 0.746 seconds; average physical-memory delta was about 437 KB. Fixture/model construction stayed outside measurement and no sleep concealed work;
- the hosted-window accessibility test passed in 0.172 seconds with exactly four unignored native button nodes in raw order, labels `Home`, the long Genuine title, `Panel View`, and `Empty View`, full-row bounds, button roles, and selected values `[true, false, false, false]`. A synthesized key event moved the actual window first responder by Tab; Space activated the exact second identity; AX selected values became `[false, true, false, false]`. A disposable verifier probe compiled the exact production sources and sent Shift-Tab and Return through `NSWindow.sendEvent`; focus moved to the previous row and Return activated it even though the XCTest-style process was not the app key window. Thus inability to make that harness the system key app is not material to the responder, event-routing, or in-process AX-node proof;
- all 11 Module 12 PNGs regenerated with valid signatures. Sidebar selected, unselected-row, and focus captures are 476x1400; wide/genuine/panel captures are 3584x2000; narrow, selected-empty, loading, zero-raw, and all-ineligible captures are 1800x1400. The selected/unselected files intentionally preserve the same frame containing both states; the focus image is distinct. The verifier-generated contact sheet shows coherent source order, selected/focus treatment, long-title clipping, one- versus three-column layout, full-width panel, and distinct loading/selected-empty/loaded-empty presentations;
- full `swift test`: 196 tests, three authorized skips, zero failures in 84.263 seconds. This includes the complete Module 02 transport, Module 01 history, Module 04 model/presentation/identity, and relevant Module 09 coordinator/ cache regressions; the known hover expected-failure marker and separate stale-viewport fallback remain unchanged;
- production `swift build -c release --product NativeHAMac`: PASS in 7.57 build seconds (7.88 seconds wall time);
- read-only live smoke: PASS in 5.085 seconds with three views, 22 top-level / 31 recursive cards, 66 rows, current-user ID present, registry 276 / 74 precision entries, representative one-hour 2,385 points, CO2/VOC one-hour 8,582 and 8,584 points, CO2/VOC 12-hour 102,737 points, and 24-hour 57,067 points. Final command/subscription/wire/delivery/receive ownership was zero; no service call or HA state mutation occurred;
- Module 12 context checker: GREEN, 121 nodes / 901 edges, two cycles, zero unresolved, no truncation, fingerprint `520448b227d6950243f102ec6ed5a3bbee6b0e1e542d84b01b5b93ecaa1100a6`; resolver self-test: PASS, 31 nodes / 61 edges, fingerprint `f9462562d7a09d8b37fea24ac7d8d9eebc7767fca7579bcedd489597a8a2ae18`; and
- `git diff --check` passed. The prerequisite 02/01/04 generated checkers show only expected yellow NativeHA-anchor changes from this uncommitted Module 12 diff; their complete contract revisions and focused/full regressions remain green and their generated files were not modified.

No product or migration question is unresolved. Remaining bounded limitations are the documented native icon fallback and the separate Module 09 stale- viewport fallback; neither blocks Module 12. The exact next action is fresh Module 05 orchestration-decomposition research, assuming one fixed server and omitting profile-transition work. Do not begin Module 05 implementation before its own research-ready packet and independent ownership audit exist.

## Bounded post-Module 05 anchor maintenance — 2026-08-31

The pre-refresh checker was yellow for exactly nine shared Module 05 anchors: `HomeAssistantWebSocketClient.swift`, `Models.swift`, `CardViews.swift`, `DashboardView.swift`, `DashboardViewModel.swift`, `HomeAssistantHistoryLiveSmokeTests.swift`, `DashboardBootstrapLifecycleTests.swift`, `GUIRenderingAndPerformanceTests.swift`, and `HistoryStreamIntegrationTests.swift`. The exact accepted Module 05 diff and final independent evidence were inspected against C12 revision 1. The pinned frontend navigation/Lovelace/user sources and npm current-user command remain unchanged; no broad reference audit was repeated.

Module 05 moves installed raw/resolved/presentation dashboard storage into `LovelaceDashboardStore` and history dictionaries/tasks/subscriptions/feeds into `DashboardHistoryCoordinator`; the manifest now pins both explicit owners. `DashboardViewModel` retains the only config/navigation/range/history owner tail, exact selected resolved identity and locator reconciliation, cancel-before-install ordering, final-candidate persistence, and exact active- owner intersections. Cards that remain visible retain their owners; hidden or removed card startup, delivery, subscription, feed, mount/coordinator, and render ownership still retires before final publication. The shell/client/ model/test changes add explicit dashboard lifecycle, typed entity ownership, and stronger stop/retry/late-result evidence without reconnecting the fixed server for navigation or changing the approved range selector. No hash, `contentRevision`, endpoint timestamp, or semantic similarity establishes freshness, identity, or ancestry.

Regeneration is green at 121 nodes / 901 edges, two cycles, zero unresolved edges, no truncation, and fingerprint `7da15bb1b6167de2da299a4c7201fcbef6a452e6e0504e23f09aed7da4c83dd4`. The resolver self-test passes at 31 nodes / 61 edges with fingerprint `da06a3bfa032082ad19743e076372c8a73181f37d75f4f468b60395000afa13d`. The fresh final Module 05 verifier passed 360/360 race processes, the 237-test full suite with three authorized skips and zero failures, release, GUI, and authorized read-only live smoke with no state-changing call. No C12 observable contract changed, so status remains `complete` and contract revision remains 1. No Swift or test file was edited by this maintenance.

## Resolved questions, risks, and stop rules

Resolved product questions:

- Module 03 is intentionally skipped, not complete; fixed server/token bootstrap remains.
- No profile/settings UI or credential/token migration is part of Module 12.
- Maintenance duplication is path-exact; graph selector remains global.
- Route persistence stores only final eligible primary selection, without a profile namespace.
- User-list visibility uses optional current user ID and fails closed only for those views.
- Global state/status remain connected; view/card/detail ownership retires.
- Module 05 follows independently verified Module 12 and omits profile work.

No material product or migration question remains unresolved. Technical risks remain duplicate/pathless config churn, reentrant owner cancellation, native icon limitations, user metadata failure, and layout cost; the contracts and tests above bound each risk.

Stop implementation and return to research/user direction if:

- exact card/view identity is insufficient and a hash/timestamp/semantic ancestry heuristic appears necessary;
- a second owner-operation tail or overlapping old/new owner is proposed;
- current-user visibility would require storing/logging credentials or changing token bootstrap;
- persistence would need a profile/server namespace or a migration guarantee beyond the fresh v1 preference;
- unrelated views require changing the approved default-dashboard layout or graph-range product behavior;
- full URL/app routing, edit mode, settings/profile UI, or Modules 05-11 become necessary to make the bounded feature work; or
- any required lifecycle/release/live evidence cannot be made green.

## Final handoff

The implementation writer changed only these production files:

- `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`;
- `Sources/NativeHACore/Models.swift`;
- new `Sources/NativeHAMac/LovelaceViewNavigation.swift`;
- `Sources/NativeHAMac/AppConfig.swift`;
- `Sources/NativeHAMac/DashboardViewModel.swift`;
- `Sources/NativeHAMac/DashboardView.swift`.

The implementation test/documentation surface is:

- new `Tests/NativeHAMacTests/LovelaceViewNavigationTests.swift`;
- focused additions to `DashboardBootstrapLifecycleTests.swift`, `HistoryStreamIntegrationTests.swift`, and `GUIRenderingAndPerformanceTests.swift`;
- minimal core WebSocket client/connection tests for `auth/current_user`;
- the read-only live-smoke test extension for current-user identity presence;
- a deterministic Module 12 fixture under `Tests/Fixtures/Lovelace/`;
- `.build/render-artifacts/` runtime outputs, which are not committed; and
- `docs/configurability.md` plus this Module 12 packet/index/generated graph if implementation changes their recorded anchors/status/evidence.

Do not edit Module 03 or add settings/profile/token migration. Modules 12, 05, and 06 remain independently complete. Module 06 preserves source-row identities and adds no navigation owner. Module 07 current conditions preserve exact `card.nativeID` and add zero forecast ownership. The next staged action is Module 08 research only under the fixed-server/no-profile assumption.

## Research validation

- Pre-generation context check: expected `ENOENT` because no Module 12 graph existed.
- Initial generated graph: 121 nodes, 901 edges, zero unresolved, not truncated, fingerprint `2029b45105e24649341ec59dc5f68a571a643059b6efd9c01a3b00c1b2eb0475`.
- Post-generation context check: GREEN.
- Resolver self-test: PASS, 31 nodes, 61 edges, fingerprint `fa0fc2aa9b4855bf7f52040f5f7f20f8fb7f1f36693be7d9a22a89fa88f7afae`.
- Green prerequisite packets retained: Module 02 contract revision 2, Module 01 revision 3, and independently verified Module 04 revision 1.
- Independent read-only configuration/ownership audit verdict: GO after adding current-user runtime tracing, fail-closed user-list eligibility, one-tail ordering, global-versus-view ownership, exact-revert, persistence, and cache rules now recorded above.
- Post-Module 07 anchor graph: GREEN, 121 nodes / 901 edges, two cycles, zero unresolved, not truncated, fingerprint `ef465e6b1a114bd7c210c61b59237ce70718343255e993e33dc7f8b6612d9791`; resolver PASS at `26a89dfc1a88704dcb44a2fc97d2c5c41f20bacf0eb79f5816f20ecfb26e9372`.

## Change log

- 2026-08-25, contract revision 1: initial bounded research-ready packet after fixed-server decision and independent navigation/ownership audit.
- 2026-08-25, contract revision 1 unchanged: implementation evidence recorded; graph refreshed; status advanced to `verification-ready` pending a fresh independent verifier.
- 2026-08-25, contract revision 1 unchanged: fresh independent verification returned NO-GO for C12-10 bootstrap isolation, C12-02 zero-view presentation, C12-12 end-to-end performance evidence, and the unresolved C12-04 interactive accessibility gate. Status remains `verification-ready` pending bounded correction and a fresh verifier.
- 2026-08-25, contract revision 1 unchanged: the bounded correction addressed all four NO-GO findings; focused, full, release, read-only live, GUI, context, and resolver gates are green. Status remains `verification-ready` pending a fresh independent verifier; Module 05 remains locked.
- 2026-08-25, contract revision 1 unchanged: fresh independent re-verification passed every C12 contract and all four prior NO-GO gates. Status advanced to `complete`; fresh Module 05 research is unlocked under the fixed-server/no- profile assumption.
- 2026-08-31, contract revision 1 unchanged: pinned the extracted Lovelace and history storage owners, inspected all nine shared Module 05 anchors, and regenerated a green 121-node / 901-edge graph. Status remains `complete`.
- 2026-09-01, contract revision 1 unchanged: inspected the six shared Module 06 anchors, confirmed distinct source-row identity and unchanged view/card ownership, and regenerated a green 121-node / 901-edge graph. Status remains `complete`; Module 07 research only is next.
- 2026-09-08, contract revision 1 unchanged: inspected the Module 07 card projection/rendering anchors, confirmed exact `card.nativeID` and navigation ownership are unchanged, and regenerated a green 121-node / 901-edge graph. Status remains `complete`; Module 08 research only is next.
