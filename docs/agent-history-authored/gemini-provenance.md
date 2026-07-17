# Gemini instruction provenance audit

> This is an authorship audit of the candidates in `docs/agent-history/gemini-user-instructions.md`. A user-role envelope is not assumed to be user-authored: copied AI text, parent-agent prompts injected as a subagent's `user` message, and AI-generated plans pasted by the user are traced separately. This report does not promote anything into `AGENTS.md`.

## 1. Method

### Corpora and role decoding

- Re-read all 61 SQLite databases in `/Users/jin/.gemini/antigravity/conversations` and used the earlier report only as a 28-candidate inventory.
- In Gemini protobuf payloads, `step_type = 14`, field `19/2` is the direct user-input text. Model-authored material was decoded separately:
  - type 15, field 20 contains model planning/response text;
  - type 23, field `30/4` contains a model response, while nearby fields may echo the triggering user prompt and were not counted as a new origin;
  - type 5 can contain a model-generated artifact or plan inside tool arguments and was searched as model-authored text.
- Searched all 354 Codex session JSONLs under `/Users/jin/.codex/sessions` (about 1 GB). Root tasks with `thread_source: user` distinguish human user turns from assistant output. Crucially, a Codex subagent's initial role-`user` task is authored by the parent agent; sessions with `thread_source: subagent` were therefore classified as model-authored for lineage purposes.
- Excluded system, developer, tool result, and injected context text as possible authors. Assistant `message`/`agent_message` output and parent-generated subagent prompts were eligible AI-origin sources.

### Matching strategy

- Every retained user utterance longer than roughly 200 characters, multiline/list-form utterance, polished plan/spec, and pasted transcript was searched backward across both platforms.
- Searches combined exact strings, normalized distinctive phrases, six-word shingles, and manual comparison of high-overlap results. Candidate text was compared only with earlier material for origin; later model echoes were recorded as echoes, not origins.
- Short candidates were spot-checked with exact distinctive phrases. Duplicate Codex `response_item`/`event_msg` records and Gemini response/context echoes were collapsed conceptually.
- For mixed text, clauses were separated. A user request copied into a later AI scaffold remains user-originated; new file lists, implementation prescriptions, or conclusions introduced by the AI do not become user-authored merely because the combined text was pasted later.

### Classification policy

- `USER_ORIGINATED`: earliest known semantic instruction is a human user turn.
- `AI_ORIGINATED`: earliest known instruction is model text and no meaningful user semantic delta was found.
- `USER_DELTA_ON_AI`: only a precise user modification to an AI base is eligible.
- `MIXED`: the old normalized candidate combines user-authored and AI-authored clauses.
- `UNRESOLVED`: origin cannot be established confidently enough for promotion.

### Limits

- Absence of an earlier match does not prove that text was never drafted outside these two local corpora. Natural wording, typos, immediate context, repeated user corrections, and lack of earlier AI overlap raise confidence but are not cryptographic authorship proof.
- One Gemini input was cleared from its original envelope. A later user-pasted Antigravity transcript identifies it as `USER_EXPLICIT` and supplies its earlier timestamp; that candidate remains medium confidence because the original payload is unavailable.
- Timestamps below are UTC. Short snippets are included only when needed to show lineage; stale bugs, private URLs, secret values, and long pasted material are omitted.

## 2. Candidate-by-candidate provenance

There are 28 previously numbered candidates: **21 USER_ORIGINATED, 4 MIXED, 2 AI_ORIGINATED, 0 USER_DELTA_ON_AI, and 1 UNRESOLVED**.

### Durable global candidates

#### G1. Validate hypotheses against evidence; investigate contradictions

- Classification: `USER_ORIGINATED`.
- Eligible user-authored core: observed behavior outranks a plausible theory or claimed fix; investigate when the result is still wrong.
- Earliest supporting user source: Gemini, 2026-07-07 09:36:11, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 81. Repeated direct corrections at steps 719, 781, and 887 reinforce the same meaning.
- Cross-platform result: no earlier assistant match for the distinctive correction language. The later Proxifier transcript contains a separate user challenge to an unsupported theory, but is not needed for origin.
- Confidence / promotion: high / eligible.

#### G2. Explicit read-only or discuss-first mode overrides edits

- Classification: `USER_ORIGINATED`.
- Eligible core: honor explicit "read only, no edits" and "no file edits yet" boundaries.
- Earliest source: Gemini, 2026-07-07 13:17:22, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 296; independently repeated in `452fe032-8f65-4cbd-acee-6336587901c8.db`, user step 0, 2026-07-12 14:10:51.
- Earlier AI source search: none.
- Confidence / promotion: high / eligible.

#### G3. Copy-first and Trash-rather-than-`rm` safety

- Classification: `UNRESOLVED`.
- Eligible core: for the specific sensitive-database investigation, copy before reading and move a disposable copy to Trash instead of permanently deleting it.
- Earliest known source: Gemini transcript entry labeled `source: USER_EXPLICIT`, 2026-07-13 12:45:47, quoted later inside `e6c67551-d534-4c2c-b0fe-d4ce37079562.db`, user step 120. The original step-0 payload is cleared. A model checkpoint at step 5 repeats the request ten seconds later, so that model occurrence is an echo, not the semantic origin.
- Later paste: the user pasted the full transcript at step 120, including both user and AI turns.
- Confidence / promotion: medium / withhold pending confirmation. The pasted role record supports user origin, but the missing original payload prevents high-confidence authorship attribution; do not generalize beyond copy/deletion safety from this evidence alone.

#### G4. Document persistent machine/configuration changes

- Classification: `USER_ORIGINATED`.
- Eligible core: save persistent configuration changes in a suitable documented location for later recall.
- Earliest source: Gemini, 2026-07-13 13:56:02, `0ce9c40c-705b-4cd1-8fc6-a5edf169f4e7.db`, user step 91.
- Earlier AI source search: none; preceding AI supplied commands, but the request to preserve and document the changes is the user's added meaning.
- Confidence / promotion: high / eligible as a global preference.

#### G5. Roll back repeatedly failed/regressive portions while keeping independent fixes

- Classification: `USER_ORIGINATED`.
- Eligible core: after another failed attempt, revert the failed portion while preserving an explicitly identified independent good change.
- Earliest source: Gemini, 2026-07-13 06:28:42, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 781; the precise keep/revert split is user step 793 at 06:30:33.
- Earlier AI source search: none. Later model responses quote the rollback instruction.
- Confidence / promotion: high / eligible, phrased as a scoped rollback preference rather than blanket permission for destructive Git commands.

### NativeHA reference and planning candidates

#### P1. Use `hass-frontend` as behavioral ground truth instead of inventing behavior

- Classification: `USER_ORIGINATED` for the core; later polished prompt instances are `MIXED` but are not needed as the source.
- Eligible core: consult the reference implementation and compare NativeHA behavior with Home Assistant instead of inventing semantics.
- Earliest source: Gemini, 2026-07-07 10:37:38, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 117. It recurs naturally in `4f2f6d27-6517-4a3e-af29-dedf94b07005.db` step 0 and `5db9cd33-bafe-49ac-8c13-6f352457a95f.db` step 0.
- Cross-platform lineage: the shorter bug/fix request first appears as a human Codex root-user turn at 2026-07-14 13:21:27 in `rollout-2026-07-14T21-18-24-019f60c7-54d4-7190-9349-858cddcc339f.jsonl`. A Codex parent assistant later supplied detailed timeline reference files and implementation guidance at 2026-07-15 05:08–05:12, including in the subagent prompt `rollout-2026-07-15T13-12-24-019f6430-c102-70b2-b26f-edf131d18ca0.jsonl` (`thread_source: subagent`). Gemini user prompts `ca4…` step 0 and `e8e…` step 0 paste the combined user goal plus AI-generated scaffold. Only the older user core is eligible.
- Confidence / promotion: high / eligible core only; no stale file list or AI implementation plan.

#### P2. Do not apply reference-repo `AGENTS.md` instructions to NativeHA work

- Classification: `USER_ORIGINATED`.
- Eligible core: the user is developing the Swift rewrite, so instructions intended for development inside `hass-frontend` should not govern NativeHA.
- Earliest source: Gemini, 2026-07-15 05:28:17, `c35ebb7b-bf46-426b-ae33-183ac43a52f4.db`, user step 0.
- Later material: step 17 asks to remove the file, but that task-specific mutation is not a durable authorization. Step 39 pastes Gemini's own prior thinking text and is AI-originated, but it does not support this candidate.
- Confidence / promotion: high / eligible semantic core only.

#### P3. Include behaviorally relevant `node_modules` dependencies in reference tracing

- Classification: `USER_ORIGINATED`.
- Eligible core: when TypeScript behavior depends on external packages, index the dependency relationship and inspect relevant package source.
- Earliest source: Gemini, 2026-07-14 10:04:02, `4f2f6d27-6517-4a3e-af29-dedf94b07005.db`, user step 26.
- Earlier AI source search: none; the immediately preceding user turn requested the reference index, and this is a user-added extension.
- Confidence / promotion: high / eligible.

#### P4. Reference parity is the default, with deliberate discussion for explicitly desired improvements

- Classification: `USER_ORIGINATED`.
- Eligible core: inspect the reference, but when the user explicitly dislikes its UX, discuss alternatives before editing rather than copying accidentally.
- Earliest source: Gemini, 2026-07-07 13:17:22, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 296: the user both requests reference inspection and says they are not satisfied with the web behavior.
- Earlier AI source search: none. The assistant's later "approaches" are AI-generated, but the preference and discuss-first instruction precede them.
- Confidence / promotion: high / eligible.

#### P5. Maintain a rescue/action plan covering broad parity and quality gaps

- Classification: `USER_ORIGINATED`.
- Eligible core: create a Markdown/structured plan covering bugs, hardcoding, missing features, UI/animation discrepancy, performance, and worse-than-reference logic/structure.
- Earliest source: Gemini, 2026-07-15 08:26:10, `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, user step 0.
- Backward search: no earlier Gemini or Codex assistant text matched the natural 903-character request or its distinctive list. Gemini generated a detailed rescue plan afterward. At 08:41:40 the user pasted that Claude/Gemini plan into a Codex root task; the pasted plan is AI-authored, but it is later and is not used as evidence for this candidate.
- Confidence / promotion: high / eligible at the category/workflow level only.

#### P6. Size modules for one bounded agent pass; improve smaller nonconforming parts before every major module is complete

- Classification: `USER_ORIGINATED`.
- Eligible core: use one-agent-sized modules and allow smaller conformance work to proceed despite larger unfinished areas.
- Earliest sources: Gemini `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 117, 2026-07-07 10:37:38 (smaller unfinished areas); `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, user step 0, 2026-07-15 08:26:10 (one-agent sizing).
- Earlier AI source search: none for either distinctive clause. Later model outputs echo both.
- Confidence / promotion: high / eligible.

#### P7. Tiny fixes are allowed during the rescue audit unless the task is read-only

- Classification: `USER_ORIGINATED`.
- Eligible core: the user explicitly allowed tiny bugs to be fixed immediately in the rescue-planning task; explicit read-only mode still overrides it.
- Earliest source: Gemini, 2026-07-15 08:26:10, `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, user step 0.
- Earlier AI source search: none.
- Confidence / promotion: high / eligible only with its narrow scope and read-only override.

### Testing and live-server candidates

#### T1. Live-server access and representative real data are allowed when relevant

- Classification: `USER_ORIGINATED`.
- Eligible core: use representative real data for graph/performance diagnosis; connect to the actual server when needed to understand the user's used configuration.
- Earliest sources: Gemini `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 310, 2026-07-07 13:24:33 (real data); `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, user step 0, 2026-07-15 08:26:10 (live-server authorization).
- Earlier AI source search: none. The later Codex rescue task repeats these user clauses after the Gemini source.
- Confidence / promotion: high / eligible authorization, without inventing credential locations or write permission.

#### T2. Measure interaction performance rather than relying only on impressions

- Classification: `USER_ORIGINATED`.
- Eligible core: add a performance measurement for pan/zoom rendering and continue investigating when visible stutters remain.
- Earliest source: Gemini, 2026-07-12 14:45:05, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 537; user step 618 adds the measured/subjective discrepancy.
- Earlier AI source search: none. Model hits are later context echoes.
- Confidence / promotion: high / eligible without the old numeric threshold.

#### T3. Verify GUI/performance fixes in runtime and check regressions

- Classification: `USER_ORIGINATED`.
- Eligible core: review performance changes for regressions and do not claim success while the observed GUI behavior remains wrong.
- Earliest source: Gemini, 2026-07-07 09:36:11, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 81; repeated correction chain at steps 704, 719, 781, and 887.
- Earlier AI source search: none for the corrections; later responses quote them.
- Confidence / promotion: high / eligible.

#### T4. No durable unit-test command or credential location was found

- Classification: `AI_ORIGINATED`.
- Eligible user-authored core: none. This is a corpus observation and recommendation written by the earlier mining agent, not a user instruction.
- Earliest known source: the AI-generated `gemini-user-instructions.md`; no supporting direct user envelope asserts this rule.
- Confidence / promotion: high / reject as authored memory. Missing information can still be reported as an audit limitation, not placed in `AGENTS.md` as the user's instruction.

### Visual and animation candidates

#### V1. Use the reference and screenshots to evaluate visible GUI mismatches

- Classification: `USER_ORIGINATED`.
- Eligible core: compare visible geometry and interaction with Home Assistant; use the attached screenshot when supplied.
- Earliest source: Gemini, 2026-07-07 12:27:58, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 261; step 264 explicitly supplies the forgotten screenshot, and step 310 specifies grid/label behavior.
- Earlier AI source search: none. Later model responses echo the screenshot note.
- Confidence / promotion: high / eligible as a visual-verification preference, without retaining old bug specifics.

#### V2. Animation correctness includes intermediate frames and continuous response

- Classification: `USER_ORIGINATED`.
- Eligible core: dependent scale/axis behavior must update during the gesture/inertia, not jump only at completion.
- Earliest source: Gemini, 2026-07-13 05:39:39, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 704; clarified by steps 719 and 731.
- Earlier AI source search: none for the complaint or proposed temporal behavior. Later model outputs repeat it.
- Confidence / promotion: high / eligible at the general animation-verification level.

#### V3. Use native macOS scrolling/inertia behavior where requested

- Classification: `USER_ORIGINATED`.
- Eligible core: horizontal scrolling should be smooth with native macOS-style inertia; vertical scrolling was requested to control zoom for that chart interaction.
- Earliest source: Gemini, 2026-07-13 05:07:19, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 639.
- Earlier AI source search: none.
- Confidence / promotion: high / eligible, but the vertical-wheel mapping is feature-specific rather than global UI policy.

### Performance candidates

#### F1. Do not sacrifice rendering accuracy for speed

- Classification: `USER_ORIGINATED`.
- Eligible core: performance work must preserve rendering accuracy; report the tradeoff if further improvement requires quality loss.
- Earliest source: Gemini, 2026-07-07 09:23:30, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 0, including the distinctive phrase "not willing to sacrifice render accuracy."
- Earlier AI source search: none. Later model responses echo the sentence.
- Confidence / promotion: high / eligible.

#### F2. Replace a bottleneck algorithm or use acceleration when evidence supports it

- Classification: `USER_ORIGINATED`.
- Eligible core: a faster algorithm and SIMD-capable approach may be researched when the current graph algorithm appears to be the bottleneck.
- Earliest source: Gemini, 2026-07-13 06:33:22, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 808.
- Earlier AI source search: none. The user expresses uncertainty about the exact bottleneck, so this is permission to investigate, not a mandate to replace a named algorithm.
- Confidence / promotion: high / eligible in that bounded form.

#### F3. The 120-FPS request is not a durable project-wide acceptance threshold

- Classification: `MIXED`.
- User-authored part: user step 537 in `943…`, 2026-07-12 14:45:05, asks that specific graph demo to aim above 120 FPS and stop only at the quality tradeoff.
- AI-authored part: the conclusion that this must not be promoted as a project-wide threshold is the earlier mining agent's scope judgment, not a separate user instruction.
- Earlier model source: none for the numeric request; it is user-originated. Later model hits are echoes.
- Confidence / promotion: high lineage confidence / do not promote the number globally. The already eligible user core is T2/F1: measure performance and preserve accuracy.

### Security and credential candidates

#### S1. Live access is authorized, but credentials/secrets must be handled in a particular way

- Classification: `MIXED`.
- Eligible user-authored part: live-server access when relevant, from `5db…` user step 0.
- Non-authored parts: "no eligible credential location was found" is a corpus finding; "never copy a secret value into project memory" was safety guidance added by the mining agent. Neither was stated in an eligible Gemini user envelope.
- Earliest source: Gemini user, 2026-07-15 08:26:10, for live access only. No user-origin source for the added credential-memory rule.
- Confidence / promotion: high / promote only the live-access clause, already covered by T1; obtain credential policy elsewhere.

#### S2. Apply copy-first/Trash safety to server exports and NativeHA debug artifacts

- Classification: `MIXED`.
- User-authored part: the CoreDuet database-specific copy/no-permanent-delete request recovered in G3.
- AI-authored part: extending that isolated instruction to server exports, all databases, and NativeHA test artifacts was the mining agent's extrapolation.
- Earliest source: recoverable Gemini `USER_EXPLICIT` transcript at 2026-07-13 12:45:47; later pasted at `e6…` user step 120.
- Confidence / promotion: medium for the narrow user source / reject the broadened scope; withhold the narrow global rule pending confirmation.

### Autonomy, delegation, and handoff candidates

#### A1. Commit completed work with detail before finishing; keep history understandable

- Classification: `USER_ORIGINATED`.
- Eligible core: commit with detail before finishing so the change can be identified/rolled back; the user also preferred collapsing experimental branches into a comprehensible linear history once validated.
- Earliest source: Gemini, 2026-07-13 05:07:19, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 639 ("In future, commit before you finish"); step 862 repeats "Git commit with detail." Earlier step 99 contains the linear-history request.
- Earlier AI source search: none. Later model responses echo it.
- Confidence / promotion: high / eligible, subject to the current task's authorization to commit.

#### A2. Separate mixed agent contributions and verify provenance from history/diffs

- Classification: `USER_ORIGINATED`.
- Eligible core: when agents' uncommitted edits become mixed, preserve/extract the patch, separate the contributions, and use chat history to verify ownership when needed.
- Earliest source: Gemini, 2026-07-15 04:45:14, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, user step 878; the explicit reverse/reapply workflow is `337a3cae-ffe3-4151-81cd-f34b4c0fc2fc.db`, user step 0 at 06:33:59.
- Earlier AI source search: none for the mixed-agent instruction. Later model responses restate it.
- Confidence / promotion: high / eligible as a handoff preference, without preserving old commit identifiers.

#### A3. Use durable Markdown/index artifacts so later work does not rediscover context

- Classification: `MIXED`.
- User-authored part: generate README/index/description artifacts for the reference and maintain a Markdown or structured rescue plan.
- AI-authored elaboration: "record enough structure that a later agent does not have to rediscover the whole reference tree" is a reasonable explanation added by the mining agent, not a direct user clause.
- Earliest sources: Gemini `4f2f6d27-6517-4a3e-af29-dedf94b07005.db`, user step 0, 2026-07-14 10:00:32; `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, user step 0, 2026-07-15 08:26:10.
- Earlier AI source search: none for the user requests. Later AI-generated artifacts implement them.
- Confidence / promotion: high / eligible only as "maintain durable reference indexes and rescue-plan artifacts."

#### A4. Do not launch subagents automatically because no durable instruction was found

- Classification: `AI_ORIGINATED`.
- Eligible user-authored core: none. This is a negative-corpus conclusion written by the mining agent, not a user preference.
- Earliest known source: `gemini-user-instructions.md`.
- Confidence / promotion: high / reject. Current user instructions and current project policy must decide delegation.

## 3. Clean high-confidence user-authored instructions

The following are the only promotion-ready meanings supported by high-confidence Gemini-side user evidence. Similar items are intentionally not expanded with the earlier report's inferred rationale.

### Global

1. Validate fixes and diagnoses against observed behavior; keep investigating when the result contradicts the explanation or claimed fix. (`943…`, user steps 81/719/781/887)
2. Respect explicit read-only, no-edit, and discuss-first boundaries. (`943…` step 296; `452…` step 0)
3. Document persistent machine/configuration changes in a discoverable location. (`0ce…` step 91)
4. When an attempted change repeatedly fails, roll back the failed portion while retaining explicitly independent good fixes. (`943…` steps 781/793)

### NativeHA reference, planning, and autonomy

5. Use `hass-frontend` as the behavioral reference rather than inventing NativeHA semantics. (`943…` step 117; `4f2…` step 0; `5db…` step 0)
6. Do not apply development instructions from the `hass-frontend` checkout to work on the Swift rewrite. (`c35…` step 0)
7. Trace relevant `node_modules` dependencies when TypeScript behavior depends on them, including the mapping from importing TS modules to packages. (`4f2…` step 26)
8. Reference parity is the default; when the user explicitly wants a better native UX than the reference, discuss the deviation before editing. (`943…` step 296)
9. Maintain a durable rescue/action plan covering parity, configuration, missing features, UI/animation, performance, and structural problems. (`5db…` step 0)
10. Keep stages/modules small enough for one bounded agent pass, and allow smaller nonconforming areas to improve before all major modules are finished. (`943…` step 117; `5db…` step 0)
11. Tiny obvious fixes are allowed during the rescue audit unless the current task is explicitly read-only or discuss-first. (`5db…` step 0, bounded by item 2)

### Testing, GUI, and performance

12. Live-server access is allowed when relevant to understand the user's actual configuration; use representative real data for graph/performance diagnosis. (`5db…` step 0; `943…` step 310)
13. Measure pan/zoom rendering performance and investigate when measurements or visible stutters remain poor. (`943…` steps 537/618)
14. Runtime-check GUI/performance changes and review them for regressions; do not call a fix complete while the observed behavior remains wrong. (`943…` steps 81/704/719/781/887)
15. Compare visible GUI behavior with Home Assistant and use supplied screenshots as evidence. (`943…` steps 261/264/310)
16. Verify animation throughout the interaction, not only at its final state; dependent axes/scales should respond continuously rather than jump at completion. (`943…` steps 704/719/731)
17. Where requested for the macOS chart, preserve smooth native-style scroll inertia and the specified wheel/zoom behavior. (`943…` step 639)
18. Do not sacrifice rendering accuracy merely to improve speed. (`943…` step 0)
19. Research or replace a suspected bottleneck algorithm, including accelerated alternatives, when evidence supports doing so. (`943…` step 808)

### Handoff

20. When commits are authorized, commit completed work with a detailed message before finishing and keep validated history understandable. (`943…` steps 99/639/862)
21. Separate mixed agent contributions and use diffs/chat history to verify provenance when ownership matters. (`943…` step 878; `337…` step 0)
22. Maintain durable README/index and rescue-plan artifacts. (`4f2…` step 0; `5db…` step 0)

Not included above: G3's copy/Trash rule, because its user provenance is recoverable only from a later pasted transcript and remains medium confidence.

## 4. Rejected AI-originated candidates

1. **"No durable unit-test command or credential location was found, therefore obtain them elsewhere."** Valid as an audit observation, but it was authored by the mining agent, not the user.
2. **"Do not launch subagents automatically because no instruction was found."** A negative-corpus inference authored by the mining agent, not a user delegation preference.

The audit also found AI-originated text inside retained user envelopes that must not be promoted:

- The detailed timeline implementation/reference scaffold in Gemini `ca4…`/`e8e…` derives from a Codex root assistant review and parent-generated subagent prompt on 2026-07-15. The older user goal—compare against the reference and fix the behavior—remains eligible; the detailed scaffold does not.
- Gemini `c35…` user step 39 quotes Gemini's own earlier "Prioritizing Tool Usage" thinking. No candidate in the clean list relies on that quoted text.
- The long rescue-plan body later pasted into Codex at 2026-07-15 08:41 is a Claude/Gemini-generated artifact. The earlier Gemini user request to create a plan is eligible; the plan's individual technical clauses are not user-authored merely because they were pasted.

## 5. Mixed or confirmation-sensitive candidates

1. **120 FPS:** the numeric demo request is user-authored, but the conclusion that it is not a durable project-wide threshold is the auditor's scope judgment. Do not promote the number without confirmation; promote measurement and accuracy instead.
2. **Credential-memory rule:** live access is user-authored; the absence of a credential path is an audit finding, and "never copy secrets into memory" was added by the mining agent. Obtain the current credential policy separately.
3. **Copy/delete safety scope:** the narrow CoreDuet request appears user-originated, but broad application to NativeHA server exports/test artifacts is an AI extrapolation. Confirm before promotion.
4. **Durable artifact rationale:** README/index and rescue-plan artifacts are user-authored requests; the explanation about preventing later rediscovery is the mining agent's inference. Promote only the artifact requirement.
5. **Polished timeline prompt:** the later Gemini prompt is mixed across platforms. Preserve only the earlier human goal; reject parent-agent file lists and implementation prescriptions as authored memory.

## 6. Corpus, exclusion, and redaction checks

- Candidate eligibility retained the earlier exclusion of old side-experiment work whose actual target was under the case-sensitive `/Users/jin/Documents/HA` prefix. Excluded Gemini conversations were nevertheless searchable as possible AI-origin sources, as required.
- A mention of `/Users/jin/Documents/HA/hass-frontend` as a reference did not by itself exclude a current NativeHA instruction.
- Codex subagent sessions were not mistaken for human authorship: their parent-generated initial role-`user` prompts were classified as AI-originated using `session_meta.thread_source` and parent linkage.
- No secret value, private authenticated URL, entity-specific stale bug detail, or long transcript passage is reproduced here. Credential policy is described only as present/absent provenance; no credential contents were inspected or recorded.
- The report contains source DB/session basenames, timestamps, roles, and step/lineage context sufficient to re-check conclusions without copying the underlying private conversation text.
