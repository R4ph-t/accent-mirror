// AMScoring: comparison against the native band, and the diff rows.
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore
import AMProsody
import AMWarp
import AMPlacement

/// Identifies the `AMScoring` module and the modules it may depend on.
public enum AMScoringModule {
    public static let name = "AMScoring"
    public static let dependencies: [String] = [AMCoreModule.name, AMProsodyModule.name, AMWarpModule.name, AMPlacementModule.name]
}
