# Module 10 established-presentation recovery

## Current correction — 2026-09-29

The user rejected the September 26 result, reported a click/drag-release target jump, and supplied three HA-web reference screenshots and three native screenshots. The web screenshots supersede conflicting historical styling in the preserve/restore table below; that table and the earlier outcome are historical recovery evidence, not current visual acceptance. Repair the demonstrated state-update and pointer-focus defects and match the supplied dial/control appearance without changing the service contract. Full more-info header metadata/actions remain a separate, disclosed gap; do not fabricate room/device names to match a screenshot. Module 10 remains open for renewed user acceptance.

Planning handoff, 2026-09-19. Recover the established native climate appearance and animation while retaining Module 10's capability, service, sparse-state and lifetime corrections. The user rejected the replacement presentation; the earlier Module 10 visual verdict is not acceptance of that replacement. See [approved decisions](../user-deviations.md#preserve-established-climate-presentation) and the [Module 10 packet](../reference-context/modules/module-10-climate-detail.md).

## Planning recommendation and limits (historical)

Stop after this plan in the current session. The recovery source is identifiable and much of its drawing code still exists, but reconnecting it safely requires a focused presentation integration and animation verification, not a whole-commit revert. There is no need for another broad module audit, new service design, or live device mutation to start that work.

The user subsequently authorized implementation. On 2026-09-20 they clarified that Mode/Preset controls are rounded boxes showing both the label and selected value, despite the historical SwiftUI Menu rendering labels only on this macOS host. Use that confirmed appearance, not the host's flattening of the historical menu label. The archived Gemini attempt is not a recovery source.

This investigation used Git history and source inspection only. No app/test code changed, build ran, browser or HA request occurred, or animation symptom was reproduced. The user report establishes dissatisfaction; the source differences below establish what changed, not a proven cause of every reported animation problem. Existing service validation evidence is historical and must be regression-tested after integration.

## Exact recovery sources

- Implementation HEAD at planning start: `dcfa5834f70c8ea109bac43f112915e3103bd7b2`.
- Replacement: `efd7252e16ae6a287c9c5092d53f924c80e3a18d`, which removed 360 lines from `CardViews.swift` and introduced the four dedicated climate files.
- Last production baseline before replacement: `3f8d15f14ee742ace447034ab4a0e482653216d2:Sources/NativeHAMac/CardViews.swift` (Git blob `f29618d4da60b0d363f539ba7b1ce5e0d56e71ac`). There was no `ClimateDetailView.swift` at this revision.
- That historical file contains `ClimateDetailContent` at line 1635, `ClimateTemperatureDial` at 1839, `BigTemperatureText` at 1993, `ClimateDialDrawing` at 2021, and the complete `DialMetrics`, `dialArcPath`, `circlePath`, `roundActionButton`, `haSliderAnimation`, and `menuControl` definitions. Symbols/revision are authoritative; line numbers are navigation hints.
- Dial source history reaches the repository's initial baseline `183cae8e2f317ecf5a04774bdf982ea7c3aa682c`. Available commits do not reconstruct the user's earlier iterative design sessions. Use the final pre-replacement production source, not an invented intermediate design.
- Current `CardViews.swift` still contains the old `BigTemperatureText`, `ClimateDialDrawing`, metrics and helpers, including the old timing curve and menu styling. `ClimateDialDrawing` currently serves the isolated `GUIRenderingAndPerformanceTests.testClimateDialAnimationKeyframesRenderDistinctImages`; it is not the production dial.
- Replacement source blobs at `efd7252`: `ClimateDetailView.swift` = `36a0d0129297a18b4b147acf5003788b98d91d26`; `ClimateControlDrawing.swift` = `4e92e8e4c4551bf9130248a81bdbbea0b0157656`.

Recover with `git show 3f8d15f:Sources/NativeHAMac/CardViews.swift`; do not check out the whole historical file. It contains unrelated weather, entities, graph and detail work.

## Preserve and restore map

| Surface | Restore from established presentation | Preserve from current implementation |
|---|---|---|
| Detail composition | Centered current-temperature reading; 18-point vertical spacing; 320-point dial; original Mode/Preset row appearance | `EntityDetailSheet` routing/shell; optional readings remain genuinely optional; corrected Home climate-row opening |
| Single-target dial | 135° start/270° sweep, radius 145 and stroke 24 at size 320; neutral white 10% track; only cooling difference arc in RGB 0.10/0.48/0.95; 7-point near-white current marker; shadowed 24/18-point target knob, blue outer ring when cooling and translucent white otherwise | Validated bounds, explicit missing values, capability gating and current server state; no fabricated target or current reading |
| Center text | 13-point semibold action at white 72%, four-point stack spacing, original reserved 24/64/24-point vertical slots; split 57-point target typography and historical unit/fraction proportions | `ClimateEntity.actionLabel` truth, server temperature units and localized `ClimateNumberFormatting`; do not restore the cross-entity fan inference or label every off state Idle |
| Adjustment controls | 48-point outlined circles, original 24-point medium symbols, 24-point gap and 10-point bottom inset | Current native button delivery/accessibility and controller button debounce; inspect actual bounds and border instead of assuming a SwiftUI label remains square |
| Menu triggers | Original icon + stacked title/value treatment, spacing, padding, translucent background and corner radius; Mode `power`, Preset `figure.walk`, Fan `fanblades`, Swing `arrow.left.and.right` | Current raw option strings, feature masks, authoritative selected value, native menu focus/selection and controller dispatch; retain horizontal swing without inventing options |
| Animation | Historical explicit `timingCurve(0.42, 0, 0.58, 1, duration: 0.30)` for target changes; direct tracking while dragging; animate a click target; target-only interpolation in the old single-target drawing | One controller-owned draft, authoritative replacement, cancellation and lifetime guards; retain configured duration and keep animation policy typed in `AppConfig.swift` |
| Services/lifetime | No historical service code restoration | `ClimateEntity`, `ClimateServiceBuilder`, `ClimateValueMapping`, `ClimateServiceController`, `DashboardViewModel.invokeClimate`, accepted replacement provenance and service-owner concurrency |

The single-target visual baseline has no full tinted remaining arc and does not recolor the action label by HVAC action. Those are confirmed replacement changes. Restoring the old appearance does not require reverting correct localized labels, raw payloads or entity capabilities.

Never restore the mutually recursive `currentTemperature`/`targetTemperature` fallback, invented `off`/`cool` modes, guessed bounds/units, preset target predictions, shared-state optimism, match-only draft clearing, or hardcoded fan-entity action inference. Those behaviors are interleaved with the old view and are the reason wholesale restoration is unsafe.

## Animation and input boundary

The old `ClimateDialDrawing.animatableData` is target progress only. Its current marker is an immediate reading. The replacement interpolates six numeric slots (four possible targets and both current readings), and applies implicit animation to both `controller.values` and the whole `entity.state`. It also resets gesture flags on state/revision changes. These are concrete differences that broaden animation triggers; none independently proves the user's “random” symptom.

The replacement sets `gestureStarted` on mouse-down and disables implicit animation while that flag is true; the old view differentiated a tap from a drag and explicitly animated its tap result. Inspect and test the actual release transaction before claiming that this causes a snap. Do not attempt to fix perceived randomness by suppressing authoritative HA replacements, delaying revisions, or reinserting predicted temperatures.

Retain current AppKit input, keyboard operations, accessibility, range selection, HA rounding and release-commit behavior. Introduce a local presentation distinction between pressed and actively dragging if needed to recover tap-versus-drag animation. The historical four-point drag slop, larger hit region, and cancel-on-release-outside behavior differ from the current reference-aligned zero threshold and release mapping. Do not silently restore those semantic differences merely by copying `DragGesture`. First recover the established visual transitions with the current service/input contract; if exact historical gesture behavior is necessary after comparison, document that narrow decision explicitly rather than weakening service tests.

For the single-target baseline, scope interpolation to actual target movement, use no interpolation for direct drag updates, and settle immediately on teardown/capability loss. Current readings should follow the historical immediate marker update. An incoming authoritative target should replace the controller draft and animate only the resulting visible target movement when not actively dragging. Test interruption/reversal and repeated equal state replacements; no unrelated entity update should restart a target transition.

## Bounded treatment of additional capabilities

The captured `climate.room_ac` surface has single temperature, Mode and Preset; it has no target range/humidity/fan/swing. Those are historical captures, not a fresh server inventory.

Restore that established production composition first. Keep the existing range and humidity controls as capability-specific branches during the initial recovery, using current selection and service semantics. They must not replace or resize the single-target baseline when absent. Optional fan/swing/horizontal-swing controls can occupy additional rows using the recovered menu-trigger treatment. Keep the temperature/humidity selector conditional and the error text conditional. Match normal and narrow fixtures without changing the fixed detail-shell size.

There is no historical approved dual-target or humidity visual baseline to recover. Retaining their existing presentation provisionally is a bounded compatibility choice, not a claim that the user approved a new design. Avoid a fresh multi-capability redesign in this repair. If these branches need substantial layout or new gesture choices, leave their current capability behavior working and present the concrete visual decision separately.

## Implementation sequence

1. Inventory the worktree and preserve the prior Home-row repair. At planning start the existing dirty files were `EntityRowPresentation.swift`, `EntityRowPresentationTests.swift`, new `ClimateDashboardEntryTests.swift`, and Module 06/10 packets. The user reports that clicking now opens the detail. Do not overwrite them while extracting historical presentation.
2. Read the complete files being changed and their relevant dependencies; use the current Module 10 packet for preserved service contracts. No broad dependency-graph refresh is needed for this bounded recovery. Keep one writer and do not spend another model session on duplicate research.
3. Build a deterministic presentation-only comparison harness from the historical view/drawing symbols and fixed fixtures. Use stub callbacks; the old controller/fallback code must not contact HA or become production. Establish old versus current whole-detail stills and target transition sequences before changing the production renderer.
4. Adapt the existing `ClimateDetailContent`/`ClimateControlDial` to the recovered single-target composition/drawing. Keep `ClimateServiceController` as sole draft owner. Reuse or extract the surviving old drawing helpers so production and the relevant regression tests exercise the same drawing code. Preserve native inputs and apply historical styling to their presentation.
5. Recover scoped target animations and original menu/button appearance. Keep the new capability branches bounded as above. Do not modify service ownership or numeric mapping unless a demonstrated integration bug requires a separate focused correction.
6. Run the regression and visual gates below. Inspect final source diff, update changed Module 10 contracts/status and climate configuration notes, refresh only affected source anchors, and commit intended changes with actual validation. Do not mark visual recovery complete from a green service suite or static PNG signature checks.

## Required gates

- **Service/state regressions:** retain existing `ClimateEntityTests` and `ClimateDetailInteractionTests` coverage for A1 sparse/malformed values, zero readings, masks, single/range precedence, unknown/unavailable, off-grid button versus pointer behavior, exact raw payloads, independent commits, debounce, menu resync, stale completions, accepted equal replacements, dismissal/reopen and weak release. Existing entity-row tests must preserve opening. No live ACTUATE run is needed for a presentation-only recovery.
- **Mounted control wiring:** exercise the restored production view, actual pointer down/move/up/cancel, keyboard and menu/button paths with a recording sender. Verify drag sends no intermediate services and exactly one release commit, button debounce remains intact, and presentation styling does not intercept the dial/center/controls. Direct `performClick` is useful wiring evidence but is not proof of real user hit testing.
- **Visual comparison:** follow `docs/visual-testing.md` for macOS 12 hosting/bitmap capture. For the established surface, compare against the historical native presentation authorized by this user decision; hass-frontend remains the semantic reference, not the replacement visual target. Render the whole 520×620 sheet and 360×620 content with matching fixtures, scale/appearance/locale. Inspect off, idle, cooling, current equal to target, current above/below target, minimum/maximum and both decimals. Keep sparse/unavailable/read-only/heating/range/humidity fixtures to prove capability safety and absence of clipping.
- **Animation:** retain deterministic geometry/interpolation endpoints, midpoint and final-equals-direct-final checks, but add hosted transition evidence for tap, drag, button repetition, reversal before completion, preset-authoritative target change, current-only replacement, equal replacement and dismissal. Static distinct keyframes alone cannot establish smoothness or correct trigger scope. Visually inspect an event sequence/video on the native app or offline hosted fixture; report unverified real trackpad/hitch behavior honestly.
- **Configuration and full regression:** preserve one-second button debounce, two-second menu resync, service correctness and macOS 12 compatibility. Any selected presentation/input policy belongs in `AppConfig.swift` with synchronized `docs/configurability.md`. Run the focused suites and the normal deterministic suite after integration; do not repeatedly benchmark unrelated graphs or refresh every module's evidence.

## Remaining decisions and confidence

Confidence is high in the recovery source and presentation differences, and high that existing capability/service owners can remain. Confidence is insufficient to call the integration trivial or the “random” animation cause reproduced. Exact old gesture slop versus reference input behavior and the final appearance of capabilities absent from the historical baseline are the bounded risks. They do not block implementing the established single-target presentation first. Preserve working optional controls and use concrete visual evidence before expanding this repair.

## Implementation outcome — 2026-09-26

Steps 1–6 are implemented and validated offline. Production reuses the established single-target drawing, typography and control styling with the corrected capability/service owners intact. The missing Home-row repair was reinstated and tested through normal and AppConfig-injected dashboard rows. The confirmed rounded Mode/Preset boxes show both label and selected value.

The historical presentation-only harness, expanded normal/narrow fixtures and real window-pixel motion sequences are reproducible from the climate tests. A stale `cacheDisplay` Canvas capture was identified and replaced in the temporal oracle; geometry-sensitive tests now track the actual target knob. Historical comparison confirms the recovered timing curve's interruption behavior. See the [current evidence packet](../reference-context/modules/module-10-climate-detail.md#presentation-recovery-implementation--2026-09-26) for artifact paths and scope.

Validation passed 35 focused tests and the supervisor's full 382-test suite (six expected opt-in skips, zero failures), plus the source-derived semantic oracle, resolver self-test and final diff checks. There were no live device calls. Additional range/humidity visuals remain provisional capability branches, not newly approved designs; real trackpad/hitch performance is not established by timed captures.

Next action: the user launches `swift run`, opens Room AC from Home, and confirms the restored appearance and animation feel. Keep Module 10 `verification-ready` until that acceptance; do not advance to another module as part of this repair.
