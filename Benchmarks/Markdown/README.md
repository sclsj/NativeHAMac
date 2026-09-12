# Native Markdown preparation and ownership

Reusable measurements live in `Tests/NativeHAMacTests/MarkdownTests.swift` so they exercise the production parser and preparation cache on macOS 12:

```sh
swift test --filter MarkdownPerformanceTests
swift test -c release --filter MarkdownPerformanceTests
```

The cold input is approximately 1 MiB of repeated headings, paragraphs, emphasis, links and lists, constructed before the measured block. XCTest collects elapsed time, CPU and memory; assertions consume the resulting blocks. Warm measurements populate a separate cache before repeated lookups. Report the configured cache budget with results: a cache too small for the estimated document cost tests repeated cold preparation instead of a warm hit.

Template owner isolation and retirement use deterministic fake transport tests, not live subscription timing. The tracked live Markdown result is small and serves as a correctness/rendering fixture. Graph `1h`/`24h` history data is not an input to Markdown preparation and is not changed by this module.

Inspect native rendering artifacts separately from preparation timings. A faster parse or a green source fingerprint does not establish rendering fidelity. These measurements do not measure app launch, scroll hitches or real input-to-frame latency.
