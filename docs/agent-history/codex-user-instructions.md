# Codex history audit: durable user instructions

This is an extraction report, not an approved instruction file. It intentionally retains provenance, uncertainty, and conflicts so a later consolidation pass can propose an `AGENTS.md` without silently turning historical or task-specific wording into standing policy.

## 1. Method and exact exclusion logic

Corpus snapshot: 2026-07-16 (Asia/Shanghai). I streamed every `*.jsonl` below `/Users/jin/.codex/sessions/`: 353 rollout files, about 1 GB, containing 1,782 `event_msg.user_message` events dated 2025-12-08 through 2026-07-16.

Selection and sanitization:

1. Only `event_msg` records whose payload type was `user_message` were treated as user-authored. I did not treat `response_item` messages injected as environment, plugin, system, developer, or tool context as user instructions.
2. I classified a top-level session by the first/original `session_meta.cwd`. I excluded all 27 top-level sessions (101 user-message events) whose cwd starts with the case-sensitive prefix `/Users/jin/Documents/HA`. This removes the side experiment, including old NativeHA work there.
3. I did **not** exclude a session rooted at `/Users/jin/Documents/Computer` merely because it mentions `/Users/jin/Documents/HA/hass-frontend`; that checkout is repeatedly cited as the current NativeHA reference implementation.
4. I excluded 56 subagent rollout files (101 copied user-message events). Their histories duplicate parent messages, and their assigned prompts are developer/inter-agent material rather than new user-authored instructions.
5. The remaining 270 top-level files contained 1,580 raw eligible events. Exact whitespace-normalized message deduplication left 1,084 distinct user utterances. Resumed/forked rollouts sometimes replay old messages with a new timestamp; those replays were not counted as new recurrence evidence.
6. I reviewed the full reduced corpus, then retained durable preferences, recurring corrections, and NativeHA rules. I excluded one-off deliverables, current bug descriptions, entity-specific behavior, stale file/line/commit references, pasted logs, assistant text repeated by the user only for review, and implementation findings that require revalidation.
7. Secret values, personal credentials, phone numbers, authenticated URLs, and unrelated private content are omitted. Credential **locations** are retained only where they matter to future NativeHA work.

### Provenance key

The short labels below expand to source session filenames. Evidence counts in this report count distinct instruction-bearing utterances, not replayed transcript copies.

- **C01** — `rollout-2025-12-11T04-43-11-019b0ccb-0abd-73d1-89d9-c9d1ee5e2fd0.jsonl`
- **C02** — `rollout-2026-01-12T14-20-46-019bb0dd-3921-7231-a794-6c8fd2d23606.jsonl`
- **C03** — `rollout-2026-01-31T01-47-38-019c12ce-a490-7751-950b-d4a1deb8939e.jsonl`
- **C04** — `rollout-2026-03-22T00-03-15-019d13b6-1cdd-70b3-b890-7560cc528d34.jsonl`
- **C05** — `rollout-2026-04-12T18-20-44-019d83c8-6f35-7222-ae75-5e48fead9e4b.jsonl`
- **C06** — `rollout-2026-06-11T17-36-02-019eb609-e60b-7cd2-bf3a-7796827875fa.jsonl`
- **C07** — `rollout-2026-06-22T20-54-14-019eef65-4ec9-7540-bacb-e95e90930e35.jsonl`
- **C08** — `rollout-2026-06-30T17-56-44-019f17f5-ae8a-7e33-9afd-f1103da5945d.jsonl`
- **C09** — `rollout-2026-07-01T14-06-37-019f1c49-5c95-7482-986e-c8f1ad0a13b9.jsonl`
- **C10** — `rollout-2026-07-03T20-06-35-019f27df-a31d-7610-a337-4ffb7a33e71c.jsonl`
- **C11** — `rollout-2026-07-08T13-28-48-019f4033-3eac-72d0-b51c-1f633e6c07e2.jsonl`
- **C12** — `rollout-2026-07-13T22-01-59-019f5bc8-e241-73a0-bf2f-9c581f19515d.jsonl`
- **C13** — `rollout-2026-07-14T21-18-24-019f60c7-54d4-7190-9349-858cddcc339f.jsonl`
- **C14** — `rollout-2026-07-15T12-38-35-019f6411-ccaa-79b0-bab0-eb01a4e8d48a.jsonl`
- **C15** — `rollout-2026-07-15T13-03-33-019f6428-a4fa-7071-803d-68478292b0ef.jsonl`
- **C16** — `rollout-2026-07-15T14-39-41-019f6480-a9a7-7bc1-89af-1bee0df1bffa.jsonl`
- **C17** — `rollout-2026-07-15T16-08-25-019f64d1-e591-7201-aabe-dd1aa0741c74.jsonl`
- **C18** — `rollout-2026-07-15T16-34-00-019f64e9-5122-7a93-895e-1c5a8a1c0fdb.jsonl`
- **C19** — `rollout-2026-07-15T19-02-46-019f6571-8461-76b3-9daf-58b1041b084a.jsonl`
- **C20** — `rollout-2026-07-16T20-38-54-019f6aef-e4fe-7aa1-946f-485f681e77c4.jsonl`
- **C21** — `rollout-2026-07-16T20-57-09-019f6b00-99e2-7be0-bf09-6a61833dc8d3.jsonl`

## 2. Durable global instructions

### Investigation and scope

- **Read the complete relevant evidence when context affects correctness; do not rely only on keyword hits or isolated snippets.** For code, this means whole relevant source files; for diagnostics, the complete applicable log interval or dataset when feasible. **Metadata:** scope: global investigation/review; confidence: high; recurrence: at least 5 distinct prompts; date range: 2026-01-12–2026-07-15; sources: C02, C04, C15 (plus two unrelated eligible review sessions).

- **Separate diagnosis/review from implementation.** If the request says inspect, explain, audit, review, read-only, or documentation-only, do not change the application or unrelated files. Implement only when the request includes implementation. **Metadata:** scope: global; confidence: high; recurrence: at least 7 distinct prompts; date range: 2025-12-11–2026-07-16; sources: C01, C05, C08, C20 (plus three unrelated eligible review sessions).

- **Establish the cause before editing when the diagnosis is uncertain.** Reason through the relevant code and/or run focused tests; do not make speculative fixes merely because a symptom suggests one. **Metadata:** scope: technical debugging, especially performance/regressions; confidence: high; recurrence: 3; date range: 2026-03-24–2026-07-06; sources: C04, C10 (and one eligible manual-diff review session).

- **Prefer the simplest minimally invasive change that preserves required behavior.** Avoid unnecessary settings, caches, abstractions, security ceremony, or rewrites when a smaller reliable change suffices. **Metadata:** scope: implementation; confidence: medium-high because individual simplification requests were sometimes task-specific; recurrence: at least 8; date range: 2025-12-27–2026-07-15; sources: C10, C17 (plus six eligible non-NativeHA implementation sessions).

- **Use reversible experiments for uncertain changes.** Test in a temporary location or separate branch/commit, compare the result, and apply to the real workspace only after it works; preserve external/user edits. **Metadata:** scope: risky or uncertain repository operations; confidence: high; recurrence: 4; date range: 2026-07-06–2026-07-15; sources: C10, C13, C16, C17.

### Verification and communication

- **Use appropriate dynamic tests when authorized, rather than stopping at static plausibility.** Small standalone tests, dry runs, benchmarks, and smoke tests are welcome when they are safe and in scope. **Metadata:** scope: implementation/verification; confidence: high; recurrence: at least 5; date range: 2026-01-31–2026-07-16; sources: C03, C06, C09, C10, C20.

- **Explain conclusions and handoffs in detailed plain language, including reasoning, evidence, risks, and next steps.** Plans intended for another session should be self-contained enough that the next agent does not have to rediscover the strategy. **Metadata:** scope: explanations, audits, plans, and handoffs; confidence: high; recurrence: at least 10; date range: 2025-12-11–2026-07-16; sources: C01, C04, C15, C18, C19, C20.

- **Pause for an action only the user can perform or for a material approval boundary, and say exactly what is needed.** Examples include CAPTCHA, sharing/access changes, destructive configuration, or a requested manual interaction. This is not a blanket instruction to stop for ordinary safe testing. **Metadata:** scope: blocked/user-only operations; confidence: medium-high; recurrence: at least 6; date range: 2026-01-31–2026-07-16; sources: C03, C06, C10 (plus three eligible browser/admin sessions).

## 3. Durable instructions specific to current NativeHA

### Project identity and behavioral source of truth

- **The active implementation repository is `/Users/jin/Documents/Computer/NativeHA`.** **Metadata:** scope: NativeHA; confidence: very high; recurrence: 4; date range: 2026-07-15–2026-07-16; sources: C16, C18, C20, C21.

- **The behavioral reference is `/Users/jin/Documents/HA/hass-frontend`, including both `src` and the specific implementation files reached in `node_modules`.** Inspect the local checkout instead of inventing behavior. **Metadata:** scope: NativeHA parity work; confidence: very high; recurrence: at least 7; date range: 2026-07-14–2026-07-16; sources: C13, C15, C18, C19, C20, C21.

- **Do not use the old `/Users/jin/Documents/HA/NativeHA` copy as the implementation source.** It was briefly suggested as a parallel source and then explicitly withdrawn; it also falls under the excluded side-experiment prefix. **Metadata:** scope: NativeHA source selection; confidence: very high; recurrence: 2 explicit corrections; date range: 2026-07-14–2026-07-15; sources: C13, C17.

- **Implement a genuinely Swift-native macOS frontend; do not use JavaScript or a WebView as the application architecture.** Native implementation is intended to improve performance. **Metadata:** scope: NativeHA architecture; confidence: high; recurrence: 2 distinct prompts; date range: 2026-07-03–2026-07-16; sources: C10, C21.

- **Copy observable hass-frontend behavior. Deviate only for a proper native-Swift implementation or a measured performance benefit, without fundamentally changing the reference logic or semantics.** Observable behavior includes state handling, layout, interactions, visuals, and animation—not merely similar output for one fixture. **Metadata:** scope: all NativeHA implementation; confidence: very high; recurrence: 5; date range: 2026-07-03–2026-07-16; sources: C10, C13, C18, C19, C21.

- **The supported deployment baseline is macOS 12 with Swift 5.6/Xcode 13.4.1.** Do not plan APIs that are unavailable on that toolchain. **Metadata:** scope: NativeHA code and tests; confidence: very high; recurrence: 2; date range: 2026-07-15–2026-07-16; sources: C19, C20.

- **Prioritize behavior and entity/card combinations actually used on the live Home Assistant server, while keeping the design extensible.** Connecting to the server to learn the current surface is allowed; unused HA breadth is lower priority. **Metadata:** scope: product prioritization; confidence: high; recurrence: 2; date range: 2026-07-15–2026-07-16; sources: C18, C21.

### Source tracing and persistent context

- **Read every relevant `.swift` and `.ts` file in full. Follow runtime references recursively, including the particular `node_modules` sources used by frontend files; do not impose an arbitrary recursion-depth cutoff.** This does not mean loading all of the 1 GB dependency tree—stop when the behaviorally relevant implementation or a stable platform/public-API boundary is understood. **Metadata:** scope: reference research and implementation; confidence: very high for full relevant-file reads, medium for the practical stopping interpretation; recurrence: 2 explicit prompts plus the current context problem; date range: 2026-07-15–2026-07-16; sources: C15, C21.

- **Break the rescue work into modules/stages small enough for one implementation session, and carry forward a self-contained evidence/plan document.** Each later session should not have to repeat broad discovery. **Metadata:** scope: NativeHA planning/handoff; confidence: very high; recurrence: 3; date range: 2026-07-15–2026-07-16; sources: C18, C20, C21.

- **Treat the module audit as a starting point, not proof that later implementation introduced no new GUI or behavioral regressions.** Verification must cover the changed surface even when the particular regression was absent from the original audit. **Metadata:** scope: implementation completion; confidence: high; recurrence: 2; date range: 2026-07-15–2026-07-16; sources: C19, C21.

## 4. Testing and verification

- **Every module plan should state its unit, integration, GUI (if visible), animation/interaction, performance/lifecycle, and manual-QA requirements, plus fixtures, artifacts, and acceptance criteria.** Do not paste generic GUI boilerplate into nonvisual modules; explicitly say when snapshots are unnecessary. **Metadata:** scope: all NativeHA modules; confidence: very high; recurrence: 2; date range: 2026-07-16; sources: C19, C20.

- **The default automated suite must be deterministic and offline:** fixed timestamps, sizes, appearance, scale, locale/timezone where possible, fixture data, fake transports, no real credentials, no live server state. **Metadata:** scope: default tests; confidence: very high; recurrence: 1 comprehensive instruction; date: 2026-07-16; source: C20.

- **For SwiftUI rendering tests on this baseline, use an `NSHostingView` in a small offscreen AppKit window and AppKit bitmap caching APIs; do not use SwiftUI `ImageRenderer`.** AppKit/SwiftUI/view-model GUI work belongs on the main actor. **Metadata:** scope: GUI test implementation; confidence: very high; recurrence: 1 comprehensive instruction; date: 2026-07-16; source: C20.

- **GUI tests should write inspectable PNG artifacts under `.build/render-artifacts/` and first check signature, dimensions, nonblank output, expected regions/colors, and settled async state.** **Metadata:** scope: visual-test artifacts; confidence: very high; recurrence: 1 comprehensive instruction; date: 2026-07-16; source: C20.

- **Do not approve the current NativeHA rendering as its own golden reference.** Compare against the corresponding hass-frontend fixture/live state first; only reviewed images enter `ReferenceImages`, with tolerant pixel comparison and an OS-version note. Intentional visual updates require review of actual, expected, and preferably diff artifacts. **Metadata:** scope: visual baselines; confidence: very high; recurrence: 2 (the detailed rule and the broader reference-parity correction); date range: 2026-07-15–2026-07-16; sources: C19, C20.

- **A screenshot does not prove data semantics, accessibility, lifecycle, or performance.** Pair important reference behavior with semantic tests and use screenshots for the visible contract. A temporary, narrowly reasoned `XCTExpectFailure` may document a known gap but must be removed with the fix. **Metadata:** scope: conformance tests; confidence: very high; recurrence: 1 comprehensive instruction; date: 2026-07-16; source: C20.

- **Test animation deterministically where practical:** expose interpolation/state, render meaningful start/mid/end keyframes, test clamping/gesture mapping/state transitions, and use bounded settlement expectations instead of long sleeps. Include reduced motion when production supports it. **Metadata:** scope: animation tests; confidence: very high; recurrence: 2 (general requirement plus earlier exact interaction debugging); date range: 2026-07-05–2026-07-16; sources: C10, C20.

- **Completion requires the tests and verification specified by the module plan, including regression coverage for the bug or behavior changed.** Re-read testing, risk, and acceptance sections and validate the diff before handoff. **Metadata:** scope: module completion; confidence: high; recurrence: 3; date range: 2026-07-15–2026-07-16; sources: C19, C20, C21.

## 5. Live server and smoke testing

- **Live Home Assistant testing is authorized and should be used when it materially verifies integration, networking, reference state, or a behavior that fixtures cannot establish.** It is especially relevant for WebSocket/reconnect/state-update and GUI smoke testing. **Metadata:** scope: separate live/integration verification; confidence: very high; recurrence: 3; date range: 2026-07-15–2026-07-16; sources: C18, C20, C21.

- **Keep live smoke tests separate from the default test suite.** Default tests remain deterministic/offline; live tests use the documented server/token locations, should avoid destructive service calls unless specifically authorized, and must not leak credentials into output or artifacts. **Metadata:** scope: live-test boundary; confidence: very high; recurrence: 2 complementary instructions; date: 2026-07-16; sources: C20, C21.

- **If a GUI behavior cannot be automated reliably on macOS 12/Xcode 13, request a bounded manual interaction/capture rather than claiming it passed.** Later XCUITest/hitch work may require newer Xcode. **Metadata:** scope: live/manual GUI verification; confidence: high; recurrence: 3; date range: 2026-07-05–2026-07-16; sources: C10, C19, C20.

## 6. Visual, UI, and animation expectations

- **Compare NativeHA and hass-frontend under the same data state, logical size/window, theme/appearance, display scale, locale/timezone, and interaction state.** Inspect layout, text, clipping, color, hover/press/focus, loading/error/empty states, and animation—not only the final resting screenshot. **Metadata:** scope: visible parity; confidence: very high; recurrence: at least 4; date range: 2026-07-03–2026-07-16; sources: C10, C19, C20, C21.

- **When CSS/browser behavior is hard to describe, inspect the actual frontend source and live reference and capture comparable screenshots/keyframes.** Do not make the user reverse-engineer CSS into Swift instructions. **Metadata:** scope: GUI parity workflow; confidence: very high; recurrence: 3; date range: 2026-07-05–2026-07-16; sources: C10, C20, C21.

- **Test meaningful interaction states explicitly.** Examples of reusable categories are hover, press/drag, release, optimistic update, backend reconciliation, interruption, outside-click dismissal, narrow/normal sizes, and reduced motion where supported. **Metadata:** scope: interactive controls; confidence: high; recurrence: at least 4; date range: 2026-07-03–2026-07-16; sources: C10, C19, C20.

- **Small antialiasing/font differences may use tolerant comparisons, but behavioral, layout, trajectory, timing, or state-transition differences are not excused as “native.”** **Metadata:** scope: visual acceptance; confidence: high; recurrence: 2; date range: 2026-07-05–2026-07-16; sources: C10, C20.

## 7. Performance and lifecycle

- **Measure alternatives on realistic and stress fixtures before adopting a performance-sensitive algorithm; compare correctness as well as speed.** Use real HA-shaped data when safe, and show optimized output is semantically/pixel equivalent across representative subsets. **Metadata:** scope: graph and other hot paths; confidence: very high; recurrence: at least 6; date range: 2026-07-04–2026-07-16; sources: C10, C15, C19, C20.

- **Prioritize user interaction over background parsing/rendering/update work.** Superseded work should cancel or defer, one expensive card must not block others, and interaction should remain smooth while higher-quality work settles afterward. **Metadata:** scope: GUI scheduling/performance; confidence: very high; recurrence: 4; date range: 2026-07-04–2026-07-16; sources: C10, C19, C20.

- **Distinguish cold preparation/initial load, warm cached interaction, repeated incremental updates, and cleanup/cancellation.** Build large fixtures outside measured blocks, warm caches before warm-path measurement, consume results, and state fixture sizes. **Metadata:** scope: XCTest performance plans; confidence: very high; recurrence: 1 comprehensive instruction backed by earlier benchmark requests; date range: 2026-07-04–2026-07-16; sources: C10, C20.

- **Use metrics available on the deployment toolchain (`XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`); do not require unavailable `XCTHitchMetric`.** Prefer stored performance baselines over brittle machine-specific millisecond thresholds. **Metadata:** scope: automated performance tests; confidence: very high; recurrence: 1 comprehensive instruction; date: 2026-07-16; source: C20.

- **Test lifecycle and memory behavior:** repeated subscribe/unsubscribe, reconnect, view switching, detail open/close, task cancellation, and disappearance must not leave active work, callbacks, or unbounded growth. **Metadata:** scope: networking/UI modules; confidence: very high; recurrence: 1 comprehensive instruction plus the general regression concern; date: 2026-07-16; sources: C20, C21.

## 8. Security and credential guidance

- **Never copy token/key contents into plans, tests, logs, PNG artifacts, commits, or final reports.** Refer only to a credential location and load it at runtime for explicitly live tests. **Metadata:** scope: all NativeHA work; confidence: very high; recurrence: 2; date range: 2026-07-16; sources: C20, C21.

- **Historical location evidence is inconsistent and must be verified before promotion to `AGENTS.md`.** Early NativeHA work says the token was exported “in this folder”; a later pasted audit names `/Users/jin/Documents/Computer/ha_apikey.txt`; separate current-HA tasks repeatedly attach `/Users/jin/Documents/HA/ha_apikey.txt` and `/Users/jin/Documents/HA/ha_server.txt`. Store only the verified canonical location, not a token or URL value. **Metadata:** scope: credential discovery; confidence: high that the ambiguity exists, low that any one path is canonical; recurrence: 5; date range: 2026-07-03–2026-07-16; sources: C10, C11, C12, C14, C18, C21.

- **The user historically described the HA token as low-risk because the server was local and asked not to overcomplicate hiding it; this does not authorize disclosure.** Interpret it as permission for pragmatic local runtime loading, while retaining redaction and test isolation. **Metadata:** scope: local development ergonomics; confidence: high for the historical statement, medium for its current applicability; recurrence: 1; date: 2026-07-04; source: C10.

## 9. Autonomy and delegation

- **For a broad new architecture, questions/preferences may be gathered before substantial implementation; for a defined module with an accepted plan, proceed through implementation and verification without repeatedly asking the same setup questions.** **Metadata:** scope: NativeHA autonomy; confidence: medium-high; recurrence: 2 complementary prompts; date range: 2026-07-03–2026-07-16; sources: C10, C21.

- **Delegate bounded read-heavy audits or easier planning modules when context pressure threatens the main implementation context.** The delegated output must be concrete and reviewable; the main agent remains responsible for synthesis. High/xhigh reasoning was explicitly requested for such audits. **Metadata:** scope: planning/reference research; confidence: very high; recurrence: 3; date range: 2026-07-15–2026-07-16; sources: C15, C18, C20.

- **Do not have multiple agents make overlapping Swift edits.** The history supports a sequence of reference audit/plan, implementation, then independent verification; overlapping uncommitted sessions previously required recovery. **Metadata:** scope: multi-agent repository work; confidence: medium because the no-overlap wording is an inference from explicit recovery incidents; recurrence evidence: 2 incidents; date: 2026-07-15; sources: C13, C16.

- **Mined history reports must not directly rewrite `AGENTS.md`.** A separate consolidation agent may propose the valuable rules only after both Codex and Gemini reports finish, and the user must approve the proposed `AGENTS.md`. **Metadata:** scope: current history-mining workflow; confidence: very high; recurrence: 1 explicit instruction; date: 2026-07-16; source: C21.

## 10. Documentation, git, and handoff

- **Module plans must be descriptive and thorough:** scope, verified reference behavior, relevant source symbols/files, tasks, dependencies, risks, fixtures, test strategy, manual QA, and acceptance criteria. Clearly label hypotheses that still need implementation-time verification. **Metadata:** scope: rescue-plan documents; confidence: very high; recurrence: 3; date range: 2026-07-15–2026-07-16; sources: C18, C20, C21.

- **Use git early so work is reversible, and exclude build products.** Keep commits scoped to the current agent’s edits and describe them in detail. **Metadata:** scope: NativeHA implementation; confidence: very high; recurrence: 4; date range: 2026-07-06–2026-07-16; sources: C10, C13, C18, C19.

- **Preserve externally made/uncommitted work.** Before rollback, rebase, squash, or replay operations, inspect diffs/session evidence and use a temporary copy/branch when uncertain; do not reconstruct complex changes from memory if an exact diff can be recovered. **Metadata:** scope: git recovery/change isolation; confidence: very high; recurrence: 3; date: 2026-07-15; sources: C13, C16, C17.

- **At stage completion, update the persistent context/evidence document with what was actually implemented and tested, deviations from the reference, artifacts, remaining gaps, and the revisions used.** **Metadata:** scope: cross-session handoff; confidence: high, though part is inferred from the explicit request to preserve insight across sequential module sessions; recurrence: 3; date range: 2026-07-15–2026-07-16; sources: C18, C20, C21.

## 11. Conflicts, ambiguities, and staleness warnings

1. **Credential location:** three historical descriptions conflict; verify the canonical server/token files before adding a path to `AGENTS.md`. Never promote a secret value.
2. **Token sensitivity:** one prompt says the local token is “not a secret,” while later test guidance forbids credentials in default tests/logs/artifacts and the current mining task forbids recording secrets. Preserve pragmatic local loading, but redaction/no-disclosure is the safer durable rule.
3. **Long waits:** one NativeHA benchmark correction says to stop and ask the user to run an anticipated long test; an unrelated API task says to wait patiently for up to roughly 30 minutes. These are task-specific, not a stable global policy. A consolidation should distinguish ordinary bounded verification, user-run interactive tests, and genuinely long monitoring.
4. **Ask first versus autonomy:** the initial greenfield app prompt invited preference questions before “real work”; later module work expects agents to proceed from detailed plans and not require repeated setup instructions. Scope the former to major product choices and the latter to accepted module implementation.
5. **Visual tolerance:** one climate-control prompt said not to bother with differences “only by a bit,” but later reference/testing guidance requires deliberate comparison and reviewed tolerance. Do not generalize the earlier comment into permission to ignore meaningful layout, animation, or interaction mismatches.
6. **Early hardcoding is stale:** July 3 POC prompts explicitly allowed hardcoded URLs/configuration and current-screen-only support. Later rescue planning treats personal hardcoding as debt. Do not promote POC hardcoding as standing policy.
7. **Specific file names, symbols, line numbers, module findings, entity IDs, graph thresholds, and commits in historical prompts may have drifted.** Re-resolve them at the current repository/reference revisions; this report intentionally does not carry them forward as instructions.
8. **“Read all dependencies recursively with no limit” needs a practical boundary.** The durable intent is complete understanding of behaviorally relevant code, not indiscriminate ingestion of a 1 GB dependency tree. Consolidation should define stop conditions at platform primitives, stable public APIs, or code irrelevant to the observed contract.
9. **The report contains inferred rules only where marked.** In particular, non-overlapping Swift edits and end-of-stage evidence updates are strongly supported by the user’s problems and requested workflow but were not stated in exactly those words.

## 12. Excluded material and extraction limitations

- Excluded by workspace rule: 27 `/Users/jin/Documents/HA...` top-level sessions / 101 user-message events, including old NativeHA side-experiment work. No instruction unique to that excluded workspace was promoted.
- Excluded as transcript duplication: 56 subagent files / 101 copied user-message events, plus exact replays in resumed top-level sessions.
- Excluded by content: hundreds of one-off coding tasks, current bug reports, temporary entity/card/layout values, stale line/commit references, pasted assistant plans offered only for review, terminal/browser logs, school/research/travel/medical tasks, and temporary “do/don’t edit” constraints tied to those individual tasks.
- Secrets were present in the raw corpus. They were neither copied nor summarized. The temporary reduced corpus used for local analysis should be deleted after this report is delivered.
- Counts are corpus-snapshot counts. Codex was actively writing new parent/subagent rollout files during the audit, so later filesystem counts may be slightly higher.
- Frequency is not authority: a single recent explicit NativeHA instruction can be more valuable than a repeated older preference. The consolidation agent should weigh scope, recency, conflicts, and user approval—not copy this report wholesale.
