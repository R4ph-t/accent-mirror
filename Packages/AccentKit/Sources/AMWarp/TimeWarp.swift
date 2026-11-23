// The partial time map (plan §4.4): built from the word alignment and spec 07's syllable anchors, with `toModel`,
// `toYou`, word playback and loop playback. Monotone piecewise-linear between anchors; never extrapolated beyond a
// 50 ms clamp at the ends and never bridged across a missing or inserted word.

import Foundation
import AMCore

/// One word on one speaker's timeline, as spec 07 segmented it.
public struct TimedWord: Sendable, Hashable {
    /// The reported word edges.
    public let range: TimeRange
    /// The word's dictionary syllables in order; empty for a substituted word, which has edges only.
    public let syllables: [TimeRange]
    /// Spec 07 timing over this word's syllables (share at medium or above against `confidence.timing*`). Poor on
    /// either side means the segment's anchors are Poor and DTW maps time inside it.
    public let timing: TimingLevel

    public init(range: TimeRange, syllables: [TimeRange] = [], timing: TimingLevel) {
        self.range = range
        self.syllables = syllables
        self.timing = timing
    }
}

/// Which timeline a playback request is for.
public enum Speaker: String, Sendable, Hashable, CaseIterable {
    case model, you
}

/// What a loop slice in model time plays: the model slice, and your mapped audio inside it (empty: model only).
public struct LoopPlayback: Sendable, Hashable {
    public let model: TimeRange
    public let you: [TimeRange]
    public var modelOnly: Bool { you.isEmpty }
}

/// Your take mapped onto the selected model voice.
public struct TimeWarp: Sendable, Hashable {
    /// Lookups clamp to the first or last mapped segment for up to this long, then return nil (§4.4).
    public static let edgeClampSeconds = 0.05

    public let map: PartialTimeMap
    /// The model's word spans, by phrase word.
    public let modelWords: [TimeRange]
    /// Comparable model syllables ÷ model syllables (feeds §1.2 step 5).
    public let comparableCoverage: Double
    /// The anchor timing of each mapped segment, by segment index.
    public let anchorTiming: [Int: TimingLevel]
    /// DTW time knots for mapped segments whose anchors are Poor, by segment index. Lookups use them in place of the
    /// anchors; the anchors, syllables and confidences are untouched.
    public let refinements: [Int: [PartialTimeMap.Anchor]]
    /// Take timing: spec 07's level, capped at Rough once DTW maps any segment.
    public let timing: TimingLevel

    public enum BuildError: Error, Equatable {
        /// The alignment names a phrase word with no model word.
        case modelWordMissing(WordIndex)
        /// A present or substituted word has no segmentation on your side.
        case yourWordMissing(WordIndex)
    }

    init(
        map: PartialTimeMap, modelWords: [TimeRange], comparableCoverage: Double, anchorTiming: [Int: TimingLevel],
        refinements: [Int: [PartialTimeMap.Anchor]], timing: TimingLevel
    ) {
        self.map = map
        self.modelWords = modelWords
        self.comparableCoverage = comparableCoverage
        self.anchorTiming = anchorTiming
        self.refinements = refinements
        self.timing = timing
    }

    /// Builds the map: `mapped` for each present word (comparable, anchors at its syllable boundaries) and each
    /// substituted word (not comparable, anchors at its edges), `modelOnly` for a missing word and `youOnly` for an
    /// inserted one, in alignment order (model time, then your time).
    ///
    /// - Parameters:
    ///   - model: the model's words, by phrase word.
    ///   - you: your present and substituted words, by phrase word.
    ///   - timing: your take's spec 07 timing level.
    public init(
        alignment: WordAlignment, model: [TimedWord], you: [WordIndex: TimedWord], timing: TimingLevel
    ) throws {
        func modelWord(_ w: WordIndex) throws -> TimedWord {
            guard model.indices.contains(w.rawValue) else { throw BuildError.modelWordMissing(w) }
            return model[w.rawValue]
        }
        var segments: [PartialTimeMap.Segment] = []
        var anchorTiming: [Int: TimingLevel] = [:]
        var modelEnd = -Double.infinity
        var yourEnd = -Double.infinity
        var comparableSyllables = 0

        for pair in alignment.pairs {
            switch pair {
            case .present(let w, _), .substituted(let w, _, _):
                let m = try modelWord(w)
                guard let y = you[w] else { throw BuildError.yourWordMissing(w) }
                let modelRange = try Self.clamped(m.range, after: modelEnd)
                let yourRange = try Self.clamped(y.range, after: yourEnd)
                let comparable: Bool
                let candidates: [PartialTimeMap.Anchor]
                if case .present = pair {
                    comparable = true
                    comparableSyllables += m.syllables.count
                    candidates = Self.syllableAnchors(model: m, you: y)
                } else {
                    comparable = false
                    candidates = Self.edgeAnchors(model: m.range, you: y.range)
                }
                let anchors = Self.monotone(candidates, inside: modelRange, yourRange)
                anchorTiming[segments.count] = m.timing.rank <= y.timing.rank ? m.timing : y.timing
                segments.append(.mapped(model: modelRange, you: yourRange, anchors: anchors, comparable: comparable))
                modelEnd = modelRange.end
                yourEnd = yourRange.end
            case .missing(let w):
                let range = try Self.clamped(try modelWord(w).range, after: modelEnd)
                segments.append(.modelOnly(model: range))
                modelEnd = range.end
            case .inserted(_, let y, _):
                let range = try Self.clamped(y, after: yourEnd)
                segments.append(.youOnly(you: range))
                yourEnd = range.end
            }
        }
        let modelSyllables = model.reduce(0) { $0 + $1.syllables.count }
        self.init(
            map: try PartialTimeMap(segments: segments), modelWords: model.map(\.range),
            comparableCoverage: modelSyllables > 0 ? Double(comparableSyllables) / Double(modelSyllables) : 0,
            anchorTiming: anchorTiming, refinements: [:], timing: timing)
    }

    /// Anchors at every syllable boundary when both sides have the same syllable count; word edges otherwise.
    static func syllableAnchors(model: TimedWord, you: TimedWord) -> [PartialTimeMap.Anchor] {
        guard !model.syllables.isEmpty, model.syllables.count == you.syllables.count else {
            return edgeAnchors(model: model.range, you: you.range)
        }
        var anchors = zip(model.syllables, you.syllables).map { PartialTimeMap.Anchor(model: $0.start, you: $1.start) }
        if let m = model.syllables.last, let y = you.syllables.last {
            anchors.append(PartialTimeMap.Anchor(model: m.end, you: y.end))
        }
        return anchors
    }

    static func edgeAnchors(model: TimeRange, you: TimeRange) -> [PartialTimeMap.Anchor] {
        [PartialTimeMap.Anchor(model: model.start, you: you.start), PartialTimeMap.Anchor(model: model.end, you: you.end)]
    }

    /// A range moved to start no earlier than `after` (segments never overlap on one timeline).
    static func clamped(_ range: TimeRange, after: Double) throws -> TimeRange {
        let start = max(range.start, after)
        return try TimeRange(start: start, end: max(range.end, start))
    }

    /// The anchors inside both ranges that strictly increase on both timelines, in order.
    static func monotone(
        _ anchors: [PartialTimeMap.Anchor], inside model: TimeRange, _ you: TimeRange
    ) -> [PartialTimeMap.Anchor] {
        var out: [PartialTimeMap.Anchor] = []
        for a in anchors where model.contains(a.model) && you.contains(a.you) {
            if let last = out.last, !(a.model > last.model && a.you > last.you) { continue }
            out.append(a)
        }
        return out
    }

    // MARK: - Lookups

    /// The model time for your time `t`; nil inside an insertion, across any gap, and past the 50 ms end clamp.
    public func toModel(_ t: Double) -> Double? { lookup(t, from: .you) }

    /// Your time for model time `t`; nil inside a missing word, across any gap, and past the 50 ms end clamp.
    public func toYou(_ t: Double) -> Double? { lookup(t, from: .model) }

    /// The span to play for one word on one timeline. The model side is the word's span (nil for an insertion, which
    /// has no model word); your side is your span for a present, substituted or inserted word and nil for a missing
    /// one.
    public func playbackRange(word: AlignedWordPair, speaker: Speaker) -> TimeRange? {
        switch speaker {
        case .model: word.phraseWord.flatMap { modelWords.indices.contains($0.rawValue) ? modelWords[$0.rawValue] : nil }
        case .you: word.yourRange
        }
    }

    /// A loop over `slice` in model time: the union of your mapped ranges inside it. Neighbouring mapped words with no
    /// gap between them join into one range; an empty union plays the model only.
    public func loopPlayback(modelSlice slice: TimeRange) -> LoopPlayback {
        var ranges: [(range: TimeRange, segment: Int)] = []
        for (i, segment) in map.segments.enumerated() {
            guard case .mapped(let model, _, _, _) = segment else { continue }
            let lo = max(slice.start, model.start)
            let hi = min(slice.end, model.end)
            guard lo < hi, let a = mapInside(i, lo, from: .model), let b = mapInside(i, hi, from: .model),
                let range = try? TimeRange(start: a, end: b)
            else { continue }
            if let last = ranges.last, isBridgeable(from: last.segment, to: i) {
                ranges[ranges.count - 1] = (try! TimeRange(start: last.range.start, end: range.end), i)
            } else {
                ranges.append((range, i))
            }
        }
        return LoopPlayback(model: slice, you: ranges.map(\.range))
    }

    /// True when model time `t` is inside a comparable (present-word) mapped segment. Comparable-frame measures and
    /// band coverage count only these frames, so they skip every gap.
    public func isComparable(modelTime t: Double) -> Bool {
        map.segments.contains { segment in
            if case .mapped(let model, _, _, true) = segment { model.contains(t) } else { false }
        }
    }

    enum Side { case model, you }

    private func range(_ segment: PartialTimeMap.Segment, _ side: Side) -> TimeRange? {
        side == .model ? segment.modelRange : segment.yourRange
    }

    /// The (model, you) knots of mapped segment `i`: its edges plus its DTW knots when refined, else its anchors.
    func knots(_ i: Int) -> [PartialTimeMap.Anchor] {
        guard case .mapped(let model, let you, let anchors, _) = map.segments[i] else { return [] }
        let inner = refinements[i] ?? anchors
        let all = [PartialTimeMap.Anchor(model: model.start, you: you.start)] + inner
            + [PartialTimeMap.Anchor(model: model.end, you: you.end)]
        return Self.monotone(all, inside: model, you)
    }

    /// Maps `t` on `side` through mapped segment `i` (piecewise-linear between knots).
    func mapInside(_ i: Int, _ t: Double, from side: Side) -> Double? {
        let k = knots(i)
        guard let first = k.first else { return nil }
        let x = { (a: PartialTimeMap.Anchor) in side == .model ? a.model : a.you }
        let y = { (a: PartialTimeMap.Anchor) in side == .model ? a.you : a.model }
        if t <= x(first) { return y(first) }
        for (a, b) in zip(k, k.dropFirst()) where t <= x(b) {
            return y(a) + (t - x(a)) / (x(b) - x(a)) * (y(b) - y(a))
        }
        return y(k[k.count - 1])
    }

    /// True when mapped segments `a` < `b` have nothing but mapped segments between them, so the pause between
    /// them maps linearly. A missing or inserted word between them is a gap that is never bridged.
    private func isBridgeable(from a: Int, to b: Int) -> Bool {
        map.segments[(a + 1)..<b].allSatisfy { if case .mapped = $0 { true } else { false } }
    }

    private func lookup(_ t: Double, from side: Side) -> Double? {
        let segments = map.segments
        var mapped: [Int] = []
        for (i, segment) in segments.enumerated() {
            guard let r = range(segment, side) else { continue }
            if case .mapped = segment {
                if r.contains(t) { return mapInside(i, t, from: side) }
                mapped.append(i)
            }
        }
        // Inside a gap on this timeline (an insertion for your time, a missing word for model time).
        for segment in segments {
            if case .mapped = segment { continue }
            if let r = range(segment, side), r.contains(t) { return nil }
        }
        guard let first = mapped.first, let last = mapped.last,
            let firstRange = range(segments[first], side), let lastRange = range(segments[last], side)
        else { return nil }
        let other: Side = side == .model ? .you : .model
        if t < firstRange.start {
            return firstRange.start - t <= Self.edgeClampSeconds ? range(segments[first], other)?.start : nil
        }
        if t > lastRange.end {
            return t - lastRange.end <= Self.edgeClampSeconds ? range(segments[last], other)?.end : nil
        }
        // Between two mapped segments: linear across the pause when no gap lies between them.
        for (a, b) in zip(mapped, mapped.dropFirst()) {
            guard let ra = range(segments[a], side), let rb = range(segments[b], side), ra.end < t, t < rb.start
            else { continue }
            guard isBridgeable(from: a, to: b), let oa = range(segments[a], other)?.end,
                let ob = range(segments[b], other)?.start
            else { return nil }
            return oa + (t - ra.end) / (rb.start - ra.end) * (ob - oa)
        }
        return nil
    }
}

extension TimingLevel {
    /// Poor < Rough < Good.
    var rank: Int {
        switch self {
        case .poor: 0
        case .rough: 1
        case .good: 2
        }
    }
}
