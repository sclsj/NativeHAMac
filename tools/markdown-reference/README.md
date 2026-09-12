# Markdown reference oracle

Run from any directory with Node 20+ and the existing reference checkout's installed dependencies (no installation or reference modification):

```sh
node tools/markdown-reference/oracle.mjs --check
node tools/markdown-reference/oracle.mjs --write /Users/jin/Documents/HA/hass-frontend
```

`--check` validates all fixture assertions and compares exact generated output, fixture hash, dependency versions, source hashes, and Git revision with the committed expected file. `--write` refreshes only `Tests/Fixtures/Markdown/expected-worker.json`; review its diff before accepting new evidence. No timestamp or local path is stored, so repeated output is deterministic. The tool does not contact Home Assistant, fetch media, or open a browser. This JavaScript is research tooling, never native application code.

The tool transpiles the exact local `src/resources/markdown-worker.ts` using its installed TypeScript, replacing only its known import bindings and Comlink `expose(api)` registration. It calls the resulting worker function with installed marked/xss and the markdown card's actual options. It preserves per-token fragments as well as their concatenated sanitized HTML. The transformation fails if the known import/export shape changes. Expected output is evidence of the web reference, not a native HTML renderer or an instruction to execute HTML.

`cases.json` has 24 deterministic fixtures. `core` covers the first-stage Markdown surface; `sanitizer` records edge behavior; `deferred` records the approved first-stage visible inert source fallback for advanced HTML, media, and custom elements. The oracle checks reference output and fixture metadata; it does **not** implement or test NativeHA's future fallback. Empty input here tests the worker; it does not override card configuration rejecting empty source. Live dashboard fixtures are maintained separately by the module owner.

The research read the complete marked 18.0.5 runtime bundle in three untruncated chunks (lines 1–24, 25–50, 51–77), plus readable sourcemap Lexer/Tokenizer source; and xss 1.0.15's complete index/default/parser/xss/util runtime files. CSS filter processing stops at an irrelevant edge: this whitelist permits no style attributes. Comlink transport, Lit rendering, browser URL/DOM parsing, CSS, image loading and custom-element rendering are outside this worker oracle. The deferred QR encoder/custom-icon provider internals are not claimed audited.

Review DOM-only GitHub alert conversion, external target/rel rewriting, visual layout, and actions separately. In particular the GitHub alert fixture's worker result is a blockquote, not the final `ha-alert` DOM. The expected file hashes the relevant DOM/action source files to detect drift, but does not test their execution. See `interaction-notes.md` for the separate action contract.

## Offline component-style visual approximation

`node tools/markdown-reference/visual-harness.mjs` generates a self-contained `generated/index.html` and provenance metadata, without launching a browser. It requires the already captured `Tests/Fixtures/Markdown/live-template-capture.json`. Generated artifacts stay ignored under this tooling directory. The harness embeds the installed Roboto regular/bold/italic fonts, exact literal CSS extracted from `ha-markdown`, `ha-card`, `hui-markdown-card`, typography/core/dark theme variables, and exact worker output. It assembles the relevant static shadow DOM. Primary link color uses the reference `--ha-color-primary-40` value `#009ac7`.

Each core, live-result, text-only and fallback-proposal fixture is available at 496 and 320 CSS pixels. The core fixture is a tall complete document, captured at natural height, not a forced 320/420px composite. Fallback is visibly labelled as a proposed native staging presentation and is not reference rendering.

This is **not** the full Home Assistant runtime or an approved native visual golden: no Lit lifecycle, custom theme, template delivery, action execution, image loading. The status fixtures reproduce the GitHub alert marker transformation and static alert/icon shadow DOM with extracted CSS and installed MDI paths; this remains an approximation of the component runtime. Root must inspect actual PNGs and record these approximations before using them to inform native comparison.

This explicit command launches the existing system Chrome headlessly and writes sixteen scale-2 PNGs. It installs nothing and blocks non-file requests:

```sh
node tools/markdown-reference/visual-harness.mjs --capture '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
```

Read-only discovery also found cached Chromium at `/Users/jin/Library/Caches/ms-playwright/chromium-1076/chrome-mac/Chromium.app/Contents/MacOS/Chromium`. Pass that path as the capture executable if system Chrome is unavailable. The Module 08 review generated and inspected these captures. Regenerate them when the fixtures or reference change; generated PNGs are not tracked baselines.


`status.md` is the shared implementer fixture, consumed verbatim apart from its final newline. States `status`, `status-text-only`, `pending` (title with no first result), and `error` (error alert plus retained live result) are generated at both widths. `status` uses a Markdown heading, not a separate card title. These explicit states do not exercise asynchronous subscriptions. Generated metadata includes the exact status source. Recapture after generation; existing PNGs do not update until the capture command runs.

## Read-only live template smoke

```sh
node tools/markdown-reference/live-probe.mjs /tmp/markdown-live-report.json
```

Uses the fixed deployment/token path, reads dashboard configuration and current user, sends the researched template payload for each existing Markdown card, and awaits successful unsubscribe acknowledgments. It invokes no services and changes no server configuration or entity state. Inspect the output before refreshing `Tests/Fixtures/Markdown/live-template-capture.json`; do not make live network access part of deterministic tests.

## GitHub alert DOM-text oracle

```sh
node tools/markdown-reference/alert-oracle.mjs --check
```

`alert-oracle.mjs` transpiles the exact worker and extracts the complete alert constant and conversion branch from `ha-markdown-element.ts`, then executes that branch unchanged over installed jsdom 29.1.1 HTML parsing/TreeWalker. Seventeen cases in `alert-cases.json` pin escaped markers, code markers, same-line and prefixed markers, distinct rich children, split markers, duplicate text chunks, alert severity, multiline/multiparagraph bodies, and lists inside alerts. `expected-alerts.json` records input/worker/output HTML, alert type/text, revisions, dependencies and source/extracted-branch hashes. `--write` refreshes this evidence only after review. It leaves the original 24-case worker oracle unchanged.

The branch inspects firstElementChild.firstChild.textContent without an escape or code-intent exclusion, using an unanchored case-insensitive expression. `match.input` is the entire first text chunk, so same-line content in that chunk is removed; separate rich children can survive. This records source behavior, including surprising loss, rather than a preferred Markdown interpretation.

Boundary: jsdom implements HTML parsing/DOM traversal here as an established API contract. Its full dependency tree is not audited. No browser, CSS/layout, custom-element initialization, click handling or native rendering is tested.

`core.md` is the shared composite document for native/browser core comparison. It closes the intentionally unterminated fence from the independent code fixture and inserts thematic rules between cases so adjacent lists cannot merge. Both renderers must parse this exact file once; concatenating separately parsed HTML is not equivalent to parsing concatenated Markdown. The original 24 standalone oracle fixtures retain their malformed-fence/list-boundary coverage unchanged.
