# Module 08 measurements — 2026-09-12

macOS 12.6.7, arm64, Swift 5.6.1, Xcode 13.4.1. Production parser, preparation cache and coordinator tests; see [methodology](README.md). These are local measurements, not portable latency guarantees.

| Workload | Final debug | Final release | Interpretation |
|---|---|---|---|
| Cold structured Markdown, 1,048,598 source bytes | 2.635 s elapsed; 2.670 s CPU | 2.379 s elapsed; 2.417 s CPU | Five measured samples; parsing happens off-main in production |
| Warm lookup, 1,125,000 source bytes, 100 repetitions | 44.60 ms total | 44.60 ms total | Diagnostic **64 MiB** cache, populated before timing |
| Same dense document under production **16 MiB** policy | 4.081 s; zero cached bytes | 3.694 s; zero cached bytes | Estimated document cost is 57,900,000 bytes, so the complete document renders but bypasses caching |
| 100 streamed updates to one of 100 cards | 22.47 ms to settle | 8.30 ms to settle | No dashboard-wide publications; other cards retain their own state; stop retires all owners |

Cold elapsed samples were 2.619159, 2.649603, 2.636663, 2.611401 and 2.660674 seconds. The cold and warm fixtures differ: the warm fixture contains 75,000 repeated paragraphs and emphasizes attributed-run/cache cost.

XCTest memory metrics are not useful allocation evidence here: the physical memory delta averaged 131.072 kB with 1,251.5% relative standard deviation, and the reported peak metric was zero. Release likewise reported a noisy 180.224 kB delta (833% relative deviation) and zero peak. Do not interpret these as peak/resident memory bounds. Explicit cache cost accounting, oversized bypass, retirement snapshots and deinit tests establish the bounded policies and owner cleanup; they do not establish a process RSS ceiling.

The production budget remains 16 MiB because the captured deployment result is small. The larger-cache measurement demonstrates reuse when a document fits; it is not the production-default performance for this oversized fixture. There is no source-size truncation or partial rendering to achieve these times.

Full validation: debug 356 tests and release 344 tests, each with 5 skipped and zero failures. Independent validation is recorded in the [Module 08 packet](../../docs/reference-context/modules/module-08-markdown-card.md).
