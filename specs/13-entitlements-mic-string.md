# 13: Sandbox, microphone entitlement and usage string (by hand)

Status: Ready · Branch: – · Depends on: 00 (project skeleton) · Estimate: – (Raph by hand) + 0.5 h Raph · Risk: high

Risk: high. Raph only: entitlements, the `NSMicrophoneUsageDescription` string, `project.yml` signing keys and the
`Makefile` are Raph-only areas (AGENTS.md). No agent edits them, and the factory never picks this row (no agent run).

Source: Plan v1 (Notion "Accent Mirror v1 groundwork plan (2026-11-23)", approved 08:58 Europe/Paris), Off limits:
"Entitlements (macOS App Sandbox and `com.apple.security.device.audio-input`) and the wording of
`NSMicrophoneUsageDescription`. The v1 spec proposed a sentence for it, but Raph approves the final string." Plan v2
§7 row 13 ("as before"). Designer spec v1 §4.4 (the proposed string, no pre-prompt screen). Spec 03's Makefile hand
follow-up (open Decision queue row).

## Goal

Let the app use the microphone, sandboxed, so specs 14 and 21 can be tried on Raph's Mac. Nothing else changes.

## Behaviour

Raph makes these changes in one PR (proposed values below; he approves or edits each):

1. **New file `AccentMirror/AccentMirror.entitlements`:**
   - `com.apple.security.app-sandbox` = true
   - `com.apple.security.device.audio-input` = true
   - `com.apple.security.files.user-selected.read-only` = true (for clip import's open panel and drag-and-drop later;
     drop it if Raph prefers to add it with the import UI)
2. **`project.yml`, target `AccentMirror`, `settings.base`:**
   - `CODE_SIGN_ENTITLEMENTS: AccentMirror/AccentMirror.entitlements`
   - `INFOPLIST_KEY_NSMicrophoneUsageDescription: "Accent Mirror listens while you record a take. Your voice is
     analysed on this Mac and never leaves it."` (Designer v1 §4.4, proposed; Raph's wording wins)
3. **`Makefile`:** `fetch-models` runs `scripts/fetch-models.sh` (today it prints `not yet: spec 03`). This is the
   open Decision queue row for spec 03's scripts; it's listed here because spec 21's hand test needs the weights.

There is no pre-prompt screen of our own: the first Record press shows macOS's prompt (spec 21).

## Defaults

- Signing stays automatic with the ad-hoc identity `-`, and CI keeps `CODE_SIGNING_ALLOWED=NO`, so CI never embeds
  the entitlements and never touches the microphone. Hardened runtime, team ID, notarization and release signing stay
  out of this spec (Raph, later).
- With ad-hoc signing, macOS may ask for microphone access again after a rebuild. That's expected for local builds.

## Guardrails

- No team ID, certificate name or personal path in any committed file.
- No other entitlement (no network client or server, no camera, no downloads folder).

## Out of scope

- Live capture code (spec 14), the Record button and permission states (spec 21), Sparkle (not in v1 unless Raph
  decides otherwise), the iOS capability and string (Milestone 2).

## Open question (built with the default)

1. **The microphone string.** Default: Designer v1 §4.4's sentence above. Raph approves the final wording.

## How to test (Raph)

1. `make check` is green (CI builds unsigned, as before).
2. `make build`, then `codesign -d --entitlements - <DerivedData>/Build/Products/Debug/AccentMirror.app` lists
   exactly the keys above.
3. `plutil -extract NSMicrophoneUsageDescription raw <app>/Contents/Info.plist` prints the approved string.
4. `make fetch-models` fetches and verifies the pinned weights (a wrong hash fails).
5. Mark this row Done in `specs/README.md` in the same PR, so specs 14 and 21 can be picked.

## Implementation notes

_(filled in by Raph)_
