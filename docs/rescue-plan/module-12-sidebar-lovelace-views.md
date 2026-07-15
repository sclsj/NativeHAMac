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

Add unit tests for:

- Default view selection.
- View selection by path.
- Subviews hidden from primary navigation.
- `visible: false` hidden from primary navigation.
- Active view card list changes when selected view changes.
- History subscription manager receives only active view cards.
- Last selected view path restore/fallback.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/LovelaceViewNavigationTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/DashboardViewRoutingTests.swift`

Manual QA:

- Launch against the live server.
- Confirm the sidebar or top navigation shows `Home`, `3h`, and `12h`.
- Select each view and confirm the visible cards match HA.
- Confirm the history cards in `3h` use 3-hour windows and cards in `12h` use 12-hour windows without a global graph-hour override.
- Switch views repeatedly and confirm old history/weather/template subscriptions do not keep updating hidden views.
- Relaunch and confirm the last selected view restores if still present.

## Dependencies

- Module 04 for robust Lovelace view decoding.
- Module 05 for active-view state and subscription lifecycle.
- Module 01 for per-card history windows.
- Module 03 for replacing hardcoded sidebar profile labels.

## Risks

- Current local column rules may have been compensating for dashboard layout. Removing them abruptly could degrade layout. Keep profile layout hints available but secondary to Lovelace.
- Lovelace visibility conditions can depend on user identity. Implement simple cases first and fail open with documented limitations if needed.
- Keeping hidden views subscribed will waste bandwidth and can corrupt visible state. Active-view subscription boundaries are required.

## Acceptance Criteria

- Navigation is driven by Lovelace views from the server.
- The live `Home`, `3h`, and `12h` views are all selectable.
- Global graph-hour controls no longer override card configuration.
- Active view selection controls which cards and subscriptions are active.
- Hardcoded personal sidebar labels are removed or isolated behind profile settings.

