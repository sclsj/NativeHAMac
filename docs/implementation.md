# Implementation route

Use this route for features, modules, planned stages, broad refactors, and
general parity work. Do not redo the planning phase or read rescue plans merely
to rediscover scope already supplied by the task and its evidence packet.

- Establish the cause or implementation need from relevant code, observed
  behavior, and tests before speculative changes. Prefer simple, minimally
  invasive changes that preserve required behavior.
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
- Maintain `docs/knowledge-base.md` when implementation measurements or
  discoveries establish or invalidate a durable, non-obvious fact that future
  work should not have to rediscover.
- When a user-directed behavior or implementation policy creates or changes a
  durable intentional deviation from hass-frontend or an earlier product
  assumption, update `docs/user-deviations.md` in the same commit.

## Algorithm selection and benchmarks

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

Before a handoff, compaction, or session end, update the applicable module
evidence packet with status, decisions, actual diff scope, validation, remaining
gaps, and the exact next action.
