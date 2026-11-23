// AMPitch: F0 tracking (own YIN/pYIN on Accelerate behind PitchTracker).
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore

/// Identifies the `AMPitch` module and the modules it may depend on.
public enum AMPitchModule {
    public static let name = "AMPitch"
    public static let dependencies: [String] = [AMCoreModule.name]
}
