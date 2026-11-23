// AMProsody: stress, rhythm and intonation features.
// Spec 07: the L1 syllable segmenter. Spec 08: prominence, observed stress, A(w), S and U, contrast, and the one
// placement rule (`placementDecision`).

import Foundation
import AMCore
import AMAlignment
import AMPitch

/// Identifies the `AMProsody` module and the modules it may depend on.
public enum AMProsodyModule {
    public static let name = "AMProsody"
    public static let dependencies: [String] = [AMCoreModule.name, AMAlignmentModule.name, AMPitchModule.name]
}
