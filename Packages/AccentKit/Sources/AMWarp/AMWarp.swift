// AMWarp: time-warping a take onto the native model.
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore
import AMPitch

/// Identifies the `AMWarp` module and the modules it may depend on.
public enum AMWarpModule {
    public static let name = "AMWarp"
    public static let dependencies: [String] = [AMCoreModule.name, AMPitchModule.name]
}
