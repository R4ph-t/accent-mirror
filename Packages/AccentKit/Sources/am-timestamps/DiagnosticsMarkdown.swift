import AMTimestampEval
import Foundation

/// The diagnostics report's Markdown: one compact table per CTO item (1–4), the decision-rule line, then identity.
enum DiagnosticsMarkdown {
    typealias Pair = AMTimestamps.DiagnosticPair

    static func pct(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "–" }
    static func points(_ value: Double?) -> String { value.map { String(format: "%+.1f points", $0) } ?? "–" }

    static func differ(_ d: VerdictDiagnostics.Diff) -> String { "\(d.differing) (\(pct(d.share)))" }

    static func parts(_ d: VerdictDiagnostics.Diff) -> String {
        VerdictDiagnostics.parts.map { "\(d.parts[$0] ?? 0)" }.joined(separator: " / ")
    }

    static func inconclusive(_ d: VerdictDiagnostics.Diff) -> String {
        "\(pct(d.oracleInconclusiveRate)) → \(pct(d.candidateInconclusiveRate)) (\(points(d.risePoints)))"
    }

    static func bin(_ b: VerdictDiagnostics.Bin) -> String { "\(b.flipped) / \(b.words) (\(pct(b.share)))" }

    static func render(_ r: AMTimestamps.DiagnosticsReport, jsonName: String) -> String {
        var md: [String] = []
        let date = ISO8601DateFormatter().string(from: r.generatedAt)
        md.append("# Word-boundary gate diagnostics (spec 23, CTO decision on #27, 2026-11-23)")
        md.append("")
        md.append("Generated \(date) from commit `\(r.identity.evaluatedCommit.prefix(12))` (clean tree: \(r.identity.cleanTree ? "yes" : "no")). **Measures only**: no shipped behaviour, threshold or aligner decision changes. Same harness (`DownstreamHarness`: spec 07's `SyllableSegmenter` with `ACFVoicing`, spec 06's bundled selector), same verdict function (`WordVerdict`), same thresholds (`ctcConfidenceMin` \(r.identity.ctcConfidenceMin), untuned), same sets and comparability rules as the gate in `\(r.gateReport)`. Machine-readable: `\(jsonName)`.")
        md.append("")
        md.append("Verdict parts are listed inconclusive / syllableCount / longestSyllable / loudestSyllable; a word counts once per part that differs.")
        md.append("")

        // Item 1
        md.append("## 1. Control: two good references (TTS markers vs MFA on TTS)")
        md.append("")
        md.append("| Pair | Comparable words | Verdicts differ n (%) | Per part | Inconclusive oracle → candidate | Against 2.0% |")
        md.append("|---|---|---|---|---|---|")
        for (index, p) in r.control.enumerated() {
            let label = index == 0 ? "**Control of record**: markers vs MFA, gate's comparable words" : "Sensitivity: all marker∩MFA words, probability 1"
            if let d = p.diff {
                let against = (d.share ?? 0) > 0.02 ? "**> 2.0%**" : "**≤ 2.0%**"
                md.append("| \(label) | \(d.words) | \(differ(d)) | \(parts(d)) | \(inconclusive(d)) | \(against) |")
            } else {
                md.append("| \(label) | NOT RUN: \(p.notRun ?? "") | | | | |")
            }
        }
        md.append("")
        if let d = r.control.first?.diff {
            md.append("The control is **\((d.share ?? 0) > 0.02 ? "> 2.0%" : "≤ 2.0%")** (\(pct(d.share))): two references about 25 ms apart (median, the cfd62cd8 report's reference-error table) already disagree on \(d.differing) of \(d.words) verdicts.")
        }
        for p in r.control { if let note = p.note { md.append("- \(note)") } }
        md.append("")

        // Item 2
        md.append("## 2. Ranking: oracle vs candidate, same columns as the gate")
        md.append("")
        md.append("| Set (oracle) | Candidate | Comparable words | Verdicts differ n (%) | Per part | Inconclusive oracle → candidate |")
        md.append("|---|---|---|---|---|---|")
        for p in r.ranking {
            let name = "`\(p.candidate)`"
            if let d = p.diff {
                md.append("| \(p.set) (\(p.oracle)) | \(name) | \(d.words) | \(differ(d)) | \(parts(d)) | \(inconclusive(d)) |")
            } else {
                md.append("| \(p.set) (\(p.oracle)) | \(name) | NOT RUN: \(p.notRun ?? "") | | | |")
            }
        }
        md.append("")
        md.append("Synthetic: Whisper base.en live on the TTS audio (the words that seed b2 in the gate); `dsp-snap-1` and b2 refine those. VCTK: spec 03's committed replay `\(r.identity.whisperReplay)`.")
        md.append("")

        // Item 3
        let b2 = r.ranking.filter { $0.candidate == "ctc-w2v2b960-1" }
        let columns = b2 + r.control.prefix(1)
        let headers = columns.map { $0.candidate == "ctc-w2v2b960-1" ? "b2, \($0.set)" : "control, \($0.set)" }
        md.append("## 3. Breakdown of the flips (b2 on both sets; control alongside)")
        md.append("")
        md.append("| Breakdown | Group | " + headers.joined(separator: " | ") + " |")
        md.append("|---|---|" + columns.map { _ in "---|" }.joined())
        func row(_ group: String, _ name: String, _ cell: (Pair) -> String) {
            md.append("| \(group) | \(name) | " + columns.map { $0.diff == nil ? "NOT RUN" : cell($0) }.joined(separator: " | ") + " |")
        }
        row("Whisper-unmatched", "substituted / deleted (excluded)") { "\($0.recogniserSubstituted ?? 0) / \($0.recogniserDeleted ?? 0)" }
        row("Diff after exclusion", "verdicts differ") { "\($0.diff!.differing) / \($0.diff!.words) (\(pct($0.diff!.share)))" }
        let cueNames = ["inconclusive": "inconclusive", "syllableCount": "syllable count",
                        "longestSyllable": "duration (longestSyllable)", "loudestSyllable": "intensity (loudestSyllable)"]
        for part in VerdictDiagnostics.parts {
            row("Cue", cueNames[part]!) { p in
                let c = p.cues!
                return "\(c.parts[part] ?? 0) (only cue: \(c.sole[part] ?? 0))"
            }
        }
        row("Cue", "pitch") { _ in "not a verdict part in spec 07" }
        for (index, label) in ["1", "2", "3", "4+"].enumerated() {
            row("Syllables (oracle)", label) { bin($0.bySyllableCount![index]) }
        }
        if columns.contains(where: { ($0.bySyllableCount?.count ?? 0) > 4 }) {
            row("Syllables (oracle)", "0") { ($0.bySyllableCount?.count ?? 0) > 4 ? bin($0.bySyllableCount![4]) : "0 / 0" }
        }
        row("Transition", "feedback↔close (decided↔decided)") { bin($0.byTransition![0]) }
        row("Transition", "anything↔inconclusive") { bin($0.byTransition![1]) }
        for (index, label) in ["0–20 ms", "20–40 ms", "40–80 ms", "80–160 ms", ">160 ms"].enumerated() {
            row("Boundary error", label) { bin($0.byBoundaryError![index]) }
        }
        md.append("")
        md.append("- Cells are flipped / words (flip %), except the transition rows (flipped of that type / all flipped words) and the cue rows (a word counts once per part that differs; \"only cue\": words where it is the sole differing part).")
        md.append("- Whisper-substituted words: the gate pairs words by exact normalised text (`Tokens.match`), so a phrase word Whisper heard as something else is never comparable. They are already outside every diff; the row counts them (substituted: an unmatched Whisper word sits in the gap; deleted: none does), and b2's diff after the exclusion is the gate's diff, unchanged.")
        md.append("- Boundary error: max(|start error|, |end error|) of the candidate's span against the oracle's; bins have inclusive upper edges.")
        md.append("- Pitch: not a verdict part in spec 07 (the verdict is inconclusive, syllable count, longest syllable, loudest syllable).")
        md.append("")

        // Item 4
        md.append("## 4. b2's inconclusive rise: CTC confidence gate vs verdict margins")
        md.append("")
        md.append("| Set | Comparable words | Oracle inconclusive | b2 inconclusive | b2, gate bypassed | Full rise | From the confidence gate | From margins | Words gated |")
        md.append("|---|---|---|---|---|---|---|---|---|")
        for p in b2 {
            guard let s = p.inconclusiveSplit else {
                md.append("| \(p.set) | NOT RUN: \(p.notRun ?? "") | | | | | | | |")
                continue
            }
            md.append("| \(p.set) | \(s.words) | \(s.oracleInconclusive) | \(s.candidateInconclusive) | \(s.candidateUngatedInconclusive) | \(points(s.fullRisePoints)) (\(s.fullRiseWords) words) | \(points(s.fromGatePoints)) (\(s.fromGateWords) words) | \(points(s.fromMarginsPoints)) (\(s.fromMarginsWords) words) | \(s.gatedWords) |")
        }
        md.append("")
        md.append("The gate is bypassed in the diagnostic path only (b2's spans keep Whisper's probability); `Thresholds.swift` and the shipped default are untouched. Rise from the gate = full rise − rise with the gate bypassed; rise from margins = the rest.")
        md.append("")

        // Decision rule
        md.append("## Which branch of CTO's decision rule")
        md.append("")
        md.append("CTO's rule, verbatim:")
        md.append("")
        md.append("- control > 2% → the gate re-runs on spec 11's tuned thresholds (held-out), same ≤ 2% / ≤ 2-point limits for b2 vs oracle, and spec 11 also reports the control on its tuned thresholds;")
        md.append("- control ≤ 2% and b2 still > 2% after spec 11's tuning → rework b2, guided by the cue breakdown;")
        md.append("- Whisper-only beats b2 on the diff → drop b2.")
        md.append("")
        md.append(decision(r))
        md.append("")

        // Gate reproduction, identity, commands
        md.append("## Gate reproduced")
        md.append("")
        md.append("| Set | Gate (cfd62cd8): differ / words, gated | This run | Same |")
        md.append("|---|---|---|---|")
        for c in r.gateCheck {
            md.append("| \(c.set) | \(c.gateDiffering) / \(c.gateWords), \(c.gateInconclusiveByConfidence) | \(c.differing) / \(c.words), \(c.gatedByConfidence) | \(c.matches ? "yes" : "**no**") |")
        }
        md.append("")
        let i = r.identity
        md.append("## Identity")
        md.append("")
        md.append("- Evaluated commit: `\(i.evaluatedCommit)`; clean tree: \(i.cleanTree ? "yes" : "no")")
        md.append("- `sourceTreeHash`: `\(i.sourceTreeHash)`")
        md.append("- Shipped aligner's `configDigest` (`whisper`): `\(i.shippedConfigDigest)`")
        for (id, digest) in i.configDigests.sorted(by: { $0.key < $1.key }) { md.append("  - `\(id)`: `\(digest)`") }
        md.append("- VCTK corpus manifest hash: `\(i.corpusManifestHash)`; label (MFA word baseline) `\(i.labelFile)`: `\(i.labelHash)`")
        md.append("- Whisper: `\(i.asrModelID)`; VCTK replay `\(i.whisperReplay)`; live on TTS from `\(i.liveWhisperManifest ?? "–")`")
        md.append("- b2 package SHA-256: `\(i.ctcPackageSHA256 ?? "–")`")
        md.append("- Synthetic set (git-ignored `.cache/reference/`, not regenerated by this run): markers.json `\(i.markersSHA256 ?? "–")`, mfa-alignment.json `\(i.mfaOnTTSSHA256 ?? "–")`, TTS audio hash `\(i.ttsAudioHash ?? "–")`")
        md.append("- Thresholds read, not changed: `ctcConfidenceMin` \(i.ctcConfidenceMin), `verdictDiffMax` \(i.verdictDiffMax), `inconclusiveRiseMaxPoints` \(i.inconclusiveRiseMaxPoints)")
        md.append("- Toolchain: \(i.toolchain.xcode); \(i.toolchain.swift); macOS \(i.toolchain.macOS); \(i.toolchain.hardware)")
        md.append("")
        md.append("## Reproduce")
        md.append("")
        md.append("```sh")
        md.append("git checkout \(i.evaluatedCommit)")
        md.append("scripts/eval-word-boundaries.sh --dev                 # once, if .cache/reference/ is missing: TTS + MFA on TTS")
        md.append("scripts/eval-word-boundary-diagnostics.sh             # release run: clean tree, writes this report")
        md.append("scripts/eval-word-boundary-diagnostics.sh --dev       # any tree, report under .cache/reports/")
        md.append("```")
        return md.joined(separator: "\n")
    }

    static func decision(_ r: AMTimestamps.DiagnosticsReport) -> String {
        guard let control = r.control.first?.diff?.share else {
            return "**Not determinable**: the control did not run."
        }
        let sets = Set(r.ranking.map(\.set)).sorted()
        var beats: [String] = [], loses: [String] = []
        for set in sets {
            let w = r.ranking.first { $0.set == set && $0.candidate == "whisper" }?.diff?.share
            let b = r.ranking.first { $0.set == set && $0.candidate == "ctc-w2v2b960-1" }?.diff?.share
            guard let w, let b else { continue }
            let line = "\(set): whisper \(pct(w)) vs b2 \(pct(b))"
            if w < b { beats.append(line) } else { loses.append(line) }
        }
        var lines: [String] = []
        if control > 0.02 {
            lines.append("**The numbers point to the first branch** (control \(pct(control)) > 2.0%): the gate re-runs on spec 11's tuned thresholds (held-out), and spec 11 also reports the control on them. The second branch's precondition (control ≤ 2%) does not hold.")
        } else {
            lines.append("**Control \(pct(control)) ≤ 2.0%**: the first branch does not hold. The second branch (rework b2, guided by the cue breakdown) applies if b2 is still > 2% after spec 11's tuning, which this round cannot measure.")
        }
        if !beats.isEmpty && loses.isEmpty {
            lines.append("**Third branch also holds**: Whisper-only beats b2 on the diff on every set (\(beats.joined(separator: "; "))).")
        } else if !beats.isEmpty {
            lines.append("Third branch, mixed: Whisper-only beats b2 on \(beats.joined(separator: "; ")), but not on \(loses.joined(separator: "; ")).")
        } else {
            lines.append("Third branch does not hold: Whisper-only does not beat b2 on the diff on any set (\(loses.joined(separator: "; "))).")
        }
        lines.append("Reported, not applied: the decision is CTO's.")
        return lines.joined(separator: " ")
    }
}
