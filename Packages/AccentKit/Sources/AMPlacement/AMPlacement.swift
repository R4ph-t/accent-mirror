// AMPlacement (spec 28): the leaf of the verdict path. Observed stress (`TakeProminence.observedStress(of:)`,
// `ObservedStress`), A(w) (`WordAcceptedSet`, `NativeReading`), the one placement rule (`placementDecision`,
// `PlacementDecision`, `PlacementSuppressionReason`) and spec 08's `StressPlacementDetector.place`. Moved out of
// AMProsody and AMPipeline so the shipped app can't link them; AMScoring and AMVerdicts depend on it.

import Foundation
import AMCore
import AMCapture
import AMAlignment
import AMPitch
import AMProsody

/// Identifies the `AMPlacement` module and the modules it may depend on.
public enum AMPlacementModule {
    public static let name = "AMPlacement"
    public static let dependencies: [String] = [
        AMCoreModule.name, AMCaptureModule.name, AMAlignmentModule.name, AMPitchModule.name, AMProsodyModule.name,
    ]
}
