# Module 08 - MarkdownCard Rendering and Template Support

## Purpose

Render Lovelace `markdown` cards as actual Markdown and prepare for Home Assistant template rendering through WebSocket subscriptions.

The live dashboard has two markdown cards, so static Markdown rendering has immediate value. Template rendering should be implemented only after WebSocket multiplexing is reliable.

## Current-Code Findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- `MarkdownCard` currently renders `card.content` using plain `Text`.
- Markdown syntax, links, lists, emphasis, headings, and code blocks are not rendered.
- HA template rendering is not supported.
- `show_empty`, `text_only`, and action options are not modeled robustly.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`:

- `LovelaceCard` includes `content` but does not preserve all markdown-card-specific options.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-markdown-card.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/components/ha-markdown.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/data/ws-templates.ts`

## Target Architecture

Split the card into three concerns:

- `MarkdownCardConfig`
  - Decodes and preserves Lovelace options.
- `MarkdownRenderer`
  - Converts static Markdown into SwiftUI-renderable attributed text or structured views.
- `TemplateRenderSubscription`
  - Uses WebSocket template rendering when the content contains HA templates.
  - Owns subscribe/unsubscribe lifecycle through Module 02.

## Confirmed Corrections to Claude's Original Direction

- Do not treat Markdown as a visual-only polish item. HA dashboards often use Markdown for dynamic status summaries.
- Do not implement template rendering by doing local string interpolation. HA templates must be rendered by Home Assistant because they can reference server state, helpers, and Jinja-specific behavior.
- Do not block static Markdown rendering on template support. The two should be staged.

## Implementation Tasks

1. Expand markdown card decoding.
   - Add or preserve:
     - `content`
     - `title`
     - `show_empty`
     - `text_only`
     - `card_size`
     - `tap_action`
     - `hold_action`
     - `double_tap_action`
   - Preserve unknown keys.

2. Implement static Markdown rendering.
   - Use `AttributedString(markdown:)` if platform deployment allows.
   - If `AttributedString(markdown:)` is insufficient for layout, add a small renderer that supports headings, paragraphs, lists, links, inline code, fenced code, emphasis, strong text, and line breaks.
   - Keep styling consistent with existing NativeHA card typography.

3. Add safe fallback behavior.
   - If Markdown parsing fails, show plain text rather than an empty card.
   - If `content` is nil or empty:
     - Hide the card when `show_empty == false`.
     - Show an empty placeholder only when consistent with HA behavior and useful for debugging.

4. Detect template content.
   - Treat content containing `{{`, `{%`, or `{#` as template-capable.
   - Static Markdown without template markers should not open a WebSocket template subscription.

5. Add template rendering after Module 02.
   - Use HA's template WebSocket API through the multiplexer.
   - Subscribe while the card is visible.
   - Update rendered content when the server pushes a new rendered result.
   - Unsubscribe when the card disappears or the active Lovelace view changes.
   - Recreate subscriptions after reconnect.

6. Render server output as Markdown.
   - HA renders the template to a string; NativeHA should then pass that string through the Markdown renderer.
   - Keep an error state if template rendering fails.

7. Honor `text_only`.
   - When `text_only` is true, render content without extra card chrome if the surrounding UI supports it.
   - If full HA parity is hard in current layout, document the difference and keep the config preserved.

8. Add link behavior.
   - External links should open in the system browser.
   - Internal HA navigation links should be decoded but can be deferred to Module 12 or a shared action-routing module.

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/MarkdownRenderer.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/MarkdownTemplateStore.swift`

Out of scope:

- A full HTML renderer.
- Running HA/Jinja templates locally.
- Editing Markdown cards.
- Full Lovelace action parity unless shared action routing already exists.

## Tests and Verification

Follow the offscreen capture and approved-reference workflow in
[`../visual-testing.md`](../visual-testing.md). Parsing, link policy, template
routing, sanitization, and lifecycle require semantic tests; pixels alone cannot
show that content is safe or that only the intended card subscribed.

### Unit tests

Add `MarkdownRendererTests.swift` and, after template task 5 is implemented,
`MarkdownTemplateStoreTests.swift` to `NativeHAMacTests`. Use fixed strings for:

- headings, paragraphs, emphasis/strong text, links, ordered and unordered
  lists, inline code, line breaks, and the subset of fenced code actually
  supported by the chosen renderer;
- long unbroken and whitespace-delimited lines, empty/nil content, malformed or
  unsupported markup, and plain-text parse fallback;
- `show_empty`, `text_only`, title, and card-chrome decisions;
- template marker detection for `{{`, `{%`, and `{#`, including similar text
  that must remain static;
- server-rendered output passing back through Markdown exactly once; and
- external versus internal link classification without opening a browser in the
  unit suite.

Define and test the renderer's safety boundary. At minimum, script/event-handler
content, unsafe URL schemes, unexpected HTML, images/data URLs, and malformed
links must be rejected, escaped, or rendered as inert text according to the
implementation's documented supported subset. This is an implementation-time
decision: NativeHA does not currently have an HTML renderer, and this plan does
not require one. Compare the intended subset and safe fallback with
`hui-markdown-card.ts`, `ha-markdown.ts`, and hass-frontend's
`ha-markdown-element.ts`/`render-markdown` path rather than assuming web HTML can
be passed directly into SwiftUI.

### Integration tests

Add `MarkdownCardIntegrationTests.swift` with fixture-only view models/transports
and no live server. Verify that static Markdown never subscribes; dynamic
content subscribes through Module 02 only while visible; an initial and late
template result rerender only the affected card; two template cards do not
share results accidentally; errors remain recoverable; reconnect does not
duplicate subscriptions; and disappearance prevents post-cancellation updates.
Assert that logs, failures, artifacts, and fixture descriptions do not expose
credentials or unredacted sensitive template results.

### GUI rendering and visual regression

Add `MarkdownCardRenderingTests.swift` (or extend the existing
`GUIRenderingAndPerformanceTests.swift` until its renderer helper is shared) and
run it on the main actor. On macOS 12 with Swift 5.6/Xcode 13.4.1, use
`MacViewPNGRenderer`: `NSHostingView` in an offscreen AppKit window with capture
through `bitmapImageRepForCachingDisplay(in:)` and
`cacheDisplay(in:to:)`. SwiftUI `ImageRenderer` is unavailable.

At display scale 2, fixed dark-Aqua appearance, dark color scheme, locale,
timezone, and timestamps, render both the production 496-point width and a
320-point narrow width. Use `496x320` for the normal composite content fixture,
`320x420` for its narrow counterpart, `496x120` and `320x160` for empty/fallback
states, and `496x220` and `320x280` for explicit async template states. Always
write inspectable PNGs to `.build/render-artifacts/` for:

- headings plus paragraphs;
- emphasis/strong text and links;
- ordered and unordered lists;
- long wrapping lines at both widths;
- empty content with each supported `show_empty` outcome;
- unsupported/malformed markup fallback; and
- a supported dynamic template's initial/loading state and settled late result,
  once template subscriptions are implemented.

Use fixture/state/width filenames such as `markdown-composite-496.png`,
`markdown-long-lines-320.png`, `markdown-empty-hidden-320.png`, and
`markdown-template-settled-496.png`. Do not write the hidden-card filename as a
fabricated blank golden; use it only for a diagnostic parent-layout artifact if
needed, while the pass/fail contract remains semantic visibility removal.

Assert valid PNG signature, exact dimensions, nonblank output when content
should be visible, expected text/link/list regions, padding, wrapping without
horizontal clipping, and the settled result replacing its loading state. For an
intentionally hidden empty card, assert semantic visibility/layout removal
rather than requiring a nonblank PNG. Always write current visible-state
artifacts and manually compare them with the same content/configuration in
`/Users/jin/Documents/HA/hass-frontend`; do not mechanically approve NativeHA's
current output. Only reviewed PNGs go in
`Tests/NativeHAMacTests/ReferenceImages/`, with tolerant pixel comparison and a
documented macOS baseline version. CI may later require the completed set via
`NATIVEHA_REQUIRE_VISUAL_REFERENCES=1`. Intentional visual changes require
reviewing actual, expected, and preferably diff artifacts before updating a
reference.

### Animation and interaction

This module does not require decorative animation. Represent async template
delivery as explicit loading, result, empty, and error states and snapshot those
meaningful states; do not sleep until a real WebSocket happens to update. Use a
bounded expectation or poll only to settle the offscreen SwiftUI view. If a
custom link/card hover or press transition is added, expose deterministic state
and render unhovered/hovered and released/pressed, or progress `0`, `0.5`, and
`1`; assert distinct keyframes and a correct final frame, and test reduced
motion where supported. Link destination and action routing remain semantic
assertions, not screenshot claims.

### Performance and lifecycle

Add `MarkdownCardPerformanceTests.swift`. Prepare content outside measured
blocks, consume the attributed/structured output, warm caches before warm
measurements, and use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric` to
measure:

- cold parsing/preparation of a deterministic 1 MB Markdown document containing
  headings, paragraphs, emphasis, links, and lists;
- warm cached preparation of that same document;
- 100 repeated late-template results affecting one of 100 cards, without live
  template subscriptions; and
- repeated subscribe/unsubscribe, reconnect, card removal, and task
  cancellation once template support exists.

Measure Markdown preparation separately from offscreen bitmap capture. Prefer
stored XCTest baselines; a broad safety ceiling is acceptable only if loose and
documented. Verify memory stabilizes and cached attributed content,
subscriptions, and callbacks do not retain disappeared cards. Signpost metrics
apply only to instrumented work. `XCTHitchMetric` is unavailable in Xcode
13.4.1, so real click/scroll event-to-frame hitch testing is later XCUITest work
under newer Xcode.

### Manual QA

- Inspect both live Markdown cards at normal and narrow window widths and
  compare typography, headings, lists, link styling, line breaks, padding,
  wrapping, clipping, empty behavior, and unsupported markup fallback with
  hass-frontend.
- With an offline fake result or a non-mutating live reference check, confirm a
  late template result changes only its card, a broken template shows a
  recoverable error, and navigating away stops updates.
- Exercise external and internal links only after reviewing routing policy;
  confirm unsafe schemes/content are inert and no fixture, artifact, or log
  contains secrets.

## Dependencies

- Module 02 for template subscriptions.
- Module 04 for complete markdown card decoding.
- Module 05 for card lifecycle and active-view cancellation.
- Module 12 for internal navigation links if supported.

## Risks

- Swift `AttributedString(markdown:)` may not cover all Markdown/HTML that HA's web component supports.
- Template subscriptions can leak if tied to SwiftUI view identity instead of the dashboard/view lifecycle.
- Rendered template output may be empty by design. Respect `show_empty` rather than forcing placeholders.
- Swift `AttributedString` behavior and supported Markdown differ across OS
  releases; document the supported subset and keep semantic parsing tests
  separate from OS-specific tolerant visual baselines.
- Treating server-rendered Markdown as trusted HTML would create a security gap.
  The implementation must choose and test an inert/sanitized fallback rather
  than infer safety from hass-frontend screenshots.
- A cache or template store keyed too broadly can display one card's late result
  in another card or retain sensitive output after disappearance.
- True browser-style focus, click, and scroll hitch testing is outside the
  current SwiftPM/Xcode 13.4.1 setup; deterministic state rendering and semantic
  routing tests are required now, with later XCUITest if needed.

## Acceptance Criteria

- Static Markdown renders as formatted content.
- Empty and malformed content have intentional fallback behavior.
- Template content is detected and routed to HA server-side rendering after WebSocket multiplexer support exists.
- Template subscriptions unsubscribe correctly.
- The live dashboard's Markdown cards no longer display raw Markdown syntax unless the source intentionally uses plain text.
- Unit tests define the supported Markdown subset, empty/fallback behavior,
  template detection, link classification, and sanitization/inert handling of
  unsafe content without opening browsers or contacting Home Assistant.
- Integration tests prove static cards do not subscribe and that late template
  results, errors, reconnect, and cancellation remain isolated to the correct
  card when template support is implemented.
- Reviewed 496-point and 320-point artifacts cover the required static fixtures
  and, when supported, explicit template states; they pass PNG, dimension,
  nonblank/visibility, region, wrapping, clipping, and padding checks with
  OS-documented tolerant references where approved.
- Cold and warm 1 MB preparation, 100-card late-result isolation, and applicable
  subscription lifecycle tests pass stored XCTest performance baselines without
  unbounded memory growth or retained disappeared cards.
- Manual hass-frontend comparison covers visible fidelity, while semantic tests
  remain the authority for safety, link routing, template lifecycle, data
  isolation, and performance.
