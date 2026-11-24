// Spec 27 §2 (lit amendment 3): per-prompt native envelopes for the phrase metrics. Spec 10's definitions: pitch
// range is P90 − P10 (linear-interpolated) of the voiced frames inside the take's words; final direction is the
// least-squares slope of the last 200 ms (300 ms when short) of voiced frames inside the words, ±5 st/s; nPVI is
// 100 × mean |d_k − d_k+1| / mean pair over the syllables in time order, read here with spec 25's `.nucleus`
// measurement (d = the assigned nucleus regions).

import AMCore
import AMProsody
import Foundation

public enum FinalClass: String, Sendable, Hashable, Codable, CaseIterable { case rise, fall, level }

public struct PhraseMetrics: Sendable, Hashable, Codable {
    public let pitchRange: Double?
    public let finalSlope: Double?
    public let finalClass: FinalClass?
    public let npvi: Double?

    public init(pitchRange: Double?, finalSlope: Double?, finalClass: FinalClass?, npvi: Double?) {
        self.pitchRange = pitchRange
        self.finalSlope = finalSlope
        self.finalClass = finalClass
        self.npvi = npvi
    }

    public static func measure(_ take: MeasuredAudio, words: [TimedWord], thresholds: Thresholds = .current)
        -> PhraseMetrics
    {
        let spans = words.map { ($0.start, $0.end) }
        func inside(_ t: Double) -> Bool { spans.contains { $0.0 <= t && t <= $0.1 } }
        let frames = zip(take.voicedTimes, take.voicedSemitones).filter { inside($0.0) }
        var range: Double?
        if !frames.isEmpty {
            let sorted = frames.map(\.1).sorted()
            range = percentile(sorted, thresholds.band.upperPercentile) - percentile(sorted, thresholds.band.lowerPercentile)
        }
        // The final window (spec 10 §11).
        var slope: Double?
        if let last = frames.map(\.0).max() {
            let f = thresholds.finalDirection
            let hop = take.hopSeconds
            func window(_ ms: Double) -> [(Double, Double)] { frames.filter { last - $0.0 < ms / 1000 - hop / 2 } }
            var w = window(f.windowMs)
            if w.count < Int(f.minVoicedFrames) { w = window(f.extendedWindowMs) }
            if w.count >= Int(f.minVoicedFrames) && Double(w.count) >= thresholds.confidence.finalDirectionMediumFrames {
                slope = leastSquares(w)
            }
        }
        let finalClass = slope.map { s -> FinalClass in
            s >= thresholds.finalDirection.riseSemitonesPerSecond ? .rise
                : s <= thresholds.finalDirection.fallSemitonesPerSecond ? .fall : .level
        }
        // nPVI over the assigned nuclei (arm A's assignment, non-short words), in time order.
        let result = NucleusAssigner.assign(take.nuclei.map(\.peakTime), to: ArmSelection.assignerWords(words),
                                            thresholds: thresholds)
        let durations = result.nuclei.compactMap { $0 }.flatMap { $0 }.sorted().map { take.nuclei[$0].duration }
        return PhraseMetrics(pitchRange: range, finalSlope: slope, finalClass: finalClass, npvi: npvi(durations))
    }

    public static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p / 100 * Double(sorted.count - 1)
        let lo = Int(position.rounded(.down))
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (position - Double(lo)) * (sorted[hi] - sorted[lo])
    }

    static func leastSquares(_ points: [(Double, Double)]) -> Double? {
        let n = Double(points.count)
        let mt = points.reduce(0) { $0 + $1.0 } / n, ms = points.reduce(0) { $0 + $1.1 } / n
        let sxx = points.reduce(0) { $0 + ($1.0 - mt) * ($1.0 - mt) }
        guard sxx > 0 else { return nil }
        return points.reduce(0) { $0 + ($1.0 - mt) * ($1.1 - ms) } / sxx
    }

    public static func npvi(_ d: [Double]) -> Double? {
        guard d.count >= 3 else { return nil }
        var sum = 0.0
        for k in 0..<(d.count - 1) {
            let mean = (d[k] + d[k + 1]) / 2
            if mean > 0 { sum += abs(d[k] - d[k + 1]) / mean }
        }
        return 100 * sum / Double(d.count - 1)
    }
}

/// One take of a prompt for the envelope.
public struct EnvelopeTake: Sendable, Hashable, Codable {
    public let speaker: String
    public let population: Population
    /// A TTS voice's name, nil for a natural speaker.
    public let ttsVoice: String?
    public let metrics: PhraseMetrics

    public init(speaker: String, population: Population, ttsVoice: String? = nil, metrics: PhraseMetrics) {
        self.speaker = speaker
        self.population = population
        self.ttsVoice = ttsVoice
        self.metrics = metrics
    }
}

public enum NativeEnvelope {
    public static let minimumNaturalTakes = 30

    /// §2: only natural speakers count toward n and the spread; TTS takes count at most once per voice (shown, never
    /// in the spread).
    public static func counts(_ takes: [EnvelopeTake]) -> (natural: Int, ttsVoices: Int) {
        (takes.filter { $0.ttsVoice == nil }.count, Set(takes.compactMap(\.ttsVoice)).count)
    }

    /// The central interval [q, 1 − q] of the natural takes' values, nil under 30 natural takes (NOT EVALUATED, no
    /// pooling fallback) or with too few values.
    public static func interval(_ takes: [EnvelopeTake], value: (PhraseMetrics) -> Double?, q: Double)
        -> ClosedRange<Double>?
    {
        let natural = takes.filter { $0.ttsVoice == nil }
        guard natural.count >= minimumNaturalTakes else { return nil }
        let values = natural.compactMap { value($0.metrics) }.sorted()
        guard values.count >= 2 else { return nil }
        return percentile(values, q) ... percentile(values, 1 - q)
    }

    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        PhraseMetrics.percentile(sorted, q * 100)
    }

    /// The candidate quantile pairs (q, 1 − q), widest first. Fixed before any data.
    public static let quantiles = [0.0, 0.01, 0.025, 0.05, 0.10]

    /// The dominant final class of the natural takes and its share.
    public static func dominantFinal(_ takes: [EnvelopeTake]) -> (FinalClass, Double)? {
        let classes = takes.filter { $0.ttsVoice == nil }.compactMap(\.metrics.finalClass)
        guard !classes.isEmpty else { return nil }
        let counts = Dictionary(grouping: classes, by: { $0 }).mapValues(\.count)
        let best = FinalClass.allCases.max { (counts[$0] ?? 0, -FinalClass.allCases.firstIndex(of: $0)!)
            < (counts[$1] ?? 0, -FinalClass.allCases.firstIndex(of: $1)!) }!
        return (best, Double(counts[best] ?? 0) / Double(classes.count))
    }

    /// Monotone: the take's pitch range is below the envelope. Nil when it can't be read.
    public static func monotone(_ metrics: PhraseMetrics, envelope: ClosedRange<Double>) -> Bool? {
        metrics.pitchRange.map { $0 < envelope.lowerBound }
    }

    /// Final direction: the take's slope is outside the envelope and its class isn't the prompt's dominant one.
    public static func finalDirection(_ metrics: PhraseMetrics, envelope: ClosedRange<Double>, dominant: FinalClass)
        -> Bool?
    {
        guard let slope = metrics.finalSlope, let c = metrics.finalClass else { return nil }
        return !envelope.contains(slope) && c != dominant
    }
}
