# accent-mirror

See how your English prosody compares with a native recording: stress, rhythm and pitch, side by side. Runs entirely
on the device. Native macOS first, iOS next.

## Build

Needs Xcode 26.2 and XcodeGen (`brew install xcodegen`).

```sh
make build   # generates AccentMirror.xcodeproj and builds the macOS app (unsigned)
make test    # runs the AccentKit package tests
make check   # build, tests and the repo guards, as CI runs them
```

## Layout

| Path | What |
|---|---|
| `AccentMirror/` | The macOS app target (thin) |
| `Packages/AccentKit/` | All the logic, as platform-neutral Swift modules |
| `project.yml` | XcodeGen spec; the `.xcodeproj` is generated and git-ignored |
| `specs/` | The spec queue |
| `docs/` | Reference notes, including the thresholds |
| `scripts/` | Repo guards run by CI |
| `AGENTS.md` | Rules for coding agents |

## Licence

GPL-3.0. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
