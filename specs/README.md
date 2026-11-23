# Specs: index

Each spec is a file `<nn>-<slug>.md` in this folder, built on its own branch `factory/<nn>-<slug>` and merged as one
PR. The factory picks only rows whose status is `Ready`, and the table order is the queue order. Raph merging a spec
PR that sets a row to `Ready` is the approval. Estimates are agent time: the agent's run plus Raph's review.

| # | Spec | Status | Depends on | Agent run | Raph review |
|---|---|---|---|---|---|
| 00 | [Project skeleton (by hand)](00-project-skeleton.md) | In review | – | – | 0.5 h |
