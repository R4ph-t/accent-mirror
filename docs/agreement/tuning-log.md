# Tuning log

Every re-tune of the prominence weights, λ and τ (plan §2) gets one entry here, newest first, in the PR that changes
`Thresholds.swift` and `docs/thresholds.md`. Tuning runs only on the tuning split (the 18 VCTK tuning speakers and the
speechocean762 tuning pools of `fixtures/splits/`), never on held-out clips. Run with `scripts/tune.sh`.

Each entry: date, commit, `configDigest` before and after, the grid slice evaluated, the chosen point and its
metrics (recall, VCTK placement FP, any-diff FP, shared-detector FP, synthetic which-syllable accuracy if present),
the number of feasible points, and why.

## Entries

None yet: the initial values (plan v2 rev 4.1) are untuned. The objective needs spec 08's detector.
