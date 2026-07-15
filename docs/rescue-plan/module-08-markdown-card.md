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

Add unit tests for:

- Markdown headings, emphasis, strong text, lists, links, and inline code.
- Parse failure falls back to plain text.
- Empty content respects `show_empty`.
- Template detection.
- Template subscription command construction after Module 02.
- Rendered template output is passed back through Markdown rendering.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/MarkdownRendererTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/MarkdownTemplateStoreTests.swift`

Manual QA:

- Open the live dashboard and inspect both Markdown cards.
- Confirm Markdown syntax renders visibly rather than as raw punctuation.
- Use a fixture card with a template and confirm the rendered result updates when referenced state changes.
- Confirm a broken template displays a recoverable error instead of crashing the card.

## Dependencies

- Module 02 for template subscriptions.
- Module 04 for complete markdown card decoding.
- Module 05 for card lifecycle and active-view cancellation.
- Module 12 for internal navigation links if supported.

## Risks

- Swift `AttributedString(markdown:)` may not cover all Markdown/HTML that HA's web component supports.
- Template subscriptions can leak if tied to SwiftUI view identity instead of the dashboard/view lifecycle.
- Rendered template output may be empty by design. Respect `show_empty` rather than forcing placeholders.

## Acceptance Criteria

- Static Markdown renders as formatted content.
- Empty and malformed content have intentional fallback behavior.
- Template content is detected and routed to HA server-side rendering after WebSocket multiplexer support exists.
- Template subscriptions unsubscribe correctly.
- The live dashboard's Markdown cards no longer display raw Markdown syntax unless the source intentionally uses plain text.

