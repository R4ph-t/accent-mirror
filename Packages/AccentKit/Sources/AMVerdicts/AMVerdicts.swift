// AMVerdicts (spec 28): the verdict scorer behind the pipeline's `PairScorer` seam, pair scoring and the placement
// goldens. Evaluation (am-eval, the agreement harness) runs `VerdictScorer()`; the shipped app links none of this.
// Milestone 2 brings scoring back by linking this product and passing `VerdictScorer()`.

import Foundation
import AMCore
import AMCapture
import AMAlignment
import AMPitch
import AMProsody
import AMWarp
import AMPlacement
import AMScoring
import AMPipeline

/// Identifies the `AMVerdicts` module and the modules it may depend on.
public enum AMVerdictsModule {
    public static let name = "AMVerdicts"
    public static let dependencies: [String] = [
        AMCoreModule.name, AMCaptureModule.name, AMAlignmentModule.name, AMPitchModule.name, AMProsodyModule.name,
        AMWarpModule.name, AMPlacementModule.name, AMScoringModule.name, AMPipelineModule.name,
    ]
}
