# User-approved NativeHA configurability

This file is the canonical list of product, performance, and resource choices
that should be configurable in
`Sources/NativeHAMac/AppConfig.swift`. It records intended configuration even
when the current implementation is partial or absent. Agents must read and
maintain this file; do not treat the historical candidate report as active
guidance.

“Configurable” here means a typed Swift value or policy in `AppConfig.swift`.
It does not require an in-app settings UI. Defaults must be validated with
reference behavior, live testing, visual correctness, and benchmarks as
appropriate rather than copied from this file without checking the current
code.

## General rule

- If a hardcoded choice can serve a useful product, performance, debugging, or
  resource-management purpose, expose it through `AppConfig.swift`.
- This includes useful hass defaults/constants, ambiguous algorithms,
  thresholds, timing, ranges, layout, interaction behavior, detail budgets,
  cache budgets, and adaptive crossover points.
- Prefer a typed policy or enum over unrelated scalar constants when multiple
  values jointly define one behavior.
- Configuration does not make reference-correct semantics optional. Diagnostic
  or lower-fidelity modes must be explicit, and fidelity-preserving behavior
  remains the default unless the user approves otherwise.
- When an implementation changes one of the following surfaces, update its
  implementation note here in the same commit.

## Approved configuration surfaces

### 1. Graph time-range selection

**Intent:** One selector changes graph time range without maintaining duplicate
`Home`, `3h`, and `12h` dashboards. The initial/default display range is not the
same thing as the maximum range reachable by zooming.

Configure a typed time-range policy including:

- available selections and the default selection;
- whether selection is global, per-dashboard, or per-graph;
- detail/pop-up defaults;
- whether a graph may zoom out beyond its selected/default range;
- an optional maximum history range and the gesture threshold for expanding
  beyond the initial range.

**Implementation note:** Module 01 now defines a typed `GraphTimeRangePolicy`
in `AppConfig.swift` with available selections, default selection, global
scope, and the detail default. It also exposes disabled expansion-policy seams
without implementing them. Arbitrary range expansion, an expansion maximum,
and gesture-driven fetch behavior remain future Module 09/cache work.

### 2. Graph sampling and detail budget

**Intent:** Make downsampling strategy and the amount of retained detail
explicit. Preserve spikes and visible accuracy by default.

Configure a typed sampling policy including algorithm, details per pixel,
minimum details per series, multi-series budget behavior, and any measured
data-size crossover. Candidate algorithms should include the native and
reference min/max approaches, a no-loss diagnostic oracle, and other sensible
algorithms established by research and benchmarks. Do not promote an algorithm
solely because it is faster.

**Implementation note:** Production currently uses a fixed min/max path and
hardcoded detail formula; benchmark targets contain alternatives, but the
production policy is not yet configurable.

### 3. Live-update and render scheduling

**Intent:** Treat state coalescing, graph render delay, and post-interaction
quiet time as one scheduling policy rather than unrelated raw timing values.

Configure typed durations and, where useful, immediate/low-latency and batched
profiles. Defaults must avoid render storms without starving the final update
or delaying foreground interaction.

**Implementation note:** `AppConfig.swift` now groups realtime-state
coalescing, live-data render delay, and post-interaction defer time in a typed
`GraphRenderSchedulingPolicy`. Viewport rendering itself uses one serialized
in-flight render plus one overwriteable latest request; that is a progress and
ownership invariant rather than a selectable fidelity mode.

### 4. Graph zoom and pan interaction

**Intent:** Make graph navigation bounds and feel deliberate and testable for
trackpad-first use.

Configure zoom/sample limits, minimum visible duration, pan sensitivity,
activation thresholds, live-edge thresholds, beyond-default-range behavior,
optional per-graph overrides, and whether the floating hover/crosshair sample
overlay is shown. Normalize and document how time- and sample-based limits
interact. Hiding hover diagnostics must not disable scroll, zoom, or pan input.

**Implementation note:** One zoom value is in `AppConfig.swift`, while other
limits and thresholds remain distributed literals. A typed
`GraphInteractionPolicy` now keeps the hover overlay enabled by default. For
repeatable visual/gesture capture without changing code, launch with
`NATIVEHA_GRAPH_HOVER_OVERLAY=0` (also accepts `false`, `no`, or `off`);
`1`, `true`, `yes`, and `on` explicitly enable it. Unknown values preserve the
normal enabled default. This setting gates only overlay drawing; the gesture
overlay and its zoom/pan callbacks remain installed.

### 5. History and prepared-series memory cache

**Intent:** Reuse fetched history/data and prepared graph series when switching
dashboards or time periods instead of fetching or recomputing the same range.

- The default adjustable cache memory budget is **1 GiB** (approximately 1 GB)
  (`1_073_741_824` bytes). This is an upper bound, not eager allocation; the app
  currently uses roughly 100 MB before this expanded caching work.
- Account for raw fetched history and prepared graph-series storage under one
  total budget, or explicit sub-budgets whose configured total does not exceed
  that budget.
- Make eviction strategy, entry safeguards, byte estimation, and a disabled
  diagnostic mode configurable. Prefer reuse of recently accessed dashboard,
  entity, and time-range data; select exact policies through measurement.
- Cache lookup must understand time-range coverage. A cached `24h` range should
  be able to satisfy a contained `1h` request, and a partially covered request
  should fetch only missing data when the server API and correctness permit.
- Expose cache statistics and reset hooks needed to compare cold and warm
  correctness, latency, and memory behavior.

**Implementation note:** The current prepared-series cache has a hardcoded
96-entry FIFO limit. A shared byte-budgeted history/prepared cache and range
reuse are not yet implemented. Approved idle prefetch behavior is recorded in
`docs/user-deviations.md` under **Approved future intent**.

### 6. Fixed or responsive dashboard layout

**Intent:** Keep the current three-column desktop composition available while
making fixed versus responsive layout an explicit policy.

Configure sidebar width/behavior, column count and width, spacing, outer
padding, minimum window size, and responsive limits together. Decoded Lovelace
layout semantics still take precedence except for an explicit approved
deviation.

**Implementation note:** Several fixed layout constants already live in
`AppConfig.swift`, but they are not yet one typed policy and responsive behavior
is not implemented.

### 7. WebSocket command and subscription delivery safety

**Intent:** Keep the transport responsive and memory-bounded without making
protocol correctness optional.

Configure command timeout, the maximum accepted incoming WebSocket message,
per-subscription buffered-delivery capacity, and the connection-wide maximum
number of concurrently executing subscriber callbacks as one typed WebSocket
policy. Timeout must remove pending command ownership exactly once. The receive
limit is a per-message upper bound, not eager allocation, and must be applied to
the concrete URLSession task before it resumes. Capacity overflow must terminate
only the slow subscription; it must not block the socket receiver, reorder
another subscription, or create an unbounded task backlog. Cancellation is
requested for in-flight callbacks, but arbitrary non-cooperative async callbacks
cannot be forcibly stopped; they stay explicitly owned and counted against the
connection-wide callback limit until they return.

**Implementation note:** Module 02 defines `WebSocketPolicy` in
`AppConfig.swift` with a 10-second command timeout and a 256-event buffered
capacity. Module 01 adds a typed 32 MiB (`33_554_432` byte) receive policy.
That bound covers the measured 24-hour four-series SPS30 response of
26,490,281 bytes and the exact 12-hour CO2/VOC stream replay of 4,912,600
bytes, while remaining finite; URLSession's 1 MiB default rejected the latter
and tore down the shared connection. At most four subscriber callbacks execute
concurrently, which bounds retained in-flight callback work even during
repeated subscription churn. Reconnect timing remains internal reference-parity
behavior rather than a selected product configuration surface.

### 8. Diagnostic logging selection and persistence

**Intent:** Preserve every diagnostic selected by configuration, including full
payloads needed to investigate failures, while allowing completed subsystems to
raise their minimum recorded severity independently.

Configure a minimum severity independently for WebSocket, other network,
rendering, interaction, lifecycle, and general diagnostics. A disabled
subsystem is represented explicitly. Once an entry passes that filter, retain
its complete message without database-size deletion, message truncation, queue
admission limits, or silent dropping.

**Implementation note:** `LoggingPolicy` now has independent optional minimum
severities for WebSocket, other network, rendering, interaction, lifecycle, and
general diagnostics. `nil` disables one subsystem. The app selects `warning`
for the completed WebSocket subsystem and `debug` for the others; changing only
WebSocket back to `debug` records complete text frames and base64-encoded binary
frames.

The former 128 MiB database ceiling, 4,096-character truncation, and
1,024-entry admission limit remain removed. Accepted entries are buffered
without an admission ceiling and written on a utility queue in one explicit
SQLite transaction every second or after 256 entries. SQLite uses WAL mode,
`FULL` synchronization, a 1,000 ms busy wait, and one-second lossless retry:
temporary writer contention requeues the complete batch ahead of newer entries
instead of dropping it. Normal application termination forces a final flush.
An abrupt crash can still lose the current memory-resident interval; increasing
the interval toward one minute would reduce commits further but enlarge that
crash window.

### 9. Graph crosshair tooltip precision

**Intent:** Let deployments override the number of digits shown by graph
crosshair tooltips without losing Home Assistant's entity-specific defaults,
localized units, or full timestamp context.

Configure one typed `GraphTooltipFormattingPolicy` with:

- a time mode of Home Assistant default, minute, second, or a bounded number of
  fractional-second digits;
- an optional global numeric digit override; and
- optional per-entity numeric digit overrides.

Numeric overrides are clamped to 0...15 digits. Precedence is per-entity
override, global override, Home Assistant's effective entity-registry
`display_precision`, Home Assistant's integer state/integer step rule, then the
canonical parsed numeric value's decimal digits. Explicit precision fixes both
minimum and maximum digits, so requested trailing zeros remain visible.

**Implementation note:** `AppConfig.swift` now defines
`GraphTooltipFormattingPolicy`; production defaults to `.homeAssistant`, no
global numeric override, and no per-entity overrides. NativeHA fetches the
compressed `config/entity_registry/list_for_display` response and uses its
effective `dp` field rather than separately interpreting
`suggested_display_precision`. It also fetches the frontend `language`
preferences and retains the REST `HAConfig` timezone. The Home Assistant time
default is a localized full date and time with seconds and no fractional
seconds. Locale and timezone fall back to the current macOS values when Home
Assistant preference data is absent. These settings affect crosshair tooltip
labels; graph-axis time labels remain unchanged.

### 10. Lovelace primary navigation

**Intent:** Keep deployment-specific primary-navigation exclusions and the
versioned native selection-preference key explicit without adding a settings
or server-profile UI.

Configure one typed `LovelaceNavigationPolicy` with:

- exact source paths excluded only from primary navigation; and
- the versioned persistence key for the last unambiguous eligible primary
  view.

**Implementation note:** Module 12 defines `LovelaceNavigationPolicy` in
`AppConfig.swift`. The fixed personal deployment excludes exact paths
`home_3h` and `home_12h` from primary navigation while preserving their raw
configuration and explicit route lookup. The preference key is
`nativeha.navigation.selected-primary-view.v1`; its property-list value stores
only a unique nonempty path or a source index for a pathless view. It stores no
server, token, profile, resolved identity, hash, content revision, or
timestamp. This policy does not add a settings UI and does not alter the
existing token/bootstrap path.

## Not selected

Render-resolution, reconnect timing, axis-density, and off-live-edge update
policies remain historical candidates rather than approved configuration
requirements. Revisit them only when the user selects them or a current task
requires a material product choice.
