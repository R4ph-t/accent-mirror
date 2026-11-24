// Spec 26 §1a: `am-eval timestamp-check --inputs <guard/tuning/inputs.json> --mfa <mfa-work/aligned> [--per-speaker 20]
// [--out <json>]`. Measures where spec 04's `PYINTracker` (and spec 05's ACF voicing) put voicing onsets against known
// onsets: spec 25's pulse train (the segmenter tests' 3 s train, rebuilt here), a hard-onset harmonic carrier (onset
// type control), and about 20 MFA vowel onsets per VCTK **tuning** speaker (vowels after silence or a voiceless
// obstruent, where voicing starts with the vowel). Prints signed offsets (detected − true): median and 90th percentile,
// per onset type. Detection-only and tuning speakers only; reads no verdict.

import AMAlignment
import AMCapture
import AMCore
import AMEvaluation
import AMPitch
import AMProsody
import Foundation

private struct TimestampInput: Decodable {
    let clipID: String
    let audio: String
}

/// Per 10 ms cell: voiced in the pYIN track (what `NucleusDetector` reads) and in ACF voicing.
private func voicing(_ samples: [Float]) async throws -> (pyin: [Bool], acf: [Bool]) {
    let track = try await PYINTracker().track(samples, sampleRate: 16_000)
    let count = (samples.count + 159) / 160
    let pyin = NucleusDetector.voicedCells(track, count: count)
    var acf = ACFVoicing().voicedFrames(samples: samples, sampleRate: 16_000)
    if acf.count < count { acf += [Bool](repeating: false, count: count - acf.count) }
    return (pyin, Array(acf.prefix(count)))
}

/// Signed onset offset (s): the first voiced cell centre in [onset − lookBack, limit] minus `onset`. Nil when the
/// first cell of that window is already voiced (voicing didn't start here) or nothing is voiced in it.
private func onsetOffset(_ voiced: [Bool], onset: Double, limit: Double, lookBack: Double = 0.06) -> Double? {
    let first = max(0, Int(((onset - lookBack) / 0.01).rounded(.down)))
    let last = min(voiced.count - 1, Int((limit / 0.01).rounded(.down)))
    guard first <= last, !voiced[first] else { return nil }
    guard let cell = (first...last).first(where: { voiced[$0] }) else { return nil }
    return (Double(cell) + 0.5) * 0.01 - onset
}

private struct OffsetStats: Encodable {
    let n: Int
    let medianMs: Double?
    let p10Ms: Double?
    let p90Ms: Double?
    let meanAbsMs: Double?

    init(_ values: [Double]) {
        let sorted = values.map { $0 * 1000 }.sorted()
        n = sorted.count
        medianMs = sorted.isEmpty ? nil : Statistics.quantile(sorted, 0.5)
        p10Ms = sorted.isEmpty ? nil : Statistics.quantile(sorted, 0.1)
        p90Ms = sorted.isEmpty ? nil : Statistics.quantile(sorted, 0.9)
        meanAbsMs = sorted.isEmpty ? nil : sorted.map(abs).reduce(0, +) / Double(sorted.count)
    }

    var text: String {
        guard n > 0 else { return "n 0" }
        return String(format: "n %d, median %+.0f ms, p10 %+.0f ms, p90 %+.0f ms", n, medianMs!, p10Ms!, p90Ms!)
    }
}

/// The segmenter tests' pulse train (spec 07/25): 120 Hz, five harmonics, a raised-cosine bump per syllable.
private func pulseTrain() -> (samples: [Float], onsets: [Double]) {
    let words: [[Double]] = [[0.10, 0.30, 0.55], [0.55, 0.70], [0.70, 0.88, 1.10, 1.25, 1.45], [1.65, 1.85, 2.05],
                             [2.15, 2.35, 2.70]]
    let rate = 16_000.0
    var samples = [Float](repeating: 0, count: Int(3.0 * rate))
    for edges in words {
        for index in Int(edges.first! * rate)..<Int(edges.last! * rate) {
            let time = Double(index) / rate
            let syllable = min(max(0, (edges.lastIndex { $0 <= time } ?? 0)), edges.count - 2)
            let phase = (time - edges[syllable]) / (edges[syllable + 1] - edges[syllable])
            let amplitude = 0.5 - 0.5 * cos(2 * .pi * phase)
            let carrier = (1...5).reduce(0.0) { $0 + sin(2 * .pi * 120 * Double($1) * time) / Double($1) }
            samples[index] = Float(0.25 * amplitude * carrier)
        }
    }
    // Voicing starts after silence at the start of "record", "lesson" and "today".
    return (samples, [0.10, 1.65, 2.15])
}

/// The same carrier at a constant level, switched on and off hard: an onset with no amplitude ramp.
private func hardOnsets() -> (samples: [Float], onsets: [Double]) {
    let rate = 16_000.0
    let segments: [(Double, Double)] = [(0.30, 0.60), (1.00, 1.40), (1.80, 2.30), (2.705, 2.95)]
    var samples = [Float](repeating: 0, count: Int(3.2 * rate))
    for (start, end) in segments {
        for index in Int(start * rate)..<Int(end * rate) {
            let time = Double(index) / rate
            let carrier = (1...5).reduce(0.0) { $0 + sin(2 * .pi * 120 * Double($1) * time) / Double($1) }
            samples[index] = Float(0.25 * carrier)
        }
    }
    return (samples, segments.map(\.0))
}

func timestampCheck(_ args: Arguments, root: URL) async throws -> Int32 {
    let perSpeaker = Int(args.value("per-speaker") ?? "20") ?? 20
    let split = try JSONDecoder().decode(
        VCTKSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/splits/vctk.json")))
    let tuning = Set(split.tuning)
    var lines: [String] = []
    func say(_ text: String) {
        print(text)
        lines.append(text)
    }

    // Synthetic onsets.
    var synthetic: [String: [String: [Double]]] = [:]
    for (name, signal) in [("pulse-train", pulseTrain()), ("hard-onset", hardOnsets())] {
        let (pyin, acf) = try await voicing(signal.samples)
        let p = signal.onsets.compactMap { onsetOffset(pyin, onset: $0, limit: $0 + 0.2) }
        let a = signal.onsets.compactMap { onsetOffset(acf, onset: $0, limit: $0 + 0.2) }
        synthetic[name] = ["pyin": p, "acf": a]
        say("\(name): pYIN offsets (ms) \(p.map { String(format: "%+.0f", $0 * 1000) }.joined(separator: " ")); "
            + "ACF \(a.map { String(format: "%+.0f", $0 * 1000) }.joined(separator: " "))")
    }

    // VCTK tuning vowel onsets.
    let inputs = try JSONDecoder().decode([TimestampInput].self, from: Data(contentsOf: try args.url("inputs")))
    let mfa = try args.url("mfa")
    var taken: [String: Int] = [:]
    var pyinBy: [MFAPhoneClass.OnsetType: [Double]] = [:]
    var acfBy: [MFAPhoneClass.OnsetType: [Double]] = [:]
    var paired: [Double] = []
    var perSpeakerPYIN: [String: [Double]] = [:]
    var missed = (pyin: 0, acf: 0)
    for input in inputs {
        let speaker = String(input.clipID.prefix { $0 != "_" })
        guard tuning.contains(speaker) else {
            throw CLIError.failed("timestamp-check reads tuning speakers only; \(input.clipID) is not one")
        }
        guard taken[speaker, default: 0] < perSpeaker else { continue }
        let file = mfa.appendingPathComponent(speaker).appendingPathComponent(input.clipID + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { continue }
        let tiers = try MFATiers(contentsOf: file)
        let samples = try WhisperKitTimestamper.samples(fromFileAt: URL(fileURLWithPath: input.audio))
        let (pyin, acf) = try await voicing(samples)
        for (index, phone) in tiers.phones.enumerated() where MFAPhoneClass.isVowel(phone.label) {
            guard taken[speaker, default: 0] < perSpeaker else { break }
            guard let type = MFAPhoneClass.onsetType(previous: index > 0 ? tiers.phones[index - 1] : nil, vowel: phone)
            else { continue }
            let p = onsetOffset(pyin, onset: phone.start, limit: phone.end)
            let a = onsetOffset(acf, onset: phone.start, limit: phone.end)
            if p == nil { missed.pyin += 1 }
            if a == nil { missed.acf += 1 }
            guard let p, let a else { continue }
            taken[speaker, default: 0] += 1
            pyinBy[type, default: []].append(p)
            acfBy[type, default: []].append(a)
            paired.append(p - a)
            perSpeakerPYIN[speaker, default: []].append(p)
        }
    }
    let speakers = taken.filter { $0.value > 0 }.keys.sorted()
    let allPYIN = pyinBy.values.flatMap { $0 }, allACF = acfBy.values.flatMap { $0 }
    say("VCTK tuning: \(speakers.count) speakers, \(allPYIN.count) vowel onsets (≤ \(perSpeaker) per speaker; "
        + "skipped: pYIN \(missed.pyin), ACF \(missed.acf) with voicing already on or none in the vowel)")
    say("  pYIN − MFA vowel start: \(OffsetStats(allPYIN).text)")
    say("  ACF  − MFA vowel start: \(OffsetStats(allACF).text)")
    say("  pYIN − ACF (paired):    \(OffsetStats(paired).text)")
    for type in MFAPhoneClass.OnsetType.allCases {
        say("  after \(type.rawValue): pYIN \(OffsetStats(pyinBy[type] ?? []).text); ACF \(OffsetStats(acfBy[type] ?? []).text)")
    }
    let speakerMedians = speakers.map { Statistics.quantile((perSpeakerPYIN[$0] ?? []).sorted(), 0.5) * 1000 }.sorted()
    if !speakerMedians.isEmpty {
        say(String(format: "  per-speaker pYIN medians: min %+.0f, median %+.0f, max %+.0f ms", speakerMedians.first!,
                   Statistics.quantile(speakerMedians, 0.5), speakerMedians.last!))
    }

    if let out = args.value("out") {
        struct Output: Encodable {
            let synthetic: [String: [String: OffsetStats]]
            let speakers: [String]
            let pyin: OffsetStats, acf: OffsetStats, paired: OffsetStats
            let pyinByOnset: [String: OffsetStats], acfByOnset: [String: OffsetStats]
            let lines: [String]
        }
        let output = Output(
            synthetic: synthetic.mapValues { $0.mapValues(OffsetStats.init) }, speakers: speakers,
            pyin: OffsetStats(allPYIN), acf: OffsetStats(allACF), paired: OffsetStats(paired),
            pyinByOnset: Dictionary(uniqueKeysWithValues: pyinBy.map { ($0.key.rawValue, OffsetStats($0.value)) }),
            acfByOnset: Dictionary(uniqueKeysWithValues: acfBy.map { ($0.key.rawValue, OffsetStats($0.value)) }),
            lines: lines)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(output).write(to: URL(fileURLWithPath: out))
    }
    return 0
}
