// The synthetic edited-native negative set (secondary, plan §6.4): VCTK tuning speakers' clear words with stress
// pushed onto another syllable by DSP, so the syllable is known by construction. Magnitudes are calibrated on the
// natives' own stressed-vs-unstressed contrast (P50, P90, 1.5 × P90) and re-measured after the edit. Controls: null
// processing (the DSP at factor 1) and correct boost (the existing primary pushed further), which must show no diff.
// Two DSPs (our TD-PSOLA, Rubber Band) must agree within `agreement.syntheticDSPAgreementMaxPoints`.
// Measures which-syllable accuracy; never tuning, never a main gate. Initial, untuned thresholds.

import AMAlignment
import AMCore
import AMEvaluation
import AMPipeline
import Foundation

/// One stressed-vs-unstressed contrast: F0 rise (semitones), duration ratio and level difference (dB).
public struct StressMagnitude: Sendable, Hashable, Codable {
    public let semitones: Double
    public let durationRatio: Double
    public let gainDB: Double

    public init(semitones: Double, durationRatio: Double, gainDB: Double) {
        self.semitones = semitones
        self.durationRatio = durationRatio
        self.gainDB = gainDB
    }

    public static let null = StressMagnitude(semitones: 0, durationRatio: 1, gainDB: 0)
}

public enum MagnitudeLevel: String, Sendable, Hashable, Codable, CaseIterable {
    case p50 = "native P50"
    case p90 = "native P90"
    case p90x15 = "1.5 × native P90"
}

public enum NativeContrast {
    /// The edit magnitudes from native contrasts measured on tuning speakers: per dimension P50, P90 and 1.5 × P90
    /// (a ratio's excess over 1 is what scales). nil with no contrast.
    public static func magnitudes(_ natives: [StressMagnitude]) -> [MagnitudeLevel: StressMagnitude]? {
        guard !natives.isEmpty else { return nil }
        func q(_ values: [Double], _ p: Double) -> Double { Statistics.quantile(values.sorted(), p) }
        let st = natives.map(\.semitones), dur = natives.map(\.durationRatio), db = natives.map(\.gainDB)
        let p90 = StressMagnitude(semitones: q(st, 0.9), durationRatio: q(dur, 0.9), gainDB: q(db, 0.9))
        return [
            .p50: StressMagnitude(semitones: q(st, 0.5), durationRatio: q(dur, 0.5), gainDB: q(db, 0.5)),
            .p90: p90,
            .p90x15: StressMagnitude(
                semitones: 1.5 * p90.semitones, durationRatio: 1 + 1.5 * (p90.durationRatio - 1),
                gainDB: 1.5 * p90.gainDB),
        ]
    }
}

public enum DSP: String, Sendable, Hashable, Codable, CaseIterable {
    case tdpsola = "TD-PSOLA"
    case rubberband = "Rubber Band"
}

/// One edited (or control) word after re-analysis.
public struct EditedWord: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case edit(MagnitudeLevel)
        case nullControl
        case correctBoost
    }

    public let speaker: TuningSpeaker
    public let phrase: String
    public let word: Int
    public let kind: Kind
    public let dsp: DSP
    /// The syllable the edit pushed (the original primary for the controls).
    public let targetSyllable: Int
    public let observedPrimary: Int?
    /// The edited take shows any placement diff against the original take of the same speaker.
    public let anyDiff: Bool
    /// The F0 shift achieved on the target syllable (semitones), re-measured; nil when unvoiced.
    public let achievedSemitones: Double?

    public init(
        speaker: TuningSpeaker, phrase: String, word: Int, kind: Kind, dsp: DSP, targetSyllable: Int,
        observedPrimary: Int?, anyDiff: Bool, achievedSemitones: Double?
    ) {
        self.speaker = speaker
        self.phrase = phrase
        self.word = word
        self.kind = kind
        self.dsp = dsp
        self.targetSyllable = targetSyllable
        self.observedPrimary = observedPrimary
        self.anyDiff = anyDiff
        self.achievedSemitones = achievedSemitones
    }

    var isEdit: Bool { if case .edit = kind { true } else { false } }
}

public enum NegativeSetMetrics {
    /// Which-syllable accuracy for one DSP: edits whose observed primary is the pushed syllable.
    public static func whichSyllable(_ words: [EditedWord], dsp: DSP, thresholds: Thresholds = .current) -> MetricResult {
        let units = words.filter { $0.dsp == dsp && $0.isEdit }.map {
            ScoredUnit(speaker: $0.speaker.id, phrase: $0.phrase, hit: $0.observedPrimary == $0.targetSyllable)
        }
        return MetricResult.rate(
            name: "Synthetic which-syllable accuracy (\(dsp.rawValue))", layer: .descriptive, units: units,
            gate: .agreement("agreement.whichSyllableAccuracyMin", \.whichSyllableAccuracyMin, .atLeast,
                             thresholds: thresholds),
            minimumN: 1)
    }

    /// Controls (null processing and correct boost) with any diff, for one DSP.
    public static func controls(_ words: [EditedWord], dsp: DSP, thresholds: Thresholds = .current) -> MetricResult {
        let units = words.filter { $0.dsp == dsp && !$0.isEdit }.map {
            ScoredUnit(speaker: $0.speaker.id, phrase: $0.phrase, hit: $0.anyDiff)
        }
        return MetricResult.rate(
            name: "Synthetic controls with a diff (\(dsp.rawValue))", layer: .descriptive, units: units,
            gate: .agreement("agreement.syntheticControlDiffsMax", \.syntheticControlDiffsMax, .atMost,
                             thresholds: thresholds),
            minimumN: 1)
    }

    /// |TD-PSOLA − Rubber Band| which-syllable accuracy; NOT EVALUATED unless both were measured.
    public static func dspAgreement(_ words: [EditedWord], thresholds: Thresholds = .current) -> MetricResult {
        let gate = Gate.agreement(
            "agreement.syntheticDSPAgreementMaxPoints", \.syntheticDSPAgreementMaxPoints, .atMost,
            thresholds: thresholds)
        let a = whichSyllable(words, dsp: .tdpsola, thresholds: thresholds)
        let b = whichSyllable(words, dsp: .rubberband, thresholds: thresholds)
        guard let va = a.value, let vb = b.value else {
            return MetricResult(
                name: "Synthetic DSP agreement (|TD-PSOLA − Rubber Band|)", layer: .descriptive, n: min(a.n, b.n),
                value: nil, gate: gate, status: .notEvaluated(n: min(a.n, b.n), minimum: 1))
        }
        let delta = abs(va - vb)
        return MetricResult(
            name: "Synthetic DSP agreement (|TD-PSOLA − Rubber Band|)", layer: .descriptive, n: min(a.n, b.n),
            value: delta, gate: gate, status: gate.passes(delta) ? .pass : .fail)
    }
}

/// One tuning speaker's take, analysed: what the builder edits.
public struct NativeTake: Sendable {
    public let speaker: TuningSpeaker
    public let phrase: String
    public let samples: [Float]
    public let words: [PlacementTake.Word]
    public let heard: [WordTimestamp]
    public let analysis: PlacementAnalysis

    public init(
        speaker: TuningSpeaker, phrase: String, samples: [Float], words: [PlacementTake.Word], heard: [WordTimestamp],
        analysis: PlacementAnalysis
    ) {
        self.speaker = speaker
        self.phrase = phrase
        self.samples = samples
        self.words = words
        self.heard = heard
        self.analysis = analysis
    }

    /// Clear words: decided, observed primary equal to the expected one at high confidence, every syllable timed.
    public var clearWords: [(index: WordIndex, primary: Int, syllables: [TimeRange])] {
        let segmented = Dictionary(
            analysis.segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { a, _ in a })
        return analysis.words.compactMap { result in
            guard let observed = result.observed, observed.confidence == .high, result.suppression == nil,
                let word = words.first(where: { $0.index == result.word }), let accepted = word.accepted,
                accepted.contains(observed.primary), let segment = segmented[result.word],
                segment.syllables.count == word.pronunciation.syllables.count, segment.syllables.count >= 2
            else { return nil }
            return (result.word, observed.primary, segment.syllables.map(\.range))
        }
    }

    /// The natives' contrast on clear words: primary syllable against the mean of the others.
    public var contrasts: [StressMagnitude] {
        clearWords.compactMap { word in
            let rate = 16_000.0
            func range(_ r: TimeRange) -> Range<Int> {
                max(0, Int(r.start * rate))..<min(samples.count, max(Int(r.start * rate) + 1, Int(r.end * rate)))
            }
            func rms(_ r: Range<Int>) -> Double {
                sqrt(samples[r].reduce(0) { $0 + Double($1 * $1) } / Double(max(r.count, 1)))
            }
            let p = word.syllables[word.primary]
            let others = word.syllables.indices.filter { $0 != word.primary }.map { word.syllables[$0] }
            guard let pf = TDPSOLA.medianF0(samples, region: range(p), sampleRate: rate) else { return nil }
            let of = others.compactMap { TDPSOLA.medianF0(samples, region: range($0), sampleRate: rate) }
            guard !of.isEmpty else { return nil }
            let st = 12 * log2(pf / (of.reduce(0, +) / Double(of.count)))
            let duration = (p.end - p.start) / (others.map { $0.end - $0.start }.reduce(0, +) / Double(others.count))
            let otherRMS = others.map { rms(range($0)) }.reduce(0, +) / Double(others.count)
            let db = 20 * log10(max(rms(range(p)), 1e-9) / max(otherRMS, 1e-9))
            return StressMagnitude(semitones: max(0, st), durationRatio: max(1, duration), gainDB: max(0, db))
        }
    }
}

/// Builds and re-analyses the edited words for one take.
public struct NegativeSetBuilder: Sendable {
    public let magnitudes: [MagnitudeLevel: StressMagnitude]
    public let rubberBand: RubberBandCLI?
    public let scratch: URL
    public let thresholds: Thresholds

    public init(
        magnitudes: [MagnitudeLevel: StressMagnitude], rubberBand: RubberBandCLI?, scratch: URL,
        thresholds: Thresholds = .current
    ) {
        self.magnitudes = magnitudes
        self.rubberBand = rubberBand
        self.scratch = scratch
        self.thresholds = thresholds
    }

    public func edits(of take: NativeTake) async throws -> [EditedWord] {
        let rate = 16_000.0
        var out: [EditedWord] = []
        for word in take.clearWords {
            let target = VerificationSet.movedSyllable(from: word.primary, count: word.syllables.count)
            var jobs: [(EditedWord.Kind, Int, StressMagnitude)] = [
                (.nullControl, word.primary, .null),
                (.correctBoost, word.primary, magnitudes[.p50] ?? .null),
            ]
            for level in MagnitudeLevel.allCases { if let m = magnitudes[level] { jobs.append((.edit(level), target, m)) } }
            for (kind, syllable, magnitude) in jobs {
                let r = word.syllables[syllable]
                let region = Int(r.start * rate)..<min(take.samples.count, Int(r.end * rate))
                guard region.count > 0 else { continue }
                for dsp in DSP.allCases {
                    let edited: [Float]
                    switch dsp {
                    case .tdpsola:
                        edited = TDPSOLA.modify(
                            take.samples, sampleRate: rate, region: region,
                            pitchFactor: pow(2, magnitude.semitones / 12), durationFactor: magnitude.durationRatio,
                            gainDB: magnitude.gainDB)
                    case .rubberband:
                        guard let rubberBand else { continue }
                        edited = try rubberBand.modify(
                            take.samples, sampleRate: rate, region: region, semitones: magnitude.semitones,
                            timeRatio: magnitude.durationRatio, gainDB: magnitude.gainDB, scratch: scratch)
                    }
                    out.append(try await analyse(
                        edited, take: take, word: word.index, kind: kind, dsp: dsp, syllable: syllable,
                        region: region, durationRatio: magnitude.durationRatio))
                }
            }
        }
        return out
    }

    /// Re-analyses an edited take: word timings after the edit shift by the added duration; the original take is the
    /// model (scored through spec 10's path) to see whether any diff shows.
    func analyse(
        _ samples: [Float], take: NativeTake, word: WordIndex, kind: EditedWord.Kind, dsp: DSP, syllable: Int,
        region: Range<Int>, durationRatio: Double
    ) async throws -> EditedWord {
        let rate = 16_000.0
        let added = Double(samples.count - take.samples.count) / rate
        let regionEnd = Double(region.upperBound) / rate
        let heard = take.heard.map { w in
            WordTimestamp(
                word: w.word, start: w.start >= regionEnd ? w.start + added : w.start,
                end: w.end >= regionEnd ? w.end + added : w.end, probability: w.probability)
        }
        let analysis = try await SyntheticScoring.analyse(
            samples: samples, words: take.words, heard: heard, l0Key: "negative-\(UUID().uuidString)",
            thresholds: thresholds)
        let observed = analysis.words.first { $0.word == word }?.observed
        let scoring = try? SyntheticScoring.score(
            words: take.words, you: analysis, reference: take.analysis, voice: take.speaker.id, thresholds: thresholds)
        let anyDiff: Bool = {
            guard let decision = scoring?.decision, case .verdict(.feedback(let rows, _)) = decision else { return false }
            return !rows.isEmpty
        }()
        let editedRegion = region.lowerBound..<min(samples.count, region.lowerBound + Int(Double(region.count) * durationRatio))
        let before = TDPSOLA.medianF0(take.samples, region: region, sampleRate: rate)
        let after = TDPSOLA.medianF0(samples, region: editedRegion, sampleRate: rate)
        return EditedWord(
            speaker: take.speaker, phrase: take.phrase, word: word.rawValue, kind: kind, dsp: dsp,
            targetSyllable: syllable, observedPrimary: observed?.primary, anyDiff: anyDiff,
            achievedSemitones: before.flatMap { b in after.map { 12 * log2($0 / b) } })
    }
}
