# Implementation route

Build the requested feature, stage, refactor, or parity change. Establish the implementation need from current code and evidence; prefer simple changes that preserve required behavior.

- For a packet-backed stage, follow `docs/reference-context/module-workflow.md`. Check staleness before editing. Use a fresh packet's scope and contracts; resolve missing/stale evidence through bounded research without reopening unrelated modules.
- Keep one Swift-writing owner at a time. Read-only research and independent verification may run in separate bounded tasks; do not overlap code edits.
- Follow `docs/configurability.md` for useful product, performance, diagnostic, and resource choices. Use typed policies/enums for meaningful modes; do not make protocol correctness or ownership invariants optional.
- Keep I/O asynchronous and expensive work off the main actor. Prioritize foreground interaction over background rendering, caches, and prefetch. Preserve cancellation and generation checks so obsolete work cannot publish. Parallelize CPU work when measured benefit outweighs scheduling overhead.
- Run validation appropriate to the changed behavior before handing it to an independent verifier. Record actual results and outstanding gaps.

## Algorithm selection

- When the choice is materially uncertain, benchmark plausible candidates, including relevant native/SIMD options, against a correctness oracle. Use current primary technical sources when research is needed.
- Delegate bounded research/benchmark work when it can run independently; the implementer owns correctness and integration.
- Keep reusable code, methodology, data sizes, and results in a tracked `Benchmarks/<topic>/` directory. Include representative live `1h` and `24h` HA data plus adversarial correctness cases; compare CPU/memory and fidelity, not only elapsed time.
- Use an adaptive algorithm only when measurements justify its extra complexity; put a useful measured crossover policy in `AppConfig.swift`.
