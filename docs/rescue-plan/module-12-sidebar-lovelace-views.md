# Module 12 - Sidebar and Routing Driven by Lovelace Views

> **Status: complete within the verified packet scope.** The
> [Module 12 evidence packet](../reference-context/modules/module-12-sidebar-lovelace-views.md)
> records implemented contracts, validation, and deferred work. The original
> findings, architecture sketches, task lists, and acceptance checklist below
> are historical planning, not a fresh code audit or remaining-work checklist.
> Preserve the packet contracts; verify current code before reopening work.

## Purpose

Replace hardcoded sidebar navigation with navigation derived from genuine Lovelace views while keeping the approved configurable graph-range selector.

The live configuration has three views:

- `Home` with path `default_view`
- `3h` with path `home_3h`
- `12h` with path `home_12h`

The `3h` and `12h` views are maintenance workarounds for graph ranges, not intended separate dashboards. Present Home once and use the typed `AppConfig` range policy; continue to support genuine additional Lovelace views.

## Historical Findings Before Rescue

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

## Post-Module-01/09 Ownership Constraints

Active-view routing now intersects implemented per-card history revision feeds and graph render coordinators. A view switch must preserve stable owners for cards that remain visible, while canceling and re-keying removed cards before late publications or render completions can install. Hidden views must retain no `GraphHistoryRevisionFeed` observer and no queued coordinator work.

Do not use history content hashes or endpoint timestamps to infer whether a hidden/visible view's snapshot is newer. Selection and late-update rejection must use decoded stable view/card identity plus explicit subscription and coordinator generations.

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
  - Updates implemented history ownership for only the selected view and
    exposes the same active-card seam for future weather/template modules.
- `SidebarView`
  - Displays Lovelace views rather than hardcoded navigation items for dashboard content.
  - Removes the current nonfunctional settings/profile rows; Module 12 adds no
    settings or profile UI.
- `DashboardView`
  - Renders active view title and cards.
  - Keeps one graph-range selector driven by the typed `AppConfig` policy.

## Confirmed Corrections to Claude's Original Direction

- Keep one selector or equivalent control that changes the intended Home dashboard's graph range; configure its ranges, default, and scope in `AppConfig.swift`.
- Do not expose the live `3h` and `12h` maintenance duplicates as intended separate navigation/content.
- Do not hardcode the user's profile name or personal labels in the sidebar. Module 03 is intentionally skipped, so remove the nonfunctional profile row rather than moving it behind a profile/settings surface.

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
   - Exclude or collapse the known `home_3h` and `home_12h` maintenance duplicates for the default dashboard while preserving their raw decoded config.

4. Keep the configured graph-range selector in the top bar or equivalent native location.
   - Do not mutate card configs when a user changes views.
   - Let the typed `AppConfig` range policy determine the effective graph window on Home.

5. Update card layout to use active view.
   - `dashboardColumns` should be active-view aware.
   - Keep the approved default-dashboard three-column composition in a typed `AppConfig` layout policy; preserve raw `vertical-stack` config without treating it as desired grouping there.
   - Use Lovelace layout semantics for unrelated dashboards, including single-column/panel behavior where configured.

6. Tie subscriptions to active view.
   - History streams from Module 01 should be active only for visible cards in the selected view.
   - Future weather forecast and Markdown template subscriptions must follow
     the same active-card seam when Modules 07 and 08 implement them; do not add
     those subscriptions in Module 12.
   - Cancel obsolete subscriptions when switching views.

7. Add route persistence.
   - Persist the last unambiguous eligible primary view locator in an injected,
     versioned fixed-deployment user preference.
   - On launch, restore it if the view still exists.
   - Otherwise fall back to default view.

8. Add subview/back-path handling.
   - Decode subview metadata now.
   - Implement direct selection if internal navigation starts using subviews.
   - Back navigation should return to the parent/default path when supported.

9. Separate app navigation from Lovelace navigation.
   - Do not add settings or server-profile navigation. Any future diagnostics
     or developer tools remain outside the Lovelace view list.
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
- Assert that active genuine views change without mutating decoded Lovelace config and that Home's `1h`, `3h`, and `12h` selector values change effective ranges without exposing duplicate dashboards.
- Make selection styling a deterministic pure value (selected, unselected, hover, keyboard focus, disabled/hidden as applicable) so its colors/indicator geometry can be tested without synthesizing pointer events.

### Integration tests

Use a fixture containing `default_view`, the `home_3h`/`home_12h` maintenance duplicates, and one genuine unrelated view, plus fake Module 01 history and graph render owners. Assert the maintenance duplicates are not primary navigation items.

- Initial routing starts history subscriptions only for the selected view. Each view switch cancels obsolete history/feed/render owners before or atomically with starting the new set; switching back creates one subscription per visible card, not duplicates.
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
- Measure `100` repeated graph-range changes plus genuine view switches with fake coordinators, and repeated narrow/normal layout changes, using `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`. Consume selected card/subscription/render counts and prefer stored XCTest baselines over tight wall-time assertions.
- Warm card/graph caches before measuring warm switching. Track subscription registries, render-task counts, and weak owners so each cycle returns to the expected active-view set and memory does not trend upward.
- Measure cleanup/cancellation separately from initial load. A hidden view must have zero active history subscriptions and no continuing graph render or animation work after bounded settlement.
- Use signpost metrics only around intentionally instrumented route-to-visible or subscription-reconciliation intervals. Do not require unavailable `XCTHitchMetric`.

### Manual QA

- Against the live server, confirm Home appears once, `3h`/`12h` maintenance duplicates are not primary navigation, and the configured selector reproduces those graph ranges without changing unrelated Home content.
- Switch views rapidly, enter/leave any implemented subview, resize from wide to narrow and back, and relaunch for persisted-route recovery. Confirm hidden graphs stop rendering and old history streams stop processing.
- Verify keyboard navigation, visible focus, logical focus order, activation, resize behavior, scroll/overflow behavior, long-title truncation, card/sidebar clipping, and empty/loading states manually. Offscreen snapshots cannot establish accessibility or real focus behavior.

## Dependencies

- Complete Module 04 for robust Lovelace view decoding and exact identity.
- Complete Modules 01 and 02 for history and WebSocket ownership.
- Module 12 owns active-view state and current history/render reconciliation; Module 05 follows only after Module 12 is independently verified.
- Module 03 is intentionally skipped under the fixed-deployment deviation.

## Risks

- Applying the default-dashboard three-column exception to unrelated dashboards would discard intended Lovelace layout semantics. Scope the typed `AppConfig` policy to the approved dashboard.
- Lovelace visibility conditions can depend on user identity. Implement simple cases first and fail open with documented limitations if needed.
- Keeping hidden views subscribed will waste bandwidth and can corrupt visible state. Active-view subscription boundaries are required.
- Fixed full-window snapshots can miss routing/subscription defects and can be OS-sensitive because of fonts/system controls. Pair them with semantic lifecycle tests and macOS-version-labelled tolerant baselines.
- A large dashboard can recreate expensive graph/card work on every selection or resize if identity is unstable. Include stable-identity, warmed-switching, and hidden-render-task assertions.

## Acceptance Criteria

- Navigation is driven by Lovelace views from the server.
- The live Home dashboard appears once; `3h` and `12h` maintenance duplicates are not exposed as intended separate dashboards.
- The configured graph-range selector changes effective graph windows without mutating decoded card configuration.
- Active view selection controls which cards and subscriptions are active.
- Hardcoded personal/settings/profile sidebar rows are removed; no profile UI is added.
- Routing, persistence/fallback, subview visibility/back path, and active-card tests pass with stable identities and no mutation of decoded config.
- Switching views starts exactly the required subscriptions, cancels the old set, rejects late hidden-view updates, and leaves hidden views with no graph rendering/animation work.
- Selected/unselected/hover/long-title/loading/empty, wide multi-column, and narrow layouts emit valid PNG artifacts at the documented sizes; any enforced references were manually reviewed against hass-frontend and compare tolerantly.
- Stored performance baselines cover the generated `500`-card dashboard and repeated warmed switching/resizing with no unexplained task, subscription, or memory growth.
- Keyboard focus/navigation and resize/clipping pass manual QA; unavailable XCUITest/hitch coverage is documented rather than simulated with unreliable sleeps.
