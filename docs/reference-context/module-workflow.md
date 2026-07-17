# Reference-parity module workflow

The main task should remain a thin orchestrator. Read-heavy exploration and
independent verification belong in bounded subagent tasks; durable findings
belong here before implementation starts.

## Phase 1: research

Use this phase when a packet is absent, yellow/red, or explicitly incomplete.
The researcher is read-only with respect to Swift and the existing rescue plan.
It may create/update only the module manifest, generated graph, and evidence
packet.

1. Read the module rescue plan and existing packet.
2. Run `check-context.mjs` if a graph exists.
3. Identify behavior entrypoints and explicit runtime seeds. Static TypeScript
   imports are insufficient when a type/interface hides the implementation.
4. Run `trace-ts-deps.mjs` and inspect only behavior-relevant nodes.
5. Write observable contracts, source anchors, native targets, tests, visual or
   live-smoke applicability, risks, and an exact handoff.
6. Set packet status to `research-ready` only when no material behavior question
   blocks implementation.

Suggested prompt:

> Research Module NN using `docs/reference-context/module-workflow.md`. Work
> read-only on Swift. Refresh the module manifest/graph and write the evidence
> packet with revision/hash/symbol anchors. Do not crawl all of hass-frontend or
> node_modules; follow runtime edges first and cross package boundaries only
> when they determine observable behavior. End with a concise handoff.

## Phase 2: implementation

The implementer owns Swift changes and tests. It should not repeat the broad
reference audit when the packet is green.

1. Run the staleness checker.
2. Read the rescue plan, packet contracts, and only the cited source anchors.
3. Implement contracts in dependency order using native Swift ownership and
   concurrency patterns.
4. Record material native decisions/deviations in the packet. A deviation must
   preserve observable semantics and have a test.
5. Run deterministic targeted tests, then the full applicable suite.
6. Set status to `verification-ready` and write the exact verifier handoff.

Current Module 02 implementation prompt:

> Implement Module 02 from
> `docs/reference-context/modules/module-02-websocket-multiplexer.md` and its
> rescue plan. First run the graph staleness check. If green, do not re-audit the
> whole frontend. Implement contracts C02-01 through C02-07, add the scripted
> fake-transport tests, run targeted and full tests, and update the packet to
> `verification-ready`. Follow the root credential policy, keep diagnostics
> concise instead of dumping full request payloads, and do not mutate the
> reference repo.

## Phase 3: independent verification

The verifier should not redesign the implementation unless it finds a contract
violation. It reads the diff, packet, and tests; runs applicable checks; and
reports failures with contract IDs.

1. Run staleness and resolver self-tests.
2. Run targeted and full deterministic tests.
3. Run applicable read-only live smoke checks. Any Home Assistant service call
   that changes state needs an explicitly safe target; read-only network tests
   do not.
4. For visual modules, capture reference and NativeHA under matching state,
   size, scale, appearance, locale, and animation phase.
5. Update validation results and set `complete`, or return to
   `verification-ready` with precise failures.

Suggested prompt:

> Independently verify Module NN against its evidence-packet contract IDs. Do
> not broaden scope or rewrite working code. Run staleness, targeted/full tests,
> applicable read-only live smoke, and visual/animation comparison. Update the
> packet with evidence and either mark complete or list exact failed contracts.

## Keeping one task lean

- Keep the main task as dispatcher and decision-maker; subagents return compact
  summaries after writing artifacts.
- Use a fresh subagent for each phase rather than carrying raw exploration logs
  into implementation.
- Before a long phase or manual compaction, require a packet `Handoff` update.
- In Codex surfaces that expose it, `/status` shows remaining context and
  `/compact` summarizes the current task. Compact only after the packet and
  worktree state are durable; compaction is not a substitute for the packet.
- Use `/side` for a small unrelated question when available, so it does not
  interrupt the implementation transcript.
- If the main task itself has accumulated large raw logs, a fresh task remains
  the cleanest implementation context. Start it with the packet path, not a
  pasted history summary.
