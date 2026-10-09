# Fan reference fixtures

## Numerical oracle

Run `node tools/fan-reference/semantic-oracle.mjs --check` from NativeHA to compare the actual reference functions with the tracked `Tests/Fixtures/Fan/expected-semantics.json`. `--print` prints candidate output without modifying the fixture. `HA_REFERENCE_ROOT` selects another read-only reference checkout if needed. Changes to source hashes or results fail the check; inspect them rather than automatically blessing new expectations.

The oracle follows the existing climate oracle's AST-extraction approach. It transpiles selected exact declarations from `src/data/fan.ts` and undecorated methods from `src/components/ha-control-slider.ts`, using the reference's installed TypeScript. Every named declaration/method must exist exactly once. Output records the reference revision, complete source hashes, selected members and TypeScript version. No reference files are edited and no packages are installed.

Coverage includes feature bits, speed-count threshold, discrete selected-speed/payload conversions, vertical pointer mapping and stepping, and LTR/RTL keyboard arithmetic with recorded keydown/keyup events. Invalid reference numbers remain explicit `{ "$number": "Infinity" }` or `"NaN"` objects, not misleading JSON nulls. Native safety tests must distinguish rejected malformed input from ordinary missing/null defaults.

Important reference distinctions include step33 High=99, step16 pointer-top=96 versus End-key=100, and out-of-domain outputs such as step22 pointer-top=110 and step40 High=120. Those last outputs are reference observations, not permission for native service dispatch; the planned native boundary rejects them without silently rewriting their value.

This is a pure source-derived oracle, not a browser or native UI test. Fixture bounding rectangles, document direction, recording events and no-op tooltip methods provide only the dependencies needed for the selected arithmetic. It does not execute Hammer recognition, Lit rendering/binding, timer behavior, service transport, header localization, menus or actual device response. Pointer composition evaluates the reviewed position/value/step sequence; it does not prove event delivery or action count. Those require the later mounted and paired-reference verification slices. No credentials, live HA requests or device mutations are used.

## Actual-component browser fixture

Run `node tools/fan-reference/browser-harness.mjs --serve`. It bundles the reference checkout's real `more-info-fan` and dependencies into `.build/fan-reference`, then prints an ephemeral loopback URL. Without `--serve`, it only builds. The harness reuses installed reference packages and the climate TypeScript loader; it installs nothing and never writes into the reference checkout. Stop the owned server after testing.

`window.harness.setFixture(name, width)` mounts a synthetic state with English locale and dark theme. Names come from `Tests/Fixtures/Fan/render-variants.json`, merged onto `complete.json` including its attributes. Use widths 360 and 520 with a 620-pixel viewport, and record actual viewport/device scale in the capture report. `harness.replace(attributes, state)` supplies an authoritative replacement; `harness.calls` records service requests without contacting Home Assistant. Exercise real DOM input rather than invoking component handlers when testing event behavior.

The fake API has no HA connection or credentials, and the server's CSP restricts connections to itself. Backend entity/component translations and attribute-icon metadata are deliberately absent; raw fallback labels or missing attribute icons are not evidence about a live deployment. The reference uses its real relative state-header clock, while native retains the existing shared absolute header. Compare control regions separately rather than claiming identical full-dialog typography, metadata, or time text. No screenshots are automatically approved baselines.

In Codex CLI, the user's plain `omp` defaults provide browser access through its `eval` tool's `browser` object. Do not override its tools with `--tools browser`: that is not a registered standalone tool. An agent timeout may leave valid screenshots but does not establish that its interaction checks finished; retain only explicit reported results.
