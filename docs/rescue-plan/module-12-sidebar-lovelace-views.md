# Module 12 - Sidebar and Routing Driven by Lovelace Views

## Purpose

Replace the hardcoded sidebar/top-bar navigation with navigation derived from Lovelace views.

The live dashboard has three views:

- `Home` with path `default_view`
- `3h` with path `home_3h`
- `12h` with path `home_12h`

NativeHA currently renders only one view and uses global graph-hour buttons, which conflicts with Lovelace's actual view/card model.

## Current-Code Findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardView.swift`:

- `SidebarView` uses hardcoded labels such as dashboard, devices, settings, and a hardcoded user/profile label.
- The top bar shows hardcoded graph-hour segmented controls.
- Main content uses `viewModel.dashboardColumns`, which is currently based on one selected/default Lovelace view plus local column rules.
- There is no Lovelace view tab/sidebar selection.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`:

- `homeView` returns only the default or first view.
- `homeCards` and `dashboardColumns` are not active-view aware.
- `cleanCards(_:)` modifies history graph hours based on global state.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`:

- Lovelace view model fields are sparse and need expansion through Module 04.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/hui-root.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/views/hui-view.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/views/hui-masonry-view.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/view.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/components/hui-view-header.ts`

## Target Architecture

Drive navigation from decoded Lovelace config:

- `LovelaceDashboardStore`
  - Owns all decoded views.
  - Determines default selected view.
  - Resolves view by path or index.
- `DashboardViewModel`
  - Publishes `views`, `selectedViewID`, `selectedView`, and `selectedViewCards`.
  - Updates history/weather/template subscriptions for only the selected view.
- `SidebarView`
  - Displays Lovelace views rather than hardcoded navigation items for dashboard content.
  - Keeps app-level settings/profile controls separate from Lovelace views.
- `DashboardView`
  - Renders active view title and cards.
  - Removes global graph-hour controls.

## Confirmed Corrections to Claude's Original Direction

- The global `1h/3h/6h/12h/24h` graph-hour UI is not HA-like and conflicts with the live dashboard, where `hours_to_show` is encoded in cards/views.
- Do not collapse the live `3h` and `12h` views into graph-hour filters. They are distinct Lovelace views and should remain navigable.
- Do not hardcode the user's profile name or personal labels in the sidebar. Profile display belongs in Module 03.

## Implementation Tasks

1. Expand Lovelace view decoding through Module 04.
   - Preserve:
     - `title`
     - `path`
     - `icon`
     - `theme`
     - `panel`
     - `subview`
     - `visible`
     - `badges`
     - `cards`
     - `type`
     - `layout`
     - `background`
   - Preserve unknown fields.

2. Add active view selection to `DashboardViewModel`.
   - Select default view from `default_view`, first visible non-subview, or first view fallback.
   - Store selection by stable path when possible.
   - Fall back to stable decoded view ID or index only when path is absent.
   - Expose active cards directly.

3. Render Lovelace views in navigation.
   - Show view title and icon when provided.
   - Hide subviews from primary navigation unless directly routed.
   - Respect simple `visible: false` cases.
   - If conditional visibility is too broad for the first pass, decode and document unsupported conditions.

4. Remove global graph-hour controls from the top bar.
   - Do not mutate card configs when a user changes views.
   - Let `Home`, `3h`, and `12h` view selection determine which cards and history windows are active.

5. Update card layout to use active view.
   - `dashboardColumns` should be active-view aware.
   - Existing column rules from `AppConfig` should become optional profile layout hints, not the default source of truth.
   - Start with masonry-like columns for regular views and single-column/panel behavior for `panel` views.

6. Tie subscriptions to active view.
   - History streams from Module 01 should be active only for visible cards in the selected view.
   - Weather forecast and Markdown template subscriptions should follow the same pattern.
   - Cancel obsolete subscriptions when switching views.

7. Add route persistence.
   - Persist last selected view path in user preferences/profile.
   - On launch, restore it if the view still exists.
   - Otherwise fall back to default view.

8. Add subview/back-path handling.
   - Decode subview metadata now.
   - Implement direct selection if internal navigation starts using subviews.
   - Back navigation should return to the parent/default path when supported.

9. Separate app navigation from Lovelace navigation.
   - Keep Settings, server profile, diagnostics, or developer tools outside the Lovelace view list.
   - Avoid mixing app pages and Lovelace views in a way that makes selected-card subscriptions ambiguous.

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardView.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/LovelaceDashboardStore.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/LovelaceViewNavigation.swift`

Out of scope:

- Full browser URL routing.
- Lovelace edit mode.
- Conditional visibility parity for every HA user/device condition.
- All Lovelace layout strategies beyond current dashboard needs.

## Tests and Verification

Use the shared offscreen and performance method in [`../visual-testing.md`](../visual-testing.md). Likely files are `Tests/NativeHAMacTests/LovelaceViewNavigationTests.swift`, `DashboardViewRoutingTests.swift`, and sidebar/dashboard cases in `GUIRenderingAndPerformanceTests.swift`. All tests touching `DashboardViewModel`, AppKit, or SwiftUI view state must be `@MainActor`.

### Unit tests

- Select the default visible non-subview, select by stable path, restore the last path, and fall back predictably when the path disappears. Cover missing/duplicate paths as malformed input without inventing random identities.
- Hide subviews and `visible: false` views from primary navigation while preserving direct subview routing/back-path data. Cover icon-only, title-only, icon-and-title, absent title, long title, panel, and empty-view configs.
- Assert that active cards change without mutating decoded Lovelace config and that `Home`, `3h`, and `12h` retain their independent history-card options.
- Make selection styling a deterministic pure value (selected, unselected, hover, keyboard focus, disabled/hidden as applicable) so its colors/indicator geometry can be tested without synthesizing pointer events.

### Integration tests

Use a three-view fixture matching `default_view`, `home_3h`, and `home_12h`, plus fake Module 01 history, Module 07 forecast, and Module 08 template coordinators:

- Initial routing starts subscriptions only for the selected view. Each view switch cancels obsolete history/weather/template owners before or atomically with starting the new set; switching back creates one subscription per visible card, not duplicates.
- Deliver a late update from a canceled hidden view and assert it does not mutate visible view state or restart rendering. Hidden views must not schedule graph bitmap work.
- Restore persisted selection, handle removed/hidden restored paths, route into/out of a subview, and verify back-path fallback.
- Repeated resize/layout recalculation must preserve selected view/card identity and must not recreate subscriptions solely because the window width changed.

### GUI rendering and visual regression

Render navigation states this module owns: selected, unselected, hover, keyboard focus if implemented, long title, narrow window, loading config, and empty view. Also render a representative multi-card dashboard with entities, weather, Markdown, numeric history, and timeline history at real layout sizes.

- Use `1792 x 1000` logical points for the current three-column desktop composition: the audited constants are a `238`-point sidebar and `496`-point card columns. Use `900 x 700` as the narrow-window fixture and document the chosen responsive behavior (fewer columns, horizontal overflow, or another implemented rule) rather than silently clipping controls.
- Fix dark appearance/color scheme, display scale `2`, fixture timestamps, `en_US_POSIX`, and `Asia/Shanghai` where production formatting permits. Host SwiftUI in `NSHostingView` in a small offscreen AppKit window and capture with `bitmapImageRepForCachingDisplay(in:)` plus `cacheDisplay(in:to:)`; do not use unavailable SwiftUI `ImageRenderer` on macOS 12/Xcode 13.4.1.
- Put all current PNGs in `.build/render-artifacts/`, for example `sidebar-selected-home.png`, `sidebar-hover-long-title.png`, `dashboard-three-column.png`, `dashboard-narrow.png`, `dashboard-loading.png`, and `dashboard-empty-view.png`. Check PNG signature, exact dimensions, nonblank content, expected selected/hover indicator regions, required card regions, and settled graphs rather than capturing their loading placeholders unintentionally.
- Compare identical Lovelace fixtures manually with `/Users/jin/Documents/HA/hass-frontend` or the live frontend. Only reviewed images may become macOS-version-labelled references in `Tests/NativeHAMacTests/ReferenceImages/`, using tolerant comparison. A dashboard PNG does not prove routing, focus order, keyboard access, subscription cancellation, data semantics, or performance.

### Animation and interaction

- Prefer explicit selection/hover/focus models over nondeterministic mouse automation. If the selected indicator or sidebar movement animates, render deterministic progress `0`, `0.5`, and `1`; assert frames differ and the final frame equals the stable selected destination. Verify reduced motion if that animation and production support exist.
- Semantically test click/keyboard selection and back routing through direct action invocation or bounded event expectations. True pointer travel, scroll deceleration, focus traversal, and event-to-frame hitch testing is deferred to a future XCUITest target under newer Xcode; Xcode 13.4.1 does not provide `XCTHitchMetric`.

### Performance and lifecycle

- Build a generated `500`-card dashboard fixture outside measured blocks, with nested stacks and a controlled mix of supported/unsupported cards. Measure cold route/layout preparation separately from a warmed render of the selected view.
- Measure `100` repeated `Home -> 3h -> 12h` switching cycles with fake coordinators, plus repeated narrow/normal layout changes, using `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. Consume selected card/subscription/render counts and prefer stored XCTest baselines over tight wall-time assertions.
- Warm card/graph caches before measuring warm switching. Track subscription registries, render-task counts, and weak owners so each cycle returns to the expected active-view set and memory does not trend upward.
- Measure cleanup/cancellation separately from initial load. A hidden view must have zero active history/forecast/template subscriptions and no continuing graph render or animation work after bounded settlement.
- Use signpost metrics only around intentionally instrumented route-to-visible or subscription-reconciliation intervals. Do not require unavailable `XCTHitchMetric`.

### Manual QA

- Against the live server, compare the visible view navigation and card sets for `Home`, `3h`, and `12h` with hass-frontend; verify per-card windows and the absence of the global hour override.
- Switch views rapidly, enter/leave any implemented subview, resize from wide to narrow and back, and relaunch for persisted-route recovery. Confirm hidden graphs stop rendering and old history/weather/template streams stop processing.
- Verify keyboard navigation, visible focus, logical focus order, activation, resize behavior, scroll/overflow behavior, long-title truncation, card/sidebar clipping, and empty/loading states manually. Offscreen snapshots cannot establish accessibility or real focus behavior.

## Dependencies

- Module 04 for robust Lovelace view decoding.
- Module 05 for active-view state and subscription lifecycle.
- Module 01 for per-card history windows.
- Module 03 for replacing hardcoded sidebar profile labels.

## Risks

- Current local column rules may have been compensating for dashboard layout. Removing them abruptly could degrade layout. Keep profile layout hints available but secondary to Lovelace.
- Lovelace visibility conditions can depend on user identity. Implement simple cases first and fail open with documented limitations if needed.
- Keeping hidden views subscribed will waste bandwidth and can corrupt visible state. Active-view subscription boundaries are required.
- Fixed full-window snapshots can miss routing/subscription defects and can be OS-sensitive because of fonts/system controls. Pair them with semantic lifecycle tests and macOS-version-labelled tolerant baselines.
- A large dashboard can recreate expensive graph/card work on every selection or resize if identity is unstable. Include stable-identity, warmed-switching, and hidden-render-task assertions.

## Acceptance Criteria

- Navigation is driven by Lovelace views from the server.
- The live `Home`, `3h`, and `12h` views are all selectable.
- Global graph-hour controls no longer override card configuration.
- Active view selection controls which cards and subscriptions are active.
- Hardcoded personal sidebar labels are removed or isolated behind profile settings.
- Routing, persistence/fallback, subview visibility/back path, and active-card tests pass with stable identities and no mutation of decoded config.
- Switching views starts exactly the required subscriptions, cancels the old set, rejects late hidden-view updates, and leaves hidden views with no graph rendering/animation work.
- Selected/unselected/hover/long-title/loading/empty, wide multi-column, and narrow layouts emit valid PNG artifacts at the documented sizes; any enforced references were manually reviewed against hass-frontend and compare tolerantly.
- Stored performance baselines cover the generated `500`-card dashboard and repeated warmed switching/resizing with no unexplained task, subscription, or memory growth.
- Keyboard focus/navigation and resize/clipping pass manual QA; unavailable XCUITest/hitch coverage is documented rather than simulated with unreliable sleeps.
