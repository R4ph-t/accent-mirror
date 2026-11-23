# Specs: index

Each spec is a file `<nn>-<slug>.md` in this folder, built on its own branch `factory/<nn>-<slug>` and merged as one
PR. The factory picks only rows whose status is `Ready`, and the table order is the queue order. Raph merging a spec
PR that sets a row to `Ready` is the approval. Estimates are agent time: the agent's run plus Raph's review.

Specs 01–02, 04–17 (contract, pipeline, scoring) and 20–21 (charts from fixtures, coordinator-wired UI) are not in this
index yet. They will arrive in later spec PRs. Row 03 is Draft: it may be implemented after it is
flipped to Ready. Spec 03 does not wait on spec 11; Raph allowed the timestamp check to proceed after the skeleton.

| # | Spec | Status | Depends on | Agent run | Raph review |
|---|---|---|---|---|---|
| 00 | [Project skeleton (by hand)](00-project-skeleton.md) | Done | – | – | 0.5 h |
| 03 | [Timestamp feasibility](03-timestamp-feasibility.md) | Draft | 00 | 3–4 h | 1 h |
| 18 | [UI foundation](18-ui-foundation.md) | Done | 00 | 3–5 h | 1 h |
| 19 | [Fixture-driven UI shell](19-fixture-driven-ui-shell.md) | Done | 18 | 6–8 h | 1.5 h |
