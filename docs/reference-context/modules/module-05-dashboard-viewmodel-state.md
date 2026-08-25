---
schema: nativeha-evidence/v1
module: "05"
title: Dashboard orchestration decomposition and lifecycle state
plan: ../../rescue-plan/module-05-dashboard-viewmodel-state.md
status: research-ready
contract_revision: 1
depends_on: ["01", "02", "04", "12"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 983a41504b622c123708ba7473249d0b2edb7dbb
graph_file: ../generated/module-05.dependencies.json
graph_fingerprint: 8523f46cac0ffd523c0207e491dfcdb45eba1c2982cb88254d0edf7b4298786c
last_researched: 2026-08-25
---

# Module 05 evidence packet

## Gate and scope delta

This packet is the implementation authority for Module 05. Modules 02, 01,
04, and 12 are complete and green. Module 05 decomposes the current mixed
`DashboardViewModel`, makes dashboard lifecycle and retry state explicit, and
adopts the modern typed entity stream. It consumes the verified transport,
history, Lovelace identity, and navigation contracts; it does not redesign
them.

The user intentionally skipped Module 03. NativeHA targets one fixed personal
Home Assistant deployment, keeps the current token-file and server-candidate
bootstrap, and adds no profile switching, settings UI, credential migration,
or profile namespace. This is a durable product decision in
`docs/user-deviations.md`, not a claim that Module 03 is complete.

Research resolves these scope points relative to the rescue plan:

- the normal app state source becomes Home Assistant's typed
  `subscribe_entities` full/delta stream, not REST `/api/states` followed by
  `state_changed`; this closes the snapshot/event gap and handles removals;
- `dashboardOwnerOperationTail` remains the only config/navigation/range/
  history owner-operation tail. Extracted collaborators are synchronously
  driven by that MainActor owner and may not add an independently racing tail;
- entity display/name/icon/toggle *semantics* remain unchanged compatibility
  behavior until Module 06. Module 05 may move mechanical wrappers, but cannot
  widen toggle domains or claim frontend display parity;
- existing REST service calls and optimistic card behavior remain. Module 05
  adds task/error ownership and disables incompatible concurrent action, but
  never automatically retries a state-changing call;
- the existing raw Lovelace configuration, exact Module 04 identities, Module
  12 selection/persistence, global graph-range selector, Core Graphics primary
  renderer, and all approved transport/history/render/tooltip/logging policies
  remain unchanged; and
- the separate Module 09 stale-viewport fallback remains open and cannot be
  repaired by hash, `contentRevision`, or endpoint timestamp ordering here.

Modules 06-11, card redesign, full MDI semantics, WebSocket service migration,
Lovelace editing, profile work, and a Metal default are out of scope.

## Observable behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Required evidence |
|---|---|---|---|---|
| C05-01 | Dashboard is created, started, retried, disconnected, reconnected, or stopped | Publish a typed dashboard lifecycle (`idle`, `connecting`, `loading`, `ready`, `reconnecting`, `disconnected`, `failed`, `stopped`) and separate component phases/errors for bootstrap, entity state, Lovelace, realtime, and service work. History continues to expose its verified per-owner statuses. Usable installed data stays visible during partial failure and reconnect. | The typed values are authority; legacy `status`/`errorMessage` may remain only as computed compatibility projections. A new app generation is advanced synchronously before startup or stop. A component error cannot erase another component's valid data or silently promote the whole dashboard to ready. Credential-free errors are user-visible and diagnostics retain the owning component. | Transition matrix, invalid-transition assertions, retained-data tests, shell-state GUI artifacts. |
| C05-02 | Initial fixed-server bootstrap or `retryBootstrap()` | Read the existing token path, try the existing ordered `baseURLs`, fetch required REST config, create/connect one Module 02 connection, acknowledge required entity and Lovelace ownership, and install exactly one winning candidate. | Preserve Module 02 C02-08: a required candidate failure disconnects that candidate exactly once before the next; only the final generation may install. Optional entity-registry precision, locale, and current-user fetches are independent and nonfatal. A fatal retry first retires all currently installed app-lifetime ownership under C05-10. No token/server persistence or migration is introduced. | Existing candidate tests plus held-token/config/connect/subscription/optional-response and retry-generation tests. |
| C05-03 | The entity owner receives `subscribe_entities` payloads | Decode compressed additions/replacements (`a`), removals (`r`), and changes (`c`, with `+` field/attribute additions and `-` attribute removals) into one `HAEntityStore` mutation path. The first accepted payload for every owner generation is an authoritative full snapshot and atomically replaces the dictionary; later payloads apply exact deltas in wire-arrival order. | Add/replace, then remove, then change ordering within a payload matches pinned `entities.js`. Unknown-entity change entries are ignored with a bounded credential-free diagnostic, matching the reference. Context string/object and `lc`/`lu` conversion semantics are pinned. Malformed initial or delta payload fails that owner generation without partially publishing. Entity deletion is observable. No timestamp, hash, semantic equality, or `contentRevision` comparison decides freshness. | Pure full/add/replace/remove/field patch/attribute patch/context/time/unknown/malformed fixtures and mixed-payload ordering tests. |
| C05-04 | Initial connection, disconnect, reconnect, cancellation, or burst entity delivery | Own the typed entity stream through one `HAEntitySubscriptionCoordinator` using the verified Module 02 dispatcher with `resubscribe: false`. Initial/reconnect readiness creates exactly one fresh subscription generation and requires a fresh authoritative first snapshot. Retain the last accepted dictionary while disconnected/reconnecting, then replace it atomically when the fresh snapshot arrives. | The coordinator observes connection status and does not rely on Module 02 generic resubscription for this consumer. It synchronously invalidates the old generation before awaiting unsubscribe, rejects late acknowledgement/payload/status callbacks, and never overlaps old/replacement owners. Coalescing may bound MainActor publication but must preserve wire order and last operation per entity while retaining unrelated entities. `fetchStates()` remains available only for probes/tests/tools, not the app bootstrap path. | Fake dispatcher initial/reconnect/full-replace/late-old/cancel tests, one-owner counts, 10k full plus ordered 1k burst tests, and read-only live subscription smoke. |
| C05-05 | Lovelace bootstrap, `lovelace_updated`, reconnect, manual retry, or config error | A `LovelaceDashboardStore` owns the installed raw/resolved/presentation dashboard and component error. Fetch uses the existing dashboard URL/path. A server update or reconnect fetches a candidate and hands it to the one Module 12 owner tail for reconciliation; manual `retryLovelace()` forces a fresh fetch through the installed client. | Preserve exact Module 04 resolved identities and Module 12 locator/reconciliation rules. Update callbacks capture app/config generation; late fetches cannot install. Reconnect refresh is once per ready generation and keeps prior usable config on failure. Normal update/reconnect fetch does not force cache bypass; explicit retry does. No hash, `contentRevision`, endpoint time, source index, or semantic similarity proves ancestry/freshness. | Fake update/reconnect/force/error/A-B-C/A-B-A tests and raw/canonical identity assertions. |
| C05-06 | Config, selected view, effective range, reconnect, detail open/close, retry, or stop changes history ownership | Move current history dictionaries, statuses, startup generations/tasks, subscription handles, projections, and graph feeds behind a `DashboardHistoryCoordinator` façade without changing Module 01 or Module 12 behavior. Desired visible-card owners are still reconciled on the sole MainActor dashboard owner tail. | Detach obsolete startup/delivery ownership synchronously before any await; cancel-before-replace; recheck app/config/navigation/request generations and desired membership after every suspension. Module 01 core alone creates fresh subscriptions on reconnect; macOS must not duplicate that resubscribe. Accepted feed publication precedes `@Published` history, and final-only mount invalidation remains immediately before final presentation. Detail history retains separate exact ownership. | All green Module 01/12 held-ack/cancel/feed/mount tests, retry-active-only test, reconnect one-wire-owner test, and weak-release/zero-registry evidence. |
| C05-07 | Config/presentation transform or graph-range change | Keep raw Lovelace cards lossless and derive effective presentation/history requests separately. Preserve the one approved global 1h/3h/6h/12h selector, default-dashboard-only synthetic/hidden/three-column policy, exact active view cards, and Core Graphics renderer. | `DashboardViewModel` must not rewrite raw `hours_to_show` or contain personal entity IDs. Presentation/layout choices come from existing typed `AppConfig` surfaces. Range changes run through the same owner tail and replace only effective range-keyed history ownership. Every existing WebSocket, history, graph-feed, render-coordinator, tooltip, logging, range, scheduling, interaction, and cache policy value remains unchanged. | Raw-before/after equality, typed policy inventory, range/owner tests, existing Lovelace presentation/navigation/graph suites. |
| C05-08 | User invokes a currently supported card action | A `DashboardServiceController` owns each tracked REST service task and nonfatal service error while preserving current payloads, optimistic state mutation, and card-facing APIs. Disable a control when its entity is missing/unavailable or the same incompatible action is already in flight. | Only an intentional user action calls a state-changing service. There is no automatic retry after timeout/disconnect/error. Completion validates app generation and action token before optimistic/error publication; cancellation/stop prevents late mutation. One entity/action failure does not overwrite bootstrap/Lovelace/history errors. Module 06 decides future domain/display parity. | Exact REST body/payload tests, current optimistic behavior tests, unavailable/missing/in-flight gating, failure/cancel/late-result tests, and explicit assertion that retry/reconnect emits no service call. |
| C05-09 | A component fails and a retry API is invoked | Expose four scoped entry points: `retryBootstrap()`, `retryLovelace()`, `retryHistoriesForActiveView()`, and `reconnectRealtime()`. Each affects only its documented ownership domain except fatal bootstrap, which replaces the full app generation. | Lovelace retry uses the installed client and `force: true`; history retry replaces only active view/detail failed owners through the sole tail; realtime retry reconnects the installed Module 02 connection and lets C05-04/Module 01 create their one fresh owners; bootstrap retry performs C05-10 stop ordering then C05-02. Concurrent duplicate retries coalesce or become latest-wins by generation. No service retry. | Per-domain failure/retry matrix, duplicate button activation, held retry supersession, exact command/subscription counts. |
| C05-10 | Explicit stop, fatal restart, owner disappearance, or app termination | Provide an idempotent explicit `stop()`/restart boundary that owns and retires bootstrap, connection-status, entity, Lovelace-update/fetch, optional metadata, history/detail, service, feed/mount/coordinator, and installed REST/WebSocket tasks. `deinit` is a safety backstop, not the primary lifecycle mechanism. | Exact ordering: advance app/config/navigation generations and clear desired ownership; stop accepting callbacks; synchronously detach owner/startup/delivery registries; cancel/await captured bootstrap/config/entity/history/detail/service tasks; disconnect feeds/mounted graph lifecycles and cancel coordinator/render work; unsubscribe update/status owners; disconnect the installed WebSocket once; publish `stopped`. Late old callbacks/results cannot alter new or stopped state. Repeated stop is no-op-safe. | Held work at every layer, stop-during-bootstrap/reconnect/service, 100 start/stop/appear/disappear cycles, deallocation and exact zero-owner counts. |
| C05-11 | Shell renders initial load, full failure, partial failure, reconnecting, disconnected, ready, or empty data | Render explicit module-owned shell states: loading progress, full-page fatal error with retry, usable content plus component banner, reconnecting/disconnected banner over retained content, ready content, and controlled empty dashboard. | UI derives from typed lifecycle/components. Error/retry controls have accessible labels and keyboard focus. No card visual redesign or arbitrary animation is added. If transition animation is introduced, it must be deterministic and honor reduced motion; otherwise animation evidence is N/A. | 1200x800 dark 2x deterministic PNGs, semantic/accessibility assertions, manual comparison to frontend shell states. |
| C05-12 | Large full snapshot, burst deltas, config reconcile, view/range switch, or repeated lifecycle | Decode/prepare large immutable entity candidates outside MainActor, apply accepted results in one bounded MainActor publication, and keep owner/task/subscription cardinality bounded. | Background preparation captures immutable input and generation. Observable state/presentation publication and owner registry mutation remain MainActor-isolated. Coalescing never reorders wire operations or uses timestamp/hash freshness. Performance acceptance uses stored XCTest baselines and consumed results, not new tight millisecond constants. | 10,000-entity cold fixture, repeated 1,000-delta bursts, 500-card fixture, metrics separated by preparation/publication, 100-cycle memory/owner tests. |
| C05-13 | Launch or upgrade from the current release | Preserve the existing token file, fixed ordered server candidates, Module 12 preference key, and every approved `AppConfig` surface/value. Add no persistence key and perform no credential/config migration. | Tokens never enter new preferences, artifacts, screenshots, errors, or ordinary logs. The local deployment credentials remain authorized for read-only testing. A missing/unreadable token or exhausted candidate set is a fatal bootstrap error with retry, while optional metadata/config component failures remain scoped as above. | Configurability inventory comparison, fresh/existing preference fixtures, token missing/unreadable tests, artifact/log scan. |
| C05-14 | Implementation/release gate | Modules 02, 01, 04, 12, and the bounded Module 09 repair remain green; the dashboard starts, changes views/ranges, reconnects, retries scoped failures, and stops without duplicates or late mutation. | Live smoke is read-only: config/current-user/entity subscription/history/reconnect only. It must not call a service or mutate HA. Any unresolved product/migration choice, transport/history/identity regression, duplicate owner, old-generation publication, raw-config mutation, new freshness heuristic, Core Graphics demotion, credential artifact, or reliance on Module 06-11 is NO-GO. | Focused/full suites, checker/resolver, GUI/manual/performance/migration/release matrix, and read-only live smoke. |

Opaque monotonically increasing integers or UUIDs are permitted as runtime
lifetime generations. They may never become persisted identity, entity event
ordering, Lovelace ancestry, or cache freshness.

## Ownership boundaries

| Owner | Authoritative state | Lifetime | Must not own |
|---|---|---|---|
| `DashboardViewModel` (`@MainActor`) | Published shell state, app generation, installed collaborators, Module 12 selection, and the single `dashboardOwnerOperationTail` | Explicit `start` to `stop` | Entity decoding, duplicate history registries, display parity policy, transport receive loop |
| `DashboardLifecycle` | Pure permitted phase/component transitions and derived compatibility status/error presentation | App generation | Tasks, clients, subscriptions, cards |
| `HAEntityStore` | Immutable `[String: HAState]` snapshot plus accepted entity generation/revision | Installed entity owner generation | WebSocket reconnect, timestamps as freshness, UI presentation |
| `HAEntitySubscriptionCoordinator` | Entity subscription startup/delivery generation, unsubscribe handle, ordered decode/preparation task | Installed connection generation | Generic Module 02 resubscribe, history, service actions |
| `LovelaceDashboardStore` | Raw config, exact resolved dashboard, presentation candidate, Lovelace component phase/error | App/config generation | Selection ancestry heuristics, its own reconciliation tail |
| `DashboardHistoryCoordinator` | Existing history/detail requests, startup/delivery generations, statuses, projections, feeds, handles | Selected view/card/detail ownership under the dashboard tail | A second owner tail, reconnect resubscribe, renderer implementation |
| `DashboardServiceController` | Current supported REST service task tokens and service errors | App generation/action | Automatic retry, domain/display parity, optimistic truth beyond current behavior |
| Module 02 connection | One socket receive loop, command/subscription routing, status | Installed fixed-server connection | Entity/Lovelace/history product state |
| Module 01 history core | Wire history owner and reconnect generation | Exact history request owner | View selection and render publication |
| Module 12 navigation/presentation | Exact selected view/card identities, locator persistence, desired visible owners | Installed Lovelace snapshot and view selection | Server/profile identity or semantic reuse |

The history collaborator is intentionally named `DashboardHistoryCoordinator`
to distinguish its macOS ownership façade from the existing core
`HAHistoryStreamCoordinator`. It is synchronously mutated on MainActor by the
dashboard owner tail. An actor or queue may prepare data, but cannot decide
selection/config/range ownership independently.

## Typed entity stream contract

The wire command is `{ "type": "subscribe_entities" }`. Add minimal typed
decode shapes in `NativeHACore`; do not expose untyped dictionaries above the
WebSocket client. A payload may contain:

- `a`: entity ID to compressed full state (`s`, `a`, `c`, `lc`, optional `lu`);
- `r`: entity IDs to remove; and
- `c`: entity ID to a patch with optional `+` values (`s`, `a`, `c`, `lc`,
  `lu`) and optional `-` values (attribute keys in `a`).

For each accepted payload, clone/prepare from the last accepted generation
snapshot, process `a`, then `r`, then `c`, and publish once. The first payload
of a new subscription generation starts from an empty dictionary, making it an
authoritative replacement. A later unknown-entity patch is skipped and logged;
it does not invent a partial entity or fail unrelated changes. Any structural
decode failure rejects the entire payload. Cancellation or a generation change
between preparation and MainActor apply drops the candidate.

Match the pinned frontend conversion rules: `lc` is seconds since epoch and
sets both `last_changed` and, when `lu` is absent, `last_updated`; `lu` sets
`last_updated`; a context string replaces the context ID while a context object
supplies the decoded context. Attribute additions merge and named removals
delete. Do not compare those times to decide whether a payload is stale: the
socket's delivery order plus subscription generation is the ordering source.

The current `REST /api/states` plus `state_changed` sequence cannot prove that
an event between snapshot and acknowledgement was observed, and the current
callback drops `new_state == nil` deletion. It is therefore removed from the
normal app path. `HomeAssistantRESTClient.fetchStates()` remains intact for
read-only probes and tests. This is a bounded consumer migration, not a Module
02 transport redesign; other generic subscriptions retain their existing
reconnect policy.

## Startup, reconnect, retry, and stop state machines

### Startup

1. On MainActor, advance app/config/navigation and component generations,
   publish `connecting`, and capture the fixed bootstrap inputs.
2. Read the current token file and try ordered `AppConfig.baseURLs`. For each
   candidate, fetch required REST config, construct/connect one Module 02
   connection, and construct typed clients/collaborators. On a required failure,
   disconnect the candidate exactly once before continuing.
3. Start the required `subscribe_entities` owner with `resubscribe: false` and
   obtain its acknowledgement. Fetch/decode Lovelace config. Start independent
   optional current-user, entity-registry precision, and frontend-locale work.
4. Accept the entity owner's first full payload and prepare Lovelace presentation.
   Required acknowledgement/config failure rejects the candidate. Optional
   failures populate their own diagnostics/defaults.
5. Only the final app generation installs the clients, global status/entity/
   Lovelace-update owners, raw/resolved dashboard, and optional results. Hand
   Lovelace selection/history activation to the existing Module 12 owner tail;
   do not bypass it from the bootstrap task.
6. Publish `ready` when installed required data and owners are live. A later
   component failure yields retained usable content plus its component state,
   not a destructive blank dashboard.

No permanent install may occur before the required subscription acknowledgement
and Lovelace/config validation. Tests may gate the first entity payload; a
bounded command/subscription timeout is the existing Module 02 policy, and this
module adds no new hidden retry timer.

### Reconnect

On connection loss, publish `reconnecting` or `disconnected`, retain last
accepted entities/config/presentation, and synchronously invalidate the entity
owner generation. Module 01 history owners independently observe the same
connection status and create their verified fresh wire owners. On each new
connection `ready` generation:

1. create exactly one fresh `subscribe_entities` owner and require its first
   full snapshot before replacing retained entity state;
2. fetch Lovelace once with normal (not forced) semantics to cover missed
   updates, and let its update subscription resume normally;
3. do not ask the macOS history façade to resubscribe what Module 01 already
   owns; and
4. clear reconnect component errors only for generations that successfully
   revalidated.

A reconnect may keep content usable while revalidation is pending. If entity
or Lovelace revalidation fails, keep the last accepted data with a scoped
error/retry surface. A subsequent ready/retry generation may recover it.

### Retry matrix

| Entry point | Retires/starts | Preserves |
|---|---|---|
| `retryBootstrap()` | Full C05-10 stop, then fixed candidate bootstrap | Typed policies and Module 12 persisted selection |
| `retryLovelace()` | One forced config fetch on installed client, then Module 12 reconcile | Connection, entities, current histories until final reconcile |
| `retryHistoriesForActiveView()` | Failed/missing active view and current detail history owners through the one owner tail | Entities, config, selection, successful unchanged owners |
| `reconnectRealtime()` | Installed connection reconnect; entity and core history owners follow their documented ready generations | Retained accepted data/config/selection |

### Stop/restart

`stop()` is explicit and idempotent. Before the first suspension it advances
all relevant generations, clears desired active ownership, stops accepting
callbacks, detaches registries/handles/tasks, and captures everything to cancel.
It then cancels and awaits bootstrap/config/entity/history/detail/service work,
disconnects feeds/mounts and resets coordinator/render generations, removes
status/update subscriptions, disconnects the installed socket exactly once,
and publishes `stopped`. Restart begins only after that barrier. `deinit` may
call a nonawaiting emergency cancellation path, but view/app lifecycle must
invoke `stop()` explicitly.

## Configuration, persistence, credentials, and migration

Module 05 adds no settings UI or new preference. It preserves the approved
`AppConfig.swift` inventory recorded in `docs/configurability.md`:

- fixed `tokenFilePath` and ordered `baseURLs`;
- Core Graphics `graphRenderEngine` and graph time-range, max-zoom, scheduling,
  interaction, tooltip, and render/cache policies;
- WebSocket command/subscription/reconnect and logging policies;
- `showEntityIDsByDefault`;
- Module 12 navigation exclusion and selection-persistence policy;
- default-dashboard hidden/extra entity, layout/card-column, and climate
  preset/product presentation policies.

Implementation may group existing presentation/layout scalars into a typed
policy only if every value and scope remains identical and
`docs/configurability.md` is updated in the same commit. It may not introduce a
new timeout, profile/server chooser, keychain decision, service retry, renderer,
or freshness policy by convenience.

There is no migration: keep the current token file and fixed candidates; keep
Module 12 key `nativeha.navigation.selected-primary-view.v1`; add no entity,
config, lifecycle, or credential persistence. Errors/logs/artifacts refer to a
candidate index/component, not the bearer token. The local HA deployment and
credentials are authorized for read-only verification, but no state-changing
live service call is allowed.

## Reference anchors

All frontend anchors are pinned to clean hass-frontend revision
`dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`. The checkout uses TypeScript
`6.0.3`; `yarn.lock` SHA-256 is
`ca345f66a74a1054b77bd2f47f20cb9e13e79b2c864f3375822cca9b14ff41b6`.
The injected package is `home-assistant-js-websocket@9.6.0`, package JSON
SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`.

| Behavior | Complete anchor and symbol/line hint | SHA-256 / git blob |
|---|---|---|
| Connection startup, calls, reconnect/disconnect state | `src/state/connection-mixin.ts`: `connectionMixin` 48, initialize 54, `callService` 98, connected 231, reconnected 368, disconnected 388 | `ed4c83f57d1…` / `a6b0beefb0b3…` |
| Lovelace load/error/retry/update/reconnect | `src/panels/lovelace/ha-panel-lovelace.ts`: phase/render 67-116, update/retry/reconnect 233-374 | `79c022d29059…` / `adb398de1f2d…` |
| Lovelace installed configuration and view ownership | `src/panels/lovelace/hui-root.ts`; `views/hui-view.ts`; `views/hui-masonry-view.ts` | `b0d88e019b04…` / `f851fa…`; `7050ef76d095…` / `0503ad…` |
| Lovelace update collection and force fetch | `src/data/lovelace.ts`: subscription/collection 49-70; `src/data/lovelace/config/types.ts`: `fetchConfig` 31 | `aa8d12f35f54…` / `98ed39…`; `49abac69abfc…` / `3735c8…` |
| History connected/disconnected owner lifecycle | `src/panels/lovelace/cards/hui-history-graph-card.ts`: lifecycle/subscription/error/loading 49, 135-174, 236, 290-358 | `f20a8c88f513…` / `9b6bb3…` |
| Full/delta entity application and modern/legacy boundary | `home-assistant-js-websocket@9.6.0/dist/entities.js`: `processEvent` 4, `subscribeUpdates` 76, `entitiesColl` 103, `subscribeEntities` 106 | `e29222ee8551dfcde7d6abea2d1b3f82237fef2cc5b346de715bf1bafaac448d` |
| Shared collection setup/teardown/reconnect | package `dist/collection.js`: `getCollection` 13, refresh 29, setup 36, teardown 58, subscribe 92 | `e558c8bc30820acd693807d4f96a3a5b8b09f415147038ca1464df8a1c2f3ce8` |
| Collection state publication | package `dist/store.js`: `createStore`, overwrite publication and subscriber notification | `37d153b62fef698c78fb35bdd7dc26014fccf9169942124d770394c0c0b739a4` |
| Socket reconnect/subscription transport | package `dist/connection.js`: close 66, socket 145, reconnect 210, close 223, subscribe 291 | `884929a38078cc51cb47b0d7d8a821ef99bc784bcd50792bf9b044f936db69e8` |
| Service call message/command crossing | package `dist/commands.js`, `dist/messages.js`; `src/data/service.ts`; toggle helpers/component | `88685ebfab73…`; `5de87c3bf012…`; `e6fb93d…`; `3c6322…`; `711dda…`; `026b61…` |
| Entity display/name/domain/toggle semantics reserved for Module 06 | `compute_state_display.ts`, `compute_state_name.ts`, `compute_domain.ts`, `can_toggle_domain.ts`, `can_toggle_state.ts` | `6ae38a…`; `541b48…`; `3965f3…`; `d65df7…`; `feb392…` |
| Shell loading/error surfaces | `src/layouts/hass-loading-screen.ts`; `hass-error-screen.ts` | `8c2cff…`; `1d33fb…` |

`connection-mixin.ts` was read completely and is pinned manually. It is not a
graph seed because its static import of build-generated translation metadata is
absent from the source checkout and would create one nonbehavioral unresolved
edge. The runtime crossings named above remain explicitly covered.

## Dependency traces and boundaries

The generated graph contains 130 nodes, 811 edges, one recorded frontend
editor/card import cycle, zero unresolved edges, and no truncation. It follows
runtime and type imports to depth one and explicitly follows
`home-assistant-js-websocket`; the packet's complete manually reviewed anchors
resolve product behavior beyond candidate discovery.

- Dashboard/config trace: `ha-panel-lovelace.ts` -> `src/data/lovelace.ts` ->
  config types and WebSocket collection behavior. Stop at editor/UI element
  construction after confirming lifecycle/update/error semantics.
- Entity trace: package `entities.js` -> `collection.js` -> `store.js`, plus
  `connection.js`, commands, and messages. This runtime package boundary is
  entered because full/delta and reconnect ownership are not implemented in
  hass-frontend source itself. Stop after exact stream application,
  subscription, reconnect, and publication behavior.
- History trace: `hui-history-graph-card.ts` into frontend history helpers,
  then NativeHA Module 01 anchors. Stop at the already verified core history
  contract; Module 05 moves the macOS façade only.
- Service/display trace: entity toggle component -> Lovelace toggle helpers ->
  service data, plus display/name/domain helpers. Stop at the Module 06 semantic
  boundary; Module 05 preserves current native compatibility behavior.
- Native trace: current `DashboardViewModel` through REST/WebSocket clients,
  Module 01 coordinator, Module 04 models, Module 12 navigation/presentation,
  and graph scheduling/rendering. Graph rendering is evidence-only and not a
  permitted implementation target.

Use the linked graph for exact node hashes and edge phases; do not expand this
packet into a duplicate graph.

## Native anchors and mapping

Native research anchors are pinned to `main` revision
`983a41504b622c123708ba7473249d0b2edb7dbb`, the independently verified Module
12 commit.

| Contract | Existing/planned Swift path | Research SHA-256 | Symbol/type and ownership |
|---|---|---|---|
| C05-01, C05-02, C05-05..10 | `Sources/NativeHAMac/DashboardViewModel.swift` (`DashboardViewModel` 5, owner tail 44, navigation 440, history load 1325) | `38098add14acd51df719cde2a0b7b527ab59f1a2b5990765058fe574ab005d53` | Shrink to MainActor lifecycle/orchestration/published façade; preserve public APIs while card modules still consume them. |
| C05-01 | New `Sources/NativeHAMac/DashboardLifecycle.swift` | N/A | Pure typed lifecycle/component phases, failure state, and transition validation. |
| C05-03, C05-04 | New `Sources/NativeHAMac/HAEntityStore.swift`; new `HAEntitySubscriptionCoordinator.swift` | N/A | Pure state application plus app-lifetime subscription generation/ordered preparation. |
| C05-03, C05-04 | `Sources/NativeHACore/Models.swift`; `HomeAssistantWebSocketClient.swift` | `bdd7689c372c…`; `c2a3a189701e…` | Minimal typed compressed event/patch models and `subscribeEntities(resubscribe:false)` API. Preserve current APIs for probes/tests. |
| C05-04, C05-10 | `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift` | `0482c187bb52…` | Consume verified status/subscription/cancellation seams; change only if a narrowly proven typed-client seam is impossible otherwise. No transport redesign. |
| C05-05 | New `Sources/NativeHAMac/LovelaceDashboardStore.swift` | N/A | Raw/resolved/presentation candidate and scoped component state; no independent tail. |
| C05-06 | New `Sources/NativeHAMac/DashboardHistoryCoordinator.swift`; existing `HomeAssistantHistoryStream.swift` | N/A; `fbaf6d5bad0a…` | Move macOS registries/façade; do not alter verified core coordinator semantics. |
| C05-07 | `Sources/NativeHAMac/LovelacePresentation.swift`; `LovelaceViewNavigation.swift`; `AppConfig.swift` | `074c6d454d3f…`; `20cde182e49d…`; `67a415fef75e…` | Preserve exact resolved identity, selection/persistence, effective range, and approved typed policies. |
| C05-08 | New `Sources/NativeHAMac/DashboardServiceController.swift`; existing `HomeAssistantRESTClient.swift` | N/A; `954c494e8eef…` | Current REST payload and optimistic behavior with explicit action task/error ownership. |
| C05-11 | `Sources/NativeHAMac/DashboardView.swift`; narrow call-site updates in `CardViews.swift` | `b66aa911ba2d…`; `23fffc4f8411…` | Shell state and stable compatibility façade consumption only; no card redesign. |
| C05-06, C05-07, C05-10, C05-12 | `GraphRenderScheduling.swift`; `GraphRendering.swift` | `6bca525704f5…`; `6fdeb14608f5…` | Preserve feed/mount/coordinator/cache/Core Graphics contracts. Evidence/test anchor only unless a compile-only API move is unavoidable. |

## Decisions and native deviations

| ID | Decision/deviation | Allowed reason | Preserved semantics | Test/status |
|---|---|---|---|---|
| D05-01 | Adopt typed `subscribe_entities` rather than retain the REST snapshot plus `state_changed` app path. | Reference parity and correctness: current frontend package uses full/delta ownership; current path has a race and drops deletion. | One global same-server entity dictionary, ordered updates, reconnect refresh, Module 02 transport. | C05-03/04; resolved. |
| D05-02 | Opt this subscription out of generic Module 02 resubscribe and coordinate a fresh full snapshot explicitly. | Native ownership clarity and generation safety. | Exactly one fresh owner on each ready generation; other subscription behavior unchanged. | Reconnect/owner-count tests; resolved. |
| D05-03 | Retain accepted config/entities during reconnect and component failure. | Native shell usability consistent with frontend retained state. | Revalidation/error is visible; old generation cannot mutate retained/new data. | Shell and late-result tests; resolved. |
| D05-04 | Preserve current entity helper semantics until Module 06 even though researched frontend domains are broader. | Staged module boundary. | No accidental card behavior expansion; compatibility APIs remain. | Existing card tests plus delegation assertion; resolved limitation. |
| D05-05 | Keep REST state-changing service transport and current optimistic behavior. | Bounded decomposition; WebSocket service parity is not required. | Existing user action/payload/result behavior, now with cancellation/error ownership. | Exact payload/optimism tests; resolved. |
| D05-06 | Keep one MainActor dashboard owner tail instead of giving extracted collaborators their own serialization actors. | Required preservation of Module 12 cancellation/publication ordering. | Latest-wins config/view/range/history behavior and exact owners. | Held-tail integration suite; resolved. |
| D05-07 | Add no persistence or migration. | User-approved fixed personal deployment. | Current token bootstrap and Module 12 selection preference. | Migration/config inventory; resolved. |

## Required verification evidence

### Offline deterministic unit and integration

- Lifecycle: every permitted startup/partial/ready/reconnect/disconnect/failure/
  retry/stop transition, component-error independence, and compatibility string
  derivation from typed state.
- Entity store: authoritative full snapshot, add/replace/remove, `+` field and
  attribute merge, `-` attribute removal, context string/object, `lc`/`lu`,
  unknown patch, malformed payload atomicity, mixed-operation ordering, late
  generation, cancellation, and ordered coalescing.
- Bootstrap: all existing Module 02 candidate/failure/disconnect-once tests,
  required acknowledgement and first snapshot gates, optional metadata
  independence, late results, and retry after installed/partial/fatal states.
- Lovelace: raw preservation, exact Module 04 identity, normal update/reconnect
  versus forced retry, retained failure, and Module 12 A-B-C/A-B-A/reorder/
  removal/duplicate-path reconciliation.
- History/render: the complete green Module 01 and 12 held acknowledgement,
  cancel-before-replace, feed-before-publish, final-only mount invalidation,
  detail, range, reconnect, coordinator, and late-completion suites.
- Services: exact existing REST requests and optimistic mutations, action-token
  gating, missing/unavailable/in-flight disable, isolated error, stop/cancel,
  and no implicit retry.
- Stop/restart: held bootstrap/status/entity/config/history/detail/service/render
  work, idempotent stop, fresh restart, exact zero registries, and old callback
  rejection.

Use fake REST inputs, the Module 02 dispatcher, injected preference storage,
cancellable gates, deterministic clocks, and fixture data. Offline tests may
not read the real token or depend on network timing.

### GUI and manual

At fixed `1200 x 800` logical size, dark appearance, scale `2`, fixed time,
`en_US_POSIX`, and explicit `Asia/Shanghai` where supported, render initial
loading, fatal error/retry, usable partial banner, ready, reconnecting with
retained content, disconnected/retry, and empty dashboard. Use the existing
AppKit offscreen capture path and write descriptive PNGs to
`.build/render-artifacts/`; assert signature, dimensions, nonblank regions,
settled semantic state, accessible labels, and keyboard focus. Card pixels are
not owned here.

Manually compare only the shell lifecycle/error/retry behavior with pinned
hass-frontend. Confirm Home appears once, maintenance duplicate paths remain
absent from primary navigation, the approved selector changes 1h/3h/12h
effective ranges without raw mutation, view switching retains/cancels exact
owners, and disconnect/recovery creates no duplicate rows/samples/owners.
If Module 05 adds no animation, animation and reduced-motion visual evidence is
explicitly N/A.

### Performance and lifecycle

- Prepare a 10,000-entity full payload and repeated 1,000-delta bursts outside
  measured blocks. Measure decode/preparation separately from the bounded
  MainActor apply/publication and consume final counts/values.
- Reuse a deterministic 500-card dashboard for warmed config/view/range owner
  reconciliation. Preserve raw config and exact identities.
- Run at least 100 fake start/stop, appearance/disappearance, view/range,
  disconnect/reconnect, and retry cycles. Assert exact connection/subscription/
  task/feed/mount/coordinator counts return to baseline, weak owners release,
  and memory does not trend upward.
- Use XCTest clock/CPU/memory metrics and stored platform-labelled baselines;
  do not add tight elapsed-time product constants, arbitrary sleeps,
  `ImageRenderer`, `XCTHitchMetric`, or a nonexistent XCUITest target.

### Migration, release, and read-only live smoke

- Prove no new preference key, keychain use, token rewrite, server profile, or
  bootstrap migration. Existing valid/malformed Module 12 selection preference
  behavior remains green. Compare the complete `AppConfig` typed inventory and
  values with `docs/configurability.md`.
- Run focused core/macOS suites, then the full suite and all existing Module
  02/01/04/12/09 gates. Run Module 05 context checker and resolver self-test at
  implementation and verification handoff.
- Live smoke may read REST config/current user, connect, receive the first
  `subscribe_entities` full snapshot and passive deltas if naturally emitted,
  load Lovelace, open history streams, switch view/range, reconnect, and verify
  final cleanup. It must use bounded waits and must not call a service, toggle
  an entity, or otherwise mutate HA.
- Scan logs, errors, PNGs, generated docs, and committed fixtures for tokens.
  The local endpoint itself need not be redacted.

## Exact implementation handoff

Implement in this order with a single implementation writer, then dispatch a
fresh independent verifier:

1. Re-run this graph's checker and the resolver. Do not repeat broad research
   while anchors are green.
2. Add the typed entity full/delta wire models/client API and pure
   `HAEntityStore`; prove C05-03 before changing dashboard bootstrap.
3. Add `HAEntitySubscriptionCoordinator` with explicit
   `resubscribe: false`, first-full/reconnect/cancel/late-generation tests.
4. Add pure typed lifecycle/component state and make compatibility display
   strings projections rather than authority.
5. Extract `LovelaceDashboardStore`, `DashboardHistoryCoordinator`, and
   `DashboardServiceController` mechanically. Preserve behavior and the sole
   owner tail; keep Module 06 helpers behavior-identical.
6. Rewire startup/reconnect/retry/stop in `DashboardViewModel`, then prove all
   held-task and exact-owner integration contracts before shell changes.
7. Render the typed shell states in `DashboardView` with narrow card call-site
   changes only. Preserve raw/presentation/navigation/range/render policy.
8. Run unit/integration/lifecycle/GUI/performance/migration/release/read-only
   live evidence. Inspect the exact diff, run full inherited gates, commit, and
   hand to an independent verifier. Stop after Module 05.

Permitted production files:

- `Sources/NativeHACore/Models.swift`
- `Sources/NativeHACore/HomeAssistantWebSocketClient.swift`
- `Sources/NativeHACore/HomeAssistantWebSocketConnection.swift` only for a
  narrow typed-client seam proven necessary by tests; no transport redesign
- `Sources/NativeHAMac/DashboardViewModel.swift`
- `Sources/NativeHAMac/DashboardView.swift`
- `Sources/NativeHAMac/CardViews.swift` only for compatibility call sites
- `Sources/NativeHAMac/AppConfig.swift` and `docs/configurability.md` only if
  existing policies are regrouped without value/semantic change
- new `Sources/NativeHAMac/DashboardLifecycle.swift`
- new `Sources/NativeHAMac/HAEntityStore.swift`
- new `Sources/NativeHAMac/HAEntitySubscriptionCoordinator.swift`
- new `Sources/NativeHAMac/LovelaceDashboardStore.swift`
- new `Sources/NativeHAMac/DashboardHistoryCoordinator.swift`
- new `Sources/NativeHAMac/DashboardServiceController.swift`

Permitted tests are focused additions/updates under
`Tests/NativeHACoreTests/` and `Tests/NativeHAMacTests/`, including new
`HAEntityStoreTests.swift`, `DashboardLifecycleTests.swift`,
`DashboardOrchestrationTests.swift`, and `DashboardServiceControllerTests.swift`.
Generated `.build/render-artifacts/` are evidence, not committed source unless
the existing reviewed reference-image policy explicitly approves a baseline.

Do not edit `GraphRendering.swift`, `GraphRenderScheduling.swift`, Module 04
identity models, Module 12 locator/persistence semantics, or Module 01 history
core merely to simplify extraction. A compile-only seam outside the permitted
list, a new typed configuration value, or a behavior change requires stopping
and returning to research/user approval.

## Resolved questions, risks, and stop rules

Resolved product/architecture questions:

- fixed server/token bootstrap is retained with no migration or settings;
- modern `subscribe_entities` full/delta is the state authority;
- each reconnect uses a fresh explicit entity owner/full snapshot;
- accepted data is retained through reconnect/component failure;
- Module 12's owner tail remains the sole reconciliation sequencer;
- display/toggle parity waits for Module 06;
- current REST service/optimistic behavior stays and never auto-retries;
- no new persistence, config policy, renderer, or freshness heuristic is
  needed.

No material product, token-storage, migration, or bootstrap question remains
open. Known implementation risks are breadth of the current 1,946-line view
model, accidentally duplicating Module 01 reconnect work, incorrect compressed
patch decode, partial publication of malformed payloads, a second hidden owner
tail, and task retention during stop. The ordered extraction/tests above bound
them; they are not product ambiguities.

Stop and return to research or the user if implementation would require:

- changing fixed server/token storage, candidate ordering, credentials, or
  migration guarantees;
- weakening required bootstrap acknowledgement/disconnect-once behavior;
- choosing REST snapshot/event ordering instead of the contracted typed stream;
- adding/altering an `AppConfig` policy or changing current service/card
  behavior beyond the stated mechanical ownership work;
- modifying exact Lovelace identity, navigation persistence, global range,
  history/feed/render/coordinator semantics, or Core Graphics primacy;
- inferring freshness/ancestry from hashes, timestamps, source index, or
  `contentRevision`;
- making a live state-changing call; or
- beginning Module 06-11 work.

## Handoff

Verdict: **research-ready** at contract revision 1. The exact next action is a
single-writer Module 05 implementation beginning with C05-03 typed entity
models/store tests, followed by C05-04 subscription ownership, then lifecycle
and mechanical collaborator extraction. Independent verification is required
after implementation; no later module may begin in the same gate.

## Change log

- 2026-08-25: Research revision 1 pins fixed-server scope, modern typed entity
  ownership, explicit lifecycle/retry/stop contracts, Module 12 single-tail and
  Module 01 publication/reconnect preservation, exact evidence matrix, and
  bounded implementation files/order.
