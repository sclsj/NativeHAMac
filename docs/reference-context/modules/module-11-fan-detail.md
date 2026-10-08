---
schema: nativeha-evidence/v1
module: "11"
title: Fan more-info controls
plan: ../../rescue-plan/module-11-fan-detail.md
status: research-ready
contract_revision: 1
depends_on: ["05", "06"]
reference_revision: "dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd"
nativeha_revision: "639c6654f9077298b596392d171688452cd3514f"
graph_file: ../generated/module-11.dependencies.json
graph_fingerprint: "c5bf6a2b9de8802c2fde71c0c4dc4b7b44a970574831af63f38c11dcc2d222da"
last_validated: 2026-10-08
---

# Module 11 evidence packet

## Scope delta

Research covers the actual `more-info-fan` component, its speed/toggle children, shared control implementations, service boundary and relevant runtime dependencies. Lovelace card features are not the detail oracle. This is a research/plan handoff for review, with no application implementation or visual acceptance claimed. The actual fan is offline; approved fake fan fixtures permit implementation and verification without live HA writes.

Corrections to the historical plan:

- Only `unavailable` disables reference controls. `unknown` stays actionable. Without speed support, unknown or assumed state shows explicit On and Off buttons.
- Discrete Off and slider zero call `fan.set_percentage` with zero. Only the separate percentage-slider power button and no-speed toggle call `fan.turn_on`/`turn_off`. TURN_ON/TURN_OFF feature bits do not gate those detail controls.
- Missing percentage is normal optional data: raw `on` remains **On in the header**, while the speed control selects Off/zero. Do not fabricate shared Off state or classify missing percentage as malformed.
- Direction has fixed raw choices `forward`, `reverse`; no direction-options attribute is required. Preset, direction, and oscillation menus may coexist with speed and remain enabled when off.
- Speed selection is locally optimistic; the header and state color remain authoritative. Preset's local variable only suppresses duplicate requests; its visible value remains authoritative. Reference fan controls do not implement climate-style debounce, timeout, delayed success resync, or failure rollback.
- Reference interaction already has meaningful finite transitions (80/180 ms), though no rotating fan animation. A completely static replacement is not equivalent motion.
- Rounding and bounding are input-path-specific. There is no universal final clamp or re-snap at the service boundary.

Preserve accepted climate visuals, animation, and climate-only feedback/two-mode-toggle deviations. Do not extend those deviations to fan. Keep existing generic sheet/history infrastructure; full more-info shell, metadata, history, and translation/icon infrastructure parity remain outside this bounded fan-control module.

## Behavior contracts

Evidence abbreviations refer to the source anchors below; all paths and hashes are pinned in the linked graph.

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| C11-01 | Fan attributes/capabilities | Bits: speed 1, oscillate 2, direction 4, preset 8, turn_off 16, turn_on 32. Speed bit chooses speed control; otherwise toggle. Preset requires bit plus present `preset_modes` (empty array still renders a trigger); other menus require their bits. Missing mask grants no attribute capabilities. | Power is not gated by 16/32; do not infer fan from climate. | F, M, T | Planned `FanEntity`/feature resolution | Sparse, every bit, bit combinations, preset absent/empty |
| C11-02 | Speed count and discrete selection | `step = percentage_step ?? 1`; count `Math.round(100/step)+1`. Counts 2/3/4 map to `[off,on]`, `[off,low,high]`, `[off,low,medium,high]`; display reverses these vertically, highest at top. Count above 4 uses slider. Selected index is `Math.round(percentage/step)`, fallback Off when absent from mapping. | Button payload is `floor(index*step)`, including Off=0; no minimum-nonzero special case. Same-option click/Enter/Space sends again. Arrows wrap focus without committing. | F, S, D | Planned `FanValueMapping`/discrete control | Exact lookup, threshold, tie, floor and repeated action tests |
| C11-03 | Authoritative entity replacement/header | Active fan percentage defaults to zero only for speed control; inactive (`off`, unknown, unavailable) forces control zero. Speed owner stores slider value `max(round(percentage),0)`; geometry bounds display separately. Header uses rounded percentage only when raw percentage is truthy and state active; otherwise formatted raw state. | Every new `stateObj` recomputes owner slider/speed values, even equal-content replacement. This is not an unconditional child-geometry reset: during drag the slider child mutates its own value while owner `sliderValue` stays unchanged; an equal-valued binding need not overwrite it. Header does not preview local speed. `on` with missing or zero percentage displays On and control zero; `on` with 0.4 displays 0%. | F, S, M, A | Planned mounted fan controller + revision bridge | Separate header/control assertions; equal replacement and external update, including mounted drag |
| C11-04 | Percentage pointer gesture | Vertical position `clamp(1-(y-top)/height,0,1)` maps to 0…100; snapped value `Math.round(value/step)*step`. Pan starts only beyond 10 px; start saves value/shows tooltip, without moving or sending. Move changes local unsnapped geometry; tooltip rounds to grid. End snaps and commits once. Tap/press release snaps and commits once. | Cancel restores saved value, hides tooltip, sends nothing. `slider-moved` is not consumed by fan owner. No service debounce or call per drag sample. | L, H | Planned AppKit slider/control interaction | Press/start/move/end/cancel, incidental movement, 1,000 samples=one commit |
| C11-05 | Percentage keyboard | Up/right add step; down/left subtract step (horizontal key sign follows RTL), bounded to 0…100 without snap. Page Up/Down use max(step,10), bound then snap. Home/End are exact 0/100. Keydown updates local value/tooltip; keyup commits. | Tooltip hides 500 ms after keyup. Unlike pointer release, End need not land on grid. Preserve accepted key action count, including repeat-down then one release. Native boundary must reject unavailable mutations even though web slider keyboard handlers omit disabled guards. | L | Planned AppKit slider | Arrows, page keys, bounds, key repeat, release, disabled keyboard |
| C11-06 | Power without speed, or slider's extra power button | No-speed ordinary state uses large vertical reversed switch (On at top); tap/press toggles local switch, up requests On/down Off. Unknown or `assumed_state` uses explicit On/Off controls. Slider power chooses `turn_off` only if raw state is `on`, otherwise `turn_on`. All payloads use exact entity ID and fan domain. | Extra slider Power has no optimistic raw-state change; repeated clicks before HA confirmation repeat the same action. No extra Power button beside discrete speeds. No-speed switch local check does not change shared state. | M, T, W | Planned service builder + toggle presentation | Exact domain/service/data; unknown/assumed; no invented power capability guard |
| C11-07 | Preset selection | Options preserve `preset_modes` order/raw strings; labels use attribute formatting, retaining raw fallback rather than title-casing arbitrary names. Ignore empty or local duplicate value; otherwise save local `_presetMode` and call `set_preset_mode`. | Trigger and selected menu item read authoritative `attributes.preset_mode`, not `_presetMode`. Every stateObj replacement resets dedup value. No automatic rollback/reset on failure. | M, Q | Planned fan controller + native menu | Raw unusual strings, empty options, duplicate before/after replacement; failure |
| C11-08 | Direction and oscillation | Direction options `forward`,`reverse`, ignore empty/same authoritative value, call `set_direction`. Oscillation menu order true/false, current selection uses truthiness (missing→false), call `oscillate` with Boolean. | Direction/oscillation remain authoritative; comparison uses raw old attribute. Missing oscillating is not Boolean false, so selecting false may send once. Repeats before confirmation are not suppressed unless equal to authoritative value. | M, Q | Planned service builder/menu | Missing attrs, repeated activation, Boolean payload type |
| C11-09 | Action/error/replacement | Shared HA states stay authoritative. Reference speed child mutates its local value before service; failures emit global error notification (10 seconds) and rethrow, with no fan-local rollback. Preset dedup value also persists until replacement. | No await-based fan busy disable; successive speed commits must not be dropped while an earlier request is outstanding. New entity replaces presentation; obsolete completion cannot publish into another detail. Native resources/callbacks require explicit ownership, not retroactive cancellation of an already-issued HA command. | S, M, C, runtime commands/messages | Planned fan controller + dashboard service bridge | Recording boundary with deferred/out-of-order results, failure, replacement, dismissal, stop |
| C11-10 | Availability and malformed data | Missing entity produces existing unavailable shell without controls; unavailable shows raw unavailable header, capability shape, disabled actions. Unknown header stays unknown and supported controls act. Malformed/nonfinite steps or impossible discrete count must not crash Swift. | Defensive native validation may reject nonfinite or out-of-domain outgoing values, without silently altering otherwise valid reference results. This defense is not exact parity for the web's malformed-input behavior; missing step→1 and missing percentage→zero control remain normal cases. | F, M, S, L; native shell | Planned parser/builder | Typed invalid fixtures, no traps/no invalid service; normal optional data distinct |
| C11-11 | Visual structure and motion | Centered state header; 130-point-wide vertical control, reference height 45vh bounded 200…320; rounded track. Discrete options separated by 4-point padding, selected white content. Slider fills bottom-up with white marker and interaction tooltip. Menus are rounded label/value triggers, 48 high, normally 120…160 wide (3 desktop menus max140), wrapping on desktop. | Slider fill/color and switch geometry/color use 180 ms ease-in-out; recognized slider drag suppresses geometry transition. Discrete opacity 80 ms, background color 180 ms. No continuous fan spin. Native menu popup is platform-owned; reference popup show/hide is 50 ms scale/opacity. | S, D, L, W, Q, runtime dropdown | Planned fan drawing/input views | Paired fixture captures + explicit keyframes + mounted geometry assertions |

### Exact numeric examples

| Step | Count/control | Low/medium/high payloads or endpoint behavior |
|---|---|---|
| absent/null | 101 / slider | Step defaults to 1; top=100 |
| 100 | 2 / discrete | Off=0, On=100; 50 selects On (positive tie rounds up) |
| 50 | 3 / discrete | Off=0, Low=50, High=100 |
| `100/3` | 4 / discrete | Off=0, Low=33, Medium=66, High=100 |
| 33 | 4 / discrete | High=99, not 100 |
| 25 | 5 / slider | 4 nonzero levels plus Off exceeds button threshold |
| 16 | 7 / slider | Pointer top snaps to 96; End key sends 100 |
| 22 | 6 / slider | Pointer top mathematically snaps to 110; proposed native service validation rejects, does not rewrite to 100 |
| 40 | 4 / discrete | High mathematically maps to 120; proposed native validation rejects |
| 0 / negative / >200 | Invalid numeric/control combinations | Zero yields infinite count/invalid snap; negative or count1 has no option table and web may throw. Native must handle safely; these are not optional-data defaults. |

## Source anchors

Reference revision is the front-matter revision (clean worktree when researched). Symbols below are navigation anchors; SHA-256 values identify complete files. Secondary files, native anchors, npm versions, package identities, and lock identities are in [the generated graph](../generated/module-11.dependencies.json), not inferred from line numbers.

| Key | Reference path / main symbol | SHA-256 |
|---|---|---|
| M | `src/dialogs/more-info/controls/more-info-fan.ts` / `MoreInfoFan` | `9bd1bf67aa57dafde70ee8f33105230741a0641588c1cfd45f0c2c9f9942421a` |
| F | `src/data/fan.ts` / feature enum, conversions, count/display | `9173b06c011ae4591e12f7231d5b680fbd33be63dafef19dd0933695185db897` |
| S | `src/state-control/fan/ha-state-control-fan-speed.ts` / `HaStateControlFanSpeed` | `9040a6829896ffa163a0ab3f489ee2b8754f7e39c66129607bd75d5ef7e17d9e` |
| T | `src/state-control/ha-state-control-toggle.ts` / `HaStateControlToggle` | `9b8c4df3d24a14ccedb627198b7a499ced19c61c4a29bfcb59792cd2b30b8608` |
| L | `src/components/ha-control-slider.ts` / `HaControlSlider` | `9b09129dd597018a4227177e81bef03f307306c57229d4f57f77384d18ca9b17` |
| D | `src/components/ha-control-select.ts` / `HaControlSelect` | `0ef4561cf82580f2cfa988f11839676e91729b1538be9928ebdd5757467d46f5` |
| W | `src/components/ha-control-switch.ts` / `HaControlSwitch` | `4f58783cc767da4496a4bdba7c5be740dce2c7dda7202c7e58c6d12a03d7e47d` |
| Q | `src/components/ha-control-select-menu.ts` / `HaControlSelectMenu` | `ff22308c16bd3985f6228ea73296d3c58f8a1d12ff32c080401fcdb2cd858d08` |
| A | `src/common/entity/state_active.ts` / `stateActive` | `9ae81c85b5523e4b1a3e7d0399ae238ef6a89b9ada810748f35c0eeda92f7d13` |
| C | `src/state/connection-mixin.ts` / `connectionMixin` service closure | `ed4c83f57d1d308480daf560b91a13d8309f76a8745c035db35f501cc9a48a8a` |
| H | `node_modules/@egjs/hammerjs/src/recognizers/pan.js` / `PanRecognizer` | `c2ff582c6a1f5a84253b23bcf39e1c855c7272f6f62f940e57aadfd2d0ce4087` |

Runtime packages: `@egjs/hammerjs` 2.0.17; `@home-assistant/webawesome` 3.7.0-ha.0; `@material/web` 2.4.1; `home-assistant-js-websocket` 9.6.0. Reference `yarn.lock` SHA-256: `ca345f66a74a1054b77bd2f47f20cb9e13e79b2c864f3375822cca9b14ff41b6`. Native complete-file anchors are `CardViews.swift` (`d8629b40f3e1c5b8099d935091bbd1f18887309100a7f84d5ba602fe98135ffb`), `DashboardViewModel.swift` (`6e210003b4ccc0048afea6495513e86b58d376819f396547e7d4772825aeabcc`), `DashboardServiceController.swift` (`a69c7f9b2142371d2d75d1701f3e4963d9699b0f778a91dfbd76296506b41f1b`) and `AppConfig.swift` (`a84bb9f42ed83ea2393b8efef6e1fd70ccdaa954bd9349e232f5d045b2888a6a`).

## Dependency traces and boundaries

- More-info → speed owner → data conversions + select/slider; no card-feature semantics imported. Runtime Hammer Pan/Tap/Press/Swipe, recognizer base, attribute recognizer and manager were read to establish gesture phases, exclusive recognition and release/cancel. Tap requires movement <9px and duration <250ms; Press uses >251ms, movement <9px; pan >10px. Platform input delivery is the native stop boundary, not climate gesture policy.
- More-info → toggle → switch/control-button; switch uses browser button/keyboard primitives plus Hammer. Outlined power follows Material `IconButton` to its native HTML button disabled state. Native AppKit button/focus/accessibility is the intended platform primitive.
- More-info → select-menu → HA dropdown/item → actual WebAwesome dropdown/item and selection event. Selection closes popup and returns focus; arrows/Home/End/typeahead move focus, Enter/Space select, Escape dismisses. Animation helper stops at DOM animation primitives; popup placement and optional submenu trees do not determine fan choices or payloads and remain native menu behavior.
- `apiContext.callService` interface → explicit `connectionMixin` implementation → websocket `commands.callService`/`messages.callService`. The latter preserves service data including entity ID; no implicit percentage normalization or state prediction. Stop at established Module 02 transport/server API boundary; this module need not replace current native REST service transport.
- Formatter and state-color paths were read through percentage-unit/number formatting, activity and CSS fallback. Percentage uses locale number formatting and language-dependent spacing before `%`; arbitrary presets retain exact fallback strings. Attribute icon lookup uses backend platform/component metadata; do not invent preset icons based on name substrings. Backend translations/icon assets and Intl formatting are established data/platform boundaries; full infrastructure replacement is outside this module. Default color must be compared in the future paired visual harness, not assumed from current native cyan.
- Generic state header was inspected: web defaults to relative last-changed (60-second update), click toggles absolute, and disconnect clears timer. Existing NativeHA absolute timestamp and shell differences are shared-detail work, not claimed fixed by this fan contract. Preserve existing history ownership without broadening into a generic shell redesign.
- Graph maxDepth=2 is a candidate-discovery ceiling; behaviorally relevant crossings above are explicit seeds. Other domains, generic theme/metadata loaders, type-only declarations, form submission (no fan form), icon drawing implementation and optional submenu placement do not determine fan control semantics.
- Freshness is **YELLOW with one reviewed boundary**, not green: `src/resources/translations-metadata.ts` imports missing generated `build/translations/translationMetadata.json`. The complete importer only exports generated language metadata; no fan choices, capability checks, numeric conversion or service rule depends on that absent build output. A future browser fixture must supply normal locale context/build metadata. Graph has no max-node truncation or missing seeded symbols. Reevaluate if the unresolved set changes.

## Native mapping and bounded implementation slices

| Slice | Files and work | Exit evidence |
|---|---|---|
| 1. Pure contract | Add `FanEntity.swift` containing typed optional attrs, feature/shape resolution, value mapping and exact service requests. Separate malformed safety from normal optional defaults. Separate helper files only if useful. | Offline parser/mapping/action matrix with positive rounding ties and fractional payloads |
| 2. Mounted service/state owner | Add `FanServiceController.swift`; narrowly bridge DashboardViewModel and DashboardServiceController. Remove fan-only optimistic writes; preserve existing row power contract. Allow independent fan commits/unknown actionability through an explicit fan policy rather than misleading `climateInteraction:true`. | Deferred recording caller proves all commits, authoritative shared states, equal replacements, stale failure suppression and cleanup |
| 3. Native detail controls | Extract fan content from CardViews into `FanDetailView.swift`. Use SwiftUI drawing/layout plus AppKit pointer/keyboard/accessibility surface for vertical select, slider and switch. Label/value trigger opens NSMenu; do not copy climate's two-mode shortcut. Keep sheet width/history path and climate implementation intact. | Mounted fake-state interactions; matching screenshots; motion geometry |
| 4. Verification | Fake fixtures + reference actual-component recording harness, full applicable deterministic suite, scoped performance/lifecycle checks and independent review. | Contract-by-contract results; remaining visual acceptance and offline limits explicit |

Current fan owner hardcodes Off/33/66/100, selects by ±17 tolerance, always displays percentage and calls DashboardViewModel. Current model converts zero to row power, writes optimistic shared states, and global service admission rejects unknown and suppresses an in-flight same service. Those are fan correction points. Existing climate replacement revision is climate-specific; add a narrow fan replacement signal without perturbing accepted climate state/motion. Pass new state/revision payload through mounted callbacks to avoid the macOS 12 previous-view capture hazard recorded in the knowledge base.

## Decisions and native deviations

| ID | Decision | Reason and preserved contract | Status |
|---|---|---|---|
| D11-01 | Native AppKit input/menu/focus with SwiftUI drawing | Required native architecture/macOS12; preserve choices, commits, local-versus-authoritative values and accessible operation | Recommended implementation mechanism, not implemented |
| D11-02 | Reject malformed/nonfinite/impossible mapping or out-of-domain outgoing values without silent clamping | Native numeric safety; preserve all valid reference payloads. Web's malformed-input crash/invalid service attempts are explicitly not reproduced | Defensive handling recommendation; adversarial tests must identify this boundary |
| D11-03 | Own finite transitions and callbacks only while mounted | Native resource/lifetime correctness; no continuous spin; dismissal sends no new command | Required lifetime behavior; implementation pending |

Useful fan geometry/motion constants should be grouped in a typed AppConfig policy with the reference defaults (130 width, bounded height, 10-point drag threshold, 180/80ms transitions, 500ms tooltip delay); update configurability notes when implemented. Feature bits, four-option threshold, payload rules and replacement authority are correctness contracts, not arbitrary UI preferences. No fan timeout, busy lockout, climate fade policy or settings UI is proposed.

## Validation

### Offline deterministic fixtures and tests

Use fixed `last_changed` and `fan.fixture_*` IDs, injected initial states and recording service boundary; never start network/bootstrap or load credentials. A complete fake fixture should include `supported_features:63`, `percentage_step:25`, `percentage:50`, `preset_modes:["auto","quiet_mode","Custom Night"]`, `preset_mode:"auto"`, `direction:"forward"`, `oscillating:false`.

| Fixture group | Required states/assertions |
|---|---|
| Core shape | No speed, speed counts2/3/4, step25 slider, default-step slider; each menu alone and all together; preset bit with absent/empty array |
| Value display | Off with retained percentage; On1/25/33/50/66/100; On missing/null/zero/0.4; unknown/unavailable/missing; exact header distinct from zero selected control |
| Services/input | All six services; raw presets; true/false Boolean; same speed resend, preset dedup, direction/oscillation authority; pointer click/drag/cancel; key arrows/Page/Home/End |
| Ownership/errors | Matching/different/equal replacement; state replacement during drag; failure before/after newer replacement; two outstanding speed commits; dismissed/reopened different entity; capability removal; app stop |
| Adversarial safety | Wrong JSON types; nonfinite local numbers; zero/negative/extreme steps; missing step distinct; step16 endpoint96 versus End100; step22 endpoint110 and step40 high120 rejected, not clamped |
| Visual/accessibility | Core shapes, unavailable/unknown, narrow360 width, long/raw preset strings, menu open/selection, focus/keyboard, discrete first/highest and bottom Off, tooltip bounds |

Research validation actually run: generated graph (200 nodes/693 edges, no truncation); freshness checker YELLOW only for reviewed generated translation metadata; direct Node TypeScript-transpiled reference `data/fan.ts`/its activity dependencies exercised count/mapping and missing-header examples in the numeric table. Slider endpoint arithmetic was evaluated from its reviewed formula; this is not a mounted browser event test. No Swift tests, application builds, live service calls or visual captures were performed in this research phase.

October 8 supervisor review read the packet and complete primary fan, speed, toggle, slider and discrete-select reference files, reconciled the historical plan, and reran freshness plus the resolver self-test (31 nodes/61 edges, PASS). Final diff checks pass. The single generated-translation boundary remains explicit; no implementation or visual acceptance is inferred from source freshness.

### Read-only live smoke

Not performed; user reports actual fan offline. This blocks real-device response confirmation, not fake-fixture implementation or source research. Any future state-changing live QA needs a separately authorized safe target; offline tests must never silently fall back to the real fan.

### Visual and animation oracle

Use the existing `tools/climate-reference/README.md`/browser harness approach to propose a separate **fan** fixture harness: bundle actual `more-info-fan`, supply matching HA contexts and fake state, record API calls instead of contacting HA. No fan browser harness exists from this research. Capture reference/native same-state control areas plus full native 520×620 and content-only 360×620 at 2× scale, fixed dark theme/locale/time. Record theme-derived colors rather than inheriting climate colors. Review pairs before approving baselines.

Per `docs/visual-testing.md`, static NSHostingView captures are suitable; hosted Canvas motion needs compositor/window capture and geometry-sensitive start/mid/end assertions. Test a slider tap/authoritative update's 180 ms movement, direct drag geometry, selected opacity 80 ms, switch 180 ms, final equality and hidden inactivity. Do not use whole-image inequality or changing header text as proof of moving control geometry. Native system menu animation can follow platform conventions; document that approximation. No continuous animation is needed.

### Performance and lifecycle

Measure pure preparation/mapping separately from rendering (10,000 fixtures/updates), a 1,000-location gesture with one service commit, and 100 open/close cycles with delayed results. Use existing XCTest clock/CPU/memory metrics on macOS 12; no new benchmark framework or speculative optimization. Assert fan-local state, input tracking, finite animation/tooltip timers and completion authority disappear on dismissal; preserve existing detail-history load/unload without rewriting graph ownership. Reduced-motion adaptation, if introduced, requires explicit fixture evidence.

## Open questions and risks

No material source-contract question blocks the scoped plan review. Implementation must resolve exact native control sizing/colors against paired fake reference captures; no current screenshot is an approved fan baseline. Backend-specific translated preset labels/icons are data-driven and cannot be inferred from offline raw strings. Scope excludes broad metadata loading/shell/history parity; report those existing limits instead of claiming full dialog equivalence. Service failure does not justify inventing climate-style rollback or timeout. Defensive invalid-input handling must remain explicitly distinguished from valid-input reference parity.

## Handoff

Research-ready, implementation not started. Task owner reconciles plan/index with these corrections and presents the bounded four-slice plan for review before application work. Then the sole Swift owner checks staleness, reads anchored owner files, starts slice1 with fake fixtures, and records implementation decisions/results here. Independent verification and user visual review follow implementation; the offline real fan remains a documented live-QA limitation. Keep all Module10 accepted visuals/behavior and global row power routing intact.

## Change log

- 2026-10-07: Initial actual-more-info research; corrected stale card-feature, unknown, Off service, missing-value, optimistic-state and animation assumptions. Added reviewed manifest, dependency graph, contract matrix and bounded fake-fixture handoff.
