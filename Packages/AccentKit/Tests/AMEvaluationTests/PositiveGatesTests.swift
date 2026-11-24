import Foundation
import Testing
import AMCore
import AMEvaluation

@Suite("Spec 10 positive-set gates") struct PositiveGatesTests {
    static let photography = try! ApplicabilityTable(Dictionary(uniqueKeysWithValues: MeasureKind.allCases.map {
        ($0, $0 == .rhythm ? MeasureApplicability.applicable(.inspectorOnly)
            : [.pitchRange, .shapeMatch, .finalDirection].contains($0) ? .applicable(.optional) : .applicable(.required))
    }))

    /// `count` held-out pairs over 16 speakers and 20 phrases; `diff(i)` gives pair i a placement row.
    static func pairs(_ count: Int, diff: (Int) -> Bool = { _ in false }, inconclusive: (Int) -> Bool = { _ in false })
        -> [PairOutcome]
    {
        (0..<count).map { i in
            let decision: Decision =
                inconclusive(i) ? .verdict(.inconclusive([.requiredMeasureUnavailable([.contrast])]))
                : diff(i) ? .verdict(.feedback(rows: BoundedRows([DiffRow(kind: .placement)])!, partial: []))
                : .verdict(.close)
            var measures: [MeasureKind: MeasureState<Double>] = [
                .stressPlacement: .evaluated(1, .high), .contrast: .evaluated(3, .high), .tooMuchContrast: .evaluated(3, .high),
                .weakLength: .evaluated(55, .high), .rhythm: .evaluated(50, .high), .pitchRange: .evaluated(7, .high),
                .shapeMatch: .evaluated(0.9, .high), .finalDirection: .evaluated(-8, .high),
            ]
            if inconclusive(i) {
                for k in [MeasureKind.contrast, .tooMuchContrast, .weakLength] { measures[k] = .unavailable(.lowConfidence) }
            }
            return PairOutcome(
                speaker: "p\(340 + i % 16)", phrase: String(format: "%03d", i % 20 + 1), decision: decision,
                applicability: photography, measures: measures,
                modelValues: [.contrast: 3.2, .tooMuchContrast: 3.2, .weakLength: 50, .rhythm: 45, .pitchRange: 8, .finalDirection: -7],
                referenceAnomaly: i % 25 == 0)
        }
    }

    static var spec10: [PositiveSetGates.Dependent] { PositiveSetGates.dependents().filter { $0.spec == "spec 10" } }

    @Test("spec 10 wires its gates, tolerance rows included, each on a Thresholds.agreement key") func dependents() {
        let names = Self.spec10.map(\.name)
        for name in ["Any-diff pairs", "Any-diff pairs, worst speaker", "Any-diff pairs, worst phrase", "Placement-diff pairs",
                     "Placement-diff pairs, worst speaker", "Inconclusive pairs", "Evaluation coverage",
                     "Contrast ratio within tolerance", "Weak length, largest |Δ|", "nPVI, largest |Δ|",
                     "Pitch range ratio at or above minimum", "Final direction agreement"] {
            #expect(names.contains(name), "\(name)")
        }
        #expect(Set(PositiveGates.measured(Self.pairs(200)).keys) == Set(names))
    }

    @Test("blocked: a NOT EVALUATED positive set gives NOT EVALUATED (blocked) lines, never a pass") func blocked() throws {
        let set = try PositiveSetGuardTests.shortSet()
        let status = set.status()
        guard case .notEvaluated = status else { Issue.record("short set should be NOT EVALUATED"); return }
        let lines = PositiveSetGates.lines(
            positiveSet: status, measured: PositiveGates.measured(Self.pairs(300)), pairs: set.headline.count)
        for line in lines where line.name.hasSuffix("(spec 10)") {
            // The status kind and prefix only: spec 24 owns the reason's wording.
            guard case .blocked(on: "spec 24", _) = line.status else { Issue.record("\(line.name): \(line.status)"); continue }
            #expect(line.status.text.hasPrefix("NOT EVALUATED (blocked on spec 24"))
            #expect(!line.status.isPass && line.value == nil && line.dependsOnPositiveSet == true)
        }
        let summary = ReleaseSummary(negativeSet: nil, positiveSet: status, gated: lines)
        #expect(summary.lines.first == "Negative set: NOT EVALUATED" && summary.lines.last == "Release gate: NOT MET")
    }

    @Test("evaluable with no measured pair: every spec 10 line is NOT EVALUATED (n=0), never a pass") func evaluableNone() {
        let lines = PositiveSetGates.lines(positiveSet: .evaluable, measured: PositiveGates.measured([]), pairs: 274)
        for line in lines where line.name.hasSuffix("(spec 10)") {
            #expect(line.status == .notEvaluated(n: 0, minimum: 150), "\(line.name)")
            #expect(line.status.text.hasPrefix("NOT EVALUATED") && !line.status.isPass)
        }
        let summary = ReleaseSummary(negativeSet: nil, positiveSet: .evaluable, gated: lines)
        #expect(summary.lines == ["Negative set: NOT EVALUATED", "Positive set: EVALUABLE", "Release gate: NOT MET"])
    }

    @Test("evaluable with too few measured pairs: NOT EVALUATED with n, never a pass") func evaluableTooFew() {
        let lines = PositiveSetGates.lines(positiveSet: .evaluable, measured: PositiveGates.measured(Self.pairs(149)), pairs: 274)
        for line in lines where line.name.hasSuffix("(spec 10)") {
            guard case .notEvaluated(let n, 150) = line.status else { Issue.record("\(line.name): \(line.status)"); continue }
            #expect(n <= 149 && !line.status.isPass && line.value == nil)
        }
    }

    @Test("evaluable and measured: rates pass or fail against their gates, with n, interval and worst clusters")
    func evaluableMeasured() throws {
        let clean = PositiveGates.measured(Self.pairs(200))
        let anyDiff = try #require(clean["Any-diff pairs"])
        #expect(anyDiff.status == .pass && anyDiff.n == 200 && anyDiff.value == 0)
        #expect(!anyDiff.intervals.isEmpty && anyDiff.worstSpeaker != nil && anyDiff.worstPhrase != nil)
        for name in ["Inconclusive pairs", "Evaluation coverage", "Contrast ratio within tolerance", "Weak length, largest |Δ|",
                     "nPVI, largest |Δ|", "Pitch range ratio at or above minimum", "Final direction agreement"] {
            #expect(clean[name]?.status == .pass, "\(name): \(String(describing: clean[name]))")
        }

        // 10% of pairs with a placement diff, all on one speaker's pairs: point and worst speaker fail.
        let noisy = PositiveGates.measured(Self.pairs(200, diff: { $0 % 16 == 3 }, inconclusive: { $0 % 8 == 0 }))
        #expect(noisy["Placement-diff pairs"]?.status == .fail)
        let worst = try #require(noisy["Placement-diff pairs, worst speaker"])
        #expect(worst.status == .fail && worst.value == 1)
        // A diff on every pair of one phrase: the worst phrase (100%) fails.
        let phrase = PositiveGates.measured(Self.pairs(200, diff: { $0 % 20 == 3 }))["Any-diff pairs, worst phrase"]
        #expect(phrase?.status == .fail && phrase?.value == 1 && phrase?.worstPhrase?.id == "004")
        #expect(noisy["Inconclusive pairs"]?.status == .fail)
        // Contrast unavailable on 1 pair in 8: coverage 87.5% < 90%.
        let coverage = try #require(noisy["Evaluation coverage"])
        #expect(coverage.status == .fail && abs(coverage.value! - 0.875) < 1e-9)

        let line = PositiveSetGates.lines(positiveSet: .evaluable, measured: noisy, pairs: 274)
            .first { $0.name == "Placement-diff pairs (spec 10)" }
        #expect(line?.status == .fail && line?.n == 200)
    }

    @Test("the referenceAnomaly rate is reported per phrase, never a pass and never a release gate") func referenceAnomaly() throws {
        let (line, review) = PositiveGates.referenceAnomaly(Self.pairs(200), positiveSet: .evaluable)
        #expect(line.status == .reported && !line.status.isPass)
        // Pairs 0, 25, 50 …: 2 of 10 pairs in each of four phrases, exactly at the 20% review share.
        #expect(line.worstPhrase?.value == 0.2 && review == ["001", "006", "011", "016"])
        let blocked = PositiveGates.referenceAnomaly(Self.pairs(200), positiveSet: try PositiveSetGuardTests.shortSet().status())
        #expect(blocked.line.status.text.hasPrefix("NOT EVALUATED (blocked on spec 24"))
        #expect(PositiveGates.referenceAnomaly([], positiveSet: .evaluable).line.status.text.hasPrefix("NOT EVALUATED"))
    }
}
