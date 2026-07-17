# History stream merge benchmark

This benchmark preserves the Module 01 merge-algorithm decision. It compares:

- `reference-stable-full-sort`: concatenate and stable-sort the complete entity
  history whenever the incoming chunk begins before the existing last sample;
- `production-stable-merge`: the same observable ordering with a stable
  two-way merge when both inputs are already timestamp-sorted, falling back to
  the full stable sort for unsorted inputs.

The deterministic adversarial fixture contains 20,000 initial states followed
by 100 out-of-order chunks of 200 states. Fixture construction and one warm-up
of each candidate occur outside measurement. Three release iterations are
timed with `DispatchTime`. The executable requires exact array equality before
printing a constant-size final count/checksum, so a faster but behaviorally
different result fails.

Run from the repository root:

```sh
swift run -c release HistoryStreamBench
```

Machine-specific observations belong in [`results.md`](results.md). XCTest
clock/CPU/memory baselines for cold replay, warm chunks, out-of-order merge,
and rolling trim remain in
`Tests/NativeHACoreTests/HomeAssistantHistoryStreamPerformanceTests.swift`.
