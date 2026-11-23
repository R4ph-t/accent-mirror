import AMAlignment
import AMCore
import AMSyllableEval
import Foundation
import Testing

@Suite("Syllable-boundary evaluation") struct SyllableEvalTests {
    @Test("MFA phones are grouped into syllables by spec 06's syllabifier, matched by position")
    func mfaReference() throws {
        // "photography" F AH0 | T AA1 | G R AH0 | F IY0, with english_mfa-style phone labels.
        let pronunciation = try Pronunciation(arpabet: "F AH0 T AA1 G R AH0 F IY0")
        let labels = ["f", "ə", "t", "ɑ", "ɡ", "ɹ", "ə", "f", "i"]
        let aligned = labels.enumerated().map { AlignedPhone(phone: $1, start: 1 + Double($0) * 0.05, end: 1.05 + Double($0) * 0.05) }
        let boundaries = try MFASyllableReference.boundaries(pronunciation: pronunciation, aligned: aligned)
        let expected = [1.10, 1.20, 1.35]
        #expect(boundaries.count == expected.count)
        for (got, want) in zip(boundaries, expected) { #expect(abs(got - want) < 1e-9) }
        #expect(throws: MFASyllableReference.Exclusion.phoneCountMismatch(dictionary: 9, aligned: 8)) {
            try MFASyllableReference.boundaries(pronunciation: pronunciation, aligned: Array(aligned.dropLast()))
        }
    }

    @Test("the bars: median ≤ 30 ms, ≥ 80% within 50 ms, and low-confidence boundaries err more")
    func bars() {
        let passing = BoundaryEvaluation(pairs: [
            BoundaryPair(reference: 1, measured: 1.010, level: .high),
            BoundaryPair(reference: 1, measured: 1.020, level: .medium),
            BoundaryPair(reference: 1, measured: 0.975, level: .high),
            BoundaryPair(reference: 1, measured: 1.040, level: .low),
            BoundaryPair(reference: 1, measured: 1.090, level: .low),
        ])
        #expect(passing.count == 5)
        #expect(abs((passing.medianErrorMs ?? 0) - 25) < 1e-6)
        #expect(passing.withinToleranceShare == 0.8)
        #expect((passing.median, passing.withinTolerance, passing.calibration) == (.pass, .pass, .pass))

        let failing = BoundaryEvaluation(pairs: [
            BoundaryPair(reference: 1, measured: 1.060, level: .high),
            BoundaryPair(reference: 1, measured: 1.035, level: .low),
        ])
        #expect((failing.median, failing.withinTolerance, failing.calibration) == (.fail, .fail, .fail))

        let empty = BoundaryEvaluation(pairs: [])
        #expect((empty.median, empty.withinTolerance, empty.calibration) == (.notEvaluated, .notEvaluated, .notEvaluated))
    }

    @Test("until spec 23 ships, every real-speech line is NOT EVALUATED (waiting on spec 23), which is not a pass")
    func waitingReport() throws {
        let identity = try SyllableBoundaryReport.Identity(
            config: .syllableSegmentation, evaluatedCommit: "abc", cleanTree: true)
        let report = SyllableBoundaryReport(identity: identity, evaluation: nil)
        #expect(report.status == .notEvaluated)
        #expect(report.lines.count == 5)
        #expect(report.lines.allSatisfy { $0.status == .notEvaluated && $0.note == "NOT EVALUATED (waiting on spec 23)" })
        #expect(report.fileStem == "syllable-boundaries-\(try configDigest(.syllableSegmentation).prefix(8))")
        #expect(identity.config.thresholdsVersion == Versions.thresholdsVersion)
        let markdown = report.markdown()
        #expect(markdown.contains("Montreal Forced Aligner 3.4.4"))
        #expect(markdown.contains("english_mfa v3.1.0"))
        #expect(markdown.contains("NOT EVALUATED (waiting on spec 23)"))
        _ = try report.json()
    }

    @Test("a FAIL on any line fails the report; spec 02's lines keep it from passing")
    func reportStatus() throws {
        let identity = try SyllableBoundaryReport.Identity(
            config: .syllableSegmentation, evaluatedCommit: "abc", cleanTree: true)
        let failing = BoundaryEvaluation(pairs: [BoundaryPair(reference: 1, measured: 1.2, level: .high)])
        #expect(SyllableBoundaryReport(identity: identity, evaluation: failing).status == .fail)
        let passing = BoundaryEvaluation(pairs: [
            BoundaryPair(reference: 1, measured: 1.01, level: .high),
            BoundaryPair(reference: 1, measured: 1.03, level: .low),
        ])
        #expect(SyllableBoundaryReport(identity: identity, evaluation: passing).status == .notEvaluated)
    }
}
