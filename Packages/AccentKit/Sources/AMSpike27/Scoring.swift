// Spec 27 §1/§3: one take's placement-applicable words through an arm, the classifier and the abstaining decision,
// with spec 02's B1 (longest) and B2 (loudest) on the same words and front end.

import AMCore
import AMProsody
import Foundation

public struct WordOutcome: Sendable, Hashable, Codable {
    public let index: Int
    public let text: String
    public let target: Int
    public let syllables: Int
    public let label: String?
    /// The word's nuclei (indices into the take's), nil when the front end abstained.
    public let nuclei: [Int]?
    public let verdict: WordVerdict
    public let predicted: Int?
    public let margin: Double?
    /// B1 / B2 flag on the same nuclei (nil when the front end abstained).
    public let b1Flag: Bool?
    public let b2Flag: Bool?
}

public enum TakeScoring {
    /// The front end's nuclei for every target word of the take under `arm` (nil entries: abstained, with reason).
    /// Arm A's ambiguity check needs the classifier: without one (collecting training words) it is skipped.
    public static func select(_ take: MeasuredAudio, words: [TimedWord], arm: Arm, source: BoundarySource,
                              classifier: StressClassifier?, tau: Double,
                              thresholds: Thresholds = .current) -> [Int: Result<[Int], AbstentionError>] {
        var out: [Int: Result<[Int], AbstentionError>] = [:]
        let targets = words.indices.filter { words[$0].target != nil }
        guard !targets.isEmpty else { return out }
        switch arm {
        case .b:
            let pad = ArmSelection.padding(source, thresholds: thresholds)
            for j in targets {
                let w = words[j]
                if let list = ArmSelection.topK(take.nuclei, start: w.start, end: w.end, count: w.syllables,
                                                paddingSeconds: pad) {
                    out[j] = .success(list)
                } else {
                    out[j] = .failure(AbstentionError(.tooFewNuclei))
                }
            }
        case .a:
            let peaks = take.nuclei.map(\.peakTime)
            let assignerWords = ArmSelection.assignerWords(words)
            let result = NucleusAssigner.assign(peaks, to: assignerWords, thresholds: thresholds)
            var ambiguous = Set<Int>()
            if let classifier {
                ambiguous = NucleusAssignmentStability.ambiguousWords(
                    peaks: peaks, words: assignerWords, result: result, thresholds: thresholds
                ) { j, nuclei, _ -> String in
                    guard let target = words[j].target else { return "n/a" }
                    guard let nuclei, nuclei.count == words[j].syllables else { return "abstain" }
                    let p = classifier.probabilities(nuclei.map { take.nuclei[$0] })
                    return WordVerdict.decide(probabilities: p, target: target, tau: tau).0.description
                }
            }
            for j in targets {
                guard let list = result.nuclei[j] else { out[j] = .failure(AbstentionError(.nucleusShort)); continue }
                guard list.count == words[j].syllables else {
                    out[j] = .failure(AbstentionError(.countNotContext))
                    continue
                }
                out[j] = ambiguous.contains(j) ? .failure(AbstentionError(.ambiguous)) : .success(list)
            }
        }
        return out
    }

    /// Every target word's outcome.
    public static func score(_ take: MeasuredAudio, words: [TimedWord], arm: Arm, source: BoundarySource,
                             classifier: StressClassifier, tau: Double,
                             thresholds: Thresholds = .current) -> [WordOutcome] {
        let selection = select(take, words: words, arm: arm, source: source, classifier: classifier, tau: tau,
                               thresholds: thresholds)
        return selection.keys.sorted().map { j in
            let w = words[j]
            let target = w.target!
            switch selection[j]! {
            case .failure(let error):
                return WordOutcome(index: w.index, text: w.text, target: target, syllables: w.syllables,
                                   label: w.label, nuclei: nil, verdict: .abstain(error.reason), predicted: nil,
                                   margin: nil, b1Flag: nil, b2Flag: nil)
            case .success(let list):
                let nuclei = list.map { take.nuclei[$0] }
                let (verdict, predicted, margin) = WordVerdict.decide(
                    probabilities: classifier.probabilities(nuclei), target: target, tau: tau)
                return WordOutcome(index: w.index, text: w.text, target: target, syllables: w.syllables,
                                   label: w.label, nuclei: list, verdict: verdict, predicted: predicted,
                                   margin: margin, b1Flag: argmax(nuclei.map(\.duration)) != target,
                                   b2Flag: argmax(nuclei.map(\.energyDB)) != target)
            }
        }
    }

    /// Ties go to the earliest (spec 02's baselines).
    static func argmax(_ values: [Double]) -> Int {
        var best = 0
        for i in values.indices where values[i] > values[best] { best = i }
        return best
    }
}

public struct AbstentionError: Error, Sendable, Hashable {
    public let reason: Abstention
    public init(_ reason: Abstention) { self.reason = reason }
}

/// §4: the swap that turns a native word into a misplaced-stress negative.
public enum StressSwap {
    public static let profilePoints = 11

    /// The two regions: the stressed nucleus takes the unstressed one's duration, intensity and f0 contour, and the
    /// other way round. Contours are read from the take's voiced frames inside each region by relative position.
    public static func regions(stressed s: MeasuredNucleus, unstressed u: MeasuredNucleus,
                               take: MeasuredAudio) -> [PSOLA.Region] {
        let cs = contour(s, take), cu = contour(u, take)
        let toS = zip(cu, cs).map { $0 - $1 }
        return [
            PSOLA.Region(start: s.regionStart, end: s.regionEnd, durationFactor: u.duration / s.duration,
                         gainDB: u.energyDB - s.energyDB, shiftProfile: toS),
            PSOLA.Region(start: u.regionStart, end: u.regionEnd, durationFactor: s.duration / u.duration,
                         gainDB: s.energyDB - u.energyDB, shiftProfile: toS.map { -$0 }),
        ]
    }

    /// Semitones at `profilePoints` relative positions across the region (nearest voiced frame; the region's mean
    /// when it has fewer than 2 voiced frames, 0 when none).
    static func contour(_ n: MeasuredNucleus, _ take: MeasuredAudio) -> [Double] {
        let points = zip(take.voicedTimes, take.voicedSemitones).filter { $0.0 >= n.regionStart && $0.0 <= n.regionEnd }
        guard points.count >= 2 else {
            let mean = points.first?.1 ?? n.f0Semitones ?? 0
            return [Double](repeating: mean, count: profilePoints)
        }
        return (0..<profilePoints).map { i in
            let t = n.regionStart + (n.regionEnd - n.regionStart) * Double(i) / Double(profilePoints - 1)
            return points.min { abs($0.0 - t) < abs($1.0 - t) }!.1
        }
    }
}
