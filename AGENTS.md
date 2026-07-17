# NativeHA working instructions

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
- Read and maintain `docs/user-deviations.md` and `docs/configurability.md`.
  They are canonical product intent, not historical planning material. Update
  them in the same commit when the user changes a durable decision or an
  implementation changes a recorded status or assumption.

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
  phase or reading rescue plans merely to rediscover scope. A planning or
  verification agent must not make application-code edits unless the current
  prompt also requests implementation.

## Shared product contract

- Build a genuinely Swift-native macOS app, not a JavaScript or WebView wrapper.
- Copy reference behavior. Deviate only for doing it the Swift way, an approved
  entry in `docs/user-deviations.md`, or measured performance, without
  fundamentally changing reference logic or semantics.
- The intentions in `docs/user-deviations.md` override literal hass behavior and
  conflicting rescue-plan text. Do not infer unlisted deviations from
  implementation convenience.
- `docs/configurability.md` is the canonical list of approved configuration
  surfaces. Configurable here means a typed value or policy in
  `Sources/NativeHAMac/AppConfig.swift`; it does not imply a settings UI unless
  the task asks for one.
- Maintain macOS 12 compatibility.
- Treat `hass-frontend/src` as source, not just rendered inspiration. Read the
  complete relevant Swift and TypeScript files. When behavior reaches
  `node_modules`, trace and read the behaviorally relevant dependency source
  without an arbitrary depth cutoff.

## Planning and context only

- Start staged rescue planning with `docs/rescue-plan/README.md`, but verify its
  claims against current code, live behavior, `docs/user-deviations.md`, and
  `docs/configurability.md`.
- Use `docs/reference-context/README.md` as the durable module evidence and
  handoff index. For a missing or stale packet, create or refresh the reviewed
  module manifest, generated dependency graph, and human evidence packet by
  following `docs/reference-context/module-workflow.md`.
- Resolve reference sources with `tools/reference-context/trace-ts-deps.mjs`
  through a module manifest instead of manually crawling all of
  `hass-frontend`. Record repository revision, relative path, stable symbol,
  and blob/content hash; line numbers are navigation hints only. Calls through
  types or dependency injection may require an explicit reviewed runtime seed.
- Keep generated graphs rebuildable and out of prompt context. Promote only
  behavior-relevant contracts, anchors, decisions, risks, and unresolved
  questions into the human evidence packet.
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
- For a staged module with a reference-context packet, run its documented
  staleness check and read the packet before editing. If green, use its contract
  IDs and cited anchors without reopening the broad planning audit or loading
  the full generated graph. If missing, yellow, or red, stop application edits
  and dispatch a bounded read-only packet refresh first.
- Use one Swift-writing owner at a time. A researcher may prepare the packet and
  an independent verifier may follow the implementation, but they must not make
  overlapping application-code edits.
- If a useful product, performance, or resource choice can be configurable,
  make it configurable in `Sources/NativeHAMac/AppConfig.swift` instead of
  hardcoding it. This includes ambiguous algorithms such as downsampling,
  useful hass defaults or constants, time ranges, thresholds, timing, layout,
  rendering, interaction, and cache budgets. Prefer typed policies or enums
  when there are meaningful modes. Keep `docs/configurability.md` synchronized.
- Keep the main UI responsive. Make I/O and long-running procedures asynchronous
  when sensible, and move expensive work off the main actor. Easily
  parallelizable CPU work should use multiple cores by default when measured
  overhead is negligible. One slow graph/card must not prevent closing or
  interacting with that surface or the rest of the app.
- Prioritize foreground interaction over background rendering, caching, and
  prefetching. Preserve cancellation and generation correctness so stale work
  cannot overwrite newer state.
- Preserve unrelated and uncommitted work. For uncertain changes or mixed agent
  contributions, use reversible isolation and inspect exact diffs before
  applying or recovering work.

### Algorithm selection and benchmarks

- When the best algorithm is unclear, benchmark all sensible candidates instead
  of choosing by intuition. Search current primary technical sources when in
  doubt, and include relevant SIMD/vectorized options such as Apple Accelerate.
- Delegate the research and benchmark run to a bounded subagent so source scans,
  build output, and raw results do not consume the implementation agent's
  context. The implementation agent owns the final correctness and integration
  decision.
- Keep reusable benchmark code, methodology, data-size metadata, and results in
  a dedicated tracked `Benchmarks/<topic>/` directory. Commit this material with
  the implementation so later stages can rerun or reference it.
- Use live Home Assistant data and cover at least a representative small window
  such as `1h` and large window such as `24h`, in addition to adversarial data
  needed for correctness. Compare output correctness and resource use, not only
  elapsed time.
- If different algorithms win at different data sizes, and an adaptive choice
  is not overly complex, implement both and select through a measured,
  configurable threshold in `AppConfig.swift`.

## Verification only

- Verify the surface changed by each stage and add relevant regression coverage;
  do not assume an earlier audit found bugs introduced later.
- For a packet-backed module, verify by contract ID, update its validation
  results and exact failures, and move its status to `complete` only when all
  required offline, live, visual, performance, and lifecycle checks that apply
  have evidence.
- Use testing appropriate to the changed module, including GUI, animation,
  responsiveness, concurrency, cache, and performance verification where those
  concerns apply.
- Live Home Assistant testing and smoke testing are authorized when they
  materially verify current behavior or integration.
- Compare visible and interactive NativeHA behavior with Home Assistant under
  meaningfully comparable state. Use screenshots or animation frames to show
  mismatches. When manual verification is needed, ask for one specific, bounded
  interaction or capture.
- Verify animation and UI availability during the interaction, not only at its
  final state. In particular, verify that slow cards do not block dismissal or
  unrelated controls.
- For algorithm or cache changes, rerun the tracked benchmark work with live
  `1h` and `24h` data, check cold and warm behavior where relevant, and compare
  correctness as well as speed and memory. Do not sacrifice rendering accuracy
  merely for speed.

## Finish

- Before a phase handoff, compaction, or session end, update the module evidence
  packet with status, decisions, actual diff scope, validation, remaining gaps,
  and the exact next action. This packet, not the raw transcript or generated
  dependency graph, is the durable continuation point.
- Give detailed plain-language conclusions and keep cross-session handoffs
  self-contained.
- If the task produced changes, inspect the exact final diff and commit the
  intended files when done. Use a detailed commit message that identifies the
  work, validation, and purpose.
