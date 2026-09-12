# Module 08 — Native Markdown and HA templates

The [revision 1 evidence packet](../reference-context/modules/module-08-markdown-card.md) is the current behavioral authority. Stage 1 is implemented and independently verified. The packet records exact contracts, full debug/release results, scoped visual evidence and remaining stage boundaries.

## Approved first stage

Implement native Markdown and Home Assistant server-rendered templates. The [user-approved staging](../user-deviations.md#markdown-implementation-stages) defers advanced HTML, media and HA-specific custom elements with an explicit, selectable source fallback. No WebView, JavaScript runtime or local Jinja interpreter belongs in the app.

The 2026-09-12 read-only check found two identical Markdown cards, only in `home_3h` and `home_12h`. Home/default_view contains none. Preserve the approved navigation policy; validate fixtures or explicitly route to a maintenance view without moving its cards into Home.

## Corrections to the original plan

- Module 04 already preserves raw config, unknown keys and Markdown options. Correct only the remaining `entity_id` string/array and empty-source validation gaps. A separate `MarkdownCardConfig` decoder is unnecessary.
- Every actually mounted supported Markdown card uses `render_template`, including content without Jinja markers. Initial uncached content is blank; source rendering is the subscription-rejection fallback. A local static-only path does not establish dashboard parity.
- The template variables contain the full raw card config and the existing current-user response's name. Retain that name during bootstrap; do not add another fetch or substitute an ID.
- `show_empty:false` hides a successful zero-length result, not pending content or whitespace. The outer `hui-card` removes that hidden child and cancels its subscription. Returning to the cached view does not revive the hidden child.
- Cached view instances retain their previous results beyond one second. That lifetime differs from the complete-config one-second handoff cache used by newly created components. Changed installed dashboard config recreates all views/cards; unchanged entity and graph-range updates do not.
- A stream error retains the previous body and alert precedence; later success does not clear the alert. Subscription rejection and transport reconnect are separate paths, specified in C08-03–07.
- Foundation Markdown parsing needs explicit native block layout and compatibility corrections. One attributed `Text` is insufficient for lists, code, tables and alerts. Preserve literal code/escaped syntax except the reference GitHub-alert DOM conversion, which also recognizes markers in those forms.
- Interactive card actions consume link clicks. Support the packet's bounded none/navigate/explicit-entity more-info/external-URL matrix; unsupported or confirmation-bearing actions show a notice and execute nothing. Full generic action parity remains outside this stage.

## Implementation ownership

| Concern | Native path |
|---|---|
| Existing config/current-user decode | `LovelaceModels.swift`, `Models.swift` |
| Typed template wire/event API | `HomeAssistantTemplate.swift` through Module 02 |
| Demand, retained view state, cancellation and result handoff | `DashboardMarkdownCoordinator.swift`, `DashboardViewModel.swift` |
| Native document preparation/cache | `MarkdownRendering.swift` |
| Card/block rendering and bounded actions | `MarkdownCardView.swift`; dispatch in `CardViews.swift` |

Keep one Swift-writing owner. Reuse Module 02's transport and Modules 05/12's weak lifetime, owner reconciliation and direct-route boundaries. Publish ordinary result updates through the individual card state. Parse off-main and reject retired generations; keep diagnostics debug-only. Typed presentation and rebuildable-document cache policy lives in `AppConfig.swift`.

## Verification gates

Follow the packet's C08-01–12 contract matrix and [visual testing workflow](../visual-testing.md), with these evidence layers:

1. **Reference oracle:** exact worker output and source hashes for tracked Markdown fixtures. Keep DOM postprocessing, lifecycle and actions separate from the worker oracle.
2. **Deterministic Swift tests:** wire payloads, config validation, supported Markdown semantics, explicit deferred fallback, link/action dispatch, per-card isolation, error precedence, cancellation, reconnect, cached-empty mounting and view/config cache lifetimes. No service calls or real URL opening.
3. **Native rendering:** matching 496/320-point dark fixtures for core content, title/text-only, pending, retained error, long wrapping and deferred fallback. Use natural content height rather than cropping a long document to an arbitrary composite height. Hidden content requires semantic parent-layout removal assertions. Inspect native images beside comparable reference captures; label offline component-style approximations honestly and do not automatically approve them as goldens.
4. **Performance/lifecycle:** cold/warm 1 MB preparation, isolated repeated updates among 100 cards, owner churn and cancellation. Construct inputs outside measurement, consume results and report CPU/memory where supported. Keep reusable methodology/results under `Benchmarks/Markdown/`. Graph history-window benchmarks do not apply to this Markdown-only cache.
5. **Read-only HA smoke:** production-shaped template requests and successful unsubscribe cleanup against existing Markdown source. This confirms server acceptance; fake transport tests establish actual Swift wire behavior.
6. **Integration review:** full debug/release suites, independent implementation review, resolver self-test, exact diff and refreshed affected source anchors.

Full-runtime browser visual comparison and event-to-frame XCUITest coverage must be distinguished from fixture/source evidence. Xcode 13.4.1 has no `XCTHitchMetric`; its absence is not a reason to fabricate performance coverage. Do not claim module completion while an applicable contract still fails.

## Deferred work

Advanced HTML/media/custom elements, editing, full generic action parity and unbounded browser navigation remain outside the first stage. The graph redesign, climate/fan modules, dashboard-card forecasts and previously deferred synthetic climate/axis failures retain their existing priority and scope.
