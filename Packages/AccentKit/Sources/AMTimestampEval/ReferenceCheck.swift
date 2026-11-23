import AMAlignment
import Foundation

/// The reference sanity check (CTO review of spec 23): how far the MFA baseline itself is from known word boundaries.
/// The eval phrases are synthesised with SSML `<mark>` bookmarks around every word, aligned with the same MFA and
/// models as the baseline, and MFA's word starts and ends are compared with the marks. A labelled line, never a gate.
public struct ReferenceCheck: Codable, Sendable, Equatable {
    /// One side's figures: MFA minus the marker, in ms.
    public struct Side: Codable, Sendable, Equatable {
        public var n: Int
        public var medianAbsErrorMs: Double?
        public var shareWithinTolerance: Double?
        /// Negative: MFA is earlier than the marker.
        public var meanSignedErrorMs: Double?

        public init(signedErrorsMs: [Double], toleranceMs: Double) {
            let absolute = signedErrorsMs.map { microsecond(abs($0)) }
            n = signedErrorsMs.count
            medianAbsErrorMs = Statistics.median(absolute)
            shareWithinTolerance = absolute.isEmpty
                ? nil : Double(absolute.filter { $0 <= toleranceMs }.count) / Double(absolute.count)
            meanSignedErrorMs = signedErrorsMs.isEmpty ? nil : signedErrorsMs.reduce(0, +) / Double(signedErrorsMs.count)
        }
    }

    /// One synthesised phrase: its transcript, the marker spans and MFA's spans.
    public struct Clip: Sendable {
        public var clipID: String
        public var transcript: String
        public var markers: [BaselineWord]
        public var aligned: [BaselineWord]

        public init(clipID: String, transcript: String, markers: [BaselineWord], aligned: [BaselineWord]) {
            self.clipID = clipID
            self.transcript = transcript
            self.markers = markers
            self.aligned = aligned
        }
    }

    public var voice: String
    public var aligner: String
    public var clips: Int
    public var toleranceMs: Double
    /// The marker offsets come in whole synthesiser buffers.
    public var markerResolutionMs: Double
    public var phraseTokens: Int
    public var starts: Side
    /// Every word's end. A word's end marker fires where the next word starts, so a pause after it counts as the
    /// word's and MFA's end looks early there.
    public var ends: Side
    /// Ends of words with no punctuation after them, where the synthesiser rarely pauses.
    public var endsWithoutPunctuation: Side
    /// Words whose two markers did not both come back from the synthesiser.
    public var wordsWithoutMarkers: Int
    public var note: String

    /// Pairs MFA's words and the markers with the transcript's tokens (as the gate pairs ASR and MFA) and measures
    /// MFA minus the marker on each side.
    public static func compare(_ clips: [Clip], voice: String, aligner: String, markerResolutionMs: Double,
                               wordsWithoutMarkers: Int = 0,
                               toleranceMs: Double = TimestampGate.plan.toleranceMs) -> ReferenceCheck {
        let inputs = clips.map { clip in
            ClipInput(clipID: clip.clipID, transcript: clip.transcript,
                      asrWords: clip.aligned.map { WordTimestamp(word: $0.word, start: $0.start, end: $0.end, probability: 1) },
                      baselineWords: clip.markers)
        }
        let (words, coverage) = Evaluation.comparableWords(inputs)
        let starts = words.map { ($0.asr.start - $0.baseline.start) * 1000 }
        let ends = words.map { ($0.asr.end - $0.baseline.end) * 1000 }
        let plainEnds = words.filter { word in
            let last = word.baseline.word.trimmingCharacters(in: .whitespaces).last
            return last.map { $0.isLetter || $0.isNumber || $0 == "'" } ?? true
        }.map { ($0.asr.end - $0.baseline.end) * 1000 }
        return ReferenceCheck(
            voice: voice, aligner: aligner, clips: clips.count, toleranceMs: toleranceMs,
            markerResolutionMs: markerResolutionMs, phraseTokens: coverage.phraseTokens,
            starts: Side(signedErrorsMs: starts, toleranceMs: toleranceMs),
            ends: Side(signedErrorsMs: ends, toleranceMs: toleranceMs),
            endsWithoutPunctuation: Side(signedErrorsMs: plainEnds, toleranceMs: toleranceMs),
            wordsWithoutMarkers: wordsWithoutMarkers,
            note: "Reference sanity check, not a gate: MFA's own error against SSML <mark> bookmarks in synthesised audio of the eval phrases.")
    }

    /// The report's one-line form.
    public var line: String {
        func side(_ s: Side) -> String {
            "median \(fmt(s.medianAbsErrorMs, "%.1f ms")), within \(fmt(toleranceMs, "%.0f ms")) \(fmt(s.shareWithinTolerance.map { $0 * 100 }, "%.1f%%")), mean signed \(fmt(s.meanSignedErrorMs, "%+.1f ms")), n \(s.n)"
        }
        return "Reference sanity check (MFA's own error, **not a gate**): \(aligner) on \(clips) phrases synthesised by `\(voice)`, against SSML `<mark>` bookmarks (marker resolution \(fmt(markerResolutionMs, "%.1f ms"))). Starts: \(side(starts)). Ends: \(side(ends)). Ends of words with no punctuation after them: \(side(endsWithoutPunctuation)). Words without both markers: \(wordsWithoutMarkers)."
    }
}

private func fmt(_ value: Double?, _ format: String) -> String {
    value.map { String(format: format, $0) } ?? "–"
}
