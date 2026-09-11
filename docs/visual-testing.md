# GUI, animation, and performance testing

NativeHA can test most of its visual behavior on macOS 12 without `ImageRenderer` or third-party snapshot libraries. The test target hosts SwiftUI in AppKit with `NSHostingView`, captures the result through `NSView`'s bitmap cache API, and writes inspectable PNGs to `.build/render-artifacts`.

## Run the tests

```sh
swift test --filter GraphRenderingTests
swift test --filter CardReferenceContractTests
swift test --filter GUIRenderingAndPerformanceTests
```

The full suite still runs with:

```sh
swift test
```

## What is covered

- Graph bitmap dimensions, plot geometry, tick generation, colored output, state-timeline segments, zoom windows, hover samples, anchored zoom, and pan sensitivity.
- Offscreen PNG rendering for an entities card and a complete history graph view, including the asynchronous graph render settling past its loading state.
- Explicit climate-dial animation keyframes at 15%, 50%, and 85%. Testing explicit progress values is deterministic and catches broken interpolation or drawing without depending on scheduler timing.
- Warm graph interaction rendering with XCTest wall-clock, CPU, and memory metrics. Xcode can store a performance baseline for this test.

One Home Assistant parity contract currently uses `XCTExpectFailure`: numeric history hover should use the previous sample rather than a future sample. Remove the expectation when corrected. The approved global graph-range policy has an ordinary passing test; per-card `hours_to_show` is not the intended default-dashboard behavior.

The step-end pixel test also passes, but the [2026-09-11 audit](audits/2026-09-11-readiness.md) demonstrates that its narrow fixture produces a false positive against the current diagonal renderer. Replace it with a geometry-sensitive oracle during the bounded graph repair; do not interpret its current result as step-end conformance.

## Approve visual baselines

1. Run `swift test --filter GUIRenderingAndPerformanceTests`.
2. Inspect `.build/render-artifacts` beside the same fixture/state in `hass-frontend`.
3. Copy an approved PNG to `Tests/NativeHAMacTests/ReferenceImages` with the same filename.
4. Re-run the test. It now applies a tolerant pixel comparison.

Once the checked-in reference set is complete, use:

```sh
NATIVEHA_REQUIRE_VISUAL_REFERENCES=1 swift test --filter GUIRenderingAndPerformanceTests
```

Do not approve all current output mechanically: a golden image is valuable only after it has been compared with the reference UI. Keep baselines on one macOS version because text antialiasing and system controls can differ across releases.

## Limits on this machine

Xcode 13.4.1 can collect `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, and signpost metrics. It does not expose the newer `XCTHitchMetric` API. True app launch, scroll/deceleration, and event-to-frame hitch tests should be added later in an XCUITest target when the project has an Xcode app target and a newer Xcode. The current deterministic renderer metrics and keyframe snapshots cover the largest useful subset without changing the macOS 12 deployment target.
