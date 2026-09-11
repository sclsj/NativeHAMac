# Debugging route

Investigate or repair a specific observed failure. Keep scope on its cause; do not expand into a module audit, general parity project, or unrelated cleanup.

- Reproduce or otherwise establish the failure before asserting a cause. Inspect the relevant code, logs, tests, and configuration; compare reference behavior when it determines correctness.
- A diagnosis-only request permits diagnostics and targeted read-only live checks, but no application-code edits. Report the cause, evidence, affected scope, and smallest credible repair; label unresolved hypotheses.
- For a repair, make the smallest change that addresses the demonstrated cause. Add focused regression coverage where practical and validate the affected path. Broaden testing when lifecycle, concurrency, or regression risk warrants it. Preserve responsiveness, cancellation, and generation correctness.
- Open rescue plans, refresh packets, add configuration, or run algorithm benchmarks only when requested or necessary to resolve this bug. Apply the root durable-record rules when the findings or repair change those records.
