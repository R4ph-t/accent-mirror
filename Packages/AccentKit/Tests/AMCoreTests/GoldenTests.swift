import Foundation
import Testing
import AMCore

/// The golden contract fixtures: one response per outcome case and per verdict case, plus the five §1.3 examples.
/// Run with `AM_RECORD_GOLDEN=1` to rewrite the files; then bump a version and append a digest (see `Versions`).
enum Golden {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden")

    static let isRecording = ProcessInfo.processInfo.environment["AM_RECORD_GOLDEN"] == "1"

    struct Fixture: Sendable {
        let path: String
        let encode: @Sendable () throws -> Data
        /// Pretty, sorted, shortest-form numbers: what is written to disk for review.
        let encodePretty: @Sendable () throws -> Data
        let matchesDecoded: @Sendable (Data) throws -> Bool
    }

    static func fixture<T: Codable & Equatable & Sendable>(_ path: String, _ value: T) -> Fixture {
        Fixture(
            path: path,
            encode: { try CanonicalJSON.encode(value) },
            encodePretty: {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .secondsSince1970
                return try encoder.encode(value)
            },
            matchesDecoded: { try CanonicalJSON.decoder().decode(T.self, from: $0) == value })
    }

    static let fixtures: [Fixture] = [
        fixture("outcome-takeProblem.json", response(.takeProblem(.tooQuiet))),
        fixture("outcome-failed.json", response(.failed(.inferenceFailed(stage: .measureStress)))),
        fixture("outcome-cancelled.json", response(.cancelled)),
        fixture("analysed-feedback.json", response(.analysed(result(verdict: feedbackVerdict)))),
        fixture("analysed-close.json", response(.analysed(result(verdict: .close)))),
        fixture(
            "analysed-noClearDifference.json",
            response(.analysed(result(verdict: .noClearDifference([.pitchShapeBelowClose(0.5)]))))),
        fixture(
            "analysed-inconclusive.json",
            response(.analysed(result(verdict: .inconclusive([.targetWordsMissing([WordIndex(0)])]))))),
        fixture("examples/1-close.json", Decision.verdict(.close)),
        fixture("examples/2-shape-0.5.json", Decision.verdict(.noClearDifference([.pitchShapeBelowClose(0.5)]))),
        fixture(
            "examples/3-record-substituted.json",
            Decision.verdict(.inconclusive([.targetWordsMissing([WordIndex(0)])]))),
        fixture(
            "examples/4-contrast-unavailable-placement-fires.json",
            Decision.verdict(.feedback(rows: BoundedRows([Scenario.placementRow])!, partial: [.contrast]))),
        fixture(
            "examples/5-contrast-unavailable-nothing-fires.json",
            Decision.verdict(.inconclusive([.requiredMeasureUnavailable([.contrast])]))),
    ]

    /// Not decodable: a feedback verdict with 4 rows. Kept under Golden/ so it counts in the digest.
    static let fourRowsPath = "invalid/analysed-feedback-4-rows.json"

    // MARK: Values

    static let config = ConfigIdentity(
        asrModelID: "whisperkit-base.en", pitchTrackerID: "pyin-1", voicingID: "acf-1", aligner: "whisper",
        alignerModelSHA256: "none")

    static let identity = AnalysisIdentity(
        takeAudioSHA256: String(repeating: "a", count: 64),
        reference: ReferenceIdentity(
            phraseID: PhraseID("record"), recordingID: RecordingID("p225-record"),
            recordingSHA256: String(repeating: "b", count: 64), transcriptRevision: 1,
            pronunciationOverridesHash: String(repeating: "c", count: 64), targetsHash: String(repeating: "d", count: 64),
            nativeSetHash: String(repeating: "e", count: 64)),
        config: config)

    static let feedbackVerdict = Verdict.feedback(
        rows: BoundedRows([DiffRow(kind: .roughTiming), Scenario.placementRow])!, partial: [])

    static func response(_ outcome: AnalysisOutcome) -> AnalysisResponse {
        AnalysisResponse(
            requestID: RequestID(UUID(uuidString: "5D7C0E1A-0000-4000-8000-000000000001")!), identity: identity,
            outcome: outcome)
    }

    private static func range(_ start: Double, _ end: Double) -> TimeRange { try! TimeRange(start: start, end: end) }

    /// "record" (noun, REC-ord): the model on its timeline, you on yours, two syllables each.
    static func result(verdict: Verdict) -> AnalysisResult {
        let model = SpeakerAnalysis(
            words: [WordSpan(text: "record", range: range(0.1, 0.62), syllables: [0, 1])],
            syllables: [
                SyllableMeasure(
                    text: "REC", wordIndex: 0, indexInWord: 0, range: range(0.1, 0.34), share: 0.46, prominence: 1,
                    stress: .primary, stressSource: .dictionary),
                SyllableMeasure(
                    text: "ord", wordIndex: 0, indexInWord: 1, range: range(0.34, 0.62), share: 0.54, prominence: 0,
                    stress: .unstressed, stressSource: .dictionary),
            ],
            pitch: [PitchSegment(start: 0.1, frames: [
                PitchFrame(semitones: 2, voiced: true), PitchFrame(semitones: 1.5, voiced: true),
                PitchFrame(semitones: 0.75, voiced: false), PitchFrame(semitones: -0.5, voiced: true),
            ])],
            medianF0Hz: 196)
        let you = SpeakerAnalysis(
            words: [WordSpan(text: "record", range: range(0.2, 0.8), syllables: [0, 1])],
            syllables: [
                SyllableMeasure(
                    text: "re", wordIndex: 0, indexInWord: 0, range: range(0.2, 0.42), share: 0.37, prominence: 0.25,
                    stress: .unstressed, stressSource: .measured),
                SyllableMeasure(
                    text: "CORD", wordIndex: 0, indexInWord: 1, range: range(0.42, 0.8), share: 0.63, prominence: 1,
                    stress: .primary, stressSource: .measured),
            ],
            pitch: [PitchSegment(start: 0.2, frames: [
                PitchFrame(semitones: -1, voiced: true), PitchFrame(semitones: 0.5, voiced: true),
                PitchFrame(semitones: 3, voiced: true),
            ])],
            medianF0Hz: 120)
        return AnalysisResult(
            phraseID: PhraseID("record"), takeID: TakeID("take-0001"), recordedAt: Date(timeIntervalSince1970: 1_795_420_800),
            model: model, you: you, modelAxis: range(0.1, 0.62),
            alignment: try! WordAlignment(pairs: [.present(phrase: WordIndex(0), you: range(0.2, 0.8))]),
            timeMap: try! PartialTimeMap(segments: [
                .mapped(
                    model: range(0.1, 0.62), you: range(0.2, 0.8),
                    anchors: [
                        PartialTimeMap.Anchor(model: 0.1, you: 0.2), PartialTimeMap.Anchor(model: 0.34, you: 0.42),
                        PartialTimeMap.Anchor(model: 0.62, you: 0.8),
                    ],
                    comparable: true),
            ]),
            youPitchOnModel: [PitchSegment(start: 0.1, frames: [
                PitchFrame(semitones: -1, voiced: true), PitchFrame(semitones: 0.5, voiced: true),
                PitchFrame(semitones: 3, voiced: true),
            ])],
            nativeBand: [
                BandPoint(time: 0.1, lower: 0.5, upper: 3.5), BandPoint(time: 0.2, lower: 0, upper: 3),
                BandPoint(time: 0.3, lower: -0.75, upper: 2.25),
            ],
            pitchAxis: -12...12, timing: .rough,
            stress: [
                StressLine(
                    word: WordIndex(0), expectedPattern: [.primary, .unstressed], observedPrimary: 1, margin: 1.14,
                    confidence: .high, matchedAccepted: nil, referenceAnomaly: false),
            ],
            measures: [
                .stressPlacement: .evaluated(1.14, .high),
                .contrast: .notApplicable(.tooFewExpectedUnstressed),
                .tooMuchContrast: .notApplicable(.tooFewExpectedUnstressed),
                .weakLength: .notApplicable(.tooFewExpectedUnstressed),
                .rhythm: .notApplicable(.tooFewSyllablesInPhrase),
                .pitchRange: .evaluated(9.5, .high),
                .shapeMatch: .evaluated(0.5, .high),
                .finalDirection: .unavailable(.lowConfidence),
            ],
            applicability: applicability(Scenario.record), verdict: verdict, identity: identity)
    }

    // MARK: Digest

    /// Every JSON file under Golden/, sorted by relative path.
    static func files() throws -> [String] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var paths: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "json" else { continue }
            paths.append(String(url.standardizedFileURL.path.dropFirst(directory.standardizedFileURL.path.count + 1)))
        }
        return paths.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// The digest `Versions.goldenDigests` records: SHA-256 over each file's path, newline, canonical JSON, newline.
    static func digest() throws -> String {
        var bytes: [UInt8] = []
        for path in try files() {
            bytes += Array(path.utf8) + [0x0A]
            bytes += Array(try CanonicalJSON.canonicalize(Data(contentsOf: directory.appendingPathComponent(path))))
            bytes += [0x0A]
        }
        return SHA256Digest.hex(of: bytes)
    }

    static func record() throws {
        func write(_ pretty: Data, to path: String) throws {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (pretty + Data("\n".utf8)).write(to: url)
        }
        for fixture in fixtures { try write(fixture.encodePretty(), to: fixture.path) }

        // The invalid file: the feedback response with its rows repeated to 4.
        let feedback = try CanonicalJSON.encode(response(.analysed(result(verdict: feedbackVerdict))))
        var object = try JSONSerialization.jsonObject(with: feedback) as! [String: Any]
        var outcome = object["outcome"] as! [String: Any]
        var analysed = outcome["analysed"] as! [String: Any]
        var result = analysed["result"] as! [String: Any]
        var verdict = result["verdict"] as! [String: Any]
        var payload = verdict["feedback"] as! [String: Any]
        let rows = payload["rows"] as! [Any]
        payload["rows"] = rows + rows
        verdict["feedback"] = payload
        result["verdict"] = verdict
        analysed["result"] = result
        outcome["analysed"] = analysed
        object["outcome"] = outcome
        try write(
            JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            to: fourRowsPath)
    }
}

@Suite("Golden contract JSON", .serialized) struct GoldenTests {
    @Test("record the golden files when AM_RECORD_GOLDEN=1", .enabled(if: Golden.isRecording))
    func recordGolden() throws {
        try Golden.record()
    }

    @Test("each golden file is exactly what the contract encodes, and decodes back to it",
        arguments: Golden.fixtures.map(\.path))
    func matchesContract(path: String) throws {
        let fixture = try #require(Golden.fixtures.first { $0.path == path })
        let data = try Data(contentsOf: Golden.directory.appendingPathComponent(path))
        #expect(try CanonicalJSON.canonicalize(data) == fixture.encode(), "\(path) differs from the contract's encoding")
        #expect(try fixture.matchesDecoded(data), "\(path) doesn't decode to the expected value")
    }

    @Test("there is one golden response per outcome case and per verdict case") func coversEveryCase() throws {
        let decoder = CanonicalJSON.decoder()
        var outcomes: Set<String> = []
        var verdicts: Set<String> = []
        for path in try Golden.files() where !path.hasPrefix("invalid/") && !path.hasPrefix("examples/") {
            let response = try decoder.decode(
                AnalysisResponse.self, from: Data(contentsOf: Golden.directory.appendingPathComponent(path)))
            switch response.outcome {
            case .analysed(let result):
                outcomes.insert("analysed")
                switch result.verdict {
                case .feedback: verdicts.insert("feedback")
                case .close: verdicts.insert("close")
                case .noClearDifference: verdicts.insert("noClearDifference")
                case .inconclusive: verdicts.insert("inconclusive")
                }
            case .takeProblem: outcomes.insert("takeProblem")
            case .failed: outcomes.insert("failed")
            case .cancelled: outcomes.insert("cancelled")
            }
        }
        #expect(outcomes == ["analysed", "takeProblem", "failed", "cancelled"])
        #expect(verdicts == ["feedback", "close", "noClearDifference", "inconclusive"])
    }

    @Test("the five §1.3 example goldens are what the decision procedure returns") func examplesMatchProcedure() throws {
        let substituted = AlignmentSummary(matchShare: 1, incompleteTargetWords: [WordIndex(0)])
        let contrastUnavailable = try Scenario.photographyMeasures(contrast: .unavailable(.lowConfidence))
        let decisions: [(String, Decision)] = [
            ("examples/1-close.json", decide(Scenario.input(measures: try Scenario.recordMeasures()))),
            ("examples/2-shape-0.5.json", decide(Scenario.input(measures: try Scenario.recordMeasures(shape: 0.5)))),
            ("examples/3-record-substituted.json", decide(Scenario.input(
                alignment: substituted,
                measures: try Scenario.recordMeasures(placement: .unavailable(.wordSubstituted))))),
            ("examples/4-contrast-unavailable-placement-fires.json", decide(Scenario.input(
                measures: contrastUnavailable, diffs: [Scenario.placementRow]))),
            ("examples/5-contrast-unavailable-nothing-fires.json", decide(Scenario.input(measures: contrastUnavailable))),
        ]
        for (path, decision) in decisions {
            let data = try Data(contentsOf: Golden.directory.appendingPathComponent(path))
            #expect(try CanonicalJSON.decoder().decode(Decision.self, from: data) == decision, "\(path)")
        }
    }

    @Test("decoding the golden file with 4 rows throws") func fourRowsThrows() throws {
        let data = try Data(contentsOf: Golden.directory.appendingPathComponent(Golden.fourRowsPath))
        #expect(throws: DecodingError.self) { try CanonicalJSON.decoder().decode(AnalysisResponse.self, from: data) }
    }
}

@Suite("Golden digest and versions") struct GoldenDigestTests {
    @Test("the golden digest matches the record for the current versions") func digestMatches() throws {
        let latest = try #require(Versions.goldenDigests.last)
        #expect(
            (latest.algorithmVersion, latest.thresholdsVersion, latest.contractVersion)
                == (Versions.algorithmVersion, Versions.thresholdsVersion, Versions.contractVersion),
            "Versions changed: append a GoldenDigest record for the new versions")
        let digest = try Golden.digest()
        #expect(
            digest == latest.digest,
            """
            Golden output changed. Bump algorithmVersion, thresholdsVersion or contractVersion in Versions.swift \
            and append a GoldenDigest record with digest: "\(digest)". Never edit an existing record.
            """)
    }

    @Test("digest records only move forward") func recordsAreMonotonic() {
        let records = Versions.goldenDigests
        #expect(Set(records.map(\.digest)).count == records.count, "each record needs its own digest")
        for (previous, next) in zip(records, records.dropFirst()) {
            let up = [
                next.algorithmVersion - previous.algorithmVersion, next.thresholdsVersion - previous.thresholdsVersion,
                next.contractVersion - previous.contractVersion,
            ]
            #expect(up.allSatisfy { $0 >= 0 } && up.contains { $0 > 0 }, "versions must increase between records")
        }
    }

    @Test("versions start at 1") func versionsAreOne() {
        #expect(Versions.algorithmVersion >= 1 && Versions.thresholdsVersion >= 1 && Versions.contractVersion >= 1)
    }
}
