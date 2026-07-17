# User-approved deviations from hass-frontend

This file is the canonical list of intentional NativeHA deviations from the
`/Users/jin/Documents/HA/hass-frontend` reference. These entries override
literal reference parity and conflicting rescue-plan text. Do not infer other
deviations from implementation convenience or old chat plans.

## Dashboard graph time range

- The live `3h` and `12h` Lovelace views are maintenance workarounds, not
  intended separate dashboards. Their differences from `Home` are accidental;
  the user was simply not keeping the duplicate configurations synchronized.
- Present the intended Home dashboard once and provide one knob, selector, or
  equivalent control that changes the displayed time range for the graphs.
- Keep the available ranges, default range, and selector policy configurable in
  `Sources/NativeHAMac/AppConfig.swift`.
- This overrides rescue-plan statements in Modules 01, 05, 09, and 12 that say
  to remove the global range selector or preserve `Home`/`3h`/`12h` as intended
  separate navigation and content.

## Default-dashboard layout

- On the user's default dashboard, `vertical-stack` is a Home Assistant layout
  workaround used to obtain the desired appearance. It is not desired native
  grouping semantics.
- Preserve the raw decoded configuration, but render the intended three-column
  composition. Keep column count, dimensions, spacing, and placement rules
  configurable in `AppConfig.swift`.
- Do not generalize this personal-dashboard exception to unrelated dashboards
  without an explicit user instruction.

## Native architecture

- NativeHA is a native macOS replacement, not a wrapper around the web
  frontend. Implement behavior with Swift, SwiftUI, AppKit, CoreGraphics, and
  other native APIs; do not use JavaScript or WebView as the app architecture.

## Numeric graph y-axis transitions

- While zooming or inertially scrolling changes the visible numeric range, the
  y-axis must respond smoothly and continuously. It must not remain frozen and
  jump only when the interaction ends.
- The user is not satisfied with hass web's abrupt transition either, so
  copying that behavior is not the goal.
- Keep the interpolation, look-ahead, hysteresis, and related tuning choices
  configurable in `AppConfig.swift`; select them through visual and performance
  testing rather than treating an old experimental algorithm as canonical.

## Trackpad-native graph navigation

- Graph interaction is trackpad-first. Vertical scrolling zooms at the pointer;
  horizontal scrolling pans with normal macOS smooth inertia; comparable
  gestures should have comparable effect across zoom levels.
- Foreground interaction takes priority over background graph work. Preserve
  mouse accessibility, but do not compromise trackpad behavior to imitate
  browser wheel handling.

## Performance and rendering accuracy

- NativeHA may use different native algorithms and rendering architecture for
  measured performance gains, but must preserve observable Home Assistant
  semantics and rendering accuracy.
- Do not discard spikes or visible detail merely to reach a speed target. If an
  unavoidable quality/performance tradeoff remains, present it for user choice.

## Approved future intent — not implemented yet

These are approved product intentions. Their presence here does not claim the
current application implements them.

### Expand graph history beyond the initial range

- A graph's selected/default range (`1h`, `3h`, and so on) is its initial
  viewport, not a zoom-out ceiling. Allow the user to continue zooming out and
  fetch or reuse older history as needed.
- Make this behavior configurable globally and overrideable per graph. Include
  whether range expansion is enabled, an optional hard maximum such as `24h` or
  `2d`, and the gesture-distance threshold required before expanding beyond the
  initial range.
- Expansion must remain smooth and must not block panning, dismissal, or other
  UI while older data is loaded and prepared.

### Idle history prefetch and range reuse

- Retain fetched history/data in memory so dashboard changes and time-range
  changes can reuse coverage already fetched instead of issuing the same
  request again.
- When the app is idle, prefetch a configurable window—initially `24h`—for all
  entities referenced by the loaded dashboard configuration so the data is
  ready before a graph requests it.
- Prefetch is lower priority than foreground input, live updates, and visible
  rendering. It must be asynchronous, cancellable, deduplicated with foreground
  requests, and constrained by the configurable cache budget in
  `docs/configurability.md`.

## Historical candidates

Unapproved or feature-specific possibilities remain in
`docs/agent-history-authored/deviation-candidates.md`. They are not active
deviations and should not be read during ordinary implementation unless the
user requests a new deviation audit.
