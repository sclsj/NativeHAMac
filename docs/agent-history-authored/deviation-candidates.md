# Provenance-corrected NativeHA deviation candidates

This is a review report, not an approved deviation policy. It identifies direct
user requests for NativeHA to differ from the local `hass-frontend` reference,
including cases where the live Home Assistant configuration was only a
workaround for a different intended product behavior. It does not change
`AGENTS.md`, create `docs/user-deviations.md`, or alter any Swift or rescue-plan
file.

## 1. Method and provenance rules

I started from the second-pass Codex and Gemini provenance reports and the
consolidated user-authored ledger, then returned to the underlying root-user
turns when a possible deviation needed narrower interpretation. I searched both
Codex roles and both Gemini/Antigravity lineages, not just messages stored under
a user role. The relevant direct sources were:

- Codex root session **C10**,
  `rollout-2026-07-03T20-06-35-019f27df-a31d-7610-a337-4ffb7a33e71c.jsonl`,
  which contains the original NativeHA product choices and later graph work;
- Codex root session **C21**,
  `rollout-2026-07-16T20-57-09-019f6b00-99e2-7be0-bf09-6a61833dc8d3.jsonl`,
  including the current 2026-07-17 clarification;
- Gemini conversation **G-GRAPH**,
  `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, especially direct-user steps
  0, 261, 296, 299, 310, 537, 639, 686, 704, 719, 731, 743, 781, 793, and 808.

The eligibility rules were:

1. A user-role envelope was not enough. Long polished text was searched against
   earlier assistant/model output. Pasted model plans and parent-model subagent
   assignments were not attributed to the user.
2. For a mixed message, only a precise independent user delta was retained.
   Merely asking an agent to apply an AI-generated recipe did not make every
   mechanism in that recipe a durable product preference.
3. Sessions actually developing the obsolete `/Users/jin/Documents/HA/NativeHA`
   side experiment were ineligible. They were usable only as provenance sources.
   C10 and G-GRAPH operated on the current `/Users/jin/Documents/Computer/NativeHA`
   project and are eligible.
4. A deviation had to change intended behavior, UX, or architecture relative to
   literal reference copying, or explain that apparent reference configuration
   was not the intended product. Ordinary parity bug reports were excluded.
5. Old file names, symbols, commits, benchmark numbers, entity-specific failures,
   and failed experimental mechanisms were not promoted as durable wording.
6. Current Swift and rescue documents were read only to report implementation or
   plan conflicts. Their model-written conclusions were not treated as evidence
   of user intent.

The existing second-pass audits had already classified the native-app rule,
reference-improvement discussion, native graph scrolling, continuous animation,
and rendering-accuracy requirement as user-originated with no earlier model
source. For the newly isolated dashboard/time-range and layout-workaround
statements, exact/distinctive phrase searches found the direct C10 user turn
first; later assistant text and rescue documents are echoes, not precursors.

## 2. Confirmed current deviations

### D1. Duplicate `3h` and `12h` views are a workaround; use one graph-range control

**Intended deviation.** NativeHA should not treat the live `3h` and `12h` tabs as
distinct intended dashboards. They are duplicate-view workarounds for changing
graph history duration. NativeHA should expose one knob, selector, or equivalent
control that changes the time range of the graphs. Differences between those
views and `Home` are accidental configuration drift from the user not keeping
the copies synchronized; they are not intentional content or semantic
differences.

**Apparent hass/reference behavior.** The live configuration exposes three
Lovelace views (`Home`, `3h`, and `12h`) with separate card configurations and
per-card `hours_to_show`. A literal configuration-driven rewrite therefore
looks like it should preserve all three as separate navigable views.

**Earliest user source.** C10, direct Codex user,
`2026-07-03T12:56:40.945Z`: the user said not to model `3h` and `12h` as separate
dashboards, called them a Home Assistant hack, wanted all graphs to switch
between ranges, and anticipated adding another range such as `6h`.

**Current confirmation.** C21, direct Codex user,
`2026-07-17T02:54:29.489Z`, explicitly adds that the tab differences from
`Home` are only maintenance laziness and that the real UX is a graph time-range
knob/selection. This current clarification controls over contradictory generated
plans.

**AI-source search.** No earlier assistant/model precursor was found for the C10
semantic core. Later AI output repeatedly converted the observed live views into
a distinct-view requirement, which is the opposite of the direct user source.

**Durability, scope, confidence.** NativeHA-wide dashboard and graph UX;
`CONFIRMED_CURRENT`; very high confidence. The control's exact visual form is
not fixed: “knob/selection” describes its function, not a mandate for a rotary
knob.

**Current code/plan conflict.** Current Swift is substantially aligned:
`AppConfig.swift:15-16`, `DashboardView.swift:63-81`, and
`DashboardViewModel.swift:6,85-94` implement a global range selection. The
rescue plan conflicts directly:

- `docs/rescue-plan/README.md:19,42-44,52` says to remove the global range model
  and preserve the three views;
- `module-01-history-ws-stream.md:98-100,181,198` makes card-local duration the
  sole contract;
- `module-05-dashboard-viewmodel-state.md:20-25,92,192,220` plans the same
  distinct-view/per-card conversion;
- `module-09-graph-rendering.md:79-82` removes global selected hours; and
- `module-12-sidebar-lovelace-views.md:60-63,84-103,188,210-211` explicitly says
  not to collapse the `3h`/`12h` views and to remove the selector.

Those statements should be corrected before Modules 01, 05, 09, or 12 are
implemented. Reference decoding can still preserve the raw views and per-card
values without presenting accidental duplicate views as intended navigation.

**Suggested canonical wording for `docs/user-deviations.md`.**

> The live `3h` and `12h` Lovelace views are maintenance workarounds, not
> intended separate dashboards. Their differences from `Home` are accidental.
> NativeHA should present the Home dashboard once and provide one configurable
> graph time-range selector that changes the displayed history range for the
> graphs; do not derive product navigation or content differences from those
> duplicate views.

## 3. Other high-confidence user-authored deviation candidates

### D2. Treat the live `vertical-stack` layout as a visual-layout workaround

**Intended deviation.** For this dashboard, the literal `vertical-stack`
structure exists to force a particular visible layout in Home Assistant.
NativeHA should reproduce the intended three-column visual arrangement rather
than mechanically preserve stack grouping when that produces a different
layout. The native layout should remain adjustable in code.

**Hass/reference behavior.** The YAML expresses card grouping through
`vertical-stack`; a literal Lovelace renderer would normally treat that
structure as semantic layout input.

**Earliest user source.** C10, direct Codex user,
`2026-07-03T12:56:40.945Z`, in the same first visual correction: the user called
the stack a hack for a specific Home Assistant layout, asked for the visible
layout to be copied, and asked that it remain adjustable in code.

**AI-source search.** No earlier model precursor was found for this distinctive
workaround explanation. Later AI-authored rescue text instead elevates Lovelace
layout and masonry rules over the local layout hints.

**Durability, scope, confidence.** High confidence for the user's current
personal default dashboard; narrower than a general rule to ignore
`vertical-stack` in arbitrary dashboards. This is a profile-specific exception,
not permission to discard decoded layout information globally.

**Current code/plan conflict.** Current Swift largely follows the request:
`AppConfig.swift:22-26,46-55` and `DashboardViewModel.swift:53-71` own a
three-column configurable arrangement. `module-12-sidebar-lovelace-views.md:
100-103` plans to make those rules merely secondary hints and use Lovelace/
masonry layout as the default, which can regress the intended dashboard.

**Suggested canonical wording.**

> On the user's default dashboard, `vertical-stack` is a Home Assistant layout
> workaround rather than desired native grouping. Preserve the raw config, but
> render the intended three-column visual composition and keep its column count,
> sizing, spacing, and placement rules configurable in `AppConfig.swift`. Do not
> generalize this exception to unrelated dashboards without evidence.

### D3. Build a genuinely native macOS replacement, not a web wrapper

**Intended deviation.** NativeHA deliberately replaces the browser runtime and
web implementation architecture with SwiftUI/AppKit/CoreGraphics. It must not
embed `hass-frontend` through JavaScript or WebView merely to obtain parity.

**Hass/reference behavior.** The reference is a TypeScript/Lit/CSS/ECharts web
application running in browser primitives.

**Earliest user source.** C10, direct Codex user,
`2026-07-03T12:08:01.901Z`, requested a Swift-native Home Assistant app for
better performance; at `2026-07-03T12:19:43.575Z` the user clarified that it is
a full Lovelace replacement with no JavaScript or WebView because those are
slow.

**AI-source search.** Codex provenance candidate 12 classified this core
`USER_ORIGINATED` and found no earlier model match.

**Durability, scope, confidence.** Project-wide architecture; very high
confidence. Reference semantics and visible behavior remain the oracle except
for approved deviations; “native” is not permission to invent behavior.

**Current code/plan conflict.** Current Swift, README direction, and rescue
Module 09 comply. No current conflict found.

**Suggested canonical wording.**

> NativeHA is a native macOS replacement. Implement reference behavior using
> Swift, SwiftUI, AppKit, and native rendering; do not use JavaScript or WebView
> as the app architecture.

### D4. Improve numeric-chart y-axis transitions beyond hass web

**Intended deviation.** When zooming or inertially scrolling changes the visible
data minimum/maximum, the numeric y-axis should update smoothly and continuously
during the interaction. It must not freeze and then jump to its new range when
the gesture or inertia finishes. The exact interpolation/filter algorithm is
not approved by history and remains configurable/empirical.

**Hass/reference behavior.** The user found hass web's vertical range change too
sudden as well as disliking NativeHA's abrupt version. This is an explicit case
where merely matching web behavior is not the desired result.

**Earliest user source.** G-GRAPH, direct Gemini user step 296,
`2026-07-07T13:17:22Z`: the user described sudden visible-range rescaling, asked
to inspect hass-frontend, explicitly said they were not happy with web's
behavior either, and requested discussion before edits. Direct steps 704, 719,
731, and 743 on 2026-07-13 repeatedly clarified that the y-axis must change
during vertical scroll/inertia rather than only at completion.

**AI-source search.** Gemini provenance P4 and V2 classify the preference and
continuous-update core as `USER_ORIGINATED`, with no earlier AI source. The
assistant-generated alternative algorithms after step 296 are not part of the
user-authored core.

**Durability, scope, confidence.** High confidence for interactive numeric
history graphs. The goal is durable; low-pass filtering, hysteresis, look-ahead,
and precomputed temporal interpolation are experiments, not mandated solutions.

**Current code/plan conflict.** Production `GraphRendering.swift:301-305`
recomputes a fresh axis directly from each visible frame, with no persistent
transition state. `GraphDemoView.swift:9-10,30-37,66-75,376-410` contains an
experimental configurable interpolated/sticky comparison, but that behavior is
not the production chart contract. `module-09-graph-rendering.md:109-113`
discusses bounds and scale safety but does not preserve the smoother-than-web
transition requirement.

**Suggested canonical wording.**

> Numeric graph y-axis bounds should respond continuously and smoothly while
> zoom or inertial scrolling changes the visible data range; do not defer the
> entire rescale and jump at interaction completion. Keep interpolation,
> look-ahead, and hysteresis parameters in `AppConfig.swift`, and select the
> mechanism through visual and performance testing rather than copying hass
> web's abrupt transition.

### D5. Use trackpad-native graph navigation semantics

**Intended deviation.** Optimize graph interaction for the user's trackpad:
vertical scrolling zooms around the pointer position; horizontal scrolling pans
smoothly with normal macOS inertia; and a given horizontal gesture should feel
consistent across zoom levels. User interaction takes priority over background
graph updates.

**Hass/reference behavior.** `hass-frontend`/ECharts supplies browser event and
data-zoom behavior. NativeHA needs a deliberate macOS event mapping rather than
a literal translation of wheel/browser mechanics. Some individual semantics may
coincide with ECharts, but the native gesture contract is an intentional
platform adaptation.

**Earliest user source.** C10 direct Codex user:

- `2026-07-03T12:56:40.945Z`: the user said they use trackpad, not mouse;
- `2026-07-06T06:45:58.487Z`: zoom should center on the pointer rather than the
  newest/right endpoint and interaction should outrank background work;
- `2026-07-06T12:05:19.477Z`: vertical scrolling should zoom and horizontal pan
  sensitivity should be consistent across zoom levels.

G-GRAPH direct user step 639, `2026-07-13T05:07:19Z`, independently requires
vertical-scroll zoom and smooth horizontal scrolling with default macOS inertia.

**AI-source search.** Gemini provenance V3 and Codex provenance candidate 35
classify the native scrolling and user-priority cores as user-originated; no
earlier model source was found. Implementation equations remain engineering
choices.

**Durability, scope, confidence.** High confidence for graph interaction on
macOS. It makes trackpad behavior primary, not mouse input forbidden.

**Current code/plan conflict.** Production `CardViews.swift:337-352,746-773,
885-900` already implements cursor anchoring, zoom-adjusted pan sensitivity,
vertical-scroll zoom, and horizontal pan. Native inertia appears to rely on the
sequence of AppKit scroll events rather than an explicit model, so runtime
verification is still required. Module 09 mentions anchoring and pan clamping
but does not state the full native gesture contract.

**Suggested canonical wording.**

> Graph interaction is trackpad-first: vertical scrolling zooms at the pointer,
> horizontal scrolling pans with normal macOS smooth inertia, and comparable
> gestures have comparable effect across zoom levels. Foreground interaction
> must preempt or defer background graph updates. Preserve mouse accessibility,
> but do not compromise trackpad behavior to mimic browser wheel handling.

### D6. Performance deviations may not reduce rendering accuracy

**Intended deviation.** NativeHA is intended to outperform the web frontend and
may choose faster native rendering/algorithms, but not by silently losing graph
features, peaks, or rendering accuracy. If further speed requires a quality
tradeoff, report that boundary rather than assuming it.

**Hass/reference behavior.** The web graph was too slow for the user's high-rate
history. NativeHA therefore need not copy ECharts' internal architecture, but
the reference's observable graph semantics remain required.

**Earliest user source.** C10 direct user,
`2026-07-03T12:08:01.901Z`, defines improved performance as the app goal.
G-GRAPH direct user step 0, `2026-07-07T09:23:30Z`, contains the distinctive
instruction that the user is not willing to sacrifice rendering accuracy.

**AI-source search.** Gemini provenance F1 and Codex provenance candidates
13/34 classify these cores as user-originated; no earlier model source was
found.

**Durability, scope, confidence.** Project-wide graph/performance decisions;
very high confidence. It is permission to use different native internals, not a
license to change data semantics.

**Current code/plan conflict.** The current CoreGraphics/min-max path and rescue
Module 09's instruction to retain spike-preserving downsampling are compatible.
No direct conflict found, though every future algorithm substitution still
needs correctness comparison.

**Suggested canonical wording.**

> NativeHA may depart from hass-frontend's internal algorithms for measured
> native performance gains, but must preserve observable semantics and rendering
> accuracy. Do not discard spikes or visible detail merely to hit a speed target;
> surface any unavoidable quality/performance tradeoff for user decision.

### D7. Hide raw entity IDs by default, with an optional diagnostic display

**Intended deviation.** Ordinary dashboard presentation should hide raw names
such as `sensor.example_name` by default and display friendly/derived names. A
user-accessible setting may expose IDs when useful.

**Hass/reference behavior.** Home Assistant normally emphasizes friendly names,
so the default may be parity rather than a true deviation. The explicit in-app
ID toggle is an extra NativeHA diagnostic affordance.

**Earliest user source.** C10 direct user,
`2026-07-03T12:56:40.945Z`.

**AI-source search.** This appears in the first direct visual-correction turn;
no earlier AI precursor was found. Later code and assistant summaries echo it.

**Durability, scope, confidence.** High confidence user-authored request, but
medium confidence that it belongs in a *deviations* file rather than general UI
configuration because its default aligns with reference intent.

**Current code/plan conflict.** `AppConfig.swift:14`,
`DashboardViewModel.swift:14`, and `DashboardView.swift:85-89` implement it.
No conflict found.

**Suggested canonical wording.**

> Show friendly/derived entity names by default. Keep raw entity IDs hidden in
> normal dashboard presentation, with an optional configurable diagnostic
> display.

## 4. Feature-specific or stale deviations not to promote without confirmation

These are authentic or partly authentic user requests, but history does not
support making them durable project-wide deviations now.

### S1. Replace Home Assistant's two-step fan-speed-from-off UX

In C10 at `2026-07-05T05:45:57.534Z`, the user said they were not sure they
liked needing two clicks to choose a non-default fan speed from off and asked
for alternatives. This is a real dissatisfaction with the reference, but the
user never selected one of the resulting approaches. **Ask before promotion.**

### S2. Exact graph zoom floor

G-GRAPH step 261 asked for a configurable maximum zoom with a suggested
30-minute visible range. Step 310 later temporarily relaxed the demo to roughly
ten samples, and current code combines a configurable visible-sample percentage
with a hardcoded 30-minute time floor (`CardViews.swift:775-818`). The durable
part is configurability; the preferred default/rule is unsettled. **Do not
promote the number without confirmation.**

### S3. Full-resolution versus quick/settled graph rendering

C10 contains evolving instructions: attempt a cheap high-frame-rate interaction
pass followed by a better graph, then try full-resolution interaction when it
became smooth, and perhaps expose that as a preference. Later investigations
changed algorithms again. README still describes a low-detail/high-detail split
and a missing/stale configuration name. **Treat this as historical experiment,
not settled product behavior.** The current instruction to make meaningful
choices configurable can govern a new measured design.

### S4. Demo-only data windows and FPS target

G-GRAPH step 537 requested one-day demo data and a goal above 120 FPS; other
turns moved between 3 hours, 12 hours, one day, and ten days for diagnosis. The
second-pass audit already found the numeric target authentic but scoped to that
demo. **Do not make one day or 120 FPS global acceptance criteria.**

### S5. Specific climate preset temperatures and personal entity overrides

C10 directly supplied `activity`/`sleep` temperatures and asked that they be
configuration variables. It also asked to hide obsolete sensors and insert an
AC entity missing from the temporary dashboard configuration. These are
personal profile data, not reference-product deviations. Current
`AppConfig.swift:28-55` contains them. **Keep them configurable/profile-scoped;
do not state them as general NativeHA behavior.**

### S6. Ignore tiny visual differences

C10 at `2026-07-05T12:38:31.112Z` said not to bother when climate-control
differences were only slight. It was a one-off stopping judgment after many
pixel-level iterations and conflicts with later broad reference-parity work.
**Do not promote it as a global visual tolerance.**

### S7. Exact y-axis algorithm

The user asked for an experimental side-by-side demo with configurable
low-pass/hysteresis settings (G-GRAPH step 299) and later proposed precomputing
temporal interpolation (steps 686 and 731). Those were attempts to reach D4,
not a stable algorithm choice; some surrounding changes regressed and were
rolled back. **Promote D4's observable behavior only.**

## 5. Rejected AI-originated deviation ideas

1. **Treat all three live views as intentional product navigation.** The rescue
   plan's “do not collapse” rule was generated from observed configuration and
   directly contradicts both the earliest C10 user instruction and the current
   clarification. It is rejected as user intent.
2. **Adopt the detailed assistant-generated climate animation recipe as a
   user-authored deviation.** Long text pasted in C10 describes SVG dash offsets,
   exact cubic-bezier timing, geometry, and typography. The eligible user core
   was much narrower: fix the control, update optimistically, and make the motion
   resemble HA. The technical prose is not an independently authored deviation
   and mostly seeks parity anyway.
3. **Mandate one of the assistant's y-axis approaches.** “Approach 2/3,” the
   initial interpolation/sticky algorithms, and their parameters came from the
   model discussion the user requested. Asking for a comparison demo did not
   adopt either as permanent behavior. Only the independently repeated smooth,
   continuous outcome in D4 survives.
4. **Promote the AI-written golden-image, animation-keyframe, XCTest metric, or
   lifecycle recipes as user deviations.** The Codex provenance audit already
   traced those mechanisms to a generated prompt pasted back by the user. They
   may be useful engineering proposals, but are neither product deviations nor
   user-authored preferences.
5. **Infer a general redesign license from “doing things the Swift way.”** The
   user-authored rule permits native implementation and measured performance
   improvements without fundamentally changing logic. It does not authorize
   unrequested UI or semantic changes; explicit items such as D1-D5 are needed.

## 6. Recommended subset

### Add now

Add D1-D6 to `docs/user-deviations.md`, with D1 first and marked as the current
correction to Modules 01/05/09/12. D2 must stay scoped to the user's default
dashboard, while D3 and D6 are project-wide architecture/performance boundaries.
D4 and D5 are graph-interaction contracts whose mechanisms remain configurable.

D7 is safe to record if the deviations file also owns NativeHA-only product
additions. Otherwise leave it in general AppConfig/UI guidance because its
default behavior is already close to Home Assistant.

### Ask the user about

- Which one-step fan-speed-from-off interaction should replace the reference UX
  (S1).
- What production zoom limit should be the default, and whether it is time-based,
  sample-based, or both (S2).
- Whether interactive rendering should always be full quality or expose a
  quick/settled quality mode (S3).

Do not ask again about the duplicate dashboard tabs: D1 is explicitly confirmed
in the current turn.

## Audit counts and checks

- 1 current-turn confirmed deviation.
- 6 additional high-confidence user-authored candidates.
- 7 authentic but feature-specific, stale, or confirmation-sensitive items.
- 5 rejected AI-originated or model-inferred ideas.
- 208 direct Gemini user envelopes were available to the second-pass corpus; 36
  direct messages in the primary current-project G-GRAPH conversation were
  re-examined for this deviation pass, together with the relevant C10/C21 Codex
  root turns and both prior provenance reports.

No secret value, access token, private URL, phone number, or long transcript
passage is copied into this report.
