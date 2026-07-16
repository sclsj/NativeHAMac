# Module 05 - DashboardViewModel Logic, State Ownership, and Loading Lifecycle

## Purpose

Turn `DashboardViewModel` from a large mixed coordinator into a predictable application-state layer that can safely compose:

- Lovelace views and cards.
- HA entity states and service calls.
- WebSocket subscriptions.
- Per-card history windows.
- User/server profile preferences.
- Error, retry, and loading states.

This module should not be treated as a visual redesign. It is the integration layer that lets Modules 01, 02, 03, 04, 06, 07, 08, and 12 work without duplicating business rules across SwiftUI views.

## Current-Code Findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`:

- `selectedGraphHours` is global view-model state. `cleanCards(_:)` rewrites every `history-graph` card with that global value, which conflicts with HA Lovelace where each history card owns `hours_to_show`.
- `homeView` returns only the first Lovelace view or the view marked `default_view`. The live server has three Lovelace views: `Home`, `3h`, and `12h`, but NativeHA currently renders only one logical view.
- `dashboardColumns` is based on `AppConfig.columnRules`, matching personal titles and entity IDs rather than Lovelace layout semantics.
- `load()` fetches REST states, fetches Lovelace through WebSocket, then starts state subscriptions on the same WebSocket client. This depends on the broken single-reader WebSocket architecture described in Module 02.
- `loadHistories(for:)` uses REST history and receives the card list after `cleanCards(_:)`, so the requested window is global rather than card-local.
- `historyKey(entityID:hours:)` includes the global hours value. This is usable as a cache key, but the input hours must come from the card configuration, not a global segmented control.
- `historyEntityIDs(for:)` filters through `AppConfig.hiddenEntities`, which mixes server/user policy into core Lovelace rendering.
- `displayState(for:)`, `displayName(for:)`, `domain(of:)`, and `canToggle(_:)` duplicate rules that should be centralized and aligned with HA frontend helpers.
- `canToggle(_:)` currently recognizes only `switch`, `fan`, `input_boolean`, and `automation`. HA frontend also treats domains such as `light`, `group`, `humidifier`, and `valve` as toggle-capable when the entity is available.
- There is no clear retry model. A failed Lovelace load, failed history load, and failed realtime subscription all collapse into limited console/error behavior.
- There is no explicit cancellation boundary for obsolete history requests when switching views, reconnecting, or changing server profiles.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- Many views call back into `DashboardViewModel` for formatting, toggling, and selection. This is workable only if the view model exposes stable helper APIs rather than ad hoc per-view behavior.

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
  - Owns per-card history subscriptions after Modules 01 and 02.
  - Keys history by entity set plus card-local `hours_to_show` and relevant options.
  - Cancels obsolete subscriptions.
- `EntityDisplayFormatter`
  - Owns state display, name display, units, device classes, timestamps, and unavailable handling for Modules 06 and 10.
- `ServiceController`
  - Encapsulates calls such as toggle, climate target temperature, fan percentage, and automation trigger.
  - Keeps REST service-call behavior initially, but has one clear place to move to WebSocket `call_service` later.
- `ServerProfile`
  - Comes from Module 03 and replaces scattered `AppConfig` decisions.

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
   - Preserve card-local options for Modules 01 and 09.

4. Move hidden/extra/personal entities behind profile policy.
   - Do not let `DashboardViewModel` know about hardcoded entity IDs.
   - Ask `ServerProfile` or `DashboardPreferences` whether a profile wants additional synthetic cards, hidden entities, or local layout hints.
   - Keep Lovelace config as the default source of truth.

5. Add active view state.
   - Expose `views: [LovelaceView]`.
   - Expose `selectedViewID` or `selectedViewPath`.
   - Expose `selectedViewCards`.
   - Update history subscriptions when the selected view changes.
   - This should be completed with Module 12.

6. Replace duplicated display/domain helpers.
   - Move `domain(of:)`, `displayName(for:)`, `displayState(for:)`, and `canToggle(_:)` out of the view model.
   - Use the new helpers from Module 06.
   - Leave compatibility wrapper methods on the view model only if that keeps SwiftUI call sites small during migration.

7. Make history subscription lifecycle explicit.
   - After Module 01, replace REST `loadHistories(for:)` with `HistoryCoordinator.subscribe(card:)`.
   - Store unsubscribe handles.
   - Cancel history subscriptions when the active view changes, when the server profile changes, and when the WebSocket reconnects.

8. Make realtime state subscription lifecycle explicit.
   - After Module 02, subscribe to `state_changed` through the multiplexer.
   - Retain the unsubscribe token.
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
- Selecting each Lovelace view exposes only that view's cards; per-card `hours_to_show` survives normalization; hidden/extra entity policy remains profile-driven; toggle decisions delegate to Module 06.
- `HAEntityStore` initial load, replacement, one-entity update, deletion/`new_state == nil`, stale update rejection if sequencing exists, and unrelated-entity preservation all receive pure tests.
- Use a fixed burst fixture with duplicate entity IDs and assert coalescing publishes the last update per entity, preserves updates for other entities, and schedules at most the intended number of main-actor publications.
- Verify retry entry points affect only their owned failure domain and that errors are sanitized of base-URL credentials/tokens.

### Integration tests

Build fake REST/bootstrap inputs, the Module 02 dispatcher, a fake history coordinator, an injected clock, and cancellable task handles; never use network access or a real token.

- Exercise successful bootstrap, states-without-Lovelace partial data, Lovelace-with-failed-history partial data, realtime disconnect/reconnect, and retry recovery. Assert the published phase, retained data, visible error, and exact subscription set at every step.
- Verify a state subscription and several card history subscriptions coexist, reconnect exactly once, and do not duplicate entity rows or samples.
- Switch active views and profiles, then disappear the owning dashboard. Obsolete bootstrap/history/realtime tasks must cancel; late callbacks must not publish; disappeared views must stop receiving updates.
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
- Repeat dashboard appearance/disappearance, view switching, profile switching, and disconnect/reconnect (at least `100` deterministic fake cycles). Assert task/subscription registries return to baseline, weakly held coordinators can deallocate, and memory does not trend upward after cleanup.
- Use signpost metrics only if the implementation instruments a meaningful bootstrap or publication interval. `XCTHitchMetric` and true event-to-frame responsiveness are unavailable in Xcode 13.4.1; defer them to a later XCUITest target under newer Xcode.

### Manual QA

- Load the live server and confirm `Home`, `3h`, and `12h` remain usable with per-card `1`, `3`, and `12` hour history while realtime state updates continue.
- Disconnect/restore the server and verify recoverable partial/reconnecting/disconnected UI, retained usable data where intended, and recovery without duplicate rows, samples, or subscriptions.
- Switch views and profiles and close/reopen the dashboard while watching diagnostics for canceled work and sanitized errors. Compare only the module-owned shell/status behavior with hass-frontend; card parity is accepted in the card modules.

## Dependencies

- Module 02 is required before concurrent WebSocket subscription behavior can be reliable.
- Module 01 is required before history can be moved off REST.
- Module 03 should land before personal config is removed from view-model decisions.
- Module 04 should land before active view routing is complete.
- Module 06 should land before display/toggle helpers are fully removed from this type.
- Module 12 should land with or shortly after active view state.

## Risks

- Refactoring all view-model responsibilities at once may create a broad diff. Prefer extracting helpers while preserving public API wrappers, then remove wrappers after card modules are migrated.
- Realtime reconnect can produce duplicate subscriptions unless unsubscribe handles are tracked carefully.
- A profile-driven hidden entity policy can accidentally hide entities that Lovelace intentionally configured. Default behavior should render Lovelace as configured and apply profile overrides only when explicitly enabled.
- A visually correct dashboard can still have illegal state transitions, expensive main-actor preparation, or retained tasks. Keep transition, executor, and lifecycle assertions independent of snapshots.
- Performance measurements that combine JSON generation, background transformation, and main-actor publication will not identify UI stalls. Measure those phases separately.

## Acceptance Criteria

- `DashboardViewModel` no longer rewrites all history cards based on `selectedGraphHours`.
- The view model exposes all decoded Lovelace views and the active view's cards.
- Entity display and toggle decisions are delegated to testable helpers.
- Entity state updates are applied through one store path.
- History and state subscriptions have explicit cancellation and retry paths.
- The live dashboard can switch among `Home`, `3h`, and `12h` without losing realtime updates.
- No hardcoded personal entity IDs remain in `DashboardViewModel`.
- Deterministic state-transition and fake-dependency integration tests cover loading, live, partial, error, reconnecting, disconnected, retry, cancellation, and late-callback suppression.
- Module-owned loading/partial/error/reconnect/empty states produce valid offscreen PNG artifacts at the documented size; any enforced reference was reviewed against hass-frontend and uses tolerant comparison.
- Stored performance baselines cover cold preparation, main-actor application, warm bursts, and subscription reconciliation, with no unexplained memory growth across repeated lifecycle cycles.
- No test depends on live network state, credentials, long arbitrary sleeps, `ImageRenderer`, `XCTHitchMetric`, or an XCUITest target that does not yet exist.
