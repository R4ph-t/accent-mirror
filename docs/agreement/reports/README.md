# Agreement reports

Written by `scripts/agreement.sh --suite <suite> --write-report` as `<suite>-<configDigest8>.json` and `.md` (spec 02,
plan §6.6). Everything in this folder is left out of `sourceTreeHash`, so a report can be committed after the commit
it evaluated; `scripts/check-report-identity.sh <report.json> <release-commit>` checks it is still valid for a release.
A dirty tree cannot write a release report (`--release`).
