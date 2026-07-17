# Gemini Antigravity: durable user instructions

> Candidate memory only. This report mines user-authored instructions from Gemini Antigravity history; it does not promote anything into `AGENTS.md`. Promotion should happen only after conflict review and user approval.

## 1. Method, confidence, and exclusion logic

### Corpus and decoding

- Inspected all **61** SQLite databases matching `/Users/jin/.gemini/antigravity/conversations/*.db` (about 190 MB), spanning **2026-07-07 through 2026-07-15 UTC**.
- Inspected every row in `steps`. There were **208 `step_type = 14` envelopes**. Raw protobuf decoding shows that type 14 is the user-input envelope: the primary prompt is top-level field 19, nested field 2; its timestamp is under field 5. Model responses, tool calls/results, and injected ephemeral messages use other step types. This mapping was cross-checked against available `transcript.jsonl` records whose corresponding entries are explicitly marked `source: USER_EXPLICIT` and `type: USER_INPUT`.
- Recovered primary text from **193/208** user envelopes. The other 15 were cleared, attachment-only, empty approval, or state-transition envelopes; four in the principal current-NativeHA conversation were empty plan/approval events and contained no additional instruction text.
- Decoding confidence is **high** for message authorship, primary text, step index, database provenance, and UTC timestamp. It is **medium** for attachment-only meaning and for conversations whose IDE workspace differed from the task target.
- Only direct user envelopes were treated as instructions. Model reasoning, system reminders, conversation summaries, and tool output were not mined. One global deletion-safety preference below was recoverable only because the user pasted their earlier `USER_EXPLICIT` transcript inside a later direct user message; it is labeled medium confidence.

### Exact scope/exclusion rule

- The trajectory metadata's workspace URI (protobuf field 1/1), direct user text, and actual tool working directories were considered together. A mere mention of a path did not establish the task target.
- **41 databases / 97 user envelopes** were excluded as work on the old side experiment rooted at the case-sensitive prefix `/Users/jin/Documents/HA`, including old `/Users/jin/Documents/HA/NativeHA` work.
- Three databases had an IDE workspace under `/Users/jin/Documents/HA` but a task that actually targeted the current repo, so they were retained:
  - `452fe032-8f65-4cbd-acee-6336587901c8.db` explicitly names `Documents/Computer/NativeHA`.
  - `337a3cae-ffe3-4151-81cd-f34b4c0fc2fc.db` performs change-provenance work in `/Users/jin/Documents/Computer/NativeHA`.
  - `5db9cd33-bafe-49ac-8c13-6f352457a95f.db` performs its rescue assessment and artifact work in `/Users/jin/Documents/Computer/NativeHA`; `/Users/jin/Documents/HA/hass-frontend` is the reference workspace.
- `4f2f6d27-6517-4a3e-af29-dedf94b07005.db` was retained with **medium project-association confidence**: its IDE workspace was unrelated, but its task is explicitly about durable reference indexing for the Swift rewrite and cites `/Users/jin/Documents/HA/hass-frontend` only as ground truth.
- The report draws project instructions from eight databases and global preferences from two more (**10 contributing DBs; 74 user envelopes, 64 with primary text**). Other conversations were inspected but yielded only unrelated questions, one-off tasks, transient bugs, or stale implementation details.
- Semantic duplicates were merged. `ca4b8cc3-cbb1-4897-8348-218e37906a10.db` and `e8e10277-1f78-4bff-a2c4-8f69fe8fb9bd.db` begin with the same copied prompt, so both records are cited but count as one independent instruction occurrence where relevant.

Evidence counts below count direct user-message records unless otherwise noted. Dates are UTC.

## 2. Durable global instructions

### Evidence and diagnosis

1. **Validate hypotheses against direct evidence and investigate further when observed behavior contradicts the theory or claimed fix.** Do not equate a plausible explanation or code edit with a verified result.
   - Scope: global diagnosis, audits, and bug fixing.
   - Confidence: high.
   - Evidence: at least 6 messages across 2 DBs, 2026-07-07 to 2026-07-15.
   - Sources: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, `e6c67551-d534-4c2c-b0fe-d4ce37079562.db`.

2. **An explicitly read-only, no-edit, or discuss-first request overrides implementation autonomy.** Provenance investigations should not mutate files, and design discussions marked "no file edits yet" should stop before editing.
   - Scope: global task-mode boundary.
   - Confidence: high.
   - Evidence: 2 messages across 2 DBs, 2026-07-07 to 2026-07-12.
   - Sources: `452fe032-8f65-4cbd-acee-6336587901c8.db`, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

3. **For sensitive or unfamiliar data, preserve the original, inspect a copy, and avoid permanent deletion; move disposable copies to Trash instead of using `rm`.**
   - Scope: global filesystem/data safety.
   - Confidence: medium, because the instruction was recovered from an earlier user transcript pasted inside a later direct user message.
   - Evidence: 1 recoverable instruction, 2026-07-13.
   - Source: `e6c67551-d534-4c2c-b0fe-d4ce37079562.db`.

4. **Document persistent machine or environment changes in a discoverable location so they can be recalled later.**
   - Scope: global system/configuration work.
   - Confidence: high.
   - Evidence: 1 message, 2026-07-13.
   - Source: `0ce9c40c-705b-4cd1-8fc6-a5edf169f4e7.db`.

5. **When a change repeatedly fails or regresses behavior, preserve independent good fixes but roll back the failed portion rather than layering more speculative edits indefinitely.**
   - Scope: global iterative implementation.
   - Confidence: high.
   - Evidence: 2 explicit messages in one DB, 2026-07-13.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

## 3. Durable instructions for current NativeHA

### Reference parity and code exploration

1. **Use `hass-frontend` as the behavioral ground truth; inspect the applicable reference implementation instead of inventing NativeHA behavior.** Compare behavior, logic, structure, setup, UI, animation, and performance-relevant choices where applicable.
   - Scope: all current NativeHA implementation, audits, and planning.
   - Confidence: high.
   - Evidence: 8 messages across 5 DBs, 2026-07-07 to 2026-07-15; the identical opening prompts in the `ca4…` and `e8e…` DBs are one independent occurrence.
   - Sources: `4f2f6d27-6517-4a3e-af29-dedf94b07005.db`, `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, `ca4b8cc3-cbb1-4897-8348-218e37906a10.db`, `e8e10277-1f78-4bff-a2c4-8f69fe8fb9bd.db`.

2. **Do not let `hass-frontend`'s repository instructions govern work on the Swift rewrite.** The user is developing NativeHA, not `hass-frontend`; reference-repo `AGENTS.md` content is out of scope for NativeHA behavior and workflow.
   - Scope: instruction precedence while reading the reference repo.
   - Confidence: high.
   - Evidence: 2 messages in one DB, 2026-07-15.
   - Source: `c35ebb7b-bf46-426b-ae33-183ac43a52f4.db`.

3. **Reference exploration must include relevant external implementation dependencies, not only `src`.** When building an index, map which TypeScript files/modules use which `node_modules` package and inspect dependency code when it contributes to behavior.
   - Scope: reference indexing and dependency tracing.
   - Confidence: medium-high; explicit but seen in one conceptual indexing task.
   - Evidence: 1 message, 2026-07-14.
   - Source: `4f2f6d27-6517-4a3e-af29-dedf94b07005.db`.

4. **Treat parity as the default, not an unquestionable requirement when the user explicitly asks for a better native experience.** If reference behavior itself is undesirable, discuss alternatives before editing and make the deviation deliberate rather than accidental.
   - Scope: intentional UX/performance deviations.
   - Confidence: high.
   - Evidence: 1 explicit discuss-first message plus multiple default-parity messages, 2026-07-07 to 2026-07-15.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db` (supported by the parity sources above).

### Planning and module boundaries

5. **Maintain a durable rescue/action plan that covers bugs, hardcoded configuration, missing features, UI/animation discrepancies, poor performance, and logic/implementation/setup/structure that is worse than the reference.** Markdown or a structured database is acceptable.
   - Scope: project planning and cross-session memory.
   - Confidence: high.
   - Evidence: 1 comprehensive message, 2026-07-15.
   - Source: `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`.

6. **Group work into modules small enough for one agent to complete in one bounded pass.** Major unfinished areas do not block improving smaller subfunctions that fail to conform to Home Assistant behavior.
   - Scope: planning, delegation, and stage sizing.
   - Confidence: high.
   - Evidence: 2 messages across 2 DBs, 2026-07-07 to 2026-07-15.
   - Sources: `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

7. **During a planning/audit pass, tiny obvious bugs may be fixed immediately, but broad changes are not implied.** Explicit read-only or discuss-first task wording still overrides this permission.
   - Scope: limited implementation autonomy during rescue work.
   - Confidence: high.
   - Evidence: 1 explicit authorization, 2026-07-15, reconciled with 2 read-only/discuss-first messages.
   - Source: `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`; boundary evidence in `452fe032-8f65-4cbd-acee-6336587901c8.db` and `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

## 4. Testing and live-server expectations

1. **The live Home Assistant server may be used when needed to understand the user's real configuration and prioritize behavior they actually use.** Representative real data is preferable for graph/performance work where fixtures would hide the issue.
   - Scope: current NativeHA integration, smoke, and representative-data testing.
   - Confidence: high for authorization; medium for treating live data as a general default.
   - Evidence: 3 messages across 2 DBs, 2026-07-07 to 2026-07-15.
   - Sources: `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

2. **Measure performance rather than relying only on subjective impressions.** Instrument render latency/FPS for representative pan and zoom interactions, then investigate other causes when measurements or visible stutters remain bad.
   - Scope: graph and GUI performance verification.
   - Confidence: high.
   - Evidence: at least 3 messages in one DB, 2026-07-12 to 2026-07-13.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

3. **After performance or GUI fixes, actively check for regressions in behavior and interaction—not merely compilation or a successful edit.** A fix should not be called complete while the originally observed runtime behavior remains broken.
   - Scope: regression and runtime verification.
   - Confidence: high.
   - Evidence: at least 7 correction/verification messages across 2 DBs, 2026-07-07 to 2026-07-15.
   - Sources: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, `e8e10277-1f78-4bff-a2c4-8f69fe8fb9bd.db`.

4. **No eligible Gemini instruction established a durable unit-test command, required test suite, or credential file location.** Do not infer those from excluded old `/Users/jin/Documents/HA` sessions; obtain them from current project documentation or the user.
   - Scope: limitation on promotion to `AGENTS.md`.
   - Confidence: high after full-corpus/exclusion review.
   - Evidence: zero eligible direct instructions containing a credential location; one eligible live-server authorization.
   - Sources: corpus-wide result; live authorization in `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`.

## 5. Visual, UI, and animation expectations

1. **Use the reference and user-provided screenshots to identify visual mismatches.** Check geometry, chart size/clipping, grid/label motion, zoom availability, and other visible interaction behavior rather than relying only on a verbal bug summary.
   - Scope: GUI and chart parity.
   - Confidence: high.
   - Evidence: at least 4 messages across 2 DBs, 2026-07-07 to 2026-07-15.
   - Sources: `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

2. **Animation correctness includes intermediate frames and continuous interaction response, not only the final state.** During gesture/inertial zoom, dependent axes/scales should update smoothly instead of jumping only when scrolling finishes.
   - Scope: interactive chart animation.
   - Confidence: high.
   - Evidence: at least 7 messages in one DB, 2026-07-13.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

3. **Use native macOS interaction behavior where requested, including smooth inertial horizontal scrolling and wheel/vertical-scroll zoom semantics, while preserving the relevant Home Assistant behavior.**
   - Scope: macOS chart interaction design.
   - Confidence: high but feature-specific.
   - Evidence: 1 message, 2026-07-13.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

## 6. Performance expectations

1. **Do not trade away rendering accuracy merely to improve speed.** Keep optimizing or report the limiting tradeoff when further gains would compromise output quality.
   - Scope: NativeHA rendering/performance work.
   - Confidence: high.
   - Evidence: 2 explicit messages in one DB, 2026-07-07 to 2026-07-12.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

2. **Performance investigation may replace an algorithm or use platform acceleration when evidence shows the existing approach is the bottleneck.** Search/research is permitted for that bounded purpose.
   - Scope: performance implementation choices.
   - Confidence: high but graph-specific.
   - Evidence: 1 explicit message, 2026-07-13.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

3. **The historical request to aim above 120 FPS was a demo-specific aspiration, not a durable acceptance threshold.** Preserve the durable rule to measure responsiveness and quality, but require new user confirmation before promoting a numeric FPS target project-wide.
   - Scope: staleness guard for performance criteria.
   - Confidence: high.
   - Evidence: 1 message, 2026-07-12.
   - Source: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

## 7. Security and credentials

1. **Live-server access is authorized when relevant, but no eligible Gemini message supplied a durable credential file location.** Never copy a secret value from session history into project memory; record only an approved current location after separate confirmation.
   - Scope: current NativeHA live testing and memory hygiene.
   - Confidence: high.
   - Evidence: 1 authorization message; 0 eligible credential-location messages, 2026-07-15.
   - Source: `5db9cd33-bafe-49ac-8c13-6f352457a95f.db` plus corpus-wide exclusion result.

2. **Apply the global copy-first/no-permanent-deletion preference when inspecting server exports, databases, or other sensitive artifacts.**
   - Scope: sensitive test/debug artifacts.
   - Confidence: medium.
   - Evidence: 1 recoverable global instruction, 2026-07-13.
   - Source: `e6c67551-d534-4c2c-b0fe-d4ce37079562.db`.

## 8. Autonomy, delegation, and handoff

1. **Commit completed work with a detailed message before finishing so it can be identified and rolled back.** Prefer a comprehensible linear sequence of commits over opaque overlapping changes.
   - Scope: current NativeHA git handoff.
   - Confidence: high.
   - Evidence: 3 explicit messages across 2 DBs, 2026-07-13 to 2026-07-15.
   - Sources: `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`, `e8e10277-1f78-4bff-a2c4-8f69fe8fb9bd.db`.

2. **When multiple agents' uncommitted edits become mixed, reconstruct provenance from history/diffs, preserve the patch, and separate contributions before committing or reapplying.** Validate a claimed agent contribution against its chat history when ownership matters.
   - Scope: multi-agent coordination and git provenance.
   - Confidence: high.
   - Evidence: at least 3 messages across 2 DBs, 2026-07-15.
   - Sources: `337a3cae-ffe3-4151-81cd-f34b4c0fc2fc.db`, `9430866c-a5c8-46a3-bdf5-b5ba1aa8690f.db`.

3. **Use durable Markdown/index artifacts to hand off reference findings and staged rescue work across sessions.** Record enough structure that a later agent does not have to rediscover the whole reference tree.
   - Scope: project documentation and cross-session handoff.
   - Confidence: high for durable artifacts; medium for the exact index shape.
   - Evidence: 3 messages across 2 DBs, 2026-07-14 to 2026-07-15.
   - Sources: `4f2f6d27-6517-4a3e-af29-dedf94b07005.db`, `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`.

4. **The Gemini corpus supports one-agent-sized modules, but contains no eligible durable instruction to launch subagents automatically.** Treat delegation policy as requiring current user/project guidance rather than inferring it from old side-experiment sessions.
   - Scope: delegation boundary.
   - Confidence: high.
   - Evidence: 1 module-sizing instruction; 0 eligible automatic-delegation instructions.
   - Source: `5db9cd33-bafe-49ac-8c13-6f352457a95f.db`.

## 9. Conflicts, ambiguities, and staleness warnings

- **Reference fidelity vs intentional improvement:** `hass-frontend` is repeatedly named as ground truth, but the user also explicitly said some reference graph behavior was unsatisfactory and asked to discuss alternatives. Promote a rule that reference behavior is the default oracle and that deliberate deviations require an explicit rationale/approval; do not promote absolute byte-for-byte or UI-for-UI copying.
- **Autonomy vs task mode:** tiny fixes were permitted during one rescue-planning task, while provenance and design tasks were explicitly read-only/discuss-first. The narrowest current task instruction should win.
- **Commits vs branches:** the user initially asked whether branches or commits were better, then later issued the durable correction to commit in detail before finishing. Do not promote a blanket branch-creation rule from this corpus.
- **Old parallel NativeHA:** two retained prompts suggested comparing with `/Users/jin/Documents/HA/NativeHA`, but that path belongs to the excluded side experiment and any exact code references there are stale. Preserve only the general value of comparison; treat `hass-frontend` and current project docs as the durable sources unless the user reauthorizes the old copy.
- **Reference `AGENTS.md`:** a historical task asked to remove/ignore the reference repo's file. Promote only the instruction-precedence result (do not apply reference-development rules to NativeHA), not a standing authorization to modify or delete files in the reference checkout.
- **Performance numbers:** the 120 FPS target, one-day/three-hour data windows, zoom limits, and particular algorithms were tied to a graph demo. They are evidence for measurement and quality priorities, not durable numeric requirements.
- **Live testing:** authorization is clear, but allowed mutation level, required smoke flows, and credential location are absent from eligible Gemini history. These need current documentation/user confirmation.
- **Task-target inference:** `4f…`, `337…`, and `5db…` had IDE workspace metadata that differed from their effective task target. Their project association was established from direct text plus actual tool/artifact paths; `4f…` remains medium confidence.
- **Duplicated prompt:** `ca4…` and `e8e…` duplicate the same initial user prompt. Recurrence counts should not treat that duplication as two independent preferences.

## 10. Excluded material and extraction limitations

- Excluded old `/Users/jin/Documents/HA` work included stage-specific module prompts, old Swift paths/symbols/line numbers, stale bug reports, old audit findings, task-specific prohibitions/permissions, and old live-test/credential guidance. None was used to establish current instructions.
- Excluded from eligible/current conversations: individual bug symptoms, exact commit hashes, exact file lists, chart-window values, temporary demo controls, transient status questions, branch names, and implementation ideas that the user later rolled back.
- Empty/attachment-only user envelopes could identify that an attachment or approval event occurred, but not reliably reconstruct its semantics from the SQLite protobuf alone. No durable rule depends solely on one of these records.
- Raw transcript text can contain pasted assistant output, system reminders, and prior conversation logs. These were not treated as user preferences merely because they appeared inside a user payload. The one copy-first/deletion-safety exception is explicitly labeled because the pasted record itself identifies the underlying entry as the user's earlier request.
- Counts describe the on-disk corpus at extraction time. Antigravity may append or rewrite databases later; rerun extraction before treating this as a permanent exhaustive archive.
