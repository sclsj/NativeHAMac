# NativeHA repository instructions

> Historical proposal, not active guidance. Use the repository-root `AGENTS.md`
> and its routed instruction files. Preserve this document as provenance.

## Scope and precedence

These instructions apply to `/Users/jin/Documents/Computer/NativeHA`. The current prompt overrides historical guidance. Review, diagnosis, audit, explanation, and documentation-only tasks do not authorize application-code changes.

## Repository map and sources of truth

- This repository is the active Swift implementation. Read its current code and tests before relying on a plan or historical finding.
- `/Users/jin/Documents/HA/hass-frontend` is the read-only behavioral reference. Never edit it for NativeHA work. Its repository instructions and `AGENTS.md` do not govern NativeHA.
- Inspect both `hass-frontend/src` and behaviorally relevant implementation files reached in its `node_modules`; do not invent behavior that the local reference source or running reference UI can establish.
- Use `README.md` for build, run, architecture, toolchain, and runtime guidance; `docs/rescue-plan/` for staged work; and `docs/visual-testing.md` for GUI, animation, baseline, and performance testing. Revalidate aged plans against code.
- `Sources/NativeHAMac/AppConfig.swift` and the current `README.md` are the sources of truth for local server configuration and credential-file location. Do not duplicate their values in plans or instructions.

## Behavioral contract

NativeHA is a native macOS client. Use Swift, SwiftUI, AppKit, and native rendering; do not introduce JavaScript or a WebView architecture unless explicitly requested.

Treat observable `hass-frontend` behavior as the default contract: preserve data semantics, state transitions, service behavior, edge states, layout, accessibility, interactions, and animation—not only one fixture. Use sound native architecture rather than mechanically translating browser structure.

Deviate only when requested, for a material native-macOS benefit, or for a measured performance benefit, while preserving Home Assistant semantics. Discuss visible deviations first, then document and test them; “native” does not excuse layout, timing, trajectory, or state-transition mismatches. Use only APIs supported by the documented deployment target and toolchain.

## Research and persistent context

Read complete relevant Swift and TypeScript files. Trace runtime imports, callers, events, registrations, CSS effects, and package implementation far enough to explain behavior; separate type-only references. Stop at a stable public API or platform primitive, or an edge irrelevant to the contract.

For broad work, maintain a self-contained Markdown evidence packet in the module or stage document. Record:

- behavior and acceptance criteria;
- current paths and stable symbols (line numbers are hints), source roles, and any package version or revision needed to detect drift;
- Swift targets, dependencies, decisions, and deliberate deviations; and
- fixtures, tests, artifacts, risks, open questions, gaps, and final verification.

Generated graphs, indexes, or databases are disposable aids; reviewed conclusions belong in version-controlled Markdown. Re-resolve stale references. Plans do not prove later regressions absent. Establish uncertain causes before editing.

## Implementation and verification

Keep modules to one implementation pass, follow dependencies, and coordinate shared surfaces. Do not broaden feature scope because related reference code exists or spread prototype hardcoding into more code.

Verify runtime behavior, not only compilation:

1. Add focused semantic and regression tests.
2. Run focused tests and full `swift test` when feasible, using current docs.
3. For visible work, inspect GUI artifacts and affected interaction states.
4. If fixtures cannot prove integration, run a separate bounded live smoke test.

Automated tests default to offline, deterministic fixtures and fake transports with fixed time, geometry, appearance, scale, and locale/timezone where supported. They must not require live state, network, or credentials.

Module plans must identify applicable unit, integration, GUI, animation, performance/lifecycle, and manual QA with artifacts and acceptance criteria; mark non-applicable categories. Never claim completion while behavior remains broken or required checks have not run; state any unverified item and why.

## GUI and animation

Compare under matching data, size, theme, scale, locale/timezone, and interaction state. Inspect geometry, typography, color, clipping, accessibility, edge states, and hover/press/focus/drag behavior. Use screenshots and the live reference for browser behavior; do not require the user to translate CSS into Swift guidance.

Never approve NativeHA output as its own golden. Compare with the reference first; use tolerance only for justified rendering differences such as antialiasing.

Test animation intermediates, gesture updates, interruption, reconciliation, and completion with deterministic state tests and start/mid/end keyframes. Test reduced motion when supported. Screenshots do not replace semantic or lifecycle checks. If automation is unavailable, request a bounded manual capture instead of claiming a pass.

## Performance and lifecycle

Measure performance-sensitive alternatives on representative and stress fixtures; compare correctness and visual output as well as speed. Separate cold preparation, warmed interaction, incremental updates, and cancellation/cleanup. Use metrics available on the current toolchain and avoid machine-specific thresholds unless the current task sets one. Do not trade away data or rendering accuracy for speed.

Keep expensive work from blocking interaction, and cancel or supersede obsolete work. Where relevant, test repeated subscribe/unsubscribe, reconnect, view switching, presentation/dismissal, and task cancellation. No path should retain active callbacks, orphaned work, or unbounded memory growth.

## Live server and credentials

Read-only live Home Assistant testing is authorized when it materially verifies networking, WebSocket behavior, integration, real configuration, representative data, or a GUI flow that fixtures cannot establish. Keep it separate from the default suite and record what was exercised.

Load current server configuration and credentials only through the locations documented by `Sources/NativeHAMac/AppConfig.swift` and `README.md`. Never print, paste, log, screenshot, persist, commit, or include token contents in tests, artifacts, plans, or reports. Do not expose authenticated or private endpoints in new documentation.

Live checks are read-only by default. A mutating service call requires explicit authorization in the current task or a clearly identified safe test target. General live-testing authorization does not permit mutation of ordinary entities.

## Delegation and handoff

For broad reference tracing, bounded read-only research subagents are encouraged when they protect implementation context. Give each a concrete behavior or dependency boundary and require a reviewable evidence packet. The main agent owns synthesis, implementation decisions, and final verification.

Do not have multiple agents make overlapping Swift edits. Independent verification may follow a stable implementation, but it should report evidence rather than silently rewrite the same surface. At handoff, update module context with the actual diff scope, tests and live/visual checks, artifacts, deviations, and gaps.

## Git and worktree safety

Inspect status before editing. Existing uncommitted changes belong to the user or another task unless proven otherwise; preserve them and avoid overwriting mixed work. Use reversible experiments or a temporary copy when provenance is uncertain. Do not perform destructive rollback, cleanup, rebase, or history rewriting without explicit current-task authorization.

Keep changes scoped to the request. Do not stage, commit, branch, push, or open a pull request unless the current task asks. Never commit build products, credentials, or local GUI artifacts.
