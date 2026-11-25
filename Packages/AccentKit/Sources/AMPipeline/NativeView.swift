// The native side of a phrase with no take of yours (addendum v3.2 W1): the selected voice's words, syllables and
// prominence, the band over every native reader, the pitch axis and the native description. It reads the stored
// native analyses only (nothing is computed from audio) and uses the same paths `Analyzer` and `ResultAssembly` use
// for the model, scoring off, so the pre-take strip and pitch card match what a result later draws.

import AMCore
import AMLibrary
import AMPitch
import AMProsody
import AMWarp
import Foundation

/// The selected native voice as the strip and the pitch card draw it before your first take.
public struct NativeDisplay: Sendable, Hashable {
    public let phraseID: PhraseID
    /// The selected voice's recording.
    public let recordingID: RecordingID
    /// The selected native take on its own timeline, stress context-resolved (spec 28 §4, scoring off).
    public let model: SpeakerAnalysis
    /// The model's first present word's start to its last's end, as `AnalysisResult.modelAxis`.
    public let modelAxis: TimeRange
    /// The native band (P10 to P90) on the selected voice's timeline.
    public let nativeBand: [BandPoint]
    /// The chart's vertical extent, as `AnalysisResult.pitchAxis` with no take of yours.
    public let pitchAxis: ClosedRange<Double>
    /// The native range of the descriptive measures (spec 28 §4a): no You.
    public let native: NativeDescription
}

public enum NativeView {
    /// The display for `selected`, with `others` (every other native reader of the phrase) warped onto it.
    /// Throws `PairScoring.Failure.modelIncomplete` when the selected take misses a phrase word.
    public static func display(
        phrase: PhraseInput, recording: RecordingID, selected: TakeProsody, selectedSHA256: String,
        others: [(prosody: TakeProsody, sha256: String)], thresholds: Thresholds = .current
    ) throws -> NativeDisplay {
        let selfWarp = try PairScoring.warp(you: selected, model: selected, words: phrase.words, thresholds: thresholds)
        let warped = others.compactMap { other -> (prosody: TakeProsody, sha256: String, warp: TimeWarp)? in
            guard let warp = try? PairScoring.warp(
                you: other.prosody, model: selected, words: phrase.words, thresholds: thresholds)
            else { return nil }
            return (other.prosody, other.sha256, warp)
        }
        let band = try NativeBand(
            selected: NativeVoice(sha256: selectedSHA256, track: selected.pitch),
            others: warped.map {
                WarpedVoice(voice: NativeVoice(sha256: $0.sha256, track: $0.prosody.pitch), ontoSelected: $0.warp)
            },
            testTake: nil, hopSeconds: selected.pitch.hopSeconds, thresholds: thresholds.band)

        let present = Dictionary(
            selected.segmentation.words.filter { $0.kind == .present }.map { ($0.phraseWord, $0) },
            uniquingKeysWith: { first, _ in first })
        let entries = phrase.words.compactMap { word in
            present[word.index].map {
                ResultAssembly.Entry(
                    text: word.text, range: $0.range, syllables: $0.syllables, expected: word.expectedStress)
            }
        }
        guard let first = entries.first, let last = entries.last else {
            throw PairScoring.Failure.modelIncomplete(phrase.words.map(\.index))
        }
        let model = ResultAssembly.speaker(
            entries, analysis: selected, measured: [:], mode: .off, thresholds: thresholds)
        let native = NativeDescription(
            [ProsodyDescription.speaker(selected, warp: selfWarp, thresholds: thresholds)]
                + warped.map { ProsodyDescription.speaker($0.prosody, warp: $0.warp, thresholds: thresholds) })
        return NativeDisplay(
            phraseID: phrase.id, recordingID: recording, model: model,
            modelAxis: try TimeRange(start: first.range.start, end: max(first.range.start, last.range.end)),
            nativeBand: band.points,
            pitchAxis: PitchAxis.extent(previous: nil, segments: selected.pitch.segments, thresholds: thresholds.pitch),
            native: native)
    }

    /// Reads `phrase`'s natives from `reference` with the key checks `Analyzer` uses (audio SHA-256, pronunciation
    /// hash, algorithm version), then `display` on `voice`. Throws `ReferenceLoadError` (a recording still corrupt
    /// after its one rebuild), `PairScoring.Failure`, `CancellationError`, or `ReferenceLoadError.notFound(voice)`
    /// when the voice has no usable analysis.
    public static func load(
        phrase: PhraseInput, voice: RecordingID, reference: any ReferenceSet, thresholds: Thresholds = .current
    ) async throws -> NativeDisplay {
        let natives = try await reference.loadNatives(phrase: phrase.id) {
            recording -> (recording: NativeRecording, analysis: NativeAnalysis)? in
            guard let native = DerivedCoding.native(in: recording.analysis),
                native.l1.key.l0.takeAudioSHA256 == recording.audioSHA256,
                native.l1.key.pronunciationHash == phrase.pronunciationHash,
                native.l1.key.algorithmVersion == Versions.algorithmVersion
            else { return nil }
            return (recording, native)
        }
        guard let selected = natives.first(where: { $0.recording.id == voice }) else {
            throw ReferenceLoadError.notFound(voice)
        }
        return try display(
            phrase: phrase, recording: voice, selected: selected.analysis.l1.analysis,
            selectedSHA256: selected.recording.audioSHA256,
            others: natives.filter { $0.recording.id != voice }.map {
                (prosody: $0.analysis.l1.analysis, sha256: $0.recording.audioSHA256)
            },
            thresholds: thresholds)
    }
}
