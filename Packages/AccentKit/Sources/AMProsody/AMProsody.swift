// AMProsody: stress, rhythm and intonation features.
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore
import AMAlignment
import AMPitch

/// Identifies the `AMProsody` module and the modules it may depend on.
public enum AMProsodyModule {
    public static let name = "AMProsody"
    public static let dependencies: [String] = [AMCoreModule.name, AMAlignmentModule.name, AMPitchModule.name]
}
