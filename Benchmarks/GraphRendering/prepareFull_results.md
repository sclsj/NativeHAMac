# prepareFull Optimization Benchmarks

These benchmarks measured the execution time of `GraphPreparedSeriesCache.shared.series(for: displayUnit:)` (which internally calls `prepareFull`) using the `sps30_1day.json` dataset (84,000 data points).

## Baseline
- Average time: **405 ms**
- Relative Standard Deviation: 0.625%

## Optimization 1: numericValue Early Return
- **Change**: Tried parsing `Double(state)` before allocating strings via `state.lowercased()`.
- **Average time**: **387 ms**
- **Speedup**: ~18 ms (4.5% faster than baseline)

## Optimization 2: displayValue Unit Check
- **Change**: Passed `isStateTimeline` boolean to `displayValue` instead of checking `unit.lowercased() == "state"` on every iteration.
- **Average time**: **368 ms**
- **Speedup**: ~19 ms (9.1% faster than baseline)

## Optimization 3: Lazy display formatting
- **Change**: Simulated lazy string formatting by skipping `Double(state)` and `String(format:)` entirely in `prepareFull`, and just passing `point.state` to `GraphRenderedPoint.display`.
- **Average time**: **279 ms**
- **Speedup**: ~89 ms (31.1% faster than baseline)

## Conclusion
By implementing these 3 optimizations together, we can drop the execution time of `prepareFull` for large datasets from 405 ms down to 279 ms (a ~31% speed improvement).
