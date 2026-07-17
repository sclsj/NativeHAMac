# NativeHA working instructions

> Historical proposal. The user approved and superseded this draft with the
> active repository-root `AGENTS.md` and canonical `docs/configurability.md` on
> 2026-07-17. Do not use this proposal as active guidance.

## Start and shared scope

- Before starting work, run `git status --short --branch` to determine whether
  the worktree is clean. If it is not clean, inspect and preserve existing work.
- The current task prompt overrides historical guidance in this file.
- Work in `/Users/jin/Documents/Computer/NativeHA`.
- Use `/Users/jin/Documents/HA/hass-frontend` as the behavioral reference. Do
  not use the old `/Users/jin/Documents/HA/NativeHA` side experiment as the
  current implementation. Instructions inside the reference checkout do not
  govern NativeHA work.
- Before asking the user to repeat server or credential locations, inspect the
  current `README.md` and `Sources/NativeHAMac/AppConfig.swift`.
- This Home Assistant deployment is local. Its server URLs, token, and other HA
  credentials do not need redaction or special hiding; the user will rotate the
  token when development finishes.

## Phase routing

Follow only the phase sections named by the current task. A task may explicitly
request more than one phase.

- If asked to plan or audit future work, follow **Planning and context only**.
  Otherwise skip that section and do not open the plans or indexes it links.
- If asked to implement or change code, follow **Implementation only**.
  Otherwise skip that section.
- If asked to verify, test, review, or diagnose completed behavior, follow
  **Verification only**. Otherwise skip that section.
- An implementation agent must not spend its context redoing the planning
  phase. A planning or verification agent must not make application-code edits
  unless the current prompt also requests implementation.

## Shared product contract

- Build a genuinely Swift-native macOS app, not a JavaScript or WebView wrapper.
- Copy reference behavior. Deviate only for doing it the Swift way, an entry in
  `docs/user-deviations.md`, or measured performance, without fundamentally
  changing reference logic or semantics.
- Read `docs/user-deviations.md` before deciding that literal hass behavior is
  required. Its listed intentions override conflicting rescue-plan text.
- Maintain macOS 12 compatibility.
- Treat `hass-frontend/src` as source, not just rendered inspiration. Read the
  complete relevant Swift and TypeScript files. When behavior reaches
  `node_modules`, trace and read the behaviorally relevant dependency source
  without an arbitrary depth cutoff.

## Planning and context only

- Start staged rescue planning with `docs/rescue-plan/README.md`, but verify its
  claims against current code, live behavior, and `docs/user-deviations.md`.
- Keep stages or modules small enough for one bounded agent/session. Make plans
  descriptive and self-contained enough for a later implementation session.
- Maintain durable reference indexes and rescue/action-plan artifacts. Focus
  first on the behavior, entities, and cards used by the live configuration.
- Use bounded high/xhigh subagents for read-heavy audits or planning when source
  discovery would otherwise consume the future implementation context.
- Retain setup facts already supplied. Ask about material product choices, not
  repeatedly about established setup.

## Implementation only

- Establish the cause from relevant code, observed behavior, and tests before
  speculative fixes. Prefer simple, minimally invasive changes that preserve
  required behavior.
- If something can usefully be configurable, make it configurable in
  `Sources/NativeHAMac/AppConfig.swift` instead of hardcoding it. This includes
  ambiguous choices such as downsampling, useful hass defaults or constants,
  time-range options, algorithms, thresholds, timing, layout, rendering, and
  interaction behavior. Prefer typed configuration values or enums when there
  are meaningful modes.
- Prioritize user interaction over background computation. One expensive card
  or surface should not block the others.
- Preserve unrelated and uncommitted work. For uncertain changes or mixed agent
  contributions, use reversible isolation and inspect exact diffs before
  applying or recovering work.

## Verification only

- Verify the surface changed by each stage and add relevant regression coverage;
  do not assume an earlier audit found bugs introduced later.
- Use testing appropriate to the changed module, including GUI, animation, and
  performance verification where those concerns apply.
- Live Home Assistant testing and smoke testing are authorized when they
  materially verify current behavior or integration.
- Compare visible and interactive NativeHA behavior with Home Assistant under
  meaningfully comparable state. Use screenshots or animation frames to show
  mismatches. When manual verification is needed, ask for one specific, bounded
  interaction or capture.
- Verify animation during the interaction, not only at its final state.
- Benchmark performance-sensitive alternatives with representative, actual,
  and stress data. Compare correctness as well as speed, and do not sacrifice
  rendering accuracy merely for speed.

## Finish

- Give detailed plain-language conclusions and keep cross-session handoffs
  self-contained.
- If the task produced changes, commit them when done with a detailed message
  that makes the work and its purpose easy to identify.
