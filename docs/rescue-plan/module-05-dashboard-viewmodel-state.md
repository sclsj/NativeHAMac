# Module 05 - DashboardViewModel Logic, State Ownership, and Loading Lifecycle

## Purpose

Turn `DashboardViewModel` from a large mixed coordinator into a predictable application-state layer that can safely compose:

- Lovelace views and cards.
- HA entity states and service calls.
- WebSocket subscriptions.
- Configured graph history ranges.
- The fixed server/bootstrap plus typed `AppConfig` policies.
- Error, retry, and loading states.

This module should not be treated as a visual redesign. It is the integration
layer that lets Modules 01, 02, 04, 06, 07, 08, and 12 work without duplicating
business rules across SwiftUI views. Module 03 is intentionally absent.

## Current-Code Findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`:

- `selectedGraphHours` is bare global view-model state, and `cleanCards(_:)` rewrites decoded `history-graph` cards with it. The approved selector remains global by default, but it must come from a typed `AppConfig` policy without mutating raw Lovelace values.
- `homeView` returns only the first Lovelace view or the view marked `default_view`. The live `3h` and `12h` views are maintenance duplicates, so rendering the intended Home view once is correct once its configurable range selector is wired properly.
- `dashboardColumns` is based on `AppConfig.columnRules`. That three-column composition is an approved default-dashboard deviation, but the layout values need one typed `AppConfig` policy instead of distributed constants.
- `load()` fetches REST states, fetches Lovelace through WebSocket, then starts state subscriptions on the same WebSocket client. This depends on the broken single-reader WebSocket architecture described in Module 02.
- `loadHistories(for:)` uses REST history and receives the card list after destructive `cleanCards(_:)`; the effective global range should instead come from the typed policy.
- `historyKey(entityID:hours:)` includes the global hours value. This is usable as a cache key once the input comes from the effective `AppConfig` selector policy.
- `historyEntityIDs(for:)` filters through `AppConfig.hiddenEntities`, which mixes server/user policy into core Lovelace rendering.
- `displayState(for:)`, `displayName(for:)`, `domain(of:)`, and `canToggle(_:)` duplicate rules that should be centralized and aligned with HA frontend helpers.
- `canToggle(_:)` currently recognizes only `switch`, `fan`, `input_boolean`, and `automation`. HA frontend also treats domains such as `light`, `group`, `humidifier`, and `valve` as toggle-capable when the entity is available.
- There is no clear retry model. A failed Lovelace load, failed history load, and failed realtime subscription all collapse into limited console/error behavior.
- Module 12 owns cancellation for obsolete history requests when switching
  views. Module 05 must preserve that boundary while decomposing reconnect and
  dashboard-lifetime ownership; profile switching is intentionally absent.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- Many views call back into `DashboardViewModel` for formatting, toggling, and selection. This is workable only if the view model exposes stable helper APIs rather than ad hoc per-view behavior.

## Superseded Findings After Modules 02 And 01

Several original findings above are historical and must not drive new work:

- The WebSocket transport now has one receive loop with routed command and
  subscription ownership; Module 05 must consume that verified API rather than
  replace it.
- Dashboard and detail history now use typed `history/stream` subscriptions,
  generation checks, explicit cancellation, per-owner status, and stable keys.
  REST history remains tool/benchmark-only.
- Visible history cards publish accepted projections through per-card
  `GraphHistoryRevisionFeed` instances before `@Published` invalidation, and
  charts use generation-scoped serial render coordinators. Extracting a
  `HistoryCoordinator` must preserve this accepted-publication boundary and
  must not regress to SwiftUI-body-driven revision delivery.
- The global graph range already comes from typed `GraphTimeRangePolicy`; raw
  Lovelace `hours_to_show` remains preserved. Module 05 should move ownership,
  not redesign that approved policy.
- Startup also fetches entity-registry display precision and frontend locale
  preferences for graph tooltip formatting. Profile/bootstrap extraction must
  retain their independent failure handling and injected test seams.

The remaining Module 05 work is orchestration decomposition, explicit loading
and retry state, preservation of Module 12 active-view ownership, and
entity/display/service collaborators. Module 03 is intentionally skipped, so
there is no profile-transition cleanup. Research must refresh all current-code
line hints before implementation.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/hui-root.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/views/hui-view.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/views/hui-masonry-view.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-history-graph-card.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_display.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_name.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/can_toggle_domain.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_domain.ts`

## Target Architecture

`DashboardViewModel` should become a thin owner of app state and orchestration. Heavy logic should move into small, testable collaborators.

Recommended ownership:

- `DashboardViewModel`
  - Owns published UI state.
  - Starts and stops app-level tasks.
  - Selects the active Lovelace view.
  - Routes service requests to the API layer.
  - Reports loading and error states.
- `HAEntityStore`
  - Owns `[String: HAEntityState]`.
  - Applies full state loads and `state_changed` events.
  - Exposes entity lookup and sorted/filter helpers.
- `LovelaceDashboardStore`
  - Owns decoded Lovelace config.
  - Provides active view and card list.
  - Preserves view path/title/visibility metadata from Module 04.
- `HistoryCoordinator`
  - Owns visible-card history subscriptions after Modules 01 and 02.
  - Keys history by entity set plus the effective selected range and relevant options.
  - Cancels obsolete subscriptions.
- `EntityDisplayFormatter`
  - Owns state display, name display, units, device classes, timestamps, and unavailable handling for Modules 06 and 10.
- `ServiceController`
  - Encapsulates calls such as toggle, climate target temperature, fan percentage, and automation trigger.
  - Keeps REST service-call behavior initially, but has one clear place to move to WebSocket `call_service` later.
- Fixed bootstrap ownership
  - Keep the existing server URL candidates and local token-file path without
    adding a profile model, migration, switching, or settings UI. Approved
    product and presentation policies remain typed in `AppConfig.swift`.

## Implementation Tasks

1. Add explicit loading phases.
   - Suggested enum: `.idle`, `.loadingStates`, `.loadingLovelace`, `.subscribing`, `.ready`, `.failed`.
   - Keep separate error slots for states, Lovelace config, history, and realtime subscription so one failure does not hide the others.

2. Extract entity state storage.
   - Move direct mutation of `states` into an `HAEntityStore` type.
   - Add `applyInitialStates(_:)`.
   - Add `applyStateChanged(entityID:oldState:newState:)`.
   - Ensure deleted entities or missing `new_state` events are handled explicitly.

3. Stop cleaning Lovelace cards globally.
   - Remove the behavior where `cleanCards(_:)` overwrites `hours_to_show`.
   - Keep only safe normalization that mirrors HA frontend behavior or is required for decode compatibility.
   - Preserve raw card options while applying the effective range policy separately for Modules 01 and 09.

4. Move hidden/extra/default-dashboard presentation choices behind typed `AppConfig` policy.
   - Do not let `DashboardViewModel` know about hardcoded entity IDs.
   - Ask the typed presentation/layout policy for additional synthetic cards, hidden entities, and the approved default-dashboard three-column placement.
   - Keep Lovelace config as the default source of truth except for the explicit default-dashboard deviation.

5. Add active view state.
   - Expose `views: [LovelaceView]`.
   - Expose `selectedViewID` or `selectedViewPath`.
   - Expose `selectedViewCards`.
   - Update history subscriptions when the selected view changes.
   - This should be completed with Module 12; do not expose the duplicate `3h`/`12h` maintenance views as intended dashboards.

6. Replace duplicated display/domain helpers.
   - Move `domain(of:)`, `displayName(for:)`, `displayState(for:)`, and `canToggle(_:)` out of the view model.
   - Use the new helpers from Module 06.
   - Leave compatibility wrapper methods on the view model only if that keeps SwiftUI call sites small during migration.

7. Extract the implemented history subscription lifecycle without changing its contracts.
   - Move the existing typed WebSocket owners, statuses, generations,
     projection stores, and graph revision feeds behind
     `HistoryCoordinator.subscribe(card:)`-style APIs.
   - Preserve unsubscribe handles and accepted-publication ordering.
   - Preserve Module 12 cancellation when the active view changes and reconcile
     appropriately when the WebSocket reconnects. Shared low-priority
     prefetch/cache ownership is separate; there is no profile-change path.

8. Extract the implemented realtime state subscription lifecycle.
   - Preserve the Module 02 multiplexer subscription and its unsubscribe token.
   - On reconnect, resubscribe and reload initial states or reconcile with a fresh state snapshot.

9. Add service-call state handling.
   - Keep service calls read-write only where the user intentionally clicks a control.
   - Disable service controls while the entity is unavailable, missing, or while an incompatible domain action is in progress.
   - Record service errors in a user-visible, nonfatal error surface.

10. Add retry entry points.
   - `retryBootstrap()`
   - `retryLovelace()`
   - `retryHistoriesForActiveView()`
   - `reconnectRealtime()`

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/HAEntityStore.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/LovelaceDashboardStore.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/HistoryCoordinator.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/EntityDisplayFormatter.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/ServiceController.swift`

Do not change visual card behavior in this module except where needed to consume the new view-model API. Card-specific fixes belong in Modules 06 through 11.

## Tests and Verification

Use [`../visual-testing.md`](../visual-testing.md) for the shared macOS 12 rendering and metric harness. Likely files are `Tests/NativeHAMacTests/DashboardViewModelTests.swift`, `HAEntityStoreTests.swift`, `LovelaceDashboardStoreTests.swift`, and dashboard-state cases in `GUIRenderingAndPerformanceTests.swift`. Tests touching `DashboardViewModel`, SwiftUI, or AppKit must be `@MainActor`.

### Unit tests

- Drive the bootstrap/state machine deterministically through starting/idle, loading states, loading Lovelace, subscribing, live/ready, partial-data, error, reconnecting, and disconnected semantics. Use the concrete production enum names that land; do not infer phases from display strings. Assert permitted transitions, retry transitions, and that component-specific errors do not erase usable data from other components.
- Raw `hours_to_show` survives normalization while `1h`, `3h`, and `12h` selector values produce the corresponding effective graph ranges; hidden/extra/layout policy remains `AppConfig`-driven; toggle decisions delegate to Module 06.
- `HAEntityStore` initial load, replacement, one-entity update, deletion/`new_state == nil`, stale update rejection if sequencing exists, and unrelated-entity preservation all receive pure tests.
- Use a fixed burst fixture with duplicate entity IDs and assert coalescing publishes the last update per entity, preserves updates for other entities, and schedules at most the intended number of main-actor publications.
- Verify retry entry points affect only their owned failure domain.

### Integration tests

Build fake REST/bootstrap inputs, the Module 02 dispatcher, a fake history coordinator, an injected clock, and cancellable task handles; never use network access or a real token.

- Exercise successful bootstrap, states-without-Lovelace partial data, Lovelace-with-failed-history partial data, realtime disconnect/reconnect, and retry recovery. Assert the published phase, retained data, visible error, and exact subscription set at every step.
- Verify a state subscription and several card history subscriptions coexist, reconnect exactly once, and do not duplicate entity rows or samples.
- Switch active views, reconnect, then disappear the owning dashboard.
  Obsolete bootstrap/history/realtime tasks must cancel; late callbacks must
  not publish; disappeared views must stop receiving updates.
- Verify background parsing/preparation feeds an immutable/prepared result to the main actor. Add an executor/thread or signpost probe only if reliable in Swift 5.6; the contract is that bulk parsing/transformation is not accidentally moved onto the main actor while observable publication remains main-actor isolated.

### GUI rendering and visual regression

This module owns dashboard shell state, not card design. Render only visible states it introduces or changes: initial loading, usable partial data with a nonfatal banner, live content, reconnecting with retained content, disconnected/retry, and empty dashboard. Use fixture cards supplied by existing card modules without asserting their visual details.

- At a fixed `1200 x 800` logical size, dark appearance, display scale `2`, fixed timestamps, `en_US_POSIX`, and explicit `Asia/Shanghai` where production APIs allow, host the state view in `NSHostingView` inside an offscreen AppKit window. Capture with `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`; macOS 12/Xcode 13.4.1 cannot use SwiftUI `ImageRenderer`.
- Write every state PNG to `.build/render-artifacts/` with descriptive names. Check the PNG signature and dimensions, nonblank output, the expected banner/content regions or status color family, and that asynchronous states have settled beyond any preceding phase.
- Manually compare owned shell states with hass-frontend before approving a macOS-version-labelled reference in `Tests/NativeHAMacTests/ReferenceImages/`; use tolerant pixel comparison after approval. Screenshots do not prove transition validity, data retention, cancellation, accessibility, or coalescing.

### Animation and interaction

Exercise state changes by setting the view-model phase directly rather than sleeping through network timing. If reconnect/error banners or retained-content transitions animate, expose deterministic transition progress and render `0`, `0.5`, and `1`; assert distinct frames and final equality with the stable destination. Test reduced-motion behavior only if the implemented transition supports it. Card gestures and sidebar selection animation belong to Modules 06-12.

### Performance and lifecycle

- Generate a `10,000`-entity initial state fixture and repeated `1,000`-update bursts outside measured blocks. Measure parsing/preparation separately from the short `@MainActor` apply/publish phase, and test cold bootstrap separately from warmed incremental updates.
- Measure burst coalescing, active-view subscription reconciliation, and retry/reconnect cleanup with `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. Warm caches for warm paths, consume the resulting state/card counts, and prefer stored XCTest baselines to tight hard-coded milliseconds.
- Repeat dashboard appearance/disappearance, view switching, and
  disconnect/reconnect (at least `100` deterministic fake cycles). Assert
  task/subscription registries return to baseline, weakly held coordinators can
  deallocate, and memory does not trend upward after cleanup.
- Use signpost metrics only if the implementation instruments a meaningful bootstrap or publication interval. `XCTHitchMetric` and true event-to-frame responsiveness are unavailable in Xcode 13.4.1; defer them to a later XCUITest target under newer Xcode.

### Manual QA

- Load the intended Home dashboard once and confirm its configurable selector produces `1h`, `3h`, and `12h` graph ranges while realtime state updates continue.
- Disconnect/restore the server and verify recoverable partial/reconnecting/disconnected UI, retained usable data where intended, and recovery without duplicate rows, samples, or subscriptions.
- Switch genuine views and close/reopen the dashboard while watching
  diagnostics for canceled work. Compare only the module-owned shell/status
  behavior with hass-frontend; card parity is accepted in the card modules.

## Dependencies

- Module 02 is required before concurrent WebSocket subscription behavior can be reliable.
- Module 01 is required before history can be moved off REST.
- Module 03 is intentionally skipped. Module 05 assumes one fixed server and
  must not add profile-transition work.
- Module 04 should land before active view routing is complete.
- Module 06 should land before display/toggle helpers are fully removed from this type.
- Module 12 must be complete before Module 05 and supplies the active-view
  state/ownership contract that this decomposition preserves.

## Risks

- Refactoring all view-model responsibilities at once may create a broad diff. Prefer extracting helpers while preserving public API wrappers, then remove wrappers after card modules are migrated.
- Realtime reconnect can produce duplicate subscriptions unless unsubscribe handles are tracked carefully.
- An `AppConfig` presentation policy can accidentally hide entities that Lovelace intentionally configured. Limit the approved default-dashboard exception to that dashboard and preserve raw Lovelace configuration.
- A visually correct dashboard can still have illegal state transitions, expensive main-actor preparation, or retained tasks. Keep transition, executor, and lifecycle assertions independent of snapshots.
- Performance measurements that combine JSON generation, background transformation, and main-actor publication will not identify UI stalls. Measure those phases separately.

## Acceptance Criteria

- `DashboardViewModel` no longer rewrites all history cards based on `selectedGraphHours`.
- The view model exposes all decoded Lovelace views and the active view's cards.
- Entity display and toggle decisions are delegated to testable helpers.
- Entity state updates are applied through one store path.
- History and state subscriptions have explicit cancellation and retry paths.
- The live dashboard presents Home once, changes graph ranges through the configured selector, and keeps realtime updates active.
- No hardcoded personal entity IDs remain in `DashboardViewModel`.
- Deterministic state-transition and fake-dependency integration tests cover loading, live, partial, error, reconnecting, disconnected, retry, cancellation, and late-callback suppression.
- Module-owned loading/partial/error/reconnect/empty states produce valid offscreen PNG artifacts at the documented size; any enforced reference was reviewed against hass-frontend and uses tolerant comparison.
- Stored performance baselines cover cold preparation, main-actor application, warm bursts, and subscription reconciliation, with no unexplained memory growth across repeated lifecycle cycles.
- No test depends on live network state, credentials, long arbitrary sleeps, `ImageRenderer`, `XCTHitchMetric`, or an XCUITest target that does not yet exist.
