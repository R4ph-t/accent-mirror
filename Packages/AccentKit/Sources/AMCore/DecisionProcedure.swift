// The decision procedure (plan §1.2) and `close` (§1.3), as one pure function. Spec 10 supplies the real inputs.

import Foundation

/// What alignment tells the decision procedure (spec 06 computes it).
public struct AlignmentSummary: Sendable, Hashable, Codable {
    /// Matched content words ÷ content words (§4.2).
    public let matchShare: Double
    /// Heard words that aren't fillers and match no phrase word.
    public let nonFillerInsertions: [String]
    /// Target words that are `missing` or `substituted`.
    public let incompleteTargetWords: [WordIndex]
    /// Non-target words that are `missing` or `substituted`.
    public let incompleteNonTargetWords: [WordIndex]

    public init(
        matchShare: Double, nonFillerInsertions: [String] = [], incompleteTargetWords: [WordIndex] = [],
        incompleteNonTargetWords: [WordIndex] = []
    ) {
        self.matchShare = matchShare
        self.nonFillerInsertions = nonFillerInsertions
        self.incompleteTargetWords = incompleteTargetWords
        self.incompleteNonTargetWords = incompleteNonTargetWords
    }
}

/// Every measure's applicability with its state for this take. Applicable measures must have a state that isn't
/// `.notApplicable`; not-applicable ones take their reason from the table.
public struct MeasureAssessments: Sendable, Hashable {
    public let applicability: ApplicabilityTable
    public let states: [MeasureKind: MeasureState<Double>]

    public enum Invalid: Error, Equatable {
        case missingState(MeasureKind)
        case contradictsApplicability(MeasureKind)
    }

    public init(applicability: ApplicabilityTable, states: [MeasureKind: MeasureState<Double>]) throws {
        var complete: [MeasureKind: MeasureState<Double>] = [:]
        for kind in MeasureKind.allCases {
            switch (applicability[kind], states[kind]) {
            case (.notApplicable(let reason), nil):
                complete[kind] = .notApplicable(reason)
            case (.notApplicable(let reason), .some(let state)):
                guard state == .notApplicable(reason) else { throw Invalid.contradictsApplicability(kind) }
                complete[kind] = state
            case (.applicable, nil):
                throw Invalid.missingState(kind)
            case (.applicable, .some(let state)):
                if case .notApplicable = state { throw Invalid.contradictsApplicability(kind) }
                complete[kind] = state
            }
        }
        self.applicability = applicability
        self.states = complete
    }

    public subscript(kind: MeasureKind) -> MeasureState<Double> { states[kind]! }

    /// Applicable kinds matching `predicate`, in `MeasureKind` order.
    func applicableKinds(where predicate: (MeasureRequirement, MeasureState<Double>) -> Bool) -> [MeasureKind] {
        MeasureKind.allCases.filter { kind in
            guard case .applicable(let requirement) = applicability[kind] else { return false }
            return predicate(requirement, self[kind])
        }
    }
}

public struct DecisionInput: Sendable, Hashable {
    /// Everything the quality checks found; only the first in Designer's order is reported.
    public let takeProblems: [TakeProblem]
    public let alignment: AlignmentSummary
    public let timing: TimingLevel
    /// Comparable syllables ÷ the model's syllables.
    public let comparableCoverage: Double
    public let measures: MeasureAssessments
    /// Triggered, unsuppressed diffs, ranked by spec 10 (ties already broken by relative gap). A rough-timing row
    /// is added here, so any passed in is ignored.
    public let triggeredDiffs: [DiffRow]

    public init(
        takeProblems: [TakeProblem] = [], alignment: AlignmentSummary, timing: TimingLevel, comparableCoverage: Double,
        measures: MeasureAssessments, triggeredDiffs: [DiffRow] = []
    ) {
        self.takeProblems = takeProblems
        self.alignment = alignment
        self.timing = timing
        self.comparableCoverage = comparableCoverage
        self.measures = measures
        self.triggeredDiffs = triggeredDiffs
    }
}

/// The decision procedure's answer: a take problem, or a verdict for an analysed take.
public enum Decision: Sendable, Hashable, Codable {
    case takeProblem(TakeProblem)
    case verdict(Verdict)

    enum TakeProblemCodingKeys: String, CodingKey { case _0 = "problem" }
    enum VerdictCodingKeys: String, CodingKey { case _0 = "verdict" }
}

/// Plan §1.2, in order; the first match wins.
public func decide(_ input: DecisionInput, thresholds: Thresholds = .current) -> Decision {
    let limits = thresholds.decision
    let measures = input.measures

    // 1. Quality checks.
    if let problem = TakeProblem.first(of: input.takeProblems) { return .takeProblem(problem) }

    // 2. Word alignment.
    if input.alignment.matchShare < limits.minMatchShare
        || Double(input.alignment.nonFillerInsertions.count) > limits.maxNonFillerInsertions
    {
        return .takeProblem(.wordsDontMatch)
    }

    // 3. Target words missing or substituted.
    if !input.alignment.incompleteTargetWords.isEmpty {
        return .verdict(.inconclusive([.targetWordsMissing(input.alignment.incompleteTargetWords)]))
    }

    // 4. Timing Poor.
    if input.timing == .poor { return .verdict(.inconclusive([.timingUnreliable])) }

    // 5. Comparable coverage.
    if input.comparableCoverage < limits.minComparableCoverage {
        return .verdict(.inconclusive([.comparableCoverageLow(input.comparableCoverage)]))
    }

    // 6. No stress measure applicable at all.
    if !measures.applicability[.stressPlacement].isApplicable && !measures.applicability[.contrast].isApplicable {
        return .verdict(.inconclusive([.noApplicableStressMeasure]))
    }

    let requiredUnavailable = measures.applicableKinds { requirement, state in
        requirement == .required && state.isUnavailable
    }

    // 7. Triggered diffs → feedback, ranked; rough-timing row first and counting toward the cap.
    let ranked = input.triggeredDiffs.enumerated()
        .filter { $0.element.kind != .roughTiming }
        .sorted { ($0.element.kind, $0.offset) < ($1.element.kind, $1.offset) }
        .map(\.element)
    if !ranked.isEmpty {
        let withTiming = input.timing == .rough ? [DiffRow(kind: .roughTiming)] + ranked : ranked
        let rows = BoundedRows(Array(withTiming.prefix(Int(limits.maxDiffRows))))!
        return .verdict(.feedback(rows: rows, partial: requiredUnavailable))
    }

    // 8. Nothing triggered and a required measure unavailable.
    if !requiredUnavailable.isEmpty {
        return .verdict(.inconclusive([.requiredMeasureUnavailable(requiredUnavailable)]))
    }

    // 9 and 10. `close` if every §1.3 condition holds, else the reasons it doesn't.
    var reasons: [NeutralReason] = []
    if case .applicable = measures.applicability[.shapeMatch], let shape = measures[.shapeMatch].value,
        shape < limits.closeMinShapeMatch
    {
        reasons.append(.pitchShapeBelowClose(shape))
    }
    let optionalUnavailable = measures.applicableKinds { requirement, state in
        requirement != .required && state.isUnavailable
    }
    if !optionalUnavailable.isEmpty { reasons.append(.optionalMeasuresUnavailable(optionalUnavailable)) }
    let belowCloseConfidence = measures.applicableKinds { requirement, state in
        guard let confidence = state.confidence else { return false }
        return confidence < (requirement == .required ? .high : .medium)
    }
    if !belowCloseConfidence.isEmpty { reasons.append(.mediumConfidenceOnly(belowCloseConfidence)) }
    if input.timing == .rough { reasons.append(.timingRough) }
    if !input.alignment.incompleteNonTargetWords.isEmpty {
        reasons.append(.nonTargetWordsIncomplete(input.alignment.incompleteNonTargetWords))
    }
    if !input.alignment.nonFillerInsertions.isEmpty {
        reasons.append(.insertionsPresent(input.alignment.nonFillerInsertions))
    }

    return .verdict(reasons.isEmpty ? .close : .noClearDifference(reasons))
}
