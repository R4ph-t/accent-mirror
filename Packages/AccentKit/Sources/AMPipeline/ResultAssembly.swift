// The analysed result (spec 01's `AnalysisResult`) from the stages' outputs: both speakers on their own timelines,
// your take on model time (`TimeWarp.pitchOnModel`), the band, the description, and the scorer's verdict (spec 28:
// `.notScored` when scoring is off). Nothing is computed from audio here.

import AMCore
import AMPitch
import AMProsody
import AMWarp
import Foundation

enum ResultAssembly {
    /// One word on a speaker's timeline and its syllables (none for a substituted or inserted word).
    struct Entry {
        let text: String
        let range: TimeRange
        let syllables: [SegmentedSyllable]
        /// The phrase word's context-resolved pattern; nil for substituted and inserted words.
        let expected: [SyllableStress]?
    }

    static func result(
        take: TakeAudio, phrase: PhraseInput, you: TakeProsody, model: TakeProsody, score: PairScore, mode: ScoringMode,
        warp: TimeWarp, band: NativeBand, describe: DescribedMeasures?, identity: AnalysisIdentity,
        thresholds: Thresholds
    ) throws -> AnalysisResult {
        let expected = Dictionary(phrase.words.map { ($0.index, $0.expectedStress) }, uniquingKeysWith: { first, _ in first })
        let modelWords = Dictionary(
            model.segmentation.words.filter { $0.kind == .present }.map { ($0.phraseWord, $0) },
            uniquingKeysWith: { first, _ in first })
        let modelEntries = phrase.words.compactMap { word in
            modelWords[word.index].map {
                Entry(text: word.text, range: $0.range, syllables: $0.syllables, expected: word.expectedStress)
            }
        }
        let yourWords = Dictionary(
            you.segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { first, _ in first })
        let text = Dictionary(phrase.words.map { ($0.index, $0.text) }, uniquingKeysWith: { first, _ in first })
        let yourEntries = you.alignment.pairs.compactMap { pair -> Entry? in
            switch pair {
            case .present(let w, let range):
                let segmented = yourWords[w].flatMap { $0.kind == .present ? $0 : nil }
                return Entry(
                    text: text[w] ?? "", range: segmented?.range ?? range, syllables: segmented?.syllables ?? [],
                    expected: expected[w] ?? nil)
            case .substituted(let w, let heard, let range):
                return Entry(text: heard, range: yourWords[w]?.range ?? range, syllables: [], expected: nil)
            case .inserted(let heard, let range, _):
                return Entry(text: heard, range: range, syllables: [], expected: nil)
            case .missing:
                return nil
            }
        }
        let modelSpeaker = speaker(
            modelEntries, analysis: model, measured: score.measuredModel, mode: mode, thresholds: thresholds)
        let youPitchOnModel = warp.pitchOnModel(you.pitch.segments, hopSeconds: you.pitch.hopSeconds)
        guard let first = modelEntries.first, let last = modelEntries.last else {
            throw PairScoring.Failure.modelIncomplete(phrase.words.map(\.index))
        }
        return AnalysisResult(
            phraseID: phrase.id, takeID: take.takeID, recordedAt: take.recordedAt, model: modelSpeaker,
            you: speaker(yourEntries, analysis: you, measured: score.measuredYou, mode: mode, thresholds: thresholds),
            modelAxis: try TimeRange(start: first.range.start, end: max(first.range.start, last.range.end)),
            alignment: you.alignment, timeMap: warp.map, youPitchOnModel: youPitchOnModel,
            nativeBand: band.points,
            pitchAxis: PitchAxis.extent(
                previous: nil, segments: model.pitch.segments + youPitchOnModel, thresholds: thresholds.pitch),
            timing: warp.timing, stress: score.stress, measures: score.measures,
            applicability: score.applicability, verdict: score.verdict, identity: identity,
            comparableCoverage: warp.comparableCoverage, describe: describe)
    }

    /// One speaker's words and syllables. Scoring on: a syllable's stress is measured where the scorer measured the
    /// word's observed stress at medium confidence or above (spec 08), else the segmented pronunciation's. Scoring off
    /// (spec 28 §4): never measured; the context-resolved pattern (`expectedStress`), or unstressed when the word is
    /// ambiguous.
    static func speaker(
        _ entries: [Entry], analysis: TakeProsody, measured: [WordIndex: MeasuredWordStress], mode: ScoringMode,
        thresholds: Thresholds
    ) -> SpeakerAnalysis {
        let prominence = TakeProminence(
            ComparableSyllable.all(in: analysis.segmentation, pitch: analysis.pitch, thresholds: thresholds.prominence),
            thresholds: thresholds.prominence)
        var display: [WordIndex: [Int: Double]] = [:]
        if let prominence {
            for (i, syllable) in prominence.syllables.enumerated() {
                display[syllable.word, default: [:]][syllable.indexInWord] = prominence.display[i]
            }
        }
        let observed = mode == .on ? measured : [:]
        let total = entries.reduce(0) { $0 + $1.range.duration }

        var words: [WordSpan] = []
        var syllables: [SyllableMeasure] = []
        for (k, entry) in entries.enumerated() {
            var indices: [Int] = []
            for syllable in entry.syllables {
                let measured = observed[syllable.phraseWord]
                let dictionary: SyllableStress = switch mode {
                case .on: syllable.stress
                case .off: entry.expected.flatMap { $0.indices.contains(syllable.indexInWord) ? $0[syllable.indexInWord] : nil } ?? .unstressed
                }
                let stress: SyllableStress = measured.map { o in
                    syllable.indexInWord == o.primary ? .primary : syllable.indexInWord == o.secondary ? .secondary : .unstressed
                } ?? dictionary
                indices.append(syllables.count)
                syllables.append(SyllableMeasure(
                    text: syllable.phones.joined(separator: " "), wordIndex: k, indexInWord: syllable.indexInWord,
                    range: syllable.range, share: total > 0 ? syllable.range.duration / total : 0,
                    prominence: display[syllable.phraseWord]?[syllable.indexInWord] ?? 0, stress: stress,
                    stressSource: measured == nil ? .dictionary : .measured))
            }
            words.append(WordSpan(text: entry.text, range: entry.range, syllables: indices, expectedStress: entry.expected))
        }
        return SpeakerAnalysis(
            words: words, syllables: syllables, pitch: analysis.pitch.segments, medianF0Hz: analysis.pitch.medianF0Hz)
    }
}
