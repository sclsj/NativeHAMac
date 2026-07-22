# Debugging route

Use this route for a specific observed bug. Keep the investigation and repair
narrow; do not turn a localized bug into a module audit, parity project, broad
refactor, or unrelated cleanup.

## Diagnosis-only requests

- Reproduce or otherwise establish the reported failure before proposing a
  cause.
- Inspect the smallest relevant execution path, logs, tests, configuration, and
  reference behavior needed to distinguish cause from symptom.
- Report the root cause, supporting evidence, affected scope, and the smallest
  credible repair.
- Do not edit application code. Read-only diagnostics and narrowly scoped test
  or live Home Assistant runs are allowed when they materially establish the
  cause.

## Repair requests

- Establish the cause from relevant code, observed behavior, and tests before
  editing.
- Make the smallest change that addresses the demonstrated cause and preserves
  required behavior. Do not introduce speculative fixes.
- Add or update focused regression coverage where practical.
- Run targeted validation first. Expand it only when the affected surface,
  lifecycle, concurrency, or regression risk warrants broader testing.
- Preserve responsiveness, cancellation, and generation correctness when the
  bug touches asynchronous or expensive work.

## Debugging boundaries

- Compare with `hass-frontend` only when reference behavior is relevant to the
  bug. Trace the complete behaviorally relevant path, but do not audit unrelated
  parts of the module.
- Do not open rescue plans, perform a general parity audit, refresh or create a
  reference-context packet, add configuration surfaces, or run algorithm
  benchmarks unless the prompt requests it or evidence shows it is necessary to
  resolve this bug.
- A repair that changes a durable product deviation, approved configuration
  surface, or recorded module contract must update the corresponding canonical
  document. A repair that does not change those records must not create
  documentation churn.
- An existing module evidence packet needs an update only when the repair
  changes one of its recorded contracts, decisions, validation results, status,
  or assumptions. Standalone bugs do not require a new packet.
- Preserve unrelated and uncommitted work, and inspect the exact diff before
  committing.
