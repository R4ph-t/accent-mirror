// Spec 26 §1: `am-eval nucleus-count --inputs <guard/tuning/inputs.json> --mfa <guard/tuning/mfa-work/aligned>
// [--lag real|offset-fixed] [--write-report] [--tuning-log <entry.md>] [--summary <file>]`.
// Runs the pre-declared grid on the VCTK tuning speakers only (detection truth: MFA words, phones and N_w; no
// verdict, flip or held-out number), prints the grid table (count-match, vowel-inside, IoU, feasible) and the chosen
// point, and writes docs/agreement/reports/nucleus-count-<configDigest8>.{json,md}. With `--tuning-log` it writes the
// tuning-log entry's text to that file (the caller puts it in docs/agreement/tuning-log.md with the frozen choice).

import AMAlignment
import AMCore
import AMEvaluation
import AMPitch
import AMProsody
import Foundation

private struct CountInput: Decodable {
    let clipID: String
    let audio: String
    let transcript: String
}

/// One clip, prepared once: the envelope, pYIN voicing cells and the comparable words (MFA-timed, with N_w).
private struct PreparedClip {
    let clip: NucleusCountGrid.Clip
    let envelope: [Double]
    let voiced: [Bool]
    let words: [NucleusAssigner.Word]
    let contexts: [Int]
}

/// Order-preserving match of folded expected words to MFA word labels (longest common subsequence).
func lcsMatch(_ a: [String], _ b: [String]) -> [Int: Int] {
    let m = a.count, n = b.count
    var best = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in stride(from: m - 1, through: 0, by: -1) {
        for j in stride(from: n - 1, through: 0, by: -1) {
            best[i][j] = a[i] == b[j] ? best[i + 1][j + 1] + 1 : max(best[i + 1][j], best[i][j + 1])
        }
    }
    var out: [Int: Int] = [:]
    var i = 0, j = 0
    while i < m && j < n {
        if a[i] == b[j] {
            out[i] = j
            i += 1
            j += 1
        } else if best[i + 1][j] >= best[i][j + 1] {
            i += 1
        } else {
            j += 1
        }
    }
    return out
}

struct NucleusCountReport: Encodable {
    let suite = "nucleus-count"
    let generatedAt: String
    let identity: ReportIdentity
    let speakers: [String]
    let clips: Int
    let comparableWords: Int
    let voicedWithinMs: [Double]
    let timestampCheck: String
    let reducedFormsSHA256: String
    let reducedFormsEntries: Int
    let points: [NucleusCountGrid.Metrics]
    let feasible: Int
    let chosen: NucleusCountGrid.Point?
    let closest: [NucleusCountGrid.Metrics]?

    var baseName: String { "\(suite)-\(identity.configDigest.prefix(8))" }
}

func nucleusCount(_ args: Arguments, root: URL) async throws -> Int32 {
    let split = try JSONDecoder().decode(
        VCTKSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/splits/vctk.json")))
    let lag = args.value("lag") ?? "real"
    guard lag == "real" || lag == "offset-fixed" else { throw CLIError.usage("--lag takes real or offset-fixed") }
    let voicedWithin = lag == "real" ? NucleusCountGrid.voicedWithinMsRealLag : NucleusCountGrid.voicedWithinMsOffsetFixed
    let points = NucleusCountGrid.points(voicedWithinMs: voicedWithin)
    let base = Thresholds.current
    let inputs = try JSONDecoder().decode([CountInput].self, from: Data(contentsOf: try args.url("inputs")))
    let mfa = try args.url("mfa")
    let selector = try PronunciationSelector.bundled()
    let dictionary = try PronouncingDictionary.bundled()
    let reduced = try ReducedForms.bundled()

    // The guard first: every clip must be a tuning speaker's.
    let speakersOf = inputs.map { String($0.clipID.prefix { $0 != "_" }) }
    try NucleusCountGrid.validate(
        zip(inputs, speakersOf).map { NucleusCountGrid.Clip(clipID: $0.clipID, speaker: $1, vowels: []) }, split: split)

    let (prepared, skipped) = try await prepareCountClips(
        inputs: inputs, speakers: speakersOf, mfa: mfa, selector: selector, dictionary: dictionary, reduced: reduced,
        pitch: base.pitch)
    if !skipped.isEmpty { print("nucleus-count: skipped \(skipped.joined(separator: "; "))") }
    let clips = prepared.map(\.clip)
    try NucleusCountGrid.validate(clips, split: split)

    var all: [NucleusCountGrid.Metrics] = []
    for point in points {
        all.append(NucleusCountGrid.metrics(
            point: point, clips: clips, outcomes: countOutcomes(prepared, thresholds: point.applied(to: base))))
    }
    let chosen = NucleusCountGrid.choose(all, voicedWithinMs: voicedWithin)
    let feasible = all.count(where: \.feasible)

    let identity = try reportIdentity(root: root, corpusManifestHash: "", labelHash: "",
                                      splitPath: "fixtures/splits/vctk.json", splitSeed: split.foldSeed)
    let report = NucleusCountReport(
        generatedAt: ISO8601DateFormatter().string(from: Date()), identity: identity,
        speakers: Array(Set(clips.map(\.speaker))).sorted(), clips: clips.count,
        comparableWords: all.first?.words ?? 0, voicedWithinMs: voicedWithin,
        timestampCheck: lag == "real" ? "REAL PYIN LAG (tracker unchanged; voicedWithinMs ∈ {0, 30, 60})"
            : "OFFSET BUG fixed (voicedWithinMs ∈ {0, 30})",
        reducedFormsSHA256: reduced.sha256, reducedFormsEntries: reduced.entries.count, points: all,
        feasible: feasible, chosen: chosen?.point, closest: chosen == nil ? NucleusCountGrid.closest(all) : nil)
    let markdown = nucleusCountMarkdown(report)
    print(markdown)
    if args.flag("write-report") {
        let directory = root.appendingPathComponent(ReportHashes.reportsPrefix)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try (encoder.encode(report) + Data("\n".utf8))
            .write(to: directory.appendingPathComponent(report.baseName + ".json"))
        try markdown.write(to: directory.appendingPathComponent(report.baseName + ".md"), atomically: true, encoding: .utf8)
        print("nucleus-count: wrote \(ReportHashes.reportsPrefix)\(report.baseName).{json,md}"
              + (identity.cleanTree ? "" : " (dirty tree: not a report of record)"))
    }
    if let path = args.value("tuning-log") {
        try nucleusCountTuningLog(report).write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        print("nucleus-count: tuning-log entry → \(path)")
    }
    if let chosen {
        print("nucleus-count: chosen \(chosen.point) (count-match \(pct(chosen.countMatchRate)), vowel-inside "
              + "\(pct(chosen.vowelInsideShare)), IoU \(String(format: "%.3f", chosen.medianIoU))); feasible \(feasible)/\(all.count)")
        return 0
    }
    print("nucleus-count: NO FEASIBLE POINT (0/\(all.count) reach vowel-inside ≥ 90%): nothing changes; go to §6")
    return 2
}

/// Loads each clip once: the envelope, pYIN voicing and the comparable words (MFA-timed, with N_w).
private func prepareCountClips(
    inputs: [CountInput], speakers speakersOf: [String], mfa: URL, selector: PronunciationSelector,
    dictionary: PronouncingDictionary, reduced: ReducedForms, pitch: Thresholds.Pitch
) async throws -> ([PreparedClip], [String]) {
    var prepared: [PreparedClip] = []
    var skipped: [String] = []
    for (input, speaker) in zip(inputs, speakersOf) {
        let file = mfa.appendingPathComponent(speaker).appendingPathComponent(input.clipID + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            skipped.append("\(input.clipID): no MFA output")
            continue
        }
        let tiers = try MFATiers(contentsOf: file)
        let samples = try WhisperKitTimestamper.samples(fromFileAt: URL(fileURLWithPath: input.audio))
        let track = try await PYINTracker(thresholds: pitch).track(samples, sampleRate: 16_000)
        let envelope = NucleusDetector.envelope(samples: samples, sampleRate: 16_000)
        let voiced = NucleusDetector.voicedCells(track, count: envelope.count)

        let phrase = selector.expectedPhrase(for: PhraseText(text: input.transcript, origin: .starter))
        let mfaWords = tiers.words.filter { !$0.label.isEmpty && $0.label != "<eps>" && $0.label != "spn" }
        let match = lcsMatch(phrase.words.map(\.folded), mfaWords.map { WordText.fold($0.label) })
        var words: [NucleusAssigner.Word] = []
        var contexts: [Int] = []
        for (position, expected) in phrase.words.enumerated() {
            guard let m = match[position], let pronunciation = expected.pronunciation,
                  !pronunciation.syllables.isEmpty else { continue }
            let allowed = AllowedSyllableCounts.of(
                word: expected.text, context: pronunciation, dictionary: dictionary, reducedForms: reduced)
            words.append(NucleusAssigner.Word(start: mfaWords[m].start, end: mfaWords[m].end,
                                              syllables: pronunciation.syllables.count, allowed: allowed.counts))
            contexts.append(pronunciation.syllables.count)
        }
        let vowels = tiers.vowels.map { $0.start...$0.end }
        prepared.append(PreparedClip(
            clip: NucleusCountGrid.Clip(clipID: input.clipID, speaker: speaker, vowels: vowels),
            envelope: envelope, voiced: voiced, words: words, contexts: contexts))
    }
    return (prepared, skipped)
}

/// One point's outcomes over the prepared clips.
private func countOutcomes(_ prepared: [PreparedClip], thresholds: Thresholds) -> [NucleusCountGrid.ClipOutcome] {
    let detector = NucleusDetector(thresholds: thresholds)
    return prepared.map { clip -> NucleusCountGrid.ClipOutcome in
        let nuclei = detector.detect(envelope: clip.envelope, voiced: clip.voiced)
        let result = NucleusAssigner.assign(nuclei.map(\.peakTime), to: clip.words, thresholds: thresholds)
        let words = result.words.map {
            NucleusCountGrid.WordOutcome(allowed: $0.allowed ?? [$0.dictionaryCount], available: $0.available,
                                         short: $0.short, nonContextCount: $0.assignedCount != nil)
        }
        let assigned = result.nuclei.compactMap { $0 }.flatMap { $0 }.map {
            NucleusCountGrid.AssignedNucleus(peak: nuclei[$0].peakTime,
                                             region: nuclei[$0].region.start...nuclei[$0].region.end)
        }
        return NucleusCountGrid.ClipOutcome(words: words, nuclei: assigned)
    }
}

/// Spec 26 §5: `am-eval nucleus-count-held-out --inputs <guard/held-out/inputs.json> --mfa <…/aligned> --out <json>`.
/// Count-match and vowel-inside on the held-out VCTK speakers at the head's nucleus values only. Reported in the
/// nucleus-jitter report, never used to choose: it evaluates one point (the committed one) and chooses nothing.
func nucleusCountHeldOut(_ args: Arguments, root: URL) async throws -> Int32 {
    let split = try JSONDecoder().decode(
        VCTKSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/splits/vctk.json")))
    let inputs = try JSONDecoder().decode([CountInput].self, from: Data(contentsOf: try args.url("inputs")))
    let speakersOf = inputs.map { String($0.clipID.prefix { $0 != "_" }) }
    let heldOut = Set(split.heldOut)
    guard speakersOf.allSatisfy(heldOut.contains) else {
        throw CLIError.failed("nucleus-count-held-out reads held-out speakers only")
    }
    let (prepared, skipped) = try await prepareCountClips(
        inputs: inputs, speakers: speakersOf, mfa: try args.url("mfa"), selector: try .bundled(),
        dictionary: try .bundled(), reduced: try .bundled(), pitch: Thresholds.current.pitch)
    if !skipped.isEmpty { print("nucleus-count-held-out: skipped \(skipped.joined(separator: "; "))") }
    let point = NucleusCountGrid.Point(
        minProminenceDB: Thresholds.current.nucleus.minProminenceDB, minSeparationMs: Thresholds.current.nucleus.minSeparationMs,
        regionDropDB: Thresholds.current.nucleus.regionDropDB, voicedWithinMs: Thresholds.current.nucleus.voicedWithinMs)
    let m = NucleusCountGrid.metrics(point: point, clips: prepared.map(\.clip),
                                     outcomes: countOutcomes(prepared, thresholds: .current))
    let out = HeldOutDetection(
        speakers: Set(prepared.map(\.clip.speaker)).count, clips: prepared.count, words: m.words,
        countMatched: m.countMatched, assignedPeaks: m.assignedPeaks, peaksInsideVowel: m.peaksInsideVowel,
        medianIoU: m.medianIoU)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(out).write(to: try args.url("out"))
    print(String(format: "nucleus-count-held-out (never used to choose): count-match %d/%d (%.1f%%), vowel-inside %d/%d (%.1f%%), IoU %.3f",
                 m.countMatched, m.words, m.countMatchRate * 100, m.peaksInsideVowel, m.assignedPeaks,
                 m.vowelInsideShare * 100, m.medianIoU))
    return 0
}

private func pct(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

private func row(_ m: NucleusCountGrid.Metrics, chosen: NucleusCountGrid.Point?) -> String {
    let p = m.point
    return String(format: "| %.1f | %.0f | %.0f | %.0f | %d/%d (%.1f%%) | %d/%d (%.1f%%) | %.3f | %d | %d | %@ |",
                  p.minProminenceDB, p.minSeparationMs, p.regionDropDB, p.voicedWithinMs, m.countMatched, m.words,
                  m.countMatchRate * 100, m.peaksInsideVowel, m.assignedPeaks, m.vowelInsideShare * 100, m.medianIoU,
                  m.short, m.nonContextCounts, (m.feasible ? "yes" : "no") + (p == chosen ? " **chosen**" : ""))
}

func nucleusCountMarkdown(_ report: NucleusCountReport) -> String {
    var lines: [String] = []
    lines.append("# Nucleus count grid (spec 26 §1): \(report.baseName)")
    lines.append("")
    lines.append("- Generated: \(report.generatedAt); commit `\(report.identity.evaluatedCommit)`"
                 + (report.identity.cleanTree ? "" : " (dirty tree: not a report of record)"))
    lines.append("- configDigest `\(report.identity.configDigest)`, sourceTreeHash `\(report.identity.sourceTreeHash)`")
    lines.append("- Data: VCTK **tuning** speakers only (\(report.speakers.count): \(report.speakers.joined(separator: ", "))), "
                 + "\(report.clips) clips, \(report.comparableWords) comparable words (MFA word boundaries, present words with ≥ 1 syllable). "
                 + "Detection only: no verdict, flip, gate or held-out number is read.")
    lines.append("- §1a timestamp check: \(report.timestampCheck)")
    lines.append("- Reduced forms: \(report.reducedFormsEntries) entries, SHA-256 `\(report.reducedFormsSHA256)` (frozen before this run)")
    lines.append("- Grid (pre-declared): minProminenceDB \(NucleusCountGrid.minProminenceDB), minSeparationMs \(NucleusCountGrid.minSeparationMs), "
                 + "regionDropDB \(NucleusCountGrid.regionDropDB), voicedWithinMs \(report.voicedWithinMs): \(report.points.count) points. "
                 + "Fixed: minPeakDBFS −45, skipCostMs 60, windowMs 30.")
    lines.append("- Objective: count-match rate (P ∈ N_w, not nucleus-short). Floor: vowel-inside share ≥ 90% (assigned peaks "
                 + "inside an MFA vowel ±10 ms). Tie-breaks: vowel-inside, median region–vowel IoU, fewest grid steps from spec 25's values.")
    lines.append("")
    if let chosen = report.chosen, let m = report.points.first(where: { $0.point == chosen }) {
        lines.append("**Chosen:** \(chosen) — count-match \(pct(m.countMatchRate)) (\(m.countMatched)/\(m.words)), vowel-inside "
                     + "\(pct(m.vowelInsideShare)) (\(m.peaksInsideVowel)/\(m.assignedPeaks)), median IoU \(String(format: "%.3f", m.medianIoU)). "
                     + "Feasible points: \(report.feasible)/\(report.points.count).")
    } else {
        lines.append("**No feasible point** (0/\(report.points.count)): nothing changes; the build goes to §6. Closest points:")
        lines.append("")
        lines.append("| prom dB | sep ms | drop dB | voiced ±ms | count-match | vowel-inside | IoU | short | non-context | feasible |")
        lines.append("|---|---|---|---|---|---|---|---|---|---|")
        for m in report.closest ?? [] { lines.append(row(m, chosen: nil)) }
    }
    lines.append("")
    lines.append("## Every point")
    lines.append("")
    lines.append("| prom dB | sep ms | drop dB | voiced ±ms | count-match | vowel-inside | IoU | short | non-context | feasible |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for m in report.points { lines.append(row(m, chosen: report.chosen)) }
    lines.append("")
    return lines.joined(separator: "\n")
}

func nucleusCountTuningLog(_ report: NucleusCountReport) -> String {
    var lines: [String] = []
    let date = String(report.generatedAt.prefix(10))
    lines.append("### \(date): spec 26 nucleus count grid (`nucleus.*`), report `\(report.baseName)`")
    lines.append("")
    lines.append("- Commit `\(report.identity.evaluatedCommit.prefix(12))`, configDigest before `\(report.identity.configDigest.prefix(8))`; "
                 + "data: VCTK tuning speakers only (\(report.speakers.count) speakers, \(report.clips) clips, \(report.comparableWords) comparable words); detection only.")
    lines.append("- §1a: \(report.timestampCheck).")
    lines.append("- Grid: minProminenceDB \(NucleusCountGrid.minProminenceDB) × minSeparationMs \(NucleusCountGrid.minSeparationMs) × "
                 + "regionDropDB \(NucleusCountGrid.regionDropDB) × voicedWithinMs \(report.voicedWithinMs) = \(report.points.count) points.")
    lines.append("- Reduced forms: `reduced-forms.json` SHA-256 `\(report.reducedFormsSHA256)` (\(report.reducedFormsEntries) entries).")
    if let chosen = report.chosen, let m = report.points.first(where: { $0.point == chosen }) {
        lines.append("- Feasible: \(report.feasible)/\(report.points.count). Chosen: \(chosen); count-match \(pct(m.countMatchRate)), "
                     + "vowel-inside \(pct(m.vowelInsideShare)), median IoU \(String(format: "%.3f", m.medianIoU)).")
    } else {
        lines.append("- Feasible: 0/\(report.points.count). Nothing changes (spec 26 §1); §6 applies.")
    }
    lines.append("")
    lines.append("| prom dB | sep ms | drop dB | voiced ±ms | count-match | vowel-inside | IoU | short | non-context | feasible |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for m in report.points { lines.append(row(m, chosen: report.chosen)) }
    lines.append("")
    return lines.joined(separator: "\n")
}

/// Spec 26 §5: `am-eval thresholds-json --spec25-nucleus --out <json>`: the head's thresholds with spec 25's nucleus
/// values (3 dB, 70 ms, 6 dB, voiced frame only) and no ambiguity check (`ambiguityEdgeMs` 0), for
/// `am-timestamps spec11-guard --thresholds … --context-counts-only` (spec 25's `.nucleus`, recomputed).
func thresholdsJSON(_ args: Arguments) throws -> Int32 {
    var thresholds = Thresholds.current
    if args.flag("spec25-nucleus") {
        let initial = NucleusCountGrid.initial
        thresholds = initial.applied(to: thresholds)
        thresholds.nucleus.ambiguityEdgeMs = 0
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(thresholds).write(to: try args.url("out"))
    return 0
}
