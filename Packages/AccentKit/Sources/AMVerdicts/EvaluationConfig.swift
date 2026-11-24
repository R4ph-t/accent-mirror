// Evaluation is pinned to the verdict scorer (spec 28 §2): am-eval and every agreement runner build their analyzer
// here, so the harness never quietly runs the shipped `NoOpScorer` and reports zero flags.

import AMCore
import AMPipeline

public enum EvaluationConfig {
    /// The shipped stages with `VerdictScorer()`: what the agreement harness measures.
    public static func configuration(thresholds: Thresholds = .current) throws -> Analyzer.Configuration {
        var configuration = try Analyzer.Configuration.shipped(thresholds: thresholds)
        configuration.scorer = VerdictScorer()
        return configuration
    }

    /// Throws when an evaluation response came back unscored.
    public static func requireScored(_ decision: Decision?, context: String) throws {
        if decision == .verdict(.notScored) { throw NotScoredInEvaluation(context) }
    }
}
