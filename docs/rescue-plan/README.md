# NativeHA Rescue Plan Index

This directory contains implementation plans only. The current audit did not change Swift source and did not commit anything.

NativeHA is a WIP Swift-native Home Assistant frontend at current audited HEAD `dba01df` on `main`. The reference implementation is `/Users/jin/Documents/HA/hass-frontend`.

## Module Order

Implement in this order unless a future audit finds a blocker:

1. `module-02-websocket-multiplexer.md`
2. `module-01-history-ws-stream.md`
3. `module-04-lovelace-model-decode.md`
4. `module-03-appconfig-profile-isolation.md`
5. `module-12-sidebar-lovelace-views.md`
6. `module-05-dashboard-viewmodel-state.md`
7. Card/detail modules: `06`, `07`, `08`, `09`, `10`, `11`

Module 1 and later subscription-heavy modules depend on module 2. Module 12 and module 1 both remove the current global graph-hour tab model, so coordinate those changes.

## Dependency Map

| Module | Area | Depends On | Blocks |
|---|---|---|---|
| 01 | History `history/stream` | 02, partly 04 | 05, 09, detail history |
| 02 | WebSocket multiplexer | none | 01, 07 forecast, 08 templates |
| 03 | Server/profile preferences | none | 05, 12 cleanup |
| 04 | Lovelace decode robustness | 02 for fetch path only | 01, 05, 06, 07, 08, 12 |
| 05 | DashboardViewModel orchestration | 01, 02, 03, 04, 12 | Card behavior consistency |
| 06 | Entities/entity rows | 04, 05 | Current dashboard row correctness |
| 07 | Weather card | 02, 04, 05 | Forecast subscription later |
| 08 | Markdown card | 02, 04 | Template rendering later |
| 09 | Graph rendering | 01, 05 | History visual parity |
| 10 | Climate detail | 03, 05, 06 | More-info climate correctness |
| 11 | Fan detail | 05, 06 | More-info fan correctness |
| 12 | Lovelace views/sidebar | 04, partly 01 | Multi-view dashboard correctness |

## Live Dashboard Scope

The live server surface from the parent audit should drive prioritization before broad Home Assistant coverage:

- Three Lovelace views: `Home` (`default_view`), `3h` (`home_3h`), `12h` (`home_12h`).
- Flattened card types currently in use: `entities`, `history-graph`, `vertical-stack`, `weather-forecast`, `markdown`.
- History cards use per-card `hours_to_show` values `1`, `3`, and `12`. NativeHA currently overwrites these with a global selected-hour control.
- Weather cards currently use `show_forecast: false`. Current-state weather display matters before forecast rows.
- Entity surface is mostly sensors, switches, automations, device trackers, binary sensors, weather, `climate.room_ac`, and `fan.ac_unit_controller_ac_fan`.

## High-Confidence Corrections To Claude's Findings

- Do not generally remove `unknown`, `unavailable`, or `none` from history ingestion. The hass-frontend timeline path keeps these as timeline states with distinct colors. Numeric line graph preparation can skip nonnumeric samples in the line-only path.
- Module 1 cannot be implemented correctly on top of the current WebSocket client. Module 2 must provide a single receive loop and ID-based dispatch first.
- The global graph-hour tabs are not Home Assistant-like and conflict with the live dashboard. Preserve each history card's `hours_to_show`; use Lovelace views for `Home`, `3h`, and `12h`.
- AppConfig's personal data is acceptable as prototype bootstrapping, but it must be isolated behind a server profile/preferences boundary instead of being scattered into dashboard transformation and rendering.
- Weather forecast support is lower priority for the current live dashboard because `show_forecast` is false, but weather icon/current-state/units should be corrected now and forecast subscription should be designed against module 2.
- Graph rendering is not a failed subsystem. It already has useful bitmap rendering, timeline colors, parsing caches, and min/max downsampling. The remaining work is reference-aligned semantics and interaction polish, not a rewrite.

## Reference Anchors

Primary hass-frontend files cited by the module plans:

- History and stream semantics: `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts`
- History graph card: `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-history-graph-card.ts`
- Timeline chart/color: `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-timeline.ts`, `/Users/jin/Documents/HA/hass-frontend/src/components/chart/timeline-color.ts`
- Line chart behavior: `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line-data.ts`, `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line.ts`, `/Users/jin/Documents/HA/hass-frontend/src/components/chart/ha-chart-base.ts`
- Entity display/icons/toggle: `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_display.ts`, `/Users/jin/Documents/HA/hass-frontend/src/common/entity/state_icon.ts`, `/Users/jin/Documents/HA/hass-frontend/src/common/entity/can_toggle_domain.ts`, `/Users/jin/Documents/HA/hass-frontend/src/common/const.ts`
- Weather: `/Users/jin/Documents/HA/hass-frontend/src/data/weather.ts`, `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-weather-forecast-card.ts`
- Markdown: `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-markdown-card.ts`
- Lovelace models/views: `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/*.ts`, `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/hui-root.ts`, `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/views/hui-view.ts`

## Shared Testing Method

Use [`../visual-testing.md`](../visual-testing.md) for the macOS 12/Xcode 13.4.1 rendering harness, artifact approval workflow, performance-metric availability, and current-machine limits. Each module plan below adds the fixtures, sizes, states, interactions, lifecycle checks, and pass conditions specific to that module.

Keep the test layers distinct:

- Pure/core tests in `NativeHACoreTests` prove decoding, formatting, geometry, state machines, and reference-frontend semantic contracts without AppKit or network access.
- `@MainActor` offscreen GUI tests in `NativeHAMacTests` host SwiftUI in `NSHostingView` and capture through `bitmapImageRepForCachingDisplay(in:)` plus `cacheDisplay(in:to:)`; SwiftUI `ImageRenderer` is unavailable at the macOS 12/Swift 5.6 deployment level.
- Every GUI test writes a current PNG to `.build/render-artifacts/` and first checks signature, dimensions, nonblank content, expected regions/colors, and settled asynchronous state. An approved, macOS-version-labelled image belongs in `Tests/NativeHAMacTests/ReferenceImages/` only after manual comparison with `/Users/jin/Documents/HA/hass-frontend` or the live reference frontend; tolerant pixel comparison may then enforce it. Do not approve current NativeHA output mechanically.
- XCTest performance coverage uses `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, separates cold preparation from warmed interaction/update work, constructs fixtures outside measured blocks, and consumes measured results. Prefer stored baselines to machine-sensitive millisecond limits.
- True launch, accessibility traversal, event-to-frame hitch, trackpad/scroll deceleration, and end-to-end input timing remain later XCUITest work under a newer Xcode app target. Xcode 13.4.1 has no `XCTHitchMetric`; module completion must not depend on that unavailable API.

Default tests use fixed timestamps, appearance, logical sizes, display scale, color scheme, and—where the production API permits—locale/timezone. They do not use live Home Assistant state, credentials, or network access. Temporary `XCTExpectFailure` is acceptable only for a narrowly identified hass-frontend conformance gap, with a reason and removal required by the implementation that fixes it.
