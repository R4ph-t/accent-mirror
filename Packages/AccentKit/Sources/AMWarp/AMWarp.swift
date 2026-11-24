// AMWarp: time-warping a take onto the native model.
// Spec 09: the partial time map (TimeWarp), pitch on model time, DTW for Poor anchors and the native band.

import Foundation
import AMCore
import AMPitch

/// Identifies the `AMWarp` module and the modules it may depend on.
public enum AMWarpModule {
    public static let name = "AMWarp"
    public static let dependencies: [String] = [AMCoreModule.name, AMPitchModule.name]
}
