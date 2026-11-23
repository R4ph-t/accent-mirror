# 00: Project skeleton (by hand)

Status: Done · Branch: factory/00-skeleton · Depends on: – · Risk: high

Source: the groundwork plan (Raph approved 2026-11-23). Scope change at 09:00 Paris the same day: "Mac first, iOS
right after", so this spec has a macOS app target only.

## Goal

A repo every later spec can build on: a macOS app shell, the `AccentKit` package with its nine modules and their
dependency direction, the rules agents follow, CI, and the guards that keep local-only corpora out of git.

## Scope

- `project.yml` (XcodeGen): one macOS app target `AccentMirror` (macOS 26, Swift 6, strict concurrency) showing a
  placeholder window, a shared scheme, no signing beyond automatic with no team.
- `Packages/AccentKit`: nine library modules (`AMCore` … `AMPipeline`), each with a placeholder file and one
  Swift Testing test. No AppKit, no UIKit, no third-party dependencies.
- `AGENTS.md`, this index, `docs/thresholds.md`, `THIRD_PARTY_NOTICES.md` skeleton, `README.md`.
- `Makefile` (`generate`, `build`, `test`, `check-corpus`, `check-ui-frameworks`, `check`, and stubs for later specs).
- `.github/workflows/ci.yml`: `build & test` on GitHub-hosted `macos-26`, Xcode 26.2 pinned.
- `scripts/check-local-corpus.sh` with its self-test, and `scripts/check-no-ui-frameworks.sh`.
- `.factory/risky-paths.txt`, proposed.

## Out of scope

- The iOS app target and the iOS simulator CI build (next, "iOS right after").
- Any real UI (Designer is redoing the design), entitlements, `NSMicrophoneUsageDescription`, a team ID, the hardened
  runtime, notarization.
- Model weights, audio files, WhisperKit, the nightly workflow (spec 03), `.factory/project.conf` (Manufacture
  onboarding writes it).

## How to test (Raph)

1. `make check`: generates the project, builds the macOS app with no warnings from our code, runs the nine package
   tests, the corpus guard and its self-test, and the AppKit/UIKit guard.
2. Check that the `build & test` check is green on the PR.
3. Read `.factory/risky-paths.txt` and decide on the list.

## Implementation notes

- Each module exposes `<Module>Module.name` and `.dependencies`; its test checks both, which also proves the
  module compiles against exactly the modules it is allowed to import.
- `Package.swift` declares the modules in one table, so the dependency direction is readable in one place.
- `.factory/risky-paths.txt` uses WriteGood's format: one extended regex per line.
