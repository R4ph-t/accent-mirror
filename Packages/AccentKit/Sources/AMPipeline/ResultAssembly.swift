// The analysed result (spec 01's `AnalysisResult`) from the stages' outputs: both speakers on their own timelines,
// your take on model time, the band, and spec 10's measures and verdict. Nothing is computed from audio here.

import AMCore
import AMPitch
import AMProsody
import AMScoring
import AMWarp
import Foundation

enum ResultAssembly {
    /// One word on a speaker's timeline and its syllables (none for a substituted or inserted word).
    struct Entry {
        let text: String
        let range: TimeRange
        let syllables: [SegmentedSyllable]
    }

    static func result(
        take: TakeAudio, phrase: PhraseInput, you: PlacementAnalysis, model: PlacementAnalysis, scoring: Scoring,
        warp: TimeWarp, band: NativeBand, verdict: Verdict, identity: AnalysisIdentity, thresholds: Thresholds
    ) throws -> AnalysisResult {
        let modelWords = Dictionary(
            model.segmentation.words.filter { $0.kind == .present }.map { ($0.phraseWord, $0) },
            uniquingKeysWith: { first, _ in first })
        let modelEntries = phrase.words.compactMap { word in
            modelWords[word.index].map { Entry(text: word.text, range: $0.range, syllables: $0.syllables) }
        }
        let yourWords = Dictionary(
            you.segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { first, _ in first })
        let text = Dictionary(phrase.words.map { ($0.index, $0.text) }, uniquingKeysWith: { first, _ in first })
        let yourEntries = you.alignment.pairs.compactMap { pair -> Entry? in
            switch pair {
            case .present(let w, let range):
                let segmented = yourWords[w].flatMap { $0.kind == .present ? $0 : nil }
                return Entry(
                    text: text[w] ?? "", range: segmented?.range ?? range, syllables: segmented?.syllables ?? [])
            case .substituted(let w, let heard, let range):
                return Entry(text: heard, range: yourWords[w]?.range ?? range, syllables: [])
            case .inserted(let heard, let range, _):
                return Entry(text: heard, range: range, syllables: [])
            case .missing:
                return nil
            }
        }
        let modelSpeaker = speaker(modelEntries, analysis: model, thresholds: thresholds)
        guard let first = modelEntries.first, let last = modelEntries.last else {
            throw PairScoring.Failure.modelIncomplete(phrase.words.map(\.index))
        }
        return AnalysisResult(
            phraseID: phrase.id, takeID: take.takeID, recordedAt: take.recordedAt, model: modelSpeaker,
            you: speaker(yourEntries, analysis: you, thresholds: thresholds),
            modelAxis: try TimeRange(start: first.range.start, end: max(first.range.start, last.range.end)),
            alignment: you.alignment, timeMap: warp.map, youPitchOnModel: scoring.youPitchOnModel,
            nativeBand: band.points,
            pitchAxis: PitchAxis.extent(
                previous: nil, segments: model.pitch.segments + scoring.youPitchOnModel, thresholds: thresholds.pitch),
            timing: scoring.timing, stress: scoring.stress, measures: scoring.measures.states,
            applicability: scoring.applicability, verdict: verdict, identity: identity)
    }

    /// One speaker's words and syllables. A syllable's stress is measured where the word's observed stress is at
    /// medium confidence or above (spec 08), else the dictionary's.
    static func speaker(_ entries: [Entry], analysis: PlacementAnalysis, thresholds: Thresholds) -> SpeakerAnalysis {
        let prominence = TakeProminence(
            ComparableSyllable.all(in: analysis.segmentation, pitch: analysis.pitch, thresholds: thresholds.prominence),
            thresholds: thresholds.prominence)
        var display: [WordIndex: [Int: Double]] = [:]
        if let prominence {
            for (i, syllable) in prominence.syllables.enumerated() {
                display[syllable.word, default: [:]][syllable.indexInWord] = prominence.display[i]
            }
        }
        let observed = Dictionary(
            analysis.words.compactMap { result in
                result.observed.flatMap { $0.confidence >= .medium ? (result.word, $0) : nil }
            }, uniquingKeysWith: { first, _ in first })
        let total = entries.reduce(0) { $0 + $1.range.duration }

        var words: [WordSpan] = []
        var syllables: [SyllableMeasure] = []
        for (k, entry) in entries.enumerated() {
            var indices: [Int] = []
            for syllable in entry.syllables {
                let measured = observed[syllable.phraseWord]
                let stress: SyllableStress = measured.map { o in
                    syllable.indexInWord == o.primary ? .primary : syllable.indexInWord == o.secondary ? .secondary : .unstressed
                } ?? syllable.stress
                indices.append(syllables.count)
                syllables.append(SyllableMeasure(
                    text: syllable.phones.joined(separator: " "), wordIndex: k, indexInWord: syllable.indexInWord,
                    range: syllable.range, share: total > 0 ? syllable.range.duration / total : 0,
                    prominence: display[syllable.phraseWord]?[syllable.indexInWord] ?? 0, stress: stress,
                    stressSource: measured == nil ? .dictionary : .measured))
            }
            words.append(WordSpan(text: entry.text, range: entry.range, syllables: indices))
        }
        return SpeakerAnalysis(
            words: words, syllables: syllables, pitch: analysis.pitch.segments, medianF0Hz: analysis.pitch.medianF0Hz)
    }
}
