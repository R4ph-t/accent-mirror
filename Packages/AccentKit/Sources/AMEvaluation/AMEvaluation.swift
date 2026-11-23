// AMEvaluation: the agreement harness (spec 02). Manifests, folds, statistics and the reporter. Evaluation only:
// the app target never links it; `am-eval` and the package tests do.

import Foundation
import AMCore

/// Identifies the `AMEvaluation` module and the modules it may depend on.
public enum AMEvaluationModule {
    public static let name = "AMEvaluation"
    public static let dependencies: [String] = [AMCoreModule.name]
}
