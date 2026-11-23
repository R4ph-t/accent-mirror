import Foundation
import Testing
import AMCore
import AMEvaluation

@Suite("Band coverage gate (spec 09)") struct BandCoverageGateTests {
    static func pairs(_ count: Int, coverage: (Int) -> Double) -> [PairBandCoverage] {
        (0..<count).map { PairBandCoverage(speaker: "p\(300 + $0 % 12)", phrase: String(format: "%03d", $0 % 18 + 1), coverage: coverage($0)) }
    }

    @Test("While the positive set is NOT EVALUATED, band coverage is NOT EVALUATED (blocked on spec 24), never a pass")
    func blockedOnSpec24() throws {
        let set = try PositiveSetGuardTests.shortSet()
        let status = set.status()
        let line = BandCoverageGate.line(
            positiveSet: status, pairs: Self.pairs(200) { _ in 1.0 }, pairCount: set.headline.count)
        #expect(line.name == "Band coverage, median over pairs (spec 09)")
        #expect(line.status == .blocked(on: "spec 24", reason: "phrases 15 < 18"))
        #expect(line.status.text == "NOT EVALUATED (blocked on spec 24: phrases 15 < 18)")
        #expect(!line.status.isPass && line.value == nil && line.dependsOnPositiveSet == true)
        #expect(line.gate?.key == "agreement.bandCoverageMedianMin" && line.gate?.bound == 0.80)
    }

    @Test("An evaluable set: median over pairs ≥ 80% passes, below fails, with n and the worst speaker")
    func evaluable() {
        let passing = BandCoverageGate.line(
            positiveSet: .evaluable, pairs: Self.pairs(160) { $0 < 60 ? 0.5 : 0.9 }, pairCount: 160)
        #expect(passing.status == .pass && passing.n == 160 && passing.value == 0.9)
        let failing = BandCoverageGate.line(
            positiveSet: .evaluable, pairs: Self.pairs(160) { $0 < 100 ? 0.79 : 0.95 }, pairCount: 160)
        #expect(failing.status == .fail && failing.value == 0.79)
        #expect(failing.worstSpeaker != nil)
    }

    @Test("Too few pairs is NOT EVALUATED, not a pass") func tooFewPairs() {
        let line = BandCoverageGate.line(positiveSet: .evaluable, pairs: Self.pairs(20) { _ in 1 }, pairCount: 20)
        #expect(line.status == .notEvaluated(n: 20, minimum: 150))
        #expect(!line.status.isPass)
    }
}
