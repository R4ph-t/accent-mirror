// Placement, contrast, too much contrast, weak length and nPVI (spec 10; spec 08's rules; confidence from first v2
// §5). Prominence for both takes is computed over the same comparable set: the syllables of the words `present` in
// your take, so your P and the model's P are measured over the same material.

import AMCore
import AMProsody
import Foundation

/// Why a placement mismatch gives no diff (§5), in the order they are checked.
public enum ScoringSuppression: String, Sendable, Hashable, Codable, CaseIterable {
    /// Timing Poor: no stress, contrast or weak-length diff.
    case timingPoor
    /// The model voice's own primary is outside A(w) at high confidence.
    case referenceAnomaly
    /// The model's stress confidence on the word is low.
    case modelStressConfidenceLow
    /// Spec 08's rule: low syllable confidence, an exposed syllable, or stress confidence below high.
    case lowSyllableConfidence, exposedSyllable, stressConfidenceBelowHigh

    init(_ reason: PlacementSuppressionReason) {
        switch reason {
        case .lowSyllableConfidence: self = .lowSyllableConfidence
        case .exposedSyllable: self = .exposedSyllable
        case .stressConfidenceBelowHigh: self = .stressConfidenceBelowHigh
        }
    }
}

/// One word's placement decision, with what suppressed it.
public struct WordPlacement: Sendable, Hashable {
    public let word: WordIndex
    public let yours: ObservedStress
    public let model: ObservedStress?
    public let decision: PlacementDecision
    public let referenceAnomaly: Bool
    /// The accepted pattern your primary matches; nil when it is outside A(w).
    public let matched: AcceptedPattern?
    /// The accepted pattern a row names: the nearest to your primary.
    public let nearest: AcceptedPattern?
    public let suppression: ScoringSuppression?

    /// Outside A(w) before suppression.
    public var mismatch: Bool { decision.outsideAccepted }
    /// Outside A(w) and not suppressed: the word is flagged.
    public var flagged: Bool { mismatch && suppression == nil }
}

/// The stress measures of one pair.
struct StressMeasures {
    var placements: [WordPlacement] = []
    var stress: [StressLine] = []
    var placement: MeasureState<Double>?
    var contrast: MeasureState<Double>?
    var weakLength: MeasureState<Double>?
    var rhythm: MeasureState<Double>?
    var modelContrast: Double?
    var modelWeakLength: Double?
    var modelRhythm: Double?

    init(_ input: ScoringInput, applicability table: ApplicabilityTable, thresholds: Thresholds) {
        let present = input.presentWords
        let you = input.you.syllables.filter { present.contains($0.word) }
        let model = input.model.syllables.filter { present.contains($0.word) }
        let yourProminence = TakeProminence(you, thresholds: thresholds.prominence)
        let modelProminence = TakeProminence(model, thresholds: thresholds.prominence)
        let timingPoor = input.warp.timing == .poor
        let minimumSyllables = Int(thresholds.applicability.placementMinSyllables)

        // Placement, per eligible word (§3.3).
        var eligible: [ScoringWord] = []
        for word in input.words {
            let observed = word.syllableCount >= 2 ? yourProminence?.observedStress(of: word.index) : nil
            let modelObserved = word.syllableCount >= 2 ? modelProminence?.observedStress(of: word.index) : nil
            var line = StressLine(
                word: word.index, expectedPattern: word.expectedPattern, observedPrimary: observed?.primary,
                margin: observed?.margin, confidence: observed?.confidence, matchedAccepted: nil, referenceAnomaly: false)
            defer { if word.syllableCount >= 2 { stress.append(line) } }

            guard let accepted = word.accepted, word.isTarget || word.isContent,
                word.syllableCount >= minimumSyllables
            else { continue }
            eligible.append(word)
            guard let observed,
                let decision = placementDecision(
                    observed: observed, accepted: accepted.primaries, confidence: observed.syllableConfidence,
                    exposure: observed.exposed)
            else { continue }
            let anomaly = modelObserved.map {
                accepted.isReferenceAnomaly(model: NativeReading(voice: input.modelVoice, observed: $0))
            } ?? false
            var suppression: ScoringSuppression?
            if decision.outsideAccepted {
                if timingPoor {
                    suppression = .timingPoor
                } else if anomaly {
                    suppression = .referenceAnomaly
                } else if modelObserved.map({ $0.confidence == .low }) ?? true {
                    suppression = .modelStressConfidenceLow
                } else if let reason = decision.suppression {
                    suppression = ScoringSuppression(reason)
                }
            }
            let matched = accepted.matched(primary: observed.primary, selectedVoice: input.modelVoice)?.pattern
            line = StressLine(
                word: word.index, expectedPattern: word.expectedPattern, observedPrimary: observed.primary,
                margin: observed.margin, confidence: observed.confidence, matchedAccepted: matched,
                referenceAnomaly: anomaly)
            placements.append(WordPlacement(
                word: word.index, yours: observed, model: modelObserved, decision: decision, referenceAnomaly: anomaly,
                matched: matched, nearest: accepted.nearest(primary: observed.primary, selectedVoice: input.modelVoice),
                suppression: suppression))
        }
        if table[.stressPlacement].isApplicable {
            placement = Self.placementState(placements, eligible: eligible, input: input)
        }

        // Contrast and weak length over the matched S and U sets, the same sets for both speakers (spec 08).
        if table[.contrast].isApplicable {
            let groups = Self.contrastGroup(
                input, you: you, model: model, placements: placements, thresholds: thresholds)
            contrast = groups.contrast
            weakLength = groups.weakLength
            modelContrast = groups.modelContrast
            modelWeakLength = groups.modelWeakLength
        }

        // nPVI over your comparable syllables in time order: inspector only, never a diff.
        if table[.rhythm].isApplicable {
            let levels = you.map(\.level)
            if let yours = Self.npvi(you.map(\.features.duration)) {
                let level = Self.shareLevel(levels, thresholds: thresholds.confidence)
                rhythm = level == .low ? .unavailable(.lowConfidence) : .evaluated(yours, level)
            } else {
                rhythm = .unavailable(.wordMissing)
            }
            modelRhythm = Self.npvi(model.map(\.features.duration))
        }
    }

    /// The phrase's placement state: the reported word's margin (the flagged word with the largest margin, else the
    /// least certain decided word), at the lowest stress confidence over decided words.
    static func placementState(
        _ placements: [WordPlacement], eligible: [ScoringWord], input: ScoringInput
    ) -> MeasureState<Double> {
        guard !placements.isEmpty else {
            let statuses = eligible.map { input.status(of: $0.index) }
            if statuses.contains(.missing) { return .unavailable(.wordMissing) }
            if statuses.contains(.substituted) { return .unavailable(.wordSubstituted) }
            return .unavailable(.lowConfidence)
        }
        let confidence = placements.map(\.yours.confidence).min()!
        let reported = reportedPlacement(placements)
            ?? placements.min { ($0.yours.confidence, $0.yours.margin) < ($1.yours.confidence, $1.yours.margin) }!
        return .evaluated(reported.yours.margin, confidence)
    }

    /// The one placement row's word: the most prominent mismatch (largest margin; ties to the earlier word).
    static func reportedPlacement(_ placements: [WordPlacement]) -> WordPlacement? {
        placements.filter(\.flagged).enumerated().max { a, b in
            a.element.yours.margin != b.element.yours.margin
                ? a.element.yours.margin < b.element.yours.margin : a.offset > b.offset
        }?.element
    }

    struct ContrastGroup {
        var contrast: MeasureState<Double>
        var weakLength: MeasureState<Double>
        var modelContrast: Double?
        var modelWeakLength: Double?
    }

    /// C (shared by too much contrast) and W in points. S and U per word come from the pattern your primary
    /// matched, else the context pronunciation; only syllables both takes have count.
    static func contrastGroup(
        _ input: ScoringInput, you: [ComparableSyllable], model: [ComparableSyllable], placements: [WordPlacement],
        thresholds: Thresholds
    ) -> ContrastGroup {
        struct Key: Hashable { let word: WordIndex; let index: Int }
        let yourIndex = Dictionary(you.enumerated().map { (Key(word: $1.word, index: $1.indexInWord), $0) },
                                   uniquingKeysWith: { a, _ in a })
        let modelIndex = Dictionary(model.enumerated().map { (Key(word: $1.word, index: $1.indexInWord), $0) },
                                    uniquingKeysWith: { a, _ in a })
        let matchedPrimary = Dictionary(placements.map { ($0.word, $0.yours.primary) }, uniquingKeysWith: { a, _ in a })
        var stressed: [Key] = []
        var unstressed: [Key] = []
        for word in input.words {
            guard let accepted = word.accepted else { continue }
            let entry = matchedPrimary[word.index].flatMap {
                accepted.matched(primary: $0, selectedVoice: input.modelVoice)
            }
            let sets = accepted.stressSets(matching: entry)
            for i in sets.stressed.sorted() { stressed.append(Key(word: word.index, index: i)) }
            for i in sets.unstressed.sorted() { unstressed.append(Key(word: word.index, index: i)) }
        }
        let both = { (key: Key) in yourIndex[key] != nil && modelIndex[key] != nil }
        stressed = stressed.filter(both)
        unstressed = unstressed.filter(both)
        let limits = thresholds.applicability
        guard Double(stressed.count) >= limits.contrastMinStressed, Double(unstressed.count) >= limits.contrastMinUnstressed
        else { return ContrastGroup(contrast: .unavailable(.wordMissing), weakLength: .unavailable(.wordMissing)) }

        let members = stressed + unstressed
        let level = min(
            shareLevel(members.map { you[yourIndex[$0]!].level }, thresholds: thresholds.confidence),
            shareLevel(members.map { model[modelIndex[$0]!].level }, thresholds: thresholds.confidence))
        let yourS = stressed.map { yourIndex[$0]! }, yourU = unstressed.map { yourIndex[$0]! }
        let modelS = stressed.map { modelIndex[$0]! }, modelU = unstressed.map { modelIndex[$0]! }
        let features = (you: you.map(\.features), model: model.map(\.features))
        let modelC = Contrast.contrast(features.model, stressed: modelS, unstressed: modelU, thresholds: thresholds.prominence)
        let modelW = Contrast.weakLength(features.model, stressed: modelS, unstressed: modelU).map { $0 * 100 }
        let yourC = Contrast.contrast(features.you, stressed: yourS, unstressed: yourU, thresholds: thresholds.prominence)
        let yourW = Contrast.weakLength(features.you, stressed: yourS, unstressed: yourU).map { $0 * 100 }

        func state(_ value: Double?) -> MeasureState<Double> {
            guard let value else { return .unavailable(.lowConfidence) }
            return level == .low ? .unavailable(.lowConfidence) : .evaluated(value, level)
        }
        return ContrastGroup(
            contrast: state(yourC), weakLength: state(yourW), modelContrast: modelC, modelWeakLength: modelW)
    }

    /// Share of syllables at medium or above → high ≥ 0.9, medium ≥ 0.7, else low (contrast and weak length).
    static func shareLevel(_ levels: [Confidence], thresholds: Thresholds.ConfidenceLevels) -> Confidence {
        guard !levels.isEmpty else { return .low }
        let share = Double(levels.count { $0 >= .medium }) / Double(levels.count)
        return share >= thresholds.contrastHigh ? .high : share >= thresholds.contrastMedium ? .medium : .low
    }

    /// nPVI = 100 × mean |d_k − d_k+1| / ((d_k + d_k+1) / 2); nil with fewer than 3 syllables.
    static func npvi(_ durations: [Double]) -> Double? {
        guard durations.count >= 3 else { return nil }
        let terms = zip(durations, durations.dropFirst()).map { a, b in
            a + b > 0 ? abs(a - b) / ((a + b) / 2) : 0
        }
        return 100 * terms.reduce(0, +) / Double(terms.count)
    }
}
