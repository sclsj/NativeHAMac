# User-approved deviations from hass-frontend

This file is the canonical list of intentional NativeHA deviations from the `/Users/jin/Documents/HA/hass-frontend` reference. These entries override literal reference parity and conflicting rescue-plan text. Do not infer other deviations from implementation convenience or old chat plans.

## Dashboard graph time range

- The live `3h` and `12h` Lovelace views are maintenance workarounds, not intended separate dashboards. Their differences from `Home` are accidental; the user was simply not keeping the duplicate configurations synchronized.
- Present the intended Home dashboard once and provide one knob, selector, or equivalent control that changes the displayed time range for the graphs.
- Keep the available ranges, default range, and selector policy configurable in `Sources/NativeHAMac/AppConfig.swift`.
- This overrides rescue-plan statements in Modules 01, 05, 09, and 12 that say to remove the global range selector or preserve `Home`/`3h`/`12h` as intended separate navigation and content.

## Default-dashboard layout

- On the user's default dashboard, `vertical-stack` is a Home Assistant layout workaround used to obtain the desired appearance. It is not desired native grouping semantics.
- Preserve the raw decoded configuration, but render the intended three-column composition. Keep column count, dimensions, spacing, and placement rules configurable in `AppConfig.swift`.
- Do not generalize this personal-dashboard exception to unrelated dashboards without an explicit user instruction.

## Native architecture

- NativeHA is a native macOS replacement, not a wrapper around the web frontend. Implement behavior with Swift, SwiftUI, AppKit, CoreGraphics, and other native APIs; do not use JavaScript or WebView as the app architecture.

## Preserve established climate presentation

- On 2026-09-19, the user rejected Module 10's replacement climate appearance and animation behavior and requested recovery of the presentation previously refined across sessions.
- Restore that established visual and animation behavior, integrating necessary capability, service and authoritative-state handling around it. Reference parity is not permission to redesign the approved native presentation.
- Retain the corrected capability/service/lifetime contracts and the working Home-row entry path. Do not restore prototype data fallbacks, fabricated HVAC options, personal preset predictions or cross-entity fan inference as part of visual recovery.
- On 2026-09-20, the user confirmed that Mode/Preset triggers should be rounded boxes showing both the label and selected value. The old SwiftUI Menu's label-only rendering on macOS 12 is not the intended appearance.
- On 2026-09-29, the user supplied HA-web and native screenshots and rejected the recovered native rendering as visually nonconforming. Those HA-web screenshots now resolve the visual target where the historical source differs: neutral Off dial, directional faint/bright Cool arcs, white target with mode-colored outline, state-specific menu icons, lighter typography and rounded dialog. Preserve the established target animation timing and service safeguards; historical-source similarity alone is not acceptance.
- After testing `99417a8`, the user approved the appearance ("It looks great!") and reported intermittent clicks snapping without animation. Preserve that appearance while repairing the click behavior; this is not acceptance of the remaining animation defect or authorization to redesign the controls.
- On 2026-10-01, the user requested a one-click toggle when exactly two HVAC modes are available, rather than opening a selector. Preserve the rounded label/value trigger and normal selectors for larger mode sets and other attributes. This is an intentional interaction difference from HA web, not permission to fabricate an optimistic entity state.
- The same follow-up requests configurable temperature-number layout alternatives to balance proportional-digit appearance against stable positioning. The user confirmed proportional digits with clipping fixed and fixed-width/tabular digits, not proportional digits with a fixed decimal position. Keep the approved overall dial presentation; the layout choice belongs in `AppConfig.swift`, not a new settings screen.
- The recovery baseline and incremental validation plan belong in `docs/rescue-plan/module-10-presentation-recovery.md`. Recovery is not complete merely because screenshots render or service tests pass; compare against the established native presentation and obtain renewed visual/animation acceptance.

## Fixed personal Home Assistant deployment

- NativeHA targets one fixed personal Home Assistant deployment. Module 03 server-profile isolation is intentionally skipped, not completed.
- Keep the existing local token-file/bootstrap path and fixed server URL candidates. Do not introduce profile switching, a profile store, a settings UI, Keychain/token migration, or cross-profile identity/persistence work unless the user later changes this decision.
- Approved product, presentation, transport, history, rendering, tooltip, logging, graph-range, and layout choices remain typed policies in `Sources/NativeHAMac/AppConfig.swift`; the fixed-server decision does not remove those configuration contracts.
- Module 05 orchestration work must assume this single fixed server and omit profile-transition state, cancellation, migration, and tests.

## Native WebSocket transport semantics

- Preserve Home Assistant's observable WebSocket protocol semantics, including monotonically increasing command IDs, routing ownership, unsubscribe, reconnect, and resubscription behavior. Do not assume the browser client's scheduling mechanism itself is portable to macOS.
- The browser client allocates an ID and synchronously enqueues `WebSocket.send` in one JavaScript turn. NativeHA may and should use a per-physical-connection FIFO, explicit continuation ownership, bounded frame and callback policies, and other native lifecycle mechanisms required by completion-based `URLSessionWebSocketTask` behavior on supported macOS versions.
- Native transport adaptations must retain the already-verified Module 02 guarantees: one receiver, ordered outbound IDs, exactly-once pending cleanup, cancellation and timeout suppression, reconnect-generation isolation, history resubscribe opt-out, bounded callback retention, and the configured large-frame receive limit.

## Lossless selected diagnostics

- Logging is for debugging only. Release builds must have no logging-related runtime overhead: compile out storage, setup/shutdown, filtering, diagnostic metadata and timing; erase log calls without evaluating their messages. The persistence and filtering policies below apply only to debug builds.

- Diagnostic configuration may disable a subsystem or raise its minimum severity after that subsystem is considered stable.
- Every entry that passes the explicit subsystem/severity filter must be persisted in full. Do not silently truncate messages, stop at a database-size ceiling, or drop entries because an in-memory queue is full.
- Reducing disk-write frequency through asynchronous transaction batching is allowed, but the implementation must retry temporary database contention and clearly account for the crash window of any memory-resident batch.
- The selected debug-build balance is a one-second or 256-entry batch, whichever comes first, using a background serial writer, explicit transactions, WAL mode with full synchronization, retry on contention, and a final normal-termination flush. A sudden process or machine failure may lose the current memory-resident batch; this is not intentional filtering or queue-pressure dropping.

## Markdown implementation stages

- Implement native Markdown and HA server-rendered templates first. Defer advanced HTML, media, and HA-specific custom elements (including icons and QR codes) to a later stage.
- Deferred content must have an explicit fallback; do not silently discard it or claim full reference rendering parity for the first stage.
- This staging does not change the approved Home/maintenance-view navigation policy or authorize moving Markdown cards into Home.

## Numeric graph y-axis transitions

- While zooming or inertially scrolling changes the visible numeric range, the y-axis must respond smoothly and continuously. It must not remain frozen and jump only when the interaction ends.
- The user is not satisfied with hass web's abrupt transition either, so copying that behavior is not the goal.
- Keep the interpolation, look-ahead, hysteresis, and related tuning choices configurable in `AppConfig.swift`; select them through visual and performance testing rather than treating an old experimental algorithm as canonical.

## Trackpad-native graph navigation

- Graph interaction is trackpad-first. Vertical scrolling zooms at the pointer; horizontal scrolling pans with normal macOS smooth inertia; comparable gestures should have comparable effect across zoom levels.
- Foreground interaction takes priority over background graph work. Preserve mouse accessibility, but do not compromise trackpad behavior to imitate browser wheel handling.

## Performance and rendering accuracy

- NativeHA may use different native algorithms and rendering architecture for measured performance gains, but must preserve observable Home Assistant semantics and rendering accuracy.
- Do not discard spikes or visible detail merely to reach a speed target. If an unavoidable quality/performance tradeoff remains, present it for user choice.

## Approved future intent — not implemented yet

These are approved product intentions. Their presence here does not claim the current application implements them.

### Expand graph history beyond the initial range

- A graph's selected/default range (`1h`, `3h`, and so on) is its initial viewport, not a zoom-out ceiling. Allow the user to continue zooming out and fetch or reuse older history as needed.
- Make this behavior configurable globally and overrideable per graph. Include whether range expansion is enabled, an optional hard maximum such as `24h` or `2d`, and the gesture-distance threshold required before expanding beyond the initial range.
- Expansion must remain smooth and must not block panning, dismissal, or other UI while older data is loaded and prepared.

### Idle history prefetch and range reuse

- Retain fetched history/data in memory so dashboard changes and time-range changes can reuse coverage already fetched instead of issuing the same request again.
- When the app is idle, prefetch a configurable window—initially `24h`—for all entities referenced by the loaded dashboard configuration so the data is ready before a graph requests it.
- Prefetch is lower priority than foreground input, live updates, and visible rendering. It must be asynchronous, cancellable, deduplicated with foreground requests, and constrained by the configurable cache budget in `docs/configurability.md`.

## Historical candidates

Unapproved or feature-specific possibilities remain in `docs/agent-history-authored/deviation-candidates.md`. They are not active deviations and should not be read during ordinary implementation unless the user requests a new deviation audit.
