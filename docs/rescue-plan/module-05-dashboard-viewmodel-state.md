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

Add unit tests for:

- Selecting each Lovelace view exposes only that view's cards.
- Per-card `hours_to_show` survives view-model normalization.
- State-change events update one entity without replacing unrelated state.
- `new_state == nil` is handled intentionally.
- A failed history subscription records a history error without clearing cards.
- Hidden/extra entity policy is profile-driven and not hardcoded in the view model.
- Toggle eligibility delegates to the Module 06 helper.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/DashboardViewModelTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/HAEntityStoreTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/LovelaceDashboardStoreTests.swift`

Manual verification:

- Launch the app against the live server.
- Confirm the dashboard can load all three Lovelace views: `Home`, `3h`, and `12h`.
- Confirm `history-graph` cards use their own configured `hours_to_show` values: 1, 3, and 12.
- Confirm realtime state updates continue while history streams are active.
- Disconnect network or stop the server and verify the app shows a recoverable connection state.
- Reconnect and verify state and history subscriptions recover without duplicate rows or duplicate samples.

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

## Acceptance Criteria

- `DashboardViewModel` no longer rewrites all history cards based on `selectedGraphHours`.
- The view model exposes all decoded Lovelace views and the active view's cards.
- Entity display and toggle decisions are delegated to testable helpers.
- Entity state updates are applied through one store path.
- History and state subscriptions have explicit cancellation and retry paths.
- The live dashboard can switch among `Home`, `3h`, and `12h` without losing realtime updates.
- No hardcoded personal entity IDs remain in `DashboardViewModel`.

