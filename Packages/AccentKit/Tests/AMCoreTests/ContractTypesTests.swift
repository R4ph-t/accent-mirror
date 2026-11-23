import Foundation
import Testing
import AMCore

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func json(_ value: some Encodable) throws -> String {
    String(decoding: try CanonicalJSON.encode(value), as: UTF8.self)
}

private func range(_ start: Double, _ end: Double) -> TimeRange { try! TimeRange(start: start, end: end) }

@Suite("Take problems") struct TakeProblemTests {
    @Test("sort in Designer's order") func designerOrder() {
        #expect(TakeProblem.allCases.sorted() == [
            .noMicrophone, .micDenied, .noSpeech, .tooShort, .tooQuiet, .clipped, .wordsDontMatch,
        ])
    }

    @Test("only the first problem of a set is reported") func firstOnly() {
        #expect(TakeProblem.first(of: [.wordsDontMatch, .clipped, .tooShort]) == .tooShort)
        #expect(TakeProblem.first(of: Set([.clipped, .micDenied])) == .micDenied)
        #expect(TakeProblem.first(of: []) == nil)
    }
}

@Suite("Bounded rows") struct BoundedRowsTests {
    private let row = DiffRow(kind: .placement, word: WordIndex(0), syllables: [1])

    @Test("holds one to three rows", arguments: [1, 2, 3]) func allowed(count: Int) throws {
        let rows = try #require(BoundedRows(Array(repeating: row, count: count)))
        #expect(rows.count == count)
    }

    @Test("can't be built with 0 or 4 rows", arguments: [0, 4]) func refused(count: Int) {
        #expect(BoundedRows(Array(repeating: row, count: count)) == nil)
    }

    @Test("decoding 0 or 4 rows throws", arguments: [0, 4]) func decodingRefused(count: Int) throws {
        let data = try JSONEncoder().encode(Array(repeating: row, count: count))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(BoundedRows.self, from: data) }
    }

    @Test("encodes as a plain array") func encodesAsArray() throws {
        let rows = try #require(BoundedRows([DiffRow(kind: .roughTiming)]))
        #expect(try json(rows) == #"[{"kind":"roughTiming","syllables":[],"values":{}}]"#)
    }
}

@Suite("Diff kinds") struct DiffKindTests {
    @Test("rank rough timing first and too much contrast last") func ranking() {
        #expect(DiffKind.allCases.sorted() == [
            .roughTiming, .placement, .contrast, .weakLength, .pitchRange, .finalDirection, .tooMuchContrast,
        ])
    }
}

@Suite("Measure states and verdicts") struct MeasureAndVerdictTests {
    @Test("measure states round-trip with readable keys") func measureStateJSON() throws {
        let evaluated = MeasureState<Double>.evaluated(1.65, .high)
        #expect(try json(evaluated) == #"{"evaluated":{"confidence":"high","value":1.65}}"#)
        #expect(try json(MeasureState<Double>.unavailable(.lowConfidence)) == #"{"unavailable":{"reason":"lowConfidence"}}"#)
        for state: MeasureState<Double> in [
            evaluated, .unavailable(.zeroVariance), .notApplicable(.tooFewExpectedUnstressed),
        ] {
            #expect(try roundTrip(state) == state)
        }
    }

    @Test("confidence orders low < medium < high") func confidenceOrder() {
        #expect(Confidence.low < .medium && Confidence.medium < .high)
    }

    @Test("every verdict case round-trips") func verdictRoundTrip() throws {
        let rows = try #require(BoundedRows([DiffRow(kind: .placement, word: WordIndex(1), syllables: [2])]))
        let verdicts: [Verdict] = [
            .feedback(rows: rows, partial: [.contrast]),
            .close,
            .noClearDifference([
                .pitchShapeBelowClose(0.5), .optionalMeasuresUnavailable([.pitchRange]),
                .mediumConfidenceOnly([.stressPlacement]), .timingRough,
                .nonTargetWordsIncomplete([WordIndex(3)]), .insertionsPresent(["so"]),
            ]),
            .inconclusive([
                .targetWordsMissing([WordIndex(0)]), .timingUnreliable, .comparableCoverageLow(0.55),
                .requiredMeasureUnavailable([.contrast]), .noApplicableStressMeasure,
            ]),
        ]
        for verdict in verdicts { #expect(try roundTrip(verdict) == verdict) }
    }

    @Test("a feedback verdict with four rows doesn't decode") func feedbackWithFourRows() {
        let row = #"{"kind":"placement","syllables":[],"values":{}}"#
        let data = Data(#"{"feedback":{"partial":[],"rows":[\#(row),\#(row),\#(row),\#(row)]}}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Verdict.self, from: data) }
    }
}

@Suite("Outcomes, errors and persistence") struct OutcomeTests {
    @Test("operational errors and persistence states round-trip") func roundTrips() throws {
        let errors: [OperationalError] = [
            .modelUnavailable(.checksumMismatch), .inferenceFailed(stage: .measureStress),
            .referenceCacheCorrupt(RecordingID("p225-001")), .audioUnreadable,
        ]
        for error in errors { #expect(try roundTrip(error) == error) }

        let statuses: [PersistenceStatus] = [
            .notSaved(.cancelled), .pending, .saved(TakeID("t1")), .saveFailed(.diskFull),
            .savedPruneFailed(TakeID("t1"), .ioFailure),
        ]
        for status in statuses { #expect(try roundTrip(status) == status) }
    }

    @Test("ID types encode as bare values") func idsAreBare() throws {
        #expect(try json([PhraseID("photography")]) == #"["photography"]"#)
        #expect(try json([WordIndex(2)]) == "[2]")
        let id = RequestID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        #expect(try json([id]) == #"["00000000-0000-0000-0000-000000000001"]"#)
    }

    @Test("a time range can't end before it starts") func timeRange() {
        #expect(throws: TimeRange.Invalid.endBeforeStart) { try TimeRange(start: 1, end: 0.5) }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TimeRange.self, from: Data(#"{"start":1,"end":0}"#.utf8))
        }
    }
}

@Suite("Word alignment") struct WordAlignmentTests {
    @Test("accepts phrase order with insertions and missing words") func valid() throws {
        let alignment = try WordAlignment(pairs: [
            .present(phrase: WordIndex(0), you: range(0, 0.3)),
            .inserted(heard: "so", you: range(0.3, 0.5), afterPhrase: WordIndex(0)),
            .missing(phrase: WordIndex(1)),
            .substituted(phrase: WordIndex(2), heard: "photograph", you: range(0.5, 1.1)),
        ])
        #expect(try roundTrip(alignment) == alignment)
    }

    @Test("refuses phrase words out of order") func phraseOrder() {
        #expect(throws: WordAlignment.Invalid.phraseOrderBroken(WordIndex(0))) {
            try WordAlignment(pairs: [.missing(phrase: WordIndex(1)), .missing(phrase: WordIndex(0))])
        }
    }

    @Test("refuses pairs that go back in your time") func yourTimeOrder() {
        #expect(throws: WordAlignment.Invalid.yourTimeOrderBroken(index: 1)) {
            try WordAlignment(pairs: [
                .present(phrase: WordIndex(0), you: range(0.5, 0.8)),
                .present(phrase: WordIndex(1), you: range(0.1, 0.4)),
            ])
        }
    }
}

@Suite("Partial time map") struct PartialTimeMapTests {
    private let anchor = PartialTimeMap.Anchor.init(model:you:)

    @Test("accepts ordered segments with anchors inside them") func valid() throws {
        let map = try PartialTimeMap(segments: [
            .mapped(model: range(0, 0.5), you: range(0, 0.6), anchors: [anchor(0, 0), anchor(0.2, 0.3)], comparable: true),
            .modelOnly(model: range(0.5, 0.8)),
            .youOnly(you: range(0.6, 0.9)),
            .mapped(model: range(0.8, 1.2), you: range(0.9, 1.4), anchors: [anchor(0.8, 0.9)], comparable: false),
        ])
        #expect(try roundTrip(map) == map)
    }

    @Test("refuses segments out of model order") func modelOrder() {
        #expect(throws: PartialTimeMap.Invalid.modelTimeOrderBroken(segment: 1)) {
            try PartialTimeMap(segments: [.modelOnly(model: range(0.5, 1)), .modelOnly(model: range(0, 0.4))])
        }
    }

    @Test("refuses mapped ranges that overlap in your time") func yourOrder() {
        #expect(throws: PartialTimeMap.Invalid.yourTimeOrderBroken(segment: 1)) {
            try PartialTimeMap(segments: [
                .mapped(model: range(0, 0.5), you: range(0, 0.6), anchors: [], comparable: true),
                .mapped(model: range(0.5, 1), you: range(0.4, 1), anchors: [], comparable: true),
            ])
        }
    }

    @Test("refuses an anchor outside its segment") func anchorInside() {
        #expect(throws: PartialTimeMap.Invalid.anchorOutsideSegment(segment: 0, anchor: 0)) {
            try PartialTimeMap(segments: [
                .mapped(model: range(0, 0.5), you: range(0, 0.6), anchors: [anchor(0.2, 0.7)], comparable: true),
            ])
        }
    }

    @Test("refuses anchors that aren't monotone") func anchorsMonotone() {
        #expect(throws: PartialTimeMap.Invalid.anchorsNotMonotone(segment: 0, anchor: 1)) {
            try PartialTimeMap(segments: [
                .mapped(
                    model: range(0, 0.5), you: range(0, 0.6), anchors: [anchor(0.1, 0.3), anchor(0.2, 0.2)],
                    comparable: true),
            ])
        }
    }

    @Test("decoding an invalid map throws") func decodingValidates() {
        let data = Data(#"{"segments":[{"modelOnly":{"model":{"start":0.5,"end":1}}},{"modelOnly":{"model":{"start":0,"end":0.4}}}]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PartialTimeMap.self, from: data) }
    }
}

@Suite("Identity") struct IdentityTests {
    private let config = ConfigIdentity(asrModelID: "none", pitchTrackerID: "none", voicingID: "none")

    @Test("config identity records the current versions") func versions() {
        #expect(config.algorithmVersion == Versions.algorithmVersion)
        #expect(config.thresholdsVersion == Versions.thresholdsVersion)
        #expect(config.contractVersion == Versions.contractVersion)
    }

    @Test("configDigest is stable and changes with any threshold") func configDigestTracksThresholds() throws {
        let digest = try configDigest(config)
        #expect(digest.count == 64)
        #expect(try configDigest(config) == digest)
        var tweaked = Thresholds.current
        tweaked.decision.closeMinShapeMatch = 0.71
        #expect(try configDigest(config, thresholds: tweaked) != digest)
        let otherVoicing = ConfigIdentity(asrModelID: "none", pitchTrackerID: "none", voicingID: "acf-1")
        #expect(try configDigest(otherVoicing) != digest)
    }
}
