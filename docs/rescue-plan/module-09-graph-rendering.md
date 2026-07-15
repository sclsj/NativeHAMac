# Module 09 - Graph Rendering Alignment and Interaction Polish

## Purpose

Keep the existing native graph rendering pipeline, but align the remaining behavior with Home Assistant history charts: step line charts, timeline handling, time axes, tooltips, per-card options, and interaction behavior.

This is not a rewrite module. The current CoreGraphics bitmap path, timeline builder, prepared series cache, and min/max downsampling cache are strong foundations.

## Current-Code Findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/GraphRendering.swift`:

- Rendering uses CoreGraphics bitmap output and has explicit line/timeline preparation.
- Timeline color handling already preserves states such as `unknown` and `unavailable`.
- `linearTicks(min:max:count:)` and SI-style axis labels already exist.
- Downsampling/minmax cache exists.
- X-axis ticks use simple linear time ticks rather than HA-like time tick selection.
- Numeric line drawing is currently continuous between samples. HA frontend line history uses step-end behavior for state history charts.
- Tooltip/sample lookup behavior should be reviewed against HA's "last point before hovered time" behavior.
- Date formatting is centralized/cached, but time-zone and locale behavior should be verified against the server/app profile.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- `HistoryGraphCard` labels use global selected hours today, not per-card `hours_to_show`.
- Card options such as names, legend behavior, `show_names`, `min_y_axis`, `max_y_axis`, and logarithmic scale are not fully modeled.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/HistoryGraphSupportTests.swift`:

- There is already coverage that `unknown` and `unavailable` remain renderable for timelines. Preserve this.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line-data.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-timeline.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/components/chart/timeline-color.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/components/chart/ha-chart-base.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-history-graph-card.ts`

## Confirmed Corrections to Claude's Original Direction

- Do not filter `unknown`, `unavailable`, or `none` out of timeline history. HA frontend preserves them as timeline states with distinct colors.
- Filtering nonnumeric states is correct only for numeric line preparation.
- Graph rendering is not the weakest subsystem. Focus on specific parity gaps rather than replacing the renderer.

## Target Architecture

Keep the existing renderer split:

- History ingestion and normalization comes from Module 01.
- Card options come from Module 04.
- Per-card subscription lifecycle comes from Module 05.
- The renderer receives prepared, card-local `HistoryGraphRenderModel` input.

Add or refine these types:

- `HistoryGraphCardOptions`
  - `hoursToShow`
  - `showNames`
  - `fitYData`
  - `minYAxis`
  - `maxYAxis`
  - `logarithmicScale`
  - `expandLegend`
  - per-entity names if supported
- `TimeTickGenerator`
  - Chooses tick intervals based on chart duration and available width.
- `LineSeriesSampler`
  - Provides hover values using HA-like previous-sample semantics.
- `StepLinePathBuilder`
  - Builds step-end paths for numeric history state charts.

## Implementation Tasks

1. Preserve the existing rendering pipeline.
   - Do not replace bitmap rendering with a web view or a new chart framework.
   - Keep caches unless profiling shows a concrete defect.

2. Use card-local options.
   - Remove graph rendering's dependence on global selected hours.
   - Consume `hours_to_show` from each `history-graph` card.
   - Add `show_names`, `min_y_axis`, `max_y_axis`, `fit_y_data`, `logarithmic_scale`, and `expand_legend` where decoded by Module 04.

3. Implement step-end line paths.
   - HA frontend line data sets `step: "end"` for state history charts.
   - Draw horizontal segments from the previous value until the next sample time, then vertical transition.
   - Preserve gaps where data is missing or nonnumeric.

4. Keep context-specific state filtering.
   - Timeline series: keep all nonempty states, including `unknown` and `unavailable`.
   - Numeric line series: parse numeric states and ignore nonnumeric values for the line only.
   - Do not mutate the stored history to remove nonnumeric states.

5. Improve time tick selection.
   - Choose tick intervals based on total duration: minutes, hours, half-days, days as appropriate.
   - Use server/profile timezone, with the live server currently in `Asia/Shanghai`.
   - Avoid overlapping x-axis labels.

6. Align hover/sample behavior.
   - For line charts, when there is no exact point at the hovered x value, show the last known point before that time if it exists.
   - Do not use nearest future value for state-like step charts.
   - For timelines, show the state segment active at the hovered time.

7. Add legend behavior.
   - Respect `show_names` when available.
   - Support compact and expanded legend modes.
   - Keep entity colors stable across redraws.

8. Review y-axis handling.
   - Honor explicit `min_y_axis` and `max_y_axis`.
   - Implement `fit_y_data` where supported.
   - Add guardrails for flat series, NaN, infinity, and empty series.
   - Implement logarithmic scale only for strictly positive numeric data; otherwise fall back with a visible debug/test error or safe linear scale.

9. Keep performance guardrails.
   - Retain min/max downsampling for high-volume numeric sensors.
   - Add performance fixtures using existing `sps30_*` scratch data only as optional local research artifacts, not as committed fixtures unless sanitized and intentionally added.

10. Add visual regression hooks.
   - Keep pure rendering functions testable.
   - Where possible, render deterministic bitmap fixtures and compare key properties such as nonblank pixels, axis label count, and expected path extents.

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/GraphRendering.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/TimeTickGenerator.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/StepLinePathBuilder.swift`

Out of scope:

- Replacing CoreGraphics rendering.
- Full ECharts feature parity.
- Dropping timeline unknown/unavailable states.

## Tests and Verification

Add unit tests for:

- Step-end path point generation.
- Numeric series ignores nonnumeric values without deleting original history.
- Timeline series keeps `unknown` and `unavailable`.
- Hover lookup returns previous sample, not nearest future sample.
- Time tick generation for 1h, 3h, 12h, and 24h windows.
- Explicit y-axis min/max.
- Flat series y-axis padding.
- Logarithmic scale fallback for zero/negative values.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/GraphRenderingTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/TimeTickGeneratorTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/StepLinePathBuilderTests.swift`

Manual QA:

- Open live 1h, 3h, and 12h history cards.
- Confirm each card uses its own configured window.
- Confirm timeline entities show unavailable/unknown periods rather than gaps when fixtures contain those states.
- Confirm numeric sensor charts use step behavior and sensible tooltip values.
- Confirm axis labels do not overlap in narrow card widths.
- Confirm graph panning/hovering remains responsive with high-volume sensor history.

## Dependencies

- Module 01 for correct history stream data.
- Module 04 for graph card options.
- Module 05 for per-card history and active-view lifecycle.
- Module 12 because only the active Lovelace view should drive active graph subscriptions.

## Risks

- Step-end paths may look visually different from existing screenshots. This is expected if aligning to HA state-history behavior.
- Logarithmic scale can be misleading with zero or negative sensor values. Guard strictly.
- Snapshot tests can be brittle across macOS versions. Prefer testing geometry/data preparation and only light bitmap smoke checks.

## Acceptance Criteria

- Graphs use card-local `hours_to_show`.
- Timeline graphs preserve `unknown` and `unavailable`.
- Numeric line graphs use step-end behavior.
- Hover/sample lookup matches state-history semantics.
- Time axes are readable for live 1h, 3h, and 12h cards.
- Existing graph performance optimizations remain intact.

