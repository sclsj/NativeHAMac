# Recorded results

## 2026-07-17 local development machine

Command:

```sh
swift run -c release HistoryStreamBench
```

Output after one unmeasured warm-up per candidate:

```text
fixture initial=20000 chunks=100x200 final=40000
checksum 8026277772552279935
production-stable-merge-ms samples=[94.669,111.969,94.079] average=100.239
reference-stable-full-sort-ms samples=[150.606,147.941,153.389] average=150.645
speedup-average 1.50x
```

The exact output arrays matched. This selects the stable two-way merge for
already-sorted inputs while retaining the stable full-sort fallback for any
unsorted input. Times are observations, not machine-independent limits.
