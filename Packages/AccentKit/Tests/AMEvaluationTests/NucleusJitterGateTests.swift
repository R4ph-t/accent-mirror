// Spec 25 §5: CI enforcement of acceptance 1. The head's thresholds must have a committed
// docs/agreement/reports/nucleus-jitter-<configDigest8>.json that shows acceptance 1 MET; the checks are re-derived from
// the stored comparisons, so neither an edited status nor an edited value passes. Red CI means no merge.

import Foundation
import Testing
import AMCore
@testable import AMEvaluation

@Suite("Nucleus jitter gate (spec 25 §5)") struct NucleusJitterGateTests {
    static let reports = Repo.url(ReportHashes.reportsPrefix)

    @Test("The head's nucleus-jitter report exists, matches its configDigest, and acceptance 1 is MET") func headReport() throws {
        guard let (report, digest) = try NucleusJitterReport.report(in: Self.reports) else {
            Issue.record("no docs/agreement/reports/nucleus-jitter-<configDigest8>.json for the head's thresholds")
            return
        }
        let failures = NucleusJitterReport.failures(report, digest: digest)
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("A passing report passes; the same report with one gated group at 2.1% fails") func doctoredGroupFails() throws {
        let passing = try Self.report(twoSyllableFlips: 2, of: 100)
        let digest = passing.identity.configDigest
        #expect(NucleusJitterReport.failures(passing, digest: digest) == [])
        #expect(passing.met)

        // The copy: the 2-syllable group's flips raised to 2.1% (3 of 143 rounds to 2.1%; use n = 1000, 21 flips).
        let doctored = try Self.doctored(Self.report(twoSyllableFlips: 2, of: 1000), set: "vctk-held-out", flips: 21)
        let failures = NucleusJitterReport.failures(doctored, digest: digest)
        #expect(failures.contains { $0.contains("2-syllable flips") && $0.contains("vctk-held-out") }, "\(failures)")
    }

    @Test("Editing only a stored check's value over its limit fails too") func storedValueOverLimitFails() throws {
        let passing = try Self.report(twoSyllableFlips: 2, of: 100)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(passing)) as! [String: Any]
        var checks = object["checks"] as! [[String: Any]]
        let index = checks.firstIndex { ($0["name"] as! String) == "jitter ±40 ms, 3-syllable flips" }!
        checks[index]["value"] = 0.021
        object["checks"] = checks
        let edited = try JSONDecoder().decode(NucleusJitterReport.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(NucleusJitterReport.failures(edited, digest: passing.identity.configDigest)
            .contains { $0.hasPrefix("stored value over its limit") })
    }

    @Test("A missing set, a high inconclusive share or a different configDigest fails; small groups are reported")
    func otherConditions() throws {
        let passing = try Self.report(twoSyllableFlips: 0, of: 100, fourPlusWords: 12, fourPlusFlips: 6)
        #expect(passing.met, "a 4+ group under 30 words is reported, not gated")
        let one = NucleusJitterReport(
            generatedAt: "", identity: passing.identity, shippedMeasurement: "nucleus", nucleus: Thresholds.current.nucleus,
            seed: 1, asrModelID: nil, sets: passing.sets.filter { $0.set == "synthetic" }, proposal: nil)
        #expect(NucleusJitterReport.failures(one, digest: passing.identity.configDigest).contains("set vctk-held-out missing"))
        let inconclusive = try Self.report(twoSyllableFlips: 0, of: 100, candidateInconclusive: 200)
        #expect(!inconclusive.met)
        #expect(!NucleusJitterReport.failures(passing, digest: String(repeating: "0", count: 64)).isEmpty)
    }

    @Test("Spec 26 §4 (CTO markup 4): the 10% budget holds on the unjittered run too; over it there, it fails")
    func unjitteredBudget() throws {
        let passing = try Self.report(twoSyllableFlips: 0, of: 100)
        #expect(passing.checks.contains { $0.name == "jitter ±40 ms, unjittered inconclusive budget" && $0.status == .met })
        let high = try Self.report(twoSyllableFlips: 0, of: 100, oracleInconclusive: 200)
        #expect(!high.met)
        #expect(NucleusJitterReport.failures(high, digest: high.identity.configDigest)
            .contains { $0.contains("unjittered inconclusive budget") })
    }

    // MARK: - Helpers

    static func comparison(_ id: String, twoSyllableFlips: Int, of twoSyllableWords: Int, fourPlusWords: Int,
                           fourPlusFlips: Int, candidateInconclusive: Int, oracleInconclusive: Int = 24) -> GuardRun.Comparison {
        let buckets = [
            GuardRun.Bucket(bucket: "1", words: 1000, differing: 10, oracleInconclusive: 20, candidateInconclusive: 20),
            GuardRun.Bucket(bucket: "2", words: twoSyllableWords, differing: twoSyllableFlips, oracleInconclusive: 2,
                            candidateInconclusive: 2),
            GuardRun.Bucket(bucket: "3", words: 100, differing: 1, oracleInconclusive: 2, candidateInconclusive: 2),
            GuardRun.Bucket(bucket: "4+", words: fourPlusWords, differing: fourPlusFlips, oracleInconclusive: 0,
                            candidateInconclusive: 0),
        ]
        let words = buckets.reduce(0) { $0 + $1.words }
        return GuardRun.Comparison(
            id: id, candidate: id, status: "evaluated", reason: nil, words: words,
            differing: buckets.reduce(0) { $0 + $1.differing }, oracleInconclusive: oracleInconclusive,
            candidateInconclusive: candidateInconclusive, parts: [:], onlyCue: [:], bySyllables: buckets,
            transitions: .init(decidedToDecided: 0, involvingInconclusive: 0), boundaryError: [], keptUnjittered: 0,
            inconclusiveSplit: nil)
    }

    static func report(twoSyllableFlips: Int, of twoSyllableWords: Int, fourPlusWords: Int = 40, fourPlusFlips: Int = 0,
                       candidateInconclusive: Int = 24, oracleInconclusive: Int = 24) throws -> NucleusJitterReport {
        let comparisons = ["jitter-20", "jitter-40", "jitter-80"].map {
            comparison($0, twoSyllableFlips: twoSyllableFlips, of: twoSyllableWords, fourPlusWords: fourPlusWords,
                       fourPlusFlips: fourPlusFlips, candidateInconclusive: max(candidateInconclusive, oracleInconclusive),
                       oracleInconclusive: oracleInconclusive)
        }
        let sets = NucleusJitter.requiredSets.map {
            NucleusJitter.Set(set: $0, oracle: "test", clips: 10, span: comparisons, nucleus: comparisons)
        }
        let config = ConfigIdentity(
            asrModelID: "replayed-word-timings", pitchTrackerID: "pyin-1", voicingID: "acf-1", aligner: "whisper",
            alignerModelSHA256: "none")
        let identity = ReportIdentity(
            config: config, configDigest: try configDigest(config), corpusManifestHash: "", labelHash: "",
            splitManifestHash: "", splitSeed: 0, sourceTreeHash: "", evaluatedCommit: "", cleanTree: true,
            xcodeVersion: "", swiftVersion: "", macOSVersion: "", runnerImage: "test")
        return NucleusJitterReport(
            generatedAt: "", identity: identity, shippedMeasurement: "nucleus", nucleus: Thresholds.current.nucleus,
            seed: 1, asrModelID: nil, sets: sets, proposal: nil)
    }

    /// A copy of `report` with the ±40 ms `.nucleus` 2-syllable group of `set` given `flips` flips, its pooled count
    /// and its stored check moved to match: what a hand edit of the JSON would look like.
    static func doctored(_ report: NucleusJitterReport, set name: String, flips: Int) throws -> NucleusJitterReport {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
        var sets = object["sets"] as! [[String: Any]]
        let s = sets.firstIndex { ($0["set"] as! String) == name }!
        var nucleus = sets[s]["nucleus"] as! [[String: Any]]
        let c = nucleus.firstIndex { ($0["id"] as! String) == "jitter-40" }!
        var buckets = nucleus[c]["bySyllables"] as! [[String: Any]]
        let b = buckets.firstIndex { ($0["bucket"] as! String) == "2" }!
        let before = buckets[b]["differing"] as! Int
        buckets[b]["differing"] = flips
        nucleus[c]["bySyllables"] = buckets
        nucleus[c]["differing"] = (nucleus[c]["differing"] as! Int) - before + flips
        sets[s]["nucleus"] = nucleus
        object["sets"] = sets
        return try JSONDecoder().decode(NucleusJitterReport.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
