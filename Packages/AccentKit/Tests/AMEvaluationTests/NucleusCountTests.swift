// Spec 26 §1: the count grid reads tuning-speaker detection data only, uses only the pre-declared values, and chooses
// by the floor, the objective and the tie-breaks in order.

import AMCore
import AMEvaluation
import Foundation
import Testing

@Suite struct NucleusCountTests {
    static func split() throws -> VCTKSplitManifest {
        try JSONDecoder().decode(VCTKSplitManifest.self, from: Data(contentsOf: Repo.url("fixtures/splits/vctk.json")))
    }

    @Test("the grid runner refuses a held-out speaker's clip") func refusesHeldOut() throws {
        let split = try Self.split()
        let tuning = NucleusCountGrid.Clip(clipID: "\(split.tuning[0])_002", speaker: split.tuning[0], vowels: [])
        try NucleusCountGrid.validate([tuning], split: split)
        let heldOut = NucleusCountGrid.Clip(clipID: "\(split.heldOut[0])_002", speaker: split.heldOut[0], vowels: [])
        #expect(throws: NucleusCountGrid.InputError.notTuning(clipID: heldOut.clipID, speaker: heldOut.speaker)) {
            try NucleusCountGrid.validate([tuning, heldOut], split: split)
        }
    }

    @Test("the grid runner refuses synthetic and L2 input") func refusesSynthetic() throws {
        let split = try Self.split()
        for (clip, speaker) in [("synthetic-001", "synthetic-001"), ("tts_starter-03", "tts"), ("so762_000010011", "so762")] {
            #expect(throws: NucleusCountGrid.InputError.self) {
                try NucleusCountGrid.validate([NucleusCountGrid.Clip(clipID: clip, speaker: speaker, vowels: [])], split: split)
            }
        }
    }

    @Test("the grid's inputs carry detection truth only: no verdict, flip or gate field") func readsNoVerdict() {
        let banned = ["verdict", "flip", "inconclusive", "gate", "placement", "longest", "loudest", "heldOut"]
        let samples: [Any] = [
            NucleusCountGrid.Clip(clipID: "p232_002", speaker: "p232", vowels: [0.1...0.2]),
            NucleusCountGrid.WordOutcome(allowed: [2, 3], available: 3, short: false),
            NucleusCountGrid.AssignedNucleus(peak: 0.15, region: 0.12...0.18),
            NucleusCountGrid.ClipOutcome(words: [], nuclei: []),
        ]
        for sample in samples {
            for child in Mirror(reflecting: sample).children {
                let label = child.label?.lowercased() ?? ""
                #expect(!banned.contains { label.contains($0.lowercased()) }, "\(type(of: sample)).\(label)")
            }
        }
    }

    @Test("the reduced-forms file's hash in the tuning log matches the committed file") func reducedFormsHash() throws {
        let file = try Data(contentsOf: Repo.url(
            "Packages/AccentKit/Sources/AMAlignment/Resources/ReducedForms/reduced-forms.json"))
        let log = try String(contentsOf: Repo.url("docs/agreement/tuning-log.md"), encoding: .utf8)
        let entry = try #require(log.components(separatedBy: "\n### ").first { $0.contains("spec 26 nucleus count grid") })
        let marker = "`reduced-forms.json` SHA-256 `"
        let start = try #require(entry.range(of: marker))
        let recorded = String(entry[start.upperBound...].prefix(64))
        #expect(recorded == SHA256Digest.hex(of: file))
    }

    @Test("the grid is the pre-declared one: 180 points with the real-lag voicing values, 120 after an offset fix")
    func predeclaredGrid() {
        #expect(NucleusCountGrid.points(voicedWithinMs: NucleusCountGrid.voicedWithinMsRealLag).count == 180)
        #expect(NucleusCountGrid.points(voicedWithinMs: NucleusCountGrid.voicedWithinMsOffsetFixed).count == 120)
        #expect(NucleusCountGrid.minProminenceDB == [1.5, 2.0, 2.5, 3.0, 4.0])
        #expect(NucleusCountGrid.minSeparationMs == [50, 60, 70, 90])
        #expect(NucleusCountGrid.regionDropDB == [3, 6, 9])
        #expect(NucleusCountGrid.points(voicedWithinMs: [0, 30, 60]).contains(NucleusCountGrid.initial))
    }

    @Test("the chosen point is feasible, then maximises count-match, then vowel-inside, IoU, closeness to spec 25")
    func choice() {
        let grid: [Double] = [0, 30, 60]
        func point(_ prominence: Double, _ voiced: Double) -> NucleusCountGrid.Point {
            NucleusCountGrid.Point(minProminenceDB: prominence, minSeparationMs: 70, regionDropDB: 6, voicedWithinMs: voiced)
        }
        func metrics(_ p: NucleusCountGrid.Point, matched: Int, inside: Int, iou: Double) -> NucleusCountGrid.Metrics {
            let clip = NucleusCountGrid.Clip(clipID: "c", speaker: "p232", vowels: [0.0...1.0])
            let words = (0..<100).map { NucleusCountGrid.WordOutcome(allowed: [1], available: $0 < matched ? 1 : 2, short: false) }
            let nuclei = (0..<100).map { k in
                NucleusCountGrid.AssignedNucleus(peak: k < inside ? 0.5 : 2.0, region: (0.5 - iou / 2)...(0.5 + iou / 2))
            }
            return NucleusCountGrid.metrics(point: p, clips: [clip], outcomes: [.init(words: words, nuclei: nuclei)])
        }
        // An infeasible point with the best count-match is never chosen.
        let infeasible = metrics(point(1.5, 60), matched: 99, inside: 89, iou: 0.5)
        let a = metrics(point(2.0, 30), matched: 80, inside: 95, iou: 0.5)
        let b = metrics(point(2.5, 30), matched: 80, inside: 96, iou: 0.4)
        let c = metrics(point(4.0, 0), matched: 80, inside: 96, iou: 0.4)
        #expect(!infeasible.feasible)
        #expect(NucleusCountGrid.choose([infeasible, a], voicedWithinMs: grid)?.point == a.point)
        #expect(NucleusCountGrid.choose([a, b], voicedWithinMs: grid)?.point == b.point)
        // b and c tie on every metric: c (4.0 dB, 0 ms) is 1 grid step from spec 25's values, b (2.5 dB, 30 ms) is 2.
        #expect(NucleusCountGrid.choose([b, c], voicedWithinMs: grid)?.point == c.point)
        #expect(NucleusCountGrid.choose([infeasible], voicedWithinMs: grid) == nil)
    }
}
