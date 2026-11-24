import AMCore
import AMWarp
import Foundation

/// The playhead's time mapping: spec 09's `TimeWarp` (`toYou`, `toModel`) built from the fixture's words, in seconds,
/// then read back as fractions of each timeline. Gaps, missing and inserted words map to nil; nothing is
/// interpolated across them. Only the chart model reads this; the chart views never see AMCore types.
struct WarpTimeMap: ChartTimeMap {
    let warp: TimeWarp
    let modelSeconds: Double
    let youSeconds: Double

    /// Nil when the take can't be mapped (no words, a word with no syllables, out-of-order times).
    init?(phrase: PhraseFixture, take: TakeFixture, modelSeconds: Double, youSeconds: Double) {
        guard modelSeconds > 0, youSeconds > 0 else { return nil }
        func range(_ start: Double, _ end: Double, _ seconds: Double) -> TimeRange? {
            try? TimeRange(start: start * seconds, end: max(start, end) * seconds)
        }
        var model: [TimedWord] = []
        for word in phrase.words {
            guard let edges = range(word.start, word.end, modelSeconds) else { return nil }
            let syllables = word.syllables.compactMap { range($0.start, $0.end, modelSeconds) }
            model.append(TimedWord(range: edges, syllables: syllables, timing: .good))
        }
        var pairs: [AMCore.AlignedWordPair] = []
        var yours: [WordIndex: TimedWord] = [:]
        var next = 0
        for pair in take.words {
            let span = pair.syllables.first.flatMap { first in
                pair.syllables.last.flatMap { range(first.start, $0.end, youSeconds) }
            }
            switch pair.kind {
            case .missing:
                guard next < phrase.words.count else { return nil }
                pairs.append(.missing(phrase: WordIndex(next)))
                next += 1
            case .inserted:
                guard let span else { return nil }
                pairs.append(.inserted(heard: pair.heard ?? "", you: span, afterPhrase: next > 0 ? WordIndex(next - 1) : nil))
            case .present, .substituted:
                guard let span, next < phrase.words.count else { return nil }
                let index = WordIndex(next)
                if pair.kind == .present {
                    pairs.append(.present(phrase: index, you: span))
                    let syllables = pair.syllables.compactMap { range($0.start, $0.end, youSeconds) }
                    yours[index] = TimedWord(range: span, syllables: syllables, timing: .good)
                } else {
                    pairs.append(.substituted(phrase: index, heard: pair.heard ?? "", you: span))
                    yours[index] = TimedWord(range: span, timing: .good)
                }
                next += 1
            }
        }
        guard let alignment = try? WordAlignment(pairs: pairs),
              let warp = try? TimeWarp(alignment: alignment, model: model, you: yours, timing: .good)
        else { return nil }
        self.warp = warp
        self.modelSeconds = modelSeconds
        self.youSeconds = youSeconds
    }

    func toModel(_ you: Double) -> Double? { warp.toModel(you * youSeconds).map { $0 / modelSeconds } }

    func toYou(_ model: Double) -> Double? { warp.toYou(model * modelSeconds).map { $0 / youSeconds } }

    func gapEdge(beforeYou you: Double) -> Double? {
        let t = you * youSeconds
        var edge: Double?
        var first: Double?
        for segment in warp.map.segments {
            guard case .mapped(let model, let yours, _, _) = segment else { continue }
            if first == nil { first = model.start }
            if yours.end <= t { edge = model.end }
        }
        return (edge ?? first).map { $0 / modelSeconds }
    }
}
