// Spec 28 §2: evaluation is pinned to `VerdictScorer`. am-eval builds every analyzer through
// `EvaluationConfig.configuration()`, whose scoring mode is `.on`, and fails on a `.notScored` result.

import AMAlignment
import AMCore
import AMPipeline
@testable import AMVerdicts
import Foundation
import Testing

private struct NoWords: WordTimestamper {
    let asrModelID = "fixture"
    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] { [] }
}

@Suite("Evaluation is pinned to VerdictScorer (spec 28)") struct EvaluationPinTests {
    static let amEval = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/am-eval")

    @Test("am-eval's analyzer configuration scores (.on)") func amEvalScoringModeIsOn() throws {
        let configuration = try EvaluationConfig.configuration()
        #expect(configuration.scorer is VerdictScorer)
        #expect(configuration.scorer.mode == .on)
        let analyzer = Analyzer(speech: SpeechModelHost(ready: NoWords()), configuration: configuration)
        #expect(analyzer.scoringMode == .on)
    }

    @Test("every Analyzer am-eval builds uses EvaluationConfig") func amEvalBuildsAnalyzersThroughEvaluationConfig() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.amEval, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 5)
        var analyzers = 0
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            where line.contains("Analyzer(speech:") {
                analyzers += 1
                #expect(line.contains("EvaluationConfig.configuration()"), "\(file.lastPathComponent): \(line)")
            }
        }
        #expect(analyzers >= 3)
    }

    @Test("an unscored evaluation result throws") func notScoredThrows() {
        #expect(throws: NotScoredInEvaluation.self) {
            try EvaluationConfig.requireScored(.verdict(.notScored), context: "test")
        }
        #expect(throws: Never.self) { try EvaluationConfig.requireScored(.verdict(.close), context: "test") }
        #expect(throws: Never.self) { try EvaluationConfig.requireScored(.takeProblem(.tooQuiet), context: "test") }
    }

    @Test("AMVerdicts names its dependencies") func moduleDependencies() {
        #expect(AMVerdictsModule.dependencies.contains("AMPipeline") && AMVerdictsModule.dependencies.contains("AMScoring"))
    }
}
