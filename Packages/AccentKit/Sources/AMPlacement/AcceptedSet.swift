// The contextual accepted set A(w) and the matched-pattern S and U sets (spec 08, plan §3.3).
//
// A(w) = {the primary of the context-compatible pronunciation (spec 06: the override, or the POS-selected persisted
// variant)} ∪ {the high-confidence observed primaries of native readers of this phrase}. Other CMUdict variants are
// never accepted. The take's own speaker is never a native reader of its own A(w) (held-out isolation, spec 02).

import AMAlignment
import AMCore
import Foundation

/// A native reader's observed stress on one word: a bundled voice of this phrase, or in evaluation a tuning speaker.
public struct NativeReading: Sendable, Hashable {
    public let voice: String
    public let observed: ObservedStress

    public init(voice: String, observed: ObservedStress) {
        self.voice = voice
        self.observed = observed
    }
}

/// A(w) for one word, with what S and U each accepted pattern gives.
public struct WordAcceptedSet: Sendable, Hashable {
    /// One accepted pattern and the stressed syllables it gives.
    public struct Entry: Sendable, Hashable {
        public let pattern: AcceptedPattern
        /// S for this pattern (indices in word); U is every other syllable.
        public let stressed: Set<Int>
    }

    public let word: WordIndex
    public let syllableCount: Int
    /// The context pronunciation first (when it has a primary), then the native readings in the order given.
    public let entries: [Entry]
    /// S from the context pronunciation: its primary and secondary syllables.
    public let contextStressed: Set<Int>

    /// Nil for an `expectedAmbiguous` word or one without a pronunciation: no placement decision, and excluded from
    /// S and U. Native readings below high confidence, of another syllable count, or by `takeSpeaker` are ignored.
    public init?(expected: ExpectedWord, natives: [NativeReading], takeSpeaker: String? = nil) {
        guard let pattern = expected.expectedPattern, !pattern.isEmpty else { return nil }
        word = expected.index
        syllableCount = pattern.count
        contextStressed = Set(pattern.indices.filter { pattern[$0] != .unstressed })
        var entries: [Entry] = []
        if let primary = pattern.firstIndex(of: .primary) {
            entries.append(Entry(
                pattern: AcceptedPattern(primary: primary, source: .contextPronunciation), stressed: contextStressed))
        }
        for native in natives where native.voice != takeSpeaker && native.observed.confidence == .high {
            let observed = native.observed
            guard observed.primary < pattern.count, (observed.secondary ?? 0) < pattern.count else { continue }
            entries.append(Entry(
                pattern: AcceptedPattern(primary: observed.primary, source: .nativeReader(voice: native.voice)),
                stressed: Set([observed.primary] + (observed.secondary.map { [$0] } ?? []))))
        }
        self.entries = entries
    }

    /// A(w): the accepted primaries.
    public var primaries: Set<Int> { Set(entries.map(\.pattern.primary)) }

    /// A(w) without one voice's own reading.
    public func primaries(excludingVoice voice: String) -> Set<Int> {
        Set(entries.filter { $0.pattern.source != .nativeReader(voice: voice) }.map(\.pattern.primary))
    }

    /// The accepted pattern your primary matches, or nil when it is outside A(w). The context pronunciation wins,
    /// then the selected voice, then the other native readers in order.
    public func matched(primary: Int, selectedVoice: String?) -> Entry? {
        ranked(selectedVoice: selectedVoice).first { $0.pattern.primary == primary }
    }

    /// The nearest accepted pattern for a row: closest primary index; ties go to the selected voice, then the
    /// context pronunciation, then the other native readers in order. Nil when A(w) is empty.
    public func nearest(primary: Int, selectedVoice: String?) -> AcceptedPattern? {
        let tieOrder: [Entry] = {
            let voice = entries.filter { selectedVoice != nil && $0.pattern.source == .nativeReader(voice: selectedVoice!) }
            return voice + entries.filter { !voice.contains($0) }
        }()
        return tieOrder.min { abs($0.pattern.primary - primary) < abs($1.pattern.primary - primary) }?.pattern
    }

    /// S and U for this word from the pattern you matched; the context pronunciation when you matched none (or
    /// when the word has no observed stress, such as a monosyllable). The model's contrast uses the same sets.
    public func stressSets(matching entry: Entry?) -> (stressed: Set<Int>, unstressed: Set<Int>) {
        let stressed = entry?.stressed ?? contextStressed
        return (stressed, Set(0..<syllableCount).subtracting(stressed))
    }

    /// The model voice's own observed primary is outside A(w) (built without its own reading) at high confidence:
    /// logged `referenceAnomaly`, and the word gives no diff.
    public func isReferenceAnomaly(model: NativeReading) -> Bool {
        model.observed.confidence == .high && !primaries(excludingVoice: model.voice).contains(model.observed.primary)
    }

    private func ranked(selectedVoice: String?) -> [Entry] {
        let context = entries.filter { $0.pattern.source == .contextPronunciation }
        let voice = entries.filter { selectedVoice != nil && $0.pattern.source == .nativeReader(voice: selectedVoice!) }
        return context + voice + entries.filter { !context.contains($0) && !voice.contains($0) }
    }
}
