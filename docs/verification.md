# Verification route

Use this route to independently verify, test, or review already-completed work.
Do not make application-code edits unless the current prompt explicitly adds
the debugging repair or implementation route.

- Verify the surface changed by each stage and add relevant regression coverage
  only when the prompt authorizes test edits; do not assume an earlier audit
  found bugs introduced later.
- For a packet-backed module, verify by contract ID, update its validation
  results and exact failures, and move its status to `complete` only when all
  required offline, live, visual, performance, and lifecycle checks that apply
  have evidence.
- Use testing appropriate to the changed module, including GUI, animation,
  responsiveness, concurrency, cache, and performance verification where those
  concerns apply.
- Live Home Assistant testing and smoke testing are authorized when they
  materially verify current behavior or integration.
- Compare visible and interactive NativeHA behavior with Home Assistant under
  meaningfully comparable state. Use screenshots or animation frames to show
  mismatches. When manual verification is needed, ask for one specific, bounded
  interaction or capture.
- Verify animation and UI availability during the interaction, not only at its
  final state. In particular, verify that slow cards do not block dismissal or
  unrelated controls.
- For algorithm or cache changes, rerun the tracked benchmark work with live
  `1h` and `24h` data, check cold and warm behavior where relevant, and compare
  correctness as well as speed and memory. Do not sacrifice rendering accuracy
  merely for speed.
- Update `docs/knowledge-base.md` when verification confirms, refines, or
  disproves a durable assumption or local performance fact relevant to future
  work.

Before a handoff, compaction, or session end, update an applicable module
evidence packet with validation results, exact failures, status, remaining gaps,
and the exact next action. Standalone verification outside a packet-backed
module does not require creating a packet.
