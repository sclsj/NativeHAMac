# Markdown interaction evidence outside the worker oracle

These are source-derived contracts at revision `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`, not browser interaction test results. Source hashes are recorded in `expected-worker.json`.

- `ha-markdown-element.ts::_render` sets different-host anchors to target `_blank` and rel `noreferrer noopener`. Host includes port; this comparison is not an origin comparison.
- `is-navigation-click.ts::isNavigationClick` ignores prevented events, nonprimary buttons, Meta/Ctrl/Shift, target/download anchors, exact rel `external`, mailto and destinations outside the current origin. A qualifying same-origin destination is passed to global navigation. Native routing must separately define supported Module 12 destinations.
- `hui-markdown-card.ts::render` binds the shared action handler to the whole card only when any explicit action is non-`none`. Its accessible role is button and tabindex is zero. Noninteractive cards have neither binding.
- `action-handler-directive.ts::bind` prevents default on completion and has no anchor exception. A link click bubbling through an interactive card can be consumed by card action before global navigation observes it. Do not automatically give the link precedence. Hold qualifies after 500ms and dispatches on release; double-tap resolution delays a single tap by 250ms; Enter/Space invoke completion.
- Rejected URL values in worker output become bare `href`, which the browser can resolve to the current document. Do not describe this as proven inert navigation. The fixture deliberately preserves that distinction. The native URL safety/activation policy needs semantic tests independent of HTML output.

Future browser/native interaction fixtures should exercise a link on an inert card, the same link with tap/hold/double actions, keyboard activation, modifiers, same-origin routing, fragments, and rejected destinations. No service calls or navigation are executed by the Node oracle.

GitHub-alert postprocessing checks the first child text with a case-insensitive, unanchored marker regex. Escaped and inline-code markers still match after Markdown parsing. The converter filters out the entire first child's text chunk (`RegExpMatchArray.input`), including same-line plain text; separately formatted following children survive. Worker HTML alone does not demonstrate this final DOM behavior.
