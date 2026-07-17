# Module 09 - Graph Rendering Alignment and Interaction Polish

## Purpose

Keep the existing native graph rendering pipeline, but align the remaining behavior with Home Assistant history charts except where the approved native interaction and smooth y-axis deviations apply.

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

- `HistoryGraphCard` labels use the current bare global selected hours. The intended global selector remains, but its ranges/default/scope must come from the typed `AppConfig` policy without rewriting decoded cards.
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
- Visible-card subscription lifecycle comes from Module 05.
- The renderer receives prepared `HistoryGraphRenderModel` input with the effective selected range.

Add or refine these types:

- `HistoryGraphCardOptions`
  - effective selected range from the typed time-range policy
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

2. Use the configured range policy without mutating cards.
   - Replace dependence on bare global selected hours with the typed `AppConfig` policy.
   - Preserve decoded `hours_to_show`, but use the effective selector range for the intended Home dashboard unless an explicit per-graph override is configured.
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
   - While zooming or inertial panning changes the visible range, update numeric y-axis bounds smoothly and continuously. Keep interpolation/look-ahead/hysteresis tuning in a typed `AppConfig` policy and select it through visual and performance testing.

9. Keep performance guardrails.
   - Preserve spikes and visible detail. Benchmark the current min/max path, a no-loss oracle, and other sensible native/reference candidates; keep the selected algorithm and any measured crossover configurable in `AppConfig.swift`.
   - Move reusable benchmark fixtures, methodology, size metadata, and results into a tracked `Benchmarks/<topic>/` directory; local live-data scratch files may remain inputs rather than test fixtures.

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

Extend the proven experiments in `Tests/NativeHAMacTests/GraphRenderingTests.swift` and `GUIRenderingAndPerformanceTests.swift`, following [`../visual-testing.md`](../visual-testing.md). Likely companion files are `TimeTickGeneratorTests.swift`, `StepLinePathBuilderTests.swift`, and `GraphInteractionTests.swift`, all in the existing `NativeHAMacTests` target. Tests using AppKit/SwiftUI/view state must run on the main actor; pure geometry and renderer inputs should stay non-AppKit where practical.

### Unit and semantic-conformance tests

- Build exact step-end geometry: horizontal from the previous sample to the next timestamp, then the vertical transition. Cover a two-point series, repeated values/timestamps, clipped window edges, nonnumeric gaps, and multi-series input. The semantic source is `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line-data.ts` (`step: "end"`). Remove the existing scoped `XCTExpectFailure` when fixed.
- Hover at exact samples, between samples, before the first sample, after the last sample, and across a gap. The line lookup must use the last sample at or before hover time, matching `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line.ts`; timeline lookup must return the active segment. Remove the current hover `XCTExpectFailure` when fixed.
- Assert timeline segment boundaries and stable, distinct colors for `off`, `on`, `unknown`, `unavailable`, and `none`; preserve the original stored history while numeric preparation skips only nonnumeric samples.
- Cover axis bounds for explicit min/max, `fit_y_data`, flat/empty/single-point series, NaN/infinity, and logarithmic fallback with nonpositive values. Assert time ticks and nonoverlap decisions for `1h`, `3h`, `12h`, and `24h` at `320` and `496` point widths with fixed `en_US_POSIX` locale and `Asia/Shanghai` timezone where the production API permits injection.
- Assert stable series colors across redraw/reorder rules, legend names/options, clipping to plot rect, raw `hours_to_show` preservation, and effective `1h`/`3h`/`12h` selector ranges. Replace the current per-card-hours `XCTExpectFailure` with the approved range-policy contract.
- Keep pure tests for pointer-anchored vertical-scroll zoom, horizontal-scroll pan sensitivity/inertia, zoom limits, viewport selection, loaded-coverage pan clamping, and gesture-delta-to-model conversion. The selected/default range is an initial viewport, not a zoom-out ceiling; test configured expansion beyond it. These tests—not screenshots—prove interaction math.
- Add deterministic downsampling tests with narrow positive and negative spikes between quiet samples. Assert both extrema survive and that downsampled time ordering and endpoints remain valid.

Any temporary conformance `XCTExpectFailure` must name one known gap and its hass-frontend source, and the fixing implementation must remove it. Do not normalize expected failures as permanent parity tests.

### Integration tests

- Feed fixed Module 01 numeric and timeline series through classification, preparation, caching, render scheduling, and `BitmapLineChart`. Assert the card's own window reaches the renderer and stale/superseded render results cannot replace a newer viewport.
- Exercise empty -> loading -> rendered, changed history, zoom, pan, and hover-tooltip models without network access. Use bounded expectations/polling for asynchronous render completion rather than long sleeps.
- Queue multiple render requests, cancel or supersede all but the newest, and assert only the newest result is published. On disappearance, no render task may publish afterward.

### GUI rendering and visual regression

Use the existing macOS 12-compatible `MacViewPNGRenderer` approach: `NSHostingView` in a small offscreen borderless AppKit window, capture via `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`. Do not propose SwiftUI `ImageRenderer`, which is unavailable for the macOS 12/Swift 5.6/Xcode 13.4.1 toolchain.

- Retain light bitmap assertions at `320 x 160` for numeric geometry/colors/axes and `320 x 96` for state timelines. These should check exact bitmap dimensions, plot bounds, meaningful colored-pixel/region presence, and segment counts rather than full-system-control pixels.
- Render the complete history-graph view/card at `496 x 260` points and display scale `2`; retain the proven direct graph-content fixture at `496 x 178`. Fix dark appearance, color scheme, timestamps, locale/timezone, scale, hover time, and card options; use bounded polling until the asynchronous bitmap is beyond loading.
- Always write PNGs to `.build/render-artifacts/`. Require valid PNG signature, exact dimensions, nonblank output, expected graph/timeline color families, visible plot/axis regions, and a settled data region before comparison.
- Produce and manually review approved-reference candidates for at least: `graph-numeric-single.png`, `graph-numeric-multi.png`, `graph-state-timeline.png`, `graph-unknown-unavailable.png`, `graph-zoomed.png`, `graph-hover-tooltip.png`, `graph-empty.png`, and `graph-loading.png`.
- Compare each candidate with the identical fixture/state in `/Users/jin/Documents/HA/hass-frontend` or the live reference frontend. Only reviewed output belongs in `Tests/NativeHAMacTests/ReferenceImages/`, documented with the baseline macOS version and enforced with tolerant comparison. When a change is intentional, inspect actual, expected, and preferably a diff artifact before updating the baseline.

Approved screenshots do not prove step semantics, tooltip selection, effective range policy, downsampling correctness, interaction math, accessibility, lifecycle, or performance; those remain explicit tests above/below.

### Animation and interaction

- Render explicit model states instead of automating a trackpad: unzoomed, `4x` pointer-anchored zoom, expanded-beyond-default coverage, left/mid/right loaded-coverage pan clamps, hover over an exact point, hover between points, and tooltip near both plot edges. Assert each viewport/tooltip model and PNG is meaningfully distinct.
- For the required smooth y-axis transition, and any data transition that remains animated, expose deterministic interpolated state and render progress `0`, `0.5`, and `1`. Assert start/mid/end differ where expected and the end frame equals a stable final render. If the production code supports reduced motion, verify the intended reduced-motion behavior. Do not make real-time sleeps or scheduler timing the primary test.
- True trackpad vertical-scroll zoom, horizontal-scroll inertia, and event-to-frame hitch coverage is deliberately deferred to an XCUITest app target under newer Xcode. Xcode 13.4.1 does not expose `XCTHitchMetric`.

### Performance and lifecycle

- Separate cold parse/classify/prepare/cache population from warm cached bitmap rendering. Generate fixtures outside measured blocks and consume the prepared model/image so optimization cannot remove work.
- Store baselines for realistic `720`-point cold preparation/rendering and a stress `20,000`-point warm cached render at `496 x 178`, scale `2`, including the current proven `4x` zoom/pan fixture. Use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric` with warmed caches for warm paths.
- Measure downsampling of a `20,000`-sample spike fixture and assert spikes remain in the result. Measure repeated warm pan/zoom/hover renders across a fixed viewport sequence separately from preparation.
- If this module changes sampling/cache algorithms, keep the reusable benchmark and results under `Benchmarks/<topic>/` and compare correctness, elapsed time, CPU, and memory with live `1h` and `24h` data as well as adversarial fixtures.
- Measure render-request scheduling/cancellation under a burst of superseding viewports and repeated card appearance/disappearance. Assert canceled tasks do not publish and cached/render-task memory returns to a documented steady state.
- Keep renderer work off the main actor where the architecture permits. Add signposts around scheduling-to-publication only if the code is instrumented meaningfully; otherwise assert main-actor work is limited to state capture/publication and use a broad, documented responsiveness ceiling only as a safety net. Prefer stored XCTest performance baselines to tight machine-dependent milliseconds.

### Manual QA

- Compare the Home dashboard at selected `1h`, `3h`, and `12h` ranges with the corresponding reference data for step lines, timeline unknown/unavailable spans, previous-sample tooltip values, stable colors, and responsive warm trackpad zoom/pan/hover.
- At normal and narrow card widths, inspect x-axis label clipping/overlap, `Asia/Shanghai` locale/time formatting, line width, grid lines, tooltip placement near edges, legend wrapping/expanded layout, explicit y-axis options, and empty/loading/error presentation.
- Observe continuous y-axis response throughout zoom and inertial pan, plus reduced-motion behavior if supported. Manual review is still required for perceived animation smoothness; automated hitch testing is not available on this machine.

## Dependencies

- Module 01 for correct history stream data.
- Module 04 for graph card options.
- Module 05 for effective range and active-view lifecycle.
- Module 12 because only the active Lovelace view should drive active graph subscriptions.

## Risks

- Step-end paths may look visually different from existing screenshots. This is expected if aligning to HA state-history behavior.
- Logarithmic scale can be misleading with zero or negative sensor values. Guard strictly.
- Snapshot tests can be brittle across macOS versions. Prefer testing geometry/data preparation and only light bitmap smoke checks.
- Approving current output without hass-frontend comparison would lock in known step/hover/window defects. Reference approval must follow semantic fixes and review.
- Cache-warm rendering can hide cold preparation cost, while combined measurements can hide which phase regressed. Maintain separate cold, warm, scheduling, and cancellation baselines.
- Asynchronous renders can make snapshots capture loading or publish stale viewports. Use bounded readiness plus generation/cancellation assertions.

## Acceptance Criteria

- Graphs use the effective typed `AppConfig` range policy while preserving raw `hours_to_show`.
- Timeline graphs preserve `unknown` and `unavailable`.
- Numeric line graphs use step-end behavior.
- Hover/sample lookup matches state-history semantics.
- Time axes are readable for selected `1h`, `3h`, and `12h` ranges.
- Existing graph performance optimizations remain intact.
- Semantic tests pass for step-end paths, previous-sample hover, timelines/gaps, axes/ticks, stable colors, pointer-anchored zoom, inertial pan mapping/clamping, effective range selection/expansion, smooth y-axis transitions, and spike-preserving downsampling; fixed gaps no longer remain under `XCTExpectFailure`.
- Light bitmap checks and the full settled `496`-point history-graph render pass without network access, and all required PNG candidates are written to `.build/render-artifacts/` for manual reference review.
- Enforced visual references, when present, were reviewed against hass-frontend, are tied to a documented macOS version, and pass tolerant comparison.
- Stored metrics cover cold preparation, realistic render, `20,000`-point warm cached render, downsampling, repeated interaction renders, superseded-task cancellation, and lifecycle memory without unexplained regression.
- No completion test requires `ImageRenderer`, `XCTHitchMetric`, nondeterministic trackpad automation, live credentials, or an app/XCUITest target absent from the current package.
