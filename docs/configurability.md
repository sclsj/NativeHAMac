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

**Implementation note:** The three timings already exist as raw nanosecond
constants in `AppConfig.swift`; they have not yet been consolidated into a
typed scheduling policy.

### 4. Graph zoom and pan interaction

**Intent:** Make graph navigation bounds and feel deliberate and testable for
trackpad-first use.

Configure zoom/sample limits, minimum visible duration, pan sensitivity,
activation thresholds, live-edge thresholds, beyond-default-range behavior,
and optional per-graph overrides. Normalize and document how time- and
sample-based limits interact.

**Implementation note:** One zoom value is in `AppConfig.swift`, while other
limits and thresholds remain distributed literals.

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

Configure command timeout, per-subscription buffered-delivery capacity, and the
connection-wide maximum number of concurrently executing subscriber callbacks
as one typed WebSocket policy. Timeout must remove pending command ownership
exactly once. Capacity overflow must terminate only the slow subscription; it
must not block the socket receiver, reorder another subscription, or create an
unbounded task backlog. Cancellation is requested for in-flight callbacks, but
arbitrary non-cooperative async callbacks cannot be forcibly stopped; they stay
explicitly owned and counted against the connection-wide callback limit until
they return.

**Implementation note:** Module 02 defines `WebSocketPolicy` in
`AppConfig.swift` with a 10-second command timeout and a 256-event buffered
capacity. At most four subscriber callbacks execute concurrently, which bounds
retained in-flight callback work even during repeated subscription churn.
Reconnect timing remains internal reference-parity behavior rather than a
selected product configuration surface.

## Not selected

Render-resolution, reconnect timing, axis-density, and off-live-edge update
policies remain historical candidates rather than approved configuration
requirements. Revisit them only when the user selects them or a current task
requires a material product choice.
